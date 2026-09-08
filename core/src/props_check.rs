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
//! legal group is — and `actions.rs`'s `clamp_video` bounds an
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
    AudioProps, Color, ShapeProps, TextProps, VideoProps, MAX_FILTERS, MAX_OBSCURE,
};
use crate::time::Ticks;

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
    for filter in &props.filters {
        in_range("video.filters[].amount", filter.amount, 0.0, 1.0)?;
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
    for region in &props.obscure {
        // The centre may sit outside the layer, for the spotlight's reason
        // above: half a region running off the edge of the frame is a
        // legitimate picture, so x and y are only required to be numbers.
        finite("video.obscure[].x", region.x)?;
        finite("video.obscure[].y", region.y)?;
        above("video.obscure[].width", region.width, 0.0)?;
        above("video.obscure[].height", region.height, 0.0)?;
        at_least("video.obscure[].feather", region.feather, 0.0)?;
        in_range("video.obscure[].amount", region.amount, 0.0, 1.0)?;
    }
    Ok(())
}

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
        // for a check to make. The KIND needs none: serde refuses an
        // unknown variant on the way in, which is what closing the enum
        // bought (`model_props.rs`).
        ticks_positive_or_zero("text.animation.in", animation.r#in)?;
        ticks_positive_or_zero("text.animation.out", animation.out)?;
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
    Ok(())
}
