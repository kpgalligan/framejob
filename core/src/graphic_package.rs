//! The `.fjgraphic` package (spec §11 G-46 (c)): the package spec's parse and
//! checks, the in-package name legaliser, `manifest.json`, the stored zip
//! with its CRC-32, and the file write. The app hands in the module's and
//! the files' bytes and their project-relative paths; which fonts and assets
//! belong in a package is decided before this module is reached.
//!
//! **The archive** is a stored zip (method 0), version needed 10, made-by
//! `0x031E`, flag bit 11 (UTF-8 names), DOS time 0 and date `0x0021`
//! (1980-01-01) so two writes of one package are byte-identical, no extra
//! fields and no directory entries, external attributes `0o100644 << 16`:
//! `manifest.json` first, then the files in the order given, then the central
//! directory and the end record. There is no Zip64, so an archive over
//! `u32::MAX` bytes (or of more than 65,535 entries) is refused.
//!
//! **An in-package name** `<n>` under `fonts/` or `assets/` is legal when it
//! is non-empty, at most 255 bytes, does not begin with `.`, and holds no
//! `/`, `\`, `:` or control scalar (U+0000–U+001F, U+007F–U+009F). Per
//! folder, the legal names are claimed first in the order given; then each
//! illegal one, in order, has each run of `\`, `:` or control scalars made
//! one `-` and its leading `.`s dropped (empty is `file`), and a name already
//! claimed takes `-2`, `-3`, … before its last `.` (G-23 (c)'s form), the
//! stem cut by whole scalars to stay within 255 bytes. The manifest's `name`
//! keeps the project's own name.

use std::collections::HashSet;

use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

use crate::model_graphic::check_name;

/// The longest in-package name, in UTF-8 bytes (APFS's file-name limit).
pub(crate) const MAX_NAME: usize = 255;
pub(crate) const MANIFEST: &str = "manifest.json";
/// A local header's fixed part, and a central directory entry's.
pub(crate) const LOCAL_FIXED: usize = 30;
pub(crate) const CENTRAL_FIXED: usize = 46;
pub(crate) const END_RECORD: usize = 22;
/// 1980-01-01 as a DOS date: day 1, month 1, year 0.
const DOS_DATE: u16 = 0x0021;
/// Bit 11: the names are UTF-8.
const UTF8_FLAG: u16 = 0x0800;
/// Unix (3) and spec version 3.0 (30), the high and low bytes.
const MADE_BY: u16 = 0x031E;
/// A regular file, `rw-r--r--`, in the external attributes' high half.
const EXTERNAL: u32 = 0o100644 << 16;

/// One file of the package: its in-package path, its project-folder name, its bytes.
struct Entry<'a> {
    path: String,
    name: String,
    bytes: &'a [u8],
}

/// Checks `package_json` against `data`, writes the archive at `path`
/// (created or truncated) and answers the `manifest.json` it holds. Every
/// refusal names the value; an input refusal writes nothing.
pub(crate) fn write(path: &str, package_json: &str, data: &[u8]) -> Result<String, String> {
    let archive = build(package_json, data)?;
    std::fs::write(path, &archive.1).map_err(|e| format!("cannot write {path}: {e}"))?;
    Ok(archive.0)
}

/// The manifest's text and the archive's bytes.
fn build(package_json: &str, data: &[u8]) -> Result<(String, Vec<u8>), String> {
    let spec: Value =
        serde_json::from_str(package_json).map_err(|e| format!("package_json is not JSON: {e}"))?;
    let Some(spec) = spec.as_object() else {
        return Err(format!("package_json must be an object, not {spec}"));
    };
    let module = match spec.get("module") {
        Some(Value::String(module)) => module.clone(),
        other => return Err(format!("module must be a string, not {}", shown(other))),
    };
    check_name(&module)?;
    let title = string(spec, "title")?;
    let category = string(spec, "category")?;
    let app_version = string(spec, "app_version")?;
    let description = match spec.get("description") {
        Some(Value::String(text)) => Value::String(text.clone()),
        Some(Value::Null) => Value::Null,
        other => {
            return Err(format!(
                "description must be a string or null, not {}",
                shown(other)
            ))
        }
    };
    let files = parse_files(spec, &module)?;
    let total = files
        .iter()
        .try_fold(0u64, |sum, (_, size)| sum.checked_add(*size))
        .ok_or_else(|| "the files' sizes overflow".to_string())?;
    if total != data.len() as u64 {
        return Err(format!(
            "the files' sizes sum to {total} bytes, but data holds {}",
            data.len()
        ));
    }
    let names = package_names(&files);
    let mut entries = Vec::with_capacity(files.len());
    let mut at = 0usize;
    for ((given, size), path) in files.iter().zip(names) {
        let end = at + *size as usize;
        let name = given.rsplit('/').next().unwrap_or(given).to_string();
        entries.push(Entry {
            path,
            name,
            bytes: &data[at..end],
        });
        at = end;
    }
    let listed: Vec<Value> = entries
        .iter()
        .map(|entry| {
            json!({
                "path": entry.path,
                "name": entry.name,
                "size": entry.bytes.len(),
                "sha256": hex(&Sha256::digest(entry.bytes)),
            })
        })
        .collect();
    let mut manifest = Map::new();
    manifest.insert("fjgraphic".to_string(), Value::from(1));
    manifest.insert("module".to_string(), Value::String(module));
    manifest.insert("title".to_string(), Value::String(title));
    manifest.insert("category".to_string(), Value::String(category));
    manifest.insert("description".to_string(), description);
    manifest.insert("app_version".to_string(), Value::String(app_version));
    manifest.insert("files".to_string(), Value::Array(listed));
    let mut text = serde_json::to_string_pretty(&Value::Object(manifest))
        .map_err(|e| format!("the manifest could not be written: {e}"))?;
    text.push('\n');
    let mut all = vec![(MANIFEST.to_string(), text.as_bytes())];
    all.extend(entries.iter().map(|e| (e.path.clone(), e.bytes)));
    let archive = zip(&all)?;
    Ok((text, archive))
}

/// A value as a refusal names it; a missing key is `nothing`.
fn shown(value: Option<&Value>) -> String {
    value.map_or_else(|| "nothing".to_string(), Value::to_string)
}

fn string(spec: &Map<String, Value>, key: &str) -> Result<String, String> {
    match spec.get(key) {
        Some(Value::String(text)) => Ok(text.clone()),
        other => Err(format!("{key} must be a string, not {}", shown(other))),
    }
}

/// `files` as `(path, size)` pairs: the first exactly `<module>.js`, every
/// other `fonts/<n>` or `assets/<n>`, no path twice.
fn parse_files(spec: &Map<String, Value>, module: &str) -> Result<Vec<(String, u64)>, String> {
    let Some(Value::Array(list)) = spec.get("files") else {
        return Err(format!(
            "files must be an array, not {}",
            shown(spec.get("files"))
        ));
    };
    let mut files = Vec::with_capacity(list.len());
    let mut seen = HashSet::new();
    for (index, file) in list.iter().enumerate() {
        let path = match file.get("path") {
            Some(Value::String(path)) => path.clone(),
            other => {
                return Err(format!(
                    "files[{index}].path must be a string, not {}",
                    shown(other)
                ))
            }
        };
        let Some(size) = file.get("size").and_then(Value::as_u64) else {
            return Err(format!(
                "files[{index}].size must be a whole number of bytes, not {}",
                shown(file.get("size"))
            ));
        };
        let module_file = format!("{module}.js");
        if index == 0 {
            if path != module_file {
                return Err(format!(
                    "the first file must be \"{module_file}\", not \"{path}\""
                ));
            }
        } else if !in_folder(&path) {
            return Err(format!(
                "file \"{path}\" is not fonts/<name> or assets/<name> (a name of 1 to 255 bytes with no /)"
            ));
        }
        if !seen.insert(path.clone()) {
            return Err(format!("file \"{path}\" is given twice"));
        }
        files.push((path, size));
    }
    if files.is_empty() {
        return Err(format!(
            "files must begin with \"{module}.js\", not be empty"
        ));
    }
    Ok(files)
}

/// `fonts/<n>` or `assets/<n>`, `<n>` non-empty, at most 255 bytes, no `/`.
fn in_folder(path: &str) -> bool {
    let name = path
        .strip_prefix("fonts/")
        .or_else(|| path.strip_prefix("assets/"));
    name.is_some_and(|n| !n.is_empty() && n.len() <= MAX_NAME && !n.contains('/'))
}

/// U+0000–U+001F and U+007F–U+009F.
fn is_control(c: char) -> bool {
    matches!(c as u32, 0..=0x1F | 0x7F..=0x9F)
}

/// What the legaliser replaces: `\`, `:` and the control scalars.
fn is_replaced(c: char) -> bool {
    c == '\\' || c == ':' || is_control(c)
}

pub(crate) fn is_legal(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= MAX_NAME
        && !name.starts_with('.')
        && !name.chars().any(|c| c == '/' || is_replaced(c))
}

/// Each run of replaced scalars one `-`, leading `.`s dropped, empty `file`.
fn legalise(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    let mut in_run = false;
    for c in name.chars() {
        if is_replaced(c) {
            if !in_run {
                out.push('-');
            }
            in_run = true;
        } else {
            out.push(c);
            in_run = false;
        }
    }
    let kept = out.trim_start_matches('.');
    if kept.is_empty() {
        "file".to_string()
    } else {
        kept.to_string()
    }
}

/// `name` with `-<k>` before its last `.`, the stem (then, only if it must,
/// the extension) cut by whole scalars to stay within 255 bytes.
fn suffixed(name: &str, k: usize) -> String {
    let (mut stem, mut ext) = match name.rfind('.') {
        Some(dot) if dot > 0 => (name[..dot].to_string(), name[dot..].to_string()),
        _ => (name.to_string(), String::new()),
    };
    let tag = format!("-{k}");
    while stem.len() + tag.len() + ext.len() > MAX_NAME {
        if stem.pop().is_none() && ext.pop().is_none() {
            break;
        }
    }
    format!("{stem}{tag}{ext}")
}

/// Each file's in-package path: the module's as given; per folder, the legal
/// names claimed first, then each illegal one legalised and suffixed free.
fn package_names(files: &[(String, u64)]) -> Vec<String> {
    let mut out: Vec<Option<String>> = vec![None; files.len()];
    out[0] = Some(files[0].0.clone());
    for folder in ["fonts/", "assets/"] {
        let mine: Vec<(usize, &str)> = files
            .iter()
            .enumerate()
            .skip(1)
            .filter_map(|(i, (path, _))| path.strip_prefix(folder).map(|n| (i, n)))
            .collect();
        let mut claimed: HashSet<String> = HashSet::new();
        for &(i, name) in &mine {
            if is_legal(name) {
                claimed.insert(name.to_string());
                out[i] = Some(format!("{folder}{name}"));
            }
        }
        for &(i, name) in &mine {
            if is_legal(name) {
                continue;
            }
            let base = legalise(name);
            let mut chosen = base.clone();
            let mut k = 2;
            while claimed.contains(&chosen) {
                chosen = suffixed(&base, k);
                k += 1;
            }
            claimed.insert(chosen.clone());
            out[i] = Some(format!("{folder}{chosen}"));
        }
    }
    out.into_iter().map(Option::unwrap_or_default).collect()
}

pub(crate) fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// CRC-32 (IEEE): the reflected polynomial `0xEDB88320`, init and xorout
/// `0xFFFFFFFF`, by a 256-entry table.
pub(crate) fn crc32(bytes: &[u8]) -> u32 {
    let mut table = [0u32; 256];
    for (n, slot) in table.iter_mut().enumerate() {
        let mut c = n as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 {
                0xEDB8_8320 ^ (c >> 1)
            } else {
                c >> 1
            };
        }
        *slot = c;
    }
    let mut crc = 0xFFFF_FFFFu32;
    for &b in bytes {
        crc = table[((crc ^ u32::from(b)) & 0xFF) as usize] ^ (crc >> 8);
    }
    crc ^ 0xFFFF_FFFF
}

/// The stored zip of `entries`, in order; refused past what a zip without
/// Zip64 can hold.
fn zip(entries: &[(String, &[u8])]) -> Result<Vec<u8>, String> {
    let mut size: u64 = END_RECORD as u64;
    for (name, bytes) in entries {
        size += (LOCAL_FIXED + CENTRAL_FIXED + 2 * name.len() + bytes.len()) as u64;
    }
    if size > u64::from(u32::MAX) || entries.len() > usize::from(u16::MAX) {
        return Err(format!(
            "the package would be {size} bytes in {} entries, more than a zip without Zip64 holds ({} bytes, {} entries)",
            entries.len(),
            u32::MAX,
            u16::MAX
        ));
    }
    let mut out = Vec::with_capacity(size as usize);
    let mut central = Vec::new();
    for (name, bytes) in entries {
        let offset = out.len() as u32;
        let crc = crc32(bytes);
        let len = bytes.len() as u32;
        let name_len = name.len() as u16;
        put32(&mut out, 0x0403_4b50);
        for field in [10, UTF8_FLAG, 0, 0, DOS_DATE] {
            put16(&mut out, field);
        }
        for field in [crc, len, len] {
            put32(&mut out, field);
        }
        put16(&mut out, name_len);
        put16(&mut out, 0);
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(bytes);

        put32(&mut central, 0x0201_4b50);
        for field in [MADE_BY, 10, UTF8_FLAG, 0, 0, DOS_DATE] {
            put16(&mut central, field);
        }
        for field in [crc, len, len] {
            put32(&mut central, field);
        }
        for field in [name_len, 0, 0, 0, 0] {
            put16(&mut central, field);
        }
        put32(&mut central, EXTERNAL);
        put32(&mut central, offset);
        central.extend_from_slice(name.as_bytes());
    }
    let central_at = out.len() as u32;
    let central_len = central.len() as u32;
    out.extend_from_slice(&central);
    let count = entries.len() as u16;
    put32(&mut out, 0x0605_4b50);
    for field in [0, 0, count, count] {
        put16(&mut out, field);
    }
    put32(&mut out, central_len);
    put32(&mut out, central_at);
    put16(&mut out, 0);
    Ok(out)
}

fn put16(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn put32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}
