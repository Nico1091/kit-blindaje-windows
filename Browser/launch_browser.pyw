"""
Lanzador del Browser.

LibreWolf 156 ignora las excepciones de cookies cuando borra al cerrar: o lo
borra todo (y se pierden las sesiones de correo) o no borra nada. Este
lanzador hace el borrado por su cuenta: antes de abrir y despues de cerrar
elimina cookies y datos de sitios de TODAS las paginas excepto las de la
lista CONSERVAR. Todo ocurre en local, sobre los archivos del perfil.

Las cookies de sesion (sin fecha; NetAcad entra con una) no llegan nunca a
cookies.sqlite: solo sobreviven dentro del archivo de sesion, y por eso el
navegador restaura la sesion al abrir. El lanzador reescribe ese archivo al
cerrar: una sola pestana con la smiley y solo las cookies de CONSERVAR.

IP oculta (desde el 02/10/2026, "siempre"): todo sale por Tor, tambien las
cuentas. Al abrir enciende, si faltan, el motor Tor de Ubuntu (127.0.0.1:9050, por
puentes WebTunnel), el de salida elegida (9055), la carrera de circuitos (9070) y
la puerta directa protegida (9060, solo para direct.txt); normalmente ya los
mantiene tor_watchdog.pyw, porque el motor no se apaga al cerrar (MOTOR_SIEMPRE).
Escribe route.pac (directo solo este equipo y la red de casa) y en user.js los
sitios de direct.txt y de chosen_exit.txt; la ruta de cada pagina la decide
el filtro de librewolf.overrides.cfg. Si el motor no esta, las paginas que van
por Tor no salen: no hay plan B directo.

Un solo lanzador a la vez limpia o abre (candado .lanzador.lock), y "abierto"
significa que el perfil del Browser esta en uso, no que haya un librewolf.exe
cualquiera (las pruebas usan perfiles temporales).
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

# Dominios cuya sesion se guarda (y todos sus subdominios).
CONSERVAR = (
    # Correo y cuentas
    "google.com", "youtube.com",
    "live.com", "outlook.com", "microsoftonline.com", "cloud.microsoft", "microsoft.com", "office.com",
    # Trabajo y desarrollo
    "github.com", "linkedin.com", "localhost", "127.0.0.1",
    # IA
    "chatgpt.com", "openai.com", "claude.ai", "anthropic.com",
    # Agregue aqui los dominios cuya sesion quiere conservar (y todos sus subdominios).
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
    """Mientras el navegador tiene abierto un perfil, Windows no deja abrir su parent.lock (medido el
    04/10/2026); cerrado, se abre. Asi solo cuenta el perfil del Browser y no los LibreWolf de pruebas,
    que usan perfiles temporales."""
    try:
        with open(os.path.join(prof, "parent.lock"), "rb"):
            return False
    except FileNotFoundError:
        return False
    except OSError:
        return True


def navegador_abierto(prof=None):
    """True si el Browser (su perfil) esta abierto. Antes contaba cualquier librewolf.exe, y con una
    prueba en marcha el lanzador creia el navegador abierto y se saltaba la limpieza."""
    if not proceso_librewolf():
        return False
    prof = prof or perfil()
    return perfil_en_uso(prof) if prof else True


CANDADO = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".lanzador.lock")


class Candado:
    """Un solo lanzador a la vez limpiando el perfil o abriendo el navegador (04/10/2026). Si un lanzador
    viejo seguia esperando el cierre y el navegador se cerraba y se volvia a abrir enseguida, los dos
    limpiaban a la vez, o uno limpiaba mientras el otro abria. Windows suelta el candado si el proceso
    muere; si en 90 s no se consigue, se sigue igual: nunca se deja de abrir el navegador por esto."""

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
    """Tras lanzar el navegador, espera a que tenga su perfil abierto (asi otro lanzador ya lo ve)."""
    fin = time.time() + plazo
    while time.time() < fin and not navegador_abierto(prof):
        time.sleep(0.5)


# --- IP oculta ---------------------------------------------------------------
# IP siempre oculta (pedida el 02/10/2026: "siempre, no a veces si y a veces no"): nada sale
# directo a internet, ni las cuentas; solo este equipo y la red de la casa, que no muestran la IP a
# nadie de fuera. Ademas el cortafuegos de Windows (Security\IP-Always-Hidden.ps1) impide que
# LibreWolf salga a internet por fuera del tunel. En False: CONSERVAR y DIRECTOS_EXTRA van directo.
# Unica excepcion (04/10/2026, decidida por el sitio por sitio): los de direct.txt, que rechazan a
# Tor, salen directo por la puerta local protegida (direct_gate.py, 127.0.0.1:9060); el cortafuegos
# sigue cerrado para LibreWolf, y lo que esas paginas carguen de terceros sigue por Tor.
IP_SIEMPRE_OCULTA = True
# Mojeek no responde por Tor (probado el 02/10/2026 por cinco salidas distintas).
DIRECTOS_EXTRA = ("mojeek.com",)
# True: en TODAS las paginas la hora sale en UTC (como Tor Browser) y las que van por Tor no ven tu
# zona horaria. A cambio, Gmail, WhatsApp Web o el aula virtual mostraran las horas 5 h adelantadas.
# LibreWolf no permite hacerlo solo en las paginas que van por Tor, y el formato regional es-CO lo
# toma de Windows sin forma de cambiarlo solo en el navegador (probado el 02/10/2026).
UBICACION_OCULTA = False
PAC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "route.pac")
def _distro():
    """Primera distribucion Ubuntu instalada en WSL."""
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

PLANTILLA_PAC = r"""// Lo escribe launch_browser.pyw en cada arranque: no editar a mano.
// Directo: solo este equipo y la red de la casa (y DIRECTOS, vacio mientras IP_SIEMPRE_OCULTA). Todo
// lo demas sale por Tor; la ruta fina por sitio la decide el filtro de librewolf.overrides.cfg (puerta
// directa 9060 para direct.txt, motor 9055 para chosen_exit.txt). Sin Tor, no hay plan B directo.
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
    """{sitio: [dominios propios]} de direct.txt: salen directo por la puerta local protegida."""
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
    """La carrera de circuitos la mantiene tor_watchdog.pyw; si no esta, se arranca aqui, sin ventana."""
    if carrera_activa():
        return
    subprocess.Popen([sys.executable, CARRERA], creationflags=0x00000008 | SIN_VENTANA, close_fds=True)


def parametros_navegador():
    """Bloque "navegador" de speed.json: umbrales del circuito nuevo automatico y de las fuentes."""
    datos = {"lento_ms": 7000, "atasco_ms": 12000, "fuentes_ms": 200}
    try:
        with open(VELOCIDAD, encoding="utf-8") as f:
            datos.update(json.load(f).get("navegador") or {})
    except (OSError, ValueError):
        pass
    return {k: int(v) for k, v in datos.items()}


def encender_puerta():
    """La puerta la mantiene tor_watchdog.pyw; si no esta, se arranca aqui por su cuenta, sin ventana."""
    if puerta_activa():
        return
    subprocess.Popen([sys.executable, PUERTA], creationflags=0x00000008 | SIN_VENTANA, close_fds=True)


def directos_ruta():
    """Sitios de internet que salen directo: ninguno con IP_SIEMPRE_OCULTA."""
    if IP_SIEMPRE_OCULTA:
        return []
    return sorted(set(CONSERVAR + DIRECTOS_EXTRA) - {"localhost", "127.0.0.1"})


def escribir_pac():
    """Ruta del Browser: directo solo este equipo, la red de la casa y directos_ruta(); lo demas por Tor."""
    texto = PLANTILLA_PAC.replace("__DIRECTOS__", json.dumps(directos_ruta()))
    with open(PAC, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)


PREFS_PROPIAS = ("smiley.directos", "smiley.elegida", "smiley.lento_ms", "smiley.atasco_ms", "gfx.downloadable_fonts.fallback_delay\"", "privacy.fingerprintingProtection.granularOverrides")


def escribir_preferencias(prof):
    """user.js del perfil: los sitios de direct.txt (salen por la puerta directa protegida, con sus
    dominios propios), los de chosen_exit.txt, los umbrales de speed.json y, para los sitios de
    CONSERVAR, la excepcion de la proteccion de huella para hora e idioma (la hora y el idioma de cada
    pestana los fija despues el bloque "Ubicacion oculta" de librewolf.overrides.cfg)."""
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
    """Enciende el Tor del Browser en Ubuntu, sin ventana. True si lo encendio esta llamada."""
    if motor_activo():
        return False
    subprocess.Popen(["wsl.exe", "-d", DISTRO, "--", MOTOR], creationflags=SIN_VENTANA,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True


# Salida elegida (04/10/2026): sitios que bloquean por pais y no por ser Tor (algunos portales educativos o del Estado) siguen
# por Tor, pero por un segundo motor (127.0.0.1:9055, tor-chosen.sh) que solo sale por los paises de
# chosen_exit.txt. Mismo puente WebTunnel: la IP sigue oculta.
SALIDA_ELEGIDA_TXT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "chosen_exit.txt")
MOTOR_ELEGIDA = "~/.smiley/tor-chosen.sh"
SOCKS_ELEGIDA = ("127.0.0.1", 9055)


def elegidos():
    """Sitios de chosen_exit.txt (la linea "paises:" no es un sitio)."""
    sitios = []
    try:
        with open(SALIDA_ELEGIDA_TXT, encoding="utf-8") as f:
            for linea in f:
                l = linea.split("#", 1)[0].strip().lower()
                if l and not l.startswith("paises:"):
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
    """Enciende el motor de salida elegida, sin ventana, si algun sitio lo usa. True si lo encendio."""
    if not elegidos() or elegida_activa():
        return False
    subprocess.Popen(["wsl.exe", "-d", DISTRO, "--", MOTOR_ELEGIDA], creationflags=SIN_VENTANA,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True


# Pedido suyo (02/10/2026): Tor encendido siempre, con o sin navegador. Lo mantiene tor_watchdog.pyw.
MOTOR_SIEMPRE = True


def apagar_motor():
    if MOTOR_SIEMPRE:
        return
    subprocess.run(["wsl.exe", "-d", DISTRO, "--", MOTOR, "--apagar"], creationflags=SIN_VENTANA,
                   capture_output=True, timeout=60)


def esperar_cierre(prof=None):
    # El proceso lanzado puede cerrar antes que el navegador: esperar a que suelte su perfil.
    while navegador_abierto(prof):
        time.sleep(3)
    time.sleep(2)


REGISTRO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lanzador.log")


def anotar_fallo(donde, error):
    """El lanzador corre sin ventana: lo que falle queda aqui (sin paginas ni datos, solo el error)."""
    try:
        if os.path.exists(REGISTRO) and os.path.getsize(REGISTRO) > 64 * 1024:
            os.replace(REGISTRO, REGISTRO + ".1")
        with open(REGISTRO, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + f"{donde}: {type(error).__name__}: {error}\n")
    except OSError:
        pass


def limpiar_seguro(prof, donde):
    """Limpia sin dejar nunca de abrir el navegador: si algo falla, se anota y se sigue (04/10/2026: un
    archivo de sesion que faltaba tumbaba el lanzador y el Browser no llegaba a abrirse)."""
    try:
        limpiar(prof)
    except Exception as e:
        anotar_fallo(donde, e)


def limpiar_tras_cierre(prof):
    """Con el navegador ya cerrado: limpia, salvo que otro lanzador lo haya vuelto a abrir entretanto
    (entonces la limpieza le toca a ese, cuando se cierre)."""
    with Candado():
        if navegador_abierto(prof):
            return
        apagar_motor()
        limpiar_seguro(prof, "limpieza al cerrar")


def limpiar(prof):
    """Borra cookies y datos de sitios salvo CONSERVAR. Devuelve lo borrado."""
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

    # Almacenamiento de sitios: storage/default/https+++sitio.com[^...]
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
    # Cache del perfil (vive en AppData\Local, no en Roaming): se conserva la de los sitios de
    # CONSERVAR, para que no vuelvan a bajar todo por Tor en cada apertura; la del resto se borra.
    local = os.path.join(os.path.expandvars(r"%LOCALAPPDATA%\librewolf\Profiles"), os.path.basename(prof), "cache2")
    limpiar_cache(local)
    limpiar_sesion(prof)
    return borradas, carpetas


def clave_cache(ruta):
    """Clave de una entrada de cache2 (p. ej. 'O^partitionKey=%28https%2Ctwitch.tv%29,a,:https://...').
    Los ultimos 4 bytes del archivo dicen donde empiezan los metadatos; la clave va tras el hash de los
    metadatos, los hashes de cada trozo de 256 KB y una cabecera de 32 bytes."""
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
    """Borra de cache2 todo lo que no sea de un sitio de CONSERVAR (lo dudoso tambien se borra)."""
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
    # El indice se rehace solo al abrir; lo que quede a medias, fuera.
    for resto in ("index", "index.log"):
        try:
            os.remove(os.path.join(local, resto))
        except OSError:
            pass
    for d in glob.glob(os.path.join(local, "doomed")) + glob.glob(os.path.join(local, "trash*")):
        shutil.rmtree(d, ignore_errors=True)


def lz4_leer(src):
    """Descomprime un bloque LZ4 (el formato de los .jsonlz4)."""
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
    """Bloque LZ4 valido sin comprimir: una sola secuencia de literales."""
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
    """Deja cada archivo de sesion con la smiley y las cookies de CONSERVAR."""
    for f in glob.glob(os.path.join(prof, "sessionstore-backups", "recovery*")):
        os.remove(f)
    archivos = [os.path.join(prof, "sessionstore.jsonlz4")]
    archivos += glob.glob(os.path.join(prof, "sessionstore-backups", "*.jsonlz4*"))
    for f in archivos:
        if not os.path.exists(f):
            continue  # perfil nuevo o cierre brusco: no hay sesion que limpiar
        try:
            with open(f, "rb") as h:
                crudo = h.read()
            if not crudo.startswith(MOZLZ4):
                continue
            j = json.loads(lz4_leer(crudo[12:]))
        except (OSError, ValueError, IndexError):
            try:
                os.remove(f)  # ilegible: mejor sin sesion que con cookies ajenas
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
        pass  # se queda la ruta anterior; nunca se deja de abrir el navegador por esto
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
            # Ya abierto: solo se le pasa la direccion.
            subprocess.Popen([LIBREWOLF] + args)
            ya_abierto = True
        else:
            ya_abierto = False
            limpiar_seguro(prof, "limpieza al abrir")
            try:
                escribir_preferencias(prof)
            except Exception as e:
                anotar_fallo("ajustes de user.js", e)
            entorno = dict(os.environ, TZ="UTC") if UBICACION_OCULTA else None
            proc = subprocess.Popen([LIBREWOLF] + args, env=entorno)
            esperar_apertura(prof)
    if ya_abierto:
        if encendido:
            # Se habia abierto por otra via, sin motor: se apaga cuando se cierre el navegador.
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
