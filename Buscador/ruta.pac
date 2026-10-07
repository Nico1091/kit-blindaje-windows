// Lo escribe lanzar_buscador.pyw en cada arranque: no editar a mano.
// Directo: solo este equipo y la red de la casa (y DIRECTOS, vacio mientras IP_SIEMPRE_OCULTA). Todo
// lo demas sale por Tor; la ruta fina por sitio la decide el filtro de librewolf.overrides.cfg (puerta
// directa 9060 para directos.txt, motor 9055 para salida_elegida.txt). Sin Tor, no hay plan B directo.
var DIRECTOS = [];
var LOCALES = [".local", ".lan", ".home.arpa", ".internal"];
function FindProxyForURL(url, host) {
  host = host.toLowerCase();
  if (isPlainHostName(host) || host == "localhost" || host == "::1" || host == "[::1]" ||
      /^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host) ||
      /^172\.(1[6-9]|2[0-9]|3[01])\./.test(host) || /^169\.254\./.test(host)) return "DIRECT";
  for (var i = 0; i < LOCALES.length; i++) if (dnsDomainIs(host, LOCALES[i])) return "DIRECT";
  for (var j = 0; j < DIRECTOS.length; j++) {
    if (host == DIRECTOS[j] || dnsDomainIs(host, "." + DIRECTOS[j])) return "DIRECT";
  }
  return "SOCKS5 127.0.0.1:9050";
}
