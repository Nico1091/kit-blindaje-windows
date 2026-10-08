"""
A/B test between two SOCKS ports that are already running, at the same time and with the same pages.
Typical use: is the circuit race still worth it?

    python ab_ports.py 9070 9050 [rounds]     (9070 = race.py in front of Tor, 9050 = Tor alone)

The result goes to tests/ab_ports-<a>-<b>-<date>.json.
"""
import json, os, sys, time
from ab_tor import HERE, run_pair, summary

a, b = int(sys.argv[1]), int(sys.argv[2])
rounds = int(sys.argv[3]) if len(sys.argv) > 3 else 3
ra, rb = run_pair(a, b, rounds, str(a), str(b), "abp")
res = {"date": time.strftime("%Y-%m-%d %H:%M"), str(a): summary(ra), str(b): summary(rb)}
json.dump(res, open(os.path.join(HERE, f"ab_ports-{a}-{b}-{time.strftime('%Y%m%d-%H%M')}.json"), "w"), indent=1)
print(a, summary(ra))
print(b, summary(rb))
