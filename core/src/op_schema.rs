//! The op table as JSON SCHEMA — what `rc_op_schemas` publishes (spec §6,
//! road map 7's D3).
//!
//! `op_table.rs` says what an op TAKES in the core's own vocabulary; this
//! module writes that vocabulary in the one dialect a caller outside the
//! process can read, so the tool catalog can print the core's structure
//! instead of restating it. The two are separate modules because they
//! change for different reasons — a row changes when an OP does, this
//! function when the published DIALECT does — and because the table's
//! 400-line cap is not a budget to spend on a wire format.
//!
//! **The match over [`Kind`] is EXHAUSTIVE**, like `Kind::values` and
//! `scope.rs`'s `refused_inside`: a kind added to the table does not
//! compile until this file says what JSON it is. A catch-all would publish
//! a new kind as whatever the fallback happened to be, and every test
//! below would agree with it.
//!
//! ### What a schema deliberately does not say
//!
//! - **What an argument is FOR.** The core says what an argument IS; the
//!   prose naming the menu item a tool mirrors, and the app state a default
//!   comes from, is the catalog's and stays there (spec
//!   kpgalligan/reelcut#14's Out of Scope).
//! - **What a caller-authored patch may carry.** [`Kind::Object`] is
//!   `{"type": "object"}` with no `properties`: deepening D1 made the core
//!   the one validator of a caller's patch, one step further in, and a
//!   schema listing its keys would be that validator restated somewhere it
//!   could drift from. The `"object"` is not the DECODER's rule — the field
//!   is a `serde_json::Value` and takes any json at all — it is the op's,
//!   whose door refuses a non-object in the words that name the group
//!   (`patch.rs`). [`Kind::Region`] is the deliberate opposite: a
//!   `ZoomRegion`'s four members are DECLARED by the core and refused by
//!   name (`edit_zoom.rs`), so they are printed, `required` and closed.
//! - **`additionalProperties` on an OP**, because the catalog merges the
//!   envelope's `project` and `scope` keys in after reading this, and a
//!   closed object would refuse the two keys every tool carries. `scope` is
//!   not an argument of any op (`scope.rs`) and appears nowhere here.
//! - **Nullability.** `set_transition`'s `kind: null` clears and
//!   `add_zoom_action`'s `region: null` is a zoom BACK; that a null MEANS
//!   something is semantics, which is `edit.rs`'s doc table, and the two
//!   tools that offer it say so in their own prose today.
//!
//! **Nothing here is the authority either.** `op_table.rs`'s rows are, and
//! they answer to the decoder in `core/tests/op_table.rs`; this module is
//! tested through the FFI in `core/tests/op_schemas.rs`, which compares
//! what came out of `rc_op_schemas` to the table it was made from.

use serde_json::{json, Map, Value};

use crate::op_table::{Argument, Kind, OpRow, OP_TABLE};

/// Every op's arguments as JSON Schema, keyed by op name: the whole table
/// in one object, in `OP_TABLE` order. The keys are exactly `OP_NAMES` —
/// the same list `rc_op_names` answers, which is what lets a reader join
/// the two without a third spelling of either.
pub fn op_schemas() -> Value {
    let mut schemas = Map::new();
    for row in &OP_TABLE {
        schemas.insert(row.name.to_string(), schema_of(row));
    }
    Value::Object(schemas)
}

/// One row: an object whose properties are the op's arguments and whose
/// `required` names the ones the decoder will not do without, in table
/// order.
///
/// `required` is written even when it is empty, so a reader never has to
/// tell "this op requires nothing" from "the key was left out" — the
/// catalog's `tool` helper has always emitted an empty list for the same
/// reason.
fn schema_of(row: &OpRow) -> Value {
    let mut properties = Map::new();
    for argument in row.arguments {
        properties.insert(argument.name.to_string(), schema_of_argument(argument));
    }
    let required: Vec<&str> = row
        .arguments
        .iter()
        .filter(|argument| argument.required)
        .map(|argument| argument.name)
        .collect();
    json!({
        "type": "object",
        "properties": Value::Object(properties),
        "required": required,
    })
}

/// One argument as JSON Schema: its [`Kind`], narrowed by its [`Bound`]
/// where the table gives it one.
///
/// A bound is written as `minimum` and `maximum` over whatever the kind
/// already said, which for the two canvas dimensions REPLACES the `0` that
/// [`Kind::Id`] carries — 16 is the smaller claim and the true one. It is
/// published only where the core refuses outside it (`op_table.rs`'s rule),
/// so a caller may read these two numbers as a rule and not as advice.
///
/// [`Bound`]: crate::op_table::Bound
fn schema_of_argument(argument: &Argument) -> Value {
    let mut schema = schema_of_kind(argument.kind);
    if let (Some(bound), Some(object)) = (argument.bound, schema.as_object_mut()) {
        object.insert("minimum".to_string(), json!(bound.min));
        object.insert("maximum".to_string(), json!(bound.max));
    }
    schema
}

/// One kind as JSON Schema — the constraint the catalog writes by hand for
/// every property today, derived from the table instead.
fn schema_of_kind(kind: Kind) -> Value {
    // An id, a track index and the two terms of a frame rate are `u32`,
    // `usize` and `u32`: one thing to a schema, a whole number that cannot
    // be negative. `Ticks` is an `i64` and deliberately carries no minimum
    // — a `delta`, a `slip` and a `roll` are negative every working day.
    let whole = json!({"type": "integer", "minimum": 0});
    match kind {
        Kind::Ticks => json!({"type": "integer"}),
        Kind::Id | Kind::Index => whole,
        Kind::Ids => json!({"type": "array", "items": whole}),
        // The silence cut's `[from, to]` pairs: an array of two-element
        // arrays, whose LENGTH is part of what the decoder refuses.
        Kind::Ranges => json!({
            "type": "array",
            "items": {
                "type": "array",
                "items": {"type": "integer"},
                "minItems": 2,
                "maxItems": 2,
            },
        }),
        Kind::Number => json!({"type": "number"}),
        Kind::Boolean => json!({"type": "boolean"}),
        Kind::Text => json!({"type": "string"}),
        Kind::Texts => json!({"type": "array", "items": {"type": "string"}}),
        Kind::Object => json!({"type": "object"}),
        Kind::Color => json!({
            "type": "array",
            "items": {"type": "number"},
            "minItems": 4,
            "maxItems": 4,
        }),
        Kind::FrameRate => json!({
            "type": "array",
            "items": whole,
            "minItems": 2,
            "maxItems": 2,
        }),
        // A closed vocabulary's members, from the core's own list — the
        // `enum` an agent picks a legal value out of without guessing, and
        // the one part of a schema the catalog could never derive.
        Kind::Transition | Kind::Alignment | Kind::Curve | Kind::Fit => {
            json!({"type": "string", "enum": kind.values()})
        }
        Kind::Groups => json!({
            "type": "array",
            "items": {"type": "string", "enum": kind.values()},
        }),
        Kind::Region => json!({
            "type": "object",
            "properties": {
                "x": {"type": "number"},
                "y": {"type": "number"},
                "width": {"type": "number"},
                "height": {"type": "number"},
            },
            "required": ["x", "y", "width", "height"],
            // The one place the core knows enough to close an object:
            // `ZoomRegion`'s `Deserialize` is `deny_unknown_fields` with no
            // defaults, so a `widht` is refused beside the four it takes.
            "additionalProperties": false,
        }),
    }
}
