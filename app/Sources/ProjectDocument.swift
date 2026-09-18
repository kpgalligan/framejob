// The app module is named "Reelcut", so project.yml sets
// NSDocumentClass = "Reelcut.ProjectDocument" on every CFBundleDocumentTypes
// entry — the package type AND the movie/audio/image Alternate entries that
// make File > Open on a `.mov` build a project (spec §1).

import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted by `ProjectDocument` (object: the document) whenever `project`
    /// is replaced — an edit, a live-edit tick, undo, redo, or an open — and
    /// by the editor when the view state every view draws (selection, the
    /// in/out range) changes without an edit. Observers that only care about
    /// the model compare the handle; nothing else distinguishes the two.
    /// `userInfo["isLive"]` is true for the ticks of a gesture that has not
    /// committed yet: observers doing expensive work (a composition rebuild,
    /// a full timeline reload) skip those and refresh once on the final
    /// `false` (app/CLAUDE.md, spec §7.6).
    static let projectDocumentDidChange = Notification.Name("ReelcutProjectDocumentDidChange")

    /// Posted by `ProjectDocument` (object: the document) when the set of
    /// pre-rendered reversed assets on disk changes — a render finished,
    /// failed or was cancelled (`ReverseRenderer`).
    ///
    /// It needs a notification of its own because it is the one change the
    /// §7.6 rebuild rule cannot see: reversal is not in the composition plan
    /// (spec §11), so the plan string is identical before and after, and
    /// `Playback` would keep playing the composition it already built —
    /// slates and all. The editor answers this by dropping the item and
    /// rebuilding.
    static let reversedMediaDidChange = Notification.Name("ReelcutReversedMediaDidChange")
}

/// The document, and **the single mutation point**. Every edit in the app —
/// menu, gesture, inspector field, and later the agent — arrives here as one
/// or more `ReelOp`s and leaves as a new `ReelProject` handle.
///
/// The undo stack is a stack of handles. A `ReelProject` holds no pixels
/// (spec §5.5), so snapshotting the whole document per edit costs a pointer;
/// that is why `registerUndo` appears nowhere else in the app and why undo
/// restores the exact prior handle rather than replaying an inverse op.
///
/// The other half of the contract lives in `ReelCore.swift` (the op builders
/// and `RecipeSource`) and `Playback.swift` (what a change notification makes
/// the preview do).
final class ProjectDocument: NSDocument {
    /// The current project. Replaced, never mutated: an edit produces a new
    /// handle, which is what makes publishing one to the compositor's queue
    /// safe (`RecipeSource`).
    private(set) var project: ReelProject

    /// This document's slot in the process-wide `RecipeSource`. It travels
    /// into the video composition's instructions, so the compositor reads
    /// THIS document's recipes and no other's. Released in `close()` — the
    /// handle (and the Rust project behind it) leaks for the life of the
    /// process otherwise.
    let recipeKey = RecipeSource.shared.register()

    // MARK: - View state (deliberately not undoable, not persisted)

    /// Spec §5.2's last bullet: selection, playhead, zoom and pane sizes are
    /// NOT in the model. They live here so every view agrees on them, but
    /// they neither dirty the document nor register an undo step.
    var playhead: Ticks = 0 {
        didSet { playhead = max(0, playhead) }
    }

    /// Selected clip ids. Re-clamped to ids that still exist on every change,
    /// so a delete or an undo never leaves a phantom selection behind.
    var selection: Set<UInt32> = []

    /// The in/out range (§4.4) when one is set. Scopes the playback loop,
    /// ripple-delete-range and export.
    ///
    /// **A range belongs to the container that was open when it was set, and
    /// it never leaves that container** — road map 2's phase 9, and this is
    /// the one place the rule is written down because a pair of bare ticks
    /// carries nothing that would say otherwise. Two halves:
    ///
    ///  - It is CLEARED on every scope change, both kinds: the deliberate one
    ///    (`setNestPath`, whose doc argues it) and the one an undo can force
    ///    (`clampViewState` truncating a path whose nest has gone). So a range
    ///    is never read in a container other than the one it was set in.
    ///  - **No export takes a range while `scope != nil`.** Inside a nest the
    ///    range scopes the loop and a ripple delete in the NEST's own time,
    ///    which is why `validateNestScopeAction` leaves I and O live in there;
    ///    an export writes the whole timeline whatever the timeline is
    ///    showing, so a nest-local pair of ticks is not a thing it can spend.
    ///    Both readers of this property for an export must therefore ask
    ///    `scope` first — `ExportSheetController.init`, which simply captures
    ///    no range, so the card's Range popup is the disabled "Whole project"
    ///    it already is on a document that has none; and the `export` tool's
    ///    handler (`AgentServer+Render.swift`), which owes the same answer in
    ///    a sentence.
    ///
    /// **Refusing rather than mapping is the decision, and the mapping is the
    /// thing that looks right and is not.** `NestScope.offset(of:in:)` maps a
    /// nest-local TIME to project time exactly — a nest has no in point and no
    /// speed (`core/src/nest.rs`) — so re-basing the pair at capture reads as
    /// the obvious repair. It is unsound for a RANGE for two reasons the
    /// playhead does not have. A nest clip is trimmed: a two-second clip can
    /// show the first two seconds of a ten-second nest, so a range set at
    /// 5 s–8 s inside it maps onto project time where the nest's content is
    /// not on screen at all, and the export would write a passage the person
    /// never saw. The playhead can land out there too, but a person watching
    /// the canvas SEES that frame before they act on it, where a range is
    /// spent unseen at the commit. And a nest can be shown by TWO clips at two
    /// different starts (which is why `nestPath` is a path at all), so a
    /// mapped range would quietly mean "as shown by the clip I happened to
    /// enter through" — a fact the range does not record and the sheet cannot
    /// show.
    ///
    /// What the refusal costs is nothing: ⌘↑ leaves the nest, which clears the
    /// range in any case, and the range an export wants is then set on the
    /// timeline, where the ruler shows it over the clips that will actually be
    /// written.
    var inOutRange: (start: Ticks, end: Ticks)?

    /// The track a command with no track argument of its own acts on: the
    /// first selected clip's, else the front-most (`tracks` is back to
    /// front, so the last is the front).
    ///
    /// It lives here because two commands with the SAME NAME read it — Edit
    /// ▸ Insert at Playhead and the media row's own Insert at Playhead —
    /// and the row cannot reach the editor. Two spellings of the rule would
    /// let one menu item land the clip on a different track from the other.
    var targetTrack: UInt32? {
        // The edited project: with a nest open, "the track a command with no
        // track argument acts on" is one of the NEST's, and the op that names
        // it carries the scope.
        let snapshot = editedProject.snapshot
        if let clip = snapshot.clips.first(where: { selection.contains($0.id) }) {
            return clip.track
        }
        return snapshot.tracks.last?.id
    }

    /// The Media tab's selected row, if any — what Edit ▸ Insert at Playhead
    /// and Overwrite at Playhead place.
    ///
    /// It lives here rather than on `MediaPane` because the pane is rebuilt
    /// wholesale whenever the media list changes (`structureSignature`), so
    /// per-row state does not survive an import; and because the editor
    /// cannot reach the pane instance — `InspectorViewController.panes` is
    /// private. Like the other three, it is view state: not undoable, not
    /// persisted, and re-clamped to ids that still exist.
    var selectedMedia: UInt32?

    // MARK: - View state: the nest the timeline is looking inside

    /// The path from the timeline INTO the nest being edited — one step per
    /// level entered, empty at the top (road map 2's phase 9, spec §4.4).
    ///
    /// **The fifth piece of view state**, and it is a PATH rather than the
    /// nest id the core wants for two reasons. A nest can be shown by two
    /// clips at two different starts, so the id alone does not say where the
    /// nest's zero sits in the container's time — and the playhead has to map
    /// in and out so the frame under it does not jump. And entering a nest
    /// inside a nest is the ordinary case, so leaving has to know which
    /// container to come back to and which clip to re-select there.
    ///
    /// Set only through `setNestPath(_:playhead:selection:)`, which is where
    /// the three pieces that must move together do. Like the other four it is
    /// not undoable, not persisted, and re-clamped to ids that still exist —
    /// `clampViewState` truncates it at the first step whose nest or nest
    /// clip has gone, which an undo past a ⌘G can do.
    private(set) var nestPath: [NestScopeStep] = []

    /// The nest every edit resolves its ids inside — the core's `scope`
    /// (`core/src/scope.rs`) — or nil for the timeline.
    var scope: UInt32? { nestPath.last?.nest }

    /// The scoped handle, memoised against the parent it was built from.
    ///
    /// It has to be STORED. `ReelProject` memoises `json`, `snapshot` and
    /// `planJSON` PER HANDLE, so a computed `editedProject` would mint a new
    /// handle at each of the ~80 read sites and re-run `rc_project_to_json`
    /// and a whole `ProjectSnapshot` decode at every one of them.
    private var scopedCache: (parent: ReelProject, nest: UInt32, view: ReelProject)?

    /// **The project every view of the TIMELINE draws from, and the one every
    /// edit is measured against**: the scoped handle while a nest is open,
    /// `project` otherwise.
    ///
    /// The split is the whole shape of the feature, so it is worth saying
    /// which side each caller is on. `editedProject` is for anything that
    /// looks at, or acts on, *what is being edited*: the timeline, the canvas,
    /// the player, the Clip tab, the selection, the snap candidates, the
    /// probes — and **Save Frame and `render_frame`**, which are the canvas
    /// written to a file. `project` stays the DOCUMENT for everything whose
    /// subject is the file — save, export, captions, consolidate, transcribe,
    /// the Document tab and the Media tab — because an export must always
    /// write the whole timeline whatever the timeline happens to be showing.
    ///
    /// **Save Frame moved to this side, and the reason it did is the test for
    /// every future caller.** The question is not "does this write a file" —
    /// a frame grab writes one — but "which TIME BASE is this thing's
    /// argument in". `playhead` is nest-local while a scope is open, and Save
    /// Frame renders at the playhead, so on the `project` side it composed
    /// the timeline at a tick counted from inside a nest and wrote a picture
    /// nobody asked for: no error, no refusal, and a file that disagreed with
    /// both the canvas and `render_frame`
    /// (`EditorViewController+SaveFrame.swift` carries the argument). An
    /// export is on the other side for the matching reason and not by
    /// analogy: its argument is a RANGE, and the rule at `inOutRange` is that
    /// there is never a nest-local one for it to be handed.
    ///
    /// A nil from `scoped(_:)` (a nest id that has gone) falls back to the
    /// parent rather than trapping. `clampViewState` clears such a path
    /// before anything reads one, so this arm is a race with an undo and not
    /// a state the app rests in — and the clamp runs on BOTH doors that can
    /// take the nest away, the edit/undo one (`projectDidChange`) and the
    /// revert (`read(from:ofType:)`). Missing the second is what this arm
    /// looks like when it is load-bearing rather than defensive: `scope`
    /// still names a nest, this falls back to the timeline, and every edit
    /// goes out carrying a scope the core answers "no nest with id 40" —
    /// measured, which is why the clamp is on that path too.
    var editedProject: ReelProject {
        guard let nest = scope else { return project }
        if let cached = scopedCache, cached.parent === project, cached.nest == nest {
            return cached.view
        }
        guard let view = project.scoped(nest) else { return project }
        scopedCache = (project, nest, view)
        return view
    }

    /// Enters, leaves or re-roots the nest scope, with the playhead and the
    /// selection that belong with it.
    ///
    /// The three move TOGETHER by construction, which is the point of one
    /// entry: the playhead is measured from the innermost container's own
    /// zero (`t − nest_clip.start`, `core/src/nest.rs`'s whole mapping), and
    /// a selection means clip ids in whichever container is open — so setting
    /// any one of them alone leaves the other two describing a different
    /// project for one refresh.
    ///
    /// **Not an undo step and not a change to the document** (spec §5.2's
    /// last bullet: this is view state). But the handle every view draws from
    /// changes, so it republishes and posts exactly as an edit does —
    /// `projectDidChange()` is what puts the scoped project on the
    /// compositor's `RecipeSource` slot and makes the editor rebuild the
    /// player against it.
    /// The in/out range is CLEARED, and that is the fourth thing this method
    /// moves. A range is a pair of ticks with no container attached, and it
    /// means two different things on either side of the door: inside a nest
    /// it scopes the loop and a ripple delete in the nest's own time, while
    /// outside it also scopes the EXPORT, which always writes the whole
    /// timeline. Carrying one across would silently re-base it. Refusing to
    /// set one inside a nest was the alternative and is worse — a range is
    /// the natural way to work on a passage of anything.
    func setNestPath(_ path: [NestScopeStep], playhead: Ticks, selection: Set<UInt32>) {
        nestPath = path
        scopedCache = nil
        self.playhead = playhead
        self.selection = selection
        inOutRange = nil
        projectDidChange()
    }

    // MARK: - Types

    /// The package UTI, exported by project.yml.
    static let projectTypeIdentifier = "com.kgalligan.reelcut-project"
    static let projectFileExtension = "reelcut"

    private static let projectFileName = "project.json"
    private static let cacheDirectoryName = "cache"
    /// Where File ▸ Consolidate Media… puts the files it copies in (§5.6).
    /// Unlike `cache/` this one is NOT regenerable: it may be the only copy
    /// of the footage, which is why `fileWrapper(ofType:)` carries it across
    /// every save and why `readPackage` re-anchors at it.
    private static let mediaDirectoryName = "media"

    /// Everything the Info.plist claims. The package first (it is what
    /// `writableTypes` offers); the rest are the Alternate handlers — opening
    /// one builds a fresh untitled project around it (spec §1).
    private static let mediaTypeIdentifiers: [String] = [
        "com.apple.quicktime-movie",
        "public.mpeg-4",
        "com.apple.m4v-video",
        "public.movie",
        "com.apple.m4a-audio",
        "public.mp3",
        "com.microsoft.waveform-audio",
        "public.aiff-audio",
        "public.png",
        "public.jpeg",
        "public.heic",
    ]

    override class var readableTypes: [String] {
        [projectTypeIdentifier] + mediaTypeIdentifiers
    }

    override class var writableTypes: [String] { [projectTypeIdentifier] }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        // A project only ever writes itself. Export (⌘E) is a different verb
        // with its own sheet (spec §7.8) and deliberately not a save format.
        [Self.projectTypeIdentifier]
    }

    /// A package document autosaves safely: NSDocument writes the whole
    /// wrapper to a sibling location and swaps, so a crash mid-save cannot
    /// leave half a package behind.
    override class var autosavesInPlace: Bool { true }

    override func fileNameExtension(
        forType typeName: String, saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        if typeName == Self.projectTypeIdentifier { return Self.projectFileExtension }
        return super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
    }

    /// Reading happens on a background queue, which is what lets
    /// `read(from:ofType:)` wait for `MediaImporter`'s async probe without
    /// blocking the main thread (see `readMediaFile`). NSDocument's default
    /// is false — the read would then run ON the main thread and the wait
    /// would deadlock against the probe's main-thread completion.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    // MARK: - Live edits

    /// Snapshot taken by `beginLiveEdit`, consumed by `endLiveEdit`.
    private var liveEditBase: ReelProject?

    /// The media file this untitled document was built from, if any. Only
    /// used to name the draft and to point the save panel at the file's own
    /// folder ("Save then writes a `.reelcut` package next to the source").
    private(set) var importSourceURL: URL?

    /// Where regenerable caches go while the document has no file yet.
    private var temporaryCacheDirectory: URL?

    private var didReleaseRecipeKey = false

    /// Media whose reverse render was cancelled or failed. They are NOT
    /// retried on the next edit: a render the user stopped must not restart
    /// itself the moment they touch the timeline, and one that cannot work
    /// would put its sheet up for ever. Their clips keep drawing the slate,
    /// and the Video tab's Speed section offers the retry.
    private var refusedReverseMedia: Set<UInt32> = []

    /// The media the sheet now on screen is rendering, so the outcome can say
    /// which of them did not land.
    private var renderingReverseMedia: [UInt32] = []
    private var isPresentingReverseSheet = false

    // MARK: - Life cycle

    override init() {
        project = ProjectDocument.blankProject()
        super.init()
        undoManager?.levelsOfUndo = 32
    }

    /// Opening a NON-package type leaves the document UNTITLED: the movie is
    /// the *source*, not this document's file, so ⌘S must prompt for a
    /// `.reelcut` location next to it (spec §1).
    ///
    /// NSDocument assigns `fileURL` and `fileType` around
    /// `read(from:ofType:)`, and there is no hook in between —
    /// `init(contentsOf:ofType:)` is a convenience initializer and cannot be
    /// overridden — so the two properties are themselves the hook. Refusing
    /// exactly the imported URL (rather than the first assignment, or all of
    /// them) keeps Save As working untouched: the package it picks is not the
    /// source, so it goes straight through.
    ///
    /// **The assignment can come BEFORE the read as well as after it**, which
    /// is what `NSDocumentController.makeDocument(withContentsOf:ofType:)` —
    /// the agent's `open_project` — does: `importSourceURL` is still nil then,
    /// the setter lets the movie's own URL through, and the document is no
    /// longer untitled. That cost a test movie: ⌘S and `save_project` both
    /// then saved IN PLACE over the source file. `readMediaFile` therefore
    /// clears whatever is already there; this setter covers the other order.
    override var fileURL: URL? {
        get { super.fileURL }
        set {
            if let source = importSourceURL, newValue == source { return }
            super.fileURL = newValue
        }
    }

    /// A project only ever writes the package type, whatever the type of the
    /// file it was built from — see `fileURL` above for why this is a
    /// property override and not a line in the initializer.
    override var fileType: String? {
        get { super.fileType }
        set { super.fileType = importSourceURL != nil ? Self.projectTypeIdentifier : newValue }
    }

    /// A blank 1920×1080 / 30 fps project — what File > New Project starts
    /// from and what an untitled document holds until a read replaces it.
    ///
    /// `ReelProject.new` refuses only a zero dimension or a degenerate rate,
    /// and this call is neither, so the failure arm is unreachable: the core
    /// allocates with Rust's allocator, which aborts rather than returning
    /// null. It is spelled out instead of `!` because the house rules ban
    /// force unwraps, and a wrong constant here should read as the
    /// programming error it is rather than as a nil every caller threads
    /// through.
    private static func blankProject() -> ReelProject {
        guard let project = ReelProject.new(width: 1920, height: 1080, fps: .thirty) else {
            preconditionFailure("A 1920×1080 30 fps project is always constructible")
        }
        return project
    }

    override func makeWindowControllers() {
        // An imported movie became a project that exists only in memory, so
        // it opens untitled AND dirty: closing it without saving has to ask.
        // Here rather than in the read, which runs before NSDocument has
        // finished setting the document up.
        if importSourceURL != nil, fileURL == nil, !isDocumentEdited {
            fileModificationDate = nil
            countEditChange(.changeDone)
        }
        // BEFORE the window: the editor builds its first composition inside
        // `addWindowController`, and a resolution published after that would
        // let a reversed clip play forwards for one build.
        publishReverseResolution()
        addWindowController(EditorWindowController(document: self))
        // Filmstrips and waveforms for whatever the open brought in. Cheap
        // to ask for repeatedly: `MediaImporter` skips a cache whose marker
        // matches the file it was made from, and rebuilds one that has no
        // marker — a strip cut short by a save or a crash.
        generateCaches()
        // A package can arrive without its `cache/` — copied out of a zip that
        // dropped it, or opened after someone cleaned it out — so an open is
        // as much a reason to render a reverse as ticking the box is.
        ensureReversedMedia()
    }

    override func close() {
        // The compositor's only channel to this document. Dropping it here —
        // not in a deinit, which a retained window controller can delay
        // indefinitely — is what keeps a closed document's Rust project from
        // living for the life of the process.
        if !didReleaseRecipeKey {
            didReleaseRecipeKey = true
            RecipeSource.shared.unregister(recipeKey)
            ReverseSource.shared.unpublish(recipeKey)
        }
        super.close()
    }

    // MARK: - Reading

    private static func isProjectType(_ typeName: String, url: URL?) -> Bool {
        if typeName == projectTypeIdentifier { return true }
        // Belt and braces: a package dropped from a volume with no Launch
        // Services registration arrives with a generic type name.
        return url?.pathExtension.lowercased() == projectFileExtension
    }

    /// The two readers, and then the view state.
    ///
    /// **The clamp is here rather than in either reader**, and it is what
    /// keeps the nest scope honest across File ▸ Revert to Saved — the one
    /// path on which a document's project is replaced by a project it has no
    /// relation to, with the person still standing inside a nest. Each reader
    /// resets the four pieces of view state that have an obvious zero
    /// (playhead, selection, range, `selectedMedia`); the fifth, `nestPath`,
    /// has no such zero — it is a path whose steps either survive in the file
    /// that was just read or do not — and `clampViewState` is the ONE place
    /// that knows how to answer that, in the order the other clamps depend
    /// on. Writing `nestPath = []` in both readers instead would be a second
    /// opinion about the scope in the two places least likely to be updated
    /// when the rule changes.
    ///
    /// It is safe against a freshly-read document, which is worth stating
    /// because "call the clamp" is only the better answer if the clamp does
    /// nothing else surprising here. Every other arm of it is already a
    /// no-op: the selection is empty (`if !selection.isEmpty` guards),
    /// `selectedMedia` is nil, the playhead is 0. What is left is the scope
    /// arm — a truncation to the valid prefix, which on a revert to an
    /// unrelated file is the empty path and on the ordinary revert (the same
    /// file, so the same nest and clip ids) is the path the person was in,
    /// which is continuity rather than staleness. And the MEMO is repaired
    /// with no line of its own: `clampViewState` reads `editedProject`
    /// unconditionally, so a `scopedCache` still holding the discarded parent
    /// is replaced there. It could not have been SERVED in any case — the
    /// accessor's guard is `cached.parent === project`, and the tuple holds
    /// the old handle alive, so its address cannot have been reused by the
    /// new one — but stale bytes pointing at a document that is gone are not
    /// a thing to leave lying around.
    override func read(from url: URL, ofType typeName: String) throws {
        if Self.isProjectType(typeName, url: url) {
            try readPackage(at: url)
        } else {
            try readMediaFile(at: url)
        }
        clampViewState()
    }

    /// The `.reelcut` package (spec §5.6). Only `project.json` is read: the
    /// `cache/` directory is regenerable and is NEVER required to open — a
    /// missing or damaged one costs nothing but a redrawn filmstrip.
    ///
    /// Missing MEDIA is likewise not a failure: the project opens, the clips
    /// draw a slate, and `missingMedia` feeds the Relink… offer.
    private func readPackage(at url: URL) throws {
        let jsonURL = url.appendingPathComponent(Self.projectFileName)
        let wrapper = try FileWrapper(url: jsonURL, options: .immediate)
        guard let data = wrapper.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw ReelCoreError(
                message: "\(url.lastPathComponent) does not contain a readable project.json.")
        }
        project = Self.reanchoringConsolidatedMedia(try ReelProject.from(json: text), package: url)
        // Four of the five pieces of view state; the fifth is `nestPath`, and
        // it is `read(from:ofType:)`'s `clampViewState()` rather than a line
        // here — that method's doc says why the scope cannot be zeroed in
        // this file.
        playhead = 0
        selection = []
        inOutRange = nil
        selectedMedia = nil
    }

    /// Points missing media at the package's own `media/` directory when the
    /// file it names is in there under the same name.
    ///
    /// Consolidate stores an ABSOLUTE path (the model has no relative form —
    /// `Media.path` in `model.rs`), so moving or renaming a consolidated
    /// package would otherwise break every link inside it and hand the user
    /// a Relink… sheet for footage that never left the package. This is the
    /// repair, and it is deliberately narrow: only media that resolves to
    /// NOTHING is touched, so a working link is never overridden by a
    /// same-named file that happens to sit in `media/`.
    ///
    /// Not an edit. It runs on the read queue before the document exists as
    /// far as AppKit is concerned, registers no undo step and dirties
    /// nothing; the new paths are written out by whatever save comes next.
    private static func reanchoringConsolidatedMedia(
        _ project: ReelProject, package: URL
    ) -> ReelProject {
        let directory = package.appendingPathComponent(mediaDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return project }
        var ops: [ReelOp] = []
        for media in project.snapshot.media where mediaURL(for: media) == nil {
            let name = (media.path as NSString).lastPathComponent
            guard !name.isEmpty else { continue }
            let candidate = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            ops.append(.relinkMedia(media: media.id, path: candidate.path))
        }
        guard !ops.isEmpty else { return project }
        // Only `.applied` is a repair; both other arms leave it as opened.
        return (try? project.applying(ops)).project ?? project
    }

    /// Spec §1's opening flow: a movie, sound file or picture becomes a fresh
    /// project sized and rated to it, with the file as the first clip on
    /// Track 1.
    ///
    /// The probe is asynchronous (`MediaImporter` is the one file allowed
    /// `async`/`await`) and this method is not, so it blocks on
    /// `MediaImporter.probeBlocking`. That call is deliberately the one face
    /// of the probe that never touches the main actor: this method can and
    /// does run ON the main thread — `canConcurrentlyReadDocuments` only
    /// governs NSDocumentController's asynchronous open path, and an agent
    /// `open_project` arrives on main regardless — so a completion delivered
    /// through `MainActor.run` would deadlock against its own waiter.
    private func readMediaFile(at url: URL) throws {
        let descriptor = try MediaImporter.probeBlocking(url: url)
        try adoptImported(descriptor, source: url)
    }

    /// `readMediaFile`'s body once its probe has answered, and the door
    /// `untitled(around:)` (`ProjectDocument+Recording.swift`, which argues
    /// it) comes in by — ONE spelling of how a probed file becomes this
    /// document's project. `fps` non-nil replaces the canvas rate alone.
    func adoptImported(_ descriptor: MediaDescriptor, source: URL, fps: Fps? = nil) throws {
        // Set BEFORE the project is built: it is what makes the `fileURL` and
        // `fileType` overrides above refuse the assignments NSDocument makes
        // as soon as the read returns. Written on the read queue and read
        // on the main thread afterwards, which NSDocument's own hand-off
        // between the two orders for us.
        importSourceURL = source
        // …and undo the assignment NSDocument may already have made, on the
        // open path that sets the two BEFORE the read (see `fileURL` above).
        // A document left pointing at the movie is not untitled, and saving
        // it writes a package over the source file.
        fileURL = nil
        fileType = Self.projectTypeIdentifier
        project = try Self.makeProject(around: descriptor, fps: fps)
        // The same four, and the same note: `nestPath` is cleared by
        // `read(from:ofType:)`'s clamp. A file-import read is always a fresh
        // document, so the path is empty already — the line is not here
        // because the rule has one home, not because this path is special.
        playhead = 0
        selection = []
        inOutRange = nil
        selectedMedia = nil
    }

    /// Builds the project one imported file becomes. The canvas takes the
    /// source's display size and rate when it has video; an audio-only file
    /// has neither, so it lands on the 1080p/30 default. A non-nil `fps`
    /// replaces that rate and nothing else: the media record keeps the file's.
    private static func makeProject(
        around descriptor: MediaDescriptor, fps: Fps? = nil
    ) throws -> ReelProject {
        let width = descriptor.hasVideo && descriptor.width > 0 ? descriptor.width : 1920
        let height = descriptor.hasVideo && descriptor.height > 0 ? descriptor.height : 1080
        let fps =
            fps ?? (descriptor.hasVideo && descriptor.fps.double > 0 ? descriptor.fps : .thirty)
        guard let base = ReelProject.new(width: width, height: height, fps: fps) else {
            throw ReelCoreError(
                message: "\(descriptor.path) reports a size or frame rate a project cannot use.")
        }
        // Neither non-applied arm is reachable on a fresh project, and one
        // that answered with the project unchanged would be worse than this.
        guard let withMedia = try base.applying(.addMedia(descriptor: descriptor)).project else {
            throw ReelCoreError(message: "The file could not be added to a project.")
        }
        // `add_media` returns a project, not an id (there is one FFI entry
        // point for every op, §11), so the id is read back off the new
        // snapshot: the core appends, so the last entry is the new one.
        let snapshot = withMedia.snapshot
        guard let media = snapshot.media.last, let track = snapshot.tracks.first else {
            return withMedia
        }
        // A clip the core refuses (an empty media, say) is not fatal, and
        // neither is an identity or a throw: all three open the project with
        // the file in the Media tab, which is better than not opening it.
        return (try? withMedia.applying(.addClip(track: track.id, media: media.id, at: 0)))
            .project ?? withMedia
    }

    // MARK: - Writing

    /// The package: `project.json` written by the CORE (nothing re-encodes a
    /// `ProjectSnapshot` — the core owns the file format) plus the
    /// regenerable `cache/` directory, carried across so a save does not
    /// throw away every filmstrip.
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        guard let data = project.json.data(using: .utf8) else {
            throw ReelCoreError(message: "The project could not be encoded.")
        }
        let json = FileWrapper(regularFileWithContents: data)
        json.preferredFilename = Self.projectFileName
        var children = [Self.projectFileName: json]
        if let cache = cacheWrapper() { children[Self.cacheDirectoryName] = cache }
        // Consolidated media, carried across the same way — and it is not
        // optional the way the cache is: this wrapper is a whitelist, so a
        // `media/` left out here is a `media/` DELETED by the next save
        // (autosave included), taking the only copy of the footage with it.
        if let media = directoryWrapper(Self.mediaDirectoryName) {
            children[Self.mediaDirectoryName] = media
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    /// The existing cache directory as a LAZY wrapper: its bytes are read
    /// while NSDocument writes the new package to its temporary location,
    /// which is before the swap that replaces the old one — so the source
    /// files are still there. Reading eagerly instead would pull every
    /// thumbnail into memory on every autosave.
    private func cacheWrapper() -> FileWrapper? {
        guard let directory = existingCacheDirectory,
              let wrapper = try? FileWrapper(url: directory, options: [])
        else { return nil }
        wrapper.preferredFilename = Self.cacheDirectoryName
        return wrapper
    }

    /// Any other directory of the package, as a lazy wrapper — `media/`
    /// today. Same reasoning as `cacheWrapper` for the laziness, and the
    /// same nil-when-absent answer; unlike the cache this one only ever
    /// lives inside a saved package, so an untitled document has none.
    private func directoryWrapper(_ name: String) -> FileWrapper? {
        guard let fileURL = fileURL else { return nil }
        let directory = fileURL.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path),
              let wrapper = try? FileWrapper(url: directory, options: [])
        else { return nil }
        wrapper.preferredFilename = name
        return wrapper
    }

    /// Save/Save As on an untitled document opens next to the file it was
    /// built from, named after it — spec §1's "Save then writes a `.reelcut`
    /// package next to the source".
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if let source = importSourceURL {
            savePanel.directoryURL = source.deletingLastPathComponent()
            savePanel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent
        }
        return super.prepareSavePanel(savePanel)
    }

    override func defaultDraftName() -> String {
        importSourceURL?.deletingPathExtension().lastPathComponent ?? "Untitled Project"
    }

    // MARK: - Media

    /// Every media entry that resolves to a file on disk. `Playback` and
    /// `CompositionBuilder` take this; an id missing from it is missing
    /// media and renders as a slate (spec §5.6).
    func mediaURLs() -> [UInt32: URL] {
        var urls: [UInt32: URL] = [:]
        for media in project.snapshot.media {
            if let url = mediaURL(for: media) { urls[media.id] = url }
        }
        return urls
    }

    /// Media whose file is gone. The Media tab badges these and offers
    /// Relink…; the project opened anyway.
    var missingMedia: [MediaSnapshot] {
        project.snapshot.media.filter { mediaURL(for: $0) == nil }
    }

    /// Where `MediaImporter` writes thumbs and peaks: inside the package once
    /// the document has a file, a per-document temporary directory before
    /// that (`fileWrapper(ofType:)` copies it in on the first save). Caches
    /// written to the temporary directory before a Save As are orphaned
    /// there, which costs nothing — they regenerate on demand.
    var cacheDirectory: URL? {
        let directory = intendedCacheDirectory
        guard let directory = directory else { return nil }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var intendedCacheDirectory: URL? {
        if let fileURL = fileURL {
            return fileURL.appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
        }
        if let existing = temporaryCacheDirectory { return existing }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Reelcut", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryCacheDirectory = directory
        return directory
    }

    /// Where File ▸ Consolidate Media… copies files to (spec §5.6). nil for
    /// an untitled document, and that nil is the feature's whole refusal:
    /// the cache may fall back to a temporary directory because a lost
    /// filmstrip is redrawn, while media consolidated into one would be
    /// footage orphaned outside any package. `MediaConsolidator` creates the
    /// directory; nothing else needs it to exist.
    var mediaDirectory: URL? {
        fileURL?.appendingPathComponent(Self.mediaDirectoryName, isDirectory: true)
    }

    /// Re-reads the package's modification date after this app has written
    /// inside it behind `NSDocument`'s back.
    ///
    /// **Consolidate is the one thing that does that**, and without this the
    /// next save is refused for good: `NSDocument` compares the package
    /// directory's modification date against `fileModificationDate` and
    /// answers *"The file has been changed by another application"* — an
    /// honest complaint about the wrong application, since the change was
    /// ours. Measured: consolidate, then ⌘S, and every save from then on
    /// fails until the document is closed and reopened, stranding the
    /// relinks in memory while the copies sit on disk.
    ///
    /// Creating `media/` is what trips it. Writing a filmstrip into `cache/`
    /// does not, because `fileWrapper(ofType:)` already wrote that directory
    /// on the last save, so only the CHILD's date moves and the package's own
    /// stays put.
    ///
    /// This is not a "save anyway" override: the date is re-read from disk,
    /// so a change some OTHER application made in the same moment still
    /// raises the conflict on the following save.
    func packageContentsDidChangeOnDisk() {
        guard let fileURL = fileURL else { return }
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values?.contentModificationDate else { return }
        fileModificationDate = date
    }

    private var existingCacheDirectory: URL? {
        guard let directory = intendedCacheDirectory,
              FileManager.default.fileExists(atPath: directory.path)
        else { return nil }
        return directory
    }

    /// Kicks off thumbnails and peaks for every media that has a file. Safe
    /// to call repeatedly — a cache whose marker matches its file is not
    /// rebuilt; a relinked, changed, partial or unmarked one is
    /// (`MediaImporter.CacheStamp`) — so the open path, the import path, the
    /// three relink paths and Consolidate all just call it; a media with
    /// nothing to do costs a stat, a marker read per half and a `fileExists`.
    func generateCaches() {
        guard let cache = cacheDirectory else { return }
        let urls = mediaURLs()
        for media in project.snapshot.media {
            guard let url = urls[media.id] else { continue }
            MediaImporter.generateCaches(for: media, url: url, in: cache)
        }
    }

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
        ReverseSource.shared.publish(state.resolution, project: project, for: recipeKey)
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
    /// Video tab's "Render Reverse" button.
    func retryReversedMedia(for clip: ClipSnapshot) {
        guard let media = clip.source.mediaID else { return }
        refusedReverseMedia.remove(media)
        ensureReversedMedia()
    }

    /// What the Video tab's Reverse row should say about one clip.
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
        // Not `.projectDocumentDidChange`: the project did not change, the
        // disk did, and the §7.6 rebuild rule compares plans. See the
        // notification's own comment.
        NotificationCenter.default.post(name: .reversedMediaDidChange, object: self)
    }

    /// File > Add Media… and every drop that adds files to an OPEN project.
    /// Probing is asynchronous, so the files are probed one at a time and the
    /// whole batch commits as ONE undo step; `completion` gets the new media
    /// ids in the order the files were given, on the main thread.
    func importMedia(_ urls: [URL], completion: (([UInt32]) -> Void)? = nil) {
        guard !urls.isEmpty else {
            completion?([])
            return
        }
        probeNext(urls, index: 0, descriptors: [], completion: completion)
    }

    private func probeNext(
        _ urls: [URL], index: Int, descriptors: [MediaDescriptor],
        completion: (([UInt32]) -> Void)?
    ) {
        guard index < urls.count else {
            // Two statements, never `completion?(commitImport(descriptors))`:
            // optional chaining skips the ARGUMENT too, so with no completion
            // — File ▸ Add Media… and a Media-tab drop pass none — the files
            // were probed and never added, with no beep and no error.
            let added = commitImport(descriptors)
            completion?(added)
            return
        }
        MediaImporter.probe(url: urls[index]) { [weak self] result in
            guard let self = self else { return }
            var collected = descriptors
            switch result {
            case .success(let descriptor):
                collected.append(descriptor)
            case .failure(let error):
                // One unreadable file must not lose the rest of the drop.
                self.present(error)
            }
            self.probeNext(
                urls, index: index + 1, descriptors: collected, completion: completion)
        }
    }

    private func commitImport(_ descriptors: [MediaDescriptor]) -> [UInt32] {
        guard !descriptors.isEmpty else { return [] }
        let before = Set(project.snapshot.media.map { $0.id })
        performGroupedEdit(
            descriptors.count == 1 ? "Add Media" : "Add \(descriptors.count) Media Files",
            descriptors.map { ReelOp.addMedia(descriptor: $0) })
        let added = project.snapshot.media.filter { !before.contains($0.id) }
        generateCaches()
        return added.map { $0.id }
    }

    // MARK: - Change counting

    /// NSDocument's automatic undo-based change counting is unreliable here:
    /// whether the DidCloseUndoGroup/DidUndo/DidRedo counting fires depends
    /// on how the run loop is being driven (real UI events versus the agent
    /// server's dispatched-to-main tool calls), which double- or zero-counts
    /// edits. So this class counts every edit explicitly at the
    /// applyEdit/restore/endLiveEdit sites, and this override drops the
    /// automatic done/undone/redone calls. Clearing (save) and other change
    /// types pass through untouched.
    private var allowEditChangeCount = false

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        switch change {
        case .changeDone, .changeUndone, .changeRedone:
            guard allowEditChangeCount else { return }
        default:
            break
        }
        publishingEditedState { super.updateChangeCount(change) }
    }

    /// The OTHER half of the count, and the one a save arrives through.
    ///
    /// **Pitfall:** a save does not pass through `updateChangeCount(_:)` at
    /// all. Measured against an AppKit harness: an `autosavesInPlace` document
    /// clears its count here instead — `updateChangeCount(withToken:for:)`,
    /// on the main thread, for ⌘S (`saveAs`) and for every silent
    /// autosave-in-place alike. Hooking only the method above would publish
    /// clean → edited and never edited → clean, which is exactly the "· edited"
    /// suffix that used to stick in the window subtitle for the life of the
    /// document.
    override func updateChangeCount(
        withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType
    ) {
        publishingEditedState {
            super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        }
    }

    /// Runs one change-count mutation and posts `.projectDocumentDidChange`
    /// when — and only when — `isDocumentEdited` CROSSED.
    ///
    /// The window subtitle is the only dirty indicator this app has: under
    /// `autosavesInPlace` AppKit never sets `NSWindow.isDocumentEdited` and
    /// never sends `NSWindowController.setDocumentEdited(_:)`, so there is no
    /// close-button dot (`EditorWindowController.subtitle(for:)` says the rest).
    /// Nothing can observe the flag either — `NSDocument.isDocumentEdited` is
    /// not KVO-compliant — so the crossing is published by hand, and
    /// `EditorViewController.refreshFromDocument` rewrites the subtitle off the
    /// back of it like any other change.
    ///
    /// **On the crossing only.** That observer reloads the timeline and the
    /// inspector; posting on every call would put a full refresh behind every
    /// autosave. `isLive: false` because a dirty-state change is never
    /// mid-gesture: the live ticks are not counted.
    ///
    /// **And never from inside an edit** (`allowEditChangeCount`), which posts
    /// its own a moment later. Not just to save the duplicate: `projectDidChange`
    /// deliberately publishes the reverse resolution BEFORE its notification,
    /// and an extra post from in here would land between the count and that
    /// publish — so the editor would rebuild its composition against the
    /// PREVIOUS project's resolution and play a just-reversed clip forwards,
    /// on the first edit after every save. The edit paths all count and then
    /// post, so the crossing is published either way.
    private func publishingEditedState(_ body: () -> Void) {
        let wasEdited = isDocumentEdited
        body()
        guard isDocumentEdited != wasEdited, !allowEditChangeCount else { return }
        NotificationCenter.default.post(
            name: .projectDocumentDidChange, object: self, userInfo: ["isLive": false])
    }

    /// The explicit counting entry used by this class's edit paths.
    func countEditChange(_ change: NSDocument.ChangeType) {
        allowEditChangeCount = true
        updateChangeCount(change)
        allowEditChangeCount = false
    }

    // MARK: - Editing

    /// Stamps the open nest onto the ops of one edit — the ONE place a scope
    /// is put on an op, and therefore the whole of "an edit inside a nest"
    /// on this side (road map 2's phase 9).
    ///
    /// **The contract this changes is one `map`.** `applyEdit` still applies
    /// its ops to the PARENT handle and still gets a whole parent project
    /// back, so undo is still a stack of parent handles, the change count is
    /// unchanged and every one of `applyEdit`'s three outcomes means what it
    /// meant. All that is different is that each op is addressed at the nest
    /// first. `updateLiveEdit` does the same to its own ops for the same
    /// reason — a drag inside a nest is a drag — and `performGroupedEdit`
    /// gets it for free, because it calls `applyEdit`.
    ///
    /// **A document-level op is sent UNSCOPED** (`ReelOp.isDocumentLevel`,
    /// which argues it where the seven names are). One edit can mix the two
    /// kinds — a Finder drop inside a nest is an `add_media` on the
    /// document's one media list plus an `add_clip` in the nest, as one undo
    /// step — and the core applies the ops of an edit in sequence to the same
    /// parent handle, so mixing them costs nothing.
    ///
    /// **A scoped edit can fail where an unscoped one cannot**, and the
    /// `catch` below is what surfaces it: the clip and track caps and the
    /// nesting depth are document-wide and invisible from inside a nest, so
    /// an op that is perfectly valid against the nest still comes back
    /// `too many clips` / `too many tracks` / `nests are more than 8 deep`
    /// (`core/src/scope.rs` states that contract). It reaches the user as the
    /// core's own message, like any other invalid edit — never swallowed as
    /// "changed nothing", which would make ⌘G inside a deep stack look like a
    /// no-op.
    /// **An op that already CARRIES a scope keeps it.** This is the seam with
    /// the agent, and it was a measured defect before the clause existed: an
    /// MCP caller may name a nest explicitly, and the window may have a
    /// DIFFERENT one open. Without the guard, `scoped(_:)` — which overwrites
    /// unconditionally, by design, so the app's own gestures need no
    /// bookkeeping — silently re-addressed such a call to the open nest, and
    /// the edit landed in the wrong container while the tool answered `ok`.
    /// (The refusal it should have produced went to an error SHEET on the
    /// window, where no agent can see it.) An explicit scope is the caller's
    /// statement about which container they mean, and it outranks the view.
    private func addressed(_ ops: [ReelOp]) -> [ReelOp] {
        guard let nest = scope else { return ops }
        return ops.map { $0.isDocumentLevel || $0.scope != nil ? $0 : $0.scoped(nest) }
    }

    /// Applies one op as one undo step.
    func applyEdit(_ actionName: String, _ op: ReelOp) {
        applyEdit(actionName, [op])
    }

    /// Applies a sequence of ops as ONE undo step — a compound gesture
    /// (freeze frame, a multi-file import) is one thing to undo.
    ///
    /// Four answers (spec §5.5): `.applied` registers undo and publishes,
    /// `.identity` and `.refused` are BOTH a beep and no undo step, and a
    /// throw is the core's own message. `ReelEdit` argues the middle two.
    func applyEdit(_ actionName: String, _ ops: [ReelOp]) {
        let current = project
        do {
            switch try current.applying(addressed(ops)) {
            case .applied(let updated):
                registerUndo(restoring: current, actionName: actionName)
                project = updated
                countEditChange(.changeDone)
                projectDidChange()
            case .identity, .refused:
                // Both arms alike: a beep, and NO undo step.
                NSSound.beep()
            }
        } catch {
            present(error)
        }
    }

    /// `applyEdit` for a path that is NOT running inside an AppKit event — the
    /// async import completion above, and later the agent's
    /// dispatched-to-main tool calls.
    ///
    /// **Pitfall** (app/CLAUDE.md): an undo registration made outside an event
    /// lands in the implicit group `NSUndoManager` opens per event, which
    /// AppKit never closes here, so every such edit silently merges into ONE
    /// undo step.
    ///
    /// The fix is to turn event grouping OFF for the duration and balance an
    /// explicit group, **not** to force the level back to zero afterwards.
    /// Force-closing leaves the manager with an end and no begin, and the
    /// next `_postCheckpointNotification` — which `NSDocument` posts from
    /// inside the file-coordination accessor of every save — then raises
    /// `NSInternalInconsistencyException: endUndoGrouping called with no
    /// matching begin`. Under `autosavesInPlace` that exception is swallowed
    /// inside the coordinator, so the save neither completes nor writes nor
    /// relinquishes its file-access claim: ⌘S and `save_project` hang for
    /// good after the first agent edit, and every later file access on the
    /// document blocks behind the claim.
    func performGroupedEdit(_ actionName: String, _ ops: [ReelOp]) {
        guard let manager = undoManager else {
            applyEdit(actionName, ops)
            return
        }
        let groupsByEvent = manager.groupsByEvent
        if groupsByEvent { manager.groupsByEvent = false }
        let level = manager.groupingLevel
        manager.beginUndoGrouping()
        applyEdit(actionName, ops)
        // Close exactly what this call opened — never a group it did not.
        while manager.groupingLevel > level { manager.endUndoGrouping() }
        if groupsByEvent { manager.groupsByEvent = true }
    }

    /// True while a live-edit gesture is in progress. Observers use it —
    /// together with `userInfo["isLive"]` — to defer expensive refreshes
    /// until the gesture ends.
    var isLiveEditing: Bool { liveEditBase != nil }

    /// Snapshots the current handle. The `updateLiveEdit` calls that follow
    /// swap the project without touching the undo stack; `endLiveEdit` turns
    /// the whole gesture into a single step.
    func beginLiveEdit() {
        guard liveEditBase == nil else { return }
        liveEditBase = project
    }

    /// One tick of a gesture: applies `op` to the handle the gesture STARTED
    /// from, not to the last tick's result, so a drag is always
    /// base-plus-current-delta and the ops never compound. No undo
    /// registration; the notification carries `["isLive": true]`.
    func updateLiveEdit(_ op: ReelOp) {
        updateLiveEdit([op])
    }

    func updateLiveEdit(_ ops: [ReelOp]) {
        guard let base = liveEditBase,
            case .applied(let updated)? = try? base.applying(addressed(ops))
        else {
            // **Every answer but `.applied` is swallowed on purpose** — an
            // invalid tick, an identity and a rule's refusal alike (spec #8's
            // eighth decision). A refused tick is NORMAL here and recovers on
            // the next one; the last good frame stays. Not chatty.
            return
        }
        project = updated
        projectDidChange(isLive: true)
    }

    /// Registers ONE undo step from the `beginLiveEdit` snapshot to the
    /// current handle — none when the gesture changed nothing, which is every
    /// tick having been refused, an identity or invalid, since
    /// `updateLiveEdit` replaces the handle only on `.applied` — then a final
    /// `["isLive": false]` so listeners that skipped the ticks refresh once.
    func endLiveEdit(_ actionName: String) {
        guard let base = liveEditBase else { return }
        liveEditBase = nil
        if base !== project {
            registerUndo(restoring: base, actionName: actionName)
            countEditChange(.changeDone)
        }
        projectDidChange(isLive: false)
    }

    /// The ONE `registerUndo` call site in the app (app/CLAUDE.md).
    private func registerUndo(restoring handle: ReelProject, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { document in
            document.restore(handle, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    /// Undo/redo target. Restores a handle and registers its own inverse, so
    /// the stack walks both ways from any point.
    private func restore(_ restored: ReelProject, actionName: String) {
        let current = project
        registerUndo(restoring: current, actionName: actionName)
        project = restored
        if undoManager?.isRedoing == true {
            countEditChange(.changeRedone)
        } else {
            countEditChange(.changeUndone)
        }
        projectDidChange()
    }

    /// Publishes the new handle and tells everyone.
    ///
    /// `RecipeSource` is written here as well as in `Playback.update` — the
    /// same handle, so the repeat is free — because a document with no
    /// window (the agent's `render_frame`) still has to composite, and
    /// nothing else would ever publish for it.
    private func projectDidChange(isLive: Bool = false) {
        clampViewState()
        // The EDITED project: this slot is what the compositor draws the
        // PREVIEW from, and with a nest open the preview shows the nest at
        // its own frozen size, on its own terms (spec §4.4). Export publishes
        // on a `RecipeSource` key of its own and is unaffected — an export
        // always writes the whole timeline.
        RecipeSource.shared.set(editedProject, for: recipeKey)
        // Before the notification, for the same reason the recipe is: the
        // editor rebuilds the composition off the back of it, and a build that
        // read a stale resolution would play a just-reversed clip forwards.
        publishReverseResolution()
        NotificationCenter.default.post(
            name: .projectDocumentDidChange, object: self, userInfo: ["isLive": isLive])
        ensureReversedMedia()
    }

    /// Keeps the non-undoable view state honest about a model that just
    /// changed under it: a deleted or undone-away clip must not stay
    /// selected, and the playhead never goes negative.
    /// **The order is load-bearing** and is the phase-9 addition to this
    /// method. The scope goes first, because every measurement after it is
    /// taken against whatever container the scope clamp left: clamping the
    /// selection against a nest that has just been undone away would empty
    /// it, and clamping it against the timeline while a stale path still
    /// says "inside nest 4" would empty it the other way. Then the
    /// selection, then `selectedMedia`, then the playhead.
    ///
    /// The selection is intersected with the EDITED project's clips, which
    /// is what stops the first edit inside a nest wiping it: at the top level
    /// `editedProject` is `project` and this is the rule it always was.
    /// `selectedMedia` is asked of the DOCUMENT, because a media row is the
    /// document's whatever is open (the scoped view carries the parent's
    /// `media[]` unchanged, so the two answers agree — it is written this way
    /// to say which one is meant).
    ///
    /// A truncated path leaves the playhead where it was, reinterpreted in
    /// the container the truncation landed in. That is a small, deliberate
    /// inaccuracy on one path — an undo past the ⌘G that made the nest — and
    /// the honest alternative is not available: the offsets that would map it
    /// back out are the starts of clips that have just ceased to exist.
    ///
    /// **The in/out range is not reinterpreted; it goes.** This is the OTHER
    /// way the scope changes — `setNestPath` is the deliberate one and clears
    /// the range for the reason its own doc gives — and the rule at
    /// `inOutRange` is that a range never leaves the container it was set in,
    /// so both doors have to close it. The playhead can be left because a
    /// person can SEE where it landed and move it; a range is a pair of ticks
    /// that is next spent, unseen, by a ripple delete or an export, and one
    /// left behind after a truncation is measured from a zero that no longer
    /// exists. Cleared only when the path actually moved, so the ordinary
    /// edit — which is every call to this method — leaves it alone.
    private func clampViewState() {
        if !nestPath.isEmpty {
            let clamped = NestScope.clamped(nestPath, in: project.snapshot)
            if clamped != nestPath {
                nestPath = clamped
                scopedCache = nil
                inOutRange = nil
            }
        }
        let ids = Set(editedProject.snapshot.clips.map { $0.id })
        if !selection.isEmpty {
            selection.formIntersection(ids)
        }
        if let media = selectedMedia,
            !project.snapshot.media.contains(where: { $0.id == media })
        {
            selectedMedia = nil
        }
        playhead = max(0, playhead)
    }

    /// Errors never crash and never go to the console alone: they land in a
    /// sheet on the document's window when it has one.
    private func present(_ error: any Error) {
        if let window = windowForSheet {
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        } else {
            _ = presentError(error)
        }
    }
}
