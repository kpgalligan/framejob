import Foundation

/// The texts the assistant's session hands the helper in `configure`
/// (`agent/src/protocol.ts`), the tools it loads up front, and the live
/// context each person message carries (spec §11 AI-15). Road map 12 A3.
///
/// **Every fact here is interpolated from the code that decides it, or
/// checked against it by `make test`** (`assistant_prompt_proof.py --probe`,
/// rows F1–F8): a backticked token must be a tool, an argument or a key of
/// `get_project`'s answer; the timescale is `ReelTime.perSecond`; the
/// ask-first and conditional withheld tools are read from
/// `AssistantToolTable.rows`; the id kinds are checked against a fixture;
/// and `searchTopics` must cover the assistant's catalog exactly. A text that
/// drifts from the code fails the build's tests, not a person's turn.
/// Backticks hold identifiers only; literals go in double quotes. No text
/// holds a blank line: the helper joins `system` and `searchGuide` with one.
enum AssistantPrompt {

    /// The tools the model sees up front (A0 C3): read, look, recover. Every
    /// other catalog entry is deferred and found through tool search.
    static let coreTools = ["get_project", "render_frame", "undo", "redo"]

    /// The arrays of `get_project`'s project whose ids share one number
    /// space (checked against a fixture by F3).
    static let sharedIdKinds = ["clips", "tracks", "markers", "media", "nests", "actions"]

    /// What tool search can find: every tool of the assistant's catalog but
    /// `coreTools`, each exactly once (F4). The guide shows the words only.
    static let searchTopics: [(words: String, tools: [String])] = [
        ("open, create or save a project, move the playhead, set the in and out range, "
            + "select clips, enter or leave a nest",
         ["open_project", "new_project", "save_project", "set_playhead", "set_range",
          "set_selection", "set_scope"]),
        ("add, remove, reorder, rename, hide, mute or lock tracks",
         ["add_track", "remove_track", "move_track", "set_track", "remove_empty_tracks"]),
        ("markers and the canvas (size, frame rate, background)",
         ["add_marker", "set_marker", "remove_marker", "set_canvas"]),
        ("place clips: media, text, shapes, backgrounds, adjustment clips that grade what is "
            + "below, insert and overwrite edits, paste, duplicate",
         ["add_clip", "add_text_clip", "add_shape_clip", "add_adjustment_clip", "add_background",
          "add_blurred_background", "insert_clip", "overwrite_clip", "paste", "duplicate"]),
        ("cut and time clips: move, trim, split, slip, roll, speed, reverse, freeze a frame, "
            + "detach audio, delete, ripple delete, delete or lift a range, insert time, close "
            + "a gap",
         ["move_clip", "trim_start", "trim_end", "rate_stretch", "slip", "roll", "split",
          "delete", "ripple_delete", "ripple_delete_range", "ripple_delete_ranges", "lift_range",
          "insert_time", "close_gap", "set_speed", "set_reversed", "freeze_frame",
          "detach_audio"]),
        ("how a clip looks and sounds: position, scale, crop, colour, filters, volume, fades, "
            + "text and its style, shapes, the clip's name, hide and mute, copying attributes",
         ["set_video", "set_audio", "set_text", "set_shape", "set_clip", "set_enabled",
          "paste_attributes"]),
        ("nest clips together or take a nest apart", ["nest", "unnest"]),
        ("transitions between clips",
         ["set_transition", "set_transition_duration", "add_transition",
          "set_transition_style"]),
        ("actions and zooms that animate a clip",
         ["add_action", "add_zoom_action", "set_action", "set_action_end", "remove_action"]),
        ("media files: import, relink, remove, copy into the project",
         ["import_media", "add_media", "relink_media", "remove_media", "consolidate_media"]),
        ("captions: import, transcribe speech, export a caption file",
         ["import_captions", "transcribe", "export_captions"]),
        ("audio clean-up: find silences, even out loudness",
         ["detect_silence", "normalize_clip"]),
        ("graphics: write a module, place and change a graphic clip, its reference, fonts and "
            + "assets; rename, delete or restore a module",
         ["add_graphic_clip", "set_graphic", "write_graphic", "get_graphic",
          "graphic_reference", "render_graphic", "import_graphic_font",
          "import_graphic_asset", "delete_graphic", "rename_graphic", "restore_graphic"]),
        ("export a movie", ["export"]),
    ]

    /// The system prompt, fixed for the session (AI-15).
    static let system: String = [
        "You are the assistant built into Reelcut, a video editor for macOS. You act on the "
            + "project open in your own window, through its tools. Leave `project` out of every "
            + "call: a call naming another project is refused. The person sees each change as "
            + "it lands, and each tool call is one step they can undo.",
        "Each message from the person begins with a <\(AssistantLiveContext.tag)> block: the "
            + "window as it was when they sent it. `name` and `path` are the project's, `scope` "
            + "is the nest open in the window (\"none\": the timeline), `playhead` is a time, "
            + "and `selection` lists the selected clip ids. It is not updated during your turn, so "
            + "after your own edits read the project again with `get_project`.",
        "Times are ticks, \(ReelTime.perSecond) per second. Every time you pass is snapped to "
            + "the frame grid of `canvas.fps`.",
        "`get_project` answers the project as JSON. `tracks[0]` is the BACK of the layer stack. "
            + "A clip sits on `track` at `start` for `duration`, and `source.kind` says what it "
            + "shows. Its property groups are patched by `set_video`, `set_audio`, `set_text`, "
            + "`set_shape` and `set_graphic`: a patch merges key by key, \"null\" clears a key "
            + "(the JSON value, never a string), and an array replaces the whole list. "
            + list(sharedIdKinds.map { "`\($0)`" })
            + " ids share one number space, and the id a call creates is the project's "
            + "`next_id` read before the call.",
        "A nest clip shows a nest, a timeline of its own. Pass `scope` with a nest's id to "
            + "edit inside it: every id and time in that call is then the nest's own, measured "
            + "from its zero. Without `scope` an edit goes where the window is looking, and "
            + "`set_scope` enters a nest as the person does. Markers belong to the timeline, "
            + "never to a nest.",
        "Captions are ordinary text clips on a track of their own, made by `import_captions` "
            + "or `transcribe`. Write or restyle a caption only when the person asks you to. "
            + "Graphics are modules: `write_graphic` writes one, `add_graphic_clip` places it, "
            + "and `graphic_reference` documents what a module can draw.",
        "`render_frame` renders one frame of the finished timeline through the compositor an "
            + "export uses, at the playhead unless you pass `t`, and answers the image and the "
            + "PNG's path. Look before and after a visual edit, and pass `max_width` to keep "
            + "the image small.",
        askFirstParagraph,
        "Reply in a sentence or two. Never repeat tool output the person can already see.",
    ].joined(separator: "\n")

    /// The ask-first tools and the conditional withheld rows, read from
    /// `AssistantToolTable.rows` (AI-7). A tool withheld outright is never
    /// named: the model never sees it.
    private static var askFirstParagraph: String {
        let asking = AssistantToolTable.rows.filter { $0.rule == .askFirst }
            .map { "`\($0.tool)`" }
        let narrowed = AssistantToolTable.rows.compactMap { row -> String? in
            guard row.rule == .withheld, let only = row.onlyWith else { return nil }
            return "`\(row.tool)` with `\(only.key)` \"\(only.value)\""
        }
        var text = "These tools write files, so each asks the person first: "
            + list(asking) + ". Nothing runs until the person clicks Allow. A result that "
            + "begins \"The person declined:\" is final for that call: do not call it again "
            + "this turn unless the person asks."
        if !narrowed.isEmpty {
            text += " Not available to you, and refused if called: " + list(narrowed) + "."
        }
        return text
    }

    /// What tool search can find, appended to the system prompt after a
    /// blank line by the helper: the core tools, then each topic's words.
    static let searchGuide: String =
        "Only " + list(coreTools.map { "`\($0)`" }) + " are loaded up front. Every other "
        + "tool is found with tool search: search in a few words for what you want to do, and "
        + "search again in other words before deciding a tool does not exist. The tools "
        + "cover: " + searchTopics.map(\.words).joined(separator: "; ") + "."

    /// What the end-of-turn compaction summary must carry (AI-9), in
    /// Rasterize's shape.
    static let compactionInstructions =
        "Summarise this video-editing conversation so the work can continue without it. Keep: "
        + "what the person asked for and every preference they stated; the project's name and "
        + "path, and any nest open; every clip, track, marker and media involved, by id, and "
        + "what each is; each edit made, in order, how it turned out, and which were undone; "
        + "what is still open or was promised. Renders do not survive, so describe in words "
        + "what each frame you looked at showed. Write the summary text only, with no tool "
        + "calls."

    /// `text` behind the window's live context (AI-15); `text` alone with no
    /// document. Main only.
    static func message(_ text: String, document: ProjectDocument?) -> String {
        guard let document else { return text }
        return AssistantLiveContext(document: document).text + "\n" + text
    }

    /// "a", "a and b", "a, b and c".
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        let head = items.dropLast()
        return head.isEmpty ? last : head.joined(separator: ", ") + " and " + last
    }
}
