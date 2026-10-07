# Keeps the Browser's Tor engine running from sign-in onwards.
# Started by the scheduled task "Browser - Tor always". Every 30 s it checks
# port 9050 and, if it does not answer, starts the engine in Ubuntu again.
# It also keeps the protected direct gate running (direct_gate.py, 127.0.0.1:9060), the
# browser's only direct way out and only for the sites in direct.txt; the chosen-exit engine
# (tor-chosen.sh, 127.0.0.1:9055) for those in chosen_exit.txt; and the circuit race
# (race.py, 127.0.0.1:9070), with parameters in speed.json.
#
# Real health: an open port is not enough. If the WebTunnel bridge dies, Tor keeps the port open
# without being able to get out, and the Browser would hang without recovering. Every 2 minutes
# it opens a test connection through each engine to check.torproject.org:443, over its own circuit
# ("vigia-salud"); after 3 failures in a row it restarts that engine (on start, the engine switches
# to all bridges if the first does not connect and requests new bridges if none do). Also, every
# 6 hours it asks for a bridge renewal (bridges.sh renovar-por 9050, capped at one every 12 hours),
# since the engine is never stopped any more. What it does is logged to vigia.log (no addresses
# or pages: only engine, failure and restart).
import importlib.util
import os
import socket
import struct
import subprocess
import threading
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location("lanzador", Path(__file__).with_name("launch_browser.pyw"))
l = importlib.util.module_from_spec(spec)
spec.loader.exec_module(l)

spec_p = importlib.util.spec_from_file_location("puerta", Path(__file__).with_name("direct_gate.py"))
puerta = importlib.util.module_from_spec(spec_p)
spec_p.loader.exec_module(puerta)


spec_c = importlib.util.spec_from_file_location("carrera", Path(__file__).with_name("race.py"))
carrera = importlib.util.module_from_spec(spec_c)
spec_c.loader.exec_module(carrera)

REGISTRO = Path(__file__).with_name("vigia.log")
PRUEBA = "check.torproject.org"
CADA_SALUD = 120            # s between health checks of each engine
FALLOS_PARA_REINICIAR = 3
GRACIA_TRAS_REINICIO = 480  # s: the engine may take a while to connect (and to rescue bridges)
CADA_RENOVAR = 6 * 3600
PUENTES = "~/.smiley/bridges.sh"


def anotar(texto):
    try:
        if REGISTRO.exists() and REGISTRO.stat().st_size > 128 * 1024:
            os.replace(REGISTRO, str(REGISTRO) + ".1")
        with open(REGISTRO, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + texto + "\n")
    except OSError:
        pass


def tor_sale(puerto, plazo=40):
    """True if the engine on the given port really opens a connection through Tor (SOCKS5 with its own username)."""
    try:
        with socket.create_connection(("127.0.0.1", puerto), timeout=5) as s:
            s.settimeout(plazo)
            s.sendall(b"\x05\x01\x02")
            if s.recv(2) != b"\x05\x02":
                return False
            u = b"vigia-salud"
            s.sendall(b"\x01" + bytes([len(u)]) + u + b"\x06carita")
            if s.recv(2)[1:2] != b"\x00":
                return False
            h = PRUEBA.encode()
            s.sendall(b"\x05\x01\x00\x03" + bytes([len(h)]) + h + struct.pack(">H", 443))
            r = s.recv(10)
            return len(r) >= 2 and r[1] == 0
    except (OSError, IndexError):
        return False


def mantener_puerta():
    if not puerta.activa():
        threading.Thread(target=puerta.servir, daemon=True).start()
    if not carrera.activa():
        threading.Thread(target=carrera.servir, daemon=True).start()


def apagar(script):
    try:
        subprocess.run(["wsl.exe", "-d", l.DISTRO, "--", script, "--apagar"], creationflags=l.SIN_VENTANA,
                       stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        pass


def renovar_puentes():
    try:
        subprocess.Popen(["wsl.exe", "-d", l.DISTRO, "--", PUENTES, "renovar-por", "9050"],
                         creationflags=l.SIN_VENTANA, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
        anotar("requesting bridge renewal (bridges.sh caps it at one every 12 hours)")
    except OSError:
        pass


class Salud:
    """An engine's consecutive failures and from when it can be judged again."""

    def __init__(self, nombre, puerto, script, encender):
        self.nombre, self.puerto, self.script, self.encender = nombre, puerto, script, encender
        self.fallos = 0
        self.juzgar_desde = time.monotonic() + 120   # at session start, give it time to connect
        self.proxima = 0.0

    def revisar(self):
        ahora = time.monotonic()
        if ahora < self.proxima or ahora < self.juzgar_desde:
            return
        self.proxima = ahora + CADA_SALUD
        if tor_sale(self.puerto):
            if self.fallos:
                anotar(f"{self.nombre}: going out through Tor again after {self.fallos} failure(s)")
            self.fallos = 0
            return
        self.fallos += 1
        anotar(f"{self.nombre}: not going out through Tor (failure {self.fallos} of {FALLOS_PARA_REINICIAR})")
        if self.fallos >= FALLOS_PARA_REINICIAR:
            anotar(f"{self.nombre}: restarting the engine")
            apagar(self.script)
            time.sleep(3)
            try:
                self.encender()
            except OSError:
                pass
            self.tras_encender()

    def tras_encender(self):
        self.fallos = 0
        self.juzgar_desde = time.monotonic() + GRACIA_TRAS_REINICIO


try:
    l.escribir_pac()
except OSError:
    pass

anotar("watchdog running")
principal = Salud("main engine (9050)", 9050, l.MOTOR, l.encender_motor)
elegida = Salud("chosen-exit engine (9055)", 9055, l.MOTOR_ELEGIDA, l.encender_elegida)
proxima_renovacion = time.monotonic() + 600   # the first one, 10 minutes after start
espera = 0
espera_elegida = 0
while True:
    mantener_puerta()
    if l.motor_activo():
        espera = 0
        principal.revisar()
    elif espera <= 0:
        try:
            l.encender_motor()
        except OSError:
            pass
        principal.tras_encender()
        espera = 90  # the engine takes a while to open the port: do not launch another while it starts
    # Chosen-exit engine (127.0.0.1:9055), only if chosen_exit.txt has sites.
    if l.elegida_activa():
        espera_elegida = 0
        if l.elegidos():
            elegida.revisar()
    elif not l.elegidos():
        espera_elegida = 0
    elif espera_elegida <= 0:
        try:
            l.encender_elegida()
        except OSError:
            pass
        elegida.tras_encender()
        espera_elegida = 90
    if time.monotonic() >= proxima_renovacion and principal.fallos == 0 and l.motor_activo():
        renovar_puentes()
        proxima_renovacion = time.monotonic() + CADA_RENOVAR
    time.sleep(30)
    espera -= 30
    espera_elegida -= 30
