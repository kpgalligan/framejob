import Foundation

/// The document's half of its offline audio renders (spec §11 SR-12, AU-52,
/// AU-144): a ramped clip's rendered audio, an isolated clip's voice and a
/// clip's voice effect — what it wants rendered, and what it does when a
/// render lands or fails.
///
/// The whole-timeline plan's ramp segments and isolated windows are wanted,
/// and with a nest open the edited plan's too (its instances can carry
/// different maps), under the document's `recipeKey`, in ONE `want` (a want
/// replaces the owner's set); `RampAudioRenders` renders them one at a time
/// off the main thread. Nothing here blocks: a pending ramp is silent time in
/// the preview and a pending isolation plays dry until it lands, and the
/// editor rebuilds then.
extension ProjectDocument {
    /// `cache/ramp-audio/` of `intendedCacheDirectory`, published beside the
    /// plan as `ReverseResolution.rampAudio`. Not created here: the first
    /// render makes it.
    var rampAudioDirectory: URL? {
        intendedCacheDirectory.map(RampAudioCache.directory(in:))
    }

    /// `cache/isolated/` of `intendedCacheDirectory` (AU-52), published as
    /// `ReverseResolution.isolated`; made by its first render.
    var isolatedAudioDirectory: URL? {
        intendedCacheDirectory.map(IsolationCache.directory(in:))
    }

    /// `cache/voiced/` of `intendedCacheDirectory` (AU-144), published as
    /// `ReverseResolution.voiced`; made by its first render.
    var voicedAudioDirectory: URL? {
        intendedCacheDirectory.map(VoiceCache.directory(in:))
    }

    /// Replaces the document's wanted renders with its plans' ramp segments,
    /// isolated windows and voiced windows. Never during a live gesture
    /// (SR-12 (c)); a plan is decoded only when its text holds a ramp, a
    /// clip is isolated or a clip has a voice effect.
    /// Main thread, after the resolution is published.
    func ensureRampAudio() {
        guard !isLiveEditing else { return }
        let reverse = ReverseSource.shared.resolution(for: recipeKey)
        let urls = mediaURLs()
        let dsp = AudioDSPParameters(snapshot: project.snapshot)
        var requests: [RampAudioRequest] = []
        func add(_ found: [RampAudioRequest]) {
            for request in found
            where !requests.contains(where: { $0.destination == request.destination }) {
                requests.append(request)
            }
        }
        for handle in scope == nil ? [project] : [project, editedProject] {
            let ramped = handle.planJSON.contains("\"ramp\":")
            guard ramped || dsp.isolates || dsp.voices, let plan = handle.plan else { continue }
            if ramped { add(RampAudioCache.requests(plan: plan, urls: urls, reverse: reverse)) }
            add(IsolationCache.requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse))
            // A voice over an isolated clip is requested once that render is
            // on disk (AU-143); the settle that lands it wants again.
            add(VoiceCache.requests(plan: plan, dsp: dsp, urls: urls, reverse: reverse))
        }
        RampAudioRenders.shared.want(requests, owner: recipeKey) { [weak self] in
            self?.rampAudioDidSettle()
        }
        ensureMasks()
    }

    /// A render this document wants landed or failed (SR-12 (f), AU-52,
    /// AU-144): the package's date re-read (the render may have created
    /// `cache/`), every file no owner wants pruned from the three folders,
    /// the renders wanted again (a voice waiting for its isolation is
    /// wanted once that lands), and the editor and the Sound tab's status
    /// told — the plan did not change, so only `.reversedMediaDidChange`
    /// makes the editor rebuild.
    func rampAudioDidSettle() {
        packageContentsDidChangeOnDisk()
        for directory in [rampAudioDirectory, isolatedAudioDirectory, voicedAudioDirectory]
            .compactMap({ $0 })
        {
            RampAudioCache.prune(
                directory, keeping: RampAudioRenders.shared.keptNames(in: directory))
        }
        ensureRampAudio()
        NotificationCenter.default.post(name: .reversedMediaDidChange, object: self)
    }
}
