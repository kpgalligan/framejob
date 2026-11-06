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

// ---- an EQ slot keyed off (spec §11 AU-88) ---------------------------------

/// Clip 11 with a base high-pass and a band 2, and one linear action (21)
/// over its first two seconds, whose end state is `end`.
fn eq_project(end: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 35,
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
            "audio": { "eq": {
                "high_pass": { "frequency": 1000.0, "slope": 24 },
                "band_2": { "frequency": 1000.0, "gain_db": 0.0, "q": 1.0 }
            } },
            "actions": [{ "id": 21, "start": 0, "duration": 2 * SEC,
                          "curve": "linear", "end": end }]
        }],
        "next_id": 22
    }))
}

#[test]
fn off_keys_one_eq_slot_off_at_the_end() {
    let after = eq_project(json!({})).apply(&op(json!({}), json!(["audio.eq.high_pass"])));
    assert_eq!(
        end(&after),
        json!({ "audio": { "eq": { "high_pass": null } } })
    );
    let midway = after.clip_state(11, SEC).expect("clip 11 has a state");
    assert!(
        at(&midway, "/audio/eq/high_pass").is_object(),
        "the high-pass is off before the end: {midway}"
    );
    let at_end = after.clip_state(11, 2 * SEC).expect("clip 11 has a state");
    assert!(
        at_end
            .pointer("/audio/eq/high_pass")
            .is_none_or(Value::is_null),
        "the high-pass is still on at the end: {at_end}"
    );
    assert!(
        at(&at_end, "/audio/eq/band_2").is_object(),
        "keying one slot off took another: {at_end}"
    );
}

#[test]
fn off_keeps_the_other_slots_the_patch_names() {
    let after = eq_project(json!({})).apply(&op(
        json!({ "audio": { "eq": { "band_2": { "gain_db": 6.0 } } } }),
        json!(["audio.eq.high_pass"]),
    ));
    assert_eq!(
        end(&after),
        json!({ "audio": { "eq": { "band_2": { "gain_db": 6.0 }, "high_pass": null } } })
    );
}

#[test]
fn off_refuses_an_unknown_slot_a_deeper_path_and_a_slot_the_patch_names() {
    let project = eq_project(json!({}));
    let bogus = project.errors(&op(json!({}), json!(["audio.eq.bogus"])));
    assert_contains(
        &bogus,
        "\"bogus\" is not one of high_pass, low_shelf, band_1, band_2",
    );
    assert!(!bogus.contains("internal error:"), "{bogus}");
    assert_contains(
        &project.errors(&op(json!({}), json!(["audio.pan.x"]))),
        "off path \"audio.pan.x\" must be \"group.key\"",
    );
    assert_contains(
        &project.errors(&op(json!({}), json!(["audio.eq.band_2.gain_db"]))),
        "must be \"group.key\"",
    );
    assert_contains(
        &project.errors(&op(
            json!({ "audio": { "eq": { "high_pass": { "slope": 12 } } } }),
            json!(["audio.eq.high_pass"]),
        )),
        "\"audio.eq.high_pass\" is named in both the patch and off",
    );
}

// ---- a qualifier range keyed off (spec §11 GR-36) --------------------------

/// Clip 11 as an adjustment clip with all three ranges on, and one linear
/// action (21) over its first two seconds, whose end state is `end`.
fn qualifier_project(end: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 35,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "adjustment" },
            "video": { "qualifier": {
                "hue": { "center": 30.0, "width": 50.0, "softness": 25.0 },
                "saturation": { "low": 0.2, "high": 0.8, "softness": 0.1 },
                "luma": { "low": 0.1, "high": 0.9, "softness": 0.1 }
            } },
            "actions": [{ "id": 21, "start": 0, "duration": 2 * SEC,
                          "curve": "linear", "end": end }]
        }],
        "next_id": 22
    }))
}

#[test]
fn off_keys_each_qualifier_range_off_at_the_end_and_keeps_the_others() {
    for (range, others) in [
        ("hue", ["saturation", "luma"]),
        ("saturation", ["hue", "luma"]),
        ("luma", ["hue", "saturation"]),
    ] {
        let path = format!("video.qualifier.{range}");
        let after = qualifier_project(json!({})).apply(&op(json!({}), json!([path])));
        assert_eq!(
            end(&after),
            json!({ "video": { "qualifier": { range: null } } })
        );
        let midway = after.clip_state(11, SEC).expect("clip 11 has a state");
        let pointer = format!("/video/qualifier/{range}");
        assert!(
            at(&midway, &pointer).is_object(),
            "{range} went off before the end: {midway}"
        );
        let at_end = after.clip_state(11, 2 * SEC).expect("clip 11 has a state");
        assert!(
            at_end.pointer(&pointer).is_none_or(Value::is_null),
            "{range} is still on at the end: {at_end}"
        );
        for other in others {
            assert!(
                at(&at_end, &format!("/video/qualifier/{other}")).is_object(),
                "keying {range} off took {other}: {at_end}"
            );
        }
    }
}

#[test]
fn off_keeps_the_range_a_patch_writes_beside_it() {
    let after = qualifier_project(json!({})).apply(&op(
        json!({ "video": { "qualifier": { "saturation": { "low": 0.0, "high": 0.3 } } } }),
        json!(["video.qualifier.hue"]),
    ));
    assert_eq!(
        end(&after),
        json!({ "video": { "qualifier": {
            "saturation": { "low": 0.0, "high": 0.3 }, "hue": null
        } } })
    );
}

#[test]
fn a_ramp_on_a_range_gives_way_to_its_off_and_a_later_patch_replaces_the_null() {
    let ramped = qualifier_project(json!({ "video": { "qualifier": {
        "hue": { "center": 90.0 }
    } } }));
    let off = ramped.apply(&op(json!({}), json!(["video.qualifier.hue"])));
    assert_eq!(
        end(&off),
        json!({ "video": { "qualifier": { "hue": null } } })
    );
    let back = off.apply(&op(
        json!({ "video": { "qualifier": { "hue": {} } } }),
        json!([]),
    ));
    assert_eq!(
        end(&back),
        json!({ "video": { "qualifier": { "hue": {} } } })
    );
}

#[test]
fn off_refuses_an_unknown_range_a_value_a_deeper_path_and_a_range_the_patch_names() {
    let project = qualifier_project(json!({}));
    for (path, third) in [
        ("video.qualifier.bogus", "bogus"),
        ("video.qualifier.invert", "invert"),
        ("video.qualifier.blur", "blur"),
    ] {
        assert_eq!(
            project.errors(&op(json!({}), json!([path]))),
            format!(
                "off path \"{path}\" names no qualifier range: \"{third}\" is not one of hue, \
                 saturation, luma"
            )
        );
    }
    assert_contains(
        &project.errors(&op(json!({}), json!(["video.qualifier.hue.center"]))),
        "must be \"group.key\"",
    );
    assert_contains(
        &project.errors(&op(
            json!({ "video": { "qualifier": { "hue": { "center": 90.0 } } } }),
            json!(["video.qualifier.hue"]),
        )),
        "\"video.qualifier.hue\" is named in both the patch and off",
    );
    let whole = project.errors(&op(json!({}), json!(["video.qualifier"])));
    assert_contains(&whole, "cannot key \"video.qualifier\" off");
    assert!(!whole.contains("internal error:"), "{whole}");
}
