"""The EQ, hum notch and channel pick's probe (road map "audio" AP3, spec §11
AU-30..AU-36, AU-39).

`eq_probe.swift` compiled with app/Sources through swift_build: the product's
`AudioEQDesign`, `AudioEQStage`, chain, tap context, schedule, curve view and
`ClipLoudness.ChannelMatrix`.

  Q1  every slot type's and each hum harmonic's |H| at 20 log-spaced
      frequencies (and each harmonic, ± f0/20) equals THIS script's numpy RBJ
      within 0.001 dB at 48 and 44.1 kHz (Butterworth section Qs; the hum's
      Q = 10·k / A, AU-33), the designed positions the oracle's; and the whole
      hum cascade at 48 kHz, 60×4 at 30 dB and 50×8 at 48 dB, reads −depth ±0.1
      dB at every k·f0 and within 0.3 dB of 0 midway between harmonics.
  Q2  HP and LP at 12 and 24 read −3.010 dB at the corner, and the bilinear
      Butterworth of their order an octave beyond.
  Q3  512, 4096 and irregular blocks byte-identical through AudioDSPChain,
      settings and picks changing at cuts.
  Q4  reset() gives a fresh stage's bytes, both channels.
  Q5  flat, bypassed and absent settings design nothing; the clip is inert;
      nil settings leave every byte.
  Q6  picks sample-identical to their source channels; mono after left is L; a
      one-channel track untouched.
  Q7  the drawn curve equals the stage's measured steady-state response within
      0.01 dB.
  Q8  ClipLoudness on a voice-on-L stereo file: left = both + 3.01 LU (±0.01),
      swapped = both.
  Q9  the tap context under a muted AVPlayer against an AVAssetReader: the same
      samples within the first 4 s, with EQ, hum and a left pick.
  Q10 µs per 1024 stereo frames at all 17 positions, reported.
  Q11 on a noise-reduced track the head stages switch at the head lookup's cut.

--mutants runs M1..M10, each over its own copy of app/Sources, scored killed
when one of its named rows fails; build failures are scored. M11 (the patch
template without `hum`) is by hand against core/tests/audio_eq.rs. Needs
ffmpeg, numpy and samples/Rode-usb-mic.m4a. Output is under
tools/proof/work/eq-probe.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np

import swift_build

ROOT = Path(__file__).resolve().parents[2]
RODE = ROOT / "samples/Rode-usb-mic.m4a"
WORK = ROOT / "tools/proof/work/eq-probe"
FIXTURES = WORK / "fixtures"
FS = 48000
ROWS = [f"Q{n}" for n in range(1, 12)]

# (name, killing rows, [(file, old, new), …])
MUTANTS = [
    ("M1 butterworth-as-lr", ["Q1", "Q2"], [
        ("AudioBiquad.swift",
         "return index == 0 ? 0.541_196_100_146_197 : 1.306_562_964_876_376_6",
         "return 0.707_106_781_186_547_6")]),
    ("M2 slope-ignored", ["Q2"], [
        ("AudioBiquad.swift", "sections: p.slope >= 18 ? 2 : 1", "sections: 1")]),
    ("M3 state-reset-each-run", ["Q3"], [
        ("AudioEQStage.swift",
         "        guard frames > 0, used > 0 else { return }\n",
         "        guard frames > 0, used > 0 else { return }\n"
         "        state.update(repeating: 0, count: stateCount)\n")]),
    ("M4 reset-misses-a-channel", ["Q4"], [
        ("AudioEQStage.swift",
         "    func reset() {\n        state.update(repeating: 0, count: stateCount)",
         "    func reset() {\n        state.update(repeating: 0, count: AudioEQDesign.positions * 2)")]),
    ("M5 hum-constant-q", ["Q1"], [
        ("AudioBiquad.swift", "q: 10 * Double(k) / a,", "q: 10 / a,")]),
    ("M6 pick-after-fold", ["Q6"], [
        ("AudioDSP.swift",
         "        if head.channels != .both, count >= 2 {\n"
         "            pick(channels, count: count, frames: frames, choice: head.channels)\n"
         "        }\n", ""),
        ("AudioDSP.swift",
         "        if params.mono, count >= 2 { fold(channels, count: count, frames: frames) }\n",
         "        if params.mono, count >= 2 { fold(channels, count: count, frames: frames) }\n"
         "        if head.channels != .both, count >= 2 {\n"
         "            pick(channels, count: count, frames: frames, choice: head.channels)\n"
         "        }\n")]),
    ("M7 head-lead-dropped", ["Q11"], [
        ("AudioTap.swift", "if track.headLead != 0 {", "if track.headLead == -1 {")]),
    ("M8 matrix-ignores-pick", ["Q8"], [
        ("ClipLoudness.swift", "switch props.channels {", "switch AudioChannelChoice.both {")]),
    ("M9 curve-at-44.1k", ["Q7"], [
        ("AudioEQCurveView.swift", "static let sampleRate = 48_000.0",
         "static let sampleRate = 44_100.0")]),
    ("M10 hum-q-not-depth-scaled", ["Q1"], [
        ("AudioBiquad.swift", "q: 10 * Double(k) / a,", "q: 10 * Double(k),")]),
]

# ---- the oracle: RBJ's cookbook in numpy ------------------------------------

BUTTERWORTH = {12: [1 / np.sqrt(2)],
               24: [1 / (2 * np.cos(np.pi / 8)), 1 / (2 * np.cos(3 * np.pi / 8))]}


def rbj(kind, f, fs, q=None, gain=0.0):
    w = 2 * np.pi * f / fs
    c, s = np.cos(w), np.sin(w)
    a_ = 10 ** (gain / 40)
    if kind in ("lp", "hp"):
        al = s / (2 * q)
        if kind == "lp":
            b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
        else:
            b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        a = [1 + al, -2 * c, 1 - al]
    elif kind == "peak":
        al = s / (2 * q)
        b = [1 + al * a_, -2 * c, 1 - al * a_]
        a = [1 + al / a_, -2 * c, 1 - al / a_]
    else:  # shelves, S = 1
        al = s / 2 * np.sqrt(2)
        k = 2 * np.sqrt(a_) * al
        if kind == "ls":
            b = [a_ * ((a_ + 1) - (a_ - 1) * c + k), 2 * a_ * ((a_ - 1) - (a_ + 1) * c),
                 a_ * ((a_ + 1) - (a_ - 1) * c - k)]
            a = [(a_ + 1) + (a_ - 1) * c + k, -2 * ((a_ - 1) + (a_ + 1) * c),
                 (a_ + 1) + (a_ - 1) * c - k]
        else:
            b = [a_ * ((a_ + 1) + (a_ - 1) * c + k), -2 * a_ * ((a_ - 1) + (a_ + 1) * c),
                 a_ * ((a_ + 1) + (a_ - 1) * c - k)]
            a = [(a_ + 1) - (a_ - 1) * c + k, 2 * ((a_ - 1) - (a_ + 1) * c),
                 (a_ + 1) - (a_ - 1) * c - k]
    return np.array(b) / a[0], np.array(a) / a[0]


def magnitude_db(section, freqs, fs):
    b, a = section
    z = np.exp(-1j * 2 * np.pi * np.asarray(freqs) / fs)
    h = (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    return 20 * np.log10(np.abs(h))


def oracle(kind, params, fs):
    """{position: section} for one slot's parameters (AU-30's positions)."""
    if kind in ("high_pass", "low_pass"):
        base = 0 if kind == "high_pass" else 7
        qs = BUTTERWORTH[params["slope"]]
        return {base + i: rbj("hp" if kind == "high_pass" else "lp", params["frequency"], fs, q)
                for i, q in enumerate(qs)}
    if kind in ("low_shelf", "high_shelf"):
        return {2 if kind == "low_shelf" else 6:
                rbj("ls" if kind == "low_shelf" else "hs", params["frequency"], fs,
                    gain=params["gain_db"])}
    if kind.startswith("band_"):
        return {2 + int(kind[-1]): rbj("peak", params["frequency"], fs, q=params["q"],
                                       gain=params["gain_db"])}
    f0, depth = params["frequency"], params["depth_db"]
    a = 10 ** (-depth / 40)
    return {8 + k: rbj("peak", k * f0, fs, q=10 * k / a, gain=-depth)
            for k in range(1, params["harmonics"] + 1)}


def score_q1(path):
    """(good, detail lines) for the probe's Q1 JSON."""
    data = json.loads(Path(path).read_text())
    good = True
    lines = []
    worst = 0.0
    for case in data["cases"]:
        label = f"{case['kind']} {case['params']} at {case['fs'] / 1000:g} kHz"
        if "error" in case:
            good = False
            lines.append(f"  FAIL Q1 {label}: {case['error']}")
            continue
        expected = oracle(case["kind"], case["params"], case["fs"])
        got = {int(p): np.array(v) for p, v in case["positions"].items()}
        if set(got) != set(expected):
            good = False
            lines.append(f"  FAIL Q1 {label}: positions {sorted(got)} not {sorted(expected)}")
            continue
        for p, section in expected.items():
            gap = float(np.max(np.abs(got[p] - magnitude_db(section, case["freqs"], case["fs"]))))
            worst = max(worst, gap)
            if gap > 0.001:
                good = False
                lines.append(f"  FAIL Q1 {label} position {p}: off by {gap:.5f} dB")
    lines.append(("  ok   " if good else "  FAIL ")
                 + f"Q1 {len(data['cases'])} slot and hum cases against numpy's RBJ: worst "
                 f"{worst:.6f} dB (≤ 0.001)")
    cascade_good = len(data["cascades"]) == 2
    for c in data["cascades"]:
        at = np.array(c["at"]) + c["depth_db"]
        mid = np.array(c["mid"])
        ok = bool(np.all(np.abs(at) <= 0.1) and np.all(np.abs(mid) <= 0.3))
        cascade_good &= ok
        lines.append(("  ok   " if ok else "  FAIL ")
                     + f"Q1 cascade {c['frequency']} Hz × {c['harmonics']} at {c['depth_db']:g} "
                     f"dB: harmonics −depth {at.min():+.3f}…{at.max():+.3f} dB, midway "
                     f"{mid.min():+.3f}…{mid.max():+.3f} dB")
    return good and cascade_good, lines


# ---- fixtures, build and run -----------------------------------------------

def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def fixtures():
    """stereo.wav: 12 s, the owner's voice with a −40 dBFS 60 Hz hum on the left,
    the right channel silent (24-bit, 48 kHz)."""
    FIXTURES.mkdir(parents=True, exist_ok=True)
    if not RODE.exists():
        raise RuntimeError(f"{RODE} is missing (the owner's recording, samples/README.md)")
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(RODE), "-t", "12", "-f", "f32le", "-acodec",
         "pcm_f32le", "-ar", str(FS), "-ac", "1", "-"], capture_output=True, check=True).stdout
    voice = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    voice = np.pad(voice, (0, max(0, 12 * FS - len(voice))))[:12 * FS]
    n = np.arange(len(voice))
    left = voice + 0.01 * np.sin(2 * np.pi * 60 * n / FS)
    stereo = np.zeros(2 * len(left), dtype="<f4")
    stereo[0::2] = left
    (FIXTURES / "stereo.f32").write_bytes(stereo.tobytes())
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(FS), "-ac", "2", "-i",
         str(FIXTURES / "stereo.f32"), "-c:a", "pcm_s24le", str(FIXTURES / "stereo.wav")],
        check=True)


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/eq_probe.swift", entry)
    binary = out / "eq-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary, optimize=True)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, ""


def run(sources, name, quiet=False):
    """{row: bool}, the probe's stderr tail."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    result = subprocess.run([str(binary), str(FIXTURES), str(scratch)], capture_output=True,
                            text=True, timeout=1200)
    rows = {}
    lines = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
            lines.append(line)
        elif parts[:1] == ["Q1JSON"]:
            good, detail = score_q1(parts[1])
            rows["Q1"] = rows.get("Q1", True) and good
            lines += detail
        else:
            lines.append(line)
    if not quiet:
        print("\n".join(lines))
    return rows, result.stderr[-600:]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutants", action="store_true")
    args = parser.parse_args()
    try:
        fixtures()
    except Exception as error:
        check("fixture construction", False, str(error))
        return 1
    if args.mutants:
        return mutants(args.sources)
    rows, problem = run(args.sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        return 1
    good = all(rows.get(row) for row in ROWS)
    good &= check("every row Q1..Q11 ran", all(row in rows for row in ROWS),
                  ", ".join(row for row in ROWS if row not in rows) or "")
    passed = sum(1 for row in ROWS if rows.get(row))
    print(f"\n{passed}/{len(ROWS)} rows passed")
    if problem.strip() and not good:
        print("stderr: " + problem)
    return 0 if good else 1


def mutants(sources):
    killed = 0
    for name, killers, edits in MUTANTS:
        slug = name.split()[0]
        tree = WORK / f"mutant-{slug}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        anchored = True
        for file, old, new in edits:
            path = tree / file
            text = path.read_text()
            if text.count(old) != 1:
                check(f"mutant {name}", False, f"anchor not found once in {file}")
                anchored = False
                break
            path.write_text(text.replace(old, new))
        if not anchored:
            continue
        rows, problem = run(tree, f"mutant-{slug}", quiet=True)
        if rows is None:
            check(f"mutant {name} ({'/'.join(killers)})", False, "did not build: " + problem)
            continue
        dead = any(rows.get(row) is False for row in killers)
        killed += dead
        check(f"mutant {name} killed by {'/'.join(killers)}", dead,
              "failing rows: " + (", ".join(sorted(r for r, ok in rows.items() if not ok))
                                  or "none"))
    print(f"\n{killed}/{len(MUTANTS)} mutants killed")
    return 0 if killed == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
