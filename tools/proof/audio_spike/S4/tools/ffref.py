"""ffmpeg ebur128 over a sample-exact window of a raw f32le file.

usage: ffref.py <raw.f32> <rate> <channels> <windows file> [--reverse] [--filter <extra af before ebur128>]

Each window "start end" (seconds) is cut with atrim by sample index (the same
rounding lcache uses: round(t*rate)). The window is scaled by an exact power
of two so its peak lands in [0.5, 1) before ebur128, because ebur128's
metadata prints the linear true peak with three decimals; the scale is taken
back out of both answers exactly (20*log10(2^k)). Prints I (LUFS) and true
peak (dBTP) per window from the LAST metadata frame.
"""
import math
import subprocess
import sys
import tempfile

import numpy as np

raw, rate, ch, wfile = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
reverse = "--reverse" in sys.argv
extra = sys.argv[sys.argv.index("--filter") + 1] if "--filter" in sys.argv else None
x = np.fromfile(raw, dtype=np.float32).reshape(-1, ch)
if reverse:
    x = x[::-1].copy()
    src = tempfile.NamedTemporaryFile(suffix=".f32", delete=False).name
    x.tofile(src)
else:
    src = raw
for line in open(wfile):
    p = line.split()
    if len(p) != 2:
        continue
    a, b = float(p[0]), float(p[1])
    fa, fb = int(round(a * rate)), min(len(x), int(round(b * rate)))
    peak = float(np.abs(x[fa:fb]).max())
    k = math.floor(math.log2(0.9 / peak)) if peak > 0 else 0
    scale = 2.0 ** k
    meta = tempfile.NamedTemporaryFile(suffix=".txt", delete=False).name
    chain = f"atrim=start_sample={fa}:end_sample={fb},asetpts=PTS-STARTPTS,volume={scale}"
    if extra:
        chain += "," + extra
    chain += f",ebur128=peak=true:metadata=1,ametadata=mode=print:file={meta}"
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-v", "error", "-f", "f32le", "-ar", str(rate), "-ac", str(ch),
         "-i", src, "-af", chain, "-f", "null", "-"], check=True)
    I = tp = None
    for l in open(meta):
        if l.startswith("lavfi.r128.I="):
            I = float(l.split("=")[1])
        if l.startswith("lavfi.r128.true_peak="):
            tp = float(l.split("=")[1])
    shift = 20 * math.log10(scale)
    I = None if I is None or I <= -70 else I - shift
    tpdb = 20 * math.log10(tp) - shift if tp else float("-inf")
    print(f"{a:.6f} {b:.6f} ffI {I if I is None else f'{I:.3f}'} ffTP {tpdb:.3f} (scale 2^{k})")
