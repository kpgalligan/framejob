//! Black-box tests for mattes and nesting (spec §11 MT-5; `nest` and
//! `unnest`, spec §6b), driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! The nest clip lands on the front-most selected track that is not a matte
//! track; a nested track keeps its source's matte only when the nested track
//! directly behind it is the copy of that matte's target (the carry rule);
//! `unnest` lines the nest's front-most NON-matte track up with the nest
//! clip's track. Every expected answer is that rule applied on paper to the
//! stack each test builds. What a matte does at one instant is `matte.rs`'s.

mod common;

use serde_json::{json, Value};

use common::{array, Handle};

/// Ticks per second (spec §5.1), written out so a change to the timescale
/// fails here rather than moving with the tests.
const SEC: i64 = 600_000;

fn id(value: &Value) -> u32 {
    u32::try_from(value.as_u64().expect("an id")).expect("an id fits in u32")
}

/// A new track at the front of the stack, and its id.
fn add_track(handle: Handle) -> (Handle, u32) {
    let next = handle.apply(&json!({"op": "add_track"}));
    let track = id(&array(&next.value(), "/tracks").last().expect("a track")["id"]);
    (next, track)
}

/// A rectangle on `track` over `[0, duration)`, and its id.
fn shape(handle: Handle, track: u32, duration: i64) -> (Handle, u32) {
    let before: Vec<Value> = array(&handle.value(), "/clips").clone();
    let next = handle.apply(&json!({
        "op": "add_shape_clip", "track": track, "at": 0, "duration": duration
    }));
    let made = array(&next.value(), "/clips")
        .iter()
        .find(|c| !before.iter().any(|b| b["id"] == c["id"]))
        .map(|c| id(&c["id"]))
        .expect("a new clip");
    (next, made)
}

fn set_matte(handle: &Handle, track: u32, mode: &str) -> Handle {
    handle.apply(&json!({"op": "set_track", "track": track, "matte": mode}))
}

/// The one nest clip on the timeline, and the nest it shows.
fn nest_clip(handle: &Handle) -> (Value, Value) {
    let value = handle.value();
    let clip = array(&value, "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .cloned()
        .expect("a nest clip");
    let nest = array(&value, "/nests")
        .iter()
        .find(|n| n["id"] == clip["source"]["project"])
        .cloned()
        .expect("its nest");
    (clip, nest)
}

/// Each nested track's matte, back to front; `"none"` for no key.
fn nested_mattes(nest: &Value) -> Vec<String> {
    array(nest, "/tracks")
        .iter()
        .map(|t| t["matte"].as_str().unwrap_or("none").to_string())
        .collect()
}

/// Each timeline track's matte, back to front.
fn mattes(handle: &Handle) -> Vec<String> {
    array(&handle.value(), "/tracks")
        .iter()
        .map(|t| t["matte"].as_str().unwrap_or("none").to_string())
        .collect()
}

/// Every layer of the recipe drawn by `clip`, in recipe order.
fn layers(recipe: &Value, clip: u32) -> Vec<Value> {
    array(recipe, "/layers")
        .iter()
        .filter(|l| l["clip"] == json!(clip))
        .cloned()
        .collect()
}

/// A on track 1 under B on track 2, B's track an `alpha` matte; answers the
/// handle and (track 1, track 2, A, B).
fn pair() -> (Handle, u32, u32, u32, u32) {
    let handle = Handle::new(640, 360, 30, 1);
    let back = 1;
    let (handle, front) = add_track(handle);
    let (handle, a) = shape(handle, back, SEC);
    let (handle, b) = shape(handle, front, SEC);
    (set_matte(&handle, front, "alpha"), back, front, a, b)
}

#[test]
fn nesting_a_matte_pair_lands_on_the_target_track_and_carries_the_matte() {
    let (handle, back, front, a, b) = pair();
    let nested = handle.apply(&json!({"op": "nest", "clips": [a, b]}));
    let (clip, nest) = nest_clip(&nested);
    // The front-most selected track that is not a matte: A's.
    assert_eq!(clip["track"], json!(back));
    // B's copy is carried: the copy of its target is directly behind it.
    assert_eq!(nested_mattes(&nest), ["none", "alpha"]);
    // The timeline keeps its own tracks, the matte included.
    assert_eq!(mattes(&nested), ["none", "alpha"]);
    assert_eq!(array(&nested.value(), "/tracks")[1]["id"], json!(front));

    // At the instant, the pair cuts inside the nest, keyed by the nest
    // clip's path; the emptied top-level matte track lists nothing.
    let recipe = nested.recipe(SEC / 2);
    assert_eq!(
        layers(&recipe, a)[0]["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(
        layers(&recipe, b)[0]["matte"],
        json!({"into": 0, "cut": []})
    );
    assert_eq!(recipe["mattes"], json!([{"group": 0, "mode": "alpha"}]));
}

#[test]
fn nesting_only_matte_clips_lands_on_the_matte_track_and_carries_nothing() {
    let (handle, back, front, a, b) = pair();
    let nested = handle.apply(&json!({"op": "nest", "clips": [b]}));
    let (clip, nest) = nest_clip(&nested);
    // All selected tracks are mattes: the front-most of them.
    assert_eq!(clip["track"], json!(front));
    // No target came along, so the nested track is ordinary.
    assert_eq!(nested_mattes(&nest), ["none"]);
    // The nest clip's whole composite is now the matte for A's track.
    let recipe = nested.recipe(SEC / 2);
    assert_eq!(
        layers(&recipe, a)[0]["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(
        layers(&recipe, b)[0]["matte"],
        json!({"into": 0, "cut": []})
    );
    assert_eq!(recipe["mattes"], json!([{"group": 0, "mode": "alpha"}]));
    assert_eq!(array(&nested.value(), "/tracks")[0]["id"], json!(back));
}

#[test]
fn the_carry_rule_keeps_a_matte_only_above_the_copy_of_its_target() {
    // Track 1 A, track 2 X, track 3 M (a matte for X). Nesting A and M
    // brings M without its target: the copy behind M's copy is A's.
    let handle = Handle::new(640, 360, 30, 1);
    let (handle, two) = add_track(handle);
    let (handle, three) = add_track(handle);
    let (handle, a) = shape(handle, 1, SEC);
    let (handle, _x) = shape(handle, two, SEC);
    let (handle, m) = shape(handle, three, SEC);
    let handle = set_matte(&handle, three, "luma");
    let nested = handle.apply(&json!({"op": "nest", "clips": [a, m]}));
    let (clip, nest) = nest_clip(&nested);
    assert_eq!(nested_mattes(&nest), ["none", "none"]);
    assert_eq!(clip["track"], json!(1));

    // A matte above a matte: the lower one is carried (its target is
    // directly behind it), the upper one is nobody's matte and is not.
    let handle = Handle::new(640, 360, 30, 1);
    let (handle, two) = add_track(handle);
    let (handle, three) = add_track(handle);
    let (handle, a) = shape(handle, 1, SEC);
    let (handle, m1) = shape(handle, two, SEC);
    let (handle, m2) = shape(handle, three, SEC);
    let handle = set_matte(&set_matte(&handle, two, "alpha"), three, "alpha");
    let nested = handle.apply(&json!({"op": "nest", "clips": [a, m1, m2]}));
    let (clip, nest) = nest_clip(&nested);
    assert_eq!(nested_mattes(&nest), ["none", "alpha", "none"]);
    assert_eq!(clip["track"], json!(1));
}

#[test]
fn unnesting_a_carried_matte_pair_puts_it_back_where_it_was() {
    let (handle, back, front, a, b) = pair();
    let before = handle.recipe(SEC / 2);
    let nested = handle.apply(&json!({"op": "nest", "clips": [a, b]}));
    let (clip, _) = nest_clip(&nested);
    let opened = nested.apply(&json!({"op": "unnest", "clip": id(&clip["id"])}));
    let value = opened.value();
    // No track was added and the timeline's matte is untouched.
    assert_eq!(mattes(&opened), ["none", "alpha"]);
    let tracks: Vec<u32> = array(&value, "/tracks")
        .iter()
        .map(|t| id(&t["id"]))
        .collect();
    assert_eq!(tracks, [back, front]);
    // A's copy on its own track, B's on the matte in front of it.
    let clips = array(&value, "/clips");
    assert_eq!(clips.len(), 2);
    let on = |track: u32| clips.iter().filter(|c| c["track"] == json!(track)).count();
    assert_eq!((on(back), on(front)), (1, 1));
    // The roles at the instant are the ones before nesting, ids aside.
    let after = opened.recipe(SEC / 2);
    let roles = |recipe: &Value| -> Vec<Value> {
        array(recipe, "/layers")
            .iter()
            .map(|l| l["matte"].clone())
            .collect()
    };
    assert_eq!(roles(&after), roles(&before));
    assert_eq!(after["mattes"], before["mattes"]);
}

#[test]
fn a_carried_matte_with_no_track_in_front_lands_on_a_new_ordinary_track() {
    let (handle, back, front, a, b) = pair();
    let nested = handle.apply(&json!({"op": "nest", "clips": [a, b]}));
    // The emptied matte track goes, so nothing is in front of the nest clip.
    let nested = nested.apply(&json!({"op": "remove_track", "track": front}));
    let (clip, _) = nest_clip(&nested);
    let opened = nested.apply(&json!({"op": "unnest", "clip": id(&clip["id"])}));
    let value = opened.value();
    let tracks = array(&value, "/tracks");
    assert_eq!(tracks.len(), 2);
    assert_eq!(tracks[0]["id"], json!(back));
    // `unnest` makes no track a matte: the matte clip now draws.
    assert_eq!(mattes(&opened), ["none", "none"]);
    assert_eq!(opened.recipe(SEC / 2)["mattes"], json!([]));
}

#[test]
fn a_split_nest_clip_in_a_dissolve_has_one_group_per_half() {
    // The pair over two seconds, nested, split at one second, and a half-
    // second dissolve made from the outgoing half's tail (a nest's head has
    // no handle). At 1.125 s both halves show the nest at once.
    let handle = Handle::new(640, 360, 30, 1);
    let (handle, front) = add_track(handle);
    let (handle, a) = shape(handle, 1, 2 * SEC);
    let (handle, b) = shape(handle, front, 2 * SEC);
    let handle = set_matte(&handle, front, "alpha");
    let nested = handle.apply(&json!({"op": "nest", "clips": [a, b]}));
    let (clip, _) = nest_clip(&nested);
    let first = id(&clip["id"]);
    let split = nested.apply(&json!({"op": "split", "clips": [first], "at": SEC}));
    let second = array(&split.value(), "/clips")
        .iter()
        .filter(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| id(&c["id"]))
        .find(|c| *c != first)
        .expect("the second half");
    let dissolved = split.apply(&json!({
        "op": "add_transition", "clip": second, "duration": SEC / 2, "align": "after"
    }));
    let recipe = dissolved.recipe(SEC + SEC / 8);
    let a_layers = layers(&recipe, a);
    let b_layers = layers(&recipe, b);
    assert_eq!((a_layers.len(), b_layers.len()), (2, 2), "{recipe}");
    // Two groups, one per half: each copy of B draws into its own, and each
    // copy of A is cut by exactly one of them, a different one.
    assert_eq!(array(&recipe, "/mattes").len(), 2, "{recipe}");
    let into: Vec<Value> = b_layers
        .iter()
        .map(|l| l["matte"]["into"].clone())
        .collect();
    let cut: Vec<Value> = a_layers.iter().map(|l| l["matte"]["cut"].clone()).collect();
    assert_ne!(into[0], into[1]);
    assert_ne!(cut[0], cut[1]);
    for (into, cut) in into.iter().zip(&cut) {
        assert_eq!(&json!([into]), cut);
    }
}
