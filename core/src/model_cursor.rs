//! The cursor's model vocabulary (format 38, spec §11 CU-30, CU-39):
//! [`MediaCursor`], a media's `media.cursor` — the cursor file recorded
//! beside its movie — and [`CursorProps`], a clip's `video.cursor` — how
//! that cursor is drawn — with [`CursorStyle`], [`CursorClicks`] and the
//! ranges `cursor_props.rs` checks and clamps to.
//!
//! Re-exported whole by `model_props.rs` (and so by `model.rs`), so every
//! `crate::model::CursorProps` path resolves. What the recipe makes of the
//! two is `recipe_cursor.rs`'s; reading the file itself is `cursor_track.rs`'s.
//! The JSON spelling of each enum variant is persisted: append, never rename.

use serde::{Deserialize, Serialize};

/// `video.cursor.scale`'s range: the drawn cursor's size against its
/// recorded one (CU-30).
pub const CURSOR_SCALE_MIN: f64 = 0.25;
pub const CURSOR_SCALE_MAX: f64 = 8.0;
/// `video.cursor.hide_idle`'s range, in seconds of no activity (CU-30).
pub const CURSOR_HIDE_IDLE_MIN: f64 = 0.5;
pub const CURSOR_HIDE_IDLE_MAX: f64 = 30.0;
/// `video.cursor.click_size`'s range: a ripple's size against its own (CU-30).
pub const CURSOR_CLICK_SIZE_MIN: f64 = 0.25;
pub const CURSOR_CLICK_SIZE_MAX: f64 = 4.0;
/// A ripple's colour when none is given, and what an unreadable one
/// evaluates as (CU-30).
pub const CURSOR_CLICK_COLOR: &str = "#ffffffcc";

/// A media's cursor file (CU-39): its path, the app's bookmark for it
/// (base64, written only when set) and whether the movie's own picture
/// already shows the pointer, in which case Frame Job draws none (CU-32).
/// `in_picture` is required: a record without it does not read.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MediaCursor {
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bookmark: Option<String>,
    pub in_picture: bool,
}

/// Which pointer is drawn: the images the file recorded, or Frame Job's
/// arrow (CU-30).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CursorStyle {
    #[default]
    Recorded,
    Arrow,
}

/// What a click draws: nothing, or a ripple (CU-23, CU-30).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CursorClicks {
    #[default]
    None,
    Ripple,
}

/// A clip's `video.cursor` (CU-30), every field written in this order;
/// `{}` reads as the defaults. `scale` and `click_size` animate in an
/// action; `show`, `style`, `clicks` and `click_color` switch at its end;
/// `smoothing` and `hide_idle` are the clip's own — the recipe reads them
/// from the BASE props only (`cursor_props.rs`'s `with_base_cursor`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct CursorProps {
    pub show: bool,
    pub scale: f64,
    pub style: CursorStyle,
    /// 0…1 (CU-21).
    pub smoothing: f64,
    /// Seconds, 0.5…30, or `None` — never hidden. Written `null`.
    pub hide_idle: Option<f64>,
    pub clicks: CursorClicks,
    /// A CSS colour in G-12's grammar, stored as given.
    pub click_color: String,
    pub click_size: f64,
}

impl Default for CursorProps {
    fn default() -> Self {
        CursorProps {
            show: true,
            scale: 1.0,
            style: CursorStyle::Recorded,
            smoothing: 0.0,
            hide_idle: None,
            clicks: CursorClicks::None,
            click_color: CURSOR_CLICK_COLOR.to_string(),
            click_size: 1.0,
        }
    }
}
