"""Limiter: true peak of each output by an oversampler independent of the
limiter's own detector (4x, 64 taps per phase, Kaiser beta 10, the window
evaluated at each tap's own distance), plus ffmpeg's ebur128 true peak and
integrated loudness as a cross-check.
Usage: python3 -I analyze_lim.py <S1 dir> [cases...]
"""
import re
import subprocess
import sys

import numpy as np

D = sys.argv[1]
CASES = sys.argv[2:] or ["dry", "own", "own48", "own12", "au", "au_trim", "au_a1", "au_a30"]
FS = 48000
TAPS, H, BETA = 64, 32, 10.0
J = np.arange(-(H - 1), H + 1)  # offsets of x[m + j]
phases = []
for p in (1, 2, 3):
    t = p / 4 - J
    r = np.clip(1 - (t / (H + 0.5)) ** 2, 0, None)
    h = np.sinc(t) * np.i0(BETA * np.sqrt(r)) / np.i0(BETA)
    phases.append(h / h.sum())


def tp_trace(x):
    """Per-sample true peak: max(|x[m]|, |x(m + p/4)|), p = 1..3."""
    tr = np.abs(x).copy()
    for h in phases:
        # y[m] = sum_j h[j] x[m + j]  -> correlate.
        y = np.correlate(np.pad(x, (H - 1, H)), h, mode="valid")
        tr = np.maximum(tr, np.abs(y))
    return tr


def db(v):
    return 20 * np.log10(v)


# BS.1770-4 Annex 2's order-48 4-phase FIR, transcribed from phase5_proof.py at
# 9e47f56 (the project's own proof meter): y_p[n] = sum_k x[n - k] * phase_p[k].
ANNEX2 = [
    (0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000, -0.0594482421875, 0.1373291015625,
     0.9721679687500, -0.1022949218750, 0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500),
    (-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250, -0.1665039062500, 0.4650878906250,
     0.7797851562500, -0.2003173828125, 0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375),
    (-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000, -0.2003173828125, 0.7797851562500,
     0.4650878906250, -0.1665039062500, 0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875),
    (-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750, -0.1022949218750, 0.9721679687500,
     0.1373291015625, -0.0594482421875, 0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750),
]


def annex2_tp(x):
    best = np.max(np.abs(x))
    for ph in ANNEX2:
        best = max(best, np.max(np.abs(np.convolve(x, np.array(ph))[:len(x)])))
    return db(best)


def ff(path):
    r = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-f", "f32le", "-ar", str(FS), "-ac", "1", "-i", path,
                        "-af", "ebur128=peak=true:framelog=quiet", "-f", "null", "-"], capture_output=True, text=True)
    t = r.stderr
    i = re.search(r"I:\s+(-?[\d.]+|-inf) LUFS", t)
    p = re.search(r"True peak:\s+Peak:\s+(-?[\d.]+|-inf) dBFS", t)
    return (i.group(1) if i else "?"), (p.group(1) if p else "?")


m = np.arange(48000)
chk = np.sin(2 * np.pi * 0.25 * m + np.pi / 4)  # samples at +-0.707: TP 0 dBTP, sample peak -3.01
print(f"meter self-check: fs/4 at 45 deg, sample peak {db(np.max(np.abs(chk))):.3f} dBFS, "
      f"true peak {db(np.max(tp_trace(chk)[1000:-1000])):.4f} dBTP (expected 0.0000)")
for f in (997, 12000, 18000, 20000):
    s = np.sin(2 * np.pi * f * m / FS + 0.3)
    print(f"meter self-check: {f} Hz full-scale sine true peak {db(np.max(tp_trace(s)[1000:-1000])):+.4f} dBTP (expected ≤ 0, ≥ −0.69 from 4× sampling alone)")
print()

print(f"{'signal':6} {'case':8} {'sample pk':>10} {'true pk':>9} {'over -1':>8} {'annex2 TP':>10} {'ffmpeg TP':>10} {'ffmpeg I':>9}")
traces = {}
for sig in ["rode", "crest"]:
    for case in CASES:
        p = f"{D}/out/lim_{sig}_{case}.f32"
        try:
            x = np.fromfile(p, dtype="<f4").astype(np.float64)
        except FileNotFoundError:
            continue
        tr = tp_trace(x)
        traces[(sig, case)] = tr
        sp = db(np.max(np.abs(x)))
        tp = db(np.max(tr))
        i, ftp = ff(p)
        print(f"{sig:6} {case:8} {sp:10.3f} {tp:9.3f} {tp + 1:8.3f} {annex2_tp(x):10.3f} {ftp:>10} {i:>9}")
    print()

print("crest signal by part (max true peak dBTP; a..e 1 s each, f 3 s; outputs read 1 s windows of one whole-file trace):")
names = ["a fs/4", "b pairs", "c burst", "d 60+clk", "e step", "f pink", "f pink", "f pink"]
for case in CASES:
    if ("crest", case) not in traces:
        continue
    tr = traces[("crest", case)]
    row = [f"{db(np.max(tr[k * FS:(k + 1) * FS])):8.2f}" for k in range(8)]
    print(f"  {case:8} " + " ".join(row))
print("  part     " + " ".join(f"{s:>8}" for s in names))
