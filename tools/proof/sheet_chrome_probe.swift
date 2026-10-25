// #359 — the six progress sheets' chrome, built from `Sheets.swift`'s shared
// pieces, paints and lays out exactly as the hand-typed chrome it replaced.
// `sheet_chrome_probe.py` builds this file over a baseline tree and over the
// working tree and compares the two builds' captures.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, through
// `swift_build.build(defines=["FRAMEJOB_DEV_TOOLS"])` (it asks `UISnapshot` and
// `UISnapshotLayout`). Everything it calls exists in the baseline tree too.
//
//   sheet_chrome_probe <light|dark> <out dir>
//
// `NSApp.appearance` is set before any view is built. Each sheet's view is
// loaded and NEVER presented, so no `viewDidAppear` starts a job: Export
// (`prores_4444` over a one-clip project), Reverse (one job), Consolidate (an
// empty plan), Transcribe after `showProgress()`, AudioSync (an empty input)
// and Rewrap (its own panel's content view). Each view but Rewrap's is the
// content view of an offscreen borderless window, sized to fit; each is
// captured with `UISnapshot.pass` into `<out dir>/<sheet>-<look>.png` and
// `UISnapshotLayout.report(root:skipping: nil)` into
// `<out dir>/<sheet>-<look>.json`. `<out dir>/answer-<look>.json` lists the
// sheets captured and any that were not, with why.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: sheet_chrome_probe <light|dark> <out dir>\n".utf8))
    exit(2)
}
let look = arguments[1]
let outDir = URL(fileURLWithPath: arguments[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)

var captured: [String] = []
var failed: [String: String] = [:]
var documents: [ProjectDocument] = []
var windows: [NSWindow] = []

func finish() -> Never {
    for document in documents { document.removeTemporaryCacheDirectory() }
    let answer: [String: Any] = ["captured": captured, "failed": failed]
    if let data = try? JSONSerialization.data(
        withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
    {
        try? data.write(to: outDir.appendingPathComponent("answer-\(look).json"))
    }
    exit(0)
}

/// Captures `root` as `<name>-<look>.png` and `.json`.
func capture(_ name: String, _ root: NSView) {
    guard let pass = UISnapshot.pass(root),
        let png = pass.rep.representation(using: .png, properties: [:])
    else {
        failed[name] = "UISnapshot.pass gave no picture"
        return
    }
    let report = UISnapshotLayout.report(root: root, skipping: nil)
    guard JSONSerialization.isValidJSONObject(report),
        let json = try? JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    else {
        failed[name] = "the layout report is not JSON"
        return
    }
    do {
        try png.write(to: outDir.appendingPathComponent("\(name)-\(look).png"))
        try json.write(to: outDir.appendingPathComponent("\(name)-\(look).json"))
        captured.append(name)
    } catch {
        failed[name] = "write: \(error.localizedDescription)"
    }
}

/// A loaded sheet's view, in an offscreen borderless window sized to fit,
/// never ordered in.
func host(_ name: String, _ controller: NSViewController) {
    let view = controller.view
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless],
        backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    window.setContentSize(view.fittingSize)
    windows.append(window)
    capture(name, view)
}

// MARK: - The fixture

let work = outDir.appendingPathComponent("fixture-\(look)", isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let mediaURL = work.appendingPathComponent("alpha.mov")
try? Data("sheet chrome probe".utf8).write(to: mediaURL)
let second: Ticks = 600_000

let document = ProjectDocument()
documents.append(document)
if let track = document.project.snapshot.tracks.first?.id {
    document.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
        path: mediaURL.path, kind: .video, duration: 10 * second, width: 1920, height: 1080,
        fps: .thirty, hasVideo: true, hasAudio: true))])
    if let media = document.project.snapshot.media.first?.id {
        document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: 0)])
    }
}

// MARK: - The six sheets

if let settings = try? ReelExport.settings(document.project, preset: "prores_4444") {
    host("export", ExportProgressSheetController(
        project: document.project, urls: document.mediaURLs(), settings: settings,
        to: work.appendingPathComponent("Alpha Export.mov")))
} else {
    failed["export"] = "the core would not resolve prores_4444"
}

let job = ReverseRenderer.Job(
    media: 1, name: "Alpha", source: mediaURL,
    destination: work.appendingPathComponent("alpha-reversed.mov"), duration: 10 * second,
    fps: .thirty, hasAudio: true)
host("reverse", ReverseProgressSheetController(document: document, jobs: [job]))

let plan = MediaConsolidator.Plan(
    directory: work.appendingPathComponent("media", isDirectory: true), copies: [],
    relinks: [], aliases: [], missing: [], bytes: 0)
host("consolidate", ConsolidateProgressSheetController(document: document, plan: plan))

let transcribe = TranscribeSheetController(
    document: document, store: MemoryStore("proof-key"), defaults: ProbeDefaults(),
    environment: [:],
    languages: [Transcriber.Language(identifier: "en-US", displayName: "English (United States)")])
_ = transcribe.view
transcribe.showProgress()
host("transcribe", transcribe)

let input = AudioSync.Input(readings: [], problems: [], anchor: nil, fps: .thirty)
host("audiosync", AudioSyncSheetController(input: input, finished: { _ in }))

let rewrap = RewrapProgressWindowController(
    progress: RewrapProgress(source: work.appendingPathComponent("Alpha.webm")))
if let root = rewrap.window?.contentView {
    capture("rewrap", root)
} else {
    failed["rewrap"] = "the panel has no content view"
}

finish()

// MARK: - Defaults that never reach disk

/// Keyed reads and writes over a dictionary; nothing reaches a real domain.
final class ProbeDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() { super.init(suiteName: nil)! }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func array(forKey defaultName: String) -> [Any]? { values[defaultName] as? [Any] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        values[defaultName] as? [String: Any]
    }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func stringArray(forKey defaultName: String) -> [String]? {
        values[defaultName] as? [String]
    }
    override func url(forKey defaultName: String) -> URL? { values[defaultName] as? URL }
    override func integer(forKey defaultName: String) -> Int {
        (values[defaultName] as? NSNumber)?.intValue ?? 0
    }
    override func double(forKey defaultName: String) -> Double {
        (values[defaultName] as? NSNumber)?.doubleValue ?? 0
    }
    override func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ?? false
    }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Double, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
    override func dictionaryRepresentation() -> [String: Any] { values }
    override func synchronize() -> Bool { true }
}
