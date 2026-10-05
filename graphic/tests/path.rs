//! The path helpers (spec §11 G-31) where JavaScript alone cannot answer:
//! what `evolvePath`'s dash DRAWS, pixel by pixel (R1); what a fresh path
//! of 200 cubics and 1,000 points costs (R2) and a path over the memo's
//! cost bound (R4), each one render under the preview budget, its
//! milliseconds printed; that a parse error is reported at the module's own
//! line (R3); and the reference shapes' relative errors, printed (R5).
//! The lengths, points and sentences themselves are `tests/js/path.test.js`.

mod common;

use std::time::Instant;

use graphic::Module;

use common::{pixel, shared, BUDGET_MS};

const RED: [u8; 4] = [0, 0, 255, 255];
const CLEAR: [u8; 4] = [0, 0, 0, 0];
const SIDE: u32 = 200;

fn compile(source: &str) -> Module {
    Module::compile(shared(), "path", source, BUDGET_MS)
        .unwrap_or_else(|d| panic!("did not compile: {}", d.message))
}

/// A 200 × 200 module stroking `d` in red, 12 wide, butt caps, drawn on by
/// `evolvePath(frame / 100, d)`.
fn stroked(d: &str) -> Module {
    compile(&format!(
        "export const meta = {{}};\n\
         const D = \"{d}\";\n\
         export function render(frame, props, ctx) {{\n\
         \x20 const dash = evolvePath(frame / 100, D);\n\
         \x20 return svg(ctx, `<path d=\"${{D}}\" fill=\"none\" stroke=\"#ff0000\" stroke-width=\"12\" \
         stroke-linecap=\"butt\" stroke-dasharray=\"${{dash.strokeDasharray}}\" \
         stroke-dashoffset=\"${{dash.strokeDashoffset}}\"/>`);\n\
         }}\n"
    ))
}

/// `module` at `progress` hundredths, rasterized without a warning.
fn drawn(module: &Module, progress: i64) -> Vec<u8> {
    let ctx = common::ctx(progress, 30.0, 150, SIDE, SIDE);
    let (svg, warnings) = graphic::svg(module, progress, &serde_json::json!({}), &ctx, BUDGET_MS)
        .unwrap_or_else(|d| panic!("{}", d.message));
    assert!(warnings.is_empty(), "{warnings:?}");
    let (buffer, warnings) = common::render(&shared(), &svg, SIDE, SIDE);
    assert!(warnings.is_empty(), "{warnings:?}");
    buffer
}

fn at(buffer: &[u8], x: usize, y: usize) -> [u8; 4] {
    pixel(buffer, SIDE as usize * 4, x, y)
}

/// R1. The circle of radius 70 about (100, 100) runs from (170, 100) down
/// through (100, 170), (30, 100) and (100, 30): pixel (169, 98) lies wholly
/// in its last 1 %, (30, 100) at its middle, (100, 169) in its first half
/// and (100, 30) in its second.
#[test]
fn evolve_path_draws_a_closed_circle_on() {
    let circle = stroked("M 170 100 A 70 70 0 1 1 30 100 A 70 70 0 1 1 170 100");
    let whole = drawn(&circle, 100);
    assert_eq!(at(&whole, 169, 98), RED, "the last 1 % at progress 1");
    assert_eq!(at(&whole, 30, 100), RED, "mid-path at progress 1");
    let none = drawn(&circle, 0);
    assert_eq!(at(&none, 169, 98), CLEAR, "the last 1 % at progress 0");
    assert_eq!(at(&none, 30, 100), CLEAR, "mid-path at progress 0");
    let half = drawn(&circle, 50);
    assert_eq!(at(&half, 100, 169), RED, "the first half at progress 0.5");
    assert_eq!(at(&half, 100, 30), CLEAR, "its mirror at progress 0.5");
}

/// R1, two subpaths, 160 and 80 long: each draws from its own start at
/// once, dashed by the longer.
#[test]
fn evolve_path_draws_every_subpath_at_once() {
    let lines = stroked("M 20 50 H 180 M 20 150 H 100");
    let quarter = drawn(&lines, 25);
    assert_eq!(at(&quarter, 40, 50), RED, "the long line at 0.25");
    assert_eq!(at(&quarter, 40, 150), RED, "the short line at 0.25");
    assert_eq!(at(&quarter, 70, 50), CLEAR, "the long line past its tip");
    assert_eq!(at(&quarter, 70, 150), CLEAR, "the short line past its tip");
    let half = drawn(&lines, 50);
    assert_eq!(at(&half, 90, 50), RED, "the long line at 0.5");
    assert_eq!(at(&half, 95, 150), RED, "the short line, whole at 0.5");
    assert_eq!(at(&half, 110, 50), CLEAR, "the long line past its tip");
}

/// The text of the `<desc>` a module answered.
fn desc(svg: &str) -> &str {
    &svg[svg.find("<desc>").expect("a desc") + 6..svg.find("</desc>").expect("its end")]
}

/// One render of `source` at frame 7 under the preview budget: its
/// `<desc>` and the milliseconds it took.
fn timed(source: &str) -> (String, f64) {
    let module = compile(source);
    let ctx = common::ctx(7, 30.0, 150, 1920, 1080);
    let started = Instant::now();
    let answer = graphic::svg(&module, 7, &serde_json::json!({}), &ctx, BUDGET_MS);
    let elapsed = started.elapsed().as_secs_f64() * 1000.0;
    let (svg, warnings) = answer.unwrap_or_else(|d| panic!("{}", d.message));
    assert!(warnings.is_empty(), "{warnings:?}");
    (desc(&svg).to_string(), elapsed)
}

/// R2. The path is built from the frame, so nothing measured it before.
#[test]
fn a_fresh_path_of_200_cubics_and_1000_points_fits_the_budget() {
    let (answer, elapsed) = timed(
        "export const meta = {};\n\
         export function render(frame, props, ctx) {\n\
         \x20 let d = \"M 0 0\";\n\
         \x20 for (let i = 0; i < 200; i++) {\n\
         \x20   const x = i * 10;\n\
         \x20   d += ` C ${x + 2} ${30 + frame} ${x + 8} ${-30 - frame} ${x + 10} 0`;\n\
         \x20 }\n\
         \x20 const total = getLength(d);\n\
         \x20 let inside = 0;\n\
         \x20 for (let i = 0; i < 1000; i++) {\n\
         \x20   const p = getPointAtLength(d, total * i / 999);\n\
         \x20   if (p.x >= 0 && p.x <= 2000) inside++;\n\
         \x20 }\n\
         \x20 return svg(ctx, `<desc>${total > 2000} ${inside}</desc>`);\n\
         }\n",
    );
    assert_eq!(answer, "true 1000");
    println!("R2: 200 cubic segments measured and 1,000 points taken in {elapsed:.1} ms (budget {BUDGET_MS} ms)");
}

/// R3.
#[test]
fn a_parse_error_names_the_modules_line() {
    let module = compile(
        "export const meta = {};\n\
         export function render(frame, props, ctx) {\n\
         \x20 const length = getLength(\"M 0 0 X\");\n\
         \x20 return svg(ctx, `<desc>${length}</desc>`);\n\
         }\n",
    );
    let ctx = common::ctx(4, 30.0, 150, 1920, 1080);
    let d = graphic::svg(&module, 4, &serde_json::json!({}), &ctx, BUDGET_MS).unwrap_err();
    assert_eq!(
        d.message,
        "Error: getLength: cannot parse the path at character 6: \"X\""
    );
    assert_eq!(d.line, Some(3), "{d:?}");
    assert_eq!(d.frame, Some(4));
}

/// R4. `big` costs 17,000 chords and 34,005 characters, over the memo's
/// 50,000 on its own: it is kept alone, dropped for the small path, and
/// measured again.
#[test]
fn a_path_over_the_memos_cost_bound_measures_the_same_twice() {
    let (answer, elapsed) = timed(
        "export const meta = {};\n\
         export function render(frame, props, ctx) {\n\
         \x20 const big = \"M 0 0\" + \"h1\".repeat(17000);\n\
         \x20 const first = getLength(big);\n\
         \x20 const small = getLength(\"M 0 0 L 3 4\");\n\
         \x20 const again = getLength(big);\n\
         \x20 const x = getPointAtLength(big, 8500.5).x;\n\
         \x20 return svg(ctx, `<desc>${big.length} ${first} ${small} ${again} ${x}</desc>`);\n\
         }\n",
    );
    assert_eq!(answer, "34005 17000 5 17000 8500.5");
    println!("R4: a 17,000-segment path measured twice with a point taken in {elapsed:.1} ms (budget {BUDGET_MS} ms)");
}

/// R5. The reference shapes of G-31 (f) against their closed forms, the
/// relative error of each printed.
#[test]
fn the_reference_shapes_are_within_the_tolerance() {
    let (answer, _) = timed(
        "export const meta = {};\n\
         export function render(frame, props, ctx) {\n\
         \x20 const a = 200 * Math.cos(Math.PI / 6);\n\
         \x20 const b = 200 * Math.sin(Math.PI / 6);\n\
         \x20 const lengths = [\n\
         \x20   \"M 500 0 A 500 500 0 1 1 -500 0 A 500 500 0 1 1 500 0\",\n\
         \x20   \"M 200 0 A 200 100 0 1 1 -200 0 A 200 100 0 1 1 200 0\",\n\
         \x20   `M ${a} ${b} A 200 100 30 1 1 ${-a} ${-b} A 200 100 30 1 1 ${a} ${b}`,\n\
         \x20   \"M -100 100 Q 0 -100 100 100\",\n\
         \x20   `M -100 100 C ${-100 / 3} ${-100 / 3} ${100 / 3} ${-100 / 3} 100 100`,\n\
         \x20   \"M 0 0 C 0 0 33.333333333333336 0 100 100\",\n\
         \x20 ].map(getLength);\n\
         \x20 return svg(ctx, `<desc>${JSON.stringify(lengths)}</desc>`);\n\
         }\n",
    );
    let lengths: Vec<f64> = serde_json::from_str(&answer).expect("the lengths");
    let ellipse = 968.844_822_054_767_5;
    let parabola = 100.0 * (5f64.sqrt() + 2f64.asinh() / 2.0);
    let cusp = 100.0 * (13.0 * 13f64.sqrt() - 8.0) / 27.0;
    let shapes = [
        ("a circle of radius 500", 2.0 * std::f64::consts::PI * 500.0),
        ("the ellipse 200 by 100", ellipse),
        ("the ellipse turned 30 degrees", ellipse),
        ("the parabola as a Q", parabola),
        ("the parabola as a C", parabola),
        ("the cusp", cusp),
    ];
    assert_eq!(lengths.len(), shapes.len());
    for ((name, exact), measured) in shapes.iter().zip(&lengths) {
        let error = (measured - exact).abs() / exact;
        println!(
            "R5: {name}: measured {measured}, closed form {exact}, relative error {error:.2e}"
        );
        assert!(error <= 1e-4, "{name}: {error:e}");
    }
}
