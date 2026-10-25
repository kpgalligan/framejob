//! The evaluator's last line of defence: [`clamp_video`], [`clamp_audio`]
//! and [`clamp_text`] bound every value an action's end patch can carry, after
//! `actions.rs` has merged and interpolated it, using the same table
//! `props_check.rs` holds for a direct edit. The video and audio clamps
//! were a pure move out of `actions.rs` (issue batch B87, toll A);
//! `clamp_text` was added by #353.

use crate::audio::MAX_GAIN;
use crate::model::{
    AudioProps, BlendMode, Color, CurveDomain, CurvePoint, Curves, HueRange, LevelRange, Qualifier,
    TextProps, VideoProps, Wheels, CURVE_POINTS_MAX, CURVE_POINTS_MIN, HUE_SOFTNESS_MAX, HUE_TURN,
    MAX_FILTERS, MAX_OBSCURE, QUALIFIER_BLUR_MAX, WHEEL_MAX,
};
use crate::props_check::{
    COMPRESSOR_MAKEUP_MAX_DB, COMPRESSOR_RATIO_MAX, COMPRESSOR_THRESHOLD_MIN_DB, EXPOSURE_MAX,
    SCALE_MAX, SCALE_MIN, SPOT_ZOOM_MAX, TONE_MAX, WORD_SCALE_MAX, WORD_SCALE_MIN,
};

/// Brings an evaluated value back into the range the ops enforce.
///
/// An action's end patch is deliberately LENIENT — `set_action_end` merges
/// whatever it is given so a half-written animation is still editable — and
/// interpolation can also overshoot nothing but reach a bad target. Nobody
/// downstream can defend itself: the Metal compositor multiplies by opacity
/// and scales a quad, and `audio.rs` would fold a nonsense gain into an
/// envelope. So the ONE place an evaluated value is produced is the one
/// place it is bounded, using the SAME table `props_check.rs` holds for a
/// direct edit (there a check errors and names the key, because a user typed
/// it; here there is nobody to tell, so it clamps).
///
/// NaN collapses to the neutral value rather than propagating: a single NaN
/// in a uniform block blanks a whole frame.
fn bounded(value: f64, low: f64, high: f64, neutral: f64) -> f64 {
    if value.is_nan() {
        neutral
    } else {
        value.clamp(low, high)
    }
}

/// Finite-only guard for the fields that have no range, just a requirement
/// that they be numbers (positions, rotation, the colour offsets).
fn finite_or(value: f64, neutral: f64) -> f64 {
    if value.is_finite() {
        value
    } else {
        neutral
    }
}

/// `is_nest` is what a NEST clip's evaluated props are held to, and it is
/// the only thing here that is not a range: a nest cannot blend (format
/// version 6), and this is where that holds for good.
pub(crate) fn clamp_video(mut props: VideoProps, is_nest: bool) -> VideoProps {
    props.x = finite_or(props.x, 0.0);
    props.y = finite_or(props.y, 0.0);
    props.scale = bounded(props.scale, SCALE_MIN, SCALE_MAX, 1.0);
    props.rotation = finite_or(props.rotation, 0.0);
    props.opacity = bounded(props.opacity, 0.0, 1.0, 1.0);
    props.corner_radius = bounded(props.corner_radius, 0.0, f64::MAX, 0.0);
    props.crop.l = bounded(props.crop.l, 0.0, f64::MAX, 0.0);
    props.crop.t = bounded(props.crop.t, 0.0, f64::MAX, 0.0);
    props.crop.r = bounded(props.crop.r, 0.0, f64::MAX, 0.0);
    props.crop.b = bounded(props.crop.b, 0.0, f64::MAX, 0.0);
    if let Some(shadow) = props.shadow.as_mut() {
        for channel in shadow.color.iter_mut() {
            *channel = bounded(*channel, 0.0, 1.0, 0.0);
        }
        shadow.opacity = bounded(shadow.opacity, 0.0, 1.0, 0.5);
        shadow.blur = bounded(shadow.blur, 0.0, f64::MAX, 0.0);
        shadow.angle = finite_or(shadow.angle, 315.0);
        shadow.distance = bounded(shadow.distance, 0.0, f64::MAX, 0.0);
    }
    props.color.brightness = finite_or(props.color.brightness, 0.0);
    props.color.contrast = finite_or(props.color.contrast, 0.0);
    props.color.saturation = finite_or(props.color.saturation, 0.0);
    props.color.hue = finite_or(props.color.hue, 0.0);
    let tone = &mut props.color;
    tone.exposure = bounded(tone.exposure, -EXPOSURE_MAX, EXPOSURE_MAX, 0.0);
    tone.temperature = bounded(tone.temperature, -TONE_MAX, TONE_MAX, 0.0);
    tone.tint = bounded(tone.tint, -TONE_MAX, TONE_MAX, 0.0);
    tone.highlights = bounded(tone.highlights, -TONE_MAX, TONE_MAX, 0.0);
    tone.shadows = bounded(tone.shadows, -TONE_MAX, TONE_MAX, 0.0);
    tone.whites = bounded(tone.whites, -TONE_MAX, TONE_MAX, 0.0);
    tone.blacks = bounded(tone.blacks, -TONE_MAX, TONE_MAX, 0.0);
    tone.vibrance = bounded(tone.vibrance, -TONE_MAX, TONE_MAX, 0.0);
    tone.fade = bounded(tone.fade, 0.0, TONE_MAX, 0.0);
    clamp_wheels(&mut props.wheels);
    clamp_curves(&mut props.curves);
    clamp_qualifier(&mut props.qualifier);
    // A NaN amount is none of the look, the neutral a filter's amount has.
    if let Some(look) = props.look.as_mut() {
        look.amount = bounded(look.amount, 0.0, 1.0, 0.0);
    }
    if let Some(chroma) = props.chroma.as_mut() {
        for channel in chroma.key.iter_mut() {
            *channel = bounded(*channel, 0.0, 1.0, 0.0);
        }
        chroma.tolerance = bounded(chroma.tolerance, 0.0, 1.0, 0.0);
        chroma.softness = bounded(chroma.softness, 0.0, 1.0, 0.0);
        chroma.spill = bounded(chroma.spill, 0.0, 1.0, 0.0);
    }
    // The shader budget is a hard limit on the recipe, not a preference:
    // a fifth filter has no uniform slot to arrive in, and the extras are
    // dropped from the END so the ones the user put first survive.
    props.filters.truncate(MAX_FILTERS);
    for filter in props.filters.iter_mut() {
        filter.amount = bounded(filter.amount, 0.0, 1.0, 0.0);
    }
    if let Some(reflection) = props.reflection.as_mut() {
        reflection.opacity = bounded(reflection.opacity, 0.0, 1.0, 0.35);
        reflection.height = bounded(reflection.height, 0.0, 1.0, 0.5);
        reflection.gap = bounded(reflection.gap, 0.0, f64::MAX, 0.0);
        reflection.falloff = bounded(reflection.falloff, 0.0, 1.0, 1.0);
    }
    if let Some(spotlight) = props.spotlight.as_mut() {
        spotlight.x = finite_or(spotlight.x, 0.0);
        spotlight.y = finite_or(spotlight.y, 0.0);
        // A zero-sized region would divide by nothing in the shader's
        // distance field, so the floor is a pixel rather than 0.
        spotlight.width = bounded(spotlight.width, 1.0, f64::MAX, 480.0);
        spotlight.height = bounded(spotlight.height, 1.0, f64::MAX, 270.0);
        spotlight.feather = bounded(spotlight.feather, 0.0, f64::MAX, 0.0);
        spotlight.dim = bounded(spotlight.dim, 0.0, 1.0, 0.6);
        spotlight.zoom = bounded(spotlight.zoom, 1.0, SPOT_ZOOM_MAX, 1.0);
    }
    // The regions are the filter list's story with a sharper ending: a
    // fifth region has no uniform slot either, and what a dropped one costs
    // is not an effect the user cannot see but the face they hid, back on
    // screen. `set_video` NAMES the overflow rather than trimming it for
    // that reason; here there is nobody to tell, so the extras go from the
    // end and the ones drawn first survive.
    props.obscure.truncate(MAX_OBSCURE);
    for region in props.obscure.iter_mut() {
        region.x = finite_or(region.x, 0.0);
        region.y = finite_or(region.y, 0.0);
        // A zero-sized region divides by nothing in the shader's distance
        // field, exactly as the spotlight's does, so the floor is a pixel.
        region.width = bounded(region.width, 1.0, f64::MAX, 480.0);
        region.height = bounded(region.height, 1.0, f64::MAX, 270.0);
        region.feather = bounded(region.feather, 0.0, f64::MAX, 0.0);
        // NaN takes the type's own default, full strength — a neutral
        // chosen for what it PREVENTS rather than for changing nothing, as
        // a filter's 0 is. An amount that arrived as a NaN and resolved to
        // "hides nothing" would quietly publish the face it was drawn over.
        region.amount = bounded(region.amount, 0.0, 1.0, 1.0);
    }
    // The nest rule, closed here rather than only at the op. `set_video`
    // refuses a blend on a nest clip by name (`edit_props.rs`'s
    // `check_blend`), but an action's `end` patch is checked against the
    // VOCABULARY and never against the clip (`edit_action.rs`), and
    // `multiply` is a perfectly legal mode, so
    // `set_action_end {"video": {"blend": "multiply"}}` would otherwise
    // sail past every check the op path has and reach the uniform block
    // anyway. Forcing it in the evaluator closes the recipe,
    // `clip_state` and both export writers at once, which no per-op check
    // can — this is the ONE place an evaluated value is produced.
    //
    // Why a nest cannot blend at all is `check_blend`'s doc: a nest is
    // flattened into one layer per clip inside it, so there is no composite
    // of its own for a blend to combine with the canvas.
    if is_nest {
        props.blend = BlendMode::Normal;
    }
    props
}

/// The wheels (spec §11 GR-11): a NaN to 0, each value to ±1, and a push
/// outside the unit circle divided by its `hypot` onto the rim — a point
/// `grade_check.rs`'s circle test always takes (its `WHEEL_RIM_TOLERANCE`).
fn clamp_wheels(wheels: &mut Wheels) {
    for wheel in [&mut wheels.lift, &mut wheels.gamma, &mut wheels.gain] {
        wheel.x = bounded(wheel.x, -WHEEL_MAX, WHEEL_MAX, 0.0);
        wheel.y = bounded(wheel.y, -WHEEL_MAX, WHEEL_MAX, 0.0);
        wheel.master = bounded(wheel.master, -WHEEL_MAX, WHEEL_MAX, 0.0);
        if wheel.x * wheel.x + wheel.y * wheel.y > 1.0 {
            let radius = wheel.x.hypot(wheel.y);
            wheel.x /= radius;
            wheel.y /= radius;
        }
    }
}

/// The curves (spec §11 GR-12): each x and y to 0…1, a channel holding a
/// NaN removed; a channel with fewer than 2 or more than 16 points, or whose
/// x's do not strictly rise after the clamp, removed; then every identity
/// channel removed, so an action that ends on the identity ends uncurved.
/// A hue curve (GR-32) clamps its x's to 0…360 and is removed when its last
/// x is 360, and its values to its domain's range.
pub(crate) fn clamp_curves(curves: &mut Curves) {
    for (domain, curve) in curves.named_mut() {
        if let Some(points) = curve.as_mut() {
            if !clamp_points(points, domain) {
                *curve = None;
            }
        }
    }
    curves.drop_identities();
}

/// One channel's points clamped in place; false when the channel must go.
fn clamp_points(points: &mut [CurvePoint], domain: CurveDomain) -> bool {
    if !(CURVE_POINTS_MIN..=CURVE_POINTS_MAX).contains(&points.len()) {
        return false;
    }
    let x_high = if domain == CurveDomain::Tone {
        1.0
    } else {
        HUE_TURN
    };
    let (low, high) = domain.value_range();
    for point in points.iter_mut() {
        if point.iter().any(|value| value.is_nan()) {
            return false;
        }
        point[0] = point[0].clamp(0.0, x_high);
        point[1] = point[1].clamp(low, high);
    }
    if domain != CurveDomain::Tone && points.last().is_some_and(|last| last[0] >= HUE_TURN) {
        return false;
    }
    points.windows(2).all(|pair| pair[1][0] > pair[0][0])
}

/// The qualifier (spec §11 GR-13): a range holding a NaN removed; every
/// other number to its bounds — the hue's width 0…360 and softness 0…180,
/// each level 0…1 — the hue centre taken `rem_euclid 360` (so a centre an
/// action moved past 360 or below 0 on the short way round,
/// `actions_qualifier.rs`, comes back onto the circle), and a level range
/// whose `low` passed its `high` closed at `high = low`. The `blur` (GR-35):
/// non-finite → 0, then 0…1.
fn clamp_qualifier(qualifier: &mut Qualifier) {
    if let Some(hue) = qualifier.hue {
        qualifier.hue = clamp_hue(hue);
    }
    for range in [&mut qualifier.saturation, &mut qualifier.luma] {
        if let Some(level) = *range {
            *range = clamp_level(level);
        }
    }
    qualifier.blur = if qualifier.blur.is_finite() {
        qualifier.blur.clamp(0.0, QUALIFIER_BLUR_MAX)
    } else {
        0.0
    };
}

/// One hue range clamped, or `None` when it must go.
fn clamp_hue(hue: HueRange) -> Option<HueRange> {
    if !hue.center.is_finite() || hue.width.is_nan() || hue.softness.is_nan() {
        return None;
    }
    Some(HueRange {
        center: hue.center.rem_euclid(HUE_TURN),
        width: hue.width.clamp(0.0, HUE_TURN),
        softness: hue.softness.clamp(0.0, HUE_SOFTNESS_MAX),
    })
}

/// One level range clamped, or `None` when it must go.
fn clamp_level(level: LevelRange) -> Option<LevelRange> {
    if level.low.is_nan() || level.high.is_nan() || level.softness.is_nan() {
        return None;
    }
    let low = level.low.clamp(0.0, 1.0);
    Some(LevelRange {
        low,
        high: level.high.clamp(0.0, 1.0).max(low),
        softness: level.softness.clamp(0.0, 1.0),
    })
}

pub(crate) fn clamp_audio(mut props: AudioProps) -> AudioProps {
    props.volume = bounded(props.volume, 0.0, MAX_GAIN, 1.0);
    props.fade_in = props.fade_in.max(0);
    props.fade_out = props.fade_out.max(0);
    if let Some(duck) = props.duck.as_mut() {
        duck.level = bounded(duck.level, 0.0, 1.0, 0.2);
        duck.attack = duck.attack.max(0);
        duck.release = duck.release.max(0);
    }
    // Pan's neutral is the CENTRE, not either end: a NaN that silently
    // threw the voice into one speaker would be worse than one that did
    // nothing.
    props.pan = bounded(props.pan, -1.0, 1.0, 0.0);
    props.noise_reduction = bounded(props.noise_reduction, 0.0, 1.0, 0.0);
    if let Some(compressor) = props.compressor.as_mut() {
        compressor.threshold_db = bounded(
            compressor.threshold_db,
            COMPRESSOR_THRESHOLD_MIN_DB,
            0.0,
            -18.0,
        );
        compressor.ratio = bounded(compressor.ratio, 1.0, COMPRESSOR_RATIO_MAX, 3.0);
        compressor.attack = compressor.attack.max(0);
        compressor.release = compressor.release.max(0);
        compressor.makeup_db = bounded(compressor.makeup_db, 0.0, COMPRESSOR_MAKEUP_MAX_DB, 0.0);
    }
    props
}

/// One colour's channels to 0..1, a NaN channel to that channel of
/// `neutral` — the colour's own default, so a NaN never blanks or tints
/// the layer it paints.
fn clamp_color(color: Color, neutral: Color) -> Color {
    let mut out = color;
    for (i, channel) in out.iter_mut().enumerate() {
        *channel = bounded(*channel, 0.0, 1.0, neutral[i]);
    }
    out
}

/// The text group, bounded as `clamp_video` bounds the picture: every NaN
/// to its field's own default, every other number into the range
/// `props_check.rs`'s `check_text` holds a direct edit to.
///
/// A value `check_text` accepts passes unchanged, with ONE exception: a
/// size in (0, 1) is raised to 1.0, the size Swift already draws it at
/// (`max(1, size)` in the text and word renderers) — the spotlight's pixel
/// floor is the precedent. `width` is floored at `f64::MIN_POSITIVE`, not
/// 1.0, so a legal width in (0, 1) is NOT an exception: the renderer sizes
/// its texture from the unfloored value, and a 1.0 floor would change the
/// picture of a width the op accepts.
///
/// `words` and `animation` are left alone: `set_action_end` refuses
/// `text.words` as a target, and `recipe_text.rs`'s `ramp` bounds the
/// animation where it is consumed.
///
/// Check and clamp stay two tables on purpose (#353): a check names the key
/// and refuses, a clamp has nobody to tell, and their neutrals, floors and
/// list policies differ.
///
/// The neutrals are written as literals rather than read from
/// `TextProps::default()`, which allocates a `String` on every evaluation;
/// each one names the `Default` it mirrors.
pub(crate) fn clamp_text(mut props: TextProps) -> TextProps {
    // `TextProps::default`'s size, colour, line spacing and tracking.
    props.size = bounded(props.size, 1.0, f64::MAX, 72.0);
    props.color = clamp_color(props.color, [1.0, 1.0, 1.0, 1.0]);
    // Not a positive floor: the renderer already draws a spacing of 0 or
    // less as the font's natural spacing, so mapping it to 1.0 draws the
    // same picture, where a floor such as 0.01 would change it.
    if !(props.line_spacing.is_finite() && props.line_spacing > 0.0) {
        props.line_spacing = 1.0;
    }
    props.tracking = finite_or(props.tracking, 0.0);
    // `Outline::default`.
    if let Some(outline) = props.outline.as_mut() {
        outline.width = bounded(outline.width, 0.0, f64::MAX, 2.0);
        outline.color = clamp_color(outline.color, [0.0, 0.0, 0.0, 1.0]);
    }
    // `Backdrop::default`.
    if let Some(backdrop) = props.backdrop.as_mut() {
        backdrop.color = clamp_color(backdrop.color, [0.0, 0.0, 0.0, 0.6]);
        backdrop.padding = bounded(backdrop.padding, 0.0, f64::MAX, 12.0);
        backdrop.radius = bounded(backdrop.radius, 0.0, f64::MAX, 8.0);
    }
    // A NaN width is `TextProps::default`'s `None`, a single line; any
    // other is kept above 0, the bound `check_text` holds.
    props.width = match props.width {
        Some(width) if width.is_nan() => None,
        Some(width) => Some(width.clamp(f64::MIN_POSITIVE, f64::MAX)),
        None => None,
    };
    // `WordStyle::default`'s scale and dim, `WordStyle::template`'s colours
    // and `ActivePill::default`'s plate.
    if let Some(style) = props.word_style.as_mut() {
        style.active_scale = bounded(style.active_scale, WORD_SCALE_MIN, WORD_SCALE_MAX, 1.0);
        style.pause_dim = bounded(style.pause_dim, 0.0, 1.0, 0.0);
        for color in [
            &mut style.active_color,
            &mut style.spoken_color,
            &mut style.upcoming_color,
        ] {
            if let Some(c) = color.as_mut() {
                *c = clamp_color(*c, [1.0, 1.0, 1.0, 1.0]);
            }
        }
        if let Some(pill) = style.active_pill.as_mut() {
            pill.color = clamp_color(pill.color, [0.55, 0.27, 0.93, 1.0]);
            pill.padding = bounded(pill.padding, 0.0, f64::MAX, 0.2);
            pill.radius = bounded(pill.radius, 0.0, f64::MAX, 0.25);
        }
    }
    props
}
