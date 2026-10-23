// Cut by transcript CT-2 (spec §11 TR-7, TR-9): the value rows of
// `fillers_proof.py`, compiled as `main.swift` over `app/Sources` (or a
// mutant's copy of it) through `swift_build.build()`. Prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`, on stdout. No network, no app, no
// defaults; the only disk it touches is a temporary folder it removes.

import Foundation

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func text(_ data: Data?) -> String { data.flatMap { String(data: $0, encoding: .utf8) } ?? "" }

typealias Span = SilenceDetector.Span

let G = FillerDetector.grid
let fps30 = Fps(num: 30, den: 1)

let fillerOptions = TranscriptOptions(
    speechModels: TranscriptOptions.shippedModels, languageCode: nil, speakerLabels: false,
    keytermsPrompt: [])
var plainOptions = fillerOptions
plainOptions.disfluencies = false

func header(_ options: TranscriptOptions) -> MediaTranscript.Header {
    MediaTranscript.Header(
        provider: MediaTranscript.provider, transcriptID: "t_fillers", requested: options,
        speechModelUsed: "universal-3-5-pro", languageCode: "en_us", languageConfidence: 0.99,
        audioDuration: 6, extractedSeconds: 5.9, uploadedFormat: "flac",
        audioTrackStartMs: 0, fetchedAt: "2026-10-22T00:00:00Z", remoteDeleted: true)
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

func input(
    clips: [FillerDetector.ClipWords], neighbours: [FillerDetector.ClipWords],
    nests: [SilenceDetector.NestExtent] = [], walls: [Span] = []
) -> FillerDetector.Input {
    FillerDetector.Input(
        fps: fps30, scope: .selected, clips: clips, needsTranscript: [], skipped: [], locked: [],
        neighbours: neighbours, nests: nests, walls: walls)
}

func spans(_ outcome: FillerDetector.Outcome) -> [[Ticks]] {
    outcome.spans.map { [$0.start, $0.end] }
}

// MARK: - P1: gridded widens outward when the neighbours are far

do {
    let run = FillerDetector.Run(
        words: ["um"], source: Span(start: 1_470_000, end: 1_770_000), previousEnd: 1_000_000,
        nextStart: 2_000_000)
    let got = FillerDetector.gridded(run, grid: G)
    let want = Span(start: 76 * 19_200, end: 93 * 19_200)
    row("P1", G == 19_200 && got == want,
        "grid \(G); [1470000, 1770000) with neighbours 1000000 / 2000000 → "
            + "\(String(describing: got)), want [\(want.start), \(want.end))")
}

// MARK: - P2: a neighbour inside the outward grid point bounds it

do {
    let run = FillerDetector.Run(
        words: ["um"], source: Span(start: 1_470_000, end: 1_770_000), previousEnd: 1_465_000,
        nextStart: 1_780_000)
    let got = FillerDetector.gridded(run, grid: G)
    // ceil(1465000 / G) = 77, floor(1780000 / G) = 92.
    let want = Span(start: 77 * 19_200, end: 92 * 19_200)
    row("P2", got == want,
        "[1470000, 1770000) with neighbours 1465000 / 1780000 → \(String(describing: got)), "
            + "want [\(want.start), \(want.end))")
}

// MARK: - P3: runs

do {
    let window = job(clip: 1)
    // Served out of order: the runs are taken in (start, end) order.
    let one = FillerDetector.runs(
        of: file([("word", 1200, 1500), ("Uh", 720, 900), ("So", 200, 420), ("um,", 480, 700),
                  ("er", 950, 1100)]), in: window)
    let wantOne = [
        FillerDetector.Run(
            words: ["um,", "Uh", "er"], source: Span(start: 288_000, end: 660_000),
            previousEnd: 252_000, nextStart: 720_000)
    ]
    let two = FillerDetector.runs(
        of: file([("um", 100, 300), ("word", 400, 700), ("uh", 800, 1000)]), in: window)
    let wantTwo = [
        FillerDetector.Run(
            words: ["um"], source: Span(start: 60_000, end: 180_000), previousEnd: 0,
            nextStart: 240_000),
        FillerDetector.Run(
            words: ["uh"], source: Span(start: 480_000, end: 600_000), previousEnd: 420_000,
            nextStart: 6_000_000),
    ]
    let none = FillerDetector.runs(of: file([("umbrella", 100, 500)]), in: window)
    row("P3", one == wantOne && two == wantTwo && none.isEmpty,
        "\"um, Uh er\" → \(one); \"um word uh\" → \(two); \"umbrella\" → \(none)")
}

// MARK: - P4: placed — start 1 s, in 0.5 s, speed 2, 30 fps

do {
    let clip = job(
        clip: 1, sourceIn: 300_000, sourceLength: 6_000_000, start: 600_000,
        duration: 3_000_000, speed: 2)
    let got = FillerDetector.placed(
        Span(start: 76 * 19_200, end: 93 * 19_200), in: clip, fps: fps30)
    // 600000 + (1459200 − 300000) / 2 = 1179600 → up to 1180000;
    // 600000 + (1785600 − 300000) / 2 = 1342800 → down to 1340000.
    let want = Span(start: 1_180_000, end: 1_340_000)
    row("P4", got == want,
        "[1459200, 1785600) placed → \(String(describing: got)), want [1180000, 1340000)")
}

// MARK: - P5: a 40 ms filler squeezed between words is too short

do {
    let words = file([("before", 0, 1010), ("um", 1010, 1050), ("after", 1050, 2000)])
    let clip = FillerDetector.ClipWords(job: job(clip: 1), file: words)
    let outcome = FillerDetector.detect(input(clips: [clip], neighbours: [clip]))
    let want = [FillerDetector.Dropped(clip: 1, words: ["um"], reason: .tooShort)]
    row("P5", outcome.spans.isEmpty && outcome.candidates.isEmpty && outcome.dropped == want,
        "spans \(spans(outcome)), dropped \(outcome.dropped)")
}

// MARK: - P6, P7: what drops a candidate

let ownWords = file([("Hello", 0, 1000), ("um", 1500, 1800), ("world", 2500, 3000)])
let own = FillerDetector.ClipWords(
    job: job(clip: 1, media: 1, sourceLength: 3_000_000, duration: 3_000_000), file: ownWords)
let other = FillerDetector.ClipWords(
    job: job(clip: 2, media: 2, sourceLength: 3_000_000, duration: 3_000_000),
    file: file([("everyone", 1400, 1700)]))
// The candidate alone: [883200, 1094400) on the grid, [900000, 1080000) in frames.
let alone = FillerDetector.detect(input(clips: [own], neighbours: [own]))

do {
    let inScope = FillerDetector.detect(input(clips: [own, other], neighbours: [own, other]))
    let outOfScope = FillerDetector.detect(input(clips: [own], neighbours: [own, other]))
    // The candidate's OWN clip, with a word over the run: never a conflict.
    let ownOver = FillerDetector.ClipWords(job: own.job, file: file([("talk", 1500, 1800)]))
    let self_ = FillerDetector.detect(input(clips: [own], neighbours: [own, ownOver]))
    let want = [
        FillerDetector.Dropped(
            clip: 1, words: ["um"], reason: .overlapsWord(clip: 2, text: "everyone"))
    ]
    row("P6",
        spans(alone) == [[900_000, 1_080_000]] && inScope.spans.isEmpty
            && inScope.dropped == want && outOfScope.spans.isEmpty && outOfScope.dropped == want
            && spans(self_) == [[900_000, 1_080_000]],
        "alone \(spans(alone)); clip 2 in scope → \(spans(inScope)) \(inScope.dropped); "
            + "only a neighbour → \(spans(outOfScope)) \(outOfScope.dropped); own clip's word "
            + "→ \(spans(self_))")
}

do {
    let nest = FillerDetector.detect(
        input(
            clips: [own], neighbours: [own],
            nests: [SilenceDetector.NestExtent(clip: 9, span: Span(start: 1_000_000, end: 2_000_000))]))
    let wall = FillerDetector.detect(
        input(clips: [own], neighbours: [own], walls: [Span(start: 0, end: 950_000)]))
    row("P7",
        nest.spans.isEmpty
            && nest.dropped == [FillerDetector.Dropped(clip: 1, words: ["um"], reason: .nest(clip: 9))]
            && wall.spans.isEmpty
            && wall.dropped == [FillerDetector.Dropped(clip: 1, words: ["um"], reason: .transition)],
        "nest → \(spans(nest)) \(nest.dropped); wall → \(spans(wall)) \(wall.dropped)")
}

// MARK: - P8: which marker a transcript is read through

let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("fillers-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
do {
    let movie = folder.appendingPathComponent("speech.mov")
    try? Data(repeating: 7, count: 1000).write(to: movie)
    let media = MediaSnapshot(
        id: 7, path: movie.path, duration: 6_000_000, hasVideo: true, hasAudio: true)
    let cache = folder.appendingPathComponent("cache", isDirectory: true)
    func seed(_ options: TranscriptOptions) -> Bool {
        guard let stamp = MediaImporter.CacheStamp.stamp(for: media, url: movie) else {
            return false
        }
        return MediaTranscript.write(file([("um", 100, 300)], options), for: 7, in: cache)
            && MediaTranscript.writeStamp(
                TranscriptStamp(source: stamp, options: options), for: 7, in: cache)
    }
    let seededTrue = seed(fillerOptions)
    let withFillers = FillerDetector.fillersFile(for: media, url: movie, in: cache) != nil
    let seededFalse = seed(plainOptions)
    let withoutFillers = FillerDetector.fillersFile(for: media, url: movie, in: cache) != nil
    let forCaptions = FillerDetector.transcriptFile(
        for: media, url: movie, in: cache, use: .captions) != nil
    let reseeded = seed(fillerOptions)
    try? Data(repeating: 7, count: 1001).write(to: movie)
    let changedSource = FillerDetector.fillersFile(for: media, url: movie, in: cache) != nil
    row("P8",
        seededTrue && seededFalse && reseeded && withFillers && !withoutFillers && forCaptions
            && !changedSource,
        "disfluencies true → \(withFillers ? "file" : "nil"); false → "
            + "\(withoutFillers ? "file" : "nil"); false for captions → "
            + "\(forCaptions ? "file" : "nil"); changed source → "
            + "\(changedSource ? "file" : "nil")")
}
try? FileManager.default.removeItem(at: folder)

// MARK: - P9: a locked track gives no candidates

do {
    let snapshot = ProjectSnapshot(
        tracks: [TrackSnapshot(id: 1, locked: true), TrackSnapshot(id: 2)],
        clips: [
            ClipSnapshot(id: 10, track: 1, duration: 600_000),
            ClipSnapshot(id: 11, track: 2, duration: 600_000),
            ClipSnapshot(id: 12, track: 99, duration: 600_000),
        ])
    let (kept, locked) = FillerDetector.onUnlockedTracks(snapshot.clips, in: snapshot)
    row("P9", kept.map(\.id) == [11, 12] && locked == [10],
        "kept \(kept.map(\.id)), locked \(locked)")
}

let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])) ?? Data()
print(text(answer))
