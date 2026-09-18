//! Black-box tests for `crate::op_table` — every op's arguments, as data.
//!
//! The table is a published interface: the tool catalog will read it rather
//! than restate it, so a row that claims an argument the op does not have,
//! or claims the wrong kind for one, is a lie an agent finds out about on
//! its first call. **The instrument here is the decoder itself**, never a
//! second list written beside the first:
//!
//! - an argument the op does not have makes serde answer with the arguments
//!   it DOES have, and that answer is compared to the row in both
//!   directions;
//! - a required argument left out makes it answer `missing field`, and
//!   every argument the row calls optional is one the baseline envelope —
//!   which carries none of them — is read without complaint;
//! - a value of another json kind makes it answer with the kind it wanted,
//!   and a closed vocabulary handed a non-member answers with its whole
//!   list.
//!
//! **How a wrong kind is attributed to its argument.** `Op` is internally
//! tagged, so serde buffers each variant's content and re-reads it through
//! a deserializer of its own; `serde_path_to_error` gets no path out of
//! that (it answers `.`), which is why a wrong-type refusal here names the
//! TYPE it wanted and not the field. The attribution is therefore built
//! rather than read: every probe is the op's baseline envelope — which
//! [`every_required_argument_is_missed_and_every_optional_one_is_not`]
//! proves the decoder reads — with exactly ONE argument replaced, so the
//! only thing that can have failed is the one this test changed.
//!
//! The one kind with no wrong value is [`Kind::Object`]: a caller-authored
//! patch is `serde_json::Value` and the decoder takes any json at all,
//! which is what "opaque" MEANS here and what the last test asserts.
//! Deepening D1 made the core the one validator of what a patch may carry,
//! one step further in.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, Handle};
use reelcut_core::op_table::{Kind, OpRow, OP_COUNT, OP_NAMES, OP_TABLE};

/// The project every probe is applied to. Its contents do not matter: a
/// probe reads the DECODER's answer, and an op that decodes and then fails
/// on an unknown id has already answered the only question asked here.
fn project() -> Handle {
    Handle::new(1920, 1080, 30, 1)
}

/// What the decoder said about `op`, or `None` when it read it.
///
/// `parse` quotes every decode failure under the op's own name, which is
/// what tells a serde refusal apart from an edit's `Err` about an unknown
/// id — the answers this test must not confuse.
fn decoded(project: &Handle, name: &str, op: &Value) -> Option<String> {
    let prefix = format!("op \"{name}\" is not valid: ");
    let Err(message) = project.try_apply(op) else {
        return None;
    };
    match message.strip_prefix(&prefix) {
        Some(rest) => Some(rest.to_string()),
        None => {
            assert!(
                !message.contains("is not valid:"),
                "{name}: a decode failure under another op's name: {message}"
            );
            None
        }
    }
}

/// [`decoded`], asserting the decoder refused.
fn refusal(project: &Handle, name: &str, op: &Value) -> String {
    decoded(project, name, op)
        .unwrap_or_else(|| panic!("{name}: the decoder read this, and should not have: {op}"))
}

/// The names serde lists after the offender it names first — the fields it
/// expected, or the variants it expected. `unknown field \`x\`, expected
/// one of \`a\`, \`b\`` for three or more, `expected \`a\` or \`b\`` for
/// two, `expected \`a\`` for one, `there are no fields` for none.
fn listed(message: &str) -> Vec<String> {
    let (_, tail) = message
        .split_once("`, ")
        .unwrap_or_else(|| panic!("serde named nothing in: {message}"));
    if tail.starts_with("there are no fields") {
        return vec![];
    }
    tail.split('`')
        .skip(1)
        .step_by(2)
        .map(String::from)
        .collect()
}

/// A value of the kind an argument takes. Plausible is not the point —
/// only the JSON KIND is, because everything past the decoder is some other
/// test's business. Exhaustive, like every other match on [`Kind`] here: a
/// kind added to the table does not compile until this file says how to
/// prove it.
fn value_of(kind: Kind) -> Value {
    match kind {
        Kind::Ticks => json!(0),
        Kind::Id => json!(1),
        Kind::Index => json!(0),
        Kind::Ids => json!([]),
        Kind::Ranges => json!([]),
        Kind::Number => json!(1.0),
        Kind::Boolean => json!(false),
        Kind::Text => json!("x"),
        Kind::Object => json!({}),
        Kind::Color => json!([0.0, 0.0, 0.0, 1.0]),
        Kind::FrameRate => json!([30, 1]),
        Kind::Region => json!({"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0}),
        Kind::Groups => json!([]),
        Kind::Transition | Kind::Alignment | Kind::Curve | Kind::Fit => json!(kind.values()[0]),
    }
}

/// The wrong values a kind is proved by, each with the phrase serde answers
/// them with. A vocabulary is proved by [`listed`] instead, so it carries
/// only the probe that shows it must be a string at all.
fn wrong_values(kind: Kind) -> Vec<(Value, String)> {
    let wrong = |value: Value, expected: &str| (value, expected.to_string());
    match kind {
        Kind::Ticks => vec![wrong(json!("soon"), "expected i64")],
        Kind::Id => vec![wrong(json!("one"), "expected u32")],
        Kind::Index => vec![wrong(json!("one"), "expected usize")],
        Kind::Ids => vec![
            wrong(json!("all"), "expected a sequence"),
            wrong(json!(["one"]), "expected u32"),
        ],
        Kind::Ranges => vec![
            wrong(json!("all"), "expected a sequence"),
            wrong(json!([1]), "expected an array of length 2"),
        ],
        Kind::Number => vec![wrong(json!("fast"), "expected f64")],
        Kind::Boolean => vec![wrong(json!("yes"), "expected a boolean")],
        Kind::Text => vec![wrong(json!(5), "expected a string")],
        Kind::Color => vec![wrong(json!("white"), "expected an array of length 4")],
        Kind::FrameRate => vec![wrong(json!("thirty"), "expected an array of length 2")],
        Kind::Region => vec![wrong(json!([0, 0, 1, 1]), "expected an object, not")],
        Kind::Groups => vec![wrong(json!("video"), "expected a sequence")],
        Kind::Object => vec![],
        Kind::Transition | Kind::Alignment | Kind::Curve | Kind::Fit => {
            vec![wrong(json!(5), "expected string or map")]
        }
    }
}

/// The op envelope carrying every REQUIRED argument and no optional one.
fn baseline(row: &OpRow) -> Value {
    let mut op = json!({ "op": row.name });
    let object = op.as_object_mut().expect("json! built an object");
    for argument in row.arguments.iter().filter(|a| a.required) {
        object.insert(argument.name.to_string(), value_of(argument.kind));
    }
    op
}

/// [`baseline`] with one argument set to `value`.
fn with(row: &OpRow, name: &str, value: Value) -> Value {
    let mut op = baseline(row);
    op.as_object_mut()
        .expect("baseline is an object")
        .insert(name.to_string(), value);
    op
}

/// [`baseline`] without `name`.
fn without(row: &OpRow, name: &str) -> Value {
    let mut op = baseline(row);
    op.as_object_mut()
        .expect("baseline is an object")
        .remove(name);
    op
}

// ---- the table's shape ---------------------------------------------------

/// `OP_NAMES` is a VIEW of the table, which is what lets `rc_op_names`, the
/// envelope's "known ops are …" sentence and the catalog parity check go on
/// reading one list while the arguments arrive beside them.
#[test]
fn the_names_are_the_tables_names_and_nothing_is_written_twice() {
    assert_eq!(OP_TABLE.len(), OP_COUNT);
    let names: Vec<&str> = OP_TABLE.iter().map(|row| row.name).collect();
    assert_eq!(
        names,
        OP_NAMES.to_vec(),
        "OP_NAMES is not the table's names"
    );

    let mut sorted = names.clone();
    sorted.sort_unstable();
    sorted.dedup();
    assert_eq!(sorted.len(), names.len(), "an op has two rows: {names:?}");

    for row in &OP_TABLE {
        let mut seen: Vec<&str> = row.arguments.iter().map(|a| a.name).collect();
        let count = seen.len();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(
            seen.len(),
            count,
            "{}: an argument is listed twice",
            row.name
        );
    }
}

// ---- the arguments -------------------------------------------------------

/// The decoder, handed an argument no op has, answers with the arguments
/// the op DOES have — in declaration order. That answer is the row, and
/// this compares the two whole, so an argument the table invented and an
/// argument the table forgot are both a failure here.
#[test]
fn the_decoder_lists_exactly_the_arguments_the_table_lists() {
    let project = project();
    for row in &OP_TABLE {
        let op = with(row, "not_an_argument", json!(1));
        let message = refusal(&project, row.name, &op);
        assert_contains(&message, "unknown field `not_an_argument`");
        let expected: Vec<String> = row.arguments.iter().map(|a| a.name.to_string()).collect();
        assert_eq!(
            listed(&message),
            expected,
            "{}: the decoder's arguments are not the table's",
            row.name
        );
    }
}

/// Required-ness, both ways round: leaving out an argument the table calls
/// required is answered `missing field`, naming it; and the baseline —
/// which carries NONE of the optional ones — is read without complaint, so
/// an argument called optional that the decoder really needs fails here.
#[test]
fn every_required_argument_is_missed_and_every_optional_one_is_not() {
    let project = project();
    for row in &OP_TABLE {
        let base = baseline(row);
        if let Some(message) = decoded(&project, row.name, &base) {
            panic!("{}: the baseline was refused: {message}\n{base}", row.name);
        }
        for argument in row.arguments {
            if argument.required {
                let message = refusal(&project, row.name, &without(row, argument.name));
                assert_eq!(
                    message,
                    format!("missing field `{}`", argument.name),
                    "{}: {} is required in the table",
                    row.name,
                    argument.name
                );
            } else {
                let op = with(row, argument.name, value_of(argument.kind));
                if let Some(message) = decoded(&project, row.name, &op) {
                    panic!(
                        "{}: {} was refused with a value of its own kind: {message}",
                        row.name, argument.name
                    );
                }
            }
        }
    }
}

/// Each argument's KIND, by sending a value of another json kind into the
/// baseline the test above proved readable — so the one thing that can have
/// failed is the argument this replaced. The decoder answers with the type
/// it wanted, and that phrase is the kind's own.
#[test]
fn every_argument_is_refused_a_value_of_another_kind() {
    let project = project();
    for row in &OP_TABLE {
        for argument in row.arguments {
            for (value, expected) in wrong_values(argument.kind) {
                let op = with(row, argument.name, value.clone());
                let message = refusal(&project, row.name, &op);
                assert!(
                    message.contains(&expected),
                    "{}: {} handed {value} was refused with {message:?}, \
                     which never says {expected:?}",
                    row.name,
                    argument.name
                );
            }
        }
    }
}

/// A closed vocabulary handed a value it does not have answers with the
/// whole list, and the list is the kind's. The table can therefore not
/// claim `curve` where the decoder reads a transition kind, nor carry a
/// member the decoder has never heard of.
#[test]
fn every_closed_vocabulary_answers_with_its_own_members() {
    let project = project();
    for row in &OP_TABLE {
        for argument in row.arguments.iter().filter(|a| !a.kind.values().is_empty()) {
            let members: Vec<String> = argument
                .kind
                .values()
                .iter()
                .map(|v| v.to_string())
                .collect();
            let sent = match argument.kind {
                Kind::Groups => json!(["not_a_member"]),
                _ => json!("not_a_member"),
            };
            let message = refusal(&project, row.name, &with(row, argument.name, sent));
            assert_contains(&message, "unknown variant `not_a_member`");
            assert_eq!(
                listed(&message),
                members,
                "{}: {} is not the vocabulary the table names",
                row.name,
                argument.name
            );
        }
    }
}

/// A published BOUND is a rule the core refuses outside, and the proof is
/// the core's own refusal: each end is put to it one step out and the
/// answer must name the range — WITH its two numbers, which is what makes
/// a bound retyped a digit off a failure here rather than a promise an
/// agent finds out about.
///
/// The ends themselves are sent too, and must not draw that answer. They
/// are not asserted to APPLY: a bounded argument on a clip op would still
/// meet an unknown id in this blank project, and the claim being made is
/// about the range and nothing else.
///
/// **A bound nothing enforces must not be published**, which is the half
/// this test is really for: `set_speed`'s `rate` CLAMPS to 0.1–10 rather
/// than refusing, so a row that published it would fail here at the first
/// probe — the core would apply 0.05 and say nothing.
#[test]
fn every_published_bound_is_one_the_core_refuses_outside() {
    let project = project();
    let mut proved = 0;
    for row in &OP_TABLE {
        for argument in row.arguments {
            let Some(bound) = argument.bound else {
                continue;
            };
            proved += 1;
            let range = format!("must be between {} and {}", bound.min, bound.max);
            for outside in [i64::from(bound.min) - 1, i64::from(bound.max) + 1] {
                let op = with(row, argument.name, json!(outside));
                let message = project.try_apply(&op).expect_err(&format!(
                    "{}: {} took {outside}, which the published bound says is outside \
                     {}–{}",
                    row.name, argument.name, bound.min, bound.max
                ));
                assert_contains(&message, &range);
                assert_contains(&message, &format!("not {outside}"));
            }
            for end in [bound.min, bound.max] {
                let op = with(row, argument.name, json!(end));
                if let Err(message) = project.try_apply(&op) {
                    assert!(
                        !message.contains(&range),
                        "{}: {} refused {end}, which its own published bound calls legal: \
                         {message}",
                        row.name,
                        argument.name
                    );
                }
            }
        }
    }
    assert!(
        proved > 0,
        "no argument carries a bound — this test would pass on an empty table"
    );
}

/// An opaque object is opaque: the decoder takes a string where a patch
/// belongs, and whatever refuses it refuses it further in. That is the
/// claim `Kind::Object` makes, and it would stop being true the moment a
/// patch argument grew a type of its own — which is exactly when the table
/// would have to stop saying "object".
#[test]
fn an_opaque_object_is_read_whatever_json_kind_it_is() {
    let project = project();
    let mut seen = 0;
    for row in &OP_TABLE {
        for argument in row.arguments.iter().filter(|a| a.kind == Kind::Object) {
            seen += 1;
            for sent in [json!("a string"), json!(7), json!([1, 2])] {
                let op = with(row, argument.name, sent.clone());
                if let Some(message) = decoded(&project, row.name, &op) {
                    panic!(
                        "{}: {} is not opaque — the decoder refused {sent}: {message}",
                        row.name, argument.name
                    );
                }
            }
        }
    }
    assert!(seen > 0, "no argument claims to be an opaque object");
}
