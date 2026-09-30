import AppKit

/// Going INSIDE a nest and coming back out — Clip ▸ Open Nest (⌘↓), Clip ▸
/// Close Nest (⌘↑), a double-click on a nest clip, and the breadcrumb the
/// timeline draws in the corner over its track headers (road map 2's phase 9,
/// spec §4.4).
///
/// **What made this buildable is a core change, not a view one.** Until
/// `core/src/scope.rs` landed, every clip argument in the op table resolved
/// through `Project::clip`, which searches the timeline's clips alone — so an
/// inside view could only ever have been read-only, and read-only would have
/// been worse than absent: `TimelineView` builds its ops out of the snapshot
/// it is handed, so every drag, trim, split and delete would have emitted an
/// op naming an id the core refuses. `EditorViewController+Nest.swift`'s doc
/// used to argue exactly that at length; it says what changed now.
///
/// What is left on this side is three things and nothing else:
///
///  - **A path, not a nest id.** The core's `scope` is one nest id, which is
///    all an EDIT needs. A gesture needs more: a nest can be shown by two
///    clips at two different starts, so the id does not say where the nest's
///    zero sits, and leaving has to know which container to return to and
///    which clip to re-select there. `ProjectDocument.nestPath` is the path,
///    and `NestScope` below is the arithmetic over it.
///  - **The playhead maps in and out.** Nest-local time is
///    `t − nest_clip.start` and that is the WHOLE mapping — a nest has no
///    speed and no in point (`core/src/nest.rs`) — so entering subtracts the
///    step's clip start and leaving adds it back, and the frame under the
///    playhead does not move.
///  - **Neither is an undo step.** Entering and leaving change view state
///    (spec §5.2's last bullet), so they register nothing, dirty nothing and
///    are not on ⌘Z. Leaving re-selects the nest clip, which is the clip the
///    person was working on before they went in.
///
/// One thing a nest clip GIVES UP for this, said out loud because it is a
/// removal: **a double-click on it no longer renames it.** Phase 2 put the
/// inline rename on `clicks == 2` (`TimelineView+Rename.swift`), and opening
/// a nest is the stronger meaning of that gesture in every editor that has
/// both. Rename is still ⇧⌘R, Clip ▸ Rename… and the Clip tab's header
/// field; only the shortcut moved, and only on nest clips.
///
/// The canvas shows the nest at its own frozen size with the OUTER transform
/// NOT applied. That is not a decision this file makes — it falls out of
/// `ProjectDocument.editedProject`, whose canvas IS the nest's `width`/
/// `height` — and it is the right one: a compound clip is edited on its own
/// terms, and a nest scaled to a corner of the timeline would otherwise be
/// edited in a postage stamp.
extension EditorViewController {

    // MARK: - Commands

    /// The two menu selectors, declared HERE rather than forwarded from the
    /// frozen base file — `pickChromaKey`'s precedent (app/CLAUDE.md): an
    /// `@objc` method on an `extension EditorViewController` needs no
    /// forward, and a second declaration over there would be a redeclaration
    /// error rather than one.
    @objc func openNest(_ sender: Any?) { openNestCommand() }
    @objc func closeNest(_ sender: Any?) { closeNestCommand() }

    /// ⌘↓ — Clip ▸ Open Nest. Enters the selected nest clip.
    func openNestCommand() {
        guard let clip = openableNestClip() else {
            NSSound.beep()
            return
        }
        enterNest(clip)
    }

    /// ⌘↑ — Clip ▸ Close Nest. Comes back out one level.
    func closeNestCommand() {
        guard let document = document, !document.nestPath.isEmpty else {
            NSSound.beep()
            return
        }
        leaveNest()
    }

    /// The one clip Open Nest would enter, or nil.
    ///
    /// Exactly one selected clip, and it must show a nest. A selection of two
    /// nest clips has no answer — "which one" is a question the command
    /// cannot invent — and the double-click path never asks this at all,
    /// because a click names its own clip.
    func openableNestClip() -> ClipSnapshot? {
        let clips = selectedClips
        guard clips.count == 1, clips[0].source.nestID != nil else { return nil }
        return clips[0]
    }

    /// The double-click path: a clip names ITSELF, so this asks nothing about
    /// the selection (`openableNestClip` refuses two selected nest clips, and
    /// a click on one is never ambiguous).
    func openNest(clipID: UInt32) {
        guard let document = document,
            let clip = document.editedProject.snapshot.clip(clipID),
            clip.source.nestID != nil
        else {
            NSSound.beep()
            return
        }
        enterNest(clip)
    }

    // MARK: - Entering and leaving

    /// Goes one level in, through `clip` — a clip of whatever container is
    /// open now.
    ///
    /// The selection is emptied rather than guessed at: nothing inside the
    /// nest was selected a moment ago, and picking its first clip would put
    /// handles on the canvas the person did not ask for.
    func enterNest(_ clip: ClipSnapshot) {
        guard let document = document, let nest = clip.source.nestID else { return }
        let step = NestScopeStep(nest: nest, clip: clip.id)
        // The frame under the playhead must not move: the clip's start is
        // where the nest's zero sits in the container we are leaving.
        let inside = max(0, document.playhead - clip.start)
        playback.pause()
        document.setNestPath(document.nestPath + [step], playhead: inside, selection: [])
        finishScopeChange()
    }

    /// Comes back out one level, re-selecting the nest clip that was entered.
    func leaveNest() {
        guard let document = document, let step = document.nestPath.last else { return }
        let path = Array(document.nestPath.dropLast())
        // The container being returned to, so the step's clip can be found in
        // it: the timeline at the top, else the nest one level up.
        let start =
            NestScope.clips(in: path, of: document.project.snapshot)
            .first { $0.id == step.clip }?.start ?? 0
        playback.pause()
        document.setNestPath(
            path, playhead: max(0, document.playhead + start), selection: [step.clip])
        finishScopeChange()
    }

    /// Leaves every level at once — what the breadcrumb's outermost component
    /// and a click on it mean.
    func leaveAllNests(to depth: Int) {
        guard let document = document, depth < document.nestPath.count else { return }
        while (document.nestPath.count) > depth, !document.nestPath.isEmpty {
            leaveNest()
        }
    }

    /// The half of a scope change the DOCUMENT cannot do.
    ///
    /// `setNestPath` republishes and posts, so the timeline, the canvas and
    /// the inspector have all refreshed by the time this runs; what is left
    /// is the PLAYER, which has to be seeked to the mapped playhead in the
    /// composition that was just rebuilt against the other project, and the
    /// timeline's own horizontal SCROLL, which would otherwise still be
    /// showing the outer document's minute forty.
    ///
    /// The scroll needs its own call, and that is worth knowing rather than
    /// discovering: `TimelineView.setPlayhead` guards on `time != playhead`,
    /// and a scope change is exactly the case where the number can be the
    /// same in the new container as it was in the old one — so the auto
    /// scroll that normally rides along with a moved playhead does not fire.
    /// `revealPlayhead` widened from private to internal for it, the widening
    /// `MediaReveal.swift` already forced on `scroll(toX:)` next door.
    ///
    /// **Not through `setPlayhead`** (#130). Its asked seek went to the item
    /// still on the player — the OUTGOING one, the other container's — where a
    /// time past that item's end clamped there and was HEARD, and the rebuild
    /// then restored to the clamped time. The playhead is snapped as
    /// `setPlayhead` snaps it and written here, and `Playback.seekAfterRebuild`
    /// holds it for the rebuild in flight, which lands there and is heard once.
    private func finishScopeChange() {
        guard let document = document else { return }
        refreshFromDocument(isLive: false)
        let snapped = ReelTime.snapToFrame(
            max(0, document.playhead), fps: document.editedProject.snapshot.canvas.fps)
        document.playhead = snapped
        playback.seekAfterRebuild(to: snapped)
        refreshTimecode()
        canvasPlayheadMoved()
        timelinePlayheadMoved()
        inspectorPlayheadMoved()
        timeline?.revealPlayhead()
    }

    // MARK: - Breadcrumb

    /// "Timeline › Intro › Lower Third" — the trail the timeline draws in the
    /// corner over its track headers (`TimelineView+NestScope.swift`).
    ///
    /// Always includes the timeline itself, so a one-level scope reads as two
    /// components and the way out is visible rather than remembered.
    func nestBreadcrumb() -> [String] {
        guard let document = document else { return [] }
        guard !document.nestPath.isEmpty else { return [] }
        return NestScope.names(of: document.nestPath, in: document.project.snapshot)
    }

    // MARK: - Validation

    /// The three Mark-menu items a nest scope turns off. `setInPoint` and
    /// `setOutPoint` are deliberately NOT here: a range is view state rather
    /// than an op, and it is CLEARED on every scope change
    /// (`ProjectDocument.setNestPath`) instead of being refused, so setting
    /// one inside a nest is a perfectly sensible thing to do — it scopes the
    /// loop and a ripple delete in the nest's own time.
    static let markerActions: Set<Selector> = [
        #selector(addMarker(_:)), #selector(nextMarker(_:)), #selector(previousMarker(_:)),
    ]

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the base file's answer alone.
    func validateNestScopeAction(_ action: Selector) -> Bool? {
        // The MARKER commands are off inside a nest, and this is more than
        // the polish the road map called it. A nest has no `markers[]`, so
        // the core refuses all three marker ops with a scope by name; and the
        // app's own answer — send them unscoped, the way it sends `add_media`
        // (`ReelOp.isDocumentLevel`) — is wrong for a different reason, since
        // the playhead inside a nest is measured from the NEST's zero and a
        // marker written at that tick would land at the wrong project time.
        // So they are refused rather than re-based: a marker is a chapter
        // point on the exported file, and the file is the timeline's.
        //
        // This arm runs BEFORE `validateTimelineAction`'s in the base file's
        // chain, which is what lets it override an answer that file gives.
        if document?.scope != nil, Self.markerActions.contains(action) { return false }
        // And BOTH scope items are dead while text is being edited, which is
        // the bare ⌫'s rule (`EditorViewController+Timeline.swift`) applied
        // to a pair that carries a modifier — because the modifier buys
        // nothing here. `NSApplication.sendEvent` offers every main-menu key
        // equivalent the key-down BEFORE the window dispatches it to the
        // first responder; what ⌘ changes is only WHICH field-editor binding
        // is displaced, and ⌘↑ / ⌘↓ are `moveToBeginningOfDocument:` and
        // `moveToEndOfDocument:`. So a live item would take them from an
        // inline rename, the Clip tab's name field and the timecode field
        // alike (AppDelegate+Menus.swift, where the items are built, used to
        // state the opposite rule and now states this one).
        //
        // Worse than a swallowed keystroke: a scope change under an open
        // field DISCARDS it. Entering leaves the renamed clip out of the
        // snapshot the timeline is handed, so `relocateRename` ends the field
        // with its commit dropped — the typing gone with no beep, no sheet
        // and no undo step to find it in. The two GESTURES need no such
        // guard: `beginGesture` opens with `endRename()`, so a double-click
        // on a nest clip and a click on the breadcrumb both commit what is
        // open before they act.
        if view.window?.firstResponder is NSText,
            action == #selector(openNest(_:)) || action == #selector(closeNest(_:))
        {
            return false
        }
        switch action {
        case #selector(openNest(_:)):
            return openableNestClip() != nil
        case #selector(closeNest(_:)):
            return !(document?.nestPath.isEmpty ?? true)
        default:
            return nil
        }
    }
}

// MARK: - The path, as arithmetic

/// One step from a container into a nest it shows.
///
/// Two fields because the core's one is not enough for a gesture: `nest` is
/// what an op's `scope` carries, and `clip` is the nest CLIP that showed it,
/// named in the container the step was taken FROM. A nest can be shown by two
/// clips at two different starts, so without the second the playhead cannot
/// be mapped and leaving cannot say what to re-select.
struct NestScopeStep: Equatable {
    let nest: UInt32
    let clip: UInt32
}

/// Reading a `nestPath` against a project — pure functions over a snapshot,
/// with no document and no view in them, so `ProjectDocument.clampViewState`
/// and the editor can ask the same questions and get the same answers.
///
/// Every walk starts at the timeline and descends one container at a time.
/// `ProjectSnapshot.nests` carries each nest's own clips (they live in the
/// parent's one id space, spec §5.2), so the whole walk is available from the
/// PARENT snapshot alone — no scoped handle is built to answer any of this,
/// which matters because `clamped` runs on every edit, undo and redo.
enum NestScope {
    /// The clips of the container `path` opens INTO — the timeline's for an
    /// empty path, else the innermost nest's.
    static func clips(in path: [NestScopeStep], of snapshot: ProjectSnapshot) -> [ClipSnapshot] {
        guard let step = path.last else { return snapshot.clips }
        return snapshot.nest(step.nest)?.clips ?? []
    }

    /// The valid prefix of `path`: every step whose nest still exists and
    /// whose nest clip is still in the container above it, still showing that
    /// nest.
    ///
    /// Truncation rather than clearing, so an undo that removes an inner nest
    /// leaves the person in the outer one they were also in, rather than
    /// throwing them out to the timeline from three levels down.
    static func clamped(_ path: [NestScopeStep], in snapshot: ProjectSnapshot)
        -> [NestScopeStep]
    {
        var kept: [NestScopeStep] = []
        for step in path {
            guard snapshot.nest(step.nest) != nil,
                let clip = clips(in: kept, of: snapshot).first(where: { $0.id == step.clip }),
                clip.source.nestID == step.nest
            else { break }
            kept.append(step)
        }
        return kept
    }

    /// Where the innermost container's zero sits in PROJECT time: the sum of
    /// every step's nest clip start, each measured in its own container.
    ///
    /// The whole mapping, because a nest clip has no in point and a nest has
    /// no speed (`core/src/nest.rs`). Stops at the first step it cannot
    /// resolve, which `clamped` has already made unreachable on the paths the
    /// app holds.
    static func offset(of path: [NestScopeStep], in snapshot: ProjectSnapshot) -> Ticks {
        var total: Ticks = 0
        var walked: [NestScopeStep] = []
        for step in path {
            guard let clip = clips(in: walked, of: snapshot).first(where: { $0.id == step.clip })
            else { break }
            total += clip.start
            walked.append(step)
        }
        return total
    }

    /// "Timeline", then one name per level.
    ///
    /// A level's name is the CLIP's (`ProjectSnapshot.name(of:)`, which falls
    /// back to the nest's own name and then to the kind), not the nest's,
    /// because a renamed nest clip is what the person sees on the bar they
    /// double-clicked. A step whose clip cannot be found still contributes a
    /// component, so the trail never comes out shorter than the path it is
    /// describing.
    static func names(of path: [NestScopeStep], in snapshot: ProjectSnapshot) -> [String] {
        var out = ["Timeline"]
        var walked: [NestScopeStep] = []
        for step in path {
            let clip = clips(in: walked, of: snapshot).first { $0.id == step.clip }
            out.append(clip.map { snapshot.name(of: $0) } ?? snapshot.nest(step.nest)?.name ?? "Nest")
            walked.append(step)
        }
        return out
    }
}
