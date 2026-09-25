//! The standard library's JavaScript unit tests (road map 10 §5l): each
//! `tests/js/*.test.js`, with `_assert.js` appended, compiled as a module
//! and drawn at frame 0; an assertion that fails throws, and the test
//! panics with its message and line. Plus the warning sink: a call's
//! warnings are that call's alone.

mod common;

use std::fs;

use graphic::{Level, Module};

use common::{shared, BUDGET_MS};

const JS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/js");
const FILES: [&str; 6] = [
    "interpolate",
    "easing",
    "spring",
    "text",
    "random",
    "format",
];

fn run_js(name: &str) {
    let file = format!("{name}.test.js");
    let source = fs::read_to_string(format!("{JS}/{file}")).expect("a JS test file");
    let assert = fs::read_to_string(format!("{JS}/_assert.js")).expect("_assert.js");
    let module = Module::compile(shared(), &file, &format!("{source}\n{assert}"), BUDGET_MS)
        .unwrap_or_else(|d| panic!("{file} did not compile: {} (line {:?})", d.message, d.line));
    let ctx = common::ctx(0, 30.0, 150, 1920, 1080);
    let (svg, warnings) = graphic::svg(&module, 0, &serde_json::json!({}), &ctx, BUDGET_MS)
        .unwrap_or_else(|d| panic!("{file}: {} (line {:?})", d.message, d.line));
    assert!(svg.starts_with("<svg"));
    assert!(warnings.is_empty(), "{file}: {warnings:?}");
}

#[test]
fn interpolate_test_js() {
    run_js("interpolate");
}

#[test]
fn easing_test_js() {
    run_js("easing");
}

#[test]
fn spring_test_js() {
    run_js("spring");
}

#[test]
fn text_test_js() {
    run_js("text");
}

#[test]
fn random_test_js() {
    run_js("random");
}

#[test]
fn format_test_js() {
    run_js("format");
}

#[test]
fn every_js_test_file_has_a_rust_test() {
    let mut found: Vec<String> = fs::read_dir(JS)
        .expect("tests/js")
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .filter_map(|name| name.strip_suffix(".test.js").map(str::to_string))
        .collect();
    found.sort();
    let mut expected: Vec<String> = FILES.iter().map(|s| s.to_string()).collect();
    expected.sort();
    assert_eq!(found, expected);
}

fn compile(source: &str) -> Module {
    Module::compile(shared(), "sink", source, BUDGET_MS)
        .unwrap_or_else(|d| panic!("did not compile: {}", d.message))
}

fn call(
    module: &Module,
    frame: i64,
) -> Result<(String, Vec<graphic::Diagnostic>), graphic::Diagnostic> {
    let ctx = common::ctx(frame, 30.0, 150, 1920, 1080);
    graphic::svg(module, frame, &serde_json::json!({}), &ctx, BUDGET_MS)
}

#[test]
fn an_unknown_asset_warns_naming_the_folder() {
    let module =
        compile("export function render(frame, props, ctx) { return svg(ctx, `<!--${asset(\"nope\")}-->`); }");
    let (svg, warnings) = call(&module, 2).unwrap();
    assert!(svg.contains("<!--nope-->"), "{svg}");
    assert_eq!(warnings.len(), 1);
    assert_eq!(
        warnings[0].message,
        "asset(\"nope\") is not in graphics/assets/; the folder has: blue-then-yellow.gif, magenta.webp, red.png, steel.jpg"
    );
    assert_eq!(warnings[0].level, Level::Warning);
    assert_eq!(warnings[0].frame, Some(2));
}

#[test]
fn warnings_do_not_leak_across_calls() {
    let module = compile(
        "export function render(frame, props, ctx) {\n  asset(\"nope\");\n  if (frame === 5) return 42;\n  return svg(ctx, \"\");\n}\n",
    );
    let refused = call(&module, 5).unwrap_err();
    assert_eq!(
        refused.message,
        "render returned number at frame 5; it must return an SVG string"
    );
    let (_, warnings) = call(&module, 6).unwrap();
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert_eq!(warnings[0].frame, Some(6));
}

#[test]
fn load_time_warnings_are_discarded() {
    let module = compile(
        "asset(\"nope\");\nexport function render(frame, props, ctx) {\n  return svg(ctx, \"\");\n}\n",
    );
    let (_, warnings) = call(&module, 0).unwrap();
    assert!(warnings.is_empty(), "{warnings:?}");
}
