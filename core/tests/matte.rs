//! Black-box tests for the matte track (format version 14, spec §11 MT-1,
//! MT-2, MT-4, MT-5; the recipe's `matte` and `mattes`, spec §7.3), driven
//! through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Every expected role below is MT-2's and MT-5's rule applied on paper to
//! the stack each test builds: which layer is drawn INTO which group, which
//! groups CUT it, which groups are LISTED and in what order. Nesting's own
//! matte rules (the front track, the carry, unnest's depth) are MT3's and
//! `matte_nest.rs`'s; what a file holds is `schema_v14.rs`'s.

mod common;

use serde_json::{json, Value};

use common::{array, Handle, Outcome};

/// Ticks per second (spec §5.1), written out so a change to the timescale
/// fails here rather than moving with the tests.
const SEC: i64 = 600_000;

/// The id of the last element of the array at `pointer` — what an op that
/// appends one (a track at the end, a clip) just minted.
fn last_id(handle: &Handle, pointer: &str) -> u32 {
    let value = handle.value();
    let ids = array(&value, pointer)
        .iter()
        .filter_map(|v| v["id"].as_u64())
        .max()
        .unwrap_or_else(|| panic!("no ids at {pointer}"));
    u32::try_from(ids).expect("an id fits in u32")
}

/// A new track at the front of the stack, and its id.
fn add_track(handle: Handle) -> (Handle, u32) {
    let next = handle.apply(&json!({"op": "add_track"}));
    let tracks = array(&next.value(), "/tracks").clone();
    let id = tracks
        .last()
        .and_then(|t| t["id"].as_u64())
        .expect("a track");
    (next, u32::try_from(id).expect("an id fits in u32"))
}

/// A white rectangle on `track` over `[0, duration)`, and its id.
fn shape(handle: Handle, track: u32, duration: i64) -> (Handle, u32) {
    let next = handle.apply(&json!({
        "op": "add_shape_clip", "track": track, "at": 0, "duration": duration
    }));
    let id = last_id(&next, "/clips");
    (next, id)
}

fn set_matte(handle: &Handle, track: u32, mode: &str) -> Handle {
    handle.apply(&json!({"op": "set_track", "track": track, "matte": mode}))
}

/// The layer drawn by `clip` in the recipe at `t`.
fn layer(recipe: &Value, clip: u32) -> Value {
    array(recipe, "/layers")
        .iter()
        .find(|l| l["clip"] == json!(clip))
        .cloned()
        .unwrap_or_else(|| panic!("no layer for clip {clip} in {recipe}"))
}

/// A on track 1 under B on track 2, both one second long; answers the
/// handle and (track 1, track 2, A, B).
fn pair() -> (Handle, u32, u32, u32, u32) {
    let handle = Handle::new(640, 360, 30, 1);
    let back = 1;
    let (handle, front) = add_track(handle);
    let (handle, a) = shape(handle, back, SEC);
    let (handle, b) = shape(handle, front, SEC);
    (handle, back, front, a, b)
}

#[test]
fn a_matte_pair_draws_into_one_listed_group_that_cuts_the_track_behind() {
    let (handle, _, front, a, b) = pair();
    let plain = handle.recipe(SEC / 2);
    assert_eq!(layer(&plain, a)["matte"], Value::Null);
    assert_eq!(layer(&plain, b)["matte"], Value::Null);
    assert_eq!(plain["mattes"], json!([]));

    let matted = set_matte(&handle, front, "alpha");
    let recipe = matted.recipe(SEC / 2);
    // Walking back to front, A is seen first, as a cut: group 0.
    assert_eq!(
        layer(&recipe, a)["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(layer(&recipe, b)["matte"], json!({"into": 0, "cut": []}));
    assert_eq!(recipe["mattes"], json!([{"group": 0, "mode": "alpha"}]));
    // The matte layer stays in `layers`, in its slot: the canvas hit test
    // reads it there.
    let order: Vec<Value> = array(&recipe, "/layers")
        .iter()
        .map(|l| l["clip"].clone())
        .collect();
    assert_eq!(order, [json!(a), json!(b)]);

    for mode in ["alpha_inverted", "luma", "luma_inverted"] {
        let recipe = set_matte(&handle, front, mode).recipe(SEC / 2);
        assert_eq!(
            recipe["mattes"],
            json!([{"group": 0, "mode": mode}]),
            "{mode}"
        );
    }
}

#[test]
fn a_back_most_matte_and_a_matte_behind_a_matte_draw_into_unlisted_groups() {
    // Back-most: the matte track has nothing behind it.
    let (handle, back, _, a, b) = pair();
    let recipe = set_matte(&handle, back, "alpha").recipe(SEC / 2);
    assert_eq!(layer(&recipe, a)["matte"], json!({"into": 0, "cut": []}));
    assert_eq!(layer(&recipe, b)["matte"], Value::Null);
    assert_eq!(recipe["mattes"], json!([]));

    // A matte behind a matte: the front one cuts nothing and still draws
    // nothing; the lower one still cuts A.
    let (handle, back, middle, a, m1) = pair();
    let (handle, top) = add_track(handle);
    let (handle, m2) = shape(handle, top, SEC);
    let handle = set_matte(&set_matte(&handle, middle, "alpha"), top, "luma");
    let recipe = handle.recipe(SEC / 2);
    assert_eq!(
        layer(&recipe, a)["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(layer(&recipe, m1)["matte"], json!({"into": 0, "cut": []}));
    assert_eq!(layer(&recipe, m2)["matte"], json!({"into": 1, "cut": []}));
    assert_eq!(recipe["mattes"], json!([{"group": 0, "mode": "alpha"}]));
    assert_eq!(handle.value()["tracks"][0]["id"], json!(back));
}

#[test]
fn a_matte_track_showing_nothing_cuts_nothing() {
    // Hidden.
    let (handle, _, front, a, b) = pair();
    let matted = set_matte(&handle, front, "alpha");
    let hidden = matted.apply(&json!({"op": "set_track", "track": front, "hidden": true}));
    let recipe = hidden.recipe(SEC / 2);
    assert_eq!(layer(&recipe, a)["matte"], Value::Null);
    assert!(array(&recipe, "/layers")
        .iter()
        .all(|l| l["clip"] != json!(b)));
    assert_eq!(recipe["mattes"], json!([]));

    // No clip at `t`: the matte clip ends before A does.
    let short = matted.apply(&json!({"op": "trim_end", "clip": b, "to": SEC / 2}));
    let recipe = short.recipe(SEC * 3 / 4);
    assert_eq!(layer(&recipe, a)["matte"], Value::Null);
    assert_eq!(recipe["mattes"], json!([]));
    // Inside the matte clip's span, A is cut.
    assert_eq!(
        layer(&short.recipe(SEC / 4), a)["matte"],
        json!({"into": null, "cut": [0]})
    );

    // Its video off.
    let off = matted.apply(&json!({"op": "set_enabled", "clip": b, "video": false}));
    let recipe = off.recipe(SEC / 2);
    assert_eq!(layer(&recipe, a)["matte"], Value::Null);
    assert_eq!(recipe["mattes"], json!([]));
}

#[test]
fn a_matte_layer_draws_normal_with_no_shadow_and_no_reflection_but_keeps_the_model() {
    let (handle, _, front, _, b) = pair();
    let styled = handle.apply(&json!({
        "op": "set_video", "clips": [b],
        "patch": {
            "blend": "multiply",
            "shadow": {"color": [0, 0, 0, 1], "opacity": 0.5, "blur": 4, "distance": 8, "angle": 45},
            "reflection": {"opacity": 0.5, "height": 0.5, "gap": 0, "falloff": 1}
        }
    }));
    let ordinary = layer(&styled.recipe(SEC / 2), b);
    assert_eq!(ordinary["blend"], json!("multiply"));
    assert!(!ordinary["shadow"].is_null());
    assert!(!ordinary["reflection"].is_null());

    let matted = set_matte(&styled, front, "alpha");
    let drawn = layer(&matted.recipe(SEC / 2), b);
    assert_eq!(drawn["blend"], json!("normal"));
    assert_eq!(drawn["shadow"], Value::Null);
    assert_eq!(drawn["reflection"], Value::Null);
    // The model keeps every value, for when the track stops being a matte.
    let state = matted.clip_state(b, SEC / 2).expect("clip b");
    assert_eq!(state["video"]["blend"], json!("multiply"));
    assert!(!state["video"]["shadow"].is_null());
    assert!(!state["video"]["reflection"].is_null());
    let back = set_matte(&matted, front, "none");
    assert_eq!(layer(&back.recipe(SEC / 2), b), ordinary);
}

#[test]
fn an_unchanged_matte_is_an_identity_and_an_unknown_one_is_refused_by_name() {
    let (handle, back, front, _, _) = pair();
    let same = |h: &Handle, track: u32, mode: &str| {
        h.try_apply(&json!({"op": "set_track", "track": track, "matte": mode}))
    };
    assert!(matches!(
        same(&handle, front, "none"),
        Ok(Outcome::Identity)
    ));
    let matted = set_matte(&handle, front, "luma");
    assert!(matches!(
        same(&matted, front, "luma"),
        Ok(Outcome::Identity)
    ));
    assert!(matches!(same(&matted, back, "none"), Ok(Outcome::Identity)));

    let message = handle.errors(&json!({"op": "set_track", "track": front, "matte": "chroma"}));
    for name in [
        "`chroma`",
        "`none`",
        "`alpha`",
        "`alpha_inverted`",
        "`luma`",
        "`luma_inverted`",
    ] {
        assert!(message.contains(name), "{name} missing from: {message}");
    }
}

#[test]
fn the_composition_plan_does_not_see_a_matte() {
    // O1: a matte track's clips decode and sound as on any track.
    let (handle, _, front, _, _) = pair();
    let plain = handle.plan_text();
    for mode in ["alpha", "alpha_inverted", "luma", "luma_inverted"] {
        assert_eq!(set_matte(&handle, front, mode).plan_text(), plain, "{mode}");
    }
}

#[test]
fn through_nests_the_first_matte_level_wins_and_groups_list_deepest_first() {
    // Track 1: A. Track 2: C, track 3: D — nested into N, which lands on
    // track 3; the emptied track 2 is removed. Inside N, D's track is a
    // luma matte for C's; at the top, N's track is an alpha matte for A's.
    let handle = Handle::new(640, 360, 30, 1);
    let (handle, two) = add_track(handle);
    let (handle, three) = add_track(handle);
    let (handle, a) = shape(handle, 1, SEC);
    let (handle, c) = shape(handle, two, SEC);
    let (handle, d) = shape(handle, three, SEC);
    let nested = handle.apply(&json!({"op": "nest", "clips": [c, d]}));
    let nested = nested.apply(&json!({"op": "remove_empty_tracks"}));
    let value = nested.value();
    let nest = &array(&value, "/nests")[0];
    let nest_id = u32::try_from(nest["id"].as_u64().expect("a nest id")).expect("u32");
    let n = last_id(&nested, "/clips");
    assert_eq!(
        nested.value()["clips"][1]["id"],
        json!(n),
        "N is the second clip"
    );
    let inner: Vec<u32> = array(nest, "/tracks")
        .iter()
        .filter_map(|t| t["id"].as_u64().and_then(|id| u32::try_from(id).ok()))
        .collect();
    assert_eq!(inner.len(), 2);

    // Neither source track was a matte, so both nested tracks are ordinary.
    assert!(array(nest, "/tracks")
        .iter()
        .all(|t| t.get("matte").is_none()));

    // A nest clip on a matted track: every layer it draws is cut.
    let n_track = three;
    let under = nested.apply(&json!({"op": "add_track", "index": 2}));
    let top = last_id(&under, "/tracks");
    let (under, b) = shape(under, top, SEC);
    let under = set_matte(&under, top, "alpha");
    let recipe = under.recipe(SEC / 2);
    assert_eq!(layer(&recipe, a)["matte"], Value::Null);
    assert_eq!(
        layer(&recipe, c)["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(
        layer(&recipe, d)["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(layer(&recipe, b)["matte"], json!({"into": 0, "cut": []}));

    // A nest clip on a matte track holding its own matte pair.
    let inside = nested.apply(&json!({
        "op": "set_track", "track": inner[1], "matte": "luma", "scope": nest_id
    }));
    let both = set_matte(&inside, n_track, "alpha");
    let recipe = both.recipe(SEC / 2);
    // A is seen first and cut by the top-level group, 0. C is drawn into
    // group 0 (its first matte level is N's track) and cut by the inner
    // group, 1; D is drawn into 1 and nothing outside applies to it.
    assert_eq!(
        layer(&recipe, a)["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(layer(&recipe, c)["matte"], json!({"into": 0, "cut": [1]}));
    assert_eq!(layer(&recipe, d)["matte"], json!({"into": 1, "cut": []}));
    assert_eq!(
        recipe["mattes"],
        json!([{"group": 1, "mode": "luma"}, {"group": 0, "mode": "alpha"}])
    );

    // The inner pair alone, under an ordinary top-level track.
    let recipe = inside.recipe(SEC / 2);
    assert_eq!(layer(&recipe, a)["matte"], Value::Null);
    assert_eq!(
        layer(&recipe, c)["matte"],
        json!({"into": null, "cut": [0]})
    );
    assert_eq!(layer(&recipe, d)["matte"], json!({"into": 0, "cut": []}));
    assert_eq!(recipe["mattes"], json!([{"group": 0, "mode": "luma"}]));
}

#[test]
fn the_burn_in_layer_has_no_matte() {
    let (handle, _, front, _, _) = pair();
    let recipe = set_matte(&handle, front, "alpha")
        .recipe_opts(SEC / 2, &json!({"burn_in_timecode": true}).to_string());
    let layers = array(&recipe, "/layers");
    assert_eq!(layers.last().map(|l| l["matte"].clone()), Some(Value::Null));
}
