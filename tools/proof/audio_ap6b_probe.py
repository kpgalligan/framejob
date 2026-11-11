"""The leveller's probe (road map "audio" AP6 part 2, spec §11 AU-66, AU-67).

`audio_ap6b_probe.swift` compiled with app/Sources through swift_build, with
`app/Resources/Models` copied beside the binary so the product's own speech
pass (Silero VAD) runs for L6, the step-2 figures and R5.

  L1  constant speech at L − 9, − 3, + 3 and − 20: r = x ±0.01 and the run's
      gain clamp(target − r, −down, +up) ±0.01 dB; a phrase with 0.3 s silent
      gaps has the same r (the window is speech only); a one-channel reading's
      curve equals its dual-mono stereo copy's.
  L2  two long phrases 12 dB apart across a 1.5 s break: B's first speech
      step's gain is B's settled gain ±0.01 dB; the break holds A ±0.001 dB
      until its last 0.25 s, then moves linearly to B inside [A, B]; a 0.5 s
      phrase between them takes A's value.
  L3  `smooth` of a step is the midpoint ±0.01 at the step and reaches 90 % at
      τ·ln 5 ±1 step on both sides (zero-phase look-ahead).
  L4  through the tap: 512, 4096 and irregular buffers byte-identical with the
      target automated; a run from mid-clip byte-identical to the same frames
      from the clip's start; no curve touches nothing; after the action each
      sample's gain is the curve's at its own frame ±0.01 dB.
  L5  the order: a pause at L − 22 under a 20 dB gate stays gated with the
      leveller at +12 dB after it; a leveller before the gate would open it.
  L6  `AudioDynamicsLevels.curves` over the steady fixture's own caches:
      pending on the loudness, then on the speech; with speech detection
      unavailable unmeasurable and not in `pendingLevels`; `media.speech` ready
      either way, used over the VAD, and a change of it recomputes; no long
      phrase unmeasurable; a nest clip absent; an end-only leveller in
      `levelling` and `wanting`; an end's other response its own curve; a
      pending curve in `pendingLevels`.
  L7  `AudioProps.interpolated` mixes the target and the limits; the response
      is the left point's.
  L8  a 1-hour clip's curve in ≤ 100 ms (best of 3); a run ≤ 1 % of real time
      per 1024 stereo frames.
  L9  a reversed and a ×2 clip of the off-mic fixture get curves on their
      played steps: a quiet phrase played first is boosted first.
  L10 a Target and cap edit inside an action (clip 4's end `{}` then
      `{target_db: 3, max_up_db: 6}`, on L6's caches) moves the plan text and
      makes no curve (`curveBuilds`), the curves equal; clip 4 trimmed to 29 s
      makes at least one (#413, AU-66 (e)).
  R1  `speechRange`: constant 0; two 10 s halves 12 dB apart 12.0 ±0.1; the
      mask honoured; nil under 300 speech steps.
  R2  `levellerRule` at 5.9 and 6.1 LU and with no range, with each sentence.
  R3  `needsRender` for a leveller alone, and the memo key's chain carries it.
  R4  `choose` over one input twice is equal, the leveller on above 6 LU.
  R5  (not with --quick) the steady fixture's Enhance trial rendered three
      times through `ProcessedLoudness.render`, its isolated render wiped
      before the third: byte-identical step energies (AP6b step 3). Its
      detail says what differed (#567): per pair of renders, for the steps
      and for the peaks, how many differ, the first one's index, time and
      both values at 17 digits and the largest difference in dB; and whether
      the isolated render made again before the third is the bytes it was.
  R6  the comparison R5 reports with, over synthetic arrays: equal, one step
      differing at a known index, another length.
  R7  `StepLoudnessMeter` gives byte-identical step energies and peaks for
      one programme fed whole, a step at a time, in 4,096-frame buffers and
      in uneven ones (AU-160: R5's non-repeat was the meter summing a step
      per reader buffer, #567).

Then, the step-2 figures (AU-67 (d)), printed: the speech range Enhance
measures on the owner's recording and on the proof's off-mic and steady
fixtures (`make_fixtures`, shared with audio_ap6b_proof.py), each through a
probe document's own loudness and speech caches; scored that the off-mic one
is over 6 LU and the steady one at or under it (else the rule is a STOP).

--mutants runs M1–M10, M12–M15 and M17–M19, each over its own copy of app/Sources,
scored killed when its named row fails (the step-2 figures and R5 skipped);
build failures are scored. M11 (`"leveller"` out of `TAP_KEYS`) is by hand
against core/tests/audio_automation.rs. M16 has no edit to make: AP6b's step 3
found nothing to fix; the non-repeat's fix is AU-160's (#567) and its mutant
is M19. Needs ffmpeg, `say`, numpy and samples/Rode-usb-mic.m4a. Output is
under tools/proof/work/audio-ap6b-probe.

--soak-r5 <minutes> runs R5 alone (`--r5-only`: a document holding the steady
fixture, nothing else scored), each time in a fresh process on a fresh scratch
folder, until one fails or the minutes are up; it prints the count and keeps
a failing run's whole output as work/audio-ap6b-probe/soak-r5-fail.txt
(#567: both recorded failures were under other builds, so run it under load).
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

import numpy as np

import swift_build

ROOT = Path(__file__).resolve().parents[2]
RODE = ROOT / "samples/Rode-usb-mic.m4a"
WORK = ROOT / "tools/proof/work/audio-ap6b-probe"
FIXTURES = WORK / "fixtures"
RATE = 48000
ROWS = [f"L{n}" for n in range(1, 11)] + [f"R{n}" for n in range(1, 8)]

# The fixtures (spec AP6b's constraints): six 10 s `say` segments, 1.5 s apart,
# over a −60 dBFS RMS white-noise bed, mono 48 kHz.
LEAD = 0.5
SEGMENT = 10.0
PAUSE = 1.5
TAIL = 1.5
TEXTS = [
    "The quick brown fox jumps over the lazy dog while the farmer counts his sheep and "
    "wonders whether the rain will come before the harvest is safely in the barn tonight.",
    "Every morning the baker opens the shop at six, sets the bread on the shelves, and "
    "greets the first customers who wait outside in the cold with their hands in pockets.",
    "A river runs through the middle of the old town, under seven bridges of grey stone, "
    "and on summer evenings the children race paper boats from one bridge to the next.",
    "The library keeps its oldest maps in a quiet room upstairs, where the light is kept "
    "low and visitors must wear cotton gloves before they turn a single fragile page.",
    "On the hill above the station there is a small observatory, and twice a month the "
    "astronomers invite the public to look through the telescope at the rings of Saturn.",
    "When the ferry finally reached the island, the passengers stepped onto the pier, "
    "stretched their legs, and followed the narrow path up toward the lighthouse keeper.",
]


def segments(peaks):
    """[(start, end)] seconds of each speech segment in a fixture."""
    return [(LEAD + k * (SEGMENT + PAUSE), LEAD + k * (SEGMENT + PAUSE) + SEGMENT)
            for k in range(len(peaks))]


OFF_MIC_PEAKS = [-6, -18, -6, -18, -6, -18]
STEADY_PEAKS = [-6] * 6


def make_fixtures(dest):
    """ap6b-offmic.wav and ap6b-steady.wav (24-bit mono 48 kHz) in `dest`:
    each segment the first 10 s of `say` speech, its sample peak set to
    the fixture's dBFS; one −60 dBFS RMS Gaussian bed throughout."""
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    speech = []
    with tempfile.TemporaryDirectory() as tmp:
        for k, text in enumerate(TEXTS):
            aiff = Path(tmp) / f"say{k}.aiff"
            raw = Path(tmp) / f"say{k}.f32"
            subprocess.run(["say", "-o", str(aiff), text], check=True)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(aiff), "-f", "f32le",
                            "-acodec", "pcm_f32le", "-ar", str(RATE), "-ac", "1", str(raw)],
                           check=True)
            y = np.fromfile(raw, dtype="<f4").astype(float)[:int(SEGMENT * RATE)]
            y = np.pad(y, (0, int(SEGMENT * RATE) - len(y)))
            speech.append(y / np.max(np.abs(y)))
    total = int((LEAD + 6 * SEGMENT + 5 * PAUSE + TAIL) * RATE)
    bed = 0.001 * np.random.default_rng(2026_10_31).standard_normal(total)
    for name, peaks in (("ap6b-offmic.wav", OFF_MIC_PEAKS), ("ap6b-steady.wav", STEADY_PEAKS)):
        y = bed.copy()
        for (start, _), peak, voice in zip(segments(peaks), peaks, speech):
            at = int(start * RATE)
            y[at:at + len(voice)] += voice * 10 ** (peak / 20)
        raw = dest / (name + ".f32")
        y.astype("<f4").tofile(raw)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac",
                        "1", "-i", str(raw), "-c:a", "pcm_s24le", str(dest / name)], check=True)
        raw.unlink()


CURVE = "AudioLevellerCurve.swift"
STAGE = "AudioLevellerStage.swift"
LEVELS = "AudioDynamicsLevels.swift"
MUTANTS = [
    ("M1 break-rides-whole", "L2", [
        (CURVE, "                r[k] = m >= glideSteps\n"
                "                    ? from : from + (to - from) * Double(glideSteps - m) / "
                "Double(glideSteps)\n",
         "                r[k] = from + (to - from) * Double(k - start + 1) / "
         "Double(next - start + 1)\n")]),
    ("M2 phrases-not-split", "L2", [
        (CURVE, "k - open.last - 1 < breakSteps", "k - open.last - 1 < Int.max")]),
    ("M3 window-counts-pauses", "L1", [
        (CURVE, "energy[j] + (isSpeech[k] ? steps[k] : 0)", "energy[j] + steps[k]"),
        (CURVE, "counted[j] + (isSpeech[k] ? 1 : 0)", "counted[j] + 1")]),
    ("M4 target-absolute", "L1", [
        (CURVE, "u[j] = StepLoudness.loudness(max(mean, 1e-20)) - level",
         "u[j] = StepLoudness.loudness(max(mean, 1e-20))")]),
    ("M5 boost-uncapped", "L1", [
        (STAGE, "-maxDownDB), maxUpDB)", "-maxDownDB), 1000)")]),
    ("M6 leveller-before-gate", "L5", [
        ("AudioDSP.swift",
         "        gate.process(channels, count: count, frames: frames, settings: params.gate)\n"
         "        leveller?.apply(channels, count: count, frames: frames)\n",
         "        leveller?.apply(channels, count: count, frames: frames)\n"
         "        gate.process(channels, count: count, frames: frames, settings: params.gate)\n")]),
    ("M7 causal-smoothing", "L3", [(CURVE, "        return backward\n", "        return forward\n")]),
    ("M8 response-interpolated", "L7", [
        ("AudioAutomation.swift", "maxDownDb: mix(a.maxDownDb, b.maxDownDb, f), response: a.response)",
         "maxDownDb: mix(a.maxDownDb, b.maxDownDb, f), response: mix(a.response, b.response, f))")]),
    ("M9 short-phrase-own-level", "L2", [
        (CURVE, "let taken = previous ?? ends[index...]",
         "let taken = StepLoudness.loudness(steps[phrases[index].first]) - level\n"
         "            _ = previous ?? ends[index...]")]),
    ("M10 range-ignores-mask", "R1", [
        ("AudioEnhance+Leveller.swift", "for k in 0..<count where speech[k] {",
         "for k in 0..<count {")]),
    ("M12 needs-render-omits", "R3", [
        ("ProcessedLoudness.swift", "        if audio.leveller != nil { return true }\n", "")]),
    ("M13 levelling-omits-ends", "L6", [
        (LEVELS, "                        if case .some(.some) = $0.end.audio?.leveller { return true }\n"
                 "                        return false\n",
         "                        _ = $0\n                        return false\n")]),
    ("M14 memo-ignores-speech", "L6", [
        (LEVELS, "entry.speech == entry.media.flatMap({ snapshot.media($0)?.speech }),", "true,")]),
    ("M15 gain-run-relative", "L4", [
        (STAGE, "let tick = Double(firstFrame + Int64(i)) * ticksPerFrame",
         "let tick = Double(Int64(i)) * ticksPerFrame")]),
    ("M17 no-detection-pending", "L6", [
        (LEVELS, ": .unmeasurable(reason: noSpeechDetection)", ": .pending(what: \"speech\")")]),
    # #413: the curves keyed by the whole plan text, automation included.
    ("M18 curves-keyed-by-plan", "L10", [
        (LEVELS, "        let key = Key(cache: cache.standardizedFileURL.path, plan: memoPlan(project))\n"
                 "        var result: [UInt32: Curves] = [:]",
         "        let key = Key(cache: cache.standardizedFileURL.path, plan: project.planJSON)\n"
         "        var result: [UInt32: Curves] = [:]")]),
    # #567, AU-160: a step's energy summed per feed chunk, as it was.
    ("M19 step-summed-per-chunk", "R7", [
        ("StepLoudness.swift", "    private var stepFilled = 0\n",
         "    private var stepFilled = 0\n    private var chunkSum: Double = 0\n"),
        ("StepLoudness.swift", "                from: channelBuffer + history, count: frames)\n",
         "                from: channelBuffer + history, count: frames)\n"
         "            var sum: Double = 0\n"
         "            vDSP_svesqD(channelBuffer + history, 1, &sum, vDSP_Length(frames))\n"
         "            chunkSum += sum\n"),
        ("StepLoudness.swift", "        steps.append(stepSum / Double(stepFilled))\n",
         "        steps.append(chunkSum / Double(stepFilled))\n"
         "        chunkSum = 0\n        _ = stepSum\n")]),
]


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def fixtures():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    if not RODE.exists():
        raise RuntimeError(f"{RODE} is missing (the owner's recording, samples/README.md)")
    shutil.copyfile(RODE, FIXTURES / "rode.m4a")
    make_fixtures(FIXTURES)


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/audio_ap6b_probe.swift", entry)
    binary = out / "audio-ap6b-probe"
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


def run(sources, name, quiet=False, quick=False):
    """{row: bool}, the probe's stderr tail, and its printed lines."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem, ""
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    command = [str(binary), str(FIXTURES), str(scratch)] + (["--quick"] if quick else [])
    result = subprocess.run(command, capture_output=True, text=True, timeout=1800)
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
    if not quiet:
        sys.stdout.write(result.stdout)
    return rows, result.stderr[-600:], result.stdout


def step_two(stdout):
    """The three ranges the probe printed, by fixture name."""
    ranges = {}
    for match in re.finditer(r"note step2 (\S+) speech_range_lu (\S+)", stdout):
        try:
            ranges[match.group(1)] = float(match.group(2))
        except ValueError:
            ranges[match.group(1)] = None
    return ranges


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutants", nargs="?", const="", default=None, metavar="M12,M19",
                        help="every mutant, or the ones named")
    parser.add_argument("--soak-r5", type=float, default=None, metavar="MINUTES",
                        help="R5 alone in fresh processes until one fails or the minutes are up")
    args = parser.parse_args()
    try:
        fixtures()
    except Exception as error:
        check("fixture construction", False, str(error))
        return 1
    if args.mutants is not None:
        return mutants(args.sources, [n for n in args.mutants.split(",") if n])
    if args.soak_r5 is not None:
        return soak_r5(args.sources, args.soak_r5)
    rows, problem, stdout = run(args.sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        return 1
    good = all(rows.get(row) for row in ROWS)
    good &= check("every row ran", all(row in rows for row in ROWS),
                  ", ".join(row for row in ROWS if row not in rows) or "")
    ranges = step_two(stdout)
    owner = ranges.get("rode.m4a")
    off = ranges.get("ap6b-offmic.wav")
    steady = ranges.get("ap6b-steady.wav")
    good &= check("step 2: the off-mic fixture reads over 6 LU and the steady one at or under",
                  off is not None and steady is not None and off > 6 and steady <= 6,
                  f"owner {owner}, off-mic {off}, steady {steady} LU")
    passed = sum(1 for row in ROWS if rows.get(row))
    print(f"\n{passed}/{len(ROWS)} rows passed")
    if problem.strip() and not good:
        print("stderr: " + problem)
    return 0 if good else 1


def soak_r5(sources, minutes):
    """R5 alone, a fresh process and scratch folder each time, until one fails
    or `minutes` have passed (#567). 0 when none failed."""
    binary, problem = build(sources, "probe")
    if binary is None:
        check("source probe builds", False, problem)
        return 1
    began = time.monotonic()
    runs = 0
    while time.monotonic() - began < minutes * 60:
        scratch = WORK / "soak-r5" / "scratch"
        shutil.rmtree(scratch, ignore_errors=True)
        scratch.mkdir(parents=True)
        result = subprocess.run([str(binary), str(FIXTURES), str(scratch), "--r5-only"],
                                capture_output=True, text=True, timeout=1800)
        runs += 1
        lines = [line for line in result.stdout.splitlines() if line.split()[1:2] == ["R5"]]
        passed = bool(lines) and all(line.split()[0] == "ok" for line in lines)
        if runs == 1 or not passed:
            sys.stdout.write(result.stdout)
        if not passed:
            kept = WORK / "soak-r5-fail.txt"
            kept.write_text(result.stdout + "\n--- stderr ---\n" + result.stderr)
            elapsed = (time.monotonic() - began) / 60
            print(f"\nR5 FAILED on run {runs} after {elapsed:.1f} min (exit "
                  f"{result.returncode}); its output is {kept}")
            return 1
    elapsed = (time.monotonic() - began) / 60
    print(f"\nR5 passed {runs} of {runs} runs in {elapsed:.1f} min "
          f"({3 * runs} renders, {runs} isolation re-renders)")
    return 0


def mutants(sources, only=()):
    killed = 0
    chosen = [m for m in MUTANTS if not only or m[0].split()[0] in only]
    for name, row, edits in chosen:
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
        rows, problem, _ = run(tree, f"mutant-{slug}", quiet=True, quick=True)
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
