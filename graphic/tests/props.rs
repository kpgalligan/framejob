//! G-4's overlay (road map 10 §5c): stored props laid over the schema's
//! defaults at render time, never refused — every surprise a warning.

mod common;

use graphic::{overlay, Diagnostic, Level, Module};
use serde_json::{json, Value};

use common::{shared, BUDGET_MS};

fn schema() -> Value {
    json!({
        "title": {"type": "string", "default": "Jane"},
        "size": {"type": "number", "default": 64},
        "boxed": {"type": "boolean", "default": true},
        "accent": {"type": "color", "default": "#ff5a36"},
        "align": {"type": "enum", "default": "left", "options": ["left", "center", "right"]},
        "logo": {"type": "asset", "default": null},
    })
}

fn keys(value: &Value) -> Vec<&str> {
    value
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect()
}

fn messages(warnings: &[Diagnostic]) -> Vec<&str> {
    warnings.iter().map(|w| w.message.as_str()).collect()
}

#[test]
fn defaults_fill_the_schemas_order() {
    let (props, warnings) = overlay(&schema(), &json!({"align": "right", "title": "B"}));
    assert_eq!(
        keys(&props),
        ["title", "size", "boxed", "accent", "align", "logo"]
    );
    assert_eq!(
        props,
        json!({"title": "B", "size": 64, "boxed": true, "accent": "#ff5a36", "align": "right", "logo": null})
    );
    assert!(warnings.is_empty(), "{warnings:?}");
}

#[test]
fn a_stale_key_is_passed_through_with_a_warning() {
    let (props, warnings) = overlay(&schema(), &json!({"old": 3, "title": "B"}));
    assert_eq!(props["old"], json!(3));
    assert_eq!(keys(&props).last(), Some(&"old"));
    assert_eq!(
        messages(&warnings),
        ["props.old is not in the schema; it is passed through"]
    );
    assert!(warnings.iter().all(|w| w.level == Level::Warning));
}

#[test]
fn a_wrong_type_is_the_default_with_a_warning() {
    let (props, warnings) = overlay(
        &schema(),
        &json!({"title": 5, "size": "big", "boxed": null, "accent": [1], "logo": {"a": 1}}),
    );
    assert_eq!(props, overlay(&schema(), &json!({})).0);
    assert_eq!(
        messages(&warnings),
        [
            "props.title is a number but the schema says string; the default \"Jane\" is used",
            "props.size is a string but the schema says number; the default 64 is used",
            "props.boxed is null but the schema says boolean; the default true is used",
            "props.accent is an array but the schema says color; the default \"#ff5a36\" is used",
            "props.logo is an object but the schema says asset; the default null is used",
        ]
    );
}

#[test]
fn an_empty_asset_is_handed_as_null() {
    let (props, warnings) = overlay(&schema(), &json!({"logo": "", "title": ""}));
    assert_eq!(props["logo"], Value::Null);
    assert_eq!(props["title"], json!(""));
    assert!(warnings.is_empty(), "{warnings:?}");
    // CONTROL: a named image is handed as it is.
    let (props, warnings) = overlay(&schema(), &json!({"logo": "x.png"}));
    assert_eq!(props["logo"], json!("x.png"));
    assert!(warnings.is_empty(), "{warnings:?}");
    // CONTROL: a stale key's `""` is passed through as `""`, with its warning.
    let (props, warnings) = overlay(&schema(), &json!({"gone": ""}));
    assert_eq!(props["gone"], json!(""));
    assert_eq!(
        messages(&warnings),
        ["props.gone is not in the schema; it is passed through"]
    );
}

#[test]
fn an_enum_outside_its_options_is_the_default() {
    let (props, warnings) = overlay(&schema(), &json!({"align": "middle"}));
    assert_eq!(props["align"], json!("left"));
    assert_eq!(
        messages(&warnings),
        ["props.align = \"middle\" is not one of [\"left\",\"center\",\"right\"]; the default \"left\" is used"]
    );
    let (_, warnings) = overlay(&schema(), &json!({"align": true}));
    assert_eq!(
        messages(&warnings),
        ["props.align is a boolean but the schema says enum; the default \"left\" is used"]
    );
}

#[test]
fn stored_props_that_are_not_an_object_are_the_defaults() {
    let (props, warnings) = overlay(&schema(), &json!([]));
    assert_eq!(props, overlay(&schema(), &json!({})).0);
    assert_eq!(
        messages(&warnings),
        ["props is an array, not an object; the defaults are used"]
    );
    let (_, warnings) = overlay(&schema(), &json!("x"));
    assert_eq!(
        messages(&warnings),
        ["props is a string, not an object; the defaults are used"]
    );
}

#[test]
fn through_svg_the_warnings_carry_the_frame() {
    let source = "export const schema = { title: { type: \"string\", default: \"A\" } };\n\
                  export function render(frame, props, ctx) {\n\
                  \x20 return svg(ctx, `<!--${props.title}|${props.old}-->`);\n\
                  }\n";
    let module = Module::compile(shared(), "props", source, BUDGET_MS).unwrap();
    let ctx = common::ctx(9, 30.0, 150, 1920, 1080);
    let (svg, warnings) = graphic::svg(
        &module,
        9,
        &json!({"title": 1, "old": "x"}),
        &ctx,
        BUDGET_MS,
    )
    .unwrap();
    assert!(svg.contains("<!--A|x-->"), "{svg}");
    assert_eq!(
        messages(&warnings),
        [
            "props.title is a number but the schema says string; the default \"A\" is used",
            "props.old is not in the schema; it is passed through",
        ]
    );
    assert!(warnings.iter().all(|w| w.frame == Some(9)));
}
