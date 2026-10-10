//! The op table — every op's ARGUMENTS, as data (spec §6).
//!
//! `edit.rs` owns what an op MEANS; this module owns what an op TAKES. One
//! [`OpRow`] per op, in table order, and one [`Argument`] per argument: its
//! name, its [`Kind`] and whether the decoder requires it. Nothing else is
//! in a row — no prose, no semantics, and no default spelled a second time,
//! because a default is what an absent argument MEANS and meaning is
//! `edit.rs`'s doc table.
//!
//! It is a module of its own because the table is a published interface —
//! the tool catalog will read it rather than restate it — while the [`Op`]
//! enum and the sixty-way dispatch are the implementation of that
//! interface. [`OP_NAMES`] is a projection of this table and is re-exported
//! from `edit.rs` under its old name, so no caller anywhere moved.
//!
//! **Nothing here is the authority.** The `Op` enum's fields are, and
//! `core/tests/op_table.rs` proves every row against them by asking the
//! decoder: an argument the op does not have makes serde answer with the
//! arguments it does have, an omitted required one makes it answer that the
//! field is missing, and a value of the wrong kind makes it answer with the
//! kind it wanted. A row that lies fails that test.
//!
//! ### The bound
//!
//! An argument may carry a [`Bound`], and the rule for one is narrow: **a
//! bound the core REFUSES outside is published; a bound it CLAMPS to is
//! not.** A published range is a promise a caller can build a call from,
//! and a range that quietly corrects what it is handed would make that
//! promise false in the one direction a caller could not see. So
//! `set_canvas`'s two dimensions carry one — `edit_canvas.rs` refuses
//! outside 16–16384 by name — and `set_speed`'s `rate`, which refuses a
//! non-positive rate and then clamps to `SPEED_MIN`–`SPEED_MAX`, carries
//! none: the clamp is the app's to say, in the tool prose that already says
//! it.
//!
//! A bound is SOURCED from the constant that enforces it and never retyped
//! here, which is what `core/tests/op_table.rs` checks by putting each end
//! to the core and reading the refusal — including the numbers in it.
//!
//! ### The kinds
//!
//! The vocabulary is closed and spelled the way `edit.rs`'s argument column
//! spelled it. **There is exactly one kind per answer the decoder can
//! give**, which is the rule that says how many there are: two kinds serde
//! refuses identically would be a distinction the table claims and no test
//! could prove. So [`Kind::Ticks`], [`Kind::Number`], [`Kind::Boolean`],
//! [`Kind::Text`], [`Kind::Texts`], [`Kind::Ids`] and [`Kind::Ranges`] are
//! `Ticks`, `f64`, `bool`, `String`, `Vec<String>` (`set_action_end`'s
//! `off` paths), `Vec<u32>` and the silence cut's `Vec<[Ticks; 2]>`, and
//! the twelve named types map like this:
//!
//! - [`Kind::Id`] — `u32`: an id naming a clip, track, action, marker or
//!   media, and the canvas's two pixel dimensions, which are the same whole
//!   non-negative number to a decoder and to a schema. [`Kind::Index`] is
//!   `usize`, a place in the track stack, and is its own kind only because
//!   serde names a different type in its refusal.
//! - [`Kind::Color`] — `Color`, four numbers; [`Kind::FrameRate`] — `Fps`,
//!   two. Named rather than "a list of numbers" because their LENGTH is
//!   part of what serde refuses.
//! - [`Kind::Transition`], [`Kind::Alignment`], [`Kind::Curve`],
//!   [`Kind::Fit`] and [`Kind::Matte`] — `TransitionKind`,
//!   `TransitionAlign`, `Curve`, `ZoomFit`, `TrackMatte`: closed
//!   vocabularies, each carrying its members in [`Kind::values`] rather
//!   than flattened to a string, because an agent
//!   picking a legal value out of a schema is a reason this table exists.
//!   [`Kind::Groups`] is `Vec<PasteGroup>`, the one vocabulary arriving
//!   as a list.
//! - [`Kind::Region`] — `ZoomRegion`, `add_zoom_action`'s four numbers. NOT
//!   an opaque object: it is a caller-authored object whose members the
//!   core declares and refuses by name (`edit_zoom.rs`), so a later schema
//!   can print them.
//! - [`Kind::Object`] — `serde_json::Value`: a caller-authored **patch**,
//!   whatever the op calls it. The decoder takes ANY json here on purpose;
//!   deepening D1 made the core the one validator of what a patch may
//!   carry, and this table does not restate a word of it.
//!
//! [`Op`]: crate::edit::Op

use crate::edit_canvas::{CANVAS_MAX, CANVAS_MIN};
use crate::model_graphic::{GRAPHIC_MAX_SIDE, GRAPHIC_MIN_SIDE};
use Kind::*;

/// How many ops there are. `edit.rs`'s enum, its dispatch and this table
/// all have exactly this many arms.
pub const OP_COUNT: usize = 60;

/// One op's row: its name, and its arguments in the order the enum declares
/// them — which is the order the decoder lists them back in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpRow {
    pub name: &'static str,
    pub arguments: &'static [Argument],
}

/// One named value an op takes. `required` is the absence of a serde
/// default on the enum's field. Optional means omission is accepted; it does
/// not imply that `null` is accepted. The five defaulted plain booleans
/// (`add_transition.ripple`, `paste_attributes.skip_missing`, both
/// `with_clips` fields, and `set_canvas.rescale_clips`) default to false
/// when absent and reject null.
/// Other optional fields are `Option<T>` and decode absence and null alike.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Argument {
    pub name: &'static str,
    pub kind: Kind,
    pub required: bool,
    /// The range the core refuses outside, for the few arguments that have
    /// one (the module doc's rule). `None` is the ordinary case, and it
    /// means the kind is the whole of what is known — never "unbounded in
    /// fact".
    pub bound: Option<Bound>,
}

/// The two ends of a range an op refuses outside, as the op's own module
/// spells them.
///
/// Whole numbers because the one rule that qualifies today is a canvas
/// dimension, whose two constants are `u32`, and a bound is taken from the
/// constant that enforces it. An argument whose bound is not a whole number
/// is a widening of this type, made deliberately and proved the same way,
/// rather than a cast written at a call site.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Bound {
    pub min: u32,
    pub max: u32,
}

/// What an argument's value IS — never what it is for (spec §7.9: the core
/// says what an argument is, the app says what it is for).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Ticks,
    Id,
    Index,
    Ids,
    Ranges,
    Number,
    Boolean,
    Text,
    Texts,
    Object,
    Color,
    FrameRate,
    Transition,
    Alignment,
    Curve,
    Fit,
    Region,
    Groups,
    Matte,
}

impl Kind {
    /// The members of a closed vocabulary, in the order its Rust enum
    /// declares them; empty for every kind that is not one.
    ///
    /// Hand-written here and proved against the decoder, which answers an
    /// unknown member with the whole list. The match is EXHAUSTIVE for
    /// `scope.rs`'s `refused_inside` reason: a kind added without a line
    /// here would answer "no members", and the test that compares a
    /// vocabulary to its own list skips a kind that claims none — so the
    /// catch-all this does not have would be a new kind silently untested.
    pub const fn values(self) -> &'static [&'static str] {
        match self {
            Transition => &[
                "cross_dissolve",
                "fade_black",
                "fade_white",
                "push_left",
                "push_right",
                "push_up",
                "push_down",
                "wipe",
                "slide",
                "zoom",
                "wipe_left",
                "wipe_up",
                "wipe_down",
            ],
            Alignment => &["center", "before", "after"],
            Curve => &["linear", "ease_in", "ease_out", "ease_in_out"],
            Fit => &["fit", "fill"],
            Groups => &["video", "audio", "text", "shape", "graphic"],
            Matte => &["none", "alpha", "alpha_inverted", "luma", "luma_inverted"],
            Ticks | Id | Index | Ids | Ranges | Number | Boolean | Text | Texts | Object
            | Color | FrameRate | Region => &[],
        }
    }
}

/// An argument the decoder will not do without.
const fn req(name: &'static str, kind: Kind) -> Argument {
    Argument {
        name,
        kind,
        required: true,
        bound: None,
    }
}

/// An argument carrying a serde default — `?` in the old doc table.
const fn opt(name: &'static str, kind: Kind) -> Argument {
    Argument {
        name,
        kind,
        required: false,
        bound: None,
    }
}

/// [`req`] or [`opt`], bounded — the two ends handed in as the constants
/// the op's own module refuses by, never as literals.
const fn within(argument: Argument, min: u32, max: u32) -> Argument {
    Argument {
        bound: Some(Bound { min, max }),
        ..argument
    }
}

const fn op(name: &'static str, arguments: &'static [Argument]) -> OpRow {
    OpRow { name, arguments }
}

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
    op("trim_start", &[req("clip", Id), req("to", Ticks)]),
    op("trim_end", &[req("clip", Id), req("to", Ticks)]),
    op("rate_stretch", &[req("clip", Id), req("to_end", Ticks)]),
    op("slip", &[req("clip", Id), req("delta", Ticks)]),
    op("roll", &[req("clip", Id), req("to", Ticks)]),
    op("split", &[opt("clips", Ids), req("at", Ticks)]),
    op("delete", &[req("clips", Ids)]),
    op("ripple_delete", &[req("clips", Ids)]),
    op("ripple_delete_range", &[req("from", Ticks), req("to", Ticks)]),
    op("ripple_delete_ranges", &[req("ranges", Ranges)]),
    op("lift_range", &[req("from", Ticks), req("to", Ticks)]),
    op("insert_time", &[req("at", Ticks), req("length", Ticks)]),
    op("close_gap", &[req("track", Id), req("at", Ticks)]),
    op("set_speed",
       &[req("clip", Id), opt("rate", Number), opt("duration", Ticks), opt("keep_pitch", Boolean)]),
    op("set_reversed", &[req("clip", Id), req("reversed", Boolean)]),
    op("freeze_frame", &[req("clip", Id), req("at", Ticks), opt("duration", Ticks)]),
    op("detach_audio", &[req("clip", Id)]),
    op("duplicate", &[req("clips", Ids)]),
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
    op("set_transition_style", &[req("clip", Id), opt("curve", Curve), opt("audio", Boolean)]),

    // ---- actions --------------------------------------------------------
    op("add_action", &[req("clip", Id), req("at", Ticks), opt("duration", Ticks)]),
    op("add_zoom_action",
       &[req("clip", Id), req("at", Ticks), opt("duration", Ticks), opt("region", Region),
         opt("fit", Fit), opt("curve", Curve)]),
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
         opt("locked", Boolean), opt("solo", Boolean), opt("matte", Matte)]),
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
         opt("timecode_frames", Boolean)]),
    op("add_media", &[req("descriptor", Object)]),
    op("relink_media",
       &[req("media", Id), req("path", Text), opt("bookmark", Text), opt("probe", Object)]),
    op("remove_media", &[req("media", Id), opt("with_clips", Boolean)]),
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
