"""Where in the crest signal does the own limiter's output exceed the ceiling?"""
import sys

import numpy as np

D = sys.argv[1]
FS = 48000
x = np.fromfile(f"{D}/out/lim_crest_own.f32", dtype="<f4").astype(np.float64)
dry = np.fromfile(f"{D}/out/lim_crest_dry.f32", dtype="<f4").astype(np.float64)
ceil = 10 ** (-1 / 20)
# Part a: steady fs/4 at 45 degrees. Envelope of sample values over time.
for a, b in [(200, 400), (1000, 1200), (20000, 20008), (47000, 47008)]:
    print(f"samples {a}..{b}: max|y| {np.max(np.abs(x[a:b])):.5f}  ({20*np.log10(np.max(np.abs(x[a:b]))):.3f} dBFS)")
print("first 8 outputs after the delay:", np.round(x[105:115], 4))
print("dry 0..8:", np.round(dry[:8], 4))
# Ideal: steady output sample magnitude = ceil / sqrt(2) = 0.630
print(f"ideal steady sample magnitude {ceil/np.sqrt(2):.5f}")
# Half-sample interpolation of the steady output by ideal sinc (long):
seg = x[10000:20000]
k = np.arange(-200, 201)
h = np.sinc(k + 0.5) * np.kaiser(401, 12)
y = np.convolve(seg, h / h.sum(), mode="valid")
print(f"half-sample peak of steady part: {20*np.log10(np.max(np.abs(y))):.3f} dBTP")
