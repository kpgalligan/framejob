import Foundation

/// The EQ and the hum notch, one stage at the head of the clip chain after
/// the channel pick (spec §11 AU-30, AU-3's order: EQ, then hum).
///
/// RBJ biquads in Double, transposed direct form II, scalar per sample over
/// raw pointers — sections outer, samples inner, one channel at a time. Never
/// `vDSP_biquad`, which gives different bits for different buffer sizes (S1),
/// and the tap cuts buffers at every clip's span.
///
/// **17 fixed positions** (`AudioEQDesign.positions`), so a slot present in
/// two abutting clips keeps its state across the cut, and a position that
/// turns on starts from zero: an inactive position is skipped and its state
/// zeroed. The coefficients are designed in `process` only when the run's
/// settings differ from the last designed — nothing allocated, nothing
/// locked — so they switch at the cut sample (S1 measured the splatter of
/// such a switch at −79 dB, accepted). AP8's seam is `design` and that swap
/// point, where a per-sample glide would go.
///
/// Real-time rules (`AudioDSP.swift`'s head): every buffer is allocated in
/// `init`; `reset()` zeroes every state and forgets the design; nil settings
/// touch no sample.
final class AudioEQStage {
    let channelCount: Int
    let sampleRate: Double
    private let coefficients: UnsafeMutablePointer<AudioBiquadCoefficients>
    private let active: UnsafeMutablePointer<Bool>
    /// z1, z2 per channel per position: `[(channel · positions + p) · 2]`.
    private let state: UnsafeMutablePointer<Double>
    private let stateCount: Int
    /// What the coefficients were designed from; nil when nothing is.
    private var designed: AudioEQSettings?

    init(channelCount: Int, sampleRate: Double) {
        self.channelCount = max(0, channelCount)
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        let positions = AudioEQDesign.positions
        coefficients = .allocate(capacity: positions)
        coefficients.initialize(repeating: .identity, count: positions)
        active = .allocate(capacity: positions)
        active.initialize(repeating: false, count: positions)
        stateCount = max(1, self.channelCount * positions * 2)
        state = .allocate(capacity: stateCount)
        state.initialize(repeating: 0, count: stateCount)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioEQStage does not support NSCoder")
    }

    deinit {
        coefficients.deallocate()
        active.deallocate()
        state.deallocate()
    }

    /// A fresh stage: every state zero, no design.
    func reset() {
        state.update(repeating: 0, count: stateCount)
        designed = nil
    }

    /// Runs the EQ and the hum over one run of `frames` in place. `settings`
    /// is the run's clip's; nil touches no sample (and zeroes every state,
    /// every position being off).
    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, settings: AudioEQSettings?
    ) {
        guard let settings else {
            if designed != nil {
                state.update(repeating: 0, count: stateCount)
                designed = nil
            }
            return
        }
        let positions = AudioEQDesign.positions
        if designed != settings {
            AudioEQDesign.design(
                settings, sampleRate: sampleRate, into: coefficients, active: active)
            for channel in 0..<channelCount {
                for p in 0..<positions where !active[p] {
                    let at = (channel * positions + p) * 2
                    state[at] = 0
                    state[at + 1] = 0
                }
            }
            designed = settings
        }
        let used = min(count, channels.count, channelCount)
        guard frames > 0, used > 0 else { return }
        for channel in 0..<used {
            guard let data = channels[channel] else { continue }
            for p in 0..<positions where active[p] {
                let c = coefficients[p]
                let at = (channel * positions + p) * 2
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
        }
    }
}
