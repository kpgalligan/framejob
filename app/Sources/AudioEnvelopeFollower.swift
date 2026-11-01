import Accelerate
import Foundation

// The envelope arithmetic the dynamics stages share (spec §11 AU-40, AU-44): the linked peak
// detector, the peak follower and the one-pole coefficients. Moved out of
// `AudioCompressorStage.swift` with its exact Float arithmetic, so the compressor's output is
// byte-identical to before; the gate (`AudioGateStage.swift`) and the de-esser's sidechain
// (`AudioDeEsserStage.swift`) follow the same envelope. `AudioDSP.swift`'s head has the
// real-time rules: nothing here allocates or locks.

enum AudioEnvelope {
    /// The follower never falls faster than this: a zero-release setting must
    /// not turn the follower back into `|x|`.
    static let fallFloorSeconds = 0.010

    /// The linked detector: `|x|` of the first channel with a buffer, then the
    /// running maximum against every other, into `detector` over `frames`
    /// samples from `offset`. Vectorised: two passes over the buffer rather
    /// than a branch per sample per channel. False when no channel has a
    /// buffer.
    static func linkedPeaks(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        offset: Int, frames: Int, into detector: UnsafeMutablePointer<Float>,
        scratch: UnsafeMutablePointer<Float>
    ) -> Bool {
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
        return wrote
    }

    /// A one-pole coefficient for a time constant in seconds: `1 − e^(−1/(s·fs))`.
    /// Zero seconds means "instantly", which is a legitimate setting (a
    /// brick-wall attack) and must not divide by zero.
    static func coefficient(seconds: Double, sampleRate: Double) -> Float {
        guard seconds > 0 else { return 1 }
        return Float(1 - exp(-1 / (seconds * sampleRate)))
    }

    /// The follower's per-sample fall, `e^(−1/(max(s, 10 ms)·fs))`.
    static func fall(seconds: Double, sampleRate: Double) -> Float {
        Float(exp(-1 / (max(seconds, fallFloorSeconds) * sampleRate)))
    }
}

/// A PEAK FOLLOWER: it jumps to each new peak and falls back at `fall` per
/// sample, rather than reading the raw `|x|`. A naive detector reads a
/// waveform's own zero crossings as the level collapsing, so a gain driven
/// by it is modulated at twice the signal's frequency: audible as distortion
/// on anything low.
struct AudioPeakFollower {
    private(set) var level: Float = 0

    @inline(__always)
    mutating func follow(_ peak: Float, fall: Float) -> Float {
        level = max(peak, level * fall)
        return level
    }

    mutating func reset() { level = 0 }
}
