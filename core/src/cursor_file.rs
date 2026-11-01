//! The cursor file, format v1 (spec §11 CU-10): what a screen recording's
//! pointer, clicks, scrolls and keys were, written by the recorder beside
//! each segment movie as `<stem>.fjcursor` (CU-15) and read back through
//! `rc_cursor_open` before it is renamed into place. **This doc is the
//! format's specification**; `cursor_file_check.rs` holds the check and the
//! base64 decoder, `ffi_cursor.rs` the two exports.
//!
//! **The body** is one UTF-8 JSON object (CU-S4 `body=json`). Every time is
//! integer µs from the movie's first frame. Every position and length is
//! integer points × 100 in global display coordinates (`x`, `y`, a rect's
//! `[x, y, w, h]`, a size's `[w, h]`, an image's hot spot and size); a size
//! in px is an integer. The keys, every one required unless marked `?`:
//!
//! - `format` `"framejob-cursor"` · `version` 1 · `in_picture` bool ·
//!   `source` `"display"` | `"window"` | `"picked"` · `display_id?` u32.
//! - `source_frame` `[x, y, w, h]`, the SCDisplay or SCWindow frame at the
//!   segment's open (CU-S2's M3) · `point_size` `[w, h]` · `pixels_per_point`
//!   f64 · `content_size` `[w, h]` px, the stream's · `movie_size` `[w, h]`
//!   px, the written track's (CU-16), each side 1…16384.
//! - `anchor` `"e2"` | `"e1"`, the first frame the times count from, and
//!   `anchor_host_us` its host time (≥ 0) · `cursor_image`
//!   `"current-system"` | `"none"` (no images and no image changes).
//! - Columns, each an object of equal-length integer arrays sorted by time:
//!   `moves {t, x, y}`; `image_changes {t, id}`, `id` an index into
//!   `images`; `hidden {from, to}`, spans in order, each `to > from`, a span
//!   starting at or after the previous one's `to` (touching allowed);
//!   `clicks {t, button, down, x, y, count}`, `button` 0…31, `down` 0 or 1,
//!   `count` ≥ 1; `scrolls {t, x, y, dx, dy}`, `dx`/`dy` the event's point
//!   deltas as delivered (after the system's scroll direction; horizontal
//!   `dx`, vertical `dy`) × 100, signed, line deltas not stored;
//!   `dirty {t, x, y, w, h}`.
//! - `images`: `[{png, hot_x, hot_y, w, h, kind?}]`, its id its index: `png`
//!   is base64 (standard alphabet, padded) of a PNG, checked by its
//!   signature only (the core does no pixel work); the hot spot lies within
//!   `[0, w] × [0, h]`; `kind` one of `arrow`, `ibeam`, `ibeam_vertical`,
//!   `pointing_hand`, `open_hand`, `closed_hand`, `crosshair`,
//!   `operation_not_allowed`, `drag_copy`, `drag_link`, `contextual_menu`,
//!   `disappearing_item`, `resize_left`, `resize_right`, `resize_left_right`,
//!   `resize_up`, `resize_down`, `resize_up_down`.
//! - `geometry`: `[{t, screen_rect, content_rect, content_scale,
//!   scale_factor}]`, at least one entry, every CU-S2 candidate's inputs.
//! - `keys`: `{shortcut {t, keys, code}, typed {t}}`. A shortcut's `keys`
//!   is its spelled keys joined by `+` (`+` itself spelled `plus`), every
//!   token non-empty, without whitespace, holding `cmd` or `ctrl`; `code` the
//!   layout-independent key code. A typed key is its time and nothing else
//!   (CU-7): no character, label or code of one can be stored.
//!
//! `hidden` and `dirty` stay empty until CU-S1 and CU-S3 pass; `keys` until
//! CU6. Floats (`pixels_per_point`, `content_scale`, `scale_factor`) must be
//! finite and above 0. The caps: [`MAX_MOVES`], [`MAX_SCROLLS`] and
//! [`MAX_DIRTY`] 1,728,000 each (4 h at 120 Hz); [`MAX_CLICKS`] 200,000;
//! [`MAX_IMAGES`] 1,024; one PNG [`MAX_IMAGE_BYTES`] 1 MiB;
//! [`MAX_IMAGE_CHANGES`] 1,000,000; [`MAX_HIDDEN`], [`MAX_GEOMETRY`] and
//! [`MAX_SHORTCUTS`] 100,000; [`MAX_TYPED`] 1,000,000.
//!
//! **The parse order** ([`CursorFile::parse`]). A loose read first, as a
//! `serde_json::Value`: bytes that are not JSON ("the cursor file is not
//! JSON: …"), then not an object ("the cursor file is not a JSON object"),
//! then `format` absent or not `"framejob-cursor"` ("this is not a Frame Job
//! cursor file: its \"format\" is not \"framejob-cursor\""), then `version`
//! absent or not an integer ("the cursor file's \"version\" is not an
//! integer"), above [`RC_CURSOR_FILE_VERSION`] ("the cursor file is version
//! N; this Frame Job reads cursor files up to version 1") or below 1 ("the
//! cursor file is version N; versions start at 1"), then a `typed` object
//! holding any key but `t` ("keys.typed holds a typed key's time only;
//! \"<key>\" is refused (spec §11 CU-7)"). Only then the strict read, every
//! object `deny_unknown_fields`, through `serde_path_to_error` ("the cursor
//! file at \"<path>\": <serde's sentence>", "…at its top level: …" for the
//! root), so a newer file carrying keys v1 does not know is refused by its
//! version and a project's JSON by its format. Then each image's base64
//! ("images[i].png is not base64: …"), then `cursor_file_check::check`,
//! whose sentences are listed under **The check** below.
//!
//! **The check** (`cursor_file_check::check`), in order: the header's values (`anchor_host_us`, the floats, the two
//! sizes), then every column's lengths, the caps, the times, the hidden
//! spans, the images, the image changes, `cursor_image: "none"`, the clicks'
//! values, the geometry and the shortcuts. The sentences:
//!
//! - "anchor_host_us is N; a host time is never negative"
//! - "pixels_per_point is V; it must be a finite number above 0" (and
//!   `geometry[i].content_scale`, `geometry[i].scale_factor`)
//! - "content_size [w, h] is outside 1…16384" (and `movie_size`)
//! - "moves.x has N entries and moves.t has M; a column's entries match its
//!   siblings'"
//! - "moves holds N entries; its cap is M" ("images[i].png is N bytes; its
//!   cap is M" for one PNG)
//! - "moves.t[i] is N, a negative time"; "moves.t[i] is N, before
//!   moves.t[i-1] (M); a column's times never go back"
//! - "hidden span i is empty (from F to T)"; "hidden span i (from F) starts
//!   before hidden span i-1 (from G); spans are in order"; "hidden span i
//!   (from F) overlaps hidden span i-1 (to T)"; "hidden.from[i] is N, a
//!   negative time"
//! - "images[i].png is not a PNG: its bytes do not begin with the PNG
//!   signature"; "images[i]'s hot spot (x, y) lies outside its size (w × h)"
//! - "image_changes.id[i] is N; the file has M images"
//! - "cursor_image is \"none\", yet the file holds N images and M image
//!   changes"
//! - "clicks.button[i] is N; a button is 0…31"; "clicks.down[i] is N; down
//!   is 0 or 1"; "clicks.count[i] is N; a click count is at least 1"
//! - "geometry holds no entry; a cursor file has at least one"
//! - "keys.shortcut.keys[i] \"…\" is not a shortcut: <why> (spec §11 CU-7)"
//! - `check_typed`'s "keys.typed holds a typed key's time only; \"<key>\"
//!   is refused (spec §11 CU-7)", run by the parse before its strict read.
//!
//! Nothing of Cap or OpenScreen is carried (spec §11 CU-8); the columnar
//! shape and the base64 follow our own CU-S4 reader prototype, whose parse
//! order is not followed.

use serde::Deserialize;
use serde_json::Value;

use crate::cursor_file_check::{check, check_typed, decode_base64};

/// The newest cursor file this core reads, and the one Swift writes.
pub const RC_CURSOR_FILE_VERSION: u32 = 1;
/// The body's `format`.
pub const CURSOR_FORMAT: &str = "framejob-cursor";

/// 4 h at 120 Hz.
pub const MAX_MOVES: usize = 1_728_000;
pub const MAX_SCROLLS: usize = 1_728_000;
pub const MAX_DIRTY: usize = 1_728_000;
pub const MAX_CLICKS: usize = 200_000;
pub const MAX_IMAGES: usize = 1_024;
/// One PNG's decoded bytes.
pub const MAX_IMAGE_BYTES: usize = 1_048_576;
pub const MAX_IMAGE_CHANGES: usize = 1_000_000;
pub const MAX_HIDDEN: usize = 100_000;
pub const MAX_GEOMETRY: usize = 100_000;
pub const MAX_SHORTCUTS: usize = 100_000;
pub const MAX_TYPED: usize = 1_000_000;
/// The largest side a size in px may have.
pub const MAX_SIDE_PX: i64 = 16_384;

/// What the recording captured.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceKind {
    Display,
    Window,
    Picked,
}

/// The first frame the file's times count from (CU-17, `CursorAnchor`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Anchor {
    E2,
    E1,
}

/// Whether the file carries the system cursor's images.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum CursorImageMode {
    #[serde(rename = "current-system")]
    CurrentSystem,
    #[serde(rename = "none")]
    None,
}

/// A known system cursor an image equals.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CursorKind {
    Arrow,
    Ibeam,
    IbeamVertical,
    PointingHand,
    OpenHand,
    ClosedHand,
    Crosshair,
    OperationNotAllowed,
    DragCopy,
    DragLink,
    ContextualMenu,
    DisappearingItem,
    ResizeLeft,
    ResizeRight,
    ResizeLeftRight,
    ResizeUp,
    ResizeDown,
    ResizeUpDown,
}

/// One cursor image: its PNG (decoded from the body's base64), its hot spot
/// and point size (points × 100), and the system cursor it equals.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CursorImage {
    #[serde(skip)]
    pub png: Vec<u8>,
    /// The body's text, decoded into `png` by [`CursorFile::parse`] and
    /// then dropped.
    #[serde(rename = "png")]
    png_base64: String,
    pub hot_x: i64,
    pub hot_y: i64,
    pub w: i64,
    pub h: i64,
    #[serde(default)]
    pub kind: Option<CursorKind>,
}

/// The stream's geometry from time `t` (CU-S2's inputs).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Geometry {
    pub t: i64,
    pub screen_rect: [i64; 4],
    pub content_rect: [i64; 4],
    pub content_scale: f64,
    pub scale_factor: f64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Moves {
    pub t: Vec<i64>,
    pub x: Vec<i64>,
    pub y: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ImageChanges {
    pub t: Vec<i64>,
    pub id: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Hidden {
    pub from: Vec<i64>,
    pub to: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Clicks {
    pub t: Vec<i64>,
    pub button: Vec<i64>,
    pub down: Vec<i64>,
    pub x: Vec<i64>,
    pub y: Vec<i64>,
    pub count: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Scrolls {
    pub t: Vec<i64>,
    pub x: Vec<i64>,
    pub y: Vec<i64>,
    pub dx: Vec<i64>,
    pub dy: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Dirty {
    pub t: Vec<i64>,
    pub x: Vec<i64>,
    pub y: Vec<i64>,
    pub w: Vec<i64>,
    pub h: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Shortcuts {
    pub t: Vec<i64>,
    pub keys: Vec<String>,
    pub code: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Typed {
    pub t: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Keys {
    pub shortcut: Shortcuts,
    pub typed: Typed,
}

/// One cursor file, parsed and checked: every top-level key of the body.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CursorFile {
    pub format: String,
    pub version: u32,
    pub in_picture: bool,
    pub source: SourceKind,
    #[serde(default)]
    pub display_id: Option<u32>,
    pub source_frame: [i64; 4],
    pub point_size: [i64; 2],
    pub pixels_per_point: f64,
    pub content_size: [i64; 2],
    pub movie_size: [i64; 2],
    pub anchor: Anchor,
    pub anchor_host_us: i64,
    pub cursor_image: CursorImageMode,
    pub moves: Moves,
    pub images: Vec<CursorImage>,
    pub image_changes: ImageChanges,
    pub hidden: Hidden,
    pub clicks: Clicks,
    pub scrolls: Scrolls,
    pub geometry: Vec<Geometry>,
    pub dirty: Dirty,
    pub keys: Keys,
}

impl CursorFile {
    /// Reads and checks a body in the module doc's order; the first
    /// refusal's sentence otherwise.
    pub fn parse(bytes: &[u8]) -> Result<CursorFile, String> {
        let value: Value = serde_json::from_slice(bytes)
            .map_err(|e| format!("the cursor file is not JSON: {e}"))?;
        let object = value
            .as_object()
            .ok_or_else(|| "the cursor file is not a JSON object".to_string())?;
        if object.get("format").and_then(Value::as_str) != Some(CURSOR_FORMAT) {
            return Err(format!(
                "this is not a Frame Job cursor file: its \"format\" is not \"{CURSOR_FORMAT}\""
            ));
        }
        let version = object.get("version").filter(|v| v.is_i64() || v.is_u64());
        let Some(version) = version else {
            return Err("the cursor file's \"version\" is not an integer".to_string());
        };
        if version.as_i64().is_some_and(|v| v < 1) {
            return Err(format!(
                "the cursor file is version {version}; versions start at 1"
            ));
        }
        if version
            .as_u64()
            .is_none_or(|v| v > u64::from(RC_CURSOR_FILE_VERSION))
        {
            return Err(format!(
                "the cursor file is version {version}; this Frame Job reads cursor files up to \
                 version {RC_CURSOR_FILE_VERSION}"
            ));
        }
        check_typed(&value)?;
        let mut file: CursorFile = serde_path_to_error::deserialize(value).map_err(|e| {
            let path = e.path().to_string();
            if path == "." {
                format!("the cursor file at its top level: {}", e.inner())
            } else {
                format!("the cursor file at \"{path}\": {}", e.inner())
            }
        })?;
        for (i, image) in file.images.iter_mut().enumerate() {
            let text = std::mem::take(&mut image.png_base64);
            image.png =
                decode_base64(&text).map_err(|e| format!("images[{i}].png is not base64: {e}"))?;
        }
        check(&file)?;
        Ok(file)
    }
}
