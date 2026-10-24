//! `add_speed_ramp`, the speed ramp presets (spec §6, §11 SR-23, #340),
//! through the FFI.
//!
//! Pinned here: each shape's spans, curves and end rates, the spans read off
//! an oracle written here (r = (to − from)·(1 − hold)/2 snapped down, never
//! under a frame); the return rate after an earlier speed action (b is the
//! rate in force, not `clip.speed`); hold 0, a hold clamped to 0.9 and the
//! defaults; an action in a dip's hold gap refused naming it; every Err and
//! refusal in its whole sentence; the fit against S(D) = D(1 + x)/2 and then
//! applying; Up with no rate above b that fits; and a constant clip's plan
//! byte-identical across the edit.

mod common;

use serde_json::{json, Value};

use common::{array, at, int, Handle};

/// Ticks per second and per 30 fps frame (spec §5.1), written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

/// Media clip 11 at 1 s on track 2 (`duration` long, from `in` 0, at
/// `speed`, with `actions`) over a media of `file` ticks; a constant media
/// clip 12 on track 3; a text clip 13 on track 3 after it.
fn project(file: i64, duration: i64, speed: f64, actions: Value) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/preset.mov", "kind": "video", "duration": file,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }, {
            "id": 4, "path": "/fixtures/other.mov", "kind": "video", "duration": 600 * SEC,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }, { "id": 3, "name": "Track 2" }],
        "clips": [{
            "id": 11, "track": 2, "start": SEC, "duration": duration,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "speed": speed, "actions": actions, "video": {}, "audio": {}
        }, {
            "id": 12, "track": 3, "start": 0, "duration": 2 * SEC,
            "source": { "kind": "media", "media": 4, "in": SEC }, "video": {}, "audio": {}
        }, {
            "id": 13, "track": 3, "start": 3 * SEC, "duration": SEC,
            "source": { "kind": "text" }, "video": {}, "text": { "content": "Hi" }
        }],
        "next_id": 100
    })
}

/// A 3 s clip over 600 s of media, at ×1, no actions.
fn roomy() -> Handle {
    Handle::from_value(&project(600 * SEC, 3 * SEC, 1.0, json!([])))
}

fn ramp(shape: &str, rate: f64) -> Value {
    json!({ "op": "add_speed_ramp", "clip": 11, "shape": shape, "rate": rate })
}

fn ramp_over(shape: &str, rate: f64, from: i64, to: i64) -> Value {
    let mut op = ramp(shape, rate);
    op["from"] = json!(from);
    op["to"] = json!(to);
    op
}

fn with(mut op: Value, key: &str, value: Value) -> Value {
    op[key] = value;
    op
}

/// The oracle for a dip's or a burst's ramp length.
fn ramp_length(span: i64, hold: f64) -> i64 {
    let raw = (span as f64 * (1.0 - hold) / 2.0) as i64;
    (raw / FRAME * FRAME).max(FRAME)
}

/// Clip 11's actions as (id, start, duration, curve, end).
fn actions(handle: &Handle) -> Vec<(i64, i64, i64, String, Value)> {
    array(&handle.value(), "/clips/0/actions")
        .iter()
        .map(|a| {
            (
                int(a, "/id"),
                int(a, "/start"),
                int(a, "/duration"),
                at(a, "/curve").as_str().unwrap_or("").to_string(),
                at(a, "/end").clone(),
            )
        })
        .collect()
}

fn speed(rate: f64) -> Value {
    json!({ "speed": rate })
}

fn act(
    id: i64,
    start: i64,
    duration: i64,
    curve: &str,
    end: Value,
) -> (i64, i64, i64, String, Value) {
    (id, start, duration, curve.to_string(), end)
}

/// The clip keeps its slot (SR-2).
fn slot_kept(handle: &Handle, duration: i64) {
    let value = handle.value();
    assert_eq!(int(&value, "/clips/0/start"), SEC);
    assert_eq!(int(&value, "/clips/0/duration"), duration);
}

// ---- the shapes -----------------------------------------------------------

#[test]
fn a_ramp_up_over_the_whole_clip_is_one_eased_action() {
    let up = roomy().apply(&ramp("ramp_up", 2.0));
    assert_eq!(
        actions(&up),
        vec![act(100, 0, 3 * SEC, "ease_in_out", speed(2.0))]
    );
    assert_eq!(int(&up.value(), "/next_id"), 101);
    slot_kept(&up, 3 * SEC);
}

#[test]
fn a_ramp_down_over_a_range_takes_its_curve() {
    let op = with(
        ramp_over("ramp_down", 0.5, SEC / 2, 5 * SEC / 2),
        "curve",
        json!("linear"),
    );
    let down = roomy().apply(&op);
    assert_eq!(
        actions(&down),
        vec![act(100, SEC / 2, 2 * SEC, "linear", speed(0.5))]
    );
}

#[test]
fn a_speed_dip_spans_its_hold() {
    let op = with(ramp("speed_dip", 0.5), "hold", json!(0.25));
    let dip = roomy().apply(&op);
    let r = ramp_length(3 * SEC, 0.25);
    assert_eq!(r, 33 * FRAME);
    assert_eq!(
        actions(&dip),
        vec![
            act(100, 0, r, "ease_in_out", speed(0.5)),
            act(101, 3 * SEC - r, r, "ease_in_out", speed(1.0)),
        ]
    );
    assert_eq!(int(&dip.value(), "/next_id"), 102);
    slot_kept(&dip, 3 * SEC);
}

#[test]
fn a_speed_burst_over_a_range_spans_its_hold() {
    let (from, to) = (9 * FRAME, 81 * FRAME);
    let op = with(ramp_over("speed_burst", 3.0, from, to), "hold", json!(0.25));
    let burst = roomy().apply(&op);
    let r = ramp_length(to - from, 0.25);
    assert_eq!(r, 27 * FRAME);
    assert_eq!(
        actions(&burst),
        vec![
            act(100, from, r, "ease_in_out", speed(3.0)),
            act(101, to - r, r, "ease_in_out", speed(1.0)),
        ]
    );
}

#[test]
fn the_return_rate_is_the_rate_in_force_not_the_clips_speed() {
    let earlier = json!([{ "id": 21, "start": 0, "duration": 15 * FRAME, "curve": "linear",
                           "end": { "speed": 2.0 } }]);
    let handle = Handle::from_value(&project(600 * SEC, 3 * SEC, 1.0, earlier));
    let (from, to) = (18 * FRAME, 72 * FRAME);
    let dip = handle.apply(&ramp_over("speed_dip", 0.5, from, to));
    let r = ramp_length(to - from, 0.5);
    let got = actions(&dip);
    assert_eq!(got.len(), 3);
    assert_eq!(got[1], act(100, from, r, "ease_in_out", speed(0.5)));
    assert_eq!(got[2], act(101, to - r, r, "ease_in_out", speed(2.0)));
}

#[test]
fn hold_zero_abuts_and_a_hold_past_the_bound_is_clamped() {
    let abut = roomy().apply(&with(ramp("speed_dip", 0.5), "hold", json!(0)));
    let half = 3 * SEC / 2;
    assert_eq!(
        actions(&abut),
        vec![
            act(100, 0, half, "ease_in_out", speed(0.5)),
            act(101, half, half, "ease_in_out", speed(1.0)),
        ]
    );
    let clamped = roomy().apply(&with(ramp("speed_dip", 0.5), "hold", json!(2)));
    let r = ramp_length(3 * SEC, 0.9);
    assert_eq!(r, 4 * FRAME);
    assert_eq!(actions(&clamped)[0].2, r);
    assert_eq!(actions(&clamped)[1].1, 3 * SEC - r);
}

#[test]
fn the_defaults_are_half_the_span_held_and_ease_in_out() {
    let burst = roomy().apply(&ramp("speed_burst", 2.0));
    let r = ramp_length(3 * SEC, 0.5);
    assert_eq!(r, 22 * FRAME);
    assert_eq!(
        actions(&burst),
        vec![
            act(100, 0, r, "ease_in_out", speed(2.0)),
            act(101, 3 * SEC - r, r, "ease_in_out", speed(1.0)),
        ]
    );
}

// ---- the overlap ----------------------------------------------------------

#[test]
fn an_action_in_a_dips_hold_gap_is_refused_by_name() {
    let inside = json!([{ "id": 21, "start": 40 * FRAME, "duration": 10 * FRAME,
                          "end": { "video": { "opacity": 0.5 } } }]);
    let handle = Handle::from_value(&project(600 * SEC, 3 * SEC, 1.0, inside));
    // The gap is [22 f, 68 f): action 21 lies in neither new action's span.
    handle.refuses_with(
        &ramp("speed_dip", 0.5),
        "action 21 on clip 11 already runs from 800000 to 1000000 ticks, and two actions on \
         one clip may not overlap",
    );
}

// ---- the errs -------------------------------------------------------------

#[test]
fn every_err_carries_its_sentence() {
    let handle = roomy();
    let mut unknown = ramp("ramp_up", 2.0);
    unknown["clip"] = json!(99);
    assert_eq!(handle.errors(&unknown), "no clip with id 99");
    let mut text = ramp("ramp_up", 2.0);
    text["clip"] = json!(13);
    assert_eq!(
        handle.errors(&text),
        "clip 13 is not a media clip, and only a media clip's action can end at a speed"
    );
    assert_eq!(
        handle.errors(&ramp("ramp_up", 0.0)),
        "rate must be a positive number, not 0"
    );
    assert_eq!(
        handle.errors(&ramp("ramp_up", -2.0)),
        "rate must be a positive number, not -2"
    );
    assert_eq!(
        handle.errors(&with(ramp("ramp_up", 2.0), "from", json!(SEC))),
        "from and to are given together or not at all"
    );
    assert_eq!(
        handle.errors(&ramp_over("ramp_up", 2.0, -2 * FRAME, SEC)),
        "from must not be negative, not -40000"
    );
    // 605 000 snaps to 600 000, which is not after it.
    assert_eq!(
        handle.errors(&ramp_over("ramp_up", 2.0, SEC, SEC + 5_000)),
        "to must be after from, not 600000 against 600000"
    );
    assert_eq!(
        handle.errors(&with(ramp("ramp_up", 2.0), "hold", json!(0.5))),
        "hold is for speed_dip and speed_burst only"
    );
    assert_eq!(
        handle.errors(&with(ramp("ramp_down", 0.5), "hold", json!(0.5))),
        "hold is for speed_dip and speed_burst only"
    );
}

// ---- the refusals ---------------------------------------------------------

#[test]
fn every_refusal_carries_its_sentence() {
    let handle = roomy();
    handle.refuses_with(
        &ramp_over("ramp_up", 2.0, 0, 100 * FRAME),
        "an action of 2000000 ticks at 0 would end at 2000000, past clip 11's own end at \
         1800000 ticks",
    );
    handle.refuses_with(
        &ramp_over("speed_dip", 0.5, 30 * FRAME, 31 * FRAME),
        "a speed dip needs a span of at least two frames (40000 ticks); 600000 to 620000 \
         ticks is 20000",
    );
    handle.refuses_with(
        &ramp_over("speed_burst", 2.0, 30 * FRAME, 31 * FRAME),
        "a speed burst needs a span of at least two frames (40000 ticks); 600000 to 620000 \
         ticks is 20000",
    );
    handle.refuses_with(
        &ramp("ramp_up", 1.0),
        "a ramp up needs a rate above ×1, the rate clip 11 plays at 0 ticks into it; ×1 is not",
    );
    handle.refuses_with(
        &ramp("ramp_down", 2.0),
        "a ramp down needs a rate below ×1, the rate clip 11 plays at 0 ticks into it; ×2 is \
         not",
    );
    handle.refuses_with(
        &ramp("speed_dip", 1.0),
        "a speed dip needs a rate below ×1, the rate clip 11 plays at 0 ticks into it; ×1 is \
         not",
    );
    let quick = Handle::from_value(&project(600 * SEC, 3 * SEC, 1.25, json!([])));
    quick.refuses_with(
        &ramp_over("speed_burst", 1.25, 3 * FRAME, 60 * FRAME),
        "a speed burst needs a rate above ×1.25, the rate clip 11 plays at 60000 ticks into \
         it; ×1.25 is not",
    );
}

#[test]
fn an_overrun_names_the_oracles_fit_and_the_fit_applies() {
    // A 3 s clip over 5 s of media from in 0. Linear from ×1 to x over the
    // whole clip reads S(D) = D(1 + x)/2, which fits while x ≤ 2F/D − 1.
    let (file, duration) = (5 * SEC, 3 * SEC);
    let handle = Handle::from_value(&project(file, duration, 1.0, json!([])));
    let op = with(ramp("ramp_up", 10.0), "curve", json!("linear"));
    let over = duration * 11 / 2 - file;
    let bound = 2.0 * file as f64 / duration as f64 - 1.0;
    let fit = (bound * 1000.0).floor() / 1000.0;
    assert_eq!(fit, 2.333);
    handle.refuses_with(
        &op,
        &format!(
            "a ramp up to ×10 would read clip 11 {over} ticks past the end of its media; the \
             largest rate that fits is ×{fit}"
        ),
    );
    let fitted = handle.apply(&with(op, "rate", json!(fit)));
    assert_eq!(actions(&fitted)[0].4, speed(fit));
    slot_kept(&fitted, duration);
}

#[test]
fn an_up_with_no_rate_above_the_base_that_fits_says_so() {
    // The clip already plays its whole media: any rate above ×1 overruns.
    let handle = Handle::from_value(&project(2 * SEC, 2 * SEC, 1.0, json!([])));
    handle.refuses_with(
        &ramp("ramp_up", 2.0),
        "a ramp up to ×2 would read clip 11 600000 ticks past the end of its media, and no \
         rate above ×1 fits",
    );
    // A dip there reads less, so it fits.
    handle.apply(&ramp("speed_dip", 0.5));
}

// ---- the constant clip ----------------------------------------------------

fn segments_of(plan: &Value, clip: i64) -> String {
    let mut out = Vec::new();
    for kind in ["video_tracks", "audio_tracks"] {
        for track in array(plan, &format!("/{kind}")) {
            for segment in array(track, "/segments") {
                if int(segment, "/clip") == clip {
                    out.push(segment.clone());
                }
            }
        }
    }
    serde_json::to_string(&out).expect("segments serialise")
}

#[test]
fn a_constant_clip_on_another_track_plans_byte_identically() {
    let before = roomy();
    let after = before.apply(&ramp("speed_dip", 0.5));
    let (was, now) = (before.plan(), after.plan());
    assert_ne!(segments_of(&was, 12), "[]");
    assert_eq!(segments_of(&was, 12), segments_of(&now, 12));
    assert_ne!(segments_of(&was, 11), segments_of(&now, 11));
}
