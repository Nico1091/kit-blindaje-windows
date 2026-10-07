"""
Carrera de circuitos del Buscador: 127.0.0.1:9070 (04/10/2026).

Medido el 04/10: con Tor, mas o menos 1 de cada 10 paginas nuevas cae en un circuito lento o muerto, y
Tor no lo abandona hasta pasados 10 s (no deja bajar ese tiempo). Esta pieza se pone entre el navegador
y Tor (9050) y hace competir varios circuitos en la PRIMERA conexion de cada sitio:

  modo "saludo" (por defecto): acepta la conexion del navegador, toma su primer mensaje (el saludo TLS)
      y lo envia por N circuitos; gana el primero cuyo servidor RESPONDE. Asi se elige el circuito que
      de verdad contesta antes, no solo el que conecta antes. Los demas se cierran.
  modo "conexion": gana el primer circuito que conecta (Tor dice "conectado").

Despues, todo el sitio sigue por el circuito ganador durante "vigencia_s" (como Tor, 9 minutos), para no
mezclar IP (Twitch falla si las mezcla). Si ese circuito cae del todo, el sitio pasa a otro.

Parametros en velocidad.json, bloque "carrera" (se relee solo al cambiar): activa, modo, circuitos
(1-3), espera_s (0 = todos a la vez; si no, cada circuito extra entra tras esa espera), vigencia_s,
max_simultaneas (carreras a la vez; por encima, un solo circuito: evita atascar la cola de Tor).

  - No sale nunca directo: solo habla con Tor. Si esta pieza no responde, el navegador pasa solo a Tor
    sin carrera (proxy de respaldo en el filtro de rutas).
  - Solo escucha en este equipo. No guarda lo que visitas: solo cuenta carreras y ganadores (carrera.json).

La arranca vigia_tor.pyw en un hilo; tambien puede correr sola:  pythonw carrera.py
Variables para pruebas: CARRERA_PUERTO (9070), CARRERA_TOR_PUERTO (9050), CARRERA_CONFIG (velocidad.json).
"""
import asyncio
import json
import os
import socket
import struct
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
ESTADO = os.path.join(AQUI, os.environ.get("CARRERA_ESTADO", "carrera.json"))
CONFIG = os.environ.get("CARRERA_CONFIG", os.path.join(AQUI, "velocidad.json"))
ESCUCHA = ("127.0.0.1", int(os.environ.get("CARRERA_PUERTO", "9070")))
TOR = ("127.0.0.1", int(os.environ.get("CARRERA_TOR_PUERTO", "9050")))
DEFECTO = {"activa": True, "modo": "saludo", "circuitos": 2, "espera_s": 0.0, "vigencia_s": 540, "max_simultaneas": 3}
TOPE = 45
SUFIJOS = "abc"

_conf = {"mtime": None, "datos": dict(DEFECTO)}
_ganador = {}
_cuenta = {"conexiones": 0, "carreras": 0, "gano_el_segundo_o_tercero": 0, "fallidas": 0}
_desde = time.strftime("%Y-%m-%d %H:%M:%S")


def conf():
    """Bloque "carrera" de velocidad.json, releido solo si el archivo cambio."""
    try:
        m = os.path.getmtime(CONFIG)
    except OSError:
        return _conf["datos"]
    if m != _conf["mtime"]:
        try:
            with open(CONFIG, encoding="utf-8") as f:
                d = json.load(f).get("carrera") or {}
        except (OSError, ValueError):
            d = {}
        datos = {**DEFECTO, **d}
        datos["circuitos"] = max(1, min(3, int(datos["circuitos"])))
        _conf.update(mtime=m, datos=datos)
    return _conf["datos"]


async def _por_tor(usuario, tipo, destino, puerto):
    """Conexion SOCKS5 con Tor aislada por usuario (un circuito por usuario). Devuelve (lector, escritor)."""
    l, e = await asyncio.open_connection(*TOR)
    try:
        e.write(b"\x05\x01\x02")
        await e.drain()
        if await l.readexactly(2) != b"\x05\x02":
            raise OSError("Tor no acepto la autenticacion")
        u = usuario.encode("utf-8")[:255]
        e.write(b"\x01" + bytes([len(u)]) + u + b"\x06carita")
        await e.drain()
        if (await l.readexactly(2))[1] != 0:
            raise OSError("Tor rechazo el usuario")
        e.write(b"\x05\x01\x00" + bytes([tipo]) + destino + struct.pack(">H", puerto))
        await e.drain()
        cab = await l.readexactly(4)
        if cab[1] != 0:
            raise ConnectionRefusedError(cab[1])
        if cab[3] == 1:
            await l.readexactly(6)
        elif cab[3] == 4:
            await l.readexactly(18)
        else:
            await l.readexactly((await l.readexactly(1))[0] + 2)
        return l, e
    except BaseException:
        e.close()
        raise


async def _por_tor_con_saludo(usuario, tipo, destino, puerto, saludo):
    """Conecta por un circuito, envia el saludo del navegador y espera la primera respuesta del servidor."""
    l, e = await _por_tor(usuario, tipo, destino, puerto)
    try:
        e.write(saludo)
        await e.drain()
        primeros = await l.read(65536)
        if not primeros:
            raise ConnectionResetError("el servidor cerro sin responder")
        return l, e, primeros
    except BaseException:
        e.close()
        raise


def _cerrar_si_conecto(tarea):
    if not tarea.cancelled() and tarea.exception() is None:
        tarea.result()[1].close()


async def _competir(fabricar, n, espera):
    """Lanza hasta n intentos (fabricar(i) -> corrutina), escalonados por 'espera' segundos (0 = a la vez).
    Devuelve (indice_ganador, resultado) del primero que acaba bien; si fallan todos, lanza el ultimo error."""
    tareas = {}
    siguiente = 0
    ultimo_error = None
    fin = time.time() + TOPE
    while True:
        if siguiente < n and (not tareas or espera <= 0):
            while siguiente < n and (not tareas or espera <= 0):
                tareas[asyncio.ensure_future(fabricar(siguiente))] = siguiente
                siguiente += 1
                if espera > 0:
                    break
        if not tareas:
            break
        limite = espera if (siguiente < n and espera > 0) else max(0.1, fin - time.time())
        hechas, _ = await asyncio.wait(list(tareas), timeout=limite, return_when=asyncio.FIRST_COMPLETED)
        if not hechas:
            if siguiente < n and time.time() < fin:
                tareas[asyncio.ensure_future(fabricar(siguiente))] = siguiente
                siguiente += 1
                continue
            break
        for t in hechas:
            i = tareas.pop(t)
            if t.exception() is None:
                for resto in tareas:
                    resto.add_done_callback(_cerrar_si_conecto)
                    resto.cancel()
                return i, t.result()
            ultimo_error = t.exception()
        if not tareas and siguiente < n:
            continue
    for resto in tareas:
        resto.add_done_callback(_cerrar_si_conecto)
        resto.cancel()
    raise ultimo_error or TimeoutError("ningun circuito respondio")


def _orden(clave, c):
    """Sufijos de circuito a probar, empezando por el ganador vigente del sitio."""
    sufijos = list(SUFIJOS[:c["circuitos"]])
    g = _ganador.get(clave)
    if g and time.time() - g[1] < c["vigencia_s"] and g[0] in SUFIJOS:
        if g[0] in sufijos:
            sufijos.remove(g[0])
        sufijos.insert(0, g[0])
        return sufijos, True
    return sufijos, False


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


def _respuesta(codigo):
    return b"\x05" + bytes([codigo]) + b"\x00\x01" + b"\x00" * 6


_en_carrera = {}
# Tope de carreras a la vez (04/10/2026): cada carrera pide 2 circuitos a Tor (4 patas con Conflux). Una
# rafaga de carreras llena la cola de circuitos de Tor y todo espera (medido: tras 150 carreras seguidas,
# 9-40 s durante unos 20 s). Por encima del tope, la conexion va por un solo circuito, sin competir.
_en_curso = {"n": 0}


def _usuario(clave, sufijo):
    return f"{clave}|{sufijo}" if sufijo else clave


def _codigo(e):
    return e.args[0] if isinstance(e, ConnectionRefusedError) and e.args and isinstance(e.args[0], int) else 1


async def _abrir_vigente(clave, sufijos, tipo, destino, puerto):
    """Sitio ya abierto: su circuito ganador; si cae del todo, el siguiente (y el sitio entero pasa a el)."""
    ultimo = None
    for k, sufijo in enumerate(sufijos):
        try:
            rl, re_ = await asyncio.wait_for(_por_tor(_usuario(clave, sufijo), tipo, destino, puerto), TOPE)
            if k > 0 and sufijo:
                _ganador[clave] = (sufijo, time.time())
            return rl, re_
        except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError) as e:
            ultimo = e
    raise ultimo or TimeoutError("sin circuito")


async def _leer_saludo(lector):
    """Primer mensaje del navegador completo: si es TLS, el registro entero (el saludo con clave
    poscuantica ocupa ~2 KB y puede llegar en dos trozos)."""
    saludo = await asyncio.wait_for(lector.read(65536), 20)
    if saludo and saludo[0] == 0x16 and len(saludo) >= 5:
        largo = 5 + int.from_bytes(saludo[3:5], "big")
        while len(saludo) < largo:
            mas = await asyncio.wait_for(lector.read(largo - len(saludo)), 20)
            if not mas:
                break
            saludo += mas
    return saludo


async def _atender(lector, escritor):
    try:
        ver, n = await asyncio.wait_for(lector.readexactly(2), 20)
        metodos = await lector.readexactly(n)
        if ver != 5 or 2 not in metodos:
            escritor.write(b"\x05\xff")
            return
        escritor.write(b"\x05\x02")
        await escritor.drain()
        _, ulen = await lector.readexactly(2)
        clave = (await lector.readexactly(ulen)).decode("utf-8", "replace")
        await lector.readexactly((await lector.readexactly(1))[0])
        escritor.write(b"\x01\x00")
        await escritor.drain()
        ver, cmd, _, tipo = await lector.readexactly(4)
        if tipo == 1:
            destino = await lector.readexactly(4)
        elif tipo == 4:
            destino = await lector.readexactly(16)
        elif tipo == 3:
            n = await lector.readexactly(1)
            destino = n + await lector.readexactly(n[0])
        else:
            escritor.write(_respuesta(8))
            return
        puerto = struct.unpack(">H", await lector.readexactly(2))[0]
        if cmd != 1:
            escritor.write(_respuesta(7))
            return
        _cuenta["conexiones"] += 1
        c = conf()

        # Si otra conexion del mismo sitio esta compitiendo, se espera a su ganador: una sola carrera por
        # sitio, para que todo el sitio salga por la misma IP.
        ev = _en_carrera.get(clave)
        if c["activa"] and ev is not None:
            try:
                await asyncio.wait_for(ev.wait(), TOPE)
            except asyncio.TimeoutError:
                pass
        sufijos, vigente = _orden(clave, c)
        if not c["activa"]:
            sufijos, vigente = [""], True

        if not vigente and len(sufijos) > 1 and _en_curso["n"] >= int(c.get("max_simultaneas", 3)):
            sufijos = sufijos[:1]          # demasiadas carreras a la vez: un solo circuito
        if vigente or len(sufijos) == 1:
            try:
                rl, re_ = await _abrir_vigente(clave, sufijos, tipo, destino, puerto)
            except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError) as e:
                _cuenta["fallidas"] += 1
                escritor.write(_respuesta(_codigo(e)))
                return
            if not vigente and sufijos[0]:
                _ganador[clave] = (sufijos[0], time.time())
            escritor.write(_respuesta(0))
            await escritor.drain()
            await asyncio.gather(_pasar(lector, re_), _pasar(rl, escritor))
            return

        # Primera conexion del sitio: carrera (una sola por sitio).
        ev = asyncio.Event()
        _en_carrera[clave] = ev
        _cuenta["carreras"] += 1
        _en_curso["n"] += 1
        primeros = b""
        try:
            if c["modo"] == "saludo":
                escritor.write(_respuesta(0))
                await escritor.drain()
                try:
                    saludo = await _leer_saludo(lector)
                except asyncio.TimeoutError:
                    return
                if not saludo:
                    return
                try:
                    i, (rl, re_, primeros) = await _competir(
                        lambda k: _por_tor_con_saludo(_usuario(clave, sufijos[k]), tipo, destino, puerto, saludo),
                        len(sufijos), float(c["espera_s"]))
                except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError):
                    _cuenta["fallidas"] += 1
                    return
            else:
                try:
                    i, (rl, re_) = await _competir(
                        lambda k: _por_tor(_usuario(clave, sufijos[k]), tipo, destino, puerto),
                        len(sufijos), float(c["espera_s"]))
                except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError) as e:
                    _cuenta["fallidas"] += 1
                    escritor.write(_respuesta(_codigo(e)))
                    return
                escritor.write(_respuesta(0))
            _ganador[clave] = (sufijos[i], time.time())
            if i > 0:
                _cuenta["gano_el_segundo_o_tercero"] += 1
        finally:
            _en_curso["n"] -= 1
            ev.set()
            _en_carrera.pop(clave, None)
        if primeros:
            escritor.write(primeros)
        await escritor.drain()
        await asyncio.gather(_pasar(lector, re_), _pasar(rl, escritor))
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError, OSError):
        pass
    finally:
        try:
            escritor.close()
        except Exception:
            pass


def guardar_estado():
    try:
        with open(ESTADO, "w", encoding="utf-8") as f:
            json.dump({"desde": _desde, "actualizado": time.strftime("%Y-%m-%d %H:%M:%S"),
                       "parametros": conf(), **_cuenta}, f, indent=1)
    except OSError:
        pass


async def _estado_periodico():
    while True:
        await asyncio.sleep(60)
        ahora = time.time()
        vigencia = conf()["vigencia_s"]
        for k in [k for k, (_, t) in _ganador.items() if ahora - t > vigencia]:
            del _ganador[k]
        guardar_estado()


async def _principal():
    servidor = await asyncio.start_server(_atender, *ESCUCHA)
    guardar_estado()
    asyncio.get_running_loop().create_task(_estado_periodico())
    async with servidor:
        await servidor.serve_forever()


def servir():
    """Bloquea sirviendo. Si el puerto ya esta ocupado (otra carrera en marcha), vuelve sin hacer nada."""
    try:
        asyncio.run(_principal())
    except OSError:
        pass


def activa():
    try:
        with socket.create_connection(ESCUCHA, timeout=1):
            return True
    except OSError:
        return False


if __name__ == "__main__":
    servir()
