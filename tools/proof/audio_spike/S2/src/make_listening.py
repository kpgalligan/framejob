"""Listening files: every condition aligned to dry, one fixed gain (+17.6 dB, the dry's peak to -1 dBFS), 24-bit WAV."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.makedirs("listen", exist_ok=True)
dry = ana.load("audio/dry.f32")
N = len(dry)
GAIN_DB = -1 - 20 * np.log10(np.abs(dry).max())
g = 10 ** (GAIN_DB / 20)


def aligned(path):
    y = ana.load(path)
    L, _, _ = ana.xcorr_lag(dry, y[:N], maxlag=8000)
    return ana.align(y, L, N)


hq = aligned("det/t0_b4096_a.f32")
items = [
    ("01-dry", dry),
    ("02-isolation-hq-100", hq),
    ("03-isolation-hq-50", aligned("mix/t0_m50.f32")),
    ("04-isolation-voice-100", aligned("det/t1_b4096_a.f32")),
    ("05-noise-reduction-50", aligned("nr/a50.f32")),
    ("06-noise-reduction-100", aligned("nr/a100.f32")),
    ("07-isolation-hq-what-it-removed", aligned("mix/t0_m-100.f32")),
    ("08-mix-50-latency-not-removed-echo", 0.5 * dry + 0.5 * np.concatenate([np.zeros(4440), hq])[:N]),
    ("09-reverb-room-and-noise", ana.load("audio/reverb.f32")),
    ("10-reverb-isolation-hq-100", aligned("rev/t0.f32")),
    ("11-reverb-isolation-hq-50", aligned("rev/t0_m50.f32")),
    ("12-reverb-isolation-voice-100", aligned("rev/t1.f32")),
    ("13-reverb-noise-reduction-100", aligned("rev/nr100.f32")),
]


def write24(path, x):
    q = np.clip(np.round(x * 8388607), -8388608, 8388607).astype(np.int32)
    b = bytearray()
    for v in q:
        b += int(v & 0xFFFFFF).to_bytes(3, "little")
    hdr = b"RIFF" + struct.pack("<I", 36 + len(b)) + b"WAVE"
    hdr += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, 48000, 48000 * 3, 3, 24)
    hdr += b"data" + struct.pack("<I", len(b))
    open(path, "wb").write(hdr + bytes(b))


print(f"gain {GAIN_DB:+.1f} dB on every file")
for name, x in items:
    y = x * g
    pk = 20 * np.log10(max(np.abs(y).max(), 1e-12))
    write24(f"listen/{name}.wav", y)
    print(f"{name}.wav  peak {pk:+.1f} dBFS{'  CLIPPED' if pk > 0 else ''}")
