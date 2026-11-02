//! The cursor file's check (spec §11 CU-10): the rules `cursor_file.rs`'s
//! module doc specifies, each refused in its own lowercase sentence naming
//! the column and the entry. A module of its own because the doc, the types
//! and the check together pass the cap for a new file. Base64 lives here
//! too, both ways: the parse's decoder and the `image` request's encoder
//! (CU-25).
//!
//! The order and the sentences are `cursor_file.rs`'s module doc's
//! ("The check").

use serde_json::Value;

use crate::cursor_file::{
    CursorFile, CursorImageMode, MAX_CLICKS, MAX_DIRTY, MAX_GEOMETRY, MAX_HIDDEN, MAX_IMAGES,
    MAX_IMAGE_BYTES, MAX_IMAGE_CHANGES, MAX_MOVES, MAX_SCROLLS, MAX_SHORTCUTS, MAX_SIDE_PX,
    MAX_TYPED,
};

/// A PNG's first eight bytes.
const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

/// CU-7, in the loose read: a `typed` object holding any key but `t`.
/// Anything not an object is left to the strict read.
pub(crate) fn check_typed(value: &Value) -> Result<(), String> {
    let typed = value.get("keys").and_then(|keys| keys.get("typed"));
    if let Some(Value::Object(typed)) = typed {
        if let Some(key) = typed.keys().find(|key| key.as_str() != "t") {
            return Err(format!(
                "keys.typed holds a typed key's time only; \"{key}\" is refused (spec §11 CU-7)"
            ));
        }
    }
    Ok(())
}

/// Every rule of the module doc, in its order.
pub(crate) fn check(file: &CursorFile) -> Result<(), String> {
    if file.anchor_host_us < 0 {
        return Err(format!(
            "anchor_host_us is {}; a host time is never negative",
            file.anchor_host_us
        ));
    }
    positive("pixels_per_point", file.pixels_per_point)?;
    side("content_size", file.content_size)?;
    side("movie_size", file.movie_size)?;

    let (m, ic, hd) = (&file.moves, &file.image_changes, &file.hidden);
    let (c, s, d, k) = (&file.clicks, &file.scrolls, &file.dirty, &file.keys);
    let typed_t = &k.typed.t;
    columns(
        "moves",
        &[("t", m.t.len()), ("x", m.x.len()), ("y", m.y.len())],
    )?;
    columns("image_changes", &[("t", ic.t.len()), ("id", ic.id.len())])?;
    columns("hidden", &[("from", hd.from.len()), ("to", hd.to.len())])?;
    columns(
        "clicks",
        &[
            ("t", c.t.len()),
            ("button", c.button.len()),
            ("down", c.down.len()),
            ("x", c.x.len()),
            ("y", c.y.len()),
            ("count", c.count.len()),
        ],
    )?;
    columns(
        "scrolls",
        &[
            ("t", s.t.len()),
            ("x", s.x.len()),
            ("y", s.y.len()),
            ("dx", s.dx.len()),
            ("dy", s.dy.len()),
        ],
    )?;
    columns(
        "dirty",
        &[
            ("t", d.t.len()),
            ("x", d.x.len()),
            ("y", d.y.len()),
            ("w", d.w.len()),
            ("h", d.h.len()),
        ],
    )?;
    let sc = &k.shortcut;
    columns(
        "keys.shortcut",
        &[
            ("t", sc.t.len()),
            ("keys", sc.keys.len()),
            ("code", sc.code.len()),
        ],
    )?;

    cap("moves", m.t.len(), MAX_MOVES)?;
    cap("scrolls", s.t.len(), MAX_SCROLLS)?;
    cap("dirty", d.t.len(), MAX_DIRTY)?;
    cap("clicks", c.t.len(), MAX_CLICKS)?;
    cap("images", file.images.len(), MAX_IMAGES)?;
    cap("image_changes", ic.t.len(), MAX_IMAGE_CHANGES)?;
    cap("hidden", hd.from.len(), MAX_HIDDEN)?;
    cap("geometry", file.geometry.len(), MAX_GEOMETRY)?;
    cap("keys.shortcut", sc.t.len(), MAX_SHORTCUTS)?;
    cap("keys.typed", typed_t.len(), MAX_TYPED)?;

    let geometry_t: Vec<i64> = file.geometry.iter().map(|g| g.t).collect();
    times("moves.t", &m.t)?;
    times("image_changes.t", &ic.t)?;
    times("clicks.t", &c.t)?;
    times("scrolls.t", &s.t)?;
    times("geometry.t", &geometry_t)?;
    times("dirty.t", &d.t)?;
    times("keys.shortcut.t", &sc.t)?;
    times("keys.typed.t", typed_t)?;
    hidden_spans(&hd.from, &hd.to)?;

    for (i, image) in file.images.iter().enumerate() {
        if image.png.len() > MAX_IMAGE_BYTES {
            return Err(format!(
                "images[{i}].png is {} bytes; its cap is {MAX_IMAGE_BYTES}",
                image.png.len()
            ));
        }
        if !image.png.starts_with(&PNG_SIGNATURE) {
            return Err(format!(
                "images[{i}].png is not a PNG: its bytes do not begin with the PNG signature"
            ));
        }
        if !(0..=image.w).contains(&image.hot_x) || !(0..=image.h).contains(&image.hot_y) {
            return Err(format!(
                "images[{i}]'s hot spot ({}, {}) lies outside its size ({} × {})",
                image.hot_x, image.hot_y, image.w, image.h
            ));
        }
    }
    let count = file.images.len();
    for (i, &id) in ic.id.iter().enumerate() {
        if usize::try_from(id).map_or(true, |id| id >= count) {
            return Err(format!(
                "image_changes.id[{i}] is {id}; the file has {count} images"
            ));
        }
    }
    if file.cursor_image == CursorImageMode::None && (count > 0 || !ic.t.is_empty()) {
        return Err(format!(
            "cursor_image is \"none\", yet the file holds {count} images and {} image changes",
            ic.t.len()
        ));
    }

    for i in 0..c.t.len() {
        if !(0..=31).contains(&c.button[i]) {
            return Err(format!(
                "clicks.button[{i}] is {}; a button is 0…31",
                c.button[i]
            ));
        }
        if !(0..=1).contains(&c.down[i]) {
            return Err(format!("clicks.down[{i}] is {}; down is 0 or 1", c.down[i]));
        }
        if c.count[i] < 1 {
            return Err(format!(
                "clicks.count[{i}] is {}; a click count is at least 1",
                c.count[i]
            ));
        }
    }

    if file.geometry.is_empty() {
        return Err("geometry holds no entry; a cursor file has at least one".to_string());
    }
    for (i, g) in file.geometry.iter().enumerate() {
        positive(&format!("geometry[{i}].content_scale"), g.content_scale)?;
        positive(&format!("geometry[{i}].scale_factor"), g.scale_factor)?;
    }

    for (i, keys) in sc.keys.iter().enumerate() {
        shortcut(keys).map_err(|why| {
            format!("keys.shortcut.keys[{i}] \"{keys}\" is not a shortcut: {why} (spec §11 CU-7)")
        })?;
    }
    Ok(())
}

/// Standard-alphabet, padded base64 into its bytes; the reason otherwise.
/// Padding is only the last one or two characters of the last quartet.
pub(crate) fn decode_base64(text: &str) -> Result<Vec<u8>, String> {
    let bytes = text.as_bytes();
    if !bytes.len().is_multiple_of(4) {
        return Err(format!("its length {} is not a multiple of 4", bytes.len()));
    }
    let pad = bytes.iter().rev().take_while(|&&b| b == b'=').count();
    if pad > 2 {
        return Err("it ends in more than two \"=\"".to_string());
    }
    let body = &bytes[..bytes.len() - pad];
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    let mut acc = 0u32;
    let mut bits = 0u32;
    for (i, &b) in body.iter().enumerate() {
        let v = match b {
            b'A'..=b'Z' => b - b'A',
            b'a'..=b'z' => b - b'a' + 26,
            b'0'..=b'9' => b - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'=' => return Err(format!("\"=\" at {i} comes before its end")),
            _ => {
                return Err(format!(
                    "byte {b:#04x} at {i} is outside the base64 alphabet"
                ))
            }
        };
        acc = (acc << 6) | u32::from(v);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    Ok(out)
}

/// Bytes into standard-alphabet, padded base64: [`decode_base64`]'s
/// inverse, so base64 has one home (the `image` request's answer, CU-25).
pub(crate) fn encode_base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            chunk.get(1).copied().unwrap_or(0),
            chunk.get(2).copied().unwrap_or(0),
        ];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        for (i, shift) in [18u32, 12, 6, 0].into_iter().enumerate() {
            if i <= chunk.len() {
                out.push(char::from(ALPHABET[((n >> shift) & 63) as usize]));
            } else {
                out.push('=');
            }
        }
    }
    out
}

fn positive(name: &str, value: f64) -> Result<(), String> {
    if value.is_finite() && value > 0.0 {
        return Ok(());
    }
    Err(format!(
        "{name} is {value}; it must be a finite number above 0"
    ))
}

fn side(name: &str, size: [i64; 2]) -> Result<(), String> {
    if size.iter().all(|v| (1..=MAX_SIDE_PX).contains(v)) {
        return Ok(());
    }
    Err(format!(
        "{name} [{}, {}] is outside 1…{MAX_SIDE_PX}",
        size[0], size[1]
    ))
}

/// The first column's length is the one its siblings are held to.
fn columns(name: &str, lengths: &[(&str, usize)]) -> Result<(), String> {
    let (first, n) = lengths[0];
    for &(column, len) in &lengths[1..] {
        if len != n {
            return Err(format!(
                "{name}.{column} has {len} entries and {name}.{first} has {n}; a column's \
                 entries match its siblings'"
            ));
        }
    }
    Ok(())
}

fn cap(name: &str, len: usize, max: usize) -> Result<(), String> {
    if len > max {
        return Err(format!("{name} holds {len} entries; its cap is {max}"));
    }
    Ok(())
}

fn times(name: &str, t: &[i64]) -> Result<(), String> {
    for (i, &v) in t.iter().enumerate() {
        if v < 0 {
            return Err(format!("{name}[{i}] is {v}, a negative time"));
        }
        if i > 0 && v < t[i - 1] {
            return Err(format!(
                "{name}[{i}] is {v}, before {name}[{}] ({}); a column's times never go back",
                i - 1,
                t[i - 1]
            ));
        }
    }
    Ok(())
}

/// Each span non-empty, starting at or after the previous span's start and
/// its end (touching allowed), at no negative time.
fn hidden_spans(from: &[i64], to: &[i64]) -> Result<(), String> {
    for i in 0..from.len() {
        let (f, t) = (from[i], to[i]);
        if f < 0 {
            return Err(format!("hidden.from[{i}] is {f}, a negative time"));
        }
        if t <= f {
            return Err(format!("hidden span {i} is empty (from {f} to {t})"));
        }
        if i > 0 && f < from[i - 1] {
            return Err(format!(
                "hidden span {i} (from {f}) starts before hidden span {} (from {}); spans are \
                 in order",
                i - 1,
                from[i - 1]
            ));
        }
        if i > 0 && f < to[i - 1] {
            return Err(format!(
                "hidden span {i} (from {f}) overlaps hidden span {} (to {})",
                i - 1,
                to[i - 1]
            ));
        }
    }
    Ok(())
}

/// CU-7: `+`-joined tokens, none empty, none holding whitespace, `cmd` or
/// `ctrl` among them.
fn shortcut(keys: &str) -> Result<(), &'static str> {
    let tokens: Vec<&str> = keys.split('+').collect();
    if tokens.iter().any(|token| token.is_empty()) {
        return Err("a token is empty");
    }
    if tokens
        .iter()
        .any(|token| token.chars().any(char::is_whitespace))
    {
        return Err("a token holds whitespace");
    }
    if !tokens
        .iter()
        .any(|token| *token == "cmd" || *token == "ctrl")
    {
        return Err("it holds neither cmd nor ctrl");
    }
    Ok(())
}
