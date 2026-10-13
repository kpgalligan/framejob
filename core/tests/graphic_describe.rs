//! `rc_graphic_describe`'s `warnings` key (spec §11 G-24 (a)), black box
//! through the FFI: what a module's top level warned while it loaded comes
//! back after `revision`, each warning shaped as `diag_out`'s entries, and a
//! module that warned nothing answers an empty array.
//!
//! The library is empty, so `asset("x")` at the top level names no asset
//! the folder holds; the message's head is the engine's own sentence
//! (`graphic/src/stdlib.js`'s `asset`), read off the parsed answer, and the
//! key order is read off the TEXT.

mod common;

use std::ffi::c_char;
use std::ptr;

use serde_json::{json, Value};

use common::{cstring, take_string};
use framejob_core::ffi_graphic::{
    rc_graphic_compile, rc_graphic_describe, rc_graphic_free, rc_graphic_library_free,
    rc_graphic_library_new, RcGraphicLibrary,
};

const RENDER: &str = "export function render(frame, props, ctx) {\n  return svg(ctx, ``);\n}\n";

/// `source` compiled against `lib` and described; the describe TEXT.
fn describe(lib: *const RcGraphicLibrary, name: &str, source: &str) -> String {
    let name = cstring(name);
    let source = cstring(source);
    let mut diag: *mut c_char = ptr::null_mut();
    let g = unsafe { rc_graphic_compile(lib, name.as_ptr(), source.as_ptr(), 250, &mut diag) };
    let diag = take_string(diag).unwrap_or_default();
    assert!(!g.is_null(), "the module did not compile: {diag}");
    let text = take_string(unsafe { rc_graphic_describe(g) }).expect("describe is not NULL");
    unsafe { rc_graphic_free(g) };
    text
}

#[test]
fn describe_answers_a_top_level_warning_after_the_revision() {
    let lib = unsafe { rc_graphic_library_new() };
    let text = describe(
        lib,
        "toplevel",
        &format!("const logo = asset(\"x\");\n{RENDER}"),
    );
    let revision_at = text.find("\"revision\":").expect("a revision key");
    let warnings_at = text.find("\"warnings\":").expect("a warnings key");
    assert!(revision_at < warnings_at, "{text}");
    let parsed: Value = serde_json::from_str(&text).expect("describe is JSON");
    let warnings = parsed["warnings"].as_array().expect("warnings is an array");
    assert_eq!(warnings.len(), 1, "{text}");
    let warning = &warnings[0];
    assert_eq!(warning["level"], json!("warning"), "{text}");
    assert_eq!(
        (&warning["line"], &warning["column"], &warning["frame"]),
        (&Value::Null, &Value::Null, &Value::Null),
        "{text}"
    );
    let message = warning["message"].as_str().expect("a message");
    assert!(
        message.starts_with("asset(\"x\") is not in graphics/assets/"),
        "{message}"
    );
    unsafe { rc_graphic_library_free(lib) };
}

#[test]
fn describe_answers_no_warnings_for_a_plain_module() {
    let lib = unsafe { rc_graphic_library_new() };
    let text = describe(lib, "plain", RENDER);
    assert!(text.contains("\"warnings\":[]"), "{text}");
    unsafe { rc_graphic_library_free(lib) };
}
