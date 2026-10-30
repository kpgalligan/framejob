"""Run one isolate command many times; hash each output. Usage: repeat.py <n> <args...>"""
import collections
import hashlib
import os
import subprocess
import sys

S2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(S2)
n = int(sys.argv[1])
args = sys.argv[2:]
seen = collections.Counter()
order = []
for i in range(n):
    out = "win/rep.f32"
    subprocess.run(["bin/isolate"] + args + ["--out", out], check=True, capture_output=True)
    h = hashlib.sha256(open(out, "rb").read()).hexdigest()[:16]
    seen[h] += 1
    order.append(h[:6])
    load = " ".join(f"{x:.1f}" for x in os.getloadavg())
print(" ".join(order))
print(dict(seen), "load", load)
