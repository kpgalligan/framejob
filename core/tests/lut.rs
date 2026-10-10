//! `.cube` LUTs as media and as looks (spec §11 GR-8), black box through the
//! C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned: a `lut` row through `add_media` and its field rule; the four
//! placing ops' answers; each look rule's sentence; a built-in kind
//! replacing a LUT; `validate` on a file; `remove_media`'s refusal and its
//! `with_clips` clear, a nest's clip included and an end left alone; `paste`
//! and `paste_attributes` into another project, the LUT's row absorbed by
//! path and the base look and an end remapped; an end LUT A → B over
//! adjacent ids switching at the end; a dangling end evaluating as no look;
//! a clip whose end names a removed LUT pasting into its own project and
//! another without aliasing; the recipe's `look`; and `ungraded` removing
//! it. What a LUT does to a pixel is `tools/proof/lut_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, Handle};

const SEC: i64 = 600_000;

fn lut_row(id: u32, path: &str) -> Value {
    json!({"id": id, "path": path, "kind": "lut"})
}

fn video_row(id: u32, path: &str) -> Value {
    json!({"id": id, "path": path, "kind": "video", "duration": 36000000, "width": 1920,
           "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false})
}

/// Media 1 (video), 2 and 3 (LUTs A and B, adjacent ids); clip 10 on track
/// 4 with no look; a nest 30 whose clip 32 has LUT A as its look, shown by
/// nest clip 11 from 6 s.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 14,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [video_row(1, "/m/talk.mov"), lut_row(2, "/l/a.cube"), lut_row(3, "/l/b.cube")],
        "tracks": [{"id": 4, "name": "Track 1"}],
        "clips": [
            {"id": 10, "track": 4, "start": 0, "duration": 6 * SEC, "speed": 1.0,
             "source": {"kind": "media", "media": 1, "in": 0},
             "enabled": {"video": true, "audio": false}, "video": {}},
            {"id": 11, "track": 4, "start": 6 * SEC, "duration": 2 * SEC, "speed": 1.0,
             "source": {"kind": "nest", "project": 30},
             "enabled": {"video": true, "audio": false}, "video": {}}
        ],
        "nests": [{"id": 30, "name": "Group", "width": 1920, "height": 1080,
                   "tracks": [{"id": 31, "name": "Track 1"}],
                   "clips": [{"id": 32, "track": 31, "start": 0, "duration": 2 * SEC,
                              "speed": 1.0, "source": {"kind": "media", "media": 1, "in": 0},
                              "enabled": {"video": true, "audio": false},
                              "video": {"look": {"kind": "lut", "media": 2}}}]}],
        "next_id": 40
    }))
}

fn set_look(clips: &[u32], look: Value) -> Value {
    json!({"op": "set_video", "clips": clips, "patch": {"look": look}})
}

fn lut(media: u32) -> Value {
    json!({"kind": "lut", "media": media})
}

/// A clip's stored look anywhere in the project (timeline or nest), or
/// `Value::Null`.
fn stored(handle: &Handle, clip: u64) -> Value {
    let value = handle.value();
    let clips = array(&value, "/clips")
        .iter()
        .chain(
            array(&value, "/nests")
                .iter()
                .flat_map(|n| array(n, "/clips").iter()),
        )
        .find(|c| c["id"].as_u64() == Some(clip))
        .cloned()
        .unwrap_or_else(|| panic!("no clip {clip}"));
    clips["video"].get("look").cloned().unwrap_or(Value::Null)
}

fn evaluated(handle: &Handle, clip: u32, t: i64) -> Value {
    handle.clip_state(clip, t).expect("the clip")["video"]
        .get("look")
        .cloned()
        .unwrap_or(Value::Null)
}

fn layer_look(handle: &Handle, t: i64, opts: Option<&str>) -> Value {
    let recipe = match opts {
        Some(opts) => handle.recipe_opts(t, opts),
        None => handle.recipe(t),
    };
    recipe["layers"]
        .as_array()
        .and_then(|layers| layers.iter().find(|l| l["clip"] == json!(10)))
        .map(|l| l["look"].clone())
        .expect("clip 10's layer")
}

fn media_ids(handle: &Handle) -> Vec<u64> {
    array(&handle.value(), "/media")
        .iter()
        .filter_map(|m| m["id"].as_u64())
        .collect()
}

fn not_placeable(media: u32) -> String {
    format!(
        "media {media} is a LUT: apply it as a look (set_video {{look: {{kind: \"lut\", \
         media: {media}}}}}), it is not placed as a clip"
    )
}

#[test]
fn add_media_takes_a_lut_row_with_no_picture_or_sound() {
    let base = Handle::new(1920, 1080, 30, 1);
    let added = base.apply(&json!({"op": "add_media",
                                   "descriptor": {"path": "/l/film.cube", "kind": "lut"}}));
    let value = added.value();
    let row = &array(&value, "/media")[0];
    assert_eq!(row["kind"], json!("lut"));
    assert_eq!(row["duration"], json!(0));
    for extra in [
        json!({"has_video": true}),
        json!({"has_audio": true}),
        json!({"has_alpha": true}),
        json!({"duration": 600000}),
    ] {
        let mut descriptor = json!({"path": "/l/other.cube", "kind": "lut"});
        for (key, value) in extra.as_object().expect("object") {
            descriptor[key] = value.clone();
        }
        assert_eq!(
            base.errors(&json!({"op": "add_media", "descriptor": descriptor})),
            "a lut media has no video, audio, alpha or duration"
        );
    }
}

#[test]
fn the_placing_ops_refuse_a_lut() {
    let base = project();
    for op in ["add_clip", "insert_clip", "overwrite_clip"] {
        assert_eq!(
            base.errors(&json!({"op": op, "track": 4, "media": 2, "at": 0})),
            not_placeable(2),
            "{op}"
        );
    }
    assert_eq!(
        base.errors(&json!({"op": "add_background", "media": 2})),
        "media 2 has no pixel size, so it cannot be a background"
    );
}

#[test]
fn each_look_rule_answers_in_its_own_sentence() {
    let base = project();
    assert_eq!(
        base.errors(&set_look(&[10], json!({"kind": "lut"}))),
        "video.look.media is required with kind lut"
    );
    assert_eq!(
        base.errors(&set_look(&[10], json!({"kind": "warm", "media": 2}))),
        "video.look.media goes with kind lut, not warm"
    );
    let warm = base.apply(&set_look(&[10], json!({"kind": "warm"})));
    assert_eq!(
        warm.errors(&set_look(&[10], json!({"media": 2}))),
        "video.look.media goes with kind lut, not warm"
    );
    assert_eq!(
        base.errors(&set_look(&[10], lut(99))),
        "video.look.media 99 is not a media of this project"
    );
    assert_eq!(
        base.errors(&set_look(&[10], lut(1))),
        "video.look.media 1 is a video media, not a lut"
    );
    let looked = base.apply(&set_look(&[10], lut(2)));
    // Stored as kind, media, amount.
    assert_eq!(
        stored(&looked, 10),
        json!({"kind": "lut", "media": 2, "amount": 1.0})
    );
    let text = looked.to_json();
    let at = text
        .find("\"kind\": \"lut\",\n")
        .expect("the look in the file");
    let rest = &text[at..];
    assert!(rest.find("\"media\": 2").expect("media") < rest.find("\"amount\"").expect("amount"));
}

#[test]
fn a_built_in_kind_replaces_the_lut_and_another_lut_switches_it() {
    let looked = project().apply(&set_look(
        &[10],
        json!({"kind": "lut", "media": 2, "amount": 0.5}),
    ));
    let warm = looked.apply(&set_look(&[10], json!({"kind": "warm"})));
    assert_eq!(stored(&warm, 10), json!({"kind": "warm", "amount": 0.5}));
    let other = looked.apply(&set_look(&[10], json!({"media": 3})));
    assert_eq!(
        stored(&other, 10),
        json!({"kind": "lut", "media": 3, "amount": 0.5})
    );
    let amount = looked.apply(&set_look(&[10], json!({"amount": 0.25})));
    assert_eq!(
        stored(&amount, 10),
        json!({"kind": "lut", "media": 2, "amount": 0.25})
    );
    let none = looked.apply(&set_look(&[10], Value::Null));
    assert_eq!(stored(&none, 10), Value::Null);
}

#[test]
fn validate_refuses_a_file_whose_look_names_no_lut() {
    let mut value = project().value();
    value["clips"][0]["video"] = json!({"look": {"kind": "lut", "media": 1}});
    assert_eq!(
        Handle::try_from_value(&value).err().as_deref(),
        Some("clip 10: video.look.media 1 is a video media, not a lut")
    );
    value["clips"][0]["video"] = json!({});
    value["nests"][0]["clips"][0]["video"] = json!({"look": {"kind": "lut", "media": 7}});
    assert_eq!(
        Handle::try_from_value(&value).err().as_deref(),
        Some("clip 32 in nest 30: video.look.media 7 is not a media of this project")
    );
    value["nests"][0]["clips"][0]["video"] = json!({"look": {"kind": "cool", "media": 2}});
    assert_eq!(
        Handle::try_from_value(&value).err().as_deref(),
        Some("clip 32 in nest 30: video.look.media goes with kind lut, not cool")
    );
}

#[test]
fn remove_media_refuses_a_used_lut_and_with_clips_clears_the_looks() {
    let looked = project()
        .apply(&set_look(&[10], lut(2)))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 40,
                        "patch": {"video": {"look": {"media": 2, "amount": 0.5}}}}));
    looked.refuses_with(
        &json!({"op": "remove_media", "media": 2}),
        "media 2 is the look of clips 10 and 32; pass with_clips: true to remove it and clear \
         their looks",
    );
    let cleared = looked.apply(&json!({"op": "remove_media", "media": 2, "with_clips": true}));
    assert_eq!(media_ids(&cleared), vec![1, 3]);
    assert_eq!(stored(&cleared, 10), Value::Null);
    assert_eq!(stored(&cleared, 32), Value::Null);
    // Both clips stay; the end is left as written, and reads as no look.
    let value = cleared.value();
    assert_eq!(array(&value, "/clips").len(), 2);
    assert_eq!(
        by_id(&value, "/clips", 10)["actions"][0]["end"]["video"]["look"],
        json!({"media": 2, "amount": 0.5})
    );
    assert_eq!(evaluated(&cleared, 10, 2 * SEC), Value::Null);
    // An unused LUT goes without the argument.
    let unused = project().apply(&json!({"op": "remove_media", "media": 3}));
    assert_eq!(media_ids(&unused), vec![1, 2]);
}

#[test]
fn an_end_lut_switches_at_the_end_and_never_interpolates_the_id() {
    let animated = project()
        .apply(&set_look(&[10], lut(2)))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 40,
                        "patch": {"video": {"look": {"media": 3, "amount": 0.5}}}}));
    for t in [SEC / 2, SEC, 3 * SEC / 2, 2 * SEC - 1] {
        assert_eq!(evaluated(&animated, 10, t)["media"], json!(2), "at {t}");
    }
    assert_eq!(
        evaluated(&animated, 10, 2 * SEC),
        json!({"kind": "lut", "media": 3,
                                                          "amount": 0.5})
    );
}

#[test]
fn a_dangling_end_evaluates_as_no_look() {
    let animated = project()
        .apply(&set_look(&[10], lut(2)))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 40,
                        "patch": {"video": {"look": {"media": 99}, "opacity": 0.5}}}));
    let state = animated.clip_state(10, 2 * SEC).expect("clip 10");
    assert_eq!(state["video"]["look"], Value::Null);
    assert_eq!(state["video"]["opacity"], json!(0.5));
    // An end naming the video media as a LUT is no look either.
    let video = project()
        .apply(&set_look(&[10], lut(2)))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 40,
                        "patch": {"video": {"look": {"media": 1}}}}));
    assert_eq!(evaluated(&video, 10, 2 * SEC), Value::Null);
}

/// A paste payload of clip 10 as the app writes it: the clip at depth 0 and
/// every media row it shows or looks through.
fn payload_of(handle: &Handle, rows: &[u64]) -> Value {
    let value = handle.value();
    let mut clip = by_id(&value, "/clips", 10).clone();
    clip["track"] = json!(0);
    let media: Vec<Value> = array(&value, "/media")
        .iter()
        .filter(|m| rows.contains(&m["id"].as_u64().unwrap_or(0)))
        .cloned()
        .collect();
    json!({"clips": [clip], "media": media})
}

/// Another project: its own video at /m/talk.mov (id 1), LUT B already in it
/// at id 2, and a different video at id 3, so a remap that kept an id would
/// name the wrong media.
fn elsewhere() -> Handle {
    Handle::from_value(&json!({
        "version": 14,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [video_row(1, "/m/talk.mov"), lut_row(2, "/l/b.cube"),
                  video_row(3, "/m/other.mov")],
        "tracks": [{"id": 4, "name": "Track 1"}],
        "clips": [],
        "next_id": 50
    }))
}

#[test]
fn paste_brings_the_lut_rows_and_remaps_the_base_and_the_end() {
    let animated = project()
        .apply(&set_look(&[10], lut(2)))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 40,
                        "patch": {"video": {"look": {"media": 3}}}}));
    let payload = payload_of(&animated, &[1, 2, 3]);
    let pasted = elsewhere().apply(&json!({"op": "paste", "at": 0, "payload": payload}));
    let value = pasted.value();
    // A (/l/a.cube) is new and appended; B is matched by path to id 2.
    let rows = array(&value, "/media");
    assert_eq!(rows.len(), 4);
    let a = rows
        .iter()
        .find(|m| m["path"] == json!("/l/a.cube"))
        .expect("A absorbed");
    assert_eq!(a["kind"], json!("lut"));
    let clip = &array(&value, "/clips")[0];
    assert_eq!(clip["source"]["media"], json!(1));
    assert_eq!(clip["video"]["look"]["media"], a["id"]);
    assert_eq!(
        clip["actions"][0]["end"]["video"]["look"]["media"],
        json!(2)
    );
}

#[test]
fn paste_attributes_brings_the_lut_row_with_the_video_group() {
    let looked = project().apply(&set_look(
        &[10],
        json!({"kind": "lut", "media": 3, "amount": 0.75}),
    ));
    let payload = payload_of(&looked, &[1, 3]);
    let target = elsewhere().apply(&json!({"op": "add_clip", "track": 4, "media": 3, "at": 0}));
    let clip = array(&target.value(), "/clips")[0]["id"]
        .as_u64()
        .expect("id") as u32;
    let pasted = target.apply(&json!({"op": "paste_attributes", "clips": [clip],
                                      "payload": payload}));
    // B is matched by path (id 2 here); nothing else is absorbed.
    assert_eq!(
        stored(&pasted, u64::from(clip)),
        json!({"kind": "lut", "media": 2,
                                                       "amount": 0.75})
    );
    assert_eq!(media_ids(&pasted), vec![1, 2, 3]);
    // Only the audio group: no LUT row comes across.
    let audio_only = project().apply(&set_look(&[10], lut(2)));
    let payload = payload_of(&audio_only, &[1, 2]);
    let answer = target.try_apply(&json!({"op": "paste_attributes", "clips": [clip],
                                          "payload": payload, "groups": ["audio"],
                                          "skip_missing": true}));
    assert!(
        !matches!(answer, Ok(common::Outcome::Applied(_))),
        "{answer:?}"
    );
}

#[test]
fn a_clip_whose_end_names_a_removed_lut_pastes_without_aliasing() {
    let animated = project()
        .apply(&set_look(&[10], lut(3)))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 40,
                        "patch": {"video": {"look": {"media": 2}}}}))
        .apply(&json!({"op": "remove_media", "media": 2, "with_clips": true}));
    // The app's payload carries only the rows that exist: 1 and 3.
    let payload = payload_of(&animated, &[1, 2, 3]);
    for into in [animated.duplicate(), elsewhere()] {
        let before = media_ids(&into);
        let pasted = into.apply(&json!({"op": "paste", "at": 20 * SEC, "payload": payload}));
        let value = pasted.value();
        let clip = array(&value, "/clips")
            .last()
            .expect("the pasted clip")
            .clone();
        assert_eq!(clip["actions"][0]["end"]["video"]["look"], Value::Null);
        let id = clip["id"].as_u64().expect("id") as u32;
        // The pasted clip starts at 20 s, and clip_state takes project time.
        let base = evaluated(&pasted, id, 20 * SEC);
        assert_eq!(base["kind"], json!("lut"));
        let row = by_id(&value, "/media", base["media"].as_u64().expect("media"));
        assert_eq!(row["path"], json!("/l/b.cube"));
        // Past the action's end the look is none, as the source's dangling
        // end is: the frames are unchanged.
        let source_end = evaluated(&animated, 10, 2 * SEC);
        assert_eq!(source_end, Value::Null);
        assert_eq!(evaluated(&pasted, id, 22 * SEC), source_end);
        assert!(media_ids(&pasted).len() <= before.len() + 1);
    }
}

#[test]
fn the_recipe_publishes_the_lut_and_ungraded_removes_it() {
    let looked = project().apply(&set_look(
        &[10],
        json!({"kind": "lut", "media": 2, "amount": 0.5}),
    ));
    let look = layer_look(&looked, SEC, None);
    assert_eq!(look, json!({"kind": "lut", "amount": 0.5, "media": 2}));
    let keys: Vec<&String> = look.as_object().expect("object").keys().collect();
    assert_eq!(keys, ["kind", "amount", "media"]);
    assert_eq!(
        layer_look(&looked, SEC, Some(r#"{"ungraded": true}"#)),
        Value::Null
    );
    let zero = looked.apply(&set_look(&[10], json!({"amount": 0})));
    assert_eq!(layer_look(&zero, SEC, None), Value::Null);
}
