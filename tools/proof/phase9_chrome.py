#!/usr/bin/env python3
"""Road map 2, phase 9 — the breadcrumb, PHOTOGRAPHED, and the two gestures
around it.

**Route 1 of `archive/reelcut-remaining.md` §1b: a probe, not two harness
arguments.** The thing under test is a z-order — the ruler must float ABOVE
the track-header column, because the two bands overlap in exactly one
square, the 132 × 22 corner where the nest breadcrumb is drawn, and they
overlap ONLY once the pane has been scrolled vertically. Every render the
shared harness makes is at scroll 0, so a `scope` argument alone would have
shown a correct corner against a build that painted it out on the first
scrolled point; a vertical-scroll argument would have had to be appended
after `mediaFilter` and then proved harmless by re-running seven chrome
scripts. And half of what this phase's fix wave changed is not a picture at
all: how many levels one double-click walks out (`beginGesture`'s
`clicks < 2`) and what Clip ▸ Open Nest / Close Nest validate as while a
field is being typed into — a click count and a validator's answer, which
no photograph of any size can read. So this is `phase9_probe.py`'s
instrument, a `main.swift` compiled against the WHOLE of `app/Sources`
with `swift_build.py`'s line, cached by content,
and a build failure scored as a FAILURE rather than an exit — except that
this one RENDERS: it builds a bare `TimelineView`, feeds it a snapshot,
scrolls it, and captures through the same `cacheDisplay` path the harness
uses. The untracked `work/phase9-corner-probe/` measured the fix this way
at the time; this is that instrument made a tracked script, with the four
things the scout found wrong with it put right (an honestly scrollable
fixture, a scene that ENDS a rename, the hit compared as the `Equatable`
enum rather than its printed string, and every picture claim a decoded
byte comparison that says WHERE rather than an FNV digest).

**Every picture claim is a byte comparison of the decoded corner** — a
crop of the full render, taken by this script from the PNG the probe wrote,
so the crop compared IS a crop of the picture and not a second capture —
and a comparison that fails prints the clusters of pixels that differ, in
crop-local pixels and points. Six scenes, each a full PNG:

    topPlain       scroll 0, no trail        — the corner every project
                                               before phase 9 ever drew
    top            scroll 0, a two-level trail
    scrolledPlain  scrolled so a row's top sits 10 pt below the ruler's
                   bottom, no trail
    scrolled       the same scroll, the trail
    rename         the same scroll, a TRACK RENAME field open on that top,
                   partly scrolled row — the one thing that must stay above
                   the ruler
    renameEnded    the same, then `endRename()` — the scene the untracked
                   probe never had, and the only one that can see the
                   restore line

What is claimed about them: the scrolled corner is byte-identical to the
at-rest corner (the trail survives the scroll) and differs from the
scrolled corner with no trail (it is VISIBLE there); the no-trail corner is
the same blank square scrolled or not and holds at most three distinct
pixel values (the fill and its two border inks — the eight-phase top-level
corner, unchanged); the trail changes NOTHING outside the corner; with a
field open the band holding it is the front-most subview and the corner
goes to it, and everything that changed is inside the corner or the field's
own rectangle; and ending the field gives the corner back byte for byte and
leaves the ruler in front again. The fixture is ten text tracks — 490 pt of
content against a 324 pt viewport — and the probe REPORTS the room it had,
so the 62 pt scroll is one the app can reach (the untracked probe's six
tracks were 306 pt against 324 and its scroll was an unclamped over-scroll
through `NSClipView.scroll(to:)`, which is a picture of a state no user
reaches).

Then the gesture half, on a REAL editor over the nested package
`phase9_probe.py` uses (a nest clip "Intro" showing nest 40, which holds a
nest clip "Deeper" showing nest 50): the corner's hit is compared as the
`TimelineHit` enum — `.corner` at the top level, `.breadcrumb(level: 0)`
one level in, `.breadcrumb(level: 1)` two levels in; a double-click on the
nest clip is delivered the way AppKit delivers one (a `clicks: 1` press,
its mouse-up, then a `clicks: 2` press) and enters; a double-click on the
breadcrumb at depth 2 comes out ONE level, not two, because the second
press is guarded; a lone click at depth 1 comes out to the timeline and a
click on the inert top-level corner does nothing; `timeline.breadcrumb`
after each step is the CONTROLLER's push (`refreshTimeline`), which nothing
tracked read before — `phase9_probe.py` proves `NestScope.names` and this
does not repeat it; and `validateNestScopeAction` answers, at the top level
and one level in, idle, while typing into a rename field, and after ending
it, for the two scope items, the three marker items and one selector that
is not its business.

**Made to fail, three ways** (road map 2 §5), each a one-line mutant on a
COPY of `app/Sources` under `work/` — never the tree — that `--mutant`
applies and builds in its own cache directory:

    --mutant init-order    `init`'s two `addSubview` lines swapped back to
                           ruler-then-headers (the defect)
    --mutant end-rename    `endRename`'s restore line deleted
    --mutant double-click  `beginGesture`'s `clicks < 2` made `true`

`--sources DIR` (or `RC_APP_SOURCES` — the one spelling of that override,
which `remaining_probe.py` shares) builds against any other copy. There
is no git commit with the old z-order AND a breadcrumb — the phase's one
app commit ships the fix — so the gate cannot be a reference build the way
phase 5's is; the mutants are the only honest pre-fix build. Measured at
the landing, against **62/62** on the tree: `init-order` scores **52/62**
and takes ten by name — the init order, the ruler front-most in the plain
scenes and at idle, scrolled == top, scrolled != scrolledPlain,
scrolledPlain == topPlain, the ≤ 3-colour corner, the only-inside-the-
corner claim, and BOTH renameEnded identities (the restore puts the ruler
above the headers, which is the fixed order, so the ended scene shows the
trail the un-ended scrolled scene lost); `end-rename` scores **57/62** and
takes five — renameEnded's `subviews.last`, its two identities, and the
two "ruler front-most again" reads in sections 3 and 4; `double-click`
scores **55/62** and takes seven, the second-press check itself and six
downstream of it, since every later step of the gesture half is then at
the wrong depth. The untracked probe's four scenes would have let the
second mutant through — its rename scene never ended the field.

What is NOT claimed. The renders are in the light appearance only; the
picture half is a bare `TimelineView`, so the trail it draws was assigned
by the probe and the CONTROLLER's push is read structurally in the gesture
half rather than photographed — the nested fixture's single track is not
scrollable, and a scrolled photograph of the editor's own timeline would
need a package with more tracks in its nest than the gesture reads want;
and no mouse event is synthesised: `beginGesture` is called with the hit,
point, flags and click count `TimelineContentView.mouseDown` would have
computed, which is the frozen file's one line and is not under test.

Run it from anywhere; it needs no port and no window server grant, only
`core/target/release/libreelcut_core.a` from `make test`:

    python3 tools/proof/phase9_chrome.py
    python3 tools/proof/phase9_chrome.py --mutant init-order

A `--mutant` run is scored as the tree is (its rows, exit 1 when any
failed); when its control could not be performed — the text to replace not
found exactly once, or the probe not built or not answering — it prints
`mutant <name>: the control could not be performed — <why>` and exits 2
(rule R, issue batch B13).
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib

import swift_build

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
PROBE_ROOT = os.path.join(WORK, "cornerprobe")
TREE_SOURCES = os.path.join(ROOT, "app", "Sources")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")

SCENES = ["topPlain", "top", "scrolledPlain", "scrolled", "rename", "renameEnded"]
TRAIL = ["Timeline", "Intro"]

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}")
    if detail:
        print(detail if detail.startswith("      ") else "      " + detail)


# --------------------------------------------------------------------------
# The probe.

PROBE_SOURCE = r'''// Written by tools/proof/phase9_chrome.py. See that file's header.
//
// A photograph of the timeline's two floating bands where they CROSS, then
// the gestures and the validator around the breadcrumb that lives there,
// on a real editor. argv: <outDir> <fontsDir> <packageDir>

import AppKit
import CoreText
import Foundation

let argv = CommandLine.arguments
guard argv.count >= 4 else {
    FileHandle.standardError.write(
        "usage: cornerprobe <outDir> <fontsDir> <packageDir>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: argv[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let fonts = URL(fileURLWithPath: argv[2])
for name in (try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}
// The one default a scroll view's PICTURE moves with. The harness pins
// twelve keys because it photographs the editor's chrome; nothing
// photographed here is the editor, and a bare `TimelineView` reads no
// `UserDefaults` key of its own.
UserDefaults.standard.setVolatileDomain(
    ["AppleShowScrollBars": "Always"], forName: UserDefaults.argumentDomain)

let app = NSApplication.shared
// `.prohibited`, the harness's and the tracked probes' choice. The one
// thing that could have needed `.accessory` is a rename field taking first
// responder in a window that is never shown; the validation half reads
// `firstResponder is NSText` and scores it, so the choice is checked.
app.setActivationPolicy(.prohibited)
NSApp.appearance = NSAppearance(named: .aqua)

var answer: [String: Any] = [:]

// --------------------------------------------------------------------------
// The render half: a bare `TimelineView` over ten text tracks.
//
// TEN, not the untracked probe's six: a text lane at size index 1 is 44 pt
// (`DS.trackHeights`), so ten make 26 + 10 × 46 + 4 = 490 pt of content
// against a 360 − 36 = 324 pt viewport, and the 62 pt scroll below is one
// the clip view can actually reach. Six made 306 pt — LESS than the
// viewport — and the scroll was an over-scroll `NSClipView.scroll(to:)`
// does not clamp. The room is reported and scored, not assumed.
var tracks: [String] = []
var clips: [String] = []
for index in 0..<10 {
    let track = 10 + index
    tracks.append("{\"id\": \(track), \"name\": \"Track \(index + 1)\"}")
    clips.append(
        "{\"id\": \(100 + index), \"track\": \(track), \"start\": \(index * 300_000),"
            + " \"duration\": 1200000, \"source\": {\"kind\": \"text\"}, \"video\": {},"
            + " \"text\": {\"content\": \"C\(index)\"}}")
}
let projectJSON = """
{"version": 6,
 "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0,0,0,1], "fit_new_clips": true, "timecode_frames": true},
 "media": [], "tracks": [\(tracks.joined(separator: ", "))],
 "clips": [\(clips.joined(separator: ", "))],
 "markers": [], "next_id": 500, "nests": []}
"""

func capture(_ view: NSView) -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// The harness's settle: capture, spin, capture again, and only answer when
/// two consecutive captures are byte-identical. Whether it did is REPORTED,
/// because a comparison of two renders that were still moving is not one.
func settled(_ view: NSView) -> (NSBitmapImageRep, Bool) {
    var rep = capture(view)
    var previous = rep.representation(using: .png, properties: [:])!
    for _ in 0..<40 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        rep = capture(view)
        let next = rep.representation(using: .png, properties: [:])!
        if next == previous { return (rep, true) }
        previous = next
    }
    return (rep, false)
}

func spin(_ turns: Int, _ view: NSView? = nil) {
    for _ in 0..<turns {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        view?.layoutSubtreeIfNeeded()
    }
}

/// A band's name for the subview-order reads: the two floating bands by
/// IDENTITY, anything else by its class.
func names(of views: [NSView], in timeline: TimelineView) -> [String] {
    views.map { view in
        if view === timeline.headers { return "headers" }
        if view === timeline.ruler { return "ruler" }
        return "other:\(type(of: view))"
    }
}

/// A rectangle in a view's (unflipped) points as image pixels with a
/// top-left origin — `[x, y, width, height]` — at the render's scale.
func pixelRect(_ rect: NSRect, of view: NSView, scale: CGFloat) -> [Int] {
    [
        Int((rect.minX * scale).rounded()),
        Int(((view.bounds.height - rect.maxY) * scale).rounded()),
        Int((rect.width * scale).rounded()),
        Int((rect.height * scale).rounded()),
    ]
}

struct Scene {
    let timeline: TimelineView
    let window: NSWindow
}

func makeScene(_ project: ReelProject) -> Scene {
    let timeline = TimelineView()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 360),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 360))
    window.contentView = host
    timeline.frame = host.bounds
    timeline.autoresizingMask = [.width, .height]
    host.addSubview(timeline)
    host.layoutSubtreeIfNeeded()
    timeline.trackHeightIndex = 1
    timeline.update(
        snapshot: project.snapshot, selection: [], playhead: 900_000, inOutRange: nil,
        cacheDirectory: nil)
    timeline.layoutSubtreeIfNeeded()
    return Scene(timeline: timeline, window: window)
}

/// What AppKit does for a wheel or a scroller: move the clip view's bounds
/// and let `boundsDidChange` reach `pinFloatingBands`.
func scroll(_ timeline: TimelineView, to y: CGFloat) {
    guard let scrollView = timeline.content.enclosingScrollView else { return }
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(scrollView.contentView)
}

func shoot(
    _ name: String, project: ReelProject, scrolled: Bool, breadcrumb: [String],
    rename: Bool, endRename: Bool
) {
    let scene = makeScene(project)
    let timeline = scene.timeline
    let atInit = names(of: timeline.content.subviews, in: timeline)
    timeline.breadcrumb = breadcrumb
    // The row whose top is to sit 10 pt below the ruler's bottom edge — the
    // top, partly scrolled row, where a rename field and the corner compete.
    let rowTop = timeline.layout.rowTop(1)
    let scrollTo = rowTop - 10
    if scrolled { scroll(timeline, to: scrollTo) }
    var fieldRect: NSRect?
    if rename {
        timeline.beginRename(
            in: timeline.headers, frame: timeline.trackRenameFrame(row: 1), text: "Track 2"
        ) { _ in }
        if let field = timeline.renameField {
            fieldRect = timeline.convert(field.frame, from: timeline.headers)
        }
    }
    if endRename { timeline.endRename() }
    let (rep, didSettle) = settled(timeline)
    let scale = CGFloat(rep.pixelsWide) / timeline.bounds.width
    // The corner, in the timeline's own coordinates: the square where the
    // pinned ruler and the pinned header column cross.
    let corner = timeline.convert(
        NSRect(
            x: timeline.pinnedX, y: timeline.pinnedY, width: TimelineLayout.headerWidth,
            height: TimelineLayout.rulerHeight), from: timeline.content)
    let clip = timeline.content.enclosingScrollView?.contentView
    var record: [String: Any] = [
        "settled": didSettle,
        "scale": scale,
        "pixelsWide": rep.pixelsWide,
        "pixelsHigh": rep.pixelsHigh,
        "pinnedX": timeline.pinnedX,
        "pinnedY": timeline.pinnedY,
        "scrollTo": scrolled ? scrollTo : 0,
        "rowTop1": rowTop,
        "contentHeight": timeline.layout.contentHeight,
        "documentHeight": timeline.content.frame.height,
        "clipHeight": clip?.bounds.height ?? -1,
        "clipMinY": clip?.bounds.minY ?? -1,
        "cornerPt": [corner.minX, corner.minY, corner.width, corner.height],
        "cornerPx": pixelRect(corner, of: timeline, scale: scale),
        "subviewsAtInit": atInit,
        "subviewsNow": names(of: timeline.content.subviews, in: timeline),
        "renameOpen": timeline.renameField != nil,
        "firstResponderIsText": scene.window.firstResponder is NSText,
    ]
    if let fieldRect { record["fieldPx"] = pixelRect(fieldRect, of: timeline, scale: scale) }
    answer[name] = record
    do {
        try rep.representation(using: .png, properties: [:])!
            .write(to: outDir.appendingPathComponent("\(name).png"))
    } catch {
        answer["error"] = "writing \(name).png: \(error)"
    }
}

do {
    let project = try ReelProject.from(json: projectJSON)
    let trail = ["Timeline", "Intro"]
    shoot("topPlain", project: project, scrolled: false, breadcrumb: [], rename: false,
          endRename: false)
    shoot("top", project: project, scrolled: false, breadcrumb: trail, rename: false,
          endRename: false)
    shoot("scrolledPlain", project: project, scrolled: true, breadcrumb: [], rename: false,
          endRename: false)
    shoot("scrolled", project: project, scrolled: true, breadcrumb: trail, rename: false,
          endRename: false)
    shoot("rename", project: project, scrolled: true, breadcrumb: trail, rename: true,
          endRename: false)
    shoot("renameEnded", project: project, scrolled: true, breadcrumb: trail, rename: true,
          endRename: true)
} catch {
    answer["error"] = "render half: \(error)"
}

// --------------------------------------------------------------------------
// The gesture half, on a real editor: what a double-click comes out to, what
// the controller pushes into the corner, and what the two menu items
// validate as while text is being edited. `phase9_probe.py`'s fixture
// without its marker: timeline clip 3 "Intro" shows nest 40, which holds
// text clip 42 and nest clip 43 "Deeper" showing nest 50.

let nestedJSON = """
{"version": 6,
 "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0,0,0,1], "fit_new_clips": true, "timecode_frames": true},
 "media": [], "tracks": [{"id": 2, "name": "T"}],
 "clips": [{"id": 3, "track": 2, "start": 1200000, "duration": 2400000,
            "name": "Intro", "source": {"kind": "nest", "project": 40}, "video": {}}],
 "markers": [], "next_id": 100,
 "nests": [
   {"id": 40, "name": "Nest 40", "width": 640, "height": 360,
    "tracks": [{"id": 41, "name": "N"}],
    "clips": [{"id": 42, "track": 41, "start": 0, "duration": 600000,
               "source": {"kind": "text"}, "video": {}, "text": {"content": "A"}},
              {"id": 43, "track": 41, "start": 1200000, "duration": 1200000,
               "name": "Deeper", "source": {"kind": "nest", "project": 50}, "video": {}}]},
   {"id": 50, "name": "Nest 50", "width": 320, "height": 180,
    "tracks": [{"id": 51, "name": "D"}],
    "clips": [{"id": 52, "track": 51, "start": 0, "duration": 600000,
               "source": {"kind": "text"}, "video": {}, "text": {"content": "B"}}]}]}
"""

func describe(_ hit: TimelineHit) -> [String: Any] {
    switch hit {
    case .corner: return ["case": "corner"]
    case .breadcrumb(let level): return ["case": "breadcrumb", "level": level]
    case .clip(let id): return ["case": "clip", "id": Int(id)]
    case .header(let row): return ["case": "header", "row": row]
    case .ruler(let time): return ["case": "ruler", "time": time]
    default: return ["case": "\(hit)"]
    }
}

do {
    let package = URL(fileURLWithPath: argv[3])
    try? FileManager.default.removeItem(at: package)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try ReelProject.from(json: nestedJSON).json.write(
        to: package.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
    let document = ProjectDocument()
    try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
    let controller = EditorViewController(document: document)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    spin(12, controller.view)
    guard let timeline = controller.timeline else {
        answer["error"] = "the editor has no timeline"
        throw NSError(domain: "cornerprobe", code: 1)
    }

    // The corner, in content coordinates — wherever the pane is scrolled to.
    func cornerPoint() -> CGPoint {
        CGPoint(x: timeline.pinnedX + 20, y: timeline.pinnedY + 10)
    }
    var steps: [[String: Any]] = []
    func state(_ label: String) {
        let hit = timeline.content.hit(at: cornerPoint())
        steps.append([
            "label": label,
            "depth": document.nestPath.count,
            "trail": timeline.breadcrumb,
            "selection": document.selection.map { Int($0) }.sorted(),
            "cornerHit": describe(hit),
            // The enum compared as the enum, not its printed form.
            "cornerHitIsCorner": hit == .corner,
            "cornerHitIsBreadcrumb0": hit == .breadcrumb(level: 0),
            "cornerHitIsBreadcrumb1": hit == .breadcrumb(level: 1),
            "renameOpen": timeline.renameField != nil,
            "firstResponderIsText": window.firstResponder is NSText,
            "lastSubview": names(of: timeline.content.subviews, in: timeline).last ?? "",
        ])
    }
    var validations: [[String: Any]] = []
    func validate(_ label: String) {
        func ask(_ selector: Selector) -> Any {
            controller.validateNestScopeAction(selector).map { $0 as Any } ?? NSNull()
        }
        validations.append([
            "label": label,
            "depth": document.nestPath.count,
            "selection": document.selection.map { Int($0) }.sorted(),
            "openNest": ask(#selector(EditorViewController.openNest(_:))),
            "closeNest": ask(#selector(EditorViewController.closeNest(_:))),
            "addMarker": ask(#selector(EditorViewController.addMarker(_:))),
            "nextMarker": ask(#selector(EditorViewController.nextMarker(_:))),
            "previousMarker": ask(#selector(EditorViewController.previousMarker(_:))),
            "splitAtPlayhead": ask(#selector(EditorViewController.splitAtPlayhead(_:))),
            "firstResponderIsText": window.firstResponder is NSText,
            "renameOpen": timeline.renameField != nil,
            "lastSubview": names(of: timeline.content.subviews, in: timeline).last ?? "",
        ])
    }
    func press(_ point: CGPoint, clicks: Int) {
        // Exactly what `TimelineContentView.mouseDown` computes and hands on.
        timeline.beginGesture(
            hit: timeline.content.hit(at: point), at: point, flags: [], clicks: clicks)
        spin(2, controller.view)
    }

    // At the top level, with the nest clip selected so Open Nest has a
    // clip to open.
    document.selection = [3]
    controller.refreshFromDocument(isLive: false)
    spin(2, controller.view)
    state("depth 0")
    validate("depth 0")

    // A double-click on the nest clip, delivered as AppKit delivers one:
    // a clickCount-1 down, its up, then a clickCount-2 down. The point is
    // the middle of the clip's bar in the top row.
    var gesture: [String: Any] = [:]
    if let clip = timeline.snapshot.clip(3) {
        let layout = timeline.layout
        let point = CGPoint(
            x: (layout.x(for: clip.start) + layout.x(for: clip.end)) / 2,
            y: layout.rowTop(0) + layout.trackHeight(row: 0) / 2)
        let hit = timeline.content.hit(at: point)
        gesture["clipHit"] = describe(hit)
        gesture["clipHitIsClip3"] = hit == .clip(3)
        press(point, clicks: 1)
        timeline.endGesture(at: point, flags: [])
        spin(2, controller.view)
        state("after a single click on the nest clip")
        press(point, clicks: 2)
        state("after a double-click on the nest clip")
    } else {
        gesture["clipHit"] = "clip 3 is not in the timeline's snapshot"
    }
    answer["gesture"] = gesture

    // Two levels in, the second through the controller's own path.
    if let inner = document.editedProject.snapshot.clip(43) { controller.enterNest(inner) }
    spin(2, controller.view)
    state("depth 2")

    // A double-click on the breadcrumb: two mouse-downs, clickCount 1 then 2.
    press(cornerPoint(), clicks: 1)
    state("after the first down on the breadcrumb")
    press(cornerPoint(), clicks: 2)
    state("after the second down on the breadcrumb")

    // One level in with the inner nest clip selected, so BOTH items have
    // something to do; then the same questions with a field open, and
    // after it is ended.
    document.selection = [43]
    controller.refreshFromDocument(isLive: false)
    spin(2, controller.view)
    validate("idle")
    timeline.beginRename(
        in: timeline.headers, frame: timeline.trackRenameFrame(row: 0), text: "N"
    ) { _ in }
    spin(2, controller.view)
    validate("typing")
    timeline.endRename()
    spin(2, controller.view)
    validate("afterEnding")

    // A lone click at depth 1 goes to the timeline; a click on the corner
    // there is swallowed.
    press(cornerPoint(), clicks: 1)
    state("after a lone click at depth 1")
    press(cornerPoint(), clicks: 1)
    state("after a click on the top-level corner")

    // Back in, a field open, and a breadcrumb click UNDER it: the gesture
    // ends the field first, so the corner is the ruler's again on the way
    // out and nothing is left being typed into.
    if let outer = document.editedProject.snapshot.clip(3) { controller.enterNest(outer) }
    spin(2, controller.view)
    timeline.beginRename(
        in: timeline.headers, frame: timeline.trackRenameFrame(row: 0), text: "N"
    ) { _ in }
    spin(2, controller.view)
    state("renaming at depth 1")
    press(cornerPoint(), clicks: 1)
    state("after a breadcrumb click under an open rename")

    answer["steps"] = steps
    answer["validations"] = validations
} catch {
    if answer["error"] == nil { answer["error"] = "gesture half: \(error)" }
}

let data = try JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outDir.appendingPathComponent("answer.json"))
exit(0)
'''


def build_probe(sources_dir, probe_dir):
    """`phase9_probe.py`'s builder, one probe along: `swift_build.build`
    (reused when every input is byte-identical to a cached build's), and a
    reason instead of an exit when it will not build. `sources_dir` is the
    tree's `app/Sources` or a mutant copy of it; each gets its own `probe_dir`
    cache."""
    os.makedirs(probe_dir, exist_ok=True)
    binary = os.path.join(probe_dir, "cornerprobe")
    entry = os.path.join(probe_dir, "main.swift")
    # Written only when it CHANGED.
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    if not os.path.isdir(sources_dir):
        return None, f"{sources_dir} is not a directory"
    sources = sorted(
        os.path.join(sources_dir, name)
        for name in os.listdir(sources_dir)
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
        print(f"corner probe: {binary} (up to date)")
    else:
        print(f"corner probe: {binary} (built in {built.seconds:.1f} s)")
    return binary, None


def run_probe(binary, probe_dir):
    out = os.path.join(probe_dir, "shots")
    package = os.path.join(probe_dir, "probe.reelcut")
    start = time.time()
    result = subprocess.run([binary, out, FONTS, package], capture_output=True, text=True)
    elapsed = time.time() - start
    answer_path = os.path.join(out, "answer.json")
    if result.returncode != 0 or not os.path.exists(answer_path):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1], elapsed, out
    with open(answer_path) as f:
        return json.load(f), None, elapsed, out


# --------------------------------------------------------------------------
# The three mutants. Each is one string replaced in a COPY of the tree's
# `app/Sources` under `work/`, and the replacement must match exactly once,
# or the copy is not the mutant it claims to be.

MUTANTS = {
    "init-order": (
        "TimelineView.swift",
        "        content.addSubview(headers)\n        content.addSubview(ruler)\n",
        "        content.addSubview(ruler)\n        content.addSubview(headers)\n",
        "init's addSubview order swapped back to ruler-then-headers (the defect)"),
    "end-rename": (
        "TimelineView.swift",
        "        content.addSubview(ruler, positioned: .above, relativeTo: headers)\n",
        "",
        "endRename's restore line deleted"),
    "double-click": (
        "TimelineView.swift",
        "            if clicks < 2 { onBreadcrumb?(level) }\n",
        "            onBreadcrumb?(level)\n",
        "beginGesture's `clicks < 2` made unconditional"),
}


def prepare_mutant(name):
    """A fresh copy of the tree's `app/Sources` with one line changed. The
    tree itself is never touched."""
    file_name, before, after, what = MUTANTS[name]
    target = os.path.join(PROBE_ROOT, f"mutant-{name}", "Sources")
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    for entry in os.listdir(TREE_SOURCES):
        if entry.endswith(".swift"):
            shutil.copy2(os.path.join(TREE_SOURCES, entry), os.path.join(target, entry))
    path = os.path.join(target, file_name)
    with open(path) as f:
        text = f.read()
    if text.count(before) != 1:
        print(f"mutant {name}: the control could not be performed — the text to replace "
              f"occurs {text.count(before)} times in {file_name}, not once — the tree has "
              f"moved and the mutant needs re-aiming", file=sys.stderr, flush=True)
        sys.exit(2)
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    print(f"mutant {name}: {what}\n      {os.path.relpath(path, ROOT)}")
    return target, f"mutant-{name}"


# --------------------------------------------------------------------------
# PNG, in pure Python: chunks, zlib, the five filters. (phase6_chrome.py's,
# unchanged — every chrome script carries its own copy so one can be run
# without the others.)

def decode_png(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path} is not a PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        sys.exit(f"{path}: only 8-bit non-interlaced PNGs are decoded here")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            sys.exit(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, channels, rows


def encode_png(width, height, channels, rows):
    """Filter-0 rows, for the crops written beside the renders."""
    colour = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(
            ">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


class Image:
    def __init__(self, path, scale):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)
        self.scale = scale


class Crop:
    """A rectangle of an `Image`, in the image's pixels — the same shape as
    an `Image` so the comparisons below take either."""

    def __init__(self, image, px):
        x, y, w, h = px
        self.path = f"{image.path}[{x},{y} {w}x{h}]"
        self.scale = image.scale
        self.channels = image.channels
        self.width, self.height = w, h
        ch = image.channels
        self.rows = [row[x * ch:(x + w) * ch] for row in image.rows[y:y + h]]

    def write(self, out):
        with open(out, "wb") as f:
            f.write(encode_png(self.width, self.height, self.channels, self.rows))

    def distinct(self):
        ch = self.channels
        seen = set()
        for row in self.rows:
            for x in range(self.width):
                seen.add(row[x * ch:(x + 1) * ch])
        return len(seen)


class PxRect:
    """A pixel rectangle a differing pixel may lie in. `slop` widens THIS
    rectangle alone, by that many pixels on every side — it belongs to the
    rectangle it was measured for and not to the comparison, so a check
    over several rectangles cannot lend one rectangle's halo to another."""

    def __init__(self, name, px, slop=0):
        self.name = name
        self.slop = slop
        self.x0, self.y0 = px[0], px[1]
        self.x1, self.y1 = px[0] + px[2], px[1] + px[3]

    def contains(self, x, y):
        slop = self.slop
        return self.x0 - slop <= x < self.x1 + slop and self.y0 - slop <= y < self.y1 + slop

    def __str__(self):
        halo = f" (+{self.slop} px halo)" if self.slop else ""
        return f"{self.name} x {self.x0}–{self.x1} y {self.y0}–{self.y1} px{halo}"


def changed_pixels(a, b):
    """Every (x, y) whose bytes differ, found by XOR-ing whole rows."""
    if (a.width, a.height, a.channels) != (b.width, b.height, b.channels):
        sys.exit(f"{a.path} and {b.path} differ in shape")
    out = []
    ch = a.channels
    for y, (ra, rb) in enumerate(zip(a.rows, b.rows)):
        if ra == rb:
            continue
        x = int.from_bytes(ra, "big") ^ int.from_bytes(rb, "big")
        xb = x.to_bytes(len(ra), "big")
        for m in re.finditer(rb"[^\x00]+", xb):
            for px in range(m.start() // ch, (m.end() - 1) // ch + 1):
                out.append((px, y))
    return out


def clusters(pixels, cell=12):
    """Bounding boxes of changed pixels grouped within `cell` px of each other."""
    buckets = {}
    for x, y in pixels:
        buckets.setdefault((x // cell, y // cell), []).append((x, y))
    parent = {k: k for k in buckets}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for cx, cy in buckets:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (cx + dx, cy + dy)
                if n in buckets:
                    parent[find(n)] = find((cx, cy))
    groups = {}
    for k, pts in buckets.items():
        groups.setdefault(find(k), []).extend(pts)
    boxes = []
    for pts in groups.values():
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        boxes.append((min(xs), min(ys), max(xs), max(ys), len(pts)))
    return sorted(boxes, key=lambda b: (b[1], b[0]))


def describe(boxes, scale, limit=12):
    lines = []
    for x0, y0, x1, y1, n in boxes[:limit]:
        lines.append(
            f"      x {x0}–{x1} y {y0}–{y1} px  = x {x0 / scale:.1f}–{(x1 + 1) / scale:.1f}"
            f" y {y0 / scale:.1f}–{(y1 + 1) / scale:.1f} pt  ({n} px)")
    if len(boxes) > limit:
        lines.append(f"      … and {len(boxes) - limit} more clusters")
    return "\n".join(lines)


def where(diff, scale):
    return f"{len(diff)} pixels differ:\n" + describe(clusters(diff), scale)


def identical(name, a, b):
    """Two pictures that must be byte-identical; a failure says WHERE."""
    if a is None or b is None:
        check(name, False, "a render is missing")
        return
    diff = changed_pixels(a, b)
    check(name, not diff, "" if not diff else where(diff, a.scale))


def different(name, a, b):
    """Two pictures that must NOT be identical; a pass says WHERE they differ,
    so the claim is about a place and not just a bit."""
    if a is None or b is None:
        check(name, False, "a render is missing")
        return
    diff = changed_pixels(a, b)
    check(name, bool(diff), "no pixel differs" if not diff else where(diff, a.scale))


def only_inside(name, a, b, rects):
    """`a` and `b` differ, and every differing pixel lies inside one of
    `rects` (each widened by its own `slop`, if it has one). Both halves are
    scored in one check: an empty diff would make "nothing outside" true of
    a build that drew nothing at all."""
    if a is None or b is None:
        check(name, False, "a render is missing")
        return
    diff = changed_pixels(a, b)
    outside = [p for p in diff if not any(r.contains(p[0], p[1]) for r in rects)]
    inside = len(diff) - len(outside)
    ok = bool(diff) and not outside
    detail = (f"{inside} px inside {', '.join(str(r) for r in rects)}, {len(outside)} outside"
              if diff else "no pixel differs at all")
    if outside:
        detail += "; outside:\n" + describe(clusters(outside), a.scale)
    check(name, ok, detail)


# --------------------------------------------------------------------------
# The checks.

def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--sources", default=os.environ.get("RC_APP_SOURCES", TREE_SOURCES),
        help="an alternative app/Sources to build the probe against (the gate); "
             "also RC_APP_SOURCES")
    parser.add_argument(
        "--tag", default=None,
        help="the work/cornerprobe/<tag>/ cache to build into (default: 'tree', or "
             "derived from --sources)")
    parser.add_argument(
        "--mutant", choices=sorted(MUTANTS), default=None,
        help="copy the tree's app/Sources under work/, apply this one-line mutant, and "
             "build against the copy")
    return parser.parse_args()


def scene_scores(answer, shots):
    """Section 1: the instrument's own honesty, and the fixture's."""
    print("\n1. The instrument")
    present = [s for s in SCENES if s in answer]
    check("all six scenes were rendered", present == SCENES,
          "" if present == SCENES else f"rendered: {present}")
    scenes = {s: answer.get(s, {}) for s in SCENES}
    check("every scene SETTLED — two consecutive captures byte-identical — so a comparison "
          "below is of a layout that had stopped",
          all(scenes[s].get("settled") is True for s in SCENES),
          ", ".join(f"{s}: {scenes[s].get('settled')}" for s in SCENES
                    if scenes[s].get("settled") is not True))
    scales = {scenes[s].get("scale") for s in SCENES}
    check("one backing scale across the six renders, and the corner comes out "
          "132 × 22 pt at it", len(scales) == 1 and None not in scales and all(
              scenes[s].get("cornerPt", [])[2:] == [132, 22]
              and scenes[s].get("cornerPx", [])[2:] == [round(132 * scenes[s]["scale"]),
                                                          round(22 * scenes[s]["scale"])]
              for s in SCENES),
          f"scales {sorted(scales)}, corners "
          f"{[scenes[s].get('cornerPt') for s in SCENES]}")
    corners = {tuple(scenes[s].get("cornerPx", [])) for s in SCENES}
    check("and it sits at the pane's visible top-left in every scene — the same pixel "
          "rectangle scrolled or not, which is what makes the crops comparable",
          len(corners) == 1, f"{sorted(corners)}")

    # The scroll must be one the app can perform. `NSClipView.scroll(to:)`
    # does not clamp, so a fixture shorter than its viewport would still
    # report a pinnedY and photograph a state no user reaches.
    for s in ("scrolledPlain", "scrolled", "rename", "renameEnded"):
        r = scenes[s]
        room = r.get("documentHeight", 0) - r.get("clipHeight", 0)
        asked = r.get("scrollTo", -1)
        check(f"{s}: the fixture is HONESTLY scrollable — content {r.get('documentHeight')} pt "
              f"against a {r.get('clipHeight')} pt viewport leaves {room:g} pt of room ≥ the "
              f"{asked:g} pt scrolled, and the clip view landed there (pinnedY "
              f"{r.get('pinnedY')})",
              asked > 0 and room >= asked and r.get("clipMinY") == asked
              and r.get("pinnedY") == asked
              and r.get("contentHeight") == r.get("documentHeight"))
    check("the scroll is `rowTop(1) − 10`: a row's top 10 pt under the ruler's bottom, the "
          "row a track rename's field sits at",
          all(scenes[s].get("scrollTo") == scenes[s].get("rowTop1", 0) - 10
              and scenes[s].get("rowTop1", 0) > 22
              for s in ("scrolledPlain", "scrolled", "rename", "renameEnded")),
          f"rowTop(1) {scenes['scrolled'].get('rowTop1')}")
    check("the two at-rest scenes are at scroll 0",
          all(scenes[s].get("pinnedY") == 0 and scenes[s].get("clipMinY") == 0
              for s in ("topPlain", "top")))


def picture_scores(answer, shots):
    """Section 2: the corner, byte-compared."""
    print("\n2. The corner, photographed")
    scenes = {s: answer.get(s, {}) for s in SCENES}
    images, corners = {}, {}
    for s in SCENES:
        path = os.path.join(shots, f"{s}.png")
        if os.path.exists(path) and "cornerPx" in scenes[s]:
            images[s] = Image(path, scenes[s]["scale"])
            corners[s] = Crop(images[s], scenes[s]["cornerPx"])
            corners[s].write(os.path.join(shots, f"{s}-corner.png"))
        else:
            images[s] = corners[s] = None
    corner_rect = PxRect("the corner", scenes["scrolled"].get("cornerPx", [0, 0, 0, 0]))

    check("init order: `content.subviews` begins [headers, ruler] in all six scenes — the "
          "header column first, so the ruler floats above it",
          all(scenes[s].get("subviewsAtInit", [])[:2] == ["headers", "ruler"] for s in SCENES),
          ", ".join(f"{s}: {scenes[s].get('subviewsAtInit')}" for s in SCENES
                    if scenes[s].get("subviewsAtInit", [])[:2] != ["headers", "ruler"]))
    check("with no field open the ruler is the FRONT-MOST subview in the four plain scenes",
          all(scenes[s].get("subviewsNow", [""])[-1] == "ruler"
              for s in ("topPlain", "top", "scrolledPlain", "scrolled")),
          ", ".join(f"{s}: {scenes[s].get('subviewsNow')}"
                    for s in ("topPlain", "top", "scrolledPlain", "scrolled")))

    identical("scrolled corner == top corner: the trail SURVIVES the scroll byte for byte",
              corners["scrolled"], corners["top"])
    different("…while the scrolled FRAME is not the at-rest frame (the lanes moved), so "
              "the corner's identity is not a whole-frame identity in disguise",
              images["scrolled"], images["top"])
    different("scrolled corner != scrolledPlain corner: the trail is VISIBLE at the scroll — "
              "the defect was these two being byte-identical",
              corners["scrolled"], corners["scrolledPlain"])
    identical("scrolledPlain corner == topPlain corner: with no trail the corner is the same "
              "blank square scrolled or not", corners["scrolledPlain"], corners["topPlain"])
    for s in ("topPlain", "scrolledPlain"):
        n = corners[s].distinct() if corners[s] else None
        check(f"{s}'s corner holds at most 3 distinct pixel values — the chrome fill and its "
              f"two border inks, the corner every project drew for eight phases",
              n is not None and n <= 3, f"{n} distinct")
    for s in ("top", "scrolled"):
        n = corners[s].distinct() if corners[s] else None
        check(f"{s}'s corner holds many more — the trail is TEXT, antialiased",
              n is not None and n > 3, f"{n} distinct")
    only_inside("scrolled vs scrolledPlain differ ONLY inside the corner: the trail moves "
                "nothing else in the pane", images["scrolled"], images["scrolledPlain"],
                [corner_rect])
    only_inside("top vs topPlain: the same at rest", images["top"], images["topPlain"],
                [corner_rect])

    r = scenes["rename"]
    check("rename: the field is open and holds first responder in a never-shown window "
          "under `.prohibited` — which is what lets the validation half's `typing` read "
          "mean something", r.get("renameOpen") is True and r.get("firstResponderIsText") is True,
          f"renameOpen {r.get('renameOpen')}, firstResponderIsText "
          f"{r.get('firstResponderIsText')}")
    check("rename: `content.subviews.last === headers` — the band HOLDING the field is raised "
          "for as long as it is open", r.get("subviewsNow", [""])[-1] == "headers",
          f"{r.get('subviewsNow')}")
    different("rename corner != scrolled corner: the raised header column takes the corner "
              "(the breadcrumb is what a rename costs, `TimelineView+NestScope.swift`)",
              corners["rename"], corners["scrolled"])
    # Slop of 2 px — one point at the Retina scale — on the FIELD alone,
    # because a bezeled `NSTextField` paints its border's halo just OUTSIDE
    # its frame. Measured: against a frame at x 12–252, y 98–138 px the
    # pixels that needed it were x 10, x 253 and y 139, and nothing further.
    # The corner gets none: it is a rectangle the view draws exactly, and
    # the halo was measured for the field — a slop applied to both (as this
    # check once did) would have let a raised column paint one pixel past
    # the corner's edge and still pass.
    field = PxRect("the field", r.get("fieldPx", [0, 0, 0, 0]), slop=2)
    only_inside("rename vs scrolled differ only inside the corner (exactly) and the field's "
                "own rectangle plus the 1 pt bezel halo a field paints outside its frame: "
                "raising the column moved nothing else",
                images["rename"], images["scrolled"], [corner_rect, field])

    e = scenes["renameEnded"]
    check("renameEnded: the field is gone and nothing is first responder as text",
          e.get("renameOpen") is False and e.get("firstResponderIsText") is False,
          f"renameOpen {e.get('renameOpen')}, firstResponderIsText "
          f"{e.get('firstResponderIsText')}")
    check("renameEnded: `content.subviews.last === ruler` — `endRename` gives the corner back",
          e.get("subviewsNow", [""])[-1] == "ruler", f"{e.get('subviewsNow')}")
    identical("renameEnded corner == scrolled corner: the trail is back byte for byte",
              corners["renameEnded"], corners["scrolled"])
    identical("renameEnded FRAME == scrolled frame, whole: ending the field leaves no trace "
              "anywhere in the pane", images["renameEnded"], images["scrolled"])


def gesture_scores(answer):
    """Section 3: the gestures, on a real editor."""
    print("\n3. The gestures, on a real editor")
    steps = {row["label"]: row for row in answer.get("steps", [])}
    gesture = answer.get("gesture", {})

    def step(label):
        return steps.get(label, {})

    def hit(label):
        s = step(label)
        return (s.get("cornerHitIsCorner"), s.get("cornerHitIsBreadcrumb0"),
                s.get("cornerHitIsBreadcrumb1"))

    d0 = step("depth 0")
    check("at the top level the trail is EMPTY — the corner is inert, not \"Timeline\" alone",
          d0.get("trail") == [] and d0.get("depth") == 0, f"{d0.get('trail')}")
    check("and the corner's hit == `.corner`, compared as the enum (not `.breadcrumb`)",
          hit("depth 0") == (True, False, False), f"{d0.get('cornerHit')}")
    check("the point in the middle of the nest clip's bar hits `.clip(3)`",
          gesture.get("clipHitIsClip3") is True, f"{gesture.get('clipHit')}")
    one = step("after a single click on the nest clip")
    check("a single click on the nest clip (clickCount 1, then its up) SELECTS and does not "
          "enter", one.get("depth") == 0 and one.get("selection") == [3],
          f"depth {one.get('depth')}, selection {one.get('selection')}")
    two = step("after a double-click on the nest clip")
    check("the clickCount-2 press on it ENTERS: depth 1", two.get("depth") == 1,
          f"depth {two.get('depth')}")
    check("and the CONTROLLER pushed the trail into the corner: [Timeline, Intro] — the clip's "
          "name, not the nest's \"Nest 40\"", two.get("trail") == ["Timeline", "Intro"],
          f"{two.get('trail')}")
    check("one level in, the corner's hit == `.breadcrumb(level: 0)`",
          hit("after a double-click on the nest clip") == (False, True, False),
          f"{two.get('cornerHit')}")
    check("entering emptied the selection", two.get("selection") == [],
          f"{two.get('selection')}")

    d2 = step("depth 2")
    check("two levels in (the second through `enterNest`): depth 2 and a three-component "
          "trail", d2.get("depth") == 2 and d2.get("trail") == ["Timeline", "Intro", "Deeper"],
          f"depth {d2.get('depth')}, trail {d2.get('trail')}")
    check("and the corner's hit == `.breadcrumb(level: 1)`",
          hit("depth 2") == (False, False, True), f"{d2.get('cornerHit')}")
    first = step("after the first down on the breadcrumb")
    check("the FIRST press on the breadcrumb comes out one level: depth 1",
          first.get("depth") == 1 and first.get("trail") == ["Timeline", "Intro"],
          f"depth {first.get('depth')}, trail {first.get('trail')}")
    second = step("after the second down on the breadcrumb")
    check("the SECOND press (clickCount 2) of the same double-click is IGNORED: still depth 1 "
          "— the guard that stops one gesture walking out two nests",
          second.get("depth") == 1 and second.get("trail") == ["Timeline", "Intro"],
          f"depth {second.get('depth')}, trail {second.get('trail')}")

    lone = step("after a lone click at depth 1")
    check("a lone click at depth 1 goes to the timeline: depth 0, trail empty",
          lone.get("depth") == 0 and lone.get("trail") == [],
          f"depth {lone.get('depth')}, trail {lone.get('trail')}")
    check("leaving re-selected the nest clip that was entered",
          lone.get("selection") == [3], f"{lone.get('selection')}")
    check("and the corner is `.corner` again", hit("after a lone click at depth 1") ==
          (True, False, False), f"{lone.get('cornerHit')}")
    inert = step("after a click on the top-level corner")
    check("a click on the top-level corner is swallowed: nothing changes",
          inert.get("depth") == 0 and inert.get("trail") == [] and inert.get("selection") == [3],
          f"depth {inert.get('depth')}, selection {inert.get('selection')}")

    typing = step("renaming at depth 1")
    check("back in with a rename field open: depth 1, the field holds first responder, the "
          "header column is raised", typing.get("depth") == 1
          and typing.get("renameOpen") is True and typing.get("firstResponderIsText") is True
          and typing.get("lastSubview") == "headers",
          f"depth {typing.get('depth')}, renameOpen {typing.get('renameOpen')}, "
          f"firstResponderIsText {typing.get('firstResponderIsText')}, "
          f"last {typing.get('lastSubview')}")
    under = step("after a breadcrumb click under an open rename")
    check("a breadcrumb click under it ENDS the field first (`beginGesture` opens with "
          "`endRename`) and then leaves: depth 0, no field, nothing typed into",
          under.get("depth") == 0 and under.get("renameOpen") is False
          and under.get("firstResponderIsText") is False,
          f"depth {under.get('depth')}, renameOpen {under.get('renameOpen')}, "
          f"firstResponderIsText {under.get('firstResponderIsText')}")
    check("and the ruler is front-most again on the way out",
          under.get("lastSubview") == "ruler", f"{under.get('lastSubview')}")


def validation_scores(answer):
    """Section 4: `validateNestScopeAction`, four states."""
    print("\n4. The validator (`validateNestScopeAction`)")
    rows = {row["label"]: row for row in answer.get("validations", [])}

    def v(label):
        return rows.get(label, {})

    d0 = v("depth 0")
    check("top level, nest clip selected: Open Nest true, Close Nest false",
          d0.get("openNest") is True and d0.get("closeNest") is False,
          f"openNest {d0.get('openNest')}, closeNest {d0.get('closeNest')}")
    check("top level: the three marker items are NOT this arm's — nil, the base file's answer "
          "stands", all(d0.get(k) is None for k in ("addMarker", "nextMarker", "previousMarker")),
          f"{[d0.get(k) for k in ('addMarker', 'nextMarker', 'previousMarker')]}")
    idle = v("idle")
    check("one level in, idle, the inner nest clip selected: Open Nest true, Close Nest true",
          idle.get("depth") == 1 and idle.get("openNest") is True
          and idle.get("closeNest") is True and idle.get("firstResponderIsText") is False,
          f"depth {idle.get('depth')}, openNest {idle.get('openNest')}, closeNest "
          f"{idle.get('closeNest')}")
    check("one level in: Add Marker, Next Marker and Previous Marker are all FALSE — a marker "
          "is at project time and the playhead in here is not",
          all(idle.get(k) is False for k in ("addMarker", "nextMarker", "previousMarker")),
          f"{[idle.get(k) for k in ('addMarker', 'nextMarker', 'previousMarker')]}")
    check("a selector that is not its business (Split at Playhead) is nil at both depths",
          d0.get("splitAtPlayhead") is None and idle.get("splitAtPlayhead") is None,
          f"{d0.get('splitAtPlayhead')}, {idle.get('splitAtPlayhead')}")
    check("idle: the ruler is front-most before any field opens",
          idle.get("lastSubview") == "ruler", f"{idle.get('lastSubview')}")
    typing = v("typing")
    check("typing into a rename field: BOTH scope items false, with the field confirmed as "
          "first responder", typing.get("openNest") is False and typing.get("closeNest") is False
          and typing.get("firstResponderIsText") is True and typing.get("renameOpen") is True,
          f"openNest {typing.get('openNest')}, closeNest {typing.get('closeNest')}, "
          f"firstResponderIsText {typing.get('firstResponderIsText')}")
    check("typing: the markers stay false — the scope arm runs first",
          all(typing.get(k) is False for k in ("addMarker", "nextMarker", "previousMarker")))
    after = v("afterEnding")
    check("after `endRename`: both scope items true again and nothing is first responder as "
          "text", after.get("openNest") is True and after.get("closeNest") is True
          and after.get("firstResponderIsText") is False and after.get("renameOpen") is False,
          f"openNest {after.get('openNest')}, closeNest {after.get('closeNest')}, "
          f"firstResponderIsText {after.get('firstResponderIsText')}")
    check("after `endRename`: the ruler is front-most again (`content.subviews.last === ruler`)",
          after.get("lastSubview") == "ruler", f"{after.get('lastSubview')}")


def main():
    args = parse_args()
    if args.mutant:
        sources, tag = prepare_mutant(args.mutant)
    else:
        sources = os.path.abspath(args.sources)
        tag = args.tag or ("tree" if sources == TREE_SOURCES else
                           re.sub(r"[^A-Za-z0-9_.-]+", "-", os.path.relpath(sources, ROOT)))
    probe_dir = os.path.join(PROBE_ROOT, tag)
    print("phase 9 — the breadcrumb photographed, and the gestures around it\n")
    if sources != TREE_SOURCES:
        print(f"NOT THE TREE: building against {os.path.relpath(sources, ROOT)} "
              f"(cache {os.path.relpath(probe_dir, ROOT)})\n")

    binary, error = build_probe(sources, probe_dir)
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return not_performed(args.mutant, "the probe did not build")
    answer, error, elapsed, shots = run_probe(binary, probe_dir)
    check("the probe answers", answer is not None, error or f"ran in {elapsed:.1f} s")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return not_performed(args.mutant, "the probe did not answer")
    check("nothing threw inside it", "error" not in answer, answer.get("error", ""))

    scene_scores(answer, shots)
    picture_scores(answer, shots)
    gesture_scores(answer)
    validation_scores(answer)

    print(f"\nPNGs and corner crops are in {os.path.relpath(shots, ROOT)}/ "
          f"(probe ran in {elapsed:.1f} s)")
    print("The picture half is a bare TimelineView with its trail ASSIGNED; the controller's "
          "push is read in section 3,\nnot photographed. Light appearance only.")
    print(f"\n{passed}/{passed + failed} checks passed")
    return 0 if failed == 0 else 1


def not_performed(mutant, why):
    """An instrument that did not build or answer: 2 under `--mutant` (rule
    R, issue batch B13 — the control could not be performed), the scored
    FAIL's 1 without."""
    if not mutant:
        return 1
    print(f"mutant {mutant}: the control could not be performed — {why}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
