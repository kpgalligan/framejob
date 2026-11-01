"""Rule items 5a-5c: pause floor, speech level, per-octave speech band, vs the shipped reducer."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
dry = ana.load("audio/dry.f32")
N = len(dry)
pause, speech, lv, p10 = ana.classify(dry)
print(f"400 ms windows: {len(lv)}; p10 {p10:.1f} dBFS; pause {pause.sum()} ({100 * pause.mean():.0f} %), "
      f"speech {speech.sum()} ({100 * speech.mean():.0f} %), excluded {len(lv) - pause.sum() - speech.sum()}")

conds = [
    ("dry", "audio/dry.f32"),
    ("iso HQ 100 %", "det/t0_b4096_a.f32"),
    ("iso Voice 100 %", "det/t1_b4096_a.f32"),
    ("iso HQ 50 %", "mix/t0_m50.f32"),
    ("iso Voice 50 %", "mix/t1_m50.f32"),
    ("NR 25 %", "nr/a25.f32"),
    ("NR 50 %", "nr/a50.f32"),
    ("NR 75 %", "nr/a75.f32"),
    ("NR 100 %", "nr/a100.f32"),
]


def p10_50ms(x):
    W = ana.windows(x, 0.05)
    return np.percentile(ana.db(np.mean(W ** 2, axis=1)), 10)


Pd_s = ana.band_powers(dry, speech)
Pd_p = ana.band_powers(dry, pause)
rows = []
for name, path in conds:
    y = ana.load(path)
    L, Lf, r = ana.xcorr_lag(dry, y[:N], maxlag=8000)
    a = ana.align(y, L, N)
    pr = ana.class_rms(a, pause)
    sp = ana.class_rms(a, speech)
    Ps = ana.band_powers(a, speech)
    Pp = ana.band_powers(a, pause)
    band = 10 * np.log10(Ps / Pd_s)
    ns_d = Pd_s - Pd_p
    ns_c = Ps - Pp
    nsub = np.where((ns_d > 0) & (ns_c > 0), 10 * np.log10(np.maximum(ns_c, 1e-30) / np.maximum(ns_d, 1e-30)), np.nan)
    pause_band = 10 * np.log10(Pp / Pd_p)
    rows.append(dict(name=name, lag=L, pause=pr, speech=sp, p10_50=p10_50ms(a), band=band, nsub=nsub, pause_band=pause_band))

d0 = rows[0]
print()
print("| Condition | lag | pause RMS | pause after +28.7 dB | floor lowered | speech RMS | speech change | 50 ms p10 |")
print("|---|---|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r['name']} | {r['lag']} | {r['pause']:.1f} | {r['pause'] + ana.LIFT_DB:.1f} | {d0['pause'] - r['pause']:.1f} | "
          f"{r['speech']:.1f} | {r['speech'] - d0['speech']:+.2f} | {r['p10_50']:.1f} |")
print()
print("Speech windows, per octave, condition minus dry (dB):")
print("| Condition | " + " | ".join(str(f) for f in ana.OCTAVES) + " |")
print("|---|" + "---|" * len(ana.OCTAVES))
for r in rows[1:]:
    print(f"| {r['name']} | " + " | ".join(f"{v:+.1f}" for v in r["band"]) + " |")
print()
print("Speech windows minus pause windows (noise-subtracted voice), per octave, condition minus dry (dB):")
print("| Condition | " + " | ".join(str(f) for f in ana.OCTAVES) + " |")
print("|---|" + "---|" * len(ana.OCTAVES))
for r in rows[1:]:
    print(f"| {r['name']} | " + " | ".join("n/a" if np.isnan(v) else f"{v:+.1f}" for v in r["nsub"]) + " |")
print()
print("Pause windows, per octave, condition minus dry (dB):")
print("| Condition | " + " | ".join(str(f) for f in ana.OCTAVES) + " |")
print("|---|" + "---|" * len(ana.OCTAVES))
for r in rows[1:]:
    print(f"| {r['name']} | " + " | ".join(f"{v:+.1f}" for v in r["pause_band"]) + " |")
print()
print("dry speech-window band levels (dBFS-ish, per octave):", " ".join(f"{10*np.log10(v):.1f}" for v in Pd_s))
print("dry pause-window band levels:", " ".join(f"{10*np.log10(v):.1f}" for v in Pd_p))
print("dry speech-minus-pause margin per octave (dB):", " ".join(f"{10*np.log10(s/p):.1f}" for s, p in zip(Pd_s, Pd_p)))
