// Copied verbatim from app/Sources/AudioDSP.swift at 9e47f56: lines 1-82 and 195-345.
import Accelerate
import Foundation

/// The four sample-level audio effects the model carries and AVFoundation
/// cannot express: pan, the mono fold, the compressor and broadband noise
/// reduction (spec §4.2, §5.2's `AudioProps`).
///
/// **Why this file has no AVFoundation in it.** Volume, the fades and ducking
/// are a gain CURVE, so `audio.rs` folds them into one envelope per
/// composition track and `AVMutableAudioMixInputParameters` plays it back as
/// volume ramps. These four cannot be a curve: pan and the mono fold need
/// every channel at once to write to, and the compressor and the noise reducer
/// are functions of the samples rather than of the clock. So they are real
/// DSP, they run in Swift,
/// and they live here — plain buffers in, plain buffers out, no player, no
/// reader, no tap. `AudioTap.swift` is the only file that knows where the
/// buffers come from, which is what lets the SAME code serve the preview and
/// the export (§7.2's one-movie-one-description rule).
///
/// **Real-time discipline.** Everything runs inside
/// `MTAudioProcessingTap`'s process callback, on a thread that must not
/// block: every buffer these types touch is allocated once in `init` and
/// never grown, nothing here takes a lock, and no Swift value that could
/// allocate is created per sample. `frames` is never larger than the
/// `maxFrames` the chain was built with.
///
/// **Transparency is a property of the CALLER, not of these types.** With
/// pan 0, mono off, no compressor and noise reduction 0 the chain is still a
/// chain, and
/// running audio through the noise reducer's FFT round trip would change the
/// low bits even though it changes nothing audible. So `CompositionBuilder`
/// installs no tap at all on a track whose every clip is inert
/// (`AudioClipDSP.isInert`), and such a track's samples are the ones today's
/// build produces, byte for byte.
enum AudioDSP {
    /// Below this the compressor's detector is treated as silence rather than
    /// fed to `log10`, which would otherwise return -inf and poison the
    /// envelope. -180 dBFS: far under any 24-bit source's noise floor.
    static let silenceFloor: Float = 1e-9

    /// dB → linear gain, and the constant that turns a dB difference into an
    /// exponent for `expf` (ln 10 / 20). One `expf` per sample is cheaper than
    /// one `powf`.
    static let dbToExponent: Float = 0.115_129_254_649_702_28

    static func gain(fromDecibels db: Float) -> Float { expf(db * dbToExponent) }
}

// MARK: - Parameters

/// The compressor's settings in the units the DSP works in.
///
/// The model spells the two time constants in TICKS, like every other time in
/// the schema (`core/src/model.rs`'s `Compressor`). They become seconds
/// exactly once, in `AudioClipDSP`'s conversion, so nothing below this line
/// ever sees a tick — the rule the slice was written to.
struct AudioCompressorSettings: Equatable {
    /// dBFS above which gain reduction starts, clamped to the model's -60…0.
    var thresholdDB: Double
    /// N:1. 1 is no reduction at all (the makeup still applies), 20 is
    /// effectively a limiter.
    var ratio: Double
    /// Seconds for the reduction to close on a level that just rose.
    var attackSeconds: Double
    /// Seconds for it to open again on a level that just fell.
    var releaseSeconds: Double
    /// dB added after the reduction, to win back what it took.
    var makeupDB: Double

    init(
        thresholdDB: Double, ratio: Double, attackSeconds: Double, releaseSeconds: Double,
        makeupDB: Double
    ) {
        // A hand-edited project can carry anything; the op's own range checks
        // (`props_check.rs`'s `check_audio`) only cover what the app wrote.
        self.thresholdDB = thresholdDB.isFinite ? Swift.min(Swift.max(thresholdDB, -60), 0) : -18
        self.ratio = ratio.isFinite ? Swift.min(Swift.max(ratio, 1), 20) : 1
        self.attackSeconds = attackSeconds.isFinite ? Swift.max(attackSeconds, 0) : 0
        self.releaseSeconds = releaseSeconds.isFinite ? Swift.max(releaseSeconds, 0) : 0
        self.makeupDB = makeupDB.isFinite ? Swift.min(Swift.max(makeupDB, 0), 24) : 0
    }
}
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
