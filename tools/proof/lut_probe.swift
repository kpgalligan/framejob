// Road map "grading", phase GR6a — the LUT probe (`lut_proof.py` builds it
// through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libframejob_core.a`, so every row drives the app's own
// types: `EditorViewController.payloadMediaIDs`, `LutTextures` (and through it
// `MediaImporter.readLUT` and the core's parser) and `RecipeSource`. Nothing
// private is widened.
//
//   lut_probe <request.json> <answer.json>
//
// `request.json` names `folder`, a scratch folder the probe writes its `.cube`
// files into. One JSON object out: `rows`, each a name, ok and detail.
//
// GR6b adds P4–P7, over the chrome: `LookGallery`'s LUT answers, Clip ▸ Look ▸'s
// `LookMenuFiller` and its validation, the Look section's Imported tiles and
// Import LUT… in a headless `ClipPane`, and `importLUT(from:into:clips:)`.
// The request then also names `package` (project LG0, saved over MCP: CHART on
// track 1 with {warm, 0.5}) and `lut` (a script-written `.cube`). The app is
// bootstrapped as `look_probe.swift` does; no window is built.
import Accelerate
import AppKit
import AVFoundation
import Metal

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let folder = URL(fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory())

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
}

// MARK: - P2 the payload's media ids

do {
    let clip: [String: Any] = [
        "id": 10, "source": ["kind": "media", "media": 1, "in": 0],
        "video": ["look": ["kind": "lut", "media": 5, "amount": 1]],
        "actions": [
            ["id": 20, "end": ["video": ["look": ["media": 6]]]],
            ["id": 21, "end": ["video": ["opacity": 0.5]]],
            ["id": 22, "end": ["video": ["look": ["media": 5, "amount": 0.5]]]],
        ],
    ]
    let text: [String: Any] = [
        "id": 11, "source": ["kind": "text"], "video": ["look": ["kind": "lut", "media": 7]],
    ]
    let plain: [String: Any] = ["id": 12, "source": ["kind": "media", "media": 2, "in": 0]]
    let ids = EditorViewController.payloadMediaIDs(clip)
    let textIDs = EditorViewController.payloadMediaIDs(text)
    let plainIDs = EditorViewController.payloadMediaIDs(plain)
    check(
        "P2 payloadMediaIDs: the source, the base look, then each end's look, without repeats",
        ids == [1, 5, 6] && textIDs == [7] && plainIDs == [2],
        "clip \(ids); text \(textIDs); plain \(plainIDs)")
}

// MARK: - T1, T2 the LUT textures

/// A size-2 table whose row k is (k/8, k mod 3 / 4, 1 − k/8), with row 0's
/// green −0.5 and row 7's red 1.5 (clamped to 0 and 1 when uploaded).
func asymmetric() -> (text: String, want: [[Float]]) {
    var lines = ["TITLE \"probe\"", "LUT_3D_SIZE 2"]
    var want: [[Float]] = []
    for k in 0..<8 {
        var red = Float(k) / 8
        var green = Float(k % 3) / 4
        let blue = 1 - Float(k) / 8
        var written = (red, green, blue)
        if k == 0 { written.1 = -0.5; green = 0 }
        if k == 7 { written.0 = 1.5; red = 1 }
        lines.append("\(written.0) \(written.1) \(written.2)")
        want.append([red, green, blue, 1])
    }
    return (lines.joined(separator: "\n") + "\n", want)
}

/// The texture's texels as floats, in texel order (x fastest, then y, then z).
func texels(_ texture: MTLTexture, device: MTLDevice) -> [Float]? {
    let n = texture.width
    let count = n * n * n * 4
    guard let queue = device.makeCommandQueue(), let buffer = queue.makeCommandBuffer() else {
        return nil
    }
    if texture.storageMode == .managed, let blit = buffer.makeBlitCommandEncoder() {
        blit.synchronize(resource: texture)
        blit.endEncoding()
    }
    buffer.commit()
    buffer.waitUntilCompleted()
    var halves = [UInt16](repeating: 0, count: count)
    halves.withUnsafeMutableBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        texture.getBytes(
            base, bytesPerRow: n * 8, bytesPerImage: n * n * 8,
            from: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0)
    }
    var floats = [Float](repeating: 0, count: count)
    let ok: Bool = halves.withUnsafeMutableBytes { source in
        floats.withUnsafeMutableBytes { target in
            guard let from = source.baseAddress, let to = target.baseAddress else { return false }
            var src = vImage_Buffer(
                data: from, height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
            var dst = vImage_Buffer(
                data: to, height: 1, width: vImagePixelCount(count), rowBytes: count * 4)
            return vImageConvert_Planar16FtoPlanarF(&src, &dst, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        }
    }
    return ok ? floats : nil
}

func cubeText(size: Int) -> String {
    var lines = ["LUT_3D_SIZE \(size)"]
    for b in 0..<size {
        for g in 0..<size {
            for r in 0..<size {
                let step = Float(size - 1)
                lines.append("\(Float(r) / step) \(Float(g) / step) \(Float(b) / step)")
            }
        }
    }
    return lines.joined(separator: "\n") + "\n"
}

if let device = MTLCreateSystemDefaultDevice() {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let luts = LutTextures(device: device)
    let (text, want) = asymmetric()
    let file = folder.appendingPathComponent("asymmetric.cube")
    try? text.write(to: file, atomically: true, encoding: .utf8)
    let texture = luts.texture(at: file)
    let read = texture.flatMap { texels($0, device: device) }
    var misses: [String] = []
    if let read = read {
        for b in 0..<2 {
            for g in 0..<2 {
                for r in 0..<2 {
                    let k = r + 2 * g + 4 * b
                    let got = Array(read[(k * 4)..<(k * 4 + 4)])
                    if got != want[k] { misses.append("(\(r),\(g),\(b)) \(got) want \(want[k])") }
                }
            }
        }
    }
    check(
        "T1 a size-2 asymmetric file uploads as a 2³ rgba16Float texture, texel (r, g, b) the "
            + "file's row r + 2g + 4b (red fastest), clamped to 0–1, alpha 1",
        texture?.width == 2 && texture?.depth == 2 && texture?.pixelFormat == .rgba16Float
            && read != nil && misses.isEmpty,
        "texture \(texture.map { "\($0.width)³ \($0.pixelFormat.rawValue)" } ?? "nil"); "
            + "misses \(misses.prefix(3))")

    let missing = folder.appendingPathComponent("absent.cube")
    let refused = folder.appendingPathComponent("refused.cube")
    try? "LUT_3D_SIZE 1\n0 0 0\n".write(to: refused, atomically: true, encoding: .utf8)
    let first = luts.texture(at: refused)
    let again = luts.texture(at: refused)
    let absent = luts.texture(at: missing)
    // The same name rewritten readable is a new key (its size and date moved).
    try? cubeText(size: 2).write(to: refused, atomically: true, encoding: .utf8)
    let fixed = luts.texture(at: refused)
    check(
        "T2 a missing file and a refused one answer nil (the refusal twice, cached), and the "
            + "refused file rewritten readable answers a texture",
        first == nil && again == nil && absent == nil && fixed != nil,
        "refused \(first == nil)/\(again == nil); missing \(absent == nil); rewritten "
            + "\(fixed != nil)")
} else {
    check("T1 a Metal device", false, "MTLCreateSystemDefaultDevice() is nil")
    check("T2 a Metal device", false, "MTLCreateSystemDefaultDevice() is nil")
}

// MARK: - P3 the look URLs

do {
    let source = RecipeSource.shared
    let published = source.register()
    let unpublished = source.register()
    let a = URL(fileURLWithPath: "/probe/a.cube")
    let b = URL(fileURLWithPath: "/probe/b.cube")
    func instruction(_ key: Int, _ urls: [UInt32: URL]) -> RecipeInstruction {
        RecipeInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)),
            requiredTrackIDs: [], recipeKey: key, mediaURLs: urls, sourceOrientations: [:],
            missingClips: [])
    }
    let built = instruction(published, [:])
    let before = source.lookURLs(for: built)
    source.setMediaURLs([3: a], for: published)
    let after = source.lookURLs(for: built)
    let fallback = source.lookURLs(for: instruction(unpublished, [4: b]))
    let none = source.lookURLs(for: nil)
    source.unregister(published)
    let dropped = source.lookURLs(for: built)
    source.unregister(unpublished)
    check(
        "P3 lookURLs(for:) answers the map published under the instruction's key after the "
            + "instruction was built with none, the instruction's own map for a key that never "
            + "published, [:] for nil, and the instruction's again once the key is unregistered",
        before.isEmpty && after == [3: a] && fallback == [4: b] && none.isEmpty
            && dropped.isEmpty,
        "before \(before); after \(after); fallback \(fallback); nil \(none); dropped \(dropped)")
}

// MARK: - GR6b: the chrome (P4–P7)

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

func spin(_ seconds: Double, until done: () -> Bool = { false }) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline, !done() {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}
func parsed(_ op: ReelOp) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
}
func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
func lgOpened() -> ProjectDocument? {
    guard let path = request["package"] as? String else { return nil }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        return nil
    }
    return document
}
func lookOf(_ document: ProjectDocument, _ clip: UInt32) -> LookProps? {
    document.project.snapshot.clips.first { $0.id == clip }?.videoProps.look
}
func edit(_ document: ProjectDocument, _ name: String, _ ops: [ReelOp]) {
    document.applyEdit(name, ops)
    spin(0.05)
}
let builtInNames = LookKind.builtIns.map(\.displayName)

/// LG0 opened, with pA and pB added as `lut` media from probe-written files,
/// a second CHART clip C2 1 s after C1 with {warm, 1}, and a text clip TX on a
/// new front track: (document, C1, C2, TX, A, B). C1 keeps LG0's {warm, 0.5}.
func lgWithLUTs() -> (ProjectDocument, UInt32, UInt32, UInt32, UInt32, UInt32)? {
    guard let document = lgOpened(), let first = document.project.snapshot.clips.first,
          let track = document.project.snapshot.tracks.first?.id,
          let chart = document.project.snapshot.media.first(where: { $0.kind == .image })?.id
    else { return nil }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var ids: [UInt32] = []
    for name in ["pA", "pB"] {
        let url = folder.appendingPathComponent("\(name).cube")
        try? cubeText(size: 2).write(to: url, atomically: true, encoding: .utf8)
        guard let descriptor = try? MediaImporter.probeLUT(url) else { return nil }
        edit(document, "Add Media", [.addMedia(descriptor: descriptor)])
        guard let id = document.project.snapshot.media.last?.id else { return nil }
        ids.append(id)
    }
    let c1 = first.id
    let before = Set(document.project.snapshot.clips.map(\.id))
    edit(document, "Add Clip", [.addClip(track: track, media: chart, at: first.end + 600_000)])
    guard let c2 = document.project.snapshot.clips.first(where: { !before.contains($0.id) })?.id
    else { return nil }
    edit(document, "Look", [LookGallery.op(.warm, clips: [c2])])
    edit(document, "Add Track", [.addTrack(index: 1)])
    guard let front = document.project.snapshot.tracks.last?.id else { return nil }
    let had = Set(document.project.snapshot.clips.map(\.id))
    edit(document, "Add Text", [.addTextClip(track: front, at: first.end + 600_000)])
    guard let tx = document.project.snapshot.clips.first(where: { !had.contains($0.id) })?.id,
          ids.count == 2
    else { return nil }
    return (document, c1, c2, tx, ids[0], ids[1])
}

// P4 the pure answers
do {
    let snapshot = ProjectSnapshot(media: [
        MediaSnapshot(id: 3, path: "/p/z.cube", kind: .lut, hasVideo: false),
        MediaSnapshot(id: 1, path: "/p/v.mov", kind: .video),
        MediaSnapshot(id: 2, path: "/p/a.cube", kind: .lut, hasVideo: false),
        MediaSnapshot(id: 4, path: "/p/i.png", kind: .image),
    ])
    let order = LookGallery.luts(in: snapshot).map(\.id)
    let names = ["/p/Film.CUBE", "/p/a.b.cube", "/p/plain"].map {
        LookGallery.lutName(MediaSnapshot(id: 9, path: $0, kind: .lut, hasVideo: false))
    }
    let lut8 = LookProps(kind: .lut, amount: 0.8, media: 3)
    let summaries = [
        LookGallery.summary([lut8, lut8], names: [3: "Film"]),
        LookGallery.summary([lut8], names: [:]),
        LookGallery.summary([lut8, LookProps(kind: .lut, amount: 0.8, media: 2)], names: [3: "Film"]),
        LookGallery.summary([LookProps(kind: .warm, amount: 0.8)], names: [3: "Film"]),
    ]
    let op = parsed(LookGallery.op(lut: 5, clips: [7]))
    let wantPatch: NSDictionary = ["look": ["kind": "lut", "media": 5]]
    check(
        "P4 luts keeps the media list's order and only lut rows; lutName \"Film.CUBE\" → Film, "
            + "\"a.b.cube\" → a.b, \"plain\" kept; summary \"Film 80%\", \"LUT 80%\" for an "
            + "unknown id, \"mixed\" by LUT, \"Warm 80%\"; op(lut:) is {kind: lut, media} with "
            + "no amount",
        order == [3, 2] && names == ["Film", "a.b", "plain"]
            && summaries == ["Film 80%", "LUT 80%", "mixed", "Warm 80%"]
            && op["op"] as? String == "set_video"
            && (op["clips"] as? [NSNumber])?.map(\.uint32Value) == [7]
            && (op["patch"] as? NSDictionary) == wantPatch,
        "order \(order); names \(names); summaries \(summaries); op \(op)")
}

// P5 Clip ▸ Look ▸'s LUT rows
if let (document, c1, c2, _, a, b) = lgWithLUTs() {
    let menu = delegate.lookMenu()
    LookMenuFiller.fill(menu, luts: LookGallery.luts(in: document.project.snapshot))
    let titles = menu.items.map { $0.isSeparatorItem ? "" : $0.title }
    let entries = menu.items.filter { !$0.isSeparatorItem }
    let tags = entries.map(\.tag)
    let carried = entries.map { ($0.representedObject as? NSNumber)?.uint32Value }
    let actions = Set(entries.compactMap { $0.action.map(NSStringFromSelector) })
    let filled = titles == builtInNames + ["", "pA", "pB", "", "None"]
        && tags == Array(0..<8) + [-2, -2, -1]
        && carried == Array(repeating: nil, count: 8) + [a, b, nil] && actions == ["setLook:"]
    let lutA = entries.first { $0.title == "pA" }
    let lutB = entries.first { $0.title == "pB" }
    let refill = delegate.lookMenu()
    LookMenuFiller.fill(refill, luts: LookGallery.luts(in: document.project.snapshot))
    LookMenuFiller.fill(refill, luts: [])
    let emptied = refill.items.map { $0.isSeparatorItem ? "" : $0.title }
    // Validation: C1 at A, C2 at warm.
    edit(document, "Look", [LookGallery.op(lut: a, clips: [c1])])
    var states: [String] = []
    for selection in [[c1], [c1, c2], [c2]] {
        document.selection = Set(selection)
        let controller = EditorViewController(document: document)
        for item in [lutA, lutB].compactMap({ $0 }) {
            let on = controller.validateUserInterfaceItem(item)
            let state = item.state == .on ? "on" : (item.state == .mixed ? "mixed" : "off")
            states.append("\(item.title) \(state)\(on ? "" : " disabled")")
        }
    }
    let wantStates = ["pA on", "pB off", "pA mixed", "pB off", "pA off", "pB off"]
    // setLook: with B's item, then a −2 item with no id.
    document.selection = [c1]
    let controller = EditorViewController(document: document)
    if let lutB { controller.setLook(lutB) }
    spin(0.05)
    let afterB = lookOf(document, c1)
    let name = document.undoManager?.undoActionName ?? ""
    document.undoManager?.undo()
    spin(0.05)
    let undone = lookOf(document, c1)
    let stray = NSMenuItem(
        title: "x", action: #selector(EditorViewController.setLook(_:)), keyEquivalent: "")
    stray.tag = EditorViewController.lookLUTTag
    let beforeStray = document.project
    controller.setLook(stray)
    let strayKept = document.project === beforeStray
    check(
        "P5 fill: the eight, \"\", pA, pB, \"\", None (tags 0…7, −2, −2, −1; ids A, B); a refill "
            + "with none: the eight, \"\", None; a LUT item is on, mixed or off over the targets; "
            + "setLook: with B's item writes {lut, B} as one step \"Look\"; a −2 item with no id "
            + "writes nothing",
        filled && emptied == builtInNames + ["", "None"] && states == wantStates
            && afterB == LookProps(kind: .lut, amount: 0.5, media: b) && name == "Look"
            && undone == LookProps(kind: .lut, amount: 0.5, media: a) && strayKept,
        "titles \(titles); tags \(tags); ids \(carried); refill \(emptied); states \(states); "
            + "B \(String(describing: afterB)) '\(name)' → undo \(String(describing: undone)); "
            + "stray kept \(strayKept)")
} else {
    check("P5 the request's LG0 opens and takes pA and pB", false, "\(request)")
}

// P6 the Look section's Imported tiles and Import LUT…
if let (document, c1, _, tx, a, b) = lgWithLUTs() {
    let inspector = InspectorViewController()
    var sent: [(String, [ReelOp])] = []
    inspector.document = document
    inspector.onEdit = { name, ops in
        sent.append((name, ops))
        document.applyEdit(name, ops)
    }
    func pane(_ selection: [UInt32]) -> ClipPane {
        document.selection = Set(selection)
        inspector.binding.invalidate()
        let pane = ClipPane(inspector: inspector)
        pane.binding.invalidate()
        pane.choose(.color)
        pane.rebuild()
        pane.refresh()
        return pane
    }
    func gallery(_ pane: ClipPane) -> LookGalleryView? {
        pane.sections.first { $0.id == "video.look" }.flatMap { section in
            walk(section).lazy.compactMap { $0 as? LookGalleryView }.first
        }
    }
    func summary(_ pane: ClipPane) -> String? {
        guard let section = pane.sections.first(where: { $0.id == "video.look" }) else {
            return nil
        }
        return Mirror(reflecting: section.header).children
            .first { $0.label == "lastSummary" }?.value as? String
    }
    edit(document, "Look", [LookGallery.op(lut: a, clips: [c1])])
    let looked = pane([c1])
    let view = gallery(looked)
    let titles = view?.lutTiles.map { $0.accessibilityLabel() ?? "?" } ?? []
    let outlined = ((view?.tiles ?? []) + (view?.lutTiles ?? [])).filter(\.isOutlined)
        .map { $0.accessibilityLabel() ?? "?" }
    let enabled = view?.importButton.isEnabled ?? false
    sent = []
    if let tile = view?.lutTiles.first(where: { $0.media == b }) {
        tile.sendAction(tile.action, to: tile.target)
    }
    let op = sent.first.flatMap { $0.1.count == 1 ? parsed($0.1[0]) : nil } ?? [:]
    let wantPatch: NSDictionary = ["look": ["kind": "lut", "media": b]]
    let picked = sent.count == 1 && sent.first?.0 == "Look"
        && op["op"] as? String == "set_video"
        && (op["clips"] as? [NSNumber])?.map(\.uint32Value) == [c1]
        && (op["patch"] as? NSDictionary) == wantPatch
        && lookOf(document, c1) == LookProps(kind: .lut, amount: 0.5, media: b)
    edit(document, "Look", [.setVideo(
        clips: [c1], patch: VideoPatch(look: .some(LookPatch(kind: .lut, amount: 0.8, media: a))))])
    let said = summary(pane([c1]))
    // TX alone: no Color sub-tab, so the view is built over its binding.
    document.selection = [tx]
    let binding = InspectorBinding(inspector: inspector)
    binding.invalidate()
    let bare = LookGalleryView(
        gallery: LookGallery(), binding: binding, onPick: { _ in }, onPickLUT: { _ in },
        onImport: {})
    bare.refresh()
    let textOff = !bare.importButton.isEnabled
    check(
        "P6 the pane's lutTiles read pA, pB; only pA's tile is outlined when the clip's own look "
            + "is A; the pB tile sends one set_video {look: {kind: lut, media: B}} named \"Look\"; "
            + "the summary at {lut, A, 0.8} is \"pA 80%\"; Import LUT… on with a target, off with "
            + "TX alone",
        titles == ["pA", "pB"] && outlined == ["pA"] && picked && said == "pA 80%" && enabled
            && textOff,
        "titles \(titles); outlined \(outlined); sent \(sent.map { ($0.0, $0.1.map(\.json)) }); "
            + "summary \(said ?? "nil"); import on \(enabled), TX off \(textOff)")
} else {
    check("P6 the request's LG0 opens and takes pA and pB", false, "\(request)")
}

// P7 importLUT(from:into:clips:)
if let document = lgOpened(), let clip = document.project.snapshot.clips.first?.id,
   let path = request["lut"] as? String
{
    let url = URL(fileURLWithPath: path)
    let controller = EditorViewController(document: document)
    let warm = LookProps(kind: .warm, amount: 0.5)
    let rows0 = document.project.snapshot.media.count
    var steps: [String] = []
    // (i)
    controller.importLUT(from: url, into: document, clips: [clip])
    spin(15) { document.project.snapshot.media.count != rows0 }
    spin(0.05)
    let added = document.project.snapshot.media.last
    let id = added?.kind == .lut ? added?.id : nil
    let first = document.project.snapshot.media.count == rows0 + 1 && id != nil
        && lookOf(document, clip) == LookProps(kind: .lut, amount: 0.5, media: id)
        && document.undoManager?.undoActionName == "Import LUT"
    steps.append("i rows \(document.project.snapshot.media.count - rows0) look "
        + "\(String(describing: lookOf(document, clip))) undo "
        + "'\(document.undoManager?.undoActionName ?? "")'")
    // (ii)
    document.undoManager?.undo()
    spin(0.05)
    let second = document.project.snapshot.media.count == rows0 && lookOf(document, clip) == warm
    steps.append("ii rows \(document.project.snapshot.media.count - rows0) look "
        + "\(String(describing: lookOf(document, clip)))")
    // (iii)
    document.undoManager?.redo()
    spin(0.05)
    edit(document, "Look", [LookGallery.op(.warm, clips: [clip])])
    let rows3 = document.project.snapshot.media.count
    let third = rows3 == rows0 + 1 && lookOf(document, clip) == warm
    steps.append("iii rows \(rows3 - rows0) look \(String(describing: lookOf(document, clip)))")
    // (iv)
    controller.importLUT(from: url, into: document, clips: [clip])
    spin(10) { lookOf(document, clip) != warm }
    spin(0.05)
    let fourth = document.project.snapshot.media.count == rows3
        && lookOf(document, clip) == LookProps(kind: .lut, amount: 0.5, media: id)
        && document.undoManager?.undoActionName == "Import LUT"
    steps.append("iv rows \(document.project.snapshot.media.count - rows0) look "
        + "\(String(describing: lookOf(document, clip))) undo "
        + "'\(document.undoManager?.undoActionName ?? "")'")
    check(
        "P7 importLUT: (i) one step \"Import LUT\" appends one lut row L and sets {lut, L, 0.5}; "
            + "(ii) one undo removes both; (iii) redo, then {warm} keeps the row; (iv) a second "
            + "import reuses L: rows unchanged, {lut, L, 0.5}, \"Import LUT\"",
        first && second && third && fourth, steps.joined(separator: "; "))
} else {
    check("P7 the request names LG0 and a .cube file", false, "\(request)")
}

finish()
