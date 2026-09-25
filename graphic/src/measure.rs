//! `measureText` (road map 10 §5c): lay one `<text>` out with the shared
//! options and read the text node's own box and its glyphs' ink box.

use std::sync::Mutex;

use resvg::usvg;

use crate::diagnostic::Diagnostic;
use crate::library::{Library, MemoKey, Probe};
use crate::raster::escape_xml;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FontStyle {
    Normal,
    Italic,
    Oblique,
}

impl FontStyle {
    fn as_css(self) -> &'static str {
        match self {
            FontStyle::Normal => "normal",
            FontStyle::Italic => "italic",
            FontStyle::Oblique => "oblique",
        }
    }
}

/// The font a text is measured in.
#[derive(Debug, Clone, PartialEq)]
pub struct TextFont {
    pub family: String,
    pub size: f64,
    pub weight: u16,
    pub style: FontStyle,
    pub letter_spacing: f64,
}

/// A text's advance, its box about the baseline, and its ink.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TextMetrics {
    pub width: f64,
    pub ascent: f64,
    pub descent: f64,
    pub line_height: f64,
    pub ink_x: f64,
    pub ink_width: f64,
}

impl TextMetrics {
    const ZERO: TextMetrics = TextMetrics {
        width: 0.0,
        ascent: 0.0,
        descent: 0.0,
        line_height: 0.0,
        ink_x: 0.0,
        ink_width: 0.0,
    };

    /// Keys `width, ascent, descent, lineHeight, inkX, inkWidth`, in order.
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "width": self.width,
            "ascent": self.ascent,
            "descent": self.descent,
            "lineHeight": self.line_height,
            "inkX": self.ink_x,
            "inkWidth": self.ink_width,
        })
    }
}

/// Measures `text` in `font`, memoised in the library. Whitespace-only text
/// measures zero; a family with no face in the set is an error naming it.
pub fn measure_text(
    library: &Library,
    text: &str,
    font: &TextFont,
) -> Result<TextMetrics, Diagnostic> {
    if !font.size.is_finite() || font.size <= 0.0 {
        return Err(Diagnostic::error(format!(
            "measureText: size {} must be finite and > 0",
            font.size
        )));
    }
    if font.weight == 0 || font.weight > 1000 {
        return Err(Diagnostic::error(format!(
            "measureText: weight {} must be 1–1000",
            font.weight
        )));
    }
    if !font.letter_spacing.is_finite() {
        return Err(Diagnostic::error(
            "measureText: letterSpacing must be finite",
        ));
    }
    if text.trim().is_empty() {
        return Ok(TextMetrics::ZERO);
    }
    let key: MemoKey = (
        font.family.clone(),
        font.size.to_bits(),
        font.weight,
        font.style,
        font.letter_spacing.to_bits(),
        text.to_string(),
    );
    if let Some(metrics) = library.memo_get(&key) {
        return Ok(metrics);
    }
    let metrics = measure_uncached(library, text, font)?;
    library.memo_put(key, metrics);
    Ok(metrics)
}

fn measure_uncached(
    library: &Library,
    text: &str,
    font: &TextFont,
) -> Result<TextMetrics, Diagnostic> {
    let size = font.size;
    let baseline = size * 2.0;
    let svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w}\" height=\"{h}\">\
         <text x=\"0\" y=\"{baseline}\" font-family=\"{family}\" font-size=\"{size}\" \
         font-weight=\"{weight}\" font-style=\"{style}\" letter-spacing=\"{spacing}\">{t}</text></svg>",
        w = (size * 64.0).ceil(),
        h = (size * 4.0).ceil(),
        family = escape_xml(&format!("'{}'", font.family.replace('\'', ""))),
        weight = font.weight,
        style = font.style.as_css(),
        spacing = font.letter_spacing,
        t = escape_xml(text),
    );
    let probe = Mutex::new(Probe::default());
    let options = library.options(&probe);
    let tree = usvg::Tree::from_str(&svg, &options)
        .map_err(|e| Diagnostic::error(format!("measureText: {e}")))?;
    let node = find_text(tree.root()).ok_or_else(|| {
        Diagnostic::error(format!(
            "measureText: no face for family \"{}\"; the set has: {}",
            font.family,
            library.families().join(", ")
        ))
    })?;
    let bbox = node.bounding_box();
    let ink = node.flattened().abs_bounding_box();
    let ascent = baseline - bbox.top() as f64;
    let descent = bbox.bottom() as f64 - baseline;
    Ok(TextMetrics {
        width: bbox.width() as f64,
        ascent,
        descent,
        line_height: ascent + descent,
        ink_x: ink.x() as f64,
        ink_width: ink.width() as f64,
    })
}

fn find_text(group: &usvg::Group) -> Option<&usvg::Text> {
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
