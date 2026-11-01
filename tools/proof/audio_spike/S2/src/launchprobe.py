"""Which launch factor changes the unit's output? Same render, launched different ways."""
import hashlib
import os
import subprocess
import sys

S2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(S2)
ISO = os.path.join(S2, "bin", "isolate")
ARGS = ["--in", "audio/dry.wav", "--type", "0", "--start", "10", "--preroll", "4", "--length", "5"]


def h(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:6]


ways = {
    "subprocess, capture": lambda o: subprocess.run([ISO] + ARGS + ["--out", o], capture_output=True),
    "subprocess, capture text cwd": lambda o: subprocess.run([ISO] + ARGS + ["--out", o], capture_output=True, text=True, cwd=S2),
    "subprocess, inherit stdout": lambda o: subprocess.run([ISO] + ARGS + ["--out", o], stdout=subprocess.DEVNULL),
    "subprocess, stdin devnull": lambda o: subprocess.run([ISO] + ARGS + ["--out", o], capture_output=True, stdin=subprocess.DEVNULL),
    "os.system": lambda o: os.system(" ".join([ISO] + ARGS + ["--out", o, ">/dev/null"])),
}
for rnd in range(2):
    for name, fn in ways.items():
        out = f"win/lp.f32"
        fn(out)
        print(f"round {rnd} {name}: {h(out)}")
