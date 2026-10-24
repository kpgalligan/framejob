// Cut by transcript CT-3 (spec §11 TR-7, TR-10): the probe rows of
// `filler_sheet_proof.py`, compiled as `main.swift` over `app/Sources` (or a
// mutant's copy of it) through `swift_build.build()` and run with the path of
// `media/speech.mov` as its one argument. It drives the REAL sheet —
// `FillerSheetController`, its view loaded, Remove pressed with
// `performClick` on a sheet presented with an animator that does nothing —
// and prints one JSON object, `{"rows": [{"id", "pass", "detail"}]}`, on
// stdout. No network: no row presses Transcribe. No defaults: every sheet
// gets a `MemoryDefaults`, a `MemoryStore` and an explicit environment. The
// only disk it writes is the documents' own temporary cache folders.

import AppKit
import Foundation

_ = NSApplication.shared

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

/// `tools/proof/harness/main.swift`'s `MemoryDefaults`, restated (the probe
/// links no harness): keyed calls from memory, the argument domain empty,
/// every domain write a trap — a crash, so a scored FAILURE.
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

/// Presents with no animation, so `dismiss(self)` has a presenter.
final class StillAnimator: NSObject, NSViewControllerPresentationAnimator {
    func animatePresentation(of viewController: NSViewController, from: NSViewController) {}
    func animateDismissal(of viewController: NSViewController, from: NSViewController) {}
}

guard CommandLine.arguments.count > 1,
    FileManager.default.fileExists(atPath: CommandLine.arguments[1])
else {
    row("S1", false, "media/speech.mov is missing (the probe's one argument)")
    finish()
}
let speech = URL(fileURLWithPath: CommandLine.arguments[1])
guard let probed = try? MediaImporter.probeBlocking(url: speech) else {
    row("S1", false, "speech.mov did not probe")
    finish()
}

let keyed = [AssemblyAIConfiguration.environmentKey: "proof-key"]
let fillerOptions = TranscriptOptions(
    speechModels: TranscriptOptions.shippedModels, languageCode: nil, speakerLabels: false,
    keytermsPrompt: [])

/// A cache file of these words, (text, start ms, end ms), requested with `options`.
func file(_ words: [(String, Int, Int)], _ options: TranscriptOptions = fillerOptions)
    -> MediaTranscript.File
{
    let parts = words.map { word -> String in
        #"{"text":"\#(word.0)","start":\#(word.1),"end":\#(word.2),"confidence":0.9,"speaker":null}"#
    }
    let header = MediaTranscript.Header(
        provider: MediaTranscript.provider, transcriptID: "t_sheet", requested: options,
        speechModelUsed: "universal-3-5-pro", languageCode: "en", languageConfidence: nil,
        audioDuration: 6, extractedSeconds: 5.2, uploadedFormat: "flac",
        audioTrackStartMs: 0, fetchedAt: "2026-10-22T00:00:00Z", remoteDeleted: true)
    return try! MediaTranscript.File(
        header: header, wordsJSON: Data(("[" + parts.joined(separator: ",") + "]").utf8))
}

/// A document holding speech.mov and one clip of the whole of it at 0.
func fixture() -> (document: ProjectDocument, media: UInt32, clip: UInt32)? {
    let document = ProjectDocument()
    guard let track = document.project.snapshot.tracks.first?.id else { return nil }
    document.performGroupedEdit("Media", [.addMedia(descriptor: probed)])
    guard let media = document.project.snapshot.media.first?.id else { return nil }
    document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: 0)])
    guard let clip = document.project.snapshot.clips.first?.id else { return nil }
    spin(0.1)
    document.undoManager?.removeAllActions()
    return (document, media, clip)
}

/// Two separate filler runs, "um" and "uh", with words on both sides.
func twoRuns(_ document: ProjectDocument, needs: [UInt32] = []) -> FillerDetector.Input? {
    let snapshot = document.editedProject.snapshot
    guard
        let job = Transcriber.jobs(for: snapshot.clips, in: snapshot, urls: document.mediaURLs())
            .jobs.first
    else { return nil }
    let words = FillerDetector.ClipWords(
        job: job,
        file: file([
            ("Hello", 0, 1000), ("um", 1500, 1800), ("world", 2500, 3000), ("uh", 3500, 3800),
            ("again", 4300, 4900),
        ]))
    return FillerDetector.Input(
        fps: snapshot.canvas.fps, scope: .all, clips: [words], needsTranscript: needs,
        skipped: [], locked: [], neighbours: [words], nests: [], walls: [])
}

func sheet(
    _ document: ProjectDocument, _ timeline: TimelineView, _ input: FillerDetector.Input,
    cache: URL?, environment: [String: String] = [:], defaults: UserDefaults = MemoryDefaults()
) -> FillerSheetController {
    let controller = FillerSheetController(
        document: document, timeline: timeline, input: input, cacheDirectory: cache,
        store: MemoryStore(), defaults: defaults, environment: environment)
    _ = controller.view
    return controller
}

func clips(_ document: ProjectDocument) -> [String] {
    document.editedProject.snapshot.clips.map {
        "\($0.track) \($0.start) \($0.duration) \($0.source)"
    }
}

func spans(_ list: [SilenceDetector.Span]) -> [[Ticks]] { list.map { [$0.start, $0.end] } }

var keptAlive: [AnyObject] = []

// MARK: - S1, S2: the count, the wash, the commit

if let one = fixture(), let input = twoRuns(one.document), let twin = fixture() {
    let timeline = TimelineView()
    let s = sheet(one.document, timeline, input, cache: one.document.cacheDirectory)
    let expected = FillerDetector.detect(input)
    let want = expected.spans.count == 2
        ? "2 cuts · removes "
            + ReelTime.format(expected.removed, fps: input.fps, frames: true)
        : "<detect gave \(expected.spans.count) spans>"
    row("S1",
        s.summaryLabel.stringValue == want && s.applyButton.isEnabled
            && timeline.candidateSpans == s.outcome.spans && s.outcome.spans == expected.spans
            && s.mediaRows.isEmpty,
        "summary \"\(s.summaryLabel.stringValue)\", want \"\(want)\"; Remove enabled "
            + "\(s.applyButton.isEnabled); wash \(spans(timeline.candidateSpans)), outcome "
            + "\(spans(s.outcome.spans)); rows \(s.mediaRows.count)")

    let host = NSViewController()
    host.view = NSView()
    let animator = StillAnimator()
    keptAlive.append(contentsOf: [host, animator, timeline, s])
    host.present(s, animator: animator)
    let before = clips(one.document)
    s.applyButton.performClick(nil)
    spin(0.2)
    let after = clips(one.document)
    twin.document.applyEdit(
        "Twin", [.rippleDeleteRanges(ranges: expected.spans.map { (from: $0.start, to: $0.end) })])
    spin(0.2)
    let twinAfter = clips(twin.document)
    let name = one.document.undoManager?.undoActionName ?? "<no undo manager>"
    one.document.undoManager?.undo()
    spin(0.2)
    let restored = clips(one.document) == before
    let washBefore = spans(timeline.candidateSpans)
    s.viewDidDisappear()
    row("S2",
        after == twinAfter && after != before && name == "Remove Filler Words" && restored
            && !washBefore.isEmpty && timeline.candidateSpans.isEmpty,
        "after Remove \(after); the twin's ripple_delete_ranges of both spans \(twinAfter); "
            + "undo \"\(name)\"; one undo restored \(restored); wash \(washBefore) → "
            + "\(spans(timeline.candidateSpans)) after viewDidDisappear")
    keptAlive.append(contentsOf: [one.document, twin.document])
} else {
    row("S1", false, "the fixture did not build")
    row("S2", false, "the fixture did not build")
}

// MARK: - S3: a media whose transcript serves captions but not fillers

if let three = fixture(), let cache = three.document.cacheDirectory,
    let media = three.document.project.snapshot.media(three.media),
    let source = MediaImporter.CacheStamp.stamp(for: media, url: speech)
{
    let old = TranscriptOptions(
        speechModels: TranscriptOptions.shippedModels, languageCode: "en", speakerLabels: true,
        keytermsPrompt: [], disfluencies: false)
    let wrote = MediaTranscript.write(file([("Hello", 0, 1000)], old), for: three.media, in: cache)
        && MediaTranscript.writeStamp(
            TranscriptStamp(source: source, options: old), for: three.media, in: cache)
    let read = MediaTranscript.read(for: three.media, in: cache) != nil
    let input = FillerDetector.read(from: three.document, clips: nil)
    let defaults = MemoryDefaults()
    let timeline = TimelineView()
    let s = sheet(three.document, timeline, input, cache: cache, defaults: defaults)
    let snapshot = three.document.editedProject.snapshot
    var records: [UInt32: MediaSnapshot] = [:]
    for entry in snapshot.media { records[entry.id] = entry }
    let jobs = FillerTranscription.jobs(
        for: three.media, in: snapshot, urls: three.document.mediaURLs(), maps: { _ in nil })
    let estimate = FillerTranscription.estimate(jobs: jobs, media: records, cacheDirectory: cache)
    let fate = estimate?.rows.first?.fate
    let line = estimate.map { CloudEstimate.describe($0, fps: snapshot.canvas.fps) } ?? "<nil>"
    let row0 = s.mediaRows.first
    let hint = FillerSheetController.uploadHint(
        region: AssemblyAIConfiguration.region(defaults: defaults))
    let keyedSheet = sheet(
        three.document, TimelineView(), input, cache: cache, environment: keyed)
    let keyedEnabled = keyedSheet.mediaRows.first?.button.isEnabled ?? false
    keptAlive.append(contentsOf: [timeline, s, keyedSheet, three.document])
    row("S3",
        wrote && read && input.needsTranscript == [three.media] && s.mediaRows.count == 1
            && row0?.media == three.media && fate == .upload(.refresh)
            && row0?.estimate.stringValue == line && line.contains("1 file to upload")
            && s.cloudNoteLabel.stringValue == FillerSheetController.cloudOnlyNote
            && !s.transcribeSection.isHidden && s.hintLabel.stringValue == hint
            && row0?.button.isEnabled == false
            && s.noteLabel.stringValue.contains(TranscribeSheetController.noKeyNote)
            && keyedEnabled && !s.applyButton.isEnabled && s.summaryLabel.stringValue == "No cuts",
        "seeded \(wrote), readable \(read); needs \(input.needsTranscript); rows "
            + "\(s.mediaRows.map(\.media)); fate \(String(describing: fate)); row line "
            + "\"\(row0?.estimate.stringValue ?? "<none>")\", describe \"\(line)\"; section shown "
            + "\(!s.transcribeSection.isHidden); hint matches \(s.hintLabel.stringValue == hint); "
            + "keyless button \(row0?.button.isEnabled ?? true), note \"\(s.noteLabel.stringValue)\"; "
            + "keyed button \(keyedEnabled); Remove \(s.applyButton.isEnabled); summary "
            + "\"\(s.summaryLabel.stringValue)\"")
} else {
    row("S3", false, "the fixture, its cache directory or its source stamp did not build")
}

// MARK: - S4: the request

do {
    let marker = TranscriptStamp(
        source: MediaImporter.CacheStamp.stamp(
            for: MediaSnapshot(
                id: 1, path: speech.path, duration: probed.duration, hasVideo: true,
                hasAudio: true), url: speech)!,
        options: TranscriptOptions(
            speechModels: ["universal-2"], languageCode: "fr", speakerLabels: true,
            keytermsPrompt: ["Frame Job"], disfluencies: false))
    let kept = FillerTranscription.options(for: marker)
    let none = FillerTranscription.options(for: nil)
    let wantKept = TranscriptOptions(
        speechModels: TranscriptOptions.shippedModels, languageCode: "fr", speakerLabels: true,
        keytermsPrompt: ["Frame Job"], disfluencies: true)
    let wantNone = TranscriptOptions(
        speechModels: TranscriptOptions.shippedModels, languageCode: nil, speakerLabels: false,
        keytermsPrompt: [], disfluencies: true)
    row("S4", kept == wantKept && none == wantNone && FillerTranscription.refresh,
        "with a marker \(kept); with none \(none); refresh \(FillerTranscription.refresh)")
}

// MARK: - S5: the jobs

do {
    let snapshot = ProjectSnapshot(
        media: [
            MediaSnapshot(id: 1, path: speech.path, duration: 3_000_000, hasVideo: true, hasAudio: true),
            MediaSnapshot(id: 2, path: speech.path, duration: 3_000_000, hasVideo: true, hasAudio: true),
        ],
        tracks: [TrackSnapshot(id: 1), TrackSnapshot(id: 2)],
        clips: [
            ClipSnapshot(
                id: 10, track: 1, start: 0, duration: 600_000,
                source: .media(id: 1, in: 0, reversed: false)),
            ClipSnapshot(
                id: 11, track: 1, start: 600_000, duration: 600_000,
                source: .media(id: 1, in: 0, reversed: true)),
            ClipSnapshot(
                id: 12, track: 2, start: 0, duration: 600_000,
                source: .media(id: 2, in: 0, reversed: false)),
        ])
    let jobs = FillerTranscription.jobs(
        for: 1, in: snapshot, urls: [1: speech, 2: speech], maps: { _ in nil })
    row("S5", jobs.map(\.clip) == [10] && jobs.allSatisfy { $0.media == 1 },
        "media 1's jobs: clips \(jobs.map(\.clip)) (want [10]: 11 is reversed, 12 plays media 2)")
}

// MARK: - S6: withheld from the assistant

do {
    let refusal = AssistantToolTable.refusal(tool: "transcribe_for_fillers", arguments: ["media": 1])
    let want = "transcribe_for_fillers is not available to the assistant: Audio leaves the "
        + "machine only by name, with the price in front of the person (spec §11 R6-2). Use "
        + "Clip ▸ Remove Filler Words…, which shows what is uploaded and what it costs."
    let kept = AssistantToolTable.assistantCatalog([
        ["name": "detect_fillers"], ["name": "transcribe_for_fillers"],
    ]).compactMap { $0["name"] as? String }
    row("S6", refusal == want && kept == ["detect_fillers"],
        "refusal \(refusal ?? "<nil>"); the assistant's catalog keeps \(kept)")
}

// MARK: - S7: Remove is off while a run goes

if let seven = fixture(), let input = twoRuns(seven.document, needs: [seven.media]) {
    let s = sheet(
        seven.document, TimelineView(), input, cache: seven.document.cacheDirectory,
        environment: keyed)
    let removeBefore = s.applyButton.isEnabled
    let transcribeBefore = s.mediaRows.first?.button.isEnabled ?? false
    s.runStarted(media: seven.media)
    let button = s.mediaRows.first?.button
    keptAlive.append(contentsOf: [s, seven.document])
    row("S7",
        removeBefore && transcribeBefore && !s.applyButton.isEnabled
            && s.runningMedia == seven.media && button?.title == "Stop"
            && button?.isEnabled == true,
        "before: Remove \(removeBefore), Transcribe \(transcribeBefore); after runStarted: "
            + "Remove \(s.applyButton.isEnabled), running \(String(describing: s.runningMedia)), "
            + "button \"\(button?.title ?? "<none>")\" enabled \(button?.isEnabled ?? false)")
} else {
    row("S7", false, "the fixture did not build")
}

withExtendedLifetime(keptAlive) { finish() }
