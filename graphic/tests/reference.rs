//! The reference an agent reads, `docs/graphics-api.md` (road map 10 §5i),
//! evaluated so it cannot rot away from the engine: every ```` ```js ````
//! block runs, every standard-library name is in it, every bundled family
//! is named, the sandbox's three sentences are quoted word for word, and the
//! schema limits it and its typings state are the engine's `MAX_PROPS`,
//! `MAX_STRING` and `MAX_OPTIONS`.
//!
//! A block that `export`s is a whole module: it compiles and draws frames 0
//! and 30. Any other block is the body of a `render(frame, props, ctx)` with
//! `return svg(ctx, "")` appended, drawn at frame 30 with `{}` props. An
//! error fails the test; a warning does not. Blocks in any other fence are
//! not run.

mod common;

use std::fs;

use graphic::{Module, MAX_OPTIONS, MAX_PROPS, MAX_STRING};

use common::{shared, BUDGET_MS};

const DOC: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../docs/graphics-api.md");
const TYPINGS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../docs/graphics-api.d.ts");
const SOURCES: [&str; 2] = [
    concat!(env!("CARGO_MANIFEST_DIR"), "/src/stdlib.js"),
    concat!(env!("CARGO_MANIFEST_DIR"), "/src/noise.js"),
];
const SANDBOX: [&str; 3] = [
    "Math.random is not available; use random(seed)",
    "imports are not available in a graphic; the standard library is global",
    "Function is not available in a graphic; the module is the one source of code",
];

fn doc() -> String {
    fs::read_to_string(DOC).expect("docs/graphics-api.md")
}

/// Where the walk over the document's lines is.
enum Fence {
    Outside,
    Js(usize, String),
    Other,
}

/// The body of every fence opened by exactly ```` ```js ````, in order,
/// with the line the fence opens on. Every other fence is skipped whole.
fn js_blocks(text: &str) -> Vec<(usize, String)> {
    let mut blocks = Vec::new();
    let mut state = Fence::Outside;
    for (index, line) in text.lines().enumerate() {
        let fence = line.trim_start().starts_with("```");
        state = match (state, fence) {
            (Fence::Outside, true) if line.trim() == "```js" => Fence::Js(index + 1, String::new()),
            (Fence::Outside, true) => Fence::Other,
            (Fence::Js(at, body), true) => {
                blocks.push((at, body));
                Fence::Outside
            }
            (Fence::Js(at, mut body), false) => {
                body.push_str(line);
                body.push('\n');
                Fence::Js(at, body)
            }
            (Fence::Other, true) => Fence::Outside,
            (other, false) => other,
        };
    }
    assert!(matches!(state, Fence::Outside), "an unclosed fence");
    blocks
}

fn run(line: usize, body: &str) {
    let name = format!("reference-{line}");
    if body.contains("export") {
        let module = Module::compile(shared(), &name, body, BUDGET_MS).unwrap_or_else(|d| {
            panic!(
                "the block at line {line} did not compile: {} ({:?}:{:?})",
                d.message, d.line, d.column
            )
        });
        for frame in [0, 30] {
            if let Err(d) = common::frame(&module, frame) {
                panic!(
                    "the block at line {line} failed at frame {frame}: {}",
                    d.message
                );
            }
        }
    } else {
        let source = format!(
            "export function render(frame, props, ctx) {{\n{body}return svg(ctx, \"\");\n}}\n"
        );
        let module = Module::compile(shared(), &name, &source, BUDGET_MS)
            .unwrap_or_else(|d| panic!("the block at line {line} did not compile: {}", d.message));
        if let Err(d) = common::frame(&module, 30) {
            panic!(
                "the block at line {line} failed: {} (line {:?} of the wrapped body)",
                d.message, d.line
            );
        }
    }
}

#[test]
fn every_js_block_in_the_reference_runs() {
    let blocks = js_blocks(&doc());
    assert!(blocks.len() >= 8, "only {} js blocks", blocks.len());
    for (line, body) in &blocks {
        run(*line, body);
    }
}

#[test]
fn the_reference_names_every_standard_library_function() {
    let text = doc();
    let mut names = vec!["Easing".to_string()];
    names.extend(stdlib_functions());
    assert!(names.contains(&"noise3D".to_string()), "{names:?}");
    let missing: Vec<&String> = names
        .iter()
        .filter(|name| !text.contains(&format!("`{name}")))
        .collect();
    assert!(
        missing.is_empty(),
        "the reference does not name {missing:?}"
    );
}

/// Every global `function NAME(` the standard library's sources declare,
/// the `__` host helpers left out.
fn stdlib_functions() -> Vec<String> {
    let mut names = Vec::new();
    for path in SOURCES {
        for line in fs::read_to_string(path).expect("a stdlib file").lines() {
            let Some(rest) = line.strip_prefix("function ") else {
                continue;
            };
            let Some((name, _)) = rest.split_once('(') else {
                continue;
            };
            if !name.starts_with("__")
                && !name.is_empty()
                && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
            {
                names.push(name.to_string());
            }
        }
    }
    names
}

#[test]
fn the_typings_declare_every_standard_library_function() {
    let text = fs::read_to_string(TYPINGS).expect("docs/graphics-api.d.ts");
    let names = stdlib_functions();
    assert!(names.contains(&"noise3D".to_string()), "{names:?}");
    let missing: Vec<&String> = names
        .iter()
        .filter(|name| !text.contains(&format!("declare function {name}(")))
        .collect();
    assert!(missing.is_empty(), "the typings do not declare {missing:?}");
    assert!(
        text.contains("declare const Easing"),
        "the typings lack Easing"
    );
    for key in [
        "fps",
        "time",
        "durationInFrames",
        "progress",
        "width",
        "height",
        "canvas",
    ] {
        assert!(text.contains(key), "the typings do not name ctx.{key}");
    }
    for line in text.lines() {
        assert!(
            !line.starts_with("import ") && !line.starts_with("export "),
            "the typings are a global declaration file, not a module: {line:?}"
        );
    }
}

#[test]
fn the_reference_names_every_bundled_family_and_the_sandbox_sentences() {
    let text = doc();
    let families = shared().families().to_vec();
    assert!(!families.is_empty());
    for family in &families {
        assert!(
            text.contains(family.as_str()),
            "the reference does not name {family}"
        );
    }
    for sentence in SANDBOX {
        assert!(
            text.contains(sentence),
            "the reference does not quote {sentence:?}"
        );
    }
}

#[test]
fn the_reference_states_the_engine_schema_limits() {
    let text = doc();
    for stated in [
        format!("At most {MAX_PROPS} keys."),
        format!("at most {MAX_STRING} characters"),
        format!("`options`: 1–{MAX_OPTIONS} strings"),
    ] {
        assert!(
            text.contains(&stated),
            "docs/graphics-api.md does not state {stated:?}"
        );
    }
    let typings = fs::read_to_string(TYPINGS).expect("docs/graphics-api.d.ts");
    let stated = format!("at most {MAX_PROPS} keys");
    assert!(
        typings.contains(&stated),
        "docs/graphics-api.d.ts does not state {stated:?}"
    );
}
