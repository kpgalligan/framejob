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
//!
//! **[`oklab_mix`] is G-40's blend, and `graphic/src/stdlib.js`'s
//! `interpolateColors` is its second implementation**: both answer
//! `graphic/tests/oklab.json`, so a change here is a change there; the
//! JavaScript is the reference. It is the stdlib's `__toLinear`,
//! `__toOklab`, `__fromOklab` and `__fromLinear` operation for operation,
//! so both round the same byte. It is [`oklab_mix_unit`] plus rounding:
//! the unit path, in floating point, is the one blend, and
//! `actions_color.rs` blends the model's own colours through it (G-43).
//! The fixture has three readers: `graphic/tests/stdlib.rs`,
//! `core/tests/graphic_actions.rs` (bytes) and `core/tests/action_colours.rs`
//! (the unit path, bytes/255 in and ×255 rounded out).

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
    Some(color_hex(channels))
}

/// The four bytes of a colour G-12's grammar reads, red, green, blue and
/// alpha: [`normalise_color`] first, then its hex digits, six of them
/// giving an alpha of 255. `actions_graphic.rs`'s blend reads a colour
/// through this, so it reads every spelling a stored colour can have.
pub(crate) fn color_channels(text: &str) -> Option<[u8; 4]> {
    let normal = normalise_color(text)?;
    hex_channels(normal.strip_prefix('#')?)
}

/// Four bytes written as G-12 writes a colour: `#rrggbb` when the alpha is
/// 255, else `#rrggbbaa`, lowercase.
pub(crate) fn color_hex(channels: [u8; 4]) -> String {
    let [r, g, b, a] = channels;
    if a == 255 {
        format!("#{r:02x}{g:02x}{b:02x}")
    } else {
        format!("#{r:02x}{g:02x}{b:02x}{a:02x}")
    }
}

/// `from` toward `to` by `t` in OKLab, as stdlib.js's interpolateColors:
/// bytes in, bytes out (G-40). [`oklab_mix_unit`] with each byte read as
/// byte/255 and each unit rounded to the nearest byte, which is the byte
/// G-40's own rounding gave: for a unit in [0, 1], rounding it ×255 and
/// clamping the byte is clamping it and rounding it ×255.
pub(crate) fn oklab_mix(from: [u8; 4], to: [u8; 4], t: f64) -> [u8; 4] {
    let unit = |c: [u8; 4]| c.map(|v| f64::from(v) / 255.0);
    oklab_mix_unit(unit(from), unit(to), t).map(|v| (v * 255.0).round() as u8)
}

/// `from` toward `to` by `t` in OKLab, sRGB-encoded units in and out
/// (G-43): red, green and blue through [`oklab_mix_rgb`]; alpha mixed
/// straight, never premultiplied, `a0 + (a1 − a0) × t` on the two inputs
/// clamped to [0, 1], the result clamped to [0, 1].
pub(crate) fn oklab_mix_unit(from: [f64; 4], to: [f64; 4], t: f64) -> [f64; 4] {
    let [r, g, b] = oklab_mix_rgb([from[0], from[1], from[2]], [to[0], to[1], to[2]], t);
    let (a0, a1) = (from[3].clamp(0.0, 1.0), to[3].clamp(0.0, 1.0));
    [r, g, b, (a0 + (a1 - a0) * t).clamp(0.0, 1.0)]
}

/// Three sRGB-encoded units toward three more by `t` in OKLab (G-40's
/// operations in floating point, G-43): each input clamped to [0, 1], then
/// sRGB → linear → OKLab, mixed component by component, and back, each
/// result clamped to [0, 1] and never rounded.
pub(crate) fn oklab_mix_rgb(from: [f64; 3], to: [f64; 3], t: f64) -> [f64; 3] {
    let a = to_oklab(from.map(|v| v.clamp(0.0, 1.0)));
    let b = to_oklab(to.map(|v| v.clamp(0.0, 1.0)));
    let mixed: [f64; 3] = std::array::from_fn(|k| a[k] + (b[k] - a[k]) * t);
    from_oklab(mixed)
}

/// stdlib.js's `__toLinear`: one sRGB unit to linear light.
fn to_linear(v: f64) -> f64 {
    if v <= 0.04045 {
        v / 12.92
    } else {
        ((v + 0.055) / 1.055).powf(2.4)
    }
}

/// stdlib.js's `__fromLinear`: linear light to an sRGB unit, clamped to
/// [0, 1] (the stdlib rounds it ×255 then; [`oklab_mix`] does).
fn from_linear(v: f64) -> f64 {
    let s = if v <= 0.0031308 {
        12.92 * v
    } else {
        1.055 * v.powf(1.0 / 2.4) - 0.055
    };
    s.clamp(0.0, 1.0)
}

/// stdlib.js's `__toOklab`, its literals in its order; alpha is not here.
fn to_oklab(rgb: [f64; 3]) -> [f64; 3] {
    let (lr, lg, lb) = (to_linear(rgb[0]), to_linear(rgb[1]), to_linear(rgb[2]));
    let l = (0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb).cbrt();
    let m = (0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb).cbrt();
    let s = (0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb).cbrt();
    [
        0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    ]
}

/// stdlib.js's `__fromOklab`: `powf(3.0)`, as `Math.pow(_, 3)`.
fn from_oklab([lightness, a, b]: [f64; 3]) -> [f64; 3] {
    let l = (lightness + 0.3963377774 * a + 0.2158037573 * b).powf(3.0);
    let m = (lightness - 0.1055613458 * a - 0.0638541728 * b).powf(3.0);
    let s = (lightness - 0.0894841775 * a - 1.291485548 * b).powf(3.0);
    [
        from_linear(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        from_linear(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        from_linear(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
    ]
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
