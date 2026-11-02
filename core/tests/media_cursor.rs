//! Black-box tests for `set_media_cursor` (road map "creator-jobs" CU5,
//! spec §11 CU-50): set, replace, clear, the identities, each refusal in
//! `check_media_cursor`'s own sentence, each `Err` of the strict read, and
//! the refusal inside a scope — all through the C FFI, as `ReelCore.swift`
//! drives it.
//!
//! The oracle for every sentence is the sentence itself, written out here.

mod common;

use serde_json::{json, Value};

use common::{array, Handle};

const VIDEO: u32 = 1;
const AUDIO: u32 = 2;
const IMAGE: u32 = 3;
const LUT: u32 = 4;
const SOUNDLESS: u32 = 5;
const TRACK: u32 = 6;
const CLIP: u32 = 7;

fn media(id: u32, kind: &str, has_video: bool) -> Value {
    let mut row = json!({"id": id, "path": format!("/fixtures/m{id}"), "kind": kind});
    if kind == "video" || kind == "image" {
        row["width"] = json!(1024);
        row["height"] = json!(128);
        row["has_video"] = json!(has_video);
        row["fps"] = json!([30, 1]);
    }
    if kind == "video" || kind == "audio" {
        row["duration"] = json!(600_000);
        row["has_audio"] = json!(true);
    }
    row
}

/// A video with a picture, an audio, an image, a LUT and a video without a
/// picture; one track; one clip of the video.
fn handle() -> Handle {
    Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": 1024, "height": 128, "fps": [30, 1]},
        "media": [media(VIDEO, "video", true), media(AUDIO, "audio", false),
                  media(IMAGE, "image", false), media(LUT, "lut", false),
                  media(SOUNDLESS, "video", false)],
        "tracks": [{"id": TRACK, "name": "Track 1"}],
        "clips": [{"id": CLIP, "track": TRACK, "start": 0, "duration": 600_000,
                   "source": {"kind": "media", "media": VIDEO, "in": 0}}],
        "next_id": 20
    }))
}

fn set(media: u32, cursor: Value) -> Value {
    json!({"op": "set_media_cursor", "media": media, "cursor": cursor})
}

fn cursor_of(h: &Handle, media: u32) -> Value {
    array(&h.value(), "/media")
        .iter()
        .find(|m| m["id"] == json!(media))
        .map(|m| m.get("cursor").cloned().unwrap_or(Value::Null))
        .expect("the media")
}

#[test]
fn a_cursor_is_stored_as_given_replaced_and_cleared() {
    let h = handle();
    let first = json!({"path": "/rec/a.fjcursor", "bookmark": "Ym9vaw==", "in_picture": false});
    let set_once = h.apply(&set(VIDEO, first.clone()));
    assert_eq!(cursor_of(&set_once, VIDEO), first);

    // A second value replaces the whole record: no bookmark asked, none kept.
    let second = json!({"path": "/pkg/media/a.fjcursor", "in_picture": true});
    let moved = set_once.apply(&set(VIDEO, second.clone()));
    assert_eq!(cursor_of(&moved, VIDEO), second);

    let cleared = moved.apply(&set(VIDEO, Value::Null));
    assert_eq!(cursor_of(&cleared, VIDEO), Value::Null);
    assert!(
        !cleared.to_json().contains("fjcursor"),
        "a cleared cursor writes no key"
    );
}

#[test]
fn null_on_none_and_the_stored_value_are_identities() {
    let h = handle();
    h.refuses(&set(VIDEO, Value::Null));
    let value = json!({"path": "/rec/a.fjcursor", "in_picture": false});
    let stored = h.apply(&set(VIDEO, value.clone()));
    match stored.try_apply(&set(VIDEO, value)) {
        Ok(common::Outcome::Identity) => {}
        other => panic!("the stored value again must be an identity, not {other:?}"),
    }
    match h.try_apply(&set(VIDEO, Value::Null)) {
        Ok(common::Outcome::Identity) => {}
        other => panic!("null on a media with none must be an identity, not {other:?}"),
    }
}

#[test]
fn every_refusal_is_check_media_cursors_own_sentence() {
    let h = handle();
    let file = json!({"path": "/rec/a.fjcursor", "in_picture": false});
    let cases = [
        (
            VIDEO,
            json!({"path": "  ", "in_picture": false}),
            "media cursor path must not be empty",
        ),
        (
            SOUNDLESS,
            file.clone(),
            "media.cursor needs a video media with a picture, not a video media without a picture",
        ),
        (
            AUDIO,
            file.clone(),
            "media.cursor needs a video media with a picture, not an audio media",
        ),
        (
            IMAGE,
            file.clone(),
            "media.cursor needs a video media with a picture, not an image media",
        ),
        (
            LUT,
            file,
            "media.cursor needs a video media with a picture, not a LUT media",
        ),
    ];
    for (media, cursor, sentence) in cases {
        h.refuses_with(&set(media, cursor), sentence);
    }
}

#[test]
fn an_unknown_media_or_an_unreadable_cursor_is_an_err() {
    let h = handle();
    let file = json!({"path": "/rec/a.fjcursor", "in_picture": false});
    assert_eq!(h.errors(&set(99, file)), "no media with id 99");
    assert_eq!(
        h.errors(&set(VIDEO, json!("/rec/a.fjcursor"))),
        "cursor must be a json object or null, not \"/rec/a.fjcursor\""
    );
    assert_eq!(
        h.errors(&set(VIDEO, json!([1]))),
        "cursor must be a json object or null, not [1]"
    );
    assert_eq!(
        h.errors(&set(
            VIDEO,
            json!({"path": "/rec/a.fjcursor", "in_picture": false, "movie_size": [1, 1]})
        )),
        "unknown key \"movie_size\" in cursor"
    );
    let missing = h.errors(&set(VIDEO, json!({"path": "/rec/a.fjcursor"})));
    assert!(
        missing.starts_with("cursor does not match the schema: missing field `in_picture`"),
        "{missing}"
    );
    let typed = h.errors(&set(VIDEO, json!({"path": 3, "in_picture": false})));
    assert!(
        typed.starts_with("cursor does not match the schema: invalid type"),
        "{typed}"
    );
    // A missing `cursor` is the decoder's, before the op is reached.
    let absent = h.errors(&json!({"op": "set_media_cursor", "media": VIDEO}));
    assert!(absent.contains("cursor"), "{absent}");
}

#[test]
fn inside_a_scope_it_has_no_meaning() {
    let nested = handle().apply(&json!({"op": "nest", "clips": [CLIP]}));
    let nest = array(&nested.value(), "/nests")[0]["id"]
        .as_u64()
        .expect("the nest's id");
    let mut op = set(
        VIDEO,
        json!({"path": "/rec/a.fjcursor", "in_picture": false}),
    );
    op["scope"] = json!(nest);
    assert_eq!(
        nested.errors(&op),
        format!("set_media_cursor has no meaning inside nest {nest}")
    );
    op.as_object_mut().expect("an object").remove("scope");
    nested.apply(&op);
}
