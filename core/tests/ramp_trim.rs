//! The trims, `roll` and `slip` on a RAMPED clip (spec §6, §11 SR-18 (a)–(d),
//! the road map's K).
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: `trim_end` extending exactly to `start + snapped_down(S∞⁻¹(file −
//! in))` and no further, an action past the clip's end ramping on; a
//! `trim_start` shrink advancing `in` by round(S(Δ)) with the actions
//! unchanged, and an extension moving `in` back at the base rate; a shrink
//! and an extension that would read past the file held by `front_edge_held`
//! at the nearest fitting frame; `roll` with a ramped clip on each side; and
//! `slip` at the base rate, clamped at `file − S(D)`.

mod common;

use serde_json::{json, Value};

use common::{at, by_id, int, Handle};

/// Ticks per second and per 30 fps frame (spec §5.1), written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

/// ∫₀ᵘ of the linear ease, the one curve these fixtures use.
fn linear_integral(u: f64) -> f64 {
    u * u / 2.0
}

/// S(t) for a clip at `r0` with ONE linear speed action over [a, b) ending
/// at `r1`, held after: the closed form.
fn s_of(t: i64, r0: f64, r1: f64, a: i64, b: i64) -> f64 {
    let t = t as f64;
    let (a, b) = (a as f64, b as f64);
    let mut s = r0 * t.min(a);
    if t > a {
        let inside = t.min(b) - a;
        s += r0 * inside + (r1 - r0) * (b - a) * linear_integral(inside / (b - a));
    }
    if t > b {
        s += r1 * (t - b);
    }
    s
}

fn round(s: f64) -> i64 {
    s.round() as i64
}

fn snapped_down(t: i64) -> i64 {
    t.div_euclid(FRAME) * FRAME
}

fn media(id: u32, file: i64) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/trim-{id}.mov"), "kind": "video",
        "duration": file, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn project(media: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": media,
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "next_id": 100
    })
}

fn clip(
    id: u32,
    media: u32,
    start: i64,
    duration: i64,
    source_in: i64,
    speed: f64,
    actions: Value,
) -> Value {
    json!({
        "id": id, "track": 2, "start": start, "duration": duration,
        "source": { "kind": "media", "media": media, "in": source_in },
        "speed": speed, "video": {}, "audio": {}, "actions": actions
    })
}

fn ramp(id: u32, start: i64, duration: i64, rate: f64) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": "linear",
            "end": { "speed": rate } })
}

fn one(file: i64, clip_value: Value) -> Handle {
    Handle::from_value(&project(vec![media(1, file)], vec![clip_value]))
}

fn clip11(handle: &Handle) -> Value {
    by_id(&handle.value(), "/clips", 11).clone()
}

#[test]
fn trim_end_extends_to_the_last_frame_the_map_reads_inside_the_file() {
    // A 2 s clip at 1 s from in 0, ×1 → ×2 over [0, 1 s) and ×2 after, in a
    // 5 s file: S∞⁻¹(5 s) = 1 s + 3.5 s / 2 = 2.75 s, its end snapped down.
    let handle = one(
        5 * SEC,
        clip(11, 1, SEC, 2 * SEC, 0, 1.0, json!([ramp(21, 0, SEC, 2.0)])),
    );
    let after = clip11(&handle.apply(&json!({ "op": "trim_end", "clip": 11, "to": 10 * SEC })));
    let end = snapped_down(SEC + 1_650_000);
    assert_eq!(int(&after, "/duration"), end - SEC);
    let read = |d: i64| round(s_of(d, 1.0, 2.0, 0, SEC));
    assert!(read(end - SEC) <= 5 * SEC, "it fits");
    assert!(read(end - SEC + FRAME) > 5 * SEC, "a frame more does not");
    assert_eq!(at(&after, "/actions"), at(&clip11(&handle), "/actions"));
}

#[test]
fn an_action_past_the_clip_s_end_keeps_ramping_in_the_bound() {
    // A 1 s clip whose action runs [0, 2 s) ×1 → ×3: past the end it keeps
    // ramping, so in a 3 s file the end is S⁻¹(3 s) along the ramp, not at
    // the rate the clip ends on. S(t) = t + t²/(2 s): t = 1.6458 s.
    let handle = one(
        3 * SEC,
        clip(11, 1, SEC, SEC, 0, 1.0, json!([ramp(21, 0, 2 * SEC, 3.0)])),
    );
    let after = clip11(&handle.apply(&json!({ "op": "trim_end", "clip": 11, "to": 10 * SEC })));
    let read = |d: i64| round(s_of(d, 1.0, 3.0, 0, 2 * SEC));
    let duration = int(&after, "/duration");
    assert_eq!(duration % FRAME, 0);
    assert!(read(duration) <= 3 * SEC, "it fits");
    assert!(read(duration + FRAME) > 3 * SEC, "a frame more does not");
    assert_eq!(duration, 980_000);
}

#[test]
fn trim_start_moving_in_advances_in_through_the_map_and_keeps_the_actions() {
    // A 3 s clip at 1 s from in 0.5 s, ×1 → ×3 over [1 s, 2 s): moved in
    // by 1.5 s, `in` advances by S(1.5 s) = 1 s + 0.5 s + 2·1 s·⅛.
    let actions = json!([ramp(21, SEC, SEC, 3.0)]);
    let handle = one(
        600 * SEC,
        clip(11, 1, SEC, 3 * SEC, SEC / 2, 1.0, actions.clone()),
    );
    let to = SEC + 3 * SEC / 2;
    let after = clip11(&handle.apply(&json!({ "op": "trim_start", "clip": 11, "to": to })));
    assert_eq!(int(&after, "/start"), to);
    assert_eq!(int(&after, "/duration"), 3 * SEC / 2);
    assert_eq!(
        int(&after, "/source/in"),
        SEC / 2 + round(s_of(3 * SEC / 2, 1.0, 3.0, SEC, 2 * SEC))
    );
    assert_eq!(int(&after, "/source/in"), 300_000 + 1_050_000);
    assert_eq!(at(&after, "/actions"), &actions);
}

#[test]
fn trim_start_moving_out_moves_in_back_at_the_base_rate() {
    // ×1.5 base: half a second out moves `in` back 0.75 s of source.
    let actions = json!([ramp(21, SEC, SEC, 3.0)]);
    let handle = one(
        600 * SEC,
        clip(11, 1, 2 * SEC, 2 * SEC, 2 * SEC, 1.5, actions.clone()),
    );
    let to = 2 * SEC - SEC / 2;
    let after = clip11(&handle.apply(&json!({ "op": "trim_start", "clip": 11, "to": to })));
    assert_eq!(int(&after, "/start"), to);
    assert_eq!(int(&after, "/duration"), 2 * SEC + SEC / 2);
    assert_eq!(int(&after, "/source/in"), 2 * SEC - 450_000);
    assert_eq!(at(&after, "/actions"), &actions);
}

#[test]
fn a_trim_start_shrink_past_the_file_is_held_at_the_nearest_fitting_frame() {
    // ×3 slowing to ×1 over [0, 1 s), ×1 after, on a 3 s clip from in 0:
    // S(D) = 2 s + 2 s = 4 s, in a 4.5 s file. Moved in by Δ ≤ 1 s it reads
    // S(Δ) + S'(3 s − Δ) = (3Δ − Δ²) + (4 s − Δ) = 4 s + 2Δ − Δ² (seconds),
    // which passes 4.5 s past Δ = 0.293 s: the edge holds at 8 frames.
    let handle = one(
        4 * SEC + SEC / 2,
        clip(11, 1, SEC, 3 * SEC, 0, 3.0, json!([ramp(21, 0, SEC, 1.0)])),
    );
    let read = |delta: i64| {
        round(s_of(delta, 3.0, 1.0, 0, SEC)) + round(s_of(3 * SEC - delta, 3.0, 1.0, 0, SEC))
    };
    let file = 4 * SEC + SEC / 2;
    assert!(read(SEC + SEC / 2) > file, "the asked edge overruns");
    let after = clip11(&handle.apply(&json!({
        "op": "trim_start", "clip": 11, "to": SEC + SEC + SEC / 2
    })));
    let delta = int(&after, "/start") - SEC;
    assert_eq!(delta, 8 * FRAME);
    assert!(read(delta) <= file, "it fits");
    assert!(read(delta + FRAME) > file, "a frame further does not");
    assert_eq!(
        int(&after, "/source/in"),
        round(s_of(delta, 3.0, 1.0, 0, SEC))
    );
    assert_eq!(int(&after, "/duration"), 3 * SEC - delta);
}

#[test]
fn a_trim_start_extension_past_the_file_is_held_at_the_nearest_fitting_frame() {
    // ×1 → ×3 over [0, 1 s), ×3 after, on a 2 s clip from in 3 s: S(D) =
    // 5 s, in an 8.5 s file. Moved out by E at ×1 the actions stay put and
    // the clip reads in − E + 5 s + 3E: past the file beyond E = 0.25 s.
    let file = 8 * SEC + SEC / 2;
    let handle = one(
        file,
        clip(
            11,
            1,
            4 * SEC,
            2 * SEC,
            3 * SEC,
            1.0,
            json!([ramp(21, 0, SEC, 3.0)]),
        ),
    );
    let read =
        |extension: i64| 3 * SEC - extension + round(s_of(2 * SEC + extension, 1.0, 3.0, 0, SEC));
    assert!(read(SEC) > file, "the asked edge overruns");
    let after = clip11(&handle.apply(&json!({
        "op": "trim_start", "clip": 11, "to": 3 * SEC
    })));
    let extension = 4 * SEC - int(&after, "/start");
    assert_eq!(extension, 7 * FRAME);
    assert!(read(extension) <= file, "it fits");
    assert!(read(extension + FRAME) > file, "a frame further does not");
    assert_eq!(int(&after, "/source/in"), 3 * SEC - extension);
}

#[test]
fn roll_moves_a_cut_between_two_ramped_clips_through_both_maps() {
    // A: 2 s at 0 from in 0, ×1 → ×2 over [0, 1 s), in a 5 s file — its end
    // may reach snapped_down(S∞⁻¹(5 s)) = snapped_down(2.75 s). B: 2 s at
    // 2 s from in 0, ×1 → ×3 over [0, 1 s), in a long file.
    let handle = Handle::from_value(&project(
        vec![media(1, 5 * SEC), media(3, 600 * SEC)],
        vec![
            clip(11, 1, 0, 2 * SEC, 0, 1.0, json!([ramp(21, 0, SEC, 2.0)])),
            clip(
                12,
                3,
                2 * SEC,
                2 * SEC,
                0,
                1.0,
                json!([ramp(22, 0, SEC, 3.0)]),
            ),
        ],
    ));
    let after = handle
        .apply(&json!({ "op": "roll", "clip": 12, "to": 3 * SEC }))
        .value();
    let cut = snapped_down(1_650_000);
    let a = by_id(&after, "/clips", 11);
    let b = by_id(&after, "/clips", 12);
    assert_eq!(int(a, "/duration"), cut);
    assert_eq!(int(b, "/start"), cut);
    assert_eq!(int(b, "/duration"), 4 * SEC - cut);
    let moved = cut - 2 * SEC;
    assert_eq!(int(b, "/source/in"), round(s_of(moved, 1.0, 3.0, 0, SEC)));
    assert_eq!(
        at(b, "/actions"),
        &json!([ramp(22, 0, SEC, 3.0)]),
        "B's actions stay in its clip time"
    );
}

#[test]
fn slip_converts_at_the_base_rate_and_stops_at_file_less_s_of_d() {
    // ×1.5 → ×3 over [0, 1 s), ×3 after, 2 s from in 1 s, in a 10 s file:
    // S(D) = 2.25 s + 3 s = 5.25 s, so `in` stops at 10 s − 5.25 s.
    let actions = json!([ramp(21, 0, SEC, 3.0)]);
    let handle = one(
        10 * SEC,
        clip(11, 1, SEC, 2 * SEC, SEC, 1.5, actions.clone()),
    );
    let s_d = round(s_of(2 * SEC, 1.5, 3.0, 0, SEC));
    assert_eq!(s_d, 3_150_000);
    let half = clip11(&handle.apply(&json!({ "op": "slip", "clip": 11, "delta": SEC / 2 })));
    assert_eq!(int(&half, "/source/in"), SEC + 450_000);
    assert_eq!(at(&half, "/actions"), &actions);
    let far = clip11(&handle.apply(&json!({ "op": "slip", "clip": 11, "delta": 10 * SEC })));
    assert_eq!(int(&far, "/source/in"), 10 * SEC - s_d);
    assert_eq!(int(&far, "/start"), SEC);
    assert_eq!(int(&far, "/duration"), 2 * SEC);
}
