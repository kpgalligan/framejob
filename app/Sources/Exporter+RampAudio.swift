import Foundation

/// The export's wait for its offline audio renders (spec §11 SR-12 (h),
/// AU-57, AU-147), before the composition is built: a ramp segment's render,
/// a clip window's isolated voice, or its voice effect, is READY only when
/// its file exists as the build runs, and an export never writes a ramp
/// silent, an isolated clip dry or a voiced clip without its effect. First,
/// a gated or de-essed clip's measured loudness (AU-42).
extension Exporter {
    /// Runs `build` once every renderable ramp segment, isolated window and
    /// voiced window of `plan` has its file, wanting them under this export's
    /// `key` meanwhile (released by `releaseRecipeKey`, from `finish` and
    /// `deinit`). An image sequence has no sound and does not wait; a plan
    /// with none builds at once. A ramp segment with no cache folder to
    /// render into, or a render that failed, fails the export
    /// `rampAudioFailed`; an isolated window the same way fails it
    /// `isolationFailed`, a voiced one `voiceFailed`; `cancelled()` answering
    /// true fails it `cancelled`. The renders are wanted in passes: a voice
    /// over an isolated clip is rendered from that clip's isolated file
    /// (AU-143), and a retimed clip's from its processed window (AU-55 as
    /// amended), so each such request exists only once that file does.
    /// The sheet reads "Preparing…" throughout. On `buildQueue`, never main.
    static func withRampAudio<T>(
        plan: CompositionPlan, urls: [UInt32: URL], settings: ExportSettings, key: Int,
        cancelled: @escaping () -> Bool, then build: () throws -> T
    ) throws -> T {
        // Every mask the range draws first (spec §11 CO-22 (e)): a GIF or APNG waits too.
        try waitForMasks(plan: plan, urls: urls, settings: settings, key: key, cancelled: cancelled)
        guard !settings.isImageSequence else { return try build() }
        return try withOfflineAudio(
            plan: plan, urls: urls, key: key, cancelled: cancelled, then: build)
    }

    /// `withRampAudio`'s waits for a composition that has sound: the levels,
    /// then the ramp, isolation and voice renders, each wanted under `key`.
    /// The export calls it through `withRampAudio`; the processed loudness
    /// measurement (`ProcessedLoudness.render`, spec §11 AU-64 (d)) calls it
    /// directly, so a clip is measured through the very files it exports
    /// with. Never main.
    static func withOfflineAudio<T>(
        plan: CompositionPlan, urls: [UInt32: URL], key: Int,
        cancelled: @escaping () -> Bool, then build: () throws -> T
    ) throws -> T {
        try waitForLevels(plan: plan, key: key, cancelled: cancelled)
        let ramped = plan.audioTracks.contains(where: { $0.segments.contains { $0.ramp != nil } })
        let dsp = AudioDSPSource.shared.parameters(for: key)
        let segments = plan.audioTracks.lazy.flatMap(\.segments)
        // Every sounding segment is isolated and voiced, ×1 in the tap and
        // retimed through its chain (AU-55, AU-145 as amended, #387).
        let isolated = segments.contains { dsp.wantsIsolation($0.clip) && $0.duration > 0 }
        let voiced = segments.contains { dsp.voice(for: $0.clip) != nil && $0.duration > 0 }
        guard ramped || isolated || voiced else { return try build() }
        let reverse = ReverseSource.shared.resolution(for: key)
        if ramped, reverse.rampAudio == nil,
            let orphan = segments.first(where: {
                $0.ramp != nil && $0.duration > 0 && urls[$0.media] != nil
                    && !reverse.pending.contains($0.clip)
            })
        {
            throw ExportError.rampAudioFailed(
                clip: orphan.clip, message: "the project has no cache folder to render it into")
        }
        if isolated, reverse.isolated == nil,
            let orphan = segments.first(where: {
                dsp.wantsIsolation($0.clip) && $0.duration > 0
                    && urls[$0.media] != nil && !reverse.pending.contains($0.clip)
            })
        {
            throw ExportError.isolationFailed(
                clip: orphan.clip, message: "the project has no cache folder to render it into")
        }
        if voiced, reverse.voiced == nil,
            let orphan = segments.first(where: {
                dsp.voice(for: $0.clip) != nil && $0.duration > 0
                    && urls[$0.media] != nil && !reverse.pending.contains($0.clip)
            })
        {
            throw ExportError.voiceFailed(
                clip: orphan.clip, message: "the project has no cache folder to render it into")
        }
        // A render made from another's file can be asked for only once that
        // file exists (a voice over an isolation, AU-143; a retimed clip's
        // mix and its render, AU-55 as amended): ask, wait, and ask again
        // until a pass names nothing new. The longest chain is three files.
        var wanted: [RampAudioRequest] = []
        for _ in 0..<offlineAudioPasses {
            let fresh = RetimedSound.exportRequests(
                plan: plan, dsp: dsp, urls: urls, reverse: reverse
            ).filter { request in !wanted.contains { $0.destination == request.destination } }
            if fresh.isEmpty { break }
            wanted += fresh
            try wait(for: wanted, wanting: wanted, key: key, cancelled: cancelled)
        }
        return try build()
    }

    /// The most passes `withOfflineAudio` asks in: one per file of the
    /// longest chain, and the one that names nothing new.
    static let offlineAudioPasses = 4

    /// Wants `wanting` under `key` (a want replaces the owner's set) and
    /// waits for `requests`, a failure thrown as its job's error.
    private static func wait(
        for requests: [RampAudioRequest], wanting: [RampAudioRequest], key: Int,
        cancelled: @escaping () -> Bool
    ) throws {
        RampAudioRenders.shared.want(wanting, owner: key, settled: nil)
        do {
            try RampAudioRenders.shared.wait(for: requests, owner: key, cancelled: cancelled)
        } catch RampAudioRenders.WaitError.failed(let request, let message) {
            switch request.job {
            case .ramp:
                throw ExportError.rampAudioFailed(clip: request.clip, message: message)
            case .isolation, .mix:
                throw ExportError.isolationFailed(clip: request.clip, message: message)
            case .voice:
                throw ExportError.voiceFailed(clip: request.clip, message: message)
            }
        } catch {
            throw ExportError.cancelled
        }
    }

    /// Waits for the level of every gated or de-essed clip that plays and is
    /// still pending (AU-42), up to `AudioDynamicsLevels.exportTimeout`; then
    /// fails `loudnessUnmeasured` naming the first, or `cancelled`. A clip
    /// that will never be measured (under 0.4 s, silent) is not pending and
    /// exports ungated, as the preview plays it.
    static func waitForLevels(
        plan: CompositionPlan, key: Int, cancelled: @escaping () -> Bool
    ) throws {
        let pending = AudioDSPSource.shared.parameters(for: key).pendingLevels
        guard !pending.isEmpty, let project = RecipeSource.shared.project(for: key) else { return }
        let playing = Set(
            plan.audioTracks.lazy.flatMap(\.segments)
                .filter { $0.duration > 0 && pending.contains($0.clip) }.map(\.clip))
        guard !playing.isEmpty else { return }
        switch AudioDynamicsLevels.shared.wait(
            for: playing, in: project, cache: ReverseSource.shared.resolution(for: key).cache,
            timeout: AudioDynamicsLevels.exportTimeout, cancelled: cancelled)
        {
        case .landed: return
        case .cancelled: throw ExportError.cancelled
        case .timedOut(let clip): throw ExportError.loudnessUnmeasured(clip: clip)
        }
    }
}
