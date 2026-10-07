#!/bin/bash
# Browser (LibreWolf) Tor engine: SOCKS on 127.0.0.1:9050. No window. Kept alive by
# Security\Browser\tor_watchdog.pyw (task "Browser - Tor always").
# Windows copy: Security\Browser\tor-browser.sh; installed as ~/.smiley/tor-browser.sh.
#
# Entry is set in Security\Browser\speed.json, block "tor" (keys stay in Spanish):
#   "entrada": "puente"  -> WebTunnel bridge (script default): your ISP only sees HTTPS to an ordinary page.
#              "directo" -> no bridge: your ISP sees that you use Tor, not what you visit. Legal in most
#                           countries, and often faster when your bridges are far from Tor's guards.
#   "conflux_ux": "throughput" (more bandwidth) | "latency" (less waiting)
#   "salida_paises" / "medio_paises": country codes for exit / middle relays (empty = any).
# Bridge maintenance (renew, rescue) only runs with "puente".
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

leer() {  # $1 = key in the "tor" block, $2 = default value
  python3 -c "import json; print(json.load(open('$VEL', encoding='utf-8')).get('tor', {}).get('$1', '$2'))" 2> /dev/null || echo "$2"
}
ENTRADA=$(leer entrada puente)
UX=$(leer conflux_ux throughput)
paises() {  # $1 = key holding a list of country codes -> "{us},{ca}" (empty = any country)
  python3 -c "import json; print(','.join('{%s}' % p.lower() for p in json.load(open('$VEL', encoding='utf-8')).get('tor', {}).get('$1', [])))" 2> /dev/null
}
SALIDA=$(paises salida_paises)
MEDIO=$(paises medio_paises)

# $1 = how many bridges to use (only with entry "puente"), in puentes.txt order.
escribir_torrc() {
  {
    echo "DataDirectory $D"
    # KeepAliveIsolateSOCKSAuth (as in Tor Browser): a site's circuit is not retired after 10 minutes
    # while you keep using it; without this, a long session (e.g. Outlook) would change IP.
    echo "SocksPort 127.0.0.1:$PUERTO KeepAliveIsolateSOCKSAuth"
    echo "AvoidDiskWrites 1"
    # Tor's country database: without it, salida_paises / medio_paises would match no relay.
    echo "GeoIPFile $C/tor-browser/Browser/TorBrowser/Data/Tor/geoip"
    echo "GeoIPv6File $C/tor-browser/Browser/TorBrowser/Data/Tor/geoip6"
    echo "PidFile $D/tor.pid"
    echo "Log notice file $D/tor.log"
    echo "ConfluxEnabled 1"
    echo "ConfluxClientUX $UX"
    # Route geography (speed.json, tor.salida_paises / tor.medio_paises; empty = any).
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

# Watchdog. Direct: only warms up the first circuit. Bridge: once connected, renews the bridges
# through Tor (at most every 12 h); if not connected after 45 s, switches to all bridges; if still
# not connected after 5 minutes, requests new bridges.
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
