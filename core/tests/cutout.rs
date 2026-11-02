//! Remove Background in the model and the recipe (format 39, spec §11 CO-20,
//! CO-21, CO-23), through the FFI.
//!
//! Pinned here against oracles written in this file: `set_video`'s `cutout`
//! storing, merging and removing; every refusal's sentence, through
//! `set_video`, `paste_attributes` and `set_action_end` (its `patch` and its
//! `off`); hand-written ends — the presence and `quality` restored to the
//! base, `edge` and `feather` lerped and clamped, `background` switched at
//! the end; the recipe's `cutout` key naming each clip's OWN media through a
//! trim, ×0.5, ×2, ×1.37, a ramp, a freeze, a reverse, a split, a nest and a
//! cross-dissolve in a two-media project whose media ids are not its clip
//! ids; `null` on a text clip and the burn-in; `add_blurred_background`'s
//! copy without the cutout; and a cutout-less project's plan, recipe and
//! saved text unchanged by a cutout elsewhere.

mod common;

use serde_json::{json, Value};

use common::{array, at, by_id, int, Handle, Outcome};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
const IN: i64 = SEC / 2;

fn media(id: u32, name: &str) -> Value {
    json!({ "id": id, "path": format!("/fixtures/{name}.mov"), "kind": "video",
            "duration": 600 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true })
}

/// Media 5 and 7, tracks 2 and 3, and `clips`.
fn project(clips: Value) -> Value {
    json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(5, "camera"), media(7, "screen"), {
            "id": 9, "path": "/fixtures/a.png", "kind": "image", "width": 10, "height": 10 }],
        "tracks": [{ "id": 2, "name": "Track 1" }, { "id": 3, "name": "Track 2" }],
        "clips": clips,
        "next_id": 100
    })
}

/// Clip `id` on track 2 at `start` for 4 s of media `media` from `IN`, with
/// `extra` laid over it.
fn clip(id: u32, media: u32, start: i64, extra: Value) -> Value {
    let mut clip = json!({
        "id": id, "track": 2, "start": start, "duration": 4 * SEC,
        "source": { "kind": "media", "media": media, "in": IN },
        "speed": 1.0, "video": {}, "audio": {}
    });
    if let (Some(base), Value::Object(more)) = (clip.as_object_mut(), extra) {
        for (key, value) in more {
            base.insert(key, value);
        }
    }
    clip
}

fn cut(extra: Value) -> Value {
    let mut cut = json!({ "subject": "person", "quality": "standard", "background": "remove",
                          "edge": 0.0, "feather": 0.0 });
    if let (Some(base), Value::Object(more)) = (cut.as_object_mut(), extra) {
        for (key, value) in more {
            base.insert(key, value);
        }
    }
    cut
}

/// The recipe key the core publishes for a clip of `media` with `cut`.
fn expected(media: u32, cut: &Value) -> Value {
    json!({ "mask": { "kind": "media", "media": media, "quality": cut["quality"] },
            "background": cut["background"], "edge": cut["edge"], "feather": cut["feather"] })
}

/// The `cutout` key of clip `id`'s layer at timeline `t`.
fn key(handle: &Handle, t: i64, id: u64) -> Value {
    let recipe = handle.recipe(t);
    array(&recipe, "/layers")
        .iter()
        .find(|layer| int(layer, "/clip") == id as i64)
        .unwrap_or_else(|| panic!("no layer of clip {id} at {t}: {recipe}"))["cutout"]
        .clone()
}

fn set(clip: u64, cutout: Value) -> Value {
    json!({ "op": "set_video", "clips": [clip], "patch": { "cutout": cutout } })
}

// ---- set_video ------------------------------------------------------------

#[test]
fn set_video_stores_merges_and_removes() {
    let handle = Handle::from_value(&project(json!([clip(11, 5, 0, json!({}))])));
    let stored = handle.apply(&set(11, json!({})));
    assert_eq!(
        at(&stored.value(), "/clips/0/video/cutout"),
        &cut(json!({}))
    );
    assert!(matches!(
        stored.try_apply(&set(11, json!({}))),
        Ok(Outcome::Identity)
    ));
    let merged = stored.apply(&set(11, json!({ "background": "keep", "edge": 0.25 })));
    let want = cut(json!({ "background": "keep", "edge": 0.25 }));
    assert_eq!(at(&merged.value(), "/clips/0/video/cutout"), &want);
    assert_eq!(key(&merged, SEC, 11), expected(5, &want));
    let removed = merged.apply(&set(11, Value::Null)).value();
    assert!(
        removed["clips"][0]["video"].get("cutout").is_none(),
        "{removed}"
    );
}

// ---- refusals ---------------------------------------------------------------

#[test]
fn every_value_and_clip_refusal_is_its_own_sentence() {
    let handle = Handle::from_value(&project(json!([
        clip(11, 5, 0, json!({})),
        { "id": 12, "track": 3, "start": 0, "duration": SEC,
          "source": { "kind": "graphic" }, "video": {},
          "graphic": { "name": "lower-third", "width": 1920, "height": 1080 } },
        { "id": 13, "track": 3, "start": SEC, "duration": SEC,
          "source": { "kind": "image", "media": 9 }, "video": {} }
    ])));
    for (cutout, sentence) in [
        (
            json!({ "edge": 2 }),
            "video.cutout.edge must be between -1 and 1, not 2",
        ),
        (
            json!({ "feather": 1.5 }),
            "video.cutout.feather must be between 0 and 1, not 1.5",
        ),
        (
            json!({ "quality": "best" }),
            "video.cutout.quality must be standard: Best masks are not made yet",
        ),
    ] {
        assert_eq!(
            handle.errors(&set(11, cutout.clone())),
            sentence,
            "{cutout}"
        );
    }

    let at_free = |op: &str, at: i64| json!({ "op": op, "track": 3, "at": at, "duration": SEC });
    let mut kinds = handle.duplicate();
    let mut ids = Vec::new();
    for (index, op) in ["add_text_clip", "add_shape_clip", "add_adjustment_clip"]
        .into_iter()
        .enumerate()
    {
        kinds = kinds.apply(&at_free(op, (3 + 2 * index as i64) * SEC));
        let value = kinds.value();
        let newest = array(&value, "/clips")
            .iter()
            .map(|c| int(c, "/id"))
            .max()
            .expect("a clip");
        ids.push(newest as u64);
    }
    let nested = kinds.apply(&json!({ "op": "nest", "clips": [11] }));
    let nest_id = array(&nested.value(), "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| int(c, "/id") as u64)
        .expect("a nest clip");
    for (id, what) in [
        (ids[0], "a text clip"),
        (ids[1], "a shape clip"),
        (ids[2], "an adjustment clip"),
        (12, "a graphic clip"),
        (13, "an image clip"),
    ] {
        assert_eq!(
            nested.errors(&set(id, json!({}))),
            format!("clip {id} is {what} and cannot take a cutout")
        );
    }
    assert_eq!(
        nested.errors(&set(nest_id, json!({}))),
        format!("clip {nest_id} shows a nest and cannot take a cutout")
    );

    // A pasted video group meets the same rule through `settle_video`.
    let source = clip(40, 5, 0, json!({ "video": { "cutout": cut(json!({})) } }));
    let error = nested.errors(&json!({ "op": "paste_attributes", "clips": [ids[0]],
        "payload": { "clips": [source], "media": [] }, "groups": ["video"] }));
    assert!(
        error.contains(&format!(
            "clip {} is a text clip and cannot take a cutout",
            ids[0]
        )),
        "{error}"
    );
}

#[test]
fn an_end_refuses_subject_quality_and_off_and_takes_the_rest() {
    let handle = Handle::from_value(&project(json!([clip(
        11,
        5,
        0,
        json!({ "video": { "cutout": cut(json!({})) },
                "actions": [{ "id": 21, "start": SEC, "duration": SEC, "curve": "linear",
                              "end": {} }] })
    )])));
    let end = |patch: Value, off: Value| {
        json!({ "op": "set_action_end", "clip": 11, "action": 21,
                "patch": { "video": { "cutout": patch } }, "off": off })
    };
    for (patch, sentence) in [
        (
            json!({ "subject": "person" }),
            "video.cutout.subject is not an animation target",
        ),
        (
            json!({ "quality": "standard" }),
            "video.cutout.quality is not an animation target",
        ),
        (
            json!({ "subject": null }),
            "video.cutout.subject is not an animation target",
        ),
        (
            json!({ "quality": null, "subject": null }),
            "video.cutout.subject is not an animation target",
        ),
    ] {
        assert_eq!(
            handle.errors(&end(patch.clone(), json!([]))),
            sentence,
            "{patch}"
        );
    }
    let off = json!({ "op": "set_action_end", "clip": 11, "action": 21, "patch": {},
                      "off": ["video.cutout"] });
    assert_eq!(
        handle.errors(&off),
        "video.cutout cannot be keyed off at an action's end; set_video {cutout: null} removes it"
    );
    let taken = handle
        .apply(&end(
            json!({ "edge": 0.5, "feather": 0.2, "background": "keep" }),
            json!([]),
        ))
        .value();
    assert_eq!(
        at(&taken, "/clips/0/actions/0/end/video/cutout"),
        &json!({ "edge": 0.5, "feather": 0.2, "background": "keep" })
    );
}

// ---- hand-written ends ------------------------------------------------------

/// Clip 11 with `base` as its cutout (when not null) and an action over
/// [1 s, 3 s) of clip time ending `end`.
fn ended(base: Value, end: Value) -> Handle {
    let mut video = json!({});
    if !base.is_null() {
        video["cutout"] = base;
    }
    Handle::from_value(&project(json!([clip(
        11,
        5,
        0,
        json!({ "video": video,
                "actions": [{ "id": 21, "start": SEC, "duration": 2 * SEC, "curve": "linear",
                              "end": { "video": end } }] })
    )])))
}

#[test]
fn the_presence_and_quality_are_the_base_at_every_time() {
    let base = cut(json!({ "quality": "best" }));
    let quality = ended(base.clone(), json!({ "cutout": { "quality": "standard" } }));
    let removed = ended(base.clone(), json!({ "cutout": null }));
    let added = ended(Value::Null, json!({ "cutout": { "edge": 1.0 } }));
    for clip_t in [SEC / 2, 2 * SEC, 7 * SEC / 2] {
        assert_eq!(key(&quality, clip_t, 11), expected(5, &base), "{clip_t}");
        assert_eq!(key(&removed, clip_t, 11), expected(5, &base), "{clip_t}");
        assert_eq!(key(&added, clip_t, 11), Value::Null, "{clip_t}");
    }
}

#[test]
fn edge_lerps_and_clamps_and_background_switches_at_the_end() {
    let lerped = ended(
        cut(json!({})),
        json!({ "cutout": { "edge": 1.0, "feather": 0.5, "background": "keep" } }),
    );
    let middle = key(&lerped, 2 * SEC, 11);
    assert_eq!(middle["edge"], json!(0.5), "{middle}");
    assert_eq!(middle["feather"], json!(0.25), "{middle}");
    assert_eq!(middle["background"], json!("remove"), "{middle}");
    let after = key(&lerped, 7 * SEC / 2, 11);
    assert_eq!(after["background"], json!("keep"), "{after}");
    assert_eq!(after["edge"], json!(1.0), "{after}");

    let clamped = ended(
        cut(json!({})),
        json!({ "cutout": { "edge": 5.0, "feather": -3.0 } }),
    );
    let after = key(&clamped, 7 * SEC / 2, 11);
    assert_eq!(after["edge"], json!(1.0), "{after}");
    assert_eq!(after["feather"], json!(0.0), "{after}");
}

// ---- the key's media through every edit --------------------------------------

#[test]
fn the_key_names_each_clips_own_media_through_every_edit() {
    let base = cut(json!({ "edge": -0.5, "background": "keep" }));
    let video = json!({ "cutout": base.clone() });
    // Clip 11 on media 5 (track 2) and clip 12 on media 7 (track 3), each
    // with `extra` laid over it, reversed when asked.
    let one = |extra: Value, reversed: bool| {
        let mut extra = extra;
        extra["video"] = video.clone();
        let mut eleven = clip(11, 5, 0, extra.clone());
        let mut twelve = clip(12, 7, 0, extra);
        twelve["track"] = json!(3);
        eleven["source"]["reversed"] = json!(reversed);
        twelve["source"]["reversed"] = json!(reversed);
        Handle::from_value(&project(json!([eleven, twelve])))
    };
    for (what, extra, reversed) in [
        ("trimmed", json!({ "duration": SEC }), false),
        ("×0.5", json!({ "speed": 0.5 }), false),
        ("×2", json!({ "speed": 2.0 }), false),
        ("×1.37", json!({ "speed": 1.37 }), false),
        ("reversed", json!({}), true),
    ] {
        let handle = one(extra, reversed);
        assert_eq!(key(&handle, SEC / 2, 11), expected(5, &base), "{what}");
        assert_eq!(key(&handle, SEC / 2, 12), expected(7, &base), "{what}");
    }

    let plain = one(json!({}), false);
    let ramped = plain.apply(&json!({ "op": "add_speed_ramp", "clip": 11,
                                      "shape": "ramp_up", "rate": 2.0 }));
    for clip_t in [SEC / 2, 2 * SEC, 3 * SEC] {
        assert_eq!(
            key(&ramped, clip_t, 11),
            expected(5, &base),
            "ramp {clip_t}"
        );
    }

    let frozen = plain.apply(&json!({ "op": "freeze_frame", "clip": 12, "at": 2 * SEC,
                                      "duration": SEC }));
    let value = frozen.value();
    let still = array(&value, "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("still"))
        .expect("a still");
    assert_eq!(still["source"]["media"], json!(7));
    let still_id = int(still, "/id") as u64;
    assert_eq!(
        key(&frozen, 2 * SEC + SEC / 2, still_id),
        expected(7, &base)
    );

    let split = plain.apply(&json!({ "op": "split", "clips": [11], "at": 2 * SEC }));
    let value = split.value();
    let halves: Vec<u64> = array(&value, "/clips")
        .iter()
        .filter(|c| c["source"]["media"] == json!(5))
        .map(|c| int(c, "/id") as u64)
        .collect();
    assert_eq!(halves.len(), 2, "{value}");
    assert_eq!(key(&split, SEC, halves[0]), expected(5, &base));
    assert_eq!(key(&split, 3 * SEC, halves[1]), expected(5, &base));
    for id in &halves {
        assert_eq!(by_id(&value, "/clips", *id)["video"]["cutout"], base);
    }
}

#[test]
fn a_nested_and_a_dissolved_clip_name_their_own_media() {
    let base = cut(json!({ "feather": 0.75 }));
    let video = json!({ "cutout": base.clone() });
    let mut inner = clip(51, 7, 0, json!({ "video": video.clone() }));
    inner["track"] = json!(53);
    let nested = Handle::from_value(&json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(5, "camera"), media(7, "screen")],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{ "id": 60, "track": 2, "start": SEC, "duration": 4 * SEC,
                    "source": { "kind": "nest", "project": 50 } }],
        "nests": [{ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                    "tracks": [{ "id": 53, "name": "Inner" }], "clips": [inner] }],
        "next_id": 100
    }));
    assert_eq!(key(&nested, 2 * SEC, 51), expected(7, &base));

    let mut incoming = clip(12, 7, 3 * SEC, json!({ "video": video.clone() }));
    incoming["transition_in"] =
        json!({ "kind": "cross_dissolve", "curve": "ease_in_out", "audio": true });
    let dissolved = Handle::from_value(&project(json!([
        clip(11, 5, 0, json!({ "video": video })),
        incoming
    ])));
    for t in [3 * SEC + SEC / 4, 3 * SEC + 3 * SEC / 4] {
        assert_eq!(key(&dissolved, t, 11), expected(5, &base), "{t}");
        assert_eq!(key(&dissolved, t, 12), expected(7, &base), "{t}");
    }
}

// ---- null --------------------------------------------------------------------

#[test]
fn a_text_clip_and_the_burn_in_publish_null() {
    let added = Handle::from_value(&project(json!([])))
        .apply(&json!({ "op": "add_text_clip", "track": 2, "at": 0 }));
    let mut value = added.value();
    value["clips"][0]["video"]["cutout"] = cut(json!({}));
    let id = int(&value, "/clips/0/id") as u64;
    let text = Handle::from_value(&value);
    assert_eq!(key(&text, SEC / 2, id), Value::Null);

    let burned = text.recipe_opts(SEC / 2, &json!({ "burn_in_timecode": true }));
    let layers = array(&burned, "/layers");
    let last = layers.last().expect("the burn-in");
    assert_ne!(int(last, "/clip"), id as i64, "{burned}");
    assert_eq!(last["cutout"], Value::Null, "{burned}");
}

// ---- add_blurred_background ----------------------------------------------------

#[test]
fn a_blurred_copy_drops_the_cutout() {
    let base = cut(json!({ "edge": 0.25 }));
    let handle = Handle::from_value(&project(json!([clip(
        11,
        5,
        0,
        json!({ "video": { "cutout": base.clone() } })
    )])));
    let blurred = handle.apply(&json!({ "op": "add_blurred_background", "clip": 11 }));
    let value = blurred.value();
    let copy = array(&value, "/clips")
        .iter()
        .find(|c| int(c, "/id") != 11)
        .expect("the copy");
    assert!(copy["video"].get("cutout").is_none(), "{copy}");
    let copy_id = int(copy, "/id") as u64;
    assert_eq!(key(&blurred, SEC, copy_id), Value::Null);
    assert_eq!(key(&blurred, SEC, 11), expected(5, &base));
    assert_eq!(by_id(&value, "/clips", 11)["video"]["cutout"], base);
}

// ---- a project without a cutout ------------------------------------------------

/// `value` with every layer's `cutout` key taken out.
fn without_cutouts(mut value: Value) -> Value {
    if let Some(layers) = value.get_mut("layers").and_then(Value::as_array_mut) {
        for layer in layers {
            if let Some(layer) = layer.as_object_mut() {
                layer.shift_remove("cutout");
            }
        }
    }
    value
}

#[test]
fn a_cutout_changes_no_plan_and_no_other_recipe_key() {
    let clips = |video: Value| {
        json!([
            clip(11, 5, 0, json!({ "video": video, "speed": 1.37 })),
            clip(
                12,
                7,
                3 * SEC,
                json!({ "transition_in":
                { "kind": "cross_dissolve", "curve": "ease_in_out", "audio": true } })
            )
        ])
    };
    let plain = Handle::from_value(&project(clips(json!({}))));
    let cut_out = Handle::from_value(&project(clips(json!({ "cutout": cut(json!({})) }))));
    assert_eq!(plain.plan_text(), cut_out.plan_text());
    for t in [0, SEC, 3 * SEC + SEC / 2, 5 * SEC] {
        assert_eq!(
            without_cutouts(plain.recipe(t)),
            without_cutouts(cut_out.recipe(t)),
            "{t}"
        );
        for layer in array(&plain.recipe(t), "/layers") {
            assert_eq!(layer["cutout"], Value::Null, "{t}");
        }
    }
    assert!(!plain.to_json().contains("\"cutout\""));
}
