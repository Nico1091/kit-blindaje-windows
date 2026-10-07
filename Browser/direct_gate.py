"""
Browser direct gate: 127.0.0.1:9060.

It is the browser's only direct way out to the Internet, and only for the sites in direct.txt,
which the user picks site by site (only those that reject the whole Tor network). The firewall still
forbids librewolf.exe from reaching the Internet: it can only talk to this gate or to Tor (9050).

Protections:
  - Listens only on this PC (127.0.0.1): nobody on the home network can use it.
  - Requires a username: the page's main site, set by the routing filter in the Browser
    settings. If that site is not in direct.txt, the connection is refused.
  - HTTPS only (port 443): nothing travels unencrypted.
  - Never towards the home network, this PC or reserved addresses: a page cannot use the gate
    to attack the router or the printer (DNS rebinding).
  - Does not record what you visit: it only counts connections per site (puerta.json) and logs
    refusals (puerta.log, size-capped).

Usage: started by tor_watchdog.pyw (task "Browser - Tor always") in a thread; it can also run alone:
    pythonw direct_gate.py
"""
import asyncio
import ipaddress
import json
import os
import socket
import struct
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
LISTA = os.path.join(AQUI, "direct.txt")
REGISTRO = os.path.join(AQUI, "puerta.log")
ESTADO = os.path.join(AQUI, "puerta.json")
DIRECCION = ("127.0.0.1", 9060)
PUERTOS = {443}
ESPERA = 20
# Connection timeout per address. On some home networks IPv6 dies minutes after connecting, and an
# IPv6 connection then hangs until the timeout: measured, 8 connections to one site failed after 20 s
# each. With IPv6 it gives up after 4 s so the browser moves on to the next address right away; with
# IPv4 it waits longer.
PLAZO_V4 = 12
PLAZO_V6 = 4

_lista = {"mtime": None, "sitios": {}}
_cuenta = {}
_desde = time.strftime("%Y-%m-%d %H:%M:%S")


def leer_lista():
    """{site: [own domains]} from direct.txt; re-read when the file changes."""
    try:
        m = os.path.getmtime(LISTA)
    except OSError:
        return {}
    if m != _lista["mtime"]:
        sitios = {}
        with open(LISTA, encoding="utf-8") as f:
            for linea in f:
                partes = linea.split("#", 1)[0].lower().split()
                if partes:
                    sitios[partes[0]] = partes[1:]
        _lista.update(mtime=m, sitios=sitios)
    return _lista["sitios"]


def sitio_permitido(sitio):
    sitio = (sitio or "").lower().strip(".")
    return any(sitio == d or sitio.endswith("." + d) for d in leer_lista())


def ip_publica(ip):
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    if getattr(a, "ipv4_mapped", None):
        a = a.ipv4_mapped
    return a.is_global and not a.is_multicast


def anotar(texto):
    try:
        if os.path.exists(REGISTRO) and os.path.getsize(REGISTRO) > 256 * 1024:
            os.replace(REGISTRO, REGISTRO + ".1")
        with open(REGISTRO, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + texto + "\n")
    except OSError:
        pass


def guardar_estado():
    try:
        with open(ESTADO, "w", encoding="utf-8") as f:
            json.dump({"desde": _desde, "actualizado": time.strftime("%Y-%m-%d %H:%M:%S"),
                       "conexiones_directas_por_sitio": _cuenta}, f, ensure_ascii=False, indent=1)
    except OSError:
        pass


async def _pasar(origen, destino):
    try:
        while True:
            datos = await origen.read(65536)
            if not datos:
                break
            destino.write(datos)
            await destino.drain()
    except (ConnectionError, OSError, asyncio.CancelledError):
        pass
    finally:
        try:
            destino.close()
        except Exception:
            pass


def _familia(ip):
    return "v6" if ":" in ip else "v4"


async def _conectar(ips, puerto):
    """Tries the addresses in order, IPv4 first, each with its own timeout. Returns (reader, writer,
    ip). If all fail, raises the last error."""
    ultimo = None
    for ip in sorted(ips, key=lambda x: _familia(x) == "v6"):
        plazo = PLAZO_V6 if _familia(ip) == "v6" else PLAZO_V4
        try:
            l, e = await asyncio.wait_for(asyncio.open_connection(ip, puerto), plazo)
            return l, e, ip
        except (asyncio.TimeoutError, OSError) as err:
            ultimo = err
    raise ultimo or OSError("no addresses")


async def _atender(lector, escritor):
    sitio = "?"
    tipo_destino = "?"
    t0 = time.monotonic()
    try:
        ver, n = await asyncio.wait_for(lector.readexactly(2), ESPERA)
        metodos = await lector.readexactly(n)
        if ver != 5 or 2 not in metodos:
            escritor.write(b"\x05\xff")
            return
        escritor.write(b"\x05\x02")
        await escritor.drain()
        _, ulen = await lector.readexactly(2)
        sitio = (await lector.readexactly(ulen)).decode("utf-8", "replace")
        plen = (await lector.readexactly(1))[0]
        await lector.readexactly(plen)
        if not sitio_permitido(sitio):
            escritor.write(b"\x01\x01")
            anotar(f"REFUSED unauthorized site: {sitio}")
            return
        escritor.write(b"\x01\x00")
        await escritor.drain()
        ver, cmd, _, tipo = await lector.readexactly(4)
        if tipo == 1:
            destino = socket.inet_ntop(socket.AF_INET, await lector.readexactly(4))
        elif tipo == 4:
            destino = socket.inet_ntop(socket.AF_INET6, await lector.readexactly(16))
        elif tipo == 3:
            largo = (await lector.readexactly(1))[0]
            destino = (await lector.readexactly(largo)).decode("idna")
        else:
            escritor.write(b"\x05\x08\x00\x01" + b"\x00" * 6)
            return
        puerto = struct.unpack(">H", await lector.readexactly(2))[0]
        if cmd != 1:
            escritor.write(b"\x05\x07\x00\x01" + b"\x00" * 6)
            anotar(f"REFUSED command {cmd} not allowed ({sitio})")
            return
        if puerto not in PUERTOS:
            escritor.write(b"\x05\x02\x00\x01" + b"\x00" * 6)
            anotar(f"REFUSED unencrypted port {puerto} ({sitio})")
            return
        # The browser resolves the name on this PC (Unbound, with DNSSEC; that way it also uses ECH) and
        # sends the address (type 1 or 4). If it sends a name (type 3), the gate resolves it.
        if tipo == 3:
            tipo_destino = "nombre"
            infos = await asyncio.get_running_loop().getaddrinfo(destino, puerto, type=socket.SOCK_STREAM)
            ips = list(dict.fromkeys(i[4][0] for i in infos))
        else:
            tipo_destino = "IPv4" if tipo == 1 else "IPv6"
            ips = [destino]
        buenas = [ip for ip in ips if ip_publica(ip)]
        if not buenas:
            escritor.write(b"\x05\x02\x00\x01" + b"\x00" * 6)
            anotar(f"REFUSED non-public destination ({sitio}): {ips}")
            return
        remoto_l, remoto_e, _ = await _conectar(buenas, puerto)
        escritor.write(b"\x05\x00\x00\x01" + b"\x00" * 6)
        await escritor.drain()
        clave = sitio.lower()
        _cuenta[clave] = _cuenta.get(clave, 0) + 1
        await asyncio.gather(_pasar(lector, remoto_e), _pasar(remoto_l, escritor))
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError, OSError) as e:
        if sitio != "?":
            try:
                escritor.write(b"\x05\x04\x00\x01" + b"\x00" * 6)
            except Exception:
                pass
            anotar(f"CONNECTION FAILED ({sitio}, destination {tipo_destino}, {time.monotonic() - t0:.1f} s): "
                   f"{type(e).__name__}")
    finally:
        try:
            escritor.close()
        except Exception:
            pass


async def _estado_periodico():
    while True:
        await asyncio.sleep(60)
        guardar_estado()


async def _principal():
    servidor = await asyncio.start_server(_atender, *DIRECCION)
    guardar_estado()
    asyncio.get_running_loop().create_task(_estado_periodico())
    async with servidor:
        await servidor.serve_forever()


def servir():
    """Blocks while serving. If the port is already taken (another gate running), returns without doing anything."""
    try:
        asyncio.run(_principal())
    except OSError:
        pass


def activa():
    try:
        with socket.create_connection(DIRECCION, timeout=1):
            return True
    except OSError:
        return False


if __name__ == "__main__":
    servir()
