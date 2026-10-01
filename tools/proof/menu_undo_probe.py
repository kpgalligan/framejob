#!/usr/bin/env python3
"""Issue batch B51 (#184 item 2): `UIMenu.perform` (the dev tools'
`perform_menu_item`) opens no eager document undo group for a target with an
undo manager of its own — the Assistant composer — measured through the app's
own sources; the vetoed-field case recorded; a document commit made during
such a target's action is still one step (F1).

    python3 tools/proof/menu_undo_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`menu_undo_probe.swift` is built with `relink_sheet_probe.py`'s swiftc line
plus `-D REELCUT_DEV_TOOLS` (`UIMenu` exists only there, as `v2_menu.py`
builds its probe) over `--sources` and run once, in a process of its own,
under `tools/proof/work/menu-undo/`, killed at a 120 s wall. No media. Prints
`<ID> pass|fail — <detail>` per row, then the probe's `pasteboard:` answer
(`restored`, or `left: <why>`; the probe copies the general pasteboard before
its Cut and puts it back only if no one else wrote it since), then `scores:
N/M`.

Rows:
  B0   the probe builds.
  M1   CONTROL: the document window's `undoManager` is the document's; an
       editable `NSTextField`'s field editor answers a manager of its own
       (AppKit's `NSCellUndoManager`, measured) and so does
       `AssistantComposerField().textView`, neither the document's; with the composer
       first responder, `UIMenu.target` of a `cut:` item is that text view;
       one applied edit undone leaves canUndo false and canRedo true.
  M2   (#184.2) the composer holds "hello", all selected; `UIMenu.perform`
       runs Cut then Paste on the target `UIMenu.target` resolves: the text
       goes "" then "hello", the composer's own manager can undo, and the
       document's canUndo, canRedo, redoActionName and groupingLevel are what
       they were before.
  V1   RECORD: a field whose delegate's `control(_:textShouldBeginEditing:)`
       answers false, holding "hello", first responder and all selected, the
       document's redo re-armed; Cut then Paste through `UIMenu.perform`.
       Passes when the field still reads "hello"; the detail prints the
       document's undo state before and after each.
  F1   (#184.2, the review's finding 1) a field whose delegate commits two
       ungrouped document edits (`applyEdit`) in `controlTextDidChange`,
       first responder and all selected; Paste through `UIMenu.perform` on
       its field editor (its own manager), then one grouped edit: the
       document's groupingLevel is back where it began after the Paste, one
       undo takes back only the later edit (canUndo true, undo "Field
       Commit"), and a second takes back both of the field's commits, the
       stack where it was before.

Mutants (`--mutant`):
  no-own-manager-guard   the guard's condition never holds: must fail M2.
  own-manager-bare-send  the guard's arm sends with no pending group: must
                         fail F1.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed; a build failure is B0's FAIL there. A `--mutant` run exits 1 when
every row the mutant names failed (caught), 0 when one passed (survived),
and 2 when the control could not be performed: the copy's `before` text not
found exactly once, the copy did not build, or a named row was not scored.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/menu-undo"
ROWS = ["B0", "M1", "M2", "V1", "F1"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "no-own-manager-guard": (["M2"], [
        ("UIMenu.swift",
         "if let own = (target as? NSResponder)?.undoManager, own !== manager {",
         "if let own = (target as? NSResponder)?.undoManager, own !== manager, false {")]),
    "own-manager-bare-send": (["F1"], [
        ("UIMenu.swift",
         "return document.inUndoGroupIfRegistered { NSApp.sendAction(action, to: target, from: item) }",
         "return NSApp.sendAction(action, to: target, from: item)")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `relink_sheet_probe.py`'s swiftc line
    with `-D REELCUT_DEV_TOOLS`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/menu_undo_probe.swift", entry)
    binary = here / "menu-undo-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).stdout.strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                  "-target", "arm64-apple-macos26.0",
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
    """(the probe's answer, None), or (None, why)."""
    try:
        result = run([str(binary)], timeout=WALL, cwd=here)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        answer = json.loads(result.stdout)
        answer["rows"]
        return answer, None
    except (ValueError, KeyError, TypeError):
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
    pasteboard = None
    rest = [row for row in wanted if row != "B0"]
    if rest:
        if binary is None:
            for row in rest:
                results[row] = (False, "not run: the probe did not build")
        else:
            answer, why = probe(binary, here)
            rows = (answer or {}).get("rows") or []
            pasteboard = (answer or {}).get("pasteboard")
            for row in rest:
                found = next((a for a in rows if a.get("id") == row), None)
                if found is None:
                    not_scored.append(row)
                    results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
                else:
                    results[row] = (bool(found["pass"]), found["detail"])

    for row in wanted:
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    if pasteboard is not None:
        print(f"pasteboard: {pasteboard}")
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
