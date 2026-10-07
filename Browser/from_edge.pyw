# Todo lo que Windows manda a Edge (PDF, enlaces de Word u Outlook) llega aqui
# por la redireccion de msedge.exe, y se abre en el Browser con su archivo.
# Siempre por el lanzador: enciende el motor Tor que oculta la IP del Browser.
import subprocess
import sys
from pathlib import Path

BUSCADOR = Path(__file__).with_name("launch_browser.pyw")

# argv[1] es la ruta de msedge.exe; lo demas son opciones de Edge y lo que se queria abrir.
# Con --single-argument, Windows parte por los espacios una sola ruta: se vuelve a juntar.
args = sys.argv[2:]
if "--single-argument" in args:
    args = [" ".join(args[args.index("--single-argument") + 1:])]
cosas = []
for a in args:
    if a.startswith("-"):
        continue
    if a.lower().startswith("microsoft-edge:"):
        a = a.split(":", 1)[1]
        if a.lower().startswith("?url="):
            from urllib.parse import unquote
            a = unquote(a[5:].split("&", 1)[0])
    if a:
        cosas.append(a)

subprocess.Popen([sys.executable, str(BUSCADOR), *cosas])


# Lo abierto sale al frente, maximizado y encima de lo que se este viendo.
# Windows no deja que un proceso de fondo robe el foco: se simula la tecla Alt.
import ctypes
import os
import time
from ctypes import wintypes

u = ctypes.windll.user32
nombres = [os.path.splitext(os.path.basename(c))[0].lower() for c in cosas if os.path.exists(c)]


def buscar():
    hallada = []

    def cada(h, _):
        if not u.IsWindowVisible(h):
            return True
        n = u.GetWindowTextLengthW(h)
        b = ctypes.create_unicode_buffer(n + 1)
        u.GetWindowTextW(h, b, n + 1)
        t = b.value.lower()
        if ("browser" in t or "librewolf" in t) and (not nombres or any(x in t for x in nombres)):
            hallada.append(h)
            return False
        return True

    u.EnumWindows(ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)(cada), 0)
    return hallada[0] if hallada else None


for _ in range(120):  # hasta 30 s: el primer arranque del Browser tarda
    time.sleep(0.25)
    h = buscar()
    if h:
        u.keybd_event(0x12, 0, 0, 0)
        u.keybd_event(0x12, 0, 2, 0)
        u.ShowWindow(h, 3)
        u.SetWindowPos(h, -1, 0, 0, 0, 0, 3)
        u.SetWindowPos(h, -2, 0, 0, 0, 0, 3)
        u.SetForegroundWindow(h)
        break
