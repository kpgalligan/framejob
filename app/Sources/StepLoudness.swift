import Accelerate
import Foundation

/// BS.1770-4's integrated loudness over 10 ms steps — the one gating rule
/// the loudness cache's readings (`ClipLoudness`), the clip limiter's model
/// (`AudioLimiterModel`) and the export's gain under its master (spec §11
/// AU-28) all count with. Moved verbatim out of `ClipLoudness` (road map
/// "audio" AP2 part 2), so the export, which has no clip, can gate its own
/// steps through it.
enum StepLoudness {
    /// One step at 48 kHz: 10 ms, the loudness cache's grid.
    static let stepFrames = 480

    /// BS.1770-4's gating over 10 ms steps: block j is the mean of steps
    /// `[10j, 10j + 40)`, `⌊(N − 40)/10⌋ + 1` of them; the absolute gate, then
    /// the relative one, once (`LoudnessMeter.integrated`'s rule).
    static func integrated(_ steps: [Double]) -> Double? {
        guard steps.count >= 40 else { return nil }
        let count = (steps.count - 40) / 10 + 1
        var blocks: [Double] = []
        blocks.reserveCapacity(count)
        for j in 0..<count {
            blocks.append(steps[(10 * j)..<(10 * j + 40)].reduce(0, +) / 40)
        }
        let gated = blocks.filter { $0 > 0 && loudness($0) > LoudnessMeter.absoluteGate }
        guard !gated.isEmpty else { return nil }
        let threshold = loudness(gated.reduce(0, +) / Double(gated.count))
            + LoudnessMeter.relativeGate
        let kept = gated.filter { loudness($0) > threshold }
        guard !kept.isEmpty else { return nil }
        return loudness(kept.reduce(0, +) / Double(kept.count))
    }

    static func loudness(_ meanSquare: Double) -> Double {
        meanSquare > 0 ? LoudnessMeter.offset + 10 * log10(meanSquare) : -.infinity
    }
}

/// The export mix's 10 ms steps (spec §11 AU-28): 48 kHz interleaved stereo
/// float in, and per 480-frame step the Σ over the two channels of the mean
/// K-weighted square (`LoudnessMeter.stage1`, `stage2`) and the step's true
/// peak — the largest over both channels of |x| and Annex 2's four
/// interpolated phases (`LoudnessMeter.peakFilter`), linear. The steps
/// `AudioLimiterModel` reads, in the shape a clip's loudness reading hands
/// it (`ClipLoudness.Reading.steps`, `stepPeaks`).
///
/// Filter state and the interpolator's history run across calls and steps,
/// as `LoudnessMeter`'s do, so the steps are one programme cut every 10 ms.
/// A last partial step is kept, its mean over the frames it holds. Pass one
/// of an export feeds it beside its `LoudnessMeter` (`ExporterLoudness`), on
/// the build queue.
final class StepLoudnessMeter {
    private static let channelCount = 2
    private static let taps = LoudnessMeter.peakTaps
    private static let phases = LoudnessMeter.peakPhases

    private var steps: [Double] = []
    private var peaks: [Double] = []
    /// Σ over channels of Σ y² for the step being filled, its frames, and its
    /// true peak so far.
    private var stepSum: Double = 0
    private var stepFilled = 0
    private var stepPeak: Double = 0

    /// Per channel: `history` raw samples, then up to one step of new ones.
    private let channelBuffer: UnsafeMutablePointer<Double>
    private let phaseBuffer: UnsafeMutablePointer<Double>
    /// The last `taps − 1` raw samples of each channel.
    private let peakHistory: UnsafeMutablePointer<Double>
    /// Each phase's taps reversed, so `vDSP_convD` convolves (`LoudnessMeter`'s
    /// arrangement).
    private let coefficients: UnsafeMutablePointer<Double>
    /// Two sections of `x[n−1], x[n−2], y[n−1], y[n−2]`, per channel.
    private let filterState: UnsafeMutablePointer<Double>

    init() {
        let taps = Self.taps
        let run = StepLoudness.stepFrames + taps - 1
        channelBuffer = .allocate(capacity: run)
        channelBuffer.initialize(repeating: 0, count: run)
        phaseBuffer = .allocate(capacity: StepLoudness.stepFrames)
        phaseBuffer.initialize(repeating: 0, count: StepLoudness.stepFrames)
        peakHistory = .allocate(capacity: Self.channelCount * (taps - 1))
        peakHistory.initialize(repeating: 0, count: Self.channelCount * (taps - 1))
        coefficients = .allocate(capacity: Self.phases * taps)
        coefficients.initialize(repeating: 0, count: Self.phases * taps)
        for (index, phase) in LoudnessMeter.peakFilter.enumerated() {
            for (tap, value) in phase.reversed().enumerated() {
                coefficients[index * taps + tap] = value
            }
        }
        filterState = .allocate(capacity: Self.channelCount * 8)
        filterState.initialize(repeating: 0, count: Self.channelCount * 8)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("StepLoudnessMeter does not support NSCoder")
    }

    deinit {
        channelBuffer.deallocate()
        phaseBuffer.deallocate()
        peakHistory.deallocate()
        coefficients.deallocate()
        filterState.deallocate()
    }

    /// `frames` interleaved stereo frames of 32-bit float, in programme order.
    func feed(_ samples: UnsafePointer<Float>, frames: Int) {
        var offset = 0
        while offset < frames {
            // Never across a step boundary: each chunk belongs to one step.
            let take = min(StepLoudness.stepFrames - stepFilled, frames - offset)
            process(samples + offset * Self.channelCount, frames: take)
            offset += take
        }
    }

    /// The steps' energies and true peaks, the last partial step included.
    func finish() -> (steps: [Double], peaks: [Double]) {
        if stepFilled > 0 { closeStep() }
        return (steps, peaks)
    }

    /// One chunk, wholly inside one step.
    private func process(_ samples: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        let taps = Self.taps
        let history = taps - 1
        var chunkPeak: Float = 0
        vDSP_maxmgv(samples, 1, &chunkPeak, vDSP_Length(frames * Self.channelCount))
        stepPeak = max(stepPeak, Double(chunkPeak))
        for channel in 0..<Self.channelCount {
            channelBuffer.update(from: peakHistory + channel * history, count: history)
            vDSP_vspdp(
                samples + channel, vDSP_Stride(Self.channelCount), channelBuffer + history, 1,
                vDSP_Length(frames))
            // The true peak on the unweighted samples.
            for phase in 0..<Self.phases {
                vDSP_convD(
                    channelBuffer, 1, coefficients + phase * taps, 1, phaseBuffer, 1,
                    vDSP_Length(frames), vDSP_Length(taps))
                var peak: Double = 0
                vDSP_maxmgvD(phaseBuffer, 1, &peak, vDSP_Length(frames))
                stepPeak = max(stepPeak, peak)
            }
            (peakHistory + channel * history).update(
                from: channelBuffer + frames, count: history)
            weight(channelBuffer + history, frames: frames, channel: channel)
            var sum: Double = 0
            vDSP_svesqD(channelBuffer + history, 1, &sum, vDSP_Length(frames))
            stepSum += sum
        }
        stepFilled += frames
        if stepFilled >= StepLoudness.stepFrames { closeStep() }
    }

    /// The two-stage K-weighting at 48 kHz, in place, with this channel's state.
    private func weight(_ samples: UnsafeMutablePointer<Double>, frames: Int, channel: Int) {
        let base = filterState + channel * 8
        for (index, section) in [LoudnessMeter.stage1, LoudnessMeter.stage2].enumerated() {
            let state = base + index * 4
            var x1 = state[0], x2 = state[1], y1 = state[2], y2 = state[3]
            for n in 0..<frames {
                let x = samples[n]
                let y = section.b0 * x + section.b1 * x1 + section.b2 * x2
                    - section.a1 * y1 - section.a2 * y2
                x2 = x1
                x1 = x
                y2 = y1
                y1 = y
                samples[n] = y
            }
            state[0] = x1
            state[1] = x2
            state[2] = y1
            state[3] = y2
        }
    }

    private func closeStep() {
        steps.append(stepSum / Double(stepFilled))
        peaks.append(stepPeak)
        stepSum = 0
        stepFilled = 0
        stepPeak = 0
    }
}
