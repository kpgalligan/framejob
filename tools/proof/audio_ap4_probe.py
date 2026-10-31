"""The gate and de-esser's probe (road map "audio" AP4, spec §11 AU-40..AU-47,
AU-49).

`audio_ap4_probe.swift` compiled with app/Sources through swift_build: the
product's `AudioGateStage`, `AudioDeEsserStage`, `AudioEnvelope`, the chain,
`AudioDynamicsLevels`, `AudioDSPParameters` and the tap context.

  D1  the compressor on the shared follower gives a verbatim copy of HEAD's
      `AudioCompressorStage` bytes (the owner's recording and a crest signal;
      512, 4096 and irregular blocks; 5 ms and 200 ms releases; settings
      changing at cuts).
  D2  the gate's static curve: steady 12 kHz tones below the threshold reduced
      by min(range, (thr − level)(ratio − 1)) ±0.05 dB, above it untouched.
  D3  hold and release: the gain crosses −range/2 at t_f + hold + release·ln 2
      ±0.2 ms (t_f the follower's analytic fall), hold 0 and 100 ms.
  D4  512, 4096 and irregular blocks byte-identical through the chain, both
      stages' settings changing at cuts.
  D5  reset() gives a fresh stage's bytes; nil settings touch nothing.
  D6  the de-esser at 6 kHz: tones at 6, 7, 9 and 11 kHz reduced by the LR4
      crossover's analytic amount ±0.1 dB; a 2–12 kHz sweep every 250 Hz none
      louder than its input by more than 0.05 dB; 1 kHz alone the allpass
      ±0.01 dB; 1 kHz beside a loud 7 kHz ±0.1 dB; a quiet 7 kHz beside a loud
      1 kHz ±0.1 dB (the sidechain is the band).
  D7  the gate runs before the compressor (a +24 dB makeup case).
  D8  the levels: threshold = L + rel exactly, L equal to ClipLoudness's,
      pending → nil and in pendingLevels, unmeasurable → nil, a nest ignored,
      no cache folder pending, a pending answer measured once its file lands.
  D9  the export's wait: landed, timedOut and cancelled over a scratch cache.
  D10 the owner's recording under the default gate and de-esser through the
      tap under a muted AVPlayer against an AVAssetReader: the same samples
      within the first 4 s.
  D11 the two stages' cost per 1024 stereo frames, reported, ≤ 1 % of real
      time.

--mutants runs M1..M9 and M11, each over its own copy of app/Sources, scored
killed when one of its named rows fails; build failures are scored. M10 (the
`check_gate` call dropped) is by hand against core/tests/audio_dynamics.rs.
Needs ffmpeg and samples/Rode-usb-mic.m4a. Output is under
tools/proof/work/audio-ap4-probe.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
RODE = ROOT / "samples/Rode-usb-mic.m4a"
WORK = ROOT / "tools/proof/work/audio-ap4-probe"
FIXTURES = WORK / "fixtures"
FS = 48000
ROWS = [f"D{n}" for n in range(1, 12)]

DE_ESSER_SUM = (
    "            vDSP_vmul(bandPlane, 1, gains, 1, bandPlane, 1, length)\n"
    "            vDSP_vadd(low + channel * capacity, 1, bandPlane, 1, data + offset, 1, length)\n")
GATE_LINE = (
    "        gate.process(channels, count: count, frames: frames, settings: params.gate)\n")
COMPRESSOR_LINE = (
    "        compressor.process(channels, count: count, frames: frames, settings: params.compressor)\n")

# (name, killing rows, [(file, old, new), …])
MUTANTS = [
    ("M1 hold-ignored", ["D3"], [
        ("AudioGateStage.swift", "holdCounter = holdFrames", "holdCounter = 0")]),
    ("M2 reset-keeps-reduction", ["D5", "D10"], [
        ("AudioGateStage.swift", "    func reset() {\n        reductionDB = 0\n",
         "    func reset() {\n")]),
    ("M3 threshold-not-relative", ["D8"], [
        ("AudioGateStage.swift", "thresholdDB = (level.isFinite ? level : 0) + relative",
         "thresholdDB = relative")]),
    ("M4 range-uncapped", ["D2"], [
        ("AudioGateStage.swift", "target = min(range, (thresholdDB - levelDB) * expansion)",
         "target = (thresholdDB - levelDB) * expansion")]),
    ("M5 de-esser-wide-band", ["D6"], [
        ("AudioDeEsserStage.swift", DE_ESSER_SUM,
         "            vDSP_vmul(data + offset, 1, gains, 1, data + offset, 1, length)\n")]),
    ("M6 de-esser-keyed-on-full-signal", ["D6"], [
        ("AudioDeEsserStage.swift",
         "            run(coefficients[0], sidechain, frames: frames, state: base)\n"
         "            run(coefficients[1], sidechain, frames: frames, state: base + 2)\n", "")]),
    ("M7 gate-after-compressor", ["D7"], [
        ("AudioDSP.swift", GATE_LINE, ""),
        ("AudioDSP.swift", COMPRESSOR_LINE, COMPRESSOR_LINE + GATE_LINE)]),
    ("M8 follower-floor-5ms", ["D1"], [
        ("AudioEnvelopeFollower.swift", "static let fallFloorSeconds = 0.010",
         "static let fallFloorSeconds = 0.005")]),
    ("M9 memo-holds-pending", ["D8"], [
        ("AudioDynamicsLevels.swift", "            guard level != .pending else { continue }\n",
         "")]),
    ("M11 split-as-subtraction", ["D6"], [
        ("AudioDeEsserStage.swift", DE_ESSER_SUM,
         "            for i in 0..<frames {\n"
         "                data[offset + i] -= (1 - gains[i]) * bandPlane[i]\n"
         "            }\n")]),
]


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def fixtures():
    """voice.f32: the owner's recording's first 12 s, mono 48 kHz float;
    voice.wav (24-bit) and three copies, one per media id the levels rows
    build a loudness cache for."""
    FIXTURES.mkdir(parents=True, exist_ok=True)
    if not RODE.exists():
        raise RuntimeError(f"{RODE} is missing (the owner's recording, samples/README.md)")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(RODE), "-t", "12", "-f", "f32le", "-acodec",
         "pcm_f32le", "-ar", str(FS), "-ac", "1", str(FIXTURES / "voice.f32")], check=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(FS), "-ac", "1", "-i",
         str(FIXTURES / "voice.f32"), "-c:a", "pcm_s24le", str(FIXTURES / "voice.wav")],
        check=True)
    for k in (2, 3, 4):
        shutil.copyfile(FIXTURES / "voice.wav", FIXTURES / f"voice{k}.wav")


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/audio_ap4_probe.swift", entry)
    binary = out / "audio-ap4-probe"
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
    good &= check("every row D1..D11 ran", all(row in rows for row in ROWS),
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
