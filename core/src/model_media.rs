//! The media types — spec §5.2's `media[]`: `Media`, `MediaOriginal` and
//! `MediaKind` — moved out of `model.rs` whole (a pure move), which
//! re-exports them, so every `crate::model::Media` path holds. A media
//! record's new keys land here.

use serde::{Deserialize, Serialize};

use crate::model::MediaColor;
use crate::time::{Fps, Ticks};

// ---- media ---------------------------------------------------------------

/// One file on disk the project references. Media is referenced, never
/// copied (spec §11); `bookmark` is the app's alias data for surviving a
/// move, base64 in the JSON.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Media {
    pub id: u32,
    pub path: String,
    #[serde(default)]
    pub bookmark: Option<String>,
    pub kind: MediaKind,
    #[serde(default)]
    pub duration: Ticks,
    #[serde(default)]
    pub width: u32,
    #[serde(default)]
    pub height: u32,
    #[serde(default)]
    pub fps: Fps,
    #[serde(default)]
    pub has_video: bool,
    #[serde(default)]
    pub has_audio: bool,
    #[serde(default)]
    pub has_alpha: bool,
    #[serde(default)]
    pub original: Option<MediaOriginal>,
    /// Camera log (format version 19, spec §11 GR-16): a video media's log
    /// curve and gamut, or the `lut` media converting it, at step 0. Written
    /// only when set, so a media with none writes the text it did.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<MediaColor>,
    /// Speech spans, forward source ticks (format 29, spec §11 AU-110).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub speech: Option<Vec<[Ticks; 2]>>,
}

/// The file a playable copy was made from (format version 11, spec §11
/// #228-O): a WebM or Matroska file the app copied into a `.mov`. `path`
/// and `bookmark` above are the copy's; these are the original's, which is
/// what the app names, reveals and copies again when the copy is gone.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MediaOriginal {
    pub path: String,
    #[serde(default)]
    pub bookmark: Option<String>,
}

/// What a media file is. `Lut` is a `.cube` 3D LUT (spec §11 GR-8): media
/// so it is referenced, relinked and consolidated like footage, but never
/// placed as a clip — it is drawn only as a clip's `video.look`, and its row
/// carries no video, audio, alpha or duration (`lut.rs`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Video,
    Audio,
    Image,
    Lut,
}
