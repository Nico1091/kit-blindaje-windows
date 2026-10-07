# Recibe carita-tor:<busqueda> desde la pagina de la carita y la abre en la red Tor.
# Tor corre dentro de Ubuntu (WSL): en Windows, Smart App Control bloquea Tor Browser.
# Sin busqueda abre la carita; con busqueda, Mojeek a traves de Tor.
# abrir.sh pone los puentes WebTunnel vivos, repone el disfraz y, si ya esta abierto,
# manda la busqueda a una pestana nueva de la misma ventana.
import subprocess
import sys
from urllib.parse import quote, unquote

def _distro():
    """Primera distribucion Ubuntu instalada en WSL."""
    try:
        out = subprocess.run(["wsl.exe", "-l", "-q"], capture_output=True,
                             creationflags=0x08000000).stdout.decode("utf-16-le", "ignore")
        return next((d.strip() for d in out.splitlines() if d.strip().lower().startswith("ubuntu")), "Ubuntu")
    except Exception:
        return "Ubuntu"


DISTRO = _distro()
TOR = "~/.carita/abrir.sh"
MOJEEK = "https://www.mojeek.com/search?q="

pedido = sys.argv[1] if len(sys.argv) > 1 else ""
q = unquote(pedido.split(":", 1)[1]).strip(" /") if ":" in pedido else ""
orden = f"exec {TOR} '{MOJEEK + quote(q)}'" if q else f"exec {TOR}"
subprocess.Popen(
    ["wsl.exe", "-d", DISTRO, "--", "bash", "-c", orden],
    creationflags=subprocess.CREATE_NO_WINDOW,
)
