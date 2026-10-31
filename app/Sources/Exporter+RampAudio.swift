import Foundation

/// The export's wait for its offline audio renders (spec §11 SR-12 (h),
/// AU-57), before the composition is built: a ramp segment's render, or a
/// clip window's isolated voice, is READY only when its file exists as the
/// build runs, and an export never writes a ramp silent or an isolated clip
/// dry. First, a gated or de-essed clip's measured loudness (AU-42).
extension Exporter {
    /// Runs `build` once every renderable ramp segment and isolated window of
    /// `plan` has its file, wanting them under this export's `key` meanwhile
    /// (released by `releaseRecipeKey`, from `finish` and `deinit`). An image
    /// sequence has no sound and does not wait; a plan with neither builds at
    /// once. A ramp segment with no cache folder to render into, or a render
    /// that failed, fails the export `rampAudioFailed`; an isolated window the
    /// same way fails it `isolationFailed`; `cancelled()` answering true fails
    /// it `cancelled`.
    /// The sheet reads "Preparing…" throughout. On `buildQueue`, never main.
    static func withRampAudio<T>(
        plan: CompositionPlan, urls: [UInt32: URL], settings: ExportSettings, key: Int,
        cancelled: @escaping () -> Bool, then build: () throws -> T
    ) throws -> T {
        guard !settings.isImageSequence else { return try build() }
        try waitForLevels(plan: plan, key: key, cancelled: cancelled)
        let ramped = plan.audioTracks.contains(where: { $0.segments.contains { $0.ramp != nil } })
        let dsp = AudioDSPSource.shared.parameters(for: key)
        let segments = plan.audioTracks.lazy.flatMap(\.segments)
        let isolated = segments.contains {
            dsp.isolation(for: $0.clip) > 0 && IsolationCache.isolatable($0)
        }
        guard ramped || isolated else { return try build() }
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
                dsp.isolation(for: $0.clip) > 0 && IsolationCache.isolatable($0)
                    && urls[$0.media] != nil && !reverse.pending.contains($0.clip)
            })
        {
            throw ExportError.isolationFailed(
                clip: orphan.clip, message: "the project has no cache folder to render it into")
        }
        let requests = RampAudioCache.requests(plan: plan, urls: urls, reverse: reverse)
            + IsolationCache.requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse)
        guard !requests.isEmpty else { return try build() }
        RampAudioRenders.shared.want(requests, owner: key, settled: nil)
        do {
            try RampAudioRenders.shared.wait(for: requests, owner: key, cancelled: cancelled)
        } catch RampAudioRenders.WaitError.failed(let request, let message) {
            switch request.job {
            case .ramp:
                throw ExportError.rampAudioFailed(clip: request.clip, message: message)
            case .isolation:
                throw ExportError.isolationFailed(clip: request.clip, message: message)
            }
        } catch {
            throw ExportError.cancelled
        }
        return try build()
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
