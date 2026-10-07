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
        let shapeNames = ShapeKind.allCases.map { $0.rawValue }
        let filterNames = FilterKind.allCases.map { $0.rawValue }
        let obscureNames = ObscureKind.allCases.map { $0.rawValue }
        let speed = ReelSpeed.limits  // set_speed's numbers, all the core's (spec §11 #190)
        // The obscure list's clause, kept as its own explicitly-typed local
        // rather than spliced into the video chain below: that chain already
        // carries a non-literal operand and is one of the three expressions
        // this file records tipping the type checker's budget.
        let obscureClause: String =
            ", obscure (an ARRAY of {shape: rect|ellipse, x, y, width, height, feather, kind, "
            + "amount} that HIDES what is under each one, at most \(ObscureProps.max) — kind is "
            + "\(obscureNames.joined(separator: "|")) and amount is 0–1, feather is the source "
            + "px the effect ramps in over, and the centre and the box are SOURCE px from the "
            + "cropped rect's centre, the same frame the spotlight uses. Like filters it is "
            + "replaced whole rather than merged, so send the whole array and [] to clear it)"
        // `video.blend`'s clause, its own explicitly-typed local for the
        // reason `obscureClause` is: the mode names are a non-literal operand
        // and the video chain below already carries one.
        //
        // The trap is named in the text rather than left to be discovered,
        // because it is the first thing a caller meets: over the empty canvas
        // half the modes render BLACK and the other half do nothing at all, so
        // a blend set on the only clip in a project looks broken either way.
        let blendNames = BlendMode.allCases.map { $0.rawValue }
        let blendClause: String =
            ", blend (how this layer combines with what is already on the canvas: "
            + "\(blendNames.joined(separator: "|")) — normal is source-over, which is what "
            + "every project drew before this key existed. A blend needs something UNDER it: "
            + "over the empty canvas multiply, darken and overlay read black while screen, "
            + "add, lighten and difference change nothing, so add_background is usually the "
            + "call before this one. It is forced to normal for the length of a cross "
            + "dissolve, whose own weighting requires it, so what the frame shows there can "
            + "legitimately differ from the value get_project reports)"
        // `video.motion`'s clause, its own explicitly-typed local for
        // `blendClause`'s reason: two non-literal operands (the two kind
        // lists) and a video chain that is long enough already.
        //
        // Three things are in the text because a caller meets each of them
        // immediately: that it MERGES slot by slot like every other nested
        // object (deepening D1·3 — the agent door used to replace the whole
        // object, and the two Swift writers still send all three slots, which
        // is the same thing said a different way); that it is not an
        // animation target; and that get_project reports the clip UN-MOVED,
        // which is what makes an edit work on the numbers a person typed and
        // would otherwise read as the tool ignoring the preset.
        let edgeNames = EdgeMotion.allCases.map { $0.rawValue }
        let duringNames = DuringMotion.allCases.map { $0.rawValue }
        let motionClause: String =
            ", motion (what the clip DOES: null, or {in, out, during} — in and out are "
            + "{kind: \(edgeNames.joined(separator: "|")), duration: ticks} measured from the "
            + "clip's first and last frame, during is {kind: "
            + "\(duringNames.joined(separator: "|")), amount: 0–1, period: ticks} over the "
            + "whole clip and drift ignores its period. Like every other object here it "
            + "MERGES: a slot you leave out keeps what is stored, a slot set to null clears "
            + "that slot, {motion: null} clears the whole preset, and a motion with no slot "
            + "left reads back as null. The two durations are snapped to the document's "
            + "frame grid and the period is snapped with a floor of ONE frame (it divides "
            + "in every during formula and has no zero), so get_project can answer with a "
            + "tick count near the one you sent rather than the one itself. "
            + "in + out longer than the clip scales both down to "
            + "meet rather than refusing. It is NOT an animation target — set_action_end "
            + "refuses it — and get_project reports the clip UN-MOVED, since the preset "
            + "becomes placement only when a frame is rendered)"
        // The three patch vocabularies, written once: every property group of
        // spec §5.2, with the ranges the ops enforce. A patch MERGES, so a key
        // left out keeps its current value and a key set to null clears an
        // optional group (shadow, chroma, duck, outline, backdrop, and text's
        // width, which null restores to auto-sizing).
        // Explicitly typed for the same reason `shapePatchDescription` is: the
        // `+` chain now carries a non-literal operand (the filter kinds), and
        // an inferred type here is what tips the `catalog` literal past the
        // type checker's budget.
        let videoPatchDescription: String =
            "Video properties to merge into the clip's base props. Keys: x, y (canvas px from "
            + "the canvas centre, y DOWN), scale (1 = native pixels, 0.01–10), rotation "
            + "(degrees, positive turns clockwise on screen), opacity (0–1), crop "
            + "({l, t, r, b} in SOURCE px — cropping never shifts the content), corner_radius "
            + "(source px), shadow (null or {color, opacity, blur, angle, distance}), color "
            + "({brightness, contrast, saturation, hue}, each 0 = unchanged), chroma (null or "
            + "{key: [r, g, b], tolerance, softness, spill}), filters (an ARRAY of "
            + "{kind, amount} applied in order, at most 4 — kind is "
            + "\(filterNames.joined(separator: "|")) and amount is 0–1; send the whole array, "
            + "since it replaces rather than merges, and [] clears the stack), reflection "
            + "(null or {opacity, height, gap, falloff} — height and falloff are fractions of "
            + "the layer's cropped height, gap is source px), spotlight (null or "
            + "{shape: rect|ellipse, x, y, width, height, feather, dim, zoom} — the centre and "
            + "the box are SOURCE px from the cropped rect's centre, dim is how much darker it "
            + "is OUTSIDE and zoom 1–2 magnifies what is inside)"
            + obscureClause
            + blendClause
            + motionClause
            + ". A colour is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
            + "length and a component outside the range is refused by name, neither "
            + "filled in nor clamped. chroma's key is the one exception, three numbers "
            + "with no alpha."
        let audioPatchDescription =
            "Audio properties to merge. Keys: volume (0–4, 1 = unity), muted, fade_in, "
            + "fade_out (ticks), duck (null or {level, attack, release}), mono, keep_pitch, "
            + "pan (-1 hard left … +1 hard right), compressor (null or {threshold_db, ratio, "
            + "attack, release, makeup_db} — the two times in ticks), noise_reduction (0–1). "
            + "duck and compressor are OBJECTS and they MERGE: a key you leave out keeps what "
            + "is stored, and {duck: null} clears the whole thing."
        // `text.animation`'s clause, its own explicitly-typed local for the
        // reason `obscureClause` is: the kind names are a non-literal operand
        // and the text chain is long enough already.
        let animationNames = TextAnimationKind.allCases.map { $0.rawValue }
        let animationClause: String =
            ", animation (null or {kind: \(animationNames.joined(separator: "|")), in, out} — "
            + "how the words arrive and leave. in and out are DURATIONS in ticks measured from "
            + "the clip's own first and last frame, not times; either may be 0 for no ramp at "
            + "that end, and in + out longer than the clip simply shows a partial reveal, and "
            + "both are snapped to the document's frame grid. Like shadow and backdrop it "
            + "MERGES: a key you leave out keeps what is stored, and {animation: null} clears "
            + "the whole thing)"
        let textPatchDescription: String =
            "Text properties to merge. Keys: content, font (a PostScript name), size (px), "
            + "color, align (left|center|right), valign (top|middle|bottom), line_spacing, "
            + "tracking, outline (null or {width, color}), backdrop (null or {color, padding, "
            + "radius}), width (null for auto-sizing, or a wrap width in px)"
            + animationClause + Self.textWordsClause
            + ". A colour is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
            + "length and a component outside the range is refused by name, neither "
            + "filled in nor clamped."
        // `shape.gradient`'s clause, its own local for the budget reason the
        // other hoisted clauses give. It used to be worth a line of its own as
        // the only patch member that named its own mistakes, the shape patch
        // being hand-read rather than decoded; since D1·1 the core names a
        // misspelt key inside ANY nested object by its dotted path, stop
        // indices included, so the gradient is no longer the exception.
        let gradientKindNames = GradientKind.allCases.map { $0.rawValue }
        let gradientClause: String =
            ", gradient (null, or {kind: \(gradientKindNames.joined(separator: "|")), "
            + "stops: [{at, color}], angle} — a gradient FILL, which takes precedence over "
            + "fill while it is set and leaves it in place, so {\"gradient\": null} restores "
            + "the colour underneath. 2 to \(Gradient.maxStops) stops, each at 0–1 along the "
            + "ramp; the stops need NOT be sorted, and the renderer sorts them. angle is "
            + "degrees from the RIGHT turning counter-clockwise, the convention shadow's angle "
            + "uses, and means nothing for radial, which is an ellipse inscribed in the box. "
            + "line and arrow have no area and ignore it. Like stroke it MERGES: a key you "
            + "leave out keeps what is stored, {gradient: null} clears it and brings the flat "
            + "fill back out, and the stops are a LIST, so sending one replaces them all)"
        // Interpolated rather than concatenated: a `+` chain this long with
        // a non-literal operand in it is what tips the whole `catalog`
        // literal past the type checker's budget.
        let shapePatchDescription: String =
            "Shape properties to merge. Keys: kind "
            + "(\(shapeNames.joined(separator: "|"))), width, height (the box, in source px), "
            + "stroke (null or {width, color}), fill (null or a colour), radius (rectangle "
            + "corners), arrow_start, arrow_end, and from / to — the endpoints of a line or "
            + "arrow as UNIT coordinates in its box, e.g. from [0, 1] to [1, 0]"
            + gradientClause
            + ". A colour is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
            + "length and a component outside the range is refused by name, neither "
            + "filled in nor clamped."
        // The fifth patch, `set_clip`'s. The label names are `ClipLabel`'s —
        // the one home of the marker-colour vocabulary — read rather than
        // restated, and typed for the same budget reason as the four above.
        let labelNames = ClipLabel.allCases.map { $0.rawValue }
        let clipPatchDescription: String =
            "name and/or label; a key set to null clears it. Labels are the marker colours: "
            + "\(labelNames.joined(separator: ", "))."
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
                        + "timed media is NOT clamped to its own length, so a short movie "
                        + "used here shows nothing for the rest of the timeline.",
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
                    + "clip is at least one frame long).",
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
                    + "source to stretch and is an error.",
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
                "Cuts clips in two at `at` — ⌘K. The second piece keeps playing the source from "
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
                    + "cutting anything — split first if you want the gap inside a clip.",
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
                        + "keep_pitch, the clip's audio is left out of the mix.", speed.min,
                    speed.max, speed.audioMax),
                [
                    "clip": clipDescription,
                    "rate": "1 = normal, 2 = twice as fast (half as long), 0.5 = slow motion.",
                    "duration": "The length to fit the clip to, instead of a rate \(ticks)",
                    "keep_pitch": "Keep the audio's pitch at the new speed (default: as it is).",
                ]),
            opTool(
                "set_reversed",
                "Plays a media clip back to front, or forward again — Clip ▸ Reverse. Nothing "
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
                    + "own name and label stay. Refused (no change) when nothing changes.",
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
            opTool(
                "set_video",
                "Changes the clips' BASE video properties — position, scale, rotation, opacity, "
                    + "crop, corner radius, shadow, colour, chroma key, filters, reflection, "
                    + "spotlight and motion (what the clip does on its way in, on its way out "
                    + "and all the way through). The patch MERGES AT EVERY DEPTH: keys you "
                    + "leave out keep their values, inside a nested object too — a patch of "
                    + "just {shadow: {blur: 20}} keeps the shadow's colour, angle and "
                    + "distance — and shadow, chroma, reflection, spotlight or motion set to "
                    + "null clears it. A LIST is the exception: filters and obscure each "
                    + "replace whole, so send the whole stack and [] to clear it. A key or a "
                    + "value the vocabulary does not have is an error naming its dotted path "
                    + "(array indices included) and the value you sent; nothing is dropped, "
                    + "corrected or clamped. "
                    + "Placement is spec §5.3: the source rectangle is centred at the "
                    + "canvas centre plus (x, y), scaled, then rotated about that centre, and "
                    + "crop removes edges in place without shifting the content. To animate a "
                    + "property instead, add_action and then set_action_end.",
                ["clips": clipsDescription, "patch": videoPatchDescription]),
            opTool(
                "set_audio",
                "Changes the clips' BASE audio properties — volume, mute, fades, ducking, mono, "
                    + "pitch preservation, pan, compression and noise reduction. Merges like "
                    + "set_video; duck or compressor set to null removes it.",
                ["clips": clipsDescription, "patch": audioPatchDescription]),
            opTool(
                "set_text",
                "Changes a text clip's words and typography. Merges like set_video; outline, "
                    + "backdrop and width set to null clear them (a null width restores "
                    + "auto-sizing). Position and scale are set_video's, not this tool's.",
                ["clips": clipsDescription, "patch": textPatchDescription]),
            opTool(
                "set_shape",
                "Changes a shape clip's geometry and paint. Merges like set_video; stroke or "
                    + "fill set to null removes that half of the paint. Position and scale are "
                    + "set_video's, not this tool's. Changing kind changes ONLY the kind — an "
                    + "arrow made this way keeps whatever arrow_end it had, unlike one created "
                    + "by add_shape_clip.",
                ["clips": clipsDescription, "patch": shapePatchDescription]),
            opTool(
                "set_clip",
                "Names or labels clips — the timeline's inline rename (double-click the name "
                    + "strip), the Clip tab's name field, Clip ▸ Rename… (⇧⌘R) and Clip ▸ "
                    + "Label ▸. A clip with no name of its own shows what it holds — the nest, "
                    + "the media file, or its kind — and clearing the name returns to that. "
                    + "The patch merges like set_video: a key left out keeps its value, null "
                    + "clears it, and so does an empty or blank name (names are trimmed). A "
                    + "split, duplicate, detach or paste carries both along; paste_attributes "
                    + "never does. The label is a colour name drawn as a dot on the clip, "
                    + "stored as given, so keep to the six names.",
                ["clips": clipsDescription, "patch": clipPatchDescription]),
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
