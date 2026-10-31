// tools/proof/audio_ap10_probe.swift — the in-process instrument behind
// `audio_ap10_proof.py --probe` (road map "audio" AP10 part 1, spec §11
// AU-104, AU-105). Compiled with every file in `app/Sources` but `main.swift`
// through `swift_build.py`'s line, copied in as `main.swift`, with `Blank.mp4`
// beside the binary (the builder's placeholder track for an audio-only plan).
//
//     audio_ap10_probe <work-dir>
//
// One line per row, `ok <ID> — <detail>` or `FAIL <ID> — <detail>`; no app is
// launched.
//
//  B1  `AudioTrackBalance`: no pans and a zero pan are unity; one pan is
//      `AudioPanLaw`'s pair; two pans are the product of their pairs; and the
//      chain applies it to channels 0 and 1 and to nothing at unity.
//  B2  the chain's order: a clip limited at −6 dB under a track pan of −1 (a
//      0.9 sine in both channels) holds its ceiling in the left channel, the
//      balance running BEFORE the limiter, and the right is silent.
//  B3  `isInert` counts the balance (unity inert, a pan not), a schedule over
//      a segment with `track_pans` is active with no clip DSP, and the
//      builder gives a project whose only processing is a track pan of −1 a
//      tap: its float read has the right channel silent and the left +3.01 dB.
//  B4  `TrackMixLevel`: 1 is 0 dB, 0.5 is −6.02, 0 and anything at or under
//      −60 dB read the floor and write 0, +12 is the rail's top, and the
//      readout is "Off" at 0.
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

func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

guard CommandLine.arguments.count == 2 else {
    row("B1", false, "usage: audio_ap10_probe <work-dir>")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

/// Runs `chain` over two channels of `input` in 1,024-frame buffers.
func run(_ chain: AudioDSPChain, _ input: [[Float]], _ params: AudioClipDSP) -> [[Float]] {
    let total = input[0].count
    let buffers = input.map { channel -> UnsafeMutablePointer<Float> in
        let p = UnsafeMutablePointer<Float>.allocate(capacity: total)
        p.update(from: channel, count: total)
        return p
    }
    let pointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(
        capacity: buffers.count)
    defer {
        pointers.deallocate()
        buffers.forEach { $0.deallocate() }
    }
    var position = 0
    while position < total {
        let size = min(1024, total - position)
        for c in buffers.indices { pointers[c] = buffers[c] + position }
        chain.process(
            UnsafeMutableBufferPointer(start: pointers, count: buffers.count), frames: size,
            params: params)
        position += size
    }
    return buffers.map { Array(UnsafeBufferPointer(start: $0, count: total)) }
}

func sine(_ amplitude: Float, frames: Int) -> [Float] {
    (0..<frames).map { amplitude * Float(sin(2 * Double.pi * 440 * Double($0) / Double(RATE))) }
}

func peak(_ x: ArraySlice<Float>) -> Float { x.map { abs($0) }.max() ?? 0 }

// MARK: - B1 the balance

do {
    let one = AudioPanLaw.gains(-0.5)
    let two = AudioPanLaw.gains(0.5)
    let single = AudioTrackBalance(pans: [-0.5])
    let pair = AudioTrackBalance(pans: [-0.5, 0.5])
    let unity = AudioTrackBalance.unity
    let tests: [(String, Bool)] = [
        ("unity is (1, 1)", unity.left == 1 && unity.right == 1),
        ("no pans is unity", AudioTrackBalance(pans: []) == unity),
        ("a zero pan is unity", AudioTrackBalance(pans: [0]) == unity),
        ("one pan is the law's pair", single.left == one.left && single.right == one.right),
        ("two pans multiply",
         pair.left == one.left * two.left && pair.right == one.right * two.right),
    ]
    let chain = AudioDSPChain(
        channelCount: 2, sampleRate: Double(RATE), maxFrames: 4096, usesNoiseReduction: false)
    let input = [sine(0.25, frames: 4800), sine(0.25, frames: 4800)]
    let balanced = run(chain, input, AudioClipDSP(trackBalance: pair))
    let untouched = run(chain, input, AudioClipDSP())
    let applied = zip(balanced[0], input[0]).allSatisfy { $0 == $1 * pair.left }
        && zip(balanced[1], input[1]).allSatisfy { $0 == $1 * pair.right }
    let failed = tests.filter { !$0.1 }.map(\.0)
    row("B1", failed.isEmpty && applied && untouched == input,
        "pair (\(pair.left), \(pair.right)) = (\(one.left)·\(two.left), \(one.right)·\(two.right)); "
            + "applied per channel \(applied), unity untouched \(untouched == input)"
            + (failed.isEmpty ? "" : "; failed: " + failed.joined(separator: ", ")))
}

// MARK: - B2 the order: the balance before the limiter

do {
    let chain = AudioDSPChain(
        channelCount: 2, sampleRate: Double(RATE), maxFrames: 4096, usesNoiseReduction: false,
        usesLimiter: true)
    let ceiling = Float(pow(10, -6.0 / 20))
    let params = AudioClipDSP(
        limiter: AudioLimiterSettings(ceilingDb: -6, volume: 1, releaseSeconds: 0.1),
        trackBalance: AudioTrackBalance(pans: [-1]))
    let input = [sine(0.9, frames: RATE), sine(0.9, frames: RATE)]
    let out = run(chain, input, params)
    let left = peak(out[0][(RATE / 5)...])
    let right = peak(out[1][...])
    row("B2", left <= ceiling * 1.001 && left >= ceiling * 0.95 && right == 0,
        "a 0.9 sine under a −6 dB limiter (ceiling \(ceiling)) and a track pan of −1: left peak "
            + "\(left) after 0.2 s (≤ ceiling; the balance after the limiter would give "
            + "\(ceiling * Float(2.0).squareRoot())), right peak \(right)")
}

// MARK: - B3 isInert, the schedule, and the builder's gate

func writeSine(_ url: URL, seconds: Double, amplitude: Float) -> String? {
    try? FileManager.default.removeItem(at: url)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(RATE), channels: 2),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(RATE) * seconds))
    else { return "no buffer" }
    buffer.frameLength = buffer.frameCapacity
    let tone = sine(amplitude, frames: Int(buffer.frameLength))
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

/// `ops` through the document; a refusal or an error is answered, not alerted.
func edit(_ document: ProjectDocument, _ name: String, _ ops: [ReelOp]) -> String? {
    var trial = document.project
    for op in ops {
        do {
            switch try trial.applying(op) {
            case .applied(let next): trial = next
            case .identity: break
            case .refused(let refusal): return "\(op.name) was refused: \(refusal.reason)"
            }
        } catch { return "\(op.name) is invalid: \(error)" }
    }
    document.performGroupedEdit(name, ops)
    return nil
}

/// The float read of the whole timeline, placed by presentation time.
func exportRead(_ built: BuiltComposition) -> [[Float]]? {
    guard let reader = try? AVAssetReader(asset: built.composition) else { return nil }
    let output = ExportWriter.audioReadOutput(built)
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    guard reader.startReading() else { return nil }
    let total = ExportAudioEnd.frames(ofTicks: CompositionBuilder.ticks(built.composition.duration))
    var left = [Float](repeating: 0, count: total)
    var right = [Float](repeating: 0, count: total)
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let count = CMBlockBufferGetDataLength(block) / 8
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
    return reader.status == .completed ? [left, right] : nil
}

/// A one-clip project of the tone with its track's pan at `pan`, built as an
/// export builds it, and read in float.
func panned(_ tone: URL, pan: Double) -> ([[Float]]?, String) {
    let document = ProjectDocument()
    if let why = edit(document, "Media", [.addMedia(descriptor: MediaDescriptor(
        path: tone.path, kind: .audio, duration: 2 * SEC, hasVideo: false, hasAudio: true))]) {
        return (nil, why)
    }
    guard let media = document.project.snapshot.media.first?.id,
          let track = document.project.snapshot.tracks.first?.id
    else { return (nil, "no media or track") }
    if let why = edit(document, "Clip", [.addClip(track: track, media: media, at: 0)]) {
        return (nil, why)
    }
    if pan != 0, let why = edit(document, "Pan", [.setTrack(track: track, pan: pan)]) {
        return (nil, why)
    }
    let key = RecipeSource.shared.register()
    RecipeSource.shared.set(document.project, for: key)
    AudioDSPSource.shared.publish(AudioDSPParameters(snapshot: document.project.snapshot), for: key)
    ReverseSource.shared.publish(
        ReverseResolution(ready: [:], pending: []), project: document.project, for: key)
    guard let plan = document.project.plan,
          let built = try? CompositionBuilder.build(
            plan: plan, planJSON: document.project.planJSON, urls: document.mediaURLs(),
            recipeKey: key, metering: false)
    else { return (nil, "the composition did not build") }
    return (exportRead(built), "")
}

do {
    var tests: [(String, Bool)] = [
        ("unity is inert", AudioClipDSP().isInert),
        ("a balance is not", !AudioClipDSP(trackBalance: AudioTrackBalance(pans: [0.5])).isInert),
        ("a zero pan's balance is", AudioClipDSP(trackBalance: AudioTrackBalance(pans: [0])).isInert),
    ]
    func segment(_ pans: String) -> PlanSegment? {
        let json = #"{"clip": 3, "media": 1, "source_in": 0, "source_duration": 600000, "#
            + #""start": 0, "duration": 600000"# + pans + "}"
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(PlanSegment.self, from: Data(json.utf8))
    }
    if let panned = segment(#", "track_pans": [0.5]"#), let plain = segment("") {
        tests.append(("track_pans decoded", panned.trackPans == [0.5] && plain.trackPans.isEmpty))
        tests.append((
            "a panned segment's schedule is active",
            AudioTrackDSP(segments: [panned], parameters: .empty).isActive))
        tests.append((
            "a plain one's is not", !AudioTrackDSP(segments: [plain], parameters: .empty).isActive))
    } else {
        tests.append(("segments decoded", false))
    }
    let tone = work.appendingPathComponent("ap10-probe-tone.wav")
    var detail = ""
    var built = false
    if let why = writeSine(tone, seconds: 2, amplitude: 0.25) {
        detail = "fixture: \(why)"
    } else {
        let (centre, a) = panned(tone, pan: 0)
        let (left, b) = panned(tone, pan: -1)
        if let centre, let left {
            let window = (RATE / 2)..<(RATE + RATE / 2)
            let l0 = Double(peak(centre[0][window])), l1 = Double(peak(left[0][window]))
            let r1 = Double(peak(left[1][window]))
            let gain = 20 * log10(l1 / max(l0, 1e-12))
            built = r1 <= 1e-6 && near(gain, 20 * log10(2.0.squareRoot()), 0.01)
            detail = "built pan −1: left \(String(format: "%+.3f", gain)) dB of centre (want "
                + "+3.010), right peak \(r1)"
        } else {
            detail = "read failed: \(a) \(b)"
        }
    }
    let failed = tests.filter { !$0.1 }.map(\.0)
    row("B3", failed.isEmpty && built,
        detail + (failed.isEmpty ? "" : "; failed: " + failed.joined(separator: ", ")))
}

// MARK: - B4 TrackMixLevel

do {
    let floor = TrackMixLevel.floorDB
    let tests: [(String, Bool)] = [
        ("1 is 0 dB", TrackMixLevel.decibels(1) == 0),
        ("0.5 is −6.02 dB", near(TrackMixLevel.decibels(0.5), -6.0206, 1e-4)),
        ("0 reads the floor", TrackMixLevel.decibels(0) == floor),
        ("under the floor reads the floor", TrackMixLevel.decibels(1e-5) == floor),
        ("the floor writes 0", TrackMixLevel.volume(floor) == 0),
        ("under the floor writes 0", TrackMixLevel.volume(-75) == 0),
        ("0 dB writes 1", TrackMixLevel.volume(0) == 1),
        ("−6.0206 dB writes 0.5", near(TrackMixLevel.volume(-6.020_599_913), 0.5, 1e-9)),
        ("+12 dB is the top", near(TrackMixLevel.volume(12), 3.981_071_7, 1e-6)),
        ("past the top is held", TrackMixLevel.volume(20) == TrackMixLevel.volume(12)),
        ("−59.9 dB is not off", TrackMixLevel.volume(-59.9) > 0),
        ("the floor reads Off", TrackMixLevel.readout(0) == "Off"),
        ("0.5 reads 50 %", TrackMixLevel.readout(0.5) == "50 %"),
        ("4 reads +12.04 dB", near(TrackMixLevel.decibels(4), 12.0412, 1e-4)),
    ]
    let failed = tests.filter { !$0.1 }.map(\.0)
    row("B4", failed.isEmpty,
        "\(tests.count - failed.count)/\(tests.count) mappings"
            + (failed.isEmpty ? "" : "; failed: " + failed.joined(separator: ", ")))
}
exit(0)
