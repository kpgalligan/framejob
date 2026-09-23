//! Road map 8, spike W0, q4 — the CORE's candidate token rule, alone.
//!
//! W-2 says `text.words` is one timing per whitespace token of `content` and
//! that the token rule is `str::split_whitespace` "unless W0 q4 says
//! otherwise". This is that rule and nothing else: one `str::split_whitespace`
//! over a JSON corpus, each token's byte offsets converted to UTF-16 units so
//! the answer is in the SAME unit CoreText indexes in and the Swift half can be
//! compared to it row by row.
//!
//!   rustc -O tokens.rs -o tokens
//!   tokens <corpus.json> <out.json>
//!
//! The corpus is `{"rows": [{"id": "…", "text": "…"}, …]}` and the answer is
//! `{"rows": [{"id": "…", "tokens": [[start, end], …]}, …]}`, written to
//! `<out.json>` and printed as the one JSON object on stdout.
//!
//! No serde: a spike instrument with a dependency is an instrument that needs
//! a network and a lockfile to run again in a year. The two JSON shapes here
//! are fixed and small, so the reader is a scanner over the corpus's own
//! escapes and the writer is a `format!`.

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::process::exit;

/// The minimum of JSON a corpus needs: `"rows"` of objects with two string
/// fields. It reads STRING values only and never numbers, so a stray key
/// cannot be mistaken for one.
fn parse_rows(text: &str) -> Result<Vec<(String, String)>, String> {
    let bytes: Vec<char> = text.chars().collect();
    let mut index = 0usize;
    let mut rows: Vec<(String, String)> = Vec::new();
    let mut current: BTreeMap<String, String> = BTreeMap::new();
    let mut pending_key: Option<String> = None;
    let mut depth = 0usize;
    while index < bytes.len() {
        match bytes[index] {
            '{' => {
                depth += 1;
                current.clear();
                index += 1;
            }
            '}' => {
                depth -= 1;
                if let (Some(id), Some(body)) = (current.get("id"), current.get("text")) {
                    rows.push((id.clone(), body.clone()));
                }
                current.clear();
                pending_key = None;
                index += 1;
            }
            '"' => {
                let (value, next) = read_string(&bytes, index)?;
                index = next;
                // A key is the string before a colon; anything else is a value.
                let mut look = index;
                while look < bytes.len() && bytes[look].is_whitespace() {
                    look += 1;
                }
                if look < bytes.len() && bytes[look] == ':' {
                    pending_key = Some(value);
                    index = look + 1;
                } else if let Some(key) = pending_key.take() {
                    if depth > 0 {
                        current.insert(key, value);
                    }
                }
            }
            _ => index += 1,
        }
    }
    Ok(rows)
}

fn read_string(chars: &[char], start: usize) -> Result<(String, usize), String> {
    let mut out = String::new();
    let mut index = start + 1;
    while index < chars.len() {
        let c = chars[index];
        if c == '"' {
            return Ok((out, index + 1));
        }
        if c == '\\' {
            index += 1;
            if index >= chars.len() {
                return Err("a string ended inside an escape".into());
            }
            match chars[index] {
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                'b' => out.push('\u{8}'),
                'f' => out.push('\u{c}'),
                '/' => out.push('/'),
                '\\' => out.push('\\'),
                '"' => out.push('"'),
                'u' => {
                    let unit = hex(chars, index + 1)?;
                    index += 4;
                    // A surrogate PAIR is two \u escapes and one scalar.
                    if (0xD800..0xDC00).contains(&unit)
                        && index + 6 < chars.len()
                        && chars[index + 1] == '\\'
                        && chars[index + 2] == 'u'
                    {
                        let low = hex(chars, index + 3)?;
                        index += 6;
                        let scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
                        out.push(char::from_u32(scalar).ok_or("a bad surrogate pair")?);
                    } else {
                        out.push(char::from_u32(unit).ok_or("a bad \\u escape")?);
                    }
                }
                other => return Err(format!("an unknown escape \\{other}")),
            }
            index += 1;
            continue;
        }
        out.push(c);
        index += 1;
    }
    Err("a string never closed".into())
}

fn hex(chars: &[char], at: usize) -> Result<u32, String> {
    if at + 3 >= chars.len() {
        return Err("a \\u escape ran off the end".into());
    }
    let text: String = chars[at..at + 4].iter().collect();
    u32::from_str_radix(&text, 16).map_err(|_| format!("a bad \\u escape {text}"))
}

/// Every token `str::split_whitespace` finds, as UTF-16 [start, end) pairs.
///
/// `split_whitespace` hands back sub-slices of the original string, so the
/// byte offset of each is its address minus the subject's — the one way to get
/// a position out of it without re-implementing it.
fn tokens(text: &str) -> Vec<(usize, usize)> {
    let base = text.as_ptr() as usize;
    let mut out = Vec::new();
    for token in text.split_whitespace() {
        let start = token.as_ptr() as usize - base;
        let end = start + token.len();
        out.push((utf16_offset(text, start), utf16_offset(text, end)));
    }
    out
}

fn utf16_offset(text: &str, byte: usize) -> usize {
    text[..byte].chars().map(|c| c.len_utf16()).sum()
}

fn escape(text: &str) -> String {
    let mut out = String::new();
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn main() {
    let arguments: Vec<String> = env::args().collect();
    if arguments.len() < 3 {
        println!("{{\"ok\":false,\"error\":\"usage: tokens <corpus.json> <out.json>\"}}");
        exit(1);
    }
    let text = match fs::read_to_string(&arguments[1]) {
        Ok(text) => text,
        Err(error) => {
            println!("{{\"ok\":false,\"error\":\"{}\"}}", escape(&error.to_string()));
            exit(1);
        }
    };
    let rows = match parse_rows(&text) {
        Ok(rows) => rows,
        Err(error) => {
            println!("{{\"ok\":false,\"error\":\"{}\"}}", escape(&error));
            exit(1);
        }
    };
    let mut parts: Vec<String> = Vec::new();
    for (id, body) in &rows {
        let pairs: Vec<String> = tokens(body)
            .iter()
            .map(|(a, b)| format!("[{a},{b}]"))
            .collect();
        let units: usize = body.chars().map(|c| c.len_utf16()).sum();
        parts.push(format!(
            "{{\"id\":\"{}\",\"utf16_length\":{},\"characters\":{},\"tokens\":[{}]}}",
            escape(id),
            units,
            body.chars().count(),
            pairs.join(",")
        ));
    }
    let answer = format!("{{\"ok\":true,\"rows\":[{}]}}", parts.join(","));
    if let Err(error) = fs::write(&arguments[2], &answer) {
        println!("{{\"ok\":false,\"error\":\"{}\"}}", escape(&error.to_string()));
        exit(1);
    }
    println!("{answer}");
}
