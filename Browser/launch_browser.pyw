"""
Browser launcher.

LibreWolf 156 ignores cookie exceptions when it clears data on close: it
either clears everything (and mail sessions are lost) or nothing. This
launcher does the clearing itself: before opening and after closing it
deletes cookies and site data for ALL pages except those in the CONSERVAR
list. Everything happens locally, on the profile files.

Session cookies (no expiry date; some sites sign you in with one) never reach
cookies.sqlite: they only survive inside the session file, which is why the
browser restores the session on start. The launcher rewrites that file on
close: a single tab with the smiley page and only the CONSERVAR cookies.

Hidden IP ("always"): everything goes through Tor, accounts included. On open
it starts, if missing, the Ubuntu Tor engine (127.0.0.1:9050, over WebTunnel
bridges), the chosen-exit engine (9055), the circuit race (9070) and the
protected direct gate (9060, only for direct.txt); normally tor_watchdog.pyw
keeps them running already, because the engine is not stopped on close
(MOTOR_SIEMPRE). It writes route.pac (direct only for this PC and the home
network) and puts the sites from direct.txt and chosen_exit.txt in user.js; the
route of each page is decided by the filter in librewolf.overrides.cfg. If the
engine is down, pages that go through Tor do not load: there is no direct plan B.

Only one launcher at a time clears or opens (lock file .lanzador.lock), and
"open" means the Browser's profile is in use, not just that some librewolf.exe
is running (tests use temporary profiles).
"""
import glob
import json
import re
import os
import shutil
import socket
import sqlite3
import struct
import subprocess
import sys
import time

LIBREWOLF = r"C:\Program Files\LibreWolf\librewolf.exe"
INICIO = "file:///" + os.path.join(os.path.dirname(os.path.abspath(__file__)), "home.html").replace("\\", "/")
MOZLZ4 = b"mozLz40\0"

# Domains whose session is kept (and all their subdomains).
CONSERVAR = (
    # Mail and accounts
    "google.com", "youtube.com",
    "live.com", "outlook.com", "microsoftonline.com", "cloud.microsoft", "microsoft.com", "office.com",
    # Work and development
    "github.com", "linkedin.com", "localhost", "127.0.0.1",
    # AI
    "chatgpt.com", "openai.com", "claude.ai", "anthropic.com",
    # Add here the domains whose session you want to keep (and all their subdomains).
)


def perfil():
    base = os.path.expandvars(r"%APPDATA%\librewolf\Profiles")
    cands = glob.glob(os.path.join(base, "*.default-default")) or glob.glob(os.path.join(base, "*"))
    return max(cands, key=os.path.getmtime) if cands else None


def se_conserva(host):
    h = host.lstrip(".").lower()
    return any(h == d or h.endswith("." + d) for d in CONSERVAR)


def proceso_librewolf():
    r = subprocess.run(["tasklist", "/fi", "imagename eq librewolf.exe", "/nh"],
                       capture_output=True, text=True, creationflags=0x08000000)
    return "librewolf.exe" in r.stdout.lower()


def perfil_en_uso(prof):
    """While the browser has a profile open, Windows will not let parent.lock be opened (measured);
    once closed, it opens. That way only the Browser's profile counts, not test LibreWolf instances,
    which use temporary profiles."""
    try:
        with open(os.path.join(prof, "parent.lock"), "rb"):
            return False
    except FileNotFoundError:
        return False
    except OSError:
        return True


def navegador_abierto(prof=None):
    """True if the Browser (its profile) is open. It used to count any librewolf.exe, and with a test
    running the launcher thought the browser was open and skipped the clean-up."""
    if not proceso_librewolf():
        return False
    prof = prof or perfil()
    return perfil_en_uso(prof) if prof else True


CANDADO = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".lanzador.lock")


class Candado:
    """Only one launcher at a time clears the profile or opens the browser. If an old launcher was still
    waiting for the close and the browser was closed and reopened right away, both cleared at once, or
    one cleared while the other opened. Windows releases the lock if the process dies; if it cannot be
    taken within 90 s, it carries on anyway: the browser is never kept from opening because of this."""

    def __enter__(self):
        import msvcrt
        self.f = open(CANDADO, "a+b")
        fin = time.time() + 90
        while True:
            try:
                self.f.seek(0)
                msvcrt.locking(self.f.fileno(), msvcrt.LK_NBLCK, 1)
                self.tomado = True
                return self
            except OSError:
                if time.time() > fin:
                    self.tomado = False
                    return self
                time.sleep(0.5)

    def __exit__(self, *_):
        import msvcrt
        try:
            if self.tomado:
                self.f.seek(0)
                msvcrt.locking(self.f.fileno(), msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
        self.f.close()


def esperar_apertura(prof, plazo=20):
    """After launching the browser, waits until its profile is open (so another launcher can see it)."""
    fin = time.time() + plazo
    while time.time() < fin and not navegador_abierto(prof):
        time.sleep(0.5)


# --- Hidden IP ---------------------------------------------------------------
# IP always hidden ("always, not sometimes"): nothing goes directly to the Internet, not even
# accounts; only this PC and the home network, which do not show your IP to anyone outside. On top
# of that, the Windows firewall (Security\IP-Always-Hidden.ps1) stops LibreWolf from reaching the
# Internet outside the tunnel. If False: CONSERVAR and DIRECTOS_EXTRA go direct.
# Only exception (chosen by the user, site by site): those in direct.txt, which reject Tor, go out
# directly through the protected local gate (direct_gate.py, 127.0.0.1:9060); the firewall stays
# closed for LibreWolf, and third-party content those pages load still goes through Tor.
IP_SIEMPRE_OCULTA = True
# Mojeek does not answer through Tor (tested through five different exits).
DIRECTOS_EXTRA = ("mojeek.com",)
# True: on ALL pages the time is shown in UTC (as in Tor Browser) and pages that go through Tor do
# not see your time zone. In exchange, Gmail, WhatsApp Web and similar sites will show times shifted
# by your UTC offset. LibreWolf cannot do this only for pages that go through Tor, and it takes the
# regional format from Windows with no way to change it only in the browser (tested).
UBICACION_OCULTA = False
PAC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "route.pac")
def _distro():
    """First Ubuntu distribution installed in WSL."""
    try:
        out = subprocess.run(["wsl.exe", "-l", "-q"], capture_output=True,
                             creationflags=0x08000000).stdout.decode("utf-16-le", "ignore")
        return next((d.strip() for d in out.splitlines() if d.strip().lower().startswith("ubuntu")), "Ubuntu")
    except Exception:
        return "Ubuntu"


DISTRO = _distro()
MOTOR = "~/.smiley/tor-browser.sh"
SOCKS = ("127.0.0.1", 9050)
SIN_VENTANA = 0x08000000

PLANTILLA_PAC = r"""// Written by launch_browser.pyw on every start: do not edit by hand.
// Direct: only this PC and the home network (and DIRECTOS, empty while IP_SIEMPRE_OCULTA). Everything
// else goes through Tor; per-site routing is decided by the filter in librewolf.overrides.cfg (direct
// gate 9060 for direct.txt, engine 9055 for chosen_exit.txt). Without Tor there is no direct plan B.
var DIRECTOS = __DIRECTOS__;
var LOCALES = [".local", ".lan", ".home.arpa", ".internal"];
function FindProxyForURL(url, host) {
  host = host.toLowerCase();
  if (isPlainHostName(host) || host == "localhost" || host == "::1" || host == "[::1]" ||
      /^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host) ||
      /^172\.(1[6-9]|2[0-9]|3[01])\./.test(host) || /^169\.254\./.test(host)) return "DIRECT";
  for (var i = 0; i < LOCALES.length; i++) if (dnsDomainIs(host, LOCALES[i])) return "DIRECT";
  for (var j = 0; j < DIRECTOS.length; j++) {
    if (host == DIRECTOS[j] || dnsDomainIs(host, "." + DIRECTOS[j])) return "DIRECT";
  }
  return "SOCKS5 127.0.0.1:9050";
}
"""


DIRECTOS_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "direct.txt")
PUERTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "direct_gate.py")


def directos_protegidos():
    """{site: [own domains]} from direct.txt: they go out directly through the protected local gate."""
    sitios = {}
    try:
        with open(DIRECTOS_TXT, encoding="utf-8") as f:
            for linea in f:
                partes = linea.split("#", 1)[0].lower().split()
                if partes:
                    sitios[partes[0]] = partes[1:]
    except OSError:
        pass
    return sitios


def puerta_activa():
    try:
        with socket.create_connection(("127.0.0.1", 9060), timeout=1):
            return True
    except OSError:
        return False


CARRERA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "race.py")
VELOCIDAD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "speed.json")


def carrera_activa():
    try:
        with socket.create_connection(("127.0.0.1", 9070), timeout=1):
            return True
    except OSError:
        return False


def encender_carrera():
    """tor_watchdog.pyw keeps the circuit race running; if it is not there, it is started here, windowless."""
    if carrera_activa():
        return
    subprocess.Popen([sys.executable, CARRERA], creationflags=0x00000008 | SIN_VENTANA, close_fds=True)


def parametros_navegador():
    """Block "navegador" of speed.json: thresholds for the automatic new circuit and for fonts."""
    datos = {"lento_ms": 7000, "atasco_ms": 12000, "fuentes_ms": 200}
    try:
        with open(VELOCIDAD, encoding="utf-8") as f:
            datos.update(json.load(f).get("navegador") or {})
    except (OSError, ValueError):
        pass
    return {k: int(v) for k, v in datos.items()}


def encender_puerta():
    """tor_watchdog.pyw keeps the gate running; if it is not there, it is started here on its own, windowless."""
    if puerta_activa():
        return
    subprocess.Popen([sys.executable, PUERTA], creationflags=0x00000008 | SIN_VENTANA, close_fds=True)


def directos_ruta():
    """Internet sites that go direct: none with IP_SIEMPRE_OCULTA."""
    if IP_SIEMPRE_OCULTA:
        return []
    return sorted(set(CONSERVAR + DIRECTOS_EXTRA) - {"localhost", "127.0.0.1"})


def escribir_pac():
    """Browser routing: direct only for this PC, the home network and directos_ruta(); the rest through Tor."""
    texto = PLANTILLA_PAC.replace("__DIRECTOS__", json.dumps(directos_ruta()))
    with open(PAC, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)


PREFS_PROPIAS = ("smiley.directos", "smiley.elegida", "smiley.lento_ms", "smiley.atasco_ms", "gfx.downloadable_fonts.fallback_delay\"", "privacy.fingerprintingProtection.granularOverrides")


def escribir_preferencias(prof):
    """Profile user.js: the sites in direct.txt (they go out through the protected direct gate, with their
    own domains), those in chosen_exit.txt, the speed.json thresholds and, for the CONSERVAR sites, the
    fingerprinting-protection exception for time and language (each tab's time and language are then
    set by the "Ubicacion oculta" block of librewolf.overrides.cfg)."""
    cuentas = sorted(set(CONSERVAR + DIRECTOS_EXTRA) - {"localhost", "127.0.0.1"})
    locales = [{"firstPartyDomain": d, "overrides": "-JSDateTimeUTC,-JSLocale"} for d in cuentas]
    nuevas = [
        f'user_pref("smiley.directos", {json.dumps(",".join(sorted(directos_protegidos())))});',
        f'user_pref("smiley.directos.grupos", {json.dumps(json.dumps(directos_protegidos()))});',
        f'user_pref("smiley.elegida", {json.dumps(",".join(elegidos()))});',
        f'user_pref("smiley.lento_ms", {parametros_navegador()["lento_ms"]});',
        f'user_pref("smiley.atasco_ms", {parametros_navegador()["atasco_ms"]});',
        f'user_pref("gfx.downloadable_fonts.fallback_delay", {parametros_navegador()["fuentes_ms"]});',
        'user_pref("privacy.fingerprintingProtection.granularOverrides", '
        f'{json.dumps(json.dumps(locales, separators=(",", ":")))});',
    ]
    archivo = os.path.join(prof, "user.js")
    previas = []
    if os.path.exists(archivo):
        with open(archivo, encoding="utf-8") as f:
            previas = [l.rstrip("\n") for l in f if not any(p in l for p in PREFS_PROPIAS)]
    with open(archivo, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(previas + nuevas) + "\n")


def motor_activo():
    try:
        with socket.create_connection(SOCKS, timeout=1):
            return True
    except OSError:
        return False


def encender_motor():
    """Starts the Browser's Tor in Ubuntu, windowless. True if this call started it."""
    if motor_activo():
        return False
    subprocess.Popen(["wsl.exe", "-d", DISTRO, "--", MOTOR], creationflags=SIN_VENTANA,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True


# Chosen exit: sites that block by country rather than for being Tor (some education or government portals) still go
# through Tor, but through a second engine (127.0.0.1:9055, tor-chosen.sh) that only exits through the countries
# in chosen_exit.txt. Same WebTunnel bridge: the IP stays hidden.
SALIDA_ELEGIDA_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "chosen_exit.txt")
MOTOR_ELEGIDA = "~/.smiley/tor-chosen.sh"
SOCKS_ELEGIDA = ("127.0.0.1", 9055)


def elegidos():
    """Sites in chosen_exit.txt (the "countries:" line is not a site)."""
    sitios = []
    try:
        with open(SALIDA_ELEGIDA_TXT, encoding="utf-8") as f:
            for linea in f:
                l = linea.split("#", 1)[0].strip().lower()
                if l and not l.startswith(("countries:", "paises:")):
                    sitios.append(l.split()[0])
    except OSError:
        pass
    return sitios


def elegida_activa():
    try:
        with socket.create_connection(SOCKS_ELEGIDA, timeout=1):
            return True
    except OSError:
        return False


def encender_elegida():
    """Starts the chosen-exit engine, windowless, if any site uses it. True if it started it."""
    if not elegidos() or elegida_activa():
        return False
    subprocess.Popen(["wsl.exe", "-d", DISTRO, "--", MOTOR_ELEGIDA], creationflags=SIN_VENTANA,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True


# Tor always on, with or without the browser. Kept alive by tor_watchdog.pyw.
MOTOR_SIEMPRE = True


def apagar_motor():
    if MOTOR_SIEMPRE:
        return
    subprocess.run(["wsl.exe", "-d", DISTRO, "--", MOTOR, "--apagar"], creationflags=SIN_VENTANA,
                   capture_output=True, timeout=60)


def esperar_cierre(prof=None):
    # The launched process may exit before the browser does: wait until it releases its profile.
    while navegador_abierto(prof):
        time.sleep(3)
    time.sleep(2)


REGISTRO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lanzador.log")


def anotar_fallo(donde, error):
    """The launcher runs windowless: failures are logged here (no pages or data, only the error)."""
    try:
        if os.path.exists(REGISTRO) and os.path.getsize(REGISTRO) > 64 * 1024:
            os.replace(REGISTRO, REGISTRO + ".1")
        with open(REGISTRO, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + f"{donde}: {type(error).__name__}: {error}\n")
    except OSError:
        pass


def limpiar_seguro(prof, donde):
    """Clears without ever keeping the browser from opening: if something fails, it is logged and the
    launcher carries on (a missing session file used to crash the launcher before the Browser opened)."""
    try:
        limpiar(prof)
    except Exception as e:
        anotar_fallo(donde, e)


def limpiar_tras_cierre(prof):
    """With the browser already closed: clears, unless another launcher reopened it in the meantime
    (then the clean-up is that launcher's job, when it closes)."""
    with Candado():
        if navegador_abierto(prof):
            return
        apagar_motor()
        limpiar_seguro(prof, "clean-up on close")


def limpiar(prof):
    """Deletes cookies and site data except CONSERVAR. Returns what was deleted."""
    borradas = 0
    db = os.path.join(prof, "cookies.sqlite")
    if os.path.exists(db):
        c = sqlite3.connect(db)
        hosts = [h for (h,) in c.execute("SELECT DISTINCT host FROM moz_cookies")]
        fuera = [h for h in hosts if not se_conserva(h)]
        for h in fuera:
            borradas += c.execute("DELETE FROM moz_cookies WHERE host = ?", (h,)).rowcount
        c.commit()
        c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        c.close()

    # Site storage: storage/default/https+++site.com[^...]
    carpetas = 0
    for d in glob.glob(os.path.join(prof, "storage", "default", "*")):
        nombre = os.path.basename(d)
        if not nombre.startswith(("http+++", "https+++")):
            continue
        host = nombre.split("+++", 1)[1].split("^")[0].split("+")[0]
        partes = nombre.split("partitionKey=")
        clave = partes[1] if len(partes) > 1 else ""
        if se_conserva(host) and (not clave or any(x in clave for x in CONSERVAR)):
            continue
        shutil.rmtree(d, ignore_errors=True)
        carpetas += 1
    # Profile cache (lives in AppData\Local, not Roaming): the CONSERVAR sites' cache is kept, so they
    # do not re-download everything through Tor on every start; the rest is deleted.
    local = os.path.join(os.path.expandvars(r"%LOCALAPPDATA%\librewolf\Profiles"), os.path.basename(prof), "cache2")
    limpiar_cache(local)
    limpiar_sesion(prof)
    return borradas, carpetas


def clave_cache(ruta):
    """Key of a cache2 entry (e.g. 'O^partitionKey=%28https%2Ctwitch.tv%29,a,:https://...').
    The file's last 4 bytes say where the metadata starts; the key follows the metadata hash, the hashes
    of each 256 KB chunk and a 32-byte header."""
    with open(ruta, "rb") as f:
        f.seek(-4, os.SEEK_END)
        fin_datos = struct.unpack(">I", f.read(4))[0]
        trozos = (fin_datos + 262143) // 262144
        f.seek(fin_datos + 4 + 2 * trozos)
        cabecera = f.read(32)
        largo = struct.unpack(">I", cabecera[24:28])[0]
        return f.read(largo).decode("utf-8", "replace")


def sitio_de_clave(clave):
    m = re.search(r"partitionKey=%28https?%2C([^%,)]+)", clave)
    if m:
        return m.group(1)
    m = re.search(r":https?://([^/:]+)", clave)
    return m.group(1) if m else ""


def limpiar_cache(local):
    """Deletes from cache2 everything not belonging to a CONSERVAR site (anything doubtful is deleted too)."""
    entradas = os.path.join(local, "entries")
    if not os.path.isdir(entradas):
        shutil.rmtree(local, ignore_errors=True)
        return
    for e in os.scandir(entradas):
        try:
            sitio = sitio_de_clave(clave_cache(e.path))
        except (OSError, struct.error, ValueError):
            sitio = ""
        if not sitio or not se_conserva(sitio):
            try:
                os.remove(e.path)
            except OSError:
                pass
    # The index rebuilds itself on start; anything half-written goes.
    for resto in ("index", "index.log"):
        try:
            os.remove(os.path.join(local, resto))
        except OSError:
            pass
    for d in glob.glob(os.path.join(local, "doomed")) + glob.glob(os.path.join(local, "trash*")):
        shutil.rmtree(d, ignore_errors=True)


def lz4_leer(src):
    """Decompresses an LZ4 block (the .jsonlz4 format)."""
    dst = bytearray()
    i, n = 0, len(src)
    while i < n:
        tok = src[i]
        i += 1
        largo = tok >> 4
        if largo == 15:
            while True:
                b = src[i]
                i += 1
                largo += b
                if b != 255:
                    break
        dst += src[i:i + largo]
        i += largo
        if i >= n:
            break
        desp = src[i] | (src[i + 1] << 8)
        i += 2
        largo = tok & 15
        if largo == 15:
            while True:
                b = src[i]
                i += 1
                largo += b
                if b != 255:
                    break
        largo += 4
        ini = len(dst) - desp
        if desp >= largo:
            dst += dst[ini:ini + largo]
        else:
            for k in range(largo):
                dst.append(dst[ini + k])
    return bytes(dst)


def lz4_escribir(datos):
    """Valid uncompressed LZ4 block: a single literal sequence."""
    n = len(datos)
    out = bytearray()
    if n < 15:
        out.append(n << 4)
    else:
        out.append(0xF0)
        r = n - 15
        while r >= 255:
            out.append(255)
            r -= 255
        out.append(r)
    return bytes(out + datos)


def cookie_se_conserva(c):
    if not se_conserva(c.get("host", "")):
        return False
    clave = (c.get("originAttributes") or {}).get("partitionKey", "")
    return not clave or any(x in clave for x in CONSERVAR)


def limpiar_sesion(prof):
    """Leaves each session file with the smiley page and the CONSERVAR cookies."""
    for f in glob.glob(os.path.join(prof, "sessionstore-backups", "recovery*")):
        os.remove(f)
    archivos = [os.path.join(prof, "sessionstore.jsonlz4")]
    archivos += glob.glob(os.path.join(prof, "sessionstore-backups", "*.jsonlz4*"))
    for f in archivos:
        if not os.path.exists(f):
            continue  # new profile or abrupt close: no session to clear
        try:
            with open(f, "rb") as h:
                crudo = h.read()
            if not crudo.startswith(MOZLZ4):
                continue
            j = json.loads(lz4_leer(crudo[12:]))
        except (OSError, ValueError, IndexError):
            try:
                os.remove(f)  # unreadable: better no session than foreign cookies
            except OSError:
                pass
            continue
        j["cookies"] = [c for c in j.get("cookies", []) if cookie_se_conserva(c)]
        ventanas = j.get("windows") or j.get("_closedWindows") or [{}]
        v = ventanas[0]
        v.update(tabs=[{"entries": [{"url": INICIO, "title": "Browser",
                                     "triggeringPrincipal_base64": '{"3":{}}'}],
                        "index": 1, "hidden": False, "userContextId": 0, "attributes": {}}],
                 selected=1, _closedTabs=[], groups=[], closedGroups=[], splitViews=[],
                 title="Browser")
        j["windows"] = [v]
        j["selectedWindow"] = 1
        j["_closedWindows"] = []
        j["savedGroups"] = []
        datos = json.dumps(j, separators=(",", ":")).encode("utf-8")
        with open(f, "wb") as h:
            h.write(MOZLZ4 + struct.pack("<I", len(datos)) + lz4_escribir(datos))


def main():
    try:
        escribir_pac()
    except OSError:
        pass  # the previous routing stays; the browser is never kept from opening because of this
    try:
        encender_puerta()
    except OSError:
        pass
    try:
        encender_elegida()
    except OSError:
        pass
    try:
        encender_carrera()
    except OSError:
        pass
    try:
        encendido = encender_motor()
    except OSError:
        encendido = False
    prof = perfil()
    args = sys.argv[1:]
    with Candado():
        if navegador_abierto(prof) or not prof:
            # Already open: just pass it the address.
            subprocess.Popen([LIBREWOLF] + args)
            ya_abierto = True
        else:
            ya_abierto = False
            limpiar_seguro(prof, "clean-up on open")
            try:
                escribir_preferencias(prof)
            except Exception as e:
                anotar_fallo("user.js settings", e)
            entorno = dict(os.environ, TZ="UTC") if UBICACION_OCULTA else None
            proc = subprocess.Popen([LIBREWOLF] + args, env=entorno)
            esperar_apertura(prof)
    if ya_abierto:
        if encendido:
            # It had been opened another way, without the engine: stop it when the browser closes.
            esperar_cierre(prof)
            apagar_motor()
        return
    proc.wait()
    esperar_cierre(prof)
    limpiar_tras_cierre(prof)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--limpiar":
        print(limpiar(sys.argv[2] if len(sys.argv) > 2 else perfil()))
    else:
        main()
