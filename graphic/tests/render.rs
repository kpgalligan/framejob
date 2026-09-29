//! `svg` (road map 10 §5b): the six fixtures draw cleanly, and every way
//! `render` can answer wrongly is named, with the frame, and with the
//! module's own line when it threw.

mod common;

use graphic::{rasterize, Diagnostic, Module};

use common::{shared, BUDGET_MS, FIXTURES};

fn compile(source: &str) -> Module {
    Module::compile(shared(), "probe", source, BUDGET_MS)
        .unwrap_or_else(|d| panic!("did not compile: {}", d.message))
}

fn failure(source: &str, frame: i64) -> Diagnostic {
    let module = compile(source);
    let ctx = common::ctx(frame, 30.0, 150, 1920, 1080);
    match graphic::svg(&module, frame, &serde_json::json!({}), &ctx, BUDGET_MS) {
        Ok((svg, _)) => panic!("drew, and should not have: {svg:.120}"),
        Err(d) => d,
    }
}

#[test]
fn the_six_fixtures_draw_without_a_warning() {
    for name in FIXTURES {
        let module = common::module(name);
        for frame in [0, 30, 90] {
            let (svg, warnings) =
                common::frame(&module, frame).unwrap_or_else(|d| panic!("{name} {frame}: {d:?}"));
            assert!(svg.starts_with("<svg"), "{name} {frame}");
            assert!(warnings.is_empty(), "{name} {frame}: {warnings:?}");
            let mut out = vec![0u8; 1920 * 1080 * 4];
            let raster = rasterize(&shared(), &svg, 1920, 1080, &mut out, 1920 * 4)
                .unwrap_or_else(|d| panic!("{name} {frame}: {}", d.message));
            assert!(raster.is_empty(), "{name} {frame}: {raster:?}");
        }
    }
}

#[test]
fn a_number_is_named() {
    let d = failure(
        "export function render(frame, props, ctx) { return 42; }",
        7,
    );
    assert_eq!(
        d.message,
        "render returned number at frame 7; it must return an SVG string"
    );
    assert_eq!(d.frame, Some(7));
    assert_eq!((d.line, d.column), (None, None));
}

#[test]
fn a_string_that_is_not_svg_is_quoted() {
    let d = failure(
        "export function render(frame, props, ctx) { return \"<div>\"; }",
        3,
    );
    assert_eq!(
        d.message,
        "render returned a string that does not start with <svg at frame 3: \"<div>\""
    );
    assert_eq!(d.frame, Some(3));
}

#[test]
fn ctx_must_be_an_object() {
    let module = compile("export function render(frame, props, ctx) { return svg(ctx, \"\"); }");
    let d = graphic::svg(
        &module,
        4,
        &serde_json::json!({}),
        &serde_json::json!([]),
        BUDGET_MS,
    )
    .unwrap_err();
    assert_eq!(d.message, "ctx must be a JSON object");
    assert_eq!(d.frame, Some(4));
}

#[test]
fn a_throw_in_a_module_helper_names_the_helpers_line() {
    let source = "export const meta = {};\n\
                  function helper() {\n\
                  \x20 throw new Error(\"boom\");\n\
                  }\n\
                  export function render(frame, props, ctx) {\n\
                  \x20 return helper();\n\
                  }\n";
    let d = failure(source, 12);
    assert_eq!(d.message, "Error: boom");
    assert_eq!((d.line, d.column), (Some(3), Some(13)));
    assert_eq!(d.frame, Some(12));
}

/// The throw starts in the standard library (`eval_script`); the module's
/// frame below it is the one reported.
#[test]
fn a_throw_from_the_stdlib_names_the_module_helpers_line() {
    let source = "export const meta = {};\n\
                  function tint() {\n\
                  \x20 return interpolateColors(0, [0, 1], [\"boom\", \"#000\"]);\n\
                  }\n\
                  export function render(frame, props, ctx) {\n\
                  \x20 return svg(ctx, `<rect fill=\"${tint()}\"/>`);\n\
                  }\n";
    let d = failure(source, 21);
    assert_eq!(
        d.message,
        "Error: interpolateColors: cannot parse colour \"boom\""
    );
    assert_eq!((d.line, d.column), (Some(3), Some(10)), "{d:?}");
    assert_eq!(d.frame, Some(21));
}

/// A thread with no engine yet loads one inside `svg`; when that load
/// runs past the budget, the sentence says "while loading" and still
/// carries the frame. The budget is 0, so the deadline has passed at the
/// load's first interrupt poll on any host; the loop is kept so polls
/// happen. (An unbounded loop cannot be used: `compile` runs the same
/// top-level code under its own budget.)
#[test]
fn a_load_that_fails_inside_svg_names_the_frame() {
    let source = "export const meta = {};\n\
                  let n = 0;\n\
                  for (let i = 0; i < 1000000; i++) n += i;\n\
                  export function render(frame, props, ctx) { return svg(ctx, \"\"); }\n";
    let module = compile(source);
    let d = std::thread::spawn(move || {
        let ctx = common::ctx(9, 30.0, 150, 1920, 1080);
        match graphic::svg(&module, 9, &serde_json::json!({}), &ctx, 0) {
            Ok((svg, _)) => panic!("drew, and should not have: {svg:.120}"),
            Err(d) => d,
        }
    })
    .join()
    .expect("the thread");
    assert_eq!(
        d.message,
        "over the 0 ms budget while loading (InternalError: interrupted)"
    );
    assert_eq!(d.frame, Some(9));
}
