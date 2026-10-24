//! Speed ramps SR5 (spec §11 SR-21 (b), SR-22): what the inspector reads of
//! a ramp and what `set_action` lets a person do to an action past its
//! clip's end (#338).
//!
//! Pinned here, through the FFI: `rc_project_clip_state`'s top-level `speed`
//! — a constant clip's own rate, a clip that is not media at its base, a
//! linear ×1 → ×2 ramp at mid-span, at its end tick and after it, and a
//! past-end ramp at its end tick reading the rate at the clip's end — beside
//! the keys it always answered; and SR-22's rule on a constant trimmed clip
//! (a curve, the same span and an earlier end still past the clip apply; a
//! longer one and a later start are refused in their whole sentences), an
//! in-clip action pushed past refused as before, and a ramped past-end speed
//! action re-curved. Every number is an oracle written here: the linear
//! rate is r(t) = r0 + (r1 − r0)·(t − a)/(b − a) over the action [a, b).

mod common;

use serde_json::{json, Value};

use common::{at, by_id, int, num, text, Handle, Outcome};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
/// Where clip 11 starts on the timeline.
const START: i64 = SEC;

/// Clip 11 at 1 s, `duration` long from `in` 0, at `speed`, over a 600 s
/// media with sound, with `actions`.
fn project(duration: i64, speed: f64, actions: Value) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/inspector.mov", "kind": "video",
            "duration": 600 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": START, "duration": duration,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "speed": speed, "video": {}, "audio": {}, "actions": actions
        }],
        "next_id": 100
    })
}

fn action(id: u32, start: i64, duration: i64, curve: &str, end: Value) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": curve, "end": end })
}

/// `clip_state`'s `speed` for clip 11 at CLIP time `t`.
fn speed_at(handle: &Handle, t: i64) -> f64 {
    let state = handle
        .clip_state(11, START + t)
        .expect("clip 11 has a state");
    num(&state, "/speed")
}

fn set_action(fields: Value) -> Value {
    let mut op = json!({ "op": "set_action", "clip": 11, "action": 21 });
    if let (Some(op), Some(fields)) = (op.as_object_mut(), fields.as_object()) {
        for (key, value) in fields {
            op.insert(key.clone(), value.clone());
        }
    }
    op
}

/// Action 21's stored start, duration and curve.
fn span(handle: &Handle) -> (i64, i64, String) {
    let value = handle.value();
    let clip = by_id(&value, "/clips", 11);
    let stored = by_id(clip, "/actions", 21);
    (
        int(stored, "/start"),
        int(stored, "/duration"),
        text(stored, "/curve").to_string(),
    )
}

#[test]
fn a_constant_clip_answers_its_own_rate_beside_the_keys_it_always_answered() {
    let handle = Handle::from_value(&project(4 * SEC, 1.5, json!([])));
    assert_eq!(speed_at(&handle, SEC / 2), 1.5);
    let state = handle.clip_state(11, START + SEC / 2).expect("a state");
    let mut keys: Vec<&str> = state
        .as_object()
        .expect("an object")
        .keys()
        .map(String::as_str)
        .collect();
    keys.sort_unstable();
    assert_eq!(
        keys,
        [
            "audio",
            "clip",
            "graphic",
            "in_action",
            "shape",
            "speed",
            "t",
            "text",
            "video"
        ]
    );
}

#[test]
fn a_clip_that_is_not_media_answers_its_base_whatever_its_actions_say() {
    let mut value = project(
        4 * SEC,
        1.0,
        json!([action(21, 0, SEC, "linear", json!({ "speed": 3.0 }))]),
    );
    value["clips"][0]["source"] = json!({ "kind": "text" });
    value["clips"][0]["text"] = json!({ "content": "Hi" });
    let handle = Handle::from_value(&value);
    assert_eq!(speed_at(&handle, SEC / 2), 1.0);
    assert_eq!(speed_at(&handle, 2 * SEC), 1.0);
}

#[test]
fn a_linear_ramp_reads_its_rate_mid_span_at_its_end_and_after() {
    // [0, 2 s) ×1 → ×2: r(1 s) = 1 + 1·(1/2) = 1.5, then held at ×2.
    let handle = Handle::from_value(&project(
        4 * SEC,
        1.0,
        json!([action(21, 0, 2 * SEC, "linear", json!({ "speed": 2.0 }))]),
    ));
    assert_eq!(speed_at(&handle, SEC), 1.5);
    assert_eq!(speed_at(&handle, 2 * SEC), 2.0);
    assert_eq!(speed_at(&handle, 3 * SEC), 2.0);
}

#[test]
fn a_ramp_past_the_clip_s_end_reads_the_rate_at_the_end_at_its_end_tick() {
    // A 2 s clip holding [0, 4 s) ×1 → ×3: at its end tick, 4 s, the core
    // reads the clip's last rate, r(2 s) = 1 + 2·(2/4) = 2, not the ×3 it
    // names — which is why the inspector shows the stored end rate first.
    let handle = Handle::from_value(&project(
        2 * SEC,
        1.0,
        json!([action(21, 0, 4 * SEC, "linear", json!({ "speed": 3.0 }))]),
    ));
    assert_eq!(speed_at(&handle, 4 * SEC), 2.0);
}

/// A constant 1.5 s clip whose action 21 runs [1 s, 2 s), past its end, as
/// `trim_end` leaves one.
fn trimmed() -> Handle {
    Handle::from_value(&project(
        3 * SEC / 2,
        1.0,
        json!([action(
            21,
            SEC,
            SEC,
            "linear",
            json!({ "video": { "opacity": 0.5 } })
        )]),
    ))
}

#[test]
fn an_action_past_the_end_can_be_re_curved_kept_or_pulled_in() {
    let curved = trimmed().apply(&set_action(json!({ "curve": "ease_in" })));
    assert_eq!(span(&curved), (SEC, SEC, "ease_in".to_string()));

    // The same span changes nothing: an identity, not a refusal.
    match trimmed()
        .try_apply(&set_action(json!({ "start": SEC, "duration": SEC })))
        .expect("a valid op")
    {
        Outcome::Identity => {}
        Outcome::Applied(_) => panic!("the same span applied a change"),
        Outcome::Refused(why) => panic!("the same span was refused: {why}"),
    }

    // Moved earlier, its end 1.8 s still past the clip's 1.5 s: applies.
    let earlier = trimmed().apply(&set_action(json!({ "start": 480_000 })));
    assert_eq!(span(&earlier), (480_000, SEC, "linear".to_string()));

    // Shortened to 0.4 s, ending at 1.4 s, inside: applies.
    let shorter = trimmed().apply(&set_action(json!({ "duration": 240_000 })));
    assert_eq!(span(&shorter), (SEC, 240_000, "linear".to_string()));
}

#[test]
fn an_action_past_the_end_cannot_be_taken_further_out() {
    // Longer: 1.2 s from 1 s ends at 2.2 s, past the 2 s it ended at.
    trimmed().refuses_with(
        &set_action(json!({ "duration": 720_000 })),
        "an action of 720000 ticks at 600000 would end at 1320000, past clip 11's own end \
         at 900000 ticks",
    );
    // Later: from 1.2 s it ends at 2.2 s.
    trimmed().refuses_with(
        &set_action(json!({ "start": 720_000 })),
        "an action of 600000 ticks at 720000 would end at 1320000, past clip 11's own end \
         at 900000 ticks",
    );
}

#[test]
fn an_action_inside_the_clip_is_refused_past_its_end_as_before() {
    // [0.2 s, 1.2 s) on the 1.5 s clip, moved to 0.6 s: it would end at 1.6 s.
    let inside = Handle::from_value(&project(
        3 * SEC / 2,
        1.0,
        json!([action(21, 120_000, SEC, "linear", json!({}))]),
    ));
    inside.refuses_with(
        &set_action(json!({ "start": 360_000 })),
        "an action of 600000 ticks at 360000 would end at 960000, past clip 11's own end \
         at 900000 ticks",
    );
}

#[test]
fn a_ramped_speed_action_past_the_end_can_be_re_curved() {
    let handle = Handle::from_value(&project(
        2 * SEC,
        1.0,
        json!([action(21, 0, 4 * SEC, "linear", json!({ "speed": 3.0 }))]),
    ));
    let curved = handle.apply(&set_action(json!({ "curve": "ease_out" })));
    assert_eq!(span(&curved), (0, 4 * SEC, "ease_out".to_string()));
    let value = curved.value();
    let clip = by_id(&value, "/clips", 11);
    assert_eq!(int(clip, "/duration"), 2 * SEC);
    assert_eq!(num(at(clip, "/actions/0"), "/end/speed"), 3.0);
}
