//! `rc_graphic_package_read` (spec §11 G-47 (c)), black box through the FFI.
//! The oracles are independent of the implementation: a stored-zip builder
//! written here (each entry's method, CRC and size fields its own knobs), a
//! bitwise CRC-32, `sha2` for the manifest's checksums, and the round trip
//! through `rc_graphic_package_write`, whose answer is spelled out in full.

mod common;

use std::ffi::c_char;
use std::fs;
use std::ptr;

use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use common::{cstring, take_string};
use framejob_core::ffi_graphic_package::{rc_graphic_package_read, rc_graphic_package_write};

/// The answer, or the refusal.
fn read(data: &[u8]) -> Result<String, String> {
    let mut err: *mut c_char = ptr::null_mut();
    let out = unsafe { rc_graphic_package_read(data.as_ptr(), data.len(), &mut err) };
    match take_string(out) {
        Some(answer) => {
            assert!(err.is_null(), "a success wrote err_out");
            Ok(answer)
        }
        None => Err(take_string(err).expect("a refusal writes err_out")),
    }
}

fn refused(data: &[u8]) -> String {
    read(data).expect_err("refused")
}

/// CRC-32 (IEEE) one bit at a time: reflected, init and xorout all ones.
fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in bytes {
        crc ^= u32::from(b);
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

fn sha(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// One entry for the builder: its name and bytes, and the fields a test
/// may set wrong.
#[derive(Clone)]
struct Item {
    name: String,
    data: Vec<u8>,
    method: u16,
    /// Both size fields, local and central; `None` is the data's length.
    sizes: Option<u32>,
}

fn item(name: &str, data: &[u8]) -> Item {
    Item {
        name: name.to_string(),
        data: data.to_vec(),
        method: 0,
        sizes: None,
    }
}

fn put16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn put32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

/// A zip of `items` in order, each local header, the central directory and
/// the end record written field by field (APPNOTE 4.3.7, 4.3.12, 4.3.16).
fn zip(items: &[Item]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut central = Vec::new();
    for it in items {
        let offset = out.len() as u32;
        let crc = crc32(&it.data);
        let size = it.sizes.unwrap_or(it.data.len() as u32);
        put32(&mut out, 0x0403_4b50);
        for v in [20, 0x0800, it.method, 0, 0x0021] {
            put16(&mut out, v);
        }
        for v in [crc, size, size] {
            put32(&mut out, v);
        }
        put16(&mut out, it.name.len() as u16);
        put16(&mut out, 0);
        out.extend_from_slice(it.name.as_bytes());
        out.extend_from_slice(&it.data);
        put32(&mut central, 0x0201_4b50);
        for v in [0x031E, 20, 0x0800, it.method, 0, 0x0021] {
            put16(&mut central, v);
        }
        for v in [crc, size, size] {
            put32(&mut central, v);
        }
        for v in [it.name.len() as u16, 0, 0, 0, 0] {
            put16(&mut central, v);
        }
        put32(&mut central, 0o100644 << 16);
        put32(&mut central, offset);
        central.extend_from_slice(it.name.as_bytes());
    }
    let at = out.len() as u32;
    out.extend_from_slice(&central);
    put32(&mut out, 0x0605_4b50);
    for v in [0, 0, items.len() as u16, items.len() as u16] {
        put16(&mut out, v);
    }
    put32(&mut out, central.len() as u32);
    put32(&mut out, at);
    put16(&mut out, 0);
    out
}

const MODULE: &[u8] = b"export function render() { return ''; }\n";
const FONT: &[u8] = b"pretend font bytes";
const PNG: &[u8] = b"\x89PNG pretend image";

/// A manifest listing `files` as `(path, name, bytes)`.
fn manifest(files: &[(&str, &str, &[u8])]) -> Value {
    let listed: Vec<Value> = files
        .iter()
        .map(|(path, name, bytes)| {
            json!({"path": path, "name": name, "size": bytes.len(), "sha256": sha(bytes)})
        })
        .collect();
    json!({
        "fjgraphic": 1, "module": "lower-third", "title": "Lower third",
        "category": "Titles & Text", "description": null, "app_version": "0.3.20",
        "files": listed,
    })
}

const FILES: [(&str, &str, &[u8]); 3] = [
    ("lower-third.js", "lower-third.js", MODULE),
    ("fonts/Anton.ttf", "Anton.ttf", FONT),
    ("assets/red.png", "red.png", PNG),
];

/// The manifest's entry first, then `files`' bytes under their paths.
fn items(manifest: &Value, files: &[(&str, &str, &[u8])]) -> Vec<Item> {
    let mut all = vec![item("manifest.json", manifest.to_string().as_bytes())];
    all.extend(files.iter().map(|(path, _, bytes)| item(path, bytes)));
    all
}

fn package(manifest: &Value, files: &[(&str, &str, &[u8])]) -> Vec<u8> {
    zip(&items(manifest, files))
}

#[test]
fn the_bitwise_oracle_has_the_standard_check_value() {
    assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
}

#[test]
fn a_package_built_here_reads_and_answers_each_offset() {
    let data = package(&manifest(&FILES), &FILES);
    let answer: Value = serde_json::from_str(&read(&data).expect("read")).unwrap();
    let files = answer["files"].as_array().unwrap();
    assert_eq!(files.len(), 3);
    for (file, (path, name, bytes)) in files.iter().zip(FILES) {
        assert_eq!(file["path"], path);
        assert_eq!(file["name"], name);
        let at = file["offset"].as_u64().unwrap() as usize;
        assert_eq!(&data[at..at + bytes.len()], bytes, "{path}");
    }
}

#[test]
fn round_trips_through_the_writer_with_offsets_bytes_and_order() {
    let dir = std::env::temp_dir().join(format!("fjread-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join("lower-third.fjgraphic");
    let spec = json!({
        "module": "lower-third", "title": "Lower third", "category": "Titles & Text",
        "description": "A name.", "app_version": "0.3.20",
        "files": [
            {"path": "lower-third.js", "size": MODULE.len()},
            {"path": "fonts/Ver:dana.ttf", "size": FONT.len()},
            {"path": "assets/red\\dot.png", "size": PNG.len()},
        ],
    });
    let c_path = cstring(path.to_str().unwrap());
    let c_spec = cstring(&spec.to_string());
    let all = [MODULE, FONT, PNG].concat();
    let mut err: *mut c_char = ptr::null_mut();
    let written = unsafe {
        rc_graphic_package_write(
            c_path.as_ptr(),
            c_spec.as_ptr(),
            all.as_ptr(),
            all.len(),
            &mut err,
        )
    };
    assert!(take_string(written).is_some(), "{:?}", take_string(err));
    let data = fs::read(&path).unwrap();
    let answer = read(&data).expect("read");
    let offsets: Vec<usize> = serde_json::from_str::<Value>(&answer).unwrap()["files"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| f["offset"].as_u64().unwrap() as usize)
        .collect();
    for (at, bytes) in offsets.iter().zip([MODULE, FONT, PNG]) {
        assert_eq!(&data[*at..*at + bytes.len()], bytes);
    }
    let row = |path: &str, name: &str, bytes: &[u8], at: usize| {
        format!(
            "{{\"path\":\"{path}\",\"name\":\"{name}\",\"size\":{},\"sha256\":\"{}\",\"offset\":{at}}}",
            bytes.len(),
            sha(bytes)
        )
    };
    let expected = format!(
        "{{\"fjgraphic\":1,\"module\":\"lower-third\",\"title\":\"Lower third\",\
         \"category\":\"Titles & Text\",\"description\":\"A name.\",\"app_version\":\"0.3.20\",\
         \"files\":[{},{},{}]}}",
        row("lower-third.js", "lower-third.js", MODULE, offsets[0]),
        row("fonts/Ver-dana.ttf", "Ver:dana.ttf", FONT, offsets[1]),
        row("assets/red-dot.png", "red\\\\dot.png", PNG, offsets[2]),
    );
    assert_eq!(answer, expected);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn a_flipped_data_byte_with_its_crc_fixed_is_refused_by_its_sha256() {
    let mut tampered = FILES;
    let bad = b"pretend font bytez";
    tampered[1].2 = bad;
    let data = package(&manifest(&FILES), &tampered);
    assert_eq!(
        refused(&data),
        format!(
            "fonts/Anton.ttf's SHA-256 is {}, but the manifest says {}",
            sha(bad),
            sha(FONT)
        )
    );
}

#[test]
fn a_flipped_byte_is_refused_by_its_crc() {
    let mut data = package(&manifest(&FILES), &FILES);
    let at = data.windows(FONT.len()).position(|w| w == FONT).unwrap();
    data[at] ^= 0x01;
    let mut flipped = FONT.to_vec();
    flipped[0] ^= 0x01;
    assert_eq!(
        refused(&data),
        format!(
            "fonts/Anton.ttf's CRC-32 is {:08x}, but the archive says {:08x}",
            crc32(&flipped),
            crc32(FONT)
        )
    );
}

#[test]
fn a_deflated_entry_is_refused() {
    let mut all = items(&manifest(&FILES), &FILES);
    all[2].method = 8;
    assert_eq!(
        refused(&zip(&all)),
        "fonts/Anton.ttf is compressed (method 8); a .fjgraphic holds stored entries only"
    );
}

#[test]
fn the_manifest_must_come_first() {
    let mut all = items(&manifest(&FILES), &FILES);
    all.swap(0, 1);
    assert_eq!(
        refused(&zip(&all)),
        "the first entry is \"lower-third.js\", not \"manifest.json\""
    );
}

#[test]
fn a_newer_format_and_format_0_are_refused() {
    let mut newer = manifest(&FILES);
    newer["fjgraphic"] = json!(2);
    assert_eq!(
        refused(&package(&newer, &FILES)),
        "the package is format 2; this Frame Job reads format 1 — a newer Frame Job wrote it"
    );
    let mut zero = manifest(&FILES);
    zero["fjgraphic"] = json!(0);
    assert_eq!(
        refused(&package(&zero, &FILES)),
        "fjgraphic must be 1, not 0"
    );
}

/// The module and one more file at `path` named `name`, archive and manifest agreeing.
fn one_more(path: &str, name: &str) -> String {
    let files = [FILES[0], (path, name, FONT)];
    refused(&package(&manifest(&files), &files))
}

#[test]
fn an_escaping_or_hidden_path_is_refused() {
    for path in ["fonts/../x.ttf", "fonts/.x.ttf", "../x.ttf"] {
        assert_eq!(
            one_more(path, "x.ttf"),
            format!(
                "file \"{path}\" is not fonts/<name> or assets/<name> with a name the package can hold"
            )
        );
    }
}

#[test]
fn a_hidden_name_or_a_slash_in_a_name_is_refused() {
    for name in [".x.ttf", "a/b.ttf", "../x.ttf"] {
        assert_eq!(
            one_more("fonts/x.ttf", name),
            format!(
                "files[1].name \"{name}\" is not a file name (1 to 247 bytes, no /, no control character, no leading .)"
            )
        );
    }
}

#[test]
fn a_path_outside_fonts_and_assets_is_refused() {
    assert_eq!(
        one_more("media/x.png", "x.png"),
        "file \"media/x.png\" is not fonts/<name> or assets/<name> with a name the package can hold"
    );
}

#[test]
fn an_extra_or_a_missing_entry_is_refused() {
    let listed = manifest(&FILES);
    let mut extra = FILES.to_vec();
    extra.push(("assets/blue.png", "blue.png", PNG));
    assert_eq!(
        refused(&package(&listed, &extra)),
        "the package's entries are \"lower-third.js\", \"fonts/Anton.ttf\", \"assets/red.png\", \
         \"assets/blue.png\", but the manifest lists \"lower-third.js\", \"fonts/Anton.ttf\", \
         \"assets/red.png\""
    );
    assert_eq!(
        refused(&package(&listed, &FILES[..2])),
        "the package's entries are \"lower-third.js\", \"fonts/Anton.ttf\", but the manifest \
         lists \"lower-third.js\", \"fonts/Anton.ttf\", \"assets/red.png\""
    );
}

#[test]
fn a_size_mismatch_is_refused() {
    let mut listed = manifest(&FILES);
    listed["files"][2]["size"] = json!(PNG.len() + 1);
    assert_eq!(
        refused(&package(&listed, &FILES)),
        format!(
            "assets/red.png is {} bytes, but the manifest says {}",
            PNG.len(),
            PNG.len() + 1
        )
    );
}

#[test]
fn a_module_that_is_not_utf8_is_refused() {
    let files = [("lower-third.js", "lower-third.js", &b"\xff\xfe"[..])];
    assert_eq!(
        refused(&package(&manifest(&files), &files)),
        "lower-third.js is not UTF-8 text"
    );
}

#[test]
fn a_truncated_archive_is_not_a_zip() {
    let data = package(&manifest(&FILES), &FILES);
    for cut in [1, 10, data.len() / 2, data.len()] {
        assert_eq!(
            refused(&data[..data.len() - cut]),
            "the package is not a zip: no end of central directory record"
        );
    }
}

#[test]
fn zip64_markers_are_refused() {
    let mut all = items(&manifest(&FILES), &FILES);
    all[3].sizes = Some(0xFFFF_FFFF);
    assert_eq!(
        refused(&zip(&all)),
        "assets/red.png uses Zip64 (a field of 0xFFFFFFFF); a .fjgraphic is a zip without Zip64"
    );
    let mut data = package(&manifest(&FILES), &FILES);
    let end = data.len() - 22;
    data[end + 8..end + 12].copy_from_slice(&[0xFF; 4]);
    assert_eq!(
        refused(&data),
        "the package's end record points to Zip64; a .fjgraphic is a zip without Zip64"
    );
}
