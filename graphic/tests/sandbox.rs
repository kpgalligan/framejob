//! G-5's sandbox (road map 10 §5b): G0's eighteen q6 cases
//! (`tools/proof/graphics_spike/src/rows_stress.rs`'s `CASES`) plus
//! `performance`, each answering what §10.1 q6 recorded. Every case that
//! compiles is called TWICE on the same engine and must answer the same
//! (the SAME-ENGINE check); then its module is dropped and `lower-third`
//! draws frame 0 on the same thread byte-identically to a fresh thread
//! (the CONTROL).

mod common;

use std::time::Instant;

use graphic::{rasterize, Diagnostic, Module};

use common::{case, shared, BUDGET_MS};

type Answer = Result<String, (String, Option<u32>, Option<u32>, Option<i64>)>;

enum Expect {
    /// Ok, and the SVG contains this text.
    Contains(&'static str),
    /// Err with this message, line, column and frame.
    Error(&'static str, Option<(u32, u32)>),
    /// The module does not compile, with this message and no position.
    Refused(&'static str),
}

const FUNCTION: &str =
    "Error: Function is not available in a graphic; the module is the one source of code";

fn call(name: &str, module: &Module) -> Answer {
    let ctx = common::ctx(0, 30.0, 300, 1920, 1080);
    let started = Instant::now();
    let answer = graphic::svg(module, 0, &serde_json::json!({}), &ctx, BUDGET_MS);
    let ms = started.elapsed().as_secs_f64() * 1000.0;
    assert!(ms < 1000.0, "the call took {ms:.2} ms");
    println!("{name}: {ms:.2} ms");
    answer
        .map(|(svg, _)| svg)
        .map_err(|d: Diagnostic| (d.message, d.line, d.column, d.frame))
}

/// The control frame's BGRA hash: `lower-third` frame 0 at 1920×1080.
fn control() -> String {
    let module = common::module("lower-third");
    let (svg, _) = common::frame(&module, 0).expect("the control draws");
    let mut out = vec![0u8; 1920 * 1080 * 4];
    rasterize(&shared(), &svg, 1920, 1080, &mut out, 1920 * 4).expect("the control rasterizes");
    common::sha256(&out)
}

fn run(name: &str, head: &str, body: &str, expect: Expect) {
    let reference = std::thread::spawn(control).join().expect("a fresh thread");
    let source = case(head, body);
    let compiled = Module::compile(shared(), name, &source, BUDGET_MS);
    let module = match (compiled, &expect) {
        (Err(d), Expect::Refused(message)) => {
            assert_eq!(&d.message, message);
            assert_eq!((d.line, d.column), (None, None));
            return;
        }
        (Err(d), _) => panic!("{name} did not compile: {}", d.message),
        (Ok(_), Expect::Refused(_)) => panic!("{name} compiled, and should not have"),
        (Ok(module), _) => module,
    };
    let first = call(name, &module);
    match (&first, &expect) {
        (Ok(svg), Expect::Contains(text)) => assert!(svg.contains(text), "{name}: {svg:.200}"),
        (Err((message, line, column, frame)), Expect::Error(expected, at)) => {
            assert_eq!(message, expected, "{name}");
            assert_eq!(*line, at.map(|a| a.0), "{name}: line");
            assert_eq!(*column, at.map(|a| a.1), "{name}: column");
            assert_eq!(*frame, Some(0), "{name}: frame");
        }
        (other, _) => panic!(
            "{name} answered {:?}",
            other
                .as_ref()
                .map(|s| s.chars().take(120).collect::<String>())
        ),
    }
    // The SAME-ENGINE check: frame N+1 after frame N's answer reuses the
    // runtime; it must answer identically.
    let second = call(name, &module);
    assert_eq!(second, first, "{name}: the second call on the same engine");
    drop(module);
    // The CONTROL, on this thread, after the case's engine is gone.
    assert_eq!(control(), reference, "{name}: the control frame");
}

#[test]
fn while_true() {
    run(
        "while_true",
        "",
        "while (true) {}",
        Expect::Error(
            "over the 250 ms budget at frame 0 (InternalError: interrupted); 3:1 is where the function begins, not the statement that ran long",
            Some((3, 1)),
        ),
    );
}

#[test]
fn array_1e9() {
    run(
        "array_1e9",
        "",
        "const a = new Array(1e9); return svg(ctx, `<!--${a.length}-->`);",
        Expect::Contains("<!--1000000000-->"),
    );
}

#[test]
fn deep_recursion() {
    run(
        "deep_recursion",
        "",
        "const f = (n) => f(n + 1) + 1; return String(f(0));",
        Expect::Error(
            "RangeError: Maximum call stack size exceeded",
            Some((4, 26)),
        ),
    );
}

#[test]
fn string_50mb() {
    run(
        "string_50mb",
        "",
        "return \"<svg\" + \"x\".repeat(5e7);",
        Expect::Error(
            "render's string could not be read at frame 0 — is it tens of megabytes?",
            None,
        ),
    );
}

#[test]
fn string_100mb() {
    run(
        "string_100mb",
        "",
        "return \"<svg\" + \"x\".repeat(1e8);",
        Expect::Error("InternalError: out of memory", Some((4, 23))),
    );
}

#[test]
fn math_random() {
    run(
        "math_random",
        "",
        "return svg(ctx, `<!--${Math.random()}-->`);",
        Expect::Error(
            "Error: Math.random is not available; use random(seed)",
            Some((4, 31)),
        ),
    );
}

#[test]
fn date_now() {
    run(
        "date_now",
        "",
        "return svg(ctx, `<!--${Date.now()} ${new Date().toISOString()}-->`);",
        Expect::Contains("<!--946684800000 2000-01-01T00:00:00.000Z-->"),
    );
}

#[test]
fn eval() {
    run(
        "eval",
        "",
        "return svg(ctx, `<!--${eval(\"1\")}-->`);",
        Expect::Error("ReferenceError: eval is not defined", Some((4, 26))),
    );
}

#[test]
fn new_function() {
    run(
        "new_function",
        "",
        "return svg(ctx, `<!--${new Function(\"return 1\")()}-->`);",
        Expect::Error(FUNCTION, Some((4, 30))),
    );
}

#[test]
fn date_constructor() {
    run(
        "date_constructor",
        "",
        "return svg(ctx, `<!--${new Date().constructor.now()}-->`);",
        Expect::Contains("<!--946684800000-->"),
    );
}

#[test]
fn async_function_constructor() {
    run(
        "async_function_constructor",
        "",
        "return svg(ctx, `<!--${typeof (async () => {}).constructor(\"return 1\")}-->`);",
        Expect::Error(FUNCTION, Some((4, 50))),
    );
}

#[test]
fn generator_function_constructor() {
    run(
        "generator_function_constructor",
        "",
        "return svg(ctx, `<!--${typeof (function* () {}).constructor(\"yield 1\")}-->`);",
        Expect::Error(FUNCTION, Some((4, 51))),
    );
}

#[test]
fn async_generator_function_constructor() {
    run(
        "async_generator_function_constructor",
        "",
        "return svg(ctx, `<!--${typeof (async function* () {}).constructor(\"yield 1\")}-->`);",
        Expect::Error(FUNCTION, Some((4, 57))),
    );
}

#[test]
fn dynamic_import() {
    run(
        "dynamic_import",
        "const m = await import(\"x\");\n",
        "return svg(ctx, \"\");",
        Expect::Refused(
            "ReferenceError: Error resolving module 'x' from 'dynamic_import': imports are not available in a graphic; the standard library is global",
        ),
    );
}

#[test]
fn static_import() {
    run(
        "static_import",
        "import x from \"x\";\n",
        "return svg(ctx, \"\");",
        Expect::Refused(
            "ReferenceError: Error resolving module 'x' from 'static_import': imports are not available in a graphic; the standard library is global",
        ),
    );
}

#[test]
fn webassembly() {
    run(
        "webassembly",
        "",
        "return svg(ctx, `<!--${typeof WebAssembly}-->`);",
        Expect::Contains("<!--undefined-->"),
    );
}

#[test]
fn uint8_leak() {
    run(
        "uint8_leak",
        "",
        "const keep = []; for (;;) keep.push(new Uint8Array(1 << 20));",
        Expect::Error("InternalError: out of memory", Some((4, 59))),
    );
}

#[test]
fn returns_undefined() {
    run(
        "returns_undefined",
        "",
        "const s = svg(ctx, \"\");",
        Expect::Error(
            "render returned undefined at frame 0 — did you forget `return`?",
            None,
        ),
    );
}

#[test]
fn performance() {
    run(
        "performance",
        "",
        "return svg(ctx, `<!--${typeof performance}-->`);",
        Expect::Contains("<!--undefined-->"),
    );
}
