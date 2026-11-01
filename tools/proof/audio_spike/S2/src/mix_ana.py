"""Rule item 6: the unit's own wet/dry, a host-side mix with and without the lag removed, phase coherence."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SR = ana.SR
dry = ana.load("audio/dry.f32")
N = len(dry)
pause, speech, lv, p10 = ana.classify(dry)
TRUE_LAG = {"0": 4440, "1": 2704}
REPORTED = {"0": 4440, "1": 2705}


def resid(a, b):
    return ana.rms_db(a - b) - ana.rms_db(b)


def transfer(x, y, mask, nseg=1 << 15):
    """|Y/X| (dB) per bin over the masked 400 ms windows' span, Welch over contiguous speech stretches."""
    W = ana.windows(x)
    w = W.shape[1]
    # concatenate the masked windows (speech) into one signal for each, with the same cuts
    xs = np.concatenate([x[i * w:(i + 1) * w] for i in np.where(mask)[0]])
    ys = np.concatenate([y[i * w:(i + 1) * w] for i in np.where(mask)[0]])
    win = np.hanning(nseg)
    Sxx = 0
    Sxy = 0
    Syy = 0
    for s in range(0, len(xs) - nseg + 1, nseg // 4):
        X = np.fft.rfft(xs[s:s + nseg] * win)
        Y = np.fft.rfft(ys[s:s + nseg] * win)
        Sxx = Sxx + np.abs(X) ** 2
        Syy = Syy + np.abs(Y) ** 2
        Sxy = Sxy + Y * np.conj(X)
    f = np.fft.rfftfreq(nseg, 1 / SR)
    return f, Sxx, Syy, Sxy


def third_octave_smooth(f, mag_db, lo=100, hi=8000):
    centers = 1000 * 2 ** (np.arange(-10, 10) / 3)
    centers = centers[(centers >= lo) & (centers <= hi)]
    vals = []
    for c in centers:
        sel = (f >= c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))
        vals.append(10 * np.log10(np.mean(10 ** (mag_db[sel] / 10))))
    return centers, np.array(vals)


for t, label in (("0", "HQ"), ("1", "Voice")):
    L = TRUE_LAG[t]
    shift = L - REPORTED[t]  # renders below were compensated by the REPORTED latency
    wet = ana.align(ana.load(f"mix/t{t}_m100.f32"), shift, N)
    m50 = ana.align(ana.load(f"mix/t{t}_m50.f32"), shift, N)
    m0 = ana.align(ana.load(f"mix/t{t}_m0.f32"), shift, N)
    mm100 = ana.align(ana.load(f"mix/t{t}_m-100.f32"), shift, N)
    mm50 = ana.align(ana.load(f"mix/t{t}_m-50.f32"), shift, N)
    print(f"== {label} (true lag {L}, reported {REPORTED[t]})")
    print(f"  mix 0 %: identical to dry? {np.array_equal(m0[:N - 10], dry[:N - 10])}; residual vs dry {resid(m0, dry):.1f} dB; max|d| {np.abs(m0 - dry).max():.1e}")
    host = 0.5 * dry + 0.5 * wet
    print(f"  mix 50 % vs 0.5*dry + 0.5*wet100 (aligned): residual {resid(m50, host):.1f} dB")
    Lm, _, _ = ana.xcorr_lag(dry, m50 - 0.5 * wet, maxlag=8000)
    print(f"  the unit's internal dry path at 50 %: lag of (m50 - 0.5*wet) vs dry = {Lm} (0 = compensated inside the unit)")
    print(f"  mix -100 % vs dry - wet100 (the removed part): residual {resid(mm100, dry - wet):.1f} dB; "
          f"rms {ana.rms_db(mm100):.1f} (dry {ana.rms_db(dry):.1f}); speech-window rms {ana.class_rms(mm100, speech):.1f}, "
          f"pause rms {ana.class_rms(mm100, pause):.1f}")
    print(f"  mix -50 % vs 0.5*dry - 0.5*wet: residual {resid(mm50, 0.5 * dry - 0.5 * wet):.1f} dB;  vs 0.5*dry + 0.5*(dry - wet): "
          f"{resid(mm50, 0.5 * dry + 0.5 * (dry - wet)):.1f} dB")

    # coherence and phase of aligned wet vs dry over speech, per octave
    f, Sxx, Syy, Sxy = transfer(dry, wet, speech)
    cells = []
    for fc in ana.OCTAVES[1:8]:
        sel = (f >= fc / np.sqrt(2)) & (f < fc * np.sqrt(2))
        coh = np.abs(Sxy[sel].sum()) ** 2 / (Sxx[sel].sum() * Syy[sel].sum())
        rc = np.real(Sxy[sel]).sum() / np.sqrt(Sxx[sel].sum() * Syy[sel].sum())
        cells.append(f"{fc}: {coh:.3f}/{rc:+.3f}")
    print("  aligned wet vs dry over speech, per octave (|coherence|^2 / real normalised cross-spectrum):", "; ".join(cells))

    # host-side 50 % mixes: aligned and not
    raw = np.concatenate([np.zeros(L), wet])[:N]  # the wet as rendered, latency not removed
    for name, mix in (("aligned", host), ("latency NOT removed", 0.5 * dry + 0.5 * raw)):
        f, Sxx, Syy, Sxy = transfer(dry, mix, speech)
        mag = 10 * np.log10(np.abs(Sxy) ** 2 / Sxx ** 2)
        sel = (f >= 100) & (f <= 8000)
        sel2 = (f >= 250) & (f <= 4000)
        c, sm = third_octave_smooth(f, mag)
        raw_spread = np.percentile(mag[sel2], 97.5) - np.percentile(mag[sel2], 2.5)
        print(f"  host 50 % mix, {name}: 1/3-oct ripple 100 Hz-8 kHz {sm.max() - sm.min():.2f} dB "
              f"(range {sm.min():+.1f}..{sm.max():+.1f}); per-bin 95 % spread 250 Hz-4 kHz {raw_spread:.1f} dB; "
              f"deepest bin {mag[sel2].min():.1f} dB; residual vs the unit's own 50 % {resid(mix, m50):.1f} dB")
    print(f"    expected notch spacing if unaligned: {SR / L:.1f} Hz (first notch {SR / (2 * L):.1f} Hz): a {1000 * L / SR:.1f} ms echo")
