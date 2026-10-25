// #364 — the editor-side de-duplication's before/after instrument: the three
// modal canvas modes on one overlay base and one teardown, the added clips
// selected through one helper, and the export codec's LPCM question asked in
// one place. `editor_dedup_probe.py` builds it and scores what it answers.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`. One process:
//
//   editor_dedup_probe <package.framejob> <out dir>
//
// It writes V1's PNGs into `<out dir>` and prints one JSON object on stdout,
// `{"rows": [...]}`, each row `{"id", "pass", "detail", "record"}`. `pass` is
// the row's ABSOLUTE check; `record` is the text `compare` holds byte-equal to
// the capture. Every wait pumps `RunLoop.main` and is bounded.
//
// It names only what exists in BOTH trees (before and after the change):
// `chromaEyedropper`, `qualifierPick`, `canvasRegion`, `pickChromaKey(_:)`,
// `pickQualifier(_:)`, `armCanvasMode(_:)`, `endChromaEyedropper()`,
// `endQualifierPick()`, `endRegionMode()`, the three overlay types and their
// init signatures, `nestSelection()`, `unnestSelection()`,
// `insertAdjustmentClip(_:)`, `ExportSheetController.Applies`,
// `ExportWriter.audioSettings` and `ReelExport.presets/settings`. No general
// pasteboard, no menu item that persists a setting, no MCP.
//
// The prologue — `ProbeDocumentController`, `AppDelegate`, `spin`, `opened`
// and `editor` — is `e2_chrome.py`'s `PROBE_SOURCE`.
import AVFoundation
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let package = CommandLine.arguments[1]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func opened(_ path: String) -> ProjectDocument {
    let document = ProjectDocument()
    try! document.read(
        from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    return document
}

func ordered(_ document: ProjectDocument) -> [ClipSnapshot] {
    document.project.snapshot.clips.sorted { $0.start < $1.start }
}

func select(_ document: ProjectDocument, _ indices: [Int]) {
    let clips = ordered(document)
    document.selection = Set(indices.compactMap {
        clips.indices.contains($0) ? clips[$0].id : nil
    })
}

func editor(_ path: String, select indices: [Int], playhead: Ticks? = nil)
    -> (ProjectDocument, EditorViewController)
{
    let document = opened(path)
    select(document, indices)
    if let playhead { document.playhead = playhead }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.2)
    let controller =
        document.windowControllers.first!.contentViewController as! EditorViewController
    if let playhead { controller.setPlayhead(playhead) }
    controller.inspector?.selectClipSubTab(.clip)
    spin(0.3)
    return (document, controller)
}

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, record: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1800)),
                 "record": record])
}

func escape() -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false, keyCode: 53)!
}

func press() -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

// MARK: - V1 — the overlays' pixels

/// `view` drawn at `size` into a PNG, the appearance pinned to aqua; and
/// whether any pixel is not fully transparent.
func paint(_ view: NSView, _ size: NSSize) -> (Data?, Bool) {
    let aqua = NSAppearance(named: .aqua)!
    view.appearance = aqua
    view.frame = NSRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()
    var data: Data?
    var inked = false
    aqua.performAsCurrentDrawingAppearance {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        data = rep.representation(using: .png, properties: [:])
        outer: for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
                inked = true
                break outer
            }
        }
    }
    return (data, inked)
}

do {
    let views: [(String, () -> NSView)] = [
        ("eyedropper", {
            CanvasEyedropperView(session: CanvasEyedropperSession(clips: [2], base: nil))
        }),
        ("qualifier", { QualifierPickView(clips: [2], behind: 2) }),
        ("region-zoom", {
            CanvasRegionView(purpose: .zoom, clip: 2, note: CanvasRegionView.duringNote)
        }),
        ("region-obscure", { CanvasRegionView(purpose: .obscure, clip: 2) }),
    ]
    var files: [String] = []
    var problems: [String] = []
    for (name, make) in views {
        for (tag, size) in [("640x360", NSSize(width: 640, height: 360)),
                            ("160x90", NSSize(width: 160, height: 90))] {
            let file = "v1-\(name)-\(tag).png"
            let (data, inked) = paint(make(), size)
            guard let data else {
                problems.append("\(file): no PNG")
                continue
            }
            do {
                try data.write(to: out.appendingPathComponent(file))
            } catch {
                problems.append("\(file): \(error.localizedDescription)")
            }
            files.append(file)
            if tag == "640x360", !inked { problems.append("\(file): nothing drawn") }
        }
    }
    row("V1", problems.isEmpty,
        problems.isEmpty ? "\(files.count) PNGs written; each 640×360 one has ink"
            : problems.joined(separator: "; "),
        record: files.joined(separator: "\n"))
}

// MARK: - E1 — Esc on each overlay

do {
    var lines: [String] = []
    var good = true
    let eyedropper = CanvasEyedropperView(
        session: CanvasEyedropperSession(clips: [2], base: nil))
    let qualifier = QualifierPickView(clips: [2], behind: 2)
    for (name, view) in [("eyedropper", eyedropper as CanvasPickOverlay),
                         ("qualifier", qualifier as CanvasPickOverlay)] {
        var calls = 0
        view.onCancel = { calls += 1 }
        view.keyDown(with: escape())
        good = good && calls == 1
        lines.append("\(name): onCancel ran \(calls) time(s)")
    }
    let region = CanvasRegionView(purpose: .zoom, clip: 2)
    region.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
    region.canvasPoint = { _ in CGPoint(x: 100, y: 100) }
    var calls = 0
    var sessionAtCancel = "unread"
    region.onCancel = {
        calls += 1
        sessionAtCancel = region.session == nil ? "nil" : "live"
    }
    region.mouseDown(with: press())
    let pressed = region.session != nil
    region.keyDown(with: escape())
    good = good && pressed && calls == 1 && sessionAtCancel == "nil"
    lines.append(
        "region: session after the press \(pressed ? "live" : "nil"); onCancel ran \(calls) "
        + "time(s); the session when it ran: \(sessionAtCancel)")
    let text = lines.joined(separator: "\n")
    row("E1", good, text.replacingOccurrences(of: "\n", with: "; "), record: text)
}

// MARK: - The canvas modes in a window

/// Whether `held` is torn down: no superview, no callbacks.
func detached(_ held: CanvasPickOverlay?) -> Bool {
    guard let held else { return false }
    return held.superview == nil && held.onPick == nil && held.onCancel == nil
}

func modes(_ controller: EditorViewController) -> Int {
    controller.canvasContainer.subviews.filter { $0 is CanvasModalMode }.count
}

func focusOnOverlay(_ controller: EditorViewController) -> Bool {
    guard let overlay = controller.previewCanvas?.overlay else { return false }
    return controller.view.window?.firstResponder === overlay
}

/// C1's arm, miss and disarm against one pick mode: `toggle` arms and
/// disarms it, `armed` reads it.
func armMissDisarm(
    _ document: ProjectDocument, _ controller: EditorViewController, toggle: () -> Void,
    armed: () -> CanvasPickOverlay?
) -> (Bool, String) {
    var lines: [String] = []
    toggle()
    guard let picker = armed() else { return (false, "the mode did not arm") }
    let focused = controller.view.window?.firstResponder === picker
    lines.append("armed; first responder is the overlay: \(focused)")
    let before = document.project.json
    picker.onPick?(CGPoint(x: -5000, y: -5000))
    let stays = armed() === picker && picker.superview != nil
    let same = document.project.json == before
    lines.append("a pick in the void: still armed \(stays); project unchanged \(same)")
    toggle()
    let gone = armed() == nil
    let clean = detached(picker)
    let back = focusOnOverlay(controller)
    lines.append(
        "second press: disarmed \(gone); no superview and no callbacks \(clean); "
        + "focus on the canvas overlay \(back)")
    return (focused && stays && same && gone && clean && back, lines.joined(separator: "\n"))
}

do {
    let (document, controller) = editor(package, select: [0])
    let (c1, c1Text) = armMissDisarm(
        document, controller, toggle: { controller.pickChromaKey(nil) },
        armed: { controller.chromaEyedropper })
    row("C1", c1, c1Text.replacingOccurrences(of: "\n", with: "; "), record: c1Text)

    // C2 — arming a second mode ends the first.
    controller.pickChromaKey(nil)
    if let eyedropper = controller.chromaEyedropper {
        controller.armCanvasMode(QualifierPickView(clips: [], behind: 0))
        let one = modes(controller)
        let first = detached(eyedropper)
        let qualifierUp = controller.qualifierPick != nil
        controller.endQualifierPick()
        let none = modes(controller)
        let back = focusOnOverlay(controller)
        let text = [
            "after arming the qualifier over the eyedropper: \(one) mode(s); the qualifier's "
                + "up \(qualifierUp); the eyedropper torn down \(first)",
            "after endQualifierPick: \(none) mode(s); focus on the canvas overlay \(back)",
        ].joined(separator: "\n")
        row("C2", one == 1 && first && qualifierUp && none == 0 && back,
            text.replacingOccurrences(of: "\n", with: "; "), record: text)
    } else {
        row("C2", false, "the eyedropper did not arm", record: "unarmed")
    }
}

// MARK: - C3 — Pick from Canvas on a new adjustment clip

do {
    let (document, controller) = editor(package, select: [])
    let before = Set(document.project.snapshot.clips.map { $0.id })
    controller.insertAdjustmentClip(nil)
    spin(0.3)
    let added = document.project.snapshot.clips.filter { !before.contains($0.id) }
    let selected = added.count == 1 && document.selection == Set(added.map { $0.id })
    var lines = ["Insert ▸ Adjustment Clip: \(added.count) clip(s) added; it is the selection "
                 + "\(selected)"]
    let (picked, pickText) = armMissDisarm(
        document, controller, toggle: { controller.pickQualifier(nil) },
        armed: { controller.qualifierPick })
    lines.append(pickText)
    let text = lines.joined(separator: "\n")
    row("C3", selected && picked, text.replacingOccurrences(of: "\n", with: "; "), record: text)
}

// MARK: - N1 — Nest and Un-nest select what they added

do {
    let (document, controller) = editor(package, select: [0, 1])
    func ids() -> [UInt32] { document.project.snapshot.clips.map { $0.id }.sorted() }
    var lines: [String] = []
    var good = true

    let start = Set(ids())
    controller.nestSelection()
    let nested = ids().filter { !start.contains($0) }
    let nest = nested.first.flatMap { document.project.snapshot.clip($0) }
    let nestSelected = nested.count == 1 && document.selection == Set(nested)
        && nest?.source.nestID != nil
    good = good && nestSelected
    lines.append(
        "Nest: new \(nested), selection \(document.selection.sorted()), nest id set "
        + "\(nest?.source.nestID != nil)")

    let lone = document.selection
    let loneText = document.project.json
    controller.nestSelection()
    let kept = document.selection == lone && document.project.json == loneText
    good = good && kept
    lines.append("Nest on the lone nest: selection \(document.selection.sorted()), kept \(kept)")

    let mid = Set(ids())
    controller.unnestSelection()
    let opened = ids().filter { !mid.contains($0) }
    let openSelected = opened.count == 2 && document.selection == Set(opened)
    good = good && openSelected
    lines.append("Un-nest: new \(opened), selection \(document.selection.sorted())")
    let text = lines.joined(separator: "\n")
    row("N1", good, text.replacingOccurrences(of: "\n", with: "; "), record: text)
}

// MARK: - X1 — the export rows' LPCM question

func flat(_ dictionary: [String: Any]) -> String {
    dictionary.keys.sorted().map { "\($0)=\(dictionary[$0]!)" }.joined(separator: " ")
}

func expectsPCM(_ codec: String) -> Bool {
    let c = codec.lowercased()
    return c == "lpcm" || c.hasPrefix("prores")
}

do {
    var lines: [String] = []
    var wrong: [String] = []
    let presets = ReelExport.presets()
    let offered: [ExportPreset?] = [nil] + presets
    for preset in offered {
        let applies = ExportSheetController.Applies(preset)
        lines.append(
            "applies \(preset?.id ?? "nil"): videoBitrate=\(applies.videoBitrate) "
            + "audioBitrate=\(applies.audioBitrate)")
    }
    let project = opened(package).project
    func audit(_ name: String, _ settings: ExportSettings) {
        let audio = ExportWriter.audioSettings(settings)
        lines.append("audio \(name): \(flat(audio))")
        let pcm = (audio[AVFormatIDKey] as? Int) == Int(kAudioFormatLinearPCM)
        if pcm != expectsPCM(settings.codec) {
            wrong.append("\(name) (codec \(settings.codec)) LPCM \(pcm)")
        }
    }
    for preset in presets {
        do {
            audit(preset.id, try ReelExport.settings(project, preset: preset.id))
        } catch {
            lines.append("audio \(preset.id): refused — \(error.localizedDescription)")
        }
    }
    for codec in ["ProRes_HQ", "LPCM", "", "H264"] {
        for container in ["mov", "aiff"] {
            let json = "{\"codec\": \"\(codec)\", \"container\": \"\(container)\"}"
            guard let settings = ReelJSON.decode(ExportSettings.self, from: json) else {
                lines.append("decoded \(codec)/\(container): not decoded")
                wrong.append("\(codec)/\(container) not decoded")
                continue
            }
            audit("decoded \(codec)/\(container)", settings)
        }
    }
    row("X1", !presets.isEmpty && wrong.isEmpty,
        presets.isEmpty ? "the core listed no presets"
            : wrong.isEmpty ? "\(presets.count) presets and 8 decoded settings; LPCM exactly "
                + "where the codec is lpcm or ProRes"
            : "LPCM misplaced: " + wrong.joined(separator: "; "),
        record: lines.joined(separator: "\n"))
}

let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(data)
exit(0)
