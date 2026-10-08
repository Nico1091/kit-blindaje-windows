"""
A/B test of a Tor configuration: the Browser engine (9050) against a candidate in the test Tor (19060),
AT THE SAME TIME, with the same pages, a new circuit per request (a different SOCKS user, like a new site
in the browser) and alternating order. No race in front: it measures Tor only.

    python ab_tor.py CANDIDATE [rounds]      (candidates: see tor_test.py; default 3 rounds)

Run "same" first: it is the A/A control and tells you how much the numbers move by chance. Only trust
a gain in the median that is clearly larger than that and repeats in every round.
The result goes to tests/ab_tor-<candidate>-<date>.json.
"""
import concurrent.futures as cf, json, os, random, statistics, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SITES = [
    "https://www.wikipedia.org/", "https://duckduckgo.com/", "https://www.debian.org/", "https://www.mozilla.org/",
    "https://www.python.org/", "https://www.eff.org/", "https://www.bbc.com/", "https://www.torproject.org/",
    "https://www.kernel.org/", "https://www.gnu.org/", "https://www.w3.org/", "https://www.rust-lang.org/",
    "https://www.reddit.com/", "https://github.com/", "https://www.youtube.com/", "https://www.twitch.tv/",
    "https://en.wikipedia.org/", "https://www.theguardian.com/", "https://www.nytimes.com/", "https://www.netflix.com/",
    "https://www.spotify.com/", "https://www.instagram.com/", "https://www.tiktok.com/", "https://stackoverflow.com/",
]
SLOW_S = 10
UA = "Mozilla/5.0 (Windows NT 10.0; rv:140.0) Gecko/20100101 Firefox/140.0"


def distro():
    """First Ubuntu distribution installed in WSL (same rule as launch_browser.pyw)."""
    try:
        out = subprocess.run(["wsl.exe", "-l", "-q"], capture_output=True).stdout.decode("utf-16-le", "ignore")
        return next((d.strip() for d in out.splitlines() if d.strip().lower().startswith("ubuntu")), "Ubuntu")
    except Exception:
        return "Ubuntu"


def wsl_path(p):
    p = os.path.abspath(p)
    return "/mnt/" + p[0].lower() + p[2:].replace("\\", "/")


def wsl(*args):
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    passed = [k for k in ("SMILEY_HOME", "REGION") if k in env]  # Windows -> WSL environment
    if passed:
        env["WSLENV"] = ":".join(filter(None, [env.get("WSLENV", "")] + [k + "/u" for k in passed]))
    p = subprocess.run(["wsl.exe", "-d", distro(), "--exec", "python3", wsl_path(os.path.join(HERE, "tor_test.py")), *args],
                       capture_output=True, timeout=400, env=env)
    return p.stdout.decode("utf-8", "replace").strip()


def fetch(port, user, url):
    p = subprocess.run(["curl.exe", "-s", "-o", "NUL", "-m", "40", "--compressed", "-A", UA,
                        "--socks5-hostname", f"{user}:x@127.0.0.1:{port}",
                        "-w", "%{http_code} %{time_starttransfer}", url], capture_output=True)
    parts = p.stdout.decode().split()
    ok = len(parts) == 2 and parts[0] != "000"
    return {"url": url, "code": parts[0] if parts else "000", "s": float(parts[1]) if ok else 40.0, "ok": ok}


def summary(r):
    t = sorted(x["s"] for x in r)
    return {"median_s": round(statistics.median(t), 2), "p75_s": round(t[int(0.75 * (len(t) - 1))], 2),
            "p90_s": round(t[int(0.9 * (len(t) - 1))], 2), "slow_pct": round(100 * sum(x > SLOW_S for x in t) / len(t), 1),
            "failed": sum(not x["ok"] for x in r), "samples": len(t)}


def run_pair(port_a, port_b, rounds, label_a, label_b, tag):
    """Same pages on both ports at the same time, alternating which goes first."""
    stamp, ra, rb = str(int(time.time())), [], []
    for v in range(rounds):
        order = SITES[:]
        random.shuffle(order)
        with cf.ThreadPoolExecutor(8) as ex:
            futures = []
            for i, url in enumerate(order):
                pairs = [(port_a, ra), (port_b, rb)]
                if (i + v) % 2:
                    pairs.reverse()
                for port, dest in pairs:
                    futures.append((dest, ex.submit(fetch, port, f"{tag}{port}-{v}-{i}-{stamp}", url)))
            for dest, f in futures:
                dest.append(f.result())
        print(f"  round {v + 1}: {label_a} {summary(ra)['median_s']} s | {label_b} {summary(rb)['median_s']} s", flush=True)
    return ra, rb


def main():
    cand = sys.argv[1]
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    status = wsl("start", cand)
    print(status, flush=True)
    if not status.startswith("READY"):
        print(wsl("stop"), flush=True)  # never leave the test Tor running
        sys.exit(1)
    stamp = str(int(time.time()))
    with cf.ThreadPoolExecutor(8) as ex:  # warm up the candidate without measuring: the engine is already warm
        list(ex.map(lambda iu: fetch(19060, f"ab-warm{iu[0]}-{stamp}", iu[1]), enumerate(SITES)))
    real, new = run_pair(9050, 19060, rounds, "engine", cand, "ab")
    print(wsl("stop"), flush=True)
    res = {"date": time.strftime("%Y-%m-%d %H:%M"), "candidate": cand, "engine_9050": summary(real),
           "candidate_19060": summary(new), "detail_engine": real, "detail_candidate": new}
    out = os.path.join(HERE, f"ab_tor-{cand}-{time.strftime('%Y%m%d-%H%M')}.json")
    json.dump(res, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"ENGINE 9050 : {res['engine_9050']}")
    print(f"{cand:12}: {res['candidate_19060']}")


if __name__ == "__main__":
    main()
