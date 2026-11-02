#!/usr/bin/env python3
"""Road map creator-jobs CU6 — record shortcuts, the ungranted rows (spec §11 CU-60…CU-63),
measured through the app's own sources. No app, no grant, no media, no prompt.

    python3 tools/proof/cursor_keys_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`cursor_keys_probe.swift` is built with `swift_build.py`'s line over `--sources` (it links
`libframejob_core.a`, so `make rust` first) and run once; everything it writes lands under
`tools/proof/work/cursor-keys-probe/<tree|mutant-NAME>/`. Prints `<ID> pass|fail — <detail>`
per row, then `scores: N/M`.

Rows:
  B0  the probe builds.
  Y1  `RecordingGrant.inputMonitoringStep` equals `screenStep` over all eight inputs; the pane
      URL is `x-apple.systempreferences:…Privacy_ListenEvent`; the refusal is CU-3's sentence
      plus `launchClause`, with no "relaunch"; `inputMonitoringNote(opened:)` is the sentence,
      " If Frame Job is not in its list, add it with +.", the opened sentence when opened, and
      `launchClause`.
  Y2  `RecorderStatusItem`: `title(elapsed:paused:keys: false)` equals the old title (string
      and attributes); keyed, `⌨︎` follows the mark with no colour of its own;
      `menuTitles(paused:keys: true)` is ["Recording keyboard shortcuts", Pause|Resume, Stop]
      and `menuTitles(paused:)` the old two; `itemLength(keys:)` holds every title at W1's
      seven times for both marks and equals its formula; `itemLength` is the keyless one.
  Y6  `CursorKeyFilter` over 74 synthetic key-downs: ⌘⇧4 `cmd+shift+4` code 21; ⌃⌘Q, ⌥←, ⌥→,
      ⌥↓, ⌥↑, ⌥⇧Tab, ⌥⌫, ⌥⌦, ⌥Return, ⌥Enter, ⌥Esc, ⌘+ (`cmd+plus`), ⌘F5, ⌘⇧F19 spelled;
      an empty, whitespace or control character `key<code>`; ⇧A, ⌥E, ⌥⇧E, ⌥Space, bare
      letters, Return, Tab, ←, F5 alone and three auto-repeats (⌘Z among them) typed marks;
      `isShortcut` true exactly for the shortcuts; every one with `secure: true` nothing; the
      flags' four modifiers; `CursorCapture.keyEvent(from:)` on a real key-down, its character
      nil.
  Y7  `CursorSegments` fed through the filter (two shortcuts with ⌥← among them, three typed
      marks, one under secure input), `.none`, then two keys between `end` and the next
      `open`: segment 0's body is accepted by `ReelCursor(data:)` with exactly those columns
      (`typed` holding `t` alone); segment 1 holds only its own typed mark.
  Y8  `RecorderPanelController.shared`, never shown, under a spy: the box "Record shortcuts"
      off by default and its note (`recordShortcutsSentence`, 11 pt) in the two grid rows
      directly under Show Clicks; `keys` follows the box, is persisted under
      `FrameJobRecordingKeys` and restored; Microphone Only and Camera answer `.off` with the
      box greyed and its value kept. Presses: granted reads Screen Recording → Input Monitoring
      → Microphone and counts down; a launchd first press asks once, remembers, opens
      `Privacy_ListenEvent` and shows `inputMonitoringNote(opened: true)`; the second asks no
      more and opens again; a shell launch asks every press and never remembers; no Screen
      Recording grant never reads Input Monitoring; the box off never reads it. And, from the
      sources: `beginIfGranted`'s guard asks Screen Recording, Input Monitoring, Camera,
      Microphone in that order.
  Y9  from the sources: both `RecorderStatusItem` constructions (the panel's
      `recordingDidStart` and the tool's `RecordingToolChrome.show`) pass `keys:
      recorder.recordsKeys`.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row failed; a build
failure is B0's FAIL there. A `--mutant` run exits 1 when every row the mutant names failed
(caught), 0 when one passed (survived), and 2 when the control could not be performed: the
copy's `before` text not found exactly once, the copy did not build, or a named row was not
scored.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/cursor-keys-probe"
ROWS = ["B0", "Y1", "Y2", "Y6", "Y7", "Y8", "Y9"]
SWIFT_ROWS = ["Y1", "Y2", "Y6", "Y7", "Y8"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...]) — spec §11 CU-63.
MUTANTS = {
    "secure-ignored": (["Y6"], [
        ("CursorKeyFilter.swift", "        if secure { return .none }\n", "")]),
    "typed-with-identity": (["Y6", "Y7"], [
        ("CursorKeyFilter.swift", "        guard isShortcut(event) else { return .typed }\n",
         "        guard isShortcut(event) else {\n"
         "            return .shortcut(keys: spelled(event), code: event.keyCode)\n"
         "        }\n")]),
    "shift-modifier": (["Y6"], [
        ("CursorKeyFilter.swift",
         "        if event.modifiers.contains(.cmd) || event.modifiers.contains(.ctrl) { return true }\n",
         "        if event.modifiers.contains(.cmd) || event.modifiers.contains(.ctrl)\n"
         "            || event.modifiers.contains(.shift)\n"
         "        {\n            return true\n        }\n")]),
    "option-rule-dropped": (["Y6"], [
        ("CursorKeyFilter.swift",
         "        return event.modifiers.contains(.opt) && optionKeyCodes.contains(event.keyCode)\n",
         "        return false\n")]),
    "indicator-omitted": (["Y2"], [
        ("RecorderStatusItem.swift",
         "            title.append(\n                NSAttributedString(\n"
         "                    string: \" \" + keysGlyph, attributes: [.font: NSFont.systemFont(ofSize: size)]))\n",
         "")]),
    "press-skips-input-monitoring": (["Y8"], [
        ("RecorderPanelController+Recording.swift",
         "        guard checkScreenRecordingGrant(), checkInputMonitoringGrant(),\n",
         "        guard checkScreenRecordingGrant(),\n")]),
}


def strip_comments(text):
    """The code without `//` comments (a `//` inside a string literal is rare enough here)."""
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def structural(sources):
    """Y8's source half and Y9: {row: [problem, ...]}."""
    problems = {"Y8": [], "Y9": []}

    def code(name):
        path = sources / name
        return strip_comments(path.read_text()) if path.exists() else ""

    recording = code("RecorderPanelController+Recording.swift")
    start = recording.find("private func beginIfGranted()")
    body = recording[start:recording.find("\n    }\n", start)] if start >= 0 else ""
    order = ["checkScreenRecordingGrant()", "checkInputMonitoringGrant()", "checkCameraGrant()",
             "checkMicrophoneGrant()"]
    places = [body.find(token) for token in order]
    if -1 in places or places != sorted(places):
        problems["Y8"].append(f"beginIfGranted's grants are not in the order {order}: {places}")
    did_start = recording[recording.find("func recordingDidStart()"):]
    did_start = did_start[:did_start.find("\n    }\n")]
    if "RecorderStatusItem(\n            keys: recorder.recordsKeys," not in did_start:
        problems["Y9"].append("the panel's recordingDidStart does not pass keys: "
                              "recorder.recordsKeys")
    chrome = code("AgentServer+RecordingChrome.swift")
    if "RecorderStatusItem(\n            keys: recorder.recordsKeys," not in chrome:
        problems["Y9"].append("the tool's chrome does not pass keys: recorder.recordsKeys")
    cursor = code("ScreenRecorder+Cursor.swift")
    if "var recordsKeys: Bool { session?.cursor?.recordsKeys ?? false }" not in cursor:
        problems["Y9"].append("ScreenRecorder.recordsKeys is not the session's capture's")
    return problems


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/cursor_keys_probe.swift", entry)
    binary = here / "cursor-keys-probe"
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
    extra = structural(sources)
    binary = None
    why = None
    if any(row in SWIFT_ROWS or row == "B0" for row in wanted):
        binary, why = build(sources, here)
        results["B0"] = (binary is not None, why or f"built from {sources}")
        if binary is None and args.mutant:
            print(f"B0 fail — {why}")
            print(f"mutant {args.mutant}: the control could not be performed — the copy did "
                  f"not build")
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
            problems = ([] if answer["pass"] else [answer["detail"]]) + extra.get(row, [])
            results[row] = (not problems, "; ".join(problems) if problems else answer["detail"])
    if "Y9" in wanted:
        results["Y9"] = (not extra["Y9"], "; ".join(extra["Y9"]) or
                         "both status-item constructions pass keys: recorder.recordsKeys")

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
