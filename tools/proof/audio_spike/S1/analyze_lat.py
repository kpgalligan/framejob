"""Latency: lag of the cross-correlation peak of wet against dry, per 4096-sample
window (after 0.5 s), for both runs; plus the whole-signal lag.
Usage: python3 -I analyze_lat.py <S1 dir>
"""
import glob
import os
import re
import sys

import numpy as np

D = sys.argv[1]
W = 4096
reported = {}
for line in open(f"{D}/out/lat_reported.txt"):
    k, sig, rep = line.rstrip("\n").split("\t")
    reported[k] = rep.replace("reported ", "")


def lag(dry, wet, maxlag=2048):
    n = len(dry)
    nfft = 1 << (2 * n - 1).bit_length()
    c = np.fft.irfft(np.fft.rfft(wet, nfft) * np.conj(np.fft.rfft(dry, nfft)), nfft)
    # lags 0..maxlag (wet later than dry) and -64..-1
    cand = np.concatenate([c[nfft - 64:], c[:maxlag + 1]])
    lags = np.concatenate([np.arange(-64, 0), np.arange(0, maxlag + 1)])
    i = np.argmax(np.abs(cand))
    return int(lags[i]), float(np.abs(cand[i]) / np.sqrt(np.sum(dry ** 2) * np.sum(wet ** 2) + 1e-30))


dry = {s: np.fromfile(f"{D}/out/lat_{s}_dry.f32", dtype="<f4").astype(np.float64) for s in ["white", "quiet"]}
files = sorted(glob.glob(f"{D}/out/lat_*_r1.f32"))
print(f"{'subject':16} {'signal':6} {'whole':>6} {'corr':>6} {'window lags (distinct, both runs)':36} reported")
for f in files:
    m = re.match(r"lat_(white|quiet)_(.+)_r1\.f32", os.path.basename(f))
    sig, key = m.group(1), m.group(2)
    d = dry[sig]
    lags = []
    whole = None
    for r in (1, 2):
        w = np.fromfile(f"{D}/out/lat_{sig}_{key}_r{r}.f32", dtype="<f4").astype(np.float64)
        n = min(len(w), len(d))
        if r == 1:
            whole, corr = lag(d[24000:n], w[24000:n])
        for a in range(24000, n - W - 2048, W):
            lags.append(lag(d[a:a + W], w[a:a + W + 2048][:W + 2048] if False else w[a:a + W])[0])
    distinct = sorted(set(lags))
    desc = ", ".join(f"{v}×{lags.count(v)}" for v in distinct)
    print(f"{key:16} {sig:6} {whole:6d} {corr:6.3f} {desc:36} {reported.get(key, '')}")
