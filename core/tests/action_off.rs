//! `set_action_end`'s `off` — an optional property keyed OFF at an action's
//! end (spec §5.4, §6, §11 CI-14).
//!
//! A `null` in the op's `patch` REMOVES a key from the end state; the only
//! way to STORE one, which the evaluator switches to at the action's end, is
//! an `off` path. These tests hold the op to that from outside, through the
//! FFI: what it writes, what the evaluator makes of it, what it refuses and
//! in whose words, and that a hand-written `end` cannot make it panic.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, at, take_string, Handle, Outcome};
use framejob_core::ffi_query::rc_op_schemas;

/// Ticks per second (spec §5.1), written out so a change to the timescale
/// fails here rather than moving with the test.
const SEC: i64 = 600_000;

/// One media clip (11) with a base shadow and one action (21) over its
/// first two seconds, whose end state is `end`.
fn project_with_end(end: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 9,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": {
                "shadow": { "x": 0.0, "y": 8.0, "blur": 12.0, "color": [0.0, 0.0, 0.0, 0.5] }
            },
            "actions": [{ "id": 21, "start": 0, "duration": 2 * SEC,
                          "curve": "linear", "end": end }]
        }],
        "next_id": 22
    }))
}

fn project() -> Handle {
    project_with_end(json!({}))
}

/// `set_action_end` on the fixture's one action.
fn op(patch: Value, off: Value) -> Value {
    json!({ "op": "set_action_end", "clip": 11, "action": 21, "patch": patch, "off": off })
}

/// The stored end state of action 21.
fn end(handle: &Handle) -> Value {
    at(&handle.value(), "/clips/0/actions/0/end").clone()
}

#[test]
fn off_stores_a_null_the_evaluator_switches_to_at_the_end() {
    let before = project();
    let after = before.apply(&op(json!({}), json!(["video.shadow"])));
    assert_eq!(end(&after), json!({ "video": { "shadow": null } }));

    let at_end = after.clip_state(11, 2 * SEC).expect("clip 11 has a state");
    assert!(
        at(&at_end, "/video/shadow").is_null(),
        "the shadow is still on at the action's end: {at_end}"
    );
    let midway = after.clip_state(11, SEC).expect("clip 11 has a state");
    assert!(
        at(&midway, "/video/shadow").is_object(),
        "a switch holds until the end, but the shadow is gone midway: {midway}"
    );
}

#[test]
fn off_refuses_a_required_key_naming_the_path() {
    let message = project().errors(&op(json!({}), json!(["video.opacity"])));
    assert_contains(&message, "video.opacity");
    assert!(!message.contains("internal error:"), "{message}");
}

#[test]
fn off_refuses_what_the_patch_refuses_in_the_ops_own_words() {
    let project = project();
    assert_eq!(
        project.errors(&op(json!({}), json!(["video.motion"]))),
        "video.motion is not an animation target"
    );
    assert_eq!(
        project.errors(&op(json!({}), json!(["text.words"]))),
        "text.words is not an animation target"
    );
}

#[test]
fn off_refuses_a_malformed_path_an_unknown_group_and_a_nested_key() {
    let project = project();
    for path in [
        "video",
        "shape.radius",
        "video.shadow.blur",
        "video.blurr",
        ".x",
        "video.",
    ] {
        let message = project.errors(&op(json!({}), json!([path])));
        assert!(!message.contains("internal error:"), "{path}: {message}");
    }
    assert_contains(
        &project.errors(&op(json!({}), json!(["shape.radius"]))),
        "unknown key \"shape\"",
    );
    assert_contains(
        &project.errors(&op(json!({}), json!(["video.blurr"]))),
        "unknown key \"blurr\"",
    );
}

#[test]
fn off_refuses_a_path_the_patch_also_names() {
    let message = project().errors(&op(
        json!({ "video": { "shadow": { "blur": 1.0 } } }),
        json!(["video.shadow"]),
    ));
    assert_contains(&message, "video.shadow");
}

#[test]
fn a_null_off_is_absent() {
    match project().try_apply(&op(json!({}), Value::Null)) {
        Ok(Outcome::Identity) => {}
        other => panic!("{{patch: {{}}, off: null}} should be an identity, got {other:?}"),
    }
}

#[test]
fn a_non_object_group_slot_is_replaced_not_indexed() {
    let before = project_with_end(json!({ "video": 5 }));
    match before.try_apply(&op(json!({}), json!(["video.shadow"]))) {
        Ok(Outcome::Applied(after)) => {
            assert_eq!(end(&after), json!({ "video": { "shadow": null } }));
        }
        Err(message) => panic!("expected an applied edit, got an error: {message}"),
        other => panic!("expected an applied edit, got {other:?}"),
    }
}

#[test]
fn a_second_off_is_an_identity_and_a_later_patch_replaces_the_null() {
    let once = project().apply(&op(json!({}), json!(["video.shadow"])));
    match once.try_apply(&op(json!({}), json!(["video.shadow"]))) {
        Ok(Outcome::Identity) => {}
        other => panic!("a second off of the same path should be an identity, got {other:?}"),
    }
    let back = once.apply(&op(
        json!({ "video": { "shadow": { "blur": 1.0 } } }),
        json!([]),
    ));
    assert_eq!(
        end(&back),
        json!({ "video": { "shadow": { "blur": 1.0 } } })
    );
}

#[test]
fn a_patch_null_is_still_a_removal() {
    let keyed = project().apply(&op(json!({}), json!(["video.shadow"])));
    let removed = keyed.apply(&op(json!({ "video": { "shadow": null } }), json!([])));
    assert_eq!(end(&removed), json!({ "video": {} }));
}

#[test]
fn the_published_schema_carries_off() {
    let text = take_string(unsafe { rc_op_schemas() }).expect("rc_op_schemas is never NULL");
    let schemas: Value = serde_json::from_str(&text).expect("rc_op_schemas is json");
    assert_eq!(
        schemas["set_action_end"]["properties"]["off"],
        json!({ "type": "array", "items": { "type": "string" } })
    );
    let required = schemas["set_action_end"]["required"]
        .as_array()
        .expect("required is a list");
    assert!(!required.contains(&json!("off")), "off is optional");
}
