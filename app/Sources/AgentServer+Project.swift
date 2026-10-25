import AppKit

/// The agent's project-level tools (spec §7.9): open, new, save, close, read,
/// and the playhead. Everything here mirrors a File-menu command or the
/// transport, and every edit goes through `ProjectDocument` exactly as the UI's
/// does. A path another open document holds is never written by `new_project`
/// or `save_project` (spec §11 #40): `close_project` closes that one first.
extension AgentServer {

    // MARK: - Opening

    /// `open_project` — File ▸ Open… (`AppDelegate`'s nil-target
    /// `openDocument:`). Takes a `.framejob` package OR any movie, sound file
    /// or picture the app handles: opening one of those builds a fresh
    /// untitled project sized and rated to it with the file as the first clip
    /// (spec §1), which is exactly what `ProjectDocument.read(from:ofType:)`
    /// does for a double-click.
    ///
    /// **Runs on the server thread** (`AgentServer.offMainTools`, spec §11
    /// #231), in three steps, so a WebM's copy, a re-copy on open or an
    /// ffmpeg conversion never holds the main thread: the already-open
    /// answer and the file's type on main; the read here, as AppKit's own
    /// concurrent read does it; then, on main, the document added and shown.
    /// It answers when the read ends, with no window and no question (MC-5).
    ///
    /// **One document per path** (spec §11 #234): each main-thread step is
    /// one block that sees a holder, or a person's open of the path still in
    /// flight (`ProjectDocumentController.isOpening`), or neither — and the
    /// last step adds in that same block. An open in flight is waited for
    /// (`afterPersonOpen`), and past `personOpenWait` the call is refused.
    func openProject(_ a: [String: Any]) throws -> String {
        let path = try requiredString(a, "path")
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "No file at \(url.path)")
        }
        let controller = NSDocumentController.shared
        // An imported movie leaves its document UNTITLED (spec §1), so
        // NSDocumentController's own `document(for:)` cannot find it — the
        // path a project is known by is `AgentServer.path(of:)`. Compared
        // canonically, as in `target(_:)`: two spellings of one file that
        // failed to match here would open the SAME file twice.
        let found: (answer: String?, type: String)? = try afterPersonOpen {
            if let answer = try self.alreadyOpen(url) { return (answer, "") }
            if ProjectDocumentController.isOpening(url) { return nil }
            return (nil, try controller.typeForContents(of: url))
        }
        guard let known = found else { throw Self.beingOpened(url) }
        if let answer = known.answer { return answer }
        // A tool call never asks the conversion question (spec §11 MC-5):
        // the read runs on this thread, inside the import's no-asking scope.
        let made = try MediaImporter.withoutAsking {
            try controller.makeDocument(withContentsOf: url, ofType: known.type)
        }
        guard let document = made as? ProjectDocument else {
            throw ToolError(
                message: "\(url.lastPathComponent) did not open as a Frame Job project.")
        }
        let landed: String? = try afterPersonOpen {
            // A document that came to hold the path during the read wins:
            // the one made here was never added and has no window.
            if let answer = try self.alreadyOpen(url) {
                document.close()
                return answer
            }
            if ProjectDocumentController.isOpening(url) { return nil }
            controller.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            controller.noteNewRecentDocumentURL(url)
            return try self.jsonResult(["project": self.summary(document)])
        }
        guard let answer = landed else {
            // The person's open outlasted the wait: theirs is the document,
            // and the one made here was never added or shown.
            onMain { document.close() }
            throw Self.beingOpened(url)
        }
        return answer
    }

    /// The longest `open_project` waits, at each of its two steps, for a
    /// person's open of the same path to end (spec §11 #234). The app never
    /// reassigns it; a probe shortens it (`ProjectDocument.copyWatch`'s
    /// precedent).
    static var personOpenWait: TimeInterval = 30

    /// One of `openProject`'s main-thread steps: `step` on main, where nil
    /// means a person's open of the path is in flight (spec §11 #234), again
    /// every 50 ms while it answers nil, until `personOpenWait` after its
    /// first nil; then nil. The sleep is this thread's and never main's: on
    /// main the deadline is at once. A hop to main is `onMain`'s and is not
    /// counted.
    private func afterPersonOpen<T>(_ step: () throws -> T?) throws -> T? {
        var deadline: Date?
        while true {
            if let found = try onMain(step) { return found }
            let now = Date()
            let limit = deadline
                ?? (Thread.isMainThread ? now : now.addingTimeInterval(Self.personOpenWait))
            deadline = limit
            if now >= limit { return nil }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// `open_project`'s refusal of a file a person's open is still reading.
    private static func beingOpened(_ url: URL) -> ToolError {
        ToolError(
            message: "\(url.lastPathComponent) is being opened in a window; call open_project "
                + "again once it has opened.")
    }

    /// `open_project`'s answer when an open document already holds `url`,
    /// else nil. Main only.
    private func alreadyOpen(_ url: URL) throws -> String? {
        guard let existing = documentHolding(url, except: nil) else { return nil }
        // Bring it forward, as double-clicking an already-open document
        // does — otherwise `target` would still resolve a later-opened
        // project and the next call would edit the wrong one.
        existing.showWindows()
        return try jsonResult(["already_open": true, "project": summary(existing)])
    }

    /// `new_project` — File ▸ New Project (`AppDelegate.newProject`): a blank
    /// 1920×1080 / 30 fps project. With `path` it is saved there straight
    /// away, so the agent has a file to name in later calls; without one it
    /// stays an untitled draft and `save_project {path}` finishes the job.
    /// A path another open document holds is refused BEFORE anything is
    /// created (spec §11 #40), so two documents never share one file.
    func newProject(_ a: [String: Any]) throws -> String {
        let url = try stringArg(a, "path").map {
            Self.destinationURL($0, extension: ProjectDocument.projectFileExtension)
        }
        let document = try onMain { () throws -> ProjectDocument in
            if let url { try self.refuseHeldPath(url, except: nil, tool: "new_project") }
            guard let document = try NSDocumentController.shared
                .openUntitledDocumentAndDisplay(true) as? ProjectDocument
            else {
                throw ToolError(message: "A new project could not be created.")
            }
            return document
        }
        guard let url else {
            return try onMain { try self.jsonResult(["project": self.summary(document)]) }
        }
        try save(document, to: url, operation: .saveAsOperation)
        return try onMain {
            try self.jsonResult(["saved": url.path, "project": self.summary(document)])
        }
    }

    // MARK: - Saving

    /// `save_project` — ⌘S. An untitled project (a movie opened as one, or a
    /// `new_project` with no path) has no file yet, so `path` is required for
    /// it and optional everywhere else; passing one writes there, the way
    /// Save As does — unless it names the document's own file, however
    /// spelled (`canonical`), which is a plain save: Save As onto itself
    /// would re-spell the document's path as the caller wrote it (#138). Any
    /// other path another open document holds is refused (spec §11 #40).
    func saveProject(_ a: [String: Any]) throws -> String {
        let document = try onMain { try self.target(a) }
        let existing = onMain { document.fileURL }
        if let path = try stringArg(a, "path") {
            let url = Self.destinationURL(path, extension: ProjectDocument.projectFileExtension)
            if let existing, Self.canonical(url.path) == Self.canonical(existing.path) {
                try save(document, to: existing, operation: .saveOperation)
                return try onMain {
                    try self.jsonResult(["saved": existing.path, "project": self.summary(document)])
                }
            }
            try onMain { try self.refuseHeldPath(url, except: document, tool: "save_project") }
            try save(document, to: url, operation: .saveAsOperation)
            return try onMain {
                try self.jsonResult(["saved": url.path, "project": self.summary(document)])
            }
        }
        guard let url = existing else {
            throw ToolError(
                message: "This project has never been saved, so save_project needs a path — "
                    + "an absolute path ending in .\(ProjectDocument.projectFileExtension).")
        }
        try save(document, to: url, operation: .saveOperation)
        return try onMain {
            try self.jsonResult(["saved": url.path, "project": self.summary(document)])
        }
    }

    /// The open document whose file is `url` — the path `get_project` reports
    /// for it, `fileURL` or the movie it was built from — compared exactly and
    /// canonically, as `target(_:)` compares: two spellings of one file that
    /// failed to match would put two documents at one path. `except` is
    /// skipped (`===`), for a save that is that document's own. Main only.
    func documentHolding(_ url: URL, except: ProjectDocument?) -> ProjectDocument? {
        let canonical = Self.canonical(url.path)
        return openProjects().first { document in
            if let except, document === except { return false }
            guard let open = Self.path(of: document) else { return false }
            return open == url.path || Self.canonical(open) == canonical
        }
    }

    /// Refuses a write to a path another open document holds (spec §11 #40),
    /// naming that document and the way out, and then to a path a person's
    /// open is still reading (spec §11 #234). Main only, so `save_project`
    /// and `new_project` call it inside `onMain`. The save is a later hop:
    /// an open that begins after this check is not seen (#234's risks).
    func refuseHeldPath(_ url: URL, except: ProjectDocument?, tool: String) throws {
        if let holder = documentHolding(url, except: except) {
            throw ToolError(
                message: "Another open project (\(holder.displayName ?? "Untitled")) is at "
                    + "\(url.path), so \(tool) did not write there: close_project closes it, "
                    + "or pass another path.")
        }
        guard ProjectDocumentController.isOpening(url) else { return }
        throw ToolError(
            message: "\(url.path) is being opened in a window, so \(tool) did not write "
                + "there: call \(tool) again once it has opened, or pass another path.")
    }

    /// Writes `document` and WAITS for NSDocument's asynchronous save to
    /// finish, so the tool's answer is only sent once the package is really on
    /// disk and the agent can read it back.
    ///
    /// The wait is why `save_project` and `new_project` run on the server
    /// thread: `save(to:ofType:for:completionHandler:)` delivers its
    /// completion on the MAIN thread, which a main-thread wait would be
    /// occupying.
    private func save(
        _ document: ProjectDocument, to url: URL, operation: NSDocument.SaveOperationType
    ) throws {
        guard !Thread.isMainThread else {
            throw ToolError(message: "Saving cannot run on the main thread.")
        }
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentBox<(any Error)?>()
        onMain {
            document.save(
                to: url, ofType: ProjectDocument.projectTypeIdentifier, for: operation
            ) { error in
                box.value = error
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + 120) == .success else {
            throw ToolError(message: "Timed out saving \(url.lastPathComponent).")
        }
        if let error = box.value ?? nil {
            throw ToolError(message: error.localizedDescription)
        }
    }

    // MARK: - Closing

    /// `close_project` — File ▸ Close (⌘W; spec §11 #40). It runs on main,
    /// as the menu item does, and closes through `ProjectDocument.close()`,
    /// which releases the recipe key and the graphic store; it never writes
    /// the package. A window with a sheet attached is refused first, because
    /// the sheet is window-modal work in progress (`handleEditorKey`'s rule);
    /// then unsaved changes, unless `discard: true`. Under autosave in place
    /// "unsaved" means "not yet autosaved", and that is all `discard` loses.
    func closeProject(_ a: [String: Any]) throws -> String {
        let discard = try boolArg(a, "discard") ?? false
        let document = try target(a)
        let name = document.displayName ?? "Untitled"
        let path = Self.path(of: document)
        let edited = document.isDocumentEdited
        if document.windowControllers.contains(where: { $0.window?.attachedSheet != nil }) {
            throw ToolError(
                message: "\(name) has a sheet open on its window, so close_project left it "
                    + "open: finish or cancel the sheet first.")
        }
        if edited && !discard {
            throw ToolError(
                message: "\(name) has unsaved changes, so close_project left it open: "
                    + "save_project saves them, or close_project with discard: true closes "
                    + "it and loses them.")
        }
        document.close()
        return try jsonResult(
            [
                "ok": true, "closed": name, "path": path ?? NSNull(),
                "discarded_changes": edited,
            ])
    }

    // MARK: - Reading

    /// `get_project` — the whole project as the JSON of spec §5.2, straight
    /// from the core (`rc_project_to_json`), plus the view state that is
    /// deliberately NOT in the model: the playhead, the selection and the
    /// in/out range live in Swift (§5.2's last bullet).
    func getProject(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        // The EDITED project (road map 2's phase 9): with a nest open
        // (`set_scope`) this reports the nest as a project — its tracks and
        // clips at the top level, its frozen size as the canvas — which is
        // what the app is showing and what a scoped op's ids resolve
        // against, so an agent reads the ids it is about to name. With no
        // nest open it is the same handle it always was, byte for byte.
        let project = document.editedProject
        var result: [String: Any] = [:]
        if let data = project.json.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            result["project"] = object
        } else {
            result["project_json"] = project.json
        }
        result["path"] = Self.path(of: document) ?? NSNull()
        result["name"] = document.displayName ?? "Untitled"
        result["unsaved_changes"] = document.isDocumentEdited
        result["duration"] = project.duration
        result["playhead"] = document.playhead
        result["selection"] = document.selection.sorted().map { Int($0) }
        if let range = document.inOutRange {
            result["in_out_range"] = ["start": range.start, "end": range.end]
        }
        result.merge(scopeReport(document)) { _, new in new }
        let missing = document.missingMedia.map { Int($0.id) }
        if !missing.isEmpty { result["missing_media"] = missing }
        result["graphics"] = graphicsSummary(document)
        result["note"] =
            "Times are ticks at 600000 per second. tracks[0] is the BACK of the layer stack; "
            + "clip ids, track ids, marker ids and media ids share one number space."
        if document.scope != nil {
            result["note"] =
                (result["note"] as? String ?? "")
                + " A nest is OPEN (set_scope), so project is that NEST seen as a project: its "
                + "own tracks and clips at the top level, its frozen size as the canvas, times "
                + "from its own zero, no markers, and its own row under nests deliberately "
                + "emptied because its contents are the top level here. media and nests are "
                + "still the document's — one id space. Send scope with an op to edit in here; "
                + "set_scope with no arguments comes back out."
        }
        return try jsonResult(result)
    }

    // MARK: - Transport

    /// `set_playhead` — clicking the ruler / the transport keys. View state,
    /// not an edit: no op runs and no undo step is registered (spec §5.2). It
    /// goes through `EditorViewController.setPlayhead` when the project has a
    /// window, so the player seeks and every pane follows; a windowless
    /// document just gets the time, which is all `render_frame` needs.
    func setPlayhead(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let time = try timeArg(a, "t", document)
        let clamped = max(0, time)
        if let editor = editor(document) {
            editor.setPlayhead(clamped)
            editor.viewStateDidChange()
        } else {
            document.playhead = clamped
        }
        return try jsonResult(
            ["ok": true, "playhead": document.playhead, "project": summary(document)])
    }

    /// `set_range` — Mark ▸ Set In / Set Out / Clear Range (I, O, ⌥X:
    /// `EditorViewController.setInPoint` / `setOutPoint` /
    /// `clearInOutRange`). View state like the playhead, so no op runs and
    /// nothing is undoable — but `export {range: "in_out"}` reads it, and
    /// `get_project` already reported it, so this is the write half of a
    /// field the agent could previously only look at.
    ///
    /// With neither bound the range is CLEARED, which is what ⌥X does.
    func setRange(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let start = try optionalTimeArg(a, "start", document)
        let end = try optionalTimeArg(a, "end", document)
        if start == nil && end == nil {
            document.inOutRange = nil
        } else {
            let from = max(0, start ?? document.inOutRange?.start ?? 0)
            let to = max(0, end ?? document.inOutRange?.end ?? document.project.duration)
            guard to > from else {
                throw ToolError(
                    message: "The range end (\(to)) must be after its start (\(from)); "
                        + "call set_range with no arguments to clear it.")
            }
            document.inOutRange = (start: from, end: to)
        }
        if let editor = editor(document) {
            editor.viewStateDidChange()
            editor.applyLoopRange()
        }
        var result: [String: Any] = ["ok": true, "project": summary(document)]
        if let range = document.inOutRange {
            result["in_out_range"] = ["start": range.start, "end": range.end]
        } else {
            result["in_out_range"] = NSNull()
        }
        return try jsonResult(result)
    }

    /// `set_selection` — clicking a clip in the timeline
    /// (`EditorViewController+Timeline.timelineSelected`) or on the canvas
    /// (`+Canvas.canvasSelected`), and Edit ▸ Select All / Select Forward
    /// (`selectAll(_:)`, `selectAfterPlayhead(_:)`). View state like the
    /// playhead and the range: no op runs and nothing is undoable.
    ///
    /// It is the write half of a field `get_project` already reported, and
    /// the one the agent was missing: the canvas handles, crop mode and
    /// every inspector pane act on the SELECTION, so without this nothing
    /// they do could be driven or checked by driving the app — which is why
    /// spec §10 step 8 stayed unverified.
    ///
    /// **Its ids mean the OPEN container** (road map 2's phase 9), and it
    /// gets that from `clipsArg` without a line of its own: a selection is
    /// clip ids in whichever container the app is looking at
    /// (`ProjectDocument.setNestPath` moves the two together), so with a nest
    /// open this selects inside it and cannot name a clip on the timeline.
    /// That is the same rule `effectiveScope` gives every other tool, read
    /// for a tool that has no `scope` argument of its own to override it
    /// with — the way in is `set_scope`, which is where a view is chosen.
    func setSelection(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        var ids: [UInt32] = []
        if let raw = a["clips"], !(raw is NSNull) {
            // An explicit `[]` means "select nothing", which is a real
            // intent here — unlike an OP over no clips, the mistake
            // `optionalClipsArg` refuses an empty list as. Omitting `clips`
            // does the same, the way `set_range` with no bounds clears the
            // range.
            if let array = raw as? [Any], array.isEmpty {
                ids = []
            } else {
                ids = try clipsArg(a, "clips", document)
            }
        }
        // `clipsArg` validating every id against the snapshot is the ONLY
        // thing keeping a dead id out of the selection: `viewStateDidChange`
        // republishes the view state but does not run
        // `ProjectDocument.clampViewState`, which prunes on a MODEL change,
        // so nothing downstream will notice one.
        document.selection = Set(ids)
        if let editor = editor(document) {
            editor.viewStateDidChange()
        }
        return try jsonResult(
            [
                "ok": true,
                "selection": document.selection.sorted().map { Int($0) },
                "project": summary(document),
            ])
    }
}
