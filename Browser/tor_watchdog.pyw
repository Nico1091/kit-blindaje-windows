# Mantiene encendido el motor Tor del Browser desde que se inicia sesion.
# Lo arranca la tarea programada "Browser - Tor always". Cada 30 s comprueba el
# puerto 9050 y, si no responde, vuelve a encender el motor en Ubuntu.
# Desde el 04/10/2026 tambien mantiene la puerta directa protegida (direct_gate.py,
# 127.0.0.1:9060), unica salida directa del navegador y solo para los sitios de direct.txt, y el
# motor de salida elegida (tor-chosen.sh, 127.0.0.1:9055) para los de chosen_exit.txt, y la
# carrera de circuitos (race.py, 127.0.0.1:9070), parametros en speed.json.
#
# Salud real (04/10/2026, noche): un puerto abierto no basta. Si el puente WebTunnel muere, Tor deja
# el puerto abierto sin poder salir y el Browser se quedaba colgado sin arreglarse solo. Cada 2
# minutos abre una conexion de prueba por cada motor hasta check.torproject.org:443, por un circuito
# propio ("vigia-salud"); tras 3 fallos seguidos reinicia ese motor (al arrancar, el motor pasa a todos
# los puentes si el primero no conecta y pide puentes nuevos si ninguno conecta). Ademas, cada 6 horas
# pide la renovacion de puentes (bridges.sh renovar-por 9050, que se limita a una cada 12 horas): antes
# solo se renovaban al arrancar el motor, y el motor ya no se apaga nunca. Lo que hace queda en
# vigia.log (sin direcciones ni paginas: solo motor, fallo y reinicio).
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
CADA_SALUD = 120            # s entre comprobaciones de salud de cada motor
FALLOS_PARA_REINICIAR = 3
GRACIA_TRAS_REINICIO = 480  # s: el motor puede tardar en conectar (y en rescatar puentes)
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
    """True si el motor del puerto dado abre de verdad una conexion por Tor (SOCKS5 con usuario propio)."""
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
        anotar("pido renovacion de puentes (bridges.sh la limita a una cada 12 horas)")
    except OSError:
        pass


class Salud:
    """Fallos seguidos de un motor y desde cuando se le puede volver a juzgar."""

    def __init__(self, nombre, puerto, script, encender):
        self.nombre, self.puerto, self.script, self.encender = nombre, puerto, script, encender
        self.fallos = 0
        self.juzgar_desde = time.monotonic() + 120   # al arrancar la sesion, dejarle conectar
        self.proxima = 0.0

    def revisar(self):
        ahora = time.monotonic()
        if ahora < self.proxima or ahora < self.juzgar_desde:
            return
        self.proxima = ahora + CADA_SALUD
        if tor_sale(self.puerto):
            if self.fallos:
                anotar(f"{self.nombre}: vuelve a salir por Tor tras {self.fallos} fallo(s)")
            self.fallos = 0
            return
        self.fallos += 1
        anotar(f"{self.nombre}: no sale por Tor (fallo {self.fallos} de {FALLOS_PARA_REINICIAR})")
        if self.fallos >= FALLOS_PARA_REINICIAR:
            anotar(f"{self.nombre}: reinicio el motor")
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

anotar("vigia en marcha")
principal = Salud("motor principal (9050)", 9050, l.MOTOR, l.encender_motor)
elegida = Salud("motor de salida elegida (9055)", 9055, l.MOTOR_ELEGIDA, l.encender_elegida)
proxima_renovacion = time.monotonic() + 600   # la primera, 10 minutos despues de arrancar
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
        espera = 90  # el motor tarda en abrir el puerto: no lanzar otro mientras arranca
    # Motor de salida elegida (127.0.0.1:9055), solo si chosen_exit.txt tiene sitios.
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
