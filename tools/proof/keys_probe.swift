// Road map "creator-jobs" CJ1 (spec §11 CJ-10…CJ-13): the probe rows of
// `keys_proof.py`, compiled as `main.swift` over `app/Sources` (or a mutant's
// copy of it) through `swift_build.build()` with `FRAMEJOB_DEV_TOOLS`, and run
// as `keys-probe <speech.mov> -RCSecretFolder <scratch>` under
// `env -u RC_ASSEMBLYAI_KEY -u ANTHROPIC_API_KEY`: the default store is a
// FileStore on that empty scratch folder, so no row opens the person's key,
// and a "key" is the dummy `proof-key` written into it. No network: no row
// presses Transcribe or Generate. Every sheet gets a `MemoryDefaults`, a
// `MemoryStore` and an explicit environment. It prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`, on stdout.

import AppKit
import Foundation

_ = NSApplication.shared
NSApp.appearance = NSAppearance(named: .aqua)

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

func spin(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// `filler_sheet_probe.swift`'s `MemoryDefaults`, restated: keyed calls from
/// memory, the argument domain empty, every domain write a trap.
final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ?? false
    }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
    override func dictionaryRepresentation() -> [String: Any] { values }
    override func volatileDomain(forName domainName: String) -> [String: Any] { [:] }
    override func register(defaults registrationDictionary: [String: Any]) { trap() }
    override func persistentDomain(forName domainName: String) -> [String: Any]? { trap() }
    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        trap()
    }
    override func removePersistentDomain(forName domainName: String) { trap() }
    override func synchronize() -> Bool { trap() }
    private func trap(_ function: String = #function) -> Never {
        fatalError("MemoryDefaults: \(function) would reach the real defaults domain")
    }
}

let sentence = ModelKeys.sentence(.assemblyAI)
let suffix = ModelKey.assemblyAI.titleSuffix

guard CommandLine.arguments.count > 1,
    FileManager.default.fileExists(atPath: CommandLine.arguments[1])
else {
    row("K3", false, "media/speech.mov is missing (the probe's first argument)")
    finish()
}
guard
    let folderText = AssemblyAIConfiguration.argument(
        AssemblyAIConfiguration.secretFolderArgument, defaults: .standard)
else {
    row("K3", false, "the probe was not launched with -RCSecretFolder")
    finish()
}
let secrets = URL(fileURLWithPath: folderText, isDirectory: true)
/// The default store's file: what "a key saved in Settings" is to this run.
let saved = FileStore(directory: secrets)
try? saved.remove()

let speech = URL(fileURLWithPath: CommandLine.arguments[1])
guard let probed = try? MediaImporter.probeBlocking(url: speech) else {
    row("K3", false, "speech.mov did not probe")
    finish()
}

/// A document holding speech.mov and one clip of the whole of it at 0.
func fixture() -> (document: ProjectDocument, media: UInt32)? {
    let document = ProjectDocument()
    guard let track = document.project.snapshot.tracks.first?.id else { return nil }
    document.performGroupedEdit("Media", [.addMedia(descriptor: probed)])
    guard let media = document.project.snapshot.media.first?.id else { return nil }
    document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: 0)])
    spin(0.1)
    document.undoManager?.removeAllActions()
    return (document, media)
}

/// A cache file of one word, requested with `options`.
func file(_ options: TranscriptOptions) -> MediaTranscript.File {
    let words = #"[{"text":"Hello","start":0,"end":1000,"confidence":0.9,"speaker":null}]"#
    let header = MediaTranscript.Header(
        provider: MediaTranscript.provider, transcriptID: "t_keys", requested: options,
        speechModelUsed: "universal-3-5-pro", languageCode: "en", languageConfidence: nil,
        audioDuration: 6, extractedSeconds: 5.2, uploadedFormat: "flac",
        audioTrackStartMs: 0, fetchedAt: "2026-11-01T00:00:00Z", remoteDeleted: true)
    return try! MediaTranscript.File(header: header, wordsJSON: Data(words.utf8))
}

/// Writes a transcript and its marker for `media`, requested with `options`.
func seed(_ document: ProjectDocument, _ media: UInt32, _ options: TranscriptOptions) -> Bool {
    guard let cache = document.cacheDirectory,
        let record = document.project.snapshot.media(media),
        let source = MediaImporter.CacheStamp.stamp(for: record, url: speech)
    else { return false }
    return MediaTranscript.write(file(options), for: media, in: cache)
        && MediaTranscript.writeStamp(
            TranscriptStamp(source: source, options: options), for: media, in: cache)
}

func find(_ action: Selector, in menu: NSMenu?) -> NSMenuItem? {
    for item in menu?.items ?? [] {
        if item.action == action { return item }
        if let found = find(action, in: item.submenu) { return found }
    }
    return nil
}

func describe(_ item: NSMenuItem?) -> String {
    "\"\(item?.title ?? "<none>")\" tooltip \(item?.toolTip.map { "\"\($0)\"" } ?? "nil")"
}

var keptAlive: [AnyObject] = []

guard let one = fixture() else {
    row("K3", false, "the fixture did not build")
    finish()
}
let controller = EditorViewController(document: one.document)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)
spin(0.3)
keptAlive.append(contentsOf: [controller, window, one.document])

// MARK: - K3: each keyed menu item, keyless then keyed

do {
    let built = AppDelegate().buildMainMenu()
    var parts: [String] = []
    var ok = true
    let menuRows = ModelKeys.keyed.filter { $0.menuAction != nil }
    if menuRows.isEmpty { ok = false; parts.append("no keyed row has a menu action") }
    for keyed in menuRows {
        guard let action = keyed.menuAction, let item = find(action, in: built) else {
            ok = false
            parts.append("\(keyed.name): no item in the main menu")
            continue
        }
        let base = item.title
        try? saved.remove()
        let off = controller.validateUserInterfaceItem(item)
        let offTitle = item.title
        let offTip = item.toolTip
        try? saved.write("proof-key")
        let on = controller.validateUserInterfaceItem(item)
        let good = !off && offTip == ModelKeys.sentence(keyed.key)
            && offTitle == base + keyed.key.titleSuffix
            && on && item.toolTip == nil && item.title == base
        ok = ok && good
        parts.append(
            "\(keyed.name): keyless \(off ? "on" : "off") \"\(offTitle)\" tooltip "
                + "\(offTip.map { "\"\($0)\"" } ?? "nil"); keyed \(on ? "on" : "off") "
                + describe(item))
    }
    try? saved.remove()
    row("K3", ok, parts.joined(separator: "; "))
}

// MARK: - K3b: a saved key resets the main menu's mark with no validation

do {
    NSApp.mainMenu = AppDelegate().buildMainMenu()
    let action = #selector(EditorViewController.removeFillerWords(_:))
    if let item = find(action, in: NSApp.mainMenu) {
        let base = item.title
        try? saved.remove()
        let off = controller.validateUserInterfaceItem(item)
        let marked = describe(item)
        let markedOK = !off && item.title == base + suffix && item.toolTip == sentence
        try? saved.write("proof-key")
        NotificationCenter.default.post(
            name: SettingsWindowController.didChangeNotification, object: nil)
        let reset = describe(item)
        let resetOK = item.title == base && item.toolTip == nil
        try? saved.remove()
        NotificationCenter.default.post(
            name: SettingsWindowController.didChangeNotification, object: nil)
        let after = describe(item)
        let afterOK = item.title == base && item.toolTip == nil
        row("K3b", markedOK && resetOK && afterOK,
            "keyless validation \(off ? "on" : "off") \(marked); key written and Settings' "
                + "notification posted, no validation: \(reset); key removed and posted "
                + "again: \(after)")
    } else {
        row("K3b", false, "Remove Filler Words… is not in the main menu")
    }
}

// MARK: - K4: presence follows the store with no notification

do {
    let folder = secrets.appendingPathComponent("k4", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = FileStore(directory: folder)
    try? store.remove()
    let before = ModelKeys.present(.assemblyAI, store: store, environment: [:])
    try? store.write("proof-key")
    let written = ModelKeys.present(.assemblyAI, store: store, environment: [:])
    try? store.remove()
    let removed = ModelKeys.present(.assemblyAI, store: store, environment: [:])
    let byEnvironment = ModelKeys.present(
        .assemblyAI, store: store,
        environment: [AssemblyAIConfiguration.environmentKey: "proof-key"])
    row("K4", !before && written && !removed && byEnvironment,
        "present: empty \(before), written \(written), removed \(removed), the variable "
            + "alone \(byEnvironment)")
}

// MARK: - K4b: both sheets follow a key saved while they are open

var changes: [String] = []
let watcher = NotificationCenter.default.addObserver(
    forName: ModelKeys.didChangeNotification, object: nil, queue: nil
) { note in
    changes.append(note.userInfo?[ModelKeys.keyInfoKey] as? String ?? "<none>")
}
keptAlive.append(watcher as AnyObject)

func cloudSheet(
    _ document: ProjectDocument, store: any SecretStore, defaults: UserDefaults
) -> TranscribeSheetController {
    let sheet = TranscribeSheetController(
        document: document, store: store, defaults: defaults, environment: [:], languages: [])
    _ = sheet.view
    if let index = sheet.enginePopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == TranscriptionEngine.assemblyai.rawValue
    }) {
        sheet.enginePopup.selectItem(at: index)
    }
    sheet.perform(NSSelectorFromString("engineChanged:"), with: nil)
    return sheet
}

if let four = fixture() {
    let fillerStore = MemoryStore()
    let captionStore = MemoryStore()
    let filler = FillerSheetController(
        document: four.document, timeline: TimelineView(),
        input: FillerDetector.read(from: four.document, clips: nil),
        cacheDirectory: four.document.cacheDirectory, store: fillerStore,
        defaults: MemoryDefaults(), environment: [:])
    _ = filler.view
    let captions = cloudSheet(four.document, store: captionStore, defaults: MemoryDefaults())
    keptAlive.append(contentsOf: [filler, captions, four.document])
    let rowButton = filler.mediaRows.first?.button
    let before = "Transcribe \(rowButton?.isEnabled ?? true) "
        + "\(rowButton?.toolTip.map { "\"\($0)\"" } ?? "nil"), Start "
        + "\(captions.startButton.isEnabled) "
        + "\(captions.startButton.toolTip.map { "\"\($0)\"" } ?? "nil")"
    let beforeOK = rowButton?.isEnabled == false && rowButton?.toolTip == sentence
        && !captions.startButton.isEnabled && captions.startButton.toolTip == sentence
    try? fillerStore.write("proof-key")
    try? captionStore.write("proof-key")
    changes = []
    NotificationCenter.default.post(name: SettingsWindowController.didChangeNotification, object: nil)
    let afterButton = filler.mediaRows.first?.button
    let after = "Transcribe \(afterButton?.isEnabled ?? false) "
        + "\(afterButton?.toolTip.map { "\"\($0)\"" } ?? "nil"), Start "
        + "\(captions.startButton.isEnabled) "
        + "\(captions.startButton.toolTip.map { "\"\($0)\"" } ?? "nil")"
    let afterOK = afterButton?.isEnabled == true && afterButton?.toolTip == nil
        && captions.startButton.isEnabled && captions.startButton.toolTip == nil
    let settingsChanges = changes
    changes = []
    NotificationCenter.default.post(name: AssistantConfiguration.didChangeNotification, object: nil)
    let assistantChanges = changes
    row("K4b",
        beforeOK && afterOK && settingsChanges == ["assemblyAI"]
            && assistantChanges == ["anthropic"],
        "rows \(filler.mediaRows.count); keyless: \(before); key written and Settings' "
            + "notification posted: \(after); ModelKeys posts for Settings' "
            + "\(settingsChanges), for the assistant's \(assistantChanges)")
} else {
    row("K4b", false, "the fixture did not build")
}

// MARK: - K5p: a filler transcript turns the item on, on the same handle

do {
    let action = #selector(EditorViewController.removeFillerWords(_:))
    let item = NSMenuItem(title: "Remove Filler Words…", action: action, keyEquivalent: "")
    try? saved.remove()
    let handle = one.document.editedProject
    let off = controller.validateUserInterfaceItem(item)
    let offText = describe(item)
    let seeded = seed(one.document, one.media, TranscriptOptions(
        speechModels: TranscriptOptions.shippedModels, languageCode: nil,
        speakerLabels: false, keytermsPrompt: [], disfluencies: true))
    let on = controller.validateUserInterfaceItem(item)
    let same = one.document.editedProject === handle
    row("K5p", !off && seeded && on && same && item.toolTip == nil,
        "keyless, no filler transcript: \(off ? "on" : "off") \(offText); seeded \(seeded); "
            + "then \(on ? "on" : "off") \(describe(item)); same handle \(same)")
}

// MARK: - K6: Generate Captions' Start, keyless

if let six = fixture() {
    let defaults = MemoryDefaults()
    let sheet = cloudSheet(six.document, store: MemoryStore(), defaults: defaults)
    let engineItem = sheet.enginePopup.itemArray.first {
        $0.representedObject as? String == TranscriptionEngine.assemblyai.rawValue
    }
    let cloudOff = !sheet.startButton.isEnabled
    let cloudTip = sheet.startButton.toolTip
    let options = sheet.runRequest().options
    let seeded = options.map { seed(six.document, six.media, $0) } ?? false
    let reused = cloudSheet(six.document, store: MemoryStore(), defaults: defaults)
    let reusedOn = reused.startButton.isEnabled
    let reusedTip = reused.startButton.toolTip
    if let index = sheet.enginePopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == TranscriptionEngine.apple.rawValue
    }) {
        sheet.enginePopup.selectItem(at: index)
    }
    sheet.perform(NSSelectorFromString("engineChanged:"), with: nil)
    let appleTip = sheet.startButton.toolTip
    keptAlive.append(contentsOf: [sheet, reused, six.document])
    row("K6",
        engineItem?.isEnabled == true && cloudOff && cloudTip == sentence && seeded && reusedOn
            && reusedTip == nil && sheet.engine == .apple && appleTip == nil,
        "AssemblyAI item enabled \(engineItem?.isEnabled ?? false); keyless Start "
            + "\(cloudOff ? "off" : "on") tooltip \(cloudTip.map { "\"\($0)\"" } ?? "nil"); "
            + "a reusable batch seeded \(seeded): Start \(reusedOn ? "on" : "off") tooltip "
            + "\(reusedTip.map { "\"\($0)\"" } ?? "nil"); on the on-device engine "
            + "(\(sheet.engine.rawValue)) tooltip \(appleTip.map { "\"\($0)\"" } ?? "nil")")
} else {
    row("K6", false, "the fixture did not build")
}

// MARK: - K7: the parity check's sixth part

do {
    let parsed = (try? AgentServer.shared.catalogJSON())
        .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [[String: Any]]
    if let tools = parsed {
        let shipped = AgentServer.keyedToolFailure(tools)
        let clause = ModelKey.assemblyAI.catalogClause
        var cut = tools
        var removed = false
        for index in cut.indices where cut[index]["name"] as? String == "transcribe_for_fillers" {
            let text = cut[index]["description"] as? String ?? ""
            removed = text.contains(clause)
            cut[index]["description"] = text.replacingOccurrences(of: clause, with: "")
        }
        let named = AgentServer.keyedToolFailure(cut)
        row("K7",
            shipped == nil && removed && (named?.contains("transcribe_for_fillers") ?? false),
            "over the shipped catalog (\(tools.count) tools): \(shipped ?? "nil"); with "
                + "transcribe_for_fillers' clause removed (\(removed)): \(named ?? "nil")")
    } else {
        row("K7", false, "the catalog did not build")
    }
}

try? saved.remove()
withExtendedLifetime(keptAlive) { finish() }
