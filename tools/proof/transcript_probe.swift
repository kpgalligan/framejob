// Cut by transcript CT-4 (spec §11 TR-11), #331 (TR-13) and #332 (TR-14): the value rows of
// `transcript_proof.py`, compiled as `main.swift` over `app/Sources` (or a
// mutant's copy of it) through `swift_build.build()`. Prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`, on stdout. No network, no app, no
// defaults; the only disk it touches is a temporary folder it removes.

import Foundation

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func text(_ data: Data?) -> String { data.flatMap { String(data: $0, encoding: .utf8) } ?? "" }

let fillerOptions = TranscriptOptions(
    speechModels: TranscriptOptions.shippedModels, languageCode: nil, speakerLabels: false,
    keytermsPrompt: [])
var plainOptions = fillerOptions
plainOptions.disfluencies = false

func header(_ options: TranscriptOptions) -> MediaTranscript.Header {
    MediaTranscript.Header(
        provider: MediaTranscript.provider, transcriptID: "t_transcript", requested: options,
        speechModelUsed: "universal-3-5-pro", languageCode: "en_us", languageConfidence: 0.99,
        audioDuration: 6, extractedSeconds: 5.9, uploadedFormat: "flac",
        audioTrackStartMs: 0, fetchedAt: "2026-10-23T00:00:00Z", remoteDeleted: true)
}

/// A cache file of these words, (text, start ms, end ms), in the order given.
func file(_ words: [(String, Int, Int)], _ options: TranscriptOptions = fillerOptions)
    -> MediaTranscript.File
{
    let parts = words.map { word -> String in
        let quoted = text(try? JSONSerialization.data(withJSONObject: [word.0]))
        return #"{"text":\#(quoted.dropFirst().dropLast()),"start":\#(word.1),"end":\#(word.2),"confidence":0.9,"speaker":null}"#
    }
    let bytes = Data(("[" + parts.joined(separator: ",") + "]").utf8)
    return try! MediaTranscript.File(header: header(options), wordsJSON: bytes)
}

func job(
    clip: UInt32, media: UInt32 = 1, sourceIn: Ticks = 0, sourceLength: Ticks = 6_000_000,
    start: Ticks = 0, duration: Ticks = 6_000_000, speed: Double = 1
) -> Transcriber.Job {
    Transcriber.Job(
        clip: clip, media: media, name: "clip \(clip)", source: URL(fileURLWithPath: "/dev/null"),
        sourceIn: sourceIn, sourceLength: sourceLength, start: start, duration: duration,
        speed: speed)
}

func sorted(_ words: [TranscriptReader.Word]) -> Bool {
    zip(words, words.dropFirst()).allSatisfy { ($0.start, $0.end) <= ($1.start, $1.end) }
}

func brief(_ words: [TranscriptReader.Word]) -> String {
    words.map { "\($0.text)@\($0.start)-\($0.end)\($0.filler ? "*" : "")" }
        .joined(separator: " ")
}

// MARK: - P1: cloudWords — start 1 s, in 0.5 s, speed 2, a file out of order

do {
    // A 3 s clip at 1 s playing 6 s of source from 0.5 s.
    let clip = job(
        clip: 1, sourceIn: 300_000, sourceLength: 6_000_000, start: 600_000,
        duration: 3_000_000, speed: 2)
    let served = file([
        ("umbrella", 3000, 3400), ("er", 2000, 2100), ("before", 400, 480), ("Uh", 1500, 1600),
        ("At", 500, 700), ("so", 2000, 2050), ("um,", 1200, 1400),
    ])
    let got = TranscriptReader.cloudWords(for: clip, in: served)
    let own = MediaTranscript.words(for: clip, in: served)
    // MediaTranscript.words' own ticks, as a multiset of (text, start, end).
    let ownTicks = own.map { "\($0.text)|\($0.start)|\($0.end)" }.sorted()
    let gotTicks = got.map { "\($0.text)|\($0.start)|\($0.end)" }.sorted()
    let order = got.map(\.text)
    let wantOrder = ["At", "um,", "Uh", "so", "er", "umbrella"]
    let fillers = got.filter(\.filler).map(\.text)
    // "At" at 500 ms = 300000 ticks = in → 600000; "umbrella" at 3000 ms →
    // 600000 + (1800000 − 300000) / 2 = 1350000.
    let at = got.first { $0.text == "At" }
    let umbrella = got.first { $0.text == "umbrella" }
    row("P1",
        !order.contains("before") && order == wantOrder && gotTicks == ownTicks && sorted(got)
            && fillers == ["um,", "Uh", "er"] && umbrella?.filler == false
            && at?.start == 600_000 && umbrella?.start == 1_350_000
            && got.allSatisfy { $0.speaker == nil },
        "words \(brief(got)); MediaTranscript.words' ticks equal \(gotTicks == ownTicks); "
            + "sorted \(sorted(got)); fillers \(fillers)")
}

// MARK: - P2: deviceWords — start 1 s, speed 2, a 2 s clip, runs out of order

do {
    let clip = job(
        clip: 2, sourceIn: 300_000, sourceLength: 2_400_000, start: 600_000,
        duration: 1_200_000, speed: 2)
    let runs = [
        SpeechEngine.Run(text: "hello", start: 0.5, end: 1.0),
        SpeechEngine.Run(text: "past", start: 4.0, end: 4.25),
        SpeechEngine.Run(text: "uh", start: 0.25, end: 0.5),
        SpeechEngine.Run(text: "late", start: 3.75, end: 4.5),
    ]
    let got = TranscriptReader.deviceWords(
        DeviceTranscriptCache.Heard(runs: runs, over: clip), for: clip)
    // start + t / speed: 0.25 s → 675000, 0.5 s → 750000, 1.0 s → 900000,
    // 3.75 s → 1725000; 4.0 s is stored at the window's source end (2700000)
    // and dropped; 4.5 s is clamped to it.
    let want: [TranscriptReader.Word] = [
        .init(text: "uh", start: 675_000, end: 750_000, speaker: nil, filler: true),
        .init(text: "hello", start: 750_000, end: 900_000, speaker: nil, filler: false),
        .init(text: "late", start: 1_725_000, end: 1_800_000, speaker: nil, filler: false),
    ]
    row("P2", got == want && sorted(got),
        "words \(brief(got)); want \(brief(want))")
}

// MARK: - P3: cached — which cache answers, and whether it asked for fillers

let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("transcript-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
do {
    let movie = folder.appendingPathComponent("speech.mov")
    try? Data(repeating: 7, count: 1000).write(to: movie)
    let media = MediaSnapshot(
        id: 7, path: movie.path, duration: 6_000_000, hasVideo: true, hasAudio: true)
    let cache = folder.appendingPathComponent("cache", isDirectory: true)
    let none = TranscriptReader.cached(for: media, url: movie, in: cache)
    func seed(_ options: TranscriptOptions) -> Bool {
        guard let stamp = MediaImporter.CacheStamp.stamp(for: media, url: movie) else {
            return false
        }
        return MediaTranscript.write(file([("um", 100, 300)], options), for: 7, in: cache)
            && MediaTranscript.writeStamp(
                TranscriptStamp(source: stamp, options: options), for: 7, in: cache)
    }
    func say(_ cached: TranscriptReader.Cached?) -> String {
        cached.map { "file, fillersReported \($0.fillersReported)" } ?? "nil"
    }
    let seededTrue = seed(fillerOptions)
    let withFillers = TranscriptReader.cached(for: media, url: movie, in: cache)
    let seededFalse = seed(plainOptions)
    let withoutFillers = TranscriptReader.cached(for: media, url: movie, in: cache)
    let reseeded = seed(fillerOptions)
    try? Data(repeating: 7, count: 1001).write(to: movie)
    let changedSource = TranscriptReader.cached(for: media, url: movie, in: cache)
    row("P3",
        none == nil && seededTrue && seededFalse && reseeded
            && withFillers?.fillersReported == true && withFillers?.file.words.count == 1
            && withoutFillers?.fillersReported == false && changedSource == nil,
        "no file → \(say(none)); disfluencies true → \(say(withFillers)); false → "
            + "\(say(withoutFillers)); changed source → \(say(changedSource))")
}
try? FileManager.default.removeItem(at: folder)

// MARK: - P4..P6: the window (spec §11 TR-13) — a 10 s clip at 1 s, in 0.5 s, speed 2

/// A 10 s clip at 1 s playing 20 s of source from 0.5 s.
let windowed = job(
    clip: 9, sourceIn: 300_000, sourceLength: 12_000_000, start: 600_000, duration: 6_000_000,
    speed: 2)

func say(_ window: TranscriptReader.Window?) -> String {
    window.map { "[\($0.from), \($0.to))" } ?? "nil"
}

/// The window, or the error it threw.
func attempt(_ from: Ticks?, _ to: Ticks?) -> (TranscriptReader.Window?, TranscriptReader.WindowError?) {
    do {
        return (try TranscriptReader.window(from: from, to: to, clip: windowed), nil)
    } catch let error as TranscriptReader.WindowError {
        return (nil, error)
    } catch {
        return (nil, nil)
    }
}

// MARK: - P4: window — defaults, the clamp, and the two refusals

do {
    var problems: [String] = []
    func expect(_ from: Ticks?, _ to: Ticks?, _ want: TranscriptReader.Window?) {
        let (got, error) = attempt(from, to)
        if got != want || error != nil {
            problems.append("(\(from.map(String.init) ?? "nil"), \(to.map(String.init) ?? "nil")) → "
                + "\(say(got)) \(error.map { "\($0)" } ?? ""), want \(say(want))")
        }
    }
    func refuse(_ from: Ticks?, _ to: Ticks?, _ want: TranscriptReader.WindowError, _ sentence: String) {
        let (got, error) = attempt(from, to)
        if got != nil || error != want || error?.errorDescription != sentence {
            problems.append("(\(from.map(String.init) ?? "nil"), \(to.map(String.init) ?? "nil")) → "
                + "\(say(got)) \(error.map { "\($0)" } ?? "no error"): "
                + "\(error?.errorDescription ?? "")")
        }
    }
    expect(nil, nil, nil)
    expect(3_000_000, nil, .init(from: 3_000_000, to: 6_600_000))
    expect(nil, 1_200_000, .init(from: 600_000, to: 1_200_000))
    expect(0, 9_000_000, .init(from: 600_000, to: 6_600_000))
    refuse(1_200_000, 1_200_000, .empty(from: 1_200_000, to: 1_200_000),
        "to must be after from: the window from 1200000 to 1200000 ticks (both snapped to "
            + "frames) is empty.")
    refuse(2_400_000, 1_200_000, .empty(from: 2_400_000, to: 1_200_000),
        "to must be after from: the window from 2400000 to 1200000 ticks (both snapped to "
            + "frames) is empty.")
    refuse(6_600_000, nil,
        .outside(from: 6_600_000, to: nil, clip: 9, start: 600_000, end: 6_600_000),
        "The window from 6600000 is outside clip 9, which plays from 600000 to 6600000 ticks.")
    refuse(nil, 600_000, .outside(from: nil, to: 600_000, clip: 9, start: 600_000, end: 6_600_000),
        "The window to 600000 is outside clip 9, which plays from 600000 to 6600000 ticks.")
    refuse(7_000_000, 8_000_000,
        .outside(from: 7_000_000, to: 8_000_000, clip: 9, start: 600_000, end: 6_600_000),
        "The window from 7000000 to 8000000 is outside clip 9, which plays from 600000 to "
            + "6600000 ticks.")
    row("P4", problems.isEmpty,
        problems.isEmpty ? "9 cases as wanted" : problems.joined(separator: "; "))
}

// MARK: - P5: overlapping over [1 000 000, 2 000 000)

do {
    func word(_ text: String, _ start: Ticks, _ end: Ticks) -> TranscriptReader.Word {
        .init(text: text, start: start, end: end, speaker: nil, filler: false)
    }
    let words = [
        word("inside", 1_200_000, 1_400_000),
        word("endsAtFrom", 800_000, 1_000_000),
        word("acrossTo", 1_900_000, 2_100_000),
        word("startsAtTo", 2_000_000, 2_200_000),
        word("acrossFrom", 900_000, 1_100_000),
        word("pointAtTo", 2_000_000, 2_000_000),
        word("pointAtFrom", 1_000_000, 1_000_000),
    ]
    let got = TranscriptReader.overlapping(
        words, in: .init(from: 1_000_000, to: 2_000_000))
    let want = [words[0], words[2], words[4], words[6]]
    row("P5", got == want, "kept \(brief(got)); want \(brief(want))")
}

// MARK: - P6: recognitionJob — 2 s of source is 600 000 ticks at speed 2

do {
    func say(_ job: Transcriber.Job) -> String {
        "start \(job.start) duration \(job.duration) in \(job.sourceIn) length \(job.sourceLength)"
    }
    func same(_ a: Transcriber.Job, _ b: Transcriber.Job) -> Bool {
        a.clip == b.clip && a.media == b.media && a.name == b.name && a.source == b.source
            && a.speed == b.speed
    }
    var problems: [String] = []
    func expect(
        _ from: Ticks, _ to: Ticks, start: Ticks, duration: Ticks, sourceIn: Ticks,
        sourceLength: Ticks
    ) -> Transcriber.Job {
        let got = TranscriptReader.recognitionJob(windowed, for: .init(from: from, to: to))
        if got.start != start || got.duration != duration || got.sourceIn != sourceIn
            || got.sourceLength != sourceLength || !same(got, windowed)
        {
            problems.append(
                "[\(from), \(to)) → \(say(got)); want start \(start) duration \(duration) in "
                    + "\(sourceIn) length \(sourceLength)")
        }
        return got
    }
    let middle = expect(
        3_000_000, 4_200_000, start: 2_400_000, duration: 2_400_000, sourceIn: 3_900_000,
        sourceLength: 4_800_000)
    _ = expect(
        600_000, 1_200_000, start: 600_000, duration: 1_200_000, sourceIn: 300_000,
        sourceLength: 2_400_000)
    _ = expect(
        6_000_000, 6_600_000, start: 5_400_000, duration: 1_200_000, sourceIn: 9_900_000,
        sourceLength: 2_400_000)
    let whole = TranscriptReader.recognitionJob(windowed, for: .init(from: 600_000, to: 6_600_000))
    if whole != windowed { problems.append("the whole clip → \(say(whole))") }
    // 1 s into the sub-extract is 7 s into the clip's: it starts 6 s of source in.
    let sub = Transcriber.project(1.0, in: middle)
    let full = Transcriber.project(7.0, in: windowed)
    if abs(sub - full) > 1 { problems.append("1 s of the sub-run → \(sub), 7 s of the clip's → \(full)") }
    row("P6", problems.isEmpty,
        problems.isEmpty
            ? "three windows and the whole clip as wanted; 1 s of the sub-run → \(sub), 7 s of "
                + "the clip's → \(full)"
            : problems.joined(separator: "; "))
}

// MARK: - P7, P8: the on-device cache (spec §11 TR-14)

let cacheFolder = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("device-transcript-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)

/// A stat-able "media file" for `id`, and its snapshot.
func movie(_ id: UInt32, bytes: Int = 1000) -> (url: URL, media: MediaSnapshot) {
    let url = cacheFolder.appendingPathComponent("speech-\(id).mov")
    try? Data(repeating: 7, count: bytes).write(to: url)
    return (url, MediaSnapshot(
        id: id, path: url.path, duration: 6_000_000, hasVideo: true, hasAudio: true))
}

/// A job over media `id`'s source [from s, to s) at speed 1.
func span(_ id: UInt32, _ url: URL, _ from: Double, _ to: Double) -> Transcriber.Job {
    let sourceIn = Ticks(from * 600_000)
    let length = Ticks((to - from) * 600_000)
    return Transcriber.Job(
        clip: id, media: id, name: "clip \(id)", source: url, sourceIn: sourceIn,
        sourceLength: length, start: 0, duration: length, speed: 1)
}

func runs(_ heard: DeviceTranscriptCache.Heard?) -> String {
    heard.map { "[\($0.sourceIn), +\($0.sourceLength)) \($0.words.count) words" } ?? "nil"
}

// MARK: - P7: read, lookup, merged, store

do {
    var problems: [String] = []
    let cache = cacheFolder.appendingPathComponent("cache-p7", isDirectory: true)
    let (url, media) = movie(7)
    guard let source = MediaImporter.CacheStamp.stamp(for: media, url: url) else {
        fatalError("the P7 media file cannot be stat'ed")
    }
    let stamp = DeviceTranscriptCache.Stamp(source: source, language: "en-US")
    let whole = span(7, url, 0, 6)
    let heard = DeviceTranscriptCache.Heard(
        runs: [SpeechEngine.Run(text: "quick", start: 1.0, end: 1.5)], over: whole)
    let inner = span(7, url, 1, 2)
    let across = span(7, url, 5, 7)
    if let got = DeviceTranscriptCache.lookup(inner, media: 7, stamp: stamp, in: cache) {
        problems.append("empty → \(runs(got))")
    }
    let stored = DeviceTranscriptCache.store(heard, media: 7, stamp: stamp, in: cache)
    let hit = DeviceTranscriptCache.lookup(inner, media: 7, stamp: stamp, in: cache)
    if !stored || hit != heard { problems.append("stored \(stored); [1, 2) → \(runs(hit))") }
    if let got = DeviceTranscriptCache.lookup(across, media: 7, stamp: stamp, in: cache) {
        problems.append("[5, 7) → \(runs(got))")
    }
    let others: [(String, DeviceTranscriptCache.Stamp)] = [
        ("language fr-FR", .init(
            source: stamp.source, language: "fr-FR", system: stamp.system,
            version: stamp.version)),
        ("another system", .init(
            source: stamp.source, language: stamp.language, system: stamp.system + " (other)",
            version: stamp.version)),
        ("version + 1", .init(
            source: stamp.source, language: stamp.language, system: stamp.system,
            version: stamp.version + 1)),
    ]
    for (name, other) in others {
        if let got = DeviceTranscriptCache.lookup(inner, media: 7, stamp: other, in: cache) {
            problems.append("\(name) → \(runs(got))")
        }
    }
    try? Data(repeating: 7, count: 1001).write(to: url)
    if let fresh = MediaImporter.CacheStamp.stamp(for: media, url: url) {
        let changed = DeviceTranscriptCache.Stamp(source: fresh, language: "en-US")
        if changed == stamp { problems.append("the rewritten file's stamp is unchanged") }
        if let got = DeviceTranscriptCache.lookup(inner, media: 7, stamp: changed, in: cache) {
            problems.append("another size → \(runs(got))")
        }
    } else {
        problems.append("the rewritten file cannot be stat'ed")
    }
    // merged: a narrow run, then a wide one that contains it → 1; a disjoint
    // one → 2; another stamp → 1.
    let narrow = DeviceTranscriptCache.Heard(runs: [], over: span(7, url, 1, 2))
    let wide = DeviceTranscriptCache.Heard(runs: [], over: span(7, url, 0, 3))
    let apart = DeviceTranscriptCache.Heard(runs: [], over: span(7, url, 4, 5))
    let one = DeviceTranscriptCache.merged(nil, adding: narrow, stamp: stamp)
    let pruned = DeviceTranscriptCache.merged(one, adding: wide, stamp: stamp)
    let two = DeviceTranscriptCache.merged(pruned, adding: apart, stamp: stamp)
    let replaced = DeviceTranscriptCache.merged(two, adding: narrow, stamp: others[1].1)
    if pruned.runs != [wide] { problems.append("narrow then wide → \(pruned.runs.map(runs))") }
    if two.runs != [wide, apart] { problems.append("then disjoint → \(two.runs.map(runs))") }
    if replaced.runs != [narrow] || replaced.stamp != others[1].1 {
        problems.append("another stamp → \(replaced.runs.map(runs))")
    }
    // Garbage bytes read as absent, and a store over them succeeds.
    let file = DeviceTranscriptCache.fileURL(for: 7, language: "en-US", in: cache)
    try? Data("not json".utf8).write(to: file)
    let garbage = DeviceTranscriptCache.read(for: 7, language: "en-US", in: cache)
    let over = DeviceTranscriptCache.store(heard, media: 7, stamp: stamp, in: cache)
    let reread = DeviceTranscriptCache.read(for: 7, language: "en-US", in: cache)
    if garbage != nil || !over || reread?.runs != [heard] {
        problems.append("garbage → \(garbage == nil ? "nil" : "a file"); store over it \(over); "
            + "then \(reread?.runs.count ?? -1) runs")
    }
    // Heard(runs:over:): [2 s, 4 s) of source; -1 s and 9 s clamp to its
    // edges, a NaN is dropped.
    let clamped = DeviceTranscriptCache.Heard(
        runs: [
            SpeechEngine.Run(text: "before", start: -1, end: 0.5),
            SpeechEngine.Run(text: "nan", start: .nan, end: 1),
            SpeechEngine.Run(text: "after", start: 1.5, end: 9),
        ], over: span(7, url, 2, 4))
    let wantClamped: [DeviceTranscriptCache.Word] = [
        .init(text: "before", start: 1_200_000, end: 1_500_000),
        .init(text: "after", start: 2_100_000, end: 2_400_000),
    ]
    if clamped.words != wantClamped || clamped.sourceIn != 1_200_000
        || clamped.sourceLength != 1_200_000
    {
        problems.append("Heard(runs:over:) → \(clamped.words)")
    }
    row("P7", problems.isEmpty,
        problems.isEmpty
            ? "empty → nil; [0, 6) stored, [1, 2) hit, [5, 7) nil; fr-FR, another system, "
                + "version + 1 and another size nil; merged 1, 2, 1; garbage nil then stored; "
                + "clamped and NaN dropped"
            : problems.joined(separator: "; "))
}

// MARK: - P8: heard() — a hit skips the run, and what is never stored

do {
    var problems: [String] = []
    let cache = cacheFolder.appendingPathComponent("cache-p8", isDirectory: true)
    var count = 0
    func counting() -> [SpeechEngine.Run] {
        count += 1
        return [SpeechEngine.Run(text: "fox", start: 0.5, end: 0.75)]
    }
    func exists(_ id: UInt32) -> Bool {
        FileManager.default.fileExists(
            atPath: DeviceTranscriptCache.fileURL(for: id, language: "en-US", in: cache).path)
    }
    struct Failed: Error {}

    let (url, media) = movie(8)
    let job = span(8, url, 0, 6)
    let first = try? DeviceTranscriptCache.heard(
        job, language: "en-US", media: media, in: cache, cancelled: { false },
        recognize: counting)
    let written = exists(8)
    let second = try? DeviceTranscriptCache.heard(
        job, language: "en-US", media: media, in: cache, cancelled: { false },
        recognize: counting)
    if first?.cached != false || !written || second?.cached != true || count != 1
        || second?.heard != first?.heard
    {
        problems.append("1st cached \(String(describing: first?.cached)), file \(written); 2nd "
            + "cached \(String(describing: second?.cached)); \(count) runs")
    }

    count = 0
    let (noURL, noMedia) = movie(9)
    let noJob = span(9, noURL, 0, 6)
    let a = try? DeviceTranscriptCache.heard(
        noJob, language: "en-US", media: noMedia, in: nil, cancelled: { false },
        recognize: counting)
    let b = try? DeviceTranscriptCache.heard(
        noJob, language: "en-US", media: noMedia, in: nil, cancelled: { false },
        recognize: counting)
    if a?.cached != false || b?.cached != false || count != 2 || exists(9) {
        problems.append("no cacheDir: \(count) runs, file \(exists(9))")
    }

    let (throwURL, throwMedia) = movie(10)
    var threw = false
    do {
        _ = try DeviceTranscriptCache.heard(
            span(10, throwURL, 0, 6), language: "en-US", media: throwMedia, in: cache,
            cancelled: { false }, recognize: { throw Failed() })
    } catch is Failed {
        threw = true
    } catch {}
    if !threw || exists(10) { problems.append("a throw: rethrown \(threw), file \(exists(10))") }

    let (cancelURL, cancelMedia) = movie(11)
    let cancelled = try? DeviceTranscriptCache.heard(
        span(11, cancelURL, 0, 6), language: "en-US", media: cancelMedia, in: cache,
        cancelled: { true }, recognize: counting)
    if cancelled?.cached != false || exists(11) {
        problems.append("cancelled: file \(exists(11))")
    }

    let (changeURL, changeMedia) = movie(12)
    let changed = try? DeviceTranscriptCache.heard(
        span(12, changeURL, 0, 6), language: "en-US", media: changeMedia, in: cache,
        cancelled: { false },
        recognize: {
            try? Data(repeating: 7, count: 1001).write(to: changeURL)
            return counting()
        })
    if changed?.cached != false || exists(12) {
        problems.append("the file changed during the run: file \(exists(12))")
    }
    row("P8", problems.isEmpty,
        problems.isEmpty
            ? "1st ran and stored, 2nd cached with 1 run; no cacheDir ran twice and wrote "
                + "nothing; a throw rethrown, a cancel and a changed file stored nothing"
            : problems.joined(separator: "; "))
}
try? FileManager.default.removeItem(at: cacheFolder)

let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])) ?? Data()
print(text(answer))
