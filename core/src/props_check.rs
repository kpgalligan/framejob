//! The range checks — `check_video`, `check_audio`, `check_text` and
//! `check_shape`, one per property group — and the bounds they check
//! against. They answer one question: is this props struct, as it stands,
//! within the ranges the inspector can show (spec §4.3)?
//!
//! Cut out of `edit_props.rs` in phase 2 under the size rule
//! (core/CLAUDE.md: a module over ~600 lines gives something up before it
//! takes anything on — `set_clip` and `check_group` took that file to
//! 619), and cut HERE because a range check is a fact about the
//! VOCABULARY, not about an edit. It reads a finished `VideoProps` and says
//! whether the numbers are legal, and it neither knows nor cares whether a
//! patch (`edit_props.rs`), a paste (`edit_paste.rs`), a new title or shape
//! (`edit_clip.rs`) or a canvas colour (`edit_track.rs`) produced them.
//! Every op that writes a group runs that group's check after writing and
//! before storing, so these four functions are the ONE statement of what a
//! legal group is — and `actions_clamp.rs`'s `clamp_video` bounds an
//! interpolated value against the same constants, which is why the bounds
//! live with the checks and not in any one op.
//!
//! The rule behind every check is `edit_props.rs`'s third: values are
//! NAMED, never clamped. A channel outside 0–1 is a units mistake (0–255)
//! and a scale of 50 is a typo; the message names the dotted key and the
//! offending value, so the caller — a typed Swift builder, an MCP call, or
//! a payload written by hand — sees the number that was refused. The
//! bounds themselves are the inspector's (spec §4.3), so a value this
//! module accepts is a value a control can show.
//!
//! Every reader names this module directly — `edit_props.rs` for the four
//! checks, `edit_clip.rs` for the two a new title or shape runs,
//! `edit_track.rs` for `color_ok`, `actions.rs` for the bounds — and nothing
//! re-exports it, so a grep for its name finds every place a bound is read.

use crate::audio::MAX_GAIN;
use crate::model::{
    AudioProps, Color, ShapeProps, TextProps, VideoProps, MAX_FILTERS, MAX_GRADIENT_STOPS,
    MAX_OBSCURE,
};
use crate::model_words::token_count;
use crate::time::Ticks;
use crate::time_bounds::MAX_STORED_TICKS;

// ---- bounds --------------------------------------------------------------

/// Scale range, matching the inspector's 1–1000 % (spec §4.3). The lower
/// bound is not 0: a zero scale is an invisible layer that looks like a
/// broken render, and `opacity` is the way to hide something.
pub(crate) const SCALE_MIN: f64 = 0.01;
pub(crate) const SCALE_MAX: f64 = 10.0;

/// The most a spotlight may magnify what is inside it — spec §4.2's
/// "optional 1.2–2× zoom". Past 2× the region is soft: the pixels are
/// coming from the same decoded frame, and nothing creates detail.
pub(crate) const SPOT_ZOOM_MAX: f64 = 2.0;

/// The compressor's bounds (spec §4.3, "smooth volume levels"). The
/// threshold floor is -60 dBFS because below it there is nothing but noise
/// to compress; 20:1 is a limiter, which is as far as a "smooth the levels"
/// control should be able to go; and 24 dB of makeup is enough to bring a
/// heavily compressed voice back to full scale and no more.
pub(crate) const COMPRESSOR_THRESHOLD_MIN_DB: f64 = -60.0;
pub(crate) const COMPRESSOR_RATIO_MAX: f64 = 20.0;
pub(crate) const COMPRESSOR_MAKEUP_MAX_DB: f64 = 24.0;

/// Where a word-caption page's active word may settle (format version 9,
/// road map 8 §5a). 1 is "no pop"; past 1.5 the active word crowds its
/// neighbours on a page the pager filled to a measured width.
pub(crate) const WORD_SCALE_MIN: f64 = 1.0;
pub(crate) const WORD_SCALE_MAX: f64 = 1.5;

// ---- range checks --------------------------------------------------------

fn finite(key: &str, value: f64) -> Result<(), String> {
    if value.is_finite() {
        Ok(())
    } else {
        Err(format!("{key} must be a finite number, not {value}"))
    }
}

fn in_range(key: &str, value: f64, low: f64, high: f64) -> Result<(), String> {
    if value.is_finite() && value >= low && value <= high {
        Ok(())
    } else {
        Err(format!(
            "{key} must be between {low} and {high}, not {value}"
        ))
    }
}

fn at_least(key: &str, value: f64, low: f64) -> Result<(), String> {
    if value.is_finite() && value >= low {
        Ok(())
    } else {
        Err(format!("{key} must be at least {low}, not {value}"))
    }
}

fn above(key: &str, value: f64, low: f64) -> Result<(), String> {
    if value.is_finite() && value > low {
        Ok(())
    } else {
        Err(format!("{key} must be greater than {low}, not {value}"))
    }
}

/// Colors are `[r, g, b, a]` floats 0–1 (spec §5.2); a channel outside that
/// is a unit mistake (0–255) the renderer would turn into a blown-out
/// layer, so it is named rather than clamped.
pub(crate) fn color_ok(key: &str, color: &Color) -> Result<(), String> {
    for channel in color {
        in_range(key, *channel, 0.0, 1.0)?;
    }
    Ok(())
}

/// A clip-time position inside D7-1's envelope, in `time_bounds.rs`'s own
/// words — a word time is a position, so it may be negative.
fn ticks_in_envelope(key: &str, value: Ticks) -> Result<(), String> {
    if (-MAX_STORED_TICKS..=MAX_STORED_TICKS).contains(&value) {
        Ok(())
    } else {
        Err(format!(
            "{key} must be between -{MAX_STORED_TICKS} and {MAX_STORED_TICKS} ticks, not {value}"
        ))
    }
}

fn ticks_positive_or_zero(key: &str, value: Ticks) -> Result<(), String> {
    if value >= 0 {
        Ok(())
    } else {
        Err(format!("{key} must not be negative, not {value}"))
    }
}

/// The video group. `size` is the source's pixel size when it is known, so
/// a crop can be checked against the thing being cropped.
pub(crate) fn check_video(props: &VideoProps, size: Option<(f64, f64)>) -> Result<(), String> {
    finite("video.x", props.x)?;
    finite("video.y", props.y)?;
    in_range("video.scale", props.scale, SCALE_MIN, SCALE_MAX)?;
    finite("video.rotation", props.rotation)?;
    in_range("video.opacity", props.opacity, 0.0, 1.0)?;
    at_least("video.corner_radius", props.corner_radius, 0.0)?;
    at_least("video.crop.l", props.crop.l, 0.0)?;
    at_least("video.crop.t", props.crop.t, 0.0)?;
    at_least("video.crop.r", props.crop.r, 0.0)?;
    at_least("video.crop.b", props.crop.b, 0.0)?;
    // Opposite edges must leave something behind: a crop that meets or
    // crosses is an empty rectangle, which no renderer can draw.
    if let Some((width, height)) = size {
        let horizontal = props.crop.l + props.crop.r;
        if horizontal >= width {
            return Err(format!(
                "video.crop l + r must be less than the source width {width}, not {horizontal}"
            ));
        }
        let vertical = props.crop.t + props.crop.b;
        if vertical >= height {
            return Err(format!(
                "video.crop t + b must be less than the source height {height}, not {vertical}"
            ));
        }
    }
    // Motion (format version 8). The two edge values are DURATIONS, so 0 is
    // legal — it means that end of the clip does not move — and a negative
    // one is a sign mistake, not a request to run the preset backwards;
    // `text.animation`'s arm below is the precedent. These ticks are not
    // snapped HERE, and since D1·2 that is an order rather than an
    // exemption: `edit_props.rs`'s `snap_motion` puts them on the frame
    // grid AFTER this check, so a refusal names the number the caller sent
    // rather than one the door rounded it to. `amount` is a fraction of the
    // preset's own range, so 0 is the identity and 1 the full strength.
    // `period` is the one value with no meaningful zero: it is a divisor in
    // every `during` formula, so one tick is the floor and the message says
    // so rather than naming a range (the snap's own floor is a FRAME, for
    // the same reason one step further on). The two KINDS need no check —
    // serde refuses an unknown variant on the way in, which is what closing
    // both enums bought (`model_motion.rs`).
    if let Some(motion) = &props.motion {
        if let Some(edge) = &motion.r#in {
            ticks_positive_or_zero("video.motion.in.duration", edge.duration)?;
        }
        if let Some(edge) = &motion.out {
            ticks_positive_or_zero("video.motion.out.duration", edge.duration)?;
        }
        if let Some(during) = &motion.during {
            in_range("video.motion.during.amount", during.amount, 0.0, 1.0)?;
            if during.period < 1 {
                return Err(format!(
                    "video.motion.during.period must be at least one tick, not {}",
                    during.period
                ));
            }
        }
    }
    if let Some(shadow) = &props.shadow {
        color_ok("video.shadow.color", &shadow.color)?;
        in_range("video.shadow.opacity", shadow.opacity, 0.0, 1.0)?;
        at_least("video.shadow.blur", shadow.blur, 0.0)?;
        finite("video.shadow.angle", shadow.angle)?;
        at_least("video.shadow.distance", shadow.distance, 0.0)?;
    }
    // The color controls are offsets from neutral, not absolute levels, so
    // any finite value is meaningful; the UI's sliders bound them.
    finite("video.color.brightness", props.color.brightness)?;
    finite("video.color.contrast", props.color.contrast)?;
    finite("video.color.saturation", props.color.saturation)?;
    finite("video.color.hue", props.color.hue)?;
    if let Some(chroma) = &props.chroma {
        for channel in &chroma.key {
            in_range("video.chroma.key", *channel, 0.0, 1.0)?;
        }
        in_range("video.chroma.tolerance", chroma.tolerance, 0.0, 1.0)?;
        in_range("video.chroma.softness", chroma.softness, 0.0, 1.0)?;
        in_range("video.chroma.spill", chroma.spill, 0.0, 1.0)?;
    }
    // The budget is named rather than trimmed, for the same reason a value
    // out of range is named: the fifth filter would be gone from the next
    // write and the user would be looking at a control that did nothing.
    if props.filters.len() > MAX_FILTERS {
        return Err(format!(
            "video.filters must hold at most {MAX_FILTERS} filters, not {}",
            props.filters.len()
        ));
    }
    for (i, filter) in props.filters.iter().enumerate() {
        in_range(
            &format!("video.filters[{i}].amount"),
            filter.amount,
            0.0,
            1.0,
        )?;
    }
    if let Some(reflection) = &props.reflection {
        in_range("video.reflection.opacity", reflection.opacity, 0.0, 1.0)?;
        in_range("video.reflection.height", reflection.height, 0.0, 1.0)?;
        at_least("video.reflection.gap", reflection.gap, 0.0)?;
        in_range("video.reflection.falloff", reflection.falloff, 0.0, 1.0)?;
    }
    if let Some(spotlight) = &props.spotlight {
        // The centre may sit outside the layer — half a spotlight running
        // off the edge of the frame is a legitimate picture — so x and y
        // are only required to be numbers.
        finite("video.spotlight.x", spotlight.x)?;
        finite("video.spotlight.y", spotlight.y)?;
        above("video.spotlight.width", spotlight.width, 0.0)?;
        above("video.spotlight.height", spotlight.height, 0.0)?;
        at_least("video.spotlight.feather", spotlight.feather, 0.0)?;
        in_range("video.spotlight.dim", spotlight.dim, 0.0, 1.0)?;
        // 1 is "no zoom", so the range starts there: a spotlight that
        // shrank what it points at would be a magnifier held backwards.
        in_range("video.spotlight.zoom", spotlight.zoom, 1.0, SPOT_ZOOM_MAX)?;
    }
    // The same budget and the same posture as the filters above: the fifth
    // region is NAMED, not trimmed. A dropped filter is a control that does
    // nothing; a dropped region is the face it was drawn over, still on
    // screen and nobody told.
    if props.obscure.len() > MAX_OBSCURE {
        return Err(format!(
            "video.obscure must hold at most {MAX_OBSCURE} regions, not {}",
            props.obscure.len()
        ));
    }
    for (i, region) in props.obscure.iter().enumerate() {
        // The centre may sit outside the layer, for the spotlight's reason
        // above: half a region running off the edge of the frame is a
        // legitimate picture, so x and y are only required to be numbers.
        finite(&format!("video.obscure[{i}].x"), region.x)?;
        finite(&format!("video.obscure[{i}].y"), region.y)?;
        above(&format!("video.obscure[{i}].width"), region.width, 0.0)?;
        above(&format!("video.obscure[{i}].height"), region.height, 0.0)?;
        at_least(&format!("video.obscure[{i}].feather"), region.feather, 0.0)?;
        in_range(
            &format!("video.obscure[{i}].amount"),
            region.amount,
            0.0,
            1.0,
        )?;
    }
    Ok(())
}

/// The audio group. Its six tick values — the two fades, the duck's and the
/// compressor's attack and release — are the one family the Times rule
/// deliberately leaves OFF the frame grid (core/CLAUDE.md): they are
/// envelope lengths sampled at the audio rate rather than positions in the
/// picture, and a 10 ms compressor attack quantised to a video frame would
/// round to nothing. Only the sign is checked, as it is for a motion
/// duration.
pub(crate) fn check_audio(props: &AudioProps) -> Result<(), String> {
    in_range("audio.volume", props.volume, 0.0, MAX_GAIN)?;
    ticks_positive_or_zero("audio.fade_in", props.fade_in)?;
    ticks_positive_or_zero("audio.fade_out", props.fade_out)?;
    if let Some(duck) = &props.duck {
        in_range("audio.duck.level", duck.level, 0.0, 1.0)?;
        ticks_positive_or_zero("audio.duck.attack", duck.attack)?;
        ticks_positive_or_zero("audio.duck.release", duck.release)?;
    }
    in_range("audio.pan", props.pan, -1.0, 1.0)?;
    in_range("audio.noise_reduction", props.noise_reduction, 0.0, 1.0)?;
    if let Some(compressor) = &props.compressor {
        in_range(
            "audio.compressor.threshold_db",
            compressor.threshold_db,
            COMPRESSOR_THRESHOLD_MIN_DB,
            0.0,
        )?;
        in_range(
            "audio.compressor.ratio",
            compressor.ratio,
            1.0,
            COMPRESSOR_RATIO_MAX,
        )?;
        ticks_positive_or_zero("audio.compressor.attack", compressor.attack)?;
        ticks_positive_or_zero("audio.compressor.release", compressor.release)?;
        in_range(
            "audio.compressor.makeup_db",
            compressor.makeup_db,
            0.0,
            COMPRESSOR_MAKEUP_MAX_DB,
        )?;
    }
    Ok(())
}

pub(crate) fn check_text(props: &TextProps) -> Result<(), String> {
    above("text.size", props.size, 0.0)?;
    color_ok("text.color", &props.color)?;
    above("text.line_spacing", props.line_spacing, 0.0)?;
    finite("text.tracking", props.tracking)?;
    if let Some(outline) = &props.outline {
        at_least("text.outline.width", outline.width, 0.0)?;
        color_ok("text.outline.color", &outline.color)?;
    }
    if let Some(backdrop) = &props.backdrop {
        color_ok("text.backdrop.color", &backdrop.color)?;
        at_least("text.backdrop.padding", backdrop.padding, 0.0)?;
        at_least("text.backdrop.radius", backdrop.radius, 0.0)?;
    }
    if let Some(width) = props.width {
        above("text.width", width, 0.0)?;
    }
    if let Some(animation) = &props.animation {
        // Both are durations, so 0 is legal — it means that end of the
        // animation does not happen — and a negative one is a sign
        // mistake, not a request to run the reveal backwards. `Ticks` is an
        // `i64`, so "finite" is the type's job and only the sign is left
        // for a check to make. They are snapped to the frame grid by
        // `edit_props.rs`'s `snap_animation`, after this check and for the
        // motion arm's reason above. The KIND needs none: serde refuses an
        // unknown variant on the way in, which is what closing the enum
        // bought (`model_props.rs`).
        ticks_positive_or_zero("text.animation.in", animation.r#in)?;
        ticks_positive_or_zero("text.animation.out", animation.out)?;
    }
    // Word timings (format version 9, spec §11 W-2 and W-3). The core is
    // the one counter: a non-empty list must hold one timing per
    // whitespace token, and it is never padded or trimmed to fit. Each
    // time is a clip-time POSITION, so a negative one is legal ("already
    // said", what `split` leaves on a second half) and only D7-1's envelope
    // bounds it. Equal starts are legal too — two engine words snapped to
    // one frame — so the order rule is non-decreasing, and a word may be
    // zero-length. These run on what the caller sent; `edit_props.rs`'s
    // `snap_animation` snaps them after, so a refusal names that number.
    if !props.words.is_empty() {
        let tokens = token_count(&props.content);
        if props.words.len() != tokens {
            return Err(format!(
                "this text is timed word by word: {} timings for {tokens} words",
                props.words.len()
            ));
        }
    }
    for (i, word) in props.words.iter().enumerate() {
        ticks_in_envelope(&format!("text.words[{i}].start"), word.start)?;
        ticks_in_envelope(&format!("text.words[{i}].end"), word.end)?;
        if word.end < word.start {
            return Err(format!(
                "text.words[{i}].end must be at least its start {}, not {}",
                word.start, word.end
            ));
        }
        if i > 0 && word.start < props.words[i - 1].start {
            return Err(format!(
                "text.words[{i}].start must not precede text.words[{}].start {}, not {}",
                i - 1,
                props.words[i - 1].start,
                word.start
            ));
        }
    }
    if let Some(style) = &props.word_style {
        in_range(
            "text.word_style.active_scale",
            style.active_scale,
            WORD_SCALE_MIN,
            WORD_SCALE_MAX,
        )?;
        if let Some(color) = &style.active_color {
            color_ok("text.word_style.active_color", color)?;
        }
        if let Some(color) = &style.spoken_color {
            color_ok("text.word_style.spoken_color", color)?;
        }
        if let Some(color) = &style.upcoming_color {
            color_ok("text.word_style.upcoming_color", color)?;
        }
        if let Some(pill) = &style.active_pill {
            color_ok("text.word_style.active_pill.color", &pill.color)?;
            at_least("text.word_style.active_pill.padding", pill.padding, 0.0)?;
            at_least("text.word_style.active_pill.radius", pill.radius, 0.0)?;
        }
        in_range("text.word_style.pause_dim", style.pause_dim, 0.0, 1.0)?;
    }
    Ok(())
}

pub(crate) fn check_shape(props: &ShapeProps) -> Result<(), String> {
    above("shape.width", props.width, 0.0)?;
    above("shape.height", props.height, 0.0)?;
    at_least("shape.radius", props.radius, 0.0)?;
    if let Some(stroke) = &props.stroke {
        at_least("shape.stroke.width", stroke.width, 0.0)?;
        color_ok("shape.stroke.color", &stroke.color)?;
    }
    if let Some(fill) = &props.fill {
        color_ok("shape.fill", fill)?;
    }
    for point in [&props.from, &props.to] {
        for coordinate in point {
            finite("shape.from/to", *coordinate)?;
        }
    }
    if let Some(gradient) = &props.gradient {
        // Two stops is the floor because ONE stop is a solid colour, and
        // `shape.fill` already spells a solid colour. `CGGradient` would
        // happily draw a single stop, which is exactly why the refusal is
        // here: a control that quietly becomes a different control is worse
        // than one that says no.
        if gradient.stops.len() < 2 {
            return Err(format!(
                "shape.gradient.stops must hold at least 2 stops, not {}",
                gradient.stops.len()
            ));
        }
        // The ceiling is NAMED rather than trimmed, the posture `MAX_FILTERS`
        // and `MAX_OBSCURE` take — but it is 8 where both of those are 4, and
        // `MAX_GRADIENT_STOPS`' own doc argues why: those two are shader
        // slots and this one is not a budget at all.
        if gradient.stops.len() > MAX_GRADIENT_STOPS {
            return Err(format!(
                "shape.gradient.stops must hold at most {MAX_GRADIENT_STOPS} stops, not {}",
                gradient.stops.len()
            ));
        }
        // There is deliberately NO ordering check here, and it is the one
        // absence in this module worth writing down. `CGGradient` requires
        // monotonic locations or its output is undefined, so the temptation
        // is to refuse an unsorted list — but a refusal has a failure mode
        // nobody would accept: dragging one stop past another is how a
        // gradient is edited, and the drag would stop working halfway
        // through. `video.filters` is the precedent — an ordered list the
        // core does not police — and the fix belongs where the requirement
        // is, so `LayerRenderers.renderShape` sorts before it draws.
        // And the question is a RENDER-time one only, which is what keeps
        // the answer small: a gradient is never interpolated, because shape
        // props are not animatable at all (`actions.rs::evaluate_clip`
        // builds its merge state from `video`, `audio` and `text`, and
        // passes `shape` through untouched — spec §5.4). So an unsorted list is
        // only ever DRAWN, once, by a renderer that sorts it first. Do not
        // read this as "the list rule handles it"; there is no list rule in
        // play here, and if shapes ever become animatable the ordering
        // question has to be asked again against `lerp`.
        for (i, stop) in gradient.stops.iter().enumerate() {
            in_range(&format!("shape.gradient.stops[{i}].at"), stop.at, 0.0, 1.0)?;
            color_ok(&format!("shape.gradient.stops[{i}].color"), &stop.color)?;
        }
        // Finite and nothing more, exactly as `video.shadow.angle` is: the
        // value is named and never clamped, and wrapping it into 0..360 here
        // would silently rewrite the number a person typed.
        finite("shape.gradient.angle", gradient.angle)?;
    }
    Ok(())
}
