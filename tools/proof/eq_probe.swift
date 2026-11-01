import AppKit
import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox

// The EQ, hum notch and channel pick's probe (road map "audio" AP3, spec §11
// AU-30..AU-36), compiled with app/Sources through swift_build. Arguments: the
// fixtures folder, a scratch folder. Prints one "ok"/"FAIL" line per check,
// each row's name first (Q2..Q11), for eq_probe.py to score; Q1's responses
// are written as JSON and named on a "Q1JSON <file>" line for the script's own
// numpy oracle.

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.prohibited)

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let fs = 48_000.0

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}
func f3(_ x: Double?) -> String { x.map { String(format: "%.3f", $0) } ?? "nil" }

func settings(_ eq: EqProps?, _ hum: HumProps? = nil) -> AudioEQSettings? {
    AudioEQSettings(eq: eq, hum: hum)
}

/// The designed positions of `s` at `rate`: (coefficients, active).
func designed(_ s: AudioEQSettings, rate: Double) -> ([AudioBiquadCoefficients], [Bool]) {
    var c = [AudioBiquadCoefficients](repeating: .identity, count: AudioEQDesign.positions)
    var a = [Bool](repeating: false, count: AudioEQDesign.positions)
    c.withUnsafeMutableBufferPointer { cp in
        a.withUnsafeMutableBufferPointer { ap in
            AudioEQDesign.design(s, sampleRate: rate, into: cp.baseAddress!, active: ap.baseAddress!)
        }
    }
    return (c, a)
}

// MARK: - Q1 every slot and harmonic's response, for the script's oracle

do {
    let grid = (0..<20).map { 20 * pow(1000, Double($0) / 19) }
    let pass = EqPassProps.self
    let cases: [(String, [String: Any], EqProps?, HumProps?)] = [
        ("high_pass", ["frequency": 80.0, "slope": 12], EqProps(highPass: pass.init(frequency: 80, slope: 12)), nil),
        ("high_pass", ["frequency": 80.0, "slope": 24], EqProps(highPass: pass.init(frequency: 80, slope: 24)), nil),
        ("high_pass", ["frequency": 1000.0, "slope": 24], EqProps(highPass: pass.init(frequency: 1000, slope: 24)), nil),
        ("low_pass", ["frequency": 12000.0, "slope": 12], EqProps(lowPass: pass.init(frequency: 12_000, slope: 12)), nil),
        ("low_pass", ["frequency": 5000.0, "slope": 24], EqProps(lowPass: pass.init(frequency: 5000, slope: 24)), nil),
        ("low_shelf", ["frequency": 100.0, "gain_db": 6.0], EqProps(lowShelf: EqShelfProps(frequency: 100, gainDb: 6)), nil),
        ("low_shelf", ["frequency": 300.0, "gain_db": -9.0], EqProps(lowShelf: EqShelfProps(frequency: 300, gainDb: -9)), nil),
        ("high_shelf", ["frequency": 8000.0, "gain_db": 4.0], EqProps(highShelf: EqShelfProps(frequency: 8000, gainDb: 4)), nil),
        ("high_shelf", ["frequency": 3000.0, "gain_db": -12.0], EqProps(highShelf: EqShelfProps(frequency: 3000, gainDb: -12)), nil),
        ("band_1", ["frequency": 300.0, "gain_db": -3.0, "q": 1.0], EqProps(band1: EqBandProps(frequency: 300, gainDb: -3, q: 1)), nil),
        ("band_2", ["frequency": 1000.0, "gain_db": 6.0, "q": 0.5], EqProps(band2: EqBandProps(frequency: 1000, gainDb: 6, q: 0.5)), nil),
        ("band_3", ["frequency": 4000.0, "gain_db": 3.0, "q": 4.0], EqProps(band3: EqBandProps(frequency: 4000, gainDb: 3, q: 4)), nil),
        ("hum", ["frequency": 60, "depth_db": 30.0, "harmonics": 8], nil, HumProps(frequency: 60, depthDb: 30, harmonics: 8)),
        ("hum", ["frequency": 50, "depth_db": 48.0, "harmonics": 8], nil, HumProps(frequency: 50, depthDb: 48, harmonics: 8)),
        ("hum", ["frequency": 60, "depth_db": 12.0, "harmonics": 3], nil, HumProps(frequency: 60, depthDb: 12, harmonics: 3)),
    ]
    var out: [[String: Any]] = []
    for rate in [48_000.0, 44_100.0] {
        for (kind, params, eq, hum) in cases {
            guard let s = settings(eq, hum) else {
                out.append(["kind": kind, "params": params, "fs": rate, "error": "no settings"])
                continue
            }
            var freqs = grid
            if let hum {
                for k in 1...hum.harmonics {
                    let f = Double(k * hum.frequency)
                    freqs += [f, f - Double(hum.frequency) / 20, f + Double(hum.frequency) / 20]
                }
            }
            let (c, a) = designed(s, rate: rate)
            var positions: [String: [Double]] = [:]
            for p in 0..<AudioEQDesign.positions where a[p] {
                positions[String(p)] = freqs.map {
                    AudioEQDesign.magnitudeDB(c[p], frequency: $0, sampleRate: rate)
                }
            }
            out.append(["kind": kind, "params": params, "fs": rate, "freqs": freqs,
                        "positions": positions])
        }
    }
    // The cascades, through the product's own `responseDB` at 48 kHz.
    var cascades: [[String: Any]] = []
    for (f0, depth, h) in [(60, 30.0, 4), (50, 48.0, 8)] {
        guard let s = settings(nil, HumProps(frequency: f0, depthDb: depth, harmonics: h)) else {
            continue
        }
        let at = (1...h).map { Double($0 * f0) }
        let mid = (1..<h).map { (Double($0) + 0.5) * Double(f0) }
        cascades.append([
            "frequency": f0, "depth_db": depth, "harmonics": h,
            "at": AudioEQDesign.responseDB(s, frequencies: at, sampleRate: fs),
            "mid": AudioEQDesign.responseDB(s, frequencies: mid, sampleRate: fs),
        ])
    }
    let url = scratch.appendingPathComponent("q1.json")
    if let data = try? JSONSerialization.data(
        withJSONObject: ["cases": out, "cascades": cascades], options: [.sortedKeys]) {
        try? data.write(to: url)
        print("Q1JSON \(url.path)")
    } else {
        check("Q1", "responses written", false)
    }
}

// MARK: - Q2 the corners

do {
    var detail: [String] = []
    var good = true
    for (kind, slope, corner) in [("hp", 12, 200.0), ("hp", 24, 200.0), ("lp", 12, 4000.0),
                                  ("lp", 24, 4000.0)] {
        let p = EqPassProps(frequency: corner, slope: slope)
        guard let s = settings(kind == "hp" ? EqProps(highPass: p) : EqProps(lowPass: p)) else {
            good = false
            continue
        }
        let beyond = kind == "hp" ? corner / 2 : corner * 2
        let r = AudioEQDesign.responseDB(s, frequencies: [corner, beyond], sampleRate: fs)
        // The bilinear Butterworth of order n (6 dB/octave each), prewarped
        // at the corner: |H|² = 1 / (1 + r^2n).
        let n = Double(slope / 6)
        let ratio = tan(Double.pi * beyond / fs) / tan(Double.pi * corner / fs)
        let expected = -10 * log10(1 + pow(kind == "hp" ? 1 / ratio : ratio, 2 * n))
        let ok = abs(r[0] + 3.0103) < 0.0005 && abs(r[1] - expected) < 0.01
        good = good && ok
        detail.append("\(kind)\(slope) corner \(f3(r[0])) octave \(f3(r[1])) (\(f3(expected)))")
    }
    check("Q2", "HP and LP at 12 and 24 read −3.010 dB at the corner and Butterworth an "
            + "octave beyond", good, detail.joined(separator: "; "))
}

// MARK: - Signals and a driver

func noise(_ n: Int, seed: UInt64) -> [Float] {
    var state = seed
    return (0..<n).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int64(bitPattern: state >> 11) % 2_000_000) / 4_000_000
    }
}
func sine(_ n: Int, _ f: Double, _ amplitude: Double = 0.5) -> [Float] {
    (0..<n).map { Float(amplitude * sin(2 * Double.pi * f * Double($0) / fs)) }
}

/// Channels in raw buffers, as the tap hands them over: `at(position)` is
/// the pointer list a stage is given for a run starting there.
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

/// `body(position, size)` over runs cut by `pattern` (cycled) and at every
/// change, as the tap cuts a buffer at a clip's span.
func runs(_ total: Int, pattern: [Int], changes: [Int], _ body: (Int, Int) -> Void) {
    var position = 0
    var turn = 0
    while position < total {
        var size = min(pattern[turn % pattern.count], total - position)
        turn += 1
        if let next = changes.first(where: { $0 > position && $0 < position + size }) {
            size = next - position
        }
        body(position, size)
        position += size
    }
}

/// The chain over whole channels, in runs.
func drive(
    _ chain: AudioDSPChain, _ input: [[Float]], pattern: [Int], changes: [Int],
    params: (Int) -> AudioClipDSP
) -> [[Float]] {
    let planar = Planar(input)
    runs(planar.length, pattern: pattern, changes: changes) { position, size in
        chain.process(planar.at(position), frames: size, params: params(position))
    }
    return planar.arrays
}

/// The EQ stage alone over whole channels, in runs of `block`.
func driveStage(
    _ stage: AudioEQStage, _ input: [[Float]], _ s: AudioEQSettings?, block: Int = 512
) -> [[Float]] {
    let planar = Planar(input)
    runs(planar.length, pattern: [block], changes: []) { position, size in
        stage.process(planar.at(position), count: input.count, frames: size, settings: s)
    }
    return planar.arrays
}

func chain(_ channels: Int, nr: Bool = false) -> AudioDSPChain {
    AudioDSPChain(channelCount: channels, sampleRate: fs, maxFrames: 4096, usesNoiseReduction: nr)
}

let n = 4 * 48_000
let left = zip(noise(n, seed: 7), sine(n, 60, 0.2)).map { $0 + $1 }
let right = zip(noise(n, seed: 11), sine(n, 997, 0.3)).map { $0 + $1 }

let eqA = settings(
    EqProps(highPass: EqPassProps(frequency: 90, slope: 24), band1: EqBandProps(frequency: 300, gainDb: -3, q: 1),
            band3: EqBandProps(frequency: 4000, gainDb: 3, q: 1)),
    HumProps(frequency: 60, depthDb: 30, harmonics: 4))
let eqB = settings(
    EqProps(lowShelf: EqShelfProps(frequency: 120, gainDb: 4), band1: EqBandProps(frequency: 500, gainDb: 2, q: 2),
            highShelf: EqShelfProps(frequency: 7000, gainDb: -6), lowPass: EqPassProps(frequency: 11_000, slope: 12)),
    HumProps(frequency: 50, depthDb: 24, harmonics: 8))

// MARK: - Q3 block sizes

do {
    let changes = Array(stride(from: 12_000, to: n, by: 12_000))
    func at(_ position: Int) -> AudioClipDSP {
        switch (position / 12_000) % 5 {
        case 0: return AudioClipDSP(eq: eqA)
        case 1: return AudioClipDSP()
        case 2: return AudioClipDSP(channels: .swapped, eq: eqB)
        case 3: return AudioClipDSP(channels: .left, eq: eqB)
        default: return AudioClipDSP(channels: .right, eq: eqA)
        }
    }
    let reference = drive(chain(2), [left, right], pattern: [512], changes: changes, params: at)
    var detail: [String] = []
    var same = reference[0] != left
    for pattern in [[4096], [1, 1023, 333, 691, 4096, 7, 2048, 17, 512]] {
        let other = drive(chain(2), [left, right], pattern: pattern, changes: changes, params: at)
        let equal = other == reference
        same = same && equal
        detail.append("\(pattern.count == 1 ? "4096" : "irregular") \(equal ? "equal" : "DIFFERS")")
    }
    check("Q3", "512, 4096 and irregular blocks byte-identical through the chain, settings "
            + "and picks changing at cuts", same, detail.joined(separator: ", "))
}

// MARK: - Q4 reset

do {
    let used = AudioEQStage(channelCount: 2, sampleRate: fs)
    _ = driveStage(used, [left, right], eqA)
    used.reset()
    let after = driveStage(used, [right, left], eqA)
    let fresh = driveStage(AudioEQStage(channelCount: 2, sampleRate: fs), [right, left], eqA)
    check("Q4", "after reset() the stage gives a fresh stage's bytes, both channels",
          after == fresh, "left \(after[0] == fresh[0] ? "equal" : "DIFFERS"), right "
            + "\(after[1] == fresh[1] ? "equal" : "DIFFERS")")
}

// MARK: - Q5 inert

do {
    let flat = settings(EqProps(lowShelf: EqShelfProps(frequency: 100), band2: EqBandProps()), nil)
    let bypassed = settings(EqProps(highPass: EqPassProps(frequency: 80), bypass: true), nil)
    let none = settings(nil, nil)
    let parameters = (try? ReelProject.from(json: """
        {"version": \(RC_FORMAT_VERSION),
         "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
         "media": [{"id": 1, "path": "/fixtures/stereo.wav", "kind": "audio",
                    "duration": 6000000, "has_video": false, "has_audio": true}],
         "tracks": [{"id": 3, "name": "Track 1"}],
         "clips": [{"id": 2, "track": 3, "start": 0, "duration": 600000,
                    "source": {"kind": "media", "media": 1, "in": 0},
                    "audio": {"eq": {"band_1": {"gain_db": 0}, "low_shelf": {}},
                              "channels": "both"}}],
         "next_id": 10}
        """)).map { AudioDSPParameters(snapshot: $0.snapshot) }
    let inert = parameters.map { $0.dsp(for: 2).isInert && $0.isEmpty } ?? false
    let untouched = drive(chain(2), [left, right], pattern: [512], changes: [],
                          params: { _ in AudioClipDSP() })
    let stageOut = driveStage(
        AudioEQStage(channelCount: 2, sampleRate: fs), [left, right], nil, block: 4096)
    check("Q5", "flat, bypassed and absent settings design nothing, the clip is inert, and "
            + "nil settings leave every byte", flat == nil && bypassed == nil && none == nil
            && inert && AudioClipDSP(channels: .both, eq: nil).isInert
            && !AudioClipDSP(channels: .left).isInert && untouched == [left, right]
            && stageOut == [left, right],
          "flat \(flat == nil), bypassed \(bypassed == nil), project inert \(inert), "
            + "chain untouched \(untouched == [left, right]), stage untouched \(stageOut == [left, right])")
}

// MARK: - Q6 picks

do {
    func picked(_ choice: AudioChannelChoice, mono: Bool = false) -> [[Float]] {
        drive(chain(2), [left, right], pattern: [512], changes: [],
              params: { _ in AudioClipDSP(mono: mono, channels: choice) })
    }
    let l = picked(.left), r = picked(.right), s = picked(.swapped), m = picked(.left, mono: true)
    let one = drive(chain(1), [left], pattern: [512], changes: [],
                    params: { _ in AudioClipDSP(channels: .right) })
    check("Q6", "left, right and swapped sample-identical to their source channels; mono after "
            + "left is L; a one-channel track untouched",
          l == [left, left] && r == [right, right] && s == [right, left] && m == [left, left]
            && one == [left],
          "left \(l == [left, left]), right \(r == [right, right]), swapped \(s == [right, left]), "
            + "mono+left \(m == [left, left]), mono track \(one == [left])")
}

// MARK: - Q7 the curve against the stage

/// The amplitude of `y`'s component at `f` over its last `m` samples, by a
/// least-squares fit of a sin + b cos + c (exact for a steady sinusoid).
func amplitude(_ y: [Float], _ f: Double, last m: Int) -> Double {
    var s = [[Double]](repeating: [0, 0, 0], count: 3)
    var t = [0.0, 0.0, 0.0]
    for i in (y.count - m)..<y.count {
        let w = 2 * Double.pi * f * Double(i) / fs
        let basis = [sin(w), cos(w), 1.0]
        for r in 0..<3 {
            t[r] += basis[r] * Double(y[i])
            for c in 0..<3 { s[r][c] += basis[r] * basis[c] }
        }
    }
    // Gaussian elimination on the 3 × 3.
    var a = s
    var b = t
    for k in 0..<3 {
        for r in (k + 1)..<3 {
            let factor = a[r][k] / a[k][k]
            for c in k..<3 { a[r][c] -= factor * a[k][c] }
            b[r] -= factor * b[k]
        }
    }
    var x = [0.0, 0.0, 0.0]
    for k in stride(from: 2, through: 0, by: -1) {
        var sum = b[k]
        for c in (k + 1)..<3 { sum -= a[k][c] * x[c] }
        x[k] = sum / a[k][k]
    }
    return (x[0] * x[0] + x[1] * x[1]).squareRoot()
}

do {
    let eq = EqProps(
        highPass: EqPassProps(frequency: 80, slope: 24), lowShelf: EqShelfProps(frequency: 120, gainDb: 3),
        band1: EqBandProps(frequency: 300, gainDb: -3, q: 1), band2: EqBandProps(frequency: 1000, gainDb: 2, q: 2),
        band3: EqBandProps(frequency: 4000, gainDb: 3, q: 1), highShelf: EqShelfProps(frequency: 9000, gainDb: -4),
        lowPass: EqPassProps(frequency: 15_000, slope: 12))
    let hum = HumProps(frequency: 60, depthDb: 30, harmonics: 4)
    let curve = AudioEQCurveView.response(eq: eq, hum: hum)
    var worst = 0.0
    var at = 0.0
    for index in stride(from: 8, to: AudioEQCurveView.points, by: 16) {
        let f = AudioEQCurveView.frequencies[index]
        let x = driveStage(
            AudioEQStage(channelCount: 1, sampleRate: fs), [sine(4 * 48_000, f, 0.25)],
            settings(eq, hum), block: 4096)[0]
        let measured = 20 * log10(amplitude(x, f, last: 48_000) / 0.25)
        let gap = abs(measured - curve[index])
        if gap > worst {
            worst = gap
            at = f
        }
    }
    check("Q7", "the drawn curve equals the stage's measured steady-state response within "
            + "0.01 dB", worst <= 0.01 && curve.count == 256,
          String(format: "worst %.4f dB at %.1f Hz over 16 points", worst, at))
}

// MARK: - Q8 the loudness reading follows the pick

final class TrackBox: @unchecked Sendable { var track: AVAssetTrack? }
final class ResultBox: @unchecked Sendable { var value = false }

func loadTrack(_ asset: AVAsset) -> AVAssetTrack? {
    let box = TrackBox()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.track = (try? await asset.loadTracks(withMediaType: .audio))?.first
        done.signal()
    }
    done.wait()
    return box.track
}

func segment(clip: UInt32 = 2, start: Ticks = 0, duration: Ticks) -> PlanSegment {
    let json = """
        {"clip": \(clip), "media": 1, "source_in": \(start), "source_duration": \(duration),
         "start": \(start), "duration": \(duration)}
        """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(PlanSegment.self, from: Data(json.utf8))
}

let stereoURL = fixtures.appendingPathComponent("stereo.wav")
let stereoTicks: Ticks = 12 * 600_000

do {
    let media = MediaSnapshot(id: 1, path: stereoURL.path, kind: .audio, duration: stereoTicks,
                              hasVideo: false, hasAudio: true)
    let dir = scratch.appendingPathComponent("loudness", isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let done = DispatchSemaphore(value: 0)
    let box = ResultBox()
    Task.detached {
        box.value = await MediaImporter.loudness(
            for: media, url: stereoURL,
            stamp: MediaImporter.CacheStamp.stamp(for: media, url: stereoURL), into: dir)
        done.signal()
    }
    _ = done.wait(timeout: .now() + 120)
    if let cache = MediaImporter.loadLoudness(for: 1, in: dir) {
        func lufs(_ choice: AudioChannelChoice) -> Double? {
            ClipLoudness.reading(
                cache, segments: [segment(duration: 10 * 600_000)], pivots: [nil],
                matrix: ClipLoudness.ChannelMatrix(AudioProps(channels: choice))).lufs
        }
        let both = lufs(.both), l = lufs(.left), s = lufs(.swapped)
        let gap = (l ?? .nan) - (both ?? .nan)
        check("Q8", "on a voice-on-L stereo file, left reads both + 3.01 LU (±0.01) and swapped "
                + "reads both", abs(gap - 3.0103) <= 0.01 && s == both && both != nil,
              "both \(f3(both)), left \(f3(l)), swapped \(f3(s)), gap \(f3(gap))")
    } else {
        check("Q8", "the stereo fixture's loudness cache builds", false)
    }
}

// MARK: - Q9 the preview against the reader

/// A tap around the product's `AudioTapContext`, capturing channel `capture`.
final class CaptureTap {
    let context: AudioTapContext
    let channel: Int
    let capacity = 48_000 * 8
    let samples: UnsafeMutablePointer<Float>
    var captured = 0
    var starts: [Int64] = Array(repeating: 0, count: 20_000)
    var sizes: [Int] = Array(repeating: 0, count: 20_000)
    var callbacks = 0

    init(track: AudioTrackDSP, channel: Int) {
        context = AudioTapContext(track: track, isolation: nil, meter: nil)
        self.channel = channel
        samples = .allocate(capacity: capacity)
    }
    deinit { samples.deallocate() }
}

func makeTap(_ state: CaptureTap) -> MTAudioProcessingTap? {
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: Unmanaged.passRetained(state).toOpaque(),
        init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
        finalize: { tap in
            Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        },
        prepare: { tap, maxFrames, format in
            let state = Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            state.context.prepare(
                channelCount: Int(format.pointee.mChannelsPerFrame),
                sampleRate: format.pointee.mSampleRate, maxFrames: Int(maxFrames),
                formatFlags: format.pointee.mFormatFlags,
                bitsPerChannel: format.pointee.mBitsPerChannel)
        },
        unprepare: { tap in
            Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue().context.unprepare()
        },
        process: { tap, numberFrames, _, list, framesOut, flagsOut in
            let state = Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            var range = CMTimeRange()
            guard MTAudioProcessingTapGetSourceAudio(
                tap, numberFrames, list, flagsOut, &range, framesOut) == noErr
            else {
                framesOut.pointee = 0
                return
            }
            let frames = Int(framesOut.pointee)
            let start = flagsOut.pointee & MTAudioProcessingTapFlags(
                kMTAudioProcessingTapFlag_StartOfStream) != 0
            state.context.process(list, frames: frames, time: range.start, startOfStream: start)
            guard state.callbacks < state.starts.count else { return }
            state.starts[state.callbacks] = range.start.isNumeric
                ? CMTimeConvertScale(range.start, timescale: 48_000, method: .roundTowardZero).value
                : -1
            state.sizes[state.callbacks] = frames
            state.callbacks += 1
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count > state.channel,
                let data = buffers[state.channel].mData?.assumingMemoryBound(to: Float.self),
                state.captured + frames <= state.capacity
            else { return }
            (state.samples + state.captured).update(from: data, count: frames)
            state.captured += frames
        })
    var tap: MTAudioProcessingTap?
    guard MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        == noErr
    else { return nil }
    return tap
}

func project(_ clips: String) -> ReelProject? {
    try? ReelProject.from(json: """
        {"version": \(RC_FORMAT_VERSION),
         "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
         "media": [{"id": 1, "path": "\(stereoURL.path)", "kind": "audio",
                    "duration": \(stereoTicks), "has_video": false, "has_audio": true}],
         "tracks": [{"id": 3, "name": "Track 1"}],
         "clips": [\(clips)],
         "next_id": 10}
        """)
}

do {
    let asset = AVURLAsset(url: stereoURL)
    let parameters = project("""
        {"id": 2, "track": 3, "start": 0, "duration": 6000000,
         "source": {"kind": "media", "media": 1, "in": 0},
         "audio": {"channels": "left", "hum": {"frequency": 60, "depth_db": 30, "harmonics": 4},
                   "eq": {"high_pass": {"frequency": 80, "slope": 24},
                          "band_3": {"frequency": 4000, "gain_db": 3, "q": 1}}}}
        """).map { AudioDSPParameters(snapshot: $0.snapshot) } ?? .empty
    let span: Ticks = 10 * 600_000
    let track = AudioTrackDSP(segments: [segment(duration: span)], parameters: parameters)
    let composition = AVMutableComposition()
    if let source = loadTrack(asset),
       let target = composition.addMutableTrack(
           withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try? target.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(value: span, timescale: 600_000)),
            of: source, at: .zero)
        func mix(_ state: CaptureTap) -> AVAudioMix {
            let input = AVMutableAudioMixInputParameters(track: target)
            input.audioTapProcessor = makeTap(state)
            let mix = AVMutableAudioMix()
            mix.inputParameters = [input]
            return mix
        }
        let reading = CaptureTap(track: track, channel: 1)
        if let reader = try? AVAssetReader(asset: composition) {
            let output = AVAssetReaderAudioMixOutput(audioTracks: [target], audioSettings: nil)
            output.audioMix = mix(reading)
            reader.add(output)
            reader.startReading()
            while output.copyNextSampleBuffer() != nil {}
        }
        let previewing = CaptureTap(track: track, channel: 1)
        let item = AVPlayerItem(asset: composition)
        item.audioMix = mix(previewing)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.play()
        RunLoop.main.run(until: Date().addingTimeInterval(5))
        player.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        var exported = [Float](repeating: .nan, count: reading.capacity)
        var position = 0
        for k in 0..<reading.callbacks {
            let start = reading.starts[k] >= 0 ? Int(reading.starts[k]) : -1
            let frames = reading.sizes[k]
            if start >= 0, start + frames <= exported.count {
                for i in 0..<frames { exported[start + i] = reading.samples[position + i] }
            }
            position += frames
        }
        var compared = 0
        var differ = 0
        var offset = 0
        let window = 188_416
        for k in 0..<previewing.callbacks {
            let frames = previewing.sizes[k]
            defer { offset += frames }
            guard offset + frames <= previewing.captured else { break }
            let start = Int(previewing.starts[k])
            guard start >= 0, start + frames <= window else { continue }
            for i in 0..<frames where previewing.samples[offset + i] != exported[start + i] {
                differ += 1
            }
            compared += frames
        }
        // The right channel is silent in the file: sound there is the pick.
        var loudest: Float = 0
        for i in 0..<min(window, exported.count) where !exported[i].isNaN {
            loudest = max(loudest, abs(exported[i]))
        }
        check("Q9", "the muted player's tap output equals the reader's, sample for sample, "
                + "within the first 4 s, with EQ, hum and a left pick, and the silent right "
                + "channel carries the voice", compared >= 100_000 && differ == 0 && loudest > 0.01,
              "compared \(compared), differ \(differ), right channel's loudest \(loudest)")
    } else {
        check("Q9", "the composition builds", false)
    }
}

// MARK: - Q10 the cost

do {
    let every = settings(
        EqProps(highPass: EqPassProps(frequency: 80, slope: 24), lowShelf: EqShelfProps(frequency: 120, gainDb: 3),
                band1: EqBandProps(frequency: 300, gainDb: -3), band2: EqBandProps(frequency: 1000, gainDb: 2),
                band3: EqBandProps(frequency: 4000, gainDb: 3), highShelf: EqShelfProps(frequency: 9000, gainDb: -4),
                lowPass: EqPassProps(frequency: 15_000, slope: 24)),
        HumProps(frequency: 50, depthDb: 30, harmonics: 8))
    let stage = AudioEQStage(channelCount: 2, sampleRate: fs)
    let planar = Planar([Array(left.prefix(1024)), Array(right.prefix(1024))])
    let active = every.map { designed($0, rate: fs).1.filter { $0 }.count } ?? 0
    let rounds = 2_000
    var best = Double.infinity
    for _ in 0..<3 {
        let begin = DispatchTime.now().uptimeNanoseconds
        let pointers = planar.at(0)
        for _ in 0..<rounds {
            stage.process(pointers, count: 2, frames: 1024, settings: every)
        }
        let micro = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1000 / Double(rounds)
        best = min(best, micro)
    }
    let share = best / (1024 / fs * 1_000_000) * 100
    check("Q10", "µs per 1024 stereo frames at all 17 positions (reported)", active == 17,
          String(format: "%d positions, %.1f µs (best of 3 × %d), %.2f %% of real time",
                 active, best, rounds, share))
}

// MARK: - Q11 the head lookup on a noise-reduced track

func headLeadIs(_ track: AudioTrackDSP) -> Bool {
    track.headLead == CompositionBuilder.AudioShift.noiseReductionLead && track.usesNoiseReduction
}

do {
    // A [0, 1 s) plays the right channel (silent), B [1 s, 2 s) the left (a
    // tone), C [2 s, 3 s) asks for noise reduction, so the track runs the
    // reducer and A and B pass through it as a delay.
    let p = project("""
        {"id": 2, "track": 3, "start": 0, "duration": 600000,
         "source": {"kind": "media", "media": 1, "in": 0}, "audio": {"channels": "right"}},
        {"id": 4, "track": 3, "start": 600000, "duration": 600000,
         "source": {"kind": "media", "media": 1, "in": 600000}, "audio": {"channels": "left"}},
        {"id": 5, "track": 3, "start": 1200000, "duration": 600000,
         "source": {"kind": "media", "media": 1, "in": 1200000}, "audio": {"noise_reduction": 0.5}}
        """).map { AudioDSPParameters(snapshot: $0.snapshot) } ?? .empty
    let track = AudioTrackDSP(
        segments: [segment(clip: 2, start: 0, duration: 600_000),
                   segment(clip: 4, start: 600_000, duration: 600_000),
                   segment(clip: 5, start: 1_200_000, duration: 600_000)],
        parameters: p)
    let context = AudioTapContext(track: track, isolation: nil, meter: nil)
    context.prepare(
        channelCount: 2, sampleRate: fs, maxFrames: 4096,
        formatFlags: AudioFormatFlags(kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved),
        bitsPerChannel: 32)
    let total = 2 * 48_000
    let tone = sine(total, 1000, 0.5)
    var outRight = [Float](repeating: 0, count: total)
    let list = AudioBufferList.allocate(maximumBuffers: 2)
    let l = UnsafeMutablePointer<Float>.allocate(capacity: 512)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: 512)
    var position = 0
    while position < total {
        let frames = min(512, total - position)
        for i in 0..<frames {
            l[i] = tone[position + i]
            r[i] = 0
        }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: l)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: r)
        context.process(
            list.unsafeMutablePointer, frames: frames,
            time: CMTime(value: Int64(position), timescale: 48_000), startOfStream: position == 0)
        for i in 0..<frames { outRight[position + i] = r[i] }
        position += frames
    }
    l.deallocate()
    r.deallocate()
    free(list.unsafeMutablePointer)
    let onset = outRight.firstIndex { abs($0) > 0.05 }
    let gap = onset.map { Double($0 - 48_000) / 48 } ?? .nan
    check("Q11", "on a noise-reduced track the pick switches at the cut (±1 ms), not the "
            + "reducer's 10.7 ms late", headLeadIs(track) && abs(gap) <= 1,
          "onset at sample \(onset.map(String.init) ?? "none"), \(f3(gap)) ms from the cut; "
            + "head lead \(track.headLead)")
}
