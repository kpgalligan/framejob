//! `framejob_core` — the decision-making half of Frame Job.
//!
//! Rust decides, AVFoundation and Metal do (spec §7): this crate holds the
//! project value, every edit, and the plans and recipes the app renders
//! from. It touches no pixel and no audio sample.
//!
//! The one contract with the app is `core/include/framejob_core.h`; the
//! `ffi*` modules implement it and are the only place `extern "C"` appears.
//! Everything complex crosses as UTF-8 JSON, which keeps the header small
//! and gives the embedded MCP agent the same vocabulary for free.
//!
//! Declarations and re-exports only — no implementation lives here.

pub mod actions;
mod actions_clamp;
mod actions_color;
mod actions_curves;
mod actions_graphic;
mod actions_qualifier;
pub mod agent;
pub mod audio;
pub mod audio_crossfade;
pub mod audio_duck;
pub mod av1_mp4;
pub mod container;
mod container_blocks;
mod container_codec;
mod container_header;
mod container_timing;
mod container_vorbis;
mod container_vorbis_setup;
pub mod cube;
pub mod dynamic_range;
pub mod edit;
pub mod edit_action;
mod edit_action_graphic;
pub mod edit_action_ramp;
mod edit_action_speed;
mod edit_adjustment;
pub mod edit_background;
pub mod edit_canvas;
pub mod edit_clip;
mod edit_clip_timing;
mod edit_commit;
mod edit_detach;
pub mod edit_edge;
pub mod edit_graphic;
pub mod edit_insert;
pub mod edit_nest;
pub mod edit_paste;
pub mod edit_paste_attributes;
pub mod edit_props;
pub mod edit_relink;
pub mod edit_split;
pub mod edit_time;
pub mod edit_track;
pub mod edit_transition;
pub mod edit_transition_shift;
pub mod edit_zoom;
pub mod evaluate;
pub mod export;
mod export_container;
pub mod export_overrides;
pub mod export_size;
pub mod export_table;
pub mod ffi;
pub mod ffi_agent;
pub mod ffi_av1;
pub mod ffi_container;
pub mod ffi_cube;
pub mod ffi_edit;
pub mod ffi_graphic;
pub mod ffi_graphic_pending;
pub mod ffi_hdr10;
pub mod ffi_query;
pub mod format;
pub mod frame_grid;
mod grade_check;
pub mod hdr10;
pub mod hdr10_still;
mod lut;
pub mod mcp_versions;
mod media_color;
pub mod model;
pub mod model_canvas;
mod model_color;
pub mod model_grade;
pub mod model_graphic;
pub mod model_look;
pub mod model_matte;
pub mod model_media_color;
pub mod model_motion;
pub mod model_props;
pub mod model_query;
pub mod model_regions;
pub mod model_shape;
pub mod model_text;
pub mod model_words;
pub mod motion;
pub mod nest;
pub mod op_schema;
pub mod op_table;
pub mod outcome;
pub mod patch;
pub mod plan;
pub mod props_check;
pub mod recipe;
mod recipe_dissolve;
mod recipe_graphic;
mod recipe_layer;
mod recipe_matte;
mod recipe_options;
mod recipe_selection;
pub mod recipe_text;
pub mod recipe_words;
pub mod scope;
pub mod snap;
pub mod source_window;
mod speed_map;
mod speed_segments;
pub mod time;
mod time_bounds;
pub mod transition;
mod transition_search;

mod ffi_util;

pub use crate::actions::Evaluated;
pub use crate::audio::Ramp;
pub use crate::edit::{Op, OP_NAMES};
pub use crate::format::{
    MAX_CLIPS, MAX_MARKERS, MAX_MEDIA, MAX_NEST_DEPTH, MAX_TRACKS, RC_FORMAT_VERSION,
};
pub use crate::model::{
    Action, AudioProps, Backdrop, BlendMode, Canvas, Chroma, Clip, Color, ColorAdjust, Compressor,
    Crop, Curve, Duck, Enabled, Filter, FilterKind, Gradient, GradientKind, GradientStop,
    GraphicProps, Marker, Media, MediaKind, Nest, ObscureKind, ObscureRegion, Outline, Project,
    Reflection, Shadow, ShapeKind, ShapeProps, Source, SpotShape, Spotlight, Stroke, TextAlign,
    TextAnimation, TextAnimationKind, TextProps, TextVAlign, Track, Transition, TransitionKind,
    VideoProps, MAX_FILTERS, MAX_GRADIENT_STOPS, MAX_OBSCURE,
};
pub use crate::outcome::Outcome;
pub use crate::time::{Fps, Ticks, TIMESCALE};
pub use crate::transition::Overlap;
