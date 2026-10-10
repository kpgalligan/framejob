//! A `.cube` 3D LUT file read into its lattice (spec §11 GR-8): the one
//! parser, which `ffi_cube.rs` exports for the app's import probe and its
//! texture upload, so a file the import accepted is the file the compositor
//! draws.
//!
//! **What is read** (GR-8 choice 7): 3D only; `LUT_3D_SIZE` 2–65; `TITLE`;
//! `#` comment lines; blank lines; CRLF; a UTF-8 BOM; `DOMAIN_MIN 0 0 0`,
//! `DOMAIN_MAX 1 1 1` and `LUT_3D_INPUT_RANGE 0 1`, which are the defaults
//! and so change nothing; table rows of three finite numbers, any value
//! (the compositor clamps to 0–1 when it draws). Everything else is
//! REFUSED by name rather than guessed at — a 1D LUT, another size, a
//! domain that is not the default, an unknown keyword, a keyword after the
//! table, a short or long table, a token that is not a number — in a
//! lowercase sentence naming the 1-based line and what was on it, which the
//! app prefixes with the file's name.
//!
//! The table's order is the format's: **red changes fastest**, then green,
//! then blue, and [`Cube::rgb`] keeps it, so row `r + g·n + b·n²` is the
//! output for input `(r, g, b) / (n − 1)` — exactly a 3D texture's texel
//! order, which is why the app uploads it unchanged.
//!
//! Written from the format's own description; nothing of Concat (the
//! effects survey's licensing rule) is read or carried.

use crate::format::RC_CUBE_MAX_BYTES;

/// The smallest lattice read: two points an axis, the corners.
pub const CUBE_SIZE_MIN: u32 = 2;
/// The largest: 65 points an axis (274,625 rows), the size the common
/// grading tools write at most.
pub const CUBE_SIZE_MAX: u32 = 65;

/// A parsed 3D LUT: `size` points an axis, and `size³` rows of red, green
/// and blue, red fastest, as the file listed them.
#[derive(Debug, Clone, PartialEq)]
pub struct Cube {
    pub size: u32,
    pub rgb: Vec<f32>,
}

/// One keyword the parser has a rule for.
enum Keyword {
    Title,
    Size,
    DomainMin,
    DomainMax,
    InputRange,
    OneD,
    Unknown,
}

impl Keyword {
    fn of(word: &str) -> Keyword {
        match word {
            "TITLE" => Keyword::Title,
            "LUT_3D_SIZE" => Keyword::Size,
            "DOMAIN_MIN" => Keyword::DomainMin,
            "DOMAIN_MAX" => Keyword::DomainMax,
            "LUT_3D_INPUT_RANGE" => Keyword::InputRange,
            "LUT_1D_SIZE" | "LUT_1D_INPUT_RANGE" => Keyword::OneD,
            _ => Keyword::Unknown,
        }
    }
}

/// A token as a number: `Ok` only for a finite one, else the sentence that
/// names the token (`"0.5x" is not a number`, `nan is not a finite number`).
fn number(token: &str, line: usize) -> Result<f64, String> {
    match token.parse::<f64>() {
        Ok(value) if value.is_finite() => Ok(value),
        Ok(_) => Err(format!("line {line}: {token} is not a finite number")),
        Err(_) => Err(format!("line {line}: \"{token}\" is not a number")),
    }
}

/// A keyword's numbers, exactly `count` of them, each finite.
fn numbers(word: &str, rest: &[&str], count: usize, line: usize) -> Result<Vec<f64>, String> {
    if rest.len() != count {
        let noun = if count == 1 { "number" } else { "numbers" };
        return Err(format!("line {line}: {word} needs {count} {noun}"));
    }
    rest.iter().map(|token| number(token, line)).collect()
}

/// A domain line holding its default, or the sentence that names what it
/// holds instead.
fn default_domain(
    word: &str,
    rest: &[&str],
    want: &[f64],
    shown: &str,
    line: usize,
) -> Result<(), String> {
    let found = numbers(word, rest, want.len(), line)?;
    if found.iter().zip(want).all(|(a, b)| a == b) {
        Ok(())
    } else {
        Err(format!(
            "line {line}: {word} must be {shown}, not {}",
            rest.join(" ")
        ))
    }
}

/// A table value as stored: an `f64` past `f32`'s range is held at its
/// largest finite value, which draws the same once clamped to 0–1.
fn stored(value: f64) -> f32 {
    (value as f32).clamp(-f32::MAX, f32::MAX)
}

impl Cube {
    /// Reads a `.cube` file's bytes; `Err` is the rule's own sentence.
    pub fn parse(bytes: &[u8]) -> Result<Cube, String> {
        if bytes.len() > RC_CUBE_MAX_BYTES {
            return Err("the file is larger than 32 MB".to_string());
        }
        let text = match std::str::from_utf8(bytes) {
            Ok(text) if !text.contains('\0') => text,
            _ => return Err("the file is not text".to_string()),
        };
        let text = text.strip_prefix('\u{feff}').unwrap_or(text);
        let mut size: Option<u32> = None;
        let mut rgb: Vec<f32> = Vec::new();
        let mut rows: usize = 0;
        let mut wanted: usize = 0;
        for (index, raw) in text.lines().enumerate() {
            let line = index + 1;
            let trimmed = raw.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            let tokens: Vec<&str> = trimmed.split_whitespace().collect();
            let first = tokens[0];
            // A table row begins with something `f64` reads (`nan` and
            // `inf` included, refused below as not finite); a keyword with
            // a letter or an underscore. Anything else is a row whose first
            // token is not a number.
            let is_keyword = first.parse::<f64>().is_err()
                && first.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_');
            if is_keyword {
                let keyword = Keyword::of(first);
                match keyword {
                    Keyword::OneD => {
                        return Err(format!(
                            "line {line}: {first} is a 1D LUT; only 3D LUTs are read"
                        ))
                    }
                    Keyword::Unknown => {
                        return Err(format!("line {line}: unknown keyword {first}"))
                    }
                    _ => {}
                }
                if rows > 0 {
                    return Err(format!("line {line}: {first} comes after the table"));
                }
                let rest = &tokens[1..];
                match keyword {
                    Keyword::Title => {}
                    Keyword::Size => {
                        if size.is_some() {
                            return Err(format!("line {line}: a second LUT_3D_SIZE"));
                        }
                        let value = numbers(first, rest, 1, line)?[0];
                        if value.fract() != 0.0 {
                            return Err(format!(
                                "line {line}: LUT_3D_SIZE {} is not a whole number",
                                rest[0]
                            ));
                        }
                        if value < f64::from(CUBE_SIZE_MIN) || value > f64::from(CUBE_SIZE_MAX) {
                            return Err(format!(
                                "line {line}: LUT_3D_SIZE {} is outside {CUBE_SIZE_MIN}–{CUBE_SIZE_MAX}",
                                rest[0]
                            ));
                        }
                        let n = value as u32;
                        size = Some(n);
                        wanted = (n as usize).pow(3);
                        rgb.reserve_exact(wanted * 3);
                    }
                    Keyword::DomainMin => {
                        default_domain(first, rest, &[0.0, 0.0, 0.0], "0 0 0", line)?
                    }
                    Keyword::DomainMax => {
                        default_domain(first, rest, &[1.0, 1.0, 1.0], "1 1 1", line)?
                    }
                    Keyword::InputRange => default_domain(first, rest, &[0.0, 1.0], "0 1", line)?,
                    Keyword::OneD | Keyword::Unknown => {}
                }
                continue;
            }
            let values = tokens
                .iter()
                .map(|token| number(token, line))
                .collect::<Result<Vec<f64>, String>>()?;
            if values.len() != 3 {
                return Err(format!(
                    "line {line}: a table row has 3 numbers, not {}",
                    values.len()
                ));
            }
            rows += 1;
            // Only the rows the size asks for are kept; the rest are
            // counted, so a long table is named by its count.
            if size.is_some() && rows <= wanted {
                rgb.extend(values.into_iter().map(stored));
            }
        }
        let Some(size) = size else {
            return Err("no LUT_3D_SIZE line".to_string());
        };
        if rows != wanted {
            return Err(format!(
                "LUT_3D_SIZE {size} needs {wanted} table rows, not {rows}"
            ));
        }
        Ok(Cube { size, rgb })
    }

    /// Points an axis.
    pub fn size(&self) -> u32 {
        self.size
    }

    /// Copies the table into `out`, red fastest; false (and `out` untouched)
    /// unless `out` holds exactly `size³ · 3` floats.
    pub fn copy_rgb(&self, out: &mut [f32]) -> bool {
        if out.len() != self.rgb.len() {
            return false;
        }
        out.copy_from_slice(&self.rgb);
        true
    }
}
