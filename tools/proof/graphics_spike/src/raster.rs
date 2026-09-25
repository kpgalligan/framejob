//! The font set, `measure_text` and `rasterize`: usvg parse → resvg render
//! → the RGBA→BGRA swizzle (G-7). Never `load_system_fonts` (G-6).

use std::sync::Arc;
use std::time::Instant;

use resvg::tiny_skia;
use resvg::usvg;
use resvg::usvg::fontdb;

use crate::diagnostic::Diagnostic;

/// The engine's font set, built from bytes the caller read.
#[derive(Clone)]
pub struct Library {
    pub(crate) db: Arc<fontdb::Database>,
}

impl Library {
    pub fn new(fonts: &[Vec<u8>]) -> Library {
        let mut db = fontdb::Database::new();
        for bytes in fonts {
            db.load_font_data(bytes.clone());
        }
        Library { db: Arc::new(db) }
    }

    pub fn families(&self) -> Vec<String> {
        let mut names: Vec<String> = self
            .db
            .faces()
            .filter_map(|face| face.families.first().map(|(name, _)| name.clone()))
            .collect();
        names.sort();
        names.dedup();
        names
    }

    /// Every face: `(family, post_script_name, weight, italic)`.
    pub fn faces(&self) -> Vec<(String, String, u16, bool)> {
        self.db
            .faces()
            .map(|face| {
                let family = face
                    .families
                    .first()
                    .map(|(n, _)| n.clone())
                    .unwrap_or_default();
                let italic = face.style != fontdb::Style::Normal;
                (family, face.post_script_name.clone(), face.weight.0, italic)
            })
            .collect()
    }

    pub(crate) fn options(&self) -> usvg::Options<'static> {
        usvg::Options {
            fontdb: self.db.clone(),
            ..usvg::Options::default()
        }
    }
}

pub struct TextMetrics {
    pub width: f64,
    pub x: f64,
    pub ascent: f64,
    pub descent: f64,
    pub line_height: f64,
    pub ink_width: f64,
    pub ink_x: f64,
}

/// Premultiplied BGRA8 sRGB, stride = width × 4.
pub struct Raster {
    pub bgra: Vec<u8>,
    pub parse_ms: f64,
    pub raster_ms: f64,
}

pub fn escape_xml(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// §5c's `measureText`, step 1: parse a one-`<text>` SVG and read the text
/// node's own box (`bounding_box`) and its flattened glyphs' ink box.
pub fn measure_text(
    lib: &Library,
    text: &str,
    family: &str,
    size: f64,
    weight: u16,
    style: &str,
) -> Result<TextMetrics, Diagnostic> {
    measure_with(lib, text, family, size, weight, style, false)
}

/// `measure_text` with `xml:space="preserve"` on the element when asked.
/// The family is written QUOTED: an unquoted `Source Sans 3` is not a CSS
/// family name (a token may not start with a digit) and lays out nothing.
pub fn measure_with(
    lib: &Library,
    text: &str,
    family: &str,
    size: f64,
    weight: u16,
    style: &str,
    preserve: bool,
) -> Result<TextMetrics, Diagnostic> {
    let baseline = size * 2.0;
    let space = if preserve {
        " xml:space=\"preserve\""
    } else {
        ""
    };
    let svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w}\" height=\"{h}\">\
         <text x=\"0\" y=\"{baseline}\" font-family=\"{f}\" font-size=\"{size}\" \
         font-weight=\"{weight}\" font-style=\"{style}\"{space}>{t}</text></svg>",
        w = (size * 64.0).ceil(),
        h = (size * 4.0).ceil(),
        f = escape_xml(&format!("'{}'", family.replace('\'', ""))),
        t = escape_xml(text),
    );
    let tree = usvg::Tree::from_str(&svg, &lib.options())
        .map_err(|e| Diagnostic::error(format!("measureText: {e}")))?;
    if text.trim().is_empty() && !preserve {
        return Ok(TextMetrics {
            width: 0.0,
            x: 0.0,
            ascent: 0.0,
            descent: 0.0,
            line_height: 0.0,
            ink_width: 0.0,
            ink_x: 0.0,
        });
    }
    let node = find_text(tree.root()).ok_or_else(|| {
        Diagnostic::error(format!(
            "measureText: nothing was laid out for {family:?} (families: {})",
            lib.families().join(", ")
        ))
    })?;
    let bbox = node.bounding_box();
    let ink = node.flattened().abs_bounding_box();
    let ascent = baseline - bbox.top() as f64;
    let descent = bbox.bottom() as f64 - baseline;
    Ok(TextMetrics {
        width: bbox.width() as f64,
        x: bbox.x() as f64,
        ascent,
        descent,
        line_height: ascent + descent,
        ink_width: ink.width() as f64,
        ink_x: ink.x() as f64,
    })
}

pub(crate) fn find_text(group: &usvg::Group) -> Option<&usvg::Text> {
    for node in group.children() {
        match node {
            usvg::Node::Text(text) => return Some(text),
            usvg::Node::Group(inner) => {
                if let Some(found) = find_text(inner) {
                    return Some(found);
                }
            }
            _ => {}
        }
    }
    None
}

/// Parses and draws `svg` into a `width`×`height` transparent pixmap and
/// answers premultiplied BGRA; the swizzle is counted in `raster_ms`.
pub fn rasterize(lib: &Library, svg: &str, width: u32, height: u32) -> Result<Raster, Diagnostic> {
    let options = lib.options();
    let started = Instant::now();
    let tree = usvg::Tree::from_str(svg, &options)
        .map_err(|e| Diagnostic::error(format!("the SVG did not parse: {e}")))?;
    let parse_ms = started.elapsed().as_secs_f64() * 1000.0;
    let started = Instant::now();
    let mut pixmap = tiny_skia::Pixmap::new(width, height)
        .ok_or_else(|| Diagnostic::error(format!("no pixmap of {width}×{height}")))?;
    resvg::render(
        &tree,
        tiny_skia::Transform::identity(),
        &mut pixmap.as_mut(),
    );
    let mut bgra = pixmap.take();
    for pixel in bgra.chunks_exact_mut(4) {
        pixel.swap(0, 2);
    }
    let raster_ms = started.elapsed().as_secs_f64() * 1000.0;
    Ok(Raster {
        bgra,
        parse_ms,
        raster_ms,
    })
}
