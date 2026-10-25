import Foundation

// MARK: - Catalog: clips and actions

/// The catalog's CLIP half: the forty tools a timeline's clips get — making
/// one, placing it, cutting it, describing it — the five that ANIMATE one, and
/// the property-group patch vocabulary all forty-five are written in. Two of
/// the forty-five are not ops (`detect_silence` and `normalize_clip`, the
/// composites phases 3 and 5 added); the other forty-three are spec §6 rows.
///
/// **The forty-three PRINT the core's table rather than restating it** (road
/// map 7's D3·3): every one is built with `opTool`, which takes this file's
/// prose and merges the structure — the kind, the constraints, the closed
/// vocabulary, the required list — in underneath from `rc_op_schemas`. So
/// there is no `"type"`, no `"enum"` and no hand-written required list in
/// this file, and adding an argument to one of these ops costs a sentence
/// here rather than a schema. The two composites are still `tool`'s, because
/// no op stands behind them; so are the four other groups.
///
/// **What this file still says is what the core cannot know**: which menu item
/// a tool mirrors, what a default is taken from, what a **Patch** may carry,
/// and — through `AgentCatalog+Declarations.swift` — where a tool
/// deliberately accepts more or less than its op does.
///
/// A pure move out of `AgentCatalog.swift`, which stood at 1552 lines against
/// app/CLAUDE.md's ~600 cap with road map 2's phase 9 about to put a `scope`
/// property on every op tool's schema and a `set_scope` tool beside them. The
/// seam is the one the file had already drawn: `// MARK: Clips` and
/// `// MARK: Actions` came here whole, in their existing order, with their
/// bodies untouched, and so did the twenty-four hoisted locals nothing outside
/// them reads — the five patch descriptions, the enum-name lists and clauses
/// they are built from, and `rangesProperty`, `zoomRegionProperty` and
/// `groupsProperty`. Of those three only their SENTENCES are left: the
/// structure each of them hand-wrote is the core's now.
///
/// **The five action rows are `AgentCatalog+Actions.swift`'s** (issue batch
/// B87 phase 2, a pure move so their graphic prose could land under the cap),
/// appended to this array last by `actionTools`, so the catalog's order is
/// unchanged. The cut spells no vocabulary twice: the action rows NAME
/// set_video's, set_audio's and set_text's keys rather than printing them,
/// and the one hoisted local they read, `zoomRegionDescription`, went with
/// them.
///
/// **The five property rows and the patch vocabulary are
/// `AgentCatalog+Properties.swift`'s** (grading GR1, a pure move ahead of
/// grading's patch prose): `set_video`, `set_audio`, `set_text`, `set_shape`
/// and `set_clip`, spliced back in by `propertyTools` after `unnest`, so the
/// catalog's order is unchanged, and the hoisted locals only they read, now
/// static members there. `add_text_clip` and `add_shape_clip` still read
/// three of them — `shapeNames`, `textPatchDescription` and
/// `shapePatchDescription` — through typed locals of the same names below.
///
/// What stayed behind is what a SECOND group also asks: `ticks` is every
/// group's, the track sentence is Tracks' as well and the colour sentence is
/// Canvas', so the three arrive as ARGUMENTS rather than as a second spelling
/// here. This array is spliced back in where it was rather than appended,
/// because the catalog's order is the order an agent reads the tools in.
///
/// **The toll is one widening**: `tool(_:_:_:required:)` is internal rather
/// than private, since `private` on an extension member reaches only its own
/// file and every entry below is built with it or with `opTool` beside it.
/// `projectProperty` and `ticksNote` did NOT have to follow it — the first is
/// read only inside `tool`, which did not move, and the second only into the
/// `ticks` argument.
extension AgentServer {

    /// The clip and action rows of `catalogJSON()`'s array, in its order.
    func clipAndActionTools(
        ticks: String, trackDescription: String,
        colorDescription: (String) -> String, clipDescription: String
    ) -> [[String: Any]] {
        let clipsDescription = "Clip ids (get_project lists them)."
        // The one property this file still builds whole: `detect_silence` and
        // `normalize_clip` have no op behind them, so they take the old form
        // and the sentence is shared with the migrated rows above them.
        let clipsProperty: [String: Any] = [
            "type": "array", "items": ["type": "integer"], "minItems": 1,
            "description": clipsDescription,
        ]
        let shapeNames: [String] = Self.shapeNames
        let speed = ReelSpeed.limits  // set_speed's numbers, all the core's (spec §11 #190)
        let textPatchDescription: String = Self.textPatchDescription
        let shapePatchDescription: String = Self.shapePatchDescription
        var rows: [[String: Any]] = [

            // MARK: Clips

            opTool(
                "add_clip",
                "Places a whole media file as one clip at `at` on `track` — dragging a Media-tab "
                    + "row onto a track. The clip starts at source time 0 and runs the media's "
                    + "whole length snapped DOWN to whole frames, so it never outruns the file; "
                    + "trim it afterwards with trim_start / trim_end. It is given "
                    + "Fit scale when the project's fit_new_clips is on and the source is bigger "
                    + "than the canvas. Refused when it would break the overlap rule: a clip may "
                    + "overlap at most one neighbour on each side, and each overlap must be at "
                    + "most half of the shorter of the two clips (an overlap IS a transition).",
                [
                    "track": trackDescription,
                    "media": "Media id — import_media returns one.",
                    "at": "Start on the timeline, \(ticks)",
                ]),
            opTool(
                "add_text_clip",
                "Adds a text clip — a title. It has no source, so it can be any length; the "
                    + "default is 5 s of the Title preset, centred. Style it afterwards with "
                    + "set_text and place it with set_video (x, y, scale).",
                [
                    "track": trackDescription,
                    "at": "Start, \(ticks)",
                    "duration": "Length \(ticks) Default 5 s (3000000).",
                    // The op takes a set_text PATCH, which is what the core
                    // publishes; the STRING beside it is the app's shorthand
                    // and is a declared row rather than a type written here
                    // (`AgentCatalog+Declarations.swift`).
                    "text": "The words, or the styling too. A plain string is "
                        + "shorthand for {\"content\": …}; an object is a set_text patch "
                        + "merged over the Title preset. " + textPatchDescription
                        + " Default: the Title preset's placeholder.",
                ]),
            opTool(
                "add_shape_clip",
                "Adds a shape clip — a rectangle, ellipse, line or arrow drawn over the video. "
                    + "Like text it has no source and any duration; set_shape changes its "
                    + "geometry and paint, set_video places it.",
                [
                    "track": trackDescription,
                    "at": "Start, \(ticks)",
                    "duration": "Length \(ticks) Default 5 s (3000000).",
                    // Optional, as the op is: omitted, the core's default
                    // rectangle lands. Declaring it a REQUIRED kind name put
                    // that default out of reach and made the box and the
                    // paint need a following set_shape.
                    "shape": "Which shape, and how it is drawn. A plain string is a "
                        + "kind — " + shapeNames.joined(separator: ", ")
                        + " — and an object is a set_shape patch merged over the default "
                        + "rectangle. " + shapePatchDescription + " Omit it for that "
                        + "rectangle; a rounded one is a rectangle with a radius, not a "
                        + "kind of its own. An arrow is created with its head on — pass "
                        + "arrow_end: false for a bare diagonal.",
                ]),
            opTool(
                "add_adjustment_clip",
                "Adds an adjustment clip — Insert ▸ Adjustment Clip. It has no picture of its "
                    + "own: while it lasts it grades everything drawn BEHIND it (every lower "
                    + "track and the canvas background, never a track in front) with the "
                    + "colour and the point filters (sepia, noir, vignette, invert) that "
                    + "set_video gives it, and its opacity is the grade's strength. On a track "
                    + "cut by a matte it grades only inside the matte; on a matte track it does "
                    + "nothing. Refused inside a nest and in any transition or overlap — fade "
                    + "it with opacity instead; blur, sharpen, pixelate and a blend mode are "
                    + "errors on it.",
                [
                    "track": trackDescription,
                    "at": "Start, \(ticks)",
                    "duration": "Length \(ticks) Default 5 s (3000000).",
                ]),
            opTool(
                "add_background",
                "Puts a backdrop on a NEW back-most track, starting at 0 and running the "
                    + "timeline's length — Clip ▸ Add Background. With no arguments at all it "
                    + "is a canvas-sized WHITE rectangle, which is what the menu's Solid Color "
                    + "row sends: white rather than black because the canvas is already black, "
                    + "so a black plate would be a command that appears to do nothing. Give it "
                    + "a color to paint the plate another colour, or a media to put that "
                    + "picture there instead, at FILL scale — where add_clip would Fit it, "
                    + "because a plate that leaves the canvas showing down one side has "
                    + "failed at that. A video or audio plate stops where its file does, an "
                    + "image runs the timeline. A full-canvas GRADIENT is this clip and a "
                    + "set_shape {gradient} after it. media and color are alternatives: both "
                    + "is an error, as is a sub-frame duration or media, or one with no pictures.",
                [
                    "media": "Media id to show as the background — get_project lists "
                        + "them and import_media adds a file. Omit for a colour plate. A "
                        + "timed media is clamped to its own file's length, so a short movie "
                        + "stops where its file does; only an image runs the whole timeline.",
                    "color": colorDescription("The plate's colour; white when omitted"),
                    "duration": "Length \(ticks) Default: the whole timeline's length, "
                        + "and never less than one frame.",
                ]),
            opTool(
                "add_blurred_background",
                "The screencast backdrop — Clip ▸ Add Blurred Background. `clip` is copied "
                    + "onto a NEW back-most track at the same start, duration, speed and "
                    + "source window, so the two play exactly the same frames, and the copy is "
                    + "scaled to FILL the canvas, centred, uncropped, blended normal and "
                    + "blurred at full strength. It is MUTED — its enabled becomes {video: "
                    + "true, audio: false}, or the mix would play one recording twice — and it "
                    + "drops the original's audio.duck along with its transition, actions and "
                    + "label. The duck goes because it is the one field of that group that "
                    + "lowers OTHER material: a copy keeping it would duck the whole mix, "
                    + "including the clip it was copied from. It is named \"Blurred "
                    + "Background\". Two objects are created, so new_tracks and new_clips both "
                    + "come back and the TRACK holds the lower id. An error for a NEST (the "
                    + "flattening drops a nest clip's own filters, so the copy would come out "
                    + "sharp), a source with no pixel size (a text clip, an audio-only one), "
                    + "or a clip carrying no video properties.",
                ["clip": clipDescription]),
            opTool(
                "insert_clip",
                "The INSERT edit — Edit ▸ Insert at Playhead, or ⌥-dropping a Media-tab row. "
                    + "Makes room for the whole media at `at`: the clip `at` is inside on "
                    + "`track` is split first, then every unlocked track opens by the media's "
                    + "length, then the media lands in the hole. Only the destination track is "
                    + "cut — a clip straddling `at` on another track rides the shift whole, "
                    + "which is what keeps a music bed unbroken. One undo step.",
                [
                    "track": trackDescription,
                    "media": "Media id — import_media returns one.",
                    "at": "Where to insert, \(ticks)",
                ]),
            opTool(
                "overwrite_clip",
                "The OVERWRITE edit — Edit ▸ Overwrite at Playhead, or ⇧⌥-dropping a Media-tab "
                    + "row. Takes the room instead of making it: the span the media needs is "
                    + "cleared on `track` ALONE — cut at both bounds, whatever is left inside "
                    + "removed — and nothing shifts, so the cut's length and every other track "
                    + "are untouched. One undo step.",
                [
                    "track": trackDescription,
                    "media": "Media id — import_media returns one.",
                    "at": "Where to overwrite, \(ticks)",
                ]),
            opTool(
                "move_clip",
                "Shifts clips along the timeline by delta ticks (negative moves left; starts "
                    + "clamp at 0) and optionally onto another track — the timeline's clip drag. "
                    + "Several clips keep their relative track offsets. Refused when the "
                    + "destination would break the overlap rule (at most one neighbour "
                    + "overlapped on each side, each overlap at most half the shorter clip); a "
                    + "clip that gains an overlap with the clip before it also gains a "
                    + "cross_dissolve transition if it had none.",
                [
                    "clips": clipsDescription,
                    "delta": "How far to shift, \(ticks) Negative moves earlier.",
                    "track": "Destination track id for the first clip; omit to stay "
                        + "on the current tracks.",
                ]),
            opTool(
                "trim_start",
                "Moves a clip's START to `to`, keeping the content in place: the source "
                    + "in-point advances by the same amount, so nothing after the new start "
                    + "shifts. Clamped by the source's own beginning and by the clip's end (a "
                    + "clip is at least one frame long). On a clip with a speed ramp the ramp "
                    + "stays where it is in the clip, so what plays after the new start can "
                    + "change, and the start is held where the clip still fits its media.",
                ["clip": clipDescription, "to": "New start, \(ticks)"]),
            opTool(
                "trim_end",
                "Moves a clip's END to `to`. Clamped by how much source is left after the "
                    + "in-point, on the frame grid, and by the clip's start.",
                ["clip": clipDescription, "to": "New end, \(ticks)"]),
            opTool(
                "rate_stretch",
                "Stretches a clip to end at `to_end` by changing its SPEED instead of trimming "
                    + "it — the whole source still plays, faster or slower (⌥-dragging the end "
                    + "edge). Media clips only: a text, shape, image or freeze clip has no "
                    + "source to stretch and is an error. A speed ramp on the clip scales with "
                    + "it; a stretch that would take any of its rates past the limits changes "
                    + "nothing.",
                ["clip": clipDescription, "to_end": "New end, \(ticks)"]),
            opTool(
                "slip",
                "Slides the SOURCE under a fixed clip — ⌥⇧-dragging a clip's body. What the "
                    + "clip shows changes; where it sits does not, so nothing downstream moves. "
                    + "`delta` is timeline ticks and the source moves by delta × the clip's "
                    + "speed; a positive delta shows LATER material. Clamped so the window "
                    + "stays inside the media, and a slip the clamps reduce to nothing changes "
                    + "nothing. A freeze clip moves the frame it holds instead. Media and "
                    + "freeze clips only: any other kind is an error.",
                [
                    "clip": clipDescription,
                    "delta": "How far to slide the source, \(ticks)",
                ]),
            opTool(
                "roll",
                "Moves a hard CUT — ⌥⇧-dragging a clip's edge. This clip's start and its "
                    + "predecessor's end both become `to`: one clip grows by exactly what the "
                    + "other loses, and the pair's outer edges and total length do not move. "
                    + "The predecessor is the clip on the same track ending EXACTLY at this "
                    + "one's start; with a gap or an overlap there instead, it is refused (an "
                    + "overlap is a transition — use set_transition_duration). Clamped so each "
                    + "clip keeps a frame and neither asks for source it does not have.",
                ["clip": clipDescription, "to": "Where the cut moves to, \(ticks)"]),
            opTool(
                "split",
                "Cuts clips in two at `at` — Clip ▸ Split (⌘T). The second piece keeps playing the source from "
                    + "where the first stopped, and each keeps the animation actions that fall "
                    + "on its side (an action straddling the cut becomes two). With no clips "
                    + "every unlocked clip under the time is split, which is what the menu "
                    + "command does with nothing selected. Refused when `at` is not strictly "
                    + "inside a clip.",
                [
                    "clips": "Clip ids; omit to split every unlocked clip at `at`.",
                    "at": "Where to cut, \(ticks) Default: the playhead.",
                ]),
            opTool(
                "delete",
                "Removes clips and LEAVES the gaps where they were — ⌫. Use ripple_delete to "
                    + "close them.",
                ["clips": clipsDescription]),
            opTool(
                "ripple_delete",
                "Removes clips and closes the gaps: everything starting after each removed span "
                    + "on an UNLOCKED track slides left by that span's length — ⌘⌫. Clips on "
                    + "locked tracks and clips that straddle a span stay where they are.",
                ["clips": clipsDescription]),
            opTool(
                "ripple_delete_range",
                "Cuts a time range out of the whole timeline: every unlocked clip is split at "
                    + "both bounds, the middles are removed, and the rest slides left by the "
                    + "range's length. The in/out-range form of ⌘⌫.",
                ["from": "Range start, \(ticks)", "to": "Range end, \(ticks)"]),
            opTool(
                "ripple_delete_ranges",
                "Cuts SEVERAL time ranges out of the whole timeline as ONE edit — what Clip ▸ "
                    + "Remove Silences… sends. Each pair is put in order (a reversed pair is "
                    + "the same range), the pairs are then MERGED — overlapping and touching "
                    + "alike — and the survivors are cut right to left exactly as "
                    + "ripple_delete_range cuts one. So this is NOT the same as calling that "
                    + "once per pair: two ranges that meet make one shift, not two. It is one "
                    + "undo step however many ranges there are, which is the point. Markers do "
                    + "not move, as under every ripple. An empty list, and a list that merges "
                    + "to nothing, change nothing. detect_silence returns ranges in this shape.",
                ["ranges": "The spans to cut, each a [from, to] pair \(ticks)"]),
        ]
        // detect_silence and normalize_clip are `AgentCatalog+Audio.swift`'s,
        // spliced in HERE rather than appended, so the catalog's order is
        // unchanged — road map 4's toll 2. `ticks` and `clipsProperty` are
        // the two hoisted locals they read.
        rows += audioTools(ticks: ticks, clipsProperty: clipsProperty)
        rows += [
            opTool(
                "lift_range",
                "Cuts a time range out and LEAVES the hole — ⌫ with an in/out range and nothing "
                    + "selected. Every unlocked clip is split at both bounds and the middles "
                    + "removed, and nothing moves: every clip after the range keeps the moment "
                    + "it had, which is what makes this the safe cut when a mix or a caption "
                    + "track is already timed. Use ripple_delete_range to close the hole "
                    + "instead.",
                ["from": "Range start, \(ticks)", "to": "Range end, \(ticks)"]),
            opTool(
                "insert_time",
                "Opens a gap: every unlocked clip starting at or after `at` moves right by "
                    + "`length`. Straddling clips are left in place, so this makes room without "
                    + "cutting anything — split first if you want the gap inside a clip. Every "
                    + "marker at or after `at` moves right by `length` too.",
                [
                    "at": "Where the gap opens, \(ticks)",
                    "length": "How much room, \(ticks)",
                ]),
            opTool(
                "close_gap",
                "Closes the empty span on `track` that contains `at` — double-clicking a gap in "
                    + "a lane, or Clip ▸ Close Gap. The gap is bounded by the nearest clip "
                    + "edges on that track, and everything from its far side slides left by its "
                    + "length across every unlocked track. Nothing changes when `at` is on a "
                    + "clip, when the track is locked, when there is no clip after the gap, or "
                    + "when the shift would break the overlap rule — a gap closes fully or not "
                    + "at all.",
                [
                    "track": trackDescription,
                    "at": "A time inside the gap, \(ticks)",
                ]),
            opTool(
                "set_speed",
                String(
                    format: "Changes a clip's playback rate — Clip ▸ Speed… — or fits it to a "
                        + "duration — the Speed section's Fit to: give rate or duration, exactly "
                        + "one. Any non-media clip is an error. The duration follows (source "
                        + "length ÷ rate, snapped and held to what the file holds); actions keep "
                        + "their place. Rate is clamped to %g–%g. Above ×%g, with or without "
                        + "keep_pitch, the clip's audio is left out of the mix. On a clip with "
                        + "a speed ramp every rate in the ramp scales with it, so the ramp keeps "
                        + "its shape; the scale stops where any of its rates would pass the "
                        + "limits.", speed.min,
                    speed.max, speed.audioMax),
                [
                    "clip": clipDescription,
                    "rate": "1 = normal, 2 = twice as fast (half as long), 0.5 = slow motion.",
                    "duration": "The length to fit the clip to, instead of a rate \(ticks)",
                    "keep_pitch": "Keep the audio's pitch at the new speed (default: as it is).",
                ]),
            opTool(
                "set_reversed",
                "Plays a media clip back to front, or forward again — the Reverse checkbox in the "
                    + "Clip tab's Timing section. Nothing "
                    + "about the timeline moves: the clip keeps its start, its duration and its "
                    + "in point, and the in point is measured in the direction the clip plays, "
                    + "so reversing a trimmed clip shows the other end of the file. Media clips "
                    + "only: any other kind is an error. The reversed frames are pre-rendered on "
                    + "the app side the first time they are needed, so the first render_frame or "
                    + "export after this may take a moment.",
                [
                    "clip": clipDescription,
                    "reversed": "true plays it backwards, false forwards again.",
                ]),
            opTool(
                "freeze_frame",
                "Holds one frame: the clip is split at `at`, a gap of `duration` is opened, and "
                    + "a still of that exact source frame fills it with the clip's own video "
                    + "properties — ⇧⌘F. Media clips only.",
                [
                    "clip": clipDescription,
                    "at": "The moment to freeze, \(ticks) Default: the playhead.",
                    "duration": "How long to hold \(ticks) Default 2 s (1200000).",
                ]),
            opTool(
                "detach_audio",
                "Splits a clip's audio onto its own clip on the track below (inserting one when "
                    + "there is none), muting the original's audio and hiding the new clip's "
                    + "video — ⌥⌘D. The two can then be trimmed and moved apart. Refused, saying "
                    + "why, for a non-media clip, media with no audio, or audio already detached.",
                ["clip": clipDescription]),
            opTool(
                "duplicate",
                "Copies clips onto the same tracks, placed immediately after the originals' "
                    + "span — ⌘D. Follow with move_clip to put them anywhere else.",
                ["clips": clipsDescription]),
            opTool(
                "paste",
                "Inserts a clipboard payload's clips with fresh ids — ⌘V. The earliest clip in "
                    + "the payload lands exactly at `at` and the others keep their offsets from "
                    + "it, so a copied arrangement pastes back intact. The payload is what Copy "
                    + "(⌘C) put on the pasteboard: {\"clips\": [...], \"media\": [...]}, whose "
                    + "clips are get_project's clip objects and whose media are its media rows. "
                    + "TWO things differ from get_project's spelling. A payload clip's `track` "
                    + "is a DEPTH from the front of the track stack (0 = front-most, 1 the lane "
                    + "behind it), not a track id, because the ids belong to the project it was "
                    + "copied from; and media is matched to this project's media[] BY PATH, so a "
                    + "row it does not have is added and one it does is reused. Ids in the "
                    + "payload are ignored — everything is re-minted. A clip the overlap rule "
                    + "refuses on its target track is placed on a new track in front rather "
                    + "than dropped.",
                [
                    "at": "Where the earliest clip lands, \(ticks) Default: the "
                        + "playhead.",
                    "track": "Track id for the payload's depth 0; the rest follow by "
                        + "the same offset. Default: the front-most track.",
                    "payload": "{\"clips\": [...], \"media\": [...]} — see above.",
                ]),
            opTool(
                "paste_attributes",
                "Copies the payload's EARLIEST clip's property groups onto each of the clips — "
                    + "Edit ▸ Paste Attributes (⌥⌘V). The payload is the same Copy payload paste "
                    + "takes; only its earliest clip is read (at one start the front-most, then "
                    + "the lower id — never the array's first, which is creation order), and its "
                    + "ids and media rows do not matter. Each group REPLACES the target's whole "
                    + "group — video and audio whole (position and scale included), text but its "
                    + "content, a shape but its kind, width, height, from and to. Left out, "
                    + "`groups` means each of video, audio, text and shape BOTH clips have, "
                    + "silently skipping the rest; a named group the payload clip lacks, or a "
                    + "target lacks, is an error, and so is a value the inspector would refuse. "
                    + "`graphic` travels only when NAMED (Edit ▸ Paste Graphic Properties): the "
                    + "props, whole, onto clips drawn by the SAME graphic, each keeping its name, "
                    + "size, in and length, and any prop the payload lacks that an action on that "
                    + "clip animates, which stays so the ramp keeps its start; a clip of another "
                    + "graphic is an error naming both. The props are checked for shape only, when "
                    + "a target takes them. Speed, enabled, actions, the transition and the clip's "
                    + "own name and label stay. A video qualifier follows the clip kind: dropped "
                    + "onto a picture clip, an adjustment clip's own kept when the payload clip is "
                    + "not an adjustment clip, copied between two. Refused (no change) when "
                    + "nothing changes.",
                [
                    "clips": clipsDescription,
                    "payload": "What Copy wrote, {\"clips\": [...], \"media\": [...]}; see paste.",
                    // The names are the CORE's (`Kind::Groups`); a refusal names the handler's.
                    "groups": "Which groups travel. Default: each of video, audio, text and "
                        + "shape both clips have, never graphic; an empty list is refused.",
                    "skip_missing": "true: with groups named, a group the payload clip lacks is "
                        + "dropped and a clip that cannot take one is skipped. Default false.",
                ]),
            opTool(
                "nest",
                "Collapses clips into ONE clip that stands for the group — ⌘G. The clips move "
                    + "whole (properties, actions, transitions) onto the nest's own tracks, "
                    + "keeping their relative times and their stacking order with the earliest "
                    + "starting at 0; the nest clip lands on the front-most track the selection "
                    + "occupied and runs from the earliest start to the latest end. From then on "
                    + "the group moves, trims, fades and transforms as one thing, and the "
                    + "nest's canvas is frozen at the project's current size so a later "
                    + "set_canvas cannot re-lay-out what is inside. get_project lists the groups "
                    + "under `nests`, each with its own tracks and clips. Refused (no change) on "
                    + "an empty selection, on a single clip that is already a nest, and when the "
                    + "nest clip would overlap something that was not selected.",
                [
                    "clips": clipsDescription,
                    "name": "What to call the group. Default: Nest <n>.",
                ]),
            opTool(
                "unnest",
                "Opens a nest clip: its contents return to the timeline and the nest clip goes — "
                    + "⇧⌘G. The exact inverse of nest apart from the ids, which are minted "
                    + "fresh. Clips land at the nest clip's start plus their own, on tracks "
                    + "counted back from the nest clip's own (tracks missing behind it are "
                    + "added), and one the overlap rule refuses goes on a new track in front "
                    + "rather than being dropped. A nest clip trimmed shorter than its contents "
                    + "gives ALL of them back — trimming a nest hides content rather than "
                    + "cutting it. An error on any clip that is not a nest.",
                ["clip": clipDescription]),
        ]
        // set_video, set_audio, set_text, set_shape and set_clip are
        // `AgentCatalog+Properties.swift`'s, spliced in HERE, after `unnest`,
        // so the catalog's order is unchanged.
        rows += propertyTools(clipsDescription: clipsDescription)
        rows += [
            opTool(
                "set_enabled",
                "Turns one clip's video and/or audio on or off — the two halves detach_audio "
                    + "flips. A disabled half contributes nothing to the composition but the "
                    + "clip stays where it is.",
                [
                    "clip": clipDescription,
                    "video": "Show this clip's picture.",
                    "audio": "Play this clip's sound.",
                ]),
            opTool(
                "set_transition",
                "Sets the transition INTO a clip — the one that plays across its overlap with "
                    + "the clip before it on the same track. The transition's duration IS that "
                    + "overlap, so a clip with no overlap ignores it: make one with move_clip or "
                    + "set_transition_duration. kind null removes it.",
                [
                    "clip": clipDescription,
                    // The null beside the core's thirteen names, and the
                    // required-ness that keeps a forgotten kind from becoming
                    // one, are both declared rows
                    // (`AgentCatalog+Declarations.swift`).
                    "kind": "The transition, or null to remove it.",
                ]),
            opTool(
                "set_transition_duration",
                "Makes a clip's transition last `duration` by MOVING the clip so its overlap "
                    + "with the clip before it equals that. Refused on a track's first clip and past "
                    + "half the shorter clip (snapped down), naming that limit.",
                ["clip": clipDescription, "duration": "Overlap length, \(ticks)"]),
        ]
        rows += actionTools(ticks: ticks, clipDescription: clipDescription)
        return rows
    }
}
