import Accelerate
import Foundation

/// What one clip's de-esser asks the stage for (spec §11 AU-44, AU-45): the
/// crossover in Hz, the threshold in absolute dBFS on the sidechain's
/// follower — the clip's measured loudness `level` plus the relative
/// threshold — and the range. A hand-edited value outside the model's ranges
/// is held to them (the core's `clamp_de_esser` says the same).
struct AudioDeEsserSettings: Equatable {
    let frequency: Double
    let thresholdDB: Double
    let rangeDB: Double

    init(level: Double, props: DeEsserProps) {
        func bounded(_ value: Double, _ low: Double, _ high: Double, _ neutral: Double) -> Double {
            value.isNaN ? neutral : Swift.min(Swift.max(value, low), high)
        }
        frequency = bounded(props.frequency, 2000, 12_000, 6000)
        thresholdDB = (level.isFinite ? level : 0) + bounded(props.thresholdDb, -30, 20, 0)
        rangeDB = bounded(props.rangeDb, 1, 24, 6)
    }
}

/// The split-band de-esser (spec §11 AU-44), after the gate and before the
/// compressor (AU-47).
///
/// **Detection.** A sidechain per channel — a 24 dB/octave Butterworth
/// high-pass at `frequency`, two RBJ sections (Q 0.541, 1.307) — then the
/// compressor's linked peak follower over it (`AudioEnvelope`, 10 ms fall).
/// Above the threshold the target reduction is `min(range, level − threshold)`
/// dB (∞:1, never deeper than the range); it closes in 1 ms and opens in
/// 60 ms, and `g = 10^(−reduction/20)`.
///
/// **Reduction, through a Linkwitz–Riley crossover.** The same `frequency`
/// splits each channel into `low` (two `lowPass(f, q: 1/√2)` sections) and
/// `band` (two `highPass(f, q: 1/√2)`), and the output is `low + g·band`.
/// LR4's two outputs are in phase at every frequency and sum to an allpass,
/// so `|out/x| = 1 − (1 − g)·|band|`, in `[g, 1]`: no frequency is boosted.
/// (`x − (1 − g)·band` would be: a 4th-order Butterworth high-pass is 180°
/// out at its cut.) At `g = 1` the output is x's allpass — flat, but not x's
/// bytes. All six sections are redesigned when the frequency changes, their
/// state kept; a frequency at or above 0.49·fs is not designed and x passes
/// untouched.
///
/// RBJ in Double, transposed direct form II, scalar per sample over raw
/// pointers (never `vDSP_biquad`, S1); the sum by element-wise vDSP. Real-time
/// rules (`AudioDSP.swift`'s head): buffers allocated in `init`, chunks at
/// capacity; nil settings reset the stage and touch no sample.
final class AudioDeEsserStage {
    static let attackSeconds = 0.001
    static let releaseSeconds = 0.060

    /// Sidechain high-pass 1 and 2, the crossover's low-pass and its
    /// high-pass (each run twice).
    private static let sections = 6
    let channelCount: Int
    private let sampleRate: Double
    private let capacity: Int
    /// The four designs: sidechain 1, sidechain 2, crossover low, crossover
    /// high.
    private let coefficients: UnsafeMutablePointer<AudioBiquadCoefficients>
    /// z1, z2 per channel per section: `[(channel · sections + s) · 2]`.
    private let state: UnsafeMutablePointer<Double>
    private let stateCount: Int
    /// `low` and `band` for every channel, `channel · capacity` apart.
    private let low: UnsafeMutablePointer<Float>
    private let band: UnsafeMutablePointer<Float>
    private let sidechain: UnsafeMutablePointer<Float>
    private let detector: UnsafeMutablePointer<Float>
    private let gains: UnsafeMutablePointer<Float>
    private var designedFrequency: Double?
    private var reductionDB: Float = 0
    private var follower = AudioPeakFollower()

    init(channelCount: Int, sampleRate: Double, maxFrames: Int) {
        self.channelCount = max(0, channelCount)
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        capacity = max(1, maxFrames)
        coefficients = .allocate(capacity: 4)
        coefficients.initialize(repeating: .identity, count: 4)
        stateCount = max(1, self.channelCount * Self.sections * 2)
        state = .allocate(capacity: stateCount)
        state.initialize(repeating: 0, count: stateCount)
        let planes = max(1, self.channelCount) * capacity
        low = .allocate(capacity: planes)
        low.initialize(repeating: 0, count: planes)
        band = .allocate(capacity: planes)
        band.initialize(repeating: 0, count: planes)
        sidechain = .allocate(capacity: capacity)
        sidechain.initialize(repeating: 0, count: capacity)
        detector = .allocate(capacity: capacity)
        detector.initialize(repeating: 0, count: capacity)
        gains = .allocate(capacity: capacity)
        gains.initialize(repeating: 1, count: capacity)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioDeEsserStage does not support NSCoder")
    }

    deinit {
        coefficients.deallocate()
        state.deallocate()
        low.deallocate()
        band.deallocate()
        sidechain.deallocate()
        detector.deallocate()
        gains.deallocate()
    }

    /// A fresh stage: every section's state zero, no reduction, no design.
    func reset() {
        state.update(repeating: 0, count: stateCount)
        reductionDB = 0
        follower.reset()
        designedFrequency = nil
    }

    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, settings: AudioDeEsserSettings?
    ) {
        guard let settings, settings.frequency < 0.49 * sampleRate else {
            reset()
            return
        }
        let used = min(count, channels.count, channelCount)
        guard frames > 0, used > 0 else { return }
        if designedFrequency != settings.frequency {
            design(settings.frequency)
        }
        var offset = 0
        while offset < frames {
            let chunk = min(capacity, frames - offset)
            processChunk(channels, count: used, offset: offset, frames: chunk, settings: settings)
            offset += chunk
        }
    }

    /// The four designs at `frequency`, into storage allocated in `init`.
    private func design(_ frequency: Double) {
        coefficients[0] = AudioEQDesign.highPass(
            frequency, q: AudioEQDesign.butterworthQ(sections: 2, index: 0),
            sampleRate: sampleRate)
        coefficients[1] = AudioEQDesign.highPass(
            frequency, q: AudioEQDesign.butterworthQ(sections: 2, index: 1),
            sampleRate: sampleRate)
        let q = 0.5.squareRoot()
        coefficients[2] = AudioEQDesign.lowPass(frequency, q: q, sampleRate: sampleRate)
        coefficients[3] = AudioEQDesign.highPass(frequency, q: q, sampleRate: sampleRate)
        designedFrequency = frequency
    }

    /// One section over `frames` samples of `data`, in place.
    @inline(__always)
    private func run(
        _ c: AudioBiquadCoefficients, _ data: UnsafeMutablePointer<Float>, frames: Int,
        state at: Int
    ) {
        var z1 = state[at]
        var z2 = state[at + 1]
        for i in 0..<frames {
            let x = Double(data[i])
            let y = c.b0 * x + z1
            z1 = c.b1 * x - c.a1 * y + z2
            z2 = c.b2 * x - c.a2 * y
            data[i] = Float(y)
        }
        state[at] = z1
        state[at + 1] = z2
    }

    private func processChunk(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        offset: Int, frames: Int, settings: AudioDeEsserSettings
    ) {
        let length = vDSP_Length(frames)
        var detected = false
        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            let input = data + offset
            let base = channel * Self.sections * 2
            // The sidechain, then |sidechain| into the linked detector.
            sidechain.update(from: input, count: frames)
            run(coefficients[0], sidechain, frames: frames, state: base)
            run(coefficients[1], sidechain, frames: frames, state: base + 2)
            vDSP_vabs(sidechain, 1, sidechain, 1, length)
            if detected {
                vDSP_vmax(detector, 1, sidechain, 1, detector, 1, length)
            } else {
                detector.update(from: sidechain, count: frames)
                detected = true
            }
            // The crossover's two halves.
            let lowPlane = low + channel * capacity
            let bandPlane = band + channel * capacity
            lowPlane.update(from: input, count: frames)
            run(coefficients[2], lowPlane, frames: frames, state: base + 4)
            run(coefficients[2], lowPlane, frames: frames, state: base + 6)
            bandPlane.update(from: input, count: frames)
            run(coefficients[3], bandPlane, frames: frames, state: base + 8)
            run(coefficients[3], bandPlane, frames: frames, state: base + 10)
        }
        guard detected else { return }

        let thresholdDB = Float(settings.thresholdDB)
        let thresholdLinear = AudioDSP.gain(fromDecibels: thresholdDB)
        let range = Float(settings.rangeDB)
        let attack = AudioEnvelope.coefficient(seconds: Self.attackSeconds, sampleRate: sampleRate)
        let release = AudioEnvelope.coefficient(
            seconds: Self.releaseSeconds, sampleRate: sampleRate)
        let fall = AudioEnvelope.fall(seconds: 0, sampleRate: sampleRate)
        for index in 0..<frames {
            let level = follower.follow(detector[index], fall: fall)
            var target: Float = 0
            if level > thresholdLinear {
                target = min(range, 20 * log10f(level) - thresholdDB)
            }
            let coefficient = target > reductionDB ? attack : release
            reductionDB += (target - reductionDB) * coefficient
            gains[index] = AudioDSP.gain(fromDecibels: -reductionDB)
        }

        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            let bandPlane = band + channel * capacity
            vDSP_vmul(bandPlane, 1, gains, 1, bandPlane, 1, length)
            vDSP_vadd(low + channel * capacity, 1, bandPlane, 1, data + offset, 1, length)
        }
    }
}
