import Accelerate
import AppKit
import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox

// The gate and de-esser's probe (road map "audio" AP4, spec §11 AU-40..AU-47,
// AU-49), compiled with app/Sources through swift_build. Arguments: the
// fixtures folder, a scratch folder. Prints one "ok"/"FAIL" line per row
// (D1..D11) for audio_ap4_probe.py to score.

// MARK: - HEAD's compressor, verbatim (3f7ed17's AudioCompressorStage.swift,
// renamed), the bytes D1 holds the shared follower to.

final class HeadAudioCompressorStage {
    /// Current gain reduction in dB, always ≥ 0. Persists across buffers.
    private var reductionDB: Float = 0
    /// The peak follower's state — see `processChunk`. Also persists.
    private var detectorState: Float = 0
    private let sampleRate: Double
    /// The linked detector and the per-sample gain, sized once.
    private let detector: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private let gains: UnsafeMutablePointer<Float>
    private let capacity: Int

    init(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48000
        capacity = max(1, maxFrames)
        detector = .allocate(capacity: capacity)
        scratch = .allocate(capacity: capacity)
        gains = .allocate(capacity: capacity)
        detector.initialize(repeating: 0, count: capacity)
        scratch.initialize(repeating: 0, count: capacity)
        gains.initialize(repeating: 1, count: capacity)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("HeadAudioCompressorStage does not support NSCoder")
    }

    deinit {
        detector.deallocate()
        scratch.deallocate()
        gains.deallocate()
    }

    /// Forgets the envelope and the follower. Called when playback restarts,
    /// so a paused-then-resumed preview does not open with the reduction the
    /// last buffer left.
    func reset() {
        reductionDB = 0
        detectorState = 0
    }

    /// A one-pole coefficient for a time constant in seconds. Zero seconds
    /// means "instantly", which is a legitimate setting (a brick-wall attack)
    /// and must not divide by zero.
    private func coefficient(_ seconds: Double) -> Float {
        guard seconds > 0 else { return 1 }
        return Float(1 - exp(-1 / (seconds * sampleRate)))
    }

    /// Compresses `frames` samples in place across `count` channels.
    ///
    /// `settings` of nil means this clip asks for no compression: the target
    /// reduction is 0 but the envelope still RELEASES toward it, so a cut from
    /// a compressed clip to an uncompressed one opens up over the last
    /// clip's release time instead of stepping.
    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, settings: AudioCompressorSettings?
    ) {
        guard frames > 0, count > 0 else { return }
        // `maxFrames` is what `prepare` promised, not a guarantee: a buffer
        // bigger than the scratch is split rather than dropped, because
        // silently leaving audio unprocessed is the one outcome worth ruling
        // out.
        var offset = 0
        while offset < frames {
            let chunk = min(capacity, frames - offset)
            processChunk(channels, count: count, offset: offset, frames: chunk, settings: settings)
            offset += chunk
        }
    }

    private func processChunk(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        offset: Int, frames: Int, settings: AudioCompressorSettings?
    ) {
        // The linked detector: |x| of the first channel, then the running
        // maximum against every other. Vectorised — this is two passes over
        // the buffer rather than a branch per sample per channel.
        var wrote = false
        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            if !wrote {
                vDSP_vabs(data + offset, 1, detector, 1, vDSP_Length(frames))
                wrote = true
            } else {
                vDSP_vabs(data + offset, 1, scratch, 1, vDSP_Length(frames))
                vDSP_vmax(detector, 1, scratch, 1, detector, 1, vDSP_Length(frames))
            }
        }
        guard wrote else { return }

        let thresholdDB = Float(settings?.thresholdDB ?? 0)
        let ratio = Float(settings?.ratio ?? 1)
        // How much of every dB above the threshold is given back. Ratio 1
        // (or no compressor at all) makes this 0 and the stage a pure makeup
        // gain, which is exactly what 1:1 means.
        let slope = ratio > 1 ? 1 - 1 / ratio : 0
        let makeupDB = Float(settings?.makeupDB ?? 0)
        let thresholdLinear = AudioDSP.gain(fromDecibels: thresholdDB)
        let attack = coefficient(settings?.attackSeconds ?? 0)
        let release = coefficient(settings?.releaseSeconds ?? 0)
        // The detector is a PEAK FOLLOWER — it jumps to each new peak and
        // falls back at the release rate — rather than the raw |x|. A naive
        // detector reads a waveform's own zero crossings as the level
        // collapsing, so the gain is modulated at twice the signal's
        // frequency: audible as distortion on anything low, and the reason a
        // sine measured through a textbook 3:1 lands a few tenths of a dB
        // shy of where the arithmetic says it should. The floor keeps a
        // zero-release setting from turning the follower back into |x|.
        let fall = Float(exp(-1 / (max(settings?.releaseSeconds ?? 0, 0.010) * sampleRate)))

        for index in 0..<frames {
            detectorState = max(detector[index], detectorState * fall)
            let level = detectorState
            // The log is skipped entirely below the threshold, which is where
            // most samples of most material are.
            var target: Float = 0
            if slope > 0, level > thresholdLinear {
                let levelDB = 20 * log10f(max(level, AudioDSP.silenceFloor))
                target = (levelDB - thresholdDB) * slope
            }
            let coefficient = target > reductionDB ? attack : release
            reductionDB += (target - reductionDB) * coefficient
            gains[index] = AudioDSP.gain(fromDecibels: makeupDB - reductionDB)
        }

        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            vDSP_vmul(data + offset, 1, gains, 1, data + offset, 1, vDSP_Length(frames))
        }
    }
}

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
func db(_ x: Double) -> Double { 20 * log10(x) }

// MARK: - Signals and drivers

func readF32(_ name: String) -> [Float] {
    guard let data = try? Data(contentsOf: fixtures.appendingPathComponent(name)) else { return [] }
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}
func noise(_ n: Int, seed: UInt64, scale: Float = 0.25) -> [Float] {
    var state = seed
    return (0..<n).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int64(bitPattern: state >> 11) % 2_000_000) / 2_000_000 * scale
    }
}
func sine(_ n: Int, _ f: Double, _ amplitude: Double, phase: Double = 0) -> [Float] {
    (0..<n).map { Float(amplitude * sin(2 * Double.pi * f * Double($0) / fs + phase)) }
}
/// A 12 kHz tone whose samples land on +A, 0, −A, 0: its peaks are exact, and
/// its first sample is one.
func quarter(_ n: Int, _ amplitude: Float) -> [Float] {
    (0..<n).map { [amplitude, 0, -amplitude, 0][$0 % 4] }
}
func add(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { $0 + $1 } }

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

/// `process(pointers, count, frames, position)` over `input` in runs.
func drive(
    _ input: [[Float]], pattern: [Int] = [512], changes: [Int] = [],
    _ process: (UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, Int, Int, Int) -> Void
) -> [[Float]] {
    let planar = Planar(input)
    runs(planar.length, pattern: pattern, changes: changes) { position, size in
        process(planar.at(position), input.count, size, position)
    }
    return planar.arrays
}
func gated(
    _ stage: AudioGateStage, _ input: [[Float]], pattern: [Int] = [512], changes: [Int] = [],
    _ s: @escaping (Int) -> AudioGateSettings?
) -> [[Float]] {
    drive(input, pattern: pattern, changes: changes) { p, c, f, at in
        stage.process(p, count: c, frames: f, settings: s(at))
    }
}
func deEssed(
    _ stage: AudioDeEsserStage, _ input: [[Float]], pattern: [Int] = [512],
    changes: [Int] = [], _ s: @escaping (Int) -> AudioDeEsserSettings?
) -> [[Float]] {
    drive(input, pattern: pattern, changes: changes) { p, c, f, at in
        stage.process(p, count: c, frames: f, settings: s(at))
    }
}
func gateStage() -> AudioGateStage { AudioGateStage(sampleRate: fs, maxFrames: 4096) }
func deEsserStage(_ channels: Int = 1) -> AudioDeEsserStage {
    AudioDeEsserStage(channelCount: channels, sampleRate: fs, maxFrames: 4096)
}

/// The amplitude of `y`'s component at `f` over its last `m` samples (a
/// least-squares fit of a sin + b cos + c, exact for a steady sinusoid).
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

let voice = readF32("voice.f32")
let n = 6 * 48_000
let voiceL = Array(voice.prefix(n))
let voiceR = add(voiceL.map { $0 * 0.7 }, noise(n, seed: 5, scale: 0.002))

func gateSettings(
    level: Double = -20, threshold: Double = -10, ratio: Double = 4, range: Double = 20,
    attack: Ticks = 600, hold: Ticks = 30_000, release: Ticks = 60_000
) -> AudioGateSettings {
    AudioGateSettings(
        level: level,
        props: GateProps(
            thresholdDb: threshold, ratio: ratio, rangeDb: range, attack: attack, hold: hold,
            release: release))
}
func deEsserSettings(
    level: Double = -30, frequency: Double = 6000, threshold: Double = 0, range: Double = 6
) -> AudioDeEsserSettings {
    AudioDeEsserSettings(
        level: level,
        props: DeEsserProps(frequency: frequency, thresholdDb: threshold, rangeDb: range))
}

// MARK: - D1 the compressor's bytes against HEAD's

do {
    let crestN = 4 * 48_000
    let crest = (0..<crestN).map { i -> Float in
        let burst = (i % 12_000) < 2_400
        return Float((burst ? 0.9 : 0.05) * sin(2 * Double.pi * 1000 * Double(i) / fs))
    }
    let inputs: [(String, [[Float]])] = [
        ("voice", [voiceL, voiceR]), ("crest", [crest, crest.map { $0 * 0.5 }]),
    ]
    let a = AudioCompressorSettings(
        thresholdDB: -30, ratio: 4, attackSeconds: 0.001, releaseSeconds: 0.005, makeupDB: 6)
    let b = AudioCompressorSettings(
        thresholdDB: -18, ratio: 3, attackSeconds: 0.01, releaseSeconds: 0.2, makeupDB: 0)
    func at(_ position: Int) -> AudioCompressorSettings? {
        [a, b, nil, a][(position / 12_000) % 4]
    }
    var good = true
    var detail: [String] = []
    for (name, input) in inputs {
        let changes = Array(stride(from: 12_000, to: input[0].count, by: 12_000))
        for pattern in [[512], [4096], [1, 1023, 333, 691, 4096, 7, 2048, 17, 512]] {
            let now = AudioCompressorStage(sampleRate: fs, maxFrames: 4096)
            let head = HeadAudioCompressorStage(sampleRate: fs, maxFrames: 4096)
            let mine = drive(input, pattern: pattern, changes: changes) { p, c, f, pos in
                now.process(p, count: c, frames: f, settings: at(pos))
            }
            let theirs = drive(input, pattern: pattern, changes: changes) { p, c, f, pos in
                head.process(p, count: c, frames: f, settings: at(pos))
            }
            let equal = mine == theirs && mine != input
            good = good && equal
            detail.append("\(name) \(pattern.count == 1 ? String(pattern[0]) : "irregular") "
                + (equal ? "equal" : "DIFFERS"))
        }
    }
    check("D1", "the compressor on the shared follower gives HEAD's bytes (5 ms and 200 ms "
            + "releases, settings changing at cuts)", good, detail.joined(separator: ", "))
}

// MARK: - D2 the gate's static curve

do {
    // Threshold −30 dBFS (−20 + −10), ratio 2, range 20.
    let s = gateSettings(threshold: -10, ratio: 2, range: 20)
    var good = true
    var detail: [String] = []
    for level in [-31.0, -35.0, -45.0, -60.0] {
        let amplitudeF = Float(pow(10, level / 20))
        let input = quarter(2 * 48_000, amplitudeF)
        let out = gated(gateStage(), [input]) { _ in s }[0]
        var sum = 0.0
        var count = 0
        for i in (input.count - 9_600)..<input.count where input[i] != 0 {
            sum += db(Double(abs(out[i])) / Double(amplitudeF))
            count += 1
        }
        let reduction = -sum / Double(count)
        let expected = min(20, (-30 - level) * (2 - 1))
        let ok = abs(reduction - expected) <= 0.05
        good = good && ok
        detail.append("\(Int(level)) dBFS \(f3(reduction)) (\(f3(expected)))")
    }
    let above = quarter(2 * 48_000, Float(pow(10, -27.0 / 20)))
    let untouched = gated(gateStage(), [above]) { _ in s }[0] == above
    good = good && untouched
    detail.append("−27 dBFS bytes \(untouched ? "unchanged" : "CHANGED")")
    check("D2", "steady tones below the threshold reduced by min(range, (thr − level)(ratio − 1)) "
            + "±0.05 dB, above it untouched", good, detail.joined(separator: ", "))
}

// MARK: - D3 hold and release

do {
    let burstA: Float = 0.1  // −20 dBFS
    let bed: Float = 1e-5  // −100 dBFS
    let input = quarter(24_000, burstA) + quarter(48_000, bed)
    let last = input.lastIndex { $0 == burstA || $0 == -burstA } ?? 0
    let fallDB = -db(Double(AudioEnvelope.fall(seconds: 0, sampleRate: fs)))
    var good = true
    var detail: [String] = []
    for holdTicks: Ticks in [0, 60_000] {
        let s = gateSettings(threshold: -10, ratio: 20, range: 20, attack: 600, hold: holdTicks,
                             release: 60_000)
        let out = gated(gateStage(), [input]) { _ in s }[0]
        let crossing = (last..<input.count).first {
            input[$0] != 0 && Double(abs(out[$0]) / abs(input[$0])) <= pow(10, -10.0 / 20)
        }
        // The follower falls `fallDB` per sample from −20 dBFS: at the
        // threshold (−30) with a hold, else at the target ramp's midpoint,
        // 20 / (2·19) dB further down.
        let below = holdTicks > 0 ? 10.0 : 10.0 + 20.0 / 38.0
        let tf = Double(last) + below / fallDB
        let expected = tf + Double(holdTicks) / 600_000 * fs + 0.1 * fs * log(2)
        let gap = crossing.map { (Double($0) - expected) / 48 } ?? .nan
        let ok = abs(gap) <= 0.2
        good = good && ok
        detail.append("hold \(holdTicks / 600) ms: crossed at \(crossing.map(String.init) ?? "never"), "
            + "expected \(f3(expected)), \(f3(gap)) ms")
    }
    check("D3", "the gain crosses −range/2 at t_f + hold + release·ln 2 ±0.2 ms", good,
          detail.joined(separator: "; "))
}

// MARK: - D4 block sizes

do {
    let input = [add(voiceL, noise(n, seed: 3, scale: 0.01)), voiceR]
    let changes = Array(stride(from: 12_000, to: n, by: 12_000))
    let gA = gateSettings(level: -40)
    let gB = gateSettings(level: -35, threshold: -6, ratio: 10, range: 40, attack: 0, hold: 0,
                          release: 600)
    let dX = deEsserSettings(level: -40)
    let dY = deEsserSettings(level: -40, frequency: 4000, threshold: -6, range: 24)
    func at(_ position: Int) -> AudioClipDSP {
        switch (position / 12_000) % 6 {
        case 0: return AudioClipDSP(gate: gA)
        case 1: return AudioClipDSP(deEsser: dX)
        case 2: return AudioClipDSP(gate: gB, deEsser: dY)
        case 3: return AudioClipDSP()
        case 4: return AudioClipDSP(gate: gA, deEsser: dX)
        default: return AudioClipDSP(gate: gB)
        }
    }
    func chained(_ pattern: [Int]) -> [[Float]] {
        let chain = AudioDSPChain(
            channelCount: 2, sampleRate: fs, maxFrames: 4096, usesNoiseReduction: false)
        return drive(input, pattern: pattern, changes: changes) { p, _, f, pos in
            chain.process(p, frames: f, params: at(pos))
        }
    }
    let reference = chained([512])
    var same = reference != input
    var detail: [String] = []
    for pattern in [[4096], [1, 1023, 333, 691, 4096, 7, 2048, 17, 512]] {
        let equal = chained(pattern) == reference
        same = same && equal
        detail.append("\(pattern.count == 1 ? "4096" : "irregular") \(equal ? "equal" : "DIFFERS")")
    }
    check("D4", "512, 4096 and irregular blocks byte-identical through the chain, both stages' "
            + "settings changing at cuts", same, detail.joined(separator: ", "))
}

// MARK: - D5 reset and nil

do {
    let other = [voiceR, voiceL]
    let g = gateSettings(level: -40)
    let used = gateStage()
    _ = gated(used, [voiceL, voiceR]) { _ in g }
    used.reset()
    let gateAfter = gated(used, other) { _ in g }
    let gateFresh = gated(gateStage(), other) { _ in g }
    let d = deEsserSettings(level: -40, threshold: -6, range: 12)
    let usedD = deEsserStage(2)
    _ = deEssed(usedD, [voiceL, voiceR]) { _ in d }
    usedD.reset()
    let deAfter = deEssed(usedD, other) { _ in d }
    let deFresh = deEssed(deEsserStage(2), other) { _ in d }
    let gateNil = gated(gateStage(), other) { _ in nil }
    let deNil = deEssed(deEsserStage(2), other) { _ in nil }
    let good = gateAfter == gateFresh && deAfter == deFresh && gateNil == other && deNil == other
        && gateFresh != other && deFresh != other
    check("D5", "reset() gives a fresh stage's bytes and nil settings touch no sample, both "
            + "stages", good,
          "gate reset \(gateAfter == gateFresh), de-esser reset \(deAfter == deFresh), gate nil "
            + "\(gateNil == other), de-esser nil \(deNil == other)")
}

// MARK: - D6 the de-esser

func sectionsDB(_ coefficients: [AudioBiquadCoefficients], _ f: Double) -> Double {
    coefficients.reduce(0) { $0 + AudioEQDesign.magnitudeDB($1, frequency: f, sampleRate: fs) }
}

do {
    let fc = 6000.0
    let side = [AudioEQDesign.highPass(fc, q: AudioEQDesign.butterworthQ(sections: 2, index: 0),
                                       sampleRate: fs),
                AudioEQDesign.highPass(fc, q: AudioEQDesign.butterworthQ(sections: 2, index: 1),
                                       sampleRate: fs)]
    let lrHigh = AudioEQDesign.highPass(fc, q: 0.5.squareRoot(), sampleRate: fs)
    let span = 2 * 48_000
    let last = 24_000
    var good = true
    var detail: [String] = []
    // Steady tones over the threshold: 0.5 against −30 dBFS, range 6.
    let s = deEsserSettings(level: -30, frequency: fc, threshold: 0, range: 6)
    for f in [6000.0, 7000.0, 9000.0, 11_000.0] {
        let input = sine(span, f, 0.5)
        let out = deEssed(deEsserStage(), [input]) { _ in s }[0]
        let measured = -db(amplitude(out, f, last: last) / 0.5)
        let over = db(0.5) + sectionsDB(side, f) - s.thresholdDB
        let g = pow(10, -min(s.rangeDB, max(over, 0)) / 20)
        let band = pow(10, 2 * AudioEQDesign.magnitudeDB(lrHigh, frequency: f, sampleRate: fs) / 20)
        let expected = -db(1 - (1 - g) * band)
        let ok = abs(measured - expected) <= 0.1
        good = good && ok
        detail.append("\(Int(f / 1000)) kHz \(f3(measured)) (\(f3(expected)))")
    }
    // The sweep: range 24, threshold −30 dBFS, no tone louder than it went in.
    let sweepS = deEsserSettings(level: -30, frequency: fc, threshold: 0, range: 24)
    var loudest = -Double.infinity
    var loudestAt = 0.0
    for f in stride(from: 2000.0, through: 12_000.0, by: 250.0) {
        let input = sine(48_000, f, 0.5)
        let out = deEssed(deEsserStage(), [input]) { _ in sweepS }[0]
        let gain = db(amplitude(out, f, last: 12_000) / amplitude(input, f, last: 12_000))
        if gain > loudest {
            loudest = gain
            loudestAt = f
        }
    }
    let noBoost = loudest <= 0.05
    good = good && noBoost
    detail.append("sweep loudest \(f3(loudest)) dB at \(Int(loudestAt)) Hz")
    // 1 kHz alone, under the threshold through the sidechain: the allpass.
    let one = sine(span, 1000, 0.5)
    let oneOut = deEssed(deEsserStage(), [one]) { _ in sweepS }[0]
    let alone = db(amplitude(oneOut, 1000, last: last) / amplitude(one, 1000, last: last))
    let aloneOK = abs(alone) <= 0.01
    good = good && aloneOK
    detail.append("1 kHz alone \(f3(alone))")
    // 1 kHz with a loud 7 kHz: the 1 kHz component stays.
    let mixed = add(sine(span, 1000, 0.1), sine(span, 7000, 0.5))
    let mixedOut = deEssed(deEsserStage(), [mixed]) { _ in s }[0]
    let kept = db(amplitude(mixedOut, 1000, last: last) / amplitude(mixed, 1000, last: last))
    let keptOK = abs(kept) <= 0.1
    good = good && keptOK
    detail.append("1 kHz beside 7 kHz \(f3(kept))")
    // A loud 1 kHz with a quiet 7 kHz under the threshold: the 7 kHz stays
    // (the sidechain is the band, not the whole signal).
    let quiet = add(sine(span, 1000, 0.5), sine(span, 7000, 0.01))
    let quietOut = deEssed(deEsserStage(), [quiet]) { _ in sweepS }[0]
    let seven = db(amplitude(quietOut, 7000, last: last) / amplitude(quiet, 7000, last: last))
    let sevenOK = abs(seven) <= 0.1
    good = good && sevenOK
    detail.append("quiet 7 kHz beside loud 1 kHz \(f3(seven))")
    check("D6", "the de-esser reduces the band by the crossover's analytic amount ±0.1 dB, never "
            + "boosts (2–12 kHz), passes 1 kHz as an allpass, keys on the band", good,
          detail.joined(separator: ", "))
}

// MARK: - D7 the gate before the compressor

do {
    let input = quarter(2 * 48_000, 0.01)  // −40 dBFS
    let params = AudioClipDSP(
        compressor: AudioCompressorSettings(
            thresholdDB: 0, ratio: 1, attackSeconds: 0, releaseSeconds: 0, makeupDB: 24),
        gate: gateSettings(level: -20, threshold: -10, ratio: 4, range: 20))
    let chain = AudioDSPChain(
        channelCount: 1, sampleRate: fs, maxFrames: 4096, usesNoiseReduction: false)
    let out = drive([input]) { p, _, f, _ in chain.process(p, frames: f, params: params) }[0]
    let level = db(Double(out.suffix(9_600).map { abs($0) }.max() ?? 0))
    check("D7", "the gate runs before the compressor: −40 dBFS gated 20 dB, then +24 dB of makeup",
          abs(level - -36) <= 0.1, "out at \(f3(level)) dBFS (−36)")
}

// MARK: - Loudness caches

final class ResultBox: @unchecked Sendable { var value = false }

func buildLoudness(media id: UInt32, file: String, into dir: URL, after delay: Double = 0,
                   wait: Bool = true) {
    let url = fixtures.appendingPathComponent(file)
    let media = MediaSnapshot(id: id, path: url.path, kind: .audio, duration: 12 * 600_000,
                              hasVideo: false, hasAudio: true)
    let done = DispatchSemaphore(value: 0)
    let box = ResultBox()
    Task.detached {
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
        box.value = await MediaImporter.loudness(
            for: media, url: url, stamp: MediaImporter.CacheStamp.stamp(for: media, url: url),
            into: dir)
        done.signal()
    }
    if wait { _ = done.wait(timeout: .now() + 120) }
}

func freshDir(_ name: String) -> URL {
    let dir = scratch.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func project(media: [(UInt32, String)], clips: String, nests: String = "[]") -> ReelProject? {
    let list = media.map { id, file in
        """
        {"id": \(id), "path": "\(fixtures.appendingPathComponent(file).path)", "kind": "audio",
         "duration": \(12 * 600_000), "has_video": false, "has_audio": true}
        """
    }.joined(separator: ",")
    do {
        return try ReelProject.from(json: """
        {"version": \(RC_FORMAT_VERSION),
         "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
         "media": [\(list)],
         "tracks": [{"id": 3, "name": "Track 1"}, {"id": 8, "name": "Track 2"}],
         "clips": [\(clips)], "nests": \(nests), "next_id": 100}
        """)
    } catch {
        print("project: \(error)")
        return nil
    }
}

// MARK: - D8 the levels

let levelsDir = freshDir("levels")
buildLoudness(media: 51, file: "voice.wav", into: levelsDir)

do {
    let p = project(
        media: [(51, "voice.wav"), (52, "voice2.wav")],
        clips: """
            {"id": 2, "track": 3, "start": 0, "duration": 1800000,
             "source": {"kind": "media", "media": 51, "in": 0}, "audio": {"gate": {}}},
            {"id": 4, "track": 3, "start": 1800000, "duration": 1800000,
             "source": {"kind": "media", "media": 51, "in": 1800000},
             "audio": {"de_esser": {"threshold_db": -3}, "pan": 0.5}},
            {"id": 6, "track": 3, "start": 3600000, "duration": 120000,
             "source": {"kind": "media", "media": 51, "in": 3600000}, "audio": {"gate": {}}},
            {"id": 7, "track": 8, "start": 0, "duration": 1800000,
             "source": {"kind": "media", "media": 52, "in": 0}, "audio": {"gate": {}}},
            {"id": 9, "track": 8, "start": 2400000, "duration": 1200000,
             "source": {"kind": "nest", "project": 20}, "audio": {"gate": {}}}
            """,
        nests: """
            [{"id": 20, "name": "Nest 20", "width": 320, "height": 180,
              "tracks": [{"id": 21, "name": "Track 1"}],
              "clips": [{"id": 22, "track": 21, "start": 0, "duration": 1200000,
                         "source": {"kind": "media", "media": 51, "in": 0}}]}]
            """)
    guard let p else {
        check("D8", "the levels project opens", false)
        exit(1)
    }
    let levels = AudioDynamicsLevels.shared.levels(for: p, cache: levelsDir)
    let parameters = AudioDSPParameters.measured(project: p, cache: levelsDir)
    let segments = p.plan.map(AudioNormalize.audioSegments(in:)) ?? [:]
    func reference(_ clip: UInt32) -> Double? {
        if case .reading(let r) = ClipLoudness.answer(
            for: clip, snapshot: p.snapshot, segments: segments,
            loader: ClipLoudness.loader(cacheDirectory: levelsDir)) { return r.lufs }
        return nil
    }
    var lufs: [UInt32: Double] = [:]
    for (id, level) in levels { if case .measured(let l) = level { lufs[id] = l } }
    let equal = lufs[2] != nil && lufs[2] == reference(2) && lufs[4] == reference(4)
    let gateRel = parameters.dsp(for: 2).gate?.thresholdDB == lufs[2].map { $0 - 10 }
    let deRel = parameters.dsp(for: 4).deEsser?.thresholdDB == lufs[4].map { $0 - 3 }
    var short = false
    if case .unmeasurable = levels[6] { short = parameters.dsp(for: 6).gate == nil }
    let pending = levels[7] == .pending && parameters.pendingLevels == [7]
        && parameters.dsp(for: 7).isInert
    let nest = levels[9] == nil && levels[22] == nil && parameters.dsp(for: 9).isInert
        && Set(levels.keys) == [2, 4, 6, 7]
    let noCache = AudioDynamicsLevels.shared.levels(for: p, cache: nil).values
        .allSatisfy { $0 == .pending }
    buildLoudness(media: 52, file: "voice2.wav", into: levelsDir)
    var landed = false
    if case .measured = AudioDynamicsLevels.shared.levels(for: p, cache: levelsDir)[7] {
        landed = true
    }
    check("D8", "threshold = L + rel exactly, L equals ClipLoudness's, pending → nil and in "
            + "pendingLevels, unmeasurable → nil, nest ignored, no cache pending, a pending "
            + "answer measured once its file is written",
          equal && gateRel && deRel && short && pending && nest && noCache && landed,
          "L2 \(f3(lufs[2])), L4 \(f3(lufs[4])), equal \(equal), gate \(gateRel), de-esser "
            + "\(deRel), short \(short), pending \(pending), nest \(nest), no cache \(noCache), "
            + "landed \(landed)")
}

// MARK: - D9 the export's wait

do {
    let dir = freshDir("wait")
    func one(_ media: UInt32, _ file: String) -> ReelProject? {
        project(media: [(media, file)], clips: """
            {"id": 2, "track": 3, "start": 0, "duration": 1800000,
             "source": {"kind": "media", "media": \(media), "in": 0}, "audio": {"gate": {}}}
            """)
    }
    var results: [String] = []
    var good = true
    if let landing = one(53, "voice3.wav") {
        buildLoudness(media: 53, file: "voice3.wav", into: dir, after: 0.3, wait: false)
        let r = AudioDynamicsLevels.shared.wait(
            for: [2], in: landing, cache: dir, timeout: 30, cancelled: { false })
        good = good && r == .landed
        results.append("landing \(r)")
    } else { good = false }
    if let never = one(54, "voice4.wav") {
        let start = Date()
        let r = AudioDynamicsLevels.shared.wait(
            for: [2], in: never, cache: dir, timeout: 0.3, cancelled: { false })
        let took = Date().timeIntervalSince(start)
        good = good && r == .timedOut(clip: 2) && took >= 0.3 && took < 2
        results.append("never \(r) after \(f3(took)) s")
        var asked = 0
        let c = AudioDynamicsLevels.shared.wait(
            for: [2], in: never, cache: dir, timeout: 30, cancelled: {
                asked += 1
                return asked > 2
            })
        good = good && c == .cancelled
        results.append("cancel \(c)")
    } else { good = false }
    check("D9", "wait answers landed, timedOut and cancelled over a scratch cache", good,
          results.joined(separator: ", "))
}

// MARK: - D10 the preview against the reader

final class TrackBox: @unchecked Sendable { var track: AVAssetTrack? }

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

do {
    let url = fixtures.appendingPathComponent("voice.wav")
    let asset = AVURLAsset(url: url)
    let span: Ticks = 10 * 600_000
    let parameters = project(media: [(51, "voice.wav")], clips: """
        {"id": 2, "track": 3, "start": 0, "duration": \(span),
         "source": {"kind": "media", "media": 51, "in": 0},
         "audio": {"gate": {}, "de_esser": {}}}
        """).map { AudioDSPParameters.measured(project: $0, cache: levelsDir) } ?? .empty
    let armed = parameters.dsp(for: 2).gate != nil && parameters.dsp(for: 2).deEsser != nil
    let track = AudioTrackDSP(segments: [segment(duration: span)], parameters: parameters)
    let composition = AVMutableComposition()
    if armed, let source = loadTrack(asset),
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
        let reading = CaptureTap(track: track, channel: 0)
        if let reader = try? AVAssetReader(asset: composition) {
            let output = AVAssetReaderAudioMixOutput(audioTracks: [target], audioSettings: nil)
            output.audioMix = mix(reading)
            reader.add(output)
            reader.startReading()
            while output.copyNextSampleBuffer() != nil {}
        }
        let previewing = CaptureTap(track: track, channel: 0)
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
        // The gate acted: some exported samples sit well under the source's.
        var turnedDown = 0
        for i in 0..<min(window, voice.count) where !exported[i].isNaN && abs(voice[i]) > 1e-4 {
            if abs(exported[i]) < abs(voice[i]) * 0.5 { turnedDown += 1 }
        }
        check("D10", "the owner's recording under the default gate and de-esser: the muted "
                + "player's tap output equals the reader's within the first 4 s",
              compared >= 100_000 && differ == 0 && turnedDown > 1000,
              "compared \(compared), differ \(differ), samples turned down \(turnedDown)")
    } else {
        check("D10", "the composition builds with both stages armed", false, "armed \(armed)")
    }
}

// MARK: - D11 the cost

do {
    let gate = gateStage()
    let de = deEsserStage(2)
    let g = gateSettings(level: -40)
    let d = deEsserSettings(level: -40, threshold: -6, range: 12)
    let planar = Planar([Array(voiceL.prefix(1024)), Array(voiceR.prefix(1024))])
    let rounds = 2_000
    var best = Double.infinity
    for _ in 0..<3 {
        let begin = DispatchTime.now().uptimeNanoseconds
        let pointers = planar.at(0)
        for _ in 0..<rounds {
            gate.process(pointers, count: 2, frames: 1024, settings: g)
            de.process(pointers, count: 2, frames: 1024, settings: d)
        }
        let micro = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1000 / Double(rounds)
        best = min(best, micro)
    }
    let share = best / (1024 / fs * 1_000_000) * 100
    check("D11", "µs per 1024 stereo frames through the gate and the de-esser (reported), ≤ 1 % "
            + "of real time", share <= 1,
          String(format: "%.1f µs (best of 3 × %d), %.2f %% of real time", best, rounds, share))
}
