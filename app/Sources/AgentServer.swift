import AppKit

/// Hosts the core's embedded MCP server (streamable HTTP on 127.0.0.1) and
/// executes its tool calls against the open projects. The Rust side owns the
/// protocol (`rc_agent_server_start`); this class owns the tool catalog and
/// the dispatch, which runs on the main thread so every edit flows through
/// the same `ProjectDocument` entry points as the UI — undoable, dirtying,
/// and live in the window.
///
/// Point any MCP client at `http://127.0.0.1:<port>/mcp` — e.g.
///   goose session --with-streamable-http-extension "http://127.0.0.1:4817/mcp"
///
/// The endpoint is unauthenticated: any local process may connect while it
/// runs. It is off by default (Tools ▸ Allow Agent Connections), and on
/// automatically when the app is launched with `-AgentServerEnabled YES`
/// (spec §7.9).
///
/// **This file is frozen at wiring** (app/CLAUDE.md): the lifecycle, the
/// dispatch table, the edit and result helpers, and the trampoline. Every
/// handler lives in an `AgentServer+<Area>.swift` extension and the argument
/// vocabulary in `AgentServer+Arguments.swift`, which is why the helpers here
/// are internal rather than private. The one piece of STATE a call leaves
/// here is `callScope` — road map 2's phase 9, and the sanctioned reason a
/// frozen file grows a property: an extension cannot hold one.
final class AgentServer {
    static let shared = AgentServer()

    /// Doubles as the persisted preference and the launch flag: AppKit puts
    /// `-AgentServerEnabled YES` into the argument domain, so one `bool`
    /// read answers both (spec §7.9).
    static let enabledDefaultsKey = "AgentServerEnabled"
    static let defaultPort: UInt16 = 4817

    private(set) var port: UInt16 = 0
    var isRunning: Bool { port != 0 }

    /// The nest the CURRENT tool call ASKED to edit inside — the envelope's
    /// `scope` (spec §6, `core/src/scope.rs`) — or nil, which means "wherever
    /// the app is looking" rather than "the timeline" (`effectiveScope`).
    /// Read once by `dispatch` below, consumed by the id readers in
    /// `AgentServer+Arguments.swift` and stamped onto every op in
    /// `performGroupedEdit`; `AgentServer+Scope.swift` is where the whole
    /// idea is written down.
    ///
    /// **A stored property is exactly what an extension cannot hold**, which
    /// is the sanctioned reason for a frozen file to gain one (app/CLAUDE.md;
    /// `Exporter`'s `lock` and `scratchStorage` are the precedent). The
    /// alternative was an arguments dictionary threaded through
    /// `performGroupedEdit`, `editResult` and fifty-eight handlers, all in
    /// two files already near the size cap, to carry one optional integer.
    ///
    /// **It is safe from races because the server is single-request.**
    /// `core/src/agent.rs`'s `serve` is one thread running
    /// `for request in server.incoming_requests()` with the comment "One
    /// request at a time" on it, and a batched array is `filter_map`ped in
    /// that same thread — so at most one tool is ever executing, whether it
    /// hopped to the main thread or (an `offMainTools` member) stayed on the
    /// server's. `private(set)` keeps the writing to this file, where the one
    /// write and its `defer` sit together.
    private(set) var callScope: UInt32?

    private init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AgentServer does not support NSCoder")
    }

    /// A tool's refusal, reported to the model IN BAND (`isError: true`) so it
    /// can read the message and correct itself rather than seeing a transport
    /// failure. Never surfaced as an alert: a modal on this dispatched-to-main
    /// path would block the main thread — and with it the MCP connection —
    /// until somebody clicked it.
    struct ToolError: Error {
        let message: String
    }

    /// A failure to START the server. This one IS user-facing (the menu item
    /// puts it in an alert), so it carries a localized description.
    struct ToolFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The tools whose handler runs on the SERVER thread instead of the main
    /// one, because each WAITS for something the main thread has to deliver or
    /// must not be doing. `import_media` waits on a probe whose completion
    /// `MediaImporter` posts to the main thread and `save_project` /
    /// `new_project` on NSDocument's asynchronous save, both of which a
    /// main-thread wait would deadlock against; `render_frame` and `export`
    /// block on decode and encode, and freezing the UI for a whole write is
    /// not acceptable. `transcribe` waits on a recognition task — whose
    /// callbacks the Speech framework delivers on an `OperationQueue` that
    /// defaults to the app's MAIN one — after extracting the clip's audio, so
    /// it is `import_media`'s case twice over. `record_screen` waits on the
    /// recorder, whose every callback is hopped to main, for up to ten
    /// minutes — `import_media`'s case again, and longer. Each hops back
    /// through `onMain` for every document touch, so the
    /// single-mutation-point rule is untouched.
    ///
    /// The criterion is NOT "touches the disk", which is why
    /// `detect_silence`, `consolidate_media`, `import_captions` and
    /// `export_captions` are all absent: each reads or writes a file on the
    /// main thread and each says so in its own handler.
    static let offMainTools: Set<String> = [
        "import_media", "render_frame", "export", "save_project", "new_project", "transcribe",
        "record_screen",
    ]

    // MARK: - Lifecycle

    /// Starts on `RC_AGENT_PORT` or the default port, falling back to an
    /// ephemeral port when that one is taken. Throws with a message on
    /// failure.
    func start() throws {
        guard !isRunning else { return }
        let preferred =
            ProcessInfo.processInfo.environment["RC_AGENT_PORT"]
            .flatMap(UInt16.init) ?? Self.defaultPort
        let catalog = try catalogJSON()
        // Nothing else forces the catalog and the dispatch table to agree, so
        // debug builds refuse to start the server on a mismatch. `make app`
        // builds Release, where an `assert` is compiled out — which would make
        // the one enforcement of the parity rule dead in every shipped build —
        // so Release logs the same message instead of failing silently.
        if let failure = Self.catalogParityFailure(catalog) {
            assertionFailure(failure)
            NSLog("Reelcut: %@", failure)
        }
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0"
        let context = Unmanaged.passUnretained(self).toOpaque()

        var bound: UInt16 = 0
        var lastError = "could not start the agent server"
        for candidate in [preferred, 0] where bound == 0 {
            var err: UnsafeMutablePointer<CChar>? = nil
            bound = rc_agent_server_start(
                candidate, "reelcut", version, catalog, agentToolTrampoline, context, &err)
            if let err = err {
                lastError = String(cString: err)
                rc_string_free(err)
            }
        }
        guard bound != 0 else {
            throw ToolFailure(message: lastError)
        }
        port = bound
        NSLog("Reelcut agent server listening on http://127.0.0.1:%d/mcp", Int(bound))
    }

    func stop() {
        guard isRunning else { return }
        rc_agent_server_stop()
        port = 0
    }

    // MARK: - Dispatch

    /// Executes one tool call and returns CallToolResult JSON. Errors are
    /// in-band (`isError: true`) so the model can read and correct them.
    ///
    /// Runs on the main thread for every tool but the `offMainTools`, which
    /// the trampoline leaves on the server thread.
    func execute(tool: String, argumentsJSON: String) -> String {
        assert(Thread.isMainThread || Self.offMainTools.contains(tool))
        let arguments =
            (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)))
            as? [String: Any] ?? [:]
        do {
            return try dispatch(tool, arguments)
        } catch let error as ToolError {
            return errorResult(error.message)
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    private func dispatch(_ tool: String, _ a: [String: Any]) throws -> String {
        guard let handler = Self.handlers[tool] else {
            throw ToolError(message: "Unknown tool: \(tool)")
        }
        // The envelope's `scope` is read ONCE, here, because this is the only
        // place that holds both the tool's name and its arguments for all
        // seventy-five of them — a read inside each handler would be
        // fifty-eight edit sites across two files, every one of them able to
        // forget. It is read for exactly the tools whose schema declares it
        // (`AgentCatalog.opNames`, the core's own op list), so a stray
        // `scope` on `get_project` or `export` is the ignored extra key it
        // has always been rather than a silently honoured one. The `defer`
        // is what makes the property a per-CALL value rather than state: the
        // next call starts with no scope of its own whatever this one asked
        // for or threw, and falls back to the view like any other.
        callScope = Self.opNames.contains(tool) ? try scopeArg(a) : nil
        defer { callScope = nil }
        return try handler(self)(a)
    }

    /// Tool name → handler, as unbound method references so the table — which
    /// lives as long as the type — holds no reference back to the singleton.
    /// The single source of truth for what the server dispatches:
    /// `catalogJSON()` (AgentCatalog.swift) must describe exactly these names,
    /// and `start()` checks the two sets match on every launch.
    ///
    /// One entry per row of the op table (spec §6, and the module doc of
    /// `core/src/edit.rs`) plus the twenty tools that are not ops: the
    /// project-level ones spec §7.9 names, the five view-state and history
    /// mirrors beside them (`set_range`, `set_selection`, `set_scope`,
    /// `undo`, `redo`), the composites later phases added —
    /// `detect_silence`, `transcribe`, `import_captions`, `export_captions`,
    /// `normalize_clip` — and road map 3's `record_screen`. The count is
    /// not decoration: `start()`'s parity check reads the core's own
    /// `rc_op_names` and holds an explicit allow-list for the ops that
    /// deliberately have no tool, so a new tool that is not an op belongs in
    /// that sentence as well as in this table.
    private static let handlers: [String: (AgentServer) -> ([String: Any]) throws -> String] = [
        // Projects (AgentServer+Project.swift)
        "open_project": { $0.openProject },
        "new_project": { $0.newProject },
        "save_project": { $0.saveProject },
        "get_project": { $0.getProject },
        "set_playhead": { $0.setPlayhead },
        "set_range": { $0.setRange },
        "set_selection": { $0.setSelection },
        // The nest being looked into (AgentServer+Scope.swift)
        "set_scope": { $0.setScope },
        // Undo history (AgentServer+History.swift)
        "undo": { $0.undoEdit },
        "redo": { $0.redoEdit },
        // Clips (AgentServer+Clips.swift)
        "add_clip": { $0.addClip },
        "add_text_clip": { $0.addTextClip },
        "add_shape_clip": { $0.addShapeClip },
        // Backgrounds (AgentServer+Background.swift)
        "add_background": { $0.addBackground },
        "add_blurred_background": { $0.addBlurredBackground },
        "insert_clip": { $0.insertClip },
        "overwrite_clip": { $0.overwriteClip },
        "move_clip": { $0.moveClip },
        "trim_start": { $0.trimStart },
        "trim_end": { $0.trimEnd },
        "rate_stretch": { $0.rateStretch },
        "slip": { $0.slip },
        "roll": { $0.roll },
        "split": { $0.split },
        "delete": { $0.deleteClips },
        "ripple_delete": { $0.rippleDelete },
        "ripple_delete_range": { $0.rippleDeleteRange },
        "ripple_delete_ranges": { $0.rippleDeleteRanges },
        "lift_range": { $0.liftRange },
        "insert_time": { $0.insertTime },
        "close_gap": { $0.closeGap },
        "set_speed": { $0.setSpeed },
        "set_reversed": { $0.setReversed },
        "freeze_frame": { $0.freezeFrame },
        "detach_audio": { $0.detachAudio },
        "duplicate": { $0.duplicateClips },
        "paste": { $0.pasteClips },
        "paste_attributes": { $0.pasteAttributes },
        "nest": { $0.nestClips },
        "unnest": { $0.unnestClips },
        "set_video": { $0.setVideo },
        "set_audio": { $0.setAudio },
        "set_text": { $0.setText },
        "set_shape": { $0.setShape },
        "set_clip": { $0.setClip },
        "set_enabled": { $0.setEnabled },
        "set_transition": { $0.setTransition },
        "set_transition_duration": { $0.setTransitionDuration },
        "add_transition": { $0.addTransition },
        "set_transition_style": { $0.setTransitionStyle },
        // Actions (AgentServer+Clips.swift)
        "add_action": { $0.addAction },
        "add_zoom_action": { $0.addZoomAction },
        "set_action": { $0.setAction },
        "set_action_end": { $0.setActionEnd },
        "remove_action": { $0.removeAction },
        // Silence detection (AgentServer+Silence.swift)
        "detect_silence": { $0.detectSilence },
        // Sound (AgentServer+Audio.swift)
        "normalize_clip": { $0.normalizeClip },
        // Captions (AgentServer+Captions.swift)
        "transcribe": { $0.transcribe },
        "export_captions": { $0.exportCaptions },
        // Recording (AgentServer+Recording.swift)
        "record_screen": { $0.recordScreen },
        // Tracks, markers and the canvas (AgentServer+Tracks.swift)
        "add_track": { $0.addTrack },
        "remove_track": { $0.removeTrack },
        "move_track": { $0.moveTrack },
        "set_track": { $0.setTrack },
        "remove_empty_tracks": { $0.removeEmptyTracks },
        "add_marker": { $0.addMarker },
        "set_marker": { $0.setMarker },
        "remove_marker": { $0.removeMarker },
        "set_canvas": { $0.setCanvas },
        // Media (AgentServer+Media.swift)
        "add_media": { $0.addMedia },
        "import_media": { $0.importMedia },
        "import_captions": { $0.importCaptions },
        "consolidate_media": { $0.consolidateMedia },
        "relink_media": { $0.relinkMedia },
        "remove_media": { $0.removeMedia },
        // Rendering and export (AgentServer+Render.swift)
        "render_frame": { $0.renderFrame },
        "export": { $0.exportProject },
    ]

    /// Ops the core declares that deliberately have NO tool. Empty, and the
    /// bar for an entry is high: the agent-parity rule (app/CLAUDE.md) says
    /// every user-visible edit gets a mirror, so the answer to "this op has
    /// no tool" is almost always to write the tool. An entry here carries a
    /// comment saying why it is the exception.
    private static let opsWithoutTools: Set<String> = []

    /// The enforcement behind the table's contract, in four parts:
    ///
    /// 1. `catalogJSON()` and `handlers` name exactly the same tools;
    /// 2. every op the CORE declares has a tool — the list read through
    ///    `ReelOp.coreNames()` (`rc_op_names` → `OP_NAMES` in
    ///    `core/src/edit.rs`) rather than restated here, because a Swift
    ///    copy of it would be one more spelling to drift and drift is what
    ///    this check exists to catch;
    /// 3. every tool's `inputSchema` is structurally sound — an object with
    ///    a `properties` map, and nothing named `required` that it does not
    ///    declare;
    /// 4. every OP tool declares `scope` — road map 2's phase 9, and the one
    ///    part that is about a feature rather than about the catalog's shape,
    ///    so it lives in `AgentServer+Scope.swift` and says there why parts 1
    ///    to 3 cannot see the omission it catches.
    ///
    /// **What it still cannot see.** Nothing validates a call against
    /// `inputSchema`, and the core publishes op NAMES, not op arguments, so
    /// a tool whose argument has the wrong TYPE — `add_text_clip`'s `text`
    /// declared `string` against the op's `text?: object` — passes all
    /// three. What guards that is the argument vocabulary in
    /// `AgentServer+Arguments.swift`, which now refuses a present value of
    /// the wrong type instead of reading it as absent; a drift of that kind
    /// then surfaces as an error on the first call rather than as a silently
    /// dropped argument. Publishing the argument names too would close it
    /// here, and wants a second table in `edit.rs` to be worth its keep.
    private static func catalogParityFailure(_ catalog: String) -> String? {
        guard
            let tools = (try? JSONSerialization.jsonObject(with: Data(catalog.utf8)))
                as? [[String: Any]]
        else { return "the tool catalog did not parse as an array of tool objects" }
        let catalogNames = Set(tools.compactMap { $0["name"] as? String })
        let handlerNames = Set(handlers.keys)
        if catalogNames != handlerNames {
            let missing = catalogNames.subtracting(handlerNames).sorted()
            let extra = handlerNames.subtracting(catalogNames).sorted()
            return "agent tool catalog and dispatch table disagree — in catalog but not "
                + "dispatch: \(missing); in dispatch but not catalog: \(extra)"
        }
        // The same set the catalog put a `scope` on and the same one
        // `dispatch` reads a `scope` for, so this check and the behaviour it
        // is checking cannot be looking at two different op tables.
        let ops = Self.opNames
        guard !ops.isEmpty else { return "the core reported no op names" }
        let uncovered = ops.subtracting(catalogNames).subtracting(opsWithoutTools).sorted()
        if !uncovered.isEmpty {
            return "the core's op table has ops with no agent tool: \(uncovered) — every row "
                + "of spec §6 needs a tool, a handler and a comment naming the UI path it "
                + "mirrors, or a line in AgentServer.opsWithoutTools saying why not"
        }
        let stale = opsWithoutTools.subtracting(ops).sorted()
        if !stale.isEmpty {
            return "AgentServer.opsWithoutTools names ops the core does not have: \(stale)"
        }
        // Part 4 lives in `AgentServer+Scope.swift` with the rest of the
        // scope, where parts 1 to 3 stay here with the table they check: it
        // is the only part that is about one FEATURE rather than about the
        // catalog's shape, and this file is frozen at wiring.
        return schemaFailure(tools) ?? Self.scopeFailure(tools, ops)
    }

    /// Part 3: the structural check on each tool's declared input. It cannot
    /// know what an argument MEANS, but a schema that is not an object, or
    /// that requires a property it never declares, is a catalog bug the
    /// model would meet as an unanswerable "missing required argument".
    private static func schemaFailure(_ tools: [[String: Any]]) -> String? {
        for tool in tools {
            let name = tool["name"] as? String ?? "<unnamed>"
            guard let schema = tool["inputSchema"] as? [String: Any],
                schema["type"] as? String == "object",
                let properties = schema["properties"] as? [String: Any]
            else { return "the tool \(name) has no object inputSchema with properties" }
            let required = (schema["required"] as? [Any])?.compactMap { $0 as? String } ?? []
            let undeclared = required.filter { properties[$0] == nil }.sorted()
            if !undeclared.isEmpty {
                return "the tool \(name) requires arguments it does not declare: \(undeclared)"
            }
        }
        return nil
    }

    // MARK: - Threading

    /// Runs `body` on the main thread and brings its answer back. The only
    /// thing an `offMainTools` handler may use to touch a document, AppKit or
    /// `RecipeSource`'s publish side.
    func onMain<T>(_ body: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try body() }
        return try DispatchQueue.main.sync(execute: body)
    }

    // MARK: - Projects

    /// Every open project document, in the document controller's order.
    func openProjects() -> [ProjectDocument] {
        NSDocumentController.shared.documents.compactMap { $0 as? ProjectDocument }
    }

    /// The file a document is identified by: its own package once saved, else
    /// the movie it was built from (spec §1 — an imported movie leaves the
    /// document untitled, so `fileURL` is deliberately nil there).
    static func path(of document: ProjectDocument) -> String? {
        document.fileURL?.path ?? document.importSourceURL?.path
    }

    /// A path in the one spelling both sides of a `project` comparison can be
    /// written in.
    ///
    /// Matching `fileURL.path` against the caller's string exactly is wrong
    /// twice over. A caller may legitimately spell the same file
    /// `~/Movies/x.reelcut`, `/tmp/x.reelcut` or `/private/tmp/x.reelcut` —
    /// and, the case that actually bit, AppKit's own save machinery can hand
    /// `fileURL` back in the OTHER spelling of that last pair, so a path that
    /// addressed the document for twenty calls suddenly answers "No open
    /// project is at …". `standardizedFileURL` folds `.`, `..` and doubled or
    /// trailing slashes; `resolvingSymlinksInPath` folds `/tmp` ⇄
    /// `/private/tmp` (and `/var`, `/etc`) whether or not the file exists yet.
    /// Two paths only collide here when they name the same file, which is the
    /// answer wanted.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The document a call targets: `project` (a path, as `get_project`
    /// reports it) when given, else the frontmost document, else the most
    /// recently created one. Main thread only.
    ///
    /// **Pitfall.** `NSDocumentController.currentDocument` is the document of
    /// `NSApp.mainWindow`, and an application that is not the ACTIVE
    /// application has no main window — which is the normal state for an
    /// agent-driven session, where nobody ever clicks the app. Falling
    /// straight through to `documents.first` there silently targets the
    /// OLDEST open project, so `new_project` followed by an edit edits some
    /// other document and says nothing. `NSApp.orderedDocuments` follows the
    /// app's own front-to-back window order, which `showWindows()` maintains
    /// whether or not the app is active, so it answers correctly in both
    /// states; `documents.last` is the last resort for a windowless document
    /// (the agent can make one), where newest is the better guess than
    /// oldest.
    func target(_ a: [String: Any]) throws -> ProjectDocument {
        let document = try targetDocument(a)
        // The scope is validated HERE, at the one gate every handler passes
        // through before it reads a single id, because the order of the two
        // refusals is part of the contract (`core/src/scope.rs`): a scope
        // naming no nest is answered by name, ahead of anything else, since
        // it is the argument that decides which document the caller thinks
        // it is editing. Doing it in the readers instead would make the
        // message depend on which argument a handler happens to read first —
        // `trim_start`'s `clip`, `close_gap`'s `at` — and would leave the
        // handlers that read no ids at all validating nothing.
        try checkCallScope(document)
        return document
    }

    private func targetDocument(_ a: [String: Any]) throws -> ProjectDocument {
        assert(Thread.isMainThread)
        let documents = openProjects()
        if let wanted = try stringArg(a, "project") {
            let path = (wanted as NSString).expandingTildeInPath
            let canonical = Self.canonical(wanted)
            guard
                let match = documents.first(where: {
                    guard let open = Self.path(of: $0) else { return false }
                    return open == path || Self.canonical(open) == canonical
                })
            else {
                throw ToolError(
                    message: "No open project is at \(path). get_project reports the open "
                        + "project's path; open_project opens another.")
            }
            return match
        }
        if let current = NSDocumentController.shared.currentDocument as? ProjectDocument {
            return current
        }
        if let ordered = NSApp.orderedDocuments.first(where: { $0 is ProjectDocument })
            as? ProjectDocument
        {
            return ordered
        }
        guard let newest = documents.last else {
            throw ToolError(
                message: "No project is open. Call open_project or new_project first.")
        }
        return newest
    }

    /// The editor showing `document`, when it has a window. nil for a
    /// windowless document — which the agent can produce, and which every
    /// caller here has to tolerate rather than assume away.
    func editor(_ document: ProjectDocument) -> EditorViewController? {
        document.windowControllers
            .compactMap { $0.contentViewController as? EditorViewController }
            .first
    }

    /// The one-line description of a project every result carries, so a model
    /// never has to call `get_project` just to see what its edit did.
    func summary(_ document: ProjectDocument) -> [String: Any] {
        let snapshot = document.project.snapshot
        let canvas = snapshot.canvas
        // missing_media rides on EVERY summary, not just get_project's: the
        // moment a caller most needs to know a file is gone is the open that
        // just surfaced it, and open_project answers with a summary. The key
        // is omitted when nothing is missing so a healthy project stays terse.
        var result: [String: Any] = [
            "name": document.displayName ?? "Untitled",
            "path": Self.path(of: document) ?? NSNull(),
            "width": canvas.width,
            "height": canvas.height,
            "fps": [canvas.fps.num, canvas.fps.den],
            "duration": document.project.duration,
            "playhead": document.playhead,
            "tracks": snapshot.tracks.count,
            "clips": snapshot.clips.count,
            "markers": snapshot.markers.count,
            "media": snapshot.media.count,
            "selection": document.selection.sorted().map { Int($0) },
            "unsaved_changes": document.isDocumentEdited,
        ]
        let missing = document.missingMedia.map { Int($0.id) }.sorted()
        if !missing.isEmpty { result["missing_media"] = missing }
        return result
    }

    // MARK: - Editing

    /// Applies `ops` as ONE undo step and returns the snapshot from BEFORE
    /// the edit (which is what names the ids it created).
    ///
    /// The ops are tried on the handle FIRST, purely — `ReelProject.applying`
    /// mutates nothing — because `ProjectDocument.applyEdit` answers the two
    /// failure cases with UI: an identity edit beeps and an invalid one puts
    /// up an alert sheet. Both are wrong on a dispatched-to-main tool call:
    /// the model needs the message, and a modal would block the connection.
    /// The trial costs a handle and no pixels (spec §5.5).
    ///
    /// The commit then goes through `ProjectDocument.performGroupedEdit`,
    /// whose explicit `beginUndoGrouping`/`endUndoGrouping` + flush is the
    /// off-event pattern (app/CLAUDE.md): an undo registration made outside an
    /// AppKit event otherwise lands in an implicit group AppKit never closes,
    /// silently merging every agent edit into one undo step.
    ///
    /// **This is where the call's scope is stamped onto its ops**, and the
    /// one place: every tool that edits ends here or in `editResult` above
    /// it, including the two composites that call it directly, so no handler
    /// has to remember. The rule is `AgentServer+Scope.addressed`, which
    /// mirrors `ProjectDocument.addressed(_:)` — and it has to be stamped
    /// BEFORE the trial below, not only at the commit, or a scoped edit would
    /// be tried against the wrong container and reported as a refusal it
    /// never suffered. With no scope anywhere it is the identity, which is
    /// what makes an unscoped call byte-for-byte the call it always was.
    ///
    /// It is also where the ops an inherited scope may NOT send are refused,
    /// for the same reason: this is the one place every editing tool passes
    /// through. `checkDocumentLevelTicks` is that rule and argues it.
    @discardableResult
    func performGroupedEdit(
        _ document: ProjectDocument, _ actionName: String, _ ops: [ReelOp]
    ) throws -> ProjectSnapshot {
        // `addressed` sends a document-level op UNSCOPED out of a scope it
        // inherited, which is right for five of the seven and a wrong
        // PLACEMENT for the two that carry a tick — a marker written from
        // inside a nest is measured from the nest's zero and lands elsewhere
        // on the timeline. Refused before the stamp, beside the rule it
        // guards (`AgentServer+Scope.swift`).
        try checkDocumentLevelTicks(ops, document)
        let ops = addressed(ops, document)
        let handle = document.project
        let before = handle.snapshot
        do {
            guard try document.project.applying(ops) != nil else {
                // `Ok(None)` is BOTH tiers of "no new project" (spec §5.5):
                // an identity edit and a documented refusal. Claiming the
                // first outright misinforms a caller whose `duplicate` or
                // `move_clip` was actually refused by the overlap rule, and
                // the core does not distinguish the two — so say both.
                throw ToolError(
                    message: "\(actionName) made no change. Either the project is already in "
                        + "that state, or the edit was refused: the usual reason for a "
                        + "placement op is the overlap rule — a clip may overlap at most one "
                        + "neighbour on each side, and each overlap must be at most half the "
                        + "shorter of the two clips. get_project shows what is where.")
            }
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        document.performGroupedEdit(actionName, ops)
        // **The trial promised a change; this is where the promise is
        // checked**, and it is one pointer comparison because `applyEdit`
        // replaces the handle only when the core answered with a new project.
        //
        // Nothing should ever be able to fire it: the commit applies the same
        // ops to the same handle the trial just succeeded against. It is here
        // because the ONE way the two can disagree is over the addressing —
        // this side stamps a scope, `ProjectDocument.addressed(_:)` stamps
        // one too, and a disagreement between them is invisible from a tool
        // result (measured, road map 2's phase 9: an explicit `scope` sent
        // while a DIFFERENT nest was open in the window was re-addressed to
        // the open one, failed in the core, put its message in a sheet the
        // agent cannot see, and the tool answered `ok`). That defect is
        // CLOSED — `addressed(_:)` now keeps a scope an op already carries,
        // so an explicit scope outranks the open view — and this guard is the
        // defence that survives it, because the two stamps still live in two
        // files. A tool that lies about an edit is worse than one that
        // refuses, so this refuses.
        guard document.project !== handle else {
            throw ToolError(
                message: "\(actionName) was accepted when it was tried but the document did "
                    + "not change, so nothing was edited. The ops as the document sent them "
                    + "were addressed differently from the ops that were tried — check the "
                    + "scope against what set_scope has open — and the project is untouched.")
        }
        return before
    }

    /// The canonical op-handler tail: `performGroupedEdit`, then the standard
    /// result — `ok`, whatever the handler wants to add, the ids the edit
    /// created, and the project summary.
    func editResult(
        _ document: ProjectDocument, _ actionName: String, _ ops: [ReelOp],
        _ fields: [String: Any] = [:]
    ) throws -> String {
        // A scoped edit changes nothing the `project` summary counts, so
        // without this an `ok` from inside a nest is indistinguishable from
        // an `ok` on the timeline that did nothing visible. What says WHERE
        // it landed is read off the ops as `addressed` STAMPS them and never
        // off the VIEW — `AgentServer+Scope.scopeLanding` is that account and
        // argues it, mixed edits included — and it is taken BEFORE the edit,
        // because how a call was addressed is a fact about the call. Nothing
        // is added with no scope anywhere, so no existing result grew a key.
        let landing = scopeLanding(ops, document)
        let before = try performGroupedEdit(document, actionName, ops)
        var result: [String: Any] = ["ok": true]
        result.merge(fields) { _, new in new }
        result.merge(Self.created(from: before, to: document.project.snapshot)) { _, new in new }
        result.merge(landing) { _, new in new }
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// The ids an edit ADDED, by kind. A split, a duplicate, a freeze frame
    /// and a detach all mint clips the caller then wants to name, and there is
    /// one FFI entry point for every op (spec §11) — so no op returns an id
    /// and the difference of the two snapshots is how they are reported.
    ///
    /// **Clips and tracks are counted across every container**, the
    /// timeline's and every nest's, which is `Project::every_clip()`'s rule
    /// in Swift and is what road map 2's phase 9 needed: a scoped `split`
    /// mints its two halves INSIDE a nest and a scoped `add_track` mints its
    /// track there, so a diff of the top level alone answered with nothing at
    /// all and left the caller to find them by reading the whole project
    /// back. Markers and media are deliberately still the top level's: a nest
    /// has neither, and both lists ARE the document's.
    ///
    /// It leaves every unscoped clip answer exactly as it was — `nest` moves
    /// its clips WHOLE, ids and all (`edit_nest.rs`), so the only new clip is
    /// still the nest clip it minted, and it comes first because the
    /// timeline's clips are concatenated ahead of the nests'. It does change
    /// ONE unscoped answer, and for the better: `nest` mints a fresh TRACK
    /// per source track inside the nest, and those ids — real ids in the
    /// document's one number space, which `set_track` and `move_track` can
    /// now name through a scope — used to be reported nowhere.
    static func created(from before: ProjectSnapshot, to after: ProjectSnapshot)
        -> [String: Any] {
        var result: [String: Any] = [:]
        func added<T: Identifiable>(_ old: [T], _ new: [T]) -> [Int] where T.ID == UInt32 {
            let existing = Set(old.map { $0.id })
            return new.map { $0.id }.filter { !existing.contains($0) }.map { Int($0) }
        }
        let clips = added(
            before.clips + before.nests.flatMap { $0.clips },
            after.clips + after.nests.flatMap { $0.clips })
        if !clips.isEmpty { result["new_clips"] = clips }
        let tracks = added(
            before.tracks + before.nests.flatMap { $0.tracks },
            after.tracks + after.nests.flatMap { $0.tracks })
        if !tracks.isEmpty { result["new_tracks"] = tracks }
        let markers = added(before.markers, after.markers)
        if !markers.isEmpty { result["new_markers"] = markers }
        let media = added(before.media, after.media)
        if !media.isEmpty { result["new_media"] = media }
        return result
    }

    // MARK: - Result encoding

    func callResult(content: [[String: Any]], isError: Bool) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["content": content, "isError": isError])
        return String(decoding: data, as: UTF8.self)
    }

    func jsonResult(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try callResult(
            content: [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
            isError: false)
    }

    private func errorResult(_ message: String) -> String {
        let content: [[String: Any]] = [["type": "text", "text": message]]
        let fallback = #"{"content":[{"type":"text","text":"tool failed"}],"isError":true}"#
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["content": content, "isError": true])
        else { return fallback }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A one-value box for an answer that crosses a `DispatchSemaphore`: the
/// off-main tools' only way to bring a main-thread (or background) result back
/// to the server thread they return on. The semaphore is the barrier, so no
/// lock is needed — the write happens-before the signal, the read after the
/// wait.
final class AgentBox<Value> {
    var value: Value?

    init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AgentBox does not support NSCoder")
    }
}

/// C callback for `RcAgentToolHandler`: hops to the main thread, executes, and
/// hands the result back as a core-owned string.
///
/// The seven `offMainTools` deliberately do NOT hop — they wait on work the
/// main thread has to perform, so taking it first would deadlock — and reach
/// the main thread through `AgentServer.onMain` instead.
private func agentToolTrampoline(
    _ context: UnsafeMutableRawPointer?,
    _ toolName: UnsafePointer<CChar>?,
    _ argumentsJSON: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let context = context, let toolName = toolName, let argumentsJSON = argumentsJSON
    else { return nil }
    let server = Unmanaged<AgentServer>.fromOpaque(context).takeUnretainedValue()
    let name = String(cString: toolName)
    let arguments = String(cString: argumentsJSON)
    let run = { server.execute(tool: name, argumentsJSON: arguments) }
    let result: String
    if AgentServer.offMainTools.contains(name) || Thread.isMainThread {
        // The header's contract is that this is called from the server
        // thread, which is what makes the off-main branch safe: an off-main
        // tool waits for the main thread, so taking it here would deadlock.
        result = run()
    } else {
        result = DispatchQueue.main.sync(execute: run)
    }
    return result.withCString { rc_agent_string_create($0) }
}
