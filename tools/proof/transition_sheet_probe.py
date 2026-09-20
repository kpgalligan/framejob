#!/usr/bin/env python3
"""Clip ▸ Transition ▸ at a cut with no footage to spare — the sheet and its
Shift Clips Left button, measured (2026-09-16).

What changed. The menu at a HARD CUT sends `add_transition`, which builds the
overlap from the two clips' unused handles (spec §11, R5-3). Two whole files
placed back to back — every screencast's first cut — have no handle on either
side, so the op answered `None` and the menu gave a bare beep with nothing on
screen, which is what was reported. `setTransitionKindCommand` now TRIES the
batch first and, when no `add_transition` in it would land, puts up a sheet
saying why; its Shift Clips Left button re-sends those cuts with `ripple`
(R5-3's amendment, the same date), which slides each incoming clip and
everything after it on unlocked tracks left by the same half second.

Why a probe. A sheet, a menu item's validation and an undo step are all
AppKit, reachable from no MCP tool — `add_transition`'s `ripple` over MCP is
the core's, and `core/tests/ripple_transition.rs` owns the core's rules. What
is asserted here is the COMMAND: when the sheet appears and when it must not,
what it says, what each button does to the document, and that a shift is ONE
undo step that restores the document byte for byte. So it is
`phase9_probe.py`'s instrument: a `main.swift` compiled against the whole of
`app/Sources` with `harness/build.sh`'s swiftc line, an editor in a real
window, cached on modification times, a build failure scored as a FAILURE.
`window.endSheet(_:returnCode:)` presses a button, which runs the sheet's own
completion exactly as a click does.

Sections:
  1. two whole clips: the menu item is enabled, the command changes nothing
     and registers no undo step, and the sheet appears with its title, its
     explanation and its two buttons;
  2. Cancel leaves the document alone;
  3. Shift Clips Left: the incoming clip and the clip after it move left by
     the menu's half second, the outgoing clip does not, the chosen kind lands,
     and one undo named "Add Transition" restores the document exactly;
  4. two cuts in one selection: the plural title, both overlaps, one undo;
  5. the sheet must NOT appear — a split clip (handles: the transition lands
     shorter or whole), and choosing the kind a clip already has (a beep);
  6. a mixed selection — one clip already overlapping, one at a whole cut:
     the overlapping clip's kind changes AND the sheet explains the other;
  7. a locked track: the sheet appears, and Shift Clips Left changes nothing;
  8. two chosen cuts whose shifts COLLIDE — the first ripple slides the second
     cut's incoming clip over a predecessor that does not slide with it, so
     the second op's cut is an overlap before its own op runs. Added by the
     E1 reader review (road map 5 §12, R3·1): the batch used to be built from
     one snapshot, the second `add_transition` came back `Err`, and the throw
     took the first shift with it.

Mutation-tested on the working tree with the probe rebuilt; the scores are
in `tools/proof/README.md`.

Needs `ffmpeg`, `swiftc` and `core/target/release/libreelcut_core.a`. No port.
Run from anywhere:

    python3 tools/proof/transition_sheet_probe.py
"""

import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "transition-sheet")
PROBE = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")

# One frame at 30 fps and the menu's half second, in ticks.
FRAME = 20_000
HALF = 300_000
WHOLE = 3_600_000  # the fixture movie: six seconds

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def section(title):
    print(f"\n{title}")


def make_movie():
    """A six-second 30 fps movie with sound. Opened as a new project it is one
    whole clip, and every further clip of it is whole too."""
    os.makedirs(WORK, exist_ok=True)
    path = os.path.join(WORK, "whole.mp4")
    if os.path.exists(path):
        return path, None
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-y",
         "-t", "6", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30",
         "-t", "6", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
         "-map", "0:v", "-map", "1:a", "-c:v", "h264", "-pix_fmt", "yuv420p", "-c:a", "aac",
         path],
        capture_output=True, text=True)
    if result.returncode != 0:
        return None, "ffmpeg failed: " + result.stderr.strip()[:300]
    return path, None


PROBE_SOURCE = r'''
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

let movie = URL(fileURLWithPath: CommandLine.arguments[1])

/// An editor over the movie opened as a new project: one whole clip on one
/// track, plus `extra` more whole clips appended back to back.
func editor(extra: Int) -> (ProjectDocument, EditorViewController, [ClipSnapshot]) {
    let document = ProjectDocument()
    try! document.read(from: movie, ofType: "public.mpeg-4")
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.2)
    let controller = document.windowControllers.first!.contentViewController as! EditorViewController
    for _ in 0..<extra {
        let last = document.project.snapshot.clips.max { $0.end < $1.end }!
        document.applyEdit(
            "setup", .addClip(track: last.track, media: document.project.snapshot.media[0].id, at: last.end))
    }
    return (document, controller, clips(document))
}

func clips(_ document: ProjectDocument) -> [ClipSnapshot] {
    document.project.snapshot.clips.sorted { $0.start < $1.start }
}

func item(_ tag: Int) -> NSMenuItem {
    let item = NSMenuItem(title: "", action: #selector(EditorViewController.setTransitionKind(_:)), keyEquivalent: "")
    item.tag = tag
    return item
}

func placement(_ document: ProjectDocument) -> [[String: Any]] {
    clips(document).map {
        ["id": Int($0.id), "start": $0.start, "end": $0.end,
         "kind": $0.transitionIn?.kind.rawValue ?? NSNull()]
    }
}

/// The attached sheet's texts and buttons, or nil when there is none.
func sheet(_ controller: EditorViewController) -> [String: Any]? {
    guard let sheet = controller.view.window?.attachedSheet else { return nil }
    func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
    let views = sheet.contentView.map(walk) ?? []
    return [
        "texts": views.compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty },
        "buttons": views.compactMap { ($0 as? NSButton)?.title }.filter { !$0.isEmpty },
    ]
}

func press(_ controller: EditorViewController, _ code: NSApplication.ModalResponse) {
    if let window = controller.view.window, let attached = window.attachedSheet {
        window.endSheet(attached, returnCode: code)
    }
    spin(0.6)
}

/// Runs the menu command for `tag` over `selection` and reports what it did
/// before any button is pressed.
func command(_ document: ProjectDocument, _ controller: EditorViewController, _ selection: [UInt32], tag: Int) -> [String: Any] {
    document.selection = Set(selection)
    let json = document.project.json
    let undoName = document.undoManager?.undoActionName ?? ""
    let enabled = controller.validateUserInterfaceItem(item(tag))
    controller.setTransitionKind(item(tag))
    spin(0.6)
    return ["enabled": enabled, "changed": document.project.json != json,
            "undoNameUnchanged": (document.undoManager?.undoActionName ?? "") == undoName,
            "sheet": sheet(controller) ?? NSNull(), "before": json]
}

var answer: [String: Any] = [:]
let kinds = TransitionKind.allCases
let chosen = 3
answer["chosenKind"] = kinds[chosen].rawValue
answer["kindAtTag0"] = kinds[0].rawValue

// 1–3. Two whole clips and one after them; Cancel, then Shift Clips Left.
for (label, code) in [("cancel", NSApplication.ModalResponse.alertSecondButtonReturn), ("shift", .alertFirstButtonReturn)] {
    let (document, controller, three) = editor(extra: 2)
    var run = command(document, controller, [three[1].id], tag: chosen)
    let before = run.removeValue(forKey: "before") as! String
    run["placementBefore"] = placement(document)
    press(controller, code)
    run["placementAfter"] = placement(document)
    run["undoName"] = document.undoManager?.undoActionName ?? ""
    run["unchangedAfterButton"] = document.project.json == before
    if label == "shift" {
        document.undoManager?.undo()
        spin(0.3)
        run["oneUndoRestores"] = document.project.json == before
    }
    answer[label] = run
}

// 4. Two cuts in one selection.
do {
    let (document, controller, three) = editor(extra: 2)
    var run = command(document, controller, [three[1].id, three[2].id], tag: chosen)
    let before = run.removeValue(forKey: "before") as! String
    press(controller, .alertFirstButtonReturn)
    run["placementAfter"] = placement(document)
    run["undoName"] = document.undoManager?.undoActionName ?? ""
    document.undoManager?.undo()
    spin(0.3)
    run["oneUndoRestores"] = document.project.json == before
    answer["twoCuts"] = run
}

// 5. The sheet must not appear: a split clip, and a kind already there.
do {
    let (document, controller, one) = editor(extra: 0)
    document.applyEdit("setup", .split(clips: nil, at: one[0].start + (one[0].end - one[0].start) / 2))
    var run = command(document, controller, [clips(document)[1].id], tag: 0)
    run.removeValue(forKey: "before")
    run["placementAfter"] = placement(document)
    answer["split"] = run
    press(controller, .alertSecondButtonReturn)
}
do {
    let (document, controller, two) = editor(extra: 1)
    document.applyEdit("setup", .moveClip(clips: [two[1].id], delta: -300_000))
    document.applyEdit("setup", .setTransition(clip: two[1].id, kind: kinds[0]))
    var run = command(document, controller, [two[1].id], tag: 0)
    run.removeValue(forKey: "before")
    answer["sameKind"] = run
    press(controller, .alertSecondButtonReturn)
}

// 6. Mixed: clip 2 at a whole cut, clip 3 already overlapping clip 2.
do {
    let (document, controller, three) = editor(extra: 2)
    document.applyEdit("setup", .moveClip(clips: [three[2].id], delta: -300_000))
    var run = command(document, controller, [three[1].id, three[2].id], tag: chosen)
    run.removeValue(forKey: "before")
    run["placementAfterCommand"] = placement(document)
    run["undoNameAfterCommand"] = document.undoManager?.undoActionName ?? ""
    answer["mixed"] = run
    press(controller, .alertSecondButtonReturn)
}

// 7. A locked track: the sheet, and a shift that cannot move anything.
do {
    let (document, controller, two) = editor(extra: 1)
    document.applyEdit("setup", .setTrack(track: two[0].track, locked: true))
    var run = command(document, controller, [two[1].id], tag: chosen)
    let before = run.removeValue(forKey: "before") as! String
    press(controller, .alertFirstButtonReturn)
    run["unchangedAfterButton"] = document.project.json == before
    answer["locked"] = run
}

// 8. Two chosen cuts whose shifts COLLIDE: the first ripple pushes the
//    second cut's incoming clip over a predecessor that does not move with
//    it, so by the time the second op runs that cut is already an overlap.
do {
    let (document, controller, two) = editor(extra: 1)
    let media = document.project.snapshot.media[0].id
    let first = two[0].track
    document.applyEdit("setup", .addTrack(index: 1, name: "Second"))
    let second = document.project.snapshot.tracks.map { $0.id }.first { $0 != first }!
    // P spans the first cut, so the first ripple cannot move it; Q sits at
    // the second cut, so the first ripple does move it.
    document.applyEdit("setup", .addClip(track: second, media: media, at: 1_800_000))
    document.applyEdit("setup", .addClip(track: second, media: media, at: 5_400_000))
    let onSecond = document.project.snapshot.clips.filter { $0.track == second }
        .sorted { $0.start < $1.start }
    let p = onSecond[0].id
    let q = onSecond[1].id
    var run = command(document, controller, [two[1].id, q], tag: chosen)
    let before = run.removeValue(forKey: "before") as! String
    run["ids"] = ["a": Int(two[0].id), "b": Int(two[1].id), "p": Int(p), "q": Int(q)]
    press(controller, .alertFirstButtonReturn)
    run["changedAfterButton"] = document.project.json != before
    run["placementAfter"] = placement(document)
    run["undoName"] = document.undoManager?.undoActionName ?? ""
    run["sheetAfterButton"] = sheet(controller) ?? NSNull()
    document.undoManager?.undo()
    spin(0.3)
    run["oneUndoRestores"] = document.project.json == before
    answer["collide"] = run
}

let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
'''


def build_probe():
    """`phase7_chrome.py`'s `build_probe`, less the shader: nothing here draws
    a frame. Answers (binary, None) or (None, reason)."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "sheetprobe")
    entry = os.path.join(PROBE, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    fonts = os.path.join(PROBE, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(PROBE, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    sources = sorted(os.path.join(SOURCES, name) for name in os.listdir(SOURCES)
                     if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in sources + [entry, lib]
    ):
        print(f"probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        tail = [line for line in result.stderr.strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {result.returncode}: "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    print(f"probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary, movie):
    if binary is None:
        return None, "the probe did not build"
    try:
        result = subprocess.run([binary, movie], capture_output=True, text=True,
                                timeout=300, cwd=PROBE)
    except subprocess.TimeoutExpired:
        return None, "the probe timed out"
    for line in result.stdout.splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {result.returncode}): {result.stderr.strip()[-300:]}"


def by_id(placements):
    return {p["id"]: p for p in placements}


def main():
    movie, why = make_movie()
    binary, build_error = build_probe()
    answer, error = (None, why or build_error) if movie is None or binary is None \
        else run_probe(binary, movie)
    if answer is None:
        section("the probe")
        check("the sheet probe answered", False, error)
        print(f"\n{passed}/{passed + failed} checks passed")
        sys.exit(1)

    chosen = answer["chosenKind"]

    section("1 — two whole clips: nothing lands, and the sheet says why")
    run = answer["cancel"]
    sheet = run["sheet"] or {}
    check("the kind's menu item is enabled at the hard cut", run["enabled"] is True)
    check("the command changes nothing", run["changed"] is False)
    check("…and registers no undo step", run["undoNameUnchanged"] is True)
    check("a sheet appears", bool(sheet), "no sheet attached")
    texts = sheet.get("texts", [])
    check("its title names the missing footage at THIS cut",
          "There’s no extra footage at this cut for a transition." in texts, str(texts))
    check("its explanation says a whole file has no footage to give",
          any("uses its whole file has none" in t for t in texts), str(texts))
    check("…and what the button will do, and that the project gets shorter",
          any("sliding the second clip" in t and "half a second" in t and "shorter" in t
              for t in texts), str(texts))
    check("its buttons are Shift Clips Left, then Cancel",
          sheet.get("buttons") == ["Shift Clips Left", "Cancel"], str(sheet.get("buttons")))

    section("2 — Cancel")
    check("Cancel leaves the document byte-identical", run["unchangedAfterButton"] is True)

    section("3 — Shift Clips Left")
    run = answer["shift"]
    before, after = by_id(run["placementBefore"]), by_id(run["placementAfter"])
    a, b, c = [p["id"] for p in run["placementBefore"]]
    check("the outgoing clip does not move", after[a] == before[a], f"{before[a]} → {after[a]}")
    check("the incoming clip moves left by the menu's half second",
          after[b]["start"] == before[b]["start"] - HALF and after[b]["end"] == before[b]["end"] - HALF,
          f"{before[b]} → {after[b]}")
    check("the clip after it moves with it",
          after[c]["start"] == before[c]["start"] - HALF, f"{before[c]} → {after[c]}")
    check("the two clips now overlap by half a second", before[a]["end"] - after[b]["start"] == HALF)
    check(f"the chosen kind ({chosen}) is on the incoming clip", after[b]["kind"] == chosen, str(after[b]))
    check("the edit is named Add Transition", run["undoName"] == "Add Transition", run["undoName"])
    check("ONE undo restores the document byte for byte", run["oneUndoRestores"] is True)

    section("4 — two cuts in one selection")
    run = answer["twoCuts"]
    texts = (run["sheet"] or {}).get("texts", [])
    check("the title is plural", "There’s no extra footage at these cuts for a transition." in texts,
          str(texts))
    check("…and the explanation says each cut", any("at each cut" in t for t in texts), str(texts))
    placements = run["placementAfter"]
    check("both cuts overlap by half a second",
          placements[0]["end"] - placements[1]["start"] == HALF
          and placements[1]["end"] - placements[2]["start"] == HALF, str(placements))
    check("both incoming clips carry the chosen kind",
          placements[1]["kind"] == chosen and placements[2]["kind"] == chosen, str(placements))
    check("ONE undo restores both", run["oneUndoRestores"] is True and run["undoName"] == "Add Transition",
          run["undoName"])

    section("5 — where the sheet must not appear")
    run = answer["split"]
    placements = run["placementAfter"]
    check("a split clip has handles: the transition lands", run["changed"] is True
          and placements[1]["kind"] == answer["kindAtTag0"], str(placements))
    check("…as the full half second, from both handles",
          placements[0]["end"] - placements[1]["start"] == HALF, str(placements))
    check("…and no sheet appears", run["sheet"] is None, str(run["sheet"]))
    run = answer["sameKind"]
    check("choosing the kind a clip already has changes nothing", run["changed"] is False)
    check("…and puts up no sheet (a beep)", run["sheet"] is None, str(run["sheet"]))

    section("6 — a mixed selection")
    run = answer["mixed"]
    placements = run["placementAfterCommand"]
    check("the clip already overlapping takes the chosen kind", placements[2]["kind"] == chosen,
          str(placements))
    check("…the whole cut is still a whole cut", placements[1]["kind"] is None
          and placements[0]["end"] == placements[1]["start"], str(placements))
    check("…as one Set Transition step", run["undoNameAfterCommand"] == "Set Transition",
          run["undoNameAfterCommand"])
    check("…and the sheet explains the one cut that could not take a transition",
          "There’s no extra footage at this cut for a transition."
          in (run["sheet"] or {}).get("texts", []), str(run["sheet"]))

    section("7 — a locked track")
    run = answer["locked"]
    check("the sheet appears on a locked track too", bool(run["sheet"]), str(run["sheet"]))
    check("…and Shift Clips Left changes nothing there", run["unchangedAfterButton"] is True)

    section("8 — two cuts whose shifts collide")
    run = answer["collide"]
    ids = run["ids"]
    landed = {clip["id"]: clip for clip in run["placementAfter"]}
    texts = (run["sheet"] or {}).get("texts", [])
    check("both cuts reach the sheet",
          "There\u2019s no extra footage at these cuts for a transition." in texts, str(texts))
    check("Shift Clips Left changes the document", run["changedAfterButton"] is True,
          "nothing landed: the second op's Err threw the batch away")
    check("…and puts up no error sheet",
          run["sheetAfterButton"] is None, str(run["sheetAfterButton"]))
    check("the first cut overlaps by half a second",
          landed[ids["a"]]["end"] - landed[ids["b"]]["start"] == HALF,
          f"{landed[ids['a']]} {landed[ids['b']]}")
    check("…and so does the second, which the FIRST ripple made",
          landed[ids["p"]]["end"] - landed[ids["q"]]["start"] == HALF,
          f"{landed[ids['p']]} {landed[ids['q']]}")
    check("both incoming clips carry the chosen kind",
          landed[ids["b"]]["kind"] == chosen and landed[ids["q"]]["kind"] == chosen,
          f"{landed[ids['b']]} {landed[ids['q']]}")
    check("…as ONE undo step named Add Transition that restores the document",
          run["undoName"] == "Add Transition" and run["oneUndoRestores"] is True,
          run["undoName"])

    print(f"\n{passed}/{passed + failed} checks passed")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
