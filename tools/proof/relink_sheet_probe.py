#!/usr/bin/env python3
"""Issue batch B29 (#180.2): the missing-media sheet alerts each refused
relink's sentence after its one grouped commit, measured through the app's
own sources.

    python3 tools/proof/relink_sheet_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`relink_sheet_probe.swift` is built with `cache_pass_probe.py`'s swiftc line
over `--sources` and run once, in a process of its own, over copies of
`tools/proof/media/` under `tools/proof/work/relink-sheet/`, killed at a
120 s wall. Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

The fixture is an untitled document with three video media whose files are
gone; the sheet chooses toneA.m4a for the first, toneB.m4a for the second
(both refused: another kind) and A.mov for the third (applied). A media's
"expected sentence" is the core's own refusal of that relink applied alone
to the pre-commit project.

Rows:
  B0   the probe builds.
  S0   CONTROL: the fixture's three media are missing (`missingMedia`).
  S1   within 20 s the third media's path is the A.mov copy's and the other
       two are unchanged; the undo action is "Relink Media", and one undo
       restores the third's path and leaves nothing to undo.
  S2   an alert attaches holding the first media's sentence, after it is
       ended a second holding the second's, and after that none within 2 s.
  S3   when the first alert attached, the project already held the third
       media's new path (the alerts follow the commit).
  S4   after S1's undo, a second sheet chooses a garbage `.png` (unreadable,
       no ffmpeg question) for the first, toneA.m4a for the second and A.mov
       for the third: an alert holding the unreadable file's error, held
       until the commit lands and 0.5 s more (a person reading it), after
       it is ended a second holding the second media's sentence, none after
       that within 2 s, and the third media relinked.
  C1   CONTROL, run first: the Media tab's door (`relinkMedia` with no flag)
       posts exactly one `projectDocumentDidRefuse` with the first media's
       sentence, and no sheet attaches within 3 s.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed; a build failure is B0's FAIL there. A `--mutant` run exits 1 when
every row the mutant names failed (caught), 0 when one passed (survived),
and 2 when the control could not be performed: the copy's `before` text not
found exactly once, the copy did not build, or a named row was not scored.
A missing medium exits 2 in either.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/relink-sheet"
MEDIA = ROOT / "tools/proof/media"
NEEDED = ("toneA.m4a", "toneB.m4a", "A.mov")
ROWS = ["B0", "S0", "S1", "S2", "S3", "S4", "C1"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "sheet-silent": (["S2"], [
        ("RelinkSheetController.swift", "document.relinkMedia(choices, alertingRefusals: true)",
         "document.relinkMedia(choices)")]),
    "unreadable-at-once": (["S4"], [
        ("ProjectDocument+Import.swift",
         "if alertingRefusals { failed.append(error) } else { self.present(error) }",
         "self.present(error)")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `cache_pass_probe.py`'s swiftc line."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/relink_sheet_probe.swift", entry)
    binary = here / "relink-sheet-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).stdout.strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = run(["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
                  "-module-name", "Reelcut", "-import-objc-header",
                  str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
                  "-L", str(lib.parent), "-lreelcut_core", *swift, str(entry),
                  "-o", str(binary)])
    if result.returncode:
        lines = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(lines[:8] or [result.stderr[-600:]])
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
    request.write_text(json.dumps({"media": str(here / "media"), "work": str(here / "rows")}))
    try:
        result = run([str(binary), str(request)], timeout=WALL)
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
    missing = [name for name in NEEDED if not (MEDIA / name).exists()]
    if missing:
        print("instrument failure: missing medium " + ", ".join(missing))
        return 2
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
    media = here / "media"
    media.mkdir()
    for name in NEEDED:
        shutil.copy2(MEDIA / name, media / name)
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
    rest = [row for row in wanted if row != "B0"]
    if rest:
        if binary is None:
            for row in rest:
                results[row] = (False, "not run: the probe did not build")
        else:
            rows, why = probe(binary, here)
            for row in rest:
                answer = next((a for a in rows or [] if a.get("id") == row), None)
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
