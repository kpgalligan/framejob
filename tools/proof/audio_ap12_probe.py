"""Match Audio's probe (road map "audio" AP12, spec §11 AU-124..AU-127, AU-129).

`audio_ap12_probe.swift` compiled with app/Sources through swift_build: the
speech spectrum (`SpeechSpectrumMeter`) fed synthetic buffers, the curve and
the fit (`AudioMatchFit`) fed curves made by the EQ's own response, and the
write (`AudioMatchFit.applied`/`trialEQ`, `AudioMatch.plan`,
`AudioMatchRun.referenceProject`). Nothing renders; the renders are
audio_ap12_proof.py's.

  P1  a band level: a 1 kHz sine at amplitude 0.5 in one channel reads
      10·log10(A²/2) within 0.05 dB over 20 frames, its neighbours 60 dB down
      (the Hann window); the bins of each band are [c·2^(−1/6), c·2^(1/6)) and
      contiguous; 20 s of pink noise reads flat 100 Hz–10 kHz within ±1.5 dB.
  P2  speech gating: a pause's tone is not in the spectrum, only frames whose
      centre step is speech count; 11 frames are nil, 12 are not.
  P3  the weights (both levels within 50 dB of their loudest) and the
      weighted mean of D removed, against this probe's own arithmetic; under
      12 weighted bands nil.
  P4  the smoothing, [1, 2, 1]/4 inside and (2, 1)/3 at the ends, through
      `target`.
  P5  a curve made by `responseDB` of a known five-slot EQ on the band
      centres recovered to rms ≤ 0.1 dB.
  P6  an off-grid curve (low shelf 250 Hz +4, bell 2.5 kHz +3 Q 1, high shelf
      4 kHz −5) fitted to rms ≤ 0.5 dB.
  P7  a ±20 dB curve held at ±12 dB; rounding; a flat or 0.04 dB curve sets no
      slot.
  P8  `applied` and `trialEQ` keep the passes and clear bypass; the plan
      writes eq, volume (and a limiter) only, at the reference's loudness;
      the reference renders the press's own project at its own volume.
  P9  a one-sided tilt (reference flat, target + a 4 kHz −6 dB high shelf)
      through `target` then `fit`: a +6 ±0.3 dB shelf at 4 ±0.5 kHz, no bell or
      low shelf above 0.5 dB, rms ≤ 0.1 dB.

--mutants runs M1–M12 (one per independent decision of the speech gate, the
curve, the fit and the write; M12 the shelves' tilt start), each over its own copy of app/Sources, scored
killed when its named row fails. Build failures are scored. Output is under
tools/proof/work/audio-ap12-probe.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/audio-ap12-probe"
ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9"]

MUTANTS = [
    ("M1 no-smoothing", "P4", "AudioMatchFit.swift",
     "return (smoothed(difference), weights)", "return (difference, weights)"),
    ("M2 weights-ignored", "P3", "AudioMatchFit.swift",
     "var weights = [Double](repeating: 0, count: count)",
     "var weights = [Double](repeating: 1, count: count)"),
    ("M3 level-kept", "P3", "AudioMatchFit.swift",
     "difference = (0..<count).map { weights[$0] > 0 ? difference[$0] - mean : 0 }",
     "difference = (0..<count).map { weights[$0] > 0 ? difference[$0] + 0 * mean : 0 }"),
    ("M4 no-gain-clamp", "P7", "AudioMatchFit.swift",
     "let gains = -AudioMatchFit.maxGainDB...AudioMatchFit.maxGainDB",
     "let gains = -1000.0...1000.0"),
    ("M5 trial-keeps-tonal", "P8", "AudioMatchFit.swift",
     "eq.lowShelf = nil\n        eq.band1 = nil\n        eq.band2 = nil\n        eq.band3 = nil\n"
     "        eq.highShelf = nil\n",
     ""),
    ("M6 mask-ignored", "P2", "SpeechSpectrumMeter.swift",
     "if step < speech.count, speech[step] { analyse() }",
     "if step >= 0 { analyse() }"),
    ("M7 reference-at-unity", "P8", "AudioMatchRun.swift",
     "if let scope { project = base.scoped(scope) } else { project = base }",
     "project = LoudnessMeasureRun.trial("
     "base: base, scope: scope, clip: clip, patch: AudioPatch(volume: 1))"),
    ("M8 whole-eq-replaced", "P8", "AudioMatchFit.swift",
     "static func applied(_ fit: Fit, to current: EqProps?) -> EqProps {\n"
     "        var eq = current ?? EqProps()",
     "static func applied(_ fit: Fit, to current: EqProps?) -> EqProps {\n"
     "        var eq = EqProps()"),
    ("M9 fixed-q", "P5", "AudioMatchFit.swift",
     "q: clamp(exp(v[6 + 3 * k]), qRange))", "q: 1.0)"),
    ("M10 no-lm", "P6", "AudioMatchFit.swift",
     "for _ in 0..<maximumIterations {", "for _ in 0..<0 {"),
    ("M11 offset-in-residual", "P9", "AudioMatchFit.swift",
     "return raw.map { $0 - mean }", "return raw.map { $0 + 0 * mean }"),
    # The implementer's addition to AU-126 (a): the refined shelves start the
    # fit only when they alone leave no band at the bell threshold.
    ("M12 tilt-start-never", "P9", "AudioMatchFit.swift",
     "if left.indices.allSatisfy({ weights[$0] == 0 || abs(left[$0]) < minimumBellDB }) {",
     "if left.isEmpty {"),
]


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/audio_ap12_probe.swift", entry)
    binary = out / "audio-ap12-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary, optimize=True)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, ""


def run(sources, name, quiet=False):
    """{row: bool}, the probe's stderr tail, and its printed lines."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem, ""
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=600)
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
    if not quiet:
        sys.stdout.write(result.stdout)
    return rows, result.stderr[-600:], result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutants", action="store_true")
    args = parser.parse_args()
    if args.mutants:
        return mutants(args.sources)
    rows, problem, _ = run(args.sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        return 1
    good = all(rows.get(row) for row in ROWS)
    good &= check("every row ran", all(row in rows for row in ROWS),
                  ", ".join(row for row in ROWS if row not in rows) or "")
    passed = sum(1 for row in ROWS if rows.get(row))
    print(f"\n{passed}/{len(ROWS)} rows passed")
    if problem.strip() and not good:
        print("stderr: " + problem)
    return 0 if good else 1


def mutants(sources):
    killed = 0
    for name, row, file, old, new in MUTANTS:
        slug = name.split()[0]
        tree = WORK / f"mutant-{slug}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        path = tree / file
        text = path.read_text()
        if text.count(old) != 1:
            check(f"mutant {name}", False, f"anchor not found once in {file}")
            continue
        path.write_text(text.replace(old, new))
        rows, problem, _ = run(tree, f"mutant-{slug}", quiet=True)
        if rows is None:
            check(f"mutant {name} ({row})", False, "did not build: " + problem)
            continue
        dead = rows.get(row) is False
        killed += dead
        check(f"mutant {name} killed by {row}", dead,
              f"{row} {'failed' if dead else 'passed'}; failing rows: "
              + ", ".join(sorted(r for r, ok in rows.items() if not ok)))
    print(f"\n{killed}/{len(MUTANTS)} mutants killed")
    return 0 if killed == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
