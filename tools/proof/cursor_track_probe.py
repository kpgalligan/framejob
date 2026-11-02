#!/usr/bin/env python3
"""Road map creator-jobs CU2: a cursor file evaluated through the app's own `ReelCursor.query`
and its typed requests, and the process-wide `CursorTracks` registry (spec §11 CU-20…CU-26).
No app, no grant, no media.

    python3 tools/proof/cursor_track_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`cursor_track_probe.swift` is built with `swift_build.py`'s line over `--sources`, with
`FRAMEJOB_DEV_TOOLS` (it links `libframejob_core.a`, so `make rust` first; optimised when
`RC_PROOF_APP=release`, so the Release run times optimised Swift), and run once with
`-RCDevCursorLoadHold 2`; every file it writes lands under
`tools/proof/work/cursor-track-probe/<tree|mutant-NAME>/`. Prints `<ID> pass|fail|skip —
<detail>` per row, then `scores: N/M` over the rows not skipped.

Rows:
  B0  the probe builds.
  T1  (skipped by name) the core's mapping against K1's granted recordings, ≤ 1.5 px p95:
      needs CU1b's granted recordings; owed.
  T2  a one-hour worst case (432,000 moves, 3,600 clicks as 7,200 records, 20,000 typed marks,
      40 images, 3,600 image changes) through `ReelCursor.query`: the median `state` over
      1,000 prebuilt requests ≤ 20 µs at a prepared smoothing and at an unprepared one (which
      answers raw), and `prepare` at 1 ≤ 1 s, each run twice.
  T3  with the dev hold at 2 s: `ready` answers nil at once and returns in under 50 ms; the
      track is there after the hold; exactly one landing posts over 4 s; a second `want`
      posts none.
  T4  `path` at 10 Hz equals hand-computed positions within 1e-9 px: a collinear uniform run
      (raw), a hold and a click pin (smoothed 0.5).
  T5  (a) one owner wants 10 fixture paths at once: all 10 land and `wait` on the 10 returns;
      (b) one path, each smoothing 0.1…0.6 wanted alone in turn under one owner: after the
      sixth 0.1 and 0.2 are not ready and 0.3…0.6 are; wanting 0.1 again lands it again,
      posting once.

Exit (rule R): a plain run exits 0 iff every row not skipped passed and 1 when one failed; a
build failure is B0's FAIL there. A `--mutant` run exits 1 when every row the mutant names
failed (caught), 0 when one passed (survived), and 2 when the control could not be performed:
the copy's `before` text not found exactly once, the copy did not build, or a named row was
not scored.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/cursor-track-probe"
ROWS = ["B0", "T1", "T2", "T3", "T4", "T5"]
SKIPPED = {"T1": "needs CU1b's granted recordings, K1; owed"}
WALL = 240

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "ready-blocks": (["T3"], [
        ("CursorTracks.swift",
         "func ready(url: URL, smoothing: Double) -> ReelCursor? {\n        condition.lock()",
         "func ready(url: URL, smoothing: Double) -> ReelCursor? {\n        work.sync {}\n"
         "        condition.lock()")]),
    "evict-pinned": (["T5"], [
        ("CursorTracks.swift", "let pinned = Set(wants.values.joined().map {",
         "let pinned = Set(wants.values.joined().prefix(0).map {")]),
}


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/cursor_track_probe.swift", entry)
    binary = here / "cursor-track-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    optimize = os.environ.get("RC_PROOF_APP") == "release"
    try:
        swift_build.build(sources=swift + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"], optimize=optimize)
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
        result = subprocess.run([str(binary), str(here / "files"), "-RCDevCursorLoadHold", "2"],
                                capture_output=True, text=True, timeout=WALL)
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
    measured = [r for r in wanted if r != "B0" and r not in SKIPPED]
    answered, why = probe(binary, here) if binary and measured else (None,
                                                                     "the probe did not build")
    for row in measured:
        answer = next((a for a in answered or [] if a.get("id") == row), None)
        if answer is None:
            not_scored.append(row)
            results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
        else:
            results[row] = (bool(answer["pass"]), answer["detail"])

    scored = [row for row in wanted if row not in SKIPPED]
    for row in wanted:
        if row in SKIPPED:
            print(f"{row} skip — {SKIPPED[row]}")
            continue
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in scored if results[row][0])
    print(f"scores: {passed}/{len(scored)}")
    if not args.mutant:
        return 0 if passed == len(scored) else 1
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
