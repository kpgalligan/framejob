// Cut by transcript CT-4 (spec §11 TR-11): the value rows of
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
    let got = TranscriptReader.deviceWords(runs, for: clip)
    // start + t / speed: 0.25 s → 675000, 0.5 s → 750000, 1.0 s → 900000,
    // 3.75 s → 1725000; 4.0 s lands on the clip's end (1800000) and is
    // dropped; 4.5 s is clamped to it.
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

let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])) ?? Data()
print(text(answer))
