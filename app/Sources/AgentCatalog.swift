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
/// ORDER is what it always was. What stayed here is the helper, the two
/// properties every op tool carries, and the eight other groups.
///
/// **The `scope` was the payment's whole point and it cost ONE line.** It is
/// injected in `tool` below, for every name the core calls an op, so the
/// fifty-five rows on the other side of the cut got it without being touched
/// — which is what makes phase 9's diff over there empty and this file's
/// readable.
///
/// **The room was not enough, which is the warning this project keeps
/// re-learning** ("budget the cut against the pessimistic number", phase 6):
/// 665 at the cut and 781 with phase 9's `scope` property, `set_scope` row,
/// `opNames` and the guard on it, so the file is over the cap again and this
/// is where the debt is written down rather than left to be discovered. The
/// next cut is named in advance so nobody has to re-derive it: the FILE
/// groups — Media, Captions, Rendering and export — go to an
/// `AgentCatalog+Files.swift`, spliced the way the clip rows are, because
/// every row in them is about a path on disk and none of them shares a
/// hoisted local with the groups that stay. It is about 300 lines and would
/// leave this file the helper, the project group, tracks, markers and the
/// canvas.
extension AgentServer {
    /// One tool. Every tool gets `project` for free: with several projects
    /// open a call would otherwise be ambiguous, and the property costs
    /// nothing when only one is.
    ///
    /// Internal rather than private for one reason and no other:
    /// `AgentCatalog+Clips.swift` builds forty-five tools with it, and
    /// `private` on an extension member reaches only its own file.
    func tool(
        _ name: String, _ description: String,
        _ properties: [String: Any], required: [String] = []
    ) -> [String: Any] {
        var schema = properties
        schema["project"] = Self.projectProperty
        // Road map 2's phase 9: every §6 OP also takes the envelope's
        // `scope`, and it is injected HERE for the reason `project` is —
        // one edit site instead of fifty-five, and the op somebody adds in
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
    /// decode behind it happen once per process instead of seventy-four
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
        let colorProperty: (String) -> [String: Any] = { role in
            [
                "type": "array", "items": ["type": "number"], "minItems": 3, "maxItems": 4,
                "description": "\(role) as [r, g, b] or [r, g, b, a], each 0–1.",
            ]
        }
        // `export_captions`' container list, read off the exporter's own enum
        // rather than restated, and hoisted for the type-checker budget reason
        // `AgentCatalog+Clips.swift`'s own hoisted clauses record.
        let captionFormatNames = CaptionExporter.Format.allCases.map { $0.rawValue }
        let captionFormatProperty: [String: Any] = [
            "type": "string", "enum": captionFormatNames,
            "description": "srt (SubRip) or vtt (WebVTT). Default: the path's own extension "
                + "when it is one of those, else srt. An explicit format WINS, and the path's "
                + "extension is replaced rather than appended to — the result reports the file "
                + "that was really written.",
        ]
        // `render_frame`'s three image containers, read off `FrameWriter`'s
        // own enum rather than restated, and hoisted for the same budget
        // reason.
        let frameFormatNames = FrameWriter.Format.allCases.map { $0.rawValue }
        let frameFormatProperty: [String: Any] = [
            "type": "string", "enum": frameFormatNames,
            "description": "The container to write. Default: the path's own extension when it "
                + "is one of those (.jpg counts as jpeg), else png — so a call with no path "
                + "and no format writes a PNG, as it always has. An explicit format WINS and "
                + "the path's extension is REPLACED rather than appended to, so {path: "
                + "\"shot.jpg\", format: \"png\"} writes shot.png. png and heic keep the "
                + "canvas's alpha; \(FrameWriter.flattenNote)",
        ]
        // The burn-in argument, written ONCE and shared by `render_frame` and
        // `export`: the two are the same question about the same layer, and
        // two spellings of it would drift the first time either was edited.
        let burnInProperty: [String: Any] = [
            "type": "boolean",
            "description": "Draw the project timecode over the picture, topmost — the export "
                + "sheet's Burn in timecode checkbox. Default: false. It is a review copy's "
                + "reference, so it reads the DOCUMENT'S timecode in the document's own "
                + "spelling (the toolbar's, non-drop, HH:MM:SS:FF or HH:MM:SS.mmm), and it "
                + "shows PROJECT time even in a file written from the in/out range: a range "
                + "export starting at 00:00:10:00 begins at 00:00 carrying a burn-in that "
                + "reads 00:00:10:00, which is the number a note about that frame needs.",
        ]
        // `export`'s two alpha-bearing arguments, hoisted for the budget
        // reason above and because both had to grow the same sentence.
        //
        // **A capability an agent cannot read is a capability it does not
        // have.** Phase 7b gave the table two rows that keep a transparent
        // canvas and gave `ExportWriter` a refusal for one of them, and
        // neither reached the schema — so the tool promised a letterbox where
        // the build throws, and the row to ask for was named nowhere a caller
        // could see it. The refusal is `prores_4444`'s alone: `apng` takes
        // the ImageIO path, which FITS instead of padding.
        let exportPresetProperty: [String: Any] = [
            "type": "string",
            "description": "Export preset id — one per encoding, a container and a codec with "
                + "no size of its own (that is size's). h264 is what the export sheet opens "
                + "on. Two rows keep a transparent canvas transparent: prores_4444 (the movie "
                + "row — see size, which it constrains) and apng. gif is not one of them: it "
                + "can show a transparent pixel but has no alpha channel, so nothing partial "
                + "survives it. Pass a wrong one once and the error lists them all.",
        ]
        let exportSizeProperty: [String: Any] = [
            "type": ["string", "array"],
            "items": ["type": "integer"], "minItems": 2, "maxItems": 2,
            "description": "Output size — the sheet's Size popup. A row id: document (the "
                + "default, the document's own size), 1080p, 720p, 1440p or 2160p (the number "
                + "is the SHORT edge and the long edge follows the document's aspect, rounded "
                + "to even, so a vertical project's 1080p is 1080 × 1920), or preset for an "
                + "image format's cap (gif and apng, where it is the default) — or an explicit "
                + "[width, height] in px, the sheet's Custom…. Every row exists on every "
                + "document — a 1920 × 1080 project's 1080p is its own size and is listed "
                + "anyway — so an id means the same thing wherever it is sent; only preset is "
                + "confined to gif and apng. Omit for the document size or the image format's "
                + "cap; a wrong id's error lists the ids. A movie is written at exactly the "
                + "size asked for, letterboxed if the aspect differs — except on prores_4444, "
                + "where a size of a DIFFERENT ASPECT from the canvas is refused rather than "
                + "written, because the padding destroys the alpha channel that row is chosen "
                + "for; every row id is already the document's own aspect, so this only bites "
                + "on a [width, height] of another shape. On gif and apng a size — the cap, a "
                + "row, or [width, height] — is a box the picture is fitted inside, aspect "
                + "kept and never upscaled, and the width and height reported back are the "
                + "file's: a vertical 1080 × 1920 project's GIF default is 152 × 270.",
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
        // the tools in. The three locals it is handed are the ones a LATER group asks
        // for too, which is why they stayed on this side of the cut.
        catalog += clipAndActionTools(
            ticks: ticks, trackProperty: trackProperty, colorProperty: colorProperty)
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

            // MARK: Media

            tool(
                "import_media",
                "Probes a movie, sound file or picture and adds it to the project's media list, "
                    + "returning its new media id — File ▸ Add Media…. It is NOT on the timeline "
                    + "yet: place it with add_clip {track, media, at}. The result also reports "
                    + "what the probe found (kind, duration, display size, frame rate, whether "
                    + "it has video, audio or an alpha channel), which is what you need to place "
                    + "and size it.",
                ["path": ["type": "string", "description": "Absolute or ~ path to the file."]],
                required: ["path"]),
            tool(
                "import_captions",
                "Reads a SubRip (.srt) caption file and lays it out as TEXT CLIPS, one per cue, "
                    + "on a new track of its own — File ▸ Import Captions…. They are ordinary "
                    + "text clips in the Caption preset, so they render in the preview, in "
                    + "render_frame and in an export (burn-in) with no further step, and any of "
                    + "them can be retimed with move_clip or restyled with set_text. Times snap "
                    + "to the frame grid; a cue that overlapped the next one is shortened to "
                    + "meet it. The result reports how many cues landed and, under skipped, "
                    + "every entry the file was too malformed to read, with its line number.",
                [
                    "path": [
                        "type": "string",
                        "description": "Absolute or ~ path to the .srt file.",
                    ],
                    "track": [
                        "type": "integer",
                        "description": "Put the captions on this existing track instead of a "
                            + "new one. Cues the overlap rule refuses there are dropped, so "
                            + "prefer omitting it.",
                    ],
                ], required: ["path"]),
            tool(
                "consolidate_media",
                "Copies every file the project references into media/ inside the .reelcut "
                    + "package and relinks the project at the copies — File ▸ Consolidate "
                    + "Media…. Afterwards the package is the whole edit: it can be moved or "
                    + "archived and still open with its original footage deleted. The project "
                    + "must have been saved (call save_project with a path first); files that "
                    + "are already inside are left alone, missing files are reported rather "
                    + "than guessed at, and a file that cannot be copied leaves its media entry "
                    + "pointing at the original, so the project always still opens. This can "
                    + "take a while and copies as many bytes as the footage weighs.",
                [:]),
            tool(
                "add_media",
                "The raw op behind import_media: adds a media entry from a descriptor you "
                    + "supply — the media[] element of the project JSON minus its id (path, "
                    + "bookmark, kind, duration, width, height, fps [num, den], has_video, "
                    + "has_audio, has_alpha). Probing files is the host's job, so unless you are "
                    + "replaying a project's own JSON, call import_media and let it probe.",
                [
                    "descriptor": [
                        "type": "object",
                        "description": "The media entry to add; only path is required.",
                    ]
                ], required: ["descriptor"]),
            tool(
                "relink_media",
                "Points a media entry at a file that moved — the Relink… sheet. Every clip using "
                    + "it comes back; a bookmark for the new location is stored so the next move "
                    + "is followed automatically. get_project's missing_media names the entries "
                    + "that need this.",
                [
                    "media": ["type": "integer", "description": "Media id."],
                    "path": ["type": "string", "description": "Where the file is now."],
                    "bookmark": [
                        "type": "string",
                        "description": "Base64 security bookmark; omit and one is made for you.",
                    ],
                ], required: ["media", "path"]),
            tool(
                "remove_media",
                "Removes a media entry from the project. Media still used by clips is refused "
                    + "unless with_clips is true, which removes those clips with it.",
                [
                    "media": ["type": "integer", "description": "Media id."],
                    "with_clips": [
                        "type": "boolean",
                        "description": "Remove the clips using it too (default false).",
                    ],
                ], required: ["media"]),

            // MARK: Captions
            //
            // `import_captions` is up in Media with the other file readers;
            // these two are the app-state tools of spec §7.9 that make and
            // write captions rather than reading a file into the project.

            tool(
                "transcribe",
                "Transcribes clips with ON-DEVICE speech recognition and lays the result out as "
                    + "TEXT CLIPS, one per cue, on a new track of its own — File ▸ Generate "
                    + "Captions…. They are ordinary text clips in the Caption preset, exactly "
                    + "what import_captions makes, so they render in the preview, in "
                    + "render_frame and in an export (burn-in) and can be retimed with "
                    + "move_clip or restyled with set_text. Cues are at most two lines of 42 "
                    + "characters and at most 6 s, with a frame between them. THE GRANT: macOS "
                    + "gates speech recognition, and this tool never asks for it — the system "
                    + "prompt needs the app to be frontmost and an agent-driven app never is, "
                    + "so without the grant the call is refused with the authorization status "
                    + "named and nothing is changed; somebody has to run File ▸ Generate "
                    + "Captions… once from the app. Recognition also stops after about a "
                    + "minute per clip: when it does, the result says so under truncated with "
                    + "the time it stopped at, rather than ending quietly. The result carries "
                    + "the cues themselves in TICKS whether or not they were placed, and "
                    + "reports under skipped every clip you named that cannot be transcribed.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Transcribe only these clips — the sheet's scope. Omit "
                            + "for every clip in the project that has recorded sound. Only a "
                            + "clip playing a movie or sound file can be transcribed, and not "
                            + "one played in REVERSE, whose words would come out backwards; a "
                            + "clip you name that cannot be is reported under skipped.",
                    ],
                    "language": [
                        "type": "string",
                        "description": "A language tag, e.g. en-US. Default: this Mac's own "
                            + "language. The two ways a tag can be wrong are two different "
                            + "problems with two different fixes, so they are refused "
                            + "SEPARATELY and the message says which you have. A tag speech "
                            + "recognition has never heard of is a misspelling: it is refused "
                            + "with the tags it does know, and answered before the grant is "
                            + "even read, so you get that answer on a machine nobody has "
                            + "granted yet. A tag it knows that this Mac has no on-device "
                            + "MODEL for is a download instead: that refusal names System "
                            + "Settings ▸ Keyboard ▸ Dictation and lists the languages ready "
                            + "here, and it comes after the grant, because an ungranted Mac "
                            + "cannot be asked which models it has.",
                    ],
                    "place": [
                        "type": "boolean",
                        "description": "Place the cues as text clips (default true), as ONE "
                            + "undo step. false returns the cues and changes nothing at all — "
                            + "no edit, no undo step — which is the way to check a transcript "
                            + "before committing to it.",
                    ],
                ]),
            tool(
                "export_captions",
                "Writes one text track out as a subtitle file — File ▸ Export Captions…. Every "
                    + "text clip on the track becomes one cue at the time it sits at, in the "
                    + "order they play. THE TRACK IS NEVER GUESSED: the default is the single "
                    + "track whose clips are ALL text clips, and with none or with more than "
                    + "one the call is refused and the candidates listed by id and name — "
                    + "writing the wrong track and reporting success is the failure this rule "
                    + "prevents. WebVTT escapes &, < and > where SubRip does not, so on text "
                    + "containing none of the three the two files differ only by the WEBVTT "
                    + "header, the missing index lines and a . where SubRip writes a , in the "
                    + "timestamps. A round trip back through import_captions returns every cue "
                    + "to the TICK it was written from, at every ordinary frame rate: a "
                    + "timestamp is rounded to the nearest millisecond, at most 300 ticks, and "
                    + "half a frame is 10,000 ticks even at 30 fps, so the snap on the way "
                    + "back in lands on the frame the cue left. What is not exact is the "
                    + "FILE: import_captions snaps every cue to the frame grid, so a source "
                    + "whose times are off that grid comes back written onto it — at 30 fps "
                    + "00:00:04,120 returns as 00:00:04,133 — and byte identity with the file "
                    + "you imported needs cue times already on the grid AND a frame that is a "
                    + "whole number of milliseconds, which is 25 or 50 fps. Nothing is edited "
                    + "and no undo step is registered.",
                [
                    "track": [
                        "type": "integer",
                        "description": "The track to write. Omit when the project has exactly "
                            + "one all-text track; a track that is not one of the candidates "
                            + "is refused by name, since a clip with no words would export as "
                            + "a blank cue.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to write, e.g. ~/Movies/talk.srt. The folder "
                            + "must exist.",
                    ],
                    "format": captionFormatProperty,
                ], required: ["path"]),

            // MARK: Rendering and export

            tool(
                "render_frame",
                "Renders one frame of the finished timeline as a picture so you can SEE the "
                    + "result — the verification hook. It goes through the same composition and "
                    + "the same Metal compositor an export does, so this is what the file will "
                    + "contain at that moment, not a preview of it. The image comes back both "
                    + "as an image block and as a file on disk whose path the text names. Use it "
                    + "before and after every edit. It writes a PNG to a temporary file unless "
                    + "path or format says otherwise, so a call that names neither is exactly "
                    + "the call it always was.",
                [
                    "t": [
                        "type": "integer",
                        "description": "The moment to render, \(ticks) Default: the playhead.",
                    ],
                    "max_width": [
                        "type": "integer", "minimum": 16, "maximum": 8192,
                        "description": "Cap the image's width in px, aspect kept and never "
                            + "upscaled. Default: the canvas's own size.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to write the file, e.g. ~/Desktop/shot.png. The "
                            + "folder must exist. Omit for a temporary file; either way the "
                            + "text block's last sentence names the file that was written. "
                            + "This is the same writer File ▸ Save Frame… uses, so a PNG "
                            + "written here and one saved from the menu are byte-identical.",
                    ],
                    "format": frameFormatProperty,
                    "burn_in_timecode": burnInProperty,
                ]),
            tool(
                "export",
                "Writes the timeline to a file and waits for it to finish — ⌘E, the export "
                    + "sheet's six controls (format, size, frame rate, quality, loudness, "
                    + "range) in the sheet's own vocabulary, all but the frame rate — this "
                    + "exports at the "
                    + "document's rate, or on gif and apng at the format's own rate (12.5 and "
                    + "25 fps). The preset is the ENCODING only and the size a separate "
                    + "choice defaulting to the document's own, or on gif and apng to the "
                    + "format's cap; the core resolves both into concrete settings "
                    + "(container, codec, size, rate, range) and hands them to the same "
                    + "exporter the sheet uses, so an agent export and a menu export cannot "
                    + "disagree. An existing file at the path is replaced, and the "
                    + "container's extension is added when the path has none. The result "
                    + "reports the settings that were used, the file's size, and — for every "
                    + "format that carries sound, normalised or not — what that sound "
                    + "MEASURED on the way through, under loudness: integrated_lufs, "
                    + "true_peak_dbtp and the gain_db that was applied. Those are read off "
                    + "the mix that was written, so they are what the file holds rather than "
                    + "what was asked for.",
                [
                    "preset": exportPresetProperty,
                    "path": [
                        "type": "string",
                        "description": "Where to write, e.g. ~/Movies/cut.mp4. The folder must "
                            + "exist.",
                    ],
                    "size": exportSizeProperty,
                    "range": [
                        "type": "string",
                        "enum": ["project", "in_out"],
                        "description": "What to write: the whole timeline (default), or just "
                            + "the in/out range set_range set — the sheet's Range popup.",
                    ],
                    "video_bitrate": [
                        "type": "integer", "minimum": 1,
                        "description": "Target video rate in BITS per second (8000000 is "
                            + "8 Mbps) — the sheet's Quality popup. Omit to let the preset's "
                            + "own encoder settings decide. Ignored by presets that carry no "
                            + "rate of their own: ProRes is fixed by its profile, and GIF and "
                            + "APNG have no bitrate at all.",
                    ],
                    "audio_bitrate": [
                        "type": "integer", "minimum": 1,
                        "description": "Target AAC rate in BITS per second (192000 is "
                            + "192 kbps) — the sheet's Quality popup. Omit for the preset's "
                            + "own. Ignored where the sound is not AAC: ProRes, WAV and AIFF "
                            + "all write LPCM, whose rate is its sample format.",
                    ],
                    "loudness_lufs": [
                        "type": "number", "minimum": -70, "maximum": 0,
                        "description": "Normalise the whole mix to this integrated loudness, "
                            + "in LUFS — the sheet's Loudness popup, whose rows are -14 "
                            + "(streaming), -16 (podcast) and -23 (EBU R 128 broadcast). The "
                            + "export measures itself first and then applies ONE gain to "
                            + "everything, so relative levels inside the timeline are "
                            + "untouched and no limiter is involved. Omit not to normalise: "
                            + "the export still measures and still reports. Ignored where "
                            + "there is no sound to measure (gif, apng).",
                    ],
                    "peak_dbtp": [
                        "type": "number", "minimum": -20, "maximum": 0,
                        "description": "The true-peak ceiling that gain is capped against, in "
                            + "dBTP. The sheet fixes it at -1 and this is the knob for "
                            + "anything else. Because normalisation is gain-only, a ceiling "
                            + "with no loudness_lufs beside it would have nothing to cap and "
                            + "is REFUSED rather than accepted and left inert. When the "
                            + "ceiling bites, the file lands quieter than the target asked "
                            + "for and the result's capped_by_peak says so.",
                    ],
                    "burn_in_timecode": burnInProperty,
                ], required: ["preset", "path"]),
        ]
        let data = try JSONSerialization.data(withJSONObject: catalog)
        return String(decoding: data, as: UTF8.self)
    }
}
