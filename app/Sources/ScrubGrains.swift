import AVFoundation

/// Audio while scrubbing, the pure half (road map "audio" AP13, spec §11
/// AU-130…AU-136): what a grain is, the window it is played through, how
/// one is read out of a built composition, and when one is asked for.
/// `ScrubAudio.swift` is the half that owns a queue and an engine.
///
/// **A grain is 80 ms of the mix forward from the playhead** (AU-131), the
/// same frames an export starting there would read, with 5 ms sin² edges so
/// that butting one grain against the next, or against silence, does not
/// click. Dragging left plays each grain FORWARD as well (AU-133): a
/// reversed 80 ms of speech carries no word, and finding a word is the point.
struct ScrubGrain: Equatable {
    /// Timeline ticks of frame 0: the frame-snapped playhead.
    let start: Ticks
    /// 48 kHz frames: `ScrubGrains.frames`, shorter only at the timeline's end.
    let frames: Int
    /// The estimated start of its sound, in `ProcessInfo.systemUptime` seconds.
    let at: TimeInterval
}

enum ScrubGrains {
    static let sampleRate = 48_000
    /// 80 ms.
    static let frames = 3_840
    /// 5 ms of sin² at each edge.
    static let fadeFrames = 240
    /// How much sound may still be queued when the next grain is asked for
    /// (AU-132). One grain ahead and no more, so the sound follows the hand.
    static let lead: TimeInterval = 0.04
    /// The shortest grain worth playing: two edges and nothing between.
    static let shortest = 2 * fadeFrames

    /// Frame `index`'s gain in a grain of `count`: `sin²(π/2·(i+0.5)/240)`
    /// over the first 240 frames, 1 between, the mirror over the last 240.
    /// The half-frame offset keeps the window symmetric and its first and
    /// last frames off exact zero by a hair (≈ 1e-5), never on it.
    static func gain(at index: Int, of count: Int) -> Float {
        guard index >= 0, index < count else { return 0 }
        let fade = min(fadeFrames, count / 2)
        let fromEdge = min(index, count - 1 - index)
        guard fromEdge < fade else { return 1 }
        let s = sin(Double.pi / 2 * (Double(fromEdge) + 0.5) / Double(fade))
        return Float(s * s)
    }

    /// Multiplies both channels by the window, in place.
    static func window(_ left: inout [Float], _ right: inout [Float]) {
        let count = min(left.count, right.count)
        for index in 0..<count {
            let g = gain(at: index, of: count)
            left[index] *= g
            right[index] *= g
        }
    }

    /// `frames` frames of `built`'s mix from `start`, as the export's float
    /// read gives them (`ExportAudioMaster.floatMixSettings`, the build's own
    /// `audioMix`), split into two channels; nil when the composition has
    /// no audio track or the reader refuses. Unwindowed.
    ///
    /// **Frames are placed by presentation time**, never by arrival order:
    /// a frame stamped before `start` is skipped, one past the end dropped,
    /// and whatever the read did not reach stays zero (AU-131).
    ///
    /// The bytes are COPIED out with `CMBlockBufferCopyDataBytes`: a block
    /// buffer may be several non-contiguous chunks, and
    /// `CMBlockBufferGetDataPointer` on the first one silently truncates it
    /// (the trap `ExporterLoudness.feed` and `ReverseRenderer` avoid).
    ///
    /// Opens a reader, so never the main thread: `ScrubAudio`'s queue.
    static func read(
        _ built: BuiltComposition, start: Ticks, frames: Int
    ) -> (left: [Float], right: [Float])? {
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard frames > 0, !tracks.isEmpty,
            let reader = try? AVAssetReader(asset: built.composition)
        else { return nil }
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks, audioSettings: ExportAudioMaster.floatMixSettings)
        output.audioMix = built.audioMix
        // Nothing here writes a sample back (`ExporterLoudness.mixOutput`).
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        let startTime = CompositionBuilder.time(start)
        reader.timeRange = CMTimeRange(
            start: startTime,
            duration: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(sampleRate)))
        guard reader.startReading() else { return nil }

        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var interleaved: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMBlockBufferGetDataLength(block) / (2 * MemoryLayout<Float>.size)
            guard count > 0 else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let offset = Int(
                CMTimeConvertScale(
                    CMTimeSubtract(pts, startTime), timescale: CMTimeScale(sampleRate),
                    method: .roundHalfAwayFromZero
                ).value)
            if interleaved.count < 2 * count {
                interleaved = [Float](repeating: 0, count: 2 * count)
            }
            let copied = interleaved.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: 2 * count * MemoryLayout<Float>.size,
                    destination: raw.baseAddress!)
            }
            guard copied == kCMBlockBufferNoErr else { continue }
            let first = max(0, -offset)
            let last = min(count, frames - offset)
            if first < last {
                for index in first..<last {
                    left[offset + index] = interleaved[2 * index]
                    right[offset + index] = interleaved[2 * index + 1]
                }
            }
            if offset + count >= frames {
                reader.cancelReading()
                break
            }
        }
        guard reader.status != .failed else { return nil }
        return (left, right)
    }
}

/// When a grain is asked for (AU-132). Main thread, one per window; pure, so
/// `scrub_audio_probe.py` drives it with its own clock.
///
/// A grain is asked for only when (a) the snapped playhead differs from the
/// last grain's start in this scrub, and (b) no more than `lead` of sound is
/// still queued. Holding still, or moving within one frame, asks for
/// nothing, so silence follows within the lead plus one grain.
struct ScrubGrainScheduler {
    /// True from a move until `end()`.
    private(set) var isActive = false
    /// Where the sound already asked for runs out, in `systemUptime` seconds.
    private(set) var queuedUntil: TimeInterval = 0
    /// The last grain's start in this scrub; nil until one is asked for.
    private(set) var lastStart: Ticks?

    init() {}

    /// A move to `playhead` (already frame-snapped) on a timeline of
    /// `duration` at `now`: the grain to play, or nil. A move on an inactive
    /// scheduler starts a new scrub, so the press and every drag position
    /// come through here alike.
    mutating func move(to playhead: Ticks, duration: Ticks, now: TimeInterval) -> ScrubGrain? {
        isActive = true
        guard playhead != lastStart else { return nil }
        guard queuedUntil - now <= ScrubGrains.lead else { return nil }
        guard playhead >= 0, playhead < duration else { return nil }
        let frames = min(ScrubGrains.frames, ExportAudioEnd.frames(ofTicks: duration - playhead))
        guard frames >= ScrubGrains.shortest else { return nil }
        let start = playhead
        let at = max(now, queuedUntil)
        queuedUntil = at + Double(frames) / Double(ScrubGrains.sampleRate)
        lastStart = start
        return ScrubGrain(start: start, frames: frames, at: at)
    }

    /// Mouse-up: the scrub is over and asks for nothing more. `queuedUntil`
    /// is kept, so a press straight after cannot stack a grain on one still
    /// sounding.
    mutating func end() {
        isActive = false
        lastStart = nil
    }
}
