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
//! enum and the sixty-four-way dispatch are the implementation of that
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
//! A refused range that is not whole numbers (`set_track`'s `volume`
//! 0–4 and `pan` −1–1) is stated in the tool's prose until [`Bound`]
//! widens.
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
//! the nineteen named types map like this:
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
//!   [`Kind::Fit`], [`Kind::Matte`], [`Kind::Output`], [`Kind::Blending`],
//!   [`Kind::RampShape`] and [`Kind::FadeShape`] — `TransitionKind`,
//!   `TransitionAlign`, `Curve`, `ZoomFit`, `TrackMatte`, `CanvasOutput`,
//!   `CanvasBlending`, `RampShape`, `FadeShape`: closed
//!   vocabularies, each carrying its members in [`Kind::values`] rather
//!   than flattened to a string, because an agent
//!   picking a legal value out of a schema is a reason this table exists.
//!   [`Kind::Groups`] is `Vec<PasteGroup>`, the one vocabulary arriving
//!   as a list.
//! - [`Kind::Layout`], [`Kind::LayoutShape`] and [`Kind::Corner`] —
//!   `CameraLayout`, `LayoutShape`, `LayoutCorner`: `switch_layout`'s three
//!   closed vocabularies (spec §11 CO-60), members in [`Kind::values`].
//!   [`Kind::Point`] is `[f64; 2]`, its `focus`: two numbers, whose LENGTH
//!   serde refuses like a colour's and whose members it names as `f64`
//!   where a frame rate's are `u32`.
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

use Kind::*;

/// The rows themselves and their names live in `op_rows.rs`, a file of its
/// own so this one stays clear of the cap; every `op_table::` path holds.
pub use crate::op_rows::{OP_NAMES, OP_TABLE};

/// How many ops there are. `edit.rs`'s enum, its dispatch and this table
/// all have exactly this many arms.
pub const OP_COUNT: usize = 68;

/// One op's row: its name, and its arguments in the order the enum declares
/// them — which is the order the decoder lists them back in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpRow {
    pub name: &'static str,
    pub arguments: &'static [Argument],
}

/// One named value an op takes. `required` is the absence of a serde
/// default on the enum's field. Optional means omission is accepted; it does
/// not imply that `null` is accepted. The eight defaulted plain booleans
/// (`add_transition.ripple`, `paste_attributes.skip_missing`, both
/// `with_clips` fields, `set_canvas.rescale_clips`, and the `alone` of
/// `trim_start`, `trim_end` and `roll`) default to false when absent and
/// reject null.
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
    Output,
    Blending,
    RampShape,
    FadeShape,
    Layout,
    LayoutShape,
    Corner,
    Point,
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
            Output => &["sdr", "hlg"],
            Blending => &["encoded", "linear"],
            RampShape => &["ramp_up", "ramp_down", "speed_dip", "speed_burst"],
            FadeShape => &["linear", "s_curve", "plus_3db", "minus_3db"],
            Layout => &[
                "corner",
                "side_by_side",
                "stacked",
                "camera_full",
                "screen_only",
            ],
            LayoutShape => &["square", "rounded", "circle"],
            Corner => &["bottom_right", "bottom_left", "top_right", "top_left"],
            Ticks | Id | Index | Ids | Ranges | Number | Boolean | Text | Texts | Object
            | Color | FrameRate | Region | Point => &[],
        }
    }
}

/// An argument the decoder will not do without.
pub(crate) const fn req(name: &'static str, kind: Kind) -> Argument {
    Argument {
        name,
        kind,
        required: true,
        bound: None,
    }
}

/// An argument carrying a serde default — `?` in the old doc table.
pub(crate) const fn opt(name: &'static str, kind: Kind) -> Argument {
    Argument {
        name,
        kind,
        required: false,
        bound: None,
    }
}

/// [`req`] or [`opt`], bounded — the two ends handed in as the constants
/// the op's own module refuses by, never as literals.
pub(crate) const fn within(argument: Argument, min: u32, max: u32) -> Argument {
    Argument {
        bound: Some(Bound { min, max }),
        ..argument
    }
}

pub(crate) const fn op(name: &'static str, arguments: &'static [Argument]) -> OpRow {
    OpRow { name, arguments }
}
