#!/bin/bash
# Browser CHOSEN-EXIT Tor engine: SOCKS on 127.0.0.1:9055.
# For sites that block by country rather than for being Tor (e.g. geo-filtered portals): exits only
# through relays in the countries on the "countries:" line of Security\Browser\chosen_exit.txt.
# Same entry as the main engine (direct or WebTunnel bridge, per speed.json): the site sees a Tor IP,
# never yours. Kept alive by tor_watchdog.pyw. "--apagar" stops it.
# Copied to ~/.smiley/tor-chosen.sh (Setup-Browser.ps1 / launcher).
# KeepAliveIsolateSOCKSAuth (a circuit is not retired while in use) and, like the main engine, if the
# first bridge has not connected after 45 s, it switches to all bridges in puentes.txt.
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

PAISES=$(grep -iE '^(countries|paises):' "$LISTA" 2> /dev/null | head -n 1 | cut -d: -f2)
[ -z "${PAISES// /}" ] && PAISES="us ca mx cl de nl fr gb"
NODOS=""
for p in $PAISES; do NODOS="$NODOS{${p,,}},"; done
NODOS=${NODOS%,}

# Network map already downloaded by the main engine: starts in seconds.
for f in "$C"/tor-browser/cached-*; do
  [ -e "$f" ] && [ ! -e "$D/$(basename "$f")" ] && cp "$f" "$D/"
done
# Entry as in the main engine (speed.json, block "tor", key "entry"): direct or bridge.
ENTRADA=$(python3 -c "import json; print(json.load(open('__WINHOME__/Security/Browser/speed.json', encoding='utf-8')).get('tor', {}).get('entry', 'bridge'))" 2> /dev/null || echo bridge)
case "$ENTRADA" in directo) ENTRADA=direct ;; puente) ENTRADA=bridge ;; esac
escribir_torrc() {  # $1 = how many bridges to use (only with entry "bridge"), in puentes.txt order
{
  echo "DataDirectory $D"
  echo "SocksPort 127.0.0.1:$PUERTO KeepAliveIsolateSOCKSAuth"
  if [ "$ENTRADA" = "direct" ]; then
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
# If the first bridge has not connected after 45 s, use all of puentes.txt (the main engine renews them).
(
  for i in $(seq 1 15); do
    sleep 3
    kill -0 "$TOR" 2> /dev/null || exit 0
    grep -q 'Bootstrapped 100%' "$D/tor.log" && exit 0
  done
  if [ "$ENTRADA" != "direct" ]; then
    escribir_torrc 6
    kill -HUP "$TOR" 2> /dev/null
  fi
) &
wait "$TOR"
