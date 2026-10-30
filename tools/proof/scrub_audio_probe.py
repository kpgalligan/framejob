"""Audio while scrubbing, the arithmetic probe (road map "audio" AP13, spec §11 AU-130..AU-136).

`scrub_audio_probe.swift` compiled with app/Sources through swift_build, with
`Blank.mp4` beside the binary: the scheduler and the window driven by their own
clock, the reader against the export's float read, and `ScrubAudio`'s queue
with a recording sink. No app is launched, no ffmpeg is needed: the fixtures
are seeded noise written by `AVAudioFile`.

  G1  a mid-timeline grain is 3,840 frames from the playhead.
  G2  the window: edges < 1e-3, 1 between, symmetric, step <= pi/480; a windowed DC grain.
  G3  a 1 s forward drag at 60 Hz on a 30 fps grid: back to back, from the playhead, the lead.
  G4  a 0.5 s hold: no grain, the last ends <= 0.12 s after the hold began.
  G5  end() clears; a press on the last grain's frame after end(); a leftward drag.
  G6  near the end: shortened; under 480 frames, at or past the end: none.
  G7  the same snapped frame twice in one scrub: one grain.
  C1  volume, pan, fade-in, a duck and a muted track at three starts, <= 1e-5 of the export.
  C2  a gap after a trimmed clip: zero from the clip's end, the export's read before it.
  C3  a compressor and noise reduction: the scheduler's adjacent grains on one build each
      equal a cold read on a fresh build (<= 1e-5); the RMS against the whole read reported.
  E1  the grains played are read x window at the scheduler's starts.
  E2  a blocked first play, three more asked, end(), release: one played.
  E3  one build per player composition object.
  E4  a composition change on a move with no grain is built before the next scrub.
  E5  a composition change on a grain dropped by end() is still built.

Build failures are scored. --sources points at a copied app/Sources tree;
--mutants runs the nine mutants, each over its own copy, and scores each killed
when its named row fails. All output is under tools/proof/work/scrub-audio-probe.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/scrub-audio-probe"
ROWS = [f"G{n}" for n in range(1, 8)] + ["C1", "C2", "C3"] + [f"E{n}" for n in range(1, 6)]

SCHEDULE_OLD = (
    "        if player !== builtFor, let source = source() {\n"
    "            queue.async { [weak self] in self?.rebuild(source) }\n"
    "            builtFor = player\n"
    "        }\n"
    "        guard let grain = scheduler.move(to: playhead, duration: duration, now: now) else { return }\n"
    "        let asked = currentGeneration()\n"
    "        queue.async { [weak self] in self?.render(grain, generation: asked) }\n")
SCHEDULE_CARRIED = (
    "        var carried: ScrubSource?\n"
    "        if player !== builtFor, let source = source() {\n"
    "            carried = source\n"
    "            builtFor = player\n"
    "        }\n"
    "        guard let grain = scheduler.move(to: playhead, duration: duration, now: now) else { return }\n"
    "        let asked = currentGeneration()\n"
    "        queue.async { [weak self] in\n"
    "            guard let self = self, !self.isStale(asked) else { return }\n"
    "            if let carried = carried { self.rebuild(carried) }\n"
    "            self.render(grain, generation: asked)\n"
    "        }\n")
READ_OLD = (
    "            let pts = CMSampleBufferGetPresentationTimeStamp(sample)\n"
    "            let offset = Int(\n"
    "                CMTimeConvertScale(\n"
    "                    CMTimeSubtract(pts, startTime), timescale: CMTimeScale(sampleRate),\n"
    "                    method: .roundHalfAwayFromZero\n"
    "                ).value)\n")
READ_ARRIVAL = (
    "            let offset = arrived\n"
    "            arrived += count\n")

# name, the rows any one of which must fail, file, before (exactly once), after;
# a second (before, after) pair when one edit needs two anchors.
MUTANTS = [
    ("flat-window", ["G2"], "ScrubGrains.swift",
     "        let s = sin(Double.pi / 2 * (Double(fromEdge) + 0.5) / Double(fade))\n"
     "        return Float(s * s)\n",
     "        return 1\n", None),
    ("no-hold-rule", ["G4", "G7"], "ScrubGrains.swift",
     "        guard playhead != lastStart else { return nil }\n", "", None),
    ("no-lead-rule", ["G3"], "ScrubGrains.swift",
     "        guard queuedUntil - now <= ScrubGrains.lead else { return nil }\n", "", None),
    ("no-end-clamp", ["G6"], "ScrubGrains.swift",
     "        guard playhead >= 0, playhead < duration else { return nil }\n"
     "        let frames = min(ScrubGrains.frames, ExportAudioEnd.frames(ofTicks: duration - playhead))\n",
     "        let frames = ScrubGrains.frames\n", None),
    ("end-keeps-last-start", ["G5"], "ScrubGrains.swift",
     "        isActive = false\n        lastStart = nil\n", "        isActive = false\n", None),
    ("leftward-backwards", ["G5"], "ScrubGrains.swift",
     "        let start = playhead\n",
     "        let start = playhead < (lastStart ?? playhead) ? playhead - Ticks(frames) * 25 / 2 : playhead\n",
     None),
    ("read-by-arrival", ["C1"], "ScrubGrains.swift", READ_OLD, READ_ARRIVAL,
     ("        var interleaved: [Float] = []\n",
      "        var interleaved: [Float] = []\n        var arrived = 0\n")),
    ("no-stale-drop", ["E2"], "ScrubAudio.swift",
     "        return asked != generation\n", "        return false\n", None),
    ("rebuild-on-grain", ["E4", "E5"], "ScrubAudio.swift", SCHEDULE_OLD, SCHEDULE_CARRIED, None),
]

# Run and reported, never scored: no row can kill it. AVAssetReaderAudioMixOutput with a
# timeRange stamps its first buffer at the range's start and fills a composition gap with
# silent buffers, so arrival order is presentation order.
EQUIVALENT = {"read-by-arrival"}


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/scrub_audio_probe.swift", entry)
    blank = out / "Blank.mp4"
    if not blank.exists():
        shutil.copyfile(ROOT / "app/Resources/Blank.mp4", blank)
    binary = out / "scrub-audio-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, ""


def run(sources, name):
    """{row: passed}, the tail of stderr, the probe's stdout; or None when it did not build."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem, ""
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        result = subprocess.run([str(binary), str(scratch)], capture_output=True, text=True,
                                timeout=600, cwd=str(binary.parent))
    except subprocess.TimeoutExpired:
        return {}, "the probe ran past 600 s and was killed", ""
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
    return rows, result.stderr[-600:], result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutants", action="store_true")
    args = parser.parse_args()
    if args.mutants:
        return mutants(args.sources)
    rows, problem, stdout = run(args.sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        print(f"\n0/{len(ROWS)} rows passed")
        return 1
    sys.stdout.write(stdout)
    missing = [row for row in ROWS if row not in rows]
    if missing:
        check("every row ran", False, ", ".join(missing) + (f" — {problem.strip()}" if problem.strip() else ""))
    passed = sum(1 for row in ROWS if rows.get(row))
    print(f"\n{passed}/{len(ROWS)} rows passed")
    return 0 if passed == len(ROWS) else 1


def mutants(sources):
    killed = 0
    for name, targets, file, old, new, extra in MUTANTS:
        tree = WORK / f"mutant-{name}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        path = tree / file
        text = path.read_text()
        pairs = [(old, new)] + ([extra] if extra else [])
        if any(text.count(before) != 1 for before, _ in pairs):
            check(f"mutant {name}", False, f"an anchor is not found exactly once in {file}")
            continue
        for before, after in pairs:
            text = text.replace(before, after)
        path.write_text(text)
        rows, problem, _ = run(tree, f"mutant-{name}")
        if rows is None:
            check(f"mutant {name} ({'/'.join(targets)})", False, "did not build: " + problem)
            continue
        failing = sorted(r for r in ROWS if not rows.get(r))
        dead = any(rows.get(row) is False for row in targets)
        if name in EQUIVALENT:
            print(f"  --   mutant {name} (equivalent, not scored): failing rows: "
                  + (", ".join(failing) or "none"))
            continue
        killed += dead
        check(f"mutant {name} killed by {'/'.join(targets)}", dead,
              "failing rows: " + (", ".join(failing) or "none"))
    scored = len(MUTANTS) - len(EQUIVALENT)
    print(f"\n{killed}/{scored} mutants killed ({len(EQUIVALENT)} equivalent, not scored)")
    return 0 if killed == scored else 1


if __name__ == "__main__":
    sys.exit(main())
