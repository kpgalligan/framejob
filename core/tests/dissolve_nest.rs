//! Black-box tests for routed dissolves (spec §7.3 `dissolve`, §11 MT-8),
//! driven through the C FFI's frame recipe exactly as `ReelCore.swift`
//! drives it.
//!
//! A `cross_dissolve` or `zoom` whose container is a nest, or one of whose
//! clips is a nest clip, is ROUTED: an entry in each half's layers'
//! `dissolve`, never their `transition`. Every expected answer below is the
//! rule applied on paper to the project each test writes: which clips play
//! at the instant, which level each transition sits at, and where each half
//! is placed on a 1920×1080 canvas.

mod common;

use serde_json::{json, Value};

use common::{array, Handle};
use framejob_core::format::RC_FORMAT_VERSION;

/// Ticks per second (spec §5.1), written out so a change to the timescale
/// fails here rather than moving with the tests.
const SEC: i64 = 600_000;
/// Half way through every overlap below, which runs 1 s – 1.5 s.
const MID: i64 = SEC + SEC / 4;

fn track(id: u32) -> Value {
    json!({ "id": id, "name": format!("Track {id}") })
}

fn matte_track(id: u32) -> Value {
    json!({ "id": id, "name": format!("Track {id}"), "matte": "luma" })
}

fn text_clip(id: u32, on: u32, start: i64, duration: i64) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "text" }, "video": {}, "text": { "content": "A" }
    })
}

fn nest_clip(id: u32, on: u32, start: i64, duration: i64, shows: u32) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "nest", "project": shows }, "video": {}
    })
}

/// `clip` with a linear `kind` transition in.
fn into(mut clip: Value, kind: &str) -> Value {
    clip["transition_in"] = json!({ "kind": kind, "curve": "linear" });
    clip
}

fn nest(id: u32, tracks: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "id": id, "name": format!("Nest {id}"), "width": 1920, "height": 1080,
        "tracks": tracks, "clips": clips
    })
}

fn project(tracks: Vec<Value>, clips: Vec<Value>, nests: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": RC_FORMAT_VERSION,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": [], "tracks": tracks, "clips": clips, "markers": [],
        "next_id": 100, "nests": nests
    }))
}

/// Nest 4: text 6 at 0 – 1.5 s under text 7 at 1 s – 2 s on track 5,
/// dissolving (`kind`) from 1 s.
fn inner_pair(kind: &str) -> Value {
    nest(
        4,
        vec![track(5)],
        vec![
            text_clip(6, 5, 0, SEC + SEC / 2),
            into(text_clip(7, 5, SEC, SEC), kind),
        ],
    )
}

/// Each layer as (clip, its `dissolve` as (id, role) pairs).
fn chains(recipe: &Value) -> Vec<(u64, Vec<(u64, String)>)> {
    array(recipe, "/layers")
        .iter()
        .map(|l| {
            let chain = l["dissolve"].as_array().cloned().unwrap_or_default();
            let pairs = chain
                .iter()
                .map(|e| {
                    let id = e["id"].as_u64().expect("an id");
                    (id, e["role"].as_str().expect("a role").to_string())
                })
                .collect();
            (l["clip"].as_u64().expect("a clip"), pairs)
        })
        .collect()
}

fn layer(recipe: &Value, index: usize) -> Value {
    array(recipe, "/layers")[index].clone()
}

/// The contract the compositor walks by: among the layers drawn to one
/// place (the canvas, or one matte group), the layers of one id at one
/// depth are one contiguous run, every `out` before every `in`.
fn assert_contiguous(recipe: &Value) {
    let layers = array(recipe, "/layers");
    let mut places: Vec<Value> = layers.iter().map(|l| l["matte"]["into"].clone()).collect();
    places.dedup();
    for place in places {
        let drawn: Vec<&Value> = layers
            .iter()
            .filter(|l| l["matte"]["into"] == place)
            .collect();
        for depth in 0..4 {
            let at = |l: &Value| l["dissolve"][depth].clone();
            let ids: Vec<Value> = drawn.iter().map(|l| at(l)["id"].clone()).collect();
            for id in ids.iter().filter(|id| !id.is_null()) {
                let run: Vec<usize> = (0..drawn.len()).filter(|i| &ids[*i] == id).collect();
                let (first, last) = (run[0], run[run.len() - 1]);
                assert_eq!(
                    run.len(),
                    last - first + 1,
                    "id {id} at depth {depth} is split"
                );
                let roles: Vec<String> = run
                    .iter()
                    .map(|i| at(drawn[*i])["role"].to_string())
                    .collect();
                let ins = roles
                    .iter()
                    .position(|r| r == "\"in\"")
                    .unwrap_or(roles.len());
                assert!(
                    roles[ins..].iter().all(|r| r == "\"in\""),
                    "id {id} at depth {depth}: an out after an in: {roles:?}"
                );
            }
        }
    }
}

fn close(actual: &Value, expected: f64, what: &str) {
    let actual = actual
        .as_f64()
        .unwrap_or_else(|| panic!("{what} is not a number"));
    assert!(
        (actual - expected).abs() < 1e-9,
        "{what}: {actual} ≠ {expected}"
    );
}

#[test]
fn a_split_nest_clip_dissolving_into_itself_is_routed_one_id_out_then_in() {
    // Nest clip 10 plays 0 – 1.5 s, 11 plays 1 s – 2 s, both nest 4, which
    // holds text 7 (1 s – 2 s) and text 9 over the whole nest. At 1.25 s,
    // 10 shows nest time 1.25 (7 and 9), 11 nest time 0.25 (9 alone).
    let nested = nest(
        4,
        vec![track(5), track(8)],
        vec![text_clip(7, 5, SEC, SEC), text_clip(9, 8, 0, 2 * SEC)],
    );
    let handle = project(
        vec![track(2)],
        vec![
            nest_clip(10, 2, 0, SEC + SEC / 2, 4),
            into(nest_clip(11, 2, SEC, SEC, 4), "cross_dissolve"),
        ],
        vec![nested],
    );
    let recipe = handle.recipe(MID);
    let out = |c: u64| (c, vec![(0, "out".to_string())]);
    let inn = |c: u64| (c, vec![(0, "in".to_string())]);
    assert_eq!(chains(&recipe), vec![out(7), out(9), inn(9)]);
    for index in 0..3 {
        let l = layer(&recipe, index);
        assert_eq!(
            l["transition"],
            Value::Null,
            "a routed level is never `transition`"
        );
        assert_eq!(l["dissolve"][0]["kind"], json!("cross_dissolve"));
        close(&l["dissolve"][0]["progress"], 0.5, "progress");
        // The nest clips sit at the canvas centre.
        assert_eq!(l["dissolve"][0]["anchor"], json!([960.0, 540.0]));
    }
    assert_contiguous(&recipe);
}

#[test]
fn plain_into_nest_and_nest_into_plain_are_both_routed() {
    let mut plain = text_clip(3, 2, 0, SEC + SEC / 2);
    plain["video"] = json!({ "x": 100.0, "y": -50.0 });
    let inner = nest(4, vec![track(5)], vec![text_clip(6, 5, 0, 2 * SEC)]);
    let handle = project(
        vec![track(2)],
        vec![plain, into(nest_clip(10, 2, SEC, SEC, 4), "cross_dissolve")],
        vec![inner.clone()],
    );
    let recipe = handle.recipe(MID);
    assert_eq!(
        chains(&recipe),
        vec![
            (3, vec![(0, "out".to_string())]),
            (6, vec![(0, "in".to_string())])
        ]
    );
    // The plain half's anchor is its own: the canvas centre plus (x, y).
    assert_eq!(
        layer(&recipe, 0)["dissolve"][0]["anchor"],
        json!([1060.0, 490.0])
    );
    assert_eq!(
        layer(&recipe, 1)["dissolve"][0]["anchor"],
        json!([960.0, 540.0])
    );
    assert_contiguous(&recipe);

    let handle = project(
        vec![track(2)],
        vec![
            nest_clip(10, 2, 0, SEC + SEC / 2, 4),
            into(text_clip(3, 2, SEC, SEC), "cross_dissolve"),
        ],
        vec![inner],
    );
    let recipe = handle.recipe(MID);
    assert_eq!(
        chains(&recipe),
        vec![
            (6, vec![(0, "out".to_string())]),
            (3, vec![(0, "in".to_string())])
        ]
    );
    assert_contiguous(&recipe);
}

#[test]
fn a_dissolve_inside_a_nest_is_routed_and_keyed_by_the_nest_clip_showing_it() {
    // Nest 4 shown twice at once, by 10 on track 2 and 11 on track 3: two
    // dissolves, two ids, first seen first.
    let mut shown = nest_clip(10, 2, 0, 2 * SEC, 4);
    shown["video"] = json!({ "x": -100.0 });
    let handle = project(
        vec![track(2), track(3)],
        vec![shown, nest_clip(11, 3, 0, 2 * SEC, 4)],
        vec![inner_pair("cross_dissolve")],
    );
    let recipe = handle.recipe(MID);
    assert_eq!(
        chains(&recipe),
        vec![
            (6, vec![(0, "out".to_string())]),
            (7, vec![(0, "in".to_string())]),
            (6, vec![(1, "out".to_string())]),
            (7, vec![(1, "in".to_string())]),
        ]
    );
    // At the layer's own level the anchor is the layer's: 10 moved its
    // contents 100 px left.
    assert_eq!(
        layer(&recipe, 0)["dissolve"][0]["anchor"],
        json!([860.0, 540.0])
    );
    assert_eq!(
        layer(&recipe, 2)["dissolve"][0]["anchor"],
        json!([960.0, 540.0])
    );
    assert_contiguous(&recipe);
}

#[test]
fn a_dissolve_inside_a_dissolving_half_is_a_chain_outermost_first() {
    // Nest clip 10 (0 – 1.5 s, nest 4's inner dissolve at 1 s) dissolving
    // into text 3 (1 s – 2 s).
    let handle = project(
        vec![track(2)],
        vec![
            nest_clip(10, 2, 0, SEC + SEC / 2, 4),
            into(text_clip(3, 2, SEC, SEC), "cross_dissolve"),
        ],
        vec![inner_pair("cross_dissolve")],
    );
    let recipe = handle.recipe(MID);
    let (o, i) = ("out".to_string(), "in".to_string());
    assert_eq!(
        chains(&recipe),
        vec![
            (6, vec![(0, o.clone()), (1, o.clone())]),
            (7, vec![(0, o.clone()), (1, i.clone())]),
            (3, vec![(0, i)]),
        ]
    );
    assert_contiguous(&recipe);
}

#[test]
fn a_layer_drawn_into_a_matte_keeps_only_the_dissolves_at_or_inside_its_matte_level() {
    // Nest 4: a card (text 6) on track 5 under a luma matte track 8 whose
    // two clips dissolve at 1 s. Nest clip 10 dissolves into text 3.
    let inner = nest(
        4,
        vec![track(5), matte_track(8)],
        vec![
            text_clip(6, 5, 0, 2 * SEC),
            text_clip(9, 8, 0, SEC + SEC / 2),
            into(text_clip(12, 8, SEC, SEC), "cross_dissolve"),
        ],
    );
    let build = |outer: &str| {
        project(
            vec![track(2)],
            vec![
                nest_clip(10, 2, 0, SEC + SEC / 2, 4),
                into(text_clip(3, 2, SEC, SEC), outer),
            ],
            vec![inner.clone()],
        )
    };
    let recipe = build("cross_dissolve").recipe(MID);
    let (o, i) = ("out".to_string(), "in".to_string());
    // The card is cut, so it keeps the outer dissolve (id 0); each matte
    // clip keeps its own matte-level dissolve (id 1) and drops the outer.
    assert_eq!(
        chains(&recipe),
        vec![
            (6, vec![(0, o.clone())]),
            (9, vec![(1, o.clone())]),
            (12, vec![(1, i.clone())]),
            (3, vec![(0, i)]),
        ]
    );
    assert_eq!(layer(&recipe, 1)["matte"]["into"], json!(0));
    assert_eq!(layer(&recipe, 1)["transition"], Value::Null);
    assert_contiguous(&recipe);

    // An unrouted transition outside the matte level is still the matte
    // layer's `transition`: only routed levels stop there.
    let recipe = build("push_left").recipe(MID);
    let matte_clip = layer(&recipe, 1);
    assert_eq!(matte_clip["transition"]["kind"], json!("push_left"));
    assert_eq!(matte_clip["transition"]["role"], json!("out"));
    assert_eq!(chains(&recipe)[1], (9, vec![(0, o)]));
}

#[test]
fn transition_is_the_innermost_unrouted_level_and_either_forces_normal() {
    // Inner wipe, outer dissolve: the wipe is the transition, the dissolve
    // the chain.
    let mut inner = inner_pair("wipe");
    inner["clips"][0]["video"] = json!({ "blend": "screen" });
    let handle = project(
        vec![track(2)],
        vec![
            nest_clip(10, 2, 0, SEC + SEC / 2, 4),
            into(text_clip(3, 2, SEC, SEC), "cross_dissolve"),
        ],
        vec![inner],
    );
    let first = layer(&handle.recipe(MID), 0);
    assert_eq!(first["transition"]["kind"], json!("wipe"));
    assert_eq!(first["transition"]["partner"], json!(7));
    assert_eq!(first["dissolve"].as_array().map(Vec::len), Some(1));
    assert_eq!(first["blend"], json!("normal"));

    // Inner dissolve, outer push: the push is inherited as the transition
    // and the inner dissolve is routed.
    let handle = project(
        vec![track(2)],
        vec![
            nest_clip(10, 2, 0, SEC + SEC / 2, 4),
            into(text_clip(3, 2, SEC, SEC), "push_left"),
        ],
        vec![inner_pair("cross_dissolve")],
    );
    let first = layer(&handle.recipe(MID), 0);
    assert_eq!(first["transition"]["kind"], json!("push_left"));
    assert_eq!(first["transition"]["partner"], json!(3));
    assert_eq!(first["dissolve"][0]["role"], json!("out"));

    // A routed dissolve alone forces normal on a layer that screens, and
    // past the overlap the layer blends again.
    let mut inner = nest(4, vec![track(5)], vec![text_clip(6, 5, 0, 2 * SEC)]);
    inner["clips"][0]["video"] = json!({ "blend": "screen" });
    let handle = project(
        vec![track(2)],
        vec![
            nest_clip(10, 2, 0, SEC + SEC / 2, 4),
            into(text_clip(3, 2, SEC, SEC), "cross_dissolve"),
        ],
        vec![inner],
    );
    let first = layer(&handle.recipe(MID), 0);
    assert_eq!(first["transition"], Value::Null);
    assert_eq!(first["blend"], json!("normal"));
    assert_eq!(layer(&handle.recipe(SEC / 2), 0)["blend"], json!("screen"));
}

#[test]
fn a_routed_zoom_names_its_kind_and_a_moved_nest_clip_anchors_at_its_rect_centre() {
    // Nest clip 10 at (300, -100), half size, its left 200 nest pixels
    // cropped away: the nest spans 780 – 1740 across, the crop takes 100
    // canvas pixels off the left, so the shown rect's centre is 1310; down,
    // 540 − 100 = 440.
    let mut moved = nest_clip(10, 2, 0, SEC + SEC / 2, 4);
    moved["video"] = json!({
        "x": 300.0, "y": -100.0, "scale": 0.5,
        "crop": { "l": 200.0, "t": 0.0, "r": 0.0, "b": 0.0 }
    });
    let handle = project(
        vec![track(2)],
        vec![moved, into(nest_clip(11, 2, SEC, SEC, 4), "zoom")],
        vec![nest(4, vec![track(5)], vec![text_clip(6, 5, 0, 2 * SEC)])],
    );
    let recipe = handle.recipe(MID);
    let out = layer(&recipe, 0);
    let incoming = layer(&recipe, 1);
    assert_eq!(out["dissolve"][0]["kind"], json!("zoom"));
    assert_eq!(out["transition"], Value::Null);
    assert_eq!(out["dissolve"][0]["anchor"], json!([1310.0, 440.0]));
    assert_eq!(incoming["dissolve"][0]["role"], json!("in"));
    assert_eq!(incoming["dissolve"][0]["anchor"], json!([960.0, 540.0]));
}

#[test]
fn a_timeline_dissolve_or_zoom_between_plain_clips_is_left_unrouted() {
    for kind in ["zoom", "cross_dissolve"] {
        let handle = project(
            vec![track(2)],
            vec![
                text_clip(3, 2, 0, SEC + SEC / 2),
                into(text_clip(4, 2, SEC, SEC), kind),
            ],
            vec![],
        );
        let recipe = handle.recipe(MID);
        for index in 0..2 {
            let l = layer(&recipe, index);
            assert_eq!(l["dissolve"], Value::Null, "{kind}: no dissolve");
            assert_eq!(l["transition"]["kind"], json!(kind));
        }
        assert_eq!(layer(&recipe, 0)["transition"]["partner"], json!(4));
    }
}
