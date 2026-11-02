//! Text Behind Subject in the model and the recipe (format 40, spec §11
//! CO-50, CO-51, CO-52), through the FFI.
//!
//! Pinned here against oracles written in this file: `set_video`'s and
//! `paste_attributes`' refusals on an adjustment and a nest clip; the flag
//! switching at an action's end; the subject copy's keys, its group's id
//! after the track groups and `mattes`' order; a cut-out layer in FRONT not a
//! subject; `background: keep` still a subject; a nested subject behind a
//! top-level clip and not the reverse; matte-drawn layers neither subjects
//! nor behind layers; a file's flag on an adjustment clip ignored; split,
//! move and Show Selection keeping the cut; a cut-out clip cross-dissolving
//! into an uncut one (one copy, its `transition` its original's); a routed
//! half's copy keeping its `dissolve` chain; and (b6) a frame with no behind
//! clip cut by a subject byte-identical to the flag-off frame.

mod common;

use serde_json::{json, Value};

use common::{array, int, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;

fn media(id: u32, name: &str) -> Value {
    json!({ "id": id, "path": format!("/fixtures/{name}.mov"), "kind": "video",
            "duration": 600 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true })
}

/// Clip `id` of media `media` on `track` at `start` for 4 s, `video` its
/// video group.
fn clip(id: u32, media: u32, track: u32, start: i64, video: Value) -> Value {
    json!({ "id": id, "track": track, "start": start, "duration": 4 * SEC,
            "source": { "kind": "media", "media": media, "in": 0 },
            "speed": 1.0, "video": video, "audio": {} })
}

fn cutout() -> Value {
    json!({ "cutout": {} })
}

fn behind() -> Value {
    json!({ "behind_subject": true })
}

/// Media 5 and 7, `tracks` (back to front) and `clips`.
fn project_with(tracks: Value, clips: Value) -> Value {
    json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(5, "camera"), media(7, "screen")],
        "tracks": tracks,
        "clips": clips,
        "next_id": 100
    })
}

/// Tracks 2, 3 and 4, back to front.
fn three_tracks() -> Value {
    json!([{ "id": 2, "name": "Track 1" }, { "id": 3, "name": "Track 2" },
           { "id": 4, "name": "Track 3" }])
}

/// The camera (clip 11, cut out) on track 2 and the title stand-in (clip
/// 12) on track 3, `title` its video group.
fn camera_and_title(title: Value) -> Handle {
    Handle::from_value(&project_with(
        three_tracks(),
        json!([clip(11, 5, 2, 0, cutout()), clip(12, 7, 3, 0, title)]),
    ))
}

/// The same project with every clip's `behind_subject` cleared.
fn flag_off(handle: &Handle) -> Handle {
    let mut value = handle.value();
    for clip in value["clips"].as_array_mut().expect("clips") {
        if let Some(video) = clip["video"].as_object_mut() {
            video.remove("behind_subject");
        }
    }
    if let Some(nests) = value["nests"].as_array_mut() {
        for nest in nests {
            for clip in nest["clips"].as_array_mut().expect("clips") {
                if let Some(video) = clip["video"].as_object_mut() {
                    video.remove("behind_subject");
                }
            }
        }
    }
    Handle::from_value(&value)
}

/// The layers of `clip` at `t`, in order.
fn layers_of(handle: &Handle, t: i64, clip: i64) -> Vec<Value> {
    let recipe = handle.recipe(t);
    array(&recipe, "/layers")
        .iter()
        .filter(|l| int(l, "/clip") == clip)
        .cloned()
        .collect()
}

fn copies(recipe: &Value) -> Vec<Value> {
    array(recipe, "/layers")
        .iter()
        .filter(|l| l["cutout"]["subject_copy"] == json!(true))
        .cloned()
        .collect()
}

// ---- refusals ----------------------------------------------------------------

#[test]
fn an_adjustment_and_a_nest_clip_are_refused() {
    let handle = Handle::from_value(&project_with(
        three_tracks(),
        json!([clip(11, 5, 2, 0, json!({})), clip(13, 7, 3, 0, json!({}))]),
    ))
    .apply(&json!({ "op": "add_adjustment_clip", "track": 4, "at": 0 }));
    let adjustment = int(&handle.value(), "/clips/2/id");
    let set = |id: i64| json!({ "op": "set_video", "clips": [id], "patch": behind() });
    assert_eq!(
        handle.errors(&set(adjustment)),
        format!("clip {adjustment} is an adjustment clip and cannot be put behind a subject")
    );
    let nested = handle.apply(&json!({ "op": "nest", "clips": [13] }));
    let nest = array(&nested.value(), "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| int(c, "/id"))
        .expect("a nest clip");
    assert_eq!(
        nested.errors(&set(nest)),
        format!("clip {nest} shows a nest and cannot be put behind a subject")
    );
    // A pasted video group meets the same rule through `settle_video`.
    let source = clip(40, 5, 2, 0, behind());
    let error = handle.errors(&json!({ "op": "paste_attributes", "clips": [adjustment],
        "payload": { "clips": [source], "media": [] }, "groups": ["video"] }));
    assert!(
        error.contains(&format!(
            "clip {adjustment} is an adjustment clip and cannot be put behind a subject"
        )),
        "{error}"
    );
    // Any other drawing clip takes it, and false is not written.
    let set_on = handle.apply(&set(13));
    assert_eq!(
        set_on.value()["clips"][1]["video"]["behind_subject"],
        json!(true)
    );
    let off = set_on.apply(&json!({ "op": "set_video", "clips": [13],
                                    "patch": { "behind_subject": false } }));
    assert!(!off.to_json().contains("behind_subject"));
}

// ---- the relation and the copy ---------------------------------------------

#[test]
fn the_flag_switches_at_an_actions_end() {
    let mut title = clip(12, 7, 3, 0, json!({}));
    title["actions"] = json!([{ "id": 21, "start": SEC, "duration": SEC, "curve": "linear",
                                "end": { "video": { "behind_subject": true } } }]);
    let handle = Handle::from_value(&project_with(
        three_tracks(),
        json!([clip(11, 5, 2, 0, cutout()), title]),
    ));
    for (t, cut) in [
        (SEC / 2, false),
        (3 * SEC / 2, false),
        (2 * SEC, true),
        (3 * SEC, true),
    ] {
        let recipe = handle.recipe(t);
        assert_eq!(!copies(&recipe).is_empty(), cut, "{t}: {recipe}");
    }
}

#[test]
fn the_copy_its_keys_its_id_and_the_mattes_order() {
    // Track 4 is an alpha matte over track 3 (the title), so the title is
    // already cut by track group 0; the camera's subject group is 1.
    let tracks = json!([{ "id": 2, "name": "Camera" }, { "id": 3, "name": "Title" },
                        { "id": 4, "name": "Matte", "matte": "alpha" }]);
    let handle = Handle::from_value(&project_with(
        tracks,
        json!([
            clip(11, 5, 2, 0, cutout()),
            clip(12, 7, 3, 0, behind()),
            clip(13, 7, 4, 0, json!({}))
        ]),
    ));
    let recipe = handle.recipe(SEC);
    let layers = array(&recipe, "/layers");
    let order: Vec<i64> = layers.iter().map(|l| int(l, "/clip")).collect();
    assert_eq!(order, vec![11, 11, 12, 13], "{recipe}");
    let original = &layers[0];
    let copy = &layers[1];
    // The copy is the original with exactly the keys CO-51 names changed.
    let mut expected = original.clone();
    expected["blend"] = json!("normal");
    expected["shadow"] = Value::Null;
    expected["reflection"] = Value::Null;
    expected["cutout"]["background"] = json!("remove");
    expected["cutout"]["subject_copy"] = json!(true);
    expected["matte"] = json!({ "into": 1, "cut": [] });
    assert_eq!(copy, &expected);
    assert_eq!(
        copy.as_object().map(|o| o.len()),
        original.as_object().map(|o| o.len())
    );
    // `subject_copy` is the cutout's last key.
    let keys: Vec<&String> = copy["cutout"].as_object().expect("cutout").keys().collect();
    assert_eq!(keys.last().map(|k| k.as_str()), Some("subject_copy"));
    assert_eq!(original["matte"], Value::Null);
    assert_eq!(layers[2]["matte"], json!({ "into": null, "cut": [0, 1] }));
    assert_eq!(layers[3]["matte"], json!({ "into": 0, "cut": [] }));
    assert_eq!(
        recipe["mattes"],
        json!([{ "group": 0, "mode": "alpha" }, { "group": 1, "mode": "alpha_inverted" }])
    );
}

#[test]
fn two_subjects_take_ascending_ids_in_instance_order() {
    let tracks = json!([{ "id": 2, "name": "A" }, { "id": 3, "name": "B" },
                        { "id": 4, "name": "Title" }]);
    let handle = Handle::from_value(&project_with(
        tracks,
        json!([
            clip(11, 5, 2, 0, cutout()),
            clip(12, 5, 3, 0, cutout()),
            clip(13, 7, 4, 0, behind())
        ]),
    ));
    let recipe = handle.recipe(SEC);
    let layers = array(&recipe, "/layers");
    let order: Vec<i64> = layers.iter().map(|l| int(l, "/clip")).collect();
    assert_eq!(order, vec![11, 11, 12, 12, 13]);
    assert_eq!(layers[1]["matte"]["into"], json!(0));
    assert_eq!(layers[3]["matte"]["into"], json!(1));
    assert_eq!(layers[4]["matte"], json!({ "into": null, "cut": [0, 1] }));
    assert_eq!(
        recipe["mattes"],
        json!([{ "group": 0, "mode": "alpha_inverted" },
               { "group": 1, "mode": "alpha_inverted" }])
    );
}

#[test]
fn a_cut_out_layer_in_front_is_not_a_subject() {
    // The camera on track 3 in front of the flagged clip on track 2.
    let handle = Handle::from_value(&project_with(
        three_tracks(),
        json!([clip(12, 7, 2, 0, behind()), clip(11, 5, 3, 0, cutout())]),
    ));
    assert_eq!(handle.recipe_text(SEC), flag_off(&handle).recipe_text(SEC));
}

#[test]
fn a_kept_background_is_still_a_subject() {
    let kept = Handle::from_value(&project_with(
        three_tracks(),
        json!([
            clip(11, 5, 2, 0, json!({ "cutout": { "background": "keep" } })),
            clip(12, 7, 3, 0, behind())
        ]),
    ));
    let recipe = kept.recipe(SEC);
    let layers = array(&recipe, "/layers");
    assert_eq!(layers[0]["cutout"]["background"], json!("keep"));
    assert_eq!(layers[1]["cutout"]["background"], json!("remove"));
    assert_eq!(layers[1]["cutout"]["subject_copy"], json!(true));
    assert_eq!(layers[2]["matte"]["cut"], json!([0]));
}

/// A nest clip 60 on track `nest_track` holding a cut-out camera (51), and
/// a flagged clip 12 on `title_track` at the top level; or, with
/// `title_inside`, the flagged clip inside the nest in front of the camera
/// and a top-level camera behind the nest clip.
fn nested(title_inside: bool) -> Handle {
    let mut camera = clip(51, 5, 53, 0, cutout());
    camera["start"] = json!(0);
    let (top, inner) = if title_inside {
        (
            json!([clip(11, 5, 2, 0, cutout()),
                   { "id": 60, "track": 3, "start": 0, "duration": 4 * SEC,
                     "source": { "kind": "nest", "project": 50 } }]),
            json!([clip(52, 7, 54, 0, behind())]),
        )
    } else {
        (
            json!([{ "id": 60, "track": 2, "start": 0, "duration": 4 * SEC,
                     "source": { "kind": "nest", "project": 50 } },
                   clip(12, 7, 3, 0, behind())]),
            json!([camera]),
        )
    };
    Handle::from_value(&json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(5, "camera"), media(7, "screen")],
        "tracks": three_tracks(),
        "clips": top,
        "nests": [{ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                    "tracks": [{ "id": 53, "name": "Inner" }, { "id": 54, "name": "Front" }],
                    "clips": inner }],
        "next_id": 100
    }))
}

#[test]
fn a_nested_subject_cuts_a_top_level_clip_and_not_the_reverse() {
    let outer = nested(false);
    let recipe = outer.recipe(SEC);
    let order: Vec<i64> = array(&recipe, "/layers")
        .iter()
        .map(|l| int(l, "/clip"))
        .collect();
    assert_eq!(order, vec![51, 51, 12], "{recipe}");
    assert_eq!(layers_of(&outer, SEC, 12)[0]["matte"]["cut"], json!([0]));

    // A top-level camera behind the nest clip does not cut a clip inside it.
    let inner = nested(true);
    assert_eq!(inner.recipe_text(SEC), flag_off(&inner).recipe_text(SEC));
}

#[test]
fn matte_drawn_layers_are_neither_subjects_nor_behind() {
    // The camera on a matte track (drawn into it) is no subject.
    let tracks = json!([{ "id": 2, "name": "Target" }, { "id": 3, "name": "Matte", "matte": "alpha" },
                        { "id": 4, "name": "Title" }]);
    let camera_matte = Handle::from_value(&project_with(
        tracks,
        json!([
            clip(10, 7, 2, 0, json!({})),
            clip(11, 5, 3, 0, cutout()),
            clip(12, 7, 4, 0, behind())
        ]),
    ));
    assert_eq!(
        camera_matte.recipe_text(SEC),
        flag_off(&camera_matte).recipe_text(SEC)
    );
    // A flagged clip on a matte track is no behind layer.
    let tracks = json!([{ "id": 2, "name": "Camera" }, { "id": 3, "name": "Target" },
                        { "id": 4, "name": "Matte", "matte": "alpha" }]);
    let title_matte = Handle::from_value(&project_with(
        tracks,
        json!([
            clip(11, 5, 2, 0, cutout()),
            clip(10, 7, 3, 0, json!({})),
            clip(12, 7, 4, 0, behind())
        ]),
    ));
    assert_eq!(
        title_matte.recipe_text(SEC),
        flag_off(&title_matte).recipe_text(SEC)
    );
}

#[test]
fn a_files_flag_on_an_adjustment_clip_is_ignored() {
    let added = Handle::from_value(&project_with(
        three_tracks(),
        json!([clip(11, 5, 2, 0, cutout())]),
    ))
    .apply(&json!({ "op": "add_adjustment_clip", "track": 3, "at": 0 }));
    let mut value = added.value();
    value["clips"][1]["video"]["behind_subject"] = json!(true);
    let handle = Handle::from_value(&value);
    assert_eq!(handle.recipe_text(SEC), flag_off(&handle).recipe_text(SEC));
}

#[test]
fn split_and_move_keep_the_cut() {
    let handle = camera_and_title(behind());
    let split = handle.apply(&json!({ "op": "split", "clips": [11], "at": 2 * SEC }));
    for t in [SEC, 3 * SEC] {
        let recipe = split.recipe(t);
        assert_eq!(copies(&recipe).len(), 1, "{t}: {recipe}");
        assert_eq!(layers_of(&split, t, 12)[0]["matte"]["cut"], json!([0]));
    }
    let moved = handle.apply(&json!({ "op": "move_clip", "clips": [12], "delta": SEC }));
    let recipe = moved.recipe(2 * SEC);
    assert_eq!(copies(&recipe).len(), 1, "{recipe}");
    let moved_title = moved.apply(&json!({ "op": "move_clip", "clips": [12], "delta": 0,
                                           "track": 4 }));
    assert_eq!(copies(&moved_title.recipe(SEC)).len(), 1);
}

#[test]
fn show_selection_keeps_the_copies() {
    let handle = Handle::from_value(&project_with(
        json!([{ "id": 1, "name": "Grade" }, { "id": 2, "name": "Camera" },
               { "id": 3, "name": "Title" }]),
        json!([clip(11, 5, 2, 0, cutout()), clip(12, 7, 3, 0, behind())]),
    ))
    .apply(&json!({ "op": "add_adjustment_clip", "track": 1, "at": 0 }));
    let adjustment = int(&handle.value(), "/clips/2/id");
    let selected = handle.recipe_opts(SEC, &json!({ "selection": adjustment }));
    let order: Vec<i64> = array(&selected, "/layers")
        .iter()
        .map(|l| int(l, "/clip"))
        .collect();
    assert_eq!(order, vec![adjustment, 11], "{selected}");
    assert_eq!(copies(&selected).len(), 1);
}

#[test]
fn a_dissolve_into_an_uncut_clip_copies_one_half() {
    let mut incoming = clip(13, 7, 2, 3 * SEC, json!({}));
    incoming["transition_in"] =
        json!({ "kind": "cross_dissolve", "curve": "linear", "audio": true });
    let mut title = clip(12, 7, 3, 0, behind());
    title["duration"] = json!(8 * SEC);
    let handle = Handle::from_value(&project_with(
        three_tracks(),
        json!([clip(11, 5, 2, 0, cutout()), incoming, title]),
    ));
    let t = 3 * SEC + SEC / 2;
    let recipe = handle.recipe(t);
    let layers = array(&recipe, "/layers");
    let order: Vec<i64> = layers.iter().map(|l| int(l, "/clip")).collect();
    assert_eq!(order, vec![11, 11, 13, 12], "{recipe}");
    assert_eq!(copies(&recipe).len(), 1);
    assert!(!layers[0]["transition"].is_null(), "{recipe}");
    assert_eq!(layers[1]["transition"], layers[0]["transition"]);
    assert_eq!(layers[1]["transition"]["partner"], json!(13), "{recipe}");
    assert_eq!(layers[3]["matte"]["cut"], json!([0]));
}

#[test]
fn a_routed_halfs_copy_keeps_its_dissolve_chain() {
    // The cut-out camera (11) dissolves into a nest clip (60): a routed pair
    // (MT-8), so the camera's layer carries a `dissolve` chain.
    let mut incoming = json!({ "id": 60, "track": 2, "start": 3 * SEC, "duration": 4 * SEC,
                               "source": { "kind": "nest", "project": 50 },
                               "transition_in": { "kind": "cross_dissolve",
                                                  "curve": "linear", "audio": true } });
    incoming["video"] = json!({});
    let mut title = clip(12, 7, 3, 0, behind());
    title["duration"] = json!(8 * SEC);
    let handle = Handle::from_value(&json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(5, "camera"), media(7, "screen")],
        "tracks": three_tracks(),
        "clips": [clip(11, 5, 2, 0, cutout()), incoming, title],
        "nests": [{ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                    "tracks": [{ "id": 53, "name": "Inner" }],
                    "clips": [clip(51, 7, 53, 0, json!({}))] }],
        "next_id": 100
    }));
    let recipe = handle.recipe(3 * SEC + SEC / 2);
    let camera = layers_of(&handle, 3 * SEC + SEC / 2, 11);
    assert_eq!(camera.len(), 2, "{recipe}");
    assert!(!camera[0]["dissolve"].is_null(), "{recipe}");
    assert_eq!(camera[1]["dissolve"], camera[0]["dissolve"]);
    assert_eq!(camera[1]["transition"], camera[0]["transition"]);
}

// ---- b6: byte identity ----------------------------------------------------------

#[test]
fn b6_no_behind_clip_cut_by_a_subject_leaves_the_recipe_as_it_was() {
    // No flag anywhere.
    let plain = camera_and_title(json!({}));
    assert_eq!(plain.recipe_text(SEC), flag_off(&plain).recipe_text(SEC));
    // A flag with no cutout on the frame.
    let uncut = Handle::from_value(&project_with(
        three_tracks(),
        json!([clip(11, 5, 2, 0, json!({})), clip(12, 7, 3, 0, behind())]),
    ));
    assert_eq!(uncut.recipe_text(SEC), flag_off(&uncut).recipe_text(SEC));
    // A flag and a cutout, but the cut-out clip in front.
    let front = Handle::from_value(&project_with(
        three_tracks(),
        json!([
            clip(12, 7, 2, 0, behind()),
            clip(11, 5, 3, 0, cutout()),
            clip(13, 5, 4, 0, cutout())
        ]),
    ));
    let text = front.recipe_text(SEC);
    assert_eq!(text, flag_off(&front).recipe_text(SEC));
    assert!(!text.contains("alpha_inverted"), "{text}");
    // And with a subject, the frame past the title's end is the flag-off one.
    let mut short = camera_and_title(behind()).value();
    short["clips"][0]["duration"] = json!(8 * SEC);
    let short = Handle::from_value(&short);
    assert_eq!(
        short.recipe_text(5 * SEC),
        flag_off(&short).recipe_text(5 * SEC)
    );
    // The plan is the flag-off plan.
    assert_eq!(short.plan_text(), flag_off(&short).plan_text());
}
