#!/usr/bin/env python3
"""Issue batch B85 phase 2 (#103, spec §11 G-32): Edit ▸ Paste Graphic
Properties — the menu item, its validator arm and what the door sends —
measured through the app's own sources, with ⌥⌘V held to what it was.

    python3 tools/proof/paste_graphic_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`paste_graphic_probe.swift` is built with `harness/build.sh`'s swiftc line
(`-D REELCUT_DEV_TOOLS`: `UIMenu` exists only there) over `--sources` and run
once, in a process of its own, under `tools/proof/work/paste-graphic/probe/`,
killed at a 120 s wall. No media, no module file, no instance, no MCP. Every
Copy and paste goes over a PRIVATE named pasteboard the probe releases at
exit; `NSPasteboard.general` is never written (K6), and the menu's action is
sent that private pasteboard as its sender (K8). Prints
`<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  K0   the probe builds.
  K1   Edit's item after "Paste Attributes" is "Paste Graphic Properties",
       its action `pasteGraphicProperties:`, no key equivalent, there once;
       `UIMenu.verdicts` holds the selector as `none` (plain).
  K2   the validator arm: false on an empty pasteboard, false with a payload
       and only the text clip selected, true with a payload and a graphic
       selected, false with nothing selected; `pasteAttributes:` answers what
       it did (false, true, false).
  K3   graphic A copied; selection {graphic B of the same module, graphic C
       of another, the text clip}; the door: B's props equal A's; B's name,
       width, height, in, length and everything outside `graphic` as before;
       A, C and the text clip as they were (canonical JSON of each clip out
       of the project text); the undo step is "Paste Graphic Properties";
       one undo restores the project text byte for byte.
  K4   nothing to do — the copied graphic onto {C, text}, then a copied text
       clip onto B: each leaves the project text, the undo state and the
       window's sheet (none) as they were.
  K5   ⌥⌘V unchanged: A's opacity set, A copied, `pasteAttributes(from:)`
       onto B: B's `video` equals A's and B's `graphic` is what it was.
  K6   `NSPasteboard.general.changeCount` is what it was at start.
  K7   CONTROL (no Swift mutant: the decision is the core's, held by
       `core/tests/paste_graphic.rs`' T11 and its mutant). A's copied payload
       read back from the private pasteboard, its props given an array
       value, written back. Onto {C, text}: project, undo state and no
       sheet, as before. Onto B, only after `windowForSheet === window` is
       asserted: a sheet within 5 s whose text holds the core's sentence,
       project and undo state as before; the probe ends the sheet.
  K8   the menu's ACTION: K1's selector, `pasteGraphicProperties:`, SENT to
       the controller with the private pasteboard as its sender
       (`perform(_:with:)`, what a menu item does with its action, the
       sender apart), A copied and {B, C, text} selected, A's video unlike
       B's: K3's claims again — B's props equal A's; B's name, width,
       height, in, length and everything outside `graphic` as before; A, C
       and the text clip as they were; the undo step is "Paste Graphic
       Properties"; one undo restores the project text and the undo name
       that was there.

K3, K4 and K7 call the door's body, `pasteGraphicProps(from:)`, and K1 holds
the item to the action's selector. K8 joins the two: the action reads a
pasteboard SENDER in place of the general pasteboard (a menu sends its
`NSMenuItem`, so the app reads the general one), which is the seam K8 sends
the private pasteboard through. What stays a person's is the item chosen by
hand over the real clipboard, `docs/manual-checks.md` TL-8 step 4.

Mutants (`--mutant`), each an edit to a COPY of the sources:
  door-no-groups            the door omits `groups`: must fail K3.
  door-strict               the door sends `skipMissing: false`: must fail K3.
  validator-any-selection   the arm asks for any selection: must fail K2.
  attributes-names-graphic  ⌥⌘V sends `groups: ["video", "graphic"]`: must
                            fail K5.
  action-empty              the action's body is emptied: must fail K8.
  action-pastes-attributes  the action's body is ⌥⌘V's, `pasteAttributes`
                            over the same sender — the one confusion the
                            owner's decision forbids: must fail K8. (The
                            sender is kept so the mutant reads the private
                            pasteboard and pastes A's look; with the default
                            it would read the owner's clipboard.)

Exit (rule R, `menu_undo_probe.py`'s): a plain run exits 0 iff every row
passed and 1 when a row failed; a build failure is K0's FAIL there. A
`--mutant` run exits 1 when every row the mutant names failed (caught), 0
when one passed (survived), and 2 when the control could not be performed:
the copy's `before` text not found exactly once, the copy did not build, or
a named row was not scored (an instrument failure included).
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/paste-graphic/probe"
ROWS = ["K0", "K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8"]
WALL = 120
CLIPBOARD = "EditorViewController+Clipboard.swift"
# The one statement of the menu's action, `pasteGraphicProperties(_:)`.
ACTION_BODY = "pasteGraphicProps(from: sender as? NSPasteboard ?? .general)"

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "door-no-groups": (["K3"], [
        (CLIPBOARD,
         'groups: ["graphic"], skipMissing: true))',
         'skipMissing: true))')]),
    "door-strict": (["K3"], [
        (CLIPBOARD,
         'groups: ["graphic"], skipMissing: true))',
         'groups: ["graphic"], skipMissing: false))')]),
    "validator-any-selection": (["K2"], [
        (CLIPBOARD,
         "&& selectedClips.contains { $0.source == .graphic && $0.graphic != nil }",
         "&& !document.selection.isEmpty")]),
    "attributes-names-graphic": (["K5"], [
        (CLIPBOARD,
         ".pasteAttributes(clips: Array(document.selection), payload: payload))",
         ".pasteAttributes(clips: Array(document.selection), payload: payload, "
         'groups: ["video", "graphic"]))')]),
    "action-empty": (["K8"], [(CLIPBOARD, ACTION_BODY, "")]),
    "action-pastes-attributes": (["K8"], [
        (CLIPBOARD, ACTION_BODY,
         "pasteAttributes(from: sender as? NSPasteboard ?? .general)")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `harness/build.sh`'s swiftc line."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/paste_graphic_probe.swift", entry)
    binary = here / "paste-graphic-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).stdout.strip()
    try:
        result = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                      "-target", "arm64-apple-macos26.0",
                      "-module-name", "Reelcut", "-import-objc-header",
                      str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
                      "-L", str(lib.parent), "-lreelcut_core", *swift, str(entry),
                      "-o", str(binary)], timeout=900)
    except subprocess.TimeoutExpired:
        return None, "swiftc: no answer within 900 s"
    if result.returncode:
        lines = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(lines[:8] or [result.stderr[-600:]])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; None, or why when a
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
    wanted = args.only.split(",") if args.only else (["K0"] + named if args.mutant else ROWS)
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
    results["K0"] = (binary is not None, why or f"built from {sources}")
    if binary is None and args.mutant:
        print(f"K0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    not_scored = []
    rest = [row for row in wanted if row != "K0"]
    if rest:
        if binary is None:
            for row in rest:
                results[row] = (False, "not run: the probe did not build")
        else:
            answer, why = probe(binary, here)
            rows = (answer or {}).get("rows") or []
            for row in rest:
                found = next((a for a in rows if a.get("id") == row), None)
                if found is None:
                    not_scored.append(row)
                    results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
                elif found.get("instrument"):
                    not_scored.append(row)
                    results[row] = (False, "INSTRUMENT — " + found["detail"])
                else:
                    results[row] = (bool(found["pass"]), found["detail"])

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
