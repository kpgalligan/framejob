//! Reading a `.fjgraphic` package (spec §11 G-47 (c)): the archive's checks,
//! the manifest's, and the two held against each other. The app hands in the
//! file's bytes and copies what this answers; nothing here touches a file.
//!
//! **The checks run in order**, as spec §11 G-47 (c) lists them, and the
//! first that fails is the answer: a lowercase sentence naming the value.
//!
//! **The answer** is the manifest re-written in G-46 (c)'s key order with
//! each file's `offset`, the byte offset of its data in the package.

use std::collections::HashSet;

use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

use crate::graphic_package::{
    crc32, hex, is_legal, CENTRAL_FIXED, END_RECORD, LOCAL_FIXED, MANIFEST,
};
use crate::model_graphic::check_name;

/// The longest project-folder name a manifest may give: G-23's 247 bytes
/// (255 less `.partial`, which the app's write adds first).
const MAX_PROJECT_NAME: usize = 247;
/// The longest archive comment, so how far back the end record may sit.
const MAX_COMMENT: usize = 65_535;
/// A 32-bit field that says "see the Zip64 record".
const ZIP64: u32 = 0xFFFF_FFFF;
const END_SIGNATURE: u32 = 0x0605_4b50;
const CENTRAL_SIGNATURE: u32 = 0x0201_4b50;
const LOCAL_SIGNATURE: u32 = 0x0403_4b50;

/// One archive entry: its name, its data, and where that data starts.
struct Entry<'a> {
    name: String,
    data: &'a [u8],
    at: usize,
}

/// One file the manifest lists.
struct Listed {
    path: String,
    name: String,
    size: u64,
    sha256: String,
}

/// Checks the package in `data` and answers its manifest with each file's
/// offset, or the first check's refusal.
pub(crate) fn read(data: &[u8]) -> Result<String, String> {
    let entries = entries(data)?;
    let Some(first) = entries.first() else {
        return Err(format!("the package holds no entries, so no {MANIFEST}"));
    };
    if first.name != MANIFEST {
        return Err(format!(
            "the first entry is \"{}\", not \"{MANIFEST}\"",
            first.name
        ));
    }
    let (mut manifest, module, files) = manifest(first.data)?;
    let rest = &entries[1..];
    let present: Vec<&str> = rest.iter().map(|e| e.name.as_str()).collect();
    let listed: Vec<&str> = files.iter().map(|f| f.path.as_str()).collect();
    if present != listed {
        return Err(format!(
            "the package's entries are {}, but the manifest lists {}",
            joined(&present),
            joined(&listed)
        ));
    }
    let mut answered = Vec::with_capacity(files.len());
    for (file, entry) in files.iter().zip(rest) {
        if entry.data.len() as u64 != file.size {
            return Err(format!(
                "{} is {} bytes, but the manifest says {}",
                file.path,
                entry.data.len(),
                file.size
            ));
        }
        let sha = hex(&Sha256::digest(entry.data));
        if sha != file.sha256 {
            return Err(format!(
                "{}'s SHA-256 is {sha}, but the manifest says {}",
                file.path, file.sha256
            ));
        }
        answered.push(json!({
            "path": file.path, "name": file.name, "size": file.size, "sha256": sha,
            "offset": entry.at,
        }));
    }
    if std::str::from_utf8(rest[0].data).is_err() {
        return Err(format!("{module}.js is not UTF-8 text"));
    }
    manifest["files"] = Value::Array(answered);
    serde_json::to_string(&manifest).map_err(|e| format!("the manifest could not be answered: {e}"))
}

/// `"a", "b"`, or `nothing`.
fn joined(names: &[&str]) -> String {
    if names.is_empty() {
        return "nothing".to_string();
    }
    let quoted: Vec<String> = names.iter().map(|n| format!("\"{n}\"")).collect();
    quoted.join(", ")
}

fn u16_at(b: &[u8], at: usize) -> u16 {
    u16::from_le_bytes([b[at], b[at + 1]])
}

fn u32_at(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}

/// The end record's offset: the last signature within the last 22 + 65,535
/// bytes whose comment ends the file.
fn end_record(data: &[u8]) -> Result<usize, String> {
    let not_zip = || "the package is not a zip: no end of central directory record".to_string();
    let last = data.len().checked_sub(END_RECORD).ok_or_else(not_zip)?;
    let first = last.saturating_sub(MAX_COMMENT);
    (first..=last)
        .rev()
        .find(|&at| {
            u32_at(data, at) == END_SIGNATURE
                && at + END_RECORD + usize::from(u16_at(data, at + 20)) == data.len()
        })
        .ok_or_else(not_zip)
}

/// Every entry, in central-directory order, each checked.
fn entries(data: &[u8]) -> Result<Vec<Entry<'_>>, String> {
    let end = end_record(data)?;
    let (disk, central_disk) = (u16_at(data, end + 4), u16_at(data, end + 6));
    let (here, total) = (u16_at(data, end + 8), u16_at(data, end + 10));
    let (central_len, central_at) = (u32_at(data, end + 12), u32_at(data, end + 16));
    if here == 0xFFFF || total == 0xFFFF || central_len == ZIP64 || central_at == ZIP64 {
        return Err(
            "the package's end record points to Zip64; a .fjgraphic is a zip without Zip64"
                .to_string(),
        );
    }
    if disk != 0 || central_disk != 0 {
        return Err(format!(
            "the package spans disks (disk {disk}, central directory on {central_disk}); a .fjgraphic is one file"
        ));
    }
    if here != total {
        return Err(format!(
            "the end record counts {here} entries on this disk but {total} in all"
        ));
    }
    let central_at = central_at as usize;
    let central_end = central_at + central_len as usize;
    if central_end > end {
        return Err(format!(
            "the central directory (bytes {central_at} to {central_end}) runs past the end record at {end}"
        ));
    }
    let mut out: Vec<Entry> = Vec::with_capacity(usize::from(total));
    let mut seen = HashSet::new();
    let mut at = central_at;
    for index in 0..usize::from(total) {
        let damaged = || format!("central directory entry {index} is damaged");
        if at + CENTRAL_FIXED > central_end || u32_at(data, at) != CENTRAL_SIGNATURE {
            return Err(damaged());
        }
        let flags = u16_at(data, at + 8);
        let method = u16_at(data, at + 10);
        let crc = u32_at(data, at + 16);
        let (compressed, size) = (u32_at(data, at + 20), u32_at(data, at + 24));
        let name_len = usize::from(u16_at(data, at + 28));
        let skipped = usize::from(u16_at(data, at + 30)) + usize::from(u16_at(data, at + 32));
        let local = u32_at(data, at + 42);
        let name_end = at + CENTRAL_FIXED + name_len;
        let next = name_end + skipped;
        if next > central_end {
            return Err(damaged());
        }
        let raw_name = &data[at + CENTRAL_FIXED..name_end];
        let name = std::str::from_utf8(raw_name)
            .map_err(|_| format!("central directory entry {index}'s name is not UTF-8"))?
            .to_string();
        if method != 0 {
            return Err(format!(
                "{name} is compressed (method {method}); a .fjgraphic holds stored entries only"
            ));
        }
        if flags & 0x0009 != 0 {
            return Err(format!("{name} is encrypted or has a data descriptor (flags {flags:#06x}); a .fjgraphic holds neither"));
        }
        if compressed == ZIP64 || size == ZIP64 || local == ZIP64 {
            return Err(format!(
                "{name} uses Zip64 (a field of 0xFFFFFFFF); a .fjgraphic is a zip without Zip64"
            ));
        }
        if compressed != size {
            return Err(format!(
                "{name} is stored but its compressed size {compressed} is not its size {size}"
            ));
        }
        if name.ends_with('/') {
            return Err(format!(
                "{name} is a folder entry; a .fjgraphic holds files only"
            ));
        }
        if !seen.insert(name.clone()) {
            return Err(format!("{name} is in the package twice"));
        }
        let local = local as usize;
        let disagrees = || {
            format!("{name}'s local header is missing or does not agree with the central directory")
        };
        if local + LOCAL_FIXED > central_at || u32_at(data, local) != LOCAL_SIGNATURE {
            return Err(disagrees());
        }
        let local_name_len = usize::from(u16_at(data, local + 26));
        let local_extra = usize::from(u16_at(data, local + 28));
        let start = local + LOCAL_FIXED + local_name_len + local_extra;
        if start > central_at
            || u16_at(data, local + 8) != method
            || u32_at(data, local + 18) != compressed
            || u32_at(data, local + 22) != size
            || &data[local + LOCAL_FIXED..local + LOCAL_FIXED + local_name_len] != raw_name
        {
            return Err(disagrees());
        }
        let stop = start + size as usize;
        if stop > central_at {
            return Err(format!(
                "{name}'s data (bytes {start} to {stop}) runs past the central directory at {central_at}"
            ));
        }
        let bytes = &data[start..stop];
        let actual = crc32(bytes);
        if actual != crc {
            return Err(format!(
                "{name}'s CRC-32 is {actual:08x}, but the archive says {crc:08x}"
            ));
        }
        out.push(Entry {
            name,
            data: bytes,
            at: start,
        });
        at = next;
    }
    Ok(out)
}

/// A value as a refusal names it; a missing key is `nothing`.
fn shown(value: Option<&Value>) -> String {
    value.map_or_else(|| "nothing".to_string(), Value::to_string)
}

fn string(object: &Map<String, Value>, key: &str, what: &str) -> Result<String, String> {
    match object.get(key) {
        Some(Value::String(text)) => Ok(text.clone()),
        other => Err(format!("{what} must be a string, not {}", shown(other))),
    }
}

/// The manifest's fields in G-46 (c)'s order (less `files`), the module's
/// name, and the files it lists.
fn manifest(bytes: &[u8]) -> Result<(Value, String, Vec<Listed>), String> {
    let text = std::str::from_utf8(bytes).map_err(|_| format!("{MANIFEST} is not UTF-8 text"))?;
    let value: Value =
        serde_json::from_str(text).map_err(|e| format!("{MANIFEST} is not JSON: {e}"))?;
    let Some(object) = value.as_object() else {
        return Err(format!("{MANIFEST} must be an object, not {value}"));
    };
    match object.get("fjgraphic").and_then(Value::as_u64) {
        Some(1) => {}
        Some(n) if n > 1 => {
            return Err(format!(
            "the package is format {n}; this Frame Job reads format 1 — a newer Frame Job wrote it"
        ))
        }
        _ => {
            return Err(format!(
                "fjgraphic must be 1, not {}",
                shown(object.get("fjgraphic"))
            ))
        }
    }
    let module = string(object, "module", "module")?;
    check_name(&module)?;
    let title = string(object, "title", "title")?;
    let category = string(object, "category", "category")?;
    let description = match object.get("description") {
        Some(Value::String(text)) => Value::String(text.clone()),
        Some(Value::Null) => Value::Null,
        other => {
            return Err(format!(
                "description must be a string or null, not {}",
                shown(other)
            ))
        }
    };
    let app_version = string(object, "app_version", "app_version")?;
    let files = files(object, &module)?;
    let out = json!({
        "fjgraphic": 1, "module": module, "title": title, "category": category,
        "description": description, "app_version": app_version,
    });
    Ok((out, module, files))
}

/// U+0000–U+001F and U+007F–U+009F.
fn is_control(c: char) -> bool {
    matches!(c as u32, 0..=0x1F | 0x7F..=0x9F)
}

/// A project-folder name: 1 to 247 bytes, no `/`, no control scalar, no
/// leading `.`.
fn is_project_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= MAX_PROJECT_NAME
        && !name.starts_with('.')
        && !name.chars().any(|c| c == '/' || is_control(c))
}

/// `files`, each checked; the first is the module.
fn files(object: &Map<String, Value>, module: &str) -> Result<Vec<Listed>, String> {
    let Some(Value::Array(list)) = object.get("files") else {
        return Err(format!(
            "files must be an array, not {}",
            shown(object.get("files"))
        ));
    };
    if list.is_empty() {
        return Err(format!(
            "files must begin with \"{module}.js\", not be empty"
        ));
    }
    let module_file = format!("{module}.js");
    let mut out = Vec::with_capacity(list.len());
    let mut names = HashSet::new();
    for (index, file) in list.iter().enumerate() {
        let empty = Map::new();
        let fields = file.as_object().unwrap_or(&empty);
        let path = string(fields, "path", &format!("files[{index}].path"))?;
        let name = string(fields, "name", &format!("files[{index}].name"))?;
        let Some(size) = fields.get("size").and_then(Value::as_u64) else {
            return Err(format!(
                "files[{index}].size must be a whole number of bytes, not {}",
                shown(fields.get("size"))
            ));
        };
        let sha256 = match fields.get("sha256") {
            Some(Value::String(sha))
                if sha.len() == 64
                    && sha
                        .bytes()
                        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) =>
            {
                sha.clone()
            }
            other => {
                return Err(format!(
                    "files[{index}].sha256 must be 64 lowercase hex digits, not {}",
                    shown(other)
                ))
            }
        };
        if index == 0 {
            if path != module_file || name != module_file {
                return Err(format!(
                    "the first file must be \"{module_file}\" in both path and name, not path \"{path}\" and name \"{name}\""
                ));
            }
        } else {
            let folder = ["fonts", "assets"]
                .into_iter()
                .find(|f| path.strip_prefix(f).is_some_and(|n| n.starts_with('/')));
            let legal = folder.is_some_and(|f| is_legal(&path[f.len() + 1..]));
            let Some(folder) = folder.filter(|_| legal) else {
                return Err(format!(
                    "file \"{path}\" is not fonts/<name> or assets/<name> with a name the package can hold"
                ));
            };
            if !is_project_name(&name) {
                return Err(format!(
                    "files[{index}].name \"{name}\" is not a file name (1 to {MAX_PROJECT_NAME} bytes, no /, no control character, no leading .)"
                ));
            }
            if !names.insert((folder, name.clone())) {
                return Err(format!("\"{name}\" is listed twice in {folder}/"));
            }
        }
        out.push(Listed {
            path,
            name,
            size,
            sha256,
        });
    }
    Ok(out)
}
