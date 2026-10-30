"""Passband of candidate quarter-sample interpolators: |H_p(f)| in dB for the
three phases, f up to 20 kHz at 48 kHz. An interpolator that reads LOW
(negative dB) lets a true-peak limiter overshoot its ceiling.
"""
import numpy as np

FS = 48000.0
f = np.linspace(0, 20000, 401)


def kaiser_at(t, half, beta):
    r = np.clip(1 - (t / half) ** 2, 0, None)
    return np.i0(beta * np.sqrt(r)) / np.i0(beta)


def design(taps, window, beta=8.0):
    # offsets j = -(taps/2 - 1) ... taps/2, target position p/4 after sample 0
    j = np.arange(-(taps // 2 - 1), taps // 2 + 1)
    out = []
    for p in (1, 2, 3):
        t = p / 4 - j
        s = np.sinc(t)
        half = taps / 2 + 0.5
        if window == "hann":
            w = 0.5 + 0.5 * np.cos(np.pi * t / half)
        else:
            w = kaiser_at(t, half, beta)
        h = s * w
        h_norm = h / h.sum()
        out.append((j, h_norm))
    return out


def response(phases):
    worst_low, worst_high = 0.0, 0.0
    rows = []
    for j, h in phases:
        H = np.abs(np.exp(-2j * np.pi * np.outer(f, j) / FS) @ h)
        db = 20 * np.log10(H)
        rows.append(db)
    rows = np.array(rows)
    return rows


for name, taps, win, beta in [("12 Hann (S1 v1)", 12, "hann", 0), ("12 Kaiser5", 12, "kaiser", 5),
                              ("16 Kaiser6", 16, "kaiser", 6), ("24 Kaiser7", 24, "kaiser", 7),
                              ("32 Kaiser8", 32, "kaiser", 8), ("64 Kaiser10 (meter)", 64, "kaiser", 10)]:
    r = response(design(taps, win, beta))
    def at(hz):
        k = int(round(hz / 50))
        return r[:, k].min()
    print(f"{name:22} min over phases: 10k {at(10000):+.3f}  12k {at(12000):+.3f}  16k {at(16000):+.3f}  "
          f"18k {at(18000):+.3f}  20k {at(20000):+.3f} dB; max overshoot {r.max():+.3f}")
