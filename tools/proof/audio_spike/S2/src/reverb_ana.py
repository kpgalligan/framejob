"""Rule item 5d: does isolation reduce reverberation? Post-offset tails and the dry->output RIR's C50."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SR = ana.SR
dry = ana.load("audio/dry.f32")
N = len(dry)
pause, speech, lv, p10w = ana.classify(dry)

conds = [
    ("dry", "audio/dry.f32"),
    ("dry -> iso HQ", "det/t0_b4096_a.f32"),
    ("dry -> iso Voice", "det/t1_b4096_a.f32"),
    ("reverb (room + noise)", "audio/reverb.f32"),
    ("reverb -> iso HQ 100 %", "rev/t0.f32"),
    ("reverb -> iso Voice 100 %", "rev/t1.f32"),
    ("reverb -> iso HQ 50 %", "rev/t0_m50.f32"),
    ("reverb -> NR 50 %", "rev/nr50.f32"),
    ("reverb -> NR 100 %", "rev/nr100.f32"),
    ("room only (no noise)", "audio/reverb_nn.f32"),
    ("room only -> iso HQ", "rev/nn_t0.f32"),
    ("room only -> iso Voice", "rev/nn_t1.f32"),
    ("room only -> NR 100 %", "rev/nn_nr100.f32"),
]

# --- offsets on dry: 10 ms envelope
F = SR // 100
E = np.mean(ana.windows(dry, 0.01) ** 2, axis=1)
Edb = ana.db(E)
S = np.percentile(Edb, 10) + 20
# Deviation from the rule's wording (which found 1 offset in 30 s): an offset is the end of a
# speech run, the last 10 ms frame at or above S = p10 + 20 dB followed by >= 250 ms below S.
offsets = []
for k in range(10, len(E) - 25):
    if Edb[k - 1] >= S and np.all(Edb[k:k + 25] < S) and (not offsets or k - offsets[-1] > 30):
        offsets.append(k)
print(f"offsets found on dry: {len(offsets)} (speech threshold {S:.1f} dBFS per 10 ms); at s: "
      + ", ".join(f"{o / 100:.2f}" for o in offsets))


def tail(a):
    Ea = np.mean(ana.windows(a, 0.01) ** 2, axis=1)
    pre = np.array([Ea[o - 10:o].sum() for o in offsets])
    post = np.array([Ea[o + 5:o + 25].sum() for o in offsets])
    per = ana.db(post / np.maximum(pre, 1e-30))
    return ana.db(post.sum() / pre.sum()), np.median(per)


# --- RIR from dry to output, Welch H = Sxy / Sxx over 100 Hz - 8 kHz
NSEG = 1 << 17
HOP = NSEG // 2
win = np.hanning(NSEG)
f = np.fft.rfftfreq(NSEG, 1 / SR)
band = np.clip((f - 80) / 40, 0, 1) * np.clip((8500 - f) / 1000, 0, 1)


def rir(a):
    Sxx = np.zeros(len(f))
    Sxy = np.zeros(len(f), dtype=complex)
    for s in range(0, N - NSEG + 1, HOP):
        X = np.fft.rfft(dry[s:s + NSEG] * win)
        Y = np.fft.rfft(a[s:s + NSEG] * win)
        Sxx += np.abs(X) ** 2
        Sxy += Y * np.conj(X)
    H = Sxy / np.maximum(Sxx, 1e-30) * band
    return np.fft.irfft(H, NSEG)


def c50(h):
    e = h[:SR] ** 2
    early = e[: int(0.05 * SR)].sum() + (h[-48:] ** 2).sum()  # a few samples of pre-ringing count as direct
    late = e[int(0.05 * SR):].sum()
    return 10 * np.log10(early / late)


def t20(h):
    e = h[:SR] ** 2
    edc = np.cumsum(e[::-1])[::-1]
    edb = 10 * np.log10(edc / edc[0])
    i5, i25 = np.argmax(edb <= -5), np.argmax(edb <= -25)
    return 3 * (i25 - i5) / SR if i25 > i5 else float("nan")


def late_db(h):
    """Energy 50-500 ms relative to the direct (0-2 ms) part."""
    e = h ** 2
    return 10 * np.log10(e[int(0.05 * SR):int(0.5 * SR)].sum() / (e[:96].sum() + e[-48:].sum()))


# reference: the true RIR, band-limited the same way
true = np.zeros(NSEG)
true[:SR] = ana.load("audio/rir.f32")
true_bl = np.fft.irfft(np.fft.rfft(true) * band, NSEG)
print(f"true RIR band-limited: C50 {c50(true_bl):.1f} dB, T20 RT60 {t20(true_bl):.2f} s, late {late_db(true_bl):.1f} dB")
print()
print("| Condition | tail 50-250 ms after offsets (sum) | median per offset | est. RIR C50 | est. RT60 (T20) | late 50-500 ms vs direct | pause RMS |")
print("|---|---|---|---|---|---|---|")
for name, path in conds:
    a = ana.load(path)
    L, _, _ = ana.xcorr_lag(dry, a[:N], maxlag=8000)
    a = ana.align(a, L, N)
    ts, tm = tail(a)
    h = rir(a)
    print(f"| {name} | {ts:.1f} dB | {tm:.1f} dB | {c50(h):.1f} dB | {t20(h):.2f} s | {late_db(h):.1f} dB | {ana.class_rms(a, pause):.1f} |")
