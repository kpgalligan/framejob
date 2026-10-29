#!/usr/bin/env python3
"""Issue batch B57 (#210): which `beginSheetModal(for:)` sites can be asked
for while another sheet is attached to the editor window, and whether the
document's alert queue keeps their order, measured through the app's own
sources.

    python3 tools/proof/sheet_queue_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`sheet_queue_probe.swift` is built with `swift_build.py`'s line over
`--sources` and run once, in a process of its own, under
`tools/proof/work/sheet-queue/<tree|mutant-NAME>/`, killed at a 240 s wall.
Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

The fixture is an untitled document whose `EditorViewController` is the
content of a 1440×900 window owned by the document's window controller. E1
and E2 are `present(_:)` of "probe alert one" and "probe alert two"; an
attached sheet is ended 0.3 s after it attaches unless a row holds it.

Rows:
  B0   the probe builds.
  C0   CONTROL: `windowForSheet` is the window, no sheet is attached, and
       `addMediaFiles:` validates true.
  V1   with E1 attached, each of the eleven editor actions that lead to a
       site validates false.
  P1   an `NSOpenPanel` sheet is up, E1 is presented and waits; the panel is
       cancelled, and its completion handler records whether E1 is attached
       and asks an `NSAlert` "probe handler": E1 was not attached at the
       handler, then [probe handler], [E1], none more within 2 s.
  P2   P1 with an `NSSavePanel`.
  X1   ExportSheet:582's shape: a bare sheet presented and dismissed, an
       `NSSavePanel` sheet asked for, E1: E1 does not attach while the
       panel is up, and after it ends E1 within 2 s, none more.
  S1   E1 attached, `frameSaved(.failure)` (SaveFrame :209), E1 held 1 s,
       E2 presented, E1 ended: [E1], [probe frame], [E2], none more in 2 s.
  S2   as S1 with `addImageBackground(from: garbage.png)` (AddClips :179),
       held 2 s; the site's text is `probeBlocking`'s error for the file.
  S3   as S1 with `placeImageBackground` of the 4×4 PNG at width 70000
       (AddClips :236); the site's text is what `add_media` throws.
  S4   as S1 with `consolidateAfterSave` on the document given a file URL
       and no media (Consolidate :67); the site's text is what
       `MediaConsolidator.plan` throws.

A P1, P2 or X1 panel that does not attach within 3 s is an instrument
failure (`instrument: panel did not attach within 3 s`), never the row's
verdict.

Mutants (`--mutant`):
  no-sheet-wait   the drain ignores an attached sheet (`if false {`).

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed, an instrument failure included; a build failure is B0's FAIL there.
A `--mutant` run exits 1 when every row the mutant names failed (caught), 0
when one passed (survived), and 2 when the control could not be performed:
the copy's `before` text not found exactly once, the copy did not build, a
named row was not scored, or any scored row is an instrument failure.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/sheet-queue"
ROWS = ["B0", "C0", "V1", "P1", "P2", "X1", "S1", "S2", "S3", "S4"]
WALL = 240

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "no-sheet-wait": (["S1", "S2", "S3", "S4", "P1", "P2", "X1"], [
        ("ProjectDocument+Alerts.swift", "if window.attachedSheet != nil {", "if false {")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/sheet_queue_probe.swift", entry)
    binary = here / "sheet-queue-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; None and why when a
    `before` text is not found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """The rows the probe answered, or None and why."""
    request = here / "request.json"
    request.write_text(json.dumps({"work": str(here / "rows")}))
    try:
        result = run([str(binary), str(request)], timeout=WALL)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def score(results, row, good, detail, *, instrument=False):
    """Keeps a row's verdict with whether its own comparison ran (rule R)."""
    results[row] = (bool(good) and not instrument, detail, instrument)


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
    score(results, "B0", binary is not None, why or f"built from {sources}",
          instrument=binary is None)
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    not_scored = []
    rest = [row for row in wanted if row != "B0"]
    if rest:
        if binary is None:
            for row in rest:
                score(results, row, False, "not run: the probe did not build", instrument=True)
        else:
            rows, why = probe(binary, here)
            for row in rest:
                answer = next((a for a in rows or [] if a.get("id") == row), None)
                if answer is None:
                    not_scored.append(row)
                    score(results, row, False,
                          f"no row: {why or 'the probe did not answer it'}", instrument=True)
                else:
                    score(results, row, answer["pass"], answer["detail"],
                          instrument=bool(answer.get("instrument")))

    for row in wanted:
        good, detail, _ = results[row]
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
    broken = [row for row in wanted if results[row][2]]
    if broken:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"instrument failure in {', '.join(broken)}")
        return 2
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
