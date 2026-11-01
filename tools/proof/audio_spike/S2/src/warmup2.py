"""HQ, window at 10 s with no pre-roll: is the second second shifted against the converged render?"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
full = ana.load("det/t0_b4096_a.f32")
dry = ana.load("audio/dry.f32")
for pre in ("0", "0.5", "1", "2", "4"):
    subprocess.run(["bin/isolate", "--in", "audio/dry.wav", "--out", "win/w2.f32", "--type", "0", "--start", "10",
                    "--length", "5", "--preroll", pre], check=True, capture_output=True)
    v = ana.load("win/w2.f32")
    ref = full[480000:480000 + len(v)]
    d = dry[480000:480000 + len(v)]
    cells = []
    for k in range(5):
        s = slice(k * 48000, (k + 1) * 48000)
        L, Lf, r = ana.xcorr_lag(ref[s], v[s], maxlag=6000)
        Ld, _, rd = ana.xcorr_lag(d[s], v[s], maxlag=6000)
        cells.append(f"{k}s: vs conv lag {L} r {r:.2f} res {ana.rms_db(v[s] - ref[s]) - ana.rms_db(ref[s]):.0f} dB; vs dry lag {Ld}")
    print(f"pre {pre}:", " | ".join(cells))
