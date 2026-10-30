import Accelerate
import Foundation

// The compressor stage `AudioDSPChain` runs: a pure move out of `AudioDSP.swift` (road map
// "audio" AP0's toll T1), whose head says why the stages have no AVFoundation in them and
// what real-time discipline they keep.

// MARK: - Compressor

/// A feed-forward peak compressor with a hard knee, channel-linked.
///
/// **Linked, not per channel.** The detector is the largest absolute sample
/// across the channels and one gain is applied to all of them. Compressing
/// each channel on its own detector makes the stereo image wander whenever
/// one side is louder, which is the classic way a compressor ruins a mix.
///
/// **One compressor per composition TRACK, not per clip.** A composition
/// audio track is a sequence of clips (§7.2) and this sits on it like a
/// channel-strip insert: the settings change at each cut, the envelope
/// carries across it. Restarting the envelope per clip would make every cut
/// audible as a jump in gain reduction.
///
/// The envelope is a one-pole smoother on the gain reduction in dB, which is
/// the standard shape: `attack` is how fast the reduction closes on a level
/// that just rose, `release` how fast it opens again.
final class AudioCompressorStage {
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
        fatalError("AudioCompressorStage does not support NSCoder")
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
