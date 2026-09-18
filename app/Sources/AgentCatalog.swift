import Foundation

// MARK: - Catalog

/// The MCP tool catalog `AgentServer` registers with the core: every tool's
/// name, description, and JSON-Schema input. The names here must match
/// `AgentServer.handlers` exactly — `start()` checks the parity and traps in
/// debug builds, logs in Release — and every op tool's name and arguments must
/// match the op table in spec §6 and the module doc of `core/src/edit.rs`,
/// because those three spellings are one contract.
///
/// **Half of it is `AgentCatalog+Clips.swift`**, which holds the forty clip
/// rows, the five action rows and the patch vocabulary they alone are written
/// in. That cut is the size payment this file owed at 1552 lines against
/// app/CLAUDE.md's ~600 cap, taken BEFORE road map 2's phase 9 put a `scope`
/// on every op tool's schema and a `set_scope` beside them, and `catalogJSON()`
/// splices those rows back in at the point they were cut from, so the catalog's
/// ORDER is what it always was. What stayed here at that cut was the helper,
/// the two properties every op tool carries, and the eight other groups.
///
/// **The `scope` was the payment's whole point and it cost ONE line.** It is
/// injected in `tool` below, for every name the core calls an op, so the
/// fifty-seven rows on the other side of the cut got it without being touched
/// — which is what makes phase 9's diff over there empty and this file's
/// readable.
///
/// **The room was not enough, which is the warning this project keeps
/// re-learning** ("budget the cut against the pessimistic number", phase 6):
/// 665 at the cut and 781 with phase 9's `scope` property, `set_scope` row,
/// `opNames` and the guard on it, so the file was over the cap again, at
/// 807, and the second cut — named here in advance so nobody had to
/// re-derive it — was paid first and alone as road map 3's R1·toll: the
/// FILE groups — Media, Captions, Rendering and export — are
/// `AgentCatalog+Files.swift`, spliced the way the clip rows are, because
/// every row in them is about a path on disk. They took their six
/// file-only hoisted locals with them and share exactly ONE with the
/// groups that stay: `render_frame`'s `t` row reads `ticks`, as Projects
/// and Markers do, so `ticks` arrives there as an argument, as the clip
/// rows' three do. (The sentence that stood here said none was shared; it
/// was false by that one.) The move was about 400 lines, not the 300 this
/// paragraph guessed, and it leaves this file the helper, the project
/// group, tracks, markers and the canvas, at about 454.
extension AgentServer {
    /// One tool. Every tool gets `project` for free: with several projects
    /// open a call would otherwise be ambiguous, and the property costs
    /// nothing when only one is.
    ///
    /// Internal rather than private for one reason and no other:
    /// `AgentCatalog+Clips.swift` builds forty-five tools with it and
    /// `AgentCatalog+Files.swift` eleven, and `private` on an extension member
    /// reaches only its own file.
    func tool(
        _ name: String, _ description: String,
        _ properties: [String: Any], required: [String] = []
    ) -> [String: Any] {
        var schema = properties
        schema["project"] = Self.projectProperty
        // Road map 2's phase 9: every §6 OP also takes the envelope's
        // `scope`, and it is injected HERE for the reason `project` is —
        // one edit site instead of fifty-seven, and the op somebody adds in
        // phase 10 cannot arrive with a tool that silently lacks it.
        //
        // Op-ness is the CORE's answer (`Self.opNames`, read through
        // `rc_op_names`) and never a list kept in this file: the startup
        // parity check already reads that list to insist every op has a
        // tool, and a second spelling of it is exactly the drift this
        // file's contract exists to prevent. It also draws the line
        // correctly without an exception list — `detect_silence` and
        // `normalize_clip` are composites rather than ops, and
        // `AgentServer+Scope.swift` argues why neither takes a scope.
        //
        // It OVERWRITES a `scope` a caller wrote into `properties`, exactly
        // as `project` does. Nothing does today, and the near miss is worth
        // naming: `detect_silence` answers a RESULT key called `scope` —
        // which set of clips it measured — and takes no argument by that
        // name, so the two spellings never meet in one schema.
        if Self.opNames.contains(name) { schema["scope"] = Self.scopeProperty }
        return [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object", "properties": schema, "required": required,
            ] as [String: Any],
        ]
    }

    /// Every op the CORE declares, read once through `rc_op_names`
    /// (`ReelOp.coreNames()` → `OP_NAMES` in `core/src/edit.rs`).
    ///
    /// Three consumers, which is the whole reason it is hoisted out of
    /// `tool`: this file puts a `scope` on exactly these tools' schemas,
    /// `AgentServer.dispatch` reads a `scope` ARGUMENT for exactly these
    /// tools, and the startup parity check asks that each of them has a tool
    /// AND that the tool declares the property. One list, so the three
    /// cannot disagree — and a `static let`, so the FFI call and the JSON
    /// decode behind it happen once per process instead of seventy-five
    /// times per catalog build.
    ///
    /// **An empty answer is a silent catastrophe, so it is not allowed to be
    /// silent.** `coreNames()` answers `[]` when the FFI call or the decode
    /// fails, and an empty set here gives NO tool a `scope`, gives the
    /// dispatch nothing to read one for, and still builds a catalog in which
    /// every tool works — a server that starts clean and cannot reach inside
    /// a nest at all. `catalogJSON()` refuses to build on it (below); the
    /// parity check's own "the core reported no op names" is the second net
    /// and cannot be the first, because by the time it runs the catalog has
    /// been built and Release only logs.
    static let opNames: Set<String> = Set(ReelOp.coreNames())

    private static let projectProperty: [String: Any] = [
        "type": "string",
        "description": "Path of the open project to act on, as get_project reports it; omit "
            + "for the frontmost one.",
    ]

    /// The envelope's one non-argument key (spec §6's preamble,
    /// `core/src/scope.rs`), carried by every op tool and by nothing else.
    private static let scopeProperty: [String: Any] = [
        "type": "integer", "minimum": 0,
        "description": "Edit INSIDE a nest, by nest id — get_project lists them under nests, "
            + "and a nest clip's source.project names the one it shows. With it, every id in "
            + "this call — clips, tracks, actions — is looked up in THAT nest's own tracks "
            + "and clips instead of the timeline's, and every time is the nest's own, "
            + "measured from its zero (a nest has no speed, so the whole mapping is t minus "
            + "the nest clip's start); media ids are unaffected, because a nest shares the "
            + "document's media. The op itself is unchanged and one call is still one undo "
            + "step. Omit it to edit whatever the app has OPEN — the timeline, or the nest "
            + "set_scope entered, exactly as an edit made by hand goes where the window is "
            + "looking — so this argument is how you act on a container you are not looking "
            + "at, and get_project always says which one you are in. Seven ops have no "
            + "meaning inside a nest and refuse by name when you ask for one: add_marker, "
            + "set_marker, remove_marker, set_canvas, add_media, relink_media, remove_media. "
            + "Those seven behave DIFFERENTLY when the scope is inherited from set_scope "
            + "rather than asked for here, and the result says which: five of them, plus "
            + "set_marker's name / chapter / color and remove_marker, simply land on the "
            + "DOCUMENT and are named under document_ops. The two that carry a TIME — "
            + "add_marker, and set_marker with a time — are refused instead, because a "
            + "marker is at project time while the playhead inside a nest is not, so the "
            + "tick you would send means the wrong frame. Leave the nest (set_scope with "
            + "no arguments) or pass the tick in project time. "
            + "And read the result rather than assuming it landed: an edit can be perfectly "
            + "valid inside the nest and still be refused for the whole DOCUMENT's sake, "
            + "since the clip and track caps and the 8-deep nesting limit are counted across "
            + "every container at once.",
    ]

    /// The sentence every time argument carries. Ticks are the model's own
    /// unit (spec §5.1) and the only one the ops take.
    private static let ticksNote =
        "in TICKS — 600000 per second, so 1 s = 600000 and one 30 fps frame = 20000. "
        + "Rounded to the project's frame grid."

    func catalogJSON() throws -> String {
        // The op list is what puts a `scope` on every op tool's schema
        // (`tool` above), so an empty one builds a catalog that looks right
        // and cannot name a nest: every call carrying a scope would be
        // dropped on the way in and then refused as a clip id the timeline
        // has not got, which reads as a core bug rather than as a failed
        // FFI read. Refuse to build the catalog at all — `start()`
        // propagates this, so the server does not come up and the menu item
        // says why, which is a failure an operator can act on.
        guard !Self.opNames.isEmpty else {
            throw ToolFailure(
                message: "The core reported no op names (rc_op_names), so no tool could be "
                    + "given the scope argument that edits inside a nest. The agent server "
                    + "was not started.")
        }
        let ticks = Self.ticksNote
        let trackProperty: [String: Any] = [
            "type": "integer", "description": "Track id (get_project lists them).",
        ]
        // The two colour-only ARGUMENTS — `set_canvas`'s background and
        // `add_background`'s plate colour. FOUR numbers since deepening D1·4,
        // not three or four: the alpha is never filled in and a component
        // outside 0–1 is never clamped, because the core is the one validator
        // of a colour now and it names what it refused.
        let colorProperty: (String) -> [String: Any] = { role in
            [
                "type": "array", "items": ["type": "number"], "minItems": 4, "maxItems": 4,
                "description": "\(role) as [r, g, b, a], each 0–1. Four numbers exactly: "
                    + "three is refused by length and a component outside the range is "
                    + "refused by name, neither filled in nor clamped.",
            ]
        }
        let clipProperty: [String: Any] = [
            "type": "integer", "description": "Clip id (get_project lists them).",
        ]

        var catalog: [[String: Any]] = [

            // MARK: Projects

            tool(
                "open_project",
                "Opens a project and shows its window. Takes a .reelcut package, or any movie, "
                    + "sound file or picture — opening one of those builds a fresh UNTITLED "
                    + "project sized and rated to it with the file as the first clip on track 1, "
                    + "exactly as double-clicking it does. Answers already_open: true when that "
                    + "file is already open.",
                ["path": ["type": "string", "description": "Absolute or ~ path to the file."]],
                required: ["path"]),
            tool(
                "new_project",
                "Creates a blank 1920×1080 / 30 fps project and shows its window — File ▸ New "
                    + "Project. With path it is saved there straight away (a .reelcut extension "
                    + "is added if missing) so later calls can name it; without one it stays an "
                    + "untitled draft until save_project. Change the size and rate afterwards "
                    + "with set_canvas.",
                [
                    "path": [
                        "type": "string",
                        "description": "Where to save the new project, e.g. ~/Movies/Cut.reelcut.",
                    ]
                ]),
            tool(
                "save_project",
                "Saves the project. A project that has never been saved — a new_project with no "
                    + "path, or a movie opened as one — needs a path; passing a path always "
                    + "writes there (Save As). Returns once the package is really on disk.",
                [
                    "path": [
                        "type": "string",
                        "description": "Where to write the .reelcut package. Required the first "
                            + "time; otherwise the project is written back to its own file.",
                    ]
                ]),
            tool(
                "get_project",
                "The whole project as JSON: canvas (width, height, fps [num, den], background, "
                    + "fit_new_clips, timecode_frames), media, tracks, clips and markers, with "
                    + "next_id — the schema every op edits. Plus the state that is deliberately "
                    + "NOT in the model and lives only in the app: playhead, selection and the "
                    + "in/out range. Read this first: every other tool names things by the ids "
                    + "it reports, and clip, track, marker and media ids share ONE number space, "
                    + "so an id is unambiguous on its own. tracks[0] is the BACK of the layer "
                    + "stack (the bottom lane of the timeline); times are ticks at 600000 per "
                    + "second. missing_media lists media whose file has moved — relink_media "
                    + "points it at the new one.",
                [:]),
            tool(
                "set_playhead",
                "Moves the playhead and seeks the preview. View state, not an edit: nothing is "
                    + "undoable and the project is untouched. split, freeze_frame and add_marker "
                    + "default to this time.",
                ["t": ["type": "integer", "description": "Time \(ticks)"]],
                required: ["t"]),
            tool(
                "set_range",
                "Sets the in/out range — Mark ▸ Set In (I) and Set Out (O). View state, not an "
                    + "edit: nothing is undoable and the project is untouched. Call it with NO "
                    + "bounds to clear the range (⌥X). export {range: \"in_out\"} writes only "
                    + "this span; get_project reports it as in_out_range.",
                [
                    "start": ["type": "integer", "description": "In point, \(ticks)"],
                    "end": ["type": "integer", "description": "Out point, \(ticks)"],
                ]),
            tool(
                "set_selection",
                "Selects clips — clicking one in the timeline or on the canvas, and Edit ▸ "
                    + "Select All (⌘A). View state like the playhead and the range: nothing is "
                    + "undoable and the project is untouched. It matters because the canvas "
                    + "handles, crop mode and every inspector pane act on the SELECTION, so "
                    + "this is how you put the app into the state a screenshot should show. "
                    + "Call it with no clips (or []) to select nothing; get_project reports the "
                    + "result as selection. Note that the ops themselves take their own clips "
                    + "argument — selecting is not a prerequisite for editing.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"],
                        "description": "Clip ids to select (get_project lists them). Omit or "
                            + "pass an empty array to select nothing.",
                    ]
                ]),
            tool(
                "set_scope",
                "Opens a nest so the app is LOOKING INSIDE it — double-clicking a nest clip "
                    + "in the timeline (Clip ▸ Open Nest, ⌘↓; Close Nest, ⌘↑). View state "
                    + "like the playhead and the selection: no op runs, nothing is undoable "
                    + "and the project is untouched. What it changes is what the app shows "
                    + "and therefore what get_project and render_frame answer — while a nest "
                    + "is open those report and draw that nest's own tracks, clips and frozen "
                    + "canvas rather than the timeline's, which is the only way to SEE what "
                    + "an edit inside one did. Name the nest, or the clip that shows it; call "
                    + "it with neither to come back out. While a nest is open every op you "
                    + "send lands INSIDE it unless the op's own scope argument says "
                    + "otherwise, exactly as an edit made by hand goes where the window is "
                    + "looking — so this is the setting to change first and the one to "
                    + "clear when you are done. Editing inside a nest does not require it: "
                    + "an op carrying scope works from wherever you are.",
                [
                    "nest": [
                        "type": "integer",
                        "description": "The nest to open, by id (get_project lists them under "
                            + "nests). It has to be shown by a clip on the TIMELINE: this is "
                            + "the view, and the app cannot show its way into a nest the "
                            + "timeline does not reach — an op's own scope still can. Where "
                            + "two clips show one nest the earliest is entered, ties going to "
                            + "the lower id.",
                    ],
                    "clip": [
                        "type": "integer",
                        "description": "The nest CLIP to open — the precise spelling, and "
                            + "what a double-click sends: it names the nest and the start the "
                            + "times inside are measured from, which two clips showing one "
                            + "nest do not share. A clip that shows no nest is refused by "
                            + "name. Pass this or nest, not both.",
                    ],
                ]),
            tool(
                "undo",
                "Undoes one step — Edit ▸ Undo (⌘Z). Every tool that edits the project makes "
                    + "exactly one step, so one undo walks back exactly one call. Reports the "
                    + "name of the step it undid. View-state tools (set_playhead, set_range) "
                    + "make no step. Errors when there is nothing to undo.",
                [:]),
            tool(
                "redo",
                "Redoes one undone step — Edit ▸ Redo (⇧⌘Z). Any new edit clears the redo "
                    + "stack, exactly as in the app.",
                [:]),
        ]
        // The clip and action rows are `AgentCatalog+Clips.swift`'s, spliced in HERE
        // rather than appended, because the catalog's order is the order an agent reads
        // the tools in. The four locals it is handed are the ones a LATER group asks
        // for too — `clipProperty` is hoisted here for exactly that reason, since the
        // transition rows below take the same one — which is why they stayed on this
        // side of the cut.
        catalog += clipAndActionTools(
            ticks: ticks, trackProperty: trackProperty, colorProperty: colorProperty,
            clipProperty: clipProperty)
        // The two transition rows go HERE, beside `set_transition` and
        // `set_transition_duration` at the end of that group, and never at
        // the end of the catalog — `recording_probe.py` reads the last
        // eleven names, which are the FILE tools.
        catalog += transitionTools(ticks: ticks, clipProperty: clipProperty)
        catalog += [

            // MARK: Tracks

            tool(
                "add_track",
                "Adds an empty track. INDEX 0 IS THE BACK of the layer stack — the bottom lane "
                    + "of the timeline, drawn first — and tracks.count is the front, which is "
                    + "what ⇧⌘N adds and where an overlay belongs.",
                [
                    "index": [
                        "type": "integer", "minimum": 0,
                        "description": "Where in the stack (0 = back). Default: the front.",
                    ],
                    "name": ["type": "string", "description": "Track name, e.g. \"Titles\"."],
                ]),
            tool(
                "remove_track",
                "Removes a track. A track that still holds clips is refused unless with_clips "
                    + "is true, which removes them with it.",
                [
                    "track": trackProperty,
                    "with_clips": [
                        "type": "boolean",
                        "description": "Remove the track's clips too (default false).",
                    ],
                ], required: ["track"]),
            tool(
                "move_track",
                "Reorders the layer stack: the track moves to `index`, 0 being the back. A "
                    + "higher index draws in FRONT of the tracks below it.",
                [
                    "track": trackProperty,
                    "index": ["type": "integer", "minimum": 0, "description": "New position."],
                ], required: ["track", "index"]),
            tool(
                "set_track",
                "Renames a track or flips its four switches — the track header's toggles, "
                    + "Track ▸ Hide Video / Mute Audio / Lock Track / Solo. hidden drops its "
                    + "picture from the composition, muted its sound; locked keeps every ripple, "
                    + "insert and range edit off it; solo silences every OTHER track in its "
                    + "container (the timeline, or a nest's own tracks) that is not also soloed "
                    + "— mute wins on a track that is both, and pictures are untouched.",
                [
                    "track": trackProperty,
                    "name": ["type": "string"],
                    "hidden": ["type": "boolean"],
                    "muted": ["type": "boolean"],
                    "locked": ["type": "boolean"],
                    "solo": ["type": "boolean"],
                ], required: ["track"]),
            tool(
                "remove_empty_tracks",
                "Removes every track that holds no clips — Track ▸ Remove Empty Tracks.",
                [:]),

            // MARK: Markers

            tool(
                "add_marker",
                "Drops a marker on the timeline. Markers snap to frames and two may not share a "
                    + "time, so a second marker on the same frame is refused. A chapter marker "
                    + "also becomes a chapter in the exported file (M2).",
                [
                    "at": [
                        "type": "integer",
                        "description": "Where, \(ticks) Default: the playhead.",
                    ],
                    "name": ["type": "string"],
                    "chapter": [
                        "type": "boolean",
                        "description": "Also a chapter of the exported movie (default false).",
                    ],
                    "color": [
                        "type": "string",
                        "description": "Colour NAME, e.g. \"red\" — not a hex string.",
                    ],
                ]),
            tool(
                "set_marker",
                "Moves or renames a marker, or changes its colour or chapter flag.",
                [
                    "marker": ["type": "integer", "description": "Marker id."],
                    "time": ["type": "integer", "description": "New time, \(ticks)"],
                    "name": ["type": "string"],
                    "chapter": ["type": "boolean"],
                    "color": ["type": "string", "description": "Colour name."],
                ], required: ["marker"]),
            tool(
                "remove_marker", "Removes a marker.",
                ["marker": ["type": "integer", "description": "Marker id."]],
                required: ["marker"]),

            // MARK: Canvas

            tool(
                "set_canvas",
                "Changes the project's canvas — the fixed frame every clip is composited into. "
                    + "rescale_clips multiplies every clip's x, y and scale by the size ratio, "
                    + "which is what keeps a layout looking the same when you resize; without "
                    + "it the clips keep their pixel positions. Changing fps re-snaps every clip "
                    + "start and duration to the new frame grid.",
                [
                    "width": ["type": "integer", "minimum": 16, "maximum": 16384],
                    "height": ["type": "integer", "minimum": 16, "maximum": 16384],
                    "fps": [
                        "type": "array", "items": ["type": "integer"], "minItems": 2,
                        "maxItems": 2,
                        "description": "Frame rate as [numerator, denominator]: [30, 1], "
                            + "[30000, 1001] for 29.97, [24000, 1001] for 23.976.",
                    ],
                    "background": colorProperty("Colour behind every layer"),
                    "rescale_clips": [
                        "type": "boolean",
                        "description": "Scale every clip's placement with the canvas "
                            + "(default false).",
                    ],
                    "fit_new_clips": [
                        "type": "boolean",
                        "description": "Give a new clip Fit scale when its source is bigger "
                            + "than the canvas.",
                    ],
                    "timecode_frames": [
                        "type": "boolean",
                        "description": "Show times as HH:MM:SS:FF rather than HH:MM:SS.mmm.",
                    ],
                ]),
        ]
        // The file rows — Media, Captions, Rendering and export — are
        // `AgentCatalog+Files.swift`'s. They are the catalog's LAST three
        // groups, so this splice is an append and the order is unchanged;
        // `ticks` is the one local they share with the groups above.
        catalog += fileTools(ticks: ticks)
        let data = try JSONSerialization.data(withJSONObject: catalog)
        return String(decoding: data, as: UTF8.self)
    }
}
