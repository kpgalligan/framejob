// tools/proof/playback_audio_probe.swift — the in-process instrument behind
// `playback_audio_proof.py` (issue batch B11: #64, #65). Compiled with every
// file in `app/Sources` but `main.swift` over `harness/build.sh`'s swiftc line,
// copied in as `main.swift`, with `Blank.mp4` beside the binary (the builder's
// placeholder track for an audio-only plan).
//
//     playback_audio_probe <work-dir>
//
// Every fixture is made from ops on an untitled `ProjectDocument`
// (`source_mirror_probe.py`'s pattern); the M media files are written here by
// `AVAudioFile` into <work-dir>. One line `ANSWER {json}` on stdout, the rows
// `[{id, ok, detail}]`, and exit 0; a crash is the caller's to see.
//
// N  #64 — a reversed clip INSIDE a closed nest is analysed mirrored.
//    A 6 s audio media at a path that does not exist, its peaks cache
//    hand-written 1.0 over the first 3 s and 0 after (with its `PeaksStamp`
//    marker); a whole-file clip at 0, reversed, nested, the nest clip's track
//    locked (a locked nest is no wall, so its voice decides the spans). A
//    second document identical but forward.
//    N1 `MediaPeaks.reversedPivot` for the nested clip's segment in the PARENT
//       plan is the media's duration.
//    N2 level-mode `SilenceDetector.detect` with the nest closed equals the
//       same with it open; non-empty; every span inside [0, 3 s].
//    N3 CONTROL the forward document: pivot nil; closed equals open, inside
//       [3 s, 6 s].
//    N4 CONTROL the two documents' plan JSON is byte-identical.
// M  #65 — a metered composition track adds only while one of its OWN
//    sounding spans holds the playhead.
//    F1 one track: aac at 0, pcm at 3 s, a missing-path audio media at 6 s
//       (2 s each; the missing segment joins family 0). F2 aac at 0 on one
//       track, long (6 s) at 0 on another. Built by `CompositionBuilder.build
//       (…, metering: true)`; the sinks written with `store(…)`.
//    M1 F1 at 4 s: the WAV family alone. M2 F2 at 4 s: the long track alone.
//    M3 CONTROL F2 at 1 s: both count (peak 0.625). M4 F1 at 7 s (the missing clip): silent.
//    M5 F1: two meters; family 0 sounds over [0, 2 s), the other [3 s, 5 s).
import AVFoundation
import AppKit

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)

let SEC: Ticks = 600_000
let BUCKETS = 600  // 100 peaks buckets per source second, 6 s
var rows: [[String: Any]] = []

func row(_ id: String, _ ok: Bool, _ detail: String) {
    rows.append(["id": id, "ok": ok, "detail": detail])
}

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print("ANSWER " + String(decoding: data, as: UTF8.self))
    exit(0)
}

guard CommandLine.arguments.count == 2 else {
    row("N1", false, "usage: playback_audio_probe <work-dir>")
    finish()
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

func addMedia(_ document: ProjectDocument, _ path: String, _ duration: Ticks) -> MediaSnapshot? {
    document.performGroupedEdit(
        "Media",
        [
            .addMedia(
                descriptor: MediaDescriptor(
                    path: path, kind: .audio, duration: duration, hasVideo: false,
                    hasAudio: true))
        ])
    return document.project.snapshot.media.first { $0.path == path }
}

func clipAt(_ document: ProjectDocument, track: UInt32, start: Ticks) -> ClipSnapshot? {
    document.project.snapshot.clips.first { $0.track == track && $0.start == start }
}

func secs(_ t: Ticks) -> String { String(format: "%.3f s", Double(t) / Double(SEC)) }

func spansText(_ spans: [SilenceDetector.Span]) -> String {
    "[" + spans.map { "\(secs($0.start))–\(secs($0.end))" }.joined(separator: ", ") + "]"
}

// =========================================================================
// N — #64

struct NestFixture {
    let document: ProjectDocument
    let inner: UInt32
    let media: MediaSnapshot
}

func nestFixture(reversed: Bool) -> (NestFixture?, String) {
    let document = ProjectDocument()
    guard let track = document.project.snapshot.tracks.first?.id else {
        return (nil, "the blank project has no track")
    }
    guard let media = addMedia(document, "/nowhere/b11-nested-tone.wav", 6 * SEC) else {
        return (nil, "add_media added nothing")
    }
    document.performGroupedEdit("Clip", [.addClip(track: track, media: media.id, at: 0)])
    guard let clip = clipAt(document, track: track, start: 0) else {
        return (nil, "add_clip placed nothing at 0")
    }
    if reversed {
        document.performGroupedEdit("Reverse", [.setReversed(clip: clip.id, reversed: true)])
    }
    document.performGroupedEdit("Nest", [.nest(clips: [clip.id])])
    let snapshot = document.project.snapshot
    guard let nestClip = snapshot.clips.first(where: {
        if case .nest = $0.source { return true } else { return false }
    }) else { return (nil, "nest made no nest clip") }
    guard snapshot.nests.count == 1, let inner = snapshot.nests[0].clips.first,
        inner.source.isReversed == reversed
    else { return (nil, "the nest does not hold the one clip as made") }
    document.performGroupedEdit("Lock", [.setTrack(track: nestClip.track, locked: true)])

    // The peaks cache, as `source_mirror_probe.py` §2 writes it.
    guard let cache = document.cacheDirectory else { return (nil, "no cache directory") }
    var peaks = [Float](repeating: 0, count: BUCKETS)
    for i in 0..<(BUCKETS / 2) { peaks[i] = 1 }
    let peaksURL = cache.appendingPathComponent("peaks", isDirectory: true)
        .appendingPathComponent("\(media.id).bin")
    try? FileManager.default.createDirectory(
        at: peaksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    peaks.withUnsafeBufferPointer { raw in try? Data(buffer: raw).write(to: peaksURL) }
    let stamp = MediaImporter.CacheStamp(
        size: 0, modified: 0, duration: media.duration, width: media.width,
        height: media.height, hasVideo: media.hasVideo, hasAudio: media.hasAudio,
        thumbnailHeight: MediaImporter.thumbnailHeight,
        maxThumbnails: MediaImporter.maxThumbnails,
        peakBucketsPerSecond: MediaImporter.peakBucketsPerSecond)
    _ = MediaImporter.writeStamp(
        MediaImporter.PeaksStamp(stamp),
        to: MediaImporter.peaksMarkerURL(for: media.id, in: cache))
    guard MediaImporter.loadPeaks(for: media.id, in: cache)?.count == BUCKETS else {
        return (nil, "the hand-written peaks file did not read back")
    }
    return (NestFixture(document: document, inner: inner.id, media: media), "")
}

func segment(of clip: UInt32, in project: ReelProject) -> PlanSegment? {
    guard let plan = project.plan else { return nil }
    for track in plan.audioTracks {
        if let found = track.segments.first(where: { $0.clip == clip }) { return found }
    }
    return nil
}

/// (closed spans, open spans, pivot, why) — the nest closed, then opened.
func detectClosedAndOpen(_ fixture: NestFixture)
    -> ([SilenceDetector.Span], [SilenceDetector.Span], Ticks?, String)
{
    let document = fixture.document
    let settings = SilenceDetector.Settings(scope: .audible, mode: .level)
    guard let parentSegment = segment(of: fixture.inner, in: document.project) else {
        return ([], [], nil, "the parent plan has no audio segment for clip \(fixture.inner)")
    }
    let pivot = MediaPeaks.reversedPivot(for: parentSegment, in: document.project.snapshot)
    guard let closedInput = SilenceDetector.read(from: document) else {
        return ([], [], pivot, "read(from:) answered nil with the nest closed")
    }
    let closed = SilenceDetector.detect(closedInput, settings: settings).spans
    let snapshot = document.project.snapshot
    guard let nestClip = snapshot.clips.first(where: {
        if case .nest = $0.source { return true } else { return false }
    }), case .nest(let nestID) = nestClip.source else {
        return (closed, [], pivot, "no nest clip to open")
    }
    document.setNestPath(
        [NestScopeStep(nest: nestID, clip: nestClip.id)], playhead: 0, selection: [])
    guard document.nestPath.count == 1, let openInput = SilenceDetector.read(from: document)
    else { return (closed, [], pivot, "the nest did not open, or read(from:) answered nil") }
    let open = SilenceDetector.detect(openInput, settings: settings).spans
    return (closed, open, pivot, "")
}

let (reversedFixture, reversedWhy) = nestFixture(reversed: true)
let (forwardFixture, forwardWhy) = nestFixture(reversed: false)
if let fixture = reversedFixture {
    let planJSON = fixture.document.project.planJSON
    let (closed, open, pivot, why) = detectClosedAndOpen(fixture)
    row("N1", why.isEmpty && pivot == fixture.media.duration,
        "reversed clip \(fixture.inner) inside a closed nest: pivot "
            + "\(pivot.map { String($0) } ?? "nil"), media duration \(fixture.media.duration)"
            + (why.isEmpty ? "" : "; \(why)"))
    let inside = closed.allSatisfy { $0.start >= 0 && $0.end <= 3 * SEC }
    row("N2", why.isEmpty && closed == open && !closed.isEmpty && inside,
        "closed \(spansText(closed)) vs open \(spansText(open)); equal \(closed == open), "
            + "non-empty \(!closed.isEmpty), inside [0, 3 s] \(inside)"
            + (why.isEmpty ? "" : "; \(why)"))
    if let forward = forwardFixture {
        let forwardPlan = forward.document.project.planJSON
        row("N4", planJSON == forwardPlan && !planJSON.isEmpty,
            "(CONTROL) the reversed and the forward document's plan JSON: "
                + "\(planJSON.utf8.count) and \(forwardPlan.utf8.count) bytes, identical "
                + "\(planJSON == forwardPlan)")
    } else {
        row("N4", false, "(CONTROL) the forward fixture: \(forwardWhy)")
    }
} else {
    row("N1", false, "the reversed fixture: \(reversedWhy)")
    row("N2", false, "the reversed fixture: \(reversedWhy)")
    row("N4", false, "(CONTROL) the reversed fixture: \(reversedWhy)")
}
if let fixture = forwardFixture {
    let (closed, open, pivot, why) = detectClosedAndOpen(fixture)
    let inside = closed.allSatisfy { $0.start >= 3 * SEC && $0.end <= 6 * SEC }
    row("N3", why.isEmpty && pivot == nil && closed == open && !closed.isEmpty && inside,
        "(CONTROL) forward clip inside a closed nest: pivot "
            + "\(pivot.map { String($0) } ?? "nil"); closed \(spansText(closed)) vs open "
            + "\(spansText(open)); inside [3 s, 6 s] \(inside)"
            + (why.isEmpty ? "" : "; \(why)"))
} else {
    row("N3", false, "(CONTROL) the forward fixture: \(forwardWhy)")
}

// =========================================================================
// M — #65

/// Writes `seconds` of a 440 Hz tone through `AVAudioFile` with `settings`.
func writeTone(_ url: URL, settings: [String: Any], rate: Double, channels: AVAudioChannelCount,
               seconds: Double) -> String?
{
    try? FileManager.default.removeItem(at: url)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds))
    else { return "no buffer for \(url.lastPathComponent)" }
    buffer.frameLength = buffer.frameCapacity
    for channel in 0..<Int(channels) {
        guard let samples = buffer.floatChannelData?[channel] else { continue }
        for i in 0..<Int(buffer.frameLength) {
            samples[i] = 0.5 * Float(sin(2 * Double.pi * 440 * Double(i) / rate))
        }
    }
    do {
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
            interleaved: false)
        try file.write(from: buffer)
    } catch {
        return "\(url.lastPathComponent) would not write: \(error)"
    }
    return nil
}

let aacURL = work.appendingPathComponent("aac.m4a")
let pcmURL = work.appendingPathComponent("pcm.wav")
let longURL = work.appendingPathComponent("long.m4a")
let aacSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
]
let written = [
    writeTone(aacURL, settings: aacSettings, rate: 48_000, channels: 2, seconds: 3),
    writeTone(
        pcmURL,
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ], rate: 44_100, channels: 1, seconds: 3),
    writeTone(longURL, settings: aacSettings, rate: 48_000, channels: 2, seconds: 7),
].compactMap { $0 }

struct Built {
    let document: ProjectDocument
    let built: BuiltComposition
    let plan: CompositionPlan
}

/// A document from `placements` (track index, media path, declared duration,
/// start), built for metering.
func buildFixture(_ placements: [(track: Int, path: String, duration: Ticks, at: Ticks)])
    -> (Built?, String)
{
    let document = ProjectDocument()
    let tracksNeeded = (placements.map(\.track).max() ?? 0) + 1
    while document.project.snapshot.tracks.count < tracksNeeded {
        document.performGroupedEdit(
            "Track", [.addTrack(index: document.project.snapshot.tracks.count)])
    }
    let tracks = document.project.snapshot.tracks.map(\.id)
    for placement in placements {
        guard let media = addMedia(document, placement.path, placement.duration) else {
            return (nil, "add_media \(placement.path) added nothing")
        }
        document.performGroupedEdit(
            "Clip",
            [.addClip(track: tracks[placement.track], media: media.id, at: placement.at)])
        guard clipAt(document, track: tracks[placement.track], start: placement.at) != nil else {
            return (nil, "add_clip placed nothing at \(placement.at)")
        }
    }
    let project = document.project
    guard let plan = project.plan else { return (nil, "no plan") }
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(project, for: key)
    do {
        let built = try CompositionBuilder.build(
            plan: plan, planJSON: project.planJSON, urls: document.mediaURLs(), recipeKey: key,
            metering: true)
        return (Built(document: document, built: built, plan: plan), "")
    } catch {
        return (nil, "the build threw: \(error)")
    }
}

func store(_ meter: LevelMeterTrack, peak: Float, rms: Float) {
    meter.sink.store(peakLeft: peak, peakRight: peak, rmsLeft: rms, rmsRight: rms)
}

func matches(_ reading: LevelMeterReading, peak: Float, rms: Float) -> Bool {
    [reading.peakLeft - peak, reading.peakRight - peak, reading.rmsLeft - rms,
     reading.rmsRight - rms].allSatisfy { abs($0) <= 1e-6 }
}

func text(_ reading: LevelMeterReading) -> String {
    "peak \(reading.peakLeft)/\(reading.peakRight) rms \(reading.rmsLeft)/\(reading.rmsRight)"
}

func spanList(_ spans: [Range<Ticks>]) -> String {
    "[" + spans.map { "[\(secs($0.lowerBound)), \(secs($0.upperBound)))" }
        .joined(separator: ", ") + "]"
}

if !written.isEmpty {
    for id in ["M1", "M2", "M3", "M4", "M5"] {
        row(id, false, "the media did not write: \(written.joined(separator: "; "))")
    }
    finish()
}

let (f1, f1Why) = buildFixture([
    (0, aacURL.path, 2 * SEC, 0), (0, pcmURL.path, 2 * SEC, 3 * SEC),
    (0, work.appendingPathComponent("missing-b11.m4a").path, 2 * SEC, 6 * SEC),
])
if let f1 = f1, let planTrack = f1.plan.audioTracks.first {
    let meters = f1.built.meters
    let family0 = meters.first { $0.id == planTrack.id }
    let other = meters.first { $0.id != planTrack.id }
    if let family0 = family0, let other = other {
        store(family0, peak: 0.5, rms: 0.25)
        store(other, peak: 0.25, rms: 0.125)
        let at4 = LevelMeterTrack.mix(meters, at: 4 * SEC)
        row("M1", matches(at4, peak: 0.25, rms: 0.125),
            "F1 at 4 s: \(text(at4)); want the WAV family alone, 0.25/0.125")
        let at7 = LevelMeterTrack.mix(meters, at: 7 * SEC)
        row("M4", matches(at7, peak: 0, rms: 0) && at7.isSilent,
            "F1 at 7 s (the missing clip): \(text(at7)); want silent")
    } else {
        row("M1", false, "F1 has \(meters.count) meters, not family 0 and another")
        row("M4", false, "F1 has \(meters.count) meters, not family 0 and another")
    }
    let want0: [Range<Ticks>] = [0..<(2 * SEC)]
    let want1: [Range<Ticks>] = [(3 * SEC)..<(5 * SEC)]
    row("M5", meters.count == 2 && family0?.sounding == want0 && other?.sounding == want1,
        "F1: \(meters.count) meters; family 0 sounding "
            + "\(family0.map { spanList($0.sounding) } ?? "none"), the other "
            + "\(other.map { spanList($0.sounding) } ?? "none"); want [[0, 2 s)] and "
            + "[[3 s, 5 s)]")
} else {
    for id in ["M1", "M4", "M5"] { row(id, false, "F1: \(f1Why)") }
}

let (f2, f2Why) = buildFixture([
    (0, aacURL.path, 2 * SEC, 0), (1, longURL.path, 6 * SEC, 0),
])
if let f2 = f2, f2.plan.audioTracks.count == 2 {
    let meters = f2.built.meters
    let shortID = f2.plan.audioTracks.first { track in
        track.segments.contains { $0.duration == 2 * SEC }
    }?.id
    let short = meters.first { $0.id == shortID }
    let long = meters.first { $0.id != shortID }
    if let short = short, let long = long, meters.count == 2 {
        store(short, peak: 0.5, rms: 0.25)
        store(long, peak: 0.125, rms: 0.0625)
        let at4 = LevelMeterTrack.mix(meters, at: 4 * SEC)
        row("M2", matches(at4, peak: 0.125, rms: 0.0625),
            "F2 at 4 s: \(text(at4)); want the long track alone, 0.125/0.0625")
        let at1 = LevelMeterTrack.mix(meters, at: 1 * SEC)
        // Peaks add linearly and RMS in power (`LevelMeterReading.adding`).
        let bothRMS = Float(0.25 * 0.25 + 0.0625 * 0.0625).squareRoot()
        row("M3", matches(at1, peak: 0.625, rms: bothRMS),
            "(CONTROL) F2 at 1 s: \(text(at1)); want both, 0.625/\(bothRMS)")
    } else {
        row("M2", false, "F2 has \(meters.count) meters, not one short and one long")
        row("M3", false, "(CONTROL) F2 has \(meters.count) meters")
    }
} else {
    row("M2", false, "F2: \(f2Why.isEmpty ? "not two audio tracks" : f2Why)")
    row("M3", false, "(CONTROL) F2: \(f2Why.isEmpty ? "not two audio tracks" : f2Why)")
}

finish()
