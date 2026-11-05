// Docs bugs b3: what the sheet's buttons do and what `Exporter.export` does on its own, through the
// app's own sources on real `.framejob` packages an app saved. Compiled AS main.swift over every
// file of app/Sources but the app's main.swift, through swift_build.py, by `docs_bugs_b3_proof.py`.
//
//   docs-bugs-b3-probe <long.framejob> <short.framejob> <scratch folder>
//
// A card: a real `ExportSheetController` on the document's editor, its view loaded and never shown,
//   `apply` then `resolveCard`, the path a remembered choice takes. Export… is never pressed.
// A direct export: `Exporter().export` over a file, with settings the door would now refuse. That is
//   what the writers' own checks are kept for, and it must leave the file.
//
// Nothing reaches the screen or takes focus: activation policy .prohibited, a window 20,000 pt off
// every display, held there by constrainFrameRect (docs_bugs_a1_probe.swift's pattern).
//
// It names only symbols present before the fix, and compares nothing itself, so it builds over the
// base's sources and `docs_bugs_b3_proof.py` scores the same rows on both. One JSON line a row.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DecoderSupport.enable()

let longPackage = URL(fileURLWithPath: CommandLine.arguments[1])
let shortPackage = URL(fileURLWithPath: CommandLine.arguments[2])
let scratch = URL(fileURLWithPath: CommandLine.arguments[3])
let realGeneralCount = NSPasteboard.general.changeCount

func say(_ row: String, _ fields: [String: Any]) {
    var line = fields
    line["row"] = row
    let data = try! JSONSerialization.data(
        withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

final class OffWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct Open {
    let doc: ProjectDocument
    let controller: EditorViewController
    let window: NSWindow
    let keep: NSWindowController
}

/// Each open reads its OWN copy of the package: a document with a fileURL autosaves in place.
var opened = 0

func open(_ package: URL) -> Open {
    opened += 1
    let copy = scratch.appendingPathComponent("open\(opened)-\(package.lastPathComponent)")
    try? FileManager.default.removeItem(at: copy)
    try! FileManager.default.copyItem(at: package, to: copy)
    let doc = ProjectDocument()
    do {
        try doc.read(from: copy, ofType: ProjectDocument.projectTypeIdentifier)
        doc.fileURL = copy
    } catch {
        say("abort", ["read": "\(error)"])
        exit(2)
    }
    doc.startGraphicStore()
    let controller = EditorViewController(document: doc)
    let window = OffWindow(
        contentRect: NSRect(x: -20000, y: -20000, width: 1440, height: 900),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    window.setFrame(NSRect(x: -20000, y: -20000, width: 1440, height: 900), display: false)
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    let keep = NSWindowController(window: window)
    doc.addWindowController(keep)
    window.orderBack(nil)
    for _ in 0..<12 {
        spin(0.05)
        controller.view.layoutSubtreeIfNeeded()
    }
    return Open(doc: doc, controller: controller, window: window, keep: keep)
}

func close(_ o: Open) {
    o.window.orderOut(nil)
    o.doc.removeWindowController(o.keep)
}

// MARK: - The rows

func card(_ o: Open, _ name: String, preset: String, fps: [Int]? = nil, custom: [Int]? = nil)
    -> [String: Any]
{
    let sheet = ExportSheetController(editor: o.controller)
    _ = sheet.view
    var choice = ExportChoice(presetID: preset)
    choice.fps = fps
    choice.customSize = custom
    sheet.apply(choice)
    sheet.resolveCard()
    return [
        "name": name, "export": sheet.exportButton?.isEnabled ?? false,
        "queue": sheet.queueButton?.isEnabled ?? false, "summary": sheet.summaryLabel.stringValue,
    ]
}

func direct(_ o: Open, _ name: String, preset: String, overrides: [String: Any]?) -> [String: Any] {
    let folder = scratch.appendingPathComponent("direct-\(name)")
    try? FileManager.default.removeItem(at: folder)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let target = folder.appendingPathComponent("old.bin")
    let bytes = Data("the file the person already had, \(name)\n".utf8)
    try! bytes.write(to: target)
    guard let settings = try? ReelExport.settings(o.doc.project, preset: preset, overrides: overrides)
    else { return ["name": name, "error": "the core refused \(preset)"] }
    let exporter = Exporter()
    var outcome: Result<URL, any Error>?
    exporter.export(
        project: o.doc.project, urls: o.doc.mediaURLs(), settings: settings, to: target,
        progress: { _ in }, completion: { outcome = $0 })
    let finished = waitUntil(120) { outcome != nil }
    var sentence = ""
    if case .failure(let error)? = outcome { sentence = error.localizedDescription }
    return [
        "name": name, "finished": finished, "failed": sentence,
        "same": (try? Data(contentsOf: target)) == bytes,
        "listing": ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted(),
    ]
}

let long = open(longPackage)
let short = open(shortPackage)
say("B1", [
    "off": [
        card(long, "gif", preset: "gif"),
        card(long, "gif at 24", preset: "gif", fps: [24, 1]),
        card(long, "hevc_alpha", preset: "hevc_alpha", custom: [1000, 1000]),
    ],
    "on": [
        card(short, "gif", preset: "gif"),
        card(short, "hevc_alpha", preset: "hevc_alpha", custom: [960, 540]),
    ],
])
say("B2", [
    "exports": [
        direct(long, "gif", preset: "gif", overrides: nil),
        direct(long, "alpha", preset: "hevc_alpha", overrides: ["width": 1000, "height": 1000]),
    ]
])
close(long)
close(short)
say("PB", ["unchanged": NSPasteboard.general.changeCount == realGeneralCount])
exit(0)
