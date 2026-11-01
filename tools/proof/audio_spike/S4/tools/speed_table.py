"""Speed table: ffmpeg's played loudness against the cache's source reading (x1) and
its time-scaled-gating reading. usage: speed_table.py <out/speed.txt> <out/speed_cache.txt>"""
import sys

ff = {}
section = None
for line in open(sys.argv[1]):
    if line.startswith("=="):
        section = line.strip("= \n")
        ff[section] = []
        continue
    p = line.split()
    ff[section].append(float(p[3]))
cache = []
for line in open(sys.argv[2]):
    p = line.split()
    cache.append({p[i]: float(p[i + 1]) for i in range(2, len(p), 2)})

speeds = [("0.5", "x0.50"), ("0.8", "x0.80"), ("1.25", "x1.25"), ("2.0", "x2.00")]
def rng(xs):
    return f"{min(xs):+.2f} … {max(xs):+.2f}"
print("| played − cache reading (LU), whole file; five windows | ×0.5 | ×0.8 | ×1.25 | ×2 |")
print("|---|---|---|---|---|")
for kind, label in [("varispeed", "varispeed"), ("pitch kept (atempo)", "pitch kept (atempo)")]:
    for reading, key in [("source reading (×1 gating)", "x1.00"), ("time-scaled gating", None)]:
        cells = []
        for s, k in speeds:
            played = ff[f"{kind} x{s}"]
            ref = [c[key or k] for c in cache]
            d = [p - r for p, r in zip(played, ref)]
            cells.append(f"{d[0]:+.2f}; {rng(d[1:])}")
        print(f"| {label} − {reading} | " + " | ".join(cells) + " |")
