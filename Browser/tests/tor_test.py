#!/usr/bin/env python3
"""
Test Tor (SOCKS 127.0.0.1:19060, control 19061, data in /tmp/tortest) started with a named configuration,
to compare it against the Browser engine (9050) with ab_tor.py. It never touches the Browser engines.
Runs inside Ubuntu (WSL):
    python3 tor_test.py start NAME    -> starts, waits for 100 % and prints READY or FAILED
    python3 tor_test.py stop

Candidates (the entry follows "tor.entry" in speed.json: direct, or bridge = WebTunnel from puentes.txt):
    same               the engine's own entry, nothing else: run it first as an A/A control
    bridge2            first bridge of puentes.txt only (to compare one bridge against another)
    conflux2_latency   first two bridges, ConfluxClientUX latency
    conflux2_throughput first two bridges, ConfluxClientUX throughput
    exit_region        exit relays only in REGION (default us,ca)
    middle_region      middle relays only in REGION; exit unrestricted
    middle_exit_region middle and exit relays only in REGION
Restricting countries costs anonymity: fewer relays and a single region. Measure it, then decide.
SMILEY_HOME (default ~/.smiley) and REGION (default "us,ca") can be set in the environment.
"""
import binascii, glob, json, os, re, shutil, socket, subprocess, sys, time

C = os.path.expanduser(os.environ.get("SMILEY_HOME", "~/.smiley"))
T = C + "/tor-browser/Browser/TorBrowser/Tor"
GEO = C + "/tor-browser/Browser/TorBrowser/Data/Tor"
D = "/tmp/tortest"
SOCKS, CTRL = 19060, 19061
SPEED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "speed.json")
REGION = ",".join("{%s}" % c.strip().lower() for c in os.environ.get("REGION", "us,ca").split(",") if c.strip())


def bridges():
    try:
        return [l.strip() for l in open(C + "/puentes.txt") if l.startswith("webtunnel ")]
    except OSError:
        return []


def entry():
    try:
        e = json.load(open(SPEED, encoding="utf-8")).get("tor", {}).get("entry", "direct")
    except (OSError, ValueError):
        e = "direct"
    return {"directo": "direct", "puente": "bridge"}.get(e, e)


def entry_lines(n=1, skip=0):
    """Same entry as the engine: direct, or the first n WebTunnel bridges (after skipping some)."""
    if entry() != "bridge":
        return ["UseBridges 0"]
    chosen = bridges()[skip:skip + n]
    if not chosen:
        raise SystemExit("FAILED: entry is 'bridge' but puentes.txt has no WebTunnel bridges")
    return (["UseBridges 1", f"ClientTransportPlugin webtunnel exec {T}/PluggableTransports/lyrebird"]
            + [f"Bridge {b}" for b in chosen])


def config(name):
    return {
        "same": lambda: entry_lines(),
        "bridge2": lambda: entry_lines(1, skip=1),
        "conflux2_latency": lambda: entry_lines(2) + ["ConfluxEnabled 1", "ConfluxClientUX latency"],
        "conflux2_throughput": lambda: entry_lines(2) + ["ConfluxEnabled 1", "ConfluxClientUX throughput"],
        "exit_region": lambda: entry_lines() + [f"ExitNodes {REGION}", "StrictNodes 1"],
        "middle_region": lambda: entry_lines() + [f"MiddleNodes {REGION}", "StrictNodes 1"],
        "middle_exit_region": lambda: entry_lines() + [f"MiddleNodes {REGION}", f"ExitNodes {REGION}", "StrictNodes 1"],
    }[name]()


def control(lines):
    s = socket.create_connection(("127.0.0.1", CTRL), timeout=30)
    cookie = binascii.hexlify(open(D + "/control_auth_cookie", "rb").read()).decode()
    reply = ""
    for line in ["AUTHENTICATE " + cookie] + lines:
        s.sendall((line + "\r\n").encode())
        data = b""
        while not re.search(rb"(^|\r\n)\d{3} [^\r\n]*\r\n$", data):
            data += s.recv(65536)
        reply = data.decode("utf-8", "replace")
    s.close()
    return reply


def stop():
    try:
        control(["SIGNAL HALT"])
    except OSError:
        pass
    time.sleep(2)
    subprocess.run(["pkill", "-f", "[t]or -f " + D + "/torrc"])
    shutil.rmtree(D, ignore_errors=True)


def start(name):
    stop()
    lines = config(name)
    os.makedirs(D)
    os.chmod(D, 0o700)
    # The engine's directory cache (wherever its DataDirectory is): boots in seconds instead of minutes.
    cache = next((os.path.dirname(f) for f in sorted(glob.glob(C + "/*/cached-microdesc-consensus"))), None)
    for f in glob.glob(cache + "/cached-*") if cache else []:
        shutil.copy(f, D)
    with open(D + "/torrc", "w") as f:
        f.write(f"DataDirectory {D}\nSocksPort 127.0.0.1:{SOCKS}\nControlPort 127.0.0.1:{CTRL}\nCookieAuthentication 1\n"
                f"GeoIPFile {GEO}/geoip\nGeoIPv6File {GEO}/geoip6\nLog notice file {D}/tor.log\n"
                + "".join(x + "\n" for x in lines))
    subprocess.Popen([T + "/tor", "-f", D + "/torrc"], env=dict(os.environ, LD_LIBRARY_PATH=T),
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(60):
        time.sleep(1)
        if os.path.exists(D + "/control_auth_cookie"):
            break
    time.sleep(1)
    t0 = time.time()
    while time.time() - t0 < 240:
        try:
            if "PROGRESS=100" in control(["GETINFO status/bootstrap-phase"]):
                time.sleep(10)  # let it build spare circuits, as in normal use
                print(f"READY {name} in {time.time() - t0:.0f} s", flush=True)
                return
        except OSError:
            pass
        time.sleep(2)
    print(f"FAILED {name}: not connected after 4 minutes", flush=True)


if __name__ == "__main__":
    if sys.argv[1] == "stop":
        stop()
        print("stopped")
    else:
        start(sys.argv[2])
