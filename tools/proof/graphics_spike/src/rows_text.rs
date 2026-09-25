//! q4 of road map 10 §3: `measureText` parity against the ink of a composed
//! render, the whitespace sub-row and the family-attribute sub-row.

use serde_json::{json, Value};

use crate::diagnostic::Diagnostic;
use crate::raster::{escape_xml, find_text, measure_with, rasterize, Library};
use crate::rows::{summary, Splitmix};

fn corpus() -> Vec<String> {
    const WORDS: &[&str] = &[
        "the",
        "Quick",
        "brown",
        "fox",
        "jumps",
        "over",
        "lazy",
        "dog",
        "Wave",
        "AVATAR",
        "kerning",
        "Typo",
        "fjord",
        "Zürich",
        "café",
        "über",
        "résumé",
        "naïve",
        "LTAV",
        "illumination",
        "WWW",
        "mm",
        "Hello",
        "world",
        "Reelcut",
    ];
    const BITS: &[&str] = &[
        "0",
        "1",
        "42",
        "2026",
        "3.14",
        "1,284,093",
        ",",
        ".",
        "!",
        "?",
        "—",
        "(",
        ")",
        "\"",
        "'",
        ":",
        ";",
        "&",
        "%",
        "é",
        "ü",
    ];
    let mut rng = Splitmix(0x5eed_0004);
    (0..200)
        .map(|_| {
            let length = 1 + rng.below(40);
            let mut s = String::new();
            while s.chars().count() < length {
                if !s.is_empty() && rng.below(3) == 0 {
                    s.push(' ');
                }
                let piece = if rng.below(3) == 0 {
                    BITS[rng.below(BITS.len())]
                } else {
                    WORDS[rng.below(WORDS.len())]
                };
                s.push_str(piece);
            }
            let cut: String = s.chars().take(length).collect();
            let trimmed = cut.trim().to_string();
            if trimmed.is_empty() {
                "x".into()
            } else {
                trimmed
            }
        })
        .collect()
}

/// The ink columns of `text` drawn inside a composed SVG: a bar above it, a
/// disc below it, the text in a translated group; columns with alpha > 0
/// in the text's band only.
fn composed_ink(
    lib: &Library,
    text: &str,
    family: &str,
    size: f64,
    weight: u16,
    advance: f64,
) -> Result<f64, Diagnostic> {
    let pad = size;
    let w = (advance + 3.0 * pad).ceil() as u32;
    let h = (size * 4.0).ceil() as u32;
    let band = (size * 0.5).ceil() as usize + 1;
    let svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w}\" height=\"{h}\">\
         <rect x=\"0\" y=\"0\" width=\"{w}\" height=\"{bar}\" fill=\"#336\"/>\
         <g transform=\"translate({pad} 0)\"><text x=\"0\" y=\"{baseline}\" font-family=\"{family}\" \
         font-size=\"{size}\" font-weight=\"{weight}\" fill=\"#fff\">{t}</text></g>\
         <circle cx=\"{c}\" cy=\"{cy}\" r=\"{r}\" fill=\"#f00\"/></svg>",
        bar = size * 0.5, baseline = size * 2.0, t = escape_xml(text),
        c = w as f64 / 2.0, cy = h as f64 - size * 0.25, r = size * 0.2,
    );
    let raster = rasterize(lib, &svg, w, h)?;
    let (w, bottom) = (w as usize, h as usize - band);
    let mut columns = (usize::MAX, 0usize);
    for y in band..bottom {
        for x in 0..w {
            if raster.bgra[(y * w + x) * 4 + 3] > 0 {
                columns = (columns.0.min(x), columns.1.max(x));
            }
        }
    }
    Ok(if columns.0 == usize::MAX {
        0.0
    } else {
        (columns.1 - columns.0 + 1) as f64
    })
}

pub fn q4(lib: &Library) -> Result<Value, Diagnostic> {
    let faces = [
        ("Montserrat", 800u16),
        ("Anton", 400),
        ("IBM Plex Mono", 400),
        ("Bebas Neue", 400),
    ];
    let strings = corpus();
    let mut per_face = Vec::new();
    let (mut all_bbox, mut all_flat) = (vec![], vec![]);
    for (family, weight) in faces {
        let (mut bbox_d, mut flat_d) = (vec![], vec![]);
        for size in [24.0, 64.0, 160.0] {
            for text in &strings {
                let m = measure_with(lib, text, family, size, weight, "normal", false)?;
                let ink = composed_ink(lib, text, family, size, weight, m.width.max(m.ink_width))?;
                bbox_d.push((m.width - ink).abs());
                flat_d.push((m.ink_width - ink).abs());
            }
        }
        let within = |d: &[f64]| d.iter().filter(|x| **x <= 1.0).count();
        per_face.push(
            json!({"family": family, "weight": weight, "n": bbox_d.len(),
            "bbox_vs_ink": summary(&bbox_d), "flat_vs_ink": summary(&flat_d),
            "bbox_within_1px": within(&bbox_d), "flat_within_1px": within(&flat_d)}),
        );
        all_bbox.extend(bbox_d);
        all_flat.extend(flat_d);
    }
    let within = |d: &[f64]| d.iter().filter(|x| **x <= 1.0).count();
    let mut whitespace = Vec::new();
    for text in ["a b", "a  b", "a b ", " a b"] {
        let plain = measure_with(lib, text, "Montserrat", 64.0, 800, "normal", false)?;
        let kept = measure_with(lib, text, "Montserrat", 64.0, 800, "normal", true)?;
        whitespace.push(
            json!({"text": text, "default_width": plain.width, "preserve_width": kept.width}),
        );
    }
    let mut variable = Vec::new();
    for family in ["Source Sans 3", "Darker Grotesque"] {
        let faces: Vec<Value> = lib
            .faces()
            .into_iter()
            .filter(|f| f.0 == family)
            .map(|f| json!({"postscript": f.1, "weight": f.2, "italic": f.3}))
            .collect();
        let mut drawn = Vec::new();
        for weight in [200u16, 400, 700, 900] {
            let m = measure_with(
                lib,
                "Hamburgefonstiv",
                family,
                64.0,
                weight,
                "normal",
                false,
            )?;
            drawn.push(json!({"weight": weight, "advance": m.width, "ink_width": m.ink_width}));
        }
        variable.push(json!({"family": family, "faces_loaded": faces, "by_weight": drawn}));
    }
    let mut families = serde_json::Map::new();
    for attr in [
        "Source Sans 3",
        "'Source Sans 3'",
        "Darker Grotesque",
        "Nope",
        "Nope, Montserrat",
    ] {
        families.insert(attr.to_string(), json!(lays_out(lib, attr)));
    }
    Ok(json!({"strings": strings.len(), "per_face": per_face,
        "all": {"n": all_bbox.len(), "bbox_vs_ink": summary(&all_bbox), "flat_vs_ink": summary(&all_flat),
                "bbox_within_1px": within(&all_bbox), "flat_within_1px": within(&all_flat)},
        "whitespace": whitespace, "variable_fonts": variable, "family_attribute_lays_out": families}))
}

/// Whether `<text font-family="{attr}">` lays out any text node at all.
fn lays_out(lib: &Library, attr: &str) -> bool {
    let svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"400\" height=\"100\">\
        <text x=\"0\" y=\"60\" font-family=\"{}\" font-size=\"40\">Hamburg</text></svg>",
        escape_xml(attr)
    );
    resvg::usvg::Tree::from_str(&svg, &lib.options())
        .map(|t| find_text(t.root()).is_some())
        .unwrap_or(false)
}
