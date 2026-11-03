#!/usr/bin/env python3
"""Road map creator-jobs CU3c — the recorder stops burning the pointer, the ungranted rows (spec §11
CU-31, CU-36), measured through the app's own sources. No app, no grant, no media, no prompt.

    python3 tools/proof/cu3c_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`cu3c_probe.swift` is built with `swift_build.py`'s line over `--sources` (it links
`libframejob_core.a`, so `make rust` first) and run once; everything it writes lands under
`tools/proof/work/cu3c-probe/<tree|mutant-NAME>/`. Prints `<ID> pass|fail — <detail>` per row,
then `scores: N/M`.

Rows:
  B0  the probe builds.
  P1  `RecorderPanelController.shared`, never shown: the grid row "Cursor:" directly after System
      Audio and directly before Show Clicks; its popup's items "Separate" and "In the picture",
      their `representedObject` `separate` and `in_picture`; its action `controlChanged:`.
  P2  never chosen (the key `""`): a display row shows Separate, `cursor` nil and
      `effectiveCursor` separate; the Window row with a pick (`.picked`) shows In the picture
      after `refreshSizeNote()`; a tool's `.window` choice is In the picture; the Window row with
      no pick (`selectedScreen` nil), the popup first set to In the picture by hand, is put back to
      Separate by `refreshSizeNote()` (its early-return path).
  P3  a pick through the popup writes `FrameJobRecordingCursor` (`in_picture`, then `separate`)
      and survives a source change; never chosen, `persistChoices` writes `""` whatever the popup
      shows; `in_picture` restores to the pick, `""` and `bogus` to nil.
  P4  Microphone Only and Camera grey the popup with its value kept, their choice's `cursor` nil;
      a display row makes it live again, the pick kept.
  P5  `RecordingCursor.defaultFor`: display separate, window and picked `windowDefault`
      (in_picture), voice-over and camera separate; a choice beats the default;
      `RecordingChoice().cursor` nil; the raw values.
  P6  `cursorNoAnchorProblem` and `cursorProblem`'s writer arm end with `cursorSeparateLost` for
      `separate: true` and equal today's sentences for false (and by default); the watch-lost and
      nil arms are the same for both.
  P7  `RecordingLanding.wantsRipples` true only with Show Clicks, Cursor Separate (chosen, or a
      display's default) and a picture — false In the picture, without Show Clicks, for a picked
      window's default and for a voice-over; `remainderActionName` of one segment with no voice and
      no camera is `ripplesActionName`, "Cursor Clicks", and with a voice "Add Microphone" (a
      row beyond the spec's six: `land_recording`'s movie always has a voice, so B3b over MCP
      cannot reach the "Cursor Clicks" name).

Mutants (spec §11 CU-36 (f)): `window-default-separate` (P2, P5), `persist-shown-cursor` (P3),
`sync-after-returns` (`syncCursorPopup()` moved to `refreshSizeNote()`'s end; P2) and
`separate-lost-dropped` (`separate:` ignored in `cursorNoAnchorProblem`; P6).

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
WORK = ROOT / "tools/proof/work/cu3c-probe"
ROWS = ["B0", "P1", "P2", "P3", "P4", "P5", "P6", "P7"]
SWIFT_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...]) — spec §11 CU-36 (f).
MUTANTS = {
    "window-default-separate": (["P2", "P5"], [
        ("RecordingSetup.swift",
         "    static let windowDefault: RecordingCursor = .inPicture\n",
         "    static let windowDefault: RecordingCursor = .separate\n")]),
    "persist-shown-cursor": (["P3"], [
        ("RecorderPanelController+Choices.swift",
         "        defaults.set(cursorChosen?.rawValue ?? \"\", forKey: Self.cursorKey)\n",
         "        defaults.set(\n"
         "            cursorPopup.selectedItem?.representedObject as? String ?? \"\",\n"
         "            forKey: Self.cursorKey)\n")]),
    "sync-after-returns": (["P2"], [
        ("RecorderPanelController+Choices.swift",
         "        syncCursorPopup()\n        if voiceOverSelected {\n",
         "        if voiceOverSelected {\n"),
        ("RecorderPanelController+Choices.swift",
         " pixels\"\n    }\n}\n",
         " pixels\"\n        syncCursorPopup()\n    }\n}\n")]),
    "separate-lost-dropped": (["P6"], [
        ("ScreenRecorder+Cursor.swift",
         "            + \"so its times have nothing to count from.\" + (separate ? cursorSeparateLost : \"\")\n",
         "            + \"so its times have nothing to count from.\"\n")]),
}


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/cu3c_probe.swift", entry)
    binary = here / "cu3c-probe"
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
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not "
              f"build")
        return 2
    not_scored = []
    swift_wanted = [r for r in wanted if r in SWIFT_ROWS]
    answered, why = (probe(binary, here) if binary else (None, why or "the probe did not build")) \
        if swift_wanted else ([], None)
    for row in swift_wanted:
        answer = next((a for a in answered or [] if a.get("id") == row), None)
        if answer is None:
            not_scored.append(row)
            results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
        else:
            results[row] = (answer["pass"], answer["detail"])

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
