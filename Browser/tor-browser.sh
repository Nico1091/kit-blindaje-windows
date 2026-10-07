#!/bin/bash
# Motor Tor del Browser (LibreWolf): SOCKS en 127.0.0.1:9050. Sin ventana. Lo mantiene vivo
# Security\Browser\tor_watchdog.pyw (tarea "Browser - Tor always").
# Copia en Windows: Security\Browser\tor-browser.sh; se instala en ~/.smiley/tor-browser.sh.
#
# Entrada parametrizada (04/10/2026) en Security\Browser\speed.json, bloque "tor":
#   "entrada": "puente"  -> WebTunnel (por defecto): el proveedor solo ve HTTPS a una pagina comun.
#              "directo" -> sin puente: el proveedor (Claro) ve que usas Tor, no que visitas. Es legal
#                           (comprobado el 04/10/2026), pero medido ese dia fue MAS LENTO para el: las
#                           entradas de Tor estan sobre todo en Europa y su puente en Norteamerica.
#   "conflux_ux": "throughput" (mas caudal) | "latency" (menos espera)
#   "salida_paises" / "medio_paises": codigos de pais de los relevos de salida / medio (vacio = cualquiera).
# La vigilancia de puentes (renovar, rescatar) solo actua con "puente".
C=$HOME/.smiley
T=$C/tor-browser/Browser/TorBrowser/Tor
D=$C/tor-browser
PUERTO=9050
VEL=__WINHOME__/Security/Browser/speed.json
mkdir -p "$D" && chmod 700 "$D"
if [ "${1:-}" = "--apagar" ]; then
  [ -f "$D/tor.pid" ] && kill "$(cat "$D/tor.pid")" 2> /dev/null
  rm -f "$D/tor.pid"
  exit 0
fi
pgrep -u "$(id -u)" -f "[t]or -f $D/torrc" > /dev/null && exit 0

leer() {  # $1 = clave del bloque "tor", $2 = valor por defecto
  python3 -c "import json; print(json.load(open('$VEL', encoding='utf-8')).get('tor', {}).get('$1', '$2'))" 2> /dev/null || echo "$2"
}
ENTRADA=$(leer entrada puente)
UX=$(leer conflux_ux throughput)
paises() {  # $1 = clave con lista de codigos de pais -> "{us},{ca}" (vacio = cualquier pais)
  python3 -c "import json; print(','.join('{%s}' % p.lower() for p in json.load(open('$VEL', encoding='utf-8')).get('tor', {}).get('$1', [])))" 2> /dev/null
}
SALIDA=$(paises salida_paises)
MEDIO=$(paises medio_paises)

# $1 = cuantos puentes usar (solo con entrada "puente"), en el orden de puentes.txt.
escribir_torrc() {
  {
    echo "DataDirectory $D"
    # KeepAliveIsolateSOCKSAuth (04/10/2026, como Tor Browser): el circuito de un sitio no se retira a
    # los 10 minutos mientras lo sigues usando; sin esto, una sesion larga (Outlook) cambiaba de IP.
    echo "SocksPort 127.0.0.1:$PUERTO KeepAliveIsolateSOCKSAuth"
    echo "AvoidDiskWrites 1"
    # Base de paises de Tor: sin ella, salida_paises / medio_paises no encontrarian ningun relevo.
    echo "GeoIPFile $C/tor-browser/Browser/TorBrowser/Data/Tor/geoip"
    echo "GeoIPv6File $C/tor-browser/Browser/TorBrowser/Data/Tor/geoip6"
    echo "PidFile $D/tor.pid"
    echo "Log notice file $D/tor.log"
    echo "ConfluxEnabled 1"
    echo "ConfluxClientUX $UX"
    # Geografia del recorrido (speed.json, tor.salida_paises / tor.medio_paises; vacio = cualquiera).
    [ -n "$SALIDA" ] && echo "ExitNodes $SALIDA"
    [ -n "$MEDIO" ] && echo "MiddleNodes $MEDIO"
    { [ -n "$SALIDA" ] || [ -n "$MEDIO" ]; } && echo "StrictNodes 1"
    if [ "$ENTRADA" = "directo" ]; then
      echo "UseBridges 0"
    else
      echo "UseBridges 1"
      echo "ClientTransportPlugin webtunnel exec $T/PluggableTransports/lyrebird"
      grep -E '^webtunnel ' "$C/puentes.txt" | head -n "${1:-1}" | sed 's/^/Bridge /'
    fi
  } > "$D/torrc"
}

escribir_torrc 1
: > "$D/tor.log"
LD_LIBRARY_PATH=$T "$T/tor" -f "$D/torrc" > /dev/null 2>&1 &
TOR=$!

# Vigilante. Directo: solo calienta el primer circuito. Puente: si conecta, renueva los puentes por
# dentro de Tor (como mucho cada 12 h); si a los 45 s no conecto, pasa a todos los puentes; si a los
# 5 minutos sigue sin conectar, pide puentes nuevos.
(
  for i in $(seq 1 100); do
    sleep 3
    kill -0 "$TOR" 2> /dev/null || exit 0
    if grep -q 'Bootstrapped 100%' "$D/tor.log"; then
      curl -s -o /dev/null -m 60 --socks5-hostname "127.0.0.1:$PUERTO" https://check.torproject.org/api/ip
      [ "$ENTRADA" = "directo" ] || "$C/bridges.sh" renovar-por "$PUERTO"
      exit 0
    fi
    if [ "$i" -eq 15 ] && [ "$ENTRADA" != "directo" ]; then
      escribir_torrc 6
      kill -HUP "$TOR" 2> /dev/null
    fi
  done
  if [ "$ENTRADA" != "directo" ] && "$C/bridges.sh" rescatar; then
    escribir_torrc 1
    kill -HUP "$TOR" 2> /dev/null
  fi
) &

wait "$TOR"
