# Everything Windows sends to Edge (PDFs, links from Word or Outlook) arrives here
# through the msedge.exe redirection, and opens in the Browser with its file.
# Always through the launcher: it starts the Tor engine that hides the Browser's IP.
import subprocess
import sys
from pathlib import Path

BUSCADOR = Path(__file__).with_name("launch_browser.pyw")

# argv[1] is the msedge.exe path; the rest are Edge options and whatever was to be opened.
# With --single-argument, Windows splits a single path on spaces: it is joined back.
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


# What was opened comes to the front, maximized and on top of whatever is showing.
# Windows does not let a background process steal focus: an Alt key press is simulated.
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


for _ in range(120):  # up to 30 s: the Browser's first start is slow
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
