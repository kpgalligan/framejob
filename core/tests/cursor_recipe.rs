//! The cursor in the model and the recipe (format 38, spec §11 CU-30, CU-32,
//! CU-35, CU-39), through the FFI.
//!
//! Pinned here against oracles written in this file: the recipe's `cursor`
//! key's `at` at ×2, through a linear ramp's S(t) = t + t²/D, for a still, a
//! reversed clip and a nested clip's own clip time; `smoothing` and
//! `hide_idle` from the BASE before, inside and after an action naming them,
//! and kept by a split's second half and a freeze's still; when the key is
//! `null`; every refusal's sentence; the evaluator's clamps through an end;
//! a relink's probe replacing, clearing or (with none) keeping the cursor;
//! an end's cursor switching at the end on a clip with none; and
//! `set_video {cursor: {}}` storing the eight defaults.

mod common;

use serde_json::{json, Value};

use common::{array, at, by_id, int, num, text, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
const START: i64 = SEC;
const IN: i64 = SEC / 2;
const CURSOR_FILE: &str = "/fixtures/screen.fjcursor";

fn media(cursor: Value) -> Value {
    let mut media = json!({
        "id": 1, "path": "/fixtures/screen.mov", "kind": "video", "duration": 600 * SEC,
        "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true
    });
    if !cursor.is_null() {
        media["cursor"] = cursor;
    }
    media
}

fn file_cursor() -> Value {
    json!({ "path": CURSOR_FILE, "in_picture": false })
}

/// One project at the current version, its media 1 carrying `cursor`, its
/// clips on track 2.
fn project(cursor: Value, clips: Value) -> Handle {
    Handle::from_value(&json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(cursor)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "next_id": 100
    }))
}

/// Clip 11 at `START` for 4 s from `in` `IN`, with `extra` laid over it.
fn clip(extra: Value) -> Value {
    let mut clip = json!({
        "id": 11, "track": 2, "start": START, "duration": 4 * SEC,
        "source": { "kind": "media", "media": 1, "in": IN },
        "speed": 1.0, "video": {}, "audio": {}
    });
    if let (Some(base), Value::Object(more)) = (clip.as_object_mut(), extra) {
        for (key, value) in more {
            base.insert(key, value);
        }
    }
    clip
}

/// The `cursor` key of clip `id`'s layer at timeline `t`.
fn key(handle: &Handle, t: i64, id: u64) -> Value {
    let recipe = handle.recipe(t);
    array(&recipe, "/layers")
        .iter()
        .find(|layer| int(layer, "/clip") == id as i64)
        .unwrap_or_else(|| panic!("no layer of clip {id} at {t}: {recipe}"))["cursor"]
        .clone()
}

fn defaults() -> Value {
    json!({ "show": true, "scale": 1.0, "style": "recorded", "smoothing": 0.0,
            "hide_idle": null, "clicks": "none", "click_color": "#ffffffcc",
            "click_size": 1.0 })
}

// ---- at ------------------------------------------------------------------

#[test]
fn at_double_speed_is_in_plus_twice_the_clip_time() {
    let handle = project(
        file_cursor(),
        json!([clip(json!({ "speed": 2.0, "duration": 2 * SEC }))]),
    );
    for clip_t in [0, 1, SEC / 3, SEC + 7, 2 * SEC - 1] {
        let key = key(&handle, START + clip_t, 11);
        assert_eq!(int(&key, "/at"), IN + 2 * clip_t, "{clip_t}: {key}");
        assert_eq!(key["media"], json!(1));
        assert_eq!(key["reversed"], json!(false));
    }
}

#[test]
fn at_on_a_ramp_follows_s_of_t() {
    // ×1 → ×3 linear over the whole 4 s clip: S(t) = t + t²/D.
    let d = 4 * SEC;
    let handle = project(
        file_cursor(),
        json!([clip(
            json!({ "actions": [{ "id": 21, "start": 0, "duration": d,
                                          "curve": "linear", "end": { "speed": 3.0 } }] })
        )]),
    );
    for clip_t in [0, SEC, 780_000, 1_234_567, 3 * SEC + 11, d - 1] {
        let t = clip_t as f64;
        let oracle = (t + t * t / d as f64).round() as i64;
        let key = key(&handle, START + clip_t, 11);
        assert_eq!(int(&key, "/at"), IN + oracle, "{clip_t}: {key}");
    }
}

#[test]
fn a_still_reads_its_own_at() {
    let handle = project(
        file_cursor(),
        json!([clip(
            json!({ "source": { "kind": "still", "media": 1, "at": 3 * SEC } })
        )]),
    );
    for clip_t in [0, SEC, 3 * SEC + 5] {
        let key = key(&handle, START + clip_t, 11);
        assert_eq!(int(&key, "/at"), 3 * SEC, "{key}");
        assert_eq!(key["reversed"], json!(false));
    }
}

#[test]
fn a_reversed_clip_reads_its_own_stream() {
    let handle = project(
        file_cursor(),
        json!([clip(json!({ "speed": 1.5,
            "source": { "kind": "media", "media": 1, "in": IN, "reversed": true } }))]),
    );
    for (clip_t, read) in [(0, 0), (SEC, 900_000), (SEC + 2, 900_003)] {
        let key = key(&handle, START + clip_t, 11);
        assert_eq!(int(&key, "/at"), IN + read, "{clip_t}: {key}");
        assert_eq!(key["reversed"], json!(true));
    }
}

#[test]
fn a_nested_clip_reads_its_own_clip_time() {
    let inner = clip(json!({ "id": 51, "track": 53 }));
    let handle = Handle::from_value(&json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(file_cursor())],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{ "id": 60, "track": 2, "start": 2 * SEC, "duration": 10 * SEC,
                    "source": { "kind": "nest", "project": 50 } }],
        "nests": [{ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                    "tracks": [{ "id": 53, "name": "Inner" }], "clips": [inner] }],
        "next_id": 100
    }));
    for clip_t in [0, SEC + 3, 3 * SEC] {
        let key = key(&handle, 2 * SEC + START + clip_t, 51);
        assert_eq!(int(&key, "/at"), IN + clip_t, "{clip_t}: {key}");
    }
}

// ---- the base's smoothing and hide_idle -----------------------------------

/// L9's fixture with `base` as the clip's cursor: an action over [1 s, 3 s)
/// of clip time ending `{smoothing: 1, hide_idle: 5, scale: 3}`.
fn l9(base: Value) -> Handle {
    let mut video = json!({});
    if !base.is_null() {
        video["cursor"] = base;
    }
    project(
        file_cursor(),
        json!([clip(json!({ "video": video,
            "actions": [{ "id": 21, "start": SEC, "duration": 2 * SEC, "curve": "linear",
                          "end": { "video": { "cursor":
                              { "smoothing": 1.0, "hide_idle": 5.0, "scale": 3.0 } } } }] }))]),
    )
}

#[test]
fn smoothing_and_hide_idle_come_from_the_base_at_every_time() {
    let handle = l9(json!({ "smoothing": 0.4, "hide_idle": 2.0 }));
    let mut scales = Vec::new();
    for clip_t in [SEC / 2, 3 * SEC / 2, 5 * SEC / 2, 7 * SEC / 2] {
        let key = key(&handle, START + clip_t, 11);
        assert_eq!(num(&key, "/smoothing"), 0.4, "{clip_t}: {key}");
        assert_eq!(num(&key, "/hide_idle"), 2.0, "{clip_t}: {key}");
        assert_eq!(num(&key, "/props/smoothing"), 0.4, "{clip_t}: {key}");
        assert_eq!(num(&key, "/props/hide_idle"), 2.0, "{clip_t}: {key}");
        scales.push(num(&key, "/props/scale"));
    }
    assert_eq!(scales[0], 1.0);
    assert!(scales[1] > 1.0 && scales[1] < 3.0, "{scales:?}");
    assert!(scales[2] > scales[1] && scales[2] < 3.0, "{scales:?}");
    assert_eq!(scales[3], 3.0);
}

#[test]
fn a_split_and_a_freeze_keep_the_base_values() {
    let handle = l9(json!({ "smoothing": 0.0 }));
    for cut in [7 * SEC / 2, 2 * SEC] {
        let split = handle.apply(&json!({ "op": "split", "clips": [11], "at": START + cut }));
        let value = split.value();
        let second = array(&value, "/clips")
            .iter()
            .find(|c| int(c, "/start") == START + cut)
            .expect("a second half")
            .clone();
        assert_eq!(
            num(&second, "/video/cursor/smoothing"),
            0.0,
            "{cut}: {second}"
        );
        assert_eq!(
            at(&second, "/video/cursor/hide_idle"),
            &Value::Null,
            "{second}"
        );
        let id = int(&second, "/id") as u64;
        let key = key(&split, START + cut + SEC / 10, id);
        assert_eq!(num(&key, "/smoothing"), 0.0, "{cut}: {key}");
        assert_eq!(key["hide_idle"], Value::Null, "{cut}: {key}");
    }

    let frozen = handle.apply(&json!({ "op": "freeze_frame", "clip": 11,
                                       "at": START + 7 * SEC / 2, "duration": SEC }));
    let value = frozen.value();
    let still = array(&value, "/clips")
        .iter()
        .find(|c| text(c, "/source/kind") == "still")
        .expect("a still")
        .clone();
    assert_eq!(num(&still, "/video/cursor/smoothing"), 0.0, "{still}");
    assert_eq!(
        at(&still, "/video/cursor/hide_idle"),
        &Value::Null,
        "{still}"
    );
    let key = key(
        &frozen,
        START + 7 * SEC / 2 + SEC / 10,
        int(&still, "/id") as u64,
    );
    assert_eq!(num(&key, "/smoothing"), 0.0, "{key}");
    assert_eq!(key["hide_idle"], Value::Null, "{key}");
}

#[test]
fn on_a_clip_with_no_cursor_an_end_switches_at_the_end() {
    let handle = project(
        file_cursor(),
        json!([clip(json!({
            "actions": [{ "id": 21, "start": SEC, "duration": 2 * SEC, "curve": "linear",
                          "end": { "video": { "cursor": { "scale": 3.0, "smoothing": 1.0 } } } }] }))]),
    );
    for (clip_t, scale) in [(3 * SEC / 2, 1.0), (5 * SEC / 2, 1.0), (7 * SEC / 2, 3.0)] {
        let key = key(&handle, START + clip_t, 11);
        assert_eq!(num(&key, "/props/scale"), scale, "{clip_t}: {key}");
        assert_eq!(num(&key, "/smoothing"), 0.0, "{clip_t}: {key}");
    }
    let split = handle
        .apply(&json!({ "op": "split", "clips": [11], "at": START + 7 * SEC / 2 }))
        .value();
    let second = array(&split, "/clips")
        .iter()
        .find(|c| int(c, "/start") == START + 7 * SEC / 2)
        .expect("a second half")
        .clone();
    assert_eq!(num(&second, "/video/cursor/smoothing"), 0.0, "{second}");
    assert_eq!(num(&second, "/video/cursor/scale"), 3.0, "{second}");
}

// ---- null ----------------------------------------------------------------

#[test]
fn the_key_is_null_unless_a_cursor_would_draw() {
    let with = |cursor: Value, video: Value| {
        let handle = project(cursor, json!([clip(json!({ "video": video }))]));
        key(&handle, START + SEC, 11)
    };
    assert_eq!(with(Value::Null, json!({})), Value::Null);
    assert_eq!(
        with(
            json!({ "path": CURSOR_FILE, "in_picture": true }),
            json!({})
        ),
        Value::Null
    );
    assert_eq!(
        with(file_cursor(), json!({ "cursor": { "show": false } })),
        Value::Null
    );
    let ripples = with(
        file_cursor(),
        json!({ "cursor": { "show": false, "clicks": "ripple" } }),
    );
    assert_eq!(ripples["props"]["clicks"], json!("ripple"), "{ripples}");
    assert_eq!(ripples["props"]["show"], json!(false), "{ripples}");
    let plain = with(file_cursor(), json!({}));
    assert_eq!(plain["props"], defaults(), "{plain}");

    // An image clip of an image media has no cursor key to draw.
    let image = Handle::from_value(&json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{ "id": 1, "path": "/fixtures/a.png", "kind": "image",
                    "width": 10, "height": 10 }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{ "id": 11, "track": 2, "start": 0, "duration": SEC,
                    "source": { "kind": "image", "media": 1 }, "video": {} }],
        "next_id": 100
    }));
    assert_eq!(key(&image, SEC / 2, 11), Value::Null);
}

// ---- refusals and clamps --------------------------------------------------

#[test]
fn every_refusal_is_its_own_sentence() {
    let handle = project(file_cursor(), json!([clip(json!({}))]));
    let set =
        |cursor: Value| json!({ "op": "set_video", "clips": [11], "patch": { "cursor": cursor } });
    for (cursor, sentence) in [
        (
            json!({ "scale": 9 }),
            "video.cursor.scale must be between 0.25 and 8, not 9",
        ),
        (
            json!({ "smoothing": 2 }),
            "video.cursor.smoothing must be between 0 and 1, not 2",
        ),
        (
            json!({ "hide_idle": 0.1 }),
            "video.cursor.hide_idle must be between 0.5 and 30, not 0.1",
        ),
        (
            json!({ "click_size": 5 }),
            "video.cursor.click_size must be between 0.25 and 4, not 5",
        ),
        (
            json!({ "click_color": "#ffg" }),
            "video.cursor.click_color must be a CSS color (spec §11 G-12), not \"#ffg\"",
        ),
    ] {
        assert_eq!(handle.errors(&set(cursor.clone())), sentence, "{cursor}");
    }

    let add = |descriptor: Value| json!({ "op": "add_media", "descriptor": descriptor });
    let video = json!({ "path": "/fixtures/b.mov", "kind": "video", "duration": SEC,
                        "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
                        "cursor": { "path": "  ", "in_picture": false } });
    assert_eq!(
        handle.errors(&add(video)),
        "media cursor path must not be empty"
    );
    for (descriptor, what) in [
        (
            json!({ "path": "/f/a.m4a", "kind": "audio", "duration": SEC, "has_audio": true }),
            "an audio media",
        ),
        (
            json!({ "path": "/f/a.png", "kind": "image", "width": 10, "height": 10 }),
            "an image media",
        ),
        (json!({ "path": "/f/a.cube", "kind": "lut" }), "a LUT media"),
        (
            json!({ "path": "/f/a.mov", "kind": "video", "duration": SEC, "has_audio": true }),
            "a video media without a picture",
        ),
    ] {
        let mut descriptor = descriptor;
        descriptor["cursor"] = file_cursor();
        assert_eq!(
            handle.errors(&add(descriptor)),
            format!("media.cursor needs a video media with a picture, not {what}")
        );
    }
}

#[test]
fn an_end_is_clamped_into_the_ranges() {
    let handle = project(
        file_cursor(),
        json!([clip(json!({ "video": { "cursor": {} },
            "actions": [{ "id": 21, "start": SEC, "duration": SEC, "curve": "linear",
                          "end": { "video": { "cursor":
                              { "scale": 20.0, "click_color": "bogus", "click_size": 0.0 } } } }] }))]),
    );
    let key = key(&handle, START + 3 * SEC, 11);
    assert_eq!(num(&key, "/props/scale"), 8.0, "{key}");
    assert_eq!(num(&key, "/props/click_size"), 0.25, "{key}");
    assert_eq!(key["props"]["click_color"], json!("#ffffffcc"), "{key}");
}

#[test]
fn set_video_with_an_empty_cursor_stores_the_defaults() {
    let handle = project(file_cursor(), json!([clip(json!({}))]))
        .apply(&json!({ "op": "set_video", "clips": [11], "patch": { "cursor": {} } }));
    assert_eq!(at(&handle.value(), "/clips/0/video/cursor"), &defaults());
    let stored = handle
        .apply(&json!({ "op": "set_video", "clips": [11],
                        "patch": { "cursor": { "scale": 2, "clicks": "ripple",
                                               "hide_idle": 3, "click_color": "red" } } }))
        .value();
    let cursor = at(&stored, "/clips/0/video/cursor");
    assert_eq!(
        cursor["click_color"],
        json!("red"),
        "stored as given: {cursor}"
    );
    assert_eq!(cursor["clicks"], json!("ripple"));
    assert_eq!(cursor.as_object().map(|o| o.len()), Some(8), "{cursor}");
}

// ---- add_media and relink_media -----------------------------------------

#[test]
fn add_media_stores_the_cursor_and_a_relink_probe_replaces_it() {
    let descriptor = json!({ "path": "/fixtures/b.mov", "kind": "video", "duration": 5 * SEC,
                             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
                             "cursor": { "path": CURSOR_FILE, "bookmark": "Qk0=",
                                         "in_picture": false } });
    let added = Handle::new(1920, 1080, 30, 1)
        .apply(&json!({ "op": "add_media", "descriptor": descriptor }));
    let value = added.value();
    let id = int(&value, "/media/0/id");
    assert_eq!(
        at(&value, "/media/0/cursor"),
        &json!({ "path": CURSOR_FILE, "bookmark": "Qk0=", "in_picture": false })
    );

    let probe = |cursor: Value| {
        let mut probe = json!({ "kind": "video", "duration": 5 * SEC, "width": 1920,
                                "height": 1080, "fps": [30, 1], "has_video": true });
        if !cursor.is_null() {
            probe["cursor"] = cursor;
        }
        probe
    };
    let relink = |probe: Option<Value>| {
        let mut op = json!({ "op": "relink_media", "media": id, "path": "/fixtures/c.mov" });
        if let Some(probe) = probe {
            op["probe"] = probe;
        }
        added.apply(&op).value()
    };
    let other = json!({ "path": "/fixtures/c.fjcursor", "in_picture": true });
    assert_eq!(
        by_id(&relink(Some(probe(other.clone()))), "/media", id as u64)["cursor"],
        other
    );
    assert!(
        by_id(&relink(Some(probe(Value::Null))), "/media", id as u64)
            .get("cursor")
            .is_none()
    );
    assert_eq!(
        by_id(&relink(None), "/media", id as u64)["cursor"],
        json!({ "path": CURSOR_FILE, "bookmark": "Qk0=", "in_picture": false })
    );
}

// ---- paste_attributes (CU4, spec §11 CU-40) ---------------------------------

#[test]
fn paste_attributes_carries_the_cursor() {
    // Clip 11 with a cursor, clip 12 without one; Copy's raw JSON of clip 11 pasted onto 12.
    let cursor = json!({ "show": true, "scale": 2.0, "style": "arrow", "smoothing": 0.5,
                         "hide_idle": 3.0, "clicks": "ripple", "click_color": "#ffffffcc",
                         "click_size": 1.0 });
    let source = clip(json!({ "video": { "cursor": cursor.clone() } }));
    let target = clip(json!({ "id": 12, "start": START + 5 * SEC }));
    let handle = project(file_cursor(), json!([source, target]));
    let copied = by_id(&handle.value(), "/clips", 11).clone();
    let pasted = handle.apply(&json!({ "op": "paste_attributes", "clips": [12],
                                       "payload": { "clips": [copied.clone()], "media": [] } }));
    let value = pasted.value();
    assert_eq!(
        by_id(&value, "/clips", 12)["video"]["cursor"],
        cursor,
        "{value}"
    );
    let key = key(&pasted, START + 6 * SEC, 12);
    assert_eq!(key["props"], cursor, "{key}");
    assert_eq!(num(&key, "/smoothing"), 0.5, "{key}");
    assert_eq!(num(&key, "/hide_idle"), 3.0, "{key}");

    let mut wide = copied;
    wide["video"]["cursor"]["scale"] = json!(9);
    let error = handle.errors(&json!({ "op": "paste_attributes", "clips": [12],
                                       "payload": { "clips": [wide], "media": [] } }));
    assert!(
        error.contains("video.cursor.scale must be between 0.25 and 8, not 9"),
        "{error}"
    );
}
