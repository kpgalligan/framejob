//! Fade and crossfade shapes (format 29, spec §11 AU-114, AU-115), through
//! the FFI: each of the four shapes on a fade in, a fade out and a
//! transition's crossfade, read off the plan's ramps against its formula;
//! the defaults planning exactly as before; and `set_transition_style`'s
//! `audio_shape`.
//!
//! Every ramp endpoint inside a shaped fade lies ON the formula (1e-12), and
//! every ramp's midpoint is within 0.01 of linear gain of it — the ramps are
//! a sampling of the curve on the 1/30 s grid, and a straight segment over
//! 1/30 s of these curves departs from them by far less than that.

use std::f64::consts::{FRAC_PI_2, PI};

use serde_json::{json, Value};

mod common;
use common::{array, at, int, num, Handle};

const SEC: i64 = 600_000;
const SHAPES: [&str; 4] = ["linear", "s_curve", "plus_3db", "minus_3db"];

/// The decision's formulas, written again here and not read from the core.
fn formula(shape: &str, u: f64) -> f64 {
    let u = u.clamp(0.0, 1.0);
    match shape {
        "linear" => u,
        "s_curve" => (1.0 - (PI * u).cos()) / 2.0,
        "plus_3db" => (u * FRAC_PI_2).sin(),
        "minus_3db" => 1.0 - (u * FRAC_PI_2).cos(),
        other => panic!("no shape {other}"),
    }
}

/// One 10 s clip at 0 with `audio` as its props.
fn one(audio: Value) -> Value {
    json!({
        "version": 29,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/1.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": [{"id": 10, "track": 2, "start": 0, "duration": 10 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "audio": audio}],
        "next_id": 100
    })
}

fn ramps(handle: &Handle) -> Vec<Value> {
    array(&handle.plan(), "/audio_tracks/0/ramps").clone()
}

/// Every ramp over `[from, to]` against `expected(t)`: endpoints exact,
/// midpoints within 0.01.
fn assert_on(ramps: &[Value], from: i64, to: i64, expected: &dyn Fn(i64) -> f64, what: &str) {
    let mut inside = 0;
    for ramp in ramps {
        let (start, duration) = (int(ramp, "/start"), int(ramp, "/duration"));
        let end = start + duration;
        if start < from || end > to {
            continue;
        }
        inside += 1;
        let (a, b) = (num(ramp, "/from"), num(ramp, "/to"));
        assert!(
            (a - expected(start)).abs() < 1e-12,
            "{what}: from at {start}: {a}"
        );
        assert!(
            (b - expected(end)).abs() < 1e-12,
            "{what}: to at {end}: {b}"
        );
        let mid = start + duration / 2;
        let between = a + (b - a) * ((mid - start) as f64 / duration as f64);
        assert!(
            (between - expected(mid)).abs() < 0.01,
            "{what}: midpoint {mid}: {between} vs {}",
            expected(mid)
        );
    }
    assert!(inside > 0, "{what}: no ramp inside the fade");
}

#[test]
fn each_fade_in_shape_follows_its_formula() {
    for shape in SHAPES {
        let handle = Handle::from_value(&one(json!({"fade_in": 2 * SEC, "fade_in_shape": shape})));
        let ramps = ramps(&handle);
        let curve = |t: i64| formula(shape, t as f64 / (2 * SEC) as f64);
        assert_on(&ramps, 0, 2 * SEC, &curve, shape);
        if shape != "linear" {
            // Sampled on the action grid: 2 s at 1/30 s is 60 ramps.
            assert!(ramps.len() >= 60, "{shape}: {} ramps", ramps.len());
        }
    }
}

#[test]
fn each_fade_out_shape_follows_its_formula() {
    for shape in SHAPES {
        let handle =
            Handle::from_value(&one(json!({"fade_out": 3 * SEC, "fade_out_shape": shape})));
        let curve = |t: i64| formula(shape, (10 * SEC - t) as f64 / (3 * SEC) as f64);
        assert_on(&ramps(&handle), 7 * SEC, 10 * SEC, &curve, shape);
    }
}

#[test]
fn a_linear_fade_plans_exactly_as_before() {
    // The file default writes no shape key and adds no samples: one ramp
    // up, one flat, one down.
    let plain = Handle::from_value(&one(json!({"fade_in": SEC, "fade_out": SEC})));
    let named = Handle::from_value(&one(json!({"fade_in": SEC, "fade_out": SEC,
        "fade_in_shape": "linear", "fade_out_shape": "linear"})));
    assert_eq!(plain.plan_text(), named.plan_text());
    assert_eq!(plain.to_json(), named.to_json());
    assert!(!named.to_json().contains("fade_in_shape"));
    assert_eq!(
        json!(ramps(&plain)),
        json!([
            {"start": 0, "duration": SEC, "from": 0.0, "to": 1.0},
            {"start": SEC, "duration": 8 * SEC, "from": 1.0, "to": 1.0},
            {"start": 9 * SEC, "duration": SEC, "from": 1.0, "to": 0.0}
        ])
    );
}

#[test]
fn set_audio_sets_a_shape_and_refuses_an_unknown_one() {
    let handle = Handle::from_value(&one(json!({"fade_in": SEC})));
    let shaped = handle.apply(&json!({"op": "set_audio", "clips": [10],
        "patch": {"fade_in_shape": "s_curve", "fade_out_shape": "minus_3db"}}));
    assert_eq!(
        at(&shaped.value(), "/clips/0/audio/fade_in_shape"),
        &json!("s_curve")
    );
    assert_eq!(
        at(&shaped.value(), "/clips/0/audio/fade_out_shape"),
        &json!("minus_3db")
    );
    let error = handle.errors(&json!({"op": "set_audio", "clips": [10],
        "patch": {"fade_in_shape": "cubic"}}));
    assert!(error.contains("fade_in_shape"), "{error}");
}

// ---- the crossfade -------------------------------------------------------

/// Two clips on one track, 0–6 s and 5–11 s, overlapping by 1 s, the later
/// one's transition linear and crossfading in `shape` (absent for `None`).
fn pair(shape: Option<&str>) -> Value {
    let mut transition = json!({"kind": "cross_dissolve", "curve": "linear", "audio": true});
    if let Some(shape) = shape {
        transition["audio_shape"] = json!(shape);
    }
    json!({
        "version": 29,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/1.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": [{"id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "audio": {}},
                  {"id": 12, "track": 2, "start": 5 * SEC, "duration": 6 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 5 * SEC}, "audio": {},
                   "transition_in": transition}],
        "next_id": 100
    })
}

/// The ramps of the composition audio track carrying `clip`.
fn track_of(plan: &Value, clip: u32) -> Vec<Value> {
    for track in array(plan, "/audio_tracks") {
        if array(track, "/segments")
            .iter()
            .any(|s| s["clip"] == json!(clip))
        {
            return array(track, "/ramps").clone();
        }
    }
    panic!("no track carries {clip}");
}

#[test]
fn each_crossfade_shape_fades_in_by_gain_p_and_out_by_gain_one_minus_p() {
    for shape in SHAPES {
        let plan = Handle::from_value(&pair(Some(shape))).plan();
        let p = |t: i64| (t - 5 * SEC) as f64 / SEC as f64;
        let incoming = |t: i64| formula(shape, p(t));
        let outgoing = |t: i64| {
            if shape == "plus_3db" {
                (p(t) * FRAC_PI_2).cos()
            } else {
                formula(shape, 1.0 - p(t))
            }
        };
        assert_on(&track_of(&plan, 12), 5 * SEC, 6 * SEC, &incoming, shape);
        assert_on(&track_of(&plan, 11), 5 * SEC, 6 * SEC, &outgoing, shape);
    }
}

/// The default crossfade's ramp ends, pinned as the text the plan carried
/// before format 29 (R5-2's `cos(p·π/2)` out and `sin(p·π/2)` in, on the
/// 1/30 s grid over a linear 1 s overlap). Bit for bit: `sin((1 − p)·π/2)`
/// is the same curve and would end at 0 where `cos(π/2)` ends at 6.1e-17.
const PINNED_OUT: &str = "1.0,0.9986295347545738,0.9945218953682732,0.9876883405951378,\
0.9781476007338056,0.9659258262890684,0.9510565162951536,0.9335804264972016,\
0.9135454576426008,0.8910065241883679,0.8660254037844387,0.838670567945424,\
0.8090169943749475,0.7771459614569708,0.7431448254773942,0.7071067811865476,\
0.6691306063588582,0.6293203910498375,0.5877852522924731,0.5446390350150271,\
0.5000000000000001,0.45399049973954686,0.4067366430758004,0.35836794954530016,\
0.30901699437494745,0.25881904510252074,0.20791169081775923,0.15643446504023092,\
0.10452846326765346,0.052335956242943966,6.123233995736766e-17";
const PINNED_IN: &str = "0.05233595624294383,0.10452846326765346,0.15643446504023087,\
0.20791169081775931,0.25881904510252074,0.3090169943749474,0.35836794954530027,\
0.40673664307580015,0.4539904997395468,0.49999999999999994,0.544639035015027,\
0.5877852522924731,0.6293203910498375,0.6691306063588582,0.7071067811865475,\
0.7431448254773942,0.7771459614569708,0.8090169943749475,0.8386705679454239,\
0.8660254037844386,0.8910065241883679,0.9135454576426008,0.9335804264972016,\
0.9510565162951536,0.9659258262890684,0.9781476007338056,0.9876883405951378,\
0.9945218953682732,0.9986295347545738,1.0,1.0";

#[test]
fn the_default_crossfade_is_r5_2_s_law_bit_for_bit() {
    let plan = Handle::from_value(&pair(None)).plan();
    let ends = |clip: u32| -> String {
        track_of(&plan, clip)
            .iter()
            .map(|r| format!("{}", r["to"]))
            .collect::<Vec<_>>()
            .join(",")
    };
    assert_eq!(ends(11), PINNED_OUT);
    assert_eq!(ends(12), PINNED_IN);
}

#[test]
fn plus_3db_is_the_default_and_plans_as_before() {
    let absent = Handle::from_value(&pair(None));
    let named = Handle::from_value(&pair(Some("plus_3db")));
    assert_eq!(absent.plan_text(), named.plan_text());
    assert_eq!(absent.to_json(), named.to_json());
    assert!(!named.to_json().contains("audio_shape"));
    // A minted transition keeps the default and writes no key.
    let cut = Handle::from_value(&json!({
        "version": 29, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/1.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": [{"id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "audio": {}}],
        "next_id": 100}));
    let minted = cut.apply(&json!({"op": "set_transition_style", "clip": 11, "audio": true}));
    let stored = at(&minted.value(), "/clips/0/transition_in").clone();
    assert_eq!(stored["audio"], json!(true));
    assert!(stored.get("audio_shape").is_none(), "{stored}");
}

#[test]
fn set_transition_style_sets_the_shape_and_keeps_it_when_absent() {
    let handle = Handle::from_value(&pair(None));
    let shaped = handle.apply(&json!({"op": "set_transition_style", "clip": 12,
                                      "audio_shape": "s_curve"}));
    let stored = at(&shaped.value(), "/clips/1/transition_in").clone();
    assert_eq!(stored["audio_shape"], json!("s_curve"));
    assert_eq!(stored["curve"], json!("linear"), "the other keys are kept");
    let eased = shaped.apply(&json!({"op": "set_transition_style", "clip": 12,
                                     "curve": "ease_in"}));
    assert_eq!(
        at(&eased.value(), "/clips/1/transition_in/audio_shape"),
        &json!("s_curve")
    );
    shaped.refuses(&json!({"op": "set_transition_style", "clip": 12,
                           "audio_shape": "s_curve"}));
    shaped.refuses(&json!({"op": "set_transition_style", "clip": 12}));
    let error = handle.errors(&json!({"op": "set_transition_style", "clip": 12,
                                      "audio_shape": "cubic"}));
    assert!(error.contains("unknown variant"), "{error}");
}
