// tools/proof/audio_ap10c_probe.swift — the in-process instrument behind
// `audio_ap10c_proof.py --probe` (road map "audio" AP10 part 2b, spec §11
// AU-150..AU-156). Compiled with every file in `app/Sources` but `main.swift`
// through `swift_build.py`'s line, copied in as `main.swift`, with `Blank.mp4`
// beside the binary (the builder's placeholder track for an audio-only plan).
//
//     audio_ap10c_probe <work-dir>
//
// One line per row, `ok <ID> — <detail>` or `FAIL <ID> — <detail>`; no app is
// launched.
//
//  B1  `AudioTrackDynamicsStage` (a compressor and a limiter over a hot sine
//      with noise) writes the same bytes at 512, 4,096 and irregular buffers;
//      its latency is 158 with a limiter and 0 with a compressor alone.
//  B2  `ExportMixRead`: a build with no track dynamics reads in single mode,
//      byte-identical to `audioReadOutput`; a build whose track has an identity
//      compressor (ratio 1, makeup 0) is sub-mixed and within −140 dB of the
//      single read; and the loudness measurement (`Exporter.measureLoudness`)
//      of a build whose track is compressed hard reads its sub-mixes, more
//      than 3 LU from the same project undynamic. A limited track whose
//      last drain is longer than a block (65,600 frames) hands back every
//      frame, in buffers of at most `ExportMixRead.blockFrames` (spec §11
//      AU-152, #414).
//  B3  a nest bus: a timeline track holding a nest clip of two simultaneous
//      tracks, limited at −6 dBTP, beside a plain track — the sub-mixed read
//      equals a fresh stage over that track's plain read (its latency dropped,
//      flushed with zeros) plus the plain track's read, within 1e-6.
//  B4  the tap's ×E/÷E (`AudioTapContext` driven directly): with an identity
//      stage the output is the input within 1e-6 where E ≥ 2⁻²⁰ and 0 under;
//      with a released limiter (0 dBTP over a −20 dBFS sine, a pure 158-frame
//      delay) under an envelope stepping 1 → 0.1 mid-buffer, the output is the
//      input delayed 158 frames within 1e-6 at 48 kHz and at 44.1 kHz (no
//      burst at the step); and with a −6 dBTP limiter under a constant E of
//      0.5, a 0.9 sine is limited post-fader (0.45 passes), so the output is
//      the delayed input within 1e-6.
//  B5  `AudioShift.of` adds 1,975 ticks for a track limiter (summed with a
//      clip limiter's); `AudioTrackDSP`'s `trackLead` and `lookupLead` sum
//      likewise and a compressor alone adds none; a non-metering build carries
//      `trackDynamics` for its owner; `TrackSnapshot.mixIsSet`; the meter
//      footer's choice.
import AVFoundation
import Accelerate
import AppKit

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)

let SEC: Ticks = 600_000
let RATE = 48_000

func row(_ id: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "ok" : "FAIL") \(id) — \(detail)")
    fflush(stdout)
}

guard CommandLine.arguments.count == 2 else {
    row("B1", false, "usage: audio_ap10c_probe <work-dir>")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

func sine(_ amplitude: Float, _ hz: Double, frames: Int, rate: Int = RATE) -> [Float] {
    (0..<frames).map { amplitude * Float(sin(2 * Double.pi * hz * Double($0) / Double(rate))) }
}

func peak(_ x: ArraySlice<Float>) -> Float { x.map { abs($0) }.max() ?? 0 }

func worst(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count else { return .infinity }
    return zip(a, b).map { abs($0 - $1) }.max() ?? 0
}

// MARK: - Projects and reads

func writeSine(_ url: URL, seconds: Double, amplitude: Float, hz: Double) -> String? {
    try? FileManager.default.removeItem(at: url)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(RATE), channels: 2),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(RATE) * seconds))
    else { return "no buffer" }
    buffer.frameLength = buffer.frameCapacity
    let tone = sine(amplitude, hz, frames: Int(buffer.frameLength))
    for i in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![0][i] = tone[i]
        buffer.floatChannelData![1][i] = tone[i]
    }
    do {
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: RATE,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    } catch { return "would not write: \(error)" }
    return nil
}

struct Failure: Error, CustomStringConvertible { let description: String }

/// `ops` through the document; a refusal or an error throws.
func edit(_ document: ProjectDocument, _ name: String, _ ops: [ReelOp]) throws {
    var trial = document.project
    for op in ops {
        switch try trial.applying(op) {
        case .applied(let next): trial = next
        case .identity: break
        case .refused(let refusal): throw Failure(description: "\(op.name): \(refusal.reason)")
        }
    }
    document.performGroupedEdit(name, ops)
}

/// A document with `tracks` timeline tracks and every tone in `tones`
/// imported; answers the track ids back to front and the media ids.
func document(tracks: Int, tones: [URL]) throws -> (ProjectDocument, [UInt32], [UInt32]) {
    let document = ProjectDocument()
    for index in 1..<max(tracks, 1) { try edit(document, "Track", [.addTrack(index: index)]) }
    for tone in tones {
        try edit(document, "Media", [.addMedia(descriptor: MediaDescriptor(
            path: tone.path, kind: .audio, duration: 2 * SEC, hasVideo: false, hasAudio: true))])
    }
    let snapshot = document.project.snapshot
    return (document, snapshot.tracks.map(\.id), snapshot.media.map(\.id))
}

func clip(_ document: ProjectDocument, track: UInt32, media: UInt32) throws -> UInt32 {
    let before = Set(document.project.snapshot.clips.map(\.id))
    try edit(document, "Clip", [.addClip(track: track, media: media, at: 0)])
    guard let id = document.project.snapshot.clips.map(\.id).first(where: { !before.contains($0) })
    else { throw Failure(description: "no clip added") }
    return id
}

/// A fresh build of the document as an export builds it.
func build(_ document: ProjectDocument, metering: Bool = false) throws -> BuiltComposition {
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(document.project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: document.project.snapshot), for: key)
    ReverseSource.shared.publish(
        ReverseResolution(ready: [:], pending: []), project: document.project, for: key)
    guard let plan = document.project.plan else { throw Failure(description: "no plan") }
    return try CompositionBuilder.build(
        plan: plan, planJSON: document.project.planJSON, urls: document.mediaURLs(),
        recipeKey: key, metering: metering)
}

/// The most frames one buffer of the last `place` held, and all it was handed.
var largestBuffer = 0
var framesHanded = 0

/// Every buffer `next` hands back, placed by its stamp from 0 at 48 kHz.
func place(_ built: BuiltComposition, _ next: () throws -> CMSampleBuffer?) throws -> [[Float]] {
    let total = ExportAudioEnd.frames(ofTicks: CompositionBuilder.ticks(built.composition.duration))
    var left = [Float](repeating: 0, count: total)
    var right = [Float](repeating: 0, count: total)
    largestBuffer = 0
    framesHanded = 0
    while let sample = try next() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let count = CMBlockBufferGetDataLength(block) / 8
        largestBuffer = max(largestBuffer, count)
        framesHanded += count
        var raw = [Float](repeating: 0, count: 2 * count)
        _ = raw.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: 8 * count, destination: $0.baseAddress!)
        }
        let offset = Int(CMTimeConvertScale(
            CMSampleBufferGetPresentationTimeStamp(sample), timescale: 48_000,
            method: .roundHalfAwayFromZero).value)
        for i in 0..<count where offset + i >= 0 && offset + i < total {
            left[offset + i] = raw[2 * i]
            right[offset + i] = raw[2 * i + 1]
        }
    }
    return [left, right]
}

/// The single read (`audioReadOutput`, optionally only `ids`).
func single(_ built: BuiltComposition, only: Set<CMPersistentTrackID>? = nil) throws -> [[Float]] {
    let reader = try AVAssetReader(asset: built.composition)
    let output = ExportWriter.audioReadOutput(built, only: only)
    guard reader.canAdd(output) else { throw Failure(description: "the reader refused") }
    reader.add(output)
    guard reader.startReading() else { throw Failure(description: "did not start") }
    let read = try place(built) { output.copyNextSampleBuffer() }
    guard reader.status == .completed else { throw Failure(description: "read failed") }
    return read
}

/// The export's read (`ExportMixRead`) and whether it was sub-mixed.
func mixRead(_ built: BuiltComposition) throws -> ([[Float]], Bool) {
    let reader = try AVAssetReader(asset: built.composition)
    let read = ExportMixRead(built, origin: .zero)
    guard read.add(to: reader) else { throw Failure(description: "the reader refused") }
    guard reader.startReading() else { throw Failure(description: "did not start") }
    let samples = try place(built) { try read.next() }
    guard reader.status == .completed else { throw Failure(description: "read failed") }
    return (samples, read.isSubMixed)
}

func tone(_ name: String, _ amplitude: Float, _ hz: Double) throws -> URL {
    let url = work.appendingPathComponent(name)
    if let why = writeSine(url, seconds: 2, amplitude: amplitude, hz: hz) {
        throw Failure(description: "fixture \(name): \(why)")
    }
    return url
}

// MARK: - B1 the stage

/// The stage over `input` in buffers of `sizes`, cycled.
func runStage(
    _ settings: AudioTrackDynamicsSettings, _ input: [[Float]], _ sizes: [Int]
) -> [[Float]] {
    let stage = AudioTrackDynamicsStage(channelCount: 2, sampleRate: Double(RATE), maxFrames: 4096)
    let total = input[0].count
    let buffers = input.map { channel -> UnsafeMutablePointer<Float> in
        let p = UnsafeMutablePointer<Float>.allocate(capacity: total)
        p.update(from: channel, count: total)
        return p
    }
    let pointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: 2)
    defer {
        pointers.deallocate()
        buffers.forEach { $0.deallocate() }
    }
    var position = 0
    var turn = 0
    while position < total {
        let size = min(sizes[turn % sizes.count], total - position)
        turn += 1
        for c in 0..<2 { pointers[c] = buffers[c] + position }
        stage.process(
            UnsafeMutableBufferPointer(start: pointers, count: 2), count: 2, frames: size,
            settings: settings)
        position += size
    }
    return buffers.map { Array(UnsafeBufferPointer(start: $0, count: total)) }
}

do {
    let settings = AudioTrackDynamicsSettings(
        compressor: CompressorProps(
            thresholdDb: -24, ratio: 4, attack: 600, release: 60_000, makeupDb: 6),
        limiter: LimiterProps(ceilingDb: -3, release: 60_000))!
    var seed: UInt32 = 12345
    let noise = (0..<RATE).map { _ -> Float in
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.2
    }
    let hot = sine(0.8, 440, frames: RATE)
    let input = [zip(hot, noise).map { $0 + $1 }, zip(hot, noise).map { $0 - $1 }]
    let a = runStage(settings, input, [512])
    let b = runStage(settings, input, [4096])
    let c = runStage(settings, input, [1, 37, 500, 4096, 123, 2048, 999])
    let compressorOnly = AudioTrackDynamicsSettings(compressor: CompressorProps(), limiter: nil)!
    let stage = AudioTrackDynamicsStage(channelCount: 2, sampleRate: Double(RATE), maxFrames: 4096)
    let latencies = (stage.latency(settings), stage.latency(compressorOnly))
    let none = AudioTrackDynamicsSettings(compressor: nil, limiter: nil) == nil
    row("B1", a == b && a == c && latencies == (158, 0) && none && a != input,
        "512 = 4096 \(a == b), 512 = irregular \(a == c), changed the input \(a != input); "
            + "latency \(latencies) (want (158, 0)); no settings is nil \(none)")
}

// MARK: - B2 single and sub-mixed reads, and the measurement

do {
    let a = try tone("b2-a.wav", 0.25, 440)
    let b = try tone("b2-b.wav", 0.05, 660)
    func project(_ compressor: CompressorProps?) throws -> ProjectDocument {
        let (doc, tracks, media) = try document(tracks: 2, tones: [a, b])
        _ = try clip(doc, track: tracks[0], media: media[0])
        _ = try clip(doc, track: tracks[1], media: media[1])
        if let compressor {
            try edit(doc, "Comp", [.setTrack(track: tracks[0], compressor: compressor.dictionary)])
        }
        return doc
    }
    let plain = try project(nil)
    let (plainRead, plainSub) = try mixRead(try build(plain))
    let plainSingle = try single(try build(plain))
    let identity = try project(CompressorProps(thresholdDb: -40, ratio: 1, makeupDb: 0))
    let (subRead, subMixed) = try mixRead(try build(identity))
    // The last drain: one limited track, 41 frames at 30 fps = 65,600 samples
    // = 16 × 4,096 + 64, so the group holds 4,002 frames when its output ends
    // and 4,160 once the stage's 158-frame flush lands behind them.
    let (tail, tailTracks, tailMedia) = try document(tracks: 1, tones: [a])
    let tailClip = try clip(tail, track: tailTracks[0], media: tailMedia[0])
    try edit(tail, "Trim", [.trimEnd(clip: tailClip, to: 41 * SEC / 30)])
    try edit(tail, "Limit", [.setTrack(
        track: tailTracks[0], limiter: LimiterProps(ceilingDb: -6, release: 60_000).dictionary)])
    let (_, tailSub) = try mixRead(try build(tail))
    let (largest, handed) = (largestBuffer, framesHanded)
    let subSingle = try single(try build(identity))
    let reference = max(peak(subSingle[0][...]), peak(subSingle[1][...]))
    let gap = max(worst(subRead[0], subSingle[0]), worst(subRead[1], subSingle[1]))
    let gapDB = 20 * log10(Double(max(gap, 1e-30)) / Double(max(reference, 1e-30)))
    // The measurement, each on a fresh build (its taps' state is its own).
    let hard = try project(CompressorProps(thresholdDb: -40, ratio: 20, makeupDb: 0))
    let settings = try ReelExport.settings(hard.project, preset: "audio_wav")
    let squeezed = Exporter().measureLoudness(try build(hard), settings: settings)?
        .measured.integratedLUFS
    let open = Exporter().measureLoudness(try build(plain), settings: settings)?
        .measured.integratedLUFS
    let apart = (squeezed != nil && open != nil) ? abs(squeezed! - open!) : 0
    row("B2", !plainSub && plainRead == plainSingle && subMixed && gapDB <= -140 && apart > 3
            && tailSub && handed == 65_600 && largest <= ExportMixRead.blockFrames,
        "no dynamics: sub-mixed \(plainSub), byte-identical to the single read "
            + "\(plainRead == plainSingle); identity compressor: sub-mixed \(subMixed), "
            + String(format: "%.1f", gapDB) + " dB from the single read (want ≤ −140); "
            + "a limited track of 65,600 frames: sub-mixed \(tailSub), \(handed) handed, the largest buffer "
            + "\(largest) frames (want ≤ \(ExportMixRead.blockFrames)); "
            + "measured \(squeezed.map { String(format: "%.2f", $0) } ?? "nil") LUFS compressed "
            + "against \(open.map { String(format: "%.2f", $0) } ?? "nil") undynamic (want > 3 LU "
            + "apart)")
} catch {
    row("B2", false, "\(error)")
}

// MARK: - B3 a nest bus

do {
    let a1 = try tone("b3-a1.wav", 0.4, 440)
    let a2 = try tone("b3-a2.wav", 0.4, 660)
    let b = try tone("b3-b.wav", 0.3, 550)
    let (doc, tracks, media) = try document(tracks: 3, tones: [a1, a2, b])
    let first = try clip(doc, track: tracks[0], media: media[0])
    let second = try clip(doc, track: tracks[1], media: media[1])
    _ = try clip(doc, track: tracks[2], media: media[2])
    try edit(doc, "Nest", [.nest(clips: [first, second])])
    guard let bus = doc.project.snapshot.clips.first(where: { $0.source.nestID != nil })?.track
    else { throw Failure(description: "no nest clip") }
    let limiter = LimiterProps(ceilingDb: -6, release: 60_000)
    try edit(doc, "Limit", [.setTrack(track: bus, limiter: limiter.dictionary)])
    let (mixed, sub) = try mixRead(try build(doc))
    // The expectation: a fresh stage over the bus's plain read, plus the rest.
    let plainBuild = try build(doc)
    let busIDs = Set(plainBuild.audioOwners.filter { $0.value == bus }.keys)
    let restIDs = Set(plainBuild.audioOwners.keys).subtracting(busIDs)
    let busRead = try single(plainBuild, only: busIDs)
    let restRead = try single(try build(doc), only: restIDs)
    let settings = AudioTrackDynamicsSettings(compressor: nil, limiter: limiter)!
    let latency = 158
    let padded = busRead.map { $0 + [Float](repeating: 0, count: latency) }
    let staged = runStage(settings, padded, [4096]).map { Array($0[latency...]) }
    let expected = (0..<2).map { c in zip(staged[c], restRead[c]).map { $0 + $1 } }
    let gap = max(worst(mixed[0], expected[0]), worst(mixed[1], expected[1]))
    let busPeak = peak(busRead[0][...])
    row("B3", sub && busIDs.count >= 2 && gap <= 1e-6 && busPeak > 0.5,
        "bus on \(busIDs.count) composition tracks (plain peak \(busPeak)), rest on "
            + "\(restIDs.count); sub-mixed \(sub); |read − (stage(bus) + rest)| \(gap) (want ≤ 1e-6)")
} catch {
    row("B3", false, "\(error)")
}

// MARK: - B4 the tap's ×E/÷E

/// `input` through a tap whose track has `settings` and an envelope of `legs`,
/// at `rate`, in buffers of `buffer` frames from frame 0.
func tapRun(
    _ settings: AudioTrackDynamicsSettings, legs: [CompositionBuilder.VolumeLeg], rate: Int,
    _ input: [[Float]], buffer: Int
) -> [[Float]] {
    let dsp = AudioTrackDSP(
        segments: [], parameters: .empty,
        dynamics: AudioTrackDynamics(settings: settings, envelope: AudioTrackEnvelope(legs: legs)))
    let context = AudioTapContext(track: dsp, isolation: nil, meter: nil)
    context.prepare(
        channelCount: 2, sampleRate: Double(rate), maxFrames: 4096,
        formatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
        bitsPerChannel: 32)
    let total = input[0].count
    var out = [[Float]](repeating: [Float](repeating: 0, count: total), count: 2)
    let list = AudioBufferList.allocate(maximumBuffers: 2)
    let scratch = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: buffer) }
    defer {
        free(list.unsafeMutablePointer)
        scratch.forEach { $0.deallocate() }
    }
    var start = 0
    while start < total {
        let n = min(buffer, total - start)
        for c in 0..<2 {
            input[c].withUnsafeBufferPointer { scratch[c].update(from: $0.baseAddress! + start, count: n) }
            list[c] = AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(n * 4), mData: scratch[c])
        }
        context.process(
            list.unsafeMutablePointer, frames: n,
            time: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
            startOfStream: start == 0)
        for c in 0..<2 {
            for i in 0..<n { out[c][start + i] = scratch[c][i] }
        }
        start += n
    }
    return out
}

do {
    var failed: [String] = []
    var details: [String] = []
    // Identity: ×E then ÷E, E from 1 down to 2⁻²⁴ over 1 s, then 0.
    let identity = AudioTrackDynamicsSettings(
        compressor: CompressorProps(thresholdDb: -40, ratio: 1, makeupDb: 0), limiter: nil)!
    let legs = [
        CompositionBuilder.VolumeLeg(start: 0, duration: SEC, from: 1, to: 1.0 / 16_777_216),
        CompositionBuilder.VolumeLeg(start: SEC, duration: SEC, from: 0, to: 0),
    ]
    let x = sine(0.5, 440, frames: 2 * RATE)
    let out = tapRun(identity, legs: legs, rate: RATE, [x, x], buffer: 512)
    let envelope = AudioTrackEnvelope(legs: legs)
    var e = [Float](repeating: 0, count: 2 * RATE)
    e.withUnsafeMutableBufferPointer {
        envelope.fill($0.baseAddress!, frames: 2 * RATE, fromFrame: 0, rate: Ticks(RATE))
    }
    var identityGap: Float = 0
    for i in 0..<(2 * RATE) {
        let want = e[i] >= AudioTapContext.envelopeFloor ? x[i] : 0
        identityGap = max(identityGap, abs(out[0][i] - want), abs(out[1][i] - want))
    }
    details.append("identity |out − in| \(identityGap)")
    if identityGap > 1e-6 { failed.append("identity") }

    // A released limiter under a step, at 48 and 44.1 kHz: a pure delay.
    let released = AudioTrackDynamicsSettings(
        compressor: nil, limiter: LimiterProps(ceilingDb: 0, release: 60_000))!
    let step = SEC / 2 + 777
    let stepLegs = [
        CompositionBuilder.VolumeLeg(start: 0, duration: step, from: 1, to: 1),
        CompositionBuilder.VolumeLeg(start: step, duration: 1, from: 1, to: 0.1),
        CompositionBuilder.VolumeLeg(start: step + 1, duration: 10 * SEC, from: 0.1, to: 0.1),
    ]
    for rate in [48_000, 44_100] {
        let y = sine(0.1, 440, frames: rate, rate: rate)
        let delayed = [Float](repeating: 0, count: 158) + y.dropLast(158)
        let got = tapRun(released, legs: stepLegs, rate: rate, [y, y], buffer: 512)
        let gap = max(worst(got[0], delayed), worst(got[1], delayed))
        details.append("step at \(rate) Hz |out − in delayed 158| \(gap)")
        if gap > 1e-6 { failed.append("step \(rate)") }
    }

    // Post-fader: E 0.5 brings a 0.9 sine under a −6 dBTP ceiling, so it passes.
    let limited = AudioTrackDynamicsSettings(
        compressor: nil, limiter: LimiterProps(ceilingDb: -6, release: 60_000))!
    let half = [CompositionBuilder.VolumeLeg(start: 0, duration: 10 * SEC, from: 0.5, to: 0.5)]
    let z = sine(0.9, 440, frames: RATE)
    let zDelayed = [Float](repeating: 0, count: 158) + z.dropLast(158)
    let got = tapRun(limited, legs: half, rate: RATE, [z, z], buffer: 512)
    let postGap = max(worst(got[0], zDelayed), worst(got[1], zDelayed))
    details.append("E 0.5 under −6 dBTP |out − in delayed| \(postGap)")
    if postGap > 1e-6 { failed.append("post-fader") }
    row("B4", failed.isEmpty,
        details.joined(separator: "; ") + " (want ≤ 1e-6)"
            + (failed.isEmpty ? "" : "; failed: " + failed.joined(separator: ", ")))
}

// MARK: - B5 the leads, the build's record, the switch and the footer

do {
    var tests: [(String, Bool)] = []
    let lead = CompositionBuilder.AudioShift.limiterLead
    tests.append(("the limiter lead is 1,975 ticks", lead == 1975))
    tests.append((
        "a track limiter adds it",
        CompositionBuilder.AudioShift.of(
            segments: [], usesNoiseReduction: false, usesLimiter: false, usesTrackLimiter: true
        ).trackLead == 1975))
    tests.append((
        "summed with a clip limiter's",
        CompositionBuilder.AudioShift.of(
            segments: [], usesNoiseReduction: false, usesLimiter: true, usesTrackLimiter: true
        ).trackLead == 3950))
    let envelope = AudioTrackEnvelope(legs: [])
    let limited = AudioTrackDynamics(
        settings: AudioTrackDynamicsSettings(compressor: nil, limiter: LimiterProps())!,
        envelope: envelope)
    let squeezed = AudioTrackDynamics(
        settings: AudioTrackDynamicsSettings(compressor: CompressorProps(), limiter: nil)!,
        envelope: envelope)
    let withLimiter = AudioTrackDSP(segments: [], parameters: .empty, dynamics: limited)
    let withCompressor = AudioTrackDSP(segments: [], parameters: .empty, dynamics: squeezed)
    tests.append(("a track limiter's trackLead", withLimiter.trackLead == 1975))
    tests.append(("its lookupLead", withLimiter.lookupLead == 1975))
    tests.append((
        "a compressor alone has none",
        withCompressor.trackLead == 0 && withCompressor.lookupLead == 0))
    // The lookup sums with a clip limiter's: a segment whose clip is limited.
    let json = #"{"clip": 3, "media": 1, "source_in": 0, "source_duration": 600000, "#
        + #""start": 0, "duration": 600000}"#
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var why = ""
    let fixture = #"""
            {"version": 36, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
             "background": [0, 0, 0, 1]},
             "media": [{"id": 1, "path": "/x.wav", "kind": "audio", "duration": 6000000,
                        "has_video": false, "has_audio": true}],
             "tracks": [{"id": 2, "name": "T", "limiter": {"ceiling_db": -6}}],
             "clips": [{"id": 3, "track": 2, "start": 0, "duration": 600000,
                        "source": {"kind": "media", "media": 1, "in": 0},
                        "audio": {"limiter": {"ceiling_db": -3}}}],
             "next_id": 4}
            """#
    let decoded: ProjectSnapshot?
    do { decoded = try ReelProject.from(json: fixture).snapshot } catch {
        decoded = nil
        why = "\(error)"
    }
    if let segment = try? decoder.decode(PlanSegment.self, from: Data(json.utf8)),
        let snapshot = decoded
    {
        let parameters = AudioDSPParameters(snapshot: snapshot)
        let both = AudioTrackDSP(segments: [segment], parameters: parameters, dynamics: limited)
        tests.append(("the clip and track leads sum", both.lookupLead == 3950))
        tests.append(("the parameters carry the track's", parameters.trackDynamics[2] != nil))
        tests.append(("and stay empty-counted", !parameters.isEmpty))
    } else {
        tests.append(("the fixture decoded: \(why)", false))
    }
    // A non-metering build records its owner's dynamics.
    do {
        let a = try tone("b5-a.wav", 0.25, 440)
        let (doc, tracks, media) = try document(tracks: 1, tones: [a])
        _ = try clip(doc, track: tracks[0], media: media[0])
        let plainBuild = try build(doc)
        try edit(doc, "Limit", [.setTrack(track: tracks[0], limiter: LimiterProps().dictionary)])
        let limitedBuild = try build(doc)
        tests.append(("a plain build records none", plainBuild.trackDynamics.isEmpty))
        tests.append((
            "a limited export build records its owner",
            limitedBuild.trackDynamics[tracks[0]] != nil))
    } catch {
        tests.append(("the builds: \(error)", false))
    }
    tests.append(("a default track's mix is not set", !TrackSnapshot(id: 1).mixIsSet))
    tests.append(("volume sets it", TrackSnapshot(id: 1, volume: 0.5).mixIsSet))
    tests.append(("pan sets it", TrackSnapshot(id: 1, pan: 0.5).mixIsSet))
    tests.append(("a compressor sets it", TrackSnapshot(id: 1, compressor: CompressorProps()).mixIsSet))
    tests.append(("a limiter sets it", TrackSnapshot(id: 1, limiter: LimiterProps()).mixIsSet))
    var reading = LiveLoudnessReading.empty
    tests.append(("plain reads pre-master", LoudnessPanelView.footerNote(reading)
        == LoudnessPanelView.preMasterNote))
    reading.tracksApproximate = true
    tests.append(("approximate reads approximate", LoudnessPanelView.footerNote(reading)
        == LoudnessPanelView.approximateNote))
    reading.offSpeed = true
    tests.append(("off speed wins", LoudnessPanelView.footerNote(reading)
        == LoudnessPanelView.offSpeedNote))
    let live = LiveLoudness()
    live.consume([], rate: 1, now: 0, tracksApproximate: true)
    let flagged = live.reading.tracksApproximate
    live.consume([], rate: 1, now: 0.1)
    tests.append(("the meter takes the flag and drops it", flagged && !live.reading.tracksApproximate))
    let failed = tests.filter { !$0.1 }.map(\.0)
    row("B5", failed.isEmpty,
        "\(tests.count - failed.count)/\(tests.count) checks"
            + (failed.isEmpty ? "" : "; failed: " + failed.joined(separator: ", ")))
}
exit(0)
