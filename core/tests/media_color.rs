//! Black-box tests for camera log on a media (spec §11 GR-16): the
//! `set_media_color` op, `media.color` through `add_media`, a relink, a
//! remove, a paste and a file, and what the recipe and the plan publish of
//! it as `input` — all through the C FFI, as `ReelCore.swift` drives it.
//!
//! The oracle for every sentence is the sentence itself, written out here.

mod common;

use serde_json::{json, Value};

use common::{array, at, Handle};

const VIDEO: u32 = 1;
const AUDIO: u32 = 2;
const IMAGE: u32 = 3;
const LUT: u32 = 4;
const OTHER: u32 = 5;
const TRACK: u32 = 6;
const CLIP: u32 = 7;

fn media(id: u32, kind: &str) -> Value {
    let mut row = json!({"id": id, "path": format!("/fixtures/m{id}"), "kind": kind});
    if kind == "video" || kind == "image" {
        row["width"] = json!(1024);
        row["height"] = json!(128);
        row["has_video"] = json!(kind == "video");
        row["fps"] = json!([30, 1]);
    }
    if kind == "video" || kind == "audio" {
        row["duration"] = json!(600_000);
    }
    if kind == "audio" {
        row["has_audio"] = json!(true);
    }
    row
}

/// A video, an audio, an image, a LUT and a second video; one track; one
/// clip of the video; `extra` clips beside it.
fn project(extra: Vec<Value>) -> Value {
    let mut clips = vec![
        json!({"id": CLIP, "track": TRACK, "start": 0, "duration": 600_000,
        "source": {"kind": "media", "media": VIDEO, "in": 0}}),
    ];
    clips.extend(extra);
    json!({
        "version": 19,
        "canvas": {"width": 1024, "height": 128, "fps": [30, 1]},
        "media": [media(VIDEO, "video"), media(AUDIO, "audio"), media(IMAGE, "image"),
                  media(LUT, "lut"), media(OTHER, "video")],
        "tracks": [{"id": TRACK, "name": "Track 1"}],
        "clips": clips,
        "next_id": 20
    })
}

fn handle() -> Handle {
    Handle::from_value(&project(vec![]))
}

fn set(media: u32, color: Value) -> Value {
    json!({"op": "set_media_color", "media": media, "color": color})
}

fn color_of(h: &Handle, media: u32) -> Value {
    array(&h.value(), "/media")
        .iter()
        .find(|m| m["id"] == json!(media))
        .map(|m| m.get("color").cloned().unwrap_or(Value::Null))
        .expect("the media")
}

// ---- the op ----------------------------------------------------------------

#[test]
fn every_refusal_is_its_own_sentence() {
    let h = handle();
    let cases = [
        (
            AUDIO,
            json!({"log": "slog3"}),
            "media 2 is an audio file; Camera Log is a setting on a video file".to_string(),
        ),
        (
            IMAGE,
            json!({"log": "slog3"}),
            "media 3 is an image; Camera Log is a setting on a video file".to_string(),
        ),
        (
            LUT,
            json!({"lut": LUT}),
            "media 4 is a LUT; Camera Log is a setting on a video file".to_string(),
        ),
        (
            VIDEO,
            json!({}),
            "color needs log or lut; null clears it".to_string(),
        ),
        (
            VIDEO,
            json!({"gamut": "bt2020"}),
            "color needs log or lut; null clears it".to_string(),
        ),
        (
            VIDEO,
            json!({"log": "vlog", "lut": LUT}),
            "color takes log or lut, not both".to_string(),
        ),
        (
            VIDEO,
            json!({"lut": LUT, "gamut": "bt2020"}),
            "color.gamut goes with log".to_string(),
        ),
        (
            VIDEO,
            json!({"log": "slog3", "gamut": "v_gamut"}),
            "slog3 takes gamut s_gamut3_cine or s_gamut3, not v_gamut".to_string(),
        ),
        (
            VIDEO,
            json!({"log": "apple_log", "gamut": "apple_wide_gamut"}),
            "apple_log takes gamut bt2020, not apple_wide_gamut".to_string(),
        ),
        (
            VIDEO,
            json!({"log": "apple_log2", "gamut": "bt2020"}),
            "apple_log2 takes gamut apple_wide_gamut, not bt2020".to_string(),
        ),
        (
            VIDEO,
            json!({"log": "canon_log2", "gamut": "s_gamut3"}),
            "canon_log2 takes gamut cinema_gamut or bt2020, not s_gamut3".to_string(),
        ),
        (
            VIDEO,
            json!({"log": "canon_log3", "gamut": "v_gamut"}),
            "canon_log3 takes gamut cinema_gamut or bt2020, not v_gamut".to_string(),
        ),
        (
            VIDEO,
            json!({"lut": 99}),
            "color.lut 99 is not a media of this project".to_string(),
        ),
        (
            VIDEO,
            json!({"lut": OTHER}),
            "color.lut 5 is a video media, not a lut".to_string(),
        ),
        (
            VIDEO,
            json!({"lut": AUDIO}),
            "color.lut 2 is an audio media, not a lut".to_string(),
        ),
        (
            VIDEO,
            json!({"log": "slog3", "detected": true}),
            "color.detected is written by import, not set".to_string(),
        ),
    ];
    for (media, color, sentence) in cases {
        h.refuses_with(&set(media, color), &sentence);
    }
}

#[test]
fn an_unknown_media_or_an_unreadable_colour_is_an_err() {
    let h = handle();
    assert_eq!(
        h.errors(&set(99, json!({"log": "slog3"}))),
        "no media with id 99"
    );
    assert!(h
        .errors(&set(VIDEO, json!(5)))
        .contains("color must be a json object or null, not"));
    assert!(h
        .errors(&set(VIDEO, json!("slog3")))
        .contains("color must be a json object or null, not"));
    assert!(h
        .errors(&set(VIDEO, json!({"log": "slog3", "foo": 1})))
        .contains("unknown key \"foo\" in color"));
    let variant = h.errors(&set(VIDEO, json!({"log": "clog3"})));
    assert!(variant.contains("unknown variant `clog3`"), "{variant}");
    let gamut = h.errors(&set(VIDEO, json!({"log": "slog3", "gamut": "s_gamut"})));
    assert!(gamut.contains("unknown variant `s_gamut`"), "{gamut}");
    let missing = h.errors(&json!({"op": "set_media_color", "media": VIDEO}));
    assert!(missing.contains("color"), "{missing}");
}

#[test]
fn every_pairing_is_stored_and_an_absent_gamut_is_the_curves_first() {
    let h = handle();
    let pairs = [
        ("apple_log", None, "bt2020"),
        ("apple_log", Some("bt2020"), "bt2020"),
        ("apple_log2", None, "apple_wide_gamut"),
        ("slog3", None, "s_gamut3_cine"),
        ("slog3", Some("s_gamut3_cine"), "s_gamut3_cine"),
        ("slog3", Some("s_gamut3"), "s_gamut3"),
        ("vlog", None, "v_gamut"),
        ("vlog", Some("v_gamut"), "v_gamut"),
        ("canon_log2", None, "cinema_gamut"),
        ("canon_log2", Some("cinema_gamut"), "cinema_gamut"),
        ("canon_log2", Some("bt2020"), "bt2020"),
        ("canon_log3", None, "cinema_gamut"),
        ("canon_log3", Some("cinema_gamut"), "cinema_gamut"),
        ("canon_log3", Some("bt2020"), "bt2020"),
    ];
    for (log, gamut, stored) in pairs {
        let mut color = json!({"log": log});
        if let Some(gamut) = gamut {
            color["gamut"] = json!(gamut);
        }
        let next = h.apply(&set(VIDEO, color));
        assert_eq!(color_of(&next, VIDEO), json!({"log": log, "gamut": stored}));
    }
    let lut = h.apply(&set(VIDEO, json!({"lut": LUT})));
    assert_eq!(color_of(&lut, VIDEO), json!({"lut": LUT}));
    // `detected: false` is accepted, and never written.
    let plain = h.apply(&set(VIDEO, json!({"log": "vlog", "detected": false})));
    assert_eq!(
        color_of(&plain, VIDEO),
        json!({"log": "vlog", "gamut": "v_gamut"})
    );
}

#[test]
fn null_clears_and_is_an_identity_with_nothing_to_clear() {
    let h = handle();
    h.refuses(&set(VIDEO, Value::Null));
    let set_to = h.apply(&set(VIDEO, json!({"log": "slog3"})));
    let cleared = set_to.apply(&set(VIDEO, Value::Null));
    assert_eq!(color_of(&cleared, VIDEO), Value::Null);
    assert_eq!(cleared.to_json(), h.to_json());
    // The same setting again is an identity, not a second undo step.
    set_to.refuses(&set(
        VIDEO,
        json!({"log": "slog3", "gamut": "s_gamut3_cine"}),
    ));
}

#[test]
fn a_scope_is_an_err() {
    let nested = json!({
        "version": 19,
        "canvas": {"width": 1024, "height": 128, "fps": [30, 1]},
        "media": [media(VIDEO, "video")],
        "tracks": [{"id": TRACK, "name": "Track 1"}],
        "clips": [{"id": CLIP, "track": TRACK, "start": 0, "duration": 600_000,
                   "source": {"kind": "nest", "project": 8}}],
        "nests": [{"id": 8, "name": "Nest", "width": 1024, "height": 128,
                   "tracks": [{"id": 9, "name": "Track 1"}],
                   "clips": [{"id": 10, "track": 9, "start": 0, "duration": 600_000,
                              "source": {"kind": "media", "media": VIDEO, "in": 0}}]}],
        "next_id": 20
    });
    let h = Handle::from_value(&nested);
    let mut op = set(VIDEO, json!({"log": "slog3"}));
    op["scope"] = json!(8);
    assert_eq!(
        h.errors(&op),
        "set_media_color has no meaning inside nest 8"
    );
}

// ---- add_media, relink -------------------------------------------------------

#[test]
fn add_media_takes_a_detected_colour_and_refuses_a_bad_one() {
    let h = handle();
    let descriptor = json!({"path": "/fixtures/iphone.mov", "kind": "video", "duration": 600_000,
        "width": 1024, "height": 128, "fps": [30, 1], "has_video": true,
        "color": {"log": "apple_log", "gamut": "bt2020", "detected": true}});
    let added = h.apply(&json!({"op": "add_media", "descriptor": descriptor}));
    assert_eq!(
        color_of(&added, 20),
        json!({"log": "apple_log", "gamut": "bt2020", "detected": true})
    );
    let mut wrong = descriptor.clone();
    wrong["color"] = json!({"log": "slog3", "gamut": "bt2020"});
    assert_eq!(
        h.errors(&json!({"op": "add_media", "descriptor": wrong})),
        "slog3 takes gamut s_gamut3_cine or s_gamut3, not bt2020"
    );
    let mut sound = json!({"path": "/fixtures/a.wav", "kind": "audio", "duration": 600_000,
        "has_audio": true});
    sound["color"] = json!({"log": "vlog"});
    assert_eq!(
        h.errors(&json!({"op": "add_media", "descriptor": sound})),
        "media 20 is an audio file; Camera Log is a setting on a video file"
    );
}

#[test]
fn a_relink_probe_may_not_carry_colour_and_a_relink_keeps_it() {
    let h = handle().apply(&set(VIDEO, json!({"log": "vlog"})));
    let probe = json!({"kind": "video", "duration": 600_000, "width": 1024, "height": 128,
        "fps": [30, 1], "has_video": true});
    let mut carrying = probe.clone();
    carrying["color"] = json!({"log": "slog3"});
    assert_eq!(
        h.errors(
            &json!({"op": "relink_media", "media": VIDEO, "path": "/fixtures/moved.mov",
                         "probe": carrying})
        ),
        "unknown key \"color\" in a relink probe"
    );
    for op in [
        json!({"op": "relink_media", "media": VIDEO, "path": "/fixtures/moved.mov",
               "probe": probe}),
        json!({"op": "relink_media", "media": VIDEO, "path": "/fixtures/copied.mov"}),
    ] {
        let relinked = h.apply(&op);
        assert_eq!(
            color_of(&relinked, VIDEO),
            json!({"log": "vlog", "gamut": "v_gamut"})
        );
    }
}

// ---- remove ------------------------------------------------------------------

#[test]
fn removing_a_conversion_lut_is_refused_then_cleared_with_with_clips() {
    let h = handle()
        .apply(&set(VIDEO, json!({"lut": LUT})))
        .apply(&set(OTHER, json!({"lut": LUT})));
    let remove = json!({"op": "remove_media", "media": LUT});
    h.refuses_with(
        &remove,
        "media 4 is the Camera Log of media 1 and 5; pass with_clips: true to remove it and \
         clear it",
    );
    let removed = h.apply(&json!({"op": "remove_media", "media": LUT, "with_clips": true}));
    assert_eq!(color_of(&removed, VIDEO), Value::Null);
    assert_eq!(color_of(&removed, OTHER), Value::Null);
    assert!(array(&removed.value(), "/media")
        .iter()
        .all(|m| m["id"] != json!(LUT)));
    assert_eq!(array(&removed.value(), "/clips").len(), 1);
}

#[test]
fn a_lut_both_a_look_and_a_conversion_names_both() {
    let looked = Handle::from_value(&project(vec![json!({"id": 11, "track": TRACK,
        "start": 600_000, "duration": 600_000,
        "source": {"kind": "media", "media": OTHER, "in": 0},
        "video": {"look": {"kind": "lut", "media": LUT}}})]));
    let h = looked.apply(&set(VIDEO, json!({"lut": LUT})));
    h.refuses_with(
        &json!({"op": "remove_media", "media": LUT}),
        "media 4 is the look of clip 11 and the Camera Log of media 1; pass with_clips: true \
         to remove it and clear both",
    );
    let removed = h.apply(&json!({"op": "remove_media", "media": LUT, "with_clips": true}));
    assert_eq!(color_of(&removed, VIDEO), Value::Null);
    assert_eq!(at(&removed.value(), "/clips/1/video").get("look"), None);
}

// ---- paste ---------------------------------------------------------------------

fn pasted_clip() -> Value {
    json!({"id": 30, "track": 0, "start": 0, "duration": 600_000,
           "source": {"kind": "media", "media": 31, "in": 0}})
}

#[test]
fn a_pasted_media_brings_its_conversion_lut_remapped() {
    let h = handle();
    let payload = json!({"clips": [pasted_clip()],
        "media": [{"id": 31, "path": "/fixtures/pasted.mov", "kind": "video",
                   "duration": 600_000, "width": 1024, "height": 128, "fps": [30, 1],
                   "has_video": true, "color": {"lut": 32}},
                  {"id": 32, "path": "/fixtures/pasted.cube", "kind": "lut"}]});
    let pasted = h.apply(&json!({"op": "paste", "at": 600_000, "payload": payload}));
    let rows = array(&pasted.value(), "/media").clone();
    let video = rows
        .iter()
        .find(|m| m["path"] == json!("/fixtures/pasted.mov"))
        .expect("the pasted video");
    let lut = rows
        .iter()
        .find(|m| m["path"] == json!("/fixtures/pasted.cube"))
        .expect("the pasted LUT");
    assert_ne!(lut["id"], json!(32));
    assert_eq!(video["color"], json!({"lut": lut["id"]}));
}

#[test]
fn a_pasted_media_without_its_lut_row_lands_without_colour() {
    let h = handle();
    let payload = json!({"clips": [pasted_clip()],
        "media": [{"id": 31, "path": "/fixtures/pasted.mov", "kind": "video",
                   "duration": 600_000, "width": 1024, "height": 128, "fps": [30, 1],
                   "has_video": true, "color": {"lut": 32}}]});
    let pasted = h.apply(&json!({"op": "paste", "at": 600_000, "payload": payload}));
    let video = array(&pasted.value(), "/media")
        .iter()
        .find(|m| m["path"] == json!("/fixtures/pasted.mov"))
        .cloned()
        .expect("the pasted video");
    assert_eq!(video.get("color"), None);
}

#[test]
fn a_pasted_row_matched_by_path_keeps_its_own_colour() {
    let h = handle().apply(&set(VIDEO, json!({"log": "vlog"})));
    let mut clip = pasted_clip();
    clip["source"]["media"] = json!(31);
    let payload = json!({"clips": [clip],
        "media": [{"id": 31, "path": "/fixtures/m1", "kind": "video",
                   "duration": 600_000, "width": 1024, "height": 128, "fps": [30, 1],
                   "has_video": true, "color": {"log": "slog3", "gamut": "s_gamut3"}}]});
    let pasted = h.apply(&json!({"op": "paste", "at": 600_000, "payload": payload}));
    assert_eq!(
        color_of(&pasted, VIDEO),
        json!({"log": "vlog", "gamut": "v_gamut"})
    );
}

// ---- a file --------------------------------------------------------------------

#[test]
fn a_file_with_a_bad_colour_is_refused() {
    let mut bad = project(vec![]);
    bad["media"][0]["color"] = json!({"log": "vlog", "gamut": "s_gamut3"});
    assert_eq!(
        Handle::try_from_value(&bad).expect_err("refused"),
        "media 1: vlog takes gamut v_gamut, not s_gamut3"
    );
    let mut dangling = project(vec![]);
    dangling["media"][0]["color"] = json!({"lut": 99});
    assert_eq!(
        Handle::try_from_value(&dangling).expect_err("refused"),
        "media 1: color.lut 99 is not a media of this project"
    );
    let mut sound = project(vec![]);
    sound["media"][1]["color"] = json!({"log": "vlog"});
    assert_eq!(
        Handle::try_from_value(&sound).expect_err("refused"),
        "media 2 is an audio file; Camera Log is a setting on a video file"
    );
}

#[test]
fn a_colour_round_trips() {
    let h = handle().apply(&set(VIDEO, json!({"log": "slog3", "gamut": "s_gamut3"})));
    let again = Handle::from_json(&h.to_json());
    assert_eq!(again.to_json(), h.to_json());
    assert_eq!(
        color_of(&again, VIDEO),
        json!({"log": "slog3", "gamut": "s_gamut3"})
    );
}

// ---- the recipe and the plan --------------------------------------------------

/// The layer of clip `clip` at `t`.
fn layer(recipe: &Value, clip: u32) -> Value {
    array(recipe, "/layers")
        .iter()
        .find(|l| l["clip"] == json!(clip))
        .cloned()
        .expect("the clip's layer")
}

#[test]
fn a_media_and_a_still_of_it_publish_input_and_nothing_else_does() {
    let extra = vec![
        json!({"id": 11, "track": 12, "start": 0, "duration": 600_000,
               "source": {"kind": "still", "media": VIDEO, "at": 0}}),
        json!({"id": 13, "track": 14, "start": 0, "duration": 600_000,
               "source": {"kind": "image", "media": IMAGE}}),
        json!({"id": 15, "track": 16, "start": 0, "duration": 600_000,
               "source": {"kind": "text"}, "text": {"content": "Title"}}),
    ];
    let mut value = project(extra);
    value["tracks"] = json!([{"id": TRACK}, {"id": 12}, {"id": 14}, {"id": 16}]);
    let plain = Handle::from_value(&value);
    for clip in [CLIP, 11, 13, 15] {
        assert_eq!(layer(&plain.recipe(300_000), clip)["input"], Value::Null);
    }
    let h = plain.apply(&set(VIDEO, json!({"log": "slog3"})));
    let recipe = h.recipe(300_000);
    let want = json!({"log": "slog3", "gamut": "s_gamut3_cine"});
    assert_eq!(layer(&recipe, CLIP)["input"], want);
    assert_eq!(layer(&recipe, 11)["input"], want);
    assert_eq!(layer(&recipe, 13)["input"], Value::Null);
    assert_eq!(layer(&recipe, 15)["input"], Value::Null);
    // Show Ungraded keeps the conversion: it is the file's, not a grade.
    let ungraded = h.recipe_opts(300_000, &json!({"ungraded": true}));
    assert_eq!(layer(&ungraded, CLIP)["input"], want);
    // The burn-in is no media's.
    let burnt = h.recipe_opts(300_000, &json!({"burn_in_timecode": true}));
    let last = array(&burnt, "/layers")
        .last()
        .cloned()
        .expect("the burn-in");
    assert_eq!(last["input"], Value::Null);
    // A LUT conversion publishes the LUT's id.
    let lut = plain.apply(&set(VIDEO, json!({"lut": LUT})));
    assert_eq!(
        layer(&lut.recipe(300_000), CLIP)["input"],
        json!({"lut": LUT})
    );
}

#[test]
fn the_plan_carries_input_only_when_the_media_converts() {
    let h = handle();
    let before = h.plan_text();
    assert!(!before.contains("\"input\""), "{before}");
    let set_to = h.apply(&set(VIDEO, json!({"log": "apple_log2"})));
    let plan = set_to.plan();
    assert_eq!(
        at(&plan, "/video_tracks/0/segments/0/input"),
        &json!({"log": "apple_log2", "gamut": "apple_wide_gamut"})
    );
    let cleared = set_to.apply(&set(VIDEO, Value::Null));
    assert_eq!(cleared.plan_text(), before);
}
