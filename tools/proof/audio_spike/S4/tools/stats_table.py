"""usage: stats_table.py <stats output>  — summarises lcache `stats` rows."""
import sys
import numpy as np

rows = [l.replace('|', ' ').split() for l in open(sys.argv[1]) if not l.startswith('#')]
a = np.array([[float(x) for x in r] for r in rows])
names = ['window length (s)', 'phase spread of DIRECT', '100 ms − direct', '25 ms − direct', '10 ms − direct',
         '10 ms dense − direct', '100 ms outside band', '25 ms outside band', '10 ms outside band',
         '10 ms dense outside band', '10 ms dense − phase mean']
print(f"n = {len(a)}")
print("| quantity (LU) | median | p95 | max | share > 0.1 |")
print("|---|---|---|---|---|")
for i, n in enumerate(names):
    col = np.abs(a[:, i])
    if i == 0:
        print(f"| {n} | {np.median(col):.1f} | {np.percentile(col, 95):.1f} | {col.max():.1f} | — |")
        continue
    print(f"| {n} | {np.median(col):.3f} | {np.percentile(col, 95):.3f} | {col.max():.3f} | {np.mean(col > 0.1) * 100:.0f} % |")
