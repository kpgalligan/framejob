import Foundation

// MARK: - Catalog: the video patch

/// `set_video`'s patch vocabulary: `videoPatchDescription` and the clauses
/// it is built from, each its own explicitly-typed `static let` for the type
/// checker's budget. A pure move out of `AgentCatalog+Properties.swift`
/// (road map creator-jobs CU3a1's toll), whose
/// `propertyTools(clipsDescription:)` reads `videoPatchDescription`; that
/// one lost `private` to be read from there.
extension AgentServer {
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
        ", look (null, or {kind: \(lookNames.joined(separator: "|")), media, amount: 0–1} — "
        + "one of the eight built-in looks, or lut: an imported .cube file, media its media "
        + "id (import_media imports one), required with lut and refused with any other kind; "
        + "applied after color and before the filters; amount is how much of it, 1 when "
        + "left out, refused outside 0–1. It MERGES: a new kind keeps the clip's amount, a "
        + "built-in kind replaces a LUT, an amount alone needs a clip that already has a "
        + "look, and {look: null} removes it. In an action's end the amount animates and a "
        + "change of kind or of LUT switches at the end)"
    // `video.wheels`' clause (spec §11 GR-11), its own explicitly-typed local
    // for `lookClause`'s reason. It mirrors the Color sub-tab's Wheels section
    // (each disc's puck, master strip and field); the push the section has no
    // field for is exact here.
    private static let wheelsClause: String =
        ", wheels ({lift, gamma, gain}, each {x, y, master}, each -1 to 1 and 0 = unchanged: "
        + "x, y is the colour push, its angle the hue (0° red, 120° green, 240° blue) and its "
        + "length the strength, and must lie inside the unit circle (x² + y² ≤ 1); master is "
        + "the brightness; refused outside, never clamped. Any subset MERGES, so {wheels: "
        + "{lift: {x: 0.2, y: -0.1}}} keeps lift's master and the other two wheels. Applied "
        + "after color's tone and before look: lift moves black and holds white, gain moves "
        + "white and holds black, gamma moves the middle and holds both ends)"
    // `video.curves`' clause (spec §11 GR-12), typed for `lookClause`'s
    // reason. It mirrors the Color sub-tab's Curves section (the channel
    // picker, the plot's points, the In and Out fields, Reset).
    private static let curvesClause: String =
        ", curves ({master, red, green, blue}, each a list of 2 to 16 [x, y] points, x "
        + "strictly rising, x and y 0–1 inclusive; refused outside, never clamped. A list "
        + "REPLACES that channel whole, null removes it, and a curve with every y = x from x "
        + "0 to x 1 is the identity, stored as no curve. Each channel is a monotone spline "
        + "(Fritsch–Carlson) through its points, flat outside its first and last x; a colour "
        + "is red(master(v)). Applied after wheels and before look. In an action's end an "
        + "identity curve animates to neutral (an identity on either side takes the other "
        + "curve's x's); two curves of different point counts blend their values across "
        + "the action. Two hue "
        + "curves too, hue_hue (Hue vs Hue) and hue_sat (Hue vs Sat): each 2 to 16 "
        + "[hue, value] points, hue in degrees 0 ≤ hue < 360 strictly rising; hue_hue's "
        + "value is a shift in degrees -180–180 (0 none) and hue_sat's a saturation gain "
        + "0–2 (1 none); a curve whose every value is its none is the identity, stored as "
        + "no curve. Each is a periodic spline that wraps at 0/360. Applied after the "
        + "channel curves and before look, at the colour's HSV hue read once: a positive "
        + "shift turns HSV hue red → yellow → green keeping Rec. 709 luma, the gain scales "
        + "saturation about that luma; a grey or near-grey (chroma at most 0.02) is left "
        + "alone, and the effect fades in up to chroma 0.06)"
    private static let qualifierClause: String =
        ", qualifier (adjustment clips only — anything else is an error naming the clip; "
        + "which pixels the clip's grade reaches, read from the picture behind it BEFORE the "
        + "grade: {hue: {center, width, softness}, saturation: {low, high, softness}, luma: "
        + "{low, high, softness}, invert, blur}. hue is in degrees: center 0–360 (wraps), width "
        + "0–360 fully selected about the centre, softness 0–180 of fall-off outside each "
        + "edge; a colour with chroma under about 0.06 has no hue and is never selected by "
        + "it. saturation is HSV saturation (chroma / max, and near-black reads as 0) and "
        + "luma Rec. 709 Y′, each low ≤ high and softness 0–1. A range MERGES: {hue: {}} "
        + "turns hue on at {30, 50, 25} (saturation and luma at {0, 1, 0.1}), a partial "
        + "range keeps the rest, null turns it off; the weight is the product of the ranges "
        + "on, inverted by invert: true. blur 0–1 (0 off) softens that weight by a Gaussian "
        + "of 24·blur canvas pixels, never the matte; it draws nothing with no range on. "
        + "Refused outside the bounds, never clamped. In an "
        + "action the numbers animate, the hue centre the short way round (350 to 10 passes "
        + "0); a range turned on or off and invert switch at the end. render_frame "
        + "{selection: clip} shows what it selects)"
    // `video.cursor`'s clause (format 38, spec §11 CU-30), its own
    // explicitly-typed local for `lookClause`'s reason: the style and clicks
    // names are non-literal operands. The UI path is the Picture sub-tab's
    // Cursor section (road map creator-jobs CU4, spec §11 CU-40, CU-41).
    private static let cursorStyleNames: [String] = CursorStyle.allCases.map { $0.rawValue }
    private static let cursorClicksNames: [String] = CursorClicks.allCases.map { $0.rawValue }
    private static let cursorClause: String =
        ", cursor (null, or {show, scale, style, smoothing, hide_idle, clicks, click_color, "
        + "click_size}: how the cursor recorded in the media's cursor file (media.cursor) is "
        + "drawn on this clip. show true/false (default true); scale 0.25–8 (default 1); style "
        + "\(cursorStyleNames.joined(separator: "|")) (default recorded); smoothing 0–1 "
        + "(default 0); hide_idle null (never hidden, the default) or 0.5–30 seconds of no "
        + "activity before it hides; clicks \(cursorClicksNames.joined(separator: "|")) "
        + "(default none); click_color a CSS colour (default #ffffffcc); click_size 0.25–4 "
        + "(default 1). Refused outside the ranges, never clamped; "
        + "{cursor: {}} stores all eight defaults, and an object MERGES. In an action's end "
        + "scale and click_size animate and show, style, clicks and click_color switch at "
        + "the end; smoothing and hide_idle act only from the clip's own props — in an end "
        + "they have no effect, and a split or a freeze frame keeps the clip's. On a clip "
        + "with no cursor an end's cursor keys all switch at the end; give it one first "
        + "with set_video {cursor: {}} to animate them. smoothing and hide_idle are the "
        + "clip's own: write them with set_video, never in an end. style arrow draws Frame "
        + "Job's own arrow, and so does recorded at a time the cursor file recorded no "
        + "cursor image. The UI path is the Picture sub-tab's Cursor section)"
    // Remove Background (format 39, spec §11 CO-20), explicitly typed for
    // `lookClause`'s reason. Nothing in the UI writes it yet (road map
    // creator-jobs CO3's Background section).
    private static let cutoutClause: String =
        ", cutout (null, or {subject, quality, background, edge, feather}: Remove Background, "
        + "the clip drawn as its subject. subject person (the default) or foreground "
        + "(the picture's foreground object: an image clip's only, refused on a media or still "
        + "clip); quality standard (best is refused: Best masks are not made yet); background "
        + "remove (only the person drawn, the default) or keep (the clip drawn whole); edge "
        + "-1–1 (default 0) shrinks or grows the outline; feather 0–1 (default 0). Refused "
        + "outside the ranges, never clamped; {cutout: {}} stores all five defaults, an object "
        + "MERGES and null removes it. A media, still or image clip takes one: a text, shape, "
        + "graphic, adjustment or nest clip is refused. An image clip's masks are made from its "
        + "picture (Vision's person segmentation, or for subject foreground its foreground "
        + "instance mask) as soon as the cutout is set; analyze_cutout answers where they "
        + "stand. In an action's end "
        + "edge and feather animate and background switches at the end; subject and quality "
        + "are refused there, the cutout cannot be keyed off, and on a clip with no cutout an "
        + "end's cutout keys do nothing. The cutout is drawn, in the preview, render_frame and "
        + "every export, where the clip's media has person masks cached "
        + "(get_media_analysis {kind: \"masks\"} makes them); a frame without its mask, or "
        + "a clip window in which no person was found, draws uncut)"
    // Text Behind Subject (format 40, spec §11 CO-52), explicitly typed for
    // `lookClause`'s reason.
    private static let behindSubjectClause: String =
        ", behind_subject (true or false, default false: Text Behind Subject, the clip cut "
        + "at each instant by the person of every cut-out clip — one with a cutout, background "
        + "remove or keep — on a track behind it in its own container, so the person stands "
        + "in front of it; a cut-out clip in front of it does not cut it. Any drawing clip "
        + "but an adjustment or nest clip takes it; those two are refused. In an action's "
        + "end it switches at the end. text_behind_subject places a title this way in one "
        + "step)"
    // Motion blur (format 42, spec §11 CU-111…CU-114, drawn since CU-117),
    // explicitly typed for `lookClause`'s reason. The UI path is the Picture
    // sub-tab's Transform section's Motion Blur row (`VideoPane+Transform.swift`,
    // CU-118 (b)).
    private static let motionBlurClause: String =
        ", motion_blur (0–1, default 0 = off: the shutter as a fraction of one canvas frame, "
        + "so 0.5 is a 180° shutter; the clip is drawn blurred along its motion across that "
        + "much of each frame. It animates in an action's end. Refused above 0 on a nest "
        + "clip (set it on the clips inside) and on an adjustment clip; drawn sharp under a "
        + "transition, a routed dissolve, a matte, Behind Subject or a drop shadow. Drawn in "
        + "the preview, render_frame and every export: the layer at its sub-frame placements, "
        + "averaged and blended once, and a moving cursor along its path — the Picture "
        + "sub-tab's Transform section, Motion Blur)"
    // Hide while silent (format 43, spec §11 CO-90…CO-94), explicitly typed
    // for `lookClause`'s reason. The UI path is the Picture sub-tab's Hide
    // While Silent section (`VideoPane+HideSilent.swift`).
    private static let hideSilentClause: String =
        ", hide_silent (null, or {media, pre_roll, hold, fade}: the camera fades out while "
        + "media's speech is silent and back in just before it — the Picture sub-tab's Hide "
        + "While Silent section. media is required: a media with sound whose speech the clip "
        + "follows. pre_roll, hold and fade are ticks, 0–3000000 (0–5 s) each, defaults "
        + "120000, 900000 and 180000 (0.2 s, 1.5 s, 0.3 s), stored off the frame grid. The "
        + "drawn opacity is multiplied by a gate: 1 while the media's speech plays, widened by "
        + "pre_roll before and hold after, ramping to 0 over fade, read from the clips of "
        + "media in the nearest container (the clip's own, then each enclosing nest outward) "
        + "where one plays; 1 where none plays. Only the drawn frame sees it: get_project and "
        + "the clip's state read the opacity ungated. Not animatable (set_action_end refuses "
        + "it). When media has no saved speech this tool first saves its spans from the "
        + "on-device voice detection in the same undo step, and refuses when the media has no "
        + "sound or its speech has not been detected yet (try again in a moment). Refused on "
        + "a nest clip: set it on the clips inside)"
    // The three patch vocabularies, written once: every property group of
    // spec §5.2, with the ranges the ops enforce. A patch MERGES, so a key
    // left out keeps its current value and a key set to null clears an
    // optional group (shadow, chroma, duck, outline, backdrop, and text's
    // width, which null restores to auto-sizing).
    // Explicitly typed for the same reason `shapePatchDescription` is: the
    // `+` chain now carries a non-literal operand (the filter kinds), and
    // an inferred type here is what tips the `catalog` literal past the
    // type checker's budget.
    static let videoPatchDescription: String =
        "Video properties to merge into the clip's base props. Keys: x, y (canvas px from "
        + "the canvas centre, y DOWN), scale (1 = native pixels, 0.01–10), rotation "
        + "(degrees, positive turns clockwise on screen), opacity (0–1), crop "
        + "({l, t, r, b} in SOURCE px — cropping never shifts the content), corner_radius "
        + "(source px), shadow (null or {color, opacity, blur, angle, distance}), color "
        + "({brightness, contrast, saturation, hue, exposure, temperature, tint, highlights, "
        + "shadows, whites, blacks, vibrance, fade}, each 0 = unchanged and any subset "
        + "merging — exposure is -3 to 3 (EV), fade 0–1 and the other seven tone keys -1 "
        + "to 1, refused outside; a positive temperature is warmer, a positive tint more "
        + "magenta; hue is in degrees, and a positive hue turns every colour's HSV hue that "
        + "far, red → yellow → green, keeping its Rec. 709 luma), chroma (null or "
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
        + wheelsClause
        + curvesClause
        + qualifierClause
        + lookClause
        + cursorClause
        + cutoutClause
        + behindSubjectClause
        + motionBlurClause
        + hideSilentClause
        + ". A colour is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
        + "length and a component outside the range is refused by name, neither "
        + "filled in nor clamped. chroma's key is the one exception, three numbers "
        + "with no alpha."
}
