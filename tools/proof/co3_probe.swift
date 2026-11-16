// Road map "creator-jobs" CO3 (spec §11 CO-30, CO-31, CO-32): the probe of `co3_proof.py`,
// compiled as `main.swift` over `app/Sources` through `swift_build.build()` with
// `FRAMEJOB_DEV_TOOLS`, so every row drives the app's own `ClipPane`, `InspectorBinding`,
// `EditorViewController`, `ProjectDocument` and `CutoutStatus`. Modes:
//
// - `co3-probe <request.json>`: the rows. The request names `work` (this run's folder). One
//   JSON object on stdout, `{"rows": [{"id", "pass", "detail"}]}`.
// - `co3-probe header <request.json>`: I9 alone, in a process of its own, because it registers
//   `-RCDevAnalysisHold 3600` before the lane's first job. Same request and answer as the rows.
// - `co3-probe centroid <request.json>`: the probe's OWN centroid of a pack (I6), never
//   `CutoutStatus.centroid`: `MaskPack` reads the file, and the arithmetic is this file's — per
//   frame whose grid index lies in `need` and `coverage` and whose mask is found, `Σ v·(2x + 1)
//   / (2 Σ v)` (likewise y) in integers, the frames' mean scaled by `width / mask width` and
//   `height / mask height`. The request names `pack`, `need` and `coverage` (`[[a, b], …]`),
//   `width` and `height`. Prints `{"ok", "x", "y", "frames"}`.
//
// Rows:
// - I1 the Picture sub-tab's sections hold `video.cutout` right after `video.chroma`, and its
//   checkbox, pressed on a clip without a cutout, commits exactly one edit, "Remove
//   Background", of one `set_video {cutout: {subject, quality, background, edge, feather}}` at
//   the defaults, which the clip then holds.
// - I3 a cut-out clip with an action selected: Edge's quick value 0.25 commits one
//   `set_action_end` whose patch is exactly `{video: {cutout: {edge: 0.25}}}` and no `off`;
//   Background's Keep exactly `{video: {cutout: {background: "keep"}}}`; the checkbox's gutter
//   is ⊘ and pressing it commits one BASE `set_video {cutout: null}`.
// - I5 Clip ▸ Remove Background follows Look with no key equivalent; over two clips, its state
//   is off (none cut out), mixed (one) and, after the toggle, on; the toggle on the mixed
//   selection turns on only the clip without one (the other's edge 0.3 kept) as one undo step,
//   "Remove Background", which one undo takes back whole.
// - I6p the probe's own centroid over a hand-made pack (two found frames in the need, one not
//   found, one outside it) is (3.0, 5.0) over 2 frames — worked by hand — and the app's
//   `CutoutStatus.centroid` agrees.
// - I8 `CutoutStatus.progress`: need 0…999, covered 0…399, running 0…999 at f 0.4 → 0.400;
//   running 200…999 at f 0.25 → 0.400; no running request → 0.400.
// - I9 (header mode, #438) a cut-out clip's Background section, shut, in an offscreen window
//   with the masks job held: its Status and its header summary both read "Analyzing 0 %"; the
//   running request's fraction set to 0.5 (`AnalysisLane.devSetProgress`), within 1.5 s both
//   read "Analyzing 50 %" — a progress-only tick refreshes the header too.
// - I10 (#438) `CutoutStatus.stamp` of a media at `work/stamp.mov` is nil while the file is
//   absent and non-nil once it is written: a nil stamp is not memoised.
// - I11 (#438) `AgentServer.cutoutDetails` over three hand-made details with a counting `read`:
//   with nothing kept it reads 3; with [ready, analysing, failed] kept under the same handles it
//   reads only the analysing clip and returns the kept ready and failed details; with the same
//   kept and another `project` handle it reads 3.

import AppKit

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

func printJSON(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

func ranges(_ raw: Any?) -> [ClosedRange<Int>] {
    ((raw as? [[NSNumber]]) ?? []).compactMap { pair in
        pair.count == 2 && pair[0].intValue <= pair[1].intValue
            ? pair[0].intValue...pair[1].intValue : nil
    }
}

/// The probe's own centroid (the header's arithmetic).
func probeCentroid(
    pack: MaskPack, need: [ClosedRange<Int>], coverage: [ClosedRange<Int>], width: Int,
    height: Int
) throws -> (x: Double, y: Double, frames: Int)? {
    var sumX = 0.0, sumY = 0.0, frames = 0
    for frame in pack.frames {
        let index = Int(frame.index)
        guard need.contains(where: { $0.contains(index) }),
            coverage.contains(where: { $0.contains(index) }),
            pack.masks[Int(frame.slot)].found
        else { continue }
        let mask = try pack.mask(slot: Int(frame.slot))
        var total: UInt64 = 0, x2: UInt64 = 0, y2: UInt64 = 0
        for (offset, value) in mask.enumerated() where value > 0 {
            let v = UInt64(value)
            total += v
            x2 += v * UInt64(2 * (offset % pack.width) + 1)
            y2 += v * UInt64(2 * (offset / pack.width) + 1)
        }
        guard total > 0 else { continue }
        sumX += Double(x2) / Double(2 * total)
        sumY += Double(y2) / Double(2 * total)
        frames += 1
    }
    guard frames > 0 else { return nil }
    return (sumX / Double(frames) * Double(width) / Double(pack.width),
            sumY / Double(frames) * Double(height) / Double(pack.height), frames)
}

let arguments = CommandLine.arguments
let headerMode = arguments.count == 3 && arguments[1] == "header"
if headerMode {
    // Before the lane's first job: every masks job holds before its first frame.
    UserDefaults.standard.register(defaults: [AnalysisLane.devHoldKey: 3600])
}
if arguments.count == 3, arguments[1] == "centroid" {
    var answer: [String: Any] = ["ok": false]
    if let data = FileManager.default.contents(atPath: arguments[2]),
        let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let path = request["pack"] as? String, let width = request["width"] as? Int,
        let height = request["height"] as? Int
    {
        do {
            let pack = try MaskPack(contentsOf: URL(fileURLWithPath: path))
            if let point = try probeCentroid(
                pack: pack, need: ranges(request["need"]), coverage: ranges(request["coverage"]),
                width: width, height: height)
            {
                answer = ["ok": true, "x": point.x, "y": point.y, "frames": point.frames]
            } else {
                answer = ["ok": true, "x": NSNull(), "y": NSNull(), "frames": 0]
            }
        } catch {
            answer = ["ok": false, "why": "\(error)"]
        }
    }
    printJSON(answer)
    exit(0)
}

guard arguments.count == 2 || headerMode,
    let requestData = FileManager.default.contents(atPath: arguments[arguments.count - 1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let workPath = request["work"] as? String
else {
    for id in headerMode ? ["I9"] : ["I1", "I3", "I5", "I6p", "I8", "I10", "I11"] {
        row(id, false, "the request could not be read")
    }
    printJSON(["rows": rows])
    exit(0)
}
let work = URL(fileURLWithPath: workPath, isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

let second: Ticks = 600_000
var documents: [ProjectDocument] = []
var kept: [AnyObject] = []

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func finish() -> Never {
    for document in documents { document.removeTemporaryCacheDirectory() }
    printJSON(["rows": rows])
    exit(0)
}

/// A document holding one 10 s 640 × 360 video media and `count` clips of it, each from 0 on
/// its own track; the clip ids.
func makeDocument(clips count: Int) -> (ProjectDocument, [UInt32])? {
    let movie = work.appendingPathComponent("movie.mov")
    if !FileManager.default.fileExists(atPath: movie.path) {
        try? Data("co3 probe".utf8).write(to: movie)
    }
    let document = ProjectDocument()
    documents.append(document)
    document.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
        path: movie.path, kind: .video, duration: 10 * second, width: 640, height: 360,
        fps: .thirty, hasVideo: true, hasAudio: false))])
    guard let media = document.project.snapshot.media.first?.id else { return nil }
    var ids: [UInt32] = []
    for index in 0..<count {
        while document.project.snapshot.tracks.count <= index {
            document.performGroupedEdit(
                "Track", [.addTrack(index: document.project.snapshot.tracks.count)])
        }
        let track = document.project.snapshot.tracks[index].id
        document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: 0)])
        guard let clip = document.project.snapshot.clips.first(where: { $0.track == track })
        else { return nil }
        ids.append(clip.id)
    }
    return (document, ids)
}

/// A Clip pane over `document` with `selection` and `action` selected and no window; every
/// commit recorded in `sent` and applied.
var sent: [(name: String, ops: [ReelOp])] = []
/// Whether a commit is applied as well as recorded. I3's last press only records: a mutant's
/// wrong op could put up an app-modal error alert, which would hang the probe.
var applying = true
func clipPane(_ document: ProjectDocument, _ selection: Set<UInt32>, action: UInt32?) -> ClipPane {
    let inspector = InspectorViewController()
    inspector.document = document
    inspector.onEdit = { [weak document] name, ops in
        sent.append((name, ops))
        if applying { document?.applyEdit(name, ops) }
    }
    inspector.onSelectAction = { [weak document] id in document?.selectAction(id) }
    document.selection = selection
    document.selectAction(action)
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    kept += [inspector, pane]
    pane.binding.invalidate()
    pane.choose(.picture)
    pane.rebuild()
    pane.refresh()
    return pane
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func labelled(_ section: InspectorSection, _ label: String) -> InspectorRowView? {
    walk(section).compactMap { $0 as? InspectorRowView }.first { row in
        row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == label }
    }
}

func parsed(_ op: ReelOp) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
}

func same(_ a: Any?, _ b: Any) -> Bool {
    guard let a else { return false }
    return (a as AnyObject).isEqual(b)
}

let click = NSEvent.mouseEvent(
    with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
let defaults: [String: Any] = [
    "subject": "person", "quality": "standard", "background": "remove", "edge": 0.0,
    "feather": 0.0,
]

// ---- I9 (header mode) --------------------------------------------------------------------------

if headerMode {
    var problems: [String] = []
    if let (document, ids) = makeDocument(clips: 1),
        let media = document.project.snapshot.media.first?.id,
        let cacheDir = document.intendedCacheDirectory
    {
        let clip = ids[0]
        document.performGroupedEdit(
            "Cutout", [.setVideo(clips: [clip], patch: VideoPatch(cutout: .some(CutoutProps())))])
        let pane = clipPane(document, [clip], action: nil)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: 0, width: 320, height: 900), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView = pane
        kept.append(window)
        pane.refresh()
        let section = pane.sections.first { $0.id == "video.cutout" }
        let readout = section.flatMap { labelled($0, "Status") }.flatMap { row in
            walk(row).lazy.compactMap { $0 as? OptionDisplayControl }.first
        }
        func summary() -> String? {
            section.flatMap { section in
                Mirror(reflecting: section.header).children
                    .first { $0.label == "lastSummary" }?.value as? String
            }
        }
        func both(_ words: String, within seconds: Double) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if readout?.text == words, summary() == words { return true }
                spin(0.05)
            }
            return readout?.text == words && summary() == words
        }
        func running() -> AnalysisRequest? {
            CutoutStatus.runningRequest(
                CutoutStatus.ownerRequests(document.maskOwner, media: media, cacheDir: cacheDir))
        }
        if section == nil || readout == nil { problems.append("no Background section or Status") }
        if section?.isExpanded == true { problems.append("the section is open") }
        let first = both("Analyzing 0 %", within: 10)
        if !first {
            problems.append(
                "before: Status \(String(describing: readout?.text)), header "
                    + "\(String(describing: summary())) (want \"Analyzing 0 %\")")
        }
        var request: AnalysisRequest?
        let deadline = Date().addingTimeInterval(10)
        while request == nil, Date() < deadline {
            request = running()
            if request == nil { spin(0.05) }
        }
        if let request {
            AnalysisLane.shared.devSetProgress(0.5, of: request)
            spin(1.5)
            if readout?.text != "Analyzing 50 %" || summary() != "Analyzing 50 %" {
                problems.append(
                    "after the fraction 0.5: Status \(String(describing: readout?.text)), header "
                        + "\(String(describing: summary())) (want \"Analyzing 50 %\" both)")
            }
        } else {
            problems.append("no running masks request within 10 s")
        }
    } else {
        problems.append("the fixture could not be made")
    }
    row("I9", problems.isEmpty,
        problems.isEmpty
            ? "Status and header \"Analyzing 0 %\", then both \"Analyzing 50 %\" after a progress tick"
            : problems.joined(separator: "; "))
    finish()
}

// ---- I1 -------------------------------------------------------------------------------------

if let (document, ids) = makeDocument(clips: 1), let event = click {
    let pane = clipPane(document, [ids[0]], action: nil)
    let order = pane.sections.map(\.id)
    let chroma = order.firstIndex(of: "video.chroma")
    let cutout = order.firstIndex(of: "video.cutout")
    let section = pane.sections.first { $0.id == "video.cutout" }
    let check = section.flatMap { walk($0).lazy.compactMap { $0 as? OptionCheckboxControl }.first }
    sent = []
    check?.mouseDown(with: event)
    let op = sent.count == 1 && sent[0].ops.count == 1 ? parsed(sent[0].ops[0]) : [:]
    let patch = op["patch"] as? [String: Any]
    let stored = document.project.snapshot.clip(ids[0])?.video?.cutout
    row("I1",
        chroma != nil && cutout == chroma.map { $0 + 1 } && section?.title == "Background"
            && sent.count == 1 && sent.first?.name == "Remove Background"
            && op["op"] as? String == "set_video"
            && same(op["clips"], [NSNumber(value: ids[0])])
            && patch?.count == 1 && same(patch?["cutout"], defaults)
            && stored == CutoutProps(),
        "sections \(order); commits \(sent.map { ($0.name, $0.ops.map(\.json)) }); stored "
            + "\(String(describing: stored))")
} else {
    row("I1", false, "the fixture could not be made")
}

// ---- I3 -------------------------------------------------------------------------------------

if let (document, ids) = makeDocument(clips: 1), let event = click {
    let clip = ids[0]
    document.performGroupedEdit(
        "Cutout", [.setVideo(clips: [clip], patch: VideoPatch(cutout: .some(CutoutProps())))])
    document.performGroupedEdit("Action", [.addAction(clip: clip, at: second, duration: second)])
    let action = document.project.snapshot.clip(clip)?.actions.first?.id
    let pane = clipPane(document, [clip], action: action)
    let section = pane.sections.first { $0.id == "video.cutout" }
    var problems: [String] = []
    if action == nil || document.selectedAction != action { problems.append("no action selected") }
    func end(_ label: String, _ want: [String: Any], _ pick: (InspectorRowView) -> Void) {
        sent = []
        guard let section, let row = labelled(section, label) else {
            problems.append("no \(label) row")
            return
        }
        pick(row)
        let op = sent.count == 1 && sent[0].ops.count == 1 ? parsed(sent[0].ops[0]) : [:]
        if op["op"] as? String != "set_action_end" || op["off"] != nil
            || !same(op["patch"], ["video": ["cutout": want]])
        {
            problems.append("\(label) committed \(sent.map { $0.ops.map(\.json) })")
        }
        pane.binding.invalidate()
        pane.refresh()
    }
    end("Edge", ["edge": 0.25]) { row in
        let field = walk(row).lazy.compactMap { $0 as? OptionFieldControl }.first
        let item = NSMenuItem(title: "0.25", action: nil, keyEquivalent: "")
        item.tag = 3
        _ = field?.perform(NSSelectorFromString("quickPicked:"), with: item)
    }
    end("Background", ["background": "keep"]) { row in
        let popup = walk(row).lazy.compactMap { $0 as? OptionPopupControl }.first
        let item = NSMenuItem(title: "Keep", action: nil, keyEquivalent: "")
        item.tag = 1
        _ = popup?.perform(NSSelectorFromString("itemPicked:"), with: item)
    }
    let checkRow = section.flatMap { section in
        walk(section).compactMap { $0 as? InspectorRowView }.first { row in
            row.arrangedSubviews.contains { $0 is OptionCheckboxControl }
        }
    }
    let gutter = checkRow?.arrangedSubviews.first as? InspectorMarkGutter
    gutter?.refresh()
    let check = checkRow.flatMap { row in
        row.arrangedSubviews.lazy.compactMap { $0 as? OptionCheckboxControl }.first
    }
    sent = []
    applying = false
    check?.mouseDown(with: event)
    applying = true
    let op = sent.count == 1 && sent[0].ops.count == 1 ? parsed(sent[0].ops[0]) : [:]
    let base = op["op"] as? String == "set_video" && same(op["clips"], [NSNumber(value: clip)])
        && (op["patch"] as? [String: Any])?["cutout"] is NSNull
    if gutter?.mark != .notAnimatable {
        problems.append("the checkbox's gutter is \(String(describing: gutter?.mark))")
    }
    if !base { problems.append("the checkbox committed \(sent.map { $0.ops.map(\.json) })") }
    row("I3", problems.isEmpty, problems.isEmpty ? "ok" : problems.joined(separator: "; "))
} else {
    row("I3", false, "the fixture could not be made")
}

// ---- I5 -------------------------------------------------------------------------------------

if let (document, ids) = makeDocument(clips: 2) {
    var problems: [String] = []
    let clipMenu = NSApp.mainMenu?.items.first { $0.title == "Clip" }?.submenu
    let titles = clipMenu?.items.map(\.title) ?? []
    let look = titles.firstIndex(of: "Look")
    let remove = titles.firstIndex(of: "Remove Background")
    let item = remove.flatMap { clipMenu?.items[$0] }
    if look == nil || remove != look.map({ $0 + 1 }) || item?.keyEquivalent != ""
        || item?.action != #selector(EditorViewController.toggleRemoveBackground(_:))
    {
        problems.append("the Clip menu \(titles), key \(String(describing: item?.keyEquivalent))")
    }
    document.selection = Set(ids)
    let controller = EditorViewController(document: document)
    kept.append(controller)
    func state() -> String {
        let probe = NSMenuItem(
            title: "Remove Background",
            action: #selector(EditorViewController.toggleRemoveBackground(_:)),
            keyEquivalent: "")
        let enabled = controller.validateUserInterfaceItem(probe)
        let s = probe.state == .on ? "on" : probe.state == .mixed ? "mixed" : "off"
        return enabled ? s : "disabled \(s)"
    }
    let none = state()
    document.performGroupedEdit(
        "Cutout",
        [.setVideo(clips: [ids[0]], patch: VideoPatch(cutout: .some(CutoutProps(edge: 0.3))))])
    let some = state()
    let before = document.project.snapshot
    document.undoManager?.removeAllActions()
    controller.toggleRemoveBackground(nil)
    spin(0.2)
    let after = document.project.snapshot
    let all = state()
    let name = document.undoManager?.undoActionName ?? ""
    document.undoManager?.undo()
    spin(0.2)
    let undone = document.project.snapshot
    let canUndoMore = document.undoManager?.canUndo ?? true
    if [none, some, all] != ["off", "mixed", "on"] {
        problems.append("states none \(none), some \(some), all \(all)")
    }
    if after.clip(ids[0])?.video?.cutout != CutoutProps(edge: 0.3)
        || after.clip(ids[1])?.video?.cutout != CutoutProps()
    {
        problems.append(
            "after the toggle \(String(describing: after.clip(ids[0])?.video?.cutout)), "
                + "\(String(describing: after.clip(ids[1])?.video?.cutout))")
    }
    if name != "Remove Background" || undone.clip(ids[1])?.video?.cutout != nil
        || undone.clip(ids[0])?.video?.cutout != before.clip(ids[0])?.video?.cutout
        || canUndoMore
    {
        problems.append(
            "undo name \(name); after one undo \(String(describing: undone.clip(ids[1])?.video?.cutout)), "
                + "more to undo \(canUndoMore)")
    }
    row("I5", problems.isEmpty, problems.isEmpty ? "off → mixed → on, one step" : problems.joined(separator: "; "))
} else {
    row("I5", false, "the fixture could not be made")
}

// ---- I6p ------------------------------------------------------------------------------------

do {
    let url = work.appendingPathComponent("i6p.pack")
    func lzfse(_ bytes: [UInt8]) -> Data {
        ((try? (Data(bytes) as NSData).compressed(using: .lzfse)) as Data?) ?? Data()
    }
    let masks = [
        MaskPack.Analysed(pts: 0, compressed: lzfse([0, 255, 0, 0, 0, 0, 0, 255]), found: true),
        MaskPack.Analysed(pts: 20_000, compressed: lzfse([0, 0, 0, 0, 100, 0, 0, 0]), found: true),
        MaskPack.Analysed(
            pts: 40_000, compressed: lzfse([255, 255, 255, 255, 255, 255, 255, 255]),
            found: false),
    ]
    try? FileManager.default.removeItem(at: url)
    try MaskPack.write(
        onDisk: nil, partial: url, width: 4, height: 2,
        frames: [(0, 0, 0), (20_000, 1, 20_000), (40_000, 2, 40_000), (60_000, 3, 0)],
        masks: masks)
    let pack = try MaskPack(contentsOf: url)
    let mine = try probeCentroid(pack: pack, need: [0...2], coverage: [0...3], width: 8, height: 8)
    let app = try CutoutStatus.centroid(
        pack: pack, need: [0...2], coverage: [0...3], mediaWidth: 8, mediaHeight: 8)
    let ok = mine.map { abs($0.x - 3.0) < 1e-12 && abs($0.y - 5.0) < 1e-12 && $0.frames == 2 }
        == true && app.map { abs($0.x - 3.0) < 1e-9 && abs($0.y - 5.0) < 1e-9 } == true
    row("I6p", ok,
        "the probe's centroid \(String(describing: mine)) (want (3.0, 5.0) over 2 frames); "
            + "CutoutStatus.centroid \(String(describing: app))")
} catch {
    row("I6p", false, "the hand-made pack: \(error)")
}

// ---- I8 -------------------------------------------------------------------------------------

do {
    let a = CutoutStatus.progress(need: [0...999], covered: [0...399], running: [0...999], fraction: 0.4)
    let b = CutoutStatus.progress(
        need: [0...999], covered: [0...399], running: [200...999], fraction: 0.25)
    let c = CutoutStatus.progress(need: [0...999], covered: [0...399], running: nil, fraction: 0)
    let ok = [a, b, c].allSatisfy { abs($0 - 0.4) < 1e-9 }
    row("I8", ok, String(format: "running 0…999 at 0.4 → %.3f; running 200…999 at 0.25 → %.3f; "
        + "none → %.3f (each 0.400)", a, b, c))
}

// ---- I10 ------------------------------------------------------------------------------------

if let (document, _) = makeDocument(clips: 1), let media = document.project.snapshot.media.first {
    let url = work.appendingPathComponent("stamp.mov")
    let cacheDir = document.intendedCacheDirectory ?? work
    try? FileManager.default.removeItem(at: url)
    let absent = CutoutStatus.stamp(media: media, url: url, cacheDir: cacheDir, in: document)
    let wrote = (try? Data("co3 stamp".utf8).write(to: url)) != nil
    let present = CutoutStatus.stamp(media: media, url: url, cacheDir: cacheDir, in: document)
    row("I10", absent == nil && wrote && present != nil,
        "absent file: \(absent == nil ? "nil" : "a stamp") (want nil); written \(wrote); then "
            + "\(present == nil ? "nil" : "a stamp") (want a stamp)")
} else {
    row("I10", false, "the fixture could not be made")
}

// ---- I11 ------------------------------------------------------------------------------------

if let (document, _) = makeDocument(clips: 1), let (other, _) = makeDocument(clips: 1) {
    func detail(_ clip: UInt32, _ state: CutoutState) -> CutoutStatus.Detail {
        CutoutStatus.Detail(
            status: CutoutClipStatus(
                clip: clip, media: nil, state: state, frames: 1, covered: 0, subjectFound: false,
                error: nil),
            media: nil, need: [], coverage: [], pack: nil, owner: nil, cacheDir: nil)
    }
    let clips: [UInt32] = [1, 2, 3]
    let p = document.project, e = document.editedProject, p2 = other.project
    var reads: [UInt32] = []
    let read = { (clip: UInt32) -> CutoutStatus.Detail in
        reads.append(clip)
        return detail(clip, .analyzing(0.7))
    }
    let a = AgentServer.cutoutDetails(clips, kept: nil, project: p, edited: e, read: read)
    let readA = reads
    reads = []
    let held = AgentServer.CutoutPoll(
        details: [detail(1, .ready), detail(2, .analyzing(0.5)), detail(3, .failed("gone"))],
        project: p, edited: e)
    let b = AgentServer.cutoutDetails(clips, kept: held, project: p, edited: e, read: read)
    let readB = reads
    reads = []
    let c = AgentServer.cutoutDetails(clips, kept: held, project: p2, edited: e, read: read)
    let readC = reads
    let states = { (poll: AgentServer.CutoutPoll) in poll.details.map { "\($0.status.state)" } }
    let pass = readA == [1, 2, 3] && a.details.count == 3
        && readB == [2]
        && b.details.map(\.status) == [held.details[0].status, detail(2, .analyzing(0.7)).status,
                                       held.details[2].status]
        && readC == [1, 2, 3] && c.details.allSatisfy { $0.status.state == .analyzing(0.7) }
    row("I11", pass,
        "(a) nothing kept: read \(readA) (want [1, 2, 3]); (b) same handles: read \(readB) (want "
            + "[2]), states \(states(b)); (c) another project handle: read \(readC) (want [1, 2, 3]), "
            + "states \(states(c))")
} else {
    row("I11", false, "the fixture could not be made")
}

finish()
