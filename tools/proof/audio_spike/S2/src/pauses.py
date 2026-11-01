"""What is left in the pause windows: per-window distribution, the loudest windows, and the bandwidth cut-off."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
dry = ana.load("audio/dry.f32")
N = len(dry)
pause, speech, lv, p10 = ana.classify(dry)
conds = [("dry", "audio/dry.f32", 0), ("iso HQ 100 %", "det/t0_b4096_a.f32", 0), ("iso Voice 100 %", "det/t1_b4096_a.f32", -1),
         ("NR 50 %", "nr/a50.f32", 0), ("NR 100 %", "nr/a100.f32", 0)]
idx = np.where(pause)[0]
print("Pause windows (400 ms): per-window RMS distribution (dBFS)")
print("| Condition | median | 75th | 90th | max | energy mean |")
print("|---|---|---|---|---|---|")
levels = {}
for name, path, L in conds:
    a = ana.align(ana.load(path), L, N)
    W = ana.windows(a)[pause]
    l = ana.db(np.mean(W ** 2, axis=1))
    levels[name] = l
    print(f"| {name} | {np.median(l):.1f} | {np.percentile(l, 75):.1f} | {np.percentile(l, 90):.1f} | {l.max():.1f} | {ana.db(np.mean(W ** 2)):.1f} |")
print()
print("Loudest pause windows after iso HQ (start s: dry -> HQ, Voice, NR100):")
order = np.argsort(-levels["iso HQ 100 %"])[:8]
for k in order:
    print(f"  {idx[k] * 0.4:5.1f} s: dry {levels['dry'][k]:.1f}  HQ {levels['iso HQ 100 %'][k]:.1f}  "
          f"Voice {levels['iso Voice 100 %'][k]:.1f}  NR100 {levels['NR 100 %'][k]:.1f}")

# Bandwidth: output/input PSD over speech windows, 1 kHz bins from 6 kHz
print()
Pd, f = ana.psd_bins(dry, speech)
for name, path, L in conds[1:3]:
    a = ana.align(ana.load(path), L, N)
    Pa, _ = ana.psd_bins(a, speech)
    cells = []
    for lo in range(6000, 24000, 1000):
        sel = (f >= lo) & (f < lo + 1000)
        cells.append(f"{lo // 1000}k {10 * np.log10(Pa[sel].sum() / Pd[sel].sum()):+.0f}")
    print(name, "speech-window gain by 1 kHz band:", ", ".join(cells))
