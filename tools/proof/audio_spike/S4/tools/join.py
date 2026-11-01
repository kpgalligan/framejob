"""Reads lcache `windows` outputs and ffref outputs and prints a joined table.

usage: join.py <name>=<windows-output> ... ff=<ffref-output>
Columns from a windows output: nearest, outward, inward, direct, phaseMin, phaseMax, cacheTP, directTP.
"""
import sys

def windows(path):
    rows = []
    for line in open(path):
        if line.startswith("#"):
            continue
        parts = [p.split() for p in line.split("|")]
        rows.append({
            "win": (float(parts[0][0]), float(parts[0][1])),
            "nearest": float(parts[1][0]), "outward": float(parts[1][1]), "inward": float(parts[1][2]),
            "direct": float(parts[2][0]), "pmin": float(parts[2][1]), "pmax": float(parts[2][2]),
            "ctp": float(parts[3][0]), "dtp": float(parts[3][1]),
        })
    return rows

def ff(path):
    rows = []
    for line in open(path):
        p = line.split()
        rows.append({"I": float(p[3]) if p[3] != "None" else float("nan"), "TP": float(p[5])})
    return rows

sets = {}
for a in sys.argv[1:]:
    k, v = a.split("=", 1)
    sets[k] = ff(v) if k.startswith("ff") else windows(v)
keys = list(sets)
n = len(next(iter(sets.values())))
print("| window (s) | " + " | ".join(keys) + " |")
for i in range(n):
    first = next(r for k, r in sets.items() if not k.startswith("ff"))[i]["win"]
    cells = []
    for k in keys:
        r = sets[k][i]
        if k.startswith("ff"):
            cells.append(f"I {r['I']:.3f} TP {r['TP']:.3f}")
        else:
            cells.append(f"cache {r['nearest']:.3f} direct {r['direct']:.3f} TP {r['ctp']:.3f}/{r['dtp']:.3f}")
    print(f"| {first[0]:.3f}–{first[1]:.3f} | " + " | ".join(cells) + " |")
