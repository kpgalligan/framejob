#!/usr/bin/env python3
"""Road map creator-jobs CU1a: the cursor file's capture buffer, anchor, writer and
read-back, measured through the app's own sources on synthetic segments (spec §11 CU-10,
CU-14…CU-17); and CU1b1's recorder rows K0, K10–K14 and K16 (spec §11 CU-11…CU-13, CU-18,
CU-19). No app, no grant, no media.

    python3 tools/proof/cursor_capture_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`cursor_capture_probe.swift` is built with `swift_build.py`'s line over `--sources` (it
links `libframejob_core.a`, so `make rust` first) and run once; every file it writes lands
under `tools/proof/work/cursor-capture-probe/<tree|mutant-NAME>/`. Prints
`<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  B0  the probe builds.
  C1  two segments with a pause between them, the second fed no geometry after open: each
      file holds only its own samples, its times from its own anchor, and one geometry
      entry at least (the second's its own opening one).
  C2  three distinct geometries and one repeat fed after open: exactly three entries past
      the opening one, which is the start's.
  C3  `CursorAnchor.choose` answers E2 when given and E1 when not, and the header names the
      one chosen with its host time.
  C4  a corrupted body (version 2, truncated, a typed key's label) leaves neither
      `.fjcursor` (one was there before) nor `.partial`, and the problem contains the
      sentence `ReelCursor(data:)` throws for the same bytes.
  C5  every synthetic fixture is accepted by the core, and its decoded counts and values
      equal the ones the probe states: negative scroll deltas, a hidden span wholly before
      the anchor (dropped) and one across it (clipped), two overlapping and two touching
      hidden spans (one span each), a `.none` segment fed images, the latest move, image
      change and geometry before the anchor kept at t 0 with every event before it
      dropped, images interned and changes deduped, events sorted.
  C6  content 1001 × 701 with a 1002 × 702 movie: `movie_size` [1002, 702].

CU1b1's rows (spec §11 CU-11…CU-13, CU-18, CU-19):
  K0  `ScreenFrameWatchRule.attaches` is camera || cursor over the four cases.
  K10 `CursorSegments`: 120 polls over 12 positions give 12 moves, and a nil records none.
  K11 a segment opened after the pointer stopped has one move at t 0, at the last polled
      point, and its opening geometry is the last fed.
  K12 `AgentServer.segmentFields` writes `cursor_path`, `cursor_image` and `cursor_problem`
      (only the problem without a file, none for a bare segment); `cursorSegmentsNote` joins
      the problems in order; `resultNotes` carries it last.
  K13 `ScreenFrameWatch.geometry(from:)` reads the four keys, and answers nil when one is
      missing.
  K14 an `NSEvent(cgEvent:)` click stamped 5e9 ns answers host 5.0, its point and count; a
      scroll its point deltas and host.
  K16 `failsStart` is true with a camera and false without; `cursorProblem` answers the
      writer's sentence, else CU-13's naming the movie and the reason, else nil.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row failed; a build
failure is B0's FAIL there. A `--mutant` run exits 1 when every row the mutant names failed
(caught), 0 when one passed (survived), and 2 when the control could not be performed: the
copy's `before` text not found exactly once, the copy did not build, or a named row was not
scored.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/cursor-capture-probe"
ROWS = ["B0", "C1", "C2", "C3", "C4", "C5", "C6", "K0", "K10", "K11", "K12", "K13", "K14", "K16"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "buffer-not-reset": (["C1"], [
        ("CursorCaptureBuffer.swift", "        samples = Samples()\n", "        _ = Samples()\n")]),
    "geometry-once": (["C2"], [
        ("CursorCaptureBuffer.swift", "guard isOpen, geometry != samples.lastGeometry else",
         "guard isOpen, samples.geometries.count < 2 else")]),
    "e1-over-e2": (["C3"], [
        ("CursorValues.swift",
         "e2.map { CursorAnchor(kind: .e2, host: $0) } ?? CursorAnchor(kind: .e1, host: e1)",
         "CursorAnchor(kind: .e1, host: e1)")]),
    "readback-skipped": (["C4"], [
        ("CursorFileWriter.swift", "_ = try ReelCursor(data: Data(contentsOf: partial))",
         "_ = try Data(contentsOf: partial)")]),
    "movie-size-from-content": (["C6"], [
        ("CursorCaptureBuffer.swift", "movieSize: [movieSize.width, movieSize.height]",
         "movieSize: [start.contentSize.width, start.contentSize.height]")]),
    # CU1b1 (spec §11 CU-11…CU-13, CU-18).
    "watch-camera-only": (["K0"], [
        ("ScreenFrameWatch.swift",
         "static func attaches(camera: Bool, cursor: Bool) -> Bool { camera || cursor }",
         "static func attaches(camera: Bool, cursor: Bool) -> Bool { camera }")]),
    "poll-every-sample": (["K10"], [
        ("CursorCapture.swift", "guard let point, point != lastPoint else { return }",
         "guard let point else { return }")]),
    "no-seed-at-open": (["K11"], [
        ("CursorCapture.swift",
         "        if let lastPoint { buffer.move(to: lastPoint, host: host) }\n", "")]),
    "cursor-note-dropped": (["K12"], [
        ("AgentServer+RecordingResult.swift", "            result.cursorSegmentsNote,\n", "")]),
    "event-clock-arrival": (["K14"], [
        ("CursorCapture.swift", "event.timestamp > 0 ? Double(event.timestamp) / 1e9 : arrival",
         "arrival")]),
    "watch-failure-refuses": (["K16"], [
        ("ScreenFrameWatch.swift", "static func failsStart(camera: Bool) -> Bool { camera }",
         "static func failsStart(camera: Bool) -> Bool { true }")]),
    "watch-lost-dropped": (["K16"], [
        ("ScreenRecorder+Cursor.swift", "        guard let watchLost else { return nil }\n",
         "        guard let watchLost = nil as String? else { return nil }\n")]),
}


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/cursor_capture_probe.swift", entry)
    binary = here / "cursor-capture-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + ("; ".join(error.diagnostics[:8]) or str(error))
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; None and why when a `before` text is not
    found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before.strip()}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """The rows the probe answered, or None and why."""
    try:
        result = subprocess.run([str(binary), str(here / "files")], capture_output=True,
                                text=True, timeout=WALL)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    named = MUTANTS[args.mutant][0] if args.mutant else []
    wanted = args.only.split(",") if args.only else (["B0"] + named if args.mutant else ROWS)
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = args.sources.resolve()
    if args.mutant:
        why = mutate(sources, args.mutant, here / "Sources")
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        sources = here / "Sources"

    results = {}
    binary, why = build(sources, here)
    results["B0"] = (binary is not None, why or f"built from {sources}")
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    not_scored = []
    answered, why = probe(binary, here) if binary else (None, "the probe did not build")
    for row in (r for r in wanted if r != "B0"):
        answer = next((a for a in answered or [] if a.get("id") == row), None)
        if answer is None:
            not_scored.append(row)
            results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
        else:
            results[row] = (bool(answer["pass"]), answer["detail"])

    for row in wanted:
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in wanted if results[row][0])
    print(f"scores: {passed}/{len(wanted)}")
    if not args.mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row in not_scored or row not in results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) not scored: {', '.join(lost)}")
        return 2
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
