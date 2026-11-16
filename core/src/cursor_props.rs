//! The cursor's rules on the model (format 38, spec §11 CU-30, CU-39): the
//! range checks `props_check.rs`'s `check_video` runs on `video.cursor`
//! ([`check_cursor`]), the evaluator's clamp `actions_clamp.rs`'s
//! `clamp_video` runs on an action's end ([`clamp_cursor`], which never
//! fails, so the video group always decodes), the media record's check
//! `edit_track.rs`'s `check_media_fields` ends with ([`check_media_cursor`]),
//! and [`with_base_cursor`] — the one statement of "`smoothing` and
//! `hide_idle` are the clip's own", read by the recipe, `split` and
//! `freeze_frame`.

use crate::actions_clamp::bounded;
use crate::model::{
    CursorProps, Media, MediaKind, VideoProps, CURSOR_CLICK_COLOR, CURSOR_CLICK_SIZE_MAX,
    CURSOR_CLICK_SIZE_MIN, CURSOR_HIDE_IDLE_MAX, CURSOR_HIDE_IDLE_MIN, CURSOR_SCALE_MAX,
    CURSOR_SCALE_MIN,
};
use crate::model_color::normalise_color;
use crate::props_check::in_range;

/// `video.cursor`'s ranges, each refused in `in_range`'s sentence under its
/// own key, then the click colour in G-12's grammar (CU-30). No cursor is
/// nothing to check.
pub(crate) fn check_cursor(cursor: &Option<CursorProps>) -> Result<(), String> {
    let Some(cursor) = cursor else {
        return Ok(());
    };
    in_range(
        "video.cursor.scale",
        cursor.scale,
        CURSOR_SCALE_MIN,
        CURSOR_SCALE_MAX,
    )?;
    in_range("video.cursor.smoothing", cursor.smoothing, 0.0, 1.0)?;
    if let Some(hide_idle) = cursor.hide_idle {
        in_range(
            "video.cursor.hide_idle",
            hide_idle,
            CURSOR_HIDE_IDLE_MIN,
            CURSOR_HIDE_IDLE_MAX,
        )?;
    }
    in_range(
        "video.cursor.click_size",
        cursor.click_size,
        CURSOR_CLICK_SIZE_MIN,
        CURSOR_CLICK_SIZE_MAX,
    )?;
    if normalise_color(&cursor.click_color).is_none() {
        return Err(format!(
            "video.cursor.click_color must be a CSS color (spec §11 G-12), not \"{}\"",
            cursor.click_color
        ));
    }
    Ok(())
}

/// An evaluated cursor brought into its ranges (CU-30): each number clamped,
/// NaN to its default (`hide_idle`'s NaN to none), the click colour
/// normalised and an unreadable one [`CURSOR_CLICK_COLOR`]. Never fails.
pub(crate) fn clamp_cursor(cursor: &mut Option<CursorProps>) {
    let Some(cursor) = cursor.as_mut() else {
        return;
    };
    cursor.scale = bounded(cursor.scale, CURSOR_SCALE_MIN, CURSOR_SCALE_MAX, 1.0);
    cursor.smoothing = bounded(cursor.smoothing, 0.0, 1.0, 0.0);
    cursor.hide_idle = cursor
        .hide_idle
        .filter(|seconds| !seconds.is_nan())
        .map(|seconds| seconds.clamp(CURSOR_HIDE_IDLE_MIN, CURSOR_HIDE_IDLE_MAX));
    cursor.click_size = bounded(
        cursor.click_size,
        CURSOR_CLICK_SIZE_MIN,
        CURSOR_CLICK_SIZE_MAX,
        1.0,
    );
    cursor.click_color =
        normalise_color(&cursor.click_color).unwrap_or_else(|| CURSOR_CLICK_COLOR.to_string());
}

/// A media's `cursor` (CU-39): an empty path refused, and a cursor on
/// anything but a video media with a picture refused naming what it is.
/// The bookmark is stored as given.
pub(crate) fn check_media_cursor(media: &Media) -> Result<(), String> {
    let Some(cursor) = &media.cursor else {
        return Ok(());
    };
    if cursor.path.trim().is_empty() {
        return Err("media cursor path must not be empty".to_string());
    }
    let what = match media.kind {
        MediaKind::Video if media.has_video => return Ok(()),
        MediaKind::Video => "a video media without a picture",
        MediaKind::Audio => "an audio media",
        MediaKind::Image => "an image media",
        MediaKind::Lut => "a LUT media",
    };
    Err(format!(
        "media.cursor needs a video media with a picture, not {what}"
    ))
}

/// `evaluated` with its cursor's `smoothing` and `hide_idle` set to `base`'s
/// — 0 and none when `base` or its cursor is `None` — so neither ever comes
/// from an action's end (CU-30). A `None` evaluated cursor stays `None`.
/// Read by `recipe_cursor.rs`, and by `split`'s second half and
/// `freeze_frame`'s still, so no splitter turns an end's values into a base.
pub(crate) fn with_base_cursor(mut evaluated: VideoProps, base: Option<&VideoProps>) -> VideoProps {
    if let Some(cursor) = evaluated.cursor.as_mut() {
        let base = base.and_then(|video| video.cursor.as_ref());
        cursor.smoothing = base.map_or(0.0, |base| base.smoothing);
        cursor.hide_idle = base.and_then(|base| base.hide_idle);
    }
    evaluated
}
