"""Uninitialised state? Vary argv length (a dummy argument), then lead every render with zeros."""
import hashlib
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

S2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(S2)
ISO = os.path.join(S2, "bin", "isolate")


def run(exe, args, out):
    subprocess.run([exe] + args + ["--out", out], check=True, capture_output=True)
    return hashlib.sha256(open(out, "rb").read()).hexdigest()[:6]


for t in "01":
    w = ["--in", "audio/dry.wav", "--type", t, "--start", "10", "--preroll", "4", "--length", "5"]
    hs = [run(ISO, w + ["--pad", "x" * k], "win/pad.f32") for k in (1, 7, 30, 100, 333)]
    print(f"type {t} window, argv padded 1/7/30/100/333 chars: {hs}")
    for lz in ("256", "1024", "4096"):
        hs = [run(ISO, w + ["--leadzeros", lz, "--pad", "x" * k], "win/lz.f32") for k in (1, 30, 333)]
        hr = run("bin/isolate", w + ["--leadzeros", lz], "win/lz_rel.f32")
        print(f"type {t} window with {lz} lead zeros, padded 1/30/333 + relative exe: {hs + [hr]}")
    lzfull = run(ISO, ["--in", "audio/dry.wav", "--type", t, "--leadzeros", "4096"], "win/lzfull.f32")
    a = ana.load("win/lzfull.f32")
    f = ana.load(f"det/t{t}_b4096_a.f32")
    print(f"type {t} full render with 4096 lead zeros: {lzfull}; identical to the plain full render {np.array_equal(a, f)}")
    v = ana.load("win/lz.f32")
    print(f"type {t} window (4096 lead zeros) vs full render's samples: identical {np.array_equal(v, f[480000:480000 + len(v)])}, "
          f"residual {ana.rms_db(v - f[480000:480000 + len(v)]) - ana.rms_db(v):.1f} dB")
