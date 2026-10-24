//! `split` on a RAMPED clip, and every splitter through `edit_split.rs`
//! (spec §6, §11 SR-18 (e), the road map's I).
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: the halves meet at `in + round(S(cut))` for each of the four
//! curves — the first half's own stored actions read exactly the second
//! half's `in` — the second half's base the rate at the cut, the head's end
//! rate solved (`ease_out`'s 2.25, not the 2.5 at the cut), `ease_out`'s
//! tail exact and `ease_in_out`'s at its own closed form; an `ease_in_out`
//! tail that would read past the file lowered to the largest rate that
//! fits, and a `linear` one a tick over by rounding left as it is;
//! `split_under_playhead` and `ripple_delete_range` cutting the same way;
//! and the actions wholly before or after the cut going to their halves.

mod common;

use serde_json::{json, Value};

use common::{array, at, by_id, int, num, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
/// Where the clip starts, and the cut 2 s into it.
const START: i64 = SEC;
const CUT: i64 = START + 2 * SEC;

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

/// §5.4's eases themselves, for the rate at a clip time.
fn ease(curve: &str, u: f64) -> f64 {
    match curve {
        "linear" => u,
        "ease_in" => u * u,
        "ease_out" => 1.0 - (1.0 - u) * (1.0 - u),
        "ease_in_out" => u * u * (3.0 - 2.0 * u),
        other => panic!("no curve {other}"),
    }
}

/// S(t) for a clip at `r0` with ONE speed action over [a, b) ending at
/// `r1` along `curve`, held after: the closed form.
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

fn project(file: i64, speed: f64, actions: Value) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/split.mov", "kind": "video", "duration": file,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": START, "duration": 4 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "speed": speed, "video": {}, "audio": {}, "actions": actions
        }],
        "next_id": 100
    })
}

fn speed_action(id: u32, start: i64, duration: i64, curve: &str, rate: f64) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": curve,
            "end": { "speed": rate } })
}

/// The 4 s clip from `in` 0 with action 21 over [0, 4 s) ×1 → ×3.
fn ramped(curve: &str) -> Handle {
    Handle::from_value(&project(
        600 * SEC,
        1.0,
        json!([speed_action(21, 0, 4 * SEC, curve, 3.0)]),
    ))
}

fn split_at(handle: &Handle, at: i64) -> Value {
    handle
        .apply(&json!({ "op": "split", "clips": [11], "at": at }))
        .value()
}

/// The clip on track 2 that starts at `start`.
fn clip_at(value: &Value, start: i64) -> Value {
    array(value, "/clips")
        .iter()
        .find(|c| int(c, "/start") == start)
        .unwrap_or_else(|| panic!("no clip starts at {start} in {value}"))
        .clone()
}

/// The clip's one audio segment's source out point: what the plan reads.
fn planned_out(handle: &Handle, clip: i64) -> i64 {
    let plan = handle.plan();
    for track in array(&plan, "/audio_tracks") {
        for segment in array(track, "/segments") {
            if int(segment, "/clip") == clip {
                return int(segment, "/source_in") + int(segment, "/source_duration");
            }
        }
    }
    panic!("no audio segment for clip {clip}");
}

#[test]
fn the_halves_meet_at_the_source_the_clip_read_by_the_cut_for_every_curve() {
    for curve in ["linear", "ease_in", "ease_out", "ease_in_out"] {
        let after = split_at(&ramped(curve), CUT);
        let first = by_id(&after, "/clips", 11).clone();
        let second = clip_at(&after, CUT);
        let joined = round(s_of(2 * SEC, 1.0, 3.0, 0, 4 * SEC, curve));
        assert_eq!(int(&second, "/source/in"), joined, "{curve}");
        let at_cut = 1.0 + 2.0 * ease(curve, 0.5);
        assert!(
            (num(&second, "/speed") - at_cut).abs() < 1e-9,
            "{curve}: {second}"
        );

        // The first half, read from its OWN stored actions, ends on the
        // tick the second half starts on.
        assert_eq!(int(&first, "/duration"), 2 * SEC, "{curve}");
        let head = &array(&first, "/actions")[0];
        assert_eq!(int(head, "/start"), 0);
        assert_eq!(int(head, "/duration"), 2 * SEC, "{curve}");
        assert_eq!(at(head, "/curve"), &json!(curve));
        let head_rate = num(head, "/end/speed");
        let head_read = s_of(2 * SEC, num(&first, "/speed"), head_rate, 0, 2 * SEC, curve);
        assert!(
            (head_read - joined as f64).abs() <= 1.0,
            "{curve}: the head reads {head_read}, the second half starts at {joined}"
        );

        // The tail keeps the original end and curve, from the rate at the
        // cut, over the rest of the action.
        let tail = &array(&second, "/actions")[0];
        assert_eq!(int(tail, "/start"), 0);
        assert_eq!(int(tail, "/duration"), 2 * SEC, "{curve}");
        assert_eq!(num(tail, "/end/speed"), 3.0, "{curve}");
        assert_eq!(at(tail, "/curve"), &json!(curve));
    }
}

#[test]
fn the_ease_out_join_has_the_objection_s_numbers() {
    let after = split_at(&ramped("ease_out"), CUT);
    let second = clip_at(&after, CUT);
    assert_eq!(int(&second, "/source/in"), 2_200_000);
    assert!((num(&second, "/speed") - 2.5).abs() < 1e-9);
    let head = &array(by_id(&after, "/clips", 11), "/actions")[0];
    // E(½)/(½·E(1)) = (5/24)/(1/3) = 0.625, so ×1 + 2·0.625: not the ×2.5
    // at the cut, which would read 4 s by the cut and repeat a third of one.
    assert!((num(head, "/end/speed") - 2.25).abs() < 1e-9, "{head}");
}

#[test]
fn linear_and_ease_in_heads_end_at_the_rate_at_the_cut() {
    for curve in ["linear", "ease_in"] {
        let after = split_at(&ramped(curve), CUT);
        let head = &array(by_id(&after, "/clips", 11), "/actions")[0];
        let second = clip_at(&after, CUT);
        assert!(
            (num(head, "/end/speed") - num(&second, "/speed")).abs() < 1e-9,
            "{curve}: {head} against {second}"
        );
    }
}

#[test]
fn an_ease_out_tail_reads_what_the_original_read_after_the_cut() {
    let handle = ramped("ease_out");
    let original_out = planned_out(&handle, 11);
    let split = handle.apply(&json!({ "op": "split", "clips": [11], "at": CUT }));
    let after = split.value();
    let second = clip_at(&after, CUT);
    let tail = &array(&second, "/actions")[0];
    let read = s_of(
        2 * SEC,
        num(&second, "/speed"),
        num(tail, "/end/speed"),
        0,
        2 * SEC,
        "ease_out",
    );
    let original = s_of(4 * SEC, 1.0, 3.0, 0, 4 * SEC, "ease_out")
        - s_of(2 * SEC, 1.0, 3.0, 0, 4 * SEC, "ease_out");
    assert!((read - original).abs() <= 1.0, "{read} against {original}");
    let out = planned_out(&split, int(&second, "/id"));
    assert!(
        (out - original_out).abs() <= 1,
        "{out} against {original_out}"
    );
}

#[test]
fn an_ease_in_out_tail_re_eases_from_the_cut() {
    let split = ramped("ease_in_out").apply(&json!({ "op": "split", "clips": [11], "at": CUT }));
    let second = clip_at(&split.value(), CUT);
    // S(2 s) = 2.75 s; ×2 at the cut, easing in and out to ×3 over 2 s:
    // 2·2 s + 1·2 s·½ = 5 s, where the original read 8 s − 2.75 s = 5.25 s
    // after the cut. The out point moves back a quarter of a second.
    assert_eq!(int(&second, "/source/in"), 1_650_000);
    let expected = 1_650_000 + round(s_of(2 * SEC, 2.0, 3.0, 0, 2 * SEC, "ease_in_out"));
    assert_eq!(expected, 1_650_000 + 3_000_000);
    assert_eq!(planned_out(&split, int(&second, "/id")), expected);
}

/// `fits` for a re-eased ×2 → x tail over 2 s from in 3.15 s, in a 8 s file.
fn tail_fits(x: f64) -> bool {
    3_150_000 + round(s_of(2 * SEC, 2.0, x, 0, 2 * SEC, "ease_in_out")) <= 8 * SEC
}

#[test]
fn an_ease_in_out_tail_past_the_file_is_lowered_to_the_largest_rate_that_fits() {
    // ×3 easing to ×1 over the whole 4 s reads exactly the 8 s file. Cut at
    // 2 s (S = 5.25 s, ×2 there), the re-eased tail would read 3 s against
    // the 2.75 s left.
    let handle = Handle::from_value(&project(
        8 * SEC,
        3.0,
        json!([speed_action(21, 0, 4 * SEC, "ease_in_out", 1.0)]),
    ));
    assert_eq!(
        round(s_of(4 * SEC, 3.0, 1.0, 0, 4 * SEC, "ease_in_out")),
        8 * SEC
    );
    let after = split_at(&handle, CUT);
    let second = clip_at(&after, CUT);
    assert_eq!(int(&second, "/source/in"), 3_150_000);
    assert!((num(&second, "/speed") - 2.0).abs() < 1e-9);
    assert!(!tail_fits(1.0), "the unlowered tail overruns");
    let lowered = num(&array(&second, "/actions")[0], "/end/speed");
    assert!((lowered - 0.75).abs() < 1e-9, "{second}");
    assert!(tail_fits(lowered));
    assert!(!tail_fits(lowered + 0.001));
    // The head reads exactly what the original did by the cut, and is not
    // lowered: ×3 + (1 − 3)·0.375.
    let head = &array(by_id(&after, "/clips", 11), "/actions")[0];
    assert!((num(head, "/end/speed") - 2.25).abs() < 1e-9, "{head}");
}

#[test]
fn a_linear_straddle_at_the_file_end_keeps_its_rates() {
    // ×1 → ×2.0000003 linear over the whole 4 s: S(D) = 3 600 000.36, so
    // the clip reads to the 3 600 000-tick file's last tick. Cut at
    // 2 200 000 ticks the halves round to 3 208 334 + 391 667, a tick over.
    let rate = 2.000_000_3;
    let handle = Handle::from_value(&project(
        3_600_000,
        1.0,
        json!([speed_action(21, 0, 4 * SEC, "linear", rate)]),
    ));
    let cut = START + 2_200_000;
    let after = split_at(&handle, cut);
    let second = clip_at(&after, cut);
    assert_eq!(
        int(&second, "/source/in"),
        round(s_of(2_200_000, 1.0, rate, 0, 4 * SEC, "linear"))
    );
    let base = num(&second, "/speed");
    let tail = num(&array(&second, "/actions")[0], "/end/speed");
    assert_eq!(tail, rate, "a linear tail is never lowered: {second}");
    assert!((base - (1.0 + (rate - 1.0) * 2_200_000.0 / 2_400_000.0)).abs() < 1e-9);
    // The rounding the exemption is for: one tick past the file.
    let read = int(&second, "/source/in") + round(s_of(200_000, base, tail, 0, 200_000, "linear"));
    assert_eq!(read, 3_600_001);
}

#[test]
fn split_under_the_playhead_cuts_the_same_way() {
    for curve in ["ease_out", "ease_in_out"] {
        let named = split_at(&ramped(curve), CUT);
        let under = ramped(curve)
            .apply(&json!({ "op": "split", "at": CUT }))
            .value();
        assert_eq!(named, under, "{curve}");
    }
}

#[test]
fn ripple_delete_range_cuts_the_same_way() {
    let named = split_at(&ramped("ease_out"), CUT);
    let second = clip_at(&named, CUT);
    let head = by_id(&named, "/clips", 11).clone();

    // Removing the first 2 s leaves the second half, moved to the start.
    let front = ramped("ease_out")
        .apply(&json!({ "op": "ripple_delete_range", "from": START, "to": CUT }))
        .value();
    let kept = clip_at(&front, START);
    assert_eq!(int(&kept, "/source/in"), 2_200_000);
    assert_eq!(num(&kept, "/speed"), num(&second, "/speed"));
    assert_eq!(kept["actions"].as_array().map(Vec::len), Some(1));
    assert_eq!(
        num(&kept, "/actions/0/end/speed"),
        num(&second, "/actions/0/end/speed")
    );

    // Removing the last 2 s leaves the first half, its end rate solved.
    let back = ramped("ease_out")
        .apply(&json!({ "op": "ripple_delete_range", "from": CUT, "to": START + 4 * SEC }))
        .value();
    let kept = by_id(&back, "/clips", 11);
    assert_eq!(int(kept, "/duration"), 2 * SEC);
    assert_eq!(at(kept, "/actions"), at(&head, "/actions"));
}

#[test]
fn actions_wholly_before_or_after_the_cut_go_to_their_halves() {
    // ×1 → ×2 over [0, 1 s), ×2 → ×3 ease-out over [1 s, 3 s) straddling the
    // cut, and ×3 → ×1 over [3 s, 3.5 s).
    let handle = Handle::from_value(&project(
        600 * SEC,
        1.0,
        json!([
            speed_action(21, 0, SEC, "linear", 2.0),
            speed_action(22, SEC, 2 * SEC, "ease_out", 3.0),
            speed_action(23, 3 * SEC, SEC / 2, "linear", 1.0)
        ]),
    ));
    let after = split_at(&handle, CUT);
    let first = by_id(&after, "/clips", 11);
    let second = clip_at(&after, CUT);
    let ids = |clip: &Value| -> Vec<i64> {
        array(clip, "/actions")
            .iter()
            .map(|a| int(a, "/id"))
            .collect()
    };
    assert_eq!(ids(first), [21, 22]);
    let before = &array(first, "/actions")[0];
    assert_eq!(int(before, "/start"), 0, "untouched");
    assert_eq!(int(before, "/duration"), SEC);
    assert_eq!(num(before, "/end/speed"), 2.0);
    let second_ids = ids(&second);
    assert_eq!(second_ids.len(), 2);
    assert_eq!(second_ids[1], 23);
    let later = &array(&second, "/actions")[1];
    assert_eq!(int(later, "/start"), SEC, "rebased by the cut");
    assert_eq!(int(later, "/duration"), SEC / 2);
    assert_eq!(num(later, "/end/speed"), 1.0);

    // The join: S(2 s) = 1.5 s + (2·1 s + 1·2 s·E_out(½)).
    let joined = 1.5 * SEC as f64 + s_of(SEC, 2.0, 3.0, 0, 2 * SEC, "ease_out");
    assert_eq!(int(&second, "/source/in"), round(joined));
    assert!((num(&second, "/speed") - (2.0 + ease("ease_out", 0.5))).abs() < 1e-9);
    let head = &array(first, "/actions")[1];
    assert_eq!(int(head, "/duration"), SEC);
    // The head over [1 s, 2 s) at ×2 to its solved rate reads S(2 s) − S(1 s).
    let head_read = 1.5 * SEC as f64 + s_of(SEC, 2.0, num(head, "/end/speed"), 0, SEC, "ease_out");
    assert!(
        (head_read - joined).abs() <= 1.0,
        "{head_read} against {joined}"
    );
}
