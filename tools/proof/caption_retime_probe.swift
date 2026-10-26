// #341 (spec §11 SR-27) — a speed or ramp edit of a clip with sound re-times
// the caption clips over it in the same undo step. Driven through the app's
// own `CaptionRetime`, `EditorViewController`, `SpeedSheetController`,
// `ProjectDocument` and `AgentServer`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` — the line
// `swift_build.py` builds. One process:
//
//   caption_retime_probe <request.json>
//
// The request names `work` (this run's directory). The answer is one JSON
// object on stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail",
// "instrument"}`; `caption_retime_probe.py` prints and scores them. Every wait
// pumps `RunLoop.main` and is bounded.
//
// The fixture, fresh per row: an untitled `ProjectDocument` (30 fps) with one
// media file of 60 s with sound, its `EditorViewController` the content of a
// 1440×900 window owned by the document's window controller, the document the
// one `NSDocumentController` holds so `AgentServer.shared.execute` edits it.
// Each row adds its own clips, tracks and captions.
//
// Every expected place is a literal oracle written here — a constant rate's
// halving or doubling, or the closed form of a linear ramp's source map
// (S(t) = t + (r − 1)·t²/(2D) for a ramp from ×1 to ×r over [0, D)) — snapped
// with the core's own `ReelTime.snapToFrame`; nothing is read from
// `CaptionRetime` but the plan's two id lists.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: caption_retime_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath, isDirectory: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
// As the app's `main.swift` does: the gate learns each tool's arguments here.
AgentLane.prepareAtLaunch()
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, instrument: Bool = false) {
    rows.append(["id": id, "pass": pass && !instrument, "detail": String(detail.prefix(1800)),
                 "instrument": instrument])
}
var documents: [ProjectDocument] = []
func finish() -> Never {
    for document in documents { document.removeTemporaryCacheDirectory() }
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return Date().timeIntervalSince(start) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition() ? Date().timeIntervalSince(start) : nil
}

func pause(_ limit: Double) { _ = waitUntil(limit) { false } }

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func views(_ sheet: NSWindow) -> [NSView] { sheet.contentView.map(walk) ?? [] }

// MARK: - The fixture

let second: Ticks = 600_000
let frame: Ticks = 20_000
var doc: ProjectDocument!
var controller: EditorViewController!
var window: NSWindow!
var windowControllers: [NSWindowController] = []
var v1: UInt32 = 0
var talk: UInt32 = 0

func mediaFile(_ name: String) -> String {
    let url = work.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: url.path) {
        try? Data("caption retime probe".utf8).write(to: url)
    }
    return url.path
}

/// A fresh document and window; nil, or why it could not be built.
func fresh() -> String? {
    window?.orderOut(nil)
    if let old = doc { NSDocumentController.shared.removeDocument(old) }
    doc = ProjectDocument()
    documents.append(doc)
    guard let track = doc.project.snapshot.tracks.first?.id else { return "no track" }
    v1 = track
    let path = mediaFile("talk.mov")
    doc.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
        path: path, kind: .video, duration: 60 * second, width: 1920, height: 1080,
        fps: .thirty, hasVideo: true, hasAudio: true))])
    guard let media = doc.project.snapshot.media.first(where: { $0.path == path })?.id else {
        return "add_media added nothing"
    }
    talk = media
    controller = EditorViewController(document: doc)
    window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    let windowController = NSWindowController(window: window)
    windowControllers.append(windowController)
    doc.addWindowController(windowController)
    NSDocumentController.shared.addDocument(doc)
    windowController.showWindow(nil)
    pause(0.2)
    return window.attachedSheet == nil ? nil : "a sheet was attached after set-up"
}

enum Fixture: Error { case failed(String) }

/// Applies set-up ops as one step; throws when they change nothing.
func setUp(_ ops: [ReelOp], _ what: String) throws {
    let before = doc.project
    doc.performGroupedEdit(what, ops)
    if doc.project === before { throw Fixture.failed("\(what) changed nothing") }
}

func addTrack(_ name: String) throws -> UInt32 {
    try setUp([.addTrack(index: doc.project.snapshot.tracks.count, name: name)], "track \(name)")
    guard let id = doc.project.snapshot.tracks.last(where: { $0.name == name })?.id else {
        throw Fixture.failed("no track named \(name)")
    }
    return id
}

/// The media clip at `at` on `track`, cut to `length`.
func addClip(_ track: UInt32, at: Ticks, length: Ticks) throws -> UInt32 {
    try setUp([.addClip(track: track, media: talk, at: at)], "clip at \(at)")
    guard let id = doc.project.snapshot.clips.first(where: { $0.track == track && $0.start == at })?.id
    else { throw Fixture.failed("no clip at \(at)") }
    try setUp([.trimEnd(clip: id, to: at + length)], "trim clip \(id)")
    return id
}

/// A text clip [from, to) on `track`; a word page when `words` (relative
/// to `from`) is given, its content one token per word.
func addCaption(
    _ track: UInt32, _ from: Ticks, _ to: Ticks, words: [(Ticks, Ticks)] = [],
    content: String? = nil
) throws -> UInt32 {
    try setUp([.addTextClip(
        track: track, at: from, duration: to - from,
        text: TextPatch(content: content ?? "cue at \(from)"))], "caption at \(from)")
    guard let id = doc.project.snapshot.clips.first(where: { $0.track == track && $0.start == from })?.id
    else { throw Fixture.failed("no caption at \(from)") }
    if !words.isEmpty {
        try setUp([.setText(clips: [id], patch: TextPatch(
            words: words.map { TextWord(start: $0.0, end: $0.1) }))], "words of \(id)")
    }
    return id
}

func addAction(_ clip: UInt32, at: Ticks, length: Ticks, speed: Double) throws -> UInt32 {
    try setUp([.addAction(clip: clip, at: at, duration: length)], "action")
    guard let id = doc.project.snapshot.clip(clip)?.actions.first(where: { $0.start == at })?.id
    else { throw Fixture.failed("no action at \(at)") }
    try setUp([
        .setAction(clip: clip, action: id, curve: .linear),
        .setActionEndRaw(clip: clip, action: id, patch: ["speed": speed]),
    ], "action end")
    return id
}

func snapped(_ t: Double) -> Ticks { ReelTime.snapToFrame(Ticks(t.rounded()), fps: .thirty) }

func span(_ id: UInt32, _ snapshot: ProjectSnapshot) -> [Ticks]? {
    snapshot.clip(id).map { [$0.start, $0.start + $0.duration] }
}

func spans(_ ids: [UInt32], _ snapshot: ProjectSnapshot) -> [[Ticks]?] {
    ids.map { span($0, snapshot) }
}

func show(_ spans: [[Ticks]?]) -> String {
    spans.map { $0.map { "[\($0[0]), \($0[1])]" } ?? "gone" }.joined(separator: " ")
}

/// The plan for `ops` on the edited container, and the snapshot of the edit
/// and the plan applied together.
func planned(_ ops: [ReelOp]) -> (plan: CaptionRetime.Plan, after: ProjectSnapshot?) {
    let project = doc.editedProject
    let plan = CaptionRetime.plan(ops, on: project)
    guard case .applied(let after)? = try? project.applying(ops + plan.ops) else {
        return (plan, nil)
    }
    return (plan, after.snapshot)
}

/// t from S(t) = s for a linear ramp ×1 → ×r over [0, D) (clip time, ticks).
func rampInverse(_ s: Double, rate r: Double, length d: Double) -> Double {
    let k = (r - 1) / (2 * d)
    return (-1 + (1 + 4 * k * s).squareRoot()) / (2 * k)
}

func rampForward(_ t: Double, rate r: Double, length d: Double) -> Double {
    t + (r - 1) * t * t / (2 * d)
}

func rowGuard(_ id: String, _ body: () throws -> Void) {
    if let why = fresh() {
        row(id, false, "instrument: fixture: \(why)", instrument: true)
        return
    }
    do { try body() } catch Fixture.failed(let why) {
        row(id, false, "instrument: fixture: \(why)", instrument: true)
    } catch {
        row(id, false, "instrument: \(error)", instrument: true)
    }
    settle()
}

func settle() {
    for _ in 0..<4 {
        if let inner = window.attachedSheet?.attachedSheet {
            window.attachedSheet?.endSheet(inner, returnCode: .alertSecondButtonReturn)
        }
        if waitUntil(1, { window.attachedSheet == nil }) != nil { break }
        if let stuck = window.attachedSheet { window.endSheet(stuck, returnCode: .cancel) }
    }
    pause(0.1)
}

var undoName: String { doc.undoManager?.undoActionName ?? "" }
var canUndo: Bool { doc.undoManager?.canUndo ?? false }

// MARK: - M1 — set_speed ×2, three abutting subtitles from the clip's start

rowGuard("M1") {
    let s = second
    let a = try addClip(v1, at: s, length: 4 * second)
    let caps = try addTrack("Captions")
    let ids = [
        try addCaption(caps, s, s + second), try addCaption(caps, s + second, s + 2 * second),
        try addCaption(caps, s + 2 * second, s + 3 * second),
    ]
    let before = spans(ids, doc.project.snapshot)
    let (plan, after) = planned([.setSpeed(clip: a, rate: 2)])
    let want: [[Ticks]?] = before.map { old in
        old.map { $0.map { s + snapped(Double($0 - s) / 2) } }
    }
    let got = after.map { spans(ids, $0) } ?? []
    row("M1", got == want && plan.retimed == ids && plan.removed.isEmpty,
        "got \(show(got)); want \(show(want)); retimed \(plan.retimed) removed \(plan.removed)")
}

// MARK: - M2 — ×0.5: cut back to abut the next clip's caption, one covered removed

rowGuard("M2") {
    let a = try addClip(v1, at: 0, length: 3 * second)
    let v2 = try addTrack("V2")
    _ = try addClip(v2, at: 3 * second + second / 2, length: 2 * second)
    let caps = try addTrack("Captions")
    let half = second / 2
    let ids = [
        try addCaption(caps, 0, half), try addCaption(caps, half, second),
        try addCaption(caps, second, 2 * second), try addCaption(caps, 2 * second, 2 * second + half),
    ]
    let next = try addCaption(caps, 3 * second + half, 4 * second + half)
    let (plan, after) = planned([.setSpeed(clip: a, rate: 0.5)])
    let want: [[Ticks]?] = [
        [0, second], [second, 2 * second], [2 * second, 3 * second + half], nil,
        [3 * second + half, 4 * second + half],
    ]
    let got = after.map { spans(ids + [next], $0) } ?? []
    row("M2", got == want && plan.retimed == Array(ids.prefix(3)) && plan.removed == [ids[3]],
        "got \(show(got)); want \(show(want)); retimed \(plan.retimed) removed \(plan.removed)")
}

// MARK: - M3 — linear Ramp Up ×2 over the whole clip

rowGuard("M3") {
    let d = 4 * second
    let a = try addClip(v1, at: 0, length: d)
    let caps = try addTrack("Captions")
    let marks: [Ticks] = [0, second, 5 * second / 2, d]
    let ids = [
        try addCaption(caps, marks[0], marks[1]), try addCaption(caps, marks[1], marks[2]),
        try addCaption(caps, marks[2], marks[3]),
    ]
    let (plan, after) = planned([.addSpeedRamp(clip: a, shape: .rampUp, rate: 2, curve: .linear)])
    let place = marks.map { snapped(rampInverse(Double($0), rate: 2, length: Double(d))) }
    let want: [[Ticks]?] = [[place[0], place[1]], [place[1], place[2]], [place[2], place[3]]]
    let got = after.map { spans(ids, $0) } ?? []
    row("M3", got == want && plan.retimed == ids && plan.removed.isEmpty,
        "got \(show(got)); want \(show(want)) (c′ = D(√(1+2c/D) − 1)); retimed "
            + "\(plan.retimed) removed \(plan.removed)")
}

// MARK: - M4 — linear Ramp Down ×0.5: past-out removed, a straddling page cut

/// t from S(t) = s for Ramp Down ×0.5 over [0, D): s = t − t²/(4D).
func downInverse(_ s: Double, length d: Double) -> Double {
    s >= 0.75 * d ? d : 2 * d * (1 - (1 - s / d).squareRoot())
}

rowGuard("M4") {
    let d = 4 * second
    let a = try addClip(v1, at: 0, length: d)
    let caps = try addTrack("Captions")
    let tenth = second / 10
    let first = try addCaption(caps, 0, second)
    let page = try addCaption(
        caps, 2 * second, 34 * tenth, words: [(0, 3 * tenth), (4 * tenth, 7 * tenth),
                                             (11 * tenth, 13 * tenth)],
        content: "alpha bravo charlie")
    let out1 = try addCaption(caps, 34 * tenth, 37 * tenth)
    let out2 = try addCaption(caps, 37 * tenth, d)
    let (plan, after) = planned([.addSpeedRamp(clip: a, shape: .rampDown, rate: 0.5, curve: .linear)])
    func at(_ s: Ticks) -> Ticks { snapped(downInverse(Double(s), length: Double(d))) }
    let wantFirst: [Ticks] = [0, at(second)]
    let wantPage: [Ticks] = [at(2 * second), d]
    let pageClip = after?.clip(page)
    let words = pageClip?.text?.words ?? []
    let wantWords = [2 * second, 24 * tenth].map { at($0) - wantPage[0] }
    let wordsNear = words.count == 2
        && zip(words.map(\.start), wantWords).allSatisfy { abs($0 - $1) <= frame }
    let content = pageClip?.text?.content
    let gone = after.map { $0.clip(out1) == nil && $0.clip(out2) == nil } ?? false
    let good = after.flatMap { span(first, $0) } == wantFirst
        && after.flatMap { span(page, $0) } == wantPage && wordsNear
        && content == "alpha bravo" && gone && plan.removed == [out1, out2]
        && plan.retimed == [first, page]
    row("M4", good,
        "first \(after.flatMap { span(first, $0) } ?? []) want \(wantFirst); page "
            + "\(after.flatMap { span(page, $0) } ?? []) want \(wantPage), words "
            + "\(words.map { [$0.start, $0.end] }) want starts ≈ \(wantWords), content "
            + "\(content ?? "nil"); past-out gone \(gone); retimed \(plan.retimed) removed "
            + "\(plan.removed)")
}

// MARK: - M6 — set_speed ×12: a 5-frame page snaps to nothing and is removed

rowGuard("M6") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let page = try addCaption(
        caps, 0, 5 * frame, words: [(0, 2 * frame), (2 * frame, 5 * frame)], content: "hi there")
    let n1 = try addCaption(caps, 5 * frame, 65 * frame)
    let n2 = try addCaption(caps, 65 * frame, 120 * frame)
    let (plan, after) = planned([.setSpeed(clip: a, rate: 12)])
    let want: [[Ticks]?] = [nil, [0, 5 * frame], [5 * frame, 10 * frame]]
    let got = after.map { spans([page, n1, n2], $0) } ?? []
    row("M6", got == want && plan.removed == [page] && plan.retimed == [n1, n2],
        "got \(show(got)); want \(show(want)); retimed \(plan.retimed) removed \(plan.removed)")
}

// MARK: - M7 — a word at the page's start never lands before its snapped start

rowGuard("M7") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let p1 = try addCaption(
        caps, frame, second + frame, words: [(0, 200_000), (200_000, 600_000)], content: "one two")
    let p2 = try addCaption(
        caps, 2 * second, 3 * second, words: [(-frame, 100_000), (100_000, 400_000)],
        content: "already said")
    let (plan, after) = planned([.setSpeed(clip: a, rate: 2)])
    let got = after.map { spans([p1, p2], $0) } ?? []
    let want: [[Ticks]?] = [[frame, 16 * frame], [second, 3 * second / 2]]
    let first1 = after?.clip(p1)?.text?.words.first?.start
    let first2 = after?.clip(p2)?.text?.words.first?.start
    // P1's start maps to 10000 and snaps half-away to 20000: its first word
    // at −10000 unclamped, which the core snaps to −20000.
    row("M7", got == want && first1 == 0 && (first2 ?? 0) < 0 && plan.retimed == [p1, p2],
        "got \(show(got)); want \(show(want)); first word P1 \(first1.map { "\($0)" } ?? "nil") "
            + "(want 0), P2 \(first2.map { "\($0)" } ?? "nil") (want < 0); retimed "
            + "\(plan.retimed) removed \(plan.removed)")
}

// MARK: - M8 — cut back at a fixed caption's place AFTER the edit

rowGuard("M8") {
    let a = try addClip(v1, at: 0, length: 3 * second)
    let caps = try addTrack("Captions")
    let c1 = try addCaption(caps, 0, second / 2)
    let c2 = try addCaption(caps, 2 * second, 5 * second / 2)
    let next = try addCaption(caps, 11 * second / 2, 13 * second / 2)
    let (plan, after) = planned([
        .setSpeed(clip: a, rate: 0.5), .moveClip(clips: [next], delta: -second),
    ])
    let got = after.map { spans([c1, c2, next], $0) } ?? []
    let want: [[Ticks]?] = [
        [0, second], [4 * second, 9 * second / 2], [9 * second / 2, 11 * second / 2],
    ]
    row("M8", got == want && plan.retimed == [c1, c2] && plan.removed.isEmpty,
        "got \(show(got)); want \(show(want)); retimed \(plan.retimed) removed \(plan.removed)")
}

// MARK: - M5 — controls, each left untouched

var controls: [String] = []
var controlsPass = true
func control(_ name: String, _ body: () throws -> (ops: [ReelOp], caption: UInt32)) {
    if let why = fresh() {
        controls.append("\(name): instrument: \(why)")
        controlsPass = false
        return
    }
    do {
        let (ops, caption) = try body()
        let before = span(caption, doc.project.snapshot)
        let (plan, after) = planned(ops)
        let now = after.flatMap { span(caption, $0) }
        let good = after != nil && plan.isEmpty && now == before
        controlsPass = controlsPass && good
        controls.append("\(name): \(good ? "untouched" : "MOVED") (plan retimed \(plan.retimed) "
            + "removed \(plan.removed); \(before ?? []) → \(now ?? []))")
    } catch {
        controls.append("\(name): instrument: \(error)")
        controlsPass = false
    }
    settle()
}

control("straddling") {
    let a = try addClip(v1, at: second, length: 3 * second)
    let caps = try addTrack("Captions")
    return ([.setSpeed(clip: a, rate: 2)], try addCaption(caps, second / 2, 3 * second / 2))
}
control("Titles track") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let titles = try addTrack("Titles")
    return ([.setSpeed(clip: a, rate: 2)], try addCaption(titles, second, 2 * second))
}
control("Captions track with a shape") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let caption = try addCaption(caps, second, 2 * second)
    try setUp([.addShapeClip(track: caps, at: 5 * second, duration: second)], "shape")
    return ([.setSpeed(clip: a, rate: 2)], caption)
}
control("locked Captions track") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let caption = try addCaption(caps, second, 2 * second)
    try setUp([.setTrack(track: caps, locked: true)], "lock")
    return ([.setSpeed(clip: a, rate: 2)], caption)
}
control("detached picture clip") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let caption = try addCaption(caps, second, 2 * second)
    try setUp([.detachAudio(clip: a)], "detach")
    return ([.setSpeed(clip: a, rate: 2)], caption)
}
control("zoom set_action") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let caption = try addCaption(caps, second, 2 * second)
    try setUp([.addZoomAction(
        clip: a, at: 0, duration: second,
        region: ZoomRegion(x: 0, y: 0, width: 960, height: 540))], "zoom")
    guard let zoom = doc.project.snapshot.clip(a)?.actions.first?.id else {
        throw Fixture.failed("no zoom action")
    }
    return ([.setAction(clip: a, action: zoom, start: second)], caption)
}
row("M5", controlsPass && controls.count == 6, controls.joined(separator: "; "))

// MARK: - The doors

/// Clip ▸ Speed… on `clips` with `rate` typed into its field, then Apply.
func speedSheetApply(_ clips: [UInt32], rate: Double) -> NSWindow? {
    doc.selection = Set(clips)
    controller.presentSpeedSheet()
    guard waitUntil(3, { window.attachedSheet != nil }) != nil,
        let sheet = window.attachedSheet,
        let speed = sheet.contentViewController as? SpeedSheetController,
        let field = views(sheet).compactMap({ $0 as? NSTextField })
            .first(where: { $0.delegate === speed })
    else { return nil }
    field.doubleValue = rate
    speed.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: field))
    let click = NSSelectorFromString("applyClicked:")
    guard let button = views(sheet).compactMap({ $0 as? NSButton })
        .first(where: { $0.action == click }),
        NSApp.sendAction(click, to: button.target, from: button)
    else { return nil }
    return sheet
}

/// D1: the Speed sheet at ×0.5 over three abutting captions — one step named
/// "Set Speed and Re-time Captions", and one undo puts every caption back.
rowGuard("D1") {
    let a = try addClip(v1, at: 0, length: 3 * second)
    let caps = try addTrack("Captions")
    let half = second / 2
    let ids = [
        try addCaption(caps, 0, half), try addCaption(caps, half, second),
        try addCaption(caps, second, 2 * second),
    ]
    doc.undoManager?.removeAllActions()
    let before = spans(ids, doc.project.snapshot)
    guard let sheet = speedSheetApply([a], rate: 0.5) else {
        throw Fixture.failed("the Speed sheet did not attach or apply")
    }
    _ = waitUntil(3) { window.attachedSheet == nil || sheet.attachedSheet != nil }
    let got = spans(ids, doc.project.snapshot)
    let want: [[Ticks]?] = [[0, second], [second, 2 * second], [2 * second, 4 * second]]
    let name = undoName
    doc.undoManager?.undo()
    let undone = spans(ids, doc.project.snapshot)
    let speedBack = doc.project.snapshot.clip(a)?.speed == 1
    row("D1", got == want && name == "Set Speed and Re-time Captions" && undone == before
            && speedBack && !canUndo,
        "got \(show(got)); want \(show(want)); step \"\(name)\"; after one undo "
            + "\(show(undone)) (want \(show(before))), speed ×1 \(speedBack), canUndo \(canUndo)")
}

/// D2: the inspector's commit of a `set_action_end {speed}` (the Speed
/// section's Rate inside an action) — an action over the whole clip, linear,
/// ending at ×2, so M3's oracle.
rowGuard("D2") {
    let d = 4 * second
    let a = try addClip(v1, at: 0, length: d)
    try setUp([.addAction(clip: a, at: 0, duration: d)], "action")
    guard let action = doc.project.snapshot.clip(a)?.actions.first?.id else {
        throw Fixture.failed("no action")
    }
    doc.performGroupedEdit("curve", [.setAction(clip: a, action: action, curve: .linear)])
    guard doc.project.snapshot.clip(a)?.actions.first?.curve == .linear else {
        throw Fixture.failed("the action's curve is not linear")
    }
    let caps = try addTrack("Captions")
    let marks: [Ticks] = [0, second, 5 * second / 2]
    let ids = [try addCaption(caps, marks[0], marks[1]), try addCaption(caps, marks[1], marks[2])]
    guard let onEdit = controller.inspector?.onEdit else {
        throw Fixture.failed("no inspector onEdit")
    }
    onEdit("Set Speed", [.setActionEnd(clip: a, action: action, patch: ActionPatch(speed: 2))])
    pause(0.2)
    let place = marks.map { snapped(rampInverse(Double($0), rate: 2, length: Double(d))) }
    let want: [[Ticks]?] = [[place[0], place[1]], [place[1], place[2]]]
    let got = spans(ids, doc.project.snapshot)
    row("D2", got == want && undoName == "Set Speed and Re-time Captions",
        "got \(show(got)); want \(show(want)); step \"\(undoName)\"")
}

/// D3: the timeline's ⌥-drag rate stretch to half the length: the captions
/// stay put during the drag and halve at its end, one step.
rowGuard("D3") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let ids = [
        try addCaption(caps, 0, second), try addCaption(caps, second, 2 * second),
        try addCaption(caps, 2 * second, 3 * second),
    ]
    guard let timeline = controller.timeline, let begin = timeline.onLiveBegin,
        let update = timeline.onLiveUpdate, let end = timeline.onLiveEnd
    else { throw Fixture.failed("no timeline live closures") }
    let before = spans(ids, doc.project.snapshot)
    begin()
    update([.rateStretch(clip: a, toEnd: 2 * second)])
    let during = spans(ids, doc.project.snapshot)
    let stretched = doc.project.snapshot.clip(a)?.duration == 2 * second
    end("Rate Stretch")
    let want: [[Ticks]?] = [[0, second / 2], [second / 2, second], [second, 3 * second / 2]]
    let got = spans(ids, doc.project.snapshot)
    row("D3", stretched && during == before && got == want
            && undoName == "Rate Stretch and Re-time Captions" && !doc.isLiveEditing,
        "the tick stretched \(stretched); during \(show(during)) (want unchanged); after "
            + "\(show(got)) want \(show(want)); step \"\(undoName)\"")
}

/// D4: the Clip tab lane's band drag (the inspector's live closures): a
/// linear ×2 speed action [0, D/2) resized to [0, D).
rowGuard("D4") {
    let d = 4 * second
    let a = try addClip(v1, at: 0, length: d)
    let action = try addAction(a, at: 0, length: d / 2, speed: 2)
    let caps = try addTrack("Captions")
    let marks: [Ticks] = [0, second, 2 * second]
    let ids = [try addCaption(caps, marks[0], marks[1]), try addCaption(caps, marks[1], marks[2])]
    guard let inspector = controller.inspector, let begin = inspector.onLiveBegin,
        let update = inspector.onLiveUpdate, let end = inspector.onLiveEnd
    else { throw Fixture.failed("no inspector live closures") }
    let before = spans(ids, doc.project.snapshot)
    begin()
    update([.setAction(clip: a, action: action, duration: d)])
    let during = spans(ids, doc.project.snapshot)
    end("Action")
    // Old: ×1→×2 over [0, D/2), then ×2 held; new: ×1→×2 over [0, D).
    let h = Double(d) / 2
    func oldSource(_ t: Double) -> Double {
        t <= h ? rampForward(t, rate: 2, length: h) : rampForward(h, rate: 2, length: h) + 2 * (t - h)
    }
    let place = marks.map { snapped(rampInverse(oldSource(Double($0)), rate: 2, length: Double(d))) }
    let want: [[Ticks]?] = [[place[0], place[1]], [place[1], place[2]]]
    let got = spans(ids, doc.project.snapshot)
    row("D4", during == before && got == want && undoName == "Action and Re-time Captions",
        "during \(show(during)) (want unchanged); after \(show(got)) want \(show(want)); step "
            + "\"\(undoName)\"")
}

/// D5: ⌫ with a whole-clip linear Ramp Up ×2 selected: the captions go back
/// to ×1, and the one whose source the clip no longer plays is removed.
rowGuard("D5") {
    let d = 4 * second
    let a = try addClip(v1, at: 0, length: d)
    try setUp([.addSpeedRamp(clip: a, shape: .rampUp, rate: 2, curve: .linear)], "ramp")
    guard let action = doc.project.snapshot.clip(a)?.actions.first?.id else {
        throw Fixture.failed("no ramp action")
    }
    let caps = try addTrack("Captions")
    let ids = [
        try addCaption(caps, 0, second), try addCaption(caps, second, 2 * second),
        try addCaption(caps, 3 * second, 4 * second),
    ]
    doc.selection = [a]
    doc.selectAction(action)
    guard doc.selectedAction == action else { throw Fixture.failed("the action is not selected") }
    controller.removeSelectedActionCommand()
    func at(_ t: Ticks) -> Ticks { snapped(rampForward(Double(t), rate: 2, length: Double(d))) }
    let want: [[Ticks]?] = [[0, at(second)], [at(second), at(2 * second)], nil]
    let got = spans(ids, doc.project.snapshot)
    let removed = doc.project.snapshot.clip(a)?.actions.isEmpty == true
    row("D5", removed && got == want && undoName == "Remove Action and Re-time Captions",
        "action removed \(removed); got \(show(got)); want \(show(want)); step \"\(undoName)\"")
}

/// D6: the Speed sheet at ×20 asks; Cancel leaves the captions and makes no
/// step.
rowGuard("D6") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let ids = [try addCaption(caps, 0, second), try addCaption(caps, second, 2 * second)]
    doc.undoManager?.removeAllActions()
    let handle = doc.project
    guard let sheet = speedSheetApply([a], rate: 20) else {
        throw Fixture.failed("the Speed sheet did not attach or apply")
    }
    var question: NSWindow?
    _ = waitUntil(3) {
        question = sheet.attachedSheet
        return question != nil
    }
    guard let asked = question else {
        row("D6", false, "no question attached to the Speed sheet within 3 s")
        return
    }
    sheet.endSheet(asked, returnCode: .alertSecondButtonReturn)
    pause(0.3)
    let same = doc.project === handle
    let got = spans(ids, doc.project.snapshot)
    row("D6", same && !canUndo && got == [[0, second], [second, 2 * second]],
        "asked; after Cancel the same handle \(same), canUndo \(canUndo), captions \(show(got))")
}

/// The D7/D8 fixture: a 4 s clip and two abutting captions.
func questionFixture() throws -> (a: UInt32, c1: UInt32, c2: UInt32) {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    return (a, try addCaption(caps, 0, 20 * frame), try addCaption(caps, 20 * frame, 40 * frame))
}

/// Moves `c2` 20 frames later while the question is up; throws when the
/// document did not change.
func moveWhileAsked(_ c2: UInt32) throws {
    let handle = doc.project
    doc.performGroupedEdit("Move", [.moveClip(clips: [c2], delta: 20 * frame)])
    if doc.project === handle { throw Fixture.failed("the move while asked changed nothing") }
}

/// D7: a ×20 Speed sheet asks; a caption is moved while the question is up;
/// Set Speed re-plans on the moved document.
rowGuard("D7") {
    let (a, c1, c2) = try questionFixture()
    guard let sheet = speedSheetApply([a], rate: 20) else {
        throw Fixture.failed("the Speed sheet did not attach or apply")
    }
    var question: NSWindow?
    _ = waitUntil(3) {
        question = sheet.attachedSheet
        return question != nil
    }
    guard let asked = question else {
        row("D7", false, "no question attached to the Speed sheet within 3 s")
        return
    }
    try moveWhileAsked(c2)
    sheet.endSheet(asked, returnCode: .alertFirstButtonReturn)
    pause(0.3)
    let got = spans([c1, c2], doc.project.snapshot)
    let speed = doc.project.snapshot.clip(a)?.speed
    row("D7", got == [[0, frame], [2 * frame, 3 * frame]] && speed == 20
            && undoName == "Set Speed and Re-time Captions",
        "after the move and Set Speed: captions \(show(got)) (want [0, \(frame)] "
            + "[\(2 * frame), \(3 * frame)]), speed \(speed.map { "\($0)" } ?? "nil"), step "
            + "\"\(undoName)\"")
}

/// D8: the timeline's live rate stretch to ×20 asks at its end; a caption is
/// moved while the question is up; Set Speed re-plans on the moved document.
rowGuard("D8") {
    let (a, c1, c2) = try questionFixture()
    guard let timeline = controller.timeline, let begin = timeline.onLiveBegin,
        let update = timeline.onLiveUpdate, let end = timeline.onLiveEnd
    else { throw Fixture.failed("no timeline live closures") }
    begin()
    update([.rateStretch(clip: a, toEnd: 6 * frame)])
    end("Rate Stretch")
    guard waitUntil(3, { window.attachedSheet != nil }) != nil, let asked = window.attachedSheet
    else {
        row("D8", false, "no question attached to the window within 3 s")
        return
    }
    try moveWhileAsked(c2)
    window.endSheet(asked, returnCode: .alertFirstButtonReturn)
    pause(0.3)
    let got = spans([c1, c2], doc.project.snapshot)
    let duration = doc.project.snapshot.clip(a)?.duration
    row("D8", got == [[0, frame], [2 * frame, 3 * frame]] && duration == 6 * frame
            && undoName == "Rate Stretch and Re-time Captions",
        "after the move and Set Speed: captions \(show(got)) (want [0, \(frame)] "
            + "[\(2 * frame), \(3 * frame)]), duration \(duration.map { "\($0)" } ?? "nil"), "
            + "step \"\(undoName)\"")
}

// MARK: - A1–A3 — MCP: the answer names what was re-timed and removed

func call(_ tool: String, _ args: [String: Any]) -> ([String: Any]?, String) {
    let json = (try? JSONSerialization.data(withJSONObject: args))
        .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    let raw = AgentServer.shared.execute(tool: tool, argumentsJSON: json)
    guard let envelope = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
        (envelope["isError"] as? Bool) != true,
        let content = envelope["content"] as? [[String: Any]],
        let text = content.first?["text"] as? String,
        let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    else { return (nil, String(raw.prefix(400))) }
    return (object, text)
}

rowGuard("A1") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let ids = [try addCaption(caps, 0, second), try addCaption(caps, second, 2 * second)]
    let (answer, raw) = call("set_speed", ["clip": Int(a), "rate": 2])
    let got = spans(ids, doc.project.snapshot)
    let retimed = answer?["captions_retimed"] as? [Int]
    row("A1", retimed == ids.map { Int($0) } && answer?["captions_removed"] == nil
            && got == [[0, second / 2], [second / 2, second]]
            && undoName == "Speed and Re-time Captions",
        "answer \(raw.prefix(500)); captions \(show(got)); step \"\(undoName)\"")
}

rowGuard("A2") {
    let d = 4 * second
    let a = try addClip(v1, at: 0, length: d)
    let caps = try addTrack("Captions")
    let tenth = second / 10
    let first = try addCaption(caps, 0, second)
    let out = try addCaption(caps, 34 * tenth, 37 * tenth)
    let (answer, raw) = call(
        "add_speed_ramp", ["clip": Int(a), "shape": "ramp_down", "rate": 0.5, "curve": "linear"])
    let removed = answer?["captions_removed"] as? [Int]
    let retimed = answer?["captions_retimed"] as? [Int]
    let gone = doc.project.snapshot.clip(out) == nil
    row("A2", removed == [Int(out)] && retimed == [Int(first)] && gone
            && (answer?["new_actions"] as? [Int])?.count == 1,
        "answer \(raw.prefix(500)); the past-out caption gone \(gone)")
}

rowGuard("A3") {
    let a = try addClip(v1, at: 0, length: 4 * second)
    let caps = try addTrack("Captions")
    let caption = try addCaption(caps, second, 2 * second)
    try setUp([.addZoomAction(
        clip: a, at: 0, duration: second,
        region: ZoomRegion(x: 0, y: 0, width: 960, height: 540))], "zoom")
    guard let zoom = doc.project.snapshot.clip(a)?.actions.first?.id else {
        throw Fixture.failed("no zoom action")
    }
    let (answer, raw) = call(
        "set_action", ["clip": Int(a), "action": Int(zoom), "start": Int(second)])
    let keys = answer.map { $0.keys.filter { $0.hasPrefix("captions_") } } ?? ["no answer"]
    let still = span(caption, doc.project.snapshot) == [second, 2 * second]
    row("A3", answer != nil && keys.isEmpty && still && undoName == "Action",
        "answer \(raw.prefix(400)); captions_ keys \(keys); caption untouched \(still); step "
            + "\"\(undoName)\"")
}

finish()
