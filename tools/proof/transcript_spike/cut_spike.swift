// Road map "creator-jobs" TX3a, spike TX-S3 — cut edges: where should a
// word's cut fall, when on-device word ranges tile the audio and start 270 ms
// early?
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, through `tools/proof/swift_build.py`, by `cut_spike.py`:
//
//   cut-spike <request.json> <out.json>
//
// The request names a package's `cache` folder, a `media` id, its words'
// `engine` and the words (`source`, `source_end`, in SOURCE ticks: the clip
// sits at 0 at ×1, so a timeline tick is a source tick). The voice cache and
// the peaks are read through the app's own `MediaImporter.loadSpeech` and
// `loadPeaks`. Each rule — E0, E1, and E2 at guards of 0, 32, 64 and 96 ms —
// runs through the app's own `TranscriptCut.sourceOnsets` (window from 0);
// each onset is answered with the voice cell it falls in (non-speech under
// `defaultVoiceConfidence`), whether the peak there is under −40 dBFS (0.01
// of full scale), and, for E2, whether it moved off E1's onset (a run found).
import Foundation

let args = CommandLine.arguments
guard args.count == 3,
    let data = FileManager.default.contents(atPath: args[1]),
    let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let cache = request["cache"] as? String, let media = request["media"] as? Int,
    let engineName = request["engine"] as? String,
    let engine = TranscriptionEngine(rawValue: engineName),
    let rows = request["words"] as? [[String: Any]]
else {
    FileHandle.standardError.write(Data("usage: cut-spike <request.json> <out.json>\n".utf8))
    exit(2)
}
let cacheDir = URL(fileURLWithPath: cache)
let id = UInt32(media)
let words = rows.map {
    TimelineTranscript.SourceWord(
        text: $0["text"] as? String ?? "", source: Ticks(($0["source"] as? Int) ?? 0),
        sourceEnd: Ticks(($0["source_end"] as? Int) ?? 0), speaker: nil)
}
let speech = MediaImporter.loadSpeech(for: id, in: cacheDir)
let peaks = MediaImporter.loadPeaks(for: id, in: cacheDir)
let threshold = Float(SilenceDetector.Settings.defaultVoiceConfidence)
let millisecond = ReelTime.perSecond / 1000

let rules: [(String, TranscriptCut.Rule)] = [
    ("E0", .e0), ("E1", .e1),
    ("E2-0", .e2(guardTicks: 0)), ("E2-32", .e2(guardTicks: 32 * millisecond)),
    ("E2-64", .e2(guardTicks: 64 * millisecond)), ("E2-96", .e2(guardTicks: 96 * millisecond)),
]
var e1: [Ticks] = []
var answers: [String: Any] = [:]
for (name, rule) in rules {
    let onsets = TranscriptCut.sourceOnsets(
        words, windowStart: 0, lead: TranscriptCut.lead(engine, rule: rule), speech: speech,
        rule: rule)
    if name == "E1" { e1 = onsets }
    let cells = onsets.map { onset -> Any in
        guard let speech, onset >= 0 else { return NSNull() }
        let cell = Int(onset / MediaSpeech.chunkTicks)
        return cell < speech.count ? speech[cell] < threshold : NSNull()
    }
    let quiet = onsets.map { onset -> Any in
        guard let peaks, onset >= 0 else { return NSNull() }
        let bucket = Int(onset / MediaPeaks.bucketTicks)
        return bucket < peaks.count ? peaks[bucket] < 0.01 : NSNull()
    }
    answers[name] = ["onsets": onsets, "nonspeech": cells, "quiet": quiet]
}
for (name, _) in rules where name.hasPrefix("E2") {
    guard var row = answers[name] as? [String: Any], let onsets = row["onsets"] as? [Ticks]
    else { continue }
    row["from_run"] = zip(onsets, e1).map { $0 != $1 }
    answers[name] = row
}
let out: [String: Any] = [
    "rules": answers, "speech_cells": speech?.count ?? NSNull(), "peaks": peaks?.count ?? NSNull(),
    "chunk_ticks": MediaSpeech.chunkTicks, "lead": CaptionPages.lead(for: engine),
    "shipped_guard": TranscriptCut.shipped.guardTicks,
]
let encoded = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
try encoded.write(to: URL(fileURLWithPath: args[2]))
print("cut-spike: \(words.count) words, speech \(speech?.count ?? -1) cells, peaks \(peaks?.count ?? -1)")
