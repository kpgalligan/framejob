import AVFoundation
import Accelerate
import Foundation

/// Where `AudioDSP`'s effects meet AVFoundation: the parameters, the schedule
/// that says which clip a buffer belongs to, and the `MTAudioProcessingTap`
/// that carries both into the audio path.
///
/// **One tap serves the preview AND the export, and that is measured.** The
/// recon this slice started from warned that `audioTapProcessor` is an
/// AVPlayer-time feature and that a tap would give a preview that sounds
/// processed and a file that does not — the one failure spec §7's whole design
/// exists to prevent. That was true of `AVAssetExportSession`, which the
/// export no longer uses. It is NOT true of the reader/writer pipeline that
/// replaced it: with a tap on the input parameters and the same
/// `AVMutableAudioMix` handed to `AVAssetReaderAudioMixOutput`, the process
/// callback ran 188 times over a two-second composition and a tap that
/// silenced its buffers produced a silent file. Two further measurements make
/// it usable:
///
///  - **Each track's tap sees only its own track, before the mix.** A tap that
///    silenced composition track 1 of two produced a mix byte-identical to
///    track 2 read alone. So per-clip settings survive the A/B track
///    assignment (§7.2), which is the thing a post-mix filter could not do.
///  - **A pass-through tap is bit-transparent.** Reading the same composition
///    with no mix at all and with a tap that pulls its source audio and
///    returns it unchanged gave identical bytes, and adding a volume ramp
///    alongside changed nothing either. The tap is not a lossy insert; the
///    reason a track with nothing to do gets none is CPU and clarity, not
///    fidelity.
///
/// **The clip's other audio properties are NOT here.** Volume, the fades and
/// ducking are already one envelope per track in the plan (`audio.rs`), played
/// back as volume ramps. Those apply downstream of a tap created with
/// `kMTAudioProcessingTapCreationFlag_PreEffects`, so the compressor sees the
/// clip at its recorded level rather than at the level the fader is passing —
/// an insert before the fader, which is where a compressor belongs. What IS
/// here is everything the plan cannot carry: voice isolation's crossfade, the
/// channel pick, the EQ and hum notch, noise reduction, the compressor, the
/// mono fold, pan and the limiter.
///
/// **The tap also meters, and it is the only thing that can.** A meter wants
/// the mix level, which would be a PostEffects tap — but
/// `AVMutableAudioMixInputParameters` has exactly one `audioTapProcessor` and
/// the two flags are exclusive, so a track carrying this one cannot carry a
/// second, and moving this one to PostEffects would put the compressor behind
/// the fader and change how every project with a compressor sounds. So a
/// METERING build (playback only, `CompositionBuilder.build(metering:)`) hands
/// every audio track a `LevelMeterSink` — including the tracks that ask for no
/// processing at all and would otherwise carry no tap, or the meter would
/// light only on tracks that happen to have a compressor — and the reader
/// multiplies by the plan's envelope to get the post-fader number.
/// `LevelMeter.swift` argues the whole of that; the part that belongs here is
/// that metering never reaches an EXPORT, so every export keeps exactly the
/// audio path it had.

// MARK: - The tap

/// One tap's state: what it was built with, and everything it carries between
/// buffers.
///
/// Held by the tap through `MTAudioProcessingTapGetStorage`, retained on
/// creation and released in the finalize callback — the tap is a CF object
/// owned by the `AVMutableAudioMixInputParameters` it is set on, and this
/// object's life is exactly the tap's.
final class AudioTapContext {
    private let track: AudioTrackDSP
    /// Voice isolation's crossfade (spec §11 AU-53, AU-54), run on the base
    /// pointers BEFORE the chain; nil or empty when no clip has a render.
    private let isolation: AudioIsolationTrack?
    /// Whether `prepare` accepted a 48 kHz format: a tap at any other rate
    /// passes dry, the renders being 48 kHz frames.
    private var isolates = false
    /// Where the last buffer ended, in 48 kHz composition frames, for a
    /// buffer with no usable time.
    private var positionFrame: Int64 = 0
    /// The same at the tap's own rate: the automation's absolute grid
    /// (AU-87) for a buffer with no usable time.
    private var gridPosition: Int64 = 0
    /// Where this track's levels are published, on a metering (playback)
    /// build; nil on every export and on every rendered frame. Written on the
    /// audio thread with two relaxed atomic stores and a copy into its
    /// lock-free `MixRing` — see `LevelMeter.swift` for why it is not the
    /// `NSLock` the rest of the app publishes across threads with.
    private let meter: LevelMeterSink?
    private var chain: AudioDSPChain?
    /// The track's compressor and limiter on a metering build (spec §11
    /// AU-153), made in `prepare`, and its two envelope buffers of
    /// `stageFrames`: E read `latency` frames ahead, and E at the frame.
    private var trackStage: AudioTrackDynamicsStage?
    private var ahead: [Float] = []
    private var behind: [Float] = []
    private var stageFrames = 0
    /// The channel base pointers, refilled per buffer. A stored array so no
    /// allocation happens on the audio thread.
    private var channels: [UnsafeMutablePointer<Float>?] = []
    /// The rate `prepare` reported. Frames are turned into ticks with THIS
    /// and not with the timestamp's own timescale: the two happen to agree on
    /// both paths measured here, and only one of them is the contract.
    private var sampleRate: Ticks = 48000
    /// Where the last buffer ended, in composition ticks. Used when the tap
    /// reports no usable time — which the player's first callback after a
    /// start does — and to notice a seek.
    private var position: Ticks = 0

    /// How far a buffer's start may be from where the last one ended before it
    /// is treated as a seek rather than as the next block. A tenth of a second
    /// is far longer than any buffer this path delivers (4096 frames is 85 ms
    /// at 48 kHz) and far shorter than any jump a scrub makes.
    private static let seekTolerance: Ticks = ReelTime.perSecond / 10

    init(track: AudioTrackDSP, isolation: AudioIsolationTrack?, meter: LevelMeterSink?) {
        self.track = track
        self.isolation = isolation
        self.meter = meter
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AudioTapContext does not support NSCoder")
    }

    /// `prepare`: the format is finally known, so the chain can size itself.
    /// Called again after every `unprepare`, so it replaces rather than adds.
    ///
    /// **The format is checked rather than assumed.** Both paths measured here
    /// hand a tap 32-bit float, non-interleaved, one `AudioBuffer` per channel
    /// — the format `AudioDSP` is written for. Nothing in the API promises
    /// that. If it is ever something else (interleaved, or fixed point) the
    /// chain is simply not built and the track passes through untouched:
    /// reading interleaved stereo as if it were one channel would apply the
    /// left gain to both and process half the buffer, which is a corrupted
    /// export rather than a missing feature. The METER is refused by the same
    /// guard and for the same reason — an interleaved buffer read as planar
    /// would meter half a channel — so a track in an unexpected format shows
    /// no level rather than a wrong one.
    ///
    /// `channels` being non-empty is what says the format was accepted; a
    /// metering-only track has no chain but still has that array, so
    /// everything that must not run in an unusable format is gated on it.
    func prepare(
        channelCount: Int, sampleRate: Double, maxFrames: Int,
        formatFlags: AudioFormatFlags, bitsPerChannel: UInt32
    ) {
        let float = formatFlags & kAudioFormatFlagIsFloat != 0
        let planar = formatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard float, planar, bitsPerChannel == 32, channelCount > 0 else {
            chain = nil
            trackStage = nil
            channels = []
            isolates = false
            meter?.clear()
            return
        }
        // No chain at all for a metering-only track: the compressor stage
        // alone allocates three buffers of `maxFrames`, and running it with no
        // settings would still be a multiply per sample per channel for a
        // track that asked for nothing.
        chain = track.isActive
            ? AudioDSPChain(
                channelCount: channelCount, sampleRate: sampleRate, maxFrames: maxFrames,
                usesNoiseReduction: track.usesNoiseReduction, usesLimiter: track.usesLimiter)
            : nil
        stageFrames = max(1, maxFrames)
        trackStage = track.dynamics == nil
            ? nil
            : AudioTrackDynamicsStage(
                channelCount: channelCount, sampleRate: sampleRate, maxFrames: stageFrames)
        ahead = trackStage == nil ? [] : [Float](repeating: 1, count: stageFrames)
        behind = trackStage == nil ? [] : [Float](repeating: 1, count: stageFrames)
        channels = Array(repeating: nil, count: channelCount)
        self.sampleRate = sampleRate >= 1 ? Ticks(sampleRate) : 48000
        position = 0
        positionFrame = 0
        gridPosition = 0
        isolates = !(isolation?.isEmpty ?? true)
            && sampleRate == Double(IsolationRenderer.sampleRate)
    }

    func unprepare() {
        chain = nil
        trackStage = nil
        channels = []
        isolates = false
        meter?.clear()
    }

    /// `process`: run the chain over one buffer of already-fetched audio.
    ///
    /// `time` is what `MTAudioProcessingTapGetSourceAudio` reported, which is
    /// invalid on the player's very first callback (measured) — hence the
    /// carried position.
    func process(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int, time: CMTime,
        startOfStream: Bool
    ) {
        guard frames > 0, !channels.isEmpty else { return }
        let start = time.isNumeric ? CompositionBuilder.ticks(time) : position
        let list = UnsafeMutableAudioBufferListPointer(bufferList)
        let count = min(list.count, channels.count)
        guard count > 0 else { return }
        let frame = time.isNumeric
            ? CMTimeConvertScale(
                time, timescale: CMTimeScale(IsolationRenderer.sampleRate),
                method: .roundHalfAwayFromZero
            ).value
            : positionFrame
        positionFrame = frame + Int64(frames)
        // The buffer's first frame at the tap's rate, the automation's grid.
        let gridBase = time.isNumeric
            ? CMTimeConvertScale(
                time, timescale: CMTimeScale(sampleRate), method: .roundHalfAwayFromZero
            ).value
            : gridPosition
        gridPosition = gridBase + Int64(frames)

        // Isolation first (AU-54): the crossfade of the dry input with the
        // clip's render, on the whole buffer, before every stage of the chain.
        if isolates, let isolation = isolation {
            for index in 0..<count {
                channels[index] = list[index].mData?.assumingMemoryBound(to: Float.self)
            }
            channels.withUnsafeMutableBufferPointer { pointers in
                isolation.apply(
                    UnsafeMutableBufferPointer(rebasing: pointers[0..<count]), count: count,
                    frames: frames, at: frame)
            }
        }

        // A seek, a loop or a fresh stream: the compressor's envelope and
        // the reducer's delay line belong to the position we just left, and
        // so does the track stage's state.
        let jumped = startOfStream || abs(start - position) > Self.seekTolerance
        if jumped { trackStage?.reset() }
        if let chain = chain {
            if jumped { chain.reset() }

            // A buffer that straddles a cut is processed in runs, so a clip's
            // pan begins exactly at its own first sample rather than up to a
            // buffer early. The stages keep their state across the boundary —
            // they are track inserts, not per-clip effects. On a limited track
            // the spans are looked up `lookupLead` ahead: its media was placed
            // that much early, and the limiter's delay brings it back (AU-23).
            // The head stages (pick, EQ, hum) run before the noise reducer, so
            // on a noise-reduced track they look `headLead` further ahead, and
            // a run ends at a cut of either lookup (AU-34). An automated
            // span's run takes its settings at its anchor on the absolute
            // grid and ends at a grid boundary or a point (AU-87), the
            // head's included; pan then moves per sample.
            var offset = 0
            while offset < frames {
                let at = start + track.lookupLead + ticks(frames: offset)
                let run = self.run(from: at, remaining: frames - offset)
                var length = run.length
                var params = run.dsp
                var head: AudioClipDSP?
                var panRamp: AudioPanRamp?
                let lookup = gridBase + Int64(offset) + leadFrames(track.lookupLead)
                if let index = run.span, let automation = track.spans[index].automation {
                    let control = automation.control(
                        atFrame: lookup, spanStart: track.spans[index].start, rate: sampleRate)
                    (params, panRamp) = (control.settings, control.pan)
                    length = min(length, control.frames)
                }
                if track.headLead != 0 {
                    let ahead = self.run(from: at + track.headLead, remaining: frames - offset)
                    length = min(length, ahead.length)
                    head = ahead.dsp
                    if let index = ahead.span, let automation = track.spans[index].automation {
                        let control = automation.control(
                            atFrame: lookup + leadFrames(track.headLead),
                            spanStart: track.spans[index].start, rate: sampleRate)
                        head = control.settings
                        length = min(length, control.frames)
                    }
                }
                guard length > 0 else { break }
                for index in 0..<count {
                    channels[index] = list[index].mData?
                        .assumingMemoryBound(to: Float.self).advanced(by: offset)
                }
                channels.withUnsafeMutableBufferPointer { pointers in
                    chain.process(
                        UnsafeMutableBufferPointer(rebasing: pointers[0..<count]),
                        frames: length, params: params, head: head, panRamp: panRamp,
                        leveller: params.leveller.map {
                            AudioLevellerRun(settings: $0, firstFrame: lookup, rate: sampleRate)
                        })
                }
                offset += length
            }
        }
        position = start + ticks(frames: frames)
        runTrackStage(list, count: count, frames: frames, gridBase: gridBase)

        // AFTER the chain, and over the whole buffer rather than per run: what
        // the meter is asked for is the level this track hands the mix, and
        // the pan and the compressor have moved it. The run loop above left
        // `channels` pointing into the LAST run, so the base pointers are
        // written back before the sink reads them.
        guard let meter = meter else { return }
        for index in 0..<count {
            channels[index] = list[index].mData?.assumingMemoryBound(to: Float.self)
        }
        channels.withUnsafeMutableBufferPointer { pointers in
            meter.measure(
                UnsafeMutableBufferPointer(rebasing: pointers[0..<count]), count: count,
                frames: frames)
        }
        // The live loudness meter's copy (spec §11 AU-70), placed by the
        // buffer's own time on this tap's sample grid. A buffer with no
        // usable time (the player's silent pre-roll) is not placed at all.
        guard time.isNumeric, time.timescale > 0 else { return }
        let first = Int64(
            (Double(time.value) * Double(sampleRate) / Double(time.timescale)).rounded())
        channels.withUnsafeMutableBufferPointer { pointers in
            meter.capture(
                UnsafeMutableBufferPointer(rebasing: pointers[0..<count]), count: count,
                frames: frames, start: first, sampleRate: Int(sampleRate))
        }
    }

    private func ticks(frames: Int) -> Ticks {
        Ticks(frames) * ReelTime.perSecond / sampleRate
    }

    /// The track's compressor and limiter after the chain (spec §11 AU-153),
    /// post-fader though the tap is not: frame `gridBase + i` is gained by the
    /// envelope at grid frame `gridBase + i + L` — the timeline frame the
    /// track's lead put there — the stage runs and delays it L frames, and
    /// the result is divided by the envelope at `gridBase + i`, the frame it
    /// now sits at (0 where E < 2⁻²⁰), so the fader downstream puts back
    /// exactly what was taken off. L is the stage's latency in frames at the
    /// tap's own rate, never the lead in ticks, so the ×E and the ÷E of one
    /// sample are the same number at any rate.
    private func runTrackStage(
        _ list: UnsafeMutableAudioBufferListPointer, count: Int, frames: Int, gridBase: Int64
    ) {
        guard let stage = trackStage, let dynamics = track.dynamics else { return }
        let latency = Int64(stage.latency(dynamics.settings))
        var offset = 0
        while offset < frames {
            let length = min(stageFrames, frames - offset)
            let first = gridBase + Int64(offset)
            for index in 0..<count {
                channels[index] = list[index].mData?
                    .assumingMemoryBound(to: Float.self).advanced(by: offset)
            }
            ahead.withUnsafeMutableBufferPointer { gains in
                guard let e = gains.baseAddress else { return }
                dynamics.envelope.fill(
                    e, frames: length, fromFrame: first + latency, rate: sampleRate)
                for index in 0..<count {
                    guard let data = channels[index] else { continue }
                    vDSP_vmul(data, 1, e, 1, data, 1, vDSP_Length(length))
                }
            }
            channels.withUnsafeMutableBufferPointer { pointers in
                stage.process(
                    UnsafeMutableBufferPointer(rebasing: pointers[0..<count]), count: count,
                    frames: length, settings: dynamics.settings)
            }
            behind.withUnsafeMutableBufferPointer { gains in
                guard let e = gains.baseAddress else { return }
                dynamics.envelope.fill(e, frames: length, fromFrame: first, rate: sampleRate)
                for index in 0..<count {
                    guard let data = channels[index] else { continue }
                    for i in 0..<length {
                        data[i] = e[i] >= Self.envelopeFloor ? data[i] / e[i] : 0
                    }
                }
            }
            offset += length
        }
    }

    /// Below this the envelope is silence, and ÷E would be a gain burst.
    static let envelopeFloor: Float = 1.0 / 1_048_576

    /// A lead in ticks as whole frames at the tap's rate, rounded (AU-87).
    private func leadFrames(_ ticks: Ticks) -> Int64 {
        (ticks * sampleRate + ReelTime.perSecond / 2) / ReelTime.perSecond
    }

    private func samples(_ ticks: Ticks) -> Int {
        let value = max(ticks, 0) * sampleRate / ReelTime.perSecond
        return value > Ticks(Int.max) ? Int.max : Int(value)
    }

    /// The longest run from `at` over which one clip's settings hold, those
    /// settings, and the span's index. A gap between clips is a run of inert
    /// samples rather than a stop, so the silence between two panned clips
    /// stays silence.
    private func run(from at: Ticks, remaining: Int)
        -> (length: Int, dsp: AudioClipDSP, span: Int?)
    {
        guard let index = span(covering: at) else {
            // Not inside any span: run to whichever comes first, the next
            // span's start or the end of the buffer.
            guard let next = track.spans.first(where: { $0.start > at })?.start
            else { return (remaining, .inert, nil) }
            return (min(remaining, max(1, samples(next - at))), .inert, nil)
        }
        let span = track.spans[index]
        return (min(remaining, max(1, samples(span.end - at))), span.dsp, index)
    }

    /// Binary search rather than a carried cursor: a scrub jumps anywhere, and
    /// `log n` with no state beats `n` with state that a seek invalidates.
    private func span(covering at: Ticks) -> Int? {
        var low = 0
        var high = track.spans.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let span = track.spans[middle]
            if at < span.start {
                high = middle - 1
            } else if at >= span.end {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }
}

/// Builds the `MTAudioProcessingTap` for one composition audio track.
enum AudioTap {
    /// nil when the track needs no processing AND is not being metered, or
    /// when MediaToolbox refuses to make a tap — in which case the track plays
    /// and exports unprocessed and unmetered, which is the old behaviour
    /// rather than a failed build.
    ///
    /// A `meter` alone is enough to earn a tap: a metering build wants a level
    /// from every audio track, including the ones no clip has asked anything
    /// of. That tap builds no chain and touches no sample — it fetches its
    /// source audio, hands it straight on, and measures it.
    ///
    /// An `isolation` with spans earns one too (spec §11 AU-53); an empty one
    /// — every render still pending — does not, so the clip plays dry
    /// through exactly the path it had.
    static func make(
        for track: AudioTrackDSP?, isolation: AudioIsolationTrack?, meter: LevelMeterSink?
    ) -> MTAudioProcessingTap? {
        let track = track ?? .inert
        guard track.isActive || !(isolation?.isEmpty ?? true) || meter != nil else { return nil }
        // Retained here, released in `finalize` (or below, if no tap is made):
        // the tap owns the context and outlives every Swift reference to it.
        let context = Unmanaged.passRetained(
            AudioTapContext(track: track, isolation: isolation, meter: meter)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<AudioTapContext>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                let context = Unmanaged<AudioTapContext>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.prepare(
                    channelCount: Int(format.pointee.mChannelsPerFrame),
                    sampleRate: format.pointee.mSampleRate, maxFrames: Int(maxFrames),
                    formatFlags: format.pointee.mFormatFlags,
                    bitsPerChannel: format.pointee.mBitsPerChannel)
            },
            unprepare: { tap in
                Unmanaged<AudioTapContext>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue().unprepare()
            },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                let context = Unmanaged<AudioTapContext>
                    .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                var timeRange = CMTimeRange()
                // The source audio must be fetched even when nothing will be
                // done to it: this call is what hands the buffer on.
                guard MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, flagsOut, &timeRange,
                    numberFramesOut) == noErr
                else {
                    numberFramesOut.pointee = 0
                    return
                }
                // `MTAudioProcessingTapFlags` is a plain bit field, not an
                // `OptionSet`: the header declares it `uint32_t`.
                let startOfStream =
                    flagsOut.pointee & MTAudioProcessingTapFlags(
                        kMTAudioProcessingTapFlag_StartOfStream) != 0
                context.process(
                    bufferListInOut, frames: Int(numberFramesOut.pointee),
                    time: timeRange.start, startOfStream: startOfStream)
            })

        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap) == noErr
        else {
            // The context was retained for a tap that does not exist.
            Unmanaged<AudioTapContext>.fromOpaque(context).release()
            return nil
        }
        return tap
    }
}
