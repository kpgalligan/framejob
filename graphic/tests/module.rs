//! `Module::compile` (road map 10 §5c): the exports read in the module's
//! key order, the revision, every compile sentence, the warnings a module's
//! top level raises (spec §11 G-21 (b)), and the per-thread engines swept
//! when their module is dropped and capped at `ENGINES_PER_THREAD`, least
//! recently used evicted first (G-21 (a)).

mod common;

use graphic::{engine_count, Diagnostic, Level, Module, ENGINES_PER_THREAD};
use sha2::{Digest, Sha256};

use common::{shared, BUDGET_MS};

/// §5c's module, verbatim (G0's `rows.rs` `SECTION_5C`).
const SECTION_5C: &str = r##"export const meta = {
  name: "Lower third",        // shown in the inspector; the file name is the id
  width: 1920, height: 1080,  // optional; default the canvas at add time (G-7)
  durationInFrames: 150,      // optional; default length of a new clip
};

export const schema = {
  title:    { type: "string",  default: "Jane Doe", label: "Title" },
  subtitle: { type: "string",  default: "Director" },
  accent:   { type: "color",   default: "#ff5a36" },
  size:     { type: "number",  default: 64, min: 12, max: 200, step: 1 },
  boxed:    { type: "boolean", default: true },
  align:    { type: "enum",    default: "left", options: ["left", "center", "right"] },
  logo:     { type: "asset",   default: null },          // a file in graphics/assets/
};

export function render(frame, props, ctx) {
  // ctx = { fps, time, durationInFrames, progress, width, height, canvas: {width, height} }
  const x = interpolate(frame, [0, 20], [-600, 80], { easing: Easing.outCubic, clamp: true });
  const s = spring({ frame: frame - 10, fps: ctx.fps, damping: 14 });
  const out = interpolate(frame, [ctx.durationInFrames - 15, ctx.durationInFrames], [1, 0], { clamp: true });
  return svg(ctx, `
    <g opacity="${out}">
      <rect x="${x}" y="${ctx.height - 260}" width="12" height="140" fill="${props.accent}"/>
      <text x="${x + 40}" y="${ctx.height - 180}" font-family="Montserrat" font-weight="800"
            font-size="${props.size}" opacity="${s}">${escapeXml(props.title)}</text>
    </g>`);
}
"##;

const RENDER: &str = "export function render(frame, props, ctx) { return svg(ctx, \"\"); }\n";

fn compile(name: &str, source: &str) -> Result<Module, Diagnostic> {
    Module::compile(shared(), name, source, BUDGET_MS)
}

fn refusal(source: &str) -> Diagnostic {
    match compile("refused", source) {
        Ok(_) => panic!("compiled, and should not have:\n{source}"),
        Err(d) => d,
    }
}

fn keys(value: &serde_json::Value) -> Vec<&str> {
    value
        .as_object()
        .expect("an object")
        .keys()
        .map(String::as_str)
        .collect()
}

#[test]
fn section_5c_compiles_with_its_keys_in_order() {
    let module = compile("section-5c", SECTION_5C).expect("§5c's module compiles");
    assert_eq!(
        keys(module.schema()),
        ["title", "subtitle", "accent", "size", "boxed", "align", "logo"]
    );
    assert_eq!(
        keys(module.meta()),
        ["name", "width", "height", "durationInFrames"]
    );
    assert_eq!(module.name(), "section-5c");
    assert_eq!(module.source(), SECTION_5C);
    assert_eq!(
        module.defaults(),
        serde_json::json!({"title": "Jane Doe", "subtitle": "Director", "accent": "#ff5a36",
            "size": 64, "boxed": true, "align": "left", "logo": null})
    );
    assert_eq!(keys(&module.defaults()), keys(module.schema()));
}

#[test]
fn the_revision_is_the_sources_sha256() {
    let module = compile("section-5c", SECTION_5C).unwrap();
    let revision = module.revision();
    assert_eq!(revision.len(), 64);
    assert!(revision
        .chars()
        .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    let oracle: String = Sha256::digest(SECTION_5C.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    assert_eq!(revision, oracle);
    let changed = SECTION_5C.replacen("Jane Doe", "Jane Dod", 1);
    let other = compile("section-5c", &changed).unwrap();
    assert_ne!(other.revision(), revision);
}

#[test]
fn a_module_is_send_sync_and_clone() {
    fn assert_all<T: Send + Sync + Clone>() {}
    assert_all::<Module>();
}

#[test]
fn absent_meta_and_schema_are_empty_objects() {
    let module = compile("bare", RENDER).unwrap();
    assert_eq!(module.meta(), &serde_json::json!({}));
    assert_eq!(module.schema(), &serde_json::json!({}));
    assert_eq!(module.defaults(), serde_json::json!({}));
}

#[test]
fn every_compile_sentence() {
    let schema = |body: &str| format!("export const schema = {body};\n{RENDER}");
    let many: Vec<String> = (0..65)
        .map(|i| format!("k{i}: {{ type: \"number\", default: 0 }}"))
        .collect();
    let cases: Vec<(String, &str)> = vec![
        (
            "export const meta = {};\n".into(),
            "the module exports no `render` function",
        ),
        (
            "export const render = 3;\n".into(),
            "the module exports no `render` function",
        ),
        (
            format!("export const meta = 3;\n{RENDER}"),
            "meta must be an object",
        ),
        (
            format!("export const meta = null;\n{RENDER}"),
            "meta must be an object",
        ),
        (schema("[]"), "schema must be an object"),
        (
            schema(&format!("{{ {} }}", many.join(", "))),
            "schema has 65 keys; the most is 64",
        ),
        (
            schema("{ \"1st\": { type: \"number\", default: 0 } }"),
            "schema key \"1st\" is not a name (letters, digits and _, starting with a letter or _, at most 32 characters)",
        ),
        (
            schema("{ a: 3 }"),
            "schema.a must be an object with a type",
        ),
        (
            schema("{ a: { default: 1 } }"),
            "schema.a must be an object with a type",
        ),
        (
            schema("{ a: { type: \"date\", default: 1 } }"),
            "schema.a.type \"date\" is not one of string, number, boolean, color, enum, asset",
        ),
        (
            schema("{ a: { type: \"number\" } }"),
            "schema.a has no default",
        ),
        (
            schema("{ a: { type: \"number\", default: \"1\" } }"),
            "schema.a.default \"1\" is not a number",
        ),
        (
            schema("{ a: { type: \"number\", default: NaN } }"),
            "schema.a.default null is not a number",
        ),
        (
            schema("{ a: { type: \"string\", default: \"x\".repeat(4097) } }"),
            "",
        ),
        (
            schema("{ a: { type: \"boolean\", default: 0 } }"),
            "schema.a.default 0 is not a boolean",
        ),
        (
            schema("{ a: { type: \"color\", default: 0 } }"),
            "schema.a.default 0 is not a color",
        ),
        (
            schema("{ a: { type: \"enum\", default: \"c\", options: [\"a\", \"b\"] } }"),
            "schema.a.default \"c\" is not a enum",
        ),
        (
            schema("{ a: { type: \"asset\", default: 7 } }"),
            "schema.a.default 7 is not a asset",
        ),
        (
            schema("{ a: { type: \"enum\", default: \"a\", options: [] } }"),
            "schema.a.options must be 1–32 strings",
        ),
        (
            schema("{ a: { type: \"enum\", default: \"a\", options: [\"a\", 2] } }"),
            "schema.a.options must be 1–32 strings",
        ),
    ];
    for (source, expected) in cases {
        let d = refusal(&source);
        if expected.is_empty() {
            assert!(
                d.message.starts_with("schema.a.default \"xxxx")
                    && d.message.ends_with("is not a string"),
                "{}",
                d.message
            );
        } else {
            assert_eq!(d.message, expected, "for:\n{source}");
        }
        assert_eq!(d.frame, None);
    }
    // At the limits, each compiles.
    let sixty_four: Vec<String> = (0..64)
        .map(|i| format!("k{i}: {{ type: \"number\", default: 0 }}"))
        .collect();
    compile(
        "limits",
        &schema(&format!("{{ {} }}", sixty_four.join(", "))),
    )
    .unwrap();
    let name = format!("_{}", "a".repeat(31));
    compile(
        "limits",
        &schema(&format!(
            "{{ {name}: {{ type: \"string\", default: \"x\".repeat(4096) }}, \
             b: {{ type: \"asset\", default: null }}, c: {{ type: \"color\", default: \"red\" }} }}"
        )),
    )
    .unwrap();
}

#[test]
fn a_syntax_error_is_named_with_its_line() {
    let d = refusal(&format!(
        "export const meta = {{}};\n\nconst x = ;\n{RENDER}"
    ));
    assert!(d.message.starts_with("SyntaxError:"), "{}", d.message);
    assert_eq!((d.line, d.column), (Some(3), Some(11)), "{d:?}");
}

#[test]
fn a_top_level_loop_is_over_the_budget_while_loading() {
    let d = refusal(&format!("while (true) {{}}\n{RENDER}"));
    assert_eq!(
        d.message,
        "over the 250 ms budget while loading (InternalError: interrupted)"
    );
    assert_eq!(d.frame, None);
}

/// Five modules compiled on one thread and dropped leave five engines; the
/// next call sweeps them (and drops each field in its order — a wrong one
/// aborts the process here).
#[test]
fn dropped_modules_engines_are_swept() {
    std::thread::spawn(|| {
        assert_eq!(engine_count(), 0);
        let five: Vec<Module> = (0..5)
            .map(|i| compile(&format!("m{i}"), RENDER).unwrap())
            .collect();
        assert_eq!(engine_count(), 5);
        drop(five);
        assert_eq!(engine_count(), 5);
        let sixth = compile("m5", RENDER).unwrap();
        let ctx = common::ctx(0, 30.0, 150, 1920, 1080);
        graphic::svg(&sixth, 0, &serde_json::json!({}), &ctx, BUDGET_MS).unwrap();
        assert_eq!(engine_count(), 1);
        drop(sixth);
    })
    .join()
    .expect("the thread finished");
}

#[test]
fn a_module_draws_on_a_thread_that_did_not_compile_it() {
    let module = common::module("lower-third");
    let here = common::frame(&module, 30).unwrap().0;
    let there = std::thread::spawn(move || {
        let answer = common::frame(&module, 30).unwrap().0;
        (answer, engine_count())
    })
    .join()
    .unwrap();
    assert_eq!(there.0, here);
    assert_eq!(there.1, 1);
}

fn draw(module: &Module) -> (String, Vec<Diagnostic>) {
    let ctx = common::ctx(0, 30.0, 150, 1920, 1080);
    graphic::svg(module, 0, &serde_json::json!({}), &ctx, BUDGET_MS).unwrap()
}

/// Forty live modules on one thread leave sixteen engines; an evicted one
/// draws again, by a reload, the same SVG it drew first, and the count
/// stays at the cap.
#[test]
fn a_thread_holds_at_most_sixteen_engines() {
    std::thread::spawn(|| {
        assert_eq!(ENGINES_PER_THREAD, 16);
        let mut first = String::new();
        let forty: Vec<Module> = (0..40)
            .map(|i| {
                let module = compile(&format!("m{i}"), RENDER).unwrap();
                if i == 0 {
                    first = draw(&module).0;
                }
                module
            })
            .collect();
        assert_eq!(engine_count(), 16);
        let again = draw(&forty[0]).0;
        assert_eq!(engine_count(), 16);
        assert_eq!(again.as_bytes(), first.as_bytes());
    })
    .join()
    .expect("the thread finished");
}

/// The engine evicted is the least recently USED, not the first compiled:
/// a counter module answers how many frames its engine has drawn, so a
/// reload shows as a count that starts again at 1.
#[test]
fn the_least_recently_used_engine_is_evicted() {
    const COUNTER: &str = "let calls = 0;\n\
        export function render(f, p, ctx) { calls++; return svg(ctx, `<!--${calls}-->`); }\n";
    let calls = |module: &Module| -> u32 {
        let text = draw(module).0;
        let start = text.find("<!--").expect("a count") + 4;
        let end = start + text[start..].find("-->").expect("a count's end");
        text[start..end].parse().expect("a number")
    };
    std::thread::spawn(move || {
        let m0 = compile("m0", COUNTER).unwrap(); // stamp 1
        assert_eq!(calls(&m0), 1); // stamp 2
        let m1 = compile("m1", COUNTER).unwrap(); // stamp 3
        assert_eq!(calls(&m1), 1); // stamp 4
        let rest: Vec<Module> = (2..16) // stamps 5..18
            .map(|i| compile(&format!("m{i}"), COUNTER).unwrap())
            .collect();
        assert_eq!(engine_count(), 16);
        assert_eq!(calls(&m0), 2); // stamp 19
        let m16 = compile("m16", COUNTER).unwrap(); // stamp 20: m1 (4) goes
        assert_eq!(engine_count(), 16);
        assert_eq!(calls(&m0), 3, "m0 was used after m1, so it was kept");
        assert_eq!(
            calls(&m1),
            1,
            "m1 was the least recently used, so it was evicted and reloaded"
        );
        drop((rest, m16));
    })
    .join()
    .expect("the thread finished");
}

/// What `__warn` collects while the top level evaluates is the compile's,
/// unframed, and never reaches a frame.
#[test]
fn a_top_level_warning_is_the_compiles() {
    std::thread::spawn(|| {
        let source = format!("const logo = asset(\"x\");\n{RENDER}");
        let module = compile("top-level-asset", &source).unwrap();
        let expected = format!(
            "asset(\"x\") is not in graphics/assets/; the folder has: {}",
            shared().asset_names().join(", ")
        );
        let warnings = module.warnings();
        assert_eq!(warnings.len(), 1, "{warnings:?}");
        assert_eq!(warnings[0].message, expected);
        assert_eq!(warnings[0].level, Level::Warning);
        assert_eq!(
            (warnings[0].frame, warnings[0].line, warnings[0].column),
            (None, None, None)
        );
        let (_, frame) = draw(&module);
        assert!(
            !frame.iter().any(|w| w.message.starts_with("asset(\"x\")")),
            "{frame:?}"
        );
        let plain = compile("plain", RENDER).unwrap();
        assert!(plain.warnings().is_empty(), "{:?}", plain.warnings());
    })
    .join()
    .expect("the thread finished");
}
