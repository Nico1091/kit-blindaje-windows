"""
Puerta directa del Buscador: 127.0.0.1:9060 (04/10/2026).

Es la unica salida directa a internet que tiene el navegador, y solo para los sitios de
directos.txt, que decide el usuario, sitio por sitio (solo los que rechazan a toda la red Tor). El cortafuegos sigue
prohibiendo a librewolf.exe salir a internet: solo puede hablar con esta puerta o con Tor (9050).

Protecciones:
  - Solo escucha en este equipo (127.0.0.1): nadie de la red de la casa puede usarla.
  - Exige usuario: el sitio principal de la pagina, que pone el filtro de rutas de los ajustes del
    Buscador. Si ese sitio no esta en directos.txt, rechaza la conexion.
  - Solo HTTPS (puerto 443): nada viaja sin cifrar.
  - Nunca hacia la red de casa, el propio equipo ni direcciones reservadas: una pagina no puede usar
    la puerta para atacar el router o la impresora (DNS rebinding).
  - No guarda lo que visitas: solo cuenta conexiones por sitio (puerta.json) y anota los rechazos
    (puerta.log, con tope de tamano).

Uso: la arranca vigia_tor.pyw (tarea "Buscador - Tor siempre") en un hilo; tambien puede correr sola:
    pythonw puerta_directa.py
"""
import asyncio
import ipaddress
import json
import os
import socket
import struct
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
LISTA = os.path.join(AQUI, "directos.txt")
REGISTRO = os.path.join(AQUI, "puerta.log")
ESTADO = os.path.join(AQUI, "puerta.json")
DIRECCION = ("127.0.0.1", 9060)
PUERTOS = {443}
ESPERA = 20
# Plazo de conexion por direccion (04/10/2026). En esta casa el IPv6 se cae a los minutos de conectar
# (el equipo deja de contestar al router), y una conexion IPv6 se queda colgada hasta agotar el plazo:
# medido, 8 conexiones de un sitio fallaron tras 20 s cada una. Con IPv6 se corta a los 4 s para que el
# navegador pase enseguida a la siguiente direccion; con IPv4 se espera mas.
PLAZO_V4 = 12
PLAZO_V6 = 4

_lista = {"mtime": None, "sitios": {}}
_cuenta = {}
_desde = time.strftime("%Y-%m-%d %H:%M:%S")


def leer_lista():
    """{sitio: [dominios propios]} de directos.txt; se relee si el archivo cambia."""
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
    """Prueba las direcciones en orden, IPv4 primero, cada una con su plazo. Devuelve (lector, escritor,
    ip). Si fallan todas, lanza el ultimo error."""
    ultimo = None
    for ip in sorted(ips, key=lambda x: _familia(x) == "v6"):
        plazo = PLAZO_V6 if _familia(ip) == "v6" else PLAZO_V4
        try:
            l, e = await asyncio.wait_for(asyncio.open_connection(ip, puerto), plazo)
            return l, e, ip
        except (asyncio.TimeoutError, OSError) as err:
            ultimo = err
    raise ultimo or OSError("sin direcciones")


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
            anotar(f"RECHAZO sitio no autorizado: {sitio}")
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
            anotar(f"RECHAZO orden {cmd} no permitida ({sitio})")
            return
        if puerto not in PUERTOS:
            escritor.write(b"\x05\x02\x00\x01" + b"\x00" * 6)
            anotar(f"RECHAZO puerto {puerto} sin cifrar ({sitio})")
            return
        # El navegador resuelve el nombre en este equipo (Unbound, con DNSSEC; asi tambien usa ECH) y
        # manda la direccion (tipo 1 o 4). Si manda un nombre (tipo 3), lo resuelve la puerta.
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
            anotar(f"RECHAZO destino no publico ({sitio}): {ips}")
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
            anotar(f"FALLO de conexion ({sitio}, destino {tipo_destino}, {time.monotonic() - t0:.1f} s): "
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
    """Bloquea sirviendo. Si el puerto ya esta ocupado (otra puerta en marcha), vuelve sin hacer nada."""
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
