# Receives smiley-tor:<search> from the smiley page and opens it on the Tor network.
# Tor runs inside Ubuntu (WSL): on Windows, Smart App Control blocks Tor Browser.
# With no search it opens the smiley page; with one, Mojeek through Tor.
# open.sh sets the live WebTunnel bridges, restores the disguise and, if already open,
# sends the search to a new tab in the same window.
import subprocess
import sys
from urllib.parse import quote, unquote

def _distro():
    """First Ubuntu distribution installed in WSL."""
    try:
        out = subprocess.run(["wsl.exe", "-l", "-q"], capture_output=True,
                             creationflags=0x08000000).stdout.decode("utf-16-le", "ignore")
        return next((d.strip() for d in out.splitlines() if d.strip().lower().startswith("ubuntu")), "Ubuntu")
    except Exception:
        return "Ubuntu"


DISTRO = _distro()
TOR = "~/.smiley/open.sh"
MOJEEK = "https://www.mojeek.com/search?q="

pedido = sys.argv[1] if len(sys.argv) > 1 else ""
q = unquote(pedido.split(":", 1)[1]).strip(" /") if ":" in pedido else ""
orden = f"exec {TOR} '{MOJEEK + quote(q)}'" if q else f"exec {TOR}"
subprocess.Popen(
    ["wsl.exe", "-d", DISTRO, "--", "bash", "-c", orden],
    creationflags=subprocess.CREATE_NO_WINDOW,
)
