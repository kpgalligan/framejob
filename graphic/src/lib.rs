//! `graphic` — Frame Job's motion-graphics engine (road map 10 §5a). Its
//! drawing half: the font and asset Library, `rasterize` (usvg parse →
//! resvg render → premultiplied BGRA), `measure_text`, and the Diagnostic.
//! Its JavaScript half: a `Module` compiled once, and `svg`, which runs its
//! `render` in a sandboxed QuickJS engine per (thread, module) (§5b, §5c).
//! The crate takes bytes and answers bytes: no file system, environment or
//! network, and no clock but the call deadline in `runtime.rs` (G-2, G-5).
//!
//! Declarations and re-exports only — no implementation lives here.

#![forbid(unsafe_code)]

mod diagnostic;
mod exception;
mod host;
mod library;
mod measure;
mod module;
mod props;
mod raster;
mod runtime;
mod sandbox;

pub use diagnostic::{Diagnostic, Level};
pub use library::{Face, Library};
pub use measure::{measure_text, FontStyle, TextFont, TextMetrics};
pub use module::Module;
pub use props::{overlay, MAX_OPTIONS, MAX_PROPS, MAX_STRING, TYPES};
pub use raster::{rasterize, MAX_SIDE};
pub use runtime::{engine_count, svg, ENGINES_PER_THREAD, HEAP_BYTES, STACK_BYTES, SVG_BYTES};
