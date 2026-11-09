"""Enhance Voice's probe (road map "audio" AP6 part 1, spec §11 AU-60..AU-64).

`audio_ap6_probe.swift` compiled with app/Sources through swift_build, with
`app/Resources/Models` copied beside the binary so the product's own speech
pass (Silero VAD) runs: `AudioEnhance`'s measurements and rules, the processed
solve's pure decisions (`ProcessedLoudness.needsRender`, `measurementPlan`,
`AudioNormalize.plan(solved:)`). Nothing here renders; the solve's figures are
audio_ap6_proof.py's V2, V12 and V13.

  E1  each rule on both sides of its threshold (synthetic readings): floor − L
      at −44 and −46 dB, isolatable or not (isolation 0.8 or noise reduction
      0.5), the gate's threshold from the pauses' median PEAK + 10 − L and its
      −40…−6 hold, the de-esser at 6 % and 4 % sibilant speech and a band at
      L − 11, the floor a MEDIAN, Rumble Cut on the clip's own EQ.
  E2  the compressor: threshold the speech's median peak, rounded and held to
      −60…0; makeup the loss this probe's own copy of the model reads, > 0, and
      the loudness through it within 0.5 LU of L.
  E3  on the owner's recording in a probe document: `choose` over its own
      committed result is the same patch, and an identity.
  E6  the owner's measurements, choices and reasons printed; noisy pauses, so
      isolation and a gate, no volume or limiter in the patch; its makeup gives
      back the loss; its job renders through the chosen patch.
  E7  the skips by name (not a clip, 0.3 s, 0.5 s of speech, no loudness file,
      no speech), and an unmeasured floor leaving isolation, noise reduction
      and the gate out of the edit.
  E8  `speechMask`: [start, end), any order.
  E9  `measurementPlan` on a fixture plan: only the clip's segments (an emptied
      track dropped), no ramps, track_pans empty, no video tracks or ducks, one
      instruction from 0 over the plan, the span; and on the owner's clip.
  E10 `needsRender`: each of the nine keys (the leveller since AP6b) true; pan, mono, channels, the
      limiter, the volume, fades, a bypassed or empty EQ and an inert voice
      false.
  E11 `plan(solved:)` keeps the clip's volume at 0.04 dB and writes the solve
      at 0.06 dB or with another limiter; a cache row is never kept; the keep
      rule compares the clip's OWN limiter, so a clip with none whose reading
      carries the chosen default writes the solve (#400, AU-64 (f)).
  E12 the processed memo's key names its document: an R0 stored for one
      document's clip is not read by a second open document over a copy of the
      same package (#401, AU-64 (g)).

--mutants runs M1–M6 and M8–M14 (M7 is the loudness probe's), each over its
own copy of app/Sources, scored killed when its named row fails. Build failures
are scored. Needs samples/Rode-usb-mic.m4a. Output is under
tools/proof/work/audio-ap6-probe.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
RODE = ROOT / "samples/Rode-usb-mic.m4a"
WORK = ROOT / "tools/proof/work/audio-ap6-probe"
FIXTURES = WORK / "fixtures"
ROWS = ["E1", "E2", "E3", "E6", "E7", "E8", "E9", "E10", "E11", "E12"]

MUTANTS = [
    ("M1 noisy-gap", "E1", "AudioEnhance.swift",
     "static let noisyGapDB = -45.0", "static let noisyGapDB = -40.0"),
    ("M2 gate-plus-6", "E1", "AudioEnhance.swift",
     "static let gateAbovePausePeakDB = 10.0", "static let gateAbovePausePeakDB = 6.0"),
    ("M3 isolation-swapped", "E1", "AudioEnhance.swift",
     "if m.isolatable {", "if !m.isolatable {"),
    ("M4 sibilance-gap", "E1", "AudioEnhance.swift",
     "static let sibilanceGapDB = -10.0", "static let sibilanceGapDB = -20.0"),
    ("M5 median-mean", "E1", "AudioEnhance.swift",
     "return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2",
     "return sorted.reduce(0, +) / Double(sorted.count)"),
    ("M6 eq-not-rendered", "E10", "ProcessedLoudness.swift",
     "if let eq = audio.eq, !eq.bypass, eq.activeCount > 0 { return true }",
     "if let eq = audio.eq, !eq.bypass, eq.activeCount > 0 { _ = eq }"),
    ("M8 mask-inverted", "E8", "AudioEnhance.swift",
     "return low < ranges.count && ranges[low].0 <= tick",
     "return !(low < ranges.count && ranges[low].0 <= tick)"),
    ("M9 makeup-zero", "E6", "AudioEnhance.swift",
     "let compressor = CompressorProps(thresholdDb: threshold, makeupDb: makeup)",
     "let compressor = CompressorProps(thresholdDb: threshold, makeupDb: 0)"),
    ("M10 gate-from-floor", "E1", "AudioEnhance.swift",
     "let opens = (m.pausePeakMedianDB ?? -.infinity) + gateAbovePausePeakDB - m.lufs",
     "let opens = (m.floorLUFS ?? -.infinity) + gateAbovePausePeakDB - m.lufs"),
    ("M11 ramps-kept", "E9", "ProcessedLoudness.swift",
     'track.removeValue(forKey: "ramps")', "_ = track.count"),
    ("M12 keep-zero", "E11", "AudioNormalize+Loudness.swift",
     "static let keepVolumeDB = 0.05", "static let keepVolumeDB = 0.0"),
    ("M13 keep-against-chosen", "E11", "AudioNormalize+Loudness.swift",
     "if solve.limiter == reading.currentLimiter, let current",
     "if solve.limiter == reading.limiter, let current"),
    ("M14 memo-without-document", "E12", "ProcessedLoudness.swift",
     "return Key(document: document, clip: clip, plan: measured.json, chain: text)",
     "return Key(document: 0, clip: clip, plan: measured.json, chain: text)"),
]


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def fixtures():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    if not RODE.exists():
        raise RuntimeError(f"{RODE} is missing (the owner's recording, samples/README.md)")
    shutil.copyfile(RODE, FIXTURES / "rode.m4a")


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/audio_ap6_probe.swift", entry)
    binary = out / "audio-ap6-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary, optimize=True)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    # `SileroVAD.bundledURL` falls back to `Models` beside a binary that is
    # not a bundle (speech_cache_probe.py's copy).
    models = binary.parent / "Models"
    shutil.rmtree(models, ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Models", models)
    return binary, ""


def run(sources, name, quiet=False):
    """{row: bool}, the probe's stderr tail, and its printed lines."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem, ""
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    result = subprocess.run([str(binary), str(FIXTURES), str(scratch)], capture_output=True,
                            text=True, timeout=1200)
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
    try:
        fixtures()
    except Exception as error:
        check("fixture construction", False, str(error))
        return 1
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
