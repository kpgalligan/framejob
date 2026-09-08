//! `reelcut_core` — the decision-making half of Reelcut.
//!
//! Rust decides, AVFoundation and Metal do (spec §7): this crate holds the
//! project value, every edit, and the plans and recipes the app renders
//! from. It touches no pixel and no audio sample.
//!
//! The one contract with the app is `core/include/reelcut_core.h`; the
//! `ffi*` modules implement it and are the only place `extern "C"` appears.
//! Everything complex crosses as UTF-8 JSON, which keeps the header small
//! and gives the embedded MCP agent the same vocabulary for free.
//!
//! Declarations and re-exports only — no implementation lives here.

pub mod actions;
pub mod agent;
pub mod audio;
pub mod edit;
pub mod edit_action;
pub mod edit_clip;
pub mod edit_edge;
pub mod edit_insert;
pub mod edit_nest;
pub mod edit_paste;
pub mod edit_props;
pub mod edit_time;
pub mod edit_track;
pub mod edit_zoom;
pub mod evaluate;
pub mod export;
pub mod export_size;
pub mod ffi;
pub mod ffi_agent;
pub mod ffi_edit;
pub mod ffi_query;
pub mod format;
pub mod model;
pub mod model_props;
pub mod model_query;
pub mod model_regions;
pub mod nest;
pub mod props_check;
pub mod recipe;
pub mod snap;
pub mod time;
pub mod transition;

mod ffi_util;

pub use crate::actions::Evaluated;
pub use crate::audio::Ramp;
pub use crate::edit::{Op, OP_NAMES};
pub use crate::format::{
    MAX_CLIPS, MAX_MARKERS, MAX_MEDIA, MAX_NEST_DEPTH, MAX_TRACKS, RC_FORMAT_VERSION,
};
pub use crate::model::{
    Action, AudioProps, Backdrop, Canvas, Chroma, Clip, Color, ColorAdjust, Compressor, Crop,
    Curve, Duck, Enabled, Filter, FilterKind, Marker, Media, MediaKind, Nest, ObscureKind,
    ObscureRegion, Outline, Project, Reflection, Shadow, ShapeKind, ShapeProps, Source, SpotShape,
    Spotlight, Stroke, TextAlign, TextAnimation, TextAnimationKind, TextProps, TextVAlign, Track,
    Transition, TransitionKind, VideoProps, MAX_FILTERS, MAX_OBSCURE,
};
pub use crate::time::{Fps, Ticks, TIMESCALE};
pub use crate::transition::Overlap;
