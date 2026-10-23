import Foundation

/// The document's half of a ramped clip's rendered audio (spec §11 SR-12):
/// what it wants rendered, and what it does when a render lands.
///
/// The whole-timeline plan's ramp segments are wanted, and with a nest open
/// the edited plan's too (its instances can carry different maps), under the
/// document's `recipeKey`; `RampAudioRenders` renders them one at a time off
/// the main thread. Nothing here blocks: a pending render is silent time in
/// the preview until it lands, and the editor rebuilds then.
extension ProjectDocument {
    /// `cache/ramp-audio/` of `intendedCacheDirectory`, published beside the
    /// plan as `ReverseResolution.rampAudio`. Not created here: the first
    /// render makes it.
    var rampAudioDirectory: URL? {
        intendedCacheDirectory.map(RampAudioCache.directory(in:))
    }

    /// Replaces the document's wanted renders with its plans' ramp segments.
    /// Never during a live gesture (SR-12 (c)); a plan is decoded only when
    /// its text holds a ramp. Main thread, after the resolution is published.
    func ensureRampAudio() {
        guard !isLiveEditing else { return }
        let reverse = ReverseSource.shared.resolution(for: recipeKey)
        let urls = mediaURLs()
        var requests: [RampAudioRequest] = []
        for handle in scope == nil ? [project] : [project, editedProject] {
            guard handle.planJSON.contains("\"ramp\":"), let plan = handle.plan else { continue }
            for request in RampAudioCache.requests(plan: plan, urls: urls, reverse: reverse)
            where !requests.contains(where: { $0.destination == request.destination }) {
                requests.append(request)
            }
        }
        RampAudioRenders.shared.want(requests, owner: recipeKey) { [weak self] in
            self?.rampAudioDidLand()
        }
    }

    /// A render this document wants landed (SR-12 (f)): the package's date
    /// re-read (the render may have created `cache/`), every file no owner
    /// wants pruned, and the editor told to rebuild — the plan did not
    /// change, so only `.reversedMediaDidChange` makes it.
    func rampAudioDidLand() {
        packageContentsDidChangeOnDisk()
        if let directory = rampAudioDirectory {
            RampAudioCache.prune(
                directory, keeping: RampAudioRenders.shared.keptNames(in: directory))
        }
        NotificationCenter.default.post(name: .reversedMediaDidChange, object: self)
    }
}
