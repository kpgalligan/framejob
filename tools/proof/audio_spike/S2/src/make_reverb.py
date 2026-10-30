"""The reverberant sample: dry * synthetic RIR (RT60 0.6 s, DRR 0 dB) + pink noise at -60 dBFS."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SR = ana.SR
rng = np.random.default_rng(20261030)

# RIR
n = SR  # 1.0 s
t = np.arange(n) / SR
rt60 = 0.6
env = np.exp(-6.907755 * t / rt60)  # amplitude down 60 dB at rt60
tail = rng.standard_normal(n) * env
tail[: int(0.0025 * SR)] = 0
tail *= np.sqrt(1.0 / np.sum(tail ** 2))  # tail energy = direct energy -> DRR 0 dB
rir = tail.copy()
rir[0] = 1.0
e = rir ** 2
c50 = 10 * np.log10(e[: int(0.05 * SR)].sum() / e[int(0.05 * SR):].sum())
# Schroeder EDC RT60 check (T20 fit -5..-25 dB)
edc = np.cumsum(e[::-1])[::-1]
edc_db = 10 * np.log10(edc / edc[0])
i5, i25 = np.argmax(edc_db <= -5), np.argmax(edc_db <= -25)
t20 = 3 * (i25 - i5) / SR
rir.astype("<f4").tofile("audio/rir.f32")

dry = ana.load("audio/dry.f32")
nfft = 1 << (len(dry) + n).bit_length()
wet = np.fft.irfft(np.fft.rfft(dry, nfft) * np.fft.rfft(rir, nfft), nfft)[: len(dry)]

pause, speech, lv, p10 = ana.classify(dry)
g = 10 ** ((ana.class_rms(dry, speech) - ana.class_rms(wet, speech)) / 20)
wet *= g

# pink noise, -60 dBFS RMS
w = rng.standard_normal(len(dry))
W = np.fft.rfft(w)
f = np.fft.rfftfreq(len(dry), 1 / SR)
W[1:] /= np.sqrt(f[1:])
W[0] = 0
pink = np.fft.irfft(W, len(dry))
pink *= 10 ** (-60 / 20) / np.sqrt(np.mean(pink ** 2))
rev = wet + pink
rev.astype("<f4").tofile("audio/reverb.f32")
wet.astype("<f4").tofile("audio/reverb_nn.f32")  # control: the same room, no added noise
info = {
    "rir_c50_db": round(c50, 2), "rir_t20_rt60_s": round(t20, 3), "speech_gain_db": round(20 * np.log10(g), 2),
    "reverb_peak_dbfs": round(20 * np.log10(np.abs(rev).max()), 2), "dry_peak_dbfs": round(20 * np.log10(np.abs(dry).max()), 2),
    "pink_rms_dbfs": -60, "reverb_pause_rms": round(ana.class_rms(rev, pause), 2), "dry_pause_rms": round(ana.class_rms(dry, pause), 2),
}
json.dump(info, open("audio/reverb_info.json", "w"), indent=1)
print(info)
