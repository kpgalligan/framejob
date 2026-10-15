import AppKit

/// Editing INSIDE a nest over MCP, and looking inside one: the envelope's
/// `scope` (spec §6, `core/src/scope.rs`) and the `set_scope` tool that
/// mirrors the double-click (road map 2's phase 9).
///
/// **The whole surface is arguments on tools that already existed.** No op
/// was added — `rc_op_names` was unchanged — so the catalog grew one property,
/// injected once in `AgentCatalog.tool` for every name the core calls an op,
/// and one tool, which is not an op either. What that buys is the thing the
/// spec designed and left (§4.4): every row of §6 can now name a clip, a
/// track or an action inside a nest.
///
/// Three pieces, and the split between them is the point:
///
///  - **The scope is read ONCE, at the dispatch.** `AgentServer.dispatch` is
///    the only place holding both a tool's name and its arguments for all
///    seventy-five of them, so it reads `scope` there and leaves it on
///    `callScope` for the length of the call; `performGroupedEdit` stamps it
///    onto every op through `addressed` below. Fifty-eight handlers were not
///    touched and cannot forget.
///  - **The id readers resolve against a CONTAINER.** `idScope` below is what
///    `clipArg`, `clipsArg`, `optionalClipsArg` and `trackArg` ask, so
///    `trim_start {clip: <inside the nest>, scope: 4}` finds its clip instead
///    of being refused by the app before the core ever saw the scope. That
///    was the real work of this phase on this side, and the road map does not
///    mention it.
///  - **`set_scope` is view state and edits nothing**, exactly like
///    `set_playhead`, `set_range` and `set_selection`. It exists because
///    `get_project` and `render_frame` answer about what the app is LOOKING
///    at, and without it there was no way to make them look inside. An op
///    sent while it is open follows it unless it carries a `scope` of its
///    own — `effectiveScope` below is that rule and argues it.
///
/// **Two composites take no scope ARGUMENT and still work inside a nest**,
/// and the ops-only injection rule excludes them without an exception list:
/// `detect_silence` and `normalize_clip` are not §6 rows. They follow the
/// VIEW instead, from both ends at once — their ids resolve through
/// `idScope` like every other tool's, and `SilenceDetector.read` /
/// `AudioNormalize.read` compute from `ProjectDocument.editedProject`'s plan,
/// which is the same container — so the pair is coherent rather than half
/// converted. What they cannot do is be pointed at a nest nobody is looking
/// at, and that is the argument for leaving it there: each one measures a
/// PLAN, the app memoises exactly one scoped handle (the open one), and a
/// per-call `scope` would mean building a second project per call and
/// mapping every tick in the answer back out of it. Nothing is lost that a
/// caller cannot reach — `set_scope`, then ask — and `ripple_delete_ranges`,
/// which is what `detect_silence`'s answer is fed to, takes a scope like any
/// other op.
///
/// There is also a spelling hazard here worth naming, since it is the reason
/// to think twice before changing that: `detect_silence` already answers a
/// RESULT key called `scope`, meaning which set of CLIPS it measured.
/// Nothing keeps those two words apart but the fact that one is an input and
/// the other an answer, so a `detect_silence` that ever took the envelope's
/// scope would have to say in both descriptions which is which.
///
/// **The captions group used to be the one place this did NOT line up, and
/// the way it was settled is the rule for the next producer.** Every one of
/// them — `CaptionImporter.plan(for:in:)`, `Transcriber`,
/// `TranscribeSheetController` and `CaptionExporter`, on the File-menu path
/// and the tool path alike — built its plan from `document.project`, the
/// DOCUMENT, while the ops that plan produced were addressed to whatever nest
/// was open, here and in `ProjectDocument.addressed(_:)` alike. So with a nest
/// open they measured a placement against the timeline and then placed it
/// inside the nest, and the menu item had exactly the same defect as the tool.
/// All four read `editedProject` now, as `SilenceDetector` and
/// `AudioNormalize` do. **A producer reads the container it writes into** —
/// that is the whole rule, it is cheaper than making the ops document-level,
/// and it is what a fifth producer should copy.
extension AgentServer {

    // MARK: - The call's scope

    /// Refuses a `scope` that names no nest in `document`, by name.
    ///
    /// Called from `target(_:)`, which every handler passes through before it
    /// reads a single argument, so the ORDER `core/src/scope.rs` documents
    /// holds on this side too: an unknown nest is answered FIRST, ahead of
    /// the op's own arguments, because it is the argument that decides which
    /// container the caller thinks it is editing.
    ///
    /// The sentence is the CORE's, word for word, with the app's own
    /// direction added after it. Both layers can answer this — the app for
    /// every op tool, the core for anything that reaches it another way — and
    /// a caller (or a proof) that learns one spelling should not have to
    /// learn a second.
    func checkCallScope(_ document: ProjectDocument) throws {
        guard let scope = callScope else { return }
        guard document.project.snapshot.nest(scope) != nil else {
            throw ToolError(
                message: "no nest with id \(scope). get_project lists them under nests, and a "
                    + "nest clip's source.project names the one it shows.")
        }
    }

    /// The container this call's id arguments resolve in: the timeline, or
    /// the nest the envelope's `scope` named.
    ///
    /// It reads the PARENT snapshot rather than building a scoped handle,
    /// which is the cheap half of `core/src/scope.rs`'s view and the only
    /// half an id lookup needs: a nest holds its tracks and clips in the
    /// parent's one id space (spec §5.2), so `snapshot.nests[]` already has
    /// them. `NestScope` next door reads the path the same way and for the
    /// same reason.
    /// The nest a call is really acting in: its own `scope` when it has one,
    /// else the nest the APP has open (`set_scope`), else nil.
    ///
    /// **The argument overrides the view; an absent argument follows it.**
    /// That is the whole rule, and it is the one that makes every other piece
    /// agree with itself. `get_project` reports the open container, so the
    /// ids a caller reads back are that container's; `render_frame` draws it;
    /// `detect_silence`, `normalize_clip` and `sync_audio` compute from
    /// `ProjectDocument.editedProject`'s plan, which is that container's too;
    /// and `ProjectDocument.addressed(_:)` already stamps the open nest onto
    /// every op the APP sends, so an agent that inherits it is doing exactly
    /// what the person at the keyboard does. The alternative — the argument
    /// or nothing — was written first and thrown away: it made
    /// `get_project` list clips that the very next op could not name, and it
    /// would have left the three composites resolving their ids in one
    /// container and reading their plan from another.
    ///
    /// What it costs is the spelling of "edit the timeline while I am looking
    /// inside a nest", which is now `set_scope` with no arguments first. That
    /// is the same thing the UI costs a person, and it is worth less than the
    /// coherence.
    func effectiveScope(_ document: ProjectDocument) -> UInt32? {
        callScope ?? document.scope
    }

    /// The container this call's id arguments resolve in — `effectiveScope`'s
    /// nest, or the timeline.
    ///
    /// It reads the PARENT snapshot rather than building a scoped handle,
    /// which is the cheap half of `core/src/scope.rs`'s view and the only
    /// half an id lookup needs: a nest holds its tracks and clips in the
    /// parent's one id space (spec §5.2), so `snapshot.nests[]` already has
    /// them. `NestScope` next door reads the path the same way and for the
    /// same reason.
    func idScope(_ document: ProjectDocument) throws -> AgentIdScope {
        let snapshot = document.project.snapshot
        guard let scope = effectiveScope(document) else {
            return AgentIdScope(
                nest: nil, clips: snapshot.clips, tracks: snapshot.tracks, fromArgument: false)
        }
        // Unreachable through `target(_:)`, which has already refused an
        // unknown `scope` argument, and through `clampViewState`, which
        // clears a view path whose nest has gone. It is here so the function
        // is total rather than optional-returning: a reader that fell back to
        // the timeline when the nest was missing would answer "No clip has id
        // 17" for a call whose real mistake was the scope.
        guard let nest = snapshot.nest(scope) else {
            try checkCallScope(document)
            return AgentIdScope(
                nest: nil, clips: snapshot.clips, tracks: snapshot.tracks, fromArgument: false)
        }
        return AgentIdScope(
            nest: nest, clips: nest.clips, tracks: nest.tracks, fromArgument: callScope != nil)
    }

    /// The scope stamped onto the ops of one agent edit — `performGroupedEdit`
    /// in the frozen file calls this, and it is the MCP mirror of
    /// `ProjectDocument.addressed(_:)`.
    ///
    /// **Two rules, and the difference between them is deliberate.** An
    /// EXPLICIT `scope` is stamped on every op, the seven document-level ones
    /// included, so an agent that asks for `add_media {scope: 4}` gets the
    /// core's own refusal by name rather than a silent redirection — it asked
    /// a question and the answer is no (`ReelOp.documentLevelNames` argues
    /// the other half of this). An INHERITED one skips them, exactly as
    /// `addressed` does, because a Finder drop inside a nest is an
    /// `add_media` on the document's one media list plus an `add_clip` in the
    /// nest, and an agent's `import_media` inside a nest is the same act.
    ///
    /// **Two of those seven may not be sent that way at all**, and
    /// `checkDocumentLevelTicks` below is the refusal: `add_marker` and a
    /// `set_marker` carrying a `time` would reach the timeline's `markers[]`
    /// at a tick the caller measured from the NEST's zero. Read the two
    /// together — this method decides which container an op is addressed to,
    /// and that one decides which ops may take the unscoped answer.
    ///
    /// It mirrors that method rather than calling it because `addressed` is
    /// private to `ProjectDocument` — but the two must not drift, and the
    /// reason is not tidiness: `AgentServer.performGroupedEdit` TRIES the ops
    /// on the handle first, purely, to turn a refusal into a message instead
    /// of a beep, and a trial addressed differently from the commit would
    /// report a failure the commit would not have had.
    func addressed(_ ops: [ReelOp], _ document: ProjectDocument) -> [ReelOp] {
        if let scope = callScope { return ops.map { $0.scoped(scope) } }
        guard let view = document.scope else { return ops }
        return ops.map { $0.isDocumentLevel ? $0 : $0.scoped(view) }
    }

    /// Refuses the ops an INHERITED scope would send at a tick measured from
    /// the wrong zero — `add_marker`, and `set_marker`'s `time`.
    ///
    /// **This is the tool path's copy of a decision the app made first.**
    /// `addressed` above sends the seven document-level ops UNSCOPED out of a
    /// scope it inherited, so `core/src/scope.rs`'s `refused_inside` never
    /// fires for them and they land on the document. For five of the seven
    /// that is exactly right, and it is why File ▸ Add Media…, a Relink, a
    /// Remove and the Document tab's canvas rows all go on working with a nest
    /// open. For the two that carry a TICK it is a wrong PLACEMENT reported as
    /// success: while a scope is open `ProjectDocument.playhead` is
    /// NEST-LOCAL, `get_project` answers the nest's clips and duration,
    /// `set_playhead` writes the nest's own time and `render_frame` draws the
    /// nest — so a caller working in the open container hands over a
    /// nest-local tick and the marker appears somewhere else on the timeline,
    /// with an `ok` on it. The app decided this already:
    /// `EditorViewController+NestScope.validateNestScopeAction` greys Add
    /// Marker out inside a nest and `addMarkerCommand` carries its own guard
    /// for the bare-M key, both for this exact reason. This is that refusal,
    /// worded for a caller who gets a sentence rather than a dead menu item.
    ///
    /// **`remove_marker` is deliberately NOT here, and neither is a
    /// `set_marker` that carries no `time`.** Both name an id and read no
    /// clock, so there is no zero for either to be measured from — and both
    /// are LIVE in the app with a nest open, in the Document tab's marker
    /// table, which is about the FILE and reads `documentSnapshot` for that
    /// very reason (app/CLAUDE.md). Refusing them would make these tools less
    /// of a mirror of the UI than they already are, and would charge a rename
    /// two `set_scope` calls and a re-entry for nothing. That the marker id is
    /// the DOCUMENT's is already settled and already said: `markerArg` resolves
    /// it against the timeline's markers on purpose, so that the core's own
    /// sentence rather than "No marker has id 12" is what a scoped call hears.
    ///
    /// An EXPLICIT `scope` is left alone. It is stamped on all seven and the
    /// core answers `"add_marker has no meaning inside nest N"` by name, which
    /// is the designed answer to a caller that asked the question outright
    /// (`addressed`'s two rules, and `ReelOp.documentLevelNames`).
    ///
    /// It is called from `AgentServer.performGroupedEdit` — the one place
    /// every editing tool passes through, the handlers that call it directly
    /// rather than through `editResult` included — so no handler has to
    /// remember it and a later composite that builds a marker op inherits it.
    /// What being there rather than at the two handlers' heads costs is the
    /// ORDER of one refusal: a call whose `at` is ALSO unreadable hears about
    /// the `at` first, because the handler reads its arguments before it
    /// reaches the edit. That is a true complaint either way, which is what
    /// makes it a fair price here and not in `checkCallScope`'s case — there
    /// the mistake being reported is which document the caller thinks it is
    /// editing, and it outranks everything.
    func checkDocumentLevelTicks(_ ops: [ReelOp], _ document: ProjectDocument) throws {
        guard callScope == nil, let view = document.scope else { return }
        for op in ops {
            switch op.name {
            case "add_marker":
                throw ToolError(
                    message: "add_marker has no meaning inside nest \(view): a nest has no "
                        + "markers, and every tick in this call is measured from that nest's "
                        + "own zero, so the marker would land somewhere else on the timeline. "
                        + "set_scope with no arguments comes back out; then add_marker at a "
                        + "project time. The app greys Add Marker out in here for the same "
                        + "reason.")
            case "set_marker" where op.args["time"] != nil:
                throw ToolError(
                    message: "set_marker's time has no meaning inside nest \(view): a marker's "
                        + "time is the timeline's, and every tick in this call is measured "
                        + "from that nest's own zero. set_scope with no arguments comes back "
                        + "out; then set_marker at a project time. Its name, chapter and color "
                        + "mean the same thing in either container and are accepted in here, "
                        + "which is what the Document tab's marker table does with a nest "
                        + "open.")
            default:
                continue
            }
        }
    }

    /// Where an edit's ops actually LANDED, as the result reports it: the nest
    /// whose id was stamped on them, and the names of any that went to the
    /// document instead.
    ///
    /// **It is read off what `addressed` STAMPS and never off
    /// `effectiveScope`**, and that difference is the whole reason it exists.
    /// `editResult` used to echo the effective scope unconditionally, which is
    /// a statement about the VIEW; `addressed` sends the seven document-level
    /// ops unscoped out of an inherited one, which is a statement about the
    /// EDIT. So a `remove_media`, a `set_canvas` or a marker rename sent with
    /// a nest open reported that it had landed inside that nest when it had
    /// landed on the document — a tool misreporting WHERE an edit went, which
    /// is the class of defect this phase already fixed once at the merge seam
    /// (`performGroupedEdit`'s closing guard).
    ///
    /// **The MIXED edit is why `document_ops` is a list and not a flag.** One
    /// edit can legitimately span both containers — a Finder drop inside a
    /// nest is `add_media` on the document plus `add_clip` in the nest, as ONE
    /// undo step (`ReelOp.documentLevelNames` argues it) — and there is no
    /// single number that describes that, which is exactly the mistake being
    /// fixed. So both halves are named: `scope` is the nest the scoped ops
    /// carried and `document_ops` is every op that skipped it, and a result
    /// carrying both says which of its ops went where. No tool sends such a
    /// mix TODAY — an agent's `import_media` and `add_clip` are two calls, and
    /// `add_background`'s Image… composite is the menu's rather than the
    /// tool's — but the account has to be right before the composite that does
    /// arrives, and nobody reading one of these results should have to know
    /// which handlers mix and which do not.
    ///
    /// With no scope anywhere it answers nothing at all, so every ordinary
    /// result is byte for byte the one it always was.
    func scopeLanding(_ ops: [ReelOp], _ document: ProjectDocument) -> [String: Any] {
        guard effectiveScope(document) != nil else { return [:] }
        let stamped = addressed(ops, document)
        var result: [String: Any] = [:]
        // Uniform by construction: `addressed` stamps ONE scope on every op it
        // stamps at all, so the first one found is the answer for all of them.
        if let nest = stamped.compactMap({ $0.scope }).first { result["scope"] = Int(nest) }
        let onDocument = stamped.filter { $0.scope == nil }.map { $0.name }
        if !onDocument.isEmpty { result["document_ops"] = onDocument }
        return result
    }

    // MARK: - The startup parity check's fourth part

    /// Part 4 of `AgentServer.catalogParityFailure`: every OP tool declares
    /// the envelope's `scope`.
    ///
    /// **It is here because parts 1 to 3 cannot see an OMISSION.** They
    /// compare name SETS and read each schema's shape, so a tool that quietly
    /// lacks an argument passes all three — and a scope-less op tool is
    /// exactly that: the server starts clean, the op works on the timeline,
    /// and editing inside a nest is unreachable through it with nothing
    /// anywhere saying so. `AgentCatalog.tool`'s injection makes that hard to
    /// do by hand, but the fifty-sixth op arriving with a hand-written schema,
    /// or an `opNames` that came back short, both land here.
    ///
    /// It reads the CATALOG rather than asking whether the injection ran,
    /// which is the only way it can catch anything: a check that asked
    /// `AgentCatalog.tool` about itself would be testing the check. Members
    /// of `opsWithoutTools` are skipped for part 2's reason — there is no
    /// tool to declare anything. It costs nothing to run: the tools array is
    /// already parsed and the op list already read.
    static func scopeFailure(_ tools: [[String: Any]], _ ops: Set<String>) -> String? {
        let scopeless =
            tools
            .filter { tool in
                guard let name = tool["name"] as? String, ops.contains(name) else { return false }
                let properties = (tool["inputSchema"] as? [String: Any])?["properties"]
                    as? [String: Any]
                return properties?["scope"] == nil
            }
            .compactMap { $0["name"] as? String }.sorted()
        guard scopeless.isEmpty else {
            return "these op tools do not declare scope: \(scopeless) — every row of spec §6 "
                + "can be sent inside a nest (core/src/scope.rs), and a tool that does not "
                + "say so is one an agent cannot use in there"
        }
        return nil
    }

    // MARK: - set_scope

    /// `set_scope` — double-clicking a nest clip, Clip ▸ Open Nest (⌘↓) and
    /// Clip ▸ Close Nest (⌘↑) (`EditorViewController+NestScope.swift`).
    ///
    /// View state like the playhead, the range and the selection: no op runs,
    /// nothing is undoable and the project is untouched. What it moves is
    /// what `get_project` reports and `render_frame` draws, which is the only
    /// way an agent can SEE what an edit inside a nest did.
    ///
    /// **It is ABSOLUTE**, like the other three `set_` tools: the argument
    /// names where to BE, not a step to take, so `set_scope {clip: 41}` means
    /// the same thing from the timeline and from three levels down. That is
    /// what makes it usable without first reading the current scope back —
    /// and it is why `clip` accepts a nest clip in ANY container, since the
    /// path down to a given id is determined (one id space, and a nest cannot
    /// show itself at any remove).
    func setScope(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let path = try nestScopePath(a, document)
        applyNestScope(path, document)
        var result: [String: Any] = ["ok": true]
        result.merge(scopeReport(document)) { _, new in new }
        result["playhead"] = document.playhead
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// `set_scope`'s two arguments read into the path they name.
    ///
    /// `nest` and `clip` are two spellings of one destination and at most one
    /// may be given; neither means the timeline. They are not interchangeable
    /// and the tool says so: `clip` names the nest AND the start the times
    /// inside are measured from, which is what a double-click has and what
    /// two clips showing one nest do not share, while `nest` is the number an
    /// op's own `scope` takes and is the one an agent already has in its
    /// hand.
    private func nestScopePath(_ a: [String: Any], _ document: ProjectDocument) throws
        -> [NestScopeStep]
    {
        let snapshot = document.project.snapshot
        let wantsNest = a["nest"] != nil && !(a["nest"] is NSNull)
        let wantsClip = a["clip"] != nil && !(a["clip"] is NSNull)
        guard !(wantsNest && wantsClip) else {
            throw ToolError(
                message: "Pass nest or clip, not both — they are two spellings of one "
                    + "destination, and clip is the precise one.")
        }
        if wantsClip {
            let id = try idArg(a, "clip")
            guard let path = Self.pathToClip(id, in: snapshot) else {
                throw ToolError(
                    message: "No clip has id \(id), in this timeline or in any of its nests. "
                        + "get_project lists the clips, and each nest's own under nests.")
            }
            guard let clip = NestScope.clips(in: path, of: snapshot)
                .first(where: { $0.id == id }), let nest = clip.source.nestID
            else {
                throw ToolError(
                    message: "Clip \(id) does not show a nest, so there is nothing to open "
                        + "inside it. A nest clip's source.kind is \"nest\".")
            }
            return path + [NestScopeStep(nest: nest, clip: id)]
        }
        if wantsNest {
            let id = try idArg(a, "nest")
            guard snapshot.nest(id) != nil else {
                throw ToolError(
                    message: "no nest with id \(id). get_project lists them under nests.")
            }
            // The earliest TIMELINE clip that shows it, ties to the lower id.
            // A nest shown only from INSIDE another nest is refused rather
            // than guessed at: this is the view, and the app's way in is a
            // clip you can point at. `clip` reaches it, and so does an op's
            // own scope, which needs no view at all.
            guard let entry = snapshot.clips
                .filter({ $0.source.nestID == id })
                .min(by: { ($0.start, $0.id) < ($1.start, $1.id) })
            else {
                throw ToolError(
                    message: "No clip on the timeline shows nest \(id), so the view cannot "
                        + "reach it in one step. Name the nest CLIP instead — set_scope "
                        + "{clip: <id>} works at any depth — or send the op itself with "
                        + "scope: \(id), which needs no view.")
            }
            return [NestScopeStep(nest: id, clip: entry.id)]
        }
        return []
    }

    /// The path from the timeline down to whichever container holds `clip`,
    /// or nil when no container does.
    ///
    /// A breadth-first walk over the containers, with the nests it has
    /// entered remembered: `check_nesting` refuses a cycle, so the visited
    /// set is belt and braces against a hand-written file rather than against
    /// anything the ops can make — but a walk that can be handed a project
    /// from disk does not get to assume the file is sane.
    private static func pathToClip(_ clip: UInt32, in snapshot: ProjectSnapshot)
        -> [NestScopeStep]?
    {
        var queue: [[NestScopeStep]] = [[]]
        var seen: Set<UInt32> = []
        while !queue.isEmpty {
            let path = queue.removeFirst()
            let clips = NestScope.clips(in: path, of: snapshot)
            if clips.contains(where: { $0.id == clip }) { return path }
            for candidate in clips {
                guard let nest = candidate.source.nestID, seen.insert(nest).inserted else {
                    continue
                }
                queue.append(path + [NestScopeStep(nest: nest, clip: candidate.id)])
            }
        }
        return nil
    }

    /// Moves the document to `path`, through the editor's own gestures where
    /// there is an editor.
    ///
    /// **The gestures are reused rather than re-derived**, which matters
    /// because entering maps the playhead (`t − nest_clip.start`) and leaving
    /// maps it back and re-selects the clip: leave to the common prefix, then
    /// enter one step at a time, and an agent's scope change is the same
    /// event as a person's double-click — the player seeked, the timeline
    /// scrolled, the breadcrumb redrawn.
    ///
    /// A windowless document (which an agent can make) has no gestures, so it
    /// gets `setNestPath` directly with the playhead mapped through
    /// `NestScope.offset` — the same sum `enterNest` arrives at one clip
    /// start at a time, which is why the two cannot disagree.
    private func applyNestScope(_ path: [NestScopeStep], _ document: ProjectDocument) {
        guard path != document.nestPath else { return }
        let snapshot = document.project.snapshot
        guard let editor = editor(document) else {
            let project = document.playhead + NestScope.offset(of: document.nestPath, in: snapshot)
            let inside = max(0, project - NestScope.offset(of: path, in: snapshot))
            // Coming OUT re-selects the nest clip that was entered, the way
            // `leaveNest` does; going in selects nothing, the way `enterNest`
            // does. "Coming out" is the case where the new path is a proper
            // prefix of the old one.
            let shared = Self.commonPrefix(document.nestPath, path)
            let selection: Set<UInt32> =
                path.count == shared && document.nestPath.count > shared
                ? [document.nestPath[shared].clip] : []
            document.setNestPath(path, playhead: inside, selection: selection)
            return
        }
        editor.leaveAllNests(to: Self.commonPrefix(document.nestPath, path))
        for step in path.dropFirst(document.nestPath.count) {
            guard let clip = NestScope.clips(in: document.nestPath, of: snapshot)
                .first(where: { $0.id == step.clip })
            else { break }
            editor.enterNest(clip)
        }
    }

    /// How many leading steps two paths share.
    private static func commonPrefix(_ a: [NestScopeStep], _ b: [NestScopeStep]) -> Int {
        var shared = 0
        while shared < a.count, shared < b.count, a[shared] == b[shared] { shared += 1 }
        return shared
    }

    /// The scope as `get_project` and `set_scope` both report it.
    ///
    /// `scope` is the NEST id and nothing else, because it is the number an
    /// op's own `scope` argument takes: a caller copies it straight across.
    /// The clip it was entered through and the whole trail ride beside it
    /// under their own names, and the whole group is `{"scope": null}` at the
    /// timeline rather than absent, so "not in a nest" is an answer rather
    /// than a missing key.
    func scopeReport(_ document: ProjectDocument) -> [String: Any] {
        guard let step = document.nestPath.last else { return ["scope": NSNull()] }
        let snapshot = document.project.snapshot
        let names = NestScope.names(of: document.nestPath, in: snapshot)
        let trail = document.nestPath.enumerated().map { index, step -> [String: Any] in
            // `names` opens with "Timeline", so a step's own name is one
            // further along than its index.
            ["nest": Int(step.nest), "clip": Int(step.clip), "name": names[index + 1]]
        }
        return [
            "scope": Int(step.nest),
            "scope_clip": Int(step.clip),
            "scope_path": trail,
        ]
    }
}

/// The container a call's id arguments are looked up in — the timeline, or
/// the nest the envelope's `scope` named.
///
/// It is a value rather than a `ProjectSnapshot` of the view because an id
/// lookup wants two lists and nothing else: assembling a whole view snapshot
/// per reader would mean a second Swift spelling of `scoped_view`'s table
/// (the canvas, the media, the emptied nest row) whose only reader compares
/// integers. `core/src/scope.rs` owns that table, and it owns it alone.
struct AgentIdScope {
    /// nil on the timeline.
    let nest: NestSnapshot?
    let clips: [ClipSnapshot]
    let tracks: [TrackSnapshot]
    /// Whether the nest came from the call's own `scope` or from the nest the
    /// app has open. It changes nothing about the lookup and one thing about
    /// the message: how to get back to the timeline is a different sentence
    /// for each.
    let fromArgument: Bool

    func clip(_ id: UInt32) -> ClipSnapshot? { clips.first { $0.id == id } }
    func track(_ id: UInt32) -> TrackSnapshot? { tracks.first { $0.id == id } }

    /// One track's clips in timeline order — `ProjectSnapshot.clips(onTrack:)`
    /// asked of this container instead of the document, which is what
    /// `remove_track`'s "still holds N clips" has to count inside a nest.
    func clips(onTrack id: UInt32) -> [ClipSnapshot] {
        clips.filter { $0.track == id }.sorted { $0.start < $1.start }
    }

    /// "No clip has id 17. get_project lists the clips." — and inside a
    /// scope, the same sentence saying WHERE it looked.
    ///
    /// The unscoped spelling is byte for byte the one every one of these
    /// readers has answered since M2, deliberately: it is what the tools'
    /// own descriptions promise and what several proof scripts match on.
    ///
    /// The scoped one ends by saying how to get OUT, which is a different
    /// sentence depending on how the call got in — dropping an argument does
    /// nothing about a nest the window has open, and closing the nest does
    /// nothing about an argument.
    func noSuchId(_ kind: String, _ id: UInt32) -> String {
        guard let nest = nest else {
            return "No \(kind) has id \(id). get_project lists the \(kind)s."
        }
        let out =
            fromArgument
            ? "drop the scope to name one on the timeline"
            : "that nest is OPEN in the view, so ids mean its own — set_scope with no "
                + "arguments comes back out"
        return "No \(kind) has id \(id) inside nest \(nest.id). get_project lists that nest's "
            + "\(kind)s under nests; \(out)."
    }
}
