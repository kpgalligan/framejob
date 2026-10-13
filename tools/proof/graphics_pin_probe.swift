// tools/proof/graphics_pin_probe.swift — the in-process instrument behind
// `graphics_proof.py`'s Q1–Q3 (road map 10 §10.6 G3c). Compiled with every
// file in `app/Sources` but `main.swift` over `harness/build.sh`'s swiftc
// line, copied in as `main.swift`, with the app's `Fonts`, `Blank.mp4` and a
// `default.metallib` of the app's own shader beside the binary.
//
//     graphics_pin_probe <package> <queue|direct|hit|warnqueue|warnsheet> <pin|nopin> <out.mov>
//
// It opens PQ as the app does (`read`, `fileURL`, `startGraphicStore()`,
// whose first scan and install are synchronous), and takes the document's
// compiled set when asked to pin. Then:
//
//   queue   `enqueue(prores_4444, graphics: set)` on its OWN
//           `ExportQueueController`;
//   direct  `Exporter().export(… graphics: set …)`;
//   hit     one `LayerRenderers` asked twice for the `nofont` graphic;
//   warnqueue  (Q4, over PW) `enqueue(prores_4444, graphics: set)` and the
//           finished job's `message` and `ExportQueueRowView.toolTip(for:)`;
//   warnsheet  (Q5, over PW) an `ExportProgressSheetController` with the
//           set, its view loaded and `viewDidAppear()` called, the run loop
//           spun until its private `didFinish`: the reflected `statusLabel`'s
//           string and toolTip.
//
// For `queue` and `direct` the document's canvas is then turned blue and its
// store STOPPED — the set it drew with is removed from the registry,
// synchronously, before the run loop has spun once and so before any frame
// of the export is drawn. The export must still draw `pin.js` from the set
// it was handed. The answer is one JSON object on stdout.
import AppKit
import Metal

let arguments = CommandLine.arguments
var answer: [String: Any] = [:]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

guard arguments.count == 5 else {
    answer["error"] = "usage: <package> <queue|direct|hit|warnqueue|warnsheet> <pin|nopin> <out.mov>"
    finish()
}
let packageURL = URL(fileURLWithPath: arguments[1])
let mode = arguments[2]
let pinned = arguments[3] == "pin"
let outURL = URL(fileURLWithPath: arguments[4])
answer["mode"] = mode
answer["pin"] = pinned

NSApplication.shared.setActivationPolicy(.prohibited)

/// The fonts beside the binary, as `harness/build.sh` puts them.
let binaryDirectory = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
    .standardizedFileURL
let fontsDirectory = binaryDirectory.appendingPathComponent("Fonts")
for name in (try? FileManager.default.contentsOfDirectory(atPath: fontsDirectory.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(
        fontsDirectory.appendingPathComponent(name) as CFURL, .process, nil)
}

/// Spins the main run loop until `done()` or the deadline: `Exporter`'s
/// progress timer and every completion arrive on it.
func spin(until done: () -> Bool, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return done()
}

let document = ProjectDocument()
do {
    try document.read(from: packageURL, ofType: ProjectDocument.projectTypeIdentifier)
} catch {
    answer["error"] = "the package would not open: \(error.localizedDescription)"
    finish()
}
document.fileURL = packageURL
document.startGraphicStore()
let set = pinned ? GraphicRegistry.shared.snapshot(for: document.recipeKey) : nil
answer["modules"] = GraphicRegistry.shared.snapshot(for: document.recipeKey)
    .map { Array($0.modules.keys).sorted() } ?? []
answer["setCaptured"] = set != nil

/// A private stored property, by reflection.
func reflected<T>(_ object: Any, _ name: String, as: T.Type) -> T? {
    Mirror(reflecting: object).children.first { $0.label == name }?.value as? T
}

/// The canvas turned blue and the document's set removed — both before the
/// run loop spins, so before any frame is drawn.
func swapOut() {
    document.applyEdit("Edit", .setCanvas(background: [0, 0, 1, 1]))
    document.stopGraphicStore()
    answer["setAfterStop"] = GraphicRegistry.shared.snapshot(for: document.recipeKey) != nil
}

switch mode {
case "queue", "direct":
    guard let settings = try? ReelExport.settings(document.project, preset: "prores_4444") else {
        answer["error"] = "the core would not resolve prores_4444"
        finish()
    }
    try? FileManager.default.removeItem(at: outURL)
    if mode == "queue" {
        let queue = ExportQueueController()
        let id = queue.enqueue(
            project: document.project, urls: document.mediaURLs(), settings: settings,
            to: outURL, graphics: set)
        swapOut()
        answer["settled"] = spin(until: { queue.isIdle }, timeout: 300)
        let job = queue.job(id)
        answer["state"] = job?.state.rawValue ?? "missing"
        answer["message"] = job?.message ?? ""
    } else {
        let exporter = Exporter()
        var outcome: Result<URL, any Error>?
        exporter.export(
            project: document.project, urls: document.mediaURLs(), settings: settings,
            to: outURL, graphics: set, progress: { _ in },
            completion: { outcome = $0 })
        swapOut()
        answer["settled"] = spin(until: { outcome != nil }, timeout: 300)
        switch outcome {
        case .success?: answer["state"] = "completed"
        case .failure(let error)?:
            answer["state"] = "failed"
            answer["message"] = error.localizedDescription
        case nil: answer["state"] = "unsettled"
        }
    }
    answer["exists"] = FileManager.default.fileExists(atPath: outURL.path)
case "warnqueue", "warnsheet":
    guard let settings = try? ReelExport.settings(document.project, preset: "prores_4444") else {
        answer["error"] = "the core would not resolve prores_4444"
        finish()
    }
    try? FileManager.default.removeItem(at: outURL)
    if mode == "warnqueue" {
        let queue = ExportQueueController()
        let id = queue.enqueue(
            project: document.project, urls: document.mediaURLs(), settings: settings,
            to: outURL, graphics: set)
        answer["settled"] = spin(until: { queue.isIdle }, timeout: 300)
        let job = queue.job(id)
        answer["state"] = job?.state.rawValue ?? "missing"
        answer["message"] = job?.message ?? ""
        answer["toolTip"] = job.map { ExportQueueRowView.toolTip(for: $0) } ?? ""
    } else {
        let sheet = ExportProgressSheetController(
            project: document.project, urls: document.mediaURLs(), settings: settings,
            to: outURL, graphics: set)
        _ = sheet.view
        sheet.viewDidAppear()
        func finished() -> Bool { reflected(sheet, "didFinish", as: Bool.self) == true }
        answer["finished"] = spin(until: finished, timeout: 300)
        let label = reflected(sheet, "statusLabel", as: NSTextField.self)
        answer["status"] = label?.stringValue ?? "no statusLabel"
        answer["toolTip"] = label?.toolTip ?? ""
    }
    document.stopGraphicStore()
case "hit":
    guard let device = MTLCreateSystemDefaultDevice() else {
        answer["error"] = "no Metal device"
        finish()
    }
    let renderers = LayerRenderers(device: device)
    func ask() -> LayerRenderers.Rendered? {
        renderers.graphic(
            name: "nofont", frame: 0, propsJSON: "{}", ctxJSON: "{}",
            size: CGSize(width: 1920, height: 1080), recipeKey: document.recipeKey)
    }
    let first = ask()
    let second = ask()
    answer["first"] = first?.warnings.map { $0.message } as Any
    answer["second"] = second?.warnings.map { $0.message } as Any
    answer["sameTexture"] = first != nil && second != nil && first?.texture === second?.texture
    document.stopGraphicStore()
default:
    answer["error"] = "unknown mode \(mode)"
}
finish()
