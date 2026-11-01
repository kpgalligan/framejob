"""Does the launch identity also flip the FULL render, and how large is the window difference?"""
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
    full = ["--in", "audio/dry.wav", "--type", t]
    print(f"type {t} full render: abs {run(ISO, full, 'win/f_abs.f32')}, rel {run('bin/isolate', full, 'win/f_rel.f32')}, "
          f"./rel {run('./bin/isolate', full, 'win/f_dot.f32')}")
    a, r = ana.load("win/f_abs.f32"), ana.load("win/f_rel.f32")
    print(f"   full abs vs rel: identical {np.array_equal(a, r)}, residual {ana.rms_db(a - r) - ana.rms_db(a):.1f} dB, max|d| {np.abs(a - r).max():.1e}")
    w = ["--in", "audio/dry.wav", "--type", t, "--start", "10", "--preroll", "4", "--length", "5"]
    print(f"type {t} window: abs {run(ISO, w, 'win/w_abs.f32')}, rel {run('bin/isolate', w, 'win/w_rel.f32')}, "
          f"./rel {run('./bin/isolate', w, 'win/w_dot.f32')}")
    a, r = ana.load("win/w_abs.f32"), ana.load("win/w_rel.f32")
    print(f"   window abs vs rel: identical {np.array_equal(a, r)}, residual {ana.rms_db(a - r) - ana.rms_db(a):.1f} dB, max|d| {np.abs(a - r).max():.1e}")
