"""Runs bin/isolate batches for spike S2. Usage: run.py <batch>"""
import hashlib
import json
import os
import subprocess
import sys

S2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ISO = os.path.join(S2, "bin", "isolate")


def iso(args, out_json=None):
    r = subprocess.run([ISO] + args, cwd=S2, capture_output=True, text=True)
    if r.returncode != 0:
        print("FAILED", args, r.stderr[-2000:], file=sys.stderr)
        return None
    j = json.loads(r.stdout.strip().splitlines()[-1])
    if out_json:
        with open(os.path.join(S2, out_json), "w") as f:
            json.dump(j, f, indent=1)
    return j


def sha(path):
    with open(os.path.join(S2, path), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:16]


def loadavg():
    return " ".join(f"{x:.2f}" for x in os.getloadavg())


def det():
    os.makedirs(os.path.join(S2, "det"), exist_ok=True)
    for t in ("0", "1"):
        rows = []
        for tag, extra in [
            ("b4096_a", ["--repeat", "2"]),
            ("b4096_b", ["--repeat", "2"]),
            ("b256", ["--block", "256", "--maxframes", "256"]),
            ("b1000", ["--block", "1000", "--maxframes", "4096"]),
            ("b512m4096", ["--block", "512", "--maxframes", "4096"]),
        ]:
            out = f"det/t{t}_{tag}.f32"
            j = iso(["--in", "audio/dry.wav", "--out", out, "--type", t] + extra, out.replace(".f32", ".json"))
            r2 = j["runs"][1] if len(j["runs"]) > 1 else {}
            rows.append((tag, sha(out), j["runs"][0]["latency_frames"], r2.get("identical_to_first"), r2.get("max_abs_diff_to_first")))
        for r in rows:
            print("type", t, *r)


def speed():
    os.makedirs(os.path.join(S2, "speed"), exist_ok=True)
    for t in ("0", "1"):
        for k in range(3):
            before = loadavg()
            j = iso(["--in", "audio/dry.wav", "--out", f"speed/t{t}_{k}.f32", "--type", t])["runs"][0]
            after = loadavg()
            print(f"type {t} run {k}: wall {j['wall_s']:.3f} s setup {j['setup_s']:.3f} first_call {j['first_call_s']*1000:.2f} ms "
                  f"cpu {j['cpu_s']:.3f} s  xRT {30.357333/j['wall_s']:.1f}  load {before} -> {after}")


def window():
    os.makedirs(os.path.join(S2, "win"), exist_ok=True)
    for t in ("0", "1"):
        for pre in ("0", "0.1", "0.25", "0.5", "1", "2", "4"):
            iso(["--in", "audio/dry.wav", "--out", f"win/t{t}_pre{pre}.f32", "--type", t,
                 "--start", "10", "--preroll", pre, "--length", "5"])
        # also a window starting at 0 with no preroll vs full (sanity: identical?)
        iso(["--in", "audio/dry.wav", "--out", f"win/t{t}_start0.f32", "--type", t,
             "--start", "0", "--preroll", "0", "--length", "5"])


def formats():
    os.makedirs(os.path.join(S2, "fmt"), exist_ok=True)
    for t in ("0", "1"):
        for name in ("dry44k", "dry16k", "dry96k", "stereo_same", "stereo_lr"):
            j = iso(["--in", f"audio/{name}.wav", "--out", f"fmt/t{t}_{name}.f32", "--type", t, "--raw"],
                    f"fmt/t{t}_{name}.json")
            r = j["runs"][0] if j else None
            print("type", t, name, "OK" if r else "FAILED",
                  (r["sr"], r["channels"], r["latency_frames"], round(r["latency_s"] * 1000, 3), r["manual_format"]) if r else "")


def mixes():
    os.makedirs(os.path.join(S2, "mix"), exist_ok=True)
    for t in ("0", "1"):
        for m in ("100", "50", "0", "-100", "-50"):
            iso(["--in", "audio/dry.wav", "--out", f"mix/t{t}_m{m}.f32", "--type", t, "--mix", m])


def reverb():
    os.makedirs(os.path.join(S2, "rev"), exist_ok=True)
    for t in ("0", "1"):
        iso(["--in", "audio/reverb.wav", "--out", f"rev/t{t}.f32", "--type", t])
        iso(["--in", "audio/reverb_nn.wav", "--out", f"rev/nn_t{t}.f32", "--type", t])
        iso(["--in", "audio/reverb.wav", "--out", f"rev/t{t}_m50.f32", "--type", t, "--mix", "50"])


if __name__ == "__main__":
    globals()[sys.argv[1]]()
