#!/bin/bash
# Motor Tor de SALIDA ELEGIDA del Browser (04/10/2026): SOCKS en 127.0.0.1:9055.
# Para los sitios que bloquean por pais y no por ser Tor (por ejemplo, portales con filtro geografico): sale
# solo por relevos de los paises de la linea "paises:" de Security\Browser\chosen_exit.txt.
# Misma entrada que el motor principal (directa o por puente WebTunnel, segun speed.json): el
# sitio ve una IP de Tor, nunca la tuya. Lo mantiene vivo tor_watchdog.pyw. "--apagar" lo detiene.
# Se copia a ~/.smiley/tor-chosen.sh (Setup-Browser.ps1 / lanzador).
# 04/10/2026, noche: KeepAliveIsolateSOCKSAuth (el circuito no se retira mientras se usa) y, como el
# motor principal, si a los 45 s no conecto con el primer puente, pasa a todos los de puentes.txt.
C=$HOME/.smiley
T=$C/tor-browser/Browser/TorBrowser/Tor
D=$C/tor-elegida
LISTA=__WINHOME__/Security/Browser/chosen_exit.txt
PUERTO=9055
mkdir -p "$D" && chmod 700 "$D"
if [ "${1:-}" = "--apagar" ]; then
  [ -f "$D/tor.pid" ] && kill "$(cat "$D/tor.pid")" 2> /dev/null
  rm -f "$D/tor.pid"
  exit 0
fi
pgrep -u "$(id -u)" -f "tor -f $D/torrc" > /dev/null && exit 0

PAISES=$(grep -i '^paises:' "$LISTA" 2> /dev/null | head -n 1 | cut -d: -f2)
[ -z "${PAISES// /}" ] && PAISES="us ca mx cl de nl fr gb"
NODOS=""
for p in $PAISES; do NODOS="$NODOS{${p,,}},"; done
NODOS=${NODOS%,}

# Mapa de la red ya descargado por el motor principal: arranque en segundos.
for f in "$C"/tor-browser/cached-*; do
  [ -e "$f" ] && [ ! -e "$D/$(basename "$f")" ] && cp "$f" "$D/"
done
# Entrada como el motor principal (speed.json, bloque "tor", clave "entrada"): directo o puente.
ENTRADA=$(python3 -c "import json; print(json.load(open('__WINHOME__/Security/Browser/speed.json', encoding='utf-8')).get('tor', {}).get('entrada', 'puente'))" 2> /dev/null || echo puente)
escribir_torrc() {  # $1 = cuantos puentes usar (solo con entrada "puente"), en el orden de puentes.txt
{
  echo "DataDirectory $D"
  echo "SocksPort 127.0.0.1:$PUERTO KeepAliveIsolateSOCKSAuth"
  if [ "$ENTRADA" = "directo" ]; then
    echo "UseBridges 0"
  else
    echo "UseBridges 1"
    echo "ClientTransportPlugin webtunnel exec $T/PluggableTransports/lyrebird"
    grep -E '^webtunnel ' "$C/puentes.txt" | head -n "${1:-1}" | sed 's/^/Bridge /'
  fi
  echo "ExitNodes $NODOS"
  echo "StrictNodes 1"
  echo "MaxCircuitDirtiness 3600"
  echo "AvoidDiskWrites 1"
  echo "GeoIPFile $C/tor-browser/Browser/TorBrowser/Data/Tor/geoip"
  echo "GeoIPv6File $C/tor-browser/Browser/TorBrowser/Data/Tor/geoip6"
  echo "PidFile $D/tor.pid"
  echo "Log notice file $D/tor.log"
} > "$D/torrc"
}

escribir_torrc 1
: > "$D/tor.log"
env LD_LIBRARY_PATH="$T" "$T/tor" -f "$D/torrc" > /dev/null 2>&1 &
TOR=$!
# Si a los 45 s no conecto con el primer puente, todos los de puentes.txt (los renueva el principal).
(
  for i in $(seq 1 15); do
    sleep 3
    kill -0 "$TOR" 2> /dev/null || exit 0
    grep -q 'Bootstrapped 100%' "$D/tor.log" && exit 0
  done
  if [ "$ENTRADA" != "directo" ]; then
    escribir_torrc 6
    kill -HUP "$TOR" 2> /dev/null
  fi
) &
wait "$TOR"
