#!/usr/bin/env python3
"""The marquee, started from anywhere empty — the timeline's rubber band.

Spec §4.4: a drag on empty timeline space bands a selection. The band has
been there since M1 (`RangeSession`, `TimelineSessions.swift`), but it could
only START inside a lane: `TimelineContentView.hit(at:)` answered `.none`
for the strip above the first lane and for everything below the last one,
and `beginGesture` swallows `.none`. With one or two tracks most of the pane
is that room, so the place a person naturally presses to band the clips
above was the one place a band could not start. `.outside` is the hit case
that closes it, and one `beginMarquee` serves it and `.lane`.

No MCP call can reach any of this — a gesture is not an op, and a selection
is view state `set_selection` writes without a mouse — and a photograph
cannot show what a press DID. So this is `CLAUDE.md`'s instrument for app
STRUCTURE with no caller a script can reach: a probe compiled out of
`app/Sources` over `swift_build.py`'s line, cached by
content, a build failure scored as a FAILURE rather than an
exit. It builds a bare `TimelineView` at 1000 × 320 over a two-track
fixture of four text clips — no media, every rectangle hand-computable —
and drives the three entry points a mouse event reaches
(`beginGesture` / `continueGesture` / `endGesture`) with synthetic points,
reading the hit test, the live session, the selection and every post the
view makes through `onSelectionChanged` and `onEdit`.

What it measures:

  * **What a press lands on.** A lane's gap is `.lane`; the room below the
    last lane and the strip above the first are `.outside`; the header
    column under the lanes stays `.none`; a clip, the ruler and a header
    still answer as themselves. And the room below the lanes is INSIDE the
    content view's frame, which is what makes a real press there reach this
    hit test at all.
  * **The band from a lane** (the control that has always worked): a drag
    from one lane's gap across two tracks selects the clips on both.
  * **The band from outside the lanes**: from below, from the strip above,
    and ⇧ from below adding to what was selected.
  * **A press with no drag**: a bare click on empty space clears the
    selection and posts once; a ⇧-click keeps it and posts nothing; a
    double-click below the lanes closes no gap (there is no row to name),
    where the same double-click in a lane's gap still does.
  * **The band's rules hold wherever it starts**: ⇧ adds, a plain band over
    nothing clears, a locked track's clips are skipped, and a band dragged
    exactly horizontally — no height at all — still reads as the line it is.
  * Every gesture ends with no session left live.

Made to fail on purpose, twice: `hit(at:)`'s new guard put back to
answering `.none` when there is no row under the point takes the nine rows
that press outside a lane and nothing else (19/28); `beginMarquee` without
its clear takes the bare-click row alone (27/28) — a DRAG over nothing
still ends empty because `RangeSession` replaces rather than adds, so the
click with no drag is the one row that can see the press-time clear.

    python3 tools/proof/marquee_probe.py
"""

import json
import os
import subprocess
import sys

import swift_build

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROBE = os.path.join(ROOT, "tools", "proof", "work", "marquee-probe")

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
# The probe. It drives one TimelineView and prints one JSON object.

PROBE_SOURCE = r'''
import AppKit
import Foundation

// AppKit wants its shared instance before a document or a view is made.
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

// ---- the fixture: two tracks, four text clips ---------------------------
// Back track (display row 1): A 0–10 s, B 12–20 s.
// Front track (display row 0): C 2–8 s, D 14–22 s.
// Text clips, so no media file and every bar is hand-computable.
let document = ProjectDocument()
guard let back = document.project.snapshot.tracks.first?.id else {
    fail("the blank project has no track")
}
document.performGroupedEdit("Track", [.addTrack(index: 1)])
guard let front = document.project.snapshot.tracks.last?.id, front != back else {
    fail("add_track did not add a front track")
}
document.performGroupedEdit("Clips", [
    .addTextClip(track: back, at: 0, duration: 10 * SEC),
    .addTextClip(track: back, at: 12 * SEC, duration: 8 * SEC),
    .addTextClip(track: front, at: 2 * SEC, duration: 6 * SEC),
    .addTextClip(track: front, at: 14 * SEC, duration: 8 * SEC),
])
let snapshot = document.project.snapshot
guard snapshot.clips.count == 4 else { fail("the fixture has \(snapshot.clips.count) clips, not 4") }
let ordered = snapshot.clips.sorted {
    (snapshot.trackIndex(of: $0.track) ?? 0, $0.start) < (snapshot.trackIndex(of: $1.track) ?? 0, $1.start)
}
let letters = ["A", "B", "C", "D"]
let names = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, letters[$0.offset]) })
let ids = Dictionary(uniqueKeysWithValues: names.map { ($0.value, $0.key) })
func spell(_ s: Set<UInt32>) -> String { s.compactMap { names[$0] }.sorted().joined() }

// ---- the view, at a size with room under two text lanes ----------------
let timeline = TimelineView()
timeline.frame = NSRect(x: 0, y: 0, width: 1000, height: 320)
timeline.layoutSubtreeIfNeeded()
func show(_ snapshot: ProjectSnapshot, selecting: [String]) {
    timeline.update(
        snapshot: snapshot, selection: Set(selecting.compactMap { ids[$0] }), playhead: 0,
        inOutRange: nil, cacheDirectory: nil)
}
show(snapshot, selecting: [])
let layout = timeline.layout
let lanesBottom = layout.rowTop(layout.trackCount)
answer["layout"] = [
    "lanesTop": layout.lanesTop, "lanesBottom": lanesBottom,
    "rowHeights": layout.rowHeights, "trackCount": layout.trackCount,
    "contentHeight": timeline.content.frame.height, "viewportHeight": layout.viewport.height,
    "headerWidth": TimelineLayout.headerWidth, "rulerHeight": TimelineLayout.rulerHeight,
]

func x(_ seconds: Double) -> CGFloat { layout.x(for: Ticks(seconds * Double(SEC))) }
let row0 = layout.rowTop(0) + 10
let row1 = layout.rowTop(1) + 10
let below = lanesBottom + 30
let above = layout.lanesTop - 2

var posted: [String] = []
var edits: [String] = []
timeline.onSelectionChanged = { ids in posted.append(spell(ids)) }
timeline.onEdit = { name, _ in edits.append(name) }

func kind(_ hit: TimelineHit) -> String {
    switch hit {
    case .ruler: return "ruler"
    case .marker: return "marker"
    case .corner: return "corner"
    case .breadcrumb: return "breadcrumb"
    case .header: return "header"
    case .headerButton: return "headerButton"
    case .clip(let id): return "clip:" + (names[id] ?? "?")
    case .clipEdge: return "clipEdge"
    case .fade: return "fade"
    case .action: return "action"
    case .actionEdge: return "actionEdge"
    case .lane(let row, _): return "lane:\(row)"
    case .outside: return "outside"
    case .none: return "none"
    }
}

// ---- 1. what a press lands on -------------------------------------------
var hits: [String: String] = [:]
func hit(_ label: String, _ point: CGPoint) {
    hits[label] = kind(timeline.content.hit(at: point))
}
hit("gapRow0", CGPoint(x: x(10.5), y: row0))
hit("gapRow1", CGPoint(x: x(11), y: row1))
hit("onA", CGPoint(x: x(5), y: row1))
hit("below", CGPoint(x: x(11), y: below))
hit("justBelow", CGPoint(x: x(11), y: lanesBottom + 1))
hit("above", CGPoint(x: x(11), y: above))
hit("belowHeaderColumn", CGPoint(x: 20, y: below))
hit("pastEndRow0", CGPoint(x: x(30), y: row0))
hit("ruler", CGPoint(x: x(11), y: 5))
hit("headerRow0", CGPoint(x: 20, y: row0))
answer["hits"] = hits

// ---- 2–6. the gestures ----------------------------------------------------
// One press, two moves (the midpoint, then the far corner), one release —
// the shape a real drag delivers — with the view's answers read at each
// step. `clicks` is what AppKit's clickCount would say.
func gesture(
    _ label: String, from a: CGPoint, to b: CGPoint?, flags: NSEvent.ModifierFlags = [],
    clicks: Int = 1, selecting: [String], snapshot shown: ProjectSnapshot = snapshot
) {
    show(shown, selecting: selecting)
    posted = []
    edits = []
    let hit = timeline.content.hit(at: a)
    timeline.beginGesture(hit: hit, at: a, flags: flags, clicks: clicks)
    let started = timeline.marquee != nil
    let end = b ?? a
    if let b = b {
        timeline.continueGesture(at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), flags: flags)
        timeline.continueGesture(at: b, flags: flags)
    }
    let live = spell(timeline.selection)
    let band = timeline.marquee?.rect ?? .zero
    timeline.endGesture(at: end, flags: flags)
    answer[label] = [
        "hit": kind(hit), "started": started, "live": live,
        "after": spell(timeline.selection), "posted": posted, "edits": edits,
        "sessionLeft": timeline.marquee != nil,
        "bandHeight": band.height, "bandWidth": band.width,
    ]
}

// the control: from a lane's gap, across both tracks
gesture("fromLane", from: CGPoint(x: x(10.5), y: row0), to: CGPoint(x: x(4), y: row1 + 5),
        selecting: [])
// the fix: from below the lanes, and from the strip above them
gesture("fromBelow", from: CGPoint(x: x(23), y: below), to: CGPoint(x: x(15), y: row0),
        selecting: [])
gesture("fromAbove", from: CGPoint(x: x(9), y: above), to: CGPoint(x: x(7), y: row0 + 5),
        selecting: [])
gesture("shiftFromBelow", from: CGPoint(x: x(11), y: below), to: CGPoint(x: x(13), y: row1 + 5),
        flags: [.shift], selecting: ["C"])
// the header column under the lanes stays inert
gesture("fromHeaderColumnBelow", from: CGPoint(x: 20, y: below), to: CGPoint(x: x(15), y: row0),
        selecting: ["C"])
// a press with no drag
gesture("clickBelow", from: CGPoint(x: x(11), y: below), to: nil, selecting: ["C"])
gesture("shiftClickBelow", from: CGPoint(x: x(11), y: below), to: nil, flags: [.shift],
        selecting: ["C"])
gesture("doubleClickBelow", from: CGPoint(x: x(11), y: below), to: nil, clicks: 2,
        selecting: [])
gesture("doubleClickLane", from: CGPoint(x: x(11), y: row1), to: nil, clicks: 2,
        selecting: [])
// the band's rules, wherever it starts
gesture("shiftFromLane", from: CGPoint(x: x(11), y: row1), to: CGPoint(x: x(13), y: row1 + 5),
        flags: [.shift], selecting: ["C"])
gesture("plainOverNothing", from: CGPoint(x: x(10.2), y: row1), to: CGPoint(x: x(11.5), y: row1 + 5),
        selecting: ["C"])
gesture("horizontal", from: CGPoint(x: x(11), y: row1), to: CGPoint(x: x(5), y: row1),
        selecting: [])
document.performGroupedEdit("Lock", [.setTrack(track: front, locked: true)])
gesture("frontLocked", from: CGPoint(x: x(11), y: below), to: CGPoint(x: x(4), y: row0),
        selecting: [], snapshot: document.project.snapshot)

write(answer)
'''


def build_probe():
    """`refusal_probe.py`'s builder, one probe along: `swift_build.build`
    (reused when every input is byte-identical to a cached build's), and a
    reason instead of an exit when it will not build."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "marqueeprobe")
    entry = os.path.join(PROBE, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=sources + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if built.reused:
        print(f"marquee probe: {binary} (up to date)")
    else:
        print(f"marquee probe: {binary} (built in {built.seconds:.1f} s)")
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


def main():
    print("the marquee, started from anywhere empty\n")
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
    check("…and it got as far as driving a timeline", "error" not in answer,
          answer.get("error", ""))
    if "error" in answer:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1

    print("\n1 — what a press lands on")
    layout = answer["layout"]
    hits = answer["hits"]
    check("two text lanes under the ruler, with room below them in a 320 pt pane",
          layout["trackCount"] == 2 and layout["lanesBottom"] < layout["viewportHeight"],
          json.dumps(layout))
    check("the room below the lanes is inside the content view's frame, so a real press "
          "there reaches this hit test",
          layout["contentHeight"] >= layout["viewportHeight"]
          and layout["lanesBottom"] + 30 < layout["contentHeight"], json.dumps(layout))
    check("a lane's gap is .lane, with its row",
          hits["gapRow0"] == "lane:0" and hits["gapRow1"] == "lane:1"
          and hits["pastEndRow0"] == "lane:0", json.dumps(hits))
    check("the room below the last lane is .outside — one point in and thirty",
          hits["below"] == "outside" and hits["justBelow"] == "outside", json.dumps(hits))
    check("the strip between the ruler and the first lane is .outside",
          hits["above"] == "outside", json.dumps(hits))
    check("the header column under the lanes is still .none",
          hits["belowHeaderColumn"] == "none", json.dumps(hits))
    check("a clip, the ruler and a header still answer as themselves",
          hits["onA"] == "clip:A" and hits["ruler"] == "ruler"
          and hits["headerRow0"] == "header", json.dumps(hits))

    print("\n2 — the band from a lane, the control")
    g = answer["fromLane"]
    check("a press in row 0's gap starts a band", g["hit"] == "lane:0" and g["started"],
          json.dumps(g))
    check("dragged over A and C across both tracks, the selection is AC while the mouse "
          "is down and AC after it comes up",
          g["live"] == "AC" and g["after"] == "AC", json.dumps(g))
    check("…posted through onSelectionChanged, the last post being the whole band",
          g["posted"] and g["posted"][-1] == "AC", json.dumps(g))

    print("\n3 — the band from outside the lanes")
    g = answer["fromBelow"]
    check("a press below the last lane starts a band", g["hit"] == "outside" and g["started"],
          json.dumps(g))
    check("dragged up over B and D, it selects them", g["live"] == "BD" and g["after"] == "BD"
          and g["posted"][-1:] == ["BD"], json.dumps(g))
    g = answer["fromAbove"]
    check("a press in the strip above the first lane starts a band",
          g["hit"] == "outside" and g["started"], json.dumps(g))
    check("dragged down over C, it selects it", g["live"] == "C" and g["after"] == "C",
          json.dumps(g))
    g = answer["shiftFromBelow"]
    check("⇧ from below the lanes ADDS: C selected, a band over B, and BC after",
          g["after"] == "BC" and "" not in g["posted"], json.dumps(g))
    g = answer["fromHeaderColumnBelow"]
    check("a press in the header column under the lanes starts nothing and keeps the "
          "selection", not g["started"] and g["after"] == "C" and g["posted"] == [],
          json.dumps(g))

    print("\n4 — a press with no drag")
    g = answer["clickBelow"]
    check("a bare click below the lanes clears the selection and posts once",
          g["after"] == "" and g["posted"] == [""] and g["edits"] == [], json.dumps(g))
    g = answer["shiftClickBelow"]
    check("a ⇧-click below the lanes keeps it and posts nothing",
          g["after"] == "C" and g["posted"] == [], json.dumps(g))
    g = answer["doubleClickBelow"]
    check("a double-click below the lanes closes no gap — there is no row to name",
          g["edits"] == [], json.dumps(g))
    g = answer["doubleClickLane"]
    check("…where the same double-click in a lane's gap still asks for Close Gap",
          g["edits"] == ["Close Gap"] and not g["started"], json.dumps(g))

    print("\n5 — the band's rules hold wherever it starts")
    g = answer["shiftFromLane"]
    check("⇧ from a lane adds: C selected, a band over B, BC after",
          g["after"] == "BC" and "" not in g["posted"], json.dumps(g))
    g = answer["plainOverNothing"]
    check("a plain band over nothing leaves nothing selected — RangeSession replaces, it "
          "never adds", g["after"] == "" and g["posted"][-1:] == [""], json.dumps(g))
    g = answer["horizontal"]
    check("a band dragged exactly horizontally — no height — still reads as the line it "
          "is, and selects A", g["bandHeight"] == 0 and g["after"] == "A", json.dumps(g))
    g = answer["frontLocked"]
    check("with the front track locked, a band from below over A and C (4–11 s, both "
          "rows) selects A alone", g["hit"] == "outside" and g["after"] == "A",
          json.dumps(g))
    check("no gesture leaves a session live after the mouse comes up",
          all(not answer[k]["sessionLeft"] for k in answer
              if isinstance(answer[k], dict) and "sessionLeft" in answer[k]),
          json.dumps({k: answer[k]["sessionLeft"] for k in answer
                      if isinstance(answer[k], dict) and "sessionLeft" in answer[k]}))

    print(f"\n{passed}/{passed + failed} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
