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
    var inOutRange: (start: Ticks, end: Ticks)?

    // MARK: - Types

    /// The package UTI, exported by project.yml.
    static let projectTypeIdentifier = "com.kgalligan.reelcut-project"
    static let projectFileExtension = "reelcut"

    private static let projectFileName = "project.json"
    private static let cacheDirectoryName = "cache"

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
        addWindowController(EditorWindowController(document: self))
        // Filmstrips and waveforms for whatever the open brought in. Cheap
        // to ask for repeatedly: `MediaImporter` skips a cache that is
        // already on disk.
        generateCaches()
    }

    override func close() {
        // The compositor's only channel to this document. Dropping it here —
        // not in a deinit, which a retained window controller can delay
        // indefinitely — is what keeps a closed document's Rust project from
        // living for the life of the process.
        if !didReleaseRecipeKey {
            didReleaseRecipeKey = true
            RecipeSource.shared.unregister(recipeKey)
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

    override func read(from url: URL, ofType typeName: String) throws {
        if Self.isProjectType(typeName, url: url) {
            try readPackage(at: url)
        } else {
            try readMediaFile(at: url)
        }
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
        project = try ReelProject.from(json: text)
        playhead = 0
        selection = []
        inOutRange = nil
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
        // Set BEFORE the project is built: it is what makes the `fileURL` and
        // `fileType` overrides above refuse the assignments NSDocument makes
        // as soon as this method returns. Written on the read queue and read
        // on the main thread afterwards, which NSDocument's own hand-off
        // between the two orders for us.
        importSourceURL = url
        // …and undo the assignment NSDocument may already have made, on the
        // open path that sets the two BEFORE the read (see `fileURL` above).
        // A document left pointing at the movie is not untitled, and saving
        // it writes a package over the source file.
        fileURL = nil
        fileType = Self.projectTypeIdentifier
        let descriptor = try MediaImporter.probeBlocking(url: url)
        project = try Self.makeProject(around: descriptor)
        playhead = 0
        selection = []
        inOutRange = nil
    }

    /// Builds the project one imported file becomes. The canvas takes the
    /// source's display size and rate when it has video; an audio-only file
    /// has neither, so it lands on the 1080p/30 default.
    private static func makeProject(around descriptor: MediaDescriptor) throws -> ReelProject {
        let width = descriptor.hasVideo && descriptor.width > 0 ? descriptor.width : 1920
        let height = descriptor.hasVideo && descriptor.height > 0 ? descriptor.height : 1080
        let fps = descriptor.hasVideo && descriptor.fps.double > 0 ? descriptor.fps : .thirty
        guard let base = ReelProject.new(width: width, height: height, fps: fps) else {
            throw ReelCoreError(
                message: "\(descriptor.path) reports a size or frame rate a project cannot use.")
        }
        guard let withMedia = try base.applying(.addMedia(descriptor: descriptor)) else {
            throw ReelCoreError(message: "The file could not be added to a project.")
        }
        // `add_media` returns a project, not an id (there is one FFI entry
        // point for every op, §11), so the id is read back off the new
        // snapshot: the core appends, so the last entry is the new one.
        let snapshot = withMedia.snapshot
        guard let media = snapshot.media.last, let track = snapshot.tracks.first else {
            return withMedia
        }
        // A clip the core refuses (an empty media, say) is not fatal: the
        // project still opens with the file in the Media tab.
        return (try? withMedia.applying(.addClip(track: track.id, media: media.id, at: 0)))
            .flatMap { $0 } ?? withMedia
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

    private var existingCacheDirectory: URL? {
        guard let directory = intendedCacheDirectory,
              FileManager.default.fileExists(atPath: directory.path)
        else { return nil }
        return directory
    }

    /// Kicks off thumbnails and peaks for every media that has a file. Safe
    /// to call repeatedly — a cache already on disk is not rebuilt — so the
    /// open path and the import path both just call it.
    func generateCaches() {
        guard let cache = cacheDirectory else { return }
        let urls = mediaURLs()
        for media in project.snapshot.media {
            guard let url = urls[media.id] else { continue }
            MediaImporter.generateCaches(for: media, url: url, in: cache)
        }
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
            completion?(commitImport(descriptors))
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
        super.updateChangeCount(change)
    }

    /// The explicit counting entry used by this class's edit paths.
    func countEditChange(_ change: NSDocument.ChangeType) {
        allowEditChangeCount = true
        updateChangeCount(change)
        allowEditChangeCount = false
    }

    // MARK: - Editing

    /// Applies one op as one undo step.
    func applyEdit(_ actionName: String, _ op: ReelOp) {
        applyEdit(actionName, [op])
    }

    /// Applies a sequence of ops as ONE undo step — a compound gesture
    /// (freeze frame, a multi-file import) is one thing to undo.
    ///
    /// Three outcomes, exactly as spec §5.5 defines them:
    /// * a new project — register undo, count the change, publish;
    /// * `nil` (valid but changes nothing) — beep and register NO undo step,
    ///   because a phantom step makes ⌘Z look broken;
    /// * a throw (invalid arguments) — present the core's own message.
    func applyEdit(_ actionName: String, _ ops: [ReelOp]) {
        let current = project
        let updated: ReelProject?
        do {
            updated = try current.applying(ops)
        } catch {
            present(error)
            return
        }
        guard let updated = updated else {
            NSSound.beep()
            return
        }
        registerUndo(restoring: current, actionName: actionName)
        project = updated
        countEditChange(.changeDone)
        projectDidChange()
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
        guard let base = liveEditBase else { return }
        let updated: ReelProject?
        do {
            updated = try base.applying(ops)
        } catch {
            // A refused tick is normal mid-gesture (a drag that has strayed
            // past the source bound): keep the last good frame, do not
            // interrupt the drag with an alert.
            return
        }
        guard let updated = updated else { return }
        project = updated
        projectDidChange(isLive: true)
    }

    /// Registers ONE undo step from the `beginLiveEdit` snapshot to the
    /// current handle — none when the gesture changed nothing (same handle)
    /// — then posts a final `["isLive": false]` so listeners that skipped
    /// the live ticks refresh exactly once per gesture.
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
        RecipeSource.shared.set(project, for: recipeKey)
        NotificationCenter.default.post(
            name: .projectDocumentDidChange, object: self, userInfo: ["isLive": isLive])
    }

    /// Keeps the non-undoable view state honest about a model that just
    /// changed under it: a deleted or undone-away clip must not stay
    /// selected, and the playhead never goes negative.
    private func clampViewState() {
        let ids = Set(project.snapshot.clips.map { $0.id })
        if !selection.isEmpty {
            selection.formIntersection(ids)
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
