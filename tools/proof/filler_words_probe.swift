// Cut by transcript CT-1 (spec §11 TR-1, TR-2, TR-8): the value rows of
// `filler_words_proof.py`, compiled as `main.swift` over `app/Sources` (or a
// mutant's copy of it) through `swift_build.build()`. Prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`, on stdout. No network, no app, no
// defaults; the only disk it touches is a temporary folder it removes.

import Foundation

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func text(_ data: Data?) -> String { data.flatMap { String(data: $0, encoding: .utf8) } ?? "" }

func sorted<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return text(try? encoder.encode(value))
}

func object(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
}

let shippedOptions = TranscriptOptions(
    speechModels: TranscriptOptions.shippedModels, languageCode: nil, speakerLabels: false,
    keytermsPrompt: [])
var plainOptions = shippedOptions
plainOptions.disfluencies = false

let source = MediaImporter.CacheStamp(
    size: 1000, modified: 2000, duration: 6_000_000, width: 1920, height: 1080,
    hasVideo: true, hasAudio: true, thumbnailHeight: MediaImporter.thumbnailHeight,
    maxThumbnails: MediaImporter.maxThumbnails,
    peakBucketsPerSecond: MediaImporter.peakBucketsPerSecond)

// The old writer's markers, literally (`cloud_captions_probe.py`'s
// LEGACY_MARKER and NARROW_MARKER): no `disfluencies` key.
let legacyMarker = #"{"source":{"size":1000,"modified":2000,"duration":6000000,"width":1920,"height":1080,"hasVideo":true,"hasAudio":true,"thumbnailHeight":160,"maxThumbnails":600,"peakBucketsPerSecond":100},"provider":"assemblyai","speech_models":["universal-3-5-pro","universal-2"],"language_code":null,"speaker_labels":false,"keyterms_prompt":[]}"#
let narrowMarker = #"{"source":{"size":1000,"modified":2000,"duration":6000000,"hasAudio":true},"provider":"assemblyai","speech_models":["universal-3-5-pro","universal-2"],"language_code":null,"speaker_labels":false,"keyterms_prompt":[]}"#
// The old writer's `requested` block.
let oldRequested = #"{"keyterms_prompt":[],"language_code":null,"speaker_labels":false,"speech_models":["universal-3-5-pro","universal-2"]}"#

func header(_ options: TranscriptOptions) -> MediaTranscript.Header {
    MediaTranscript.Header(
        provider: MediaTranscript.provider, transcriptID: "t_filler", requested: options,
        speechModelUsed: "universal-3-5-pro", languageCode: "en_us", languageConfidence: 0.99,
        audioDuration: 6, extractedSeconds: 5.9, uploadedFormat: "flac",
        audioTrackStartMs: 0, fetchedAt: "2026-10-22T00:00:00Z", remoteDeleted: true)
}

// MARK: - W1: the wire body

do {
    let body = sorted(
        TranscriptRequest(audioURL: URL(string: "https://cdn.assemblyai.com/upload/x")!,
                          options: shippedOptions))
    let keys = Set(object(body).keys)
    let want: Set<String> = ["audio_url", "disfluencies", "speaker_labels", "speech_models"]
    row("W1", shippedOptions.disfluencies && keys == want && body.contains(#""disfluencies":true"#),
        "memberwise disfluencies=\(shippedOptions.disfluencies), body \(body)")
}

// MARK: - D1: the cache file's `requested`

do {
    let old = try? JSONDecoder().decode(TranscriptOptions.self, from: Data(oldRequested.utf8))
    let wordsJSON = Data(#"[{"text":"Hello","start":600,"end":1120,"confidence":0.98,"speaker":null}]"#.utf8)
    let fresh = try? MediaTranscript.File(header: header(shippedOptions), wordsJSON: wordsJSON)
    let freshBytes = (try? fresh?.encoded()) ?? nil
    let roundTrip = freshBytes.flatMap { try? MediaTranscript.File(data: $0) }
    let key = #""disfluencies":true,"#
    let freshText = text(freshBytes)
    let oldText = freshText.replacingOccurrences(of: key, with: "")
    let oldFile = try? MediaTranscript.File(data: Data(oldText.utf8))
    let pass = old?.disfluencies == false && old?.speechModels == TranscriptOptions.shippedModels
        && freshText.components(separatedBy: key).count == 2 && !oldText.contains("disfluencies")
        && oldFile?.header.requested.disfluencies == false && oldFile?.wordsJSON == wordsJSON
        && roundTrip == fresh && roundTrip?.header.requested.disfluencies == true
    row("D1", pass,
        "old requested disfluencies=\(String(describing: old?.disfluencies)), old file reads="
            + "\(oldFile != nil) disfluencies=\(String(describing: oldFile?.header.requested.disfluencies)), "
            + "new round-trips=\(roundTrip == fresh) disfluencies="
            + "\(String(describing: roundTrip?.header.requested.disfluencies))")
}

// MARK: - D2: the marker

do {
    let legacy = try? JSONDecoder().decode(TranscriptStamp.self, from: Data(legacyMarker.utf8))
    let narrow = try? JSONDecoder().decode(TranscriptStamp.self, from: Data(narrowMarker.utf8))
    let marker = sorted(TranscriptStamp(source: source, options: shippedOptions))
    let keys = Set(object(marker).keys)
    let want: Set<String> = [
        "disfluencies", "keyterms_prompt", "language_code", "provider", "source",
        "speaker_labels", "speech_models",
    ]
    let order = marker.hasPrefix(#"{"disfluencies":true,"keyterms_prompt":[],"language_code":null,"provider":"assemblyai","source":{"#)
        && marker.hasSuffix(#""speaker_labels":false,"speech_models":["universal-3-5-pro","universal-2"]}"#)
    row("D2", legacy?.disfluencies == false && narrow?.disfluencies == false && keys == want && order,
        "legacy=\(String(describing: legacy?.disfluencies)) narrow=\(String(describing: narrow?.disfluencies)), "
            + "new marker \(marker)")
}

// MARK: - S1: serves

let wanted = TranscriptStamp(source: source, options: shippedOptions)
let falseMarker = TranscriptStamp(source: source, options: plainOptions)
do {
    var failures: [String] = []
    if !falseMarker.serves(wanted, for: .captions) { failures.append("false marker does not serve captions") }
    if falseMarker.serves(wanted, for: .fillers) { failures.append("false marker serves fillers") }
    if !wanted.serves(wanted, for: .captions) { failures.append("true marker does not serve captions") }
    if !wanted.serves(wanted, for: .fillers) { failures.append("true marker does not serve fillers") }
    var changed: [(String, TranscriptOptions)] = []
    var options = shippedOptions
    options.speechModels = ["universal-2"]
    changed.append(("speech_models", options))
    options = shippedOptions
    options.languageCode = "de"
    changed.append(("language_code", options))
    options = shippedOptions
    options.speakerLabels = true
    changed.append(("speaker_labels", options))
    options = shippedOptions
    options.keytermsPrompt = ["Frame Job"]
    changed.append(("keyterms_prompt", options))
    var markers = changed.map { ($0.0, TranscriptStamp(source: source, options: $0.1)) }
    let other = MediaImporter.CacheStamp(
        size: 1001, modified: 2000, duration: 6_000_000, width: 1920, height: 1080,
        hasVideo: true, hasAudio: true, thumbnailHeight: MediaImporter.thumbnailHeight,
        maxThumbnails: MediaImporter.maxThumbnails,
        peakBucketsPerSecond: MediaImporter.peakBucketsPerSecond)
    markers.append(("source.size", TranscriptStamp(source: other, options: shippedOptions)))
    for (label, marker) in markers where marker.serves(wanted, for: .captions)
        || marker.serves(wanted, for: .fillers)
    {
        failures.append("\(label) changed still serves")
    }
    row("S1", failures.isEmpty, failures.isEmpty ? "false marker serves captions only; true serves both; "
        + "\(markers.count) changed markers serve neither" : failures.joined(separator: "; "))
}

// MARK: - S2 and E1: a marker on disk with no key

let folder = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("filler-words-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
do {
    let wordsJSON = Data(#"[{"text":"Hello","start":600,"end":1120,"confidence":0.98,"speaker":null}]"#.utf8)
    let file = try? MediaTranscript.File(header: header(plainOptions), wordsJSON: wordsJSON)
    let wrote = file.map { MediaTranscript.write($0, for: 7, in: folder) } ?? false
    let rawMarker = sorted(wanted).replacingOccurrences(of: #""disfluencies":true,"#, with: "")
    let markerWrote = (try? Data(rawMarker.utf8).write(
        to: MediaTranscript.markerURL(for: 7, in: folder), options: .atomic)) != nil
    let current = MediaTranscript.isCurrent(wanted, for: 7, in: folder)
    row("S2", wrote && markerWrote && !rawMarker.contains("disfluencies") && current,
        "file written=\(wrote), raw marker \(rawMarker), isCurrent=\(current)")

    let read = MediaTranscript.readStamp(for: 7, in: folder)
    func fate(_ refresh: Bool) -> CloudEstimate.Fate {
        CloudEstimate.fate(
            CloudEstimate.Facts(
                media: 7, name: "speech.mov", duration: 6_000_000, source: source, marker: read,
                cacheReads: MediaTranscript.read(for: 7, in: folder) != nil, deleteOwed: false),
            options: shippedOptions, refresh: refresh)
    }
    let plain = fate(false)
    let again = fate(true)
    row("E1", read != nil && plain == .cached && again == .upload(.refresh),
        "marker decodes=\(read != nil), fate=\(plain), under refresh=\(again)")
}
try? FileManager.default.removeItem(at: folder)

// MARK: - V1: the match rule

do {
    let fillers = ["Um,", "UH.", "Hmm?", "uh-huh", "M", "mhm", "Er,", "erm"]
    let words = ["umbrella", "uhm", "hum", "Ahh", "them", "I'm", "err", "here"]
    let missed = fillers.filter { !FillerWords.isFiller($0) }
    let taken = words.filter { FillerWords.isFiller($0) }
    row("V1", missed.isEmpty && taken.isEmpty,
        "fillers not matched \(missed), words matched \(taken)")
}

// MARK: - C1 and C2: captions with and without fillers

func wordJSON(_ words: [(String, Int, Int)]) -> Data {
    let parts = words.map { word -> String in
        let quoted = text(try? JSONSerialization.data(withJSONObject: [word.0]))
        return #"{"text":\#(quoted.dropFirst().dropLast()),"start":\#(word.1),"end":\#(word.2),"confidence":0.9,"speaker":null}"#
    }
    return Data(("[" + parts.joined(separator: ",") + "]").utf8)
}

let spoken: [(String, Int, Int)] = [
    ("So", 200, 420), ("um,", 480, 700), ("I", 760, 860), ("was", 900, 1100),
    ("thinking", 1150, 1600), ("Uh", 1900, 2100), ("that", 2200, 2400), ("we", 2450, 2600),
    ("could", 2650, 2900), ("er", 3000, 3200), ("start", 3300, 3600), ("early.", 3650, 4100),
    ("Hmm,", 4400, 4700), ("let", 4800, 4950), ("me", 5000, 5100), ("check.", 5150, 5600),
]
let job = Transcriber.Job(
    clip: 1, media: 1, name: "speech", source: URL(fileURLWithPath: "/dev/null"),
    sourceIn: 0, sourceLength: 6_000_000, start: 600_000, duration: 6_000_000, speed: 1)
let withBytes = wordJSON(spoken)
let withoutBytes = wordJSON(spoken.filter { !["um,", "Uh", "er", "Hmm,"].contains($0.0) })
let withFile = try? MediaTranscript.File(header: header(shippedOptions), wordsJSON: withBytes)
let withoutFile = try? MediaTranscript.File(header: header(shippedOptions), wordsJSON: withoutBytes)
let captioned = withFile.map { MediaTranscript.captionWords(for: job, in: $0) } ?? []
let all = withFile.map { MediaTranscript.words(for: job, in: $0) } ?? []
let reference = withoutFile.map { MediaTranscript.words(for: job, in: $0) } ?? []
do {
    let verbatim = (try? withFile?.encoded()).flatMap { text($0) }?.contains(#""text":"um,""#) ?? false
    row("C1", withFile != nil && all.count == spoken.count && !reference.isEmpty
            && captioned == reference && verbatim,
        "words \(all.count), caption words \(captioned.map(\.text)), reference \(reference.map(\.text)), "
            + "cache keeps fillers=\(verbatim)")
}
do {
    let span = job.start..<(job.start + job.duration)
    var differ: [String] = []
    for style in CaptionStyle.allCases {
        let request = CaptionPages.Request(style: style, canvas: CGSize(width: 1920, height: 1080))
        let mine = CaptionPages.cues(
            from: captioned, span: span, frame: 20_000, request: request, engine: .assemblyai,
            clip: 1, media: 1)
        let theirs = CaptionPages.cues(
            from: reference, span: span, frame: 20_000, request: request, engine: .assemblyai,
            clip: 1, media: 1)
        if mine.isEmpty || mine != theirs { differ.append("\(style.rawValue) (\(mine.count) vs \(theirs.count))") }
    }
    row("C2", differ.isEmpty,
        differ.isEmpty ? "cues equal for \(CaptionStyle.allCases.map(\.rawValue))"
            : "cues differ for \(differ)")
}

let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])) ?? Data()
print(text(answer))
