import Foundation

// MARK: - Catalog: clip properties

/// The catalog's five PROPERTY rows — `set_video`, `set_audio`, `set_text`,
/// `set_shape` and `set_clip`, the patches that change a clip's base
/// property groups — and the patch vocabulary they are written in.
///
/// A pure move out of `AgentCatalog+Clips.swift` (grading GR1), which stood
/// over app/CLAUDE.md's ~600-line cap with grading's own patch prose still to
/// land. The five rows came here whole, in their existing order, with their
/// bodies untouched, and are SPLICED back in where they left — after
/// `unnest`, before `set_enabled` — by `clipAndActionTools`, so the catalog's
/// order is unchanged. The hoisted locals they read came with them as
/// `static let`s, each with its own name, comment and an explicit type, so
/// every one stays its own expression for the type checker's budget. Three are internal rather than private — `shapeNames`,
/// `textPatchDescription` and `shapePatchDescription` — because
/// `add_text_clip` and `add_shape_clip`, which stayed, read them through
/// typed locals of the same names. `clipsDescription` is the clips' sentence
/// and arrives as an argument rather than a second spelling here.
extension AgentServer {

    static let shapeNames: [String] = ShapeKind.allCases.map { $0.rawValue }
    private static let filterNames: [String] = FilterKind.allCases.map { $0.rawValue }
    private static let obscureNames: [String] = ObscureKind.allCases.map { $0.rawValue }
    // The obscure list's clause, kept as its own explicitly-typed local
    // rather than spliced into the video chain below: that chain already
    // carries a non-literal operand and is one of the three expressions
    // this file records tipping the type checker's budget.
    private static let obscureClause: String =
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
    private static let blendNames: [String] = BlendMode.allCases.map { $0.rawValue }
    private static let blendClause: String =
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
    private static let edgeNames: [String] = EdgeMotion.allCases.map { $0.rawValue }
    private static let duringNames: [String] = DuringMotion.allCases.map { $0.rawValue }
    private static let motionClause: String =
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
    // `video.look`'s clause (spec §11 GR-7), its own explicitly-typed local
    // for `blendClause`'s reason: the kind names are a non-literal operand.
    // They are `LookKind.allCases`, the core's order, which is the order the
    // UI paths it mirrors show them in: the Color sub-tab's Look section (its
    // gallery and Amount row) and Clip ▸ Look ▸.
    private static let lookNames: [String] = LookKind.allCases.map { $0.rawValue }
    private static let lookClause: String =
        ", look (null, or {kind: \(lookNames.joined(separator: "|")), amount: 0–1} — one of "
        + "the eight built-in looks, applied after color and before the filters; amount is "
        + "how much of it, 1 when left out, refused outside 0–1. It MERGES: a new kind keeps "
        + "the clip's amount, an amount alone needs a clip that already has a look, and "
        + "{look: null} removes it. In an action's end the amount animates and a change of "
        + "kind switches at the end)"
    // The three patch vocabularies, written once: every property group of
    // spec §5.2, with the ranges the ops enforce. A patch MERGES, so a key
    // left out keeps its current value and a key set to null clears an
    // optional group (shadow, chroma, duck, outline, backdrop, and text's
    // width, which null restores to auto-sizing).
    // Explicitly typed for the same reason `shapePatchDescription` is: the
    // `+` chain now carries a non-literal operand (the filter kinds), and
    // an inferred type here is what tips the `catalog` literal past the
    // type checker's budget.
    private static let videoPatchDescription: String =
        "Video properties to merge into the clip's base props. Keys: x, y (canvas px from "
        + "the canvas centre, y DOWN), scale (1 = native pixels, 0.01–10), rotation "
        + "(degrees, positive turns clockwise on screen), opacity (0–1), crop "
        + "({l, t, r, b} in SOURCE px — cropping never shifts the content), corner_radius "
        + "(source px), shadow (null or {color, opacity, blur, angle, distance}), color "
        + "({brightness, contrast, saturation, hue, exposure, temperature, tint, highlights, "
        + "shadows, whites, blacks, vibrance, fade}, each 0 = unchanged and any subset "
        + "merging — exposure is -3 to 3 (EV), fade 0–1 and the other seven tone keys -1 "
        + "to 1, refused outside; a positive temperature is warmer, a positive tint more "
        + "magenta), chroma (null or "
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
        + lookClause
        + ". A colour is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
        + "length and a component outside the range is refused by name, neither "
        + "filled in nor clamped. chroma's key is the one exception, three numbers "
        + "with no alpha."
    private static let audioPatchDescription: String =
        "Audio properties to merge. Keys: volume (0–4, 1 = unity), muted, fade_in, "
        + "fade_out (ticks), duck (null or {level, attack, release}), mono, keep_pitch, "
        + "pan (-1 hard left … +1 hard right), compressor (null or {threshold_db, ratio, "
        + "attack, release, makeup_db} — the two times in ticks), noise_reduction (0–1). "
        + "duck and compressor are OBJECTS and they MERGE: a key you leave out keeps what "
        + "is stored, and {duck: null} clears the whole thing."
    // `text.animation`'s clause, its own explicitly-typed local for the
    // reason `obscureClause` is: the kind names are a non-literal operand
    // and the text chain is long enough already.
    private static let animationNames: [String] = TextAnimationKind.allCases.map { $0.rawValue }
    private static let animationClause: String =
        ", animation (null or {kind: \(animationNames.joined(separator: "|")), in, out} — "
        + "how the words arrive and leave. in and out are DURATIONS in ticks measured from "
        + "the clip's own first and last frame, not times; either may be 0 for no ramp at "
        + "that end, and in + out longer than the clip simply shows a partial reveal, and "
        + "both are snapped to the document's frame grid. Like shadow and backdrop it "
        + "MERGES: a key you leave out keeps what is stored, and {animation: null} clears "
        + "the whole thing)"
    static let textPatchDescription: String =
        "Text properties to merge. Keys: content, font (a PostScript name), size (px), "
        + "color, align (left|center|right), valign (top|middle|bottom), line_spacing, "
        + "tracking, outline (null or {width, color}), backdrop (null or {color, padding, "
        + "radius}), width (null for auto-sizing, or a wrap width in px)"
        + animationClause + AgentServer.textWordsClause
        + ". A colour is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
        + "length and a component outside the range is refused by name, neither "
        + "filled in nor clamped."
    // `shape.gradient`'s clause, its own local for the budget reason the
    // other hoisted clauses give. It used to be worth a line of its own as
    // the only patch member that named its own mistakes, the shape patch
    // being hand-read rather than decoded; since D1·1 the core names a
    // misspelt key inside ANY nested object by its dotted path, stop
    // indices included, so the gradient is no longer the exception.
    private static let gradientKindNames: [String] = GradientKind.allCases.map { $0.rawValue }
    private static let gradientClause: String =
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
    static let shapePatchDescription: String =
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
    private static let labelNames: [String] = ClipLabel.allCases.map { $0.rawValue }
    private static let clipPatchDescription: String =
        "name and/or label; a key set to null clears it. Labels are the marker colours: "
        + "\(labelNames.joined(separator: ", "))."

    /// The five property rows of `clipAndActionTools`' array, in its order.
    func propertyTools(clipsDescription: String) -> [[String: Any]] {
        let videoPatchDescription: String = Self.videoPatchDescription
        let audioPatchDescription: String = Self.audioPatchDescription
        let textPatchDescription: String = Self.textPatchDescription
        let shapePatchDescription: String = Self.shapePatchDescription
        let clipPatchDescription: String = Self.clipPatchDescription
        return [

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
                    + "property instead, add_action and then set_action_end. On an adjustment "
                    + "clip only color, the point filters and opacity (the grade's strength) "
                    + "do anything, and blur, sharpen, pixelate or a blend mode is an error.",
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
        ]
    }
}
