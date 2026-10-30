"""One factor at a time between repeat.py (a25345) and launchprobe.py (0deb83)."""
import hashlib
import os
import subprocess

S2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(S2)
ISO = os.path.join(S2, "bin", "isolate")
A = ["--in", "audio/dry.wav", "--type", "0", "--start", "10", "--preroll", "4", "--length", "5"]


def run(exe, args, out):
    subprocess.run([exe] + args + ["--out", out], check=True, capture_output=True)
    return hashlib.sha256(open(out, "rb").read()).hexdigest()[:6]


print("abs exe, lp.f32           :", run(ISO, A, "win/lp.f32"))
print("rel exe, lp.f32           :", run("bin/isolate", A, "win/lp.f32"))
print("abs exe, rep.f32          :", run(ISO, A, "win/rep.f32"))
print("rel exe, rep.f32          :", run("bin/isolate", A, "win/rep.f32"))
print("abs exe, x.f32 (new file) :", run(ISO, A, "win/x_new.f32"))
print("abs exe, rep.f32 again    :", run(ISO, A, "win/rep.f32"))
print("abs exe, lp.f32 again     :", run(ISO, A, "win/lp.f32"))
