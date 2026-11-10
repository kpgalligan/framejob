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
/// and arrives as an argument rather than a second spelling here. The video
/// patch's vocabulary is `AgentCatalog+VideoPatch.swift`'s (road map
/// creator-jobs CU3a1's toll).
extension AgentServer {

    static let shapeNames: [String] = ShapeKind.allCases.map { $0.rawValue }
    private static let audioPatchDescription: String =
        "Audio properties to merge. Keys: volume (0–"
        + String(format: "%g", AudioNormalize.maxGain) + ", 1 = unity), muted, fade_in, "
        + "fade_out (ticks), fade_in_shape and fade_out_shape (linear — the default — "
        + "s_curve, plus_3db, which moves fastest near silence, or minus_3db, which moves "
        + "fastest near full level), duck (null or "
        + "{level, attack, release, mode, pre_roll, hold}: mode extent — the default, for "
        + "the clip's whole length — or speech, only while the clip's speech plays, "
        + "widened by pre_roll before and hold after, in ticks, 0.5 s each by default; "
        + "speech saves the media's speech spans from its detected speech in the same "
        + "step, and is an error for a clip that is not a media clip with sound or whose "
        + "speech has not been detected yet), mono, keep_pitch, "
        + "pan (-1 hard left … +1 hard right), compressor (null or {threshold_db, ratio, "
        + "attack, release, makeup_db} — the two times in ticks), noise_reduction (0–1), "
        + "limiter (null or {ceiling_db, release}: a true-peak limiter last in the clip's "
        + "chain, ceiling_db in dBTP after the clip's base volume, -24 to 0, default -1, "
        + "release in ticks, 600 to 600000, default 60000; {limiter: {}} turns it on at "
        + "the defaults), "
        + "isolation (0–1: voice isolation, Apple's on-device voice model, which also "
        + "reduces room echo; 0 off, 0.8 the app's default, 1 leaves silence between words; "
        + "rendered offline, the clip plays without it until the render lands and an export "
        + "waits for it; a clip not at ×1 plays without it)" + audioEQClause
        + audioDynamicsClause + audioVoiceClause + ". duck, "
        + "compressor, limiter, eq (and each of its slots), hum, gate, leveller, de_esser and "
        + "voice are OBJECTS and they "
        + "MERGE: a key you leave out keeps what is stored, and {duck: null} clears the "
        + "whole thing."
    // Format 32's keys (spec §11 AU-31..AU-34), their own typed local so the
    // chain above stays short enough to type-check quickly. The presets' values
    // are the inspector's EQ buttons (AU-32).
    private static let audioEQClause: String =
        ", channels (both — the default — left, right or swapped: left and right play that "
        + "channel of a stereo source from both sides, swapped exchanges them; first in the "
        + "clip's chain after isolation, ignored on a mono source), eq (null or {high_pass, "
        + "low_shelf, band_1, band_2, band_3, high_shelf, low_pass, bypass}, after the "
        + "channel pick: "
        + "each slot null (off) or an object; high_pass and low_pass {frequency, slope}, "
        + "frequency 20–20000 Hz, slope 12 or 24 dB/octave, defaults {80, 12} and "
        + "{12000, 12}; low_shelf and high_shelf {frequency, gain_db}, gain -24 to 24 dB, "
        + "defaults {100, 0} and {8000, 0}; band_1..band_3 {frequency, gain_db, q}, q "
        + "0.1–10, default {1000, 0, 1}; bypass true keeps the settings and silences them; "
        + "{eq: {high_pass: {}}} turns one slot on at its defaults. The inspector's presets: "
        + "Rumble Cut is high_pass {80, 24}, De-mud band_1 {300, -3, 1}, Presence band_3 "
        + "{4000, 3, 1}), hum (null or {frequency, depth_db, harmonics}: notches at the "
        + "mains frequency, 50 or 60, default 60, and its harmonics, 1–8, default 4, each "
        + "depth_db deep, 6–60, default 30; after the EQ)"
    // Format 33's keys (spec §11 AU-40..AU-45), their own typed local for the
    // reason `audioEQClause` is.
    private static let audioDynamicsClause: String =
        ", gate (null or {threshold_db, ratio, range_db, attack, hold, release}: a "
        + "downward expander after noise reduction that turns the pauses down; "
        + "threshold_db is dB RELATIVE to the clip's measured loudness (the Loudness "
        + "normalize_clip reports, before volume), -40 to 0, default -10; below it the "
        + "level drops ratio - 1 dB per dB, ratio 1–20, default 4, never more than "
        + "range_db, 1–80, default 20; attack 0–60000 ticks (default 600, 1 ms) opens it, "
        + "hold 0–300000 (default 30000, 50 ms) keeps it open, release 600–1200000 "
        + "(default 60000, 100 ms) closes it; {gate: {}} turns it on at the defaults), "
        + "leveller (null or {target_db, max_up_db, max_down_db, response}: a gain curve after "
        + "the gate for a speaker who moves on and off the mic, made AHEAD of time from the "
        + "clip's measured loudness and its speech (media.speech, else speech detection): each "
        + "phrase's level over a 3 s window of its speech, smoothed both ways over response "
        + "ticks (300000–6000000, default 1200000, 2 s), is brought to target_db (dB RELATIVE "
        + "to the clip's loudness, -20 to 10, default 0), never more than max_up_db up or "
        + "max_down_db down (each 0–24, default 12); a phrase starts at its own level, a pause "
        + "holds the gain and glides to the next phrase over its last 0.25 s, and a phrase "
        + "under 1 s takes its neighbor's; the same in the preview and an export; it waits "
        + "for the clip's speech as well as its loudness, and does nothing where speech "
        + "detection is unavailable or no phrase has 1 s of speech; {leveller: {}} turns it on "
        + "at the defaults), "
        + "de_esser (null or {frequency, threshold_db, range_db}: after the leveler, turns "
        + "the band above frequency down on sibilance and never boosts; frequency "
        + "2000–12000 Hz, default 6000; threshold_db relative to the clip's loudness, -30 "
        + "to 20, default 0; range_db 1–24, default 6). The three act only once the clip's "
        + "loudness is measured: until then it plays without them and an export waits; a "
        + "clip too short or too quiet to measure plays without them; on a nest clip they "
        + "do nothing"
    // Format 34's voice effect (spec §11 AU-140, AU-141), its own typed
    // local for the reason `audioEQClause` is. Its UI paths are the Sound
    // tab's Voice Effect section (AU-146) and Clip ▸ Voice ▸ (AU-158).
    private static let audioVoiceClause: String =
        ", voice (null or {kind, amount, pitch}: a voice effect rendered offline and played "
        + "in place of the clip's sound, after isolation and before the channel pick; kind "
        + "is one of voice: pitch, high, deep, robot; tone: bass, treble, bright, telephone, "
        + "radio; character: lofi, distorted; space: echo, room, hall, plate, cathedral; "
        + "amount 0–1, default 1, how much of the effect (0 plays the clip dry); pitch "
        + "-12 to 12 semitones, read only by pitch, high and deep, absent meaning the "
        + "kind's own, 0, +5 and -5; a new kind keeps a stored pitch unless pitch: null "
        + "is sent with it; {voice: null} clears it. The clip plays without the effect "
        + "until its render lands and an export waits for it; a clip not at ×1 plays "
        + "without it; reverb and echo tails end with the clip)"
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
        + ". A color is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
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
        + "the color underneath. 2 to \(Gradient.maxStops) stops, each at 0–1 along the "
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
        + "stroke (null or {width, color}), fill (null or a color), radius (rectangle "
        + "corners), arrow_start, arrow_end, and from / to — the endpoints of a line or "
        + "arrow as UNIT coordinates in its box, e.g. from [0, 1] to [1, 0]"
        + gradientClause
        + ". A color is FOUR numbers, [r, g, b, a], each 0–1: three is refused by "
        + "length and a component outside the range is refused by name, neither "
        + "filled in nor clamped."
    // The fifth patch, `set_clip`'s. The label names are `ClipLabel`'s —
    // the one home of the marker-colour vocabulary — read rather than
    // restated, and typed for the same budget reason as the four above.
    private static let labelNames: [String] = ClipLabel.allCases.map { $0.rawValue }
    private static let clipPatchDescription: String =
        "name and/or label; a key set to null clears it. Labels are the marker colors: "
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
                    + "crop, corner radius, shadow, color, chroma key, filters, reflection, "
                    + "spotlight and motion (what the clip does on its way in, on its way out "
                    + "and all the way through). The patch MERGES AT EVERY DEPTH: keys you "
                    + "leave out keep their values, inside a nested object too — a patch of "
                    + "just {shadow: {blur: 20}} keeps the shadow's color, angle and "
                    + "distance — and shadow, chroma, reflection, spotlight or motion set to "
                    + "null clears it. A LIST is the exception: filters and obscure each "
                    + "replace whole, so send the whole stack and [] to clear it. A key or a "
                    + "value the vocabulary does not have is an error naming its dotted path "
                    + "(array indices included) and the value you sent; nothing is dropped, "
                    + "corrected or clamped. "
                    + "Placement is spec §5.3: the source rectangle is centered at the "
                    + "canvas center plus (x, y), scaled, then rotated about that center, and "
                    + "crop removes edges in place without shifting the content. To animate a "
                    + "property instead, add_action and then set_action_end. On an adjustment "
                    + "clip only color, wheels, curves, look, the point filters and opacity (the "
                    + "grade's strength) do anything, the qualifier narrows which pixels they "
                    + "reach, and blur, sharpen, pixelate or a blend mode is an error. cutout "
                    + "(Remove Background) is taken by media and still clips only, and "
                    + "behind_subject (Text Behind Subject) by any drawing clip but an "
                    + "adjustment or nest clip. A text, shape, graphic or adjustment clip has "
                    + "no crop, corner radius or chroma key: a value other than none for one "
                    + "is an error (clearing is allowed), except a crop on a matte track, "
                    + "where it shapes the matte (never on an adjustment clip). A nest clip "
                    + "has no corner radius or chroma key either (an error the same way); a "
                    + "crop draws on one.",
                ["clips": clipsDescription, "patch": videoPatchDescription]),
            opTool(
                "set_audio",
                "Changes the clips' BASE audio properties — volume, mute, fades, ducking, mono, "
                    + "pitch preservation, pan, compression and noise reduction. Merges like "
                    + "set_video; duck or compressor set to null removes it. To animate one, "
                    + "use an action's set_action_end: volume, mute, the fades and every key the "
                    + "sound's effects read animate there (pan, mono, channels, eq, hum, "
                    + "noise_reduction, gate, leveller, de_esser, compressor, limiter, "
                    + "isolation); duck, "
                    + "keep_pitch, the fade shapes and voice are this tool's alone.",
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
                    + "never does. The label is a color name drawn as a dot on the clip, "
                    + "stored as given, so keep to the six names.",
                ["clips": clipsDescription, "patch": clipPatchDescription]),
        ]
    }
}
