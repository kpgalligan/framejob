import AppKit

/// The agent's project-level tools (spec §7.9): open, new, save, read, and
/// the playhead. Everything here mirrors a File-menu command or the transport,
/// and every edit goes through `ProjectDocument` exactly as the UI's does.
extension AgentServer {

    // MARK: - Opening

    /// `open_project` — File ▸ Open… (`AppDelegate`'s nil-target
    /// `openDocument:`). Takes a `.reelcut` package OR any movie, sound file
    /// or picture the app handles: opening one of those builds a fresh
    /// untitled project sized and rated to it with the file as the first clip
    /// (spec §1), which is exactly what `ProjectDocument.read(from:ofType:)`
    /// does for a double-click.
    func openProject(_ a: [String: Any]) throws -> String {
        let path = try requiredString(a, "path")
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError(message: "No file at \(url.path)")
        }
        // An imported movie leaves its document UNTITLED (spec §1), so
        // NSDocumentController's own `document(for:)` cannot find it — the
        // path a project is known by is `AgentServer.path(of:)`. Compared
        // canonically, as in `target(_:)`: two spellings of one file that
        // failed to match here would open the SAME file twice.
        let canonical = Self.canonical(url.path)
        if let existing = openProjects().first(where: {
            guard let open = Self.path(of: $0) else { return false }
            return open == url.path || Self.canonical(open) == canonical
        }) {
            // Bring it forward, as double-clicking an already-open document
            // does — otherwise `target` would still resolve a later-opened
            // project and the next call would edit the wrong one.
            existing.showWindows()
            return try jsonResult(["already_open": true, "project": summary(existing)])
        }
        let controller = NSDocumentController.shared
        let type = try controller.typeForContents(of: url)
        guard let document = try controller.makeDocument(withContentsOf: url, ofType: type)
            as? ProjectDocument
        else {
            throw ToolError(
                message: "\(url.lastPathComponent) did not open as a Reelcut project.")
        }
        controller.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        controller.noteNewRecentDocumentURL(url)
        return try jsonResult(["project": summary(document)])
    }

    /// `new_project` — File ▸ New Project (`AppDelegate.newProject`): a blank
    /// 1920×1080 / 30 fps project. With `path` it is saved there straight
    /// away, so the agent has a file to name in later calls; without one it
    /// stays an untitled draft and `save_project {path}` finishes the job.
    func newProject(_ a: [String: Any]) throws -> String {
        let document = try onMain { () throws -> ProjectDocument in
            guard let document = try NSDocumentController.shared
                .openUntitledDocumentAndDisplay(true) as? ProjectDocument
            else {
                throw ToolError(message: "A new project could not be created.")
            }
            return document
        }
        guard let path = try stringArg(a, "path") else {
            return try onMain { try self.jsonResult(["project": self.summary(document)]) }
        }
        let url = Self.destinationURL(path, extension: ProjectDocument.projectFileExtension)
        try save(document, to: url, operation: .saveAsOperation)
        return try onMain {
            try self.jsonResult(["saved": url.path, "project": self.summary(document)])
        }
    }

    // MARK: - Saving

    /// `save_project` — ⌘S. An untitled project (a movie opened as one, or a
    /// `new_project` with no path) has no file yet, so `path` is required for
    /// it and optional everywhere else; passing one always writes there, the
    /// way Save As does.
    func saveProject(_ a: [String: Any]) throws -> String {
        let document = try onMain { try self.target(a) }
        let existing = onMain { document.fileURL }
        if let path = try stringArg(a, "path") {
            let url = Self.destinationURL(path, extension: ProjectDocument.projectFileExtension)
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

    /// An output path as the tools take one: `~` expanded, and the extension
    /// the format actually needs (a `.reelcut` package without its extension
    /// is not a package, and an `.mp4` written to a name ending `.mov` claims
    /// a container it does not have).
    ///
    /// A WRONG extension is REPLACED, not appended to. Appending is what
    /// turned an export to `final.mov` with an MP4-container preset into
    /// `final.mov.mp4` — a file at neither the path the caller asked for nor
    /// one they would guess. Every caller reports the URL this returns, so
    /// the substitution is never silent.
    /// The extensions `destinationURL` will REPLACE: the containers this app
    /// writes, its own package, and the media extensions a caller is most
    /// likely to type out of habit. Everything else is part of the name.
    ///
    /// `srt` and `vtt` joined the list when `export_captions` landed, because
    /// after it they satisfy the set's own description: they are containers
    /// this app writes. Without them `export_captions {path: "talk.srt",
    /// format: "vtt"}` would write `talk.srt.vtt`, which is exactly the
    /// doubled name the paragraph above says the replacement exists to
    /// prevent.
    ///
    /// The five image containers joined it in road map 2's phase 7a, on the
    /// same terms and for two reasons rather than one. The new one:
    /// `render_frame` takes a `path` and a `format` now (`FrameWriter`), so
    /// `render_frame {path: "shot.jpg", format: "png"}` would have written
    /// `shot.jpg.png`. The old one is a REAL BUG this fixes rather than
    /// prevents — `gif` has been a container this app writes since M3's image
    /// sequences, and without it `export {path: "loop.gif", preset: "apng"}`
    /// writes `loop.gif.png` today. Both spellings of JPEG are here because a
    /// person types both; `heif` is NOT, because this app never writes one
    /// (`FrameWriter.Format.heic` is `UTType.heic` for the measured reason
    /// recorded there), so a file called `scene.heif` keeps its name.
    private static let replaceableExtensions: Set<String> = [
        "mov", "mp4", "m4v", "m4a", "mp3", "wav", "aif", "aiff", "caf", "reelcut", "srt", "vtt",
        "png", "jpg", "jpeg", "heic", "gif",
    ]

    static func destinationURL(_ path: String, extension ext: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let current = url.pathExtension
        if current.lowercased() == ext.lowercased() { return url }
        // Only a KNOWN container extension is replaced. A "looks like an
        // extension" heuristic is not good enough: it turns "Talk v1.2" into
        // "Talk v1.mp4", silently dropping a character the caller typed on
        // purpose. Anything not on this list is treated as part of the name
        // and the extension is appended to it.
        let base = Self.replaceableExtensions.contains(current.lowercased())
            ? url.deletingPathExtension() : url
        return base.appendingPathExtension(ext)
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
