//! The CSS colour a graphic's `color` prop is stored through (G-12):
//! [`normalise_color`] answers lowercase `#rrggbb`, or `#rrggbbaa` when the
//! colour is not opaque. Moved out of `model_graphic.rs` whole.
//!
//! **This file is G-12's grammar, and `graphic/src/stdlib.js`'s
//! `__parseColour` is its second implementation**: both answer
//! `graphic/tests/colours.json` (`core/tests/graphic.rs` and
//! `graphic/tests/stdlib.rs`), so a change here is a change there. The
//! grammar, in G-12's order: non-ASCII refused; ASCII whitespace trimmed and
//! the text ASCII-lowercased; `#` and 3, 4, 6 or 8 hex digits; `rgb(`,
//! `rgba(`, `hsl(` or `hsla(` with 3 or 4 parts; else a word looked up in
//! svgtypes' named-colour table — the one usvg draws `fill` with, so a name
//! the core stores is a name the engine would have drawn. A value outside
//! its range is refused, never clamped.

/// A CSS colour as `#rrggbb`, or `#rrggbbaa` when it is not opaque,
/// lowercase (G-12). Takes the four hex forms in any case, `rgb()` /
/// `rgba()` and `hsl()` / `hsla()` with three or four components separated
/// by commas, spaces or `/`, and the CSS colour names (with `transparent`).
pub(crate) fn normalise_color(text: &str) -> Option<String> {
    if !text.is_ascii() {
        return None;
    }
    let text = text
        .trim_matches(|c: char| c.is_ascii_whitespace())
        .to_ascii_lowercase();
    let channels = match text.strip_prefix('#') {
        Some(hex) => hex_channels(hex)?,
        None => function_channels(&text).or_else(|| named_channels(&text))?,
    };
    let [r, g, b, a] = channels;
    Some(if a == 255 {
        format!("#{r:02x}{g:02x}{b:02x}")
    } else {
        format!("#{r:02x}{g:02x}{b:02x}{a:02x}")
    })
}

fn hex_channels(hex: &str) -> Option<[u8; 4]> {
    if !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let digit = |i: usize| u8::from_str_radix(&hex[i..=i], 16).ok();
    let pair = |i: usize| u8::from_str_radix(&hex[i..i + 2], 16).ok();
    match hex.len() {
        3 | 4 => {
            let mut out = [255u8; 4];
            for (i, slot) in out.iter_mut().enumerate().take(hex.len()) {
                *slot = digit(i)? * 17;
            }
            Some(out)
        }
        6 | 8 => {
            let mut out = [255u8; 4];
            for (i, slot) in out.iter_mut().enumerate().take(hex.len() / 2) {
                *slot = pair(i * 2)?;
            }
            Some(out)
        }
        _ => None,
    }
}

/// `rgb(`, `rgba(`, `hsl(` or `hsla(` … `)`, the text already lowercased.
/// Either name of a pair takes 3 or 4 parts.
fn function_channels(lower: &str) -> Option<[u8; 4]> {
    let (hsl, rest) = if let Some(rest) = lower.strip_prefix("rgba(") {
        (false, rest)
    } else if let Some(rest) = lower.strip_prefix("rgb(") {
        (false, rest)
    } else if let Some(rest) = lower.strip_prefix("hsla(") {
        (true, rest)
    } else {
        (true, lower.strip_prefix("hsl(")?)
    };
    let inner = rest.strip_suffix(')')?;
    let parts: Vec<&str> = inner
        .split(|c: char| c == ',' || c == '/' || c.is_ascii_whitespace())
        .filter(|part| !part.is_empty())
        .collect();
    if !(3..=4).contains(&parts.len()) {
        return None;
    }
    let alpha = match parts.get(3) {
        Some(part) => byte(alpha_unit(part)?),
        None => 255,
    };
    let [r, g, b] = if hsl {
        hsl_channels(&parts)?
    } else {
        let mut out = [0u8; 3];
        for (slot, part) in out.iter_mut().zip(&parts) {
            let unit = match part.strip_suffix('%') {
                Some(percent) => number(percent)? / 100.0,
                None => number(part)? / 255.0,
            };
            *slot = byte(in_unit(unit)?);
        }
        out
    };
    Some([r, g, b, alpha])
}

/// An alpha: `N%` is N/100, a bare `N` is N; either inside [0, 1].
fn alpha_unit(part: &str) -> Option<f64> {
    in_unit(match part.strip_suffix('%') {
        Some(percent) => number(percent)? / 100.0,
        None => number(part)?,
    })
}

/// CSS Color 4's `hsl()` to sRGB, step for step in f64 (G-12):
/// `a = s × min(l, 1 − l)`, `k = (n + h/30) mod 12`, channel
/// `l − a × max(−1, min(k − 3, 9 − k, 1))` for n = 0, 8, 4. The standard
/// library's copy runs the same steps in the same order, so the two round
/// the same byte.
fn hsl_channels(parts: &[&str]) -> Option<[u8; 3]> {
    let hue = number(parts[0].strip_suffix("deg").unwrap_or(parts[0]))?;
    if !hue.is_finite() {
        return None;
    }
    let mut h = hue % 360.0;
    if h < 0.0 {
        h += 360.0;
    }
    let s = in_unit(number(parts[1].strip_suffix('%')?)? / 100.0)?;
    let l = in_unit(number(parts[2].strip_suffix('%')?)? / 100.0)?;
    let a = s * l.min(1.0 - l);
    let channel = |n: f64| {
        let k = (n + h / 30.0) % 12.0;
        byte(l - a * (k - 3.0).min(9.0 - k).clamp(-1.0, 1.0))
    };
    Some([channel(0.0), channel(8.0), channel(4.0)])
}

/// A word of ASCII lowercase letters looked up in svgtypes' table of the
/// CSS named colours, `transparent` included; nothing else is read by it.
fn named_channels(lower: &str) -> Option<[u8; 4]> {
    if lower.is_empty() || !lower.bytes().all(|b| b.is_ascii_lowercase()) {
        return None;
    }
    let colour: svgtypes::Color = lower.parse().ok()?;
    Some([colour.red, colour.green, colour.blue, colour.alpha])
}

/// G-12's number, `[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?`, checked before
/// `parse` so that `inf`, `nan` and `0x10` are never read as numbers.
fn number(text: &str) -> Option<f64> {
    let bytes = text.as_bytes();
    let mut i = 0;
    let digits = |i: &mut usize| {
        let from = *i;
        while *i < bytes.len() && bytes[*i].is_ascii_digit() {
            *i += 1;
        }
        *i - from
    };
    if matches!(bytes.first(), Some(b'+' | b'-')) {
        i += 1;
    }
    let whole = digits(&mut i);
    let mut fraction = 0;
    if bytes.get(i) == Some(&b'.') {
        i += 1;
        fraction = digits(&mut i);
    }
    if whole == 0 && fraction == 0 {
        return None;
    }
    if bytes.get(i) == Some(&b'e') {
        i += 1;
        if matches!(bytes.get(i), Some(b'+' | b'-')) {
            i += 1;
        }
        if digits(&mut i) == 0 {
            return None;
        }
    }
    if i != bytes.len() {
        return None;
    }
    text.parse().ok()
}

/// A unit inside [0, 1], or `None`: refused, never clamped.
fn in_unit(unit: f64) -> Option<f64> {
    (0.0..=1.0).contains(&unit).then_some(unit)
}

fn byte(unit: f64) -> u8 {
    (unit * 255.0).round() as u8
}
