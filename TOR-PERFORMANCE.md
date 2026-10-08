# Tor speed: what was measured and what was learned

This page explains where the waiting time goes when the Browser reaches the Internet through Tor, which changes help, which do not, and how to measure it on your own connection. The numbers come from one connection far from Europe using one WebTunnel bridge, in October 2026. Yours will differ; the method is what you should reuse.

## How to measure without fooling yourself

The tools are in `Browser\tests` (see `COMMANDS.md`).

1. **Compare at the same time, never one after the other.** Tor changes from minute to minute. `ab_tor.py` sends the same pages to the Browser engine (port 9050) and to a test Tor with the candidate configuration (port 19060) at once, in alternating order, with a new circuit per request.
2. **Run the A/A control first** (`ab_tor.py same`): both sides use the same configuration. In our runs the median moved by about 0.1 s by pure chance, and the 90th percentile by up to 1.5 s. A change only counts when its median gain is clearly larger than that and repeats in every round.
3. **Prefer the real browser over curl for site behaviour.** curl does not have Firefox's TLS fingerprint: several sites answered 403 to curl and 200 to LibreWolf.
4. **One good round proves nothing.** A change that looked like a 34 % gain in a single round turned out, over eleven loads, to be faster on most loads but to stall on two of them.

## Where the time goes

- **Your own network is rarely the problem.** Wi-Fi to the router measured 3–5 ms with no loss, and the hop from Windows into WSL2 added 0.25 ms. Check yours with `ping` to your router before blaming Tor.
- **Each round trip through the circuit cost about 0.55 s**, against 0.28 s in the Tor Project's own measurements from a data centre. A new page needs about three round trips (open the stream, TLS, request), which is why a new site takes around 1.7–2 s to send its first byte.
- **Most of Tor is in Europe.** In the consensus of that day, 83 % of exit bandwidth was outside the United States and Canada (Netherlands 29 %, Germany 25 %, United States 16 %), and Latin America had 0.1 %. From the Americas, almost every circuit crosses the Atlantic twice.
- **The bridge is the bottleneck you can choose.** Circuits took 1.0 s to build (median) against 0.19 s in the official measurements; the extra time is the trip to the bridge and its queue.
- **Tor's 10-second stream timeout makes the slow tail.** When an exit does not answer, Tor waits 10 s before trying another circuit (`MIN_CIRCUIT_STREAM_TIMEOUT`, a fixed value; see Tor issue #21394). The circuit race in `race.py` exists to hide exactly that.

## Results (Browser engine against each candidate, 72 samples per side)

| Candidate | Median, candidate / engine | 90th percentile, candidate / engine | Verdict |
|---|---|---|---|
| A different single bridge (the one with the best raw throughput) | 2.41 / 1.62 s | 7.1 / 3.8 s | Worse. Raw throughput does not predict browsing speed |
| Conflux over two bridges, `latency` | 2.01 / 1.69 s | 4.6 / 11.1 s | Worse median |
| Conflux over two bridges, `throughput` | 2.10 / 1.94 s | 9.5 / 3.8 s | Worse |
| Exit relays only in the US and Canada | 2.08 / 1.81 s | 3.5 / 3.7 s | No gain: big sites serve from a CDN near any exit |
| Middle relays only in the US and Canada | 1.62 / 1.85 s | 2.9 / 4.9 s | About 12 % faster; costs some anonymity |
| Middle and exit relays only in the US and Canada | 1.46 / 2.34 s | 3.1 / 5.3 s | About 38 % faster; costs more anonymity |

**Circuit race (`race.py`, port 9070) against Tor alone (9050), 96 samples per side:** median 2.09 / 2.20 s, 75th percentile 2.56 / 3.59 s, 90th percentile 3.61 / 5.52 s, slow pages 4.2 / 6.2 %. It barely moves the median but clearly shortens the slow tail. Keep it on.

**What this means for `speed.json`:** with one good bridge and the race on, nothing tested beat the default without giving up anonymity. Restricting `middle_countries` (and `exit_countries`) to your own region is the only large gain, and it shrinks the set of relays you can use to about one sixth, all in one region. Measure it with `ab_tor.py middle_region` and `middle_exit_region` (set `REGION`), then decide.

**Choosing a bridge:** measure it by page response (`ab_tor.py bridge2`), not by how fast it downloads a big file. In our tests the bridge with the shortest round trip won, even though another one downloaded faster.

## Encryption notes

- **ECH does nothing through Tor.** Encrypted Client Hello needs the site's HTTPS DNS record. With DNS resolved by the exit (SOCKS remote DNS), Firefox never fetches it, and Tor exits cannot resolve that record type. The browser sends only an ECH "grease" extension: the exit relay sees the site name. Your local network does not, because it only sees encrypted Tor traffic. Only `.onion` addresses avoid the exit entirely.
- **TLS 0-RTT:** Tor Browser keeps Firefox's default (0-RTT on). LibreWolf turns it off. Turning it on saves one round trip when you return to a site after its connection closed. It also lets early data be replayed and gives it no forward secrecy. With keep-alive at 600 s the gain is small; it was left off.
- **Post-quantum TLS** (X25519MLKEM768) is on by default in current Firefox and LibreWolf. Tor's own circuit handshakes are not post-quantum yet.
- **Counter Galois Onion (CGO)**, the new relay encryption, shipped in Tor 0.4.9 and is in the protocols the network recommends to clients. Keep Tor up to date: in autumn 2026 C-tor moved to a two-week security release cadence.

## Two traps worth knowing

- **IPv6 that dies in the middle.** If your provider's IPv6 is broken, sites in `direct.txt` can lose 4 s per IPv6 address before falling back to IPv4. The browser resolves those names locally, so `network.dns.disableIPv6 = true` in `librewolf.overrides.cfg` fixes it. In our test, one load of such a site made 43 connections with no IPv6 failure, against dozens of 4 s timeouts before. This does not affect sites that go through Tor: their names are resolved by the exit.
- **Search through `.onion`.** DuckDuckGo's onion address opens in LibreWolf with no extra setting. It was as fast as the normal site after the first search (the first one takes a few seconds more while Tor reaches the onion service), and no exit relay sees which search engine you use.

## Sources

- Tor Metrics, OnionPerf: https://metrics.torproject.org/onionperf-latencies.html
- Proposal 329, Conflux: https://spec.torproject.org/proposals/329-traffic-splitting.html
- AlSabah et al., "The Path Less Travelled" (PETS 2013): https://www.freehaven.net/anonbib/cache/pets13-splitting.pdf
- Tor issue #21394, stream timeouts: https://gitlab.torproject.org/tpo/core/tor/-/work_items/21394
- PTPerf, pluggable transport performance (IMC 2023): https://arxiv.org/html/2309.14856
- ECH in Tor Browser (Tor forum): https://forum.torproject.org/t/tor-browser-seemingly-doesnt-use-ech-secure-sni/21753
- Proposal 359, Counter Galois Onion: https://spec.torproject.org/proposals/359-cgo-redux.html
- Post-quantum migration of Tor: https://eprint.iacr.org/2025/479.pdf
- Tor 0.4.9.12 and the two-week cadence: https://forum.torproject.org/t/security-release-0-4-9-12/22096
