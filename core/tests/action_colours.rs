//! Black-box tests for the model's colours inside an action (spec §11
//! G-43): every `[r, g, b, a]` key of `video` and `text`, and
//! `video.chroma.key`'s `[r, g, b]`, ramps in OKLab with straight alpha —
//! the blend a graphic `color` prop ramps with (G-40), in floating point.
//!
//! The oracles are `graphic/tests/oklab.json`'s cases (each case's bytes/255
//! in, the answer ×255 rounded compared to the fixture's bytes), the
//! fixture's red → blue middle `#8c53a2`, and arithmetic stated beside each
//! assertion. The fixture's other two readers are `graphic/tests/stdlib.rs`
//! and `core/tests/graphic_actions.rs`.

mod common;

use serde_json::{json, Map, Value};

use common::{array, at, int, Handle};

/// Ticks per second (spec §5.1), written out so a change to the timescale
/// fails here rather than moving with the tests.
const SEC: i64 = 600_000;

/// The shared OKLab fixture (spec §11 G-40, G-43 (b)).
const OKLAB: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../graphic/tests/oklab.json");

/// The nine colour keys of an action's state, by JSON pointer (G-43 (a)),
/// with each one's arity.
const COLOUR_KEYS: [(&str, usize); 9] = [
    ("/video/shadow/color", 4),
    ("/video/chroma/key", 3),
    ("/text/color", 4),
    ("/text/outline/color", 4),
    ("/text/backdrop/color", 4),
    ("/text/word_style/active_color", 4),
    ("/text/word_style/spoken_color", 4),
    ("/text/word_style/upcoming_color", 4),
    ("/text/word_style/active_pill/color", 4),
];

const RED: [f64; 4] = [1.0, 0.0, 0.0, 1.0];
const BLUE: [f64; 4] = [0.0, 0.0, 1.0, 1.0];

/// A text clip, id 11, on track 2 for 10 s, with every colour group present:
/// shadow, chroma, outline, backdrop and a word style holding all three
/// colours and the pill.
fn full_clip() -> Value {
    json!({
        "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
        "source": {"kind": "text"},
        "video": {
            "shadow": {"color": [0.1, 0.1, 0.1, 1.0], "opacity": 0.5, "blur": 12.0,
                       "angle": 315.0, "distance": 8.0},
            "chroma": {"key": [0.0, 1.0, 0.0], "tolerance": 0.2, "softness": 0.1,
                       "spill": 0.5}
        },
        "text": {
            "content": "Hello there",
            "color": [1.0, 1.0, 1.0, 1.0],
            "outline": {"width": 2.0, "color": [0.0, 0.0, 0.0, 1.0]},
            "backdrop": {"color": [0.0, 0.0, 0.0, 0.6], "padding": 12.0, "radius": 8.0},
            "word_style": {
                "active_color": [1.0, 0.8, 0.0, 1.0],
                "spoken_color": [0.8, 0.8, 0.8, 1.0],
                "upcoming_color": [0.5, 0.5, 0.5, 1.0],
                "active_pill": {"color": [0.55, 0.27, 0.93, 1.0], "padding": 0.2,
                                "radius": 0.25, "glide": false}
            }
        }
    })
}

/// A project holding `clip` alone.
fn project(clip: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 1,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0.0, 0.0, 0.0, 1.0],
            "fit_new_clips": true, "timecode_frames": true
        },
        "media": [],
        "tracks": [{"id": 2, "name": "Track 2"}],
        "clips": [clip],
        "markers": [],
        "next_id": 30
    }))
}

/// Writes `value` at `pointer` inside `target`, making each object on the
/// way.
fn put(target: &mut Value, pointer: &str, value: Value) {
    let keys: Vec<&str> = pointer.trim_start_matches('/').split('/').collect();
    let mut here = target;
    for key in &keys[..keys.len() - 1] {
        if !here.get(*key).is_some_and(Value::is_object) {
            here[*key] = Value::Object(Map::new());
        }
        here = &mut here[*key];
    }
    here[keys[keys.len() - 1]] = value;
}

/// `clip` with one linear action, id 21, from 1 s for `duration`, whose end
/// holds `value` at `pointer`.
fn with_action(mut clip: Value, pointer: &str, value: Value, duration: i64) -> Value {
    let mut end = json!({});
    put(&mut end, pointer, value);
    clip["actions"] = json!([{
        "id": 21, "start": SEC, "duration": duration, "curve": "linear", "end": end
    }]);
    clip
}

/// The first `n` channels of `colour`, as given.
fn colour(value: &[f64], n: usize) -> Value {
    json!(value[..n].to_vec())
}

/// The numbers at `pointer`.
fn channels(value: &Value, pointer: &str) -> Vec<f64> {
    array(value, pointer)
        .iter()
        .map(|v| v.as_f64().unwrap_or_else(|| panic!("{v} at {pointer}")))
        .collect()
}

/// Each channel ×255, rounded to the nearest byte.
fn bytes(channels: &[f64]) -> Vec<i64> {
    channels
        .iter()
        .map(|v| (v * 255.0).round() as i64)
        .collect()
}

/// The bytes of a `#rrggbb[aa]` colour, alpha 255 when absent.
fn hex_bytes(colour: &Value) -> [i64; 4] {
    let text = colour.as_str().unwrap_or_else(|| panic!("{colour}"));
    let hex = text.strip_prefix('#').expect("a # colour");
    let pair = |i: usize| i64::from_str_radix(&hex[i..i + 2], 16).expect("hex");
    let alpha = if hex.len() == 8 { pair(6) } else { 255 };
    [pair(0), pair(2), pair(4), alpha]
}

fn state(handle: &Handle, clip: u32, t: i64) -> Value {
    handle
        .clip_state(clip, t)
        .unwrap_or_else(|| panic!("clip {clip}"))
}

/// The clip a split made, by its id not being 11.
fn tail(handle: &Handle) -> Value {
    let value = handle.value();
    array(&value, "/clips")
        .iter()
        .find(|c| int(c, "/id") != 11)
        .expect("the tail")
        .clone()
}

#[test]
fn every_colour_key_ramps_in_oklab() {
    for (pointer, arity) in COLOUR_KEYS {
        let mut clip = full_clip();
        put(&mut clip, pointer, colour(&RED, arity));
        let handle = project(with_action(clip, pointer, colour(&BLUE, arity), 2 * SEC));
        // 1 s into a 2 s linear action: u = 0.5, oklab.json's red → blue
        // middle `#8c53a2`; channel by channel it would be [0.5, 0, 0.5].
        let mid = state(&handle, 11, 2 * SEC);
        let expected: Vec<i64> = [140, 83, 162, 255][..arity].to_vec();
        assert_eq!(bytes(&channels(&mid, pointer)), expected, "{pointer}");
    }
}

/// G-43 (b): `oklab.json` through the unit path, each case's bytes/255 in
/// and ×255 rounded out — all four channels through `text.color`, the rgb
/// through `video.chroma.key`.
#[test]
fn the_float_blend_answers_the_shared_oklab_fixture() {
    let text = std::fs::read_to_string(OKLAB).expect("graphic/tests/oklab.json");
    let fixture: Value = serde_json::from_str(&text).expect("the OKLab fixture is JSON");
    let blends = fixture["blends"].as_array().expect("blends");
    assert!(!blends.is_empty());
    for case in blends {
        let unit = |c: &Value| hex_bytes(c).map(|b| b as f64 / 255.0);
        let (from, to) = (unit(&case[0]), unit(&case[1]));
        let t = case[2].as_f64().expect("t");
        let at_t = SEC + (t * SEC as f64) as i64;
        let expected = hex_bytes(&case[3]);
        for (pointer, arity) in [("/text/color", 4), ("/video/chroma/key", 3)] {
            let mut clip = full_clip();
            put(&mut clip, pointer, colour(&from, arity));
            let handle = project(with_action(clip, pointer, colour(&to, arity), SEC));
            let blended = state(&handle, 11, at_t);
            assert_eq!(
                bytes(&channels(&blended, pointer)),
                expected[..arity].to_vec(),
                "{pointer} {case}"
            );
        }
    }
}

#[test]
fn the_recipe_draws_the_blended_colour() {
    let mut clip = full_clip();
    put(&mut clip, "/text/color", json!(RED));
    let handle = project(with_action(clip, "/text/color", json!(BLUE), 2 * SEC));
    let recipe = handle.recipe(2 * SEC);
    let layer = array(&recipe, "/layers")
        .iter()
        .find(|l| int(l, "/clip") == 11)
        .expect("the text layer")
        .clone();
    let drawn = channels(&layer, "/source/text/color");
    let inspected = channels(&state(&handle, 11, 2 * SEC), "/text/color");
    assert_eq!(drawn, inspected);
    assert_eq!(bytes(&drawn), vec![140, 83, 162, 255]);
}

/// stdlib.js's `__toLinear`, `__toOklab`, `__fromOklab`, `__fromLinear`
/// on units, the test's own copy: one colour's round trip, unmixed.
fn round_trip(rgb: [f64; 3]) -> [f64; 3] {
    let lin = |v: f64| {
        if v <= 0.04045 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    };
    let srgb = |v: f64| {
        let s = if v <= 0.0031308 {
            12.92 * v
        } else {
            1.055 * v.powf(1.0 / 2.4) - 0.055
        };
        s.clamp(0.0, 1.0)
    };
    let (lr, lg, lb) = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]));
    let l = (0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb).cbrt();
    let m = (0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb).cbrt();
    let s = (0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb).cbrt();
    let ok = [
        0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    ];
    let l = (ok[0] + 0.3963377774 * ok[1] + 0.2158037573 * ok[2]).powf(3.0);
    let m = (ok[0] - 0.1055613458 * ok[1] - 0.0638541728 * ok[2]).powf(3.0);
    let s = (ok[0] - 0.0894841775 * ok[1] - 1.291485548 * ok[2]).powf(3.0);
    [
        srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        srgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
    ]
}

#[test]
fn an_action_s_first_tick_is_the_stored_start() {
    let start = [0.3, 0.6, 0.9, 1.0];
    // The guard is what keeps this exact: blended at u = 0 the start would
    // come back through OKLab, which does not return it.
    assert_ne!(round_trip([start[0], start[1], start[2]]), [0.3, 0.6, 0.9]);
    let mut clip = full_clip();
    put(&mut clip, "/text/color", json!(start));
    let handle = project(with_action(clip, "/text/color", json!(BLUE), 2 * SEC));
    assert_eq!(state(&handle, 11, SEC)["in_action"], json!(21));
    assert_eq!(channels(&state(&handle, 11, SEC), "/text/color"), start);
    // And its end is its end.
    assert_eq!(
        channels(&state(&handle, 11, 3 * SEC), "/text/color"),
        BLUE.to_vec()
    );
}

#[test]
fn an_untouched_colour_stays_exact() {
    let handle = project(with_action(
        full_clip(),
        "/text/size",
        json!(144.0),
        2 * SEC,
    ));
    let white = vec![1.0, 1.0, 1.0, 1.0];
    let pill = vec![0.55, 0.27, 0.93, 1.0];
    let mid = state(&handle, 11, 2 * SEC);
    assert_eq!(at(&mid, "/text/size").as_f64(), Some(108.0));
    assert_eq!(channels(&mid, "/text/color"), white);
    assert_eq!(channels(&mid, "/text/word_style/active_pill/color"), pill);

    // A split mid-action writes the evaluated state as the second half's
    // base, so the drift would be saved; it has none to save.
    let split = handle.apply(&json!({"op": "split", "clips": [11], "at": 2 * SEC}));
    let tail = tail(&split);
    assert_eq!(channels(&tail, "/text/color"), white);
    assert_eq!(channels(&tail, "/text/word_style/active_pill/color"), pill);
}

#[test]
fn an_end_equal_to_its_start_in_other_spelling_stays_exact() {
    // The base's white is stored as floats; an end naming the same colour as
    // integers is the same colour, so it is not blended (no round-trip drift).
    let handle = project(with_action(
        full_clip(),
        "/text/color",
        json!([1, 1, 1, 1]),
        2 * SEC,
    ));
    let mid = state(&handle, 11, 2 * SEC);
    assert_eq!(channels(&mid, "/text/color"), vec![1.0, 1.0, 1.0, 1.0]);
}

#[test]
fn a_colour_that_does_not_read_holds() {
    let handle = project(with_action(
        full_clip(),
        "/text/word_style/active_color",
        Value::Null,
        2 * SEC,
    ));
    let mid = state(&handle, 11, 2 * SEC);
    assert_eq!(
        channels(&mid, "/text/word_style/active_color"),
        vec![1.0, 0.8, 0.0, 1.0]
    );
    let after = state(&handle, 11, 3 * SEC);
    assert_eq!(after["text"]["word_style"]["active_color"], Value::Null);

    // A chroma key end of four numbers is not a colour of the key's arity:
    // mid-action it holds its start exactly, as `lerp` holds two arrays of
    // different lengths.
    let four = project(with_action(
        full_clip(),
        "/video/chroma/key",
        json!([0.0, 0.0, 1.0, 1.0]),
        2 * SEC,
    ));
    assert_eq!(
        channels(&state(&four, 11, 2 * SEC), "/video/chroma/key"),
        vec![0.0, 1.0, 0.0]
    );
}

#[test]
fn an_out_of_range_end_blends_from_its_clamp() {
    let middle = |start: Value, end: Value| {
        let mut clip = full_clip();
        put(&mut clip, "/text/color", start);
        let handle = project(with_action(clip, "/text/color", end, 2 * SEC));
        channels(&state(&handle, 11, 2 * SEC), "/text/color")
    };
    assert_eq!(
        middle(json!(RED), json!([0.0, 0.0, 2.0, 1.0])),
        middle(json!(RED), json!(BLUE))
    );
    // Alpha too: 0.2 toward 1 is 0.6 halfway; toward an unclamped 3 it would
    // be 1.6, clamped to 1.
    let faint = json!([1.0, 0.0, 0.0, 0.2]);
    let clamped = middle(faint.clone(), json!(BLUE));
    assert!((clamped[3] - 0.6).abs() < 1e-12, "{clamped:?}");
    assert_eq!(middle(faint, json!([0.0, 0.0, 1.0, 3.0])), clamped);
}

#[test]
fn a_split_through_a_colour_ramp_joins_exactly() {
    let mut clip = full_clip();
    put(&mut clip, "/text/color", json!([0.2, 0.4, 0.6, 1.0]));
    let whole = project(with_action(
        clip,
        "/text/color",
        json!([0.6, 0.5, 0.3, 1.0]),
        2 * SEC,
    ));
    let cut = 2 * SEC;
    let split = whole.apply(&json!({"op": "split", "clips": [11], "at": cut}));
    let tail = int(&tail(&split), "/id") as u32;
    let colour_of = |h: &Handle, id: u32, t: i64| channels(&state(h, id, t), "/text/color");

    // The pair either side of the cut: the head's end state (its shortened
    // action finished) and the tail's first tick, both the unsplit clip's
    // value at the cut, exactly.
    let at_cut = colour_of(&whole, 11, cut);
    assert_eq!(colour_of(&split, 11, cut), at_cut);
    assert_eq!(colour_of(&split, tail, cut), at_cut);

    // Inside each half the blend restarts from the cut's colour, so a sample
    // matches the unsplit ramp within the matrices' round trip.
    for (id, t) in [(11, SEC + SEC / 2), (tail, 2 * SEC + SEC / 2)] {
        let (a, b) = (colour_of(&split, id, t), colour_of(&whole, 11, t));
        for (x, y) in a.iter().zip(&b) {
            assert!((x - y).abs() < 1e-6, "clip {id} at {t}: {a:?} vs {b:?}");
        }
    }
}

/// Every pointer under `value` whose value is an array of 3 or 4 numbers.
fn census(value: &Value, pointer: String, out: &mut Vec<String>) {
    match value {
        Value::Array(list)
            if (3..=4).contains(&list.len()) && list.iter().all(Value::is_number) =>
        {
            out.push(pointer)
        }
        Value::Array(list) => {
            for (i, v) in list.iter().enumerate() {
                census(v, format!("{pointer}/{i}"), out);
            }
        }
        Value::Object(map) => {
            for (k, v) in map {
                census(v, format!("{pointer}/{k}"), out);
            }
        }
        _ => {}
    }
}

/// The test's own census, not the evaluator's rule: on the fully populated
/// clip, the arrays of 3 or 4 numbers under `video` and `text` are the nine
/// colour keys. A non-colour the census finds is excluded here by name.
#[test]
fn the_colour_keys_are_every_colour_in_the_state() {
    let handle = project(full_clip());
    let state = state(&handle, 11, 0);
    let mut found = Vec::new();
    census(at(&state, "/video"), "/video".to_string(), &mut found);
    census(at(&state, "/text"), "/text".to_string(), &mut found);
    found.sort();
    let mut expected: Vec<String> = COLOUR_KEYS.iter().map(|(p, _)| p.to_string()).collect();
    expected.sort();
    assert_eq!(found, expected);
}
