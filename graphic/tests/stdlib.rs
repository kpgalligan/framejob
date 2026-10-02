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

/// G-12's one fixture, which `core/tests/graphic.rs` runs through the core.
const COLOURS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/colours.json");

#[test]
fn interpolate_colors_answers_the_shared_colour_fixture() {
    let fixture: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(COLOURS).expect("tests/colours.json"))
            .expect("the colour fixture is JSON");
    let accepted = fixture["accepted"].as_array().expect("accepted");
    let refused = fixture["refused"].as_array().expect("refused");
    assert!(!accepted.is_empty() && !refused.is_empty());
    let sent: Vec<&serde_json::Value> = accepted
        .iter()
        .map(|case| &case[0])
        .chain(refused.iter())
        .collect();
    // Each colour at both ends of a segment answers itself: what the core
    // would store for it, or the throw.
    let source = format!(
        "const SENT = {};\n\
         export function render(frame, props, ctx) {{\n\
           const answers = SENT.map((c) => {{\n\
             try {{ return interpolateColors(0, [0, 1], [c, c]); }}\n\
             catch (e) {{ return `threw: ${{e.message}}`; }}\n\
           }});\n\
           return svg(ctx, `<desc>${{escapeXml(JSON.stringify(answers))}}</desc>`);\n\
         }}\n",
        serde_json::Value::from(sent.iter().map(|v| (*v).clone()).collect::<Vec<_>>())
    );
    let module = compile(&source);
    let (svg, warnings) = call(&module, 0).unwrap_or_else(|d| panic!("{}", d.message));
    assert!(warnings.is_empty(), "{warnings:?}");
    let body = &svg[svg.find("<desc>").expect("a desc") + 6..svg.find("</desc>").expect("its end")];
    let unescaped = body
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&");
    let answers: Vec<String> = serde_json::from_str(&unescaped).expect("the answers");
    for (case, answer) in accepted.iter().zip(&answers) {
        assert_eq!(answer, case[1].as_str().unwrap(), "{}", case[0]);
    }
    for (sent, answer) in refused.iter().zip(&answers[accepted.len()..]) {
        let sent = sent.as_str().unwrap();
        assert_eq!(
            answer,
            &format!("threw: interpolateColors: cannot parse colour \"{sent}\""),
            "{sent:?}"
        );
    }
}
