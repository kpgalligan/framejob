import Accelerate
import Foundation

/// What one clip's gate asks the stage for, in the stage's units (spec §11
/// AU-40, AU-41, AU-43): its threshold in absolute dBFS — the clip's measured
/// loudness `level` plus the relative threshold — and its times in seconds.
/// A hand-edited value outside the model's ranges is held to them (the
/// core's `clamp_gate` says the same).
struct AudioGateSettings: Equatable {
    let thresholdDB: Double
    let ratio: Double
    let rangeDB: Double
    let attackSeconds: Double
    let holdSeconds: Double
    let releaseSeconds: Double

    init(level: Double, props: GateProps) {
        func bounded(_ value: Double, _ low: Double, _ high: Double, _ neutral: Double) -> Double {
            value.isNaN ? neutral : Swift.min(Swift.max(value, low), high)
        }
        func seconds(_ ticks: Ticks, _ low: Ticks, _ high: Ticks) -> Double {
            Double(Swift.min(Swift.max(ticks, low), high)) / Double(ReelTime.perSecond)
        }
        let relative = bounded(props.thresholdDb, -40, 0, -10)
        thresholdDB = (level.isFinite ? level : 0) + relative
        ratio = bounded(props.ratio, 1, 20, 4)
        rangeDB = bounded(props.rangeDb, 1, 80, 20)
        attackSeconds = seconds(props.attack, 0, 60_000)
        holdSeconds = seconds(props.hold, 0, 300_000)
        releaseSeconds = seconds(props.release, 600, 1_200_000)
    }
}

/// The downward expander/gate (spec §11 AU-40), after noise reduction and
/// before the de-esser (AU-47).
///
/// The detector is the compressor's: the linked peak follower
/// (`AudioEnvelope`), falling at its 10 ms floor. Per sample, a level at or
/// above the threshold restarts the hold counter and asks for no reduction;
/// while the counter runs the gate stays open; after it, the target is
/// `min(range, (threshold − level)·(ratio − 1))` dB. The reduction moves
/// toward the target by one-pole steps — the attack's coefficient when it
/// opens (the target below the reduction), the release's when it closes —
/// and one gain multiplies every channel.
///
/// **Fresh state is OPEN** (no reduction, the follower at 0, no hold), and
/// `reset()` restores it; `AudioTap` resets the chain at every StartOfStream,
/// so the preview does not start closed off the silent pre-roll (S1).
/// Real-time rules (`AudioDSP.swift`'s head): buffers allocated in `init`,
/// scalar recursion and element-wise vDSP, chunks at capacity; nil settings
/// reset the stage and touch no sample.
final class AudioGateStage {
    private var reductionDB: Float = 0
    private var follower = AudioPeakFollower()
    /// Samples the gate stays open for after the level last reached the
    /// threshold.
    private var holdCounter = 0
    private let sampleRate: Double
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
        fatalError("AudioGateStage does not support NSCoder")
    }

    deinit {
        detector.deallocate()
        scratch.deallocate()
        gains.deallocate()
    }

    /// A fresh, open gate.
    func reset() {
        reductionDB = 0
        follower.reset()
        holdCounter = 0
    }

    /// Gates `frames` samples in place across `count` channels.
    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, settings: AudioGateSettings?
    ) {
        guard let settings else {
            reset()
            return
        }
        guard frames > 0, count > 0 else { return }
        var offset = 0
        while offset < frames {
            let chunk = min(capacity, frames - offset)
            processChunk(channels, count: count, offset: offset, frames: chunk, settings: settings)
            offset += chunk
        }
    }

    private func processChunk(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        offset: Int, frames: Int, settings: AudioGateSettings
    ) {
        guard
            AudioEnvelope.linkedPeaks(
                channels, count: count, offset: offset, frames: frames, into: detector,
                scratch: scratch)
        else { return }

        let thresholdDB = Float(settings.thresholdDB)
        let thresholdLinear = AudioDSP.gain(fromDecibels: thresholdDB)
        let expansion = Float(settings.ratio) - 1
        let range = Float(settings.rangeDB)
        let attack = AudioEnvelope.coefficient(
            seconds: settings.attackSeconds, sampleRate: sampleRate)
        let release = AudioEnvelope.coefficient(
            seconds: settings.releaseSeconds, sampleRate: sampleRate)
        let fall = AudioEnvelope.fall(seconds: 0, sampleRate: sampleRate)
        let holdFrames = Int((settings.holdSeconds * sampleRate).rounded())

        for index in 0..<frames {
            let level = follower.follow(detector[index], fall: fall)
            var target: Float = 0
            if level >= thresholdLinear {
                holdCounter = holdFrames
            } else if holdCounter > 0 {
                holdCounter -= 1
            } else if expansion > 0 {
                let levelDB = 20 * log10f(max(level, AudioDSP.silenceFloor))
                target = min(range, (thresholdDB - levelDB) * expansion)
            }
            let coefficient = target < reductionDB ? attack : release
            reductionDB += (target - reductionDB) * coefficient
            gains[index] = AudioDSP.gain(fromDecibels: -reductionDB)
        }

        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            vDSP_vmul(data + offset, 1, gains, 1, data + offset, 1, vDSP_Length(frames))
        }
    }
}
