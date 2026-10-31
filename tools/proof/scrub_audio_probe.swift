// tools/proof/scrub_audio_probe.swift — the in-process instrument behind
// `scrub_audio_probe.py` (road map "audio" AP13, spec §11 AU-130…AU-136).
// Compiled with every file in `app/Sources` but `main.swift` through
// `swift_build.py`'s line, copied in as `main.swift`, with `Blank.mp4` beside
// the binary (the builder's placeholder track for an audio-only plan).
//
//     scrub_audio_probe <work-dir>
//
// Fixtures are 48 kHz stereo float WAVs of seeded noise written by
// `AVAudioFile` into <work-dir>; projects are made from ops on an untitled
// `ProjectDocument`, with `AudioDSPSource` published for the key. One line
// per row, `ok <ID> — <detail>` or `FAIL <ID> — <detail>`; no app is launched.
//
// G  the scheduler and the window (`ScrubGrains`, `ScrubGrainScheduler`)
//    G1 a mid-timeline grain: 3,840 frames from the playhead (C1 reads that length)
//    G2 the window: edges < 1e-3, 1 between, symmetric, step ≤ π/480; a windowed DC grain
//    G3 a 1 s forward drag at 60 Hz on a 30 fps grid: back to back, the playhead, the lead
//    G4 a 0.5 s hold on the last grain's frame: no grain, the last ends ≤ 0.12 s after the hold began
//    G5 end() clears; a press on the last grain's frame after end(); a leftward drag
//    G6 near the end: shortened to the end; under 480 frames, at or past the end: none
//    G7 the same snapped frame twice in one scrub: one grain
// C  the reader against the export's float read (`ExportWriter.audioReadOutput`)
//    C1 three tracks (volume, pan, fade-in, a duck, a muted track) at three starts, ≤ 1e-5;
//       a grain inside the duck's attack reported against the export, not scored
//    C2 a gap after a trimmed clip: zero from the clip's end, the export's read before it
//    C3 a compressor and noise reduction: the scheduler's adjacent grains on one build
//       each equal a cold read on a fresh build (≤ 1e-5); the warm RMS is reported
// E  `ScrubAudio`'s queue
//    E1 a recording sink: the grains played are read × window at the scheduler's starts
//    E2 a sink whose first play blocks; three more asked, end(), release: one played
//    E3 one build per player composition object
//    E4 a composition change on a move with no grain is built before the next scrub
//    E5 a composition change on a grain dropped by end() is still built
import AVFoundation
import AppKit

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)

let SEC: Ticks = 600_000
let FPS = Fps(num: 30, den: 1)
let GRAIN_SECONDS = Double(ScrubGrains.frames) / Double(ScrubGrains.sampleRate)

func row(_ id: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "ok" : "FAIL") \(id) — \(detail)")
}

guard CommandLine.arguments.count == 2 else {
    row("G1", false, "usage: scrub_audio_probe <work-dir>")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

func ticks(_ seconds: Double) -> Ticks { Ticks((seconds * Double(SEC)).rounded()) }
func snap(_ seconds: Double) -> Ticks { ReelTime.snapToFrame(ticks(seconds), fps: FPS) }
func secs(_ t: Ticks) -> String { String(format: "%.4f s", Double(t) / Double(SEC)) }
func frameOf(_ t: Ticks) -> Int { ExportAudioEnd.frames(ofTicks: t) }

// =========================================================================
// G — the scheduler and the window

do {
    var s = ScrubGrainScheduler()
    let g = s.move(to: 3 * SEC, duration: 6 * SEC, now: 10)
    row("G1", g?.frames == ScrubGrains.frames && g?.start == 3 * SEC && g?.at == 10 && s.isActive,
        "grain at 3 s of 6 s: start \(g.map { secs($0.start) } ?? "none"), frames "
            + "\(g.map { String($0.frames) } ?? "none"), at \(g.map { String($0.at) } ?? "none"); "
            + "active \(s.isActive)")
}

do {
    let n = ScrubGrains.frames
    let gains = (0..<n).map { ScrubGrains.gain(at: $0, of: n) }
    let edges = gains[0] < 1e-3 && gains[n - 1] < 1e-3
    let middle = (ScrubGrains.fadeFrames..<(n - ScrubGrains.fadeFrames)).allSatisfy { gains[$0] == 1 }
    let symmetric = (0..<n).allSatisfy { gains[$0] == gains[n - 1 - $0] }
    var step: Float = 0
    for i in 1..<n { step = max(step, abs(gains[i] - gains[i - 1])) }
    let stepOK = Double(step) <= Double.pi / 480 + 1e-7
    var left = [Float](repeating: 1, count: n)
    var right = [Float](repeating: 1, count: n)
    ScrubGrains.window(&left, &right)
    let dc = left[0] <= 1e-3 && left[n - 1] <= 1e-3 && right[0] <= 1e-3 && right[n - 1] <= 1e-3
    row("G2", edges && middle && symmetric && stepOK && dc,
        "gain[0] \(gains[0]), gain[n−1] \(gains[n - 1]); 1 across the middle \(middle); "
            + "symmetric \(symmetric); max step \(step) (π/480 = \(Float.pi / 480)); windowed DC "
            + "first/last \(left[0])/\(left[n - 1])")
}

do {
    // 1 s forward at 60 Hz on a 30 fps grid.
    var s = ScrubGrainScheduler()
    var grains: [(grain: ScrubGrain, playhead: Ticks)] = []
    var problems: [String] = []
    for k in 0...60 {
        let now = 100.0 + Double(k) / 60
        let playhead = snap(1.0 + Double(k) / 60)
        let queued = s.queuedUntil - now
        if let g = s.move(to: playhead, duration: 6 * SEC, now: now) {
            if !grains.isEmpty && queued > ScrubGrains.lead + 1e-9 {
                problems.append("asked at \(k) with \(queued) s queued")
            }
            if g.start != playhead { problems.append("start \(secs(g.start)) ≠ \(secs(playhead))") }
            grains.append((g, playhead))
        }
    }
    for i in 1..<max(1, grains.count) {
        let want = grains[i - 1].grain.at + GRAIN_SECONDS
        if abs(grains[i].grain.at - want) > 1e-9 {
            problems.append("grain \(i) at \(grains[i].grain.at), want \(want)")
        }
    }
    row("G3", grains.count >= 10 && problems.isEmpty,
        "\(grains.count) grains in a 1 s drag (back to back at 80 ms is about 12); "
            + (problems.isEmpty ? "each at the last one's end, each from its playhead, none with more "
                + "than the lead queued" : problems.prefix(4).joined(separator: "; ")))
}

do {
    // Half a second of moving at 60 Hz, then on to the next move that is
    // granted: the hand stops there, on a frame that was played. (A hand that
    // stops on a frame the lead rule passed over gets that frame's one grain
    // first, which is AU-132's rule and not a hold.)
    var s = ScrubGrainScheduler()
    var lastEnd = 0.0
    var k = 0
    var holdBegan = 0.0
    var held: Ticks = 0
    while k <= 30 || held == 0 {
        let now = 200.0 + Double(k) / 60
        let playhead = snap(1.0 + Double(k) / 60)
        if let g = s.move(to: playhead, duration: 6 * SEC, now: now) {
            lastEnd = g.at + Double(g.frames) / Double(ScrubGrains.sampleRate)
            if k >= 30 { (holdBegan, held) = (now, playhead) }
        }
        k += 1
    }
    var during = 0
    for j in 1...30 {  // hold still for 0.5 s
        if s.move(to: held, duration: 6 * SEC, now: holdBegan + Double(j) / 60) != nil { during += 1 }
    }
    row("G4", during == 0 && lastEnd - holdBegan <= 0.12 + 1e-9,
        "\(during) grains during a 0.5 s hold; the last grain ends "
            + String(format: "%.4f", lastEnd - holdBegan) + " s after the hold began (≤ 0.12)")
}

do {
    var s = ScrubGrainScheduler()
    var last: ScrubGrain?
    for k in 0...12 {
        if let g = s.move(to: snap(2.0 + Double(k) / 60), duration: 6 * SEC, now: 300 + Double(k) / 60) {
            last = g
        }
    }
    s.end()
    let cleared = !s.isActive && s.lastStart == nil
    var detail = "after end(): active \(s.isActive), lastStart \(s.lastStart.map(secs) ?? "nil")"
    var ok = cleared && last != nil
    if let last = last {
        let pressAt = s.queuedUntil + 0.01
        let press = s.move(to: last.start, duration: 6 * SEC, now: pressAt)
        let full = press?.frames == ScrubGrains.frames && press?.start == last.start && s.isActive
        detail += "; a press on \(secs(last.start)) once the queue ran out: "
            + "\(press.map { "\($0.frames) frames from \(secs($0.start))" } ?? "no grain"), active \(s.isActive)"
        ok = ok && full
        // A leftward drag at 60 Hz.
        var left: [(ScrubGrain, Ticks)] = []
        for k in 1...30 {
            let playhead = snap(Double(last.start) / Double(SEC) - Double(k) / 60)
            if let g = s.move(to: playhead, duration: 6 * SEC, now: pressAt + Double(k) / 60) {
                left.append((g, playhead))
            }
        }
        let forward = left.allSatisfy { $0.0.start == $0.1 && $0.0.frames == ScrubGrains.frames }
        detail += "; leftward \(left.count) grains, each from its playhead with full forward length \(forward)"
        ok = ok && !left.isEmpty && forward
    }
    row("G5", ok, detail)
}

do {
    let duration = 6 * SEC
    var a = ScrubGrainScheduler()
    let near = duration - ticks(0.05)
    let shortened = a.move(to: near, duration: duration, now: 400)
    let wantFrames = frameOf(duration - near)
    var b = ScrubGrainScheduler()
    let tooShort = b.move(to: duration - ticks(0.009), duration: duration, now: 400)
    var c = ScrubGrainScheduler()
    let atEnd = c.move(to: duration, duration: duration, now: 400)
    var d = ScrubGrainScheduler()
    let past = d.move(to: duration + SEC, duration: duration, now: 400)
    row("G6", shortened?.frames == wantFrames && wantFrames == 2_400 && tooShort == nil
        && atEnd == nil && past == nil,
        "0.05 s before the end: \(shortened.map { String($0.frames) } ?? "none") frames "
            + "(duration − start = \(wantFrames)); 432 frames left: \(tooShort == nil ? "none" : "a grain"); "
            + "at the end: \(atEnd == nil ? "none" : "a grain"); past it: \(past == nil ? "none" : "a grain")")
}

do {
    var s = ScrubGrainScheduler()
    let first = s.move(to: snap(1.5), duration: 6 * SEC, now: 500)
    let second = s.move(to: snap(1.5), duration: 6 * SEC, now: 501)
    let grains = [first, second].compactMap { $0 }.count
    row("G7", grains == 1 && first != nil,
        "the same snapped frame twice in one scrub, a second apart (the queue long empty): "
            + "\(grains) grain(s)")
}

// =========================================================================
// Fixtures

/// Seeded noise (a 32-bit LCG), stereo, 48 kHz float, at `amplitude`.
func writeNoise(_ url: URL, seed: UInt32, seconds: Double, amplitude: Float) -> String? {
    try? FileManager.default.removeItem(at: url)
    let rate = 48_000.0
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds))
    else { return "no buffer for \(url.lastPathComponent)" }
    buffer.frameLength = buffer.frameCapacity
    var state = seed
    func next() -> Float {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
    for i in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![0][i] = amplitude * next()
        buffer.floatChannelData![1][i] = amplitude * next()
    }
    do {
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    } catch {
        return "\(url.lastPathComponent) would not write: \(error)"
    }
    return nil
}

let noiseA = work.appendingPathComponent("noise-a.wav")
let noiseB = work.appendingPathComponent("noise-b.wav")
let noiseC = work.appendingPathComponent("noise-c.wav")
let written = [
    writeNoise(noiseA, seed: 1, seconds: 6, amplitude: 0.4),
    writeNoise(noiseB, seed: 2, seconds: 6, amplitude: 0.3),
    writeNoise(noiseC, seed: 3, seconds: 6, amplitude: 0.5),
].compactMap { $0 }

struct Fixture {
    let document: ProjectDocument
    let key: Int
    var project: ReelProject { document.project }
    var source: ScrubSource? {
        guard let plan = project.plan else { return nil }
        return ScrubSource(
            plan: plan, planJSON: project.planJSON, urls: document.mediaURLs(), recipeKey: key)
    }
}

func addMedia(_ document: ProjectDocument, _ url: URL) -> UInt32? {
    document.performGroupedEdit(
        "Media",
        [.addMedia(descriptor: MediaDescriptor(
            path: url.path, kind: .audio, duration: 6 * SEC, hasVideo: false, hasAudio: true))])
    return document.project.snapshot.media.first { $0.path == url.path }?.id
}

/// A document from `edit`, which gets the document and its track ids (as many as asked).
func fixture(tracks: Int, _ edit: (ProjectDocument, [UInt32]) -> String?) -> (Fixture?, String) {
    let document = ProjectDocument()
    while document.project.snapshot.tracks.count < tracks {
        document.performGroupedEdit("Track", [.addTrack(index: document.project.snapshot.tracks.count)])
    }
    let ids = document.project.snapshot.tracks.map(\.id)
    if let why = edit(document, ids) { return (nil, why) }
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(document.project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: document.project.snapshot), for: key)
    return (Fixture(document: document, key: key), "")
}

func clip(_ document: ProjectDocument, track: UInt32, at: Ticks) -> UInt32? {
    document.project.snapshot.clips.first { $0.track == track && $0.start == at }?.id
}

func place(_ document: ProjectDocument, _ url: URL, track: UInt32, at: Ticks) -> UInt32? {
    guard let media = addMedia(document, url) else { return nil }
    document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: at)])
    return clip(document, track: track, at: at)
}

func build(_ f: Fixture) -> BuiltComposition? {
    guard let source = f.source else { return nil }
    return try? CompositionBuilder.build(
        plan: source.plan, planJSON: source.planJSON, urls: source.urls, recipeKey: source.recipeKey,
        metering: false)
}

/// The export's float read of the whole timeline, placed by presentation time from 0.
func exportRead(_ built: BuiltComposition) -> (left: [Float], right: [Float])? {
    guard let reader = try? AVAssetReader(asset: built.composition) else { return nil }
    let output = ExportWriter.audioReadOutput(built)
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    guard reader.startReading() else { return nil }
    let total = frameOf(CompositionBuilder.ticks(built.composition.duration))
    var left = [Float](repeating: 0, count: total)
    var right = [Float](repeating: 0, count: total)
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let count = CMBlockBufferGetDataLength(block) / 8
        var raw = [Float](repeating: 0, count: 2 * count)
        _ = raw.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 8 * count, destination: $0.baseAddress!)
        }
        let offset = Int(CMTimeConvertScale(
            CMSampleBufferGetPresentationTimeStamp(sample), timescale: 48_000,
            method: .roundHalfAwayFromZero).value)
        for i in 0..<count where offset + i >= 0 && offset + i < total {
            left[offset + i] = raw[2 * i]
            right[offset + i] = raw[2 * i + 1]
        }
    }
    return reader.status == .completed ? (left, right) : nil
}

func maxDiff(_ a: (left: [Float], right: [Float]), _ b: (left: [Float], right: [Float]), from: Int = 0) -> Float {
    var worst: Float = 0
    for i in 0..<min(a.left.count, b.left.count) {
        worst = max(worst, abs(a.left[i] - b.left[from + i]), abs(a.right[i] - b.right[from + i]))
    }
    return worst
}

func slice(_ whole: (left: [Float], right: [Float]), from: Int, count: Int) -> (left: [Float], right: [Float]) {
    (Array(whole.left[from..<(from + count)]), Array(whole.right[from..<(from + count)]))
}

func peak(_ a: (left: [Float], right: [Float])) -> Float {
    max(a.left.map(abs).max() ?? 0, a.right.map(abs).max() ?? 0)
}

func windowed(_ a: (left: [Float], right: [Float])) -> (left: [Float], right: [Float]) {
    var l = a.left
    var r = a.right
    ScrubGrains.window(&l, &r)
    return (l, r)
}

if !written.isEmpty {
    for id in ["C1", "C2", "C3", "E1", "E2", "E3", "E4", "E5"] {
        row(id, false, "the fixtures did not write: \(written.joined(separator: "; "))")
    }
    exit(0)
}

// =========================================================================
// C — the reader

// C1: A (volume 0.5, pan −0.6, a 0.5 s fade-in) at 0; B ducking A for [2 s, 4 s) (the
// default 0.5 s attack and 1 s release: gain steps at 2.0, 2.5, 4.0 and 5.0 s); C muted.
let (c1, c1Why) = fixture(tracks: 3) { document, tracks in
    guard let a = place(document, noiseA, track: tracks[0], at: 0),
        let b = place(document, noiseB, track: tracks[1], at: 2 * SEC),
        place(document, noiseC, track: tracks[2], at: 0) != nil
    else { return "a clip did not land" }
    document.performGroupedEdit("Trim", [.trimEnd(clip: b, to: 4 * SEC)])
    document.performGroupedEdit(
        "Audio", [.setAudio(clips: [a], patch: AudioPatch(volume: 0.5, fadeIn: SEC / 2, pan: -0.6))])
    document.performGroupedEdit(
        "Duck", [.setAudio(clips: [b], patch: AudioPatch(duck: .some(DuckProps(level: 0.25))))])
    document.performGroupedEdit("Mute", [.setTrack(track: tracks[2], muted: true)])
    return nil
}
if let c1 = c1, let one = build(c1), let two = build(c1), let whole = exportRead(two) {
    var parts: [String] = []
    var ok = true
    for start in [SEC, 3 * SEC, ticks(5.3)] {
        guard let grain = ScrubGrains.read(one, start: start, frames: ScrubGrains.frames) else {
            ok = false
            parts.append("\(secs(start)): no read")
            continue
        }
        let at = frameOf(start)
        let diff = maxDiff(grain, whole, from: at)
        let level = peak(grain)
        ok = ok && diff <= 1e-5 && level > 0.01 && grain.left.count == ScrubGrains.frames
        parts.append("\(secs(start)): max |Δ| \(diff), peak \(level)")
    }
    // Reported, not scored: a grain that starts inside a gain ramp (the duck's
    // attack, 2.0–2.5 s) against the export at the same frames.
    let inRamp = ScrubGrains.read(one, start: ticks(2.25), frames: ScrubGrains.frames)
        .map { maxDiff($0, whole, from: frameOf(ticks(2.25))) }
    row("C1", ok, parts.joined(separator: "; ") + "; each read \(ScrubGrains.frames) frames; "
        + "(reported) a grain from 2.25 s, inside the duck's attack: max |Δ| "
        + (inRamp.map { String($0) } ?? "no read"))
} else {
    row("C1", false, c1Why.isEmpty ? "a build or the export read failed" : c1Why)
}

// C2: a clip trimmed to end at 2 s on 6 s media, a gap, a clip at 3 s.
let (c2, c2Why) = fixture(tracks: 1) { document, tracks in
    guard let a = place(document, noiseA, track: tracks[0], at: 0) else { return "the clip did not land" }
    document.performGroupedEdit("Trim", [.trimEnd(clip: a, to: 2 * SEC)])
    guard place(document, noiseB, track: tracks[0], at: 3 * SEC) != nil else { return "the second clip did not land" }
    return nil
}
if let c2 = c2, let one = build(c2), let two = build(c2), let whole = exportRead(two),
    let grain = ScrubGrains.read(one, start: ticks(1.96), frames: ScrubGrains.frames)
{
    let cut = frameOf(ticks(0.04))
    let tail = (cut..<ScrubGrains.frames).allSatisfy { grain.left[$0] == 0 && grain.right[$0] == 0 }
    let head = maxDiff(slice(grain, from: 0, count: cut), whole, from: frameOf(ticks(1.96)))
    let level = peak(slice(grain, from: 0, count: cut))
    row("C2", tail && head <= 1e-5 && level > 0.01,
        "from 1.96 s: frames \(cut)… exactly 0 \(tail); before the clip's end max |Δ| \(head) "
            + "against the export, peak \(level)")
} else {
    row("C2", false, c2Why.isEmpty ? "a build, the read or the export read failed" : c2Why)
}

// C3: the scheduler's own adjacent grains through a compressor and noise reduction.
let (c3, c3Why) = fixture(tracks: 1) { document, tracks in
    guard let a = place(document, noiseA, track: tracks[0], at: 0) else { return "the clip did not land" }
    document.performGroupedEdit(
        "DSP",
        [.setAudio(clips: [a], patch: AudioPatch(
            compressor: .some(CompressorProps(thresholdDb: -30, ratio: 6)), noiseReduction: 0.8))])
    return nil
}
if let c3 = c3, let warm = build(c3), let whole = build(c3).flatMap(exportRead) {
    var s = ScrubGrainScheduler()
    var starts: [ScrubGrain] = []
    for k in 0...90 {
        if let g = s.move(to: snap(1.0 + Double(k) / 60), duration: 6 * SEC, now: 600 + Double(k) / 60) {
            starts.append(g)
        }
    }
    var adjacent = true
    for i in 1..<starts.count {
        let previousEnd = starts[i - 1].start + ticks(GRAIN_SECONDS)
        if abs(starts[i].start - previousEnd) >= SEC / 10 { adjacent = false }
    }
    var worst: Float = 0
    var warmRMS: [Double] = []
    var failed = 0
    for (i, g) in starts.enumerated() {
        guard let hot = ScrubGrains.read(warm, start: g.start, frames: g.frames) else { failed += 1; continue }
        let against = slice(whole, from: frameOf(g.start), count: g.frames)
        var sum = 0.0
        for j in 0..<g.frames {
            let d = Double(hot.left[j] - against.left[j])
            let e = Double(hot.right[j] - against.right[j])
            sum += d * d + e * e
        }
        warmRMS.append((sum / Double(2 * g.frames)).squareRoot())
        guard i > 0 else { continue }
        guard let fresh = build(c3), let cold = ScrubGrains.read(fresh, start: g.start, frames: g.frames)
        else { failed += 1; continue }
        worst = max(worst, maxDiff(hot, cold))
    }
    let active = AudioDSPParameters(snapshot: c3.project.snapshot).dsp(
        for: c3.project.snapshot.clips[0].id).isInert == false
    row("C3", starts.count >= 10 && adjacent && failed == 0 && worst <= 1e-5 && active,
        "\(starts.count) grains from a 1.5 s 1× drag, each within 0.1 s of the last one's end \(adjacent); "
            + "DSP active \(active); each after the first against a cold read on a fresh build: "
            + "max |Δ| \(worst); \(failed) reads failed; (reported) RMS against the whole-timeline "
            + "read: max " + String(format: "%.6f", warmRMS.max() ?? 0) + ", mean "
            + String(format: "%.6f", warmRMS.reduce(0, +) / Double(max(1, warmRMS.count))))
} else {
    row("C3", false, c3Why.isEmpty ? "a build or the export read failed" : c3Why)
}

// =========================================================================
// E — ScrubAudio's queue

final class RecordingSink: ScrubGrainSink {
    let lock = NSLock()
    var played: [(left: [Float], right: [Float])] = []
    var stops = 0
    /// When set, the first play waits on `release` after signalling `entered`.
    let blocking: Bool
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    init(blocking: Bool = false) { self.blocking = blocking }
    func start() -> Bool { true }
    func play(left: [Float], right: [Float]) {
        lock.lock()
        let first = played.isEmpty
        played.append((left, right))
        lock.unlock()
        if blocking && first {
            entered.signal()
            release.wait()
        }
    }
    func stop() {
        lock.lock()
        stops += 1
        lock.unlock()
    }
    var snapshot: [(left: [Float], right: [Float])] {
        lock.lock()
        defer { lock.unlock() }
        return played
    }
}

let (eA, eAWhy) = fixture(tracks: 1) { document, tracks in
    place(document, noiseA, track: tracks[0], at: 0) == nil ? "the clip did not land" : nil
}
let (eB, eBWhy) = fixture(tracks: 1) { document, tracks in
    guard let a = place(document, noiseA, track: tracks[0], at: 0) else { return "the clip did not land" }
    document.performGroupedEdit("Volume", [.setAudio(clips: [a], patch: AudioPatch(volume: 0.5))])
    return nil
}

if let eA = eA, let eB = eB, let refA = build(eA), let refB = build(eB) {
    // E1
    do {
        let sink = RecordingSink()
        let audio = ScrubAudio(sink: sink)
        let player = AVMutableComposition()
        var shadow = ScrubGrainScheduler()
        var expected: [ScrubGrain] = []
        for k in 0...30 {
            let now = 1000 + Double(k) / 60
            let playhead = snap(1.0 + Double(k) / 60)
            if let g = shadow.move(to: playhead, duration: 6 * SEC, now: now) { expected.append(g) }
            audio.move(to: playhead, duration: 6 * SEC, player: player, now: now) { eA.source }
        }
        audio.drain()
        let played = sink.snapshot
        var worst: Float = 0
        var missing = 0
        for (i, g) in expected.enumerated() where i < played.count {
            guard let want = ScrubGrains.read(refA, start: g.start, frames: g.frames) else { missing += 1; continue }
            worst = max(worst, maxDiff(played[i], windowed(want)))
        }
        row("E1", !expected.isEmpty && played.count == expected.count && missing == 0 && worst <= 1e-5,
            "\(played.count) grains played, \(expected.count) asked by the scheduler; against read × "
                + "window at its starts max |Δ| \(worst)")
        audio.invalidate()
        audio.drain()
    }
    // E2
    do {
        let sink = RecordingSink(blocking: true)
        let audio = ScrubAudio(sink: sink)
        let player = AVMutableComposition()
        var shadow = ScrubGrainScheduler()
        var asked = 0
        let moves: [(Double, Double)] = [(2000, 1.0), (2000.05, 1.1), (2000.13, 1.2), (2000.21, 1.3)]
        for (i, (now, at)) in moves.enumerated() {
            if shadow.move(to: snap(at), duration: 6 * SEC, now: now) != nil { asked += 1 }
            audio.move(to: snap(at), duration: 6 * SEC, player: player, now: now) { eA.source }
            if i == 0 { _ = sink.entered.wait(timeout: .now() + 30) }
        }
        audio.end()
        sink.release.signal()
        audio.drain()
        row("E2", asked == 4 && sink.snapshot.count == 1,
            "\(asked) grains asked (the first held in play), end(), release: \(sink.snapshot.count) played")
        audio.invalidate()
        audio.drain()
    }
    // E3
    do {
        let audio = ScrubAudio(sink: RecordingSink())
        let first = AVMutableComposition()
        audio.move(to: snap(1), duration: 6 * SEC, player: first, now: 3000) { eA.source }
        audio.move(to: snap(1.5), duration: 6 * SEC, player: first, now: 3001) { eA.source }
        audio.drain()
        let one = audio.builds
        audio.move(to: snap(2), duration: 6 * SEC, player: AVMutableComposition(), now: 3002) { eA.source }
        audio.drain()
        let two = audio.builds
        row("E3", one == 1 && two == 2,
            "two moves on one composition: \(one) build(s); a new composition object: \(two)")
        audio.invalidate()
        audio.drain()
    }
    // E4
    do {
        let sink = RecordingSink()
        let audio = ScrubAudio(sink: sink)
        let a = AVMutableComposition()
        let b = AVMutableComposition()
        audio.move(to: snap(1), duration: 6 * SEC, player: a, now: 4000) { eA.source }
        audio.drain()  // A's grain is read and played before end() could drop it
        var shadow = ScrubGrainScheduler()
        _ = shadow.move(to: snap(1), duration: 6 * SEC, now: 4000)
        let quiet = shadow.move(to: snap(1.2), duration: 6 * SEC, now: 4000.01) == nil
        audio.move(to: snap(1.2), duration: 6 * SEC, player: b, now: 4000.01) { eB.source }
        audio.end()
        audio.move(to: snap(2), duration: 6 * SEC, player: b, now: 4001) { eB.source }
        audio.drain()
        let played = sink.snapshot
        let want = ScrubGrains.read(refB, start: snap(2), frames: ScrubGrains.frames).map(windowed)
        let diff = played.last.flatMap { got in want.map { maxDiff(got, $0) } } ?? .infinity
        row("E4", quiet && audio.builds == 2 && played.count == 2 && diff <= 1e-5,
            "the move with B asked for no grain \(quiet); builds \(audio.builds); \(played.count) played; "
                + "the next scrub's grain against B's read × window max |Δ| \(diff)")
        audio.invalidate()
        audio.drain()
    }
    // E5
    do {
        let sink = RecordingSink(blocking: true)
        let audio = ScrubAudio(sink: sink)
        let a = AVMutableComposition()
        let b = AVMutableComposition()
        audio.move(to: snap(1), duration: 6 * SEC, player: a, now: 5000) { eA.source }
        _ = sink.entered.wait(timeout: .now() + 30)
        var shadow = ScrubGrainScheduler()
        _ = shadow.move(to: snap(1), duration: 6 * SEC, now: 5000)
        let asks = shadow.move(to: snap(1.1), duration: 6 * SEC, now: 5000.05) != nil
        audio.move(to: snap(1.1), duration: 6 * SEC, player: b, now: 5000.05) { eB.source }
        audio.end()
        sink.release.signal()
        audio.drain()
        audio.move(to: snap(2), duration: 6 * SEC, player: b, now: 5001) { eB.source }
        audio.drain()
        let played = sink.snapshot
        let want = ScrubGrains.read(refB, start: snap(2), frames: ScrubGrains.frames).map(windowed)
        let diff = played.last.flatMap { got in want.map { maxDiff(got, $0) } } ?? .infinity
        row("E5", asks && played.count == 2 && diff <= 1e-5,
            "the move with B asked for a grain \(asks) (dropped by end()); \(played.count) played; builds "
                + "\(audio.builds); the next scrub's grain against B's read × window max |Δ| \(diff)")
        audio.invalidate()
        audio.drain()
    }
} else {
    let why = [eAWhy, eBWhy].filter { !$0.isEmpty }.joined(separator: "; ")
    for id in ["E1", "E2", "E3", "E4", "E5"] {
        row(id, false, why.isEmpty ? "a reference build failed" : why)
    }
}
exit(0)
