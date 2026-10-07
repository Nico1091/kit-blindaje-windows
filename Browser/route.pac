// Written by launch_browser.pyw on every start: do not edit by hand.
// Direct: only this PC and the home network (and DIRECTOS, empty while IP_SIEMPRE_OCULTA). Everything
// else goes through Tor; per-site routing is decided by the filter in librewolf.overrides.cfg (direct
// gate 9060 for direct.txt, engine 9055 for chosen_exit.txt). Without Tor there is no direct plan B.
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
