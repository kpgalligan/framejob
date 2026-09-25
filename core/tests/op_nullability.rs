//! The published optional bit promises omission, not universal JSON nullability.
mod common;

use common::{Handle, Outcome};
use reelcut_core::op_table::{Kind, OpRow, OP_TABLE};
use serde_json::{json, Value};

const PLAIN: [(&str, &str); 4] = [
    ("add_transition", "ripple"),
    ("remove_track", "with_clips"),
    ("remove_media", "with_clips"),
    ("set_canvas", "rescale_clips"),
];

fn sample(kind: Kind) -> Value {
    match kind {
        Kind::Ticks | Kind::Index => json!(1),
        Kind::Id => json!(1),
        Kind::Ids | Kind::Ranges | Kind::Groups => json!([]),
        Kind::Number => json!(1.0),
        Kind::Boolean => json!(false),
        Kind::Text => json!("x"),
        Kind::Texts => json!(["x"]),
        Kind::Object => json!({}),
        Kind::Color => json!([0.0, 0.0, 0.0, 1.0]),
        Kind::FrameRate => json!([30, 1]),
        Kind::Region => json!({"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0}),
        Kind::Transition | Kind::Alignment | Kind::Curve | Kind::Fit => json!(kind.values()[0]),
    }
}

fn baseline(row: &OpRow) -> Value {
    let mut op = json!({"op": row.name});
    for arg in row.arguments.iter().filter(|a| a.required) {
        op[arg.name] = sample(arg.kind);
    }
    op
}

fn probe(handle: &Handle, row: &OpRow, op: &Value, decode_error: bool) {
    let prefix = format!("op \"{}\" is not valid: ", row.name);
    match handle.try_apply(op) {
        Err(message) if decode_error => {
            assert!(message.starts_with(&prefix), "{op}: {message}");
            assert!(!message.contains("internal error:"), "{op}: {message}");
        }
        Err(message) => {
            assert!(!message.starts_with(&prefix), "{op}: {message}");
            assert!(!message.contains("internal error:"), "{op}: {message}");
        }
        Ok(Outcome::Applied(_) | Outcome::Identity | Outcome::Refused(_)) if !decode_error => {}
        other => panic!("{op}: expected decode_error={decode_error}, got {other:?}"),
    }
}

#[test]
fn every_optional_field_has_its_real_null_contract() {
    let handle = Handle::new(640, 360, 30, 1);
    let mut seen = Vec::new();
    for row in OP_TABLE.iter() {
        let base = baseline(row);
        probe(&handle, row, &base, false);
        for arg in row.arguments.iter().filter(|a| !a.required) {
            seen.push((row.name, arg.name));
            let plain = PLAIN.contains(&(row.name, arg.name));
            if plain {
                assert_eq!(arg.kind, Kind::Boolean, "plain exception changed kind");
            }
            let mut with_null = base.clone();
            with_null[arg.name] = Value::Null;
            probe(&handle, row, &with_null, plain);
            let mut with_value = base.clone();
            with_value[arg.name] = sample(arg.kind);
            probe(&handle, row, &with_value, false);
            if arg.kind == Kind::Boolean {
                with_value[arg.name] = json!(true);
                probe(&handle, row, &with_value, false);
            }
        }
    }
    assert_eq!(seen.len(), 61, "optional inventory changed");
    for field in PLAIN {
        assert!(seen.contains(&field), "missing plain bool {field:?}");
    }
    assert_eq!(seen.iter().filter(|x| !PLAIN.contains(x)).count(), 57);
}

#[test]
fn required_boolean_and_scope_are_independent_controls() {
    let handle = Handle::new(640, 360, 30, 1);
    let row = OP_TABLE.iter().find(|r| r.name == "set_reversed").unwrap();
    assert!(row
        .arguments
        .iter()
        .any(|a| a.name == "reversed" && a.required && a.kind == Kind::Boolean));
    let mut op = baseline(row);
    op.as_object_mut().unwrap().remove("reversed");
    probe(&handle, row, &op, true);
    op["reversed"] = Value::Null;
    probe(&handle, row, &op, true);
    for value in [false, true] {
        op["reversed"] = json!(value);
        probe(&handle, row, &op, false);
    }

    let marker = OP_TABLE.iter().find(|r| r.name == "add_marker").unwrap();
    let base = baseline(marker);
    probe(&handle, marker, &base, false);
    let mut scoped = base.clone();
    scoped["scope"] = Value::Null;
    probe(&handle, marker, &scoped, false);
    scoped["scope"] = json!(999);
    let Err(message) = handle.try_apply(&scoped) else {
        panic!("unknown scope applied")
    };
    assert!(
        message.contains("scope") || message.contains("nest"),
        "{message}"
    );
    assert!(!message.contains("internal error:"));
    scoped["scope"] = json!("wrong");
    assert_eq!(
        handle.try_apply(&scoped).unwrap_err(),
        "scope must be a nest id, not \"wrong\""
    );
}
