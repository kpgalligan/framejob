#!/usr/bin/env python3
"""Road map creator-jobs CU10 — the recorder polishes on landing, the ungranted rows (spec §11
CU-100…CU-103), measured through the app's own sources. No app, no grant, no media, no prompt.

    python3 tools/proof/cu10_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`cu10_probe.swift` is built with `swift_build.py`'s line over `--sources` (it links
`libframejob_core.a`, so `make rust` first) and run once; everything it writes lands under
`tools/proof/work/cu10-probe/<tree|mutant-NAME>/`. Prints `<ID> pass|fail — <detail>` per row,
then `scores: N/M`.

Rows:
  B0  the probe builds.
  Q1  `RecorderPanelController.shared`, never shown: "When it lands:" with Zoom in on clicks, then
      Show shortcuts and Speed up typing under it with no label, directly after the Record
      shortcuts note and directly before Rate; each box's action `controlChanged:` on the panel,
      its tooltip naming its step.
  Q2  the three keys absent read on, on, off; a change writes all three; stored values restore;
      absent again reads on, on, off.
  Q3  a display row: Zoom in on clicks live, the other two only with Record shortcuts ticked;
      greyed boxes keep their values; `applyPolish` gives the choice the same gates (a box off is
      off); Microphone Only and Camera grey all three and ask none; a countdown greys all three.
  Q4  `RecordingPolish.commands(of:)` in `allCases` order; the titles the undo steps' names;
      `RecordingChoice()` asks none.
  Q5  `decide`: no clips → drop (even while enhancing); enhancing → wait (even past the limit);
      ready and not busy → run; not ready or busy → wait; 299 s waits, 300 s gives up.
  Q6  `recordingPolish`: each argument refused without `place`, then the last two without `keys:
      "shortcuts"`, in the order auto_zoom, shortcut_overlays, speed_up_typing, in CU-102 (b)'s
      sentences, exact; `recordingSourceKind` refuses the three by name with voice_over (in
      `voiceOverScreenOnlyArguments` order, a null not given) and with camera.

Mutants (spec §11 CU-103): `place-admitted` and `keys-admitted` (Q6), `enhance-ignored` and
`ready-ignored` (Q5), `absent-zoom-off` (Q2) and `shortcuts-without-keys` (Q3).

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
WORK = ROOT / "tools/proof/work/cu10-probe"
ROWS = ["B0", "Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
SWIFT_ROWS = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...]) — spec §11 CU-103.
MUTANTS = {
    "place-admitted": (["Q6"], [
        ("AgentServer+RecordingPolish.swift",
         "            if !place { throw ToolError(message: Self.polishNeedsPlace(command)) }\n",
         "            if false && !place {\n"
         "                throw ToolError(message: Self.polishNeedsPlace(command))\n"
         "            }\n")]),
    "keys-admitted": (["Q6"], [
        ("AgentServer+RecordingPolish.swift",
         "            if command != .autoZoom, keys != .shortcuts {\n",
         "            if false, command != .autoZoom, keys != .shortcuts {\n")]),
    "enhance-ignored": (["Q5"], [
        ("RecordingPolish.swift",
         "        if enhancing { return .wait }\n",
         "")]),
    "ready-ignored": (["Q5"], [
        ("RecordingPolish.swift",
         "        if ready && !busy { return .run(command, clips) }\n",
         "        if !busy { return .run(command, clips) }\n")]),
    "absent-zoom-off": (["Q2"], [
        ("RecorderPanelController+Polish.swift",
         "        polishBoxes.autoZoom.state = stored(Self.autoZoomKey, absent: true)\n",
         "        polishBoxes.autoZoom.state = stored(Self.autoZoomKey, absent: false)\n")]),
    "shortcuts-without-keys": (["Q3"], [
        ("RecorderPanelController+Polish.swift",
         "            polishBoxes.shortcutOverlays.state == .on && choice.keys == .shortcuts\n",
         "            polishBoxes.shortcutOverlays.state == .on\n")]),
}


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/cu10_probe.swift", entry)
    binary = here / "cu10-probe"
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
