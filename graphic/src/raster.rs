//! `rasterize`: usvg parse with the Library's options → resvg render → the
//! RGBA→BGRA swizzle into the caller's strided buffer (G-7), and the
//! warnings resvg never reports — a family no face answers, an href no
//! asset answers, a data: URL, an asset that is not an image, a size that
//! is not the graphic's.

use std::sync::Mutex;

use resvg::tiny_skia;
use resvg::usvg;

use crate::diagnostic::Diagnostic;
use crate::library::{lock, Library, Probe};

/// The largest width or height a graphic draws at (G-7).
pub const MAX_SIDE: u32 = 8192;

/// Parses `svg` and draws it into `out`, `width`×`height` premultiplied BGRA
/// rows `stride` bytes apart. `Ok` holds the warnings, and every pixel was
/// written (transparent where nothing drew); bytes past `width × 4` in a
/// row are untouched. `Err` writes nothing.
pub fn rasterize(
    library: &Library,
    svg: &str,
    width: u32,
    height: u32,
    out: &mut [u8],
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
            "out holds {} bytes; height × stride needs {needed}",
            out.len()
        )));
    }
    let probe = Mutex::new(Probe::default());
    let options = library.options(&probe);
    let tree = usvg::Tree::from_str(svg, &options)
        .map_err(|e| Diagnostic::error(format!("the SVG did not parse: {e}")))?;
    let mut pixmap = tiny_skia::Pixmap::new(width, height)
        .ok_or_else(|| Diagnostic::error(format!("no pixmap of {width}×{height}")))?;
    resvg::render(
        &tree,
        tiny_skia::Transform::identity(),
        &mut pixmap.as_mut(),
    );
    let rgba = pixmap.data();
    for y in 0..height as usize {
        let src = &rgba[y * row..(y + 1) * row];
        let dst = &mut out[y * stride..y * stride + row];
        for (to, from) in dst.chunks_exact_mut(4).zip(src.chunks_exact(4)) {
            to[0] = from[2];
            to[1] = from[1];
            to[2] = from[0];
            to[3] = from[3];
        }
    }
    let probe = lock(&probe);
    let mut warnings = Vec::new();
    let set = library.families().join(", ");
    let mut seen: Vec<&Vec<usvg::FontFamily>> = Vec::new();
    for families in &probe.families {
        if seen.contains(&families) {
            continue;
        }
        seen.push(families);
        if families.as_slice() == [usvg::FontFamily::Named(options.font_family.clone())] {
            for message in unparsed_family_warnings(svg, &set, &options.font_family) {
                push(&mut warnings, message);
            }
        } else {
            push(&mut warnings, family_warning(families, &set));
        }
    }
    let names = library.asset_names();
    let assets = if names.is_empty() {
        "(no assets)".to_string()
    } else {
        names.join(", ")
    };
    for href in &probe.hrefs {
        push(
            &mut warnings,
            format!("<image> href \"{href}\" is not an asset; the assets are: {assets}"),
        );
    }
    if probe.data_url {
        push(
            &mut warnings,
            "<image> data: URLs are not supported; put the file in graphics/assets/ and use asset(name)"
                .to_string(),
        );
    }
    for name in &probe.bad_assets {
        push(
            &mut warnings,
            format!("asset \"{name}\" is not a PNG, JPEG, GIF, WebP or SVG(Z) image"),
        );
    }
    let size = tree.size();
    let (svg_w, svg_h) = (size.width().round() as u32, size.height().round() as u32);
    if (svg_w, svg_h) != (width, height) {
        push(
            &mut warnings,
            format!("the SVG is {svg_w}×{svg_h} but the graphic is {width}×{height}"),
        );
    }
    Ok(warnings)
}

fn check_side(name: &str, value: u32) -> Result<(), Diagnostic> {
    if value == 0 {
        Err(Diagnostic::error(format!("{name} 0 is not allowed")))
    } else if value > MAX_SIDE {
        Err(Diagnostic::error(format!(
            "{name} {value} is over the {MAX_SIDE} cap"
        )))
    } else {
        Ok(())
    }
}

/// Appends a warning unless the same text is already there.
fn push(warnings: &mut Vec<Diagnostic>, message: String) {
    if !warnings.iter().any(|w| w.message == message) {
        warnings.push(Diagnostic::warning(message));
    }
}

fn family_warning(families: &[usvg::FontFamily], set: &str) -> String {
    let names: Vec<String> = families
        .iter()
        .map(|family| match family {
            usvg::FontFamily::Named(name) => name.clone(),
            generic => generic.to_string(),
        })
        .collect();
    if names.len() == 1 {
        format!(
            "font-family \"{}\" is not in the font set; the set has: {set}",
            names[0]
        )
    } else {
        format!(
            "font-family \"{}\" — none of these is in the font set; the set has: {set}",
            names.join(", ")
        )
    }
}

/// usvg falls back to its default family both when no `font-family` is
/// given and when the value does not parse, and a value that names the
/// default itself looks the same; this scan tells the three apart by
/// reading every value usvg could have read — attributes, `style`
/// attributes and `<style>` sheets, and in the last two the family of a
/// `font` shorthand — through usvg's own parsers.
fn unparsed_family_warnings(svg: &str, set: &str, default: &str) -> Vec<String> {
    let options = usvg::roxmltree::ParsingOptions {
        allow_dtd: true,
        ..Default::default()
    };
    let mut values: Vec<String> = Vec::new();
    if let Ok(doc) = usvg::roxmltree::Document::parse_with_options(svg, options) {
        for node in doc.descendants().filter(|n| n.is_element()) {
            if let Some(value) = node.attribute("font-family") {
                values.push(value.to_string());
            }
            if let Some(style) = node.attribute("style") {
                for declaration in simplecss::DeclarationTokenizer::from(style) {
                    family_value(declaration.name, declaration.value, &mut values);
                }
            }
            if node.tag_name().name() == "style" {
                let text: String = node.children().filter_map(|child| child.text()).collect();
                let sheet = simplecss::StyleSheet::parse(&text);
                for rule in &sheet.rules {
                    for declaration in &rule.declarations {
                        family_value(declaration.name, declaration.value, &mut values);
                    }
                }
            }
        }
    }
    let mut messages: Vec<String> = Vec::new();
    let only_default = [usvg::FontFamily::Named(default.to_string())];
    let mut names_default = false;
    for value in values {
        if let Ok(families) = svgtypes::parse_font_families(&value) {
            names_default |= families.as_slice() == only_default;
            continue;
        }
        let message = unparsed_message(value.trim(), set);
        if !messages.contains(&message) {
            messages.push(message);
        }
    }
    if messages.is_empty() && names_default {
        messages.push(family_warning(&only_default, set));
    } else if messages.is_empty() {
        messages.push(format!(
            "a <text> has no font-family (the default \"{default}\" is not in the font set); the set has: {set}"
        ));
    }
    messages
}

/// Keeps a CSS declaration's family: a `font-family` value as written, or
/// a `font` shorthand's family when svgtypes parses it (a shorthand that
/// does not parse is skipped, as usvg skips it).
fn family_value(name: &str, value: &str, values: &mut Vec<String>) {
    if name == "font-family" {
        values.push(value.to_string());
    } else if name == "font" {
        if let Ok(shorthand) = svgtypes::FontShorthand::from_str(value) {
            values.push(shorthand.font_family.trim().to_string());
        }
    }
}

/// svgtypes refuses a digit-leading word in an unquoted family name, so
/// `Source Sans 3` fails on `3`; such a value gets the quoted spelling.
fn unparsed_message(value: &str, set: &str) -> String {
    let pieces: Vec<&str> = value.split(',').map(str::trim).collect();
    let digit = |piece: &str| {
        !piece.starts_with(['\'', '"'])
            && piece
                .split_whitespace()
                .any(|word| word.starts_with(|c: char| c.is_ascii_digit()))
    };
    if pieces.iter().any(|piece| digit(piece)) {
        let quoted: Vec<String> = pieces
            .iter()
            .map(|piece| {
                if digit(piece) {
                    format!("'{piece}'")
                } else {
                    piece.to_string()
                }
            })
            .collect();
        format!(
            "font-family=\"{value}\" could not be parsed — a family name with a word that starts with a digit must be quoted: font-family=\"{}\"; the set has: {set}",
            quoted.join(", ")
        )
    } else {
        format!("font-family=\"{value}\" could not be parsed; the set has: {set}")
    }
}

/// Escapes text for an XML attribute or element body.
pub(crate) fn escape_xml(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
