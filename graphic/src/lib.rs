//! `graphic` — Reelcut's motion-graphics engine (road map 10 §5a). This is
//! its drawing half: the font and asset Library, `rasterize` (usvg parse →
//! resvg render → premultiplied BGRA), `measure_text`, and the Diagnostic.
//! The crate takes bytes and answers bytes: no file system, clock,
//! environment or network (G-2, G-5).
//!
//! Declarations and re-exports only — no implementation lives here.

#![forbid(unsafe_code)]

mod diagnostic;
mod library;
mod measure;
mod raster;

pub use diagnostic::{Diagnostic, Level};
pub use library::{Face, Library};
pub use measure::{measure_text, FontStyle, TextFont, TextMetrics};
pub use raster::{rasterize, MAX_SIDE};
