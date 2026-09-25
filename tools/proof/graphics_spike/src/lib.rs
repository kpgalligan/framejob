//! `graphics_spike` — road map 10 G0's scratch engine (designs/reelcut-roadmap-10.md
//! §3): QuickJS through `rquickjs`, SVG through `resvg`, the six §5k
//! graphics' workload. Not product code. Re-exports only.

mod diagnostic;
mod raster;
mod rows;
mod rows_stress;
mod rows_text;
mod runtime;

pub use crate::diagnostic::Diagnostic;
pub use crate::raster::{
    escape_xml, measure_text, measure_with, rasterize, Library, Raster, TextMetrics,
};
pub use crate::rows::{q2, q3, q8, render_frame, summary, Timed, SECTION_5C};
pub use crate::rows_stress::{mutant, q5, q6, CASES};
pub use crate::rows_text::q4;
pub use crate::runtime::{default_props, Ctx, Engine, Limits, ModuleInfo, SPIKE_LIMITS};
