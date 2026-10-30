"""The start of a render: what an unconverged window sounds like, and whether a pre-roll of zeros helps."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

S2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(S2)
dry = ana.load("audio/dry.f32")
for t in "01":
    full = ana.load(f"det/t{t}_b4096_a.f32")
    ref = full[480000:480000 + 96000]
    d = dry[480000:480000 + 96000]
    rows = {}
    for tag, extra in (("no pre-roll", ["--preroll", "0"]), ("4 s of zeros", ["--preroll", "4", "--zeropre"]),
                       ("0.5 s media", ["--preroll", "0.5"]), ("2 s media", ["--preroll", "2"])):
        out = f"win/warm_t{t}.f32"
        subprocess.run(["bin/isolate", "--in", "audio/dry.wav", "--out", out, "--type", t, "--start", "10",
                        "--length", "2"] + extra, check=True, capture_output=True)
        rows[tag] = ana.load(out)
    print(f"type {t}: per 100 ms from 10.0 s, level dBFS (dry | converged | each start)")
    print("| ms | dry | converged | " + " | ".join(rows) + " |")
    print("|---|---|---|" + "---|" * len(rows))
    for k in range(0, 15):
        s = slice(k * 4800, (k + 1) * 4800)
        print(f"| {k * 100} | {ana.rms_db(d[s]):.1f} | {ana.rms_db(ref[s]):.1f} | "
              + " | ".join(f"{ana.rms_db(v[s]):.1f}" for v in rows.values()) + " |")
    for tag, v in rows.items():
        print(f"  {tag}: residual vs converged, first 1 s {ana.rms_db(v[:48000] - ref[:48000]) - ana.rms_db(ref[:48000]):.1f} dB, "
              f"second 1 s {ana.rms_db(v[48000:] - ref[48000:]) - ana.rms_db(ref[48000:]):.1f} dB")
