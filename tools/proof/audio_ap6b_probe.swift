// tools/proof/audio_ap6b_probe.swift — the in-process instrument behind
// `audio_ap6b_probe.py` (road map "audio" AP6 part 2, spec §11 AU-66, AU-67).
// Compiled with every file in `app/Sources` but `main.swift` through
// `swift_build.py`'s line, copied in as `main.swift`.
//
//     audio-ap6b-probe <fixtures> <scratch> [--quick]
//
// One line per row, `  ok   <ID> <name>: <detail>` or `  FAIL <ID> …`, and
// `  note …` lines with the figures. `--quick` skips the step-2 figures and R5 (the
// probe document, its speech pass and its renders).
import AVFoundation
import Accelerate
import AppKit
import CoreMedia
import Foundation

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.prohibited)

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let quick = CommandLine.arguments.contains("--quick")
let fs = 48_000.0
let RATE = 48_000
let SEC: Ticks = 600_000

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
    fflush(stdout)
}
func f3(_ x: Double?) -> String { x.map { String(format: "%.3f", $0) } ?? "nil" }

// MARK: - Signals and drivers

func sine(_ n: Int, _ f: Double, _ amplitude: Double) -> [Float] {
    (0..<n).map { Float(amplitude * sin(2 * Double.pi * f * Double($0) / fs)) }
}
func add(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { $0 + $1 } }
func noise(_ n: Int, seed: UInt64, scale: Float) -> [Float] {
    var state = seed
    return (0..<n).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return (Float(Int64(bitPattern: state >> 11) % 2_000_000) / 1_000_000 - 1) * scale
    }
}

/// BS.1770 integrated loudness of planar `channels`, through the product's
/// meter (stereo sums the two channels' mean squares; mono is one channel).
func loudness(_ channels: [[Float]]) -> Double {
    let count = channels.count
    let frames = channels[0].count
    guard let meter = LoudnessMeter(sampleRate: fs, channelCount: count) else { return .nan }
    var interleaved = [Float](repeating: 0, count: frames * count)
    for i in 0..<frames { for c in 0..<count { interleaved[i * count + c] = channels[c][i] } }
    interleaved.withUnsafeBufferPointer { meter.feed($0.baseAddress!, frames: frames) }
    return meter.finish().integratedLUFS ?? .nan
}

final class Planar {
    let buffers: [UnsafeMutablePointer<Float>]
    let length: Int
    private let pointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>

    init(_ input: [[Float]]) {
        length = input.map(\.count).max() ?? 0
        buffers = input.map { channel in
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, channel.count))
            channel.withUnsafeBufferPointer {
                if let base = $0.baseAddress { buffer.initialize(from: base, count: $0.count) }
            }
            return buffer
        }
        pointers = .allocate(capacity: max(1, input.count))
    }
    deinit {
        buffers.forEach { $0.deallocate() }
        pointers.deallocate()
    }
    func at(_ position: Int) -> UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?> {
        for (c, buffer) in buffers.enumerated() { pointers[c] = buffer + position }
        return UnsafeMutableBufferPointer(start: pointers, count: buffers.count)
    }
    var arrays: [[Float]] { buffers.map { Array(UnsafeBufferPointer(start: $0, count: length)) } }
}

func rmsDB(_ y: ArraySlice<Float>) -> Double {
    10 * log10(y.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, y.count)) + 1e-30)
}

// MARK: - Tap contexts

/// A one-segment PlanSegment of `clip` at [start, start + duration).
func segment(clip: UInt32, start: Ticks, duration: Ticks) -> PlanSegment {
    let json = """
        {"clip": \(clip), "media": 1, "source_in": \(start), "source_duration": \(duration),
         "start": \(start), "duration": \(duration)}
        """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(PlanSegment.self, from: Data(json.utf8))
}

func project(_ clips: String, nests: String = "[]") -> ReelProject? {
    do {
        return try ReelProject.from(json: """
            {"version": \(RC_FORMAT_VERSION),
             "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
             "media": [{"id": 1, "path": "/fixtures/ap6b.wav", "kind": "audio",
                        "duration": \(60 * SEC), "has_video": false, "has_audio": true}],
             "tracks": [{"id": 3, "name": "Track 1"}, {"id": 8, "name": "Track 2"}],
             "clips": [\(clips)], "nests": \(nests), "next_id": 100}
            """)
    } catch {
        print("  note project: \(error)")
        return nil
    }
}

// MARK: - Curves and caches

/// The mean-square energy of a loudness, `StepLoudness.loudness`'s inverse.
func energy(_ lufs: Double) -> Double { pow(10, (lufs - LoudnessMeter.offset) / 10) }
let STEP = ClipLoudness.stepTicks
let RESPONSE: Ticks = 1_200_000

/// The settings of `props` over a single curve made for its response.
func settings(_ curve: AudioLevellerCurve, _ props: LevellerProps = LevellerProps())
    -> AudioLevellerSettings?
{
    AudioLevellerSettings(props: props, curves: [AudioLevellerSettings.response(props): curve])
}
/// The gain in dB a run's settings give at r.
func gainDB(_ s: AudioLevellerSettings?, _ r: Double) -> Double {
    s.map { 20 * log10(Double($0.gain(Float(r)))) } ?? .nan
}
/// A one-segment curve over `values` from tick 0.
func flat(_ values: [Double]) -> AudioLevellerCurve {
    AudioLevellerCurve(
        segments: [AudioLevellerCurve.Segment(start: 0, first: 0, count: values.count)],
        values: values.map { Float($0) })
}

/// A project over the real `file` (media 1, `duration` ticks, `speech` its saved spans).
func fileProject(_ file: URL, duration: Ticks, speech: [[Ticks]]? = nil, clips: String,
                 nests: String = "[]") -> ReelProject? {
    let spans = speech.map { s in
        ", \"speech\": [" + s.map { "[\($0[0]), \($0[1])]" }.joined(separator: ", ") + "]"
    } ?? ""
    do {
        return try ReelProject.from(json: """
            {"version": \(RC_FORMAT_VERSION),
             "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
             "media": [{"id": 1, "path": "\(file.path)", "kind": "audio",
                        "duration": \(duration), "has_video": false, "has_audio": true\(spans)}],
             "tracks": [{"id": 3, "name": "T1"}, {"id": 8, "name": "T2"}, {"id": 9, "name": "T3"},
                        {"id": 10, "name": "T4"}],
             "clips": [\(clips)], "nests": \(nests), "next_id": 100}
            """)
    } catch {
        print("  note project: \(error)")
        return nil
    }
}

final class TrackBox: @unchecked Sendable { var track: AVAssetTrack? }
final class ResultBox: @unchecked Sendable { var value = false }

func duration(_ url: URL) -> Ticks? {
    let asset = AVURLAsset(url: url)
    let box = TrackBox()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.track = (try? await asset.loadTracks(withMediaType: .audio))?.first
        done.signal()
    }
    done.wait()
    guard let track = box.track else { return nil }
    let seconds = CMTimeGetSeconds(track.timeRange.duration)
    return seconds.isFinite ? Ticks((seconds * Double(SEC)).rounded(.down)) : nil
}

/// `file`'s loudness (and, with `speech`, its VAD) cache written into a fresh `name` folder.
func cacheFolder(_ name: String, _ file: URL, length: Ticks, loudness: Bool, speech: Bool) -> URL {
    let folder = scratch.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: folder)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let snapshot = MediaSnapshot(id: 1, path: file.path, kind: .audio, duration: length,
                                 hasVideo: false, hasAudio: true)
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        let stamp = MediaImporter.CacheStamp.stamp(for: snapshot, url: file)
        if loudness {
            _ = await MediaImporter.loudness(for: snapshot, url: file, stamp: stamp, into: folder)
        }
        if speech { await MediaImporter.speech(for: snapshot, url: file, stamp: stamp, into: folder) }
        done.signal()
    }
    _ = done.wait(timeout: .now() + 600)
    return folder
}

// MARK: - L1 constant speech, the speech-only window, one channel

do {
    let L = -30.0
    var detail: [String] = []
    var good = true
    for x in [-9.0, -3.0, 3.0, -20.0] {
        let steps = [Double](repeating: energy(L + x), count: 1000)
        let r = AudioLevellerCurve.relative(
            steps: steps, speech: [Bool](repeating: true, count: 1000), level: L,
            response: RESPONSE) ?? []
        let worst = r.map { abs($0 - x) }.max() ?? .infinity
        let s = settings(flat(r))
        let got = gainDB(s, r.first ?? .nan)
        let want = min(max(-x, -12), 12)
        good = good && worst <= 0.01 && abs(got - want) <= 0.01
        detail.append("x \(Int(x)): r ±\(f3(worst)), gain \(f3(got)) (want \(f3(want)))")
    }
    // 0.7 s of speech at L − 6, 0.3 s silent, by turns: one phrase, the window speech-only.
    var steps: [Double] = []
    var speech: [Bool] = []
    for _ in 0..<10 {
        steps += [Double](repeating: energy(L - 6), count: 70) + [Double](repeating: 1e-12, count: 30)
        speech += [Bool](repeating: true, count: 100)
    }
    let r = AudioLevellerCurve.relative(steps: steps, speech: speech, level: L, response: RESPONSE)
        ?? []
    let gapped = r.map { abs($0 + 6) }.max() ?? .infinity
    good = good && gapped <= 0.01
    detail.append("0.3 s gaps: r ±\(f3(gapped)) of −6")
    // One channel against its dual-mono stereo copy, through ClipLoudness.
    let count = 600
    let z = (0..<count).map { Float(energy(L + 4 * sin(Double($0) / 37)) / 2) }
    let mono = MediaLoudness(channels: 1, count: count, records: z.flatMap { [$0, 0.1, 0] })
    let stereo = MediaLoudness(
        channels: 2, count: count, records: z.flatMap { [$0, $0, $0, 0.1, 0.1, 0, 0, 0] })
    let seg = segment(clip: 2, start: 0, duration: Ticks(count) * STEP)
    let a = ClipLoudness.reading(mono, segments: [seg], pivots: [nil], matrix: .identity)
    let b = ClipLoudness.reading(stereo, segments: [seg], pivots: [nil], matrix: .identity)
    let all = [Bool](repeating: true, count: count)
    let ca = a.lufs.flatMap {
        AudioLevellerCurve.make(reading: a, segments: [seg], speech: all, level: $0,
                                response: RESPONSE)
    }
    let cb = b.lufs.flatMap {
        AudioLevellerCurve.make(reading: b, segments: [seg], speech: all, level: $0,
                                response: RESPONSE)
    }
    let matches = ca != nil && ca == cb && a.lufs == b.lufs
    good = good && matches
    detail.append("one channel = its dual mono \(matches) (L \(f3(a.lufs)) / \(f3(b.lufs)))")
    check("L1", "constant speech at L − 9, − 3, + 3, − 20: r = x ±0.01 and the gain clamp(target "
            + "− r, −down, +up) ±0.01 dB; 0.3 s gaps change nothing; one channel = dual mono",
          good, detail.joined(separator: ", "))
}

// MARK: - L2 phrases, breaks and short phrases

do {
    let L = -30.0
    // A 5 s at L − 6, a 1.5 s break, B 5 s at L + 6.
    let steps = [Double](repeating: energy(L - 6), count: 500)
        + [Double](repeating: 1e-12, count: 150) + [Double](repeating: energy(L + 6), count: 500)
    let all = [Bool](repeating: true, count: steps.count)
    let r = AudioLevellerCurve.relative(steps: steps, speech: all, level: L, response: RESPONSE)
        ?? []
    let s = settings(flat(r))
    var good = r.count == steps.count
    var detail: [String] = []
    if good {
        let a = r[499]
        let b = r[1149]
        let first = abs(gainDB(s, r[650]) - gainDB(s, b))
        let held = (500..<(650 - 25)).map { abs(r[$0] - a) }.max() ?? .infinity
        var glide = 0.0
        var inside = true
        for k in (650 - 25)..<650 {
            let want = a + (b - a) * Double(25 - (650 - k)) / 25
            glide = max(glide, abs(r[k] - want))
            inside = inside && r[k] >= min(a, b) - 1e-9 && r[k] <= max(a, b) + 1e-9
        }
        good = first <= 0.01 && held <= 0.001 && glide <= 0.001 && inside
        detail.append("A \(f3(a)), B \(f3(b)); B's first step's gain off its settled by "
            + "\(f3(first)) dB; held ±\(f3(held)); the glide ±\(f3(glide)), inside \(inside)")
    }
    // A, a 1 s break, a 0.5 s phrase at L + 10, a 1 s break, B.
    let short = [Double](repeating: energy(L - 6), count: 500)
        + [Double](repeating: 1e-12, count: 100) + [Double](repeating: energy(L + 10), count: 50)
        + [Double](repeating: 1e-12, count: 100) + [Double](repeating: energy(L + 6), count: 500)
    let q = AudioLevellerCurve.relative(
        steps: short, speech: [Bool](repeating: true, count: short.count), level: L,
        response: RESPONSE) ?? []
    let taken = q.count == short.count ? (600..<650).map { abs(q[$0] - q[499]) }.max() ?? 1 : 1
    good = good && taken <= 0.001
    detail.append("the 0.5 s phrase takes A's value ±\(f3(taken))")
    check("L2", "two phrases 12 dB apart across a 1.5 s break: B starts at its settled gain, the "
            + "break holds A then glides its last 0.25 s inside [A, B]; a 0.5 s phrase takes A's",
          good, detail.joined(separator: ", "))
}

// MARK: - L3 the smoothing is zero-phase

do {
    let tau = 50.0
    let u = [Double](repeating: 0, count: 500) + [Double](repeating: 1, count: 500)
    let r = AudioLevellerCurve.smooth(u, tau: tau)
    let mid = max(abs(r[499] - 0.5), abs(r[500] - 0.5))
    let up = (500..<1000).first { r[$0] >= 0.9 }.map { Double($0) - 499.5 } ?? .infinity
    let down = (0..<500).last { r[$0] <= 0.1 }.map { 499.5 - Double($0) } ?? .infinity
    let want = tau * log(5)
    check("L3", "a step smoothed is the midpoint ±0.01 at the step and 90 % at τ·ln 5 ±1 step "
            + "on both sides",
          mid <= 0.01 && abs(up - want) <= 1 && abs(down - want) <= 1,
          "midpoint ±\(f3(mid)); 90 % at +\(f3(up)) and −\(f3(down)) steps (τ·ln 5 = "
            + "\(f3(want)))")
}

// MARK: - L4 block sizes, a mid-clip start, nil settings

/// `input` (two channels) from timeline frame `from` through a tap built on `track`, in
/// buffers of the sizes `sizes` cycles through.
func tapped(_ track: AudioTrackDSP, _ input: [[Float]], sizes: [Int], from: Int = 0)
    -> [[Float]]
{
    let context = AudioTapContext(track: track, isolation: nil, meter: nil)
    context.prepare(
        channelCount: 2, sampleRate: fs, maxFrames: 4096,
        formatFlags: AudioFormatFlags(kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved),
        bitsPerChannel: 32)
    let total = input[0].count
    var out = [[Float]](repeating: [Float](repeating: 0, count: total), count: 2)
    let list = AudioBufferList.allocate(maximumBuffers: 2)
    let l = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    var position = 0
    var turn = 0
    while position < total {
        let frames = min(sizes[turn % sizes.count], total - position)
        turn += 1
        for i in 0..<frames {
            l[i] = input[0][position + i]
            r[i] = input[1][position + i]
        }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: l)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: r)
        context.process(
            list.unsafeMutablePointer, frames: frames,
            time: CMTime(value: Int64(from + position), timescale: CMTimeScale(RATE)),
            startOfStream: position == 0)
        for i in 0..<frames {
            out[0][position + i] = l[i]
            out[1][position + i] = r[i]
        }
        position += frames
    }
    l.deallocate()
    r.deallocate()
    free(list.unsafeMutablePointer)
    return out
}

do {
    let n = 6 * RATE
    let input = [add(sine(n, 700, 0.03), noise(n, seed: 3, scale: 0.01)),
                 add(sine(n, 300, 0.02), noise(n, seed: 4, scale: 0.01))]
    let curve = flat((0..<600).map { -6 + 5 * sin(Double($0) / 23) })
    var good = true
    var detail: [String] = []
    if let p = project("""
        {"id": 2, "track": 3, "start": 0, "duration": \(6 * SEC),
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"leveller": {}},
         "actions": [{"id": 9, "start": \(SEC), "duration": \(2 * SEC), "curve": "linear",
                      "end": {"audio": {"leveller": {"target_db": -6}}}}]}
        """), let segments = p.plan?.audioTracks.first?.segments
    {
        let parameters = AudioDSPParameters(
            snapshot: p.snapshot, curves: [2: .ready([RESPONSE: curve])])
        let track = AudioTrackDSP(segments: segments, parameters: parameters)
        let small = tapped(track, input, sizes: [512])
        let large = tapped(track, input, sizes: [4096])
        let odd = tapped(track, input, sizes: [1000, 37, 2048, 333, 4096, 1, 777])
        let automated = track.spans.first?.automation != nil
        let same = small == large && small == odd && small != input
        // From 2.5 s, inside the action: the same frames as from the clip's start.
        let at = 5 * RATE / 2
        let late = tapped(track, input.map { Array($0[at...]) }, sizes: [1000, 333], from: at)
        let mid = late[0] == Array(small[0][at...]) && late[1] == Array(small[1][at...])
        // Pending: no curve, so nothing runs.
        let pending = AudioDSPParameters(
            snapshot: p.snapshot, curves: [2: .pending(what: "speech")])
        let untouched = tapped(
            AudioTrackDSP(segments: segments, parameters: pending), input, sizes: [512]) == input
        // After the action (target −6): each sample's gain is the curve's at its own frame.
        var followed = 0.0
        if let s = settings(curve, LevellerProps(targetDb: -6)) {
            for f in stride(from: 7 * RATE / 2, to: 11 * RATE / 2, by: 997)
            where abs(input[0][f]) > 0.005 {
                let got = 20 * log10(Double(abs(small[0][f] / input[0][f])))
                let want = gainDB(s, curve.value(atTick: Double(f) * Double(SEC) / fs))
                followed = max(followed, abs(got - want))
            }
        } else {
            followed = .infinity
        }
        good = same && automated && mid && untouched && followed <= 0.01
        detail.append("automated \(automated); 512 = 4096 \(small == large), 512 = irregular "
            + "\(small == odd); from 2.5 s = from 0 \(mid); no curve touches nothing \(untouched); "
            + "the gain follows the curve at its frame ±\(f3(followed)) dB")
    } else {
        good = false
        detail.append("the project or its plan did not build")
    }
    check("L4", "512, 4096 and irregular buffers byte-identical through the tap (target "
            + "automated); a run from mid-clip = the same frames from its start; nil touches nothing; "
            + "each sample's gain the curve's at its own frame",
          good, detail.joined(separator: ", "))
}

// MARK: - L5 the order: after the gate

do {
    let n = 8 * RATE
    let bed = [noise(n, seed: 11, scale: 0.02), noise(n, seed: 12, scale: 0.02)]
    let level = loudness(bed) + 22  // the noise at L − 22
    let gate = AudioGateSettings(level: level, props: GateProps(thresholdDb: -15, rangeDb: 20))
    let lift = settings(flat([Double](repeating: -12, count: 800)))  // +12 dB everywhere
    func chained(_ params: AudioClipDSP, leveller: AudioLevellerSettings?, first: Bool = false)
        -> [[Float]]
    {
        let chain = AudioDSPChain(
            channelCount: 2, sampleRate: fs, maxFrames: 4096, usesNoiseReduction: false)
        let planar = Planar(bed)
        var position = 0
        while position < n {
            let size = min(512, n - position)
            let run = leveller.map {
                AudioLevellerRun(settings: $0, firstFrame: Int64(position), rate: Int64(RATE))
            }
            // A leveller before the gate, by hand: what AU-66 (a) rules out.
            if first, let run { run.apply(planar.at(position), count: 2, frames: size) }
            chain.process(planar.at(position), frames: size, params: params,
                          leveller: first ? nil : run)
            position += size
        }
        return planar.arrays
    }
    let both = chained(AudioClipDSP(gate: gate), leveller: lift)
    let gated = chained(AudioClipDSP(gate: gate), leveller: nil)
    let before = chained(AudioClipDSP(gate: gate), leveller: lift, first: true)
    let tail = (n - 2 * RATE)..<n
    let held = rmsDB(both[0][tail]) - rmsDB(gated[0][tail])
    let opened = rmsDB(before[0][tail]) - rmsDB(bed[0][tail])
    check("L5", "a pause at L − 22 under a 20 dB gate stays gated with the leveller at +12 dB "
            + "after it; before the gate it would open it",
          abs(held - 12) <= 1 && opened >= 6,
          "after the gate \(f3(held)) dB over the gate alone (12 ±1); a leveller before the "
            + "gate \(f3(opened)) dB over the input (≥ 6)")
}

// MARK: - L6 the curves' resolution

/// L6's steady fixture, its length and its loudness-and-speech cache, which L10 reuses.
var l6Fixture: (file: URL, length: Ticks, both: URL)?
do {
    let file = fixtures.appendingPathComponent("ap6b-steady.wav")
    let length = (duration(file) ?? 0) / 20_000 * 20_000
    let empty = cacheFolder("l6-empty", file, length: length, loudness: false, speech: false)
    let loud = cacheFolder("l6-loudness", file, length: length, loudness: true, speech: false)
    let both = cacheFolder("l6-both", file, length: length, loudness: true, speech: true)
    l6Fixture = (file, length, both)
    let clips = """
        {"id": 2, "track": 3, "start": 0, "duration": \(30 * SEC),
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"leveller": {}}},
        {"id": 4, "track": 8, "start": 0, "duration": \(30 * SEC),
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {},
         "actions": [{"id": 90, "start": \(SEC), "duration": \(SEC), "curve": "linear",
                      "end": {"audio": {"leveller": {}}}}]},
        {"id": 6, "track": 10, "start": 0, "duration": \(2 * SEC),
         "source": {"kind": "nest", "project": 20}, "audio": {"leveller": {}}},
        {"id": 7, "track": 9, "start": 0, "duration": \(30 * SEC),
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"leveller": {}},
         "actions": [{"id": 91, "start": \(SEC), "duration": \(SEC), "curve": "linear",
                      "end": {"audio": {"leveller": {"response": 2400000}}}}]}
        """
    let nests = """
        [{"id": 20, "name": "Nest 20", "width": 320, "height": 180,
          "tracks": [{"id": 21, "name": "Track 1"}],
          "clips": [{"id": 22, "track": 21, "start": 0, "duration": \(2 * SEC),
                     "source": {"kind": "media", "media": 1, "in": 0}}]}]
        """
    let levels = AudioDynamicsLevels.shared
    var detail: [String] = []
    var good = false
    var crumbSpans: [[Ticks]] = []
    for start in stride(from: Ticks(0), to: Ticks(30) * SEC, by: 900_000) {
        crumbSpans.append([start, start + SEC / 2])
    }
    if let p = fileProject(file, duration: length, clips: clips, nests: nests),
        let first = fileProject(file, duration: length, speech: [[0, 15 * SEC]], clips: clips,
                                nests: nests),
        let whole = fileProject(file, duration: length, speech: [[0, length]], clips: clips,
                                nests: nests),
        let crumbs = fileProject(
            file, duration: length,
            speech: crumbSpans, clips: clips, nests: nests)
    {
        let noLoudness = levels.curves(for: p, cache: empty, speechDetection: true)[2]
        let noSpeech = levels.curves(for: p, cache: loud, speechDetection: true)[2]
        let unavailableAll = levels.curves(for: p, cache: loud, speechDetection: false)
        let unavailable = unavailableAll[2]
        let notPending = !AudioDSPParameters(
            snapshot: p.snapshot, levels: levels.levels(for: p, cache: loud),
            curves: unavailableAll).pendingLevels.contains(2)
        func ready(_ c: AudioDynamicsLevels.Curves?) -> [Ticks: AudioLevellerCurve]? {
            if case .ready(let made)? = c { return made }
            return nil
        }
        let savedOn = ready(levels.curves(for: whole, cache: loud, speechDetection: true)[2]) != nil
        let savedOff = ready(levels.curves(for: whole, cache: loud, speechDetection: false)[2])
            != nil
        let all = levels.curves(for: p, cache: both, speechDetection: true)
        let vad = ready(all[2])?[RESPONSE]
        let saved = ready(levels.curves(for: first, cache: both, speechDetection: true)[2])?[RESPONSE]
        let again = ready(levels.curves(for: whole, cache: both, speechDetection: true)[2])?[RESPONSE]
        let overVAD = vad != nil && saved != nil && saved != vad
        let recomputed = saved != nil && again != nil && again != saved
        let noPhrase = levels.curves(for: crumbs, cache: both, speechDetection: true)[2]
        let nestAbsent = all[6] == nil
        let levelling = AudioDynamicsLevels.levelling(p.snapshot).map(\.id).sorted()
        let wanting = AudioDynamicsLevels.wanting(p.snapshot).map(\.id).sorted()
        let responses = ready(all[7]).map { Set($0.keys) } ?? []
        let pending = AudioDSPParameters(
            snapshot: p.snapshot, curves: [2: .pending(what: "speech")]).pendingLevels
        let waits = noLoudness == .pending(what: "loudness") && noSpeech == .pending(what: "speech")
        let absent = unavailable == .unmeasurable(reason: "speech detection is unavailable")
            && notPending
        let spans = savedOn && savedOff && vad != nil && overVAD && recomputed
        let short = noPhrase == .unmeasurable(reason: "it has no phrase with 1 s of speech")
        let which = nestAbsent && levelling == [2, 4, 7] && wanting.contains(4)
        let ends = responses == Set([RESPONSE, 2_400_000]) && pending.contains(2)
        good = waits && absent && spans && short && which && ends
        detail = [
            "no loudness \(String(describing: noLoudness))",
            "no spans \(String(describing: noSpeech))",
            "detection unavailable \(String(describing: unavailable)), not pending \(notPending)",
            "media.speech ready either way \(savedOn)/\(savedOff)",
            "both ready \(vad != nil)", "media.speech over the VAD \(overVAD)",
            "a new media.speech recomputes \(recomputed)",
            "no long phrase \(String(describing: noPhrase))", "nest absent \(nestAbsent)",
            "levelling \(levelling), wanting has 4 \(wanting.contains(4))",
            "clip 7's responses \(responses.sorted())", "pending in pendingLevels \(pending)",
        ]
    } else {
        detail = ["the projects did not build"]
    }
    check("L6", "curves: pending on loudness then speech; unmeasurable, not pending, with speech "
            + "detection unavailable; media.speech used and remembered; no long phrase; nest "
            + "absent; end-only leveller; an end's response; pending in pendingLevels",
          good, detail.joined(separator: "; "))
}

// MARK: - L10 a Target or cap edit inside an action remakes no curve (#413, AU-66 (e))

do {
    var detail: [String] = []
    var good = false
    /// Clip 2 levelled on its base; clip 4 by action 90's end, `end` its leveller.
    func levelled(_ end: String, clip4: Ticks = 30 * SEC) -> ReelProject? {
        guard let fixture = l6Fixture else { return nil }
        return fileProject(fixture.file, duration: fixture.length, clips: """
            {"id": 2, "track": 3, "start": 0, "duration": \(30 * SEC),
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"leveller": {}}},
            {"id": 4, "track": 8, "start": 0, "duration": \(clip4),
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": {},
             "actions": [{"id": 90, "start": \(SEC), "duration": \(SEC), "curve": "linear",
                          "end": {"audio": {"leveller": \(end)}}}]}
            """)
    }
    let levels = AudioDynamicsLevels.shared
    if let both = l6Fixture?.both, let before = levelled("{}"),
       let edited = levelled("{\"target_db\": 3, \"max_up_db\": 6}"),
       let trimmed = levelled("{\"target_db\": 3, \"max_up_db\": 6}", clip4: 29 * SEC)
    {
        let first = levels.curves(for: before, cache: both, speechDetection: true)
        let built = levels.curveBuilds
        let second = levels.curves(for: edited, cache: both, speechDetection: true)
        let reused = levels.curveBuilds - built
        let planMoved = before.planJSON != edited.planJSON
        let ready = [2, 4].allSatisfy { id -> Bool in
            if case .ready? = first[UInt32(id)] { return true }
            return false
        }
        let equal = first[2] == second[2] && first[4] == second[4]
        let builtBefore = levels.curveBuilds
        _ = levels.curves(for: trimmed, cache: both, speechDetection: true)
        let control = levels.curveBuilds - builtBefore
        good = planMoved && ready && reused == 0 && equal && control >= 1
        detail = [
            "plan text moved \(planMoved)", "both clips ready \(ready)",
            "curves made across the Target edit \(reused)", "the curves equal \(equal)",
            "clip 4 trimmed to 29 s made \(control)",
        ]
    } else {
        detail = ["the projects did not build"]
    }
    check("L10", "a Target and cap edit inside an action moves the plan's automation and remakes "
            + "no curve; a trim remakes them", good, detail.joined(separator: "; "))
}

// MARK: - L7 interpolation

do {
    let a = AudioProps(leveller: LevellerProps(
        targetDb: 0, maxUpDb: 12, maxDownDb: 12, response: 1_200_000))
    let b = AudioProps(leveller: LevellerProps(
        targetDb: -6, maxUpDb: 6, maxDownDb: 18, response: 2_400_000))
    let half = a.interpolated(toward: b, by: 0.5).leveller
    let leftOnly = a.interpolated(toward: AudioProps(), by: 0.5).leveller
    let rightOnly = AudioProps().interpolated(toward: b, by: 0.5).leveller
    let good = half == LevellerProps(targetDb: -3, maxUpDb: 9, maxDownDb: 15, response: 1_200_000)
        && leftOnly == a.leveller && rightOnly == nil
    check("L7", "`interpolated` mixes the target and the limits, the response the left point's, "
            + "presence from the left", good, "\(String(describing: half))")
}

// MARK: - L8 the cost

do {
    // One hour: 8 s phrases drifting ±6 dB, 1 s pauses.
    let count = 360_000
    let L = -30.0
    var steps = [Double](repeating: 1e-12, count: count)
    for k in 0..<count where k % 900 < 800 { steps[k] = energy(L + 6 * sin(Double(k) / 3000)) }
    let reading = ClipLoudness.Reading(
        lufs: L, truePeak: 0.5, playedTicks: Ticks(count) * STEP, steps: steps,
        stepPeaks: [Double](repeating: 0.25, count: count),
        stepSources: (0..<count).map { Ticks($0) * STEP },
        stepHighs: [Double](repeating: 0, count: count))
    let hour = segment(clip: 2, start: 0, duration: Ticks(count) * STEP)
    let mask = [Bool](repeating: true, count: count)
    var made: AudioLevellerCurve?
    var bestMake = Double.infinity
    for _ in 0..<3 {
        let begin = DispatchTime.now().uptimeNanoseconds
        made = AudioLevellerCurve.make(
            reading: reading, segments: [hour], speech: mask, level: L, response: RESPONSE)
        bestMake = min(bestMake, Double(DispatchTime.now().uptimeNanoseconds - begin) / 1e6)
    }
    var share = Double.infinity
    var best = Double.infinity
    let rounds = 2_000
    if let made, let s = settings(made) {
        let planar = Planar([sine(1024, 700, 0.05), sine(1024, 300, 0.05)])
        for _ in 0..<3 {
            let begin = DispatchTime.now().uptimeNanoseconds
            let pointers = planar.at(0)
            for round in 0..<rounds {
                AudioLevellerRun(settings: s, firstFrame: Int64(round * 1024 + 7), rate: Int64(RATE))
                    .apply(pointers, count: 2, frames: 1024)
            }
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - begin) / 1000
                / Double(rounds))
        }
        share = best / (1024 / fs * 1_000_000) * 100
    }
    check("L8", "a 1-hour clip's curve in ≤ 100 ms (best of 3), and a run ≤ 1 % of real time "
            + "per 1024 stereo frames", bestMake <= 100 && share <= 1,
          String(format: "curve %.1f ms; run %.1f µs (best of 3 × %d), %.3f %% of real time",
                 bestMake, best, rounds, share))
}

// MARK: - L9 reversed and ×2 clips are measured on what plays

do {
    let file = fixtures.appendingPathComponent("ap6b-offmic.wav")
    let length = (duration(file) ?? 0) / 20_000 * 20_000
    let cache = cacheFolder("l9", file, length: length, loudness: true, speech: false)
    // The fixture's known speech, as saved spans.
    let spans: [[Ticks]] = (0..<6).map { k in
        let start = Ticks((0.5 + Double(k) * 11.5) * Double(SEC))
        return [start, start + 10 * SEC]
    }
    let whole = length / 20_000 * 20_000
    let clips = """
        {"id": 2, "track": 3, "start": 0, "duration": \(whole),
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"leveller": {}}},
        {"id": 4, "track": 8, "start": 0, "duration": \(whole),
         "source": {"kind": "media", "media": 1, "in": 0, "reversed": true},
         "audio": {"leveller": {}}},
        {"id": 7, "track": 9, "start": 0, "duration": \(whole / 2 / 20_000 * 20_000),
         "speed": 2.0, "source": {"kind": "media", "media": 1, "in": 0},
         "audio": {"leveller": {}}}
        """
    var detail: [String] = []
    var good = false
    if let p = fileProject(file, duration: length, speech: spans, clips: clips) {
        let curves = AudioDynamicsLevels.shared.curves(for: p, cache: cache, speechDetection: true)
        /// The gain at the middle of each of the first two phrases played, at `at` seconds of
        /// the timeline (a `say` sentence is padded to 10 s, so a reversed phrase opens on
        /// the padding's bed).
        func starts(_ clip: UInt32, _ at: [Double]) -> [Double] {
            guard case .ready(let made)? = curves[clip], let curve = made[RESPONSE],
                let s = settings(curve)
            else { return [] }
            return at.map { gainDB(s, curve.value(atTick: $0 * Double(SEC))) }
        }
        // Forward the phrases' middles play at 5.5 s and 17 s; reversed, the file's last two
        // (58–68 s, 46.5–56.5 s) at length − 63 and length − 51.5; at ×2 at 2.75 and 8.5 s.
        let tail = Double(length) / Double(SEC)
        let forward = starts(2, [5.5, 17.0])
        let reversed = starts(4, [tail - 63, tail - 51.5])
        let fast = starts(7, [2.75, 8.5])
        // Forward: loud then quiet; reversed: the quiet last segment plays first.
        good = forward.count == 2 && reversed.count == 2 && fast.count == 2
            && forward[0] < 0 && forward[1] > 3 && reversed[0] > 3 && reversed[1] < 0
            && fast[0] < 0 && fast[1] > 3
        detail.append("the first two phrases' gains mid-phrase: forward \(forward.map(f3)), reversed "
            + "\(reversed.map(f3)), ×2 \(fast.map(f3))")
    } else {
        detail.append("the project did not build")
    }
    check("L9", "a reversed and a ×2 clip are levelled on their played steps: a quiet phrase "
            + "played first is boosted first", good, detail.joined(separator: ", "))
}

// MARK: - R1 the speech range

do {
    let flat = AudioEnhance.speechRange(
        steps: [Double](repeating: energy(-30), count: 600), speech: [Bool](repeating: true,
                                                                             count: 600))
    let halves = [Double](repeating: energy(-30), count: 1000)
        + [Double](repeating: energy(-42), count: 1000)
    let all = [Bool](repeating: true, count: 2000)
    let twelve = AudioEnhance.speechRange(steps: halves, speech: all)
    let loudOnly = AudioEnhance.speechRange(
        steps: halves, speech: [Bool](repeating: true, count: 1000)
            + [Bool](repeating: false, count: 1000))
    let short = AudioEnhance.speechRange(
        steps: halves, speech: [Bool](repeating: true, count: 299)
            + [Bool](repeating: false, count: 1701))
    let good = flat.map { abs($0) < 1e-9 } == true
        && twelve.map { abs($0 - 12) <= 0.1 } == true
        && loudOnly.map { abs($0) < 1e-9 } == true && short == nil
    check("R1", "speechRange: constant 0, two 10 s halves 12 dB apart 12.0 ±0.1, the mask "
            + "honoured, nil under 300 speech steps", good,
          "constant \(f3(flat)), halves \(f3(twelve)), loud half alone \(f3(loudOnly)), 299 "
            + "steps \(f3(short))")
}

// MARK: - R2 the rule

func measurement(range: Double?) -> AudioEnhance.Measurement {
    AudioEnhance.Measurement(
        lufs: -30, truePeak: 0.5, speechSteps: 1000, pauseSteps: 100, floorLUFS: -80,
        pausePeakMedianDB: -80, sibilantShare: 0, peakMedianDB: -12,
        speechRangeLU: range)
}

do {
    let under = AudioEnhance.levellerRule(measurement(range: 5.9))
    let over = AudioEnhance.levellerRule(measurement(range: 6.1))
    let none = AudioEnhance.levellerRule(measurement(range: nil))
    var underOff = false
    if case .some(.none) = under.leveller { underOff = true }
    var overOn = false
    if case .some(.some(let props)) = over.leveller { overOn = props == LevellerProps() }
    let good = underOff && overOn && none.leveller == nil
        && under.reason == "Leveler: the speech's short-term loudness range is 5.9 LU, at or "
            + "under 6 LU, so the leveler is off."
        && over.reason == "Leveler: the speech's short-term loudness range is 6.1 LU, above 6 "
            + "LU, so the leveler is on at its defaults."
        && none.reason == "Leveler: under 3 s of speech, so there is no short-term loudness "
            + "range to measure; the leveler is left as it is."
    check("R2", "the rule at 5.9 (off), 6.1 (on at its defaults) and with no range (left out), "
            + "each with its sentence", good,
          [under.reason, over.reason, none.reason].joined(separator: " | "))
}

// MARK: - R3 rendering

do {
    let renders = ProcessedLoudness.needsRender(AudioProps(leveller: LevellerProps()))
    var differ = false
    if let plain = project("""
        {"id": 2, "track": 3, "start": 0, "duration": \(4 * SEC),
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"gate": {}}}
        """), let levelled = project("""
        {"id": 2, "track": 3, "start": 0, "duration": \(4 * SEC),
         "source": {"kind": "media", "media": 1, "in": 0},
         "audio": {"gate": {}, "leveller": {}}}
        """),
        let a = ProcessedLoudness.key(clip: 2, project: plain, document: 0),
        let b = ProcessedLoudness.key(clip: 2, project: levelled, document: 0)
    {
        differ = a.plan == b.plan && a.chain != b.chain
    }
    check("R3", "needsRender is true for a leveller alone, and the memo key's chain carries it",
          renders && differ, "needsRender \(renders), keys differ by the chain \(differ)")
}

// MARK: - R4 choose twice

do {
    // 600 speech steps, 300 at L and 300 at L − 12, then 100 pause steps.
    var steps = [Double](repeating: energy(-30), count: 300)
        + [Double](repeating: energy(-42), count: 300)
    steps += [Double](repeating: energy(-80), count: 100)
    let mask = [Bool](repeating: true, count: 600) + [Bool](repeating: false, count: 100)
    let reading = ClipLoudness.Reading(
        lufs: -32, truePeak: 0.5, playedTicks: Ticks(steps.count) * 6000, steps: steps,
        stepPeaks: steps.map { _ in 0.25 }, stepSources: steps.indices.map { Ticks($0) * 6000 },
        stepHighs: steps.map { _ in 0 })
    var good = false
    var detail = "no measurement"
    if let m = AudioEnhance.measure(reading, speech: mask) {
        let input = AudioEnhance.Input(
            readings: [AudioEnhance.Reading(clip: 7, media: 1, measurement: m, loudness: reading,
                                            current: AudioProps())], problems: [])
        let once = AudioEnhance.choose(input)
        let twice = AudioEnhance.choose(input)
        var on = false
        if case .some(.some(let props)) = once.first?.patch.leveller {
            on = props == LevellerProps()
        }
        good = once == twice && on
        detail = "range \(f3(m.speechRangeLU)), leveller on \(on), equal \(once == twice)"
    }
    check("R4", "choose over one input twice is equal, the leveller on above 6 LU", good, detail)
}

// MARK: - The step-2 figures: the owner's recording and the proof's fixtures

// MARK: - The step-2 figures and R5: the owner's recording and the proof's fixtures

if !quick {
    let files: [(UInt32, String)] = [(91, "rode.m4a"), (92, "ap6b-offmic.wav"),
                                     (93, "ap6b-steady.wav")]
    let package = scratch.appendingPathComponent("ranges.framejob", isDirectory: true)
    try? FileManager.default.removeItem(at: package)
    try? FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    var media: [[String: Any]] = []
    var clips: [[String: Any]] = []
    var snapshots: [UInt32: MediaSnapshot] = [:]
    for (index, (id, name)) in files.enumerated() {
        let url = fixtures.appendingPathComponent(name)
        let length = (duration(url) ?? 0) / 20_000 * 20_000
        media.append(["id": Int(id), "path": url.path, "kind": "audio", "duration": Int(length),
                      "has_video": false, "has_audio": true])
        clips.append(["id": Int(id) + 100, "track": 11 + index, "start": 0,
                      "duration": Int(length),
                      "source": ["kind": "media", "media": Int(id), "in": 0], "audio": [:]])
        snapshots[id] = MediaSnapshot(id: id, path: url.path, kind: .audio, duration: length,
                                      hasVideo: false, hasAudio: true)
    }
    let projectJSON: [String: Any] = [
        "version": Int(RC_FORMAT_VERSION),
        "canvas": ["width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]],
        "media": media, "tracks": (11...13).map { ["id": $0, "name": "Track \($0)"] },
        "clips": clips, "markers": [], "next_id": 300, "nests": []]
    try! JSONSerialization.data(withJSONObject: projectJSON)
        .write(to: package.appendingPathComponent("project.json"))
    let document = ProjectDocument()
    do {
        try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        print("  note step2: the probe document did not open: \(error)")
    }
    if let cache = document.cacheDirectory {
        for (id, name) in files {
            let url = fixtures.appendingPathComponent(name)
            guard let snapshot = snapshots[id] else { continue }
            let done = DispatchSemaphore(value: 0)
            let box = ResultBox()
            Task.detached {
                let stamp = MediaImporter.CacheStamp.stamp(for: snapshot, url: url)
                box.value = await MediaImporter.loudness(
                    for: snapshot, url: url, stamp: stamp, into: cache)
                await MediaImporter.speech(for: snapshot, url: url, stamp: stamp, into: cache)
                done.signal()
            }
            _ = done.wait(timeout: .now() + 600)
        }
        let input = AudioEnhance.read(from: document, clips: files.map { $0.0 + 100 })
        for (id, name) in files {
            let range = input?.readings.first { $0.clip == id + 100 }?.measurement.speechRangeLU
            print("  note step2 \(name) speech_range_lu \(f3(range))")
        }
        for problem in input?.problems ?? [] { print("  note step2 skipped \(problem.description)") }
    
        // R5 (AP6b step 3, AU-64 (f)): the steady fixture's Enhance trial rendered three times
        // through `ProcessedLoudness.render`, the isolated render wiped before the third.
        document.publishReverseResolution()
        let resolution = ReverseSource.shared.resolution(for: document.recipeKey)
        var renders: [[Double]] = []
        var why = ""
        if let read = AudioEnhance.read(from: document, clips: [193]),
            var patch = AudioEnhance.choose(read).first?.patch
        {
            patch.limiter = .some(nil)
            patch.volume = 1
            if let trial = LoudnessMeasureRun.trial(
                base: document.project, scope: nil, clip: 193, patch: patch)
            {
                for round in 0..<3 {
                    if round == 2, let folder = resolution.isolated {
                        for name in (try? FileManager.default.contentsOfDirectory(
                            atPath: folder.path)) ?? []
                        {
                            try? FileManager.default.removeItem(
                                at: folder.appendingPathComponent(name))
                        }
                    }
                    let urls = document.mediaURLs()
                    let done = DispatchSemaphore(value: 0)
                    nonisolated(unsafe) var answer: ProcessedLoudness.Rendered = .cancelled
                    nonisolated(unsafe) var key = 0
                    ProcessedLoudness.queue.async {
                        (answer, key) = ProcessedLoudness.render(
                            trial, clip: 193, urls: urls, resolution: resolution,
                            cancelled: { false })
                        done.signal()
                    }
                    done.wait()
                    RampAudioRenders.shared.release(owner: key)
                    if case .steps(let steps, _) = answer {
                        renders.append(steps)
                    } else {
                        why = "\(answer)"
                    }
                }
            } else {
                why = "the trial was refused"
            }
        } else {
            why = "Enhance could not read the steady clip"
        }
        let figures = renders.map { f3(StepLoudness.integrated($0)) }
        check("R5", "the steady fixture's Enhance trial rendered three times through "
                + "ProcessedLoudness.render (its isolation re-rendered before the third) gives "
                + "byte-identical step energies",
              renders.count == 3 && renders[0] == renders[1] && renders[0] == renders[2],
              "processed \(figures.joined(separator: ", ")) LUFS; " + (why.isEmpty ? "" : why))
    }
}
exit(0)
