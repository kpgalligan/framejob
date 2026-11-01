"""Formats: measured lag vs reported, bandwidth kept, stereo independence."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def hi(x, sr, f0):
    X = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / sr)
    return 10 * np.log10(X[f >= f0].sum() / X.sum())


for t in "01":
    for name in ["dry44k", "dry16k", "dry96k"]:
        d, sr = ana.load_wav(f"audio/{name}.wav")
        y = ana.load(f"fmt/t{t}_{name}.f32")
        rep = json.load(open(f"fmt/t{t}_{name}.json"))["runs"][0]
        L, Lf, r = ana.xcorr_lag(d, y[: len(d) + sr], maxlag=sr // 2)
        a = ana.align(y, L, len(d))
        s16 = f"{hi(d, sr, 16000):.1f} -> {hi(a, sr, 16000):.1f}" if sr > 32000 else "n/a"
        print(f"type {t} {name}: reported {rep['latency_frames']} measured {L} ({Lf:.2f}) corr {r:.3f}; "
              f"energy share >8k {hi(d, sr, 8000):.1f} -> {hi(a, sr, 8000):.1f} dB; >16k {s16}")
    d = ana.load("audio/dry.f32")
    mono = ana.load(f"audio/probe_{'hq' if t == '0' else 'v'}.f32")
    Lm, _, _ = ana.xcorr_lag(d, mono[: len(d) + 48000])
    am = ana.align(mono, Lm, len(d))
    print(f"type {t} dry48k mono: measured {Lm}; energy share >8k {hi(d, 48000, 8000):.1f} -> {hi(am, 48000, 8000):.1f} dB; "
          f">16k {hi(d, 48000, 16000):.1f} -> {hi(am, 48000, 16000):.1f}")
    for name in ["stereo_same", "stereo_lr"]:
        y = ana.load(f"fmt/t{t}_{name}.f32", 2)
        rep = json.load(open(f"fmt/t{t}_{name}.json"))["runs"][0]
        L0, _, _ = ana.xcorr_lag(d, y[: len(d) + 48000, 0])
        ref1 = d if name == "stereo_same" else d[::-1].copy()
        L1, _, _ = ana.xcorr_lag(ref1, y[: len(d) + 48000, 1])
        a0 = ana.align(y[:, 0], L0, len(d))
        print(f"type {t} {name}: reported {rep['latency_frames']} measured L {L0} R {L1}; "
              f"L==R {np.array_equal(y[:, 0], y[:, 1])}; L vs mono render (both aligned) residual "
              f"{ana.rms_db(a0 - am) - ana.rms_db(am):.1f} dB")
