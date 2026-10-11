//! The evaluator's last line of defence: [`clamp_video`] and
//! [`clamp_audio`] bound every value an action's end patch can carry, after
//! `actions.rs` has merged and interpolated it, using the same table
//! `props_check.rs` holds for a direct edit. A pure move out of `actions.rs`
//! (issue batch B87, toll A); the rule and its reasons are unchanged.

use crate::audio::MAX_GAIN;
use crate::model::{
    AudioProps, BlendMode, VideoProps, Wheels, MAX_FILTERS, MAX_OBSCURE, WHEEL_MAX,
};
use crate::props_check::{
    COMPRESSOR_MAKEUP_MAX_DB, COMPRESSOR_RATIO_MAX, COMPRESSOR_THRESHOLD_MIN_DB, EXPOSURE_MAX,
    SCALE_MAX, SCALE_MIN, SPOT_ZOOM_MAX, TONE_MAX,
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
