// Docs bugs c2: the presses and the full-length labels MCP cannot read (`snapshot_ui` cuts a label
// at 200 characters), on the real `TranscribeSheetController` and `FillerSheetController`, compiled
// from `app/Sources` through `swift_build.py` and run over real `.framejob` packages an app saved.
// Fake AssemblyAI on loopback, dummy key: nothing is paid for. No pasteboard, no real defaults
// (`ProbeDefaults`), no window on screen.
//
// It names only symbols present before the fix, and compares nothing itself, so it builds over the
// base's sources and `docs_bugs_c2_proof.py` scores the same rows on both.
//
//   probe captions <package> <fake base> <selected ids, comma separated, or -> [<start>,<end> ticks]
//     (the optional fifth argument is the In/Out range, set before the sheet is made)
//   probe fillers <package> <file to delete> <fake base>
//   probe lost <package> <file to delete> <fake base>
//   probe note <package> <fake base>
//
// Prints one JSON line. A beep is counted by `docs_bugs_c2_beep.c`, an interposer whose count this
// probe reads through dlsym; with no interposer it stops at once, so nothing ever sounds.

import AppKit
import Foundation

_ = NSApplication.shared

func emit(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
        let line = String(data: data, encoding: .utf8)
    else { exit(5) }
    print(line)
    fflush(stdout)
}

func spin(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

typealias Counter = @convention(c) () -> Int32
guard let counted = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "beep_count_read") else {
    emit(["error": "the beep interposer is not loaded"])
    exit(4)
}
let counter = unsafeBitCast(counted, to: Counter.self)
func beeps() -> Int { Int(counter()) }

final class ProbeDefaults: UserDefaults {
    var values: [String: Any] = [:]
    var arguments: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ?? false
    }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
    override func dictionaryRepresentation() -> [String: Any] { values }
    override func volatileDomain(forName domainName: String) -> [String: Any] {
        domainName == UserDefaults.argumentDomain ? arguments : [:]
    }
    override func synchronize() -> Bool { true }
}

final class StillAnimator: NSObject, NSViewControllerPresentationAnimator {
    func animatePresentation(of viewController: NSViewController, from: NSViewController) {}
    func animateDismissal(of viewController: NSViewController, from: NSViewController) {}
}

func open(_ path: String) -> ProjectDocument {
    let package = URL(fileURLWithPath: path)
    let document = ProjectDocument()
    do {
        try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = package
    } catch {
        emit(["error": "read failed: \(error)"])
        exit(1)
    }
    return document
}

func defaults(_ base: String, engine: String? = nil) -> ProbeDefaults {
    guard let made = ProbeDefaults(suiteName: nil) else { exit(3) }
    made.arguments = [AssemblyAIConfiguration.endpointArgument: base]
    if let engine { made.values["FrameJobCaptionEngine"] = engine }
    return made
}

let keyed = [AssemblyAIConfiguration.environmentKey: "proof-key"]

// MARK: - Generate Captions

func captionSheet(
    _ package: String, base: String, selection: Set<UInt32>, engine: String,
    range: (start: Ticks, end: Ticks)?
) -> [String: Any] {
    let document = open(package)
    document.selection = selection
    if let range { document.inOutRange = range }
    let sheet = TranscribeSheetController(
        document: document, store: MemoryStore(), defaults: defaults(base, engine: engine),
        environment: keyed,
        languages: [
            Transcriber.Language(
                identifier: "en-US", displayName: "English (United States)", installed: true)
        ])
    _ = sheet.view
    func ids(_ scope: TranscribeSheetController.Scope) -> [Int] {
        sheet.jobs(in: scope).map { Int($0.clip) }
    }
    return [
        "scope": "\(sheet.scope)", "selection": ids(.selection), "range": ids(.range),
        "all": ids(.all), "jobs": ids(sheet.scope), "summary": sheet.summaryLabel.stringValue,
        "note": sheet.noteLabel.stringValue,
    ]
}

// MARK: - Remove Filler Words

func fillerSheet(_ document: ProjectDocument, base: String) -> FillerSheetController {
    let input = FillerDetector.read(from: document, clips: nil)
    return FillerSheetController(
        document: document, timeline: nil, input: input, cacheDirectory: document.cacheDirectory,
        store: MemoryStore(), defaults: defaults(base), environment: keyed)
}

func orNull(_ value: Any?) -> Any { value ?? NSNull() }

func state(_ sheet: FillerSheetController) -> [String: Any] {
    [
        "rows": sheet.mediaRows.map { row -> [String: Any] in
            [
                "name": row.name.stringValue, "estimate": row.estimate.stringValue,
                "button": row.button.title, "enabled": row.button.isEnabled,
            ]
        },
        "running": orNull(sheet.runningMedia.map { Int($0) }),
        "last_error": orNull(sheet.lastError),
        "note": sheet.noteLabel.stringValue, "beeps": beeps(),
    ]
}

/// Every text field's whole value: the hint has no property of its own.
func fieldTexts(_ view: NSView) -> [String] {
    var out = (view as? NSTextField).map { [$0.stringValue] } ?? []
    for child in view.subviews { out += fieldTexts(child) }
    return out
}

func removeFile(_ path: String) {
    do {
        try FileManager.default.removeItem(atPath: path)
    } catch {
        emit(["error": "could not delete \(path): \(error)"])
        exit(6)
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    emit(["error": "usage"])
    exit(64)
}

// The interposer's control: it must count a direct beep, or a 0 below means nothing.
let before = beeps()
NSSound.beep()
let control = beeps() - before

switch arguments[1] {
case "captions":
    let selection = Set(arguments[4].split(separator: ",").compactMap { UInt32($0) })
    var range: (start: Ticks, end: Ticks)?
    if arguments.count > 5 {
        let ends = arguments[5].split(separator: ",").compactMap { Ticks($0) }
        guard ends.count == 2 else {
            emit(["error": "the range is <start>,<end> in ticks"])
            exit(64)
        }
        range = (start: ends[0], end: ends[1])
    }
    emit([
        "control": control,
        "apple": captionSheet(
            arguments[2], base: arguments[3], selection: selection, engine: "apple", range: range),
        "assemblyai": captionSheet(
            arguments[2], base: arguments[3], selection: selection, engine: "assemblyai",
            range: range),
    ])

case "fillers":
    let document = open(arguments[2])
    let lost = arguments[3]
    let name = URL(fileURLWithPath: lost).lastPathComponent
    let sheet = fillerSheet(document, base: arguments[4])
    let host = NSViewController()
    host.view = NSView()
    let animator = StillAnimator()
    _ = sheet.view
    host.present(sheet, animator: animator)
    spin(0.2)
    let opened = state(sheet)
    removeFile(lost)
    spin(0.5)
    sheet.refresh()
    let deleted = state(sheet)
    guard let target = sheet.mediaRows.first(where: { $0.name.stringValue == name }) else {
        emit(["error": "no row for \(name)", "opened": opened])
        exit(2)
    }
    target.button.performClick(nil)
    spin(0.5)
    let pressed = state(sheet)
    guard let other = sheet.mediaRows.first(where: { $0.name.stringValue != name }) else {
        emit(["error": "no other row", "pressed": pressed])
        exit(2)
    }
    other.button.performClick(nil)
    let began = Date()
    spin(0.3)
    while sheet.runningMedia != nil, Date().timeIntervalSince(began) < 60 { spin(0.1) }
    spin(0.5)
    let ended = state(sheet)
    let again = fillerSheet(document, base: arguments[4])
    _ = again.view
    emit([
        "control": control, "opened": opened, "deleted": deleted, "pressed": pressed,
        "ended": ended, "reopened": state(again),
    ])

case "lost":
    removeFile(arguments[3])
    let sheet = fillerSheet(open(arguments[2]), base: arguments[4])
    _ = sheet.view
    emit(["control": control, "sheet": state(sheet)])

case "note":
    let sheet = fillerSheet(open(arguments[2]), base: arguments[3])
    _ = sheet.view
    emit(["control": control, "sheet": state(sheet), "texts": fieldTexts(sheet.view)])

default:
    emit(["error": "usage"])
    exit(64)
}
exit(0)
