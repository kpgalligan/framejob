import Foundation

// MARK: - Catalog

/// The MCP tool catalog `AgentServer` registers with the core: every tool's
/// name, description, and JSON-Schema input. The names here must match
/// `AgentServer.handlers` exactly — `start()` checks the parity and traps in
/// debug builds, logs in Release — and every op tool's name and arguments must
/// match the op table in spec §6 and the module doc of `core/src/edit.rs`,
/// because those three spellings are one contract.
extension AgentServer {
    /// One tool. Every tool gets `project` for free: with several projects
    /// open a call would otherwise be ambiguous, and the property costs
    /// nothing when only one is.
    private func tool(
        _ name: String, _ description: String,
        _ properties: [String: Any], required: [String] = []
    ) -> [String: Any] {
        var schema = properties
        schema["project"] = Self.projectProperty
        return [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object", "properties": schema, "required": required,
            ] as [String: Any],
        ]
    }

    private static let projectProperty: [String: Any] = [
        "type": "string",
        "description": "Path of the open project to act on, as get_project reports it; omit "
            + "for the frontmost one.",
    ]

    /// The sentence every time argument carries. Ticks are the model's own
    /// unit (spec §5.1) and the only one the ops take.
    private static let ticksNote =
        "in TICKS — 600000 per second, so 1 s = 600000 and one 30 fps frame = 20000. "
        + "Rounded to the project's frame grid."

    func catalogJSON() throws -> String {
        let ticks = Self.ticksNote
        let clipsProperty: [String: Any] = [
            "type": "array", "items": ["type": "integer"], "minItems": 1,
            "description": "Clip ids (get_project lists them).",
        ]
        let clipProperty: [String: Any] = [
            "type": "integer", "description": "Clip id (get_project lists them).",
        ]
        let trackProperty: [String: Any] = [
            "type": "integer", "description": "Track id (get_project lists them).",
        ]
        let colorProperty: (String) -> [String: Any] = { role in
            [
                "type": "array", "items": ["type": "number"], "minItems": 3, "maxItems": 4,
                "description": "\(role) as [r, g, b] or [r, g, b, a], each 0–1.",
            ]
        }
        let shapeNames = ShapeKind.allCases.map { $0.rawValue }
        let transitionNames = TransitionKind.allCases.map { $0.rawValue }
        // `null` is a legal value of `set_transition`'s kind — it is how a
        // transition is removed — so the enum has to carry it beside the
        // names, which makes the array heterogeneous.
        var transitionEnum: [Any] = transitionNames
        transitionEnum.append(NSNull())
        let curveNames = Curve.allCases.map { $0.rawValue }
        // The three patch vocabularies, written once: every property group of
        // spec §5.2, with the ranges the ops enforce. A patch MERGES, so a key
        // left out keeps its current value and a key set to null clears an
        // optional group (shadow, chroma, duck, outline, backdrop, and text's
        // width, which null restores to auto-sizing).
        let videoPatchDescription =
            "Video properties to merge into the clip's base props. Keys: x, y (canvas px from "
            + "the canvas centre, y DOWN), scale (1 = native pixels, 0.01–10), rotation "
            + "(degrees, positive turns clockwise on screen), opacity (0–1), crop "
            + "({l, t, r, b} in SOURCE px — cropping never shifts the content), corner_radius "
            + "(source px), shadow (null or {color, opacity, blur, angle, distance}), color "
            + "({brightness, contrast, saturation, hue}, each 0 = unchanged), chroma (null or "
            + "{key: [r, g, b], tolerance, softness, spill}). A colour is [r, g, b] or "
            + "[r, g, b, a], each 0–1; chroma's key is the one that takes no alpha."
        let audioPatchDescription =
            "Audio properties to merge. Keys: volume (0–4, 1 = unity), muted, fade_in, "
            + "fade_out (ticks), duck (null or {level, attack, release}), mono, keep_pitch."
        let textPatchDescription =
            "Text properties to merge. Keys: content, font (a PostScript name), size (px), "
            + "color, align (left|center|right), valign (top|middle|bottom), line_spacing, "
            + "tracking, outline (null or {width, color}), backdrop (null or {color, padding, "
            + "radius}), width (null for auto-sizing, or a wrap width in px). A colour is "
            + "[r, g, b] or [r, g, b, a], each 0–1."

        let catalog: [[String: Any]] = [

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

            // MARK: Clips

            tool(
                "add_clip",
                "Places a whole media file as one clip at `at` on `track` — dragging a Media-tab "
                    + "row onto a track. The clip starts at source time 0 and runs the media's "
                    + "whole length; trim it afterwards with trim_start / trim_end. It is given "
                    + "Fit scale when the project's fit_new_clips is on and the source is bigger "
                    + "than the canvas. Refused when it would break the overlap rule: a clip may "
                    + "overlap at most one neighbour on each side, and each overlap must be at "
                    + "most half of the shorter of the two clips (an overlap IS a transition).",
                [
                    "track": trackProperty,
                    "media": [
                        "type": "integer",
                        "description": "Media id — import_media returns one.",
                    ],
                    "at": ["type": "integer", "description": "Start on the timeline, \(ticks)"],
                ], required: ["track", "media", "at"]),
            tool(
                "add_text_clip",
                "Adds a text clip — a title. It has no source, so it can be any length; the "
                    + "default is 5 s of the Title preset, centred. Style it afterwards with "
                    + "set_text and place it with set_video (x, y, scale).",
                [
                    "track": trackProperty,
                    "at": ["type": "integer", "description": "Start, \(ticks)"],
                    "duration": [
                        "type": "integer",
                        "description": "Length \(ticks) Default 5 s (3000000).",
                    ],
                    "text": [
                        "type": "string",
                        "description": "The words. Default: the Title preset's placeholder.",
                    ],
                ], required: ["track", "at"]),
            tool(
                "add_shape_clip",
                "Adds a shape clip — a rectangle, ellipse, line or arrow drawn over the video. "
                    + "Like text it has no source and any duration; set_shape changes its "
                    + "geometry and paint, set_video places it.",
                [
                    "track": trackProperty,
                    "at": ["type": "integer", "description": "Start, \(ticks)"],
                    "duration": [
                        "type": "integer",
                        "description": "Length \(ticks) Default 5 s (3000000).",
                    ],
                    "shape": [
                        "type": "string", "enum": shapeNames,
                        "description": "Which shape. A rounded rectangle is a rectangle with a "
                            + "radius, not a kind of its own.",
                    ],
                ], required: ["track", "at", "shape"]),
            tool(
                "move_clip",
                "Shifts clips along the timeline by delta ticks (negative moves left; starts "
                    + "clamp at 0) and optionally onto another track — the timeline's clip drag. "
                    + "Several clips keep their relative track offsets. Refused when the "
                    + "destination would break the overlap rule (at most one neighbour "
                    + "overlapped on each side, each overlap at most half the shorter clip); a "
                    + "clip that gains an overlap with the clip before it also gains a "
                    + "cross_dissolve transition if it had none.",
                [
                    "clips": clipsProperty,
                    "delta": [
                        "type": "integer",
                        "description": "How far to shift, \(ticks) Negative moves earlier.",
                    ],
                    "track": [
                        "type": "integer",
                        "description": "Destination track id for the first clip; omit to stay "
                            + "on the current tracks.",
                    ],
                ], required: ["clips", "delta"]),
            tool(
                "trim_start",
                "Moves a clip's START to `to`, keeping the content in place: the source "
                    + "in-point advances by the same amount, so nothing after the new start "
                    + "shifts. Clamped by the source's own beginning and by the clip's end (a "
                    + "clip is at least one frame long).",
                [
                    "clip": clipProperty,
                    "to": ["type": "integer", "description": "New start, \(ticks)"],
                ], required: ["clip", "to"]),
            tool(
                "trim_end",
                "Moves a clip's END to `to`. Clamped by how much source is left after the "
                    + "in-point and by the clip's start.",
                [
                    "clip": clipProperty,
                    "to": ["type": "integer", "description": "New end, \(ticks)"],
                ], required: ["clip", "to"]),
            tool(
                "rate_stretch",
                "Stretches a clip to end at `to_end` by changing its SPEED instead of trimming "
                    + "it — the whole source still plays, faster or slower (⌥-dragging the end "
                    + "edge). Media clips only: a text, shape, image or freeze clip has no "
                    + "source to stretch and is an error.",
                [
                    "clip": clipProperty,
                    "to_end": ["type": "integer", "description": "New end, \(ticks)"],
                ], required: ["clip", "to_end"]),
            tool(
                "split",
                "Cuts clips in two at `at` — ⌘K. The second piece keeps playing the source from "
                    + "where the first stopped, and each keeps the animation actions that fall "
                    + "on its side (an action straddling the cut becomes two). With no clips "
                    + "every unlocked clip under the time is split, which is what the menu "
                    + "command does with nothing selected. Refused when `at` is not strictly "
                    + "inside a clip.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Clip ids; omit to split every unlocked clip at `at`.",
                    ],
                    "at": [
                        "type": "integer",
                        "description": "Where to cut, \(ticks) Default: the playhead.",
                    ],
                ]),
            tool(
                "delete",
                "Removes clips and LEAVES the gaps where they were — ⌫. Use ripple_delete to "
                    + "close them.",
                ["clips": clipsProperty], required: ["clips"]),
            tool(
                "ripple_delete",
                "Removes clips and closes the gaps: everything starting after each removed span "
                    + "on an UNLOCKED track slides left by that span's length — ⌘⌫. Clips on "
                    + "locked tracks and clips that straddle a span stay where they are.",
                ["clips": clipsProperty], required: ["clips"]),
            tool(
                "ripple_delete_range",
                "Cuts a time range out of the whole timeline: every unlocked clip is split at "
                    + "both bounds, the middles are removed, and the rest slides left by the "
                    + "range's length. The in/out-range form of ⌘⌫.",
                [
                    "from": ["type": "integer", "description": "Range start, \(ticks)"],
                    "to": ["type": "integer", "description": "Range end, \(ticks)"],
                ], required: ["from", "to"]),
            tool(
                "insert_time",
                "Opens a gap: every unlocked clip starting at or after `at` moves right by "
                    + "`length`. Straddling clips are left in place, so this makes room without "
                    + "cutting anything — split first if you want the gap inside a clip.",
                [
                    "at": ["type": "integer", "description": "Where the gap opens, \(ticks)"],
                    "length": ["type": "integer", "description": "How much room, \(ticks)"],
                ], required: ["at", "length"]),
            tool(
                "set_speed",
                "Changes a clip's playback rate — Clip ▸ Speed…. The duration follows (source "
                    + "length ÷ rate) and the clip's animation actions keep their relative "
                    + "position inside it. Rate is clamped to 0.1–10. Media clips only: any "
                    + "other kind is an error.",
                [
                    "clip": clipProperty,
                    "rate": [
                        "type": "number", "minimum": 0.1, "maximum": 10,
                        "description": "1 = normal, 2 = twice as fast (half as long), 0.5 = "
                            + "slow motion.",
                    ],
                    "keep_pitch": [
                        "type": "boolean",
                        "description": "Keep the audio's pitch while the speed changes "
                            + "(default: the clip's current setting).",
                    ],
                ], required: ["clip", "rate"]),
            tool(
                "freeze_frame",
                "Holds one frame: the clip is split at `at`, a gap of `duration` is opened, and "
                    + "a still of that exact source frame fills it with the clip's own video "
                    + "properties — ⇧⌘F. Media clips only.",
                [
                    "clip": clipProperty,
                    "at": [
                        "type": "integer",
                        "description": "The moment to freeze, \(ticks) Default: the playhead.",
                    ],
                    "duration": [
                        "type": "integer",
                        "description": "How long to hold \(ticks) Default 2 s (1200000).",
                    ],
                ], required: ["clip"]),
            tool(
                "detach_audio",
                "Splits a clip's audio onto its own clip on the track below (inserting one when "
                    + "there is none), muting the original's audio and hiding the new clip's "
                    + "video — ⌥⌘D. The two can then be trimmed and moved apart. Refused when "
                    + "the media has no audio or the audio is already detached.",
                ["clip": clipProperty], required: ["clip"]),
            tool(
                "duplicate",
                "Copies clips onto the same tracks, placed immediately after the originals' "
                    + "span — ⌘D. Follow with move_clip to put them anywhere else.",
                ["clips": clipsProperty], required: ["clips"]),
            tool(
                "set_video",
                "Changes the clips' BASE video properties — position, scale, rotation, opacity, "
                    + "crop, corner radius, shadow, colour and chroma key. The patch MERGES: "
                    + "keys you leave out keep their values, and shadow or chroma set to null "
                    + "clears it. Placement is spec §5.3: the source rectangle is centred at the "
                    + "canvas centre plus (x, y), scaled, then rotated about that centre, and "
                    + "crop removes edges in place without shifting the content. To animate a "
                    + "property instead, add_action and then set_action_end.",
                [
                    "clips": clipsProperty,
                    "patch": ["type": "object", "description": videoPatchDescription],
                ], required: ["clips", "patch"]),
            tool(
                "set_audio",
                "Changes the clips' BASE audio properties — volume, mute, fades, ducking, mono "
                    + "and pitch preservation. Merges like set_video; duck set to null removes "
                    + "the ducking.",
                [
                    "clips": clipsProperty,
                    "patch": ["type": "object", "description": audioPatchDescription],
                ], required: ["clips", "patch"]),
            tool(
                "set_text",
                "Changes a text clip's words and typography. Merges like set_video; outline, "
                    + "backdrop and width set to null clear them (a null width restores "
                    + "auto-sizing). Position and scale are set_video's, not this tool's.",
                [
                    "clips": clipsProperty,
                    "patch": ["type": "object", "description": textPatchDescription],
                ], required: ["clips", "patch"]),
            tool(
                "set_shape",
                "Changes a shape clip's geometry and paint. Keys: kind ("
                    + shapeNames.joined(separator: "|") + "), width, height (the box, in source "
                    + "px), stroke (null or {width, color}), fill (null or a colour), radius "
                    + "(rectangle corners), arrow_start, arrow_end, and from / to — the "
                    + "endpoints of a line or arrow as UNIT coordinates in its box, e.g. "
                    + "from [0, 1] to [1, 0]. Merges like set_video.",
                [
                    "clips": clipsProperty,
                    "patch": [
                        "type": "object",
                        "description": "The shape properties to change (see above).",
                    ],
                ], required: ["clips", "patch"]),
            tool(
                "set_enabled",
                "Turns one clip's video and/or audio on or off — the two halves detach_audio "
                    + "flips. A disabled half contributes nothing to the composition but the "
                    + "clip stays where it is.",
                [
                    "clip": clipProperty,
                    "video": ["type": "boolean", "description": "Show this clip's picture."],
                    "audio": ["type": "boolean", "description": "Play this clip's sound."],
                ], required: ["clip"]),
            tool(
                "set_transition",
                "Sets the transition INTO a clip — the one that plays across its overlap with "
                    + "the clip before it on the same track. The transition's duration IS that "
                    + "overlap, so a clip with no overlap ignores it: make one with move_clip or "
                    + "set_transition_duration. kind null removes it.",
                [
                    "clip": clipProperty,
                    "kind": [
                        "type": ["string", "null"], "enum": transitionEnum,
                        "description": "The transition, or null to remove it.",
                    ] as [String: Any],
                ], required: ["clip", "kind"]),
            tool(
                "set_transition_duration",
                "Makes a clip's transition last `duration` by MOVING the clip so its overlap "
                    + "with the clip before it equals that. Subject to the overlap rule, so a "
                    + "duration past half the shorter clip is refused.",
                [
                    "clip": clipProperty,
                    "duration": [
                        "type": "integer", "description": "Overlap length, \(ticks)",
                    ],
                ], required: ["clip", "duration"]),

            // MARK: Actions

            tool(
                "add_action",
                "Adds an animation span to a clip: over `duration` starting at `at`, the clip's "
                    + "properties ease from whatever they are to the span's END state. The end "
                    + "state starts EMPTY — nothing changes until set_action_end fills it in. "
                    + "`at` is CLIP time, measured from the clip's own start, not the "
                    + "timeline's. Refused when it would overlap another action or run past the "
                    + "clip's end. The new action's id comes back as new_actions.",
                [
                    "clip": clipProperty,
                    "at": [
                        "type": "integer",
                        "description": "Where the animation starts, in CLIP time, \(ticks)",
                    ],
                    "duration": [
                        "type": "integer",
                        "description": "How long it runs \(ticks) Default 1 s (600000).",
                    ],
                ], required: ["clip", "at"]),
            tool(
                "set_action",
                "Moves or re-times an action, or changes its easing curve. Same overlap checks "
                    + "as add_action.",
                [
                    "clip": clipProperty,
                    "action": [
                        "type": "integer",
                        "description": "Action id (get_project lists each clip's actions).",
                    ],
                    "start": [
                        "type": "integer", "description": "New start in CLIP time, \(ticks)",
                    ],
                    "duration": ["type": "integer", "description": "New length, \(ticks)"],
                    "curve": [
                        "type": "string", "enum": curveNames,
                        "description": "How the values ease from start to end.",
                    ],
                ], required: ["clip", "action"]),
            tool(
                "set_action_end",
                "Sets what an action animates TO. The patch is the action's end state and "
                    + "merges into it — {\"video\": {\"scale\": 0.6, \"x\": 520}} makes the clip "
                    + "shrink into the corner over the action's span. A key set to null is "
                    + "REMOVED from the end state, so that property stops being animated. Groups "
                    + "are video, audio and text, with the same keys as set_video / set_audio / "
                    + "set_text.",
                [
                    "clip": clipProperty,
                    "action": ["type": "integer", "description": "Action id."],
                    "patch": [
                        "type": "object",
                        "description": "{video?: {...}, audio?: {...}, text?: {...}} — the "
                            + "properties the animation ends at.",
                    ],
                ], required: ["clip", "action", "patch"]),
            tool(
                "remove_action",
                "Removes an animation span. The clip keeps its base properties.",
                [
                    "clip": clipProperty,
                    "action": ["type": "integer", "description": "Action id."],
                ], required: ["clip", "action"]),

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
                "Renames a track or flips its three switches. hidden drops its picture from the "
                    + "composition, muted its sound; locked keeps every ripple, insert and range "
                    + "edit off it.",
                [
                    "track": trackProperty,
                    "name": ["type": "string"],
                    "hidden": ["type": "boolean"],
                    "muted": ["type": "boolean"],
                    "locked": ["type": "boolean"],
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

            // MARK: Rendering and export

            tool(
                "render_frame",
                "Renders one frame of the finished timeline as a PNG so you can SEE the result "
                    + "— the verification hook. It goes through the same composition and the "
                    + "same Metal compositor an export does, so this is what the file will "
                    + "contain at that moment, not a preview of it. The image comes back both "
                    + "as an image block and as a file on disk whose path the text names. Use it "
                    + "before and after every edit.",
                [
                    "t": [
                        "type": "integer",
                        "description": "The moment to render, \(ticks) Default: the playhead.",
                    ],
                    "max_width": [
                        "type": "integer", "minimum": 16, "maximum": 8192,
                        "description": "Cap the PNG's width in px, aspect kept and never "
                            + "upscaled. Default: the canvas's own size.",
                    ],
                ]),
            tool(
                "export",
                "Writes the timeline to a movie file and waits for it to finish — ⌘E. The "
                    + "preset is resolved by the core into concrete settings (container, codec, "
                    + "size, rate, range) and handed to the same exporter the app's own sheet "
                    + "uses, so an agent export and a menu export cannot disagree. An existing "
                    + "file at the path is replaced, and the container's extension is added when "
                    + "the path has none. The result reports the settings that were used and the "
                    + "file's size.",
                [
                    "preset": [
                        "type": "string",
                        "description": "Export preset id. Pass a wrong one once and the error "
                            + "lists them all.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to write, e.g. ~/Movies/cut.mp4. The folder must "
                            + "exist.",
                    ],
                    "range": [
                        "type": "string",
                        "enum": ["project", "in_out"],
                        "description": "What to write: the whole timeline (default), or just "
                            + "the in/out range set_range set — the sheet's Range popup.",
                    ],
                ], required: ["preset", "path"]),
        ]
        let data = try JSONSerialization.data(withJSONObject: catalog)
        return String(decoding: data, as: UTF8.self)
    }
}
