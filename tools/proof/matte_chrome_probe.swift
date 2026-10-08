// matte_chrome_probe.swift — road map "mattes", phase MT4 (#240; spec §11
// MT-7): the matte track's chrome, measured in the app's own code. Built as
// `main.swift` over every other file in `app/Sources` (or a mutant's copy)
// by `matte_chrome_probe.py` through `swift_build.build`; it writes one JSON
// answer to argv[1] and launches no app. The rows are the Python side's.
import AppKit
import Foundation

_ = NSApplication.shared
NSApp.appearance = NSAppearance(named: .aqua)

let SEC: Ticks = 600_000

var answer: [String: Any] = [:]

func write(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

func fail(_ why: String) -> Never {
    answer["error"] = why
    write(answer)
    exit(0)
}

func turn(_ n: Int = 4) {
    for _ in 0..<n { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
}

// ---- T1: the header tag's words (pure) ------------------------------------
func tag(_ track: TrackSnapshot, _ tracks: [TrackSnapshot]) -> Any {
    guard let made = TimelineMatteTag.text(for: track, in: tracks) else { return NSNull() }
    return ["text": made.text, "dimmed": made.dimmed]
}
var tags: [String: Any] = [:]
let plain = TrackSnapshot(id: 1)
for mode in TrackMatte.allCases where mode != .none {
    let matte = TrackSnapshot(id: 2, matte: mode)
    tags[mode.rawValue] = tag(matte, [plain, matte])
}
let backMost = TrackSnapshot(id: 2, matte: .alpha)
tags["backMost"] = tag(backMost, [backMost, plain])
let lower = TrackSnapshot(id: 2, matte: .luma)
let upper = TrackSnapshot(id: 3, matte: .alpha)
tags["matteBehindMatte"] = tag(upper, [plain, lower, upper])
tags["lowerOfTwo"] = tag(lower, [plain, lower, upper])
tags["ordinary"] = tag(plain, [plain, upper])
answer["tags"] = tags
// Not scored: where the tag goes per lane height (T2 scores the name line).
answer["placement"] = DS.trackHeights.map { sizes in
    sizes.map { height -> [String: Any] in
        [
            "height": Double(height),
            "ownLine": TimelineHeaderView.matteTagOnOwnLine(rowHeight: height),
        ]
    }
}

// ---- the fixture: six tracks, back to front -----------------------------
//   0 B  ordinary, shape b      1 M  alpha → B, shape m
//   2 O  ordinary, shape o      3 M2 alpha → O, shape m2
//   4 L  luma, behind it a matte: no target, shape l
//   5 F  ordinary, empty (the front-most: `currentTrack` with no selection)
let document = ProjectDocument()
guard let first = document.project.snapshot.tracks.first?.id else { fail("no track") }
document.performGroupedEdit("Tracks", (1...5).map { .addTrack(index: $0) })
let trackIDs = document.project.snapshot.tracks.map { $0.id }
guard trackIDs.count == 6, trackIDs[0] == first else {
    fail("the fixture has \(trackIDs.count) tracks")
}
let (tB, tM, tO, tM2, tL, tF) = (
    trackIDs[0], trackIDs[1], trackIDs[2], trackIDs[3], trackIDs[4], trackIDs[5])
document.performGroupedEdit("Clips", [tB, tM, tO, tM2, tL].map {
    .addShapeClip(track: $0, at: SEC, duration: 4 * SEC, shape: .rectangle)
})
document.performGroupedEdit("Mattes", [
    .setTrack(track: tM, matte: .alpha), .setTrack(track: tM2, matte: .alpha),
    .setTrack(track: tL, matte: .luma),
])
func clipOn(_ track: UInt32) -> ClipSnapshot? {
    document.project.snapshot.clips(onTrack: track).first
}
guard let cB = clipOn(tB), let cM = clipOn(tM), let cO = clipOn(tO), let cM2 = clipOn(tM2),
      let cL = clipOn(tL)
else { fail("the fixture's clips did not land") }
answer["ids"] = ["B": tB, "M": tM, "O": tO, "M2": tM2, "L": tL, "F": tF]

let controller = EditorViewController(document: document)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.appearance = NSAppearance(named: .aqua)
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

func row(_ track: UInt32) -> Int {
    timeline.layout.row(
        forTrackIndex: document.project.snapshot.tracks.firstIndex { $0.id == track } ?? 0)
}
func laneY(_ track: UInt32) -> CGFloat {
    timeline.layout.rowTop(row(track)) + timeline.layout.trackHeight(row: row(track)) / 2
}
func laneX(_ seconds: Double) -> CGFloat { timeline.layout.x(for: Ticks(seconds * Double(SEC))) }

func rightClick(_ point: CGPoint) -> NSMenu? {
    let location = content.convert(point, to: nil)
    guard let event = NSEvent.mouseEvent(
        with: .rightMouseDown, location: location, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 1)
    else { fail("could not make a right-mouse event") }
    return content.menu(for: event)
}
/// The empty part of `track`'s lane, right of every clip.
func contextMenu(_ track: UInt32) -> NSMenu? { rightClick(CGPoint(x: laneX(8), y: laneY(track))) }

func items(_ menu: NSMenu?) -> [[String: Any]] {
    (menu?.items ?? []).map { item in
        [
            "title": item.isSeparatorItem ? "-" : item.title,
            "on": item.state == .on,
            "tag": item.tag,
            "track": (item.representedObject as? NSNumber)?.intValue ?? -1,
            "submenu": item.submenu.map { items($0) } ?? NSNull(),
        ]
    }
}

func mattes() -> [String: String] {
    var out: [String: String] = [:]
    for track in document.project.snapshot.tracks { out[String(track.id)] = track.matte.rawValue }
    return out
}

/// Runs `body` as one AppKit event would: the undo manager groups by event,
/// opening a group only when something registers and closing it when the run
/// loop turns — so an identity, which registers nothing, leaves no step (an
/// explicit begin/end pair would leave an empty one).
func asEvent(_ body: () -> Void) {
    document.undoManager?.groupsByEvent = true
    body()
    turn(2)
}

func matteItem(_ menu: NSMenu?, _ title: String) -> (NSMenu, Int)? {
    guard let sub = menu?.items.first(where: { $0.title == "Matte" })?.submenu,
          let index = sub.items.firstIndex(where: { $0.title == title })
    else { return nil }
    return (sub, index)
}

// ---- M1: the two menus' rows ----------------------------------------------
let mainMenu = AppDelegate().buildMainMenu()
guard let trackMenu = mainMenu.items.first(where: { $0.title == "Track" })?.submenu else {
    fail("the main menu has no Track menu")
}
answer["trackMenu"] = items(trackMenu)
refresh()
answer["contextMenu"] = items(contextMenu(tO))

// ---- M2: check states --------------------------------------------------------
guard let mainMatte = trackMenu.items.first(where: { $0.title == "Matte" })?.submenu else {
    fail("Track ▸ Matte is missing")
}
func validated() -> [[String: Any]] {
    mainMatte.items.map { item in
        let enabled = controller.validateUserInterfaceItem(item)
        return ["title": item.title, "on": item.state == .on, "enabled": enabled]
    }
}
var states: [String: Any] = [:]
document.selection = [cM.id]
refresh()
states["currentM"] = ["current": controller.currentTrack?.id ?? 0, "items": validated()]
document.selection = [cL.id]
refresh()
states["currentL"] = ["current": controller.currentTrack?.id ?? 0, "items": validated()]
document.selection = []
refresh()
states["currentF"] = ["current": controller.currentTrack?.id ?? 0, "items": validated()]
states["contextM"] = items(contextMenu(tM))
states["contextL"] = items(contextMenu(tL))
states["contextO"] = items(contextMenu(tO))
answer["states"] = states

// ---- LN: a matte lane's clip, captured as the window paints it ------------
document.selection = []
refresh()
for _ in 0..<4 { turn(1); content.layoutSubtreeIfNeeded() }
let captureRect = content.bounds
guard let rep = content.bitmapImageRepForCachingDisplay(in: captureRect) else {
    fail("no bitmap for the timeline")
}
content.cacheDisplay(in: captureRect, to: rep)
let scale = CGFloat(rep.pixelsWide) / max(captureRect.width, 1)
func pixel(_ point: CGPoint) -> [Int] {
    let x = Int(((point.x - captureRect.minX) * scale).rounded(.down))
    let y = Int(((point.y - captureRect.minY) * scale).rounded(.down))
    // The capture's OWN encoding, not converted: the transparency layer is
    // composited there, so a 0.5 mix is linear in these numbers.
    guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
          let color = rep.colorAt(x: x, y: y)
    else { return [] }
    return [color.redComponent, color.greenComponent, color.blueComponent].map {
        Int(($0 * 255).rounded())
    }
}
/// A point inside `clip`'s body, under its name strip, clear of its edges.
func inside(_ clip: ClipSnapshot) -> CGPoint {
    let lane = timeline.layout.clipRect(clip, row: row(clip.track))
    let body = TimelineContentView.bodyRect(lane)
    return CGPoint(x: laneX(3), y: body.maxY - 5)
}
let matteFillPoint = inside(cM)
let laneOnlyPoint = CGPoint(x: laneX(8), y: matteFillPoint.y)
answer["lane"] = [
    "space": rep.colorSpaceName.rawValue, "scale": Double(scale), "contentWidth": Double(captureRect.width),
    "points": [[Double(matteFillPoint.x), Double(matteFillPoint.y)],
               [Double(laneOnlyPoint.x), Double(laneOnlyPoint.y)]],
    "matteClip": pixel(matteFillPoint),
    "matteLane": pixel(laneOnlyPoint),
    "ownFill": pixel(inside(cB)),
    "ordinaryControl": pixel(inside(cO)),
]

// ---- NT: the Clip tab's note ---------------------------------------------
let snapshot = document.project.snapshot
func note(_ clips: [ClipSnapshot]) -> Any {
    ClipPane.matteNote(clips: clips, tracks: snapshot.tracks) ?? NSNull()
}
answer["notes"] = [
    "singleM": note([cM]),
    "sharedM_M2": note([cM, cM2]),
    "mixedModeM_L": note([cM, cL]),
    "mixedOrdinaryM_B": note([cM, cB]),
    "noTargetL": note([cL]),
    "ordinaryB": note([cB]),
    "ordinaryB_O": note([cB, cO]),
    "empty": note([]),
]
func headerBlock(_ view: NSView) -> ClipHeaderBlock? {
    if let block = view as? ClipHeaderBlock { return block }
    for sub in view.subviews { if let found = headerBlock(sub) { return found } }
    return nil
}
func shownNote() -> Any {
    controller.view.layoutSubtreeIfNeeded()
    guard let block = headerBlock(controller.view) else { return "no block" }
    return block.noteText ?? NSNull()
}
var shown: [String: Any] = [:]
document.selection = [cM.id]
refresh()
controller.inspector?.select(.clip)
refresh()
shown["mFirstTab"] = shownNote()
controller.inspector?.selectClipSubTab(.clip)
refresh()
shown["mClipTab"] = shownNote()
document.selection = [cB.id]
refresh()
shown["b"] = shownNote()
document.selection = [cL.id]
refresh()
shown["l"] = shownNote()
answer["shownNotes"] = shown

// ---- HT: the canvas hit on a matte pair ---------------------------------
let hitDoc = ProjectDocument()
guard let back = hitDoc.project.snapshot.tracks.first?.id else { fail("no hit track") }
hitDoc.performGroupedEdit("Track", [.addTrack(index: 1)])
guard hitDoc.project.snapshot.tracks.count == 2 else { fail("the hit fixture has no 2 tracks") }
let front = hitDoc.project.snapshot.tracks[1].id
hitDoc.performGroupedEdit("Clips", [
    .addShapeClip(track: back, at: 0, duration: 2 * SEC, shape: .rectangle),
    .addShapeClip(track: front, at: 0, duration: 2 * SEC, shape: .rectangle),
])
guard let card = hitDoc.project.snapshot.clips(onTrack: back).first?.id,
      let windowClip = hitDoc.project.snapshot.clips(onTrack: front).first?.id
else { fail("the hit fixture's clips did not land") }
hitDoc.performGroupedEdit("Shape", [
    .setShapeRaw(clips: [card], patch: ["width": 1600.0, "height": 900.0]),
    .setShapeRaw(clips: [windowClip], patch: ["width": 200.0, "height": 200.0]),
    .setTrack(track: front, matte: .alpha),
])
let hitSnapshot = hitDoc.project.snapshot
guard let recipe = hitDoc.project.recipe(at: SEC / 2) else { fail("no recipe for the hit") }
let centre = CGPoint(
    x: Double(hitSnapshot.canvas.width) / 2, y: Double(hitSnapshot.canvas.height) / 2)
let outside = CGPoint(x: centre.x + 500, y: centre.y)
let boxes = CanvasLayerBox.boxes(recipe: recipe, snapshot: hitSnapshot)
/// `PreviewCanvasView.hit(at:)`'s body rule over the boxes it builds.
func canvasHit(_ point: CGPoint) -> Any {
    boxes.reversed().first(where: { !$0.locked && $0.contains(point) })?.id ?? NSNull()
}
func recipeHit(_ point: CGPoint) -> Any {
    recipe.layer(at: point, measuring: LayerRenderers.measuredSize(for:))?.clip ?? NSNull()
}
answer["hit"] = [
    "card": card, "window": windowClip,
    "windowInto": recipe.layers.first { $0.clip == windowClip }?.matte?.into ?? NSNull(),
    "layers": recipe.layers.map { $0.clip },
    "canvasInside": canvasHit(centre), "canvasOutside": canvasHit(outside),
    "recipeInside": recipeHit(centre), "recipeOutside": recipeHit(outside),
]

// ---- M3: the edits ------------------------------------------------------------
var edits: [String: Any] = [:]
// (a) the context menu on O — not the current track (F, the front-most, with
// nothing selected) — chooses Luma.
document.selection = []
refresh()
edits["currentBefore"] = controller.currentTrack?.id ?? 0
let before = document.project.json
let mattesBefore = mattes()
var performed = false
if let (sub, index) = matteItem(contextMenu(tO), "Luma") {
    asEvent { sub.performActionForItem(at: index) }
    performed = true
}
refresh()
let afterContext = document.project.json
edits["context"] = [
    "performed": performed, "before": mattesBefore, "after": mattes(),
    "undoName": document.undoManager?.undoActionName ?? "",
]
var again = false
if let (sub, index) = matteItem(contextMenu(tO), "Luma") {
    asEvent { sub.performActionForItem(at: index) }
    again = true
}
refresh()
edits["contextAgain"] = [
    "performed": again, "unchanged": document.project.json == afterContext,
    "undoName": document.undoManager?.undoActionName ?? "",
]
document.undoManager?.undo()
refresh()
edits["contextUndone"] = document.project.json == before

// (b) Track ▸ Matte ▸ Inverted Alpha with a clip on B selected (current = B).
document.selection = [cB.id]
refresh()
edits["menuCurrent"] = controller.currentTrack?.id ?? 0
let beforeMenu = document.project.json
let mattesBeforeMenu = mattes()
let inverted = mainMatte.items.first { $0.title == "Inverted Alpha" }
if let inverted { asEvent { controller.setTrackMatte(inverted) } }
refresh()
let afterMenu = document.project.json
edits["menu"] = [
    "performed": inverted != nil, "tag": inverted?.tag ?? -1, "before": mattesBeforeMenu,
    "after": mattes(), "undoName": document.undoManager?.undoActionName ?? "",
]
if let inverted { asEvent { controller.setTrackMatte(inverted) } }
refresh()
edits["menuAgain"] = [
    "unchanged": document.project.json == afterMenu,
    "undoName": document.undoManager?.undoActionName ?? "",
]
document.undoManager?.undo()
refresh()
edits["menuUndone"] = document.project.json == beforeMenu
answer["edits"] = edits

// ---- T2: the tag on a Small name line ------------------------------------
// M (cuts B) in each of the four modes, and L (nothing behind), on the Small
// text and audio rows: the width the frozen file clips the name by, and the
// words and box `drawMatteTag` draws, into an offscreen bitmap.
let headers = timeline.headers
let smallRows: [(String, CGFloat)] = [("text", DS.trackHeights[0][0]),
                                      ("audio", DS.trackHeights[0][2])]
func drawnTag(_ track: TrackSnapshot, height: CGFloat) -> (text: String, box: CGRect)? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(TimelineLayout.headerWidth),
        pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    return headers.drawMatteTag(
        track, row: CGRect(x: 0, y: 0, width: TimelineLayout.headerWidth, height: height),
        tracks: document.project.snapshot.tracks)
}
func nameLine(_ trackID: UInt32) -> [String: Any] {
    guard let track = document.project.snapshot.tracks.first(where: { $0.id == trackID }),
          let full = TimelineMatteTag.text(for: track, in: document.project.snapshot.tracks)
    else { return ["error": "no tag"] }
    var out: [String: Any] = ["full": full.text]
    for (kind, height) in smallRows {
        let drawn = drawnTag(track, height: height)
        out[kind] = [
            "height": Double(height),
            "ownLine": TimelineHeaderView.matteTagOnOwnLine(rowHeight: height),
            "clip": Double(headers.matteTagWidth(track, rowHeight: height)),
            "drawnText": drawn?.text ?? NSNull(),
            "drawnWidth": drawn.map { Double($0.box.width) } ?? NSNull(),
        ] as [String: Any]
    }
    return out
}
var nameLines: [[String: Any]] = []
for mode in TrackMatte.allCases where mode != .none {
    document.performGroupedEdit("Mode", [.setTrack(track: tM, matte: mode)])
    refresh()
    nameLines.append(nameLine(tM))
}
nameLines.append(nameLine(tL))
answer["nameLines"] = [
    "headerWidth": Double(TimelineLayout.headerWidth),
    "gap": Double(TimelineMatteTag.gap),
    "minimum": Double(TimelineMatteTag.minimumNameWidth),
    "rows": nameLines,
] as [String: Any]

// ---- T3: the tag's contrast in both looks --------------------------------
func rgba(_ color: () -> NSColor, _ look: NSAppearance.Name) -> [Double] {
    var out: [Double] = []
    NSAppearance(named: look)?.performAsCurrentDrawingAppearance {
        let resolved = color().usingColorSpace(.sRGB) ?? color()
        out = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent,
               resolved.alphaComponent].map { Double($0) }
    }
    return out
}
var looks: [String: Any] = [:]
for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    looks[name] = [
        "row": rgba({ DS.chromeBackground }, look),
        "dimmedFill": rgba({ TimelineMatteTag.fillColor(dimmed: true) }, look),
        "dimmedText": rgba({ TimelineMatteTag.textColor(dimmed: true) }, look),
        "fill": rgba({ TimelineMatteTag.fillColor(dimmed: false) }, look),
        "text": rgba({ TimelineMatteTag.textColor(dimmed: false) }, look),
    ]
}
answer["contrast"] = looks

write(answer)
