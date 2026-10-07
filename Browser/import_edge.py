"""
Imports bookmarks, history and form data from Edge into the Browser (LibreWolf)
using the browser's own importer, driven locally through Marionette.

    python import_edge.py                 bookmarks + history + form data
    python import_edge.py --csv FILE      also, passwords exported from Edge
    python import_edge.py --recordar URL...  sites that keep their session on disk
    python import_edge.py --instalar FILE.xpi  signed extension, permanent

Everything happens on this PC: the control channel listens only on 127.0.0.1 and
closes when done. The Browser must be closed.
"""
import json
import os
import socket
import subprocess
import sys
import time

LIBREWOLF = r"C:\Program Files\LibreWolf\librewolf.exe"
PUERTO = 2828


class Marionette:
    def __init__(self, puerto):
        self.s = socket.create_connection(("127.0.0.1", puerto), timeout=600)
        self.n = 0
        self._leer()  # server greeting

    def _leer(self):
        largo = b""
        while not largo.endswith(b":"):
            largo += self.s.recv(1)
        largo = int(largo[:-1])
        datos = b""
        while len(datos) < largo:
            datos += self.s.recv(largo - len(datos))
        return json.loads(datos)

    def orden(self, nombre, params=None):
        self.n += 1
        cuerpo = json.dumps([0, self.n, nombre, params or {}]).encode()
        self.s.sendall(str(len(cuerpo)).encode() + b":" + cuerpo)
        _, _, error, resultado = self._leer()
        if error:
            raise RuntimeError(f"{nombre}: {error.get('message', error)}")
        return resultado


SCRIPT = r"""
const hecho = arguments[arguments.length - 1];
(async () => {
  const { MigrationUtils } = ChromeUtils.importESModule("resource:///modules/MigrationUtils.sys.mjs");
  const { PlacesUtils } = ChromeUtils.importESModule("resource://gre/modules/PlacesUtils.sys.mjs");
  const csv = arguments[0];
  const recordar = arguments[1];
  const salida = {};
  if (recordar) {
    // Sites whose session is kept on disk even though everything else is wiped on close.
    for (const sitio of recordar) {
      const pr = Services.scriptSecurityManager.createContentPrincipalFromOrigin(sitio);
      Services.perms.addFromPrincipal(pr, "cookie", Services.perms.ALLOW_ACTION);
    }
    // Outlook/Office sign in through an embedded Microsoft window: they are
    // allowed their own storage despite Total Cookie Protection.
    const tops = ["https://outlook.office.com", "https://outlook.live.com", "https://outlook.office365.com", "https://www.office.com", "https://office.com"];
    const logins = ["https://login.microsoftonline.com", "https://login.live.com", "https://login.microsoft.com"];
    for (const t of tops) {
      const pr = Services.scriptSecurityManager.createContentPrincipalFromOrigin(t);
      for (const l of logins) {
        for (const tipo of ["3rdPartyStorage^", "3rdPartyFrameStorage^"]) {
          Services.perms.addFromPrincipal(pr, tipo + l, Services.perms.ALLOW_ACTION);
        }
      }
    }
    salida.accesoLogin = Services.perms.all.filter(x => x.type.startsWith("3rdParty")).length;
    salida.recordados = Services.perms.getAllByTypes(["cookie"])
      .filter(p => p.capability === Services.perms.ALLOW_ACTION).map(p => p.principal.origin);
  } else if (!csv) {
    // Without these limits the importer only brings 2000 pages from 180 days.
    Services.prefs.setIntPref("browser.migrate.chrome.history.limit", 200000);
    Services.prefs.setIntPref("browser.migrate.chrome.history.maxAgeInDays", 3650);
    const m = await MigrationUtils.getMigrator("chromium-edge");
    const perfiles = (await m.getSourceProfiles()) || [];
    const p = perfiles.find(x => x.id === "Default") || perfiles[0];
    salida.perfil = p ? p.name : null;
    const t = MigrationUtils.resourceTypes;
    const quiero = t.BOOKMARKS | t.HISTORY | t.FORMDATA;
    const hay = await m.getMigrateData(p);
    await m.migrate(quiero & hay, false, p);
  } else {
    const { LoginCSVImport } = ChromeUtils.importESModule("resource://gre/modules/LoginCSVImport.sys.mjs");
    const r = await LoginCSVImport.importFromCSV(csv);
    salida.contrasenas = r.filter(x => x.result === "added" || x.result === "modified").length;
    salida.fallidas = r.filter(x => x.result.startsWith("error")).length;
  }
  const db = await PlacesUtils.promiseDBConnection();
  salida.favoritos = (await db.execute("SELECT count(*) FROM moz_bookmarks WHERE type = 1"))[0].getResultByIndex(0);
  salida.paginas = (await db.execute("SELECT count(*) FROM moz_places WHERE visit_count > 0"))[0].getResultByIndex(0);
  hecho(salida);
})().catch(e => hecho({ error: String(e) }));
"""


def main():
    csv = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--csv" else None
    recordar = sys.argv[2:] if len(sys.argv) > 2 and sys.argv[1] == "--recordar" else None
    proc = subprocess.Popen([LIBREWOLF, "--headless", "--marionette", "--remote-allow-system-access"])
    try:
        cliente = None
        for _ in range(60):
            try:
                cliente = Marionette(PUERTO)
                break
            except OSError:
                time.sleep(1)
        if not cliente:
            print("ERROR: the Browser did not open its local channel")
            return 1
        cliente.orden("WebDriver:NewSession", {"capabilities": {}})
        if len(sys.argv) > 2 and sys.argv[1] == "--instalar":
            # Installs a signed extension permanently (not temporary).
            r = cliente.orden("Addon:Install", {"path": os.path.abspath(sys.argv[2]), "temporary": False})
            print(json.dumps({"instalada": r.get("value", r)}))
            try:
                cliente.orden("Marionette:Quit", {"flags": ["eAttemptQuit"]})
            except Exception:
                pass
            proc.wait(timeout=60)
            return 0
        cliente.orden("Marionette:SetContext", {"value": "chrome"})
        cliente.orden("WebDriver:SetTimeouts", {"script": 600000})
        r = cliente.orden("WebDriver:ExecuteAsyncScript", {"script": SCRIPT, "args": [csv, recordar], "newSandbox": True})
        print(json.dumps(r.get("value", r), ensure_ascii=False))
        try:
            cliente.orden("Marionette:Quit", {"flags": ["eAttemptQuit"]})
        except Exception:
            pass
        proc.wait(timeout=60)
        return 0
    finally:
        if proc.poll() is None:
            proc.terminate()


if __name__ == "__main__":
    sys.exit(main())
