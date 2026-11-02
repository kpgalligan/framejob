//! A picture's cutout in the model and the recipe (format 41, spec §11
//! CO-100, CO-101), through the FFI.
//!
//! Pinned here against oracles written in this file: an image clip's
//! `set_video {cutout}` storing the person defaults, merging a `foreground`
//! subject and removing; `foreground` refused on a media clip and on a
//! freeze frame's still, each in its own sentence, with `person` still taken
//! on both, and the same refusal through `paste_attributes`; `subject` in an
//! action's end refused on an image clip in CO-20's sentence; the recipe's
//! image arm `{kind: "image", media, subject, quality}` at two times beside
//! a media clip's arm with no `subject`; `add_blurred_background`'s copy of
//! a cut image without the cutout; and a text clip's key `null`.

mod common;

use serde_json::{json, Value};

use common::{array, at, int, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;

/// Media 5 (a video) and 9 (an image), tracks 2 and 3, and `clips`.
fn project(clips: Value) -> Value {
    json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{ "id": 5, "path": "/fixtures/camera.mov", "kind": "video",
                    "duration": 600 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
                    "has_video": true, "has_audio": true },
                  { "id": 9, "path": "/fixtures/a.png", "kind": "image",
                    "width": 640, "height": 480 }],
        "tracks": [{ "id": 2, "name": "Track 1" }, { "id": 3, "name": "Track 2" }],
        "clips": clips,
        "next_id": 100
    })
}

/// Media clip 11 on track 2 for 4 s, with `video`.
fn media_clip(video: Value) -> Value {
    json!({ "id": 11, "track": 2, "start": 0, "duration": 4 * SEC,
            "source": { "kind": "media", "media": 5, "in": 0 },
            "speed": 1.0, "video": video, "audio": {} })
}

/// Image clip 13 of media 9 on track 3 for 4 s, with `video` and `actions`.
fn image_clip(video: Value, actions: Value) -> Value {
    json!({ "id": 13, "track": 3, "start": 0, "duration": 4 * SEC,
            "source": { "kind": "image", "media": 9 }, "video": video,
            "actions": actions })
}

/// The stored cutout: the defaults with `extra` laid over them.
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

fn set(clip: u64, cutout: Value) -> Value {
    json!({ "op": "set_video", "clips": [clip], "patch": { "cutout": cutout } })
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

/// The clip with `id` in `value`'s top-level clips.
fn clip_of(value: &Value, id: u64) -> Value {
    array(value, "/clips")
        .iter()
        .find(|c| int(c, "/id") == id as i64)
        .unwrap_or_else(|| panic!("no clip {id}: {value}"))
        .clone()
}

fn foreground_sentence(id: u64, what: &str) -> String {
    format!("clip {id} is {what} and cannot take a foreground cutout: only an image clip can")
}

// ---- set_video on an image clip ----------------------------------------------

#[test]
fn an_image_clip_stores_merges_and_removes() {
    let handle = Handle::from_value(&project(json!([image_clip(json!({}), json!([]))])));
    let stored = handle.apply(&set(13, json!({})));
    assert_eq!(
        at(&stored.value(), "/clips/0/video/cutout"),
        &cut(json!({})),
        "{{}} reads as the person defaults"
    );
    let merged = stored.apply(&set(13, json!({ "subject": "foreground" })));
    assert_eq!(
        at(&merged.value(), "/clips/0/video/cutout"),
        &cut(json!({ "subject": "foreground" }))
    );
    let removed = merged.apply(&set(13, Value::Null)).value();
    assert!(
        removed["clips"][0]["video"].get("cutout").is_none(),
        "{removed}"
    );
}

// ---- foreground on a media or still clip ---------------------------------------

#[test]
fn foreground_is_refused_on_a_media_clip_and_a_still_in_its_own_sentence() {
    let handle = Handle::from_value(&project(json!([media_clip(json!({}))])));
    assert_eq!(
        handle.errors(&set(11, json!({ "subject": "foreground" }))),
        foreground_sentence(11, "a media clip")
    );
    let person = handle.apply(&set(11, json!({ "subject": "person" })));
    assert_eq!(
        at(&person.value(), "/clips/0/video/cutout"),
        &cut(json!({}))
    );

    let frozen = handle.apply(&json!({ "op": "freeze_frame", "clip": 11, "at": 2 * SEC,
                                       "duration": SEC }));
    let value = frozen.value();
    let still = array(&value, "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("still"))
        .map(|c| int(c, "/id") as u64)
        .expect("a still");
    assert_eq!(
        frozen.errors(&set(still, json!({ "subject": "foreground" }))),
        foreground_sentence(still, "a still clip")
    );
    let person = frozen
        .apply(&set(still, json!({ "subject": "person" })))
        .value();
    assert_eq!(clip_of(&person, still)["video"]["cutout"], cut(json!({})));
}

#[test]
fn a_pasted_foreground_group_is_refused_on_a_media_clip() {
    let handle = Handle::from_value(&project(json!([media_clip(json!({}))])));
    let mut source = image_clip(
        json!({ "cutout": cut(json!({ "subject": "foreground" })) }),
        json!([]),
    );
    source["id"] = json!(40);
    let error = handle.errors(&json!({ "op": "paste_attributes", "clips": [11],
        "payload": { "clips": [source], "media": [] }, "groups": ["video"] }));
    assert!(
        error.contains(&foreground_sentence(11, "a media clip")),
        "{error}"
    );
}

#[test]
fn an_end_naming_subject_is_refused_on_an_image_clip() {
    let handle = Handle::from_value(&project(json!([image_clip(
        json!({ "cutout": cut(json!({ "subject": "foreground" })) }),
        json!([{ "id": 21, "start": SEC, "duration": SEC, "curve": "linear", "end": {} }])
    )])));
    for subject in ["person", "foreground"] {
        let op = json!({ "op": "set_action_end", "clip": 13, "action": 21,
                         "patch": { "video": { "cutout": { "subject": subject } } } });
        assert_eq!(
            handle.errors(&op),
            "video.cutout.subject is not an animation target",
            "{subject}"
        );
    }
}

// ---- the recipe ------------------------------------------------------------------

#[test]
fn the_image_arm_names_the_subject_and_the_media_arm_does_not() {
    let base = cut(json!({ "subject": "foreground", "background": "keep",
                           "edge": -0.5, "feather": 0.25 }));
    let handle = Handle::from_value(&project(json!([
        media_clip(json!({ "cutout": cut(json!({})) })),
        image_clip(
            json!({ "cutout": base }),
            json!([{ "id": 21, "start": SEC, "duration": 2 * SEC, "curve": "linear",
                     "end": { "video": { "cutout": {
                         "edge": 0.5, "feather": 0.75, "background": "remove" } } } }])
        )
    ])));
    let mask = json!({ "kind": "image", "media": 9, "subject": "foreground",
                       "quality": "standard" });
    assert_eq!(
        key(&handle, SEC / 2, 13),
        json!({ "mask": mask, "background": "keep", "edge": -0.5, "feather": 0.25 })
    );
    // Halfway through the action: edge and feather lerped, background held
    // until the end.
    assert_eq!(
        key(&handle, 2 * SEC, 13),
        json!({ "mask": mask, "background": "keep", "edge": 0.0, "feather": 0.5 })
    );
    for t in [SEC / 2, 2 * SEC] {
        let media = key(&handle, t, 11);
        assert_eq!(
            media["mask"],
            json!({ "kind": "media", "media": 5, "quality": "standard" }),
            "{t}"
        );
    }
}

#[test]
fn a_blurred_copy_of_a_cut_image_drops_the_cutout() {
    let base = cut(json!({ "subject": "foreground" }));
    let handle = Handle::from_value(&project(json!([image_clip(
        json!({ "cutout": base.clone() }),
        json!([])
    )])));
    let blurred = handle.apply(&json!({ "op": "add_blurred_background", "clip": 13 }));
    let value = blurred.value();
    let copy = array(&value, "/clips")
        .iter()
        .find(|c| int(c, "/id") != 13)
        .expect("the copy")
        .clone();
    assert!(copy["video"].get("cutout").is_none(), "{copy}");
    let copy_id = int(&copy, "/id") as u64;
    assert_eq!(key(&blurred, SEC, copy_id), Value::Null);
    assert_eq!(clip_of(&value, 13)["video"]["cutout"], base);
}

#[test]
fn a_text_clip_publishes_null() {
    let added = Handle::from_value(&project(json!([])))
        .apply(&json!({ "op": "add_text_clip", "track": 2, "at": 0 }));
    let mut value = added.value();
    value["clips"][0]["video"]["cutout"] = cut(json!({ "subject": "foreground" }));
    let id = int(&value, "/clips/0/id") as u64;
    let text = Handle::from_value(&value);
    assert_eq!(key(&text, SEC / 2, id), Value::Null);
}
