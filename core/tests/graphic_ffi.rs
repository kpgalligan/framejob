//! The ten `rc_graphic_*` exports (road map 10 §5e), black box through the
//! FFI: a library built from the app's bundled faces, the `lower-third`
//! fixture compiled and drawn, and every answer read back off the C side.
//!
//! The oracles are independent of the implementation: the revision is
//! `sha2` of the fixture's bytes, the frame is the crate's own pin in
//! `graphic/tests/pins.json` (read from the file, never copied here), and
//! each refusal is the sentence the header promises, read off the TEXT so
//! the key order `diag_out` carries is what is checked, not a parsed map's.

mod common;

use std::ffi::c_char;
use std::fs;
use std::ptr;

use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use common::{cstring, take_string};
use reelcut_core::ffi_graphic::{
    rc_graphic_compile, rc_graphic_describe, rc_graphic_free, rc_graphic_library_add_asset,
    rc_graphic_library_add_font, rc_graphic_library_families, rc_graphic_library_free,
    rc_graphic_library_new, rc_graphic_rasterize, rc_graphic_svg, RcGraphic, RcGraphicLibrary,
};

const FONTS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../app/Resources/Fonts");
const FIXTURE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../graphic/tests/graphics/lower-third.js"
);
const PINS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../graphic/tests/pins.json");
const FROZEN: &str =
    "the library is frozen: a graphic was compiled or a frame drawn against it; build a new one";

/// Every `.ttf` in the app's fonts folder, in file-name order.
fn font_files() -> Vec<Vec<u8>> {
    let mut paths: Vec<_> = fs::read_dir(FONTS)
        .expect("the bundled fonts directory")
        .map(|entry| entry.expect("a directory entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "ttf"))
        .collect();
    paths.sort();
    paths
        .iter()
        .map(|path| fs::read(path).expect("a font file"))
        .collect()
}

/// `None` when the font was taken, else the refusal.
fn add_font(lib: *mut RcGraphicLibrary, bytes: &[u8]) -> Option<String> {
    let mut err: *mut c_char = ptr::null_mut();
    if unsafe { rc_graphic_library_add_font(lib, bytes.as_ptr(), bytes.len(), &mut err) } {
        assert!(err.is_null(), "a success wrote err_out");
        return None;
    }
    Some(take_string(err).expect("a refusal writes err_out"))
}

/// `None` when the asset was taken, else the refusal.
fn add_asset(lib: *mut RcGraphicLibrary, name: &str, bytes: &[u8]) -> Option<String> {
    let name = cstring(name);
    let mut err: *mut c_char = ptr::null_mut();
    let ok = unsafe {
        rc_graphic_library_add_asset(lib, name.as_ptr(), bytes.as_ptr(), bytes.len(), &mut err)
    };
    if ok {
        return None;
    }
    Some(take_string(err).expect("a refusal writes err_out"))
}

/// A library holding every bundled face.
fn library() -> *mut RcGraphicLibrary {
    let lib = unsafe { rc_graphic_library_new() };
    for font in font_files() {
        assert_eq!(add_font(lib, &font), None, "a bundled face loads");
    }
    lib
}

/// The raw `diag_out` text, and the graphic or its absence.
fn compile(lib: *const RcGraphicLibrary, source: &str, budget: u32) -> (*mut RcGraphic, String) {
    let name = cstring("lower-third");
    let source = cstring(source);
    let mut diag: *mut c_char = ptr::null_mut();
    let g = unsafe { rc_graphic_compile(lib, name.as_ptr(), source.as_ptr(), budget, &mut diag) };
    (g, take_string(diag).unwrap_or_default())
}

fn fixture() -> String {
    fs::read_to_string(FIXTURE).expect("the lower-third fixture")
}

/// `graphic/tests/common/mod.rs`'s `ctx(frame, 30.0, 150, 1920, 1080)`.
fn ctx(frame: i64) -> String {
    let progress = (frame as f64 / 149.0).clamp(0.0, 1.0);
    json!({
        "fps": 30.0, "time": frame as f64 / 30.0, "durationInFrames": 150,
        "progress": progress, "width": 1920, "height": 1080,
        "canvas": {"width": 1920, "height": 1080},
    })
    .to_string()
}

/// The SVG (or NULL) and the raw `diag_out` text.
fn svg(g: *const RcGraphic, frame: i64, props: Option<&str>) -> (Option<String>, String) {
    let props = props.map(cstring);
    let ctx = cstring(&ctx(frame));
    let mut diag: *mut c_char = ptr::null_mut();
    let props_ptr = props.as_ref().map_or(ptr::null(), |p| p.as_ptr());
    let out = unsafe { rc_graphic_svg(g, frame, props_ptr, ctx.as_ptr(), 250, &mut diag) };
    (take_string(out), take_string(diag).unwrap_or_default())
}

/// The BGRA of `svg` at 1920×1080, panicking on a failure.
fn draw(lib: *const RcGraphicLibrary, svg: &str) -> Vec<u8> {
    let text = cstring(svg);
    let mut out = vec![0u8; 1920 * 1080 * 4];
    let mut diag: *mut c_char = ptr::null_mut();
    let ok = unsafe {
        rc_graphic_rasterize(
            lib,
            text.as_ptr(),
            1920,
            1080,
            out.as_mut_ptr(),
            1920 * 4,
            &mut diag,
        )
    };
    assert!(ok, "rasterize failed: {:?}", take_string(diag));
    out
}

fn hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// The one Diagnostic a failure writes: asserts its keys are the five, in
/// order, on the TEXT, and answers it parsed.
fn one(text: &str) -> Value {
    let list: Value = serde_json::from_str(text).unwrap_or_else(|e| panic!("{e}: {text}"));
    assert_eq!(
        list.as_array().map(Vec::len),
        Some(1),
        "one diagnostic: {text}"
    );
    let keys = [
        "\"level\":",
        "\"message\":",
        "\"line\":",
        "\"column\":",
        "\"frame\":",
    ];
    let at: Vec<usize> = keys
        .iter()
        .map(|k| {
            text.find(k)
                .unwrap_or_else(|| panic!("{k} missing in {text}"))
        })
        .collect();
    assert!(at.windows(2).all(|w| w[0] < w[1]), "key order: {text}");
    list[0].clone()
}

fn error_message(text: &str) -> String {
    let d = one(text);
    assert_eq!(d["level"], "error", "{text}");
    d["message"].as_str().expect("a message").to_string()
}

#[test]
fn a_library_takes_the_bundled_faces_and_refuses_a_non_font_an_empty_and_a_duplicate_asset() {
    let fonts = font_files();
    assert_eq!(fonts.len(), 8, "the app bundles eight .ttf files");
    let lib = library();
    assert_eq!(
        add_font(lib, &[0u8; 16]).as_deref(),
        Some("font bytes loaded no face")
    );
    assert_eq!(add_asset(lib, "", b"x").as_deref(), Some("name is empty"));
    assert_eq!(add_asset(lib, "red.png", b"x"), None);
    assert_eq!(
        add_asset(lib, "red.png", b"y").as_deref(),
        Some("asset \"red.png\" is already in the library")
    );
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn describe_answers_schema_keys_in_module_order_and_the_sha256_revision() {
    let lib = library();
    let source = fixture();
    let (g, diag) = compile(lib, &source, 250);
    assert!(!g.is_null(), "lower-third did not compile: {diag}");
    assert_eq!(diag, "", "a clean compile writes no diag_out");
    let text = take_string(unsafe { rc_graphic_describe(g) }).expect("describe is not NULL");
    assert!(text.starts_with("{\"meta\":"), "{text}");
    let schema_at = text.find("\"schema\":").expect("a schema key");
    let revision_at = text.find("\"revision\":").expect("a revision key");
    assert!(schema_at < revision_at, "{text}");
    let at: Vec<usize> = ["title", "subtitle", "accent", "size", "boxed", "align"]
        .iter()
        .map(|k| text[schema_at..].find(&format!("\"{k}\":{{")).expect(k))
        .collect();
    assert!(
        at.windows(2).all(|w| w[0] < w[1]),
        "schema key order: {text}"
    );
    let parsed: Value = serde_json::from_str(&text).expect("describe is JSON");
    assert_eq!(parsed["revision"], hex(source.as_bytes()));
    assert_eq!(parsed["meta"]["durationInFrames"], 150);
    unsafe { rc_graphic_free(g) };
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn svg_at_frame_30_writes_no_diag_and_a_wrong_prop_warns_with_the_frame() {
    let lib = library();
    let (g, _) = compile(lib, &fixture(), 250);
    let (out, diag) = svg(g, 30, None);
    assert!(out.expect("an SVG").starts_with("<svg"));
    assert_eq!(diag, "", "no warnings, no diag_out");
    let (out, diag) = svg(g, 30, Some(r#"{"size":"big"}"#));
    assert!(out.is_some(), "a warning still draws");
    let d = one(&diag);
    assert_eq!(d["level"], "warning");
    assert_eq!(
        d["message"],
        "props.size is a string but the schema says number; the default 64 is used"
    );
    assert_eq!(d["frame"], 30);
    unsafe { rc_graphic_free(g) };
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn rasterize_matches_the_crate_pin_and_leaves_padding_untouched() {
    let lib = library();
    let (g, _) = compile(lib, &fixture(), 250);
    let text = svg(g, 30, None).0.expect("frame 30");
    let pins: Value =
        serde_json::from_str(&fs::read_to_string(PINS).expect("pins.json")).expect("JSON");
    assert_eq!(hex(&draw(lib, &text)), pins["lower-third"]["30"]);

    let small = cstring(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="5" height="3"><rect width="5" height="3" fill="#ff0000"/></svg>"##,
    );
    let mut out = vec![0xABu8; 32 * 3];
    let mut diag: *mut c_char = ptr::null_mut();
    assert!(unsafe {
        rc_graphic_rasterize(lib, small.as_ptr(), 5, 3, out.as_mut_ptr(), 32, &mut diag)
    });
    assert_eq!(take_string(diag), None);
    for row in out.chunks_exact(32) {
        assert_eq!(&row[..4], &[0, 0, 255, 255], "red, as BGRA");
        assert!(row[20..].iter().all(|&b| b == 0xAB), "padding touched");
    }
    unsafe { rc_graphic_free(g) };
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn a_syntax_error_and_a_top_level_loop_each_answer_one_error() {
    let lib = library();
    let (g, diag) = compile(lib, "export const meta = {};\n\nconst x = ;\n", 250);
    assert!(g.is_null());
    let d = one(&diag);
    assert_eq!(d["level"], "error");
    assert!(
        d["message"].as_str().unwrap().starts_with("SyntaxError:"),
        "{diag}"
    );
    assert_eq!(d["line"], 3);

    let (g, diag) = compile(lib, "while (true) {}\n", 50);
    assert!(g.is_null());
    let message = error_message(&diag);
    assert!(
        message.contains("over the 50 ms budget while loading"),
        "{message}"
    );
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn every_refused_argument_is_one_error_diagnostic_with_keys_in_order() {
    let lib = library();
    let (g, _) = compile(lib, &fixture(), 250);
    let name = cstring("n");
    let source = cstring(&fixture());
    let ctx = cstring(&ctx(0));
    let bad = cstring("{nope");
    let svg_text = cstring("<svg/>");
    let mut buf = [0u8; 4];
    let mut refusals: Vec<(String, String)> = Vec::new();
    let mut expect = |want: &str, call: &dyn Fn(*mut *mut c_char) -> bool| {
        let mut diag: *mut c_char = ptr::null_mut();
        assert!(!call(&mut diag), "{want}: the call succeeded");
        let text = take_string(diag).expect("diag_out written");
        refusals.push((want.to_string(), error_message(&text)));
    };
    let compiled = |l, n, s, d| unsafe { !rc_graphic_compile(l, n, s, 50, d).is_null() };
    expect("library is NULL", &|d| {
        compiled(ptr::null(), name.as_ptr(), source.as_ptr(), d)
    });
    expect("name is NULL", &|d| {
        compiled(lib, ptr::null(), source.as_ptr(), d)
    });
    expect("source is NULL", &|d| {
        compiled(lib, name.as_ptr(), ptr::null(), d)
    });
    let drawn = |g, p, c, d| unsafe { take_string(rc_graphic_svg(g, 0, p, c, 250, d)).is_some() };
    expect("graphic is NULL", &|d| {
        drawn(ptr::null(), ptr::null(), ctx.as_ptr(), d)
    });
    expect("ctx_json is NULL", &|d| {
        drawn(g, ptr::null(), ptr::null(), d)
    });
    expect("props_json is not JSON: ", &|d| {
        drawn(g, bad.as_ptr(), ctx.as_ptr(), d)
    });
    expect("ctx_json is not JSON: ", &|d| {
        drawn(g, ptr::null(), bad.as_ptr(), d)
    });
    let raster = |s, o: *mut u8, h, st, d| unsafe { rc_graphic_rasterize(lib, s, 1, h, o, st, d) };
    let out = buf.as_mut_ptr();
    expect("svg is NULL", &|d| raster(ptr::null(), out, 1, 4, d));
    expect("out_bgra is NULL", &|d| {
        raster(svg_text.as_ptr(), ptr::null_mut(), 1, 4, d)
    });
    expect("height × stride overflows", &|d| {
        raster(svg_text.as_ptr(), out, u32::MAX, usize::MAX / 2, d)
    });
    expect("library is NULL", &|d| unsafe {
        rc_graphic_rasterize(ptr::null(), svg_text.as_ptr(), 1, 1, out, 4, d)
    });
    for (want, got) in refusals {
        if want.ends_with(": ") {
            assert!(got.starts_with(&want) && got.len() > want.len(), "{got}");
        } else {
            assert_eq!(got, want);
        }
    }
    let mut err: *mut c_char = ptr::null_mut();
    let empty: *const u8 = ptr::null();
    assert!(!unsafe { rc_graphic_library_add_font(lib, empty, 4, &mut err) });
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    unsafe { rc_graphic_free(g) };
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn a_library_freezes_at_first_use_and_outlives_its_free() {
    let fonts = font_files();
    let lib = library();
    let (g, _) = compile(lib, &fixture(), 250);
    assert_eq!(add_font(lib, &fonts[0]).as_deref(), Some(FROZEN));
    assert_eq!(add_asset(lib, "late.png", b"x").as_deref(), Some(FROZEN));

    let drawn = library();
    draw(
        drawn,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1920\" height=\"1080\"/>",
    );
    assert_eq!(add_font(drawn, &fonts[0]).as_deref(), Some(FROZEN));
    unsafe { rc_graphic_library_free(drawn) };

    // The fixture measures its text, so its SVG needs the faces.
    let before = svg(g, 30, None).0.expect("frame 30");
    unsafe { rc_graphic_library_free(lib) };
    assert_eq!(svg(g, 30, None).0.as_deref(), Some(before.as_str()));
    unsafe { rc_graphic_free(g) };
}

#[test]
fn families_answers_the_bundled_faces_sorted_and_freezes() {
    let fonts = font_files();
    let lib = library();
    let text = take_string(unsafe { rc_graphic_library_families(lib) }).expect("a family list");
    let families: Value = serde_json::from_str(&text).unwrap_or_else(|e| panic!("{e}: {text}"));
    // The eight files' own family names: six families, two duplicates dropped.
    assert_eq!(
        families,
        json!([
            "Anton",
            "Bebas Neue",
            "Darker Grotesque",
            "IBM Plex Mono",
            "Montserrat",
            "Source Sans 3"
        ])
    );
    assert_eq!(add_font(lib, &fonts[0]).as_deref(), Some(FROZEN));
    assert!(unsafe { rc_graphic_library_families(ptr::null()) }.is_null());
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn a_graphic_draws_from_a_second_thread_identically() {
    let lib = library();
    let (g, _) = compile(lib, &fixture(), 250);
    let here = svg(g, 30, None).0.expect("frame 30");
    let address = g as usize;
    let there = std::thread::spawn(move || svg(address as *const RcGraphic, 30, None).0)
        .join()
        .expect("the thread did not panic");
    assert_eq!(there.as_deref(), Some(here.as_str()));
    unsafe { rc_graphic_free(g) };
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn only_ffi_graphic_names_the_graphic_crate() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/src");
    let mut naming: Vec<String> = Vec::new();
    for entry in fs::read_dir(dir).expect("core/src") {
        let path = entry.expect("an entry").path();
        let text = fs::read_to_string(&path).expect("a source file");
        let names = text.lines().any(|line| {
            line.trim_start().starts_with("use graphic")
                || line.match_indices("graphic::").any(|(i, _)| {
                    i == 0
                        || !line.as_bytes()[i - 1].is_ascii_alphanumeric()
                            && line.as_bytes()[i - 1] != b'_'
                })
        });
        if names {
            naming.push(path.file_name().unwrap().to_string_lossy().into_owned());
        }
    }
    assert_eq!(naming, vec!["ffi_graphic.rs".to_string()]);
}
