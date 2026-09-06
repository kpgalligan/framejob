//! Black-box tests for `rc_op_names` — the op table published through the
//! C surface.
//!
//! The export exists so the host can check its MCP tool catalog covers every
//! row of the table (`AgentServer.catalogParityFailure` in
//! `app/Sources/AgentServer.swift`). That check is only worth anything if
//! the list it reads is the SAME list `rc_project_apply` dispatches on, so
//! what these tests assert is that identity rather than the contents: every
//! reported name is an op the envelope knows, and a name the envelope does
//! not know is not reported. The oracle is the dispatcher itself — no
//! spelling of the table is written down here.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, take_string, Handle};
use reelcut_core::ffi_query::rc_op_names;
use reelcut_core::OP_NAMES;

/// The export's answer, parsed. Every call frees the string it read, which
/// is the header's rule for every `char *` the library hands back.
fn reported_names() -> Vec<String> {
    let text = take_string(unsafe { rc_op_names() }).expect("rc_op_names is never NULL");
    let value: Value = serde_json::from_str(&text)
        .unwrap_or_else(|e| panic!("rc_op_names is not valid json: {e}\n{text}"));
    let array = value
        .as_array()
        .unwrap_or_else(|| panic!("rc_op_names must answer an array, got {text}"))
        .clone();
    array
        .into_iter()
        .map(|name| match name {
            Value::String(text) => text,
            other => panic!("rc_op_names must answer strings, got {other}"),
        })
        .collect()
}

#[test]
fn every_reported_name_is_a_distinct_non_empty_string() {
    let names = reported_names();
    assert!(!names.is_empty(), "the op table is never empty");
    for name in &names {
        assert!(!name.is_empty(), "an op name is never empty");
        assert_eq!(
            name.trim(),
            name,
            "op name {name:?} carries surrounding whitespace"
        );
    }
    let mut sorted = names.clone();
    sorted.sort();
    sorted.dedup();
    assert_eq!(
        sorted.len(),
        names.len(),
        "rc_op_names repeated an op: {names:?}"
    );
}

/// The export is a VIEW of the dispatcher's list, not a second copy of it.
/// `{"op": name}` with no arguments is normally an `Err` about a missing
/// field — what matters is that it is never the "unknown op" error, which
/// is the only answer a name the envelope does not know can produce.
#[test]
fn every_reported_name_is_an_op_the_envelope_knows() {
    let project = Handle::new(1920, 1080, 30, 1);
    for name in reported_names() {
        let answer = project.try_apply(&json!({ "op": name }));
        if let Err(message) = answer {
            assert!(
                !message.contains("unknown op"),
                "rc_op_names reports {name:?}, which rc_project_apply rejects as unknown"
            );
        }
    }
}

/// The other direction: a name the export does NOT report is refused, and
/// refused with the same list — so the two cannot have drifted apart while
/// both still looking healthy.
#[test]
fn a_name_the_export_does_not_report_is_an_unknown_op() {
    let names = reported_names();
    let project = Handle::new(1920, 1080, 30, 1);
    let message = project.errors(&json!({"op": "add_shape_clipp", "track": 1, "at": 0}));
    assert_contains(&message, "unknown op \"add_shape_clipp\"");
    for name in &names {
        assert_contains(&message, name);
    }
}

/// The shim neither reorders nor truncates the table: the C answer is the
/// crate constant, in the order the module doc lists it. (The constant is
/// the one thing a Rust test may read directly — `edit_tests.rs` drives its
/// coverage check off the same one.)
#[test]
fn the_export_is_the_op_table_in_table_order() {
    assert_eq!(reported_names(), OP_NAMES.to_vec());
}

/// Called twice, it answers the same thing twice — it holds no state and
/// leaks nothing the caller cannot free.
#[test]
fn the_export_is_stable_across_calls() {
    assert_eq!(reported_names(), reported_names());
}
