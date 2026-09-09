import Foundation

// MARK: - Catalog: clips and actions

/// The catalog's CLIP half: the forty tools a timeline's clips get — making
/// one, placing it, cutting it, describing it — the five that ANIMATE one, and
/// the property-group patch vocabulary all forty-five are written in. Two of
/// the forty-five are not ops (`detect_silence` and `normalize_clip`, the
/// composites phases 3 and 5 added); the other forty-three are spec §6 rows.
///
/// A pure move out of `AgentCatalog.swift`, which stood at 1552 lines against
/// app/CLAUDE.md's ~600 cap with road map 2's phase 9 about to put a `scope`
/// property on every op tool's schema and a `set_scope` tool beside them. The
/// seam is the one the file had already drawn: `// MARK: Clips` and
/// `// MARK: Actions` came here whole, in their existing order, with their
/// bodies untouched, and so did the twenty-four hoisted locals nothing outside
/// them reads — the five patch descriptions, the enum-name lists and clauses
/// they are built from, and `rangesProperty`, `zoomRegionProperty` and
/// `groupsProperty`.
///
/// **The actions travel with the clips**, which is the one decision in the
/// cut: `set_action_end` takes the very `video` / `audio` / `text` patches
/// `set_video`, `set_audio` and `set_text` take, so a boundary between them
/// would have left one vocabulary spelt on both sides of it — and an action is
/// a clip's own span in CLIP time, not an object of its own.
///
/// What stayed behind is what a SECOND group also asks: `ticks` is every
/// group's, `trackProperty` is Tracks' as well and `colorProperty` is Canvas',
/// so the three arrive as ARGUMENTS rather than as a second spelling here.
/// This array is spliced back in where it was rather than appended, because
/// the catalog's order is the order an agent reads the tools in.
///
/// **The toll is one widening**: `tool(_:_:_:required:)` is internal rather
/// than private, since `private` on an extension member reaches only its own
/// file and every entry below is built with it. `projectProperty` and
/// `ticksNote` did NOT have to follow it — the first is read only inside
/// `tool`, which did not move, and the second only into the `ticks` argument.
extension AgentServer {

    /// The clip and action rows of `catalogJSON()`'s array, in its order.
    func clipAndActionTools(
        ticks: String, trackProperty: [String: Any],
        colorProperty: (String) -> [String: Any]
    ) -> [[String: Any]] {
        let clipsProperty: [String: Any] = [
            "type": "array", "items": ["type": "integer"], "minItems": 1,
            "description": "Clip ids (get_project lists them).",
        ]
        let clipProperty: [String: Any] = [
            "type": "integer", "description": "Clip id (get_project lists them).",
        ]
        let shapeNames = ShapeKind.allCases.map { $0.rawValue }
        let filterNames = FilterKind.allCases.map { $0.rawValue }
        let transitionNames = TransitionKind.allCases.map { $0.rawValue }
        // `null` is a legal value of `set_transition`'s kind — it is how a
        // transition is removed — so the enum has to carry it beside the
        // names, which makes the array heterogeneous.
        var transitionEnum: [Any] = transitionNames
        transitionEnum.append(NSNull())
        let curveNames = Curve.allCases.map { $0.rawValue }
        let obscureNames = ObscureKind.allCases.map { $0.rawValue }
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
            + ". A colour is [r, g, b] or "
            + "[r, g, b, a], each 0–1; chroma's key is the one that takes no alpha."
        let audioPatchDescription =
            "Audio properties to merge. Keys: volume (0–4, 1 = unity), muted, fade_in, "
            + "fade_out (ticks), duck (null or {level, attack, release}), mono, keep_pitch, "
            + "pan (-1 hard left … +1 hard right), compressor (null or {threshold_db, ratio, "
            + "attack, release, makeup_db} — the two times in ticks), noise_reduction (0–1)."
        // `text.animation`'s clause, its own explicitly-typed local for the
        // reason `obscureClause` is: the kind names are a non-literal operand
        // and the text chain is long enough already.
        let animationNames = TextAnimationKind.allCases.map { $0.rawValue }
        let animationClause: String =
            ", animation (null or {kind: \(animationNames.joined(separator: "|")), in, out} — "
            + "how the words arrive and leave. in and out are DURATIONS in ticks measured from "
            + "the clip's own first and last frame, not times; either may be 0 for no ramp at "
            + "that end, and in + out longer than the clip simply shows a partial reveal. Like "
            + "shadow and backdrop it is an OBJECT and is REPLACED whole rather than merged, so "
            + "send every key you want: one you leave out arrives as its default, a 1 s "
            + "typewriter with no un-reveal)"
        let textPatchDescription: String =
            "Text properties to merge. Keys: content, font (a PostScript name), size (px), "
            + "color, align (left|center|right), valign (top|middle|bottom), line_spacing, "
            + "tracking, outline (null or {width, color}), backdrop (null or {color, padding, "
            + "radius}), width (null for auto-sizing, or a wrap width in px)"
            + animationClause
            + ". A colour is [r, g, b] or [r, g, b, a], each 0–1."
        // `shape.gradient`'s clause, its own local for the budget reason the
        // other hoisted clauses give — and worth a line of its own, because it
        // is the one patch member that names its own mistakes: the shape patch
        // is built by hand rather than decoded, so a key misspelt INSIDE
        // gradient is refused by name, which shadow, chroma and an obscure
        // region cannot manage.
        let gradientKindNames = GradientKind.allCases.map { $0.rawValue }
        let gradientClause: String =
            ", gradient (null, or {kind: \(gradientKindNames.joined(separator: "|")), "
            + "stops: [{at, color}], angle} — a gradient FILL, which takes precedence over "
            + "fill while it is set and leaves it in place, so {\"gradient\": null} restores "
            + "the colour underneath. 2 to \(Gradient.maxStops) stops, each at 0–1 along the "
            + "ramp; the stops need NOT be sorted, and the renderer sorts them. angle is "
            + "degrees from the RIGHT turning counter-clockwise, the convention shadow's angle "
            + "uses, and means nothing for radial, which is an ellipse inscribed in the box. "
            + "line and arrow have no area and ignore it. Like stroke it is an OBJECT and is "
            + "REPLACED whole rather than merged, so send every key you want)"
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
            + ". A colour is [r, g, b] or [r, g, b, a], each 0–1."
        // The fifth patch, `set_clip`'s. The label names are `ClipLabel`'s —
        // the one home of the marker-colour vocabulary — read rather than
        // restated, and typed for the same budget reason as the four above.
        let labelNames = ClipLabel.allCases.map { $0.rawValue }
        let clipPatchDescription: String =
            "name and/or label; a key set to null clears it. Labels are the marker colours: "
            + "\(labelNames.joined(separator: ", "))."
        // `ripple_delete_ranges`' list of pairs and `add_zoom_action`'s
        // region, hoisted out of the `catalog` literal for the same reason
        // the patch descriptions above are: a nested schema written inline
        // there is the kind of expression that tips the whole literal past
        // the type checker's budget.
        let rangesProperty: [String: Any] = [
            "type": "array", "minItems": 1,
            "items": [
                "type": "array", "items": ["type": "integer"], "minItems": 2, "maxItems": 2,
            ] as [String: Any],
            "description": "The spans to cut, each a [from, to] pair \(ticks)",
        ]
        // `region` is nullable — null is the zoom BACK — and REQUIRED, which
        // is the one place that distinction can be made: the op reads an
        // absent argument and an explicit null the same way, so a forgotten
        // rectangle would silently become the opposite edit.
        let zoomRegionProperty: [String: Any] = [
            "type": ["object", "null"],
            "properties": [
                "x": ["type": "number", "description": "The region's CENTRE, source px."],
                "y": ["type": "number", "description": "The region's CENTRE, source px."],
                "width": ["type": "number", "description": "Its width in source px."],
                "height": ["type": "number", "description": "Its height in source px."],
            ] as [String: Any],
            "required": ["x", "y", "width", "height"],
            "description": "The rectangle to zoom to, in SOURCE pixels: x and y are its "
                + "CENTRE measured from the centre of the clip's cropped rect — the frame "
                + "video.spotlight and video.obscure use — and width and height its size. "
                + "null is a zoom BACK to the clip's own scale and position; the key is "
                + "required so a forgotten rectangle cannot become that by accident.",
        ]
        // `paste_attributes`'s group list, its enum read from the handler's
        // own list so the schema and the check cannot disagree.
        let groupsProperty: [String: Any] = [
            "type": "array", "minItems": 1,
            "items": ["type": "string", "enum": Self.attributeGroups] as [String: Any],
            "description": "Which property groups travel. Default: every group both clips "
                + "have; an empty list is refused.",
        ]
        return [

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
                    // The op takes a set_text PATCH (`core/src/edit.rs`), and
                    // this used to declare a bare string — so an object was
                    // read as absent and the clip got the placeholder. Both
                    // forms are declared because a string and an object can
                    // never be confused for one another, and the string is
                    // the spelling every caller written against the old tool
                    // already uses.
                    "text": [
                        "type": ["object", "string"],
                        "description": "The words, or the styling too. A plain string is "
                            + "shorthand for {\"content\": …}; an object is a set_text patch "
                            + "merged over the Title preset. " + textPatchDescription
                            + " Default: the Title preset's placeholder.",
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
                    // Optional, as the op is: omitted, the core's default
                    // rectangle lands. Declaring it a REQUIRED kind name put
                    // that default out of reach and made the box and the
                    // paint need a following set_shape.
                    "shape": [
                        "type": ["object", "string"],
                        "description": "Which shape, and how it is drawn. A plain string is a "
                            + "kind — " + shapeNames.joined(separator: ", ")
                            + " — and an object is a set_shape patch merged over the default "
                            + "rectangle. " + shapePatchDescription + " Omit it for that "
                            + "rectangle; a rounded one is a rectangle with a radius, not a "
                            + "kind of its own. An arrow is created with its head on — pass "
                            + "arrow_end: false for a bare diagonal.",
                    ],
                ], required: ["track", "at"]),
            tool(
                "add_background",
                "Puts a backdrop on a NEW back-most track, starting at 0 and running the "
                    + "timeline's length — Clip ▸ Add Background. With no arguments at all it "
                    + "is a canvas-sized WHITE rectangle, which is what the menu's Solid Color "
                    + "row sends: white rather than black because the canvas is already black, "
                    + "so a black plate would be a command that appears to do nothing. Give it "
                    + "a color to paint the plate another colour, or a media to put that "
                    + "picture there instead, at FILL scale — where add_clip would Fit it, "
                    + "because a plate that leaves the canvas showing down one side has "
                    + "failed at the one thing a background is for. A full-canvas GRADIENT is this "
                    + "clip and a set_shape {gradient} after it. media and color are "
                    + "alternatives: passing both is an error, and so is a duration under one "
                    + "frame or a media with no pictures.",
                [
                    "media": [
                        "type": "integer",
                        "description": "Media id to show as the background — get_project lists "
                            + "them and import_media adds a file. Omit for a colour plate. A "
                            + "timed media is NOT clamped to its own length, so a short movie "
                            + "used here shows nothing for the rest of the timeline.",
                    ],
                    "color": colorProperty("The plate's colour; white when omitted"),
                    "duration": [
                        "type": "integer",
                        "description": "Length \(ticks) Default: the whole timeline's length, "
                            + "and never less than one frame.",
                    ],
                ]),
            tool(
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
                ["clip": clipProperty], required: ["clip"]),
            tool(
                "insert_clip",
                "The INSERT edit — Edit ▸ Insert at Playhead, or ⌥-dropping a Media-tab row. "
                    + "Makes room for the whole media at `at`: the clip `at` is inside on "
                    + "`track` is split first, then every unlocked track opens by the media's "
                    + "length, then the media lands in the hole. Only the destination track is "
                    + "cut — a clip straddling `at` on another track rides the shift whole, "
                    + "which is what keeps a music bed unbroken. One undo step.",
                [
                    "track": trackProperty,
                    "media": [
                        "type": "integer",
                        "description": "Media id — import_media returns one.",
                    ],
                    "at": ["type": "integer", "description": "Where to insert, \(ticks)"],
                ], required: ["track", "media", "at"]),
            tool(
                "overwrite_clip",
                "The OVERWRITE edit — Edit ▸ Overwrite at Playhead, or ⇧⌥-dropping a Media-tab "
                    + "row. Takes the room instead of making it: the span the media needs is "
                    + "cleared on `track` ALONE — cut at both bounds, whatever is left inside "
                    + "removed — and nothing shifts, so the cut's length and every other track "
                    + "are untouched. One undo step.",
                [
                    "track": trackProperty,
                    "media": [
                        "type": "integer",
                        "description": "Media id — import_media returns one.",
                    ],
                    "at": ["type": "integer", "description": "Where to overwrite, \(ticks)"],
                ], required: ["track", "media", "at"]),
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
                "slip",
                "Slides the SOURCE under a fixed clip — ⌥⇧-dragging a clip's body. What the "
                    + "clip shows changes; where it sits does not, so nothing downstream moves. "
                    + "`delta` is timeline ticks and the source moves by delta × the clip's "
                    + "speed; a positive delta shows LATER material. Clamped so the window "
                    + "stays inside the media, and a slip the clamps reduce to nothing changes "
                    + "nothing. A freeze clip moves the frame it holds instead. Media and "
                    + "freeze clips only: any other kind is an error.",
                [
                    "clip": clipProperty,
                    "delta": [
                        "type": "integer",
                        "description": "How far to slide the source, \(ticks)",
                    ],
                ], required: ["clip", "delta"]),
            tool(
                "roll",
                "Moves a hard CUT — ⌥⇧-dragging a clip's edge. This clip's start and its "
                    + "predecessor's end both become `to`: one clip grows by exactly what the "
                    + "other loses, and the pair's outer edges and total length do not move. "
                    + "The predecessor is the clip on the same track ending EXACTLY at this "
                    + "one's start; with a gap or an overlap there instead, nothing changes (an "
                    + "overlap is a transition — use set_transition_duration). Clamped so each "
                    + "clip keeps a frame and neither asks for source it does not have.",
                [
                    "clip": clipProperty,
                    "to": ["type": "integer", "description": "Where the cut moves to, \(ticks)"],
                ], required: ["clip", "to"]),
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
                ["ranges": rangesProperty], required: ["ranges"]),
            tool(
                "detect_silence",
                "Finds the quiet stretches of the timeline and REPORTS them, changing nothing "
                    + "— the read half of Clip ▸ Remove Silences…, whose Remove button sends "
                    + "the answer to ripple_delete_ranges. Quiet is measured IN THE MIX: each "
                    + "10 ms of a clip's cached waveform times the audio envelope at that "
                    + "moment, so volume, fades, ducking, mute and another track's solo all "
                    + "count. A run quieter than threshold_db and at least min_length long is "
                    + "a candidate; it then loses padding at each end, and its bounds snap "
                    + "INWARD to the frame grid — which can leave a frame of room tone, where "
                    + "outward would clip the attack of the next word. A moment no clip in "
                    + "scope covers is not a candidate at all: a hole in the timeline is not "
                    + "dead air. The result reports the scope it used, and names any media "
                    + "whose waveform is still being analysed rather than counting it silent.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Analyse only these clips — the sheet's Selected "
                            + "clips scope. Omit to take the sheet's own opening rule: the "
                            + "project's current selection when it holds anything with sound, "
                            + "every audible clip otherwise. The result says which ran.",
                    ],
                    "threshold_db": [
                        "type": "number", "maximum": 0,
                        "description": "Quieter than this counts as silence, in dBFS in the "
                            + "mix. Default -40.",
                    ],
                    "min_length": [
                        "type": "integer",
                        "description": "The shortest quiet run worth cutting, \(ticks) "
                            + "Default 0.5 s (300000).",
                    ],
                    "padding": [
                        "type": "integer",
                        "description": "Left at each end of every candidate, \(ticks) "
                            + "Default 0.1 s (60000).",
                    ],
                ]),
            tool(
                "normalize_clip",
                "Sets each clip's audio volume so its own loudest moment lands at peak_db — "
                    + "the Normalize button in the Clip tab's Volume section, and Clip ▸ "
                    + "Normalize. The level is measured from the clip's cached waveform over "
                    + "the part of it that actually plays, which is PRE-FADER: it knows "
                    + "nothing about the volume, fades, ducking, mute or solo already on the "
                    + "clip, because normalise is a statement about the material and not "
                    + "about the mix. Three things follow, and each is a decision rather than "
                    + "an accident. It REPLACES volume rather than multiplying it, so a "
                    + "second call changes nothing (and comes back as \"made no change\", "
                    + "which is that working). It writes the clip's BASE volume even when the "
                    + "playhead is inside an action, since it is about the whole clip — a "
                    + "clip whose volume is animated is normalised underneath and then "
                    + "overridden for the action's span. And it leaves muted alone: a mute is "
                    + "a switch, not a level. Each clip gets its OWN gain, so this does not "
                    + "match levels across a selection. One undo step however many clips. "
                    + "The model's volume ceiling is 4×, so a clip quieter than about "
                    + "-13 dBFS cannot reach -1: it is still normalised, as loud as it goes, "
                    + "and result_db says where it landed. A clip that plays no sound, one "
                    + "that is silent over the part that plays, and one whose waveform has "
                    + "not been analysed yet are each reported by name under skipped and the "
                    + "rest are still normalised.",
                [
                    "clips": clipsProperty,
                    "peak_db": [
                        "type": "number", "minimum": -60, "maximum": 0,
                        "description": "Where the loudest moment should land, in dBFS. "
                            + "Default -1, which is what the button uses: hot enough to use "
                            + "the format, with a decibel of room for the inter-sample peaks "
                            + "a lossy encoder can add. Above 0 is a request to clip and is "
                            + "refused rather than clamped.",
                    ],
                ], required: ["clips"]),
            tool(
                "lift_range",
                "Cuts a time range out and LEAVES the hole — ⌫ with an in/out range and nothing "
                    + "selected. Every unlocked clip is split at both bounds and the middles "
                    + "removed, and nothing moves: every clip after the range keeps the moment "
                    + "it had, which is what makes this the safe cut when a mix or a caption "
                    + "track is already timed. Use ripple_delete_range to close the hole "
                    + "instead.",
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
                "close_gap",
                "Closes the empty span on `track` that contains `at` — double-clicking a gap in "
                    + "a lane, or Clip ▸ Close Gap. The gap is bounded by the nearest clip "
                    + "edges on that track, and everything from its far side slides left by its "
                    + "length across every unlocked track. Nothing changes when `at` is on a "
                    + "clip, when the track is locked, when there is no clip after the gap, or "
                    + "when the shift would break the overlap rule — a gap closes fully or not "
                    + "at all.",
                [
                    "track": trackProperty,
                    "at": [
                        "type": "integer",
                        "description": "A time inside the gap, \(ticks)",
                    ],
                ], required: ["track", "at"]),
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
                "set_reversed",
                "Plays a media clip back to front, or forward again — Clip ▸ Reverse. Nothing "
                    + "about the timeline moves: the clip keeps its start, its duration and its "
                    + "in point, and the in point is measured in the direction the clip plays, "
                    + "so reversing a trimmed clip shows the other end of the file. Media clips "
                    + "only: any other kind is an error. The reversed frames are pre-rendered on "
                    + "the app side the first time they are needed, so the first render_frame or "
                    + "export after this may take a moment.",
                [
                    "clip": clipProperty,
                    "reversed": [
                        "type": "boolean",
                        "description": "true plays it backwards, false forwards again.",
                    ],
                ], required: ["clip", "reversed"]),
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
                    "at": [
                        "type": "integer",
                        "description": "Where the earliest clip lands, \(ticks) Default: the "
                            + "playhead.",
                    ],
                    "track": [
                        "type": "integer",
                        "description": "Track id for the payload's depth 0; the rest follow by "
                            + "the same offset. Default: the front-most track.",
                    ],
                    "payload": [
                        "type": "object",
                        "description": "{\"clips\": [...], \"media\": [...]} — see above.",
                    ],
                ], required: ["payload"]),
            tool(
                "paste_attributes",
                "Copies the payload's EARLIEST clip's property groups onto each of the clips — "
                    + "Edit ▸ Paste Attributes (⌥⌘V). The payload is the same Copy payload "
                    + "paste takes, but only its earliest clip's video, audio, text and shape are "
                    + "read (at one start the front-most, then the lower id — never the array's "
                    + "first, which is creation order): its ids and media rows do not matter. Each group "
                    + "REPLACES the target's whole group rather than merging — video and audio "
                    + "whole (position and scale included), text but its content, a shape but "
                    + "its kind, width, height, from and to. Left out, `groups` means every "
                    + "group BOTH clips have, silently skipping the rest; a named group the "
                    + "payload clip lacks, or a target lacks, is an error, and so is a value "
                    + "the inspector would refuse. Speed, enabled, actions, the transition and "
                    + "the clip's own name and label stay. Refused (no change) when nothing "
                    + "would change.",
                [
                    "clips": clipsProperty,
                    "payload": [
                        "type": "object",
                        "description": "{\"clips\": [...], \"media\": [...]} — what Copy puts "
                            + "on the pasteboard; see paste.",
                    ],
                    "groups": groupsProperty,
                ], required: ["clips", "payload"]),
            tool(
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
                    "clips": clipsProperty,
                    "name": [
                        "type": "string",
                        "description": "What to call the group. Default: Nest <n>.",
                    ],
                ], required: ["clips"]),
            tool(
                "unnest",
                "Opens a nest clip: its contents return to the timeline and the nest clip goes — "
                    + "⇧⌘G. The exact inverse of nest apart from the ids, which are minted "
                    + "fresh. Clips land at the nest clip's start plus their own, on tracks "
                    + "counted back from the nest clip's own (tracks missing behind it are "
                    + "added), and one the overlap rule refuses goes on a new track in front "
                    + "rather than being dropped. A nest clip trimmed shorter than its contents "
                    + "gives ALL of them back — trimming a nest hides content rather than "
                    + "cutting it. An error on any clip that is not a nest.",
                ["clip": clipProperty], required: ["clip"]),
            tool(
                "set_video",
                "Changes the clips' BASE video properties — position, scale, rotation, opacity, "
                    + "crop, corner radius, shadow, colour, chroma key, filters, reflection and "
                    + "spotlight. The patch MERGES: keys you leave out keep their values, and "
                    + "shadow, chroma, reflection or spotlight set to null clears it. Filters "
                    + "are the exception — the array replaces, so send the whole stack. "
                    + "Placement is spec §5.3: the source rectangle is centred at the "
                    + "canvas centre plus (x, y), scaled, then rotated about that centre, and "
                    + "crop removes edges in place without shifting the content. To animate a "
                    + "property instead, add_action and then set_action_end.",
                [
                    "clips": clipsProperty,
                    "patch": ["type": "object", "description": videoPatchDescription],
                ], required: ["clips", "patch"]),
            tool(
                "set_audio",
                "Changes the clips' BASE audio properties — volume, mute, fades, ducking, mono, "
                    + "pitch preservation, pan, compression and noise reduction. Merges like "
                    + "set_video; duck or compressor set to null removes it.",
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
                "Changes a shape clip's geometry and paint. Merges like set_video; stroke or "
                    + "fill set to null removes that half of the paint. Position and scale are "
                    + "set_video's, not this tool's. Changing kind changes ONLY the kind — an "
                    + "arrow made this way keeps whatever arrow_end it had, unlike one created "
                    + "by add_shape_clip.",
                [
                    "clips": clipsProperty,
                    "patch": ["type": "object", "description": shapePatchDescription],
                ], required: ["clips", "patch"]),
            tool(
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
                [
                    "clips": clipsProperty,
                    "patch": ["type": "object", "description": clipPatchDescription],
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
                "add_zoom_action",
                "Adds an animation that zooms the picture to a rectangle — the screencast "
                    + "zoom, and what the canvas's Z mode and the Video tab's Zoom to Region… "
                    + "both send. Over `duration` starting at `at`, the clip's scale, x and y "
                    + "ease to the values that bring `region` to the canvas: `fit` shows the "
                    + "whole region, `fill` covers the whole canvas, both measured THROUGH the "
                    + "clip's rotation. `region: null` is a zoom BACK — the end state is the "
                    + "clip's own base scale, x and y. `at` is CLIP time, measured from the "
                    + "clip's own start. Rotation and crop are read from the clip as it is at "
                    + "`at`, and the scale is clamped to the layer maximum with the position "
                    + "computed from the clamped value, so a region too small to fill the "
                    + "canvas still lands centred. Refused when it would overlap another "
                    + "action or run past the clip's end; an error on a clip with no picture. "
                    + "The new action's id comes back as new_actions, and set_action_end adds "
                    + "to what the same action animates.",
                [
                    "clip": clipProperty,
                    "at": [
                        "type": "integer",
                        "description": "Where the zoom starts, in CLIP time, \(ticks)",
                    ],
                    "duration": [
                        "type": "integer",
                        "description": "How long it runs \(ticks) Default 1 s (600000).",
                    ],
                    "region": zoomRegionProperty,
                    "fit": [
                        "type": "string", "enum": ZoomFit.allCases.map { $0.rawValue },
                        "description": "fit shows the whole region (the default); fill covers "
                            + "the whole canvas, cropping whatever the region's shape does not "
                            + "match.",
                    ],
                    "curve": [
                        "type": "string", "enum": curveNames,
                        "description": "How the zoom eases. Default ease_in_out, not linear: "
                            + "a zoom that starts and stops abruptly is the thing this exists "
                            + "to avoid.",
                    ],
                ], required: ["clip", "at", "region"]),
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
        ]
    }
}
