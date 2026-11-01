import AppKit

/// The document's half of the reverse (spec §11): which reversed clips want a
/// rendered file, the progress sheet that renders them, and the sheet's exit.
///
/// A pure move out of `ProjectDocument.swift` (road map "creator-jobs" CJ0c,
/// T7): the declarations came here whole, in their existing order, with their
/// bodies untouched. **The toll is visibility**: the three stored properties
/// this code reads and writes — `refusedReverseMedia`, `renderingReverseMedia`
/// and `isPresentingReverseSheet` — stay in `ProjectDocument.swift`, because an
/// extension cannot hold a stored property, and are internal rather than
/// private for that reason. `reverseState()` stays `private`: its two callers
/// came with it.
extension ProjectDocument {

    // MARK: - Reverse (spec §11)

    /// Which clips play backwards from a pre-rendered file, which are still
    /// waiting for one, and what would have to be rendered to finish the job.
    ///
    /// Nests are walked as well as the top level: `assign()` gives an inner
    /// media clip its own composition track exactly as a top-level clip gets
    /// one, so an inner reversed clip needs the same substitution — the same
    /// reason `AudioDSPParameters` walks them.
    ///
    /// A media of kind `image` is left alone: a still played backwards is the
    /// same still, so there is nothing to render and nothing to slate.
    private func reverseState() -> (resolution: ReverseResolution, jobs: [ReverseRenderer.Job]) {
        let snapshot = project.snapshot
        var reversed: [(clip: UInt32, media: MediaSnapshot)] = []
        // Built by hand rather than with `uniqueKeysWithValues`, which TRAPS
        // on a repeated key. `validate` rejects duplicate media ids, so this
        // cannot happen — and a project file is still an input, which is the
        // one kind of thing that must never take the app down.
        var media: [UInt32: MediaSnapshot] = [:]
        for entry in snapshot.media where media[entry.id] == nil { media[entry.id] = entry }
        func collect(_ clips: [ClipSnapshot]) {
            for clip in clips where clip.source.isReversed {
                guard let id = clip.source.mediaID, let entry = media[id],
                    entry.kind != .image
                else { continue }
                reversed.append((clip: clip.id, media: entry))
            }
        }
        collect(snapshot.clips)
        for nest in snapshot.nests { collect(nest.clips) }
        guard !reversed.isEmpty, let cache = cacheDirectory else { return (.none, []) }

        var ready: [UInt32: URL] = [:]
        var pending: Set<UInt32> = []
        var jobs: [UInt32: ReverseRenderer.Job] = [:]
        for entry in reversed {
            // A media file that is gone is already a missing clip; there is
            // nothing to reverse and nothing this can add to the slate it
            // already draws.
            guard let source = mediaURL(for: entry.media), entry.media.duration > 0 else {
                continue
            }
            if let url = ReverseCache.existing(
                media: entry.media.id, source: source, in: cache) {
                ready[entry.clip] = url
                continue
            }
            pending.insert(entry.clip)
            guard jobs[entry.media.id] == nil,
                let destination = ReverseCache.destination(
                    media: entry.media.id, source: source, in: cache)
            else { continue }
            jobs[entry.media.id] = ReverseRenderer.Job(
                media: entry.media.id, name: entry.media.name, source: source,
                destination: destination, duration: entry.media.duration, fps: entry.media.fps,
                hasAudio: entry.media.hasAudio)
        }
        return (
            ReverseResolution(ready: ready, pending: pending),
            jobs.values.sorted { $0.media < $1.media }
        )
    }

    /// Tells `CompositionBuilder` — through `ReverseSource`, beside the plan —
    /// which clips read from a reversed file. Main thread, after every edit
    /// and after every render, and before the first composition is built.
    func publishReverseResolution() {
        let state = reverseState()
        // A refusal lasts exactly as long as the clip that earned it. Untick
        // Reverse and the media stops being wanted, so the refusal goes with
        // it — which is what makes ticking the box again a real second ask
        // rather than a silent no.
        refusedReverseMedia.formIntersection(state.jobs.map { $0.media })
        var resolution = state.resolution
        resolution.rampAudio = rampAudioDirectory
        resolution.isolated = isolatedAudioDirectory
        resolution.cache = intendedCacheDirectory
        ReverseSource.shared.publish(resolution, project: project, for: recipeKey)
    }

    /// Renders whatever reversed asset is missing, behind a progress sheet.
    ///
    /// Deliberately quiet about the cases where it should do nothing: a live
    /// gesture (the timeline is moving under the user), a sheet already up
    /// (Export, Consolidate, or this one), and a document with no window
    /// (the agent's, which gets slates and no dialog). It also never retries
    /// media the user has already stopped — see `refusedReverseMedia`.
    ///
    /// Asynchronous on purpose: it is called from inside an edit, and putting
    /// a sheet up while the model is mid-mutation is how re-entrancy bugs
    /// start.
    func ensureReversedMedia() {
        guard !isLiveEditing, !isPresentingReverseSheet else { return }
        let jobs = reverseState().jobs.filter { !refusedReverseMedia.contains($0.media) }
        guard !jobs.isEmpty else { return }
        isPresentingReverseSheet = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let host = self.windowControllers.first?.contentViewController,
                host.view.window?.attachedSheet == nil
            else {
                self.isPresentingReverseSheet = false
                return
            }
            self.renderingReverseMedia = jobs.map { $0.media }
            host.presentAsSheet(
                ReverseProgressSheetController(document: self, jobs: jobs))
        }
    }

    /// Asks for `clip`'s reverse again after a cancel or a failure — the
    /// Clip tab's Timing section's "Render Reverse" button.
    func retryReversedMedia(for clip: ClipSnapshot) {
        guard let media = clip.source.mediaID else { return }
        refusedReverseMedia.remove(media)
        ensureReversedMedia()
    }

    /// What the Clip tab's Timing section's Reverse row should say about one clip.
    func reverseStatus(of clip: ClipSnapshot) -> ReverseStatus {
        guard clip.source.isReversed, let id = clip.source.mediaID,
            let media = project.snapshot.media.first(where: { $0.id == id }),
            media.kind != .image
        else { return .off }
        guard let source = mediaURL(for: media), media.duration > 0 else { return .unavailable }
        guard let cache = cacheDirectory,
            ReverseCache.existing(media: media.id, source: source, in: cache) != nil
        else { return refusedReverseMedia.contains(media.id) ? .stopped : .pending }
        return .ready
    }

    /// The sheet's one exit. Everything here is ordered around one fact: the
    /// files on disk changed, and nothing else in the app can tell.
    func reverseRenderDidFinish(rendered: [UInt32], failures: [String], cancelled: Bool) {
        isPresentingReverseSheet = false
        // Unconditionally, and first: a run that failed or was cancelled may
        // still have created `cache/reversed/` inside the package, and that
        // alone is what makes NSDocument refuse every later save (the trap
        // `packageContentsDidChangeOnDisk` exists for).
        packageContentsDidChangeOnDisk()
        let landed = Set(rendered)
        for media in renderingReverseMedia where !landed.contains(media) {
            refusedReverseMedia.insert(media)
        }
        renderingReverseMedia = []
        publishReverseResolution()
        ensureRampAudio()
        // Not `.projectDocumentDidChange`: the project did not change, the
        // disk did, and the §7.6 rebuild rule compares plans. See the
        // notification's own comment.
        NotificationCenter.default.post(name: .reversedMediaDidChange, object: self)
    }
}
