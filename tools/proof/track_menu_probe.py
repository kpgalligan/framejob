#!/usr/bin/env python3
"""The track context menu — a right-click on a track's header or empty lane.

Before it, the only way to delete an EMPTY track that was not the front-most
was to select a clip on it first, and an empty track has none: Track ▸
Remove Track acts on `currentTrack`, which is the first selected clip's
track or else the front-most. The menu (`TimelineView+TrackMenu.swift`)
names its track by the click instead, and carries the header's four toggles
beside Remove Track.

No MCP call can reach a right-click — `remove_track` and `set_track` already
have their tools, and what is new is which track a CLICK names — so this is
`CLAUDE.md`'s instrument for app STRUCTURE with no caller a script can
reach: a probe compiled out of `app/Sources` over `swift_build.py`'s line
(`marquee_probe.py`'s builder, one probe along), a build failure
scored as a FAILURE rather than an exit. It puts a real
`EditorViewController` in an offscreen `NSWindow` over a three-track
fixture — front and middle EMPTY, the back one holding a text clip — and
sends synthetic right-mouse-down events through the content view's own
`menu(for:)`, so the wiring (`onRemoveTrack` → `removeTrackCommand`) is on
the path, then performs items and reads the document back.

What it measures:

  * **Where a menu opens.** A header, a header's toggle button and an empty
    lane each open the menu for THEIR row's track; a clip, the ruler and the
    room below the lanes open none.
  * **What it says.** Hide Video, Mute Audio, Lock Track, Solo, Matte, a
    separator, Remove Track — the toggles checked from the clicked track's
    own flags, every item naming that track's id, and the Matte submenu
    (spec §11 MT-7) listing the five modes for that track with Off checked
    (`matte_chrome_probe.py` measures what its rows do).
  * **What the toggles do.** Hide Video on the middle track hides the middle
    track and nothing else, as one undo step.
  * **Remove Track on an empty track that is neither front-most nor
    selected** removes exactly it, with a clip selected on ANOTHER track
    (the case Track ▸ Remove Track gets wrong) — and undo brings it back.
  * **A track that holds clips asks first**: the item puts up the sheet and
    removes nothing until Remove is pressed, then the track and its clip go.
  * **The last track** gets a disabled Remove Track.

Made to fail on purpose, twice, when the probe had 22 rows (before the
three Matte rows, mattes MT4): `removeTrackCommand` ignoring its `id`
(falling back to `currentTrack`, the front track) takes the three rows that
say WHICH track went — the middle one, no clip lost, the back one after the
sheet — and nothing else (19/22); the content view's `menu(for:)` answering
nil takes the five menu rows, the fresh-track row and every row that
performs an item through a right-click (8/22 left: the build, the fixture,
the hit test, the no-menu row, an undo with nothing to undo and the
last-track row, which asks `trackMenu(for:)` directly).

Not measured: ⌃-click, which AppKit routes to `menu(for:)` itself before any
`mouseDown` — a person at the machine confirms it (#48).

    python3 tools/proof/track_menu_probe.py
"""

import json
import os
import subprocess
import sys

import swift_build

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROBE = os.path.join(ROOT, "tools", "proof", "work", "track-menu-probe")

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


# --------------------------------------------------------------------------
# The probe. It drives one editor and prints one JSON object.

PROBE_SOURCE = r'''
import AppKit
import Foundation

_ = NSApplication.shared

let SEC: Ticks = 600_000

var answer: [String: Any] = [:]
func fail(_ why: String) -> Never {
    answer["error"] = why
    write(answer)
    exit(0)
}

func write(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

func turn(_ n: Int = 4) {
    for _ in 0..<n { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
}

// ---- the fixture: back (text clip A), middle (empty), front (text clip F
// on the far right, so a click at 1 s in the front lane is empty) --------
let document = ProjectDocument()
guard let back = document.project.snapshot.tracks.first?.id else { fail("no track") }
document.performGroupedEdit("Tracks", [.addTrack(index: 1), .addTrack(index: 2)])
let tracks = document.project.snapshot.tracks.map { $0.id }
guard tracks.count == 3, tracks[0] == back else { fail("the fixture has \(tracks.count) tracks") }
let middle = tracks[1]
let front = tracks[2]
document.performGroupedEdit("Clips", [
    .addTextClip(track: back, at: 0, duration: 10 * SEC),
    .addTextClip(track: front, at: 20 * SEC, duration: 4 * SEC),
])
guard let clipA = document.project.snapshot.clips(onTrack: back).first?.id,
      let clipF = document.project.snapshot.clips(onTrack: front).first?.id
else { fail("the fixture's clips did not land") }
answer["ids"] = ["back": back, "middle": middle, "front": front]

let controller = EditorViewController(document: document)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
window.setContentSize(NSSize(width: 1400, height: 900))
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)
for _ in 0..<8 { turn(1); controller.view.layoutSubtreeIfNeeded() }
guard let timeline = controller.timeline else { fail("the editor has no timeline") }
let content = timeline.content

func refresh() {
    controller.refreshFromDocument(isLive: false)
    turn(2)
    controller.view.layoutSubtreeIfNeeded()
}

// Content-view points. Display row 0 is the FRONT track.
func rowY(_ row: Int) -> CGFloat {
    timeline.layout.rowTop(row) + timeline.layout.trackHeight(row: row) / 2
}
func laneX(_ seconds: Double) -> CGFloat { timeline.layout.x(for: Ticks(seconds * Double(SEC))) }
func headerLabelPoint(_ row: Int) -> CGPoint {
    // The first point across the header, mid-row, that is not a button.
    let height = timeline.layout.trackHeight(row: row)
    let y = rowY(row)
    for x in stride(from: CGFloat(4), to: TimelineLayout.headerWidth, by: 2) {
        let local = CGPoint(x: x, y: y - timeline.layout.rowTop(row))
        if TimelineHeaderView.button(at: local, height: height) == nil {
            return CGPoint(x: timeline.pinnedX + x, y: y)
        }
    }
    return CGPoint(x: timeline.pinnedX + 4, y: y)
}
func headerButtonPoint(_ row: Int) -> CGPoint? {
    let height = timeline.layout.trackHeight(row: row)
    let top = timeline.layout.rowTop(row)
    for x in stride(from: CGFloat(0), to: TimelineLayout.headerWidth, by: 1) {
        for dy in stride(from: CGFloat(0), to: height, by: 1)
        where TimelineHeaderView.button(at: CGPoint(x: x, y: dy), height: height) != nil {
            return CGPoint(x: timeline.pinnedX + x, y: top + dy)
        }
    }
    return nil
}

func kind(_ hit: TimelineHit) -> String {
    switch hit {
    case .header(let row): return "header:\(row)"
    case .headerButton(let row, _): return "headerButton:\(row)"
    case .lane(let row, _): return "lane:\(row)"
    case .clip: return "clip"
    case .clipEdge: return "clipEdge"
    case .ruler: return "ruler"
    case .outside: return "outside"
    default: return "other"
    }
}

func rightClick(_ point: CGPoint) -> NSMenu? {
    let location = content.convert(point, to: nil)
    guard let event = NSEvent.mouseEvent(
        with: .rightMouseDown, location: location, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 1)
    else { fail("could not make a right-mouse event") }
    return content.menu(for: event)
}

func describe(_ menu: NSMenu?) -> Any {
    guard let menu = menu else { return NSNull() }
    return menu.items.map { item -> [String: Any] in
        [
            "title": item.isSeparatorItem ? "-" : item.title,
            "on": item.state == .on,
            "enabled": item.isEnabled,
            "track": (item.representedObject as? NSNumber)?.intValue ?? -1,
            "submenu": item.submenu.map { describe($0) } ?? NSNull(),
        ]
    }
}

/// Performs an item as an AppKit event would: inside one undo group.
func perform(_ menu: NSMenu?, _ title: String) -> Bool {
    guard let menu = menu, let index = menu.items.firstIndex(where: { $0.title == title }),
          menu.items[index].isEnabled
    else { return false }
    let manager = document.undoManager
    manager?.groupsByEvent = false
    manager?.beginUndoGrouping()
    menu.performActionForItem(at: index)
    manager?.endUndoGrouping()
    turn(2)
    return true
}

func state() -> [String: Any] {
    let s = document.project.snapshot
    return [
        "tracks": s.tracks.map { $0.id },
        "hidden": s.tracks.filter { $0.hidden }.map { $0.id },
        "clips": s.clips.map { $0.id }.sorted(),
    ]
}

// ---- 1. where a menu opens ------------------------------------------------
var hits: [String: String] = [:]
var menus: [String: Any] = [:]
func probe(_ label: String, _ point: CGPoint) {
    hits[label] = kind(content.hit(at: point))
    menus[label] = describe(rightClick(point))
}
probe("headerFront", headerLabelPoint(0))
probe("headerMiddle", headerLabelPoint(1))
if let p = headerButtonPoint(2) { probe("buttonBack", p) }
probe("laneFront", CGPoint(x: laneX(1), y: rowY(0)))
probe("laneMiddle", CGPoint(x: laneX(5), y: rowY(1)))
probe("clipA", CGPoint(x: laneX(5), y: rowY(2)))
probe("ruler", CGPoint(x: laneX(5), y: timeline.pinnedY + 5))
probe("below", CGPoint(x: laneX(5), y: timeline.layout.rowTop(timeline.layout.trackCount) + 30))
answer["hits"] = hits
answer["menus"] = menus

// ---- 2. a toggle -----------------------------------------------------------
let beforeHide = state()
let hid = perform(rightClick(CGPoint(x: laneX(5), y: rowY(1))), "Hide Video")
answer["hide"] = ["performed": hid, "before": beforeHide, "after": state()]
refresh()
answer["hideMenu"] = describe(rightClick(CGPoint(x: laneX(5), y: rowY(1))))
document.undoManager?.undo()
refresh()
answer["hideUndone"] = state()

// ---- 3. Remove Track on the empty middle track, a clip selected elsewhere ---
document.selection = [clipF]
refresh()
answer["currentTrackBefore"] = controller.currentTrack?.id ?? 0
let removed = perform(rightClick(CGPoint(x: laneX(5), y: rowY(1))), "Remove Track")
answer["remove"] = ["performed": removed, "after": state(),
                    "sheet": window.attachedSheet != nil]
document.undoManager?.undo()
refresh()
answer["removeUndone"] = state()

// ---- 4. a track holding a clip asks first -------------------------------
let askPerformed = perform(rightClick(CGPoint(x: laneX(15), y: rowY(2))), "Remove Track")
turn(4)
var ask: [String: Any] = ["performed": askPerformed, "sheet": window.attachedSheet != nil,
                          "beforeAnswer": state()]
if let sheet = window.attachedSheet {
    func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? [] + view.subviews.flatMap(buttons)
    }
    let all = sheet.contentView.map(buttons) ?? []
    ask["buttons"] = all.map { $0.title }
    all.first { $0.title == "Remove" }?.performClick(nil)
    turn(6)
}
ask["afterAnswer"] = state()
answer["ask"] = ask

// ---- 5. the last track ---------------------------------------------------
let lone = ProjectDocument()
lone.performGroupedEdit("Clip", [.addTextClip(
    track: lone.project.snapshot.tracks[0].id, at: 0, duration: 2 * SEC)])
let loneTimeline = TimelineView()
loneTimeline.frame = NSRect(x: 0, y: 0, width: 1000, height: 320)
loneTimeline.layoutSubtreeIfNeeded()
loneTimeline.update(
    snapshot: lone.project.snapshot, selection: [], playhead: 0, inOutRange: nil,
    cacheDirectory: nil)
let loneHit = loneTimeline.content.hit(at: CGPoint(
    x: loneTimeline.layout.x(for: 5 * SEC),
    y: loneTimeline.layout.rowTop(0) + loneTimeline.layout.trackHeight(row: 0) / 2))
answer["lone"] = ["hit": kind(loneHit), "menu": describe(loneTimeline.trackMenu(for: loneHit))]

write(answer)
'''


def build_probe():
    """`refusal_probe.py`'s builder, one probe along: `swift_build.build`
    (reused when every input is byte-identical to a cached build's), and a
    reason instead of an exit when it will not build."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "trackmenuprobe")
    entry = os.path.join(PROBE, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=sources + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if built.reused:
        print(f"track menu probe: {binary} (up to date)")
    else:
        print(f"track menu probe: {binary} (built in {built.seconds:.1f} s)")
    return binary, None


def run_probe(binary):
    out = os.path.join(PROBE, "answer.json")
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run([binary, out], capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return None, "the probe never returned"
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


TITLES = ["Hide Video", "Mute Audio", "Lock Track", "Solo", "Matte", "-", "Remove Track"]
MATTE = ["Off", "Alpha", "Inverted Alpha", "Luma", "Inverted Luma"]


def matte_rows(menu):
    """The Matte submenu's rows of a described menu, or None."""
    for item in menu if isinstance(menu, list) else []:
        if item["title"] == "Matte":
            return item["submenu"]
    return None


def main():
    print("the track context menu\n")
    binary, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    answer, error = run_probe(binary)
    check("the probe answers", answer is not None, error or "")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    check("…and it got as far as driving an editor", "error" not in answer,
          answer.get("error", ""))
    if "error" in answer:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1

    ids = answer["ids"]
    back, middle, front = ids["back"], ids["middle"], ids["front"]
    hits, menus = answer["hits"], answer["menus"]

    print("\n1 — where a menu opens")
    check("the probe's points land where they are meant to",
          hits == {"headerFront": "header:0", "headerMiddle": "header:1",
                   "buttonBack": "headerButton:2", "laneFront": "lane:0",
                   "laneMiddle": "lane:1", "clipA": "clip", "ruler": "ruler",
                   "below": "outside"}, json.dumps(hits))
    for label, track in [("headerFront", front), ("headerMiddle", middle),
                         ("buttonBack", back), ("laneFront", front), ("laneMiddle", middle)]:
        menu = menus.get(label)
        check(f"{label}: the menu for its own row's track (id {track})",
              isinstance(menu, list) and [i["title"] for i in menu] == TITLES
              and all(i["track"] == track for i in menu if i["title"] != "-")
              and all(i["enabled"] for i in menu if i["title"] != "-"),
              json.dumps(menu))
    for label, track in [("headerFront", front), ("laneMiddle", middle), ("buttonBack", back)]:
        rows = matte_rows(menus.get(label))
        check(f"{label}: its Matte submenu lists Off, Alpha, Inverted Alpha, Luma, Inverted "
              "Luma, each naming that track, Off checked on an ordinary track (spec §11 MT-7)",
              isinstance(rows, list) and [i["title"] for i in rows] == MATTE
              and all(i["track"] == track and i["enabled"] for i in rows)
              and [i["title"] for i in rows if i["on"]] == ["Off"], json.dumps(rows))
    check("a clip, the ruler and the room below the lanes open no menu",
          menus["clipA"] is None and menus["ruler"] is None and menus["below"] is None,
          json.dumps({k: menus[k] for k in ("clipA", "ruler", "below")}))
    check("nothing checked on a fresh track",
          isinstance(menus["headerMiddle"], list)
          and not any(i["on"] for i in menus["headerMiddle"]), json.dumps(menus["headerMiddle"]))

    print("\n2 — a toggle")
    h = answer["hide"]
    check("Hide Video on the middle lane hides the middle track and nothing else",
          h["performed"] and h["before"]["hidden"] == [] and h["after"]["hidden"] == [middle],
          json.dumps(h))
    hm = answer["hideMenu"]
    check("…and the menu opened on it again says so with a checkmark",
          isinstance(hm, list) and hm[0]["title"] == "Hide Video" and hm[0]["on"]
          and not any(i["on"] for i in hm[1:]), json.dumps(hm))
    check("…as one undo step", answer["hideUndone"]["hidden"] == [],
          json.dumps(answer["hideUndone"]))

    print("\n3 — Remove Track on an empty track neither front-most nor selected")
    check("the fixture's Track ▸ Remove Track would act on the FRONT track (a clip there "
          "is selected)", answer["currentTrackBefore"] == front,
          json.dumps(answer["currentTrackBefore"]))
    r = answer["remove"]
    check("the menu's Remove Track removes exactly the middle track",
          r["performed"] and r["after"]["tracks"] == [back, front], json.dumps(r))
    check("…with no question, since it held nothing, and no clip lost",
          not r["sheet"] and len(r["after"]["clips"]) == 2, json.dumps(r))
    check("…and undo brings it back in place",
          answer["removeUndone"]["tracks"] == [back, middle, front],
          json.dumps(answer["removeUndone"]))

    print("\n4 — a track that holds a clip asks first")
    a = answer["ask"]
    check("Remove Track on the back lane puts up the sheet and removes nothing yet",
          a["performed"] and a["sheet"] and a["beforeAnswer"]["tracks"] == [back, middle, front],
          json.dumps(a))
    check("…whose buttons are Remove and Cancel",
          "Remove" in a.get("buttons", []) and "Cancel" in a.get("buttons", []), json.dumps(a))
    check("pressing Remove takes the back track and its clip, and only those",
          a["afterAnswer"]["tracks"] == [middle, front]
          and len(a["afterAnswer"]["clips"]) == 1, json.dumps(a))

    print("\n5 — the last track")
    lone = answer["lone"]
    menu = lone["menu"]
    check("a one-track project's menu disables Remove Track and nothing else",
          lone["hit"] == "lane:0" and isinstance(menu, list)
          and [i["title"] for i in menu] == TITLES
          and not menu[-1]["enabled"]
          and all(i["enabled"] for i in menu[:4]), json.dumps(lone))

    print(f"\n{passed}/{passed + failed} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
