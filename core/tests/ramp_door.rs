//! `set_action_end`'s `speed` (spec §6, §11 SR-10) and the slot rule
//! (SR-2): the refusals of `set_action_end`, `set_action` and
//! `remove_action` when a ramp would read past its media's end.
//!
//! Pinned here, through the FFI: `speed` stored clamped to ×0.1–×1000; a
//! `null` removing it; `off: ["speed"]` refused as any path that is not
//! `group.key`; the two errors (a value that is not a number, a clip that is
//! not a media clip); R1, R2 and R3 in their whole sentences, the numbers
//! in them from oracles written here; each named rate or end then fitting;
//! and no ramp edit moving the clip's start or duration.

mod common;

use serde_json::{json, Value};

use common::{at, int, Handle};

/// Ticks per second and per 30 fps frame (spec §5.1), written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

/// One media clip 11 at 1 s on track 2, from `in`, at `speed`, whose
/// media is `file` ticks long, with `actions`.
fn project(file: i64, duration: i64, source_in: i64, speed: f64, actions: Value) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/door.mov", "kind": "video", "duration": file,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": SEC, "duration": duration,
            "source": { "kind": "media", "media": 1, "in": source_in },
            "speed": speed, "actions": actions
        }],
        "next_id": 100
    })
}

fn action(id: u32, start: i64, duration: i64, end: Value) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": "linear", "end": end })
}

fn end_op(action: u32, patch: Value) -> Value {
    json!({ "op": "set_action_end", "clip": 11, "action": action, "patch": patch })
}

fn stored_end(handle: &Handle) -> Value {
    at(&handle.value(), "/clips/0/actions/0/end").clone()
}

/// The clip's start and duration are what they were.
fn slot_kept(handle: &Handle, duration: i64) {
    let value = handle.value();
    assert_eq!(int(&value, "/clips/0/start"), SEC);
    assert_eq!(int(&value, "/clips/0/duration"), duration);
}

/// A long media and one action [1 s, 2 s) on a 2 s clip, empty end.
fn roomy() -> Handle {
    Handle::from_value(&project(
        600 * SEC,
        2 * SEC,
        0,
        1.0,
        json!([action(21, SEC, SEC, json!({}))]),
    ))
}

#[test]
fn speed_is_stored_clamped_and_a_null_removes_it() {
    let fast = roomy().apply(&end_op(21, json!({ "speed": 5000 })));
    assert_eq!(stored_end(&fast), json!({ "speed": 1000.0 }));
    slot_kept(&fast, 2 * SEC);
    let slow = roomy().apply(&end_op(21, json!({ "speed": 0.01 })));
    assert_eq!(stored_end(&slow), json!({ "speed": 0.1 }));
    let two = roomy().apply(&end_op(
        21,
        json!({ "speed": 2, "video": { "opacity": 0.5 } }),
    ));
    assert_eq!(
        stored_end(&two),
        json!({ "speed": 2.0, "video": { "opacity": 0.5 } })
    );
    let removed = two.apply(&end_op(21, json!({ "speed": null })));
    assert_eq!(stored_end(&removed), json!({ "video": { "opacity": 0.5 } }));
    slot_kept(&removed, 2 * SEC);
}

#[test]
fn off_cannot_name_speed() {
    let message = roomy().errors(&json!({
        "op": "set_action_end", "clip": 11, "action": 21, "patch": {}, "off": ["speed"]
    }));
    assert_eq!(
        message,
        "off path \"speed\" must be \"group.key\", a group of video, audio or text and one of \
         its top-level keys"
    );
}

#[test]
fn speed_must_be_a_number_on_a_media_clip() {
    for (value, said) in [
        (json!("fast"), "\"fast\""),
        (json!(true), "true"),
        (json!([2]), "[2]"),
        (json!({ "rate": 2 }), "{\"rate\":2}"),
    ] {
        assert_eq!(
            roomy().errors(&end_op(21, json!({ "speed": value }))),
            format!("speed must be a number, not {said}")
        );
    }
    let mut text = project(
        600 * SEC,
        2 * SEC,
        0,
        1.0,
        json!([action(21, 0, SEC, json!({}))]),
    );
    text["clips"][0]["source"] = json!({ "kind": "text" });
    text["clips"][0]["text"] = json!({ "content": "Hi" });
    let handle = Handle::from_value(&text);
    assert_eq!(
        handle.errors(&end_op(21, json!({ "speed": 2 }))),
        "clip 11 is not a media clip, and only a media clip's action can end at a speed"
    );
}

/// M4's fixture: an 11 s media, a 6 s clip at in 0, action 21 linear over
/// the whole clip, so S(D) = 3 s + 3x s for an end rate x.
fn eleven() -> Handle {
    Handle::from_value(&project(
        11 * SEC,
        6 * SEC,
        0,
        1.0,
        json!([action(21, 0, 6 * SEC, json!({}))]),
    ))
}

#[test]
fn r1_names_the_largest_end_rate_that_fits_and_it_applies() {
    // ×3 reads 12 s, a second past the end; (11 − 3) / 3 = 2.6666…, floored.
    eleven().refuses_with(
        &end_op(21, json!({ "speed": 3 })),
        "ending action 21 at ×3 would read clip 11 600000 ticks past the end of its media; \
         the largest end rate that fits is ×2.666",
    );
    let fits = eleven().apply(&end_op(21, json!({ "speed": 2.666 })));
    assert_eq!(stored_end(&fits), json!({ "speed": 2.666 }));
    slot_kept(&fits, 6 * SEC);
    // ×2.667 reads 3 + 8.001 s, past 11 s.
    eleven().refuses(&end_op(21, json!({ "speed": 2.667 })));
}

#[test]
fn r2_names_the_latest_end_when_no_rate_fits() {
    // A hand-written ×2 clip, 6 s from in 0 of a 10.5 s media, action 21
    // over [5 s, 6 s): S(5 s) = 10 s whatever the end rate, so none fits.
    let handle = Handle::from_value(&project(
        21 * SEC / 2,
        6 * SEC,
        0,
        2.0,
        json!([action(21, 5 * SEC, SEC, json!({}))]),
    ));
    // At ×5: S(D) = 10 s + (2 + 5) / 2 s = 13.5 s, 3 s over.
    let over = 27 * SEC / 2 - 21 * SEC / 2;
    // At ×0.1, S = 10.5 s inside the ramp: 2u − 0.95u² = 0.5.
    let u = (2.0 - (4.0f64 - 1.9).sqrt()) / 1.9;
    let fits = 5 * SEC + (u * SEC as f64).floor() as i64;
    let end = SEC + fits - (SEC + fits) % FRAME;
    handle.refuses_with(
        &end_op(21, json!({ "speed": 5 })),
        &format!(
            "ending action 21 at ×5 would read clip 11 {over} ticks past the end of its media, \
             and no end rate down to ×0.1 fits; at ×0.1 the latest clip end that fits is {end} \
             ticks"
        ),
    );
    // That end fits at ×0.1, and a frame more does not.
    let s = |t: i64| {
        let t = (t - SEC) as f64;
        let inside = (t - 5.0 * SEC as f64) / SEC as f64;
        10.0 * SEC as f64 + (2.0 * inside - 0.95 * inside * inside) * SEC as f64
    };
    assert!(s(end).round() as i64 <= 21 * SEC / 2);
    assert!(s(end + FRAME).round() as i64 > 21 * SEC / 2);
}

#[test]
fn r1_names_an_exact_fit_when_the_file_ends_on_a_whole_rate() {
    // D2's case: a 5 s media, a 2 s clip, one action over it, S(D) = 1 s +
    // x s, so exactly ×4 fits.
    let five = Handle::from_value(&project(
        5 * SEC,
        2 * SEC,
        0,
        1.0,
        json!([action(21, 0, 2 * SEC, json!({}))]),
    ));
    five.refuses_with(
        &end_op(21, json!({ "speed": 5 })),
        "ending action 21 at ×5 would read clip 11 600000 ticks past the end of its media; \
         the largest end rate that fits is ×4",
    );
    let fits = five.apply(&end_op(21, json!({ "speed": 4 })));
    slot_kept(&fits, 2 * SEC);
}

/// `eleven` with the end at ×2.666 (S(D) = 10.998 s).
fn eleven_fitted() -> Handle {
    eleven().apply(&end_op(21, json!({ "speed": 2.666 })))
}

#[test]
fn r3_refuses_a_retime_naming_the_latest_end() {
    // [0, 3 s) linear to ×2.666, then held 3 s: S = 5.499 s + 7.998 s.
    let s = |t: f64| {
        if t <= 3.0 {
            t + (2.666 - 1.0) * t * t / 6.0
        } else {
            5.499 + 2.666 * (t - 3.0)
        }
    };
    let over = (s(6.0) * SEC as f64).round() as i64 - 11 * SEC;
    let fits = ((3.0 + (11.0 - 5.499) / 2.666) * SEC as f64).floor() as i64;
    let end = SEC + fits - (SEC + fits) % FRAME;
    eleven_fitted().refuses_with(
        &json!({ "op": "set_action", "clip": 11, "action": 21, "duration": 3 * SEC }),
        &format!(
            "retiming action 21 would read clip 11 {over} ticks past the end of its media; \
             the latest clip end that fits is {end} ticks"
        ),
    );
    let clip_end = |e: i64| (e - SEC) as f64 / SEC as f64;
    assert!((s(clip_end(end)) * SEC as f64).round() as i64 <= 11 * SEC);
    assert!((s(clip_end(end + FRAME)) * SEC as f64).round() as i64 > 11 * SEC);
    // A retime that keeps it inside applies, and the slot stays.
    let moved = eleven_fitted().apply(&json!({
        "op": "set_action", "clip": 11, "action": 21, "curve": "ease_in"
    }));
    slot_kept(&moved, 6 * SEC);
}

/// A ×2 clip, 3 s from in 0 of a 3 s media, slowed by action 21 over
/// [0, 1 s) to ×0.5: S = 1.25 s + 1 s. Without it, 6 s.
fn slowed() -> Handle {
    Handle::from_value(&project(
        3 * SEC,
        3 * SEC,
        0,
        2.0,
        json!([action(21, 0, SEC, json!({ "speed": 0.5 }))]),
    ))
}

#[test]
fn r3_refuses_removing_a_rate_action_or_its_end_rate() {
    // At ×2 the 3 s media lasts 1.5 s of clip.
    let end = SEC + 3 * SEC / 2;
    slowed().refuses_with(
        &json!({ "op": "remove_action", "clip": 11, "action": 21 }),
        &format!(
            "removing action 21 would read clip 11 {} ticks past the end of its media; the \
             latest clip end that fits is {end} ticks",
            3 * SEC
        ),
    );
    slowed().refuses_with(
        &end_op(21, json!({ "speed": null })),
        &format!(
            "removing action 21's end rate would read clip 11 {} ticks past the end of its \
             media; the latest clip end that fits is {end} ticks",
            3 * SEC
        ),
    );
    // Another key of that end is no rate edit, and applies.
    let other = slowed().apply(&end_op(21, json!({ "video": { "opacity": 0.5 } })));
    slot_kept(&other, 3 * SEC);
}

#[test]
fn removing_an_action_with_no_rate_is_never_refused_for_the_media() {
    // The same overrunning ×2 clip with an opacity action: not a rate edit.
    let handle = Handle::from_value(&project(
        3 * SEC,
        3 * SEC,
        0,
        2.0,
        json!([action(21, 0, SEC, json!({ "video": { "opacity": 0.5 } }))]),
    ));
    let removed = handle.apply(&json!({ "op": "remove_action", "clip": 11, "action": 21 }));
    slot_kept(&removed, 3 * SEC);
}
