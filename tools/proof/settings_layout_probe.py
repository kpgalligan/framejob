#!/usr/bin/env python3
"""Issue batch B71: the Settings window's structure after the redesign —
Assistant above Transcription, each key label naming its service, each
heading's ⓘ holding its pane's explanation (spec §11 SH-5) at 13 pt in the
label colour, no long paragraph left in the window, and the ⓘ's hover and
click policy — measured through the app's own sources.

    python3 tools/proof/settings_layout_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`settings_layout_probe.swift` is built with `menu_undo_probe.py`'s swiftc
line (without `-D REELCUT_DEV_TOOLS`) over `--sources` and run once, in a
process of its own, under `tools/proof/work/settings-layout/`, killed at a
120 s wall. The fixture is `SettingsWindowController` over two
`MemoryStore`s, an empty environment, an absent spend folder and a scratch
`UserDefaults` suite, never shown; nothing on this Mac is read or written.
Every string a row compares is a literal, never the app's own constant.
Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  B0   the probe builds.
  L1   `content.arrangedSubviews` is exactly [assistantPane,
       transcriptionPane], in that order, and `content.spacing` is 24.
  L2   each pane's first arranged subview is a stack of [headingLabel,
       infoButton]; the headings read "Assistant" and "Transcription".
  L3   the row holding each key field opens with "Anthropic API key:" /
       "AssemblyAI API key:"; both empty placeholders read "Paste your key";
       no text field in the window reads exactly "API key:".
  L4   each ⓘ's `infoText` is its owner's `explanation()`; its accessibility
       label is "About Assistant" / "About Transcription" and its help the
       text; no `toolTip`; its popover's `infoLabel` holds the text at 13 pt in
       `NSColor.labelColor` and sits in the popover's content view; the
       Transcription text names the upload, the delete, "$0.21 an hour" and
       "2026-09-17", the Assistant text the compaction threshold and "Changing
       either setting keeps the conversation."
  L5   no text field in the window holds "uploaded to AssemblyAI" or
       "compaction threshold", none runs past 200 characters, and the spend
       note is still present and visible.
  L6   a synthesized mouse-entered sets `hoverPending`; a mouse-exited before
       the delay clears it, and the popover is not showing.
  L7   the click policy, on a button in no window (so nothing is shown):
       hover → .hover; press → .held; exit → still .held; press → .closed;
       press → .held; hideInfo → .closed; hover then exit → .closed.
  L8   the transient guard's hit test, on a button in an unshown window:
       `isOnIcon` is true at its centre, false 40 pt outside it, and false at
       its centre in another window.

Mutants (`--mutant`), each a literal found exactly once in the written code:
  order-swapped       the panes added Transcription first: must fail L1.
  bare-label          the AssemblyAI label back to "API key:": must fail L3.
  grey-info           the popover's label in `DS.textFaint`: must fail L4.
  paragraph-back      a wrapping label holding the Transcription explanation
                      added to its pane: must fail L5.
  exit-keeps-pending  `mouseExited` does not cancel the hover: must fail L6.
  click-closes-hover  a press on a hover-opened popover closes it: must fail L7.
  guard-off           `isOnIcon` always answers false: must fail L8.

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
WORK = ROOT / "tools/proof/work/settings-layout"
ROWS = ["B0", "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "order-swapped": (["L1"], [
        ("SettingsWindowController.swift",
         "for pane in [assistantPane, transcriptionPane] {",
         "for pane in [transcriptionPane, assistantPane] {")]),
    "bare-label": (["L3"], [
        ("SettingsWindowController.swift",
         'static let keyLabel = "AssemblyAI API key:"',
         'static let keyLabel = "API key:"')]),
    "grey-info": (["L4"], [
        ("SettingsInfoButton.swift",
         "infoLabel.textColor = DS.textStrong",
         "infoLabel.textColor = DS.textFaint")]),
    "paragraph-back": (["L5"], [
        ("SettingsWindowController.swift",
         "for view in [header, keyRow, regionRow, statusLabel, buttons] {",
         "for view in [header, keyRow, regionRow, statusLabel,\n"
         "            NSTextField(wrappingLabelWithString: Self.explanation()), buttons] {")]),
    "exit-keeps-pending": (["L6"], [
        ("SettingsInfoButton.swift",
         "        cancelHover()\n        if infoState == .hover { hideInfo() }\n",
         "        if infoState == .hover { hideInfo() }\n")]),
    "click-closes-hover": (["L7"], [
        ("SettingsInfoButton.swift",
         "case .hover: infoState = .held",
         "case .hover: hideInfo()")]),
    "guard-off": (["L8"], [
        ("SettingsInfoButton.swift",
         "return bounds.contains(convert(locationInWindow, from: nil))",
         "return false")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `menu_undo_probe.py`'s swiftc line,
    without the dev-tools flag (nothing here needs it)."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/settings_layout_probe.swift", entry)
    binary = here / "settings-layout-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).stdout.strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = run(["swiftc", "-sdk", sdk,
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
    rest = [row for row in wanted if row != "B0"]
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
