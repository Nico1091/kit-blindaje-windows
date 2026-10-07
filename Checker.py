"""Protection checker: lightweight, low priority, and sends none of your data anywhere.

1. Visits pages and confirms each one encrypts with TLS 1.3.
2. Checks that ads and trackers are blocked by the local DNS.
3. Reviews which connections are going out right now and whether any go to known telemetry.
4. Checks that Windows, Office and Browser telemetry is at the minimum.
5. If Tor is running, confirms it exits through the Tor network.
The report is saved in Security\\Reports.
"""
import datetime
import socket
import ssl
import subprocess
import winreg
from pathlib import Path

import psutil

psutil.Process().nice(psutil.IDLE_PRIORITY_CLASS)  # does not compete with what the user is doing

PAGINAS = ["www.mojeek.com", "en.wikipedia.org", "www.eltiempo.com", "github.com", "duckduckgo.com"]
ANUNCIOS = ["doubleclick.net", "googlesyndication.com", "adservice.google.com", "ads.yahoo.com", "scorecardresearch.com"]
TELEMETRIA = ("vortex", "telemetry", "watson", "settings-win", "self.events", "browser.events", "diagtrack",
              "scorecardresearch", "doubleclick", "app-measurement", "google-analytics")
OVERRIDES = Path.home() / ".librewolf" / "librewolf.overrides.cfg"
informe = []


def linea(ok, texto):
    informe.append(f"[{'OK' if ok else '!!'}] {texto}")


def visitar(host):
    ctx = ssl.create_default_context()
    try:
        with socket.create_connection((host, 443), timeout=8) as s, ctx.wrap_socket(s, server_hostname=host) as t:
            t.sendall(f"HEAD / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode())
            t.recv(64)
            return t.version()
    except OSError as e:
        return f"no answer ({e.__class__.__name__})"


def resuelve(dominio):
    try:
        return socket.gethostbyname(dominio) not in ("0.0.0.0", "127.0.0.1")
    except OSError:
        return False


def reg(ruta, nombre, raiz=winreg.HKEY_LOCAL_MACHINE):
    try:
        with winreg.OpenKey(raiz, ruta) as k:
            return winreg.QueryValueEx(k, nombre)[0]
    except OSError:
        return None


informe.append("1. Page visits (encryption)")
for p in PAGINAS:
    v = visitar(p)
    linea(v == "TLSv1.3", f"{p}: {v}")

informe.append("\n2. Ad and tracker blocking")
for d in ANUNCIOS:
    linea(not resuelve(d), f"{d}: {'resolves (NOT blocked)' if resuelve(d) else 'blocked'}")

informe.append("\n3. Outgoing connections right now")
vistos = {}
for c in psutil.net_connections("inet"):
    if c.status != "ESTABLISHED" or not c.raddr:
        continue
    ip = c.raddr.ip
    if ip.startswith(("127.", "::1", "192.168.", "10.", "172.", "fe80")):
        continue
    try:
        nombre = psutil.Process(c.pid).name()
    except (psutil.Error, TypeError):
        nombre = "?"
    vistos.setdefault(nombre, set()).add(ip)
sospechosas = 0
for nombre, ips in sorted(vistos.items()):
    destinos = []
    for ip in list(ips)[:4]:
        try:
            destinos.append(socket.gethostbyaddr(ip)[0])
        except OSError:
            destinos.append(ip)
    malo = any(t in d.lower() for d in destinos for t in TELEMETRIA)
    sospechosas += malo
    linea(not malo, f"{nombre}: {', '.join(destinos)}")
if not vistos:
    linea(True, "no outgoing connections")

informe.append("\n4. Telemetry at the minimum")
dc = r"SOFTWARE\Policies\Microsoft\Windows\DataCollection"
linea(reg(dc, "AllowTelemetry") == 0, f"Windows diagnostic level (AllowTelemetry): {reg(dc, 'AllowTelemetry')} (0 = minimum)")
linea(reg(dc, "AllowDeviceNameInTelemetry") == 0, "Windows does not send the device name")
linea(reg(r"Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo", "Enabled", winreg.HKEY_CURRENT_USER) == 0,
      "Advertising ID off")
linea(reg(r"Software\Microsoft\Windows\CurrentVersion\Search", "BingSearchEnabled", winreg.HKEY_CURRENT_USER) == 0,
      "The Start menu does not send what you type to Bing")
linea(reg(r"Software\Policies\Microsoft\office\common\clienttelemetry", "sendtelemetry", winreg.HKEY_CURRENT_USER) == 3,
      "Office: diagnostics set to 'none'")
linea(reg(r"Software\Policies\Microsoft\office\16.0\common\privacy", "usercontentdisabled", winreg.HKEY_CURRENT_USER) == 2,
      "Office does not upload document content")
try:
    diag = psutil.win_service_get("DiagTrack").as_dict()
    informe.append(f"[--] Windows diagnostic service: {diag['status']} (left on: disabling it risks breaking Windows)")
except psutil.Error:
    linea(True, "Windows diagnostic service: not present")
cfg = OVERRIDES.read_text(encoding="utf-8") if OVERRIDES.exists() else ""
for pref in ("toolkit.telemetry.enabled\", false", "datareporting.healthreport.uploadEnabled\", false",
             "security.tls.version.min\", 3", "devtools.debugger.remote-enabled\", false"):
    linea(f'lockPref("{pref})' in cfg, f"Browser, lock {pref.split(chr(34))[0]}")
# 2026-10-04: TLS 1.2 allowed with a handshake identical to Firefox's; weak ciphers are cut afterwards (watched TLS)
linea("--- TLS vigilado" in cfg, "Browser: cuts connections with weak encryption (watched TLS)")
linea("--- Avisos ocultos" in cfg, "Browser: hides terms and chat-rules notices without accepting them")

informe.append("\n5. Tor and Browser exits")
def escucha(puerto):
    return any(c.laddr.port == puerto and c.status == "LISTEN" for c in psutil.net_connections("inet"))
for puerto, nombre in ((9050, "Regular Tor"), (9055, "Tor with chosen exit")):
    if escucha(puerto):
        r = subprocess.run(["curl.exe", "-s", "--max-time", "40", "--socks5-hostname",
                            f"comprobador{puerto}:x@127.0.0.1:{puerto}", "https://check.torproject.org/api/ip"],
                           capture_output=True, text=True)
        linea('"IsTor":true' in r.stdout, f"{nombre}: {r.stdout.strip() or 'still connecting'}")
    else:
        linea(False, f"{nombre}: port {puerto} is not listening (the watchdog starts it within 2 minutes)")
linea(escucha(9060), "Protected direct gate (only the sites in Browser\\direct.txt) on 127.0.0.1:9060")
if escucha(9070):
    r = subprocess.run(["curl.exe", "-s", "--max-time", "40", "--socks5-hostname",
                        "comprobador-carrera:smiley@127.0.0.1:9070", "https://check.torproject.org/api/ip"],
                       capture_output=True, text=True)
    linea('"IsTor":true' in r.stdout, f"Circuit race (9070) exits through Tor: {r.stdout.strip() or 'still connecting'}")
else:
    linea(False, "Circuit race (9070) is not listening: the browser uses Tor directly (slower, just as hidden)")
try:
    import json as _json
    _v = _json.loads((Path.home() / "Security" / "Browser" / "speed.json").read_text(encoding="utf-8"))
    _a = _v.get("ultimo_afinado") or {}
    if _a:
        _c = _a.get("con_la_elegida", {})
        informe.append(f"[--] Last tuning ({_a.get('fecha')}): target {'MET' if _a.get('cumplido') else 'not met'}; "
                       f"median response {_c.get('mediana_s')} s, p90 {_c.get('p90_s')} s, slow {_c.get('lentas_pct')} %")
except (OSError, ValueError):
    pass

malos = sum(l.startswith("[!!]") for l in informe)
informe.append(f"\nResult: {'ALL GOOD' if malos == 0 else f'{malos} item(s) to review'}")
texto = "\n".join(informe)
print(texto)
d = Path.home() / "Security" / "Reports"
d.mkdir(parents=True, exist_ok=True)
(d / f"checker-{datetime.datetime.now():%Y%m%d-%H%M}.txt").write_text(texto, encoding="utf-8")
