import AVFoundation
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
/// here is everything the plan cannot carry: pan, the mono fold, the
/// compressor and noise reduction.
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

// MARK: - The schedule

/// One clip's stretch of a composition audio track, in composition ticks.
///
/// Composition time equals timeline time on these tracks — `CompositionBuilder`
/// fills them behind a cursor precisely so that stays true through speed
/// changes — so the plan's own `start` and `duration` are what a buffer's
/// timestamp is compared against.
struct AudioDSPSpan: Equatable {
    let start: Ticks
    /// Exclusive.
    let end: Ticks
    let dsp: AudioClipDSP
}

/// What one composition audio track's tap needs to know, decided once when
/// the composition is built.
struct AudioTrackDSP: Equatable {
    let spans: [AudioDSPSpan]
    /// Whether any clip on this track asks for anything at all. False means no
    /// tap is created, and the track's samples are exactly what the build
    /// before this file existed produced.
    let isActive: Bool
    /// Whether the noise reducer runs for the WHOLE track. It is all or
    /// nothing per track by design: the stage delays by 512 samples, and
    /// switching it in at a cut would jump the track 10 ms backwards
    /// mid-programme.
    let usesNoiseReduction: Bool

    init(segments: [PlanSegment], parameters: AudioDSPParameters) {
        var spans: [AudioDSPSpan] = []
        spans.reserveCapacity(segments.count)
        for segment in segments where segment.duration > 0 {
            let dsp = parameters.dsp(for: segment.clip)
            guard !dsp.isInert else { continue }
            spans.append(
                AudioDSPSpan(
                    start: segment.start, end: segment.start + segment.duration, dsp: dsp))
        }
        self.spans = spans
        isActive = !spans.isEmpty
        usesNoiseReduction = spans.contains { $0.dsp.noiseReduction > 0 }
    }

    private init() {
        spans = []
        isActive = false
        usesNoiseReduction = false
    }

    /// A track that asks for no processing at all. What a METERING-only tap is
    /// built with: it still has to fetch and hand on its source audio, and it
    /// still has to measure it, but no chain is built for it and no sample is
    /// touched.
    static let inert = AudioTrackDSP()
}

// MARK: - Parameters, and where they come from

/// Every clip's sample-level audio settings, keyed by clip id.
///
/// Only the clips that ask for something are in the dictionary: an empty one
/// means the whole project needs no tap anywhere, which is the state every
/// project made before this feature existed is in.
struct AudioDSPParameters: Equatable {
    private let clips: [UInt32: AudioClipDSP]

    static let empty = AudioDSPParameters(clips: [:])

    private init(clips: [UInt32: AudioClipDSP]) {
        self.clips = clips
    }

    /// Reads the settings off a project snapshot, nests included — a nested
    /// clip gets its own composition audio track exactly as a top-level one
    /// does, and `Project.clips` and `Nest.clips` share one id space, so one
    /// flat dictionary covers both.
    ///
    /// **A nest CLIP is not in the dictionary, and its own `mono` is carried
    /// down instead.** The plan replaced a nest with the clips inside it
    /// (`nest.rs`), so an audio segment always names the INNERMOST clip and
    /// nothing could ever look a nest clip's entry up — a `mono` written on
    /// one would be accepted by the core, kept by the checkbox, saved with
    /// the project and silently fold nothing, which is what it did until this
    /// walk existed. So every clip inside a folded nest is marked
    /// `enclosingMono` and folds at the tail of its own chain, which sums to
    /// exactly the fold of the nest's mix (`AudioClipDSP.enclosingMono`).
    /// A nest inside a folded nest is walked too: an outer fold applies to
    /// everything within, and folding twice is folding once.
    ///
    /// **The nest clip's other three do NOT travel, and two of them cannot.**
    /// The compressor and the noise reducer are not linear, so running either
    /// on each contributor is a different sound from running it on the mix —
    /// bus compression is the whole reason a bus has a compressor — and the
    /// reducer would also delay each inner track by its own 512 samples. Pan
    /// is linear and could ride down the same walk, but two pans do not
    /// compose into one number (`AudioClipDSP` carries one `pan`, and the
    /// product of two constant-power pairs is no single position), and
    /// turning it on would change how projects that already carry a nest pan
    /// sound — the decision M3 recorded for `mono` itself, which phase 5
    /// took deliberately and one at a time. So a nest clip's pan, compressor
    /// and noise reduction reach nothing, exactly as they did in M3.
    ///
    /// **One limit the id space imposes:** two nest clips may show the SAME
    /// nest, and the dictionary is keyed by clip id while the plan's segments
    /// carry no instance path, so a fold asked for by one of them folds both.
    /// Folding is the choice that makes the control do what it says on the
    /// clip that asked; the alternative — fold only when every nest clip
    /// showing the nest agrees — makes the checkbox do nothing at all.
    ///
    /// **Base properties only, never through actions.** A clip's numbers can
    /// be animated (`actions.rs` lerps any of them), and none of the four is
    /// read at the animated value: the plan carries no per-tick audio, the
    /// tap would have to evaluate the action itself, and evaluation is Rust's
    /// job. Ducking already works this way — `audio.rs`'s `duckers()` reads
    /// base props and says so — so this is the established answer rather than
    /// a new exception. An action that animates `pan` moves nothing.
    init(snapshot: ProjectSnapshot) {
        var clips: [UInt32: AudioClipDSP] = [:]
        func collect(_ list: [ClipSnapshot]) {
            for clip in list {
                // A nest clip's own entry could never be looked up: its id
                // names no audio segment. `fold` below is where its `mono`
                // goes instead.
                guard clip.source.nestID == nil, let audio = clip.audio else { continue }
                let dsp = AudioClipDSP(
                    pan: audio.pan,
                    compressor: audio.compressor.map {
                        AudioCompressorSettings(
                            thresholdDB: $0.thresholdDb, ratio: $0.ratio,
                            attackSeconds: AudioDSPParameters.seconds($0.attack),
                            releaseSeconds: AudioDSPParameters.seconds($0.release),
                            makeupDB: $0.makeupDb)
                    },
                    noiseReduction: audio.noiseReduction,
                    mono: audio.mono)
                guard !dsp.isInert else { continue }
                clips[clip.id] = dsp
            }
        }
        collect(snapshot.clips)
        for nest in snapshot.nests { collect(nest.clips) }

        // Marks everything `nestID` stands for, however deep. Bounded by the
        // core's `MAX_NEST_DEPTH` (8, `format.rs`) rather than trusted to
        // terminate: `validate` refuses a deeper — and so a circular — nest,
        // but this walk reads a decoded snapshot and a walk that can be
        // handed a cycle is a walk that must be bounded.
        func fold(contentsOf nestID: UInt32, depth: Int) {
            guard depth <= AudioDSPParameters.nestDepthCap, let nest = snapshot.nest(nestID)
            else { return }
            for clip in nest.clips {
                if let inner = clip.source.nestID {
                    fold(contentsOf: inner, depth: depth + 1)
                    continue
                }
                // Every clip inside, not only the ones carrying audio props:
                // which of them gets an audio segment is `evaluate.rs`'s rule
                // (the media has sound, and `enabled.audio` holds all the way
                // up), not one Swift may restate, and an entry the tap never
                // looks up costs a dictionary slot and nothing else.
                var dsp = clips[clip.id] ?? .inert
                dsp.enclosingMono = true
                clips[clip.id] = dsp
            }
        }
        func foldMonoNests(_ list: [ClipSnapshot]) {
            for clip in list where clip.audio?.mono == true {
                guard let nestID = clip.source.nestID else { continue }
                fold(contentsOf: nestID, depth: 1)
            }
        }
        foldMonoNests(snapshot.clips)
        for nest in snapshot.nests { foldMonoNests(nest.clips) }
        self.clips = clips
    }

    /// `format.rs`'s `MAX_NEST_DEPTH`. Duplicated rather than bridged: the
    /// FFI carries no constant for it, and a walk one level shallower than
    /// the core allows would silently stop folding, so the number is written
    /// where a reader comparing the two files can see it.
    private static let nestDepthCap = 8

    /// Ticks → seconds, the one place the compressor's two times cross that
    /// boundary.
    private static func seconds(_ ticks: Ticks) -> Double {
        Double(max(ticks, 0)) / Double(ReelTime.perSecond)
    }

    func dsp(for clip: UInt32) -> AudioClipDSP { clips[clip] ?? .inert }

    var isEmpty: Bool { clips.isEmpty }
}

/// The process-wide place `CompositionBuilder` finds a document's audio DSP
/// parameters, keyed by the same `RecipeSource` slot the compositor reads
/// recipes under.
///
/// **Why this is not simply read off the project.** The parameters are per
/// clip, and `CompositionBuilder.build` is handed the composition PLAN, not
/// the project: the plan is `plan.rs`'s structural description and carries
/// no audio properties beyond the envelope and the time-pitch algorithm. Both
/// callers do publish the project first — `Playback.update` and
/// `Exporter.export` each call `RecipeSource.shared.set` before building — but
/// `RecipeSource` exposes only `recipe(for:at:)`, and a frame recipe has no
/// audio in it. So this mirror exists beside it, published from `Playback`.
///
/// **Why a key with no entry still gets the right answer.** An export mints a
/// FRESH `RecipeSource` key (`Exporter.swift`: "NOT the document's", so a
/// frame already queued cannot be composed from a project the user changed
/// mid-write), and nothing publishes a document's parameters under that new
/// key. What every such caller DOES publish under it is the project handle
/// itself, so the lookup reads that handle back through
/// `RecipeSource.project(for:)` and derives the parameters from its snapshot —
/// the same pure `init(snapshot:)` `Playback` publishes through, applied to
/// exactly the project being built.
///
/// It was once a scan for the published document whose plan JSON matched the
/// one being built. That is a guess, and it guessed wrong the moment two
/// documents were open with byte-identical composition plans: it could not
/// tell them apart, so it returned nothing and every export ran with the DSP
/// silently switched off. Measured, not theorised — two projects each holding
/// one clip of the same file was enough. A key names one composition; ask it
/// rather than the population.
final class AudioDSPSource {
    static let shared = AudioDSPSource()

    private let lock = NSLock()
    private var entries: [Int: AudioDSPParameters] = [:]

    private init() {}

    /// Publishes a document's parameters. Main thread, after every edit.
    ///
    /// `Playback` publishes here so the player never pays for a decode on a
    /// scrub; the derivation in `parameters(for:)` is the same function, so
    /// the two can never disagree about what a project asks for.
    func publish(_ parameters: AudioDSPParameters, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = parameters
    }

    /// Drops a document's slot, the way `RecipeSource.unregister` does.
    func unpublish(_ key: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    /// The parameters for the composition being built under `key`: the
    /// published entry, or — for a key minted for one export or one rendered
    /// frame — derived from the project that key was registered with.
    ///
    /// Never guesses. A key with no entry and no published project is a
    /// composition nothing claims, and that gets `.empty`: an unprocessed
    /// export, not a wrongly processed one.
    func parameters(for key: Int) -> AudioDSPParameters {
        lock.lock()
        let published = entries[key]
        lock.unlock()
        if let published = published { return published }
        guard let project = RecipeSource.shared.project(for: key) else { return .empty }
        return AudioDSPParameters(snapshot: project.snapshot)
    }
}

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
    /// Where this track's levels are published, on a metering (playback)
    /// build; nil on every export and on every rendered frame. Written on the
    /// audio thread with two relaxed atomic stores and nothing else — see
    /// `LevelMeter.swift` for why it is not the `NSLock` the rest of the app
    /// publishes across threads with.
    private let meter: LevelMeterSink?
    private var chain: AudioDSPChain?
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

    init(track: AudioTrackDSP, meter: LevelMeterSink?) {
        self.track = track
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
            channels = []
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
                usesNoiseReduction: track.usesNoiseReduction)
            : nil
        channels = Array(repeating: nil, count: channelCount)
        self.sampleRate = sampleRate >= 1 ? Ticks(sampleRate) : 48000
        position = 0
    }

    func unprepare() {
        chain = nil
        channels = []
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

        if let chain = chain {
            // A seek, a loop or a fresh stream: the compressor's envelope and
            // the reducer's delay line belong to the position we just left.
            if startOfStream || abs(start - position) > Self.seekTolerance {
                chain.reset()
            }

            // A buffer that straddles a cut is processed in runs, so a clip's
            // pan begins exactly at its own first sample rather than up to a
            // buffer early. The stages keep their state across the boundary —
            // they are track inserts, not per-clip effects.
            var offset = 0
            while offset < frames {
                let run = self.run(from: start + ticks(frames: offset), remaining: frames - offset)
                guard run.length > 0 else { break }
                for index in 0..<count {
                    channels[index] = list[index].mData?
                        .assumingMemoryBound(to: Float.self).advanced(by: offset)
                }
                channels.withUnsafeMutableBufferPointer { pointers in
                    chain.process(
                        UnsafeMutableBufferPointer(rebasing: pointers[0..<count]),
                        frames: run.length, params: run.dsp)
                }
                offset += run.length
            }
        }
        position = start + ticks(frames: frames)

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
    }

    private func ticks(frames: Int) -> Ticks {
        Ticks(frames) * ReelTime.perSecond / sampleRate
    }

    private func samples(_ ticks: Ticks) -> Int {
        let value = max(ticks, 0) * sampleRate / ReelTime.perSecond
        return value > Ticks(Int.max) ? Int.max : Int(value)
    }

    /// The longest run from `at` over which one clip's settings hold, and
    /// those settings. A gap between clips is a run of inert samples rather
    /// than a stop, so the silence between two panned clips stays silence.
    private func run(from at: Ticks, remaining: Int) -> (length: Int, dsp: AudioClipDSP) {
        guard let index = span(covering: at) else {
            // Not inside any span: run to whichever comes first, the next
            // span's start or the end of the buffer.
            guard let next = track.spans.first(where: { $0.start > at })?.start
            else { return (remaining, .inert) }
            return (min(remaining, max(1, samples(next - at))), .inert)
        }
        let span = track.spans[index]
        return (min(remaining, max(1, samples(span.end - at))), span.dsp)
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
    static func make(for track: AudioTrackDSP?, meter: LevelMeterSink?) -> MTAudioProcessingTap? {
        let track = track ?? .inert
        guard track.isActive || meter != nil else { return nil }
        // Retained here, released in `finalize` (or below, if no tap is made):
        // the tap owns the context and outlives every Swift reference to it.
        let context = Unmanaged.passRetained(
            AudioTapContext(track: track, meter: meter)).toOpaque()
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
