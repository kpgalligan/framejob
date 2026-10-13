// Issue batch B57 (#210) — which `beginSheetModal(for:)` sites can be asked
// for while another sheet is attached to the editor window, and whether the
// document's alert queue keeps their order, driven through the app's own
// `EditorViewController` and `ProjectDocument`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` — the swiftc
// line `relink_sheet_probe.py` uses. One process:
//
//   sheet_queue_probe <request.json>
//
// The request names `work` (this run's directory). The answer is one JSON
// object on stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail",
// "instrument"}`; `sheet_queue_probe.py` prints and scores them. Every wait
// pumps `RunLoop.main` and is bounded.
//
// The fixture: an untitled `ProjectDocument` and its `EditorViewController`
// as the content of a 1440×900 window (`graphics_menu_probe.swift`'s
// set-up), owned by an `NSWindowController` added to the document, so
// `windowForSheet` is that window. No media from `tools/proof/media`: the
// probe writes its own garbage `.png` and a valid 4×4 PNG. E1 and E2 are
// `present(_:)` of "probe alert one" and "probe alert two". An attached
// sheet is ended with `endSheet` 0.3 s after it attaches unless a row says
// it is held.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: sheet_queue_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath, isDirectory: true)
let files = FileManager.default
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
try? files.createDirectory(at: work, withIntermediateDirectories: true)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, instrument: Bool = false) {
    rows.append(["id": id, "pass": pass && !instrument, "detail": String(detail.prefix(1500)),
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

/// Pumps until `condition` holds or `limit` seconds pass; the seconds it
/// took, or nil.
func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return Date().timeIntervalSince(start) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition() ? Date().timeIntervalSince(start) : nil
}

func pause(_ limit: Double) { _ = waitUntil(limit) { false } }

func seconds(_ value: Double?) -> String { value.map { String(format: "%.2f s", $0) } ?? "never" }

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

/// Every text field's string in a sheet's view tree.
func texts(_ sheet: NSWindow) -> [String] {
    (sheet.contentView.map(walk) ?? []).compactMap { ($0 as? NSTextField)?.stringValue }
        .filter { !$0.isEmpty }
}

func holds(_ shown: [String]?, _ text: String?) -> Bool {
    guard let shown, let text else { return false }
    return shown.contains(text)
}

func probeError(_ text: String) -> NSError {
    NSError(domain: "SheetQueueProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}

// MARK: - The fixture

let garbage = work.appendingPathComponent("garbage.png")
try? Data("not a picture".utf8).write(to: garbage)
let valid = work.appendingPathComponent("valid.png")
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
try? rep?.representation(using: .png, properties: [:])?.write(to: valid)

// Each row gets a fixture of its own, so a queue a mutant jams in one row
// cannot keep the next row's E1 from attaching.
var doc: ProjectDocument!
var controller: EditorViewController!
var window: NSWindow!
var windowControllers: [NSWindowController] = []
func fresh() {
    window?.orderOut(nil)
    doc = ProjectDocument()
    documents.append(doc)
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
    windowController.showWindow(nil)
    pause(0.3)
}

/// A newly attached sheet that is none of `besides` and not in `seen`,
/// within `limit` s.
func newSheet(_ limit: Double, after seen: [NSWindow], besides: [NSWindow?] = []) -> NSWindow? {
    var found: NSWindow?
    _ = waitUntil(limit) {
        if let attached = window.attachedSheet,
            !besides.contains(where: { $0 === attached }),
            !seen.contains(where: { $0 === attached }) {
            found = attached
        }
        return found != nil
    }
    return found
}

/// Ends `sheet` and returns its texts.
func end(_ sheet: NSWindow) -> [String] {
    let shown = texts(sheet)
    window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
    return shown
}

/// Every sheet that attaches from now on, in order, each ended 0.3 s after
/// it attaches; stops when none attaches within `limit` s of the last.
func collect(after seen: [NSWindow], besides: [NSWindow?] = [], limit: Double = 2)
    -> [[String]]
{
    var seen = seen
    var shown: [[String]] = []
    while seen.count < 12, let next = newSheet(limit, after: seen, besides: besides) {
        seen.append(next)
        pause(0.3)
        shown.append(end(next))
    }
    return shown
}

/// No sheet attached, the queue drained: up to 3 s, ending whatever stays.
func settle() {
    for _ in 0..<4 {
        if waitUntil(3, { window.attachedSheet == nil }) != nil { break }
        if let stuck = window.attachedSheet { window.endSheet(stuck, returnCode: .cancel) }
    }
    pause(0.3)
}

func describe(_ order: [[String]]) -> String {
    "[" + order.map { "[" + $0.joined(separator: " | ") + "]" }.joined(separator: ", ") + "]"
}

// MARK: - C0 — CONTROL: the window is the document's, and actions validate

func validates(_ name: String) -> Bool {
    controller.validateUserInterfaceItem(
        NSMenuItem(title: "x", action: NSSelectorFromString(name), keyEquivalent: ""))
}
fresh()
let c0Window = doc.windowForSheet === window
let c0Clear = window.attachedSheet == nil
let c0Add = validates("addMediaFiles:")
row("C0", c0Window && c0Clear && c0Add,
    "windowForSheet is the window: \(c0Window); no sheet attached: \(c0Clear); "
    + "addMediaFiles: validates \(c0Add)")

// MARK: - V1 — with E1 attached, every editor door to a site validates false

let actions = ["exportCaptions:", "importCaptions:", "addImageBackground:", "addMediaFiles:",
               "consolidateMedia:", "insertGraphicFromFile:", "addGraphicFont:",
               "addGraphicImage:", "insertGraphicTemplate:", "setTransitionKind:", "saveFrame:",
               "removeTrack:"]
fresh()
doc.present(probeError("probe alert one"))
if let e1 = newSheet(5, after: []) {
    let live = actions.filter(validates)
    row("V1", live.isEmpty,
        "E1 attached (\(texts(e1).joined(separator: " | "))); validating true: "
        + (live.isEmpty ? "none" : live.joined(separator: " ")))
    _ = end(e1)
} else {
    row("V1", false, "instrument: E1 did not attach within 5 s", instrument: true)
}
settle()

// MARK: - P1, P2 — a panel's completion asks for an alert while E1 waits

func panelRow(_ id: String, _ panel: NSSavePanel) {
    fresh()
    var atHandler: String?
    panel.beginSheetModal(for: window) { _ in
        atHandler = window.attachedSheet.map { holds(texts($0), "probe alert one") ? "E1" : "a sheet" }
            ?? "nothing"
        let alert = NSAlert()
        alert.messageText = "probe handler"
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
    guard waitUntil(3, { window.attachedSheet != nil }) != nil, let up = window.attachedSheet else {
        row(id, false, "instrument: panel did not attach within 3 s", instrument: true)
        window.endSheet(panel, returnCode: .cancel)
        settle()
        return
    }
    doc.present(probeError("probe alert one"))
    pause(0.5)
    let e1Early = window.attachedSheet !== up
    window.endSheet(up, returnCode: .cancel)
    let order = collect(after: [up], limit: 3)
    let pass = !e1Early && atHandler != nil && atHandler != "E1" && order.count == 2
        && holds(order.first, "probe handler") && holds(order.last, "probe alert one")
    row(id, pass,
        "panel attached (the panel itself: \(up === panel)); E1 attached over it: \(e1Early); "
        + "at the handler attached: \(atHandler ?? "<handler never ran>"); sheets after the "
        + "panel \(order.count): \(describe(order)); expected [probe handler], [probe alert one]")
    settle()
}
panelRow("P1", NSOpenPanel())
panelRow("P2", NSSavePanel())

// MARK: - X1 — ExportSheet:582's shape: a panel over an outgoing sheet

fresh()
let bare = NSViewController()
bare.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
controller.presentAsSheet(bare)
controller.dismiss(bare)
let savePanel = NSSavePanel()
savePanel.beginSheetModal(for: window) { _ in }
doc.present(probeError("probe alert one"))
if waitUntil(3, { window.attachedSheet === savePanel }) == nil {
    row("X1", false, "instrument: panel did not attach within 3 s", instrument: true)
    window.endSheet(savePanel, returnCode: .cancel)
} else {
    var e1Over = false
    _ = waitUntil(1) {
        if let attached = window.attachedSheet, attached !== savePanel { e1Over = true }
        return false
    }
    window.endSheet(savePanel, returnCode: .cancel)
    let order = collect(after: [savePanel], besides: [bare.view.window])
    row("X1", !e1Over && order.count == 1 && holds(order.first, "probe alert one"),
        "a sheet other than the panel attached while it was up: \(e1Over); sheets after the "
        + "panel \(order.count): \(describe(order)); expected [probe alert one]")
}
settle()

// MARK: - S1–S4 — a site asked for while E1 is attached

/// On a fresh fixture `expect` answers the site's text, E1 attaches, `site`
/// runs, E1 is held `hold` s, E2 is presented and E1 is ended: [E1], [the
/// site's text], [E2], none more within 2 s.
func siteRow(
    _ id: String, hold: Double, expect: () -> String?, _ site: () -> Void
) {
    fresh()
    let expected = expect()
    doc.present(probeError("probe alert one"))
    guard let e1 = newSheet(5, after: []) else {
        row(id, false, "instrument: E1 did not attach within 5 s", instrument: true)
        settle()
        return
    }
    site()
    pause(hold)
    doc.present(probeError("probe alert two"))
    let first = end(e1)
    let order = [first] + collect(after: [e1])
    let pass = order.count == 3 && holds(order[0], "probe alert one")
        && holds(order[1], expected) && holds(order[2], "probe alert two")
    row(id, pass,
        "sheets \(order.count): \(describe(order)); expected [probe alert one], "
        + "[\(expected ?? "<no expected text>")], [probe alert two]")
    settle()
}

siteRow("S1", hold: 1, expect: { "probe frame" }) {
    controller.frameSaved(.failure(probeError("probe frame")), in: window)
}

var garbageText: String?
do { _ = try MediaImporter.probeBlocking(url: garbage) } catch {
    garbageText = error.localizedDescription
}
siteRow("S2", hold: 2, expect: { garbageText }) {
    controller.addImageBackground(from: garbage, into: doc, in: window)
}

var wide: MediaDescriptor?
if var d = try? MediaImporter.probeBlocking(url: valid) {
    d.width = 70000
    wide = d
}
if let wide {
    let wideText = {
        do { _ = try doc.project.applying(.addMedia(descriptor: wide)) } catch {
            return error.localizedDescription as String?
        }
        return nil
    }
    siteRow("S3", hold: 1, expect: wideText) {
        controller.placeImageBackground(wide, into: doc, in: window)
    }
} else {
    row("S3", false, "instrument: the 4×4 PNG did not probe", instrument: true)
}

// The row's own document is given a file URL (no media) before the call.
func planText() -> String? {
    doc.fileURL = work.appendingPathComponent("probe.framejob", isDirectory: true)
    do { _ = try MediaConsolidator.plan(for: doc) } catch { return error.localizedDescription }
    return nil
}
siteRow("S4", hold: 1, expect: planText) {
    controller.consolidateAfterSave(doc, didSave: true, contextInfo: nil)
}

finish()
