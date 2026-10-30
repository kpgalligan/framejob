"""How many word offsets each variant of the offset rule finds on dry."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
dry = ana.load("audio/dry.f32")
E = np.mean(ana.windows(dry, 0.01) ** 2, axis=1)
Edb = ana.db(E)
p10 = np.percentile(Edb, 10)
print(f"10 ms envelope p10 {p10:.1f}, p50 {np.percentile(Edb, 50):.1f}, p90 {np.percentile(Edb, 90):.1f}, p99 {np.percentile(Edb, 99):.1f}")


def find(above, drop, hold_frames, hold_drop):
    S = p10 + above
    out = []
    k = 10
    while k < len(E) - 26:
        pre = ana.db(np.mean(E[k - 10:k]))
        if pre >= S and Edb[k] <= pre - drop and np.all(Edb[k + 1:k + 1 + hold_frames] <= pre - hold_drop):
            out.append(k)
            k += 30
        else:
            k += 1
    return out


def runs(above, gap_below, gap_frames):
    S = p10 + above
    out = []
    for k in range(10, len(E) - gap_frames):
        if Edb[k - 1] >= S and np.all(Edb[k:k + gap_frames] < S - gap_below) and (not out or k - out[-1] > 30):
            out.append(k)
    return out


for above in (20, 15):
    for gb in (0, 6):
        o = runs(above, gb, 25)
        print(f"run end: frame >= p10+{above}, next 250 ms < that - {gb}: {len(o)} offsets at "
              + ", ".join(f"{x / 100:.2f}" for x in o))

for above in (20, 15, 12):
    for hold, hd in ((25, 15), (25, 10), (20, 10)):
        o = find(above, 15, hold, hd)
        print(f"speech >= p10+{above}, fall 15 dB, next {hold * 10} ms <= pre-{hd}: {len(o)} offsets")
