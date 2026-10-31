import Foundation

/// A timeline track's compressor and limiter (format 36, spec §11 AU-150): the
/// settings, the stage both the export's sub-mix and the preview's tap run, and
/// the envelope the preview's tap pairs it with.
///
/// **Post-fader, on the track's sub-mix** (AU-151): after every clip's chain,
/// the envelope (clip volume, fades, crossfades, ducks, the track's volume) and
/// the track's pan — the compressor, then the limiter, whose ceiling is the
/// dBTP on what the track hands the mix (so it is told volume 1). The export
/// runs the stage on each track's float sub-mix (`ExportMixRead`, AU-152),
/// where it is exact. The preview runs it in each composition track's tap
/// (AU-153), which is PreEffects — the fader is downstream — so the tap gains
/// its samples by the track's envelope before the stage and takes it back off
/// after: approximate wherever a track's clips split over composition tracks.
///
/// Real-time rules as `AudioDSP.swift`'s head: every buffer is allocated in
/// `init`, nothing locks, `reset()` restores the fresh state.

// MARK: - The settings

/// One track's dynamics in the stages' units; nil when it has neither.
struct AudioTrackDynamicsSettings: Equatable {
    let compressor: AudioCompressorSettings?
    let limiter: AudioLimiterSettings?

    init?(compressor: CompressorProps?, limiter: LimiterProps?) {
        guard compressor != nil || limiter != nil else { return nil }
        self.compressor = compressor.map {
            AudioCompressorSettings(
                thresholdDB: $0.thresholdDb, ratio: $0.ratio,
                attackSeconds: Self.seconds($0.attack), releaseSeconds: Self.seconds($0.release),
                makeupDB: $0.makeupDb)
        }
        // Absolute: the ceiling holds on what the track hands the mix, so the
        // stage is told volume 1 (a hand-written ceiling clamped as the clip's).
        self.limiter = limiter.map {
            AudioLimiterSettings(
                ceilingDb: $0.ceilingDb, volume: 1, releaseSeconds: Self.seconds($0.release))
        }
    }

    /// A track's own, from its snapshot.
    init?(_ track: TrackSnapshot) {
        self.init(compressor: track.compressor, limiter: track.limiter)
    }

    private static func seconds(_ ticks: Ticks) -> Double {
        Double(max(ticks, 0)) / Double(ReelTime.perSecond)
    }
}

// MARK: - The stage

/// The compressor then the limiter, the clip's own two stages, over one
/// track's sound. Its latency is the limiter's 158 frames when there is one,
/// else 0; a stage the settings leave out is not run at all.
final class AudioTrackDynamicsStage {
    private let compressor: AudioCompressorStage
    private let limiter: AudioLimiterStage

    init(channelCount: Int, sampleRate: Double, maxFrames: Int) {
        compressor = AudioCompressorStage(sampleRate: sampleRate, maxFrames: maxFrames)
        limiter = AudioLimiterStage(
            channelCount: channelCount, sampleRate: sampleRate, maxFrames: maxFrames)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioTrackDynamicsStage does not support NSCoder")
    }

    /// The frames the stage delays its input by under `s`.
    func latency(_ s: AudioTrackDynamicsSettings) -> Int {
        s.limiter == nil ? 0 : AudioLimiterStage.latency
    }

    func reset() {
        compressor.reset()
        limiter.reset()
    }

    /// `frames` samples of the first `count` channels, in place.
    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, settings: AudioTrackDynamicsSettings
    ) {
        if let compressor = settings.compressor {
            self.compressor.process(channels, count: count, frames: frames, settings: compressor)
        }
        if let limiter = settings.limiter {
            self.limiter.process(channels, count: count, frames: frames, settings: limiter)
        }
    }
}

// MARK: - The preview's envelope

/// A composition track's volume envelope as `audioParameters` sets it
/// (`volumeLegs(ramps:onset:)`), read per frame on the tap's absolute grid
/// (spec §11 AU-87, AU-153): frame f is the tick `f × perSecond / rate`. The
/// value at a frame is a pure function of the frame, so a sample's ×E before
/// the stage and its ÷E after it, L frames later, are the same Float.
///
/// Before the first leg the mix input is at its default 1; between legs and
/// after the last it holds the last leg's end, as AVFoundation does.
struct AudioTrackEnvelope: Equatable {
    private let legs: [CompositionBuilder.VolumeLeg]

    init(legs: [CompositionBuilder.VolumeLeg]) {
        self.legs = legs.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
    }

    /// `out[i]` = E at frame `fromFrame + i` at `rate` frames per second.
    func fill(_ out: UnsafeMutablePointer<Float>, frames: Int, fromFrame: Int64, rate: Ticks) {
        guard frames > 0 else { return }
        guard !legs.isEmpty, rate > 0 else {
            out.update(repeating: 1, count: frames)
            return
        }
        let ticksPerFrame = Double(ReelTime.perSecond) / Double(rate)
        // The last leg starting at or before the first frame's tick, walked
        // forward from there: ticks only grow along the buffer.
        var index = lastLeg(startingBy: Double(fromFrame) * ticksPerFrame)
        for i in 0..<frames {
            let tick = Double(fromFrame + Int64(i)) * ticksPerFrame
            while index + 1 < legs.count, Double(legs[index + 1].start) <= tick { index += 1 }
            out[i] = Float(value(at: tick, from: index))
        }
    }

    /// The index of the last leg whose start is at or before `tick`, or −1.
    private func lastLeg(startingBy tick: Double) -> Int {
        var low = 0
        var high = legs.count - 1
        var found = -1
        while low <= high {
            let middle = (low + high) / 2
            if Double(legs[middle].start) <= tick {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }

    /// E at `tick` given the last leg starting by it.
    private func value(at tick: Double, from index: Int) -> Double {
        guard index >= 0 else { return 1 }
        let leg = legs[index]
        let end = Double(leg.start + leg.duration)
        guard tick < end else { return leg.to }
        let u = (tick - Double(leg.start)) / Double(leg.duration)
        return leg.from + (leg.to - leg.from) * u
    }
}

/// What a metering build's tap is given for a track with dynamics: its
/// settings and its composition track's envelope.
struct AudioTrackDynamics: Equatable {
    let settings: AudioTrackDynamicsSettings
    let envelope: AudioTrackEnvelope
}
