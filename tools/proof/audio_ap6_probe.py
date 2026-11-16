"""Enhance Voice's probe (road map "audio" AP6 part 1, spec §11 AU-60..AU-64).

`audio_ap6_probe.swift` compiled with app/Sources through swift_build, with
`app/Resources/Models` copied beside the binary so the product's own speech
pass (Silero VAD) runs: `AudioEnhance`'s measurements and rules, the processed
solve's pure decisions (`ProcessedLoudness.needsRender`, `measurementPlan`,
`AudioNormalize.plan(solved:)`). Nothing here renders; the solve's figures are
audio_ap6_proof.py's V2, V12 and V13.

  E1  each rule on both sides of its threshold (synthetic readings): floor − L
      at −44 and −46 dB (isolation 0.8 with noise reduction off, at any
      speed since #387), the gate's threshold from the pauses' median PEAK + 10 − L and its
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
      false. On a clip (AU-159 (a), #402): each of the eight stages an action
      can switch on, and a limiter or a null limiter (AU-165 (a)), only at an
      action's end, true; pan, mono, channels, a volume, a null EQ or gate
      and a 0 isolation or noise reduction at an end false; a gate or a
      limiter at the end of an action of no duration false.
  E11 `plan(solved:)` keeps the clip's volume at 0.04 dB and writes the solve
      at 0.06 dB or with another limiter; a cache row is never kept; the keep
      rule compares the clip's OWN limiter, so a clip with none whose reading
      carries the chosen default writes the solve (#400, AU-64 (f)).
  E12 the processed memo's key names its document: an R0 stored for one
      document's clip is not read by a second open document over a copy of the
      same package (#401, AU-64 (g)).
  E13 the memo's key survives the solve (AU-159 (g), #402): on a clip with a
      base gate and an action whose end is a pan, R0's trial (no base limiter,
      volume 1) and the clip after `set_audio {volume: 2, limiter}` have one
      key, though their measurement plans differ.
  E14 the key follows an action's audio: another gate threshold or limiter
      ceiling at an action's end is another key; another end volume is not;
      a limiter keyed off at a later action's end is another key than the
      limiter left on.
  E15 (AU-165 (a), (b), #402) `endSetsLimiter`: true for a limiter at an
      action's end, a null one (keyed off) and one beside a gate; false for
      one at the end of an action of no duration, an end with no `limiter`
      key, the clip's own limiter alone and no clip. `verifiesByRender` over
      its four cases (only no limiter and no end limiter answers from R0).
      `endLimiterOn` (AU-168 (a), #608) over the same clips: true for a limiter
      at an end and one beside a gate, false for the null and every other.
  E16 (AU-165 (c)) `Verified.holds` at its own volume and 0.04 dB away
      (true), 0.06 dB away, under another limiter and at volume 0 (false), a
      limited render with no limiter (false); the memo answers a verify
      render stored beside an R0 and the next R0 for the key drops it.
  E17 (AU-165 (b)) `limiterGoesOn`: R0's peak 0.01 dB under −1 dBTP at the
      volume stays off, 0.01 dB over goes on, a limiter already on is not
      asked; `AudioNormalize.ceilingLimiter`: the default at −1 dBTP, a
      clip's own lowered to −1 or kept under it.
  E18 (AU-167, #607) `verifiedLimit`: at ×2 0.11 LU short or over
      `verify_renders`, 0.09 nil; at ×32 0.11 short `max_gain`, 0.09 nil,
      0.11 over `verify_renders`; at ×31.9 5 LU short `verify_renders`.
      `limitNote`: none nil; the ceiling's clips alone today's sentence byte
      for byte; a verify clip named with `verify_renders` and a limiter, no
      `max_gain`; both, the tail once. `AudioEnhance.loudnessReason`: landed
      "."; the ceiling's clause kept; the verify bound "short of" or "over"
      with a limiter and not "would pass". AU-168 (#608): of two ceiling
      clips the one an action's limiter is on for named with that limiter in
      the ceiling's place, the other in the ceiling's sentence; both, no
      "would pass"; R0 at −50, so ×32 of it short of −16 anyway, the ceiling's
      sentence byte for byte; ×32 of R0 0.05 LU short names the limiter, 0.15
      LU short the ceiling; a row with no R0 the ceiling; the set changing
      nothing for a landed or a verify bound's clip; a measured target
      (Match's, −15.999999999117435) written as −16.0; the reason at ×32 under
      an action's limiter naming it, and the verify bound's clause unchanged.
  E19 (AU-169, #609) the app's own sentence, `AudioMeasureNotice.make`: no
      limit and no skip nil; the ceiling, an action's limiter (R0 reaching)
      and the verify bound short and over, each its cause; R0 too quiet to
      reach keeps the ceiling; a cache row 0.03 LU short "less than 0.1 LU";
      three clips counted, the furthest named with its cause, the tooltip a
      line per clip; two cuts of one recording at one distance, the first by
      its start; Match's "the reference's"; one skip, a clip and two skips
      (an unnamed id "clip N"), every clip skipped and an identity in the
      "changed nothing" form; over the probe document's snapshot the clip's
      name and m:ss start; the clock.

--mutants runs M1–M6 and M8–M43 (M7 is the loudness probe's), each over its
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
ROWS = ["E1", "E2", "E3", "E6", "E7", "E8", "E9", "E10", "E11", "E12", "E13", "E14", "E15",
        "E16", "E17", "E18", "E19"]

MUTANTS = [
    ("M1 noisy-gap", "E1", "AudioEnhance.swift",
     "static let noisyGapDB = -45.0", "static let noisyGapDB = -40.0"),
    ("M2 gate-plus-6", "E1", "AudioEnhance.swift",
     "static let gateAbovePausePeakDB = 10.0", "static let gateAbovePausePeakDB = 6.0"),
    # The arm #387 removed: noise reduction in isolation's place.
    ("M3 isolation-swapped", "E1", "AudioEnhance.swift",
     "                    patch.isolation = IsolationCache.defaultAmount\n"
     "                    patch.noiseReduction = 0\n",
     "                    patch.isolation = 0\n"
     "                    patch.noiseReduction = 0.5\n"),
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
     "return Key(document: document, clip: clip, plan: plan, chain: text + ends)",
     "return Key(document: 0, clip: clip, plan: plan, chain: text + ends)"),
    # AU-159 (#402): the render test and the memo's key read a clip's actions.
    ("M15 actions-not-read", "E10", "ProcessedLoudness.swift",
     "return clip.actions.contains { $0.duration > 0 && endNeedsRender($0.end.audio) }",
     "return false && clip.actions.contains { endNeedsRender($0.end.audio) }"),
    ("M16 no-duration-counts", "E10", "ProcessedLoudness.swift",
     "return clip.actions.contains { $0.duration > 0 && endNeedsRender($0.end.audio) }",
     "return clip.actions.contains { endNeedsRender($0.end.audio) }"),
    ("M17 key-keeps-point-limiters", "E13", "ProcessedLoudness.swift",
     'audio.removeValue(forKey: "limiter")', "_ = audio.count"),
    ("M18 key-without-end-limiters", "E14", "ProcessedLoudness.swift",
     "return Key(document: document, clip: clip, plan: plan, chain: text + ends)",
     "return Key(document: document, clip: clip, plan: plan, chain: text)"),
    ("M19 key-without-automation", "E14", "ProcessedLoudness.swift",
     'point["audio"] = audio', 'point["audio"] = [String: Any]()'),
    ("M20 key-without-limiter-offs", "E14", "ProcessedLoudness.swift",
     'let value = limiter.map { "\\($0.ceilingDb),\\($0.release)" } ?? "off"',
     'guard let held = limiter else { continue }\n'
     '            let value = "\\(held.ceilingDb),\\(held.release)"'),
    # AU-165 (#402): an action-end limiter renders, is verified by render, and At
    # volume reads the verify render while the clip is at its volume and limiter.
    ("M21 end-limiter-not-rendered", "E10", "ProcessedLoudness.swift",
     "if needsRender(clip.audio) || endSetsLimiter(clip) { return true }",
     "if needsRender(clip.audio) { return true }"),
    ("M22 verify-only-under-a-limiter", "E15", "LoudnessMeasureRun.swift",
     "limiter != nil || endLimiter", "limiter != nil"),
    ("M23 null-limiter-not-counted", "E15", "ProcessedLoudness.swift",
     "if case .some = end.limiter { return true }",
     "if case .some(.some) = end.limiter { return true }"),
    ("M24 holds-at-any-volume", "E16", "ProcessedLoudness.swift",
     "return abs(20 * log10(current / volume)) <= AudioNormalize.keepVolumeDB",
     "return true"),
    ("M25 r0-keeps-verified", "E16", "ProcessedLoudness.swift",
     "            verified.removeValue(forKey: key)\n",
     ""),
    ("M26 limiter-never-goes-on", "E17", "LoudnessMeasureRun.swift",
     "limiter == nil && truePeak * volume > pow(10, AudioNormalize.ceilingDBTP / 20)",
     "false && limiter == nil && truePeak * volume > 0"),
    # AU-167 (#607): the verify bound named, apart from the ceiling, in every reader.
    ("M27 verify-threshold-1lu", "E18", "AudioNormalize+Loudness.swift",
     "if abs(resultLUFS - targetLUFS) > tolerance { return .verifyRenders }",
     "if abs(resultLUFS - targetLUFS) > 1.0 { return .verifyRenders }"),
    ("M28 verify-bound-unnamed", "E18", "AudioNormalize+Loudness.swift",
     "if abs(resultLUFS - targetLUFS) > tolerance { return .verifyRenders }",
     "if abs(resultLUFS - targetLUFS) > tolerance { return nil }"),
    ("M29 verify-before-ceiling", "E18", "AudioNormalize+Loudness.swift",
     "        if volume >= maxGain && resultLUFS < targetLUFS - tolerance { return .maxGain }\n"
     "        if abs(resultLUFS - targetLUFS) > tolerance { return .verifyRenders }\n",
     "        if abs(resultLUFS - targetLUFS) > tolerance { return .verifyRenders }\n"
     "        if volume >= maxGain && resultLUFS < targetLUFS - tolerance { return .maxGain }\n"),
    ("M30 note-every-limit-the-ceiling", "E18", "AudioNormalize+Loudness.swift",
     "let clips = rows.filter { $0.limit == limit }",
     "let clips = rows.filter { $0.limit != nil && limit == .maxGain }"),
    ("M31 reason-every-limit-the-ceiling", "E18", "AudioEnhance+Reasons.swift",
     "case .maxGain?:", "case .maxGain?, .verifyRenders?:"),
    # AU-168 (#608): a limiter an action's end turns on, named at the ×32 stop.
    ("M32 note-ignores-end-limiters", "E18", "AudioNormalize+Loudness.swift",
     "row, endLimiter: endLimiters.contains(row.clip), targetLUFS: targetLUFS)",
     "row, endLimiter: false, targetLUFS: targetLUFS)"),
    ("M33 end-limiter-on-counts-a-null", "E15", "ProcessedLoudness.swift",
     "if case .some(.some) = end.limiter { return true }",
     "if case .some = end.limiter { return true }"),
    ("M34 held-at-any-limit", "E18", "AudioNormalize+Loudness.swift",
     "guard endLimiter, result.limit == .maxGain, let r0",
     "guard endLimiter, result.limit != nil, let r0"),
    ("M35 reason-ignores-end-limiter", "E18", "AudioEnhance+Reasons.swift",
     "result, endLimiter: endLimiter, targetLUFS: target)",
     "result, endLimiter: false, targetLUFS: target)"),
    ("M36 held-without-reach", "E18", "AudioNormalize+Loudness.swift",
     "return r0 + 20 * log10(maxGain) >= targetLUFS - LoudnessMeasureRun.verifyToleranceLU",
     "return r0 > -.infinity"),
    ("M37 reach-without-tolerance", "E18", "AudioNormalize+Loudness.swift",
     "return r0 + 20 * log10(maxGain) >= targetLUFS - LoudnessMeasureRun.verifyToleranceLU",
     "return r0 + 20 * log10(maxGain) >= targetLUFS"),
    # AU-169 (#609): the app's own sentence, by case.
    ("M38 notice-limiter-for-any-max-gain", "E19", "AudioMeasureNotice.swift",
     "row, endLimiter: endLimiters.contains(row.clip), targetLUFS: target)",
     "row, endLimiter: true, targetLUFS: target)"),
    ("M39 first-not-furthest", "E19", "AudioMeasureNotice.swift",
     "            abs($0.resultLUFS - target) < abs($1.resultLUFS - target)\n",
     "            abs($0.resultLUFS - target) < abs($1.resultLUFS - target) && false\n"),
    ("M40 skips-left-out", "E19", "AudioMeasureNotice.swift",
     "        if let skip = facts.skipped.first {\n",
     "        if let skip = facts.skipped.first, false {\n"),
    ("M41 short-for-over", "E19", "AudioMeasureNotice.swift",
     'row.resultLUFS < target ? (of ? "short of" : "short") : "over"',
     '(of ? "short of" : "short")'),
    ("M42 no-changed-nothing", "E19", "AudioMeasureNotice.swift",
     "        if !changed {", "        if false, !changed {"),
    ("M43 label-without-start", "E19", "AudioMeasureNotice.swift",
     '"“\\(snapshot.name(of: clip))” (\\(clock(clip.start)))"',
     '"“\\(snapshot.name(of: clip))”"'),
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
    parser.add_argument("--mutants", nargs="?", const="", default=None, metavar="M3,M5",
                        help="every mutant, or the ones whose names start with these")
    args = parser.parse_args()
    try:
        fixtures()
    except Exception as error:
        check("fixture construction", False, str(error))
        return 1
    if args.mutants is not None:
        return mutants(args.sources, [n for n in args.mutants.split(",") if n])
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


def mutants(sources, only=()):
    killed = 0
    chosen = [m for m in MUTANTS if not only or m[0].split()[0] in only]
    for name, row, file, old, new in chosen:
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
    print(f"\n{killed}/{len(chosen)} mutants killed")
    return 0 if chosen and killed == len(chosen) else 1


if __name__ == "__main__":
    sys.exit(main())
