//! `set_speed` and `rate_stretch` on a RAMPED clip, and the plan's one ×12
//! figure (spec §6, §11 SR-19 (a)–(d), the road map's L and P).
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: one factor scales the base, every end rate and every speed action's
//! span, so the clip keeps its shape and reads the source it read — a
//! speed action running past the clip's end included; the duration arm, the
//! identities at f = 1 (an integer `end.speed` kept as stored), the clamp of
//! f where one rate would pass a limit, the hold through S∞ when the grid's
//! rounding would read past the file, `rate_stretch`'s scaling and its
//! out-of-range identity; the ×12 test on the greatest rate the clip NAMES,
//! reached inside the clip or not; and `scope` into a nest.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, flag, int, num, Handle, Outcome};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
/// One frame at the fixtures' 30 fps.
const FRAME: i64 = 20_000;
/// Where clip 11 starts.
const START: i64 = SEC;

/// The four curves' eases' integrals over [0, u], from §5.4's polynomials.
fn ease_integral(curve: &str, u: f64) -> f64 {
    match curve {
        "linear" => u * u / 2.0,
        "ease_in" => u.powi(3) / 3.0,
        "ease_out" => u * u - u.powi(3) / 3.0,
        "ease_in_out" => u.powi(3) - u.powi(4) / 2.0,
        other => panic!("no curve {other}"),
    }
}

/// S(t) for a clip at `r0` with ONE speed action over [a, b) ending at
/// `r1` along `curve`, held after: the closed form, read on past the
/// clip's end (S∞).
fn s_of(t: i64, r0: f64, r1: f64, a: i64, b: i64, curve: &str) -> f64 {
    let t = t as f64;
    let (a, b) = (a as f64, b as f64);
    let mut s = r0 * t.min(a);
    if t > a {
        let inside = t.min(b) - a;
        s += r0 * inside + (r1 - r0) * (b - a) * ease_integral(curve, inside / (b - a));
    }
    if t > b {
        s += r1 * (t - b);
    }
    s
}

fn round(s: f64) -> i64 {
    s.round() as i64
}

/// Clip 11 at 1 s, `duration` long from `in` 0, at `speed`, over a media
/// `file` ticks long with sound.
fn project(file: i64, duration: i64, speed: f64, actions: Value) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/scale.mov", "kind": "video", "duration": file,
            "width": 1920, "height": 1080, "fps": [30, 1],
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

fn speed_action(id: u32, start: i64, duration: i64, curve: &str, rate: Value) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": curve,
            "end": { "speed": rate } })
}

/// The 4 s clip with action 21 over [1 s, 3 s) ×1 → ×3 along `curve`, in a
/// long file: S(4 s) = 8 s for `linear`.
fn four_seconds(curve: &str) -> Handle {
    Handle::from_value(&project(
        600 * SEC,
        4 * SEC,
        1.0,
        json!([speed_action(21, SEC, 2 * SEC, curve, json!(3.0))]),
    ))
}

fn set_speed(rate: f64) -> Value {
    json!({ "op": "set_speed", "clip": 11, "rate": rate })
}

fn clip(handle: &Handle) -> Value {
    by_id(&handle.value(), "/clips", 11).clone()
}

fn action(clip: &Value) -> Value {
    array(clip, "/actions")[0].clone()
}

/// The clip's audio segments in the plan.
fn audio_segments(handle: &Handle, clip: i64) -> Vec<Value> {
    let plan = handle.plan();
    let mut out = Vec::new();
    for track in array(&plan, "/audio_tracks") {
        for segment in array(track, "/segments") {
            if int(segment, "/clip") == clip {
                out.push(segment.clone());
            }
        }
    }
    out
}

/// The source the plan reads for the clip: its one audio segment's length.
fn planned_source(handle: &Handle) -> i64 {
    let audio = audio_segments(handle, 11);
    assert_eq!(audio.len(), 1, "{audio:?}");
    int(&audio[0], "/source_duration")
}

fn is_identity(handle: &Handle, op: &Value) -> bool {
    matches!(handle.try_apply(op), Ok(Outcome::Identity))
}

#[test]
fn the_rate_arm_scales_every_rate_and_every_span_by_one_factor() {
    for curve in ["linear", "ease_out"] {
        let handle = four_seconds(curve);
        let read = s_of(4 * SEC, 1.0, 3.0, SEC, 3 * SEC, curve);
        let after = handle.apply(&set_speed(2.0));
        let scaled = clip(&after);
        assert_eq!(num(&scaled, "/speed"), 2.0, "{curve}");
        assert_eq!(int(&scaled, "/duration"), 2 * SEC, "{curve}");
        let ramp = action(&scaled);
        assert_eq!(num(&ramp, "/end/speed"), 6.0, "{curve}");
        assert_eq!(int(&ramp, "/start"), SEC / 2, "{curve}");
        assert_eq!(int(&ramp, "/duration"), SEC, "{curve}");
        assert_eq!(ramp["curve"], json!(curve));
        // The window is the one the clip read before.
        let planned = planned_source(&after);
        assert!(
            (planned - round(read)).abs() <= 1,
            "{curve}: the plan reads {planned}, the clip read {read}"
        );
    }
}

#[test]
fn a_speed_action_past_the_end_scales_with_the_clip_and_is_not_clamped() {
    // A 2 s clip holding [0, 4 s) ×1 → ×3, as `trim_end` leaves it: it has
    // read S(2 s) = 3 s.
    let handle = Handle::from_value(&project(
        600 * SEC,
        2 * SEC,
        1.0,
        json!([speed_action(21, 0, 4 * SEC, "linear", json!(3.0))]),
    ));
    assert_eq!(
        round(s_of(2 * SEC, 1.0, 3.0, 0, 4 * SEC, "linear")),
        1_800_000
    );
    let after = handle.apply(&set_speed(2.0));
    let scaled = clip(&after);
    assert_eq!(num(&scaled, "/speed"), 2.0);
    assert_eq!(int(&scaled, "/duration"), SEC);
    let ramp = action(&scaled);
    assert_eq!(num(&ramp, "/end/speed"), 6.0);
    assert_eq!(int(&ramp, "/start"), 0);
    assert_eq!(int(&ramp, "/duration"), 2 * SEC, "{ramp}");
    let planned = planned_source(&after);
    assert!((planned - 1_800_000).abs() <= 1, "the plan reads {planned}");

    // An action wholly past the end moves with the same factor.
    let past = Handle::from_value(&project(
        600 * SEC,
        2 * SEC,
        1.0,
        json!([speed_action(21, 3 * SEC, SEC, "linear", json!(3.0))]),
    ));
    let scaled = clip(&past.apply(&set_speed(2.0)));
    assert_eq!(int(&scaled, "/duration"), SEC);
    let ramp = action(&scaled);
    assert_eq!(int(&ramp, "/start"), 3 * SEC / 2, "{ramp}");
    assert_eq!(int(&ramp, "/duration"), SEC / 2, "{ramp}");
    assert_eq!(num(&ramp, "/end/speed"), 6.0);
}

#[test]
fn the_duration_arm_scales_by_d_over_the_new_duration() {
    let handle = four_seconds("linear");
    let after = handle.apply(&json!({ "op": "set_speed", "clip": 11, "duration": 8 * SEC }));
    let scaled = clip(&after);
    assert_eq!(num(&scaled, "/speed"), 0.5);
    assert_eq!(int(&scaled, "/duration"), 8 * SEC);
    let ramp = action(&scaled);
    assert_eq!(num(&ramp, "/end/speed"), 1.5);
    assert_eq!(int(&ramp, "/start"), 2 * SEC);
    assert_eq!(int(&ramp, "/duration"), 4 * SEC);
}

#[test]
fn fitting_the_current_duration_or_the_clip_s_own_rate_is_an_identity() {
    // An integer end rate, kept as stored: no rate is rewritten at f = 1.
    let handle = Handle::from_value(&project(
        600 * SEC,
        4 * SEC,
        1.0,
        json!([speed_action(21, SEC, 2 * SEC, "linear", json!(2))]),
    ));
    assert!(is_identity(
        &handle,
        &json!({ "op": "set_speed", "clip": 11, "duration": 4 * SEC })
    ));
    assert!(is_identity(&handle, &set_speed(1.0)));
    assert!(is_identity(
        &handle,
        &json!({ "op": "rate_stretch", "clip": 11, "to_end": START + 4 * SEC })
    ));
    assert_eq!(action(&clip(&handle))["end"]["speed"], json!(2));
}

#[test]
fn the_factor_stops_where_one_rate_would_pass_a_limit() {
    // ×1 → ×500 at rate 4: the end stops at ×1000, so f = 2. The file is
    // long enough for the 1 503 s the clip reads.
    let fast = Handle::from_value(&project(
        3000 * SEC,
        4 * SEC,
        1.0,
        json!([speed_action(21, SEC, 2 * SEC, "linear", json!(500.0))]),
    ));
    let scaled = clip(&fast.apply(&set_speed(4.0)));
    assert_eq!(num(&scaled, "/speed"), 2.0);
    assert_eq!(num(&action(&scaled), "/end/speed"), 1000.0);
    assert_eq!(int(&scaled, "/duration"), 2 * SEC);
    assert_eq!(int(&action(&scaled), "/start"), SEC / 2);

    // ×1 → ×0.2 at rate 0.05: the rate clamps to ×0.1, the end would pass
    // it, so f = 0.5.
    let slow = Handle::from_value(&project(
        600 * SEC,
        4 * SEC,
        1.0,
        json!([speed_action(21, SEC, 2 * SEC, "linear", json!(0.2))]),
    ));
    let scaled = clip(&slow.apply(&set_speed(0.05)));
    assert_eq!(num(&scaled, "/speed"), 0.5);
    assert!((num(&action(&scaled), "/end/speed") - 0.1).abs() < 1e-12);
    assert_eq!(int(&scaled, "/duration"), 8 * SEC);

    // ×1 → ×1000 at rate 2: f clamps to 1, which changes nothing...
    let pinned = Handle::from_value(&project(
        3000 * SEC,
        4 * SEC,
        1.0,
        json!([speed_action(21, SEC, 2 * SEC, "linear", json!(1000.0))]),
    ));
    assert!(is_identity(&pinned, &set_speed(2.0)));
    // ...but `keep_pitch`.
    let kept = pinned.apply(&json!({ "op": "set_speed", "clip": 11, "rate": 2.0,
                                     "keep_pitch": false }));
    let after = clip(&kept);
    assert!(!flag(&after, "/audio/keep_pitch"));
    let mut back = after.clone();
    back["audio"] = clip(&pinned)["audio"].clone();
    assert_eq!(back, clip(&pinned));
}

#[test]
fn a_scale_whose_rounding_would_read_past_the_file_is_held() {
    // [0, 4 s) ×1 → ×2 reads S(4 s) = 6 s, exactly the file.
    let file = 3_600_000;
    let handle = Handle::from_value(&project(
        file,
        4 * SEC,
        1.0,
        json!([speed_action(21, 0, 4 * SEC, "linear", json!(2.0))]),
    ));
    // D / 5.5 = 436 364 rounds UP to 440 000, which reads past the file.
    let after = handle.apply(&set_speed(5.5));
    let scaled = clip(&after);
    let ramp = action(&scaled);
    let (a, b) = (
        int(&ramp, "/start"),
        int(&ramp, "/start") + int(&ramp, "/duration"),
    );
    let (r0, r1) = (num(&scaled, "/speed"), num(&ramp, "/end/speed"));
    assert_eq!(
        (a, b),
        (0, 440_000),
        "the actions stay where the scale put them"
    );
    assert_eq!((r0, r1), (5.5, 11.0));
    assert!(s_of(440_000, r0, r1, a, b, "linear") > file as f64);
    // Held to snapped_down(S∞′⁻¹(file)): the last frame that fits.
    let held = (0..)
        .map(|k| k * FRAME)
        .take_while(|t| s_of(*t, r0, r1, a, b, "linear") <= file as f64)
        .last()
        .unwrap();
    assert!(held < 440_000);
    assert_eq!(int(&scaled, "/duration"), held);
    assert!(planned_source(&after) <= file);
}

#[test]
fn rate_stretch_scales_the_profile_and_refuses_nothing_out_of_range() {
    let handle = four_seconds("linear");
    let after = handle.apply(&json!({ "op": "rate_stretch", "clip": 11,
                                      "to_end": START + 8 * SEC }));
    let scaled = clip(&after);
    assert_eq!(num(&scaled, "/speed"), 0.5);
    assert_eq!(int(&scaled, "/duration"), 8 * SEC);
    let ramp = action(&scaled);
    assert_eq!(num(&ramp, "/end/speed"), 1.5);
    assert_eq!(int(&ramp, "/start"), 2 * SEC);
    assert_eq!(int(&ramp, "/duration"), 4 * SEC);
    assert!((planned_source(&after) - 4_800_000).abs() <= 1);

    // ×1 → ×500 squeezed to 1 s is f = 4: the end would pass ×1000.
    let fast = Handle::from_value(&project(
        3000 * SEC,
        4 * SEC,
        1.0,
        json!([speed_action(21, SEC, 2 * SEC, "linear", json!(500.0))]),
    ));
    assert!(is_identity(
        &fast,
        &json!({ "op": "rate_stretch", "clip": 11, "to_end": START + SEC })
    ));
}

#[test]
fn a_scale_taking_the_ramp_above_x12_leaves_the_audio_out() {
    let handle = Handle::from_value(&project(
        600 * SEC,
        4 * SEC,
        2.0,
        json!([speed_action(21, SEC, 2 * SEC, "linear", json!(4.0))]),
    ));
    assert_eq!(audio_segments(&handle, 11).len(), 1);
    let after = handle.apply(&set_speed(8.0));
    assert_eq!(num(&action(&clip(&after)), "/end/speed"), 16.0);
    assert!(audio_segments(&after, 11).is_empty());
}

#[test]
fn the_x12_test_reads_the_greatest_rate_the_clip_names() {
    // A 1 s clip holding [0, 2 s) ×1 → ×13: it reaches ×7 by its end and
    // names ×13, so the audio is left out, as `SpeedAudioDrop` reads it.
    let named = |rate: f64| {
        Handle::from_value(&project(
            600 * SEC,
            SEC,
            1.0,
            json!([speed_action(21, 0, 2 * SEC, "linear", json!(rate))]),
        ))
    };
    assert!(audio_segments(&named(13.0), 11).is_empty());
    assert_eq!(audio_segments(&named(12.0), 11).len(), 1);
}

#[test]
fn set_speed_through_scope_matches_the_top_level() {
    let inner = |track: u32| {
        json!({
            "id": 51, "track": track, "start": SEC, "duration": 4 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "speed": 1.0, "video": {}, "audio": {},
            "actions": [speed_action(52, SEC, 2 * SEC, "ease_out", json!(3.0))]
        })
    };
    let media = json!({
        "id": 1, "path": "/fixtures/scale.mov", "kind": "video", "duration": 600 * SEC,
        "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true
    });
    let top = Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media.clone()],
        "tracks": [{ "id": 53, "name": "Track 1" }],
        "clips": [inner(53)],
        "next_id": 100
    }));
    let nested = Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{ "id": 60, "track": 2, "start": 0, "duration": 10 * SEC,
                    "source": { "kind": "nest", "project": 50 } }],
        "nests": [{ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                    "tracks": [{ "id": 53, "name": "Inner" }], "clips": [inner(53)] }],
        "next_id": 100
    }));
    let op = json!({ "op": "set_speed", "clip": 51, "rate": 2.0 });
    let mut scoped = op.clone();
    scoped["scope"] = json!(50);
    let top = top.apply(&op).value();
    let inside = nested.apply(&scoped).value();
    let nest = by_id(&inside, "/nests", 50);
    assert_eq!(array(nest, "/clips"), array(&top, "/clips"));
    let scaled = by_id(&top, "/clips", 51);
    assert_eq!(num(scaled, "/speed"), 2.0);
    assert_eq!(int(scaled, "/duration"), 2 * SEC);
    assert_eq!(num(&array(scaled, "/actions")[0], "/end/speed"), 6.0);
}

#[test]
fn an_unclamped_rate_writes_the_base_asked_and_a_repeat_is_an_identity() {
    // ×49 → ×98: 49 × (1 ÷ 49) is 0.9999999999999999 in doubles, so the
    // base is written as the rate asked, not as `speed` × f.
    let handle = Handle::from_value(&project(
        3000 * SEC,
        4 * SEC,
        49.0,
        json!([speed_action(21, SEC, 2 * SEC, "linear", json!(98.0))]),
    ));
    let after = handle.apply(&set_speed(1.0));
    let scaled = clip(&after);
    assert_eq!(num(&scaled, "/speed"), 1.0);
    assert!((num(&action(&scaled), "/end/speed") - 2.0).abs() < 1e-12);
    assert_eq!(int(&scaled, "/duration"), 196 * SEC);
    assert!(is_identity(&after, &set_speed(1.0)));
}

#[test]
fn a_held_scale_re_clamps_the_other_actions_into_what_is_left() {
    // The rate-5.5 hold above, with an opacity action over [2 s, 4 s):
    // scaled to [220 000, 440 000), then re-clamped into the held 420 000,
    // as `resnap_clip_times`' second pass clamps it.
    let handle = Handle::from_value(&project(
        3_600_000,
        4 * SEC,
        1.0,
        json!([
            speed_action(21, 0, 4 * SEC, "linear", json!(2.0)),
            { "id": 22, "start": 2 * SEC, "duration": 2 * SEC, "curve": "linear",
              "end": { "video": { "opacity": 0.4 } } }
        ]),
    ));
    let scaled = clip(&handle.apply(&set_speed(5.5)));
    assert_eq!(int(&scaled, "/duration"), 420_000);
    let ramp = by_id(&scaled, "/actions", 21);
    assert_eq!((int(ramp, "/start"), int(ramp, "/duration")), (0, 440_000));
    let fade = by_id(&scaled, "/actions", 22);
    assert_eq!(
        (int(fade, "/start"), int(fade, "/duration")),
        (220_000, 200_000)
    );
}
