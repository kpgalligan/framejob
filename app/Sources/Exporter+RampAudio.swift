import Foundation

/// The export's wait for its ramp renders (spec §11 SR-12 (h)), before the
/// composition is built: a ramp segment's render is READY only when its file
/// exists as the build runs, and an export never writes a ramp silent.
extension Exporter {
    /// Runs `build` once every renderable ramp segment of `plan` has its
    /// file, wanting them under this export's `key` meanwhile (released by
    /// `releaseRecipeKey`, from `finish` and `deinit`). An image sequence has
    /// no sound and does not wait; a plan with no ramp segment builds at once.
    /// A ramp segment with no cache folder to render into, or a render that
    /// failed, fails the export `rampAudioFailed`; `cancelled()` answering
    /// true fails it `cancelled`.
    /// The sheet reads "Preparing…" throughout. On `buildQueue`, never main.
    static func withRampAudio<T>(
        plan: CompositionPlan, urls: [UInt32: URL], settings: ExportSettings, key: Int,
        cancelled: @escaping () -> Bool, then build: () throws -> T
    ) throws -> T {
        guard !settings.isImageSequence,
            plan.audioTracks.contains(where: { $0.segments.contains { $0.ramp != nil } })
        else { return try build() }
        let reverse = ReverseSource.shared.resolution(for: key)
        if reverse.rampAudio == nil,
            let orphan = plan.audioTracks.lazy.flatMap(\.segments).first(where: {
                $0.ramp != nil && $0.duration > 0 && urls[$0.media] != nil
                    && !reverse.pending.contains($0.clip)
            })
        {
            throw ExportError.rampAudioFailed(
                clip: orphan.clip, message: "the project has no cache folder to render it into")
        }
        let requests = RampAudioCache.requests(plan: plan, urls: urls, reverse: reverse)
        guard !requests.isEmpty else { return try build() }
        RampAudioRenders.shared.want(requests, owner: key, landed: nil)
        do {
            try RampAudioRenders.shared.wait(for: requests, owner: key, cancelled: cancelled)
        } catch RampAudioRenders.WaitError.failed(let clip, let message) {
            throw ExportError.rampAudioFailed(clip: clip, message: message)
        } catch {
            throw ExportError.cancelled
        }
        return try build()
    }
}
