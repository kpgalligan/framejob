//! Black-box tests for `rc_op_schemas` — every op's ARGUMENTS published
//! through the C surface as JSON Schema.
//!
//! The export exists so the MCP tool catalog can print the core's structure
//! instead of restating it, which is only worth anything if what comes out
//! of the C surface is the table the core dispatches on. So what these
//! tests assert is that IDENTITY, in both directions — every op in the
//! table has a schema, no schema names an op the table has not got, every
//! schema declares that op's arguments and only them, and each argument is
//! published as its `Kind` says — rather than the contents of any
//! particular tool. `core/tests/op_names.rs` is the prior art, and this is
//! the same shape one level in.
//!
//! **The chain, and which link each file holds.** `op_table.rs`'s rows are
//! proved against the decoder itself in `core/tests/op_table.rs` — an
//! argument the op has not got makes serde answer with the ones it has, a
//! required one left out is answered `missing field`, a wrong kind is
//! answered with the type it wanted. This file holds the other link: that
//! the table reaches the C surface unbent. Neither writes a second spelling
//! of the op table down for the first to be compared against, and
//! [`every_published_name_is_an_op_the_envelope_knows`] ties the published
//! names to the dispatcher directly, so the chain does not rest on
//! `OP_NAMES` alone.
//!
//! [`expected`] is a deliberate second spelling, and it is of the
//! kind→schema MAPPING rather than of the table: a test that asked the core
//! for the schema of a kind would agree with any mapping at all. Its match
//! is exhaustive for the reason every match on `Kind` in these tests is — a
//! kind added to the table does not compile until this file says what JSON
//! it is — and [`all_twenty_kinds_are_carried_by_an_argument`] is what
//! stops a kind being published wrongly with no argument standing on it to
//! notice. `tools/proof/op_schema_probe.py` carries a THIRD, of twelve
//! representative rows: it is another process in another language reading
//! the app's wrapper, so it cannot import either of these, and a mapping
//! edited in one place is caught by the other two.

mod common;

use serde_json::{json, Map, Value};

use common::{take_string, Handle};
use framejob_core::ffi_query::rc_op_schemas;
use framejob_core::op_table::{Argument, Kind, OpRow, OP_NAMES, OP_TABLE};

/// The export's answer, parsed. Every call frees the string it read, which
/// is the header's rule for every `char *` the library hands back.
fn published() -> Map<String, Value> {
    let text = take_string(unsafe { rc_op_schemas() }).expect("rc_op_schemas is never NULL");
    let value: Value = serde_json::from_str(&text)
        .unwrap_or_else(|e| panic!("rc_op_schemas is not valid json: {e}\n{text}"));
    match value {
        Value::Object(map) => map,
        other => panic!("rc_op_schemas must answer an object, got {other}"),
    }
}

/// One op's published schema.
fn schema<'a>(map: &'a Map<String, Value>, row: &OpRow) -> &'a Value {
    map.get(row.name)
        .unwrap_or_else(|| panic!("no schema published for {:?}", row.name))
}

/// One op's published properties.
fn properties<'a>(map: &'a Map<String, Value>, row: &OpRow) -> &'a Map<String, Value> {
    match schema(map, row).get("properties") {
        Some(Value::Object(properties)) => properties,
        other => panic!("{}: properties must be an object, got {other:?}", row.name),
    }
}

/// The row an op's name names.
fn row(name: &str) -> OpRow {
    *OP_TABLE
        .iter()
        .find(|row| row.name == name)
        .unwrap_or_else(|| panic!("no row for {name:?}"))
}

/// What an argument must publish: its kind, narrowed by its bound where
/// the table gives it one.
///
/// A bound REPLACES the kind's own `minimum`, which for the two canvas
/// dimensions means 16 rather than `Kind::Id`'s 0 — the smaller claim, and
/// the one the core enforces. Written out here rather than asked of the
/// core, so a bound that reached the table and not the schema is named.
fn expected(argument: &Argument) -> Value {
    let mut schema = expected_kind(argument.kind);
    if let (Some(bound), Some(object)) = (argument.bound, schema.as_object_mut()) {
        object.insert("minimum".to_string(), json!(bound.min));
        object.insert("maximum".to_string(), json!(bound.max));
    }
    schema
}

/// What each kind must publish, written out here rather than asked of the
/// core. A closed vocabulary's MEMBERS are read from `Kind::values` on
/// purpose: which members there are is proved against the decoder in
/// `core/tests/op_table.rs`, and the claim here is that they reach the
/// schema, in that order, under `enum`.
fn expected_kind(kind: Kind) -> Value {
    let whole = json!({"type": "integer", "minimum": 0});
    match kind {
        Kind::Ticks => json!({"type": "integer"}),
        Kind::Id | Kind::Index => whole,
        Kind::Ids => json!({"type": "array", "items": whole}),
        Kind::Ranges => json!({
            "type": "array",
            "items": {
                "type": "array", "items": {"type": "integer"},
                "minItems": 2, "maxItems": 2,
            },
        }),
        Kind::Number => json!({"type": "number"}),
        Kind::Boolean => json!({"type": "boolean"}),
        Kind::Text => json!({"type": "string"}),
        Kind::Texts => json!({"type": "array", "items": {"type": "string"}}),
        Kind::Object => json!({"type": "object"}),
        Kind::Color => json!({
            "type": "array", "items": {"type": "number"},
            "minItems": 4, "maxItems": 4,
        }),
        Kind::FrameRate => json!({
            "type": "array", "items": whole, "minItems": 2, "maxItems": 2,
        }),
        Kind::Transition
        | Kind::Alignment
        | Kind::Curve
        | Kind::Fit
        | Kind::Matte
        | Kind::Output => {
            json!({"type": "string", "enum": kind.values()})
        }
        Kind::Groups => json!({
            "type": "array",
            "items": {"type": "string", "enum": kind.values()},
        }),
        Kind::Region => json!({
            "type": "object",
            "properties": {
                "x": {"type": "number"}, "y": {"type": "number"},
                "width": {"type": "number"}, "height": {"type": "number"},
            },
            "required": ["x", "y", "width", "height"],
            "additionalProperties": false,
        }),
    }
}

// ---- the map -------------------------------------------------------------

/// Both directions at once: the published keys ARE the op table's names. An
/// op with no schema is a tool the catalog could not build out of this; a
/// schema for a name the table has not got is a tool for an op that does
/// not exist.
#[test]
fn every_op_has_a_schema_and_no_other_name_does() {
    let mut names: Vec<String> = published().keys().cloned().collect();
    names.sort();
    let mut table: Vec<String> = OP_NAMES.iter().map(|name| name.to_string()).collect();
    table.sort();
    assert_eq!(
        names, table,
        "rc_op_schemas and the op table name different ops"
    );
}

/// The published names are not merely `OP_NAMES` — they are ops
/// `rc_project_apply` dispatches on. `{"op": name}` with no arguments is
/// normally an `Err` about a missing field; what matters is that it is
/// never the "unknown op" error, the one answer a name the envelope does
/// not know can give.
#[test]
fn every_published_name_is_an_op_the_envelope_knows() {
    let project = Handle::new(1920, 1080, 30, 1);
    for name in published().keys() {
        if let Err(message) = project.try_apply(&json!({ "op": name })) {
            assert!(
                !message.contains("unknown op"),
                "rc_op_schemas publishes {name:?}, which rc_project_apply rejects as unknown"
            );
        }
    }
}

/// Called twice, it answers the same thing twice — it holds no state and
/// leaks nothing the caller cannot free.
#[test]
fn the_export_is_stable_across_calls() {
    assert_eq!(published(), published());
}

// ---- one op's schema -----------------------------------------------------

/// Every schema is a JSON-Schema object whose properties are the row's
/// arguments, in both directions: an argument with no property is one an
/// agent cannot send, and a property with no argument is one the core would
/// refuse as an unknown field on the first call.
#[test]
fn every_schema_declares_its_arguments_and_only_them() {
    let map = published();
    for op in &OP_TABLE {
        assert_eq!(
            schema(&map, op).get("type"),
            Some(&json!("object")),
            "{}: a schema is an object",
            op.name
        );
        let mut declared: Vec<String> = properties(&map, op).keys().cloned().collect();
        declared.sort();
        let mut arguments: Vec<String> = op
            .arguments
            .iter()
            .map(|argument| argument.name.to_string())
            .collect();
        arguments.sort();
        assert_eq!(
            declared, arguments,
            "{}: the published properties are not the table's arguments",
            op.name
        );
    }
}

/// `required` is the arguments the decoder will not do without, in table
/// order — and it is written even when it is empty, so a reader never has
/// to tell "this op requires nothing" from "the key was left out".
#[test]
fn required_is_what_the_table_requires_in_table_order() {
    let map = published();
    for op in &OP_TABLE {
        let required = schema(&map, op)
            .get("required")
            .unwrap_or_else(|| panic!("{}: no required list", op.name));
        let table: Vec<&str> = op
            .arguments
            .iter()
            .filter(|argument| argument.required)
            .map(|argument| argument.name)
            .collect();
        assert_eq!(
            required,
            &json!(table),
            "{}: the published required list is not the table's",
            op.name
        );
    }
}

/// The envelope's `scope` is not an argument of any op (`core/src/scope.rs`)
/// and the catalog injects it over every op tool's schema, so a `scope`
/// published HERE would be the core claiming an argument no op has. Its
/// sibling `project` is the app's own key and belongs here even less.
#[test]
fn no_schema_carries_an_envelope_key() {
    let map = published();
    for op in &OP_TABLE {
        // Membership, not a substring of the serialized list: an argument
        // named `projects` would pass one and fail the other.
        let required: Vec<&str> = schema(&map, op)["required"]
            .as_array()
            .unwrap_or_else(|| panic!("{}: required must be an array", op.name))
            .iter()
            .map(|name| name.as_str().expect("required holds strings"))
            .collect();
        for key in ["scope", "project"] {
            assert!(
                !properties(&map, op).contains_key(key),
                "{}: {key:?} is an envelope key, not an argument",
                op.name
            );
            assert!(
                !required.contains(&key),
                "{}: {key:?} is named in required",
                op.name
            );
        }
    }
}

// ---- the kinds -----------------------------------------------------------

/// Every argument of every op, against [`expected`] — which is where an
/// id's `minimum: 0`, a vocabulary's `enum` and a pair's `maxItems` come
/// from now, instead of from a hand-written property in the catalog.
#[test]
fn every_argument_is_published_as_its_kind_says() {
    let map = published();
    for op in &OP_TABLE {
        let properties = properties(&map, op);
        for argument in op.arguments {
            assert_eq!(
                properties[argument.name],
                expected(argument),
                "{}.{}: published as the wrong kind",
                op.name,
                argument.name
            );
        }
    }
}

/// The test above only reaches a kind some argument HAS, so this is what
/// says none is sitting unexercised: the number of DISTINCT kinds in use is
/// `Kind`'s whole variant count, which by the pigeonhole is every one of
/// them. The 20 is that variant count, written here because Rust will not
/// count an enum's arms for a test; the exhaustive matches in
/// `op_schema.rs` and in [`expected`] are what keep it honest, since a
/// kind added to the vocabulary does not compile until both say what it is.
#[test]
fn all_twenty_kinds_are_carried_by_an_argument() {
    let mut kinds: Vec<Kind> = Vec::new();
    for op in &OP_TABLE {
        for argument in op.arguments {
            if !kinds.contains(&argument.kind) {
                kinds.push(argument.kind);
            }
        }
    }
    assert_eq!(kinds.len(), 20, "the kinds in use are {kinds:?}");
}

/// A closed vocabulary publishes its members and nothing else does — which
/// is what makes "pick a legal value out of the schema" possible for the
/// six scalar vocabularies and the one list, and unfakeable for anything
/// else: an `enum` on an id would be a vocabulary the core has not got.
#[test]
fn only_a_closed_vocabulary_publishes_an_enum() {
    let map = published();
    for op in &OP_TABLE {
        let properties = properties(&map, op);
        for argument in op.arguments {
            let schema = &properties[argument.name];
            // A vocabulary is either the value itself or the member type of
            // a list of them (`paste_attributes`' groups).
            let enumerated = match schema.get("enum").or_else(|| schema.pointer("/items/enum")) {
                Some(Value::Array(members)) => members.clone(),
                _ => Vec::new(),
            };
            let members: Vec<Value> = argument
                .kind
                .values()
                .iter()
                .map(|member| json!(member))
                .collect();
            assert_eq!(
                enumerated, members,
                "{}.{}: the published enum is not the kind's members",
                op.name, argument.name
            );
        }
    }
}

/// A caller-authored **patch** is published as an object with NO declared
/// properties: the schema says an object belongs there and says nothing
/// about what may be in it, because deepening D1 made the core the one
/// validator of that, one step further in (`patch.rs`). The opposite case
/// is beside it — a `ZoomRegion`'s four members ARE declared by the core
/// and refused by name (`edit_zoom.rs`), so they are printed and the object
/// is closed.
#[test]
fn a_patch_is_opaque_and_a_region_is_not() {
    let map = published();

    let patch = &properties(&map, &row("set_video"))["patch"];
    assert_eq!(patch, &json!({"type": "object"}));
    assert!(
        patch.get("properties").is_none(),
        "a patch declares no properties: {patch}"
    );

    let region = &properties(&map, &row("add_zoom_action"))["region"];
    assert_eq!(region["type"], json!("object"));
    assert_eq!(region["required"], json!(["x", "y", "width", "height"]));
    assert_eq!(region["additionalProperties"], json!(false));
}
