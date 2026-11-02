// Road map "creator-jobs" TX1b — on-device word starts moved to their sound
// (spec §11 TX-15…TX-18); `word_onset_proof.py` builds and runs it. Compiled
// from `app/Sources` minus the app's `main.swift`, through `swift_build.py`
// with `-D FRAMEJOB_DEV_TOOLS`, with THIS file as `main.swift`; the app's
// `Compositor.metal` is built beside it (`space_key_proof.build_shader`).
//
//   word-onset-probe <package>
//
// U1–U8 call `WordOnsets`, `TimelineTranscript`, `TranscriptCut` and
// `TranscriptTokens` over voice and peaks caches written on this page, so
// every expected tick is arithmetic here (cell 19,200 ticks, bucket 6,000).
// U9 and U10 open the package's editor window (`transcript_tab_probe.swift`'s
// `openEditor()`): media 20, a 20 s silent WAV under clip 3 (0–20 s), whose
// stored on-device run is written here before the window opens, beside
// silent caches so the open's cache pass skips them; the landing caches are
// written here too and announced with `MediaImporter.postCacheChange`.
// Prints one JSON object, {"rows": [{id, pass, detail}]}.
//   U1  a start in silence moves to the exact 10 ms bucket where its sound
//       begins.
//   U2  a start inside the previous speech, then a 2-cell non-speech run:
//       moved to the bucket after it.
//   U3  a 1-cell run that does not hold the start: unmoved.
//   U4  the walls: an onset at or past the word's own end, and at or past
//       the next word's start, falls back to the first speech cell.
//   U5  no voice cache: nil; no peaks: the first speech cell's start.
//   U6  a noise floor over −40 dBFS inside [a, b) raises T to +12 dB over it;
//       loud speech elsewhere in the run does not (a −20 dBFS run with a
//       −60 dBFS gap keeps T at −40 dBFS).
//   U7  identity: `id.source` is the recogniser's tick while `start` is
//       moved; `TranscriptCut.edges` matches the moved word (E1 adds the
//       lead); the pause set holds the recogniser's tick.
//   U8  a click in the silence earlier than b − 3 cells is not the onset.
//   U9  the tab, its load finished: a selected word; both caches land; the
//       starts move to the sound, the selection's identity is kept, and no
//       rebuild between the post and the merge drops a token.
//   U10 the tab, a load in flight (`TranscriptTabSource.loadHold`): read with
//       no voice cache, both caches land, the load released: the merged
//       starts are moved.
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

let args = CommandLine.arguments
let package = args.count > 1 ? args[1] : ""
let SEC: Ticks = 600_000
let chunk = MediaSpeech.chunkTicks
let bucket = MediaPeaks.bucketTicks

func w(_ start: Ticks, _ end: Ticks, _ text: String = "w") -> DeviceTranscriptCache.Word {
    DeviceTranscriptCache.Word(text: text, start: start, end: end)
}

/// `count` cells, speech (1) in `on`, else 0.
func cells(_ count: Int, speech on: [Range<Int>]) -> [Float] {
    (0..<count).map { k in on.contains { $0.contains(k) } ? 1 : 0 }
}

/// `count` buckets at `base`, with `spans` set to their level.
func buckets(_ count: Int, base: Float = 0, _ spans: [(Range<Int>, Float)] = []) -> [Float] {
    var out = [Float](repeating: base, count: count)
    for (span, level) in spans { for k in span where k < count { out[k] = level } }
    return out
}

func moved(_ words: [DeviceTranscriptCache.Word], _ speech: [Float]?, _ peaks: [Float]?) -> [Ticks]? {
    WordOnsets.moved(words, speech: speech, peaks: peaks)
}

func show(_ value: [Ticks]?) -> String { value.map { "\($0)" } ?? "nil" }

// U1's caches: cells 0…9 silent, 10…19 speech (b = 10, 192,000); the sound
// from bucket 30 (180,000), inside the 3-cell lead window [134,400, 211,200).
let u1Speech = cells(20, speech: [10..<20])
let u1Peaks = buckets(80, [(30..<64, 0.5)])

// MARK: - U1 a start in silence

do {
    let got = moved([w(50_000, 500_000)], u1Speech, u1Peaks)
    row("U1", got == [180_000],
        "start 50000 in silence, speech from cell 10 (192000), sound from bucket 30: \(show(got)) "
            + "(want [180000])")
}

// MARK: - U2 a start in speech, then a 2-cell run

do {
    // Cells 0…4 the previous speech, 5…6 non-speech (96,000–134,400), 7… speech;
    // the sound before bucket 16, quiet 16…21, then from bucket 22 (132,000).
    let speech = cells(15, speech: [0..<5, 7..<15])
    let peaks = buckets(60, [(0..<16, 0.5), (22..<60, 0.5)])
    let got = moved([w(40_000, 400_000)], speech, peaks)
    row("U2", got == [132_000],
        "start 40000 inside speech, a 2-cell run [5, 7): \(show(got)) (want [132000])")
}

// MARK: - U3 a 1-cell run does not move it

do {
    let speech = cells(15, speech: [0..<5, 6..<15])
    let peaks = buckets(60, [(0..<60, 0.5)])
    let got = moved([w(40_000, 200_000)], speech, peaks)
    row("U3", got == [40_000],
        "start 40000 inside speech, a 1-cell run [5, 6): \(show(got)) (want [40000], unmoved)")
}

// MARK: - U4 the walls

do {
    // U1's speech; the sound only from bucket 33 (198,000), past both walls.
    let peaks = buckets(80, [(33..<64, 0.5)])
    let own = moved([w(50_000, 195_000)], u1Speech, peaks)
    let next = moved([w(50_000, 400_000), w(195_000, 500_000)], u1Speech, peaks)
    row("U4", own == [192_000] && next == [192_000, 195_000],
        "the refined onset 198000 at or past the own end 195000: \(show(own)) (want [192000]); "
            + "past the next word's start 195000: \(show(next)) (want [192000, 195000])")
}

// MARK: - U5 no voice cache, no peaks

do {
    let none = moved([w(50_000, 500_000)], nil, u1Peaks)
    let cell = moved([w(50_000, 500_000)], u1Speech, nil)
    row("U5", none == nil && cell == [192_000],
        "no voice cache \(show(none)) (want nil); no peaks \(show(cell)) (want [192000])")
}

// MARK: - U6 the noise floor

do {
    // (1) U1's speech, a 0.02 floor (−34 dBFS) to bucket 29, the sound 0.5 from
    // bucket 30: T = 4 × 0.02 = 0.08, so the floor is not the onset.
    let floor = buckets(80, base: 0.02, [(30..<64, 0.5)])
    let raised = moved([w(50_000, 500_000)], u1Speech, floor)
    // (2) cells 0…9 speech at 0.1 (−20 dBFS), 10…15 a gap at 0.001 (−60 dBFS),
    // 16… speech at 0.1 from bucket 49 (294,000); b = 16 (307,200). Over the
    // run [192,000, 307,200) the median is 0.001, so T stays 0.01.
    let speech = cells(40, speech: [0..<10, 16..<40])
    let loud = buckets(128, [(0..<32, 0.1), (32..<49, 0.001), (49..<128, 0.1)])
    let kept = moved([w(150_000, 900_000)], speech, loud)
    row("U6", raised == [180_000] && kept == [294_000],
        "a −34 dBFS floor in [a, b): \(show(raised)) (want [180000]); a −20 dBFS run with a "
            + "−60 dBFS gap: \(show(kept)) (want [294000])")
}

// MARK: - U7 identity, the cut's match and the pause set

do {
    let json = #"{"version":38,"canvas":{"width":1920,"height":1080,"fps":[30,1]},"media":[{"id":1,"path":"/fixtures/a.wav","kind":"audio","duration":\#(10 * SEC),"has_audio":true}],"tracks":[{"id":5,"name":"T5","muted":false,"locked":false}],"clips":[{"id":10,"track":5,"start":0,"duration":\#(10 * SEC),"source":{"kind":"media","media":1,"in":0,"reversed":false},"enabled":{"video":true,"audio":true}}],"markers":[],"nests":[],"next_id":500}"#
    let heard = DeviceTranscriptCache.Heard(
        sourceIn: 0, sourceLength: 10 * SEC,
        words: [w(50_000, 400_000, "one"), w(2_500_000, 2_800_000, "two")])
    let shift = WordOnsets.moved(heard.words, speech: u1Speech, peaks: u1Peaks)
    let media = TimelineTranscript.MediaWords(
        media: 1, engine: .apple, language: "en-US", fillersReported: false,
        words: TimelineTranscript.sourceWords(device: heard, moved: shift))
    var detail = "no project"
    var pass = false
    do {
        _ = try ReelProject.from(json: json)
    } catch {
        detail = "no project: \(error)"
    }
    if let project = try? ReelProject.from(json: json), let plan = project.plan {
        let snapshot = project.snapshot
        let found = TimelineTranscript.read(
            plan: plan, snapshot: snapshot, urls: [1: URL(fileURLWithPath: "/fixtures/a.wav")],
            maps: { _, _ in nil })
        let words = TimelineTranscript.words(found.instances, media: [1: media], snapshot: snapshot)
        let edges = TranscriptCut.edges(
            words,
            context: TranscriptCut.Context(instances: found.instances, media: [1: media], speech: [:]),
            rule: .e1)
        let lead = CaptionPages.lead(for: .apple)
        let pauses = TranscriptTokens.pauses(
            media.words, speech: nil, confidence: Float(SilenceDetector.Settings.defaultVoiceConfidence))
        let paragraphs = TranscriptTokens.build(words, pauses: [1: pauses]).paragraphs.count
        let starts = words.map(\.start)
        let ids = words.map(\.id.source)
        let onsets = edges.map(\.onset)
        pass = starts == [180_000, 2_500_000] && ids == [50_000, 2_500_000]
            && onsets == [180_000 + lead, 2_500_000 + lead] && pauses == [50_000] && paragraphs == 2
        detail = "starts \(starts) (want [180000, 2500000]); id.source \(ids) (want [50000, "
            + "2500000]); E1 onsets \(onsets) (want the moved starts + \(lead)); pause set "
            + "\(pauses.sorted()) (want [50000]); paragraphs \(paragraphs) (want 2)"
    }
    row("U7", pass, detail)
}

// MARK: - U8 a click before the lead window

do {
    let peaks = buckets(80, [(10..<11, 0.9), (30..<64, 0.5)])
    let got = moved([w(50_000, 500_000)], u1Speech, peaks)
    row("U8", got == [180_000],
        "a click at bucket 10 (60000), 7 cells before b: \(show(got)) (want [180000])")
}

// MARK: - The editor rows (U9, U10)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

func until(_ seconds: Double, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return done()
}

// Six words: each sound at 2 + 3i s, each recognised 0.6 s early, 1.6 s long.
let sounds: [Ticks] = (0..<6).map { (2 + 3 * Ticks($0)) * SEC }
let early: Ticks = 6 * SEC / 10
let stored: [DeviceTranscriptCache.Word] = sounds.enumerated().map { (index: Int, sound: Ticks) in
    w(sound - early, sound + SEC, "word\(index)")
}
let fileTicks = 20 * SEC
let cellCount = MediaSpeech.chunkCount(duration: fileTicks)
let soundLength: Ticks = 12 * SEC / 10
let speechSpans: [Range<Int>] = sounds.map { (sound: Ticks) -> Range<Int> in
    let first = Int(sound / chunk)
    let past = Int((sound + soundLength + chunk - 1) / chunk)
    return first..<past
}
let peakSpans: [(Range<Int>, Float)] = sounds.map { (sound: Ticks) -> (Range<Int>, Float) in
    let first = Int(sound / bucket)
    let past = Int((sound + soundLength) / bucket)
    return (first..<past, Float(0.5))
}
let landingSpeech = cells(cellCount, speech: speechSpans)
let landingPeaks = buckets(Int(fileTicks / bucket), peakSpans)
let wantMoved = WordOnsets.moved(stored, speech: landingSpeech, peaks: landingPeaks)

/// Media 20's caches written whole with the file's stamp, as a pass would
/// publish them; with `post`, announced as landed.
func writeCaches(_ document: ProjectDocument, speech: [Float], peaks: [Float], post: Bool) -> Bool {
    guard let cache = document.cacheDirectory, let record = document.project.snapshot.media(20),
        let url = document.mediaURLs()[20],
        let stamp = MediaImporter.CacheStamp.stamp(for: record, url: url)
    else { return false }
    let speechFile = MediaImporter.speechURL(for: 20, in: cache)
    let peaksFile = MediaImporter.peaksURL(for: 20, in: cache)
    for folder in [speechFile, peaksFile].map({ $0.deletingLastPathComponent() }) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    let ok = (try? speech.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: speechFile)) != nil
        && (try? peaks.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: peaksFile)) != nil
        && MediaImporter.writeStamp(
            MediaImporter.SpeechStamp(stamp), to: MediaImporter.speechMarkerURL(for: 20, in: cache))
        && MediaImporter.writeStamp(
            MediaImporter.PeaksStamp(stamp), to: MediaImporter.peaksMarkerURL(for: 20, in: cache))
    if post {
        MediaImporter.postCacheChange(media: 20, kind: MediaImporter.speechKind)
        MediaImporter.postCacheChange(media: 20, kind: MediaImporter.peaksKind)
    }
    return ok
}

/// Media 20's caches removed, markers first.
func clearCaches(_ document: ProjectDocument) {
    guard let cache = document.cacheDirectory else { return }
    for url in [MediaImporter.speechMarkerURL(for: 20, in: cache), MediaImporter.speechURL(for: 20, in: cache),
                MediaImporter.peaksMarkerURL(for: 20, in: cache), MediaImporter.peaksURL(for: 20, in: cache)] {
        try? FileManager.default.removeItem(at: url)
    }
}

/// The document read, its stored run and silent caches written, then its
/// window opened on the Transcript tab; nil (with why) when any step fails.
func openEditor() -> (ProjectDocument, NSWindow, InspectorViewController, TranscriptPane)? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: package), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        return nil
    }
    guard let cache = document.cacheDirectory, let record = document.project.snapshot.media(20),
        let url = document.mediaURLs()[20],
        let language = TranscriptTabSource.resolve(nil, in: Transcriber.languages()),
        let stamp = DeviceTranscriptCache.currentStamp(record, url: url, language: language.identifier),
        DeviceTranscriptCache.store(
            DeviceTranscriptCache.Heard(sourceIn: 0, sourceLength: record.duration, words: stored),
            media: 20, stamp: stamp, in: cache),
        writeCaches(
            document, speech: [Float](repeating: 0, count: cellCount),
            peaks: [Float](repeating: 0, count: Int(fileTicks / bucket)), post: false)
    else { return nil }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
        let editor = window.contentViewController as? EditorViewController
    else { return nil }
    window.appearance = NSAppearance(named: .aqua)
    editor.showTranscript(nil)
    guard let inspector = editor.inspector, let pane = TranscriptPane.pane(in: inspector) else {
        return nil
    }
    return (document, window, inspector, pane)
}

if let (document, _, inspector, pane) = openEditor() {
    let source: TranscriptTabSource = pane.source
    let starts = { source.model.tokens.map(\.word.start) }
    let recognised = stored.map(\.start)

    // U9: the load finished on silent caches, so the starts are the recogniser's.
    let loaded = until(15) { source.settled && starts().count == 6 }
    let before = starts()
    pane.transcriptView.select(3...3)
    spin(0.3)
    let selected = pane.transcriptView.selection
    let id = selected.map { source.model.tokens[$0.lowerBound].word.id }
    let rebuilds = source.rebuilds
    let written = writeCaches(document, speech: landingSpeech, peaks: landingPeaks, post: true)
    var dropped = 0
    let merged = until(15) {
        if source.model.tokens.count != 6 { dropped += 1 }
        return starts() == wantMoved ?? []
    }
    let after = pane.transcriptView.selection
    let kept = after.map { source.model.tokens[$0.lowerBound].word.id } == id && id != nil
    row("U9", loaded && before == recognised && written && merged && kept && dropped == 0
            && wantMoved == sounds,
        "loaded \(loaded), starts \(before) (want the recogniser's \(recognised)); caches written "
            + "\(written); after the landing \(starts()) (want \(show(wantMoved)), the sounds "
            + "\(sounds)); selection \(String(describing: selected)) → \(String(describing: after)), "
            + "identity kept \(kept); samples with a token dropped \(dropped); rebuilds "
            + "\(rebuilds) → \(source.rebuilds)")

    // U10: hidden (its words dropped), the caches gone, shown with the load held.
    inspector.select(.media)
    spin(0.3)
    clearCaches(document)
    let hold = DispatchSemaphore(value: 0)
    TranscriptTabSource.loadHold = hold
    inspector.select(.transcript)
    spin(1.5)
    let heldEmpty = starts().isEmpty
    let rewritten = writeCaches(document, speech: landingSpeech, peaks: landingPeaks, post: true)
    spin(0.5)
    TranscriptTabSource.loadHold = nil
    hold.signal()
    let settled = until(15) { source.settled && starts() == wantMoved ?? [] }
    spin(0.3)
    row("U10", heldEmpty && rewritten && settled && starts() == wantMoved ?? [],
        "nothing merged while held \(heldEmpty); caches written \(rewritten); after the release "
            + "\(starts()) (want \(show(wantMoved))); settled \(source.settled)")
} else {
    for id in ["U9", "U10"] {
        row(id, false, "the editor did not open on \(package), or its stored run and caches were "
            + "not written (no installed on-device language?)")
    }
}

if let data = try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]),
    let text = String(data: data, encoding: .utf8)
{
    print(text)
}
exit(0)
