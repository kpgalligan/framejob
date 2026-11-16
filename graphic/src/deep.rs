//! `rasterize_deep` (spec §11 PR-15): `rasterize`'s draw at 16 bits a
//! channel, for a frame that is delivered deeper than 8 bits. The root
//! pixmap and every layer under it are tiny-skia's deep pixmaps (the
//! vendored patch, `vendor/README.md`), so a gradient keeps its levels and
//! takes no dither. A filter's region and a luminance mask's coverage are
//! read at 8 bits inside the renderer, rounded with PR-13's offset.

use crate::diagnostic::Diagnostic;
use crate::library::Library;
use crate::raster::{check_side, draw};

/// Parses `svg` and draws it into `out`, `width`×`height` premultiplied RGBA
/// rows of 16-bit values with 65,535 as 1, `stride` VALUES apart. `Ok` holds
/// the warnings `rasterize` answers, and every pixel was written
/// (transparent where nothing drew); values past `width × 4` in a row are
/// untouched. `Err` writes nothing.
pub fn rasterize_deep(
    library: &Library,
    svg: &str,
    width: u32,
    height: u32,
    out: &mut [u16],
    stride: usize,
) -> Result<Vec<Diagnostic>, Diagnostic> {
    check_side("width", width)?;
    check_side("height", height)?;
    let row = width as usize * 4;
    if stride < row {
        return Err(Diagnostic::error(format!(
            "stride {stride} is under width × 4 = {row}"
        )));
    }
    let needed = height as u128 * stride as u128;
    if (out.len() as u128) < needed {
        return Err(Diagnostic::error(format!(
            "out holds {} values; height × stride needs {needed}",
            out.len()
        )));
    }
    let (pixmap, warnings) = draw(library, svg, width, height, true)?;
    pixmap.copy_rgba16(out, stride);
    Ok(warnings)
}
