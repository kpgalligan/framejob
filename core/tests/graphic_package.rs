//! `rc_graphic_package_write` (spec §11 G-46 (c)), black box through the
//! FFI. The oracles are independent of the implementation: a zip reader
//! written here (end record → central directory → local headers), a bitwise
//! CRC-32 checked against the standard check value, `sha2` for the
//! manifest's checksums, and the manifest's text spelled out in full.

mod common;

use std::ffi::c_char;
use std::fs;
use std::path::{Path, PathBuf};
use std::ptr;

use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use common::{cstring, take_string};
use framejob_core::ffi_graphic_package::rc_graphic_package_write;

/// A fresh, empty scratch folder for one test.
fn scratch(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("fjpkg-{}-{tag}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("a scratch folder");
    dir
}

/// The manifest the core answers, or its refusal.
fn write(path: &Path, spec: &Value, data: &[u8]) -> Result<String, String> {
    let path = cstring(path.to_str().expect("a UTF-8 path"));
    let spec = cstring(&spec.to_string());
    let mut err: *mut c_char = ptr::null_mut();
    let out = unsafe {
        rc_graphic_package_write(
            path.as_ptr(),
            spec.as_ptr(),
            data.as_ptr(),
            data.len(),
            &mut err,
        )
    };
    match take_string(out) {
        Some(manifest) => {
            assert!(err.is_null(), "a success wrote err_out");
            Ok(manifest)
        }
        None => Err(take_string(err).expect("a refusal writes err_out")),
    }
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

fn u16_at(b: &[u8], at: usize) -> u16 {
    u16::from_le_bytes([b[at], b[at + 1]])
}

fn u32_at(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}

/// One entry as the central directory and its local header both say it.
#[derive(Debug)]
struct Entry {
    name: String,
    data: Vec<u8>,
    crc: u32,
}

/// Reads the archive the long way, asserting every fixed field G-46 (c)
/// names on both the central and the local record.
fn read_zip(zip: &[u8]) -> Vec<Entry> {
    let end = zip.len() - 22;
    assert_eq!(u32_at(zip, end), 0x0605_4b50, "the end record is last");
    assert_eq!(u16_at(zip, end + 20), 0, "no archive comment");
    let count = usize::from(u16_at(zip, end + 10));
    assert_eq!(u16_at(zip, end + 8), count as u16);
    let central_len = u32_at(zip, end + 12) as usize;
    let mut at = u32_at(zip, end + 16) as usize;
    assert_eq!(
        at + central_len,
        end,
        "the central directory ends at the end record"
    );
    let mut entries = Vec::new();
    for _ in 0..count {
        assert_eq!(u32_at(zip, at), 0x0201_4b50);
        assert_eq!(u16_at(zip, at + 4), 0x031E, "made-by");
        assert_eq!(u16_at(zip, at + 6), 10, "version needed");
        assert_eq!(u16_at(zip, at + 8), 0x0800, "flag bit 11 alone");
        assert_eq!(u16_at(zip, at + 10), 0, "stored");
        assert_eq!(u16_at(zip, at + 12), 0, "time 0");
        assert_eq!(u16_at(zip, at + 14), 0x0021, "1980-01-01");
        let crc = u32_at(zip, at + 16);
        let compressed = u32_at(zip, at + 20) as usize;
        let size = u32_at(zip, at + 24) as usize;
        assert_eq!(compressed, size, "stored: both sizes agree");
        let name_len = usize::from(u16_at(zip, at + 28));
        assert_eq!(u16_at(zip, at + 30), 0, "no extra field");
        assert_eq!(u16_at(zip, at + 32), 0, "no comment");
        assert_eq!(u32_at(zip, at + 38), 0o100644 << 16, "external attributes");
        let local = u32_at(zip, at + 42) as usize;
        let name = String::from_utf8(zip[at + 46..at + 46 + name_len].to_vec()).expect("UTF-8");
        assert!(!name.ends_with('/'), "no directory entries");
        at += 46 + name_len;

        assert_eq!(u32_at(zip, local), 0x0403_4b50);
        assert_eq!(u16_at(zip, local + 4), 10);
        assert_eq!(u16_at(zip, local + 6), 0x0800);
        assert_eq!(u16_at(zip, local + 8), 0);
        assert_eq!(u16_at(zip, local + 10), 0);
        assert_eq!(u16_at(zip, local + 12), 0x0021);
        assert_eq!(u32_at(zip, local + 14), crc, "{name}: local CRC");
        assert_eq!(u32_at(zip, local + 18) as usize, size);
        assert_eq!(u32_at(zip, local + 22) as usize, size);
        assert_eq!(usize::from(u16_at(zip, local + 26)), name_len);
        assert_eq!(u16_at(zip, local + 28), 0, "no local extra field");
        assert_eq!(&zip[local + 30..local + 30 + name_len], name.as_bytes());
        let start = local + 30 + name_len;
        entries.push(Entry {
            name,
            data: zip[start..start + size].to_vec(),
            crc,
        });
    }
    entries
}

const MODULE: &[u8] = b"export function render() { return ''; }\n";
const FONT: &[u8] = b"pretend font bytes";
const PNG: &[u8] = b"\x89PNG pretend image";

/// A module, one font and one asset, and their bytes concatenated.
fn package() -> (Value, Vec<u8>) {
    let spec = json!({
        "module": "lower-third",
        "title": "Lower third",
        "category": "Titles & Text",
        "description": null,
        "app_version": "0.3.19",
        "files": [
            {"path": "lower-third.js", "size": MODULE.len()},
            {"path": "fonts/Anton.ttf", "size": FONT.len()},
            {"path": "assets/red.png", "size": PNG.len()},
        ],
    });
    (spec, [MODULE, FONT, PNG].concat())
}

#[test]
fn the_bitwise_oracle_has_the_standard_check_value() {
    assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
}

#[test]
fn each_entry_carries_the_ieee_crc_of_its_bytes() {
    let dir = scratch("crc");
    let path = dir.join("a.fjgraphic");
    let (spec, data) = package();
    write(&path, &spec, &data).expect("written");
    let entries = read_zip(&fs::read(&path).expect("the package"));
    assert_eq!(entries.len(), 4);
    for entry in &entries {
        assert_eq!(entry.crc, crc32(&entry.data), "{}", entry.name);
    }
}

#[test]
fn the_archive_is_the_manifest_then_the_files_in_order_and_the_answer_is_its_manifest() {
    let dir = scratch("order");
    let path = dir.join("lower-third.fjgraphic");
    let (spec, data) = package();
    let answered = write(&path, &spec, &data).expect("written");
    let entries = read_zip(&fs::read(&path).expect("the package"));
    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(
        names,
        [
            "manifest.json",
            "lower-third.js",
            "fonts/Anton.ttf",
            "assets/red.png"
        ]
    );
    assert_eq!(entries[1].data, MODULE);
    assert_eq!(entries[2].data, FONT);
    assert_eq!(entries[3].data, PNG);
    let manifest = format!(
        "{{\n  \"fjgraphic\": 1,\n  \"module\": \"lower-third\",\n  \"title\": \"Lower third\",\n  \
         \"category\": \"Titles & Text\",\n  \"description\": null,\n  \"app_version\": \"0.3.19\",\n  \
         \"files\": [\n{},\n{},\n{}\n  ]\n}}\n",
        file_text("lower-third.js", "lower-third.js", MODULE),
        file_text("fonts/Anton.ttf", "Anton.ttf", FONT),
        file_text("assets/red.png", "red.png", PNG),
    );
    assert_eq!(
        String::from_utf8(entries[0].data.clone()).unwrap(),
        manifest
    );
    assert_eq!(answered, manifest);
}

/// One `files` entry as pretty JSON prints it, four spaces in.
fn file_text(path: &str, name: &str, bytes: &[u8]) -> String {
    format!(
        "    {{\n      \"path\": \"{path}\",\n      \"name\": \"{name}\",\n      \"size\": {},\n      \
         \"sha256\": \"{}\"\n    }}",
        bytes.len(),
        sha(bytes)
    )
}

#[test]
fn a_description_string_is_kept_and_two_writes_are_byte_identical() {
    let dir = scratch("same");
    let (mut spec, data) = package();
    spec["description"] = json!("A name and a role.");
    let one = dir.join("one.fjgraphic");
    let two = dir.join("two.fjgraphic");
    let manifest = write(&one, &spec, &data).expect("written");
    write(&two, &spec, &data).expect("written");
    assert_eq!(fs::read(&one).unwrap(), fs::read(&two).unwrap());
    let parsed: Value = serde_json::from_str(&manifest).unwrap();
    assert_eq!(parsed["description"], "A name and a role.");
    // A rewrite to the same path truncates: the same bytes, not appended.
    write(&one, &spec, &data).expect("rewritten");
    assert_eq!(fs::read(&one).unwrap(), fs::read(&two).unwrap());
}

#[test]
fn every_refusal_names_its_value_and_writes_nothing() {
    let dir = scratch("refusals");
    let (base, data) = package();
    let with = |key: &str, value: Value| {
        let mut spec = base.clone();
        spec[key] = value;
        spec
    };
    let files = |list: Value| with("files", list);
    let cases: Vec<(Value, Vec<u8>, &str)> = vec![
        (
            with("module", json!("Lower Third")),
            data.clone(),
            "graphic name \"Lower Third\" is not a module name",
        ),
        (
            with("title", json!(5)),
            data.clone(),
            "title must be a string, not 5",
        ),
        (
            with("category", Value::Null),
            data.clone(),
            "category must be a string, not null",
        ),
        (
            with("app_version", json!([])),
            data.clone(),
            "app_version must be a string, not []",
        ),
        (
            with("description", json!(false)),
            data.clone(),
            "description must be a string or null, not false",
        ),
        (
            files(json!([{"path": "title-card.js", "size": data.len()}])),
            data.clone(),
            "the first file must be \"lower-third.js\", not \"title-card.js\"",
        ),
        (
            files(json!([
                {"path": "lower-third.js", "size": MODULE.len()},
                {"path": "Anton.ttf", "size": FONT.len() + PNG.len()},
            ])),
            data.clone(),
            "file \"Anton.ttf\" is not fonts/<name> or assets/<name>",
        ),
        (
            files(json!([
                {"path": "lower-third.js", "size": MODULE.len()},
                {"path": "fonts/", "size": FONT.len() + PNG.len()},
            ])),
            data.clone(),
            "file \"fonts/\" is not fonts/<name> or assets/<name>",
        ),
        (
            files(json!([
                {"path": "lower-third.js", "size": MODULE.len()},
                {"path": "assets/a/b.png", "size": FONT.len() + PNG.len()},
            ])),
            data.clone(),
            "file \"assets/a/b.png\" is not fonts/<name> or assets/<name>",
        ),
        (
            files(json!([
                {"path": "lower-third.js", "size": MODULE.len()},
                {"path": format!("fonts/{}", "a".repeat(256)), "size": FONT.len() + PNG.len()},
            ])),
            data.clone(),
            "is not fonts/<name> or assets/<name>",
        ),
        (
            files(json!([
                {"path": "lower-third.js", "size": MODULE.len()},
                {"path": "fonts/Anton.ttf", "size": FONT.len()},
                {"path": "fonts/Anton.ttf", "size": PNG.len()},
            ])),
            data.clone(),
            "file \"fonts/Anton.ttf\" is given twice",
        ),
        (
            base.clone(),
            data[..data.len() - 1].to_vec(),
            &format!(
                "the files' sizes sum to {} bytes, but data holds {}",
                data.len(),
                data.len() - 1
            )
            .leak()[..],
        ),
    ];
    for (n, (spec, bytes, sentence)) in cases.iter().enumerate() {
        let path = dir.join(format!("{n}.fjgraphic"));
        let refusal = write(&path, spec, bytes).expect_err("refused");
        assert!(
            refusal.contains(sentence),
            "case {n}: {refusal:?} does not hold {sentence:?}"
        );
        assert_eq!(
            refusal.chars().next().map(char::is_lowercase),
            Some(true),
            "case {n}: a lowercase sentence: {refusal}"
        );
        assert!(!path.exists(), "case {n}: nothing written");
    }
    assert!(
        fs::read_dir(&dir).unwrap().next().is_none(),
        "the folder is empty"
    );
}

#[test]
fn an_io_failure_is_refused_by_its_path() {
    let dir = scratch("io");
    let path = dir.join("missing").join("a.fjgraphic");
    let (spec, data) = package();
    let refusal = write(&path, &spec, &data).expect_err("refused");
    assert!(
        refusal.starts_with(&format!("cannot write {}", path.display())),
        "{refusal}"
    );
}

/// The in-package paths and manifest names a package of `given` (each a
/// project-relative path, holding its own path's bytes) gets.
fn names_of(dir: &Path, given: &[&str]) -> (Vec<String>, Vec<String>) {
    let path = dir.join("names.fjgraphic");
    let mut files = vec![json!({"path": "lower-third.js", "size": MODULE.len()})];
    let mut data = MODULE.to_vec();
    for name in given {
        files.push(json!({"path": name, "size": name.len()}));
        data.extend_from_slice(name.as_bytes());
    }
    let (mut spec, _) = package();
    spec["files"] = Value::Array(files);
    let manifest = write(&path, &spec, &data).expect("written");
    let entries = read_zip(&fs::read(&path).unwrap());
    let parsed: Value = serde_json::from_str(&manifest).unwrap();
    let listed = parsed["files"].as_array().unwrap();
    for (i, entry) in entries.iter().skip(1).enumerate() {
        assert_eq!(listed[i]["path"], entry.name.as_str());
        assert_eq!(listed[i]["sha256"], sha(&entry.data).as_str());
    }
    for (i, name) in given.iter().enumerate() {
        assert_eq!(entries[i + 2].data, name.as_bytes(), "{name}'s bytes");
    }
    (
        entries.iter().skip(2).map(|e| e.name.clone()).collect(),
        listed
            .iter()
            .skip(1)
            .map(|f| f["name"].as_str().unwrap().to_string())
            .collect(),
    )
}

#[test]
fn an_illegal_in_package_name_is_legalised_and_the_manifest_keeps_the_given_name() {
    let dir = scratch("names");
    let given = [
        "fonts/a:b.ttf",
        "assets/red\\dot.png",
        "fonts/x\u{1}\u{2}\u{85}y.otf",
        "fonts/.hidden.ttf",
        "fonts/:",
        "fonts/..",
        "assets/Kept Name (1).png",
    ];
    let (paths, names) = names_of(&dir, &given);
    assert_eq!(
        paths,
        [
            "fonts/a-b.ttf",
            "assets/red-dot.png",
            "fonts/x-y.otf",
            "fonts/hidden.ttf",
            "fonts/-",
            "fonts/file",
            "assets/Kept Name (1).png",
        ]
    );
    assert_eq!(
        names,
        [
            "a:b.ttf",
            "red\\dot.png",
            "x\u{1}\u{2}\u{85}y.otf",
            ".hidden.ttf",
            ":",
            "..",
            "Kept Name (1).png",
        ]
    );
}

#[test]
fn a_legalised_name_already_claimed_takes_a_suffix_and_the_legal_name_keeps_its_own() {
    let dir = scratch("collide");
    let given = [
        "fonts/a:b.ttf",
        "fonts/a-b.ttf",
        "fonts/a\\b.ttf",
        "assets/a:b.ttf",
    ];
    let (paths, names) = names_of(&dir, &given);
    assert_eq!(
        paths,
        [
            "fonts/a-b-2.ttf",
            "fonts/a-b.ttf",
            "fonts/a-b-3.ttf",
            "assets/a-b.ttf",
        ]
    );
    assert_eq!(names, ["a:b.ttf", "a-b.ttf", "a\\b.ttf", "a:b.ttf"]);
}

#[test]
fn a_suffixed_name_stays_within_255_bytes_by_whole_scalars() {
    let dir = scratch("long");
    // 250 bytes of stem: "é" is two bytes, so the cut must not split one.
    let stem = "é".repeat(125);
    let legal = format!("fonts/{stem}-.ttf");
    let illegal = format!("fonts/{stem}:.ttf");
    let (paths, _) = names_of(&dir, &[legal.as_str(), illegal.as_str()]);
    assert_eq!(paths[0], legal);
    let renamed = paths[1].strip_prefix("fonts/").unwrap();
    assert!(renamed.len() <= 255, "{} bytes", renamed.len());
    assert!(renamed.ends_with("-2.ttf"), "{renamed}");
    assert!(renamed.starts_with(&"é".repeat(120)), "{renamed}");
}
