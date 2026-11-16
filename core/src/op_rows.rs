//! The op table's rows — `OP_TABLE`, every op and its arguments, and
//! `OP_NAMES`, its projection — moved out of `op_table.rs` whole (a pure
//! move), which re-exports both, so every `op_table::` path holds. An op's
//! row is added here; what a row is made of (`OpRow`, `Argument`, `Kind`,
//! `Bound` and the four builders) stays `op_table.rs`'s.

use crate::edit_canvas::{CANVAS_MAX, CANVAS_MIN};
use crate::model_graphic::{GRAPHIC_MAX_SIDE, GRAPHIC_MIN_SIDE};
use crate::op_table::Kind::*;
use crate::op_table::{op, opt, req, within, OpRow, OP_COUNT};

/// Every op and its arguments, in the order `edit.rs`'s doc table and its
/// `Op` enum use.
///
/// Laid out by hand — rustfmt's sixty-character budget for a call's
/// arguments would break all but the shortest row into four lines and cost
/// this file the 400-line cap the deepening gave it. Every line here is
/// inside the same 100 columns rustfmt keeps.
#[rustfmt::skip]
pub const OP_TABLE: [OpRow; OP_COUNT] = [
    // ---- clips ----------------------------------------------------------
    op("add_clip", &[req("track", Id), req("media", Id), req("at", Ticks)]),
    op("add_text_clip",
       &[req("track", Id), req("at", Ticks), opt("duration", Ticks), opt("text", Object)]),
    op("add_shape_clip",
       &[req("track", Id), req("at", Ticks), opt("duration", Ticks), opt("shape", Object)]),
    op("add_graphic_clip",
       &[req("track", Id), req("at", Ticks), opt("duration", Ticks), req("name", Text),
         within(opt("width", Id), GRAPHIC_MIN_SIDE, GRAPHIC_MAX_SIDE),
         within(opt("height", Id), GRAPHIC_MIN_SIDE, GRAPHIC_MAX_SIDE),
         opt("props", Object), opt("schema", Object)]),
    op("add_adjustment_clip", &[req("track", Id), req("at", Ticks), opt("duration", Ticks)]),
    op("add_background", &[opt("media", Id), opt("color", Color), opt("duration", Ticks)]),
    op("add_blurred_background", &[req("clip", Id)]),
    op("insert_clip", &[req("track", Id), req("media", Id), req("at", Ticks)]),
    op("overwrite_clip", &[req("track", Id), req("media", Id), req("at", Ticks)]),
    op("move_clip", &[req("clips", Ids), req("delta", Ticks), opt("track", Id)]),
    op("trim_start", &[req("clip", Id), req("to", Ticks), opt("alone", Boolean)]),
    op("trim_end", &[req("clip", Id), req("to", Ticks), opt("alone", Boolean)]),
    op("rate_stretch", &[req("clip", Id), req("to_end", Ticks)]),
    op("slip", &[req("clip", Id), req("delta", Ticks)]),
    op("roll", &[req("clip", Id), req("to", Ticks), opt("alone", Boolean)]),
    op("split", &[opt("clips", Ids), req("at", Ticks)]),
    op("delete", &[req("clips", Ids)]),
    op("ripple_delete", &[req("clips", Ids)]),
    op("ripple_delete_range", &[req("from", Ticks), req("to", Ticks)]),
    op("ripple_delete_ranges", &[req("ranges", Ranges)]),
    op("lift_range", &[req("from", Ticks), req("to", Ticks), opt("tracks", Ids)]),
    op("keep_range", &[req("from", Ticks), req("to", Ticks)]),
    op("insert_time", &[req("at", Ticks), req("length", Ticks)]),
    op("close_gap", &[req("track", Id), req("at", Ticks)]),
    op("retime_range",
       &[req("from", Ticks), req("to", Ticks), req("rate", Number), opt("keep_pitch", Boolean)]),
    op("set_speed",
       &[req("clip", Id), opt("rate", Number), opt("duration", Ticks), opt("keep_pitch", Boolean)]),
    op("set_reversed", &[req("clip", Id), req("reversed", Boolean)]),
    op("freeze_frame", &[req("clip", Id), req("at", Ticks), opt("duration", Ticks)]),
    op("detach_audio", &[req("clip", Id)]),
    op("attach_audio", &[req("clip", Id)]),
    op("duplicate", &[req("clips", Ids), opt("delta", Ticks), opt("track", Id)]),
    op("copy_pieces",
       &[req("clip", Id), req("track", Id), req("ranges", Ranges), opt("video", Boolean),
         opt("audio", Boolean)]),
    op("paste", &[req("at", Ticks), opt("track", Id), req("payload", Object)]),
    op("paste_attributes",
       &[req("clips", Ids), req("payload", Object), opt("groups", Groups),
         opt("skip_missing", Boolean)]),
    op("nest", &[req("clips", Ids), opt("name", Text)]),
    op("unnest", &[req("clip", Id)]),
    op("set_video", &[req("clips", Ids), req("patch", Object)]),
    op("set_audio", &[req("clips", Ids), req("patch", Object)]),
    op("set_text", &[req("clips", Ids), req("patch", Object)]),
    op("set_shape", &[req("clips", Ids), req("patch", Object)]),
    op("set_graphic", &[req("clips", Ids), req("patch", Object), opt("schema", Object)]),
    op("set_clip", &[req("clips", Ids), req("patch", Object)]),
    op("set_enabled", &[req("clip", Id), opt("video", Boolean), opt("audio", Boolean)]),
    op("set_transition", &[req("clip", Id), opt("kind", Transition)]),
    op("set_transition_duration", &[req("clip", Id), req("duration", Ticks)]),
    op("add_transition",
       &[req("clip", Id), opt("kind", Transition), req("duration", Ticks),
         opt("align", Alignment), opt("ripple", Boolean)]),
    op("set_transition_style",
       &[req("clip", Id), opt("curve", Curve), opt("audio", Boolean),
         opt("audio_shape", FadeShape)]),

    // ---- actions --------------------------------------------------------
    op("add_action", &[req("clip", Id), req("at", Ticks), opt("duration", Ticks)]),
    op("add_zoom_action",
       &[req("clip", Id), req("at", Ticks), opt("duration", Ticks), opt("region", Region),
         opt("fit", Fit), opt("curve", Curve)]),
    op("add_speed_ramp",
       &[req("clip", Id), req("shape", RampShape), req("rate", Number), opt("from", Ticks),
         opt("to", Ticks), opt("curve", Curve), opt("hold", Number)]),
    op("switch_layout",
       &[req("camera", Id), opt("screen", Id), req("layout", Layout), opt("shape", LayoutShape),
         opt("corner", Corner), req("at", Ticks), opt("duration", Ticks), opt("curve", Curve),
         opt("focus", Point), opt("nest", Boolean), opt("through", Ticks)]),
    op("reframe_clip",
       &[req("clip", Id), req("follow", Follow), opt("zoom", Number),
         opt("where_empty", WhereEmpty), opt("from_width", Id), opt("from_height", Id),
         opt("backdrop", Id), opt("replace", Boolean), opt("mics", Ids), opt("mic_faces", Ids),
         opt("subjects", Subjects)]),
    op("set_action",
       &[req("clip", Id), req("action", Id), opt("start", Ticks), opt("duration", Ticks),
         opt("curve", Curve)]),
    op("set_action_end",
       &[req("clip", Id), req("action", Id), req("patch", Object), opt("off", Texts),
         opt("schema", Object)]),
    op("remove_action", &[req("clip", Id), req("action", Id)]),

    // ---- tracks, markers, canvas, media ---------------------------------
    op("add_track", &[opt("index", Index), opt("name", Text)]),
    op("remove_track", &[req("track", Id), opt("with_clips", Boolean)]),
    op("move_track", &[req("track", Id), req("index", Index)]),
    op("set_track",
       &[req("track", Id), opt("name", Text), opt("hidden", Boolean), opt("muted", Boolean),
         opt("locked", Boolean), opt("solo", Boolean), opt("matte", Matte),
         opt("volume", Number), opt("pan", Number), opt("compressor", Object),
         opt("limiter", Object)]),
    op("remove_empty_tracks", &[]),
    op("add_marker",
       &[req("at", Ticks), opt("name", Text), opt("chapter", Boolean), opt("color", Text)]),
    op("set_marker",
       &[req("marker", Id), opt("time", Ticks), opt("name", Text), opt("chapter", Boolean),
         opt("color", Text)]),
    op("remove_marker", &[req("marker", Id)]),
    op("set_canvas",
       &[within(opt("width", Id), CANVAS_MIN, CANVAS_MAX),
         within(opt("height", Id), CANVAS_MIN, CANVAS_MAX),
         opt("fps", FrameRate), opt("background", Color),
         opt("rescale_clips", Boolean), opt("fit_new_clips", Boolean),
         opt("timecode_frames", Boolean), opt("output", Output),
         opt("blending", Blending)]),
    op("add_media", &[req("descriptor", Object)]),
    op("relink_media",
       &[req("media", Id), req("path", Text), opt("bookmark", Text), opt("probe", Object)]),
    op("remove_media", &[req("media", Id), opt("with_clips", Boolean)]),
    op("set_media_color", &[req("media", Id), req("color", Object)]),
    op("set_media_speech", &[req("media", Id), req("spans", Ranges)]),
    op("set_media_cursor", &[req("media", Id), req("cursor", Object)]),
];

/// Every op name, in table order — a projection of [`OP_TABLE`], not a
/// second list beside it.
///
/// Re-exported by `edit.rs` under the name and path it has always had, so
/// the FFI, the tests and the app all read it exactly where they did. It is
/// kept next to [`Op`] so a mistyped op can be answered with the list
/// instead of a bare parse error — models and users both mistype op names,
/// and the alternative is a serde message written in variant-speak.
///
/// [`Op`]: crate::edit::Op
pub const OP_NAMES: [&str; OP_COUNT] = names();

/// [`OP_TABLE`]'s names, read out at compile time.
const fn names() -> [&'static str; OP_COUNT] {
    let mut names = [""; OP_COUNT];
    let mut i = 0;
    while i < OP_COUNT {
        names[i] = OP_TABLE[i].name;
        i += 1;
    }
    names
}
