"""Comprobador de proteccion: ligero, en prioridad baja y sin enviar datos propios a nadie.

1. Visita paginas y confirma que cada una cifra con TLS 1.3.
2. Comprueba que los anuncios y rastreadores esten bloqueados en el DNS local.
3. Revisa que conexiones salen ahora mismo y si alguna va a telemetria conocida.
4. Revisa que la telemetria de Windows, Office y del Buscador este al minimo.
5. Si Tor esta abierto, confirma que sale por la red Tor.
El informe queda en Seguridad\\Informes.
"""
import datetime
import socket
import ssl
import subprocess
import winreg
from pathlib import Path

import psutil

psutil.Process().nice(psutil.IDLE_PRIORITY_CLASS)  # no compite con lo que el use

PAGINAS = ["www.mojeek.com", "es.wikipedia.org", "www.eltiempo.com", "github.com", "duckduckgo.com"]
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
        return f"sin respuesta ({e.__class__.__name__})"


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


informe.append("1. Visitas a paginas (cifrado)")
for p in PAGINAS:
    v = visitar(p)
    linea(v == "TLSv1.3", f"{p}: {v}")

informe.append("\n2. Bloqueo de anuncios y rastreadores")
for d in ANUNCIOS:
    linea(not resuelve(d), f"{d}: {'resuelve (NO bloqueado)' if resuelve(d) else 'bloqueado'}")

informe.append("\n3. Conexiones que salen ahora")
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
    linea(True, "ninguna conexion hacia fuera")

informe.append("\n4. Telemetria al minimo")
dc = r"SOFTWARE\Policies\Microsoft\Windows\DataCollection"
linea(reg(dc, "AllowTelemetry") == 0, f"Windows, nivel de diagnostico (AllowTelemetry): {reg(dc, 'AllowTelemetry')} (0 = el minimo)")
linea(reg(dc, "AllowDeviceNameInTelemetry") == 0, "Windows no envia el nombre del equipo")
linea(reg(r"Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo", "Enabled", winreg.HKEY_CURRENT_USER) == 0,
      "Id de publicidad apagado")
linea(reg(r"Software\Microsoft\Windows\CurrentVersion\Search", "BingSearchEnabled", winreg.HKEY_CURRENT_USER) == 0,
      "El menu Inicio no envia lo que escribe a Bing")
linea(reg(r"Software\Policies\Microsoft\office\common\clienttelemetry", "sendtelemetry", winreg.HKEY_CURRENT_USER) == 3,
      "Office: diagnostico en 'ninguno'")
linea(reg(r"Software\Policies\Microsoft\office\16.0\common\privacy", "usercontentdisabled", winreg.HKEY_CURRENT_USER) == 2,
      "Office no sube el contenido de los documentos")
try:
    diag = psutil.win_service_get("DiagTrack").as_dict()
    informe.append(f"[--] Servicio de diagnostico de Windows: {diag['status']} (se deja: apagarlo arriesga el bloqueo de Windows)")
except psutil.Error:
    linea(True, "Servicio de diagnostico de Windows: no existe")
cfg = OVERRIDES.read_text(encoding="utf-8") if OVERRIDES.exists() else ""
for pref in ("toolkit.telemetry.enabled\", false", "datareporting.healthreport.uploadEnabled\", false",
             "security.tls.version.min\", 3", "devtools.debugger.remote-enabled\", false"):
    linea(f'lockPref("{pref})' in cfg, f"Buscador, candado {pref.split(chr(34))[0]}")
# 04/10/2026: TLS 1.2 permitido con saludo identico al de Firefox; lo debil se corta despues (TLS vigilado)
linea("--- TLS vigilado" in cfg, "Buscador: corta conexiones con cifrado debil (TLS vigilado)")
linea("--- Avisos ocultos" in cfg, "Buscador: oculta avisos de terminos y reglas del chat sin aceptarlos")

informe.append("\n5. Tor y salidas del Buscador")
def escucha(puerto):
    return any(c.laddr.port == puerto and c.status == "LISTEN" for c in psutil.net_connections("inet"))
for puerto, nombre in ((9050, "Tor normal"), (9055, "Tor con salida elegida")):
    if escucha(puerto):
        r = subprocess.run(["curl.exe", "-s", "--max-time", "40", "--socks5-hostname",
                            f"comprobador{puerto}:x@127.0.0.1:{puerto}", "https://check.torproject.org/api/ip"],
                           capture_output=True, text=True)
        linea('"IsTor":true' in r.stdout, f"{nombre}: {r.stdout.strip() or 'aun conectando'}")
    else:
        linea(False, f"{nombre}: el puerto {puerto} no escucha (lo enciende el vigilante en menos de 2 minutos)")
linea(escucha(9060), "Puerta directa protegida (solo los sitios de Buscador\\directos.txt) en 127.0.0.1:9060")
if escucha(9070):
    r = subprocess.run(["curl.exe", "-s", "--max-time", "40", "--socks5-hostname",
                        "comprobador-carrera:carita@127.0.0.1:9070", "https://check.torproject.org/api/ip"],
                       capture_output=True, text=True)
    linea('"IsTor":true' in r.stdout, f"Carrera de circuitos (9070) sale por Tor: {r.stdout.strip() or 'aun conectando'}")
else:
    linea(False, "Carrera de circuitos (9070) no escucha: el navegador usa Tor directo (mas lento, igual de oculto)")
try:
    import json as _json
    _v = _json.loads((Path.home() / "Seguridad" / "Buscador" / "velocidad.json").read_text(encoding="utf-8"))
    _a = _v.get("ultimo_afinado") or {}
    if _a:
        _c = _a.get("con_la_elegida", {})
        informe.append(f"[--] Ultimo afinado ({_a.get('fecha')}): {'CUMPLE' if _a.get('cumplido') else 'no cumple'} el objetivo; "
                       f"respuesta mediana {_c.get('mediana_s')} s, p90 {_c.get('p90_s')} s, lentas {_c.get('lentas_pct')} %")
except (OSError, ValueError):
    pass

malos = sum(l.startswith("[!!]") for l in informe)
informe.append(f"\nResultado: {'TODO EN ORDEN' if malos == 0 else f'{malos} punto(s) a revisar'}")
texto = "\n".join(informe)
print(texto)
d = Path.home() / "Seguridad" / "Informes"
d.mkdir(parents=True, exist_ok=True)
(d / f"comprobador-{datetime.datetime.now():%Y%m%d-%H%M}.txt").write_text(texto, encoding="utf-8")
