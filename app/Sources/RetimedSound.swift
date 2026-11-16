import AVFoundation

/// Voice isolation and a voice effect on a RETIMED audio segment (spec §11
/// AU-55 and AU-145 as amended, #387): a constant speed, or a speed ramp.
///
/// At ×1 both are a crossfade in the tap against a render of the media
/// window (AU-53), which lines up with the dry sound only because the
/// composition plays the media at ×1. A retimed segment's processed sound is
/// written to a file instead, and that file is what the retimer reads:
///
/// 1. the isolation of the segment's window `W` (`IsolationCache`'s job and
///    name, unchanged);
/// 2. the PROCESSED window `P`: with a voice effect, `VoiceCache`'s job over
///    `W`; else `IsolationMix`'s crossfade of `W` with its isolation;
/// 3. for a RENDERED segment (a ramp, or a constant speed with Keep pitch
///    off, SR-28), the ramp render of `P` through the segment's own map,
///    counted from `W`'s first frame. A LIVE segment (a constant speed with
///    Keep pitch on) has no third stage: the composition inserts `P` where it
///    inserted the media and scales it as before.
///
/// Each stage is a request on `RampAudioRenders`, formable only once the
/// file before it is on disk (AU-143's pattern), so every settle wants
/// again. The tap does nothing for such a segment.
enum RetimedSound {
    enum Kind: Equatable {
        /// ×1: isolated and voiced in the tap (AU-53, AU-143).
        case tapped
        /// The composition plays a render of it from `cache/ramp-audio/`.
        case rendered
        /// The composition scales its source itself.
        case live
    }

    /// The frames `W` is widened by on each side before it is rounded out to
    /// `gridFrames`: what a retimer reads outside what the clip plays — Keep
    /// pitch on's 4,800-frame preroll (`timePitchPreroll`), the resampler's
    /// reach at ×12, SY-24's 46 samples.
    static let padFrames: Int64 = 8192
    /// `W`'s ends are rounded outward to whole seconds, so an edit that moves
    /// the source range by less keeps the isolated render (its name carries
    /// the window, AU-52), and its first frame is a whole number of ticks.
    static let gridFrames: Int64 = 48_000

    /// Nil for a segment that plays nothing.
    static func kind(of s: PlanSegment) -> Kind? {
        guard s.duration > 0 else { return nil }
        if s.ramp != nil { return .rendered }
        return s.isTimeScaled ? .live : .tapped
    }

    /// The 48 kHz frames of its source a retimed segment plays, `[S(0),
    /// S(D))`: the ramp map's first and last source tick, or the segment's
    /// own source range. Nil for a tapped segment or an unreadable map.
    static func sounding(of s: PlanSegment) -> IsolationWindow? {
        guard let kind = kind(of: s), kind != .tapped else { return nil }
        let first: Ticks
        let end: Ticks
        if let ramp = s.ramp {
            guard let a = ramp.map.first, let b = ramp.map.last, a.count > 1, b.count > 1
            else { return nil }
            first = a[1]
            end = b[1]
        } else {
            first = s.sourceIn
            end = s.sourceIn + s.sourceDuration
        }
        guard first >= 0, end > first else { return nil }
        return IsolationWindow(firstFrame: floor(2 * first, 25), endFrame: -floor(-2 * end, 25))
    }

    /// `W`: what the segment plays, widened by the pad — and, for a Keep
    /// pitch on render, by what Apple's unit reads past the clip's end at the
    /// rate it ends at — then rounded outward to the grid, its first frame
    /// never before 0.
    static func window(of s: PlanSegment) -> IsolationWindow? {
        guard let sounding = sounding(of: s) else { return nil }
        let first = max(0, floor(sounding.firstFrame - padFrames, gridFrames) * gridFrames)
        let end = -floor(-(sounding.endFrame + padFrames + tailFrames(of: s)), gridFrames)
            * gridFrames
        return IsolationWindow(firstFrame: first, endFrame: end)
    }

    /// Source frames a Keep pitch on render reads past `S(D)`: the unit is
    /// commanded `rateLeadFrames` output frames ahead and runs its latency
    /// on, at the map's last slope (`renderTimePitch`). 0 otherwise.
    static func tailFrames(of s: PlanSegment) -> Int64 {
        guard let ramp = s.ramp, ramp.keepPitch, ramp.map.count >= 2 else { return 0 }
        let a = ramp.map[ramp.map.count - 2]
        let b = ramp.map[ramp.map.count - 1]
        guard a.count > 1, b.count > 1, b[0] > a[0] else { return 0 }
        let rate = Double(b[1] - a[1]) / Double(b[0] - a[0])
        let ahead = Double(RampAudioRenderer.rateLeadFrames + tailSlackFrames)
        return Int64((ahead * max(rate, 1)).rounded(.up))
    }

    /// Output frames past the lead a Keep pitch on render's feed runs on:
    /// the unit's latency and what it holds. Measured 642 at an end rate of
    /// ×2 and 288 at ×12 (`audio_ap5_probe` P13's figure), rounded up.
    static let tailSlackFrames = 1024

    private static func floor(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    /// One retimed segment's renders, in order. Every stage is named whether
    /// or not the file before it exists (a name needs no file), so a build
    /// can ask for the last file alone; `formable` is what can be wanted now.
    struct Chain: Equatable {
        let kind: Kind
        let window: IsolationWindow
        /// Stage 1, nil for a voiced clip that does not isolate.
        let isolation: RampAudioRequest?
        /// Stage 2: `P`, a `.voice` or a `.mix` job.
        let processed: RampAudioRequest
        /// Stage 3, a rendered segment's only.
        let render: RampAudioRequest?

        var stages: [RampAudioRequest] { [isolation, processed, render].compactMap { $0 } }
        /// The file the composition plays.
        var last: RampAudioRequest { render ?? processed }

        /// The stages that can be rendered now: each one whose input is on
        /// disk, the ones already rendered included (a want keeps them).
        var formable: [RampAudioRequest] {
            var out: [RampAudioRequest] = []
            for stage in stages {
                out.append(stage)
                guard FileManager.default.fileExists(atPath: stage.destination.path) else {
                    break
                }
            }
            return out
        }

        /// The chain's state for a Status read-out (AU-56, AU-146): ready
        /// when its last file exists, a failed stage's reason first, else
        /// rendering. The Voice Effect section says a failed isolation as
        /// `VoiceCache.status` does at ×1.
        func status(voice: Bool) -> IsolationStatus {
            if FileManager.default.fileExists(atPath: last.destination.path) { return .ready }
            for stage in stages {
                guard let message = RampAudioRenders.shared.failure(for: stage.destination)
                else { continue }
                if voice, stage == isolation {
                    return .failed("its isolated voice was not rendered")
                }
                return .failed(message)
            }
            return .rendering
        }
    }

    /// The segment's chain, or nil: it is retimed, its clip isolates or has
    /// a voice effect, the folders it renders into exist, its media resolves
    /// and its reverse (when reversed) is not pending. The source is the
    /// reversed file for a reversed clip, else the media file, as at ×1.
    static func chain(
        for s: PlanSegment, dsp: AudioDSPParameters, urls: [UInt32: URL],
        reverse: ReverseResolution
    ) -> Chain? {
        let voice = dsp.voice(for: s.clip)
        let wants = dsp.wantsIsolation(s.clip)
        guard voice != nil || wants, let kind = kind(of: s), kind != .tapped,
            let sounding = sounding(of: s), let window = window(of: s),
            let mediaFile = urls[s.media], !reverse.pending.contains(s.clip)
        else { return nil }
        let reversedFile = reverse.ready[s.clip]
        let reversed = reversedFile != nil
        let source = reversedFile ?? mediaFile
        func request(_ directory: URL, _ name: String, _ job: OfflineAudioJob) -> RampAudioRequest {
            RampAudioRequest(
                clip: s.clip, media: s.media, destination: directory.appendingPathComponent(name),
                source: source, reversed: reversed, job: job)
        }

        // A voiced clip takes its isolation from the base amount alone, as
        // at ×1 (AU-143).
        let amount = dsp.isolation(for: s.clip)
        var isolation: RampAudioRequest?
        if voice == nil || amount > 0 {
            guard wants, let directory = reverse.isolated,
                let name = IsolationCache.name(
                    media: s.media, mediaFile: mediaFile, reversed: reversed, window: window)
            else { return nil }
            isolation = request(directory, name, .isolation(window))
        }

        let processed: RampAudioRequest
        if let voice {
            let job = VoiceJob(
                window: window, settings: voice, isolated: isolation?.destination,
                isolation: isolation == nil ? 0 : amount, sounding: sounding)
            guard let directory = reverse.voiced,
                let name = VoiceCache.name(
                    media: s.media, mediaFile: mediaFile, reversed: reversed, job: job)
            else { return nil }
            processed = request(directory, name, .voice(job))
        } else {
            guard let isolation, let directory = reverse.isolated else { return nil }
            let points = IsolationMix.points(of: s, base: amount, dsp: dsp)
            let job = MixJob(
                window: window, isolated: isolation.destination,
                amount: min(max(amount, 0), 1),
                map: points.isEmpty ? [] : map(of: s), points: points)
            processed = request(directory, IsolationMix.name(media: s.media, job: job), .mix(job))
        }

        var render: RampAudioRequest?
        if let ramp = s.ramp {
            guard let directory = reverse.rampAudio,
                let name = RampAudioCache.name(
                    media: s.media, mediaFile: mediaFile, reversed: reversed, ramp: ramp,
                    processed: (processed.destination.lastPathComponent, window.firstFrame))
            else { return nil }
            render = RampAudioRequest(
                clip: s.clip, media: s.media, destination: directory.appendingPathComponent(name),
                source: processed.destination, reversed: reversed, job: .ramp(ramp),
                sourceFirstFrame: window.firstFrame)
        }
        return Chain(
            kind: kind, window: window, isolation: isolation, processed: processed,
            render: render)
    }

    /// Clip time → source time for a retimed segment, `[clip tick, source
    /// tick]`: the ramp's map, or a constant segment's two points.
    static func map(of s: PlanSegment) -> [[Ticks]] {
        s.ramp?.map ?? [[0, s.sourceIn], [s.duration, s.sourceIn + s.sourceDuration]]
    }

    /// Every retimed chain of `plan`, each stage that can be rendered now,
    /// one request per file.
    static func requests(
        plan: CompositionPlan, dsp: AudioDSPParameters, urls: [UInt32: URL],
        reverse: ReverseResolution
    ) -> [RampAudioRequest] {
        guard dsp.isolates || dsp.voices else { return [] }
        var out: [RampAudioRequest] = []
        var seen: Set<URL> = []
        for s in plan.audioTracks.lazy.flatMap(\.segments) {
            guard let chain = chain(for: s, dsp: dsp, urls: urls, reverse: reverse) else {
                continue
            }
            for stage in chain.formable where seen.insert(stage.destination).inserted {
                out.append(stage)
            }
        }
        return out
    }

    /// What an export can want NOW (AU-57, AU-147 as amended): every tapped
    /// isolation and voice, every retimed chain's formable stages, and the
    /// dry render of each ramp segment that has no chain. The export asks
    /// again after each wait, until a pass names nothing new.
    static func exportRequests(
        plan: CompositionPlan, dsp: AudioDSPParameters, urls: [UInt32: URL],
        reverse: ReverseResolution
    ) -> [RampAudioRequest] {
        var out: [RampAudioRequest] = []
        var seen: Set<URL> = []
        func add(_ found: [RampAudioRequest]) {
            for request in found where seen.insert(request.destination).inserted {
                out.append(request)
            }
        }
        for s in plan.audioTracks.lazy.flatMap(\.segments) where s.ramp != nil {
            guard chain(for: s, dsp: dsp, urls: urls, reverse: reverse) == nil,
                let dry = RampAudioCache.request(for: s, urls: urls, reverse: reverse)
            else { continue }
            add([dry])
        }
        add(IsolationCache.requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse))
        add(VoiceCache.requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse))
        add(requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse))
        return out
    }
}

extension CompositionBuilder {
    /// A LIVE retimed segment's processed window as the builder reads it:
    /// the file's audio track and the media frame its frame 0 is.
    struct ProcessedSource {
        let track: AVAssetTrack
        let firstFrame: Int64

        /// `firstFrame` in ticks: a whole number, the window starting on a
        /// second (`RetimedSound.gridFrames`).
        var firstTick: Ticks { firstFrame * ReelTime.perSecond / 48_000 }
    }

    /// Each live retimed segment whose processed window is on disk as the
    /// composition is built (AU-55 as amended): `resolveSource` answers its
    /// track in place of the media's, and `fill` reads it from the window's
    /// first frame. A pending one is absent and its clip plays dry. `assets`
    /// holds the opened files for the build, as the ramp renders' do.
    static func processedAudioTracks(
        plan: CompositionPlan, urls: [UInt32: URL], reverse: ReverseResolution,
        dsp: AudioDSPParameters, assets: inout [URL: AVURLAsset]
    ) -> [IsolationSegmentKey: ProcessedSource] {
        guard dsp.isolates || dsp.voices else { return [:] }
        var out: [IsolationSegmentKey: ProcessedSource] = [:]
        for s in plan.audioTracks.lazy.flatMap(\.segments) {
            let key = IsolationSegmentKey(s)
            guard out[key] == nil, RetimedSound.kind(of: s) == .live,
                let chain = RetimedSound.chain(for: s, dsp: dsp, urls: urls, reverse: reverse),
                FileManager.default.fileExists(atPath: chain.processed.destination.path),
                let track = retimedTrack(at: chain.processed.destination, assets: &assets)
            else { continue }
            out[key] = ProcessedSource(track: track, firstFrame: chain.window.firstFrame)
        }
        return out
    }
}
