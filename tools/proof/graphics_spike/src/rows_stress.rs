//! q5 (determinism across threads and orders) and q6 (the sandbox) of road
//! map 10 §3.

use std::collections::HashMap;
use std::time::Instant;

use serde_json::{json, Value};

use crate::diagnostic::Diagnostic;
use crate::raster::{rasterize, Library};
use crate::rows::{loaded, ms, render_frame, sha, Splitmix};
use crate::runtime::{default_props, Ctx, Engine, SPIKE_LIMITS};

/// `counter.js` with a module-level call counter drawn into the frame: the
/// graphic G-5 says the standard library cannot stop.
pub fn mutant(counter: &str) -> String {
    counter.replace("export function render(", "function __render(")
        + "\nlet __calls = 0;\nexport function render(frame, props, ctx) {\n  __calls++;\n  \
           return __render(frame, props, ctx).replace(\"</svg>\", `<rect width=\"${__calls % 97 + 1}\" height=\"1\" fill=\"#fff\"/></svg>`);\n}\n"
}

type Key = (String, i64);
type Renders = Vec<Result<Vec<(Key, (String, String))>, Diagnostic>>;

fn one(
    engines: &mut HashMap<String, (Engine, Value)>,
    lib: &Library,
    graphics: &[(String, String)],
    key: &Key,
) -> Result<(String, String), Diagnostic> {
    let source = &graphics.iter().find(|g| g.0 == key.0).unwrap().1;
    if !engines.contains_key(&key.0) {
        engines.insert(key.0.clone(), loaded(lib, &key.0, source)?);
    }
    let (engine, props) = engines.get_mut(&key.0).unwrap();
    let ctx = Ctx::at(key.1, 30.0, 300, 1920, 1080);
    let svg = engine.svg(key.1, props, &ctx)?;
    let raster = rasterize(lib, &svg, 1920, 1080)?;
    Ok((sha(&raster.bgra), sha(svg.as_bytes())))
}

pub fn q5(lib: &Library, graphics: &[(String, String)]) -> Result<Value, Diagnostic> {
    const FRAMES: [i64; 6] = [0, 7, 30, 90, 150, 299];
    let keys: Vec<Key> = graphics
        .iter()
        .flat_map(|g| FRAMES.iter().map(move |f| (g.0.clone(), *f)))
        .collect();
    let mut reference = HashMap::new();
    for (name, _) in graphics {
        let mut engines = HashMap::new();
        for frame in FRAMES {
            let key = (name.clone(), frame);
            reference.insert(key.clone(), one(&mut engines, lib, graphics, &key)?);
        }
    }
    let results: Renders = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..8u32)
            .map(|t| {
                let (keys, lib) = (keys.clone(), lib.clone());
                scope.spawn(move || {
                    let mut rng = Splitmix(0xd5_0000 + t);
                    let mut order: Vec<Key> = (0..3).flat_map(|_| keys.clone()).collect();
                    for i in (1..order.len()).rev() {
                        order.swap(i, rng.below(i + 1));
                    }
                    let mut engines = HashMap::new();
                    order
                        .into_iter()
                        .map(|k| one(&mut engines, &lib, graphics, &k).map(|r| (k, r)))
                        .collect()
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    let (mut renders, mut raster_mismatch, mut svg_mismatch) = (0, 0, 0);
    for thread in results {
        for (key, (raster, svg)) in thread? {
            renders += 1;
            raster_mismatch += usize::from(reference[&key].0 != raster);
            svg_mismatch += usize::from(reference[&key].1 != svg);
        }
    }
    let mut after = Vec::new();
    for (name, source) in graphics {
        let (mut engine, props) = loaded(lib, name, source)?;
        for frame in 0..300 {
            engine.svg(frame, &props, &Ctx::at(frame, 30.0, 300, 1920, 1080))?;
        }
        let mut engines = HashMap::from([(name.clone(), (engine, props))]);
        let equal = FRAMES.iter().all(|f| {
            let key = (name.clone(), *f);
            one(&mut engines, lib, graphics, &key)
                .map(|r| r == reference[&key])
                .unwrap_or(false)
        });
        after.push(json!({"graphic": name, "equal": equal}));
    }
    Ok(
        json!({"threads": 8, "repeats": 3, "renders": renders, "reference_renders": reference.len(),
        "sha256_mismatches": raster_mismatch, "svg_mismatches": svg_mismatch,
        "after_300_others_equal": after}),
    )
}

pub const CASES: &[(&str, &str, &str)] = &[
    ("while_true", "", "while (true) {}"),
    (
        "array_1e9",
        "",
        "const a = new Array(1e9); return svg(ctx, `<!--${a.length}-->`);",
    ),
    (
        "deep_recursion",
        "",
        "const f = (n) => f(n + 1) + 1; return String(f(0));",
    ),
    ("string_50mb", "", "return \"<svg\" + \"x\".repeat(5e7);"),
    ("string_100mb", "", "return \"<svg\" + \"x\".repeat(1e8);"),
    (
        "math_random",
        "",
        "return svg(ctx, `<!--${Math.random()}-->`);",
    ),
    (
        "date_now",
        "",
        "return svg(ctx, `<!--${Date.now()} ${new Date().toISOString()}-->`);",
    ),
    ("eval", "", "return svg(ctx, `<!--${eval(\"1\")}-->`);"),
    (
        "new_function",
        "",
        "return svg(ctx, `<!--${new Function(\"return 1\")()}-->`);",
    ),
    (
        "date_constructor",
        "",
        "return svg(ctx, `<!--${new Date().constructor.now()}-->`);",
    ),
    (
        "async_function_constructor",
        "",
        "return svg(ctx, `<!--${typeof (async () => {}).constructor(\"return 1\")}-->`);",
    ),
    (
        "generator_function_constructor",
        "",
        "return svg(ctx, `<!--${typeof (function* () {}).constructor(\"yield 1\")}-->`);",
    ),
    (
        "async_generator_function_constructor",
        "",
        "return svg(ctx, `<!--${typeof (async function* () {}).constructor(\"yield 1\")}-->`);",
    ),
    (
        "dynamic_import",
        "const m = await import(\"x\");\n",
        "return svg(ctx, \"\");",
    ),
    (
        "static_import",
        "import x from \"x\";\n",
        "return svg(ctx, \"\");",
    ),
    (
        "webassembly",
        "",
        "return svg(ctx, `<!--${typeof WebAssembly}-->`);",
    ),
    (
        "uint8_leak",
        "",
        "const keep = []; for (;;) keep.push(new Uint8Array(1 << 20));",
    ),
    ("returns_undefined", "", "const s = svg(ctx, \"\");"),
];

pub fn q6(lib: &Library, case: &str, control: &str) -> Result<Value, Diagnostic> {
    let (_, head, body) = CASES
        .iter()
        .find(|c| c.0 == case)
        .ok_or_else(|| Diagnostic::error(format!("no case {case}")))?;
    let source = format!(
        "{head}export const meta = {{ name: \"{case}\" }};\nexport const schema = {{}};\n\
                          export function render(frame, props, ctx) {{\n  {body}\n}}\n"
    );
    let mut engine = Engine::new(lib, &SPIKE_LIMITS)?;
    let ctx = Ctx::at(0, 30.0, 300, 1920, 1080);
    let started = Instant::now();
    let answer = engine
        .load(case, &source)
        .and_then(|_| engine.svg(0, &json!({}), &ctx));
    let elapsed = ms(started);
    let mut out = match answer {
        Ok(svg) => json!({"outcome": "ok", "message": svg.chars().take(120).collect::<String>(),
                          "svg_bytes": svg.len(), "line": null, "column": null}),
        Err(d) => {
            json!({"outcome": "error", "message": d.message, "line": d.line, "column": d.column})
        }
    };
    let fresh = loaded(lib, "lower-third", control)
        .and_then(|(mut e, p)| render_frame(&mut e, lib, 0, &p, &ctx, 1920, 1080));
    let same = engine.load("lower-third", control).and_then(|info| {
        render_frame(&mut engine, lib, 0, &default_props(&info), &ctx, 1920, 1080)
    });
    let control_ok = matches!((&same, &fresh), (Ok(a), Ok(b)) if a.sha256 == b.sha256);
    out["case"] = json!(case);
    out["ms"] = json!(elapsed);
    out["control_ok"] = json!(control_ok);
    if let Err(d) = &same {
        out["control_error"] = json!(d.message);
    }
    Ok(out)
}
