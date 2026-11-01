"""Parameter steps.
(1) 2 kHz peaking 0 -> +12 dB at sample 96000 under a 1 kHz tone (-20 dBFS):
    energy outside 700..1300 Hz in the 50 ms after the step (Hann, dB re the
    tone), and how long the tone's level takes to settle (10 %..90 %).
(2) AUPeakLimiter attack 1 ms -> 30 ms at sample 144384 on quiet noise: the
    cross-correlation lag before and after.
Usage: python3 -I analyze_zip.py <S1 dir>
"""
import sys

import numpy as np

D = sys.argv[1]
FS = 48000
STEP = 96256


def splatter(x, a, n=2400):
    seg = x[a:a + n] * np.hanning(n)
    S = np.abs(np.fft.rfft(seg)) ** 2
    f = np.fft.rfftfreq(n, 1 / FS)
    out = S[(f < 700) | (f > 1300)].sum()
    tone = S[(f >= 700) & (f <= 1300)].sum()
    return 10 * np.log10(out / tone + 1e-30)


def level(x, a, n=96):
    t = np.arange(a, a + n) / FS
    M = np.stack([np.sin(2 * np.pi * 1000 * t), np.cos(2 * np.pi * 1000 * t)], 1)
    c, *_ = np.linalg.lstsq(M, x[a:a + n], rcond=None)
    return np.hypot(*c)


print(f"{'case':14} {'before':>8} {'after 50ms':>11} {'settle 10-90%':>14} {'level change':>12}")
for case in ["none", "own_abrupt", "own_smoothed", "au_none", "au_abrupt"]:
    x = np.fromfile(f"{D}/out/zip_{case}.f32", dtype="<f4").astype(np.float64)
    b = splatter(x, STEP - 4800)
    a = splatter(x, STEP)
    l0 = level(x, STEP - 960)
    l1 = level(x, STEP + 9600)
    settle = "-"
    if abs(20 * np.log10(l1 / l0)) > 0.1:
        lv = np.array([level(x, STEP + k) for k in range(0, 4800, 24)])
        frac = (lv - l0) / (l1 - l0)
        t10 = np.argmax(frac >= 0.1) * 24 / FS * 1000
        t90 = np.argmax(frac >= 0.9) * 24 / FS * 1000
        settle = f"{t10:.1f}..{t90:.1f} ms"
    print(f"{case:14} {b:8.1f} {a:11.1f} {settle:>14} {20*np.log10(l1/l0):+11.2f} dB")

print()
q = np.fromfile(f"{D}/out/zip_quiet_dry.f32", dtype="<f4").astype(np.float64)
y = np.fromfile(f"{D}/out/zip_au_limiter_attack_step.f32", dtype="<f4").astype(np.float64)


def lag(d, w, maxlag=2048):
    n = len(d)
    nfft = 1 << (2 * n + maxlag).bit_length()
    c = np.fft.irfft(np.fft.rfft(w, nfft) * np.conj(np.fft.rfft(d, nfft)), nfft)[:maxlag + 1]
    return int(np.argmax(np.abs(c)))


for a in [48000, 96000, 140000, 150000, 200000, 240000]:
    print(f"AUPeakLimiter attack step: window at {a} ({'before' if a < 144384 else 'after'} the change): lag {lag(q[a:a+4096], y[a:a+4096+2048][:4096+2048])}")
