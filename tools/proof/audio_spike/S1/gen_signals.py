"""Synthetic fixtures for S1. Writes raw float32 then ffmpeg makes CAF (pcm_f32le).

Usage: python3 -I gen_signals.py <outdir>
"""
import json
import subprocess
import sys

import numpy as np

FS = 48000
out = sys.argv[1]
rng = np.random.default_rng(20261030)

FREQS = list(np.geomspace(20, 20000, 20))
# Anchor frequencies of the EQ settings under test, measured exactly at f0.
ANCHORS = [80.0, 60.0, 200.0, 1000.0, 8000.0, 2000.0]
SEG = 1.0  # seconds per step


def write(name, x, channels=1):
    raw = f"{out}/{name}.f32"
    x.astype("<f4").tofile(raw)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(FS), "-ac", str(channels),
         "-i", raw, "-c:a", "pcm_f32le", f"{out}/{name}.caf"], check=True)


# 1. Stepped sine: each frequency 1 s at amplitude 0.1 (-20 dBFS), 20 log-spaced then anchors.
steps = FREQS + ANCHORS
t = np.arange(int(SEG * FS)) / FS
stepped = np.concatenate([0.1 * np.sin(2 * np.pi * f * t) for f in steps])
write("stepped", stepped)
json.dump({"fs": FS, "seg": SEG, "freqs": steps, "n_log": len(FREQS)},
          open(f"{out}/stepped.json", "w"), indent=1)

# 2. White noise, -20 dBFS RMS, 10 s, mono and stereo.
white = rng.standard_normal(10 * FS) * 0.1
write("white", white)
stereo = (rng.standard_normal((10 * FS, 2)) * 0.1).reshape(-1)
write("white_stereo", stereo, channels=2)

# 3. Crest signal, 8 s, built to have true peaks well above sample peaks.
parts = []
n = np.arange(FS)
# (a) fs/4 sine at 45 degrees: samples at +-0.707 of the peak, so the true
#     peak is 3.01 dB above the sample peak. Sample peak 1.0 -> +3.01 dBTP.
parts.append(np.sqrt(2) * np.sin(2 * np.pi * 0.25 * n + np.pi / 4))
# (b) Alternating-pair impulses (+1,+1,-1,-1 bursts) in silence: strong
#     intersample overshoot.
b = np.zeros(FS)
for k in range(0, FS - 8, 2400):
    b[k:k + 4] = [1.0, 1.0, -1.0, -1.0]
parts.append(b)
# (c) Abrupt white-noise bursts at +6 dBFS peak-ish, 100 ms on / 150 ms off.
c = np.zeros(FS)
for k in range(0, FS, 12000):
    c[k:k + 4800] = rng.standard_normal(4800) * 0.7
parts.append(c)
# (d) 60 Hz tone at -6 dBFS with single-sample full-scale clicks.
d = 0.5 * np.sin(2 * np.pi * 60 * n / FS)
d[::4801] += 1.5
parts.append(d)
# (e) A quiet-to-loud step: -40 dBFS 1 kHz then +6 dBFS 1 kHz (attack).
e = np.concatenate([0.01 * np.sin(2 * np.pi * 1000 * n[:FS // 2] / FS),
                    2.0 * np.sin(2 * np.pi * 1000 * n[FS // 2:] / FS)])
parts.append(e)
# (f) Pink-ish noise (1/f by FFT shaping) at high level, 3 s.
w = rng.standard_normal(3 * FS)
W = np.fft.rfft(w)
f = np.fft.rfftfreq(len(w), 1 / FS)
W[1:] /= np.sqrt(f[1:] / 20)
W[0] = 0
pink = np.fft.irfft(W, len(w))
pink *= 1.8 / np.max(np.abs(pink))
parts.append(pink)
crest = np.concatenate(parts)
write("crest", crest)

# 4. 1 kHz tone, -20 dBFS, 4 s (zipper test).
tone = 0.1 * np.sin(2 * np.pi * 1000 * np.arange(4 * FS) / FS)
write("tone1k", tone)

# 5. Quiet white noise for latency of level-dependent stages: -40 dBFS RMS, 6 s.
write("white_quiet", rng.standard_normal(6 * FS) * 0.01)
print("ok", len(stepped) / FS, "s stepped;", len(crest) / FS, "s crest")
