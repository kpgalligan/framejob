//! Black-box tests for what `paste` and `paste_attributes` ADMIT (issue
//! #349), driven through `rc_project_apply` exactly as the app drives it.
//!
//! Pinned here: a media row a paste APPENDS passes `add_media`'s own field
//! checks (`check_media_fields`, an error `pasted media N: …` naming the
//! payload's id) with its `original` stored as `add_media` stores it, and a
//! row matched by path is the project's own and is not checked; and every
//! pasted video group goes through `set_video`'s own chain
//! (`Project::settle_video`), so an identity curve is dropped as a patch
//! drops it (spec §11 GR-12) — after the range check, so a malformed
//! identity-shaped curve is still named in `set_video`'s sentence.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, Handle, Outcome};

const SEC: i64 = 600_000;

/// One valid video row at `/m/talk.mov`.
fn video_row(id: u32, path: &str) -> Value {
    json!({"id": id, "path": path, "kind": "video", "duration": 36_000_000,
           "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
           "has_audio": false})
}

/// A one-track project with clip 10 (uncurved) showing `/m/talk.mov` (id 1).
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 17,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [video_row(1, "/m/talk.mov")],
        "tracks": [{"id": 4, "name": "Track 1"}],
        "clips": [
            {"id": 10, "track": 4, "start": 0, "duration": 6 * SEC, "speed": 1.0,
             "source": {"kind": "media", "media": 1, "in": 0},
             "enabled": {"video": true, "audio": false}, "video": {}}
        ],
        "next_id": 20
    }))
}

/// A payload of one clip showing payload media 7, its video group `video`,
/// carrying `row` as media 7.
fn payload(row: Value, video: Value) -> Value {
    json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": SEC, "speed": 1.0,
                   "source": {"kind": "media", "media": 7, "in": 0},
                   "enabled": {"video": true, "audio": false}, "video": video}],
        "media": [row]
    })
}

fn paste(payload: Value) -> Value {
    json!({"op": "paste", "at": 10 * SEC, "payload": payload})
}

/// Media 7 at a path the project does not have, with `fields` laid over a
/// valid video row.
fn new_row(fields: Value) -> Value {
    let mut row = video_row(7, "/m/new.mov");
    for (key, value) in fields.as_object().expect("an object") {
        row[key] = value.clone();
    }
    row
}

#[test]
fn an_appended_row_with_pixels_and_no_size_is_an_error() {
    let msg = project().errors(&paste(payload(
        new_row(json!({"width": 0, "height": 0})),
        json!({}),
    )));
    assert_eq!(
        msg,
        "pasted media 7: a media with pixels must have a positive width and height, not 0x0"
    );
}

#[test]
fn an_appended_row_with_a_negative_duration_is_an_error() {
    let msg = project().errors(&paste(payload(new_row(json!({"duration": -1})), json!({}))));
    assert_eq!(
        msg,
        "pasted media 7: media duration must not be negative, not -1"
    );
}

#[test]
fn an_appended_row_whose_original_path_is_blank_is_an_error() {
    let msg = project().errors(&paste(payload(
        new_row(json!({"original": {"path": "   "}})),
        json!({}),
    )));
    assert_eq!(msg, "pasted media 7: media original path must not be empty");
}

#[test]
fn an_appended_row_stores_its_original_as_add_media_does() {
    let pasted = project().apply(&paste(payload(
        new_row(json!({"original": {"path": "  /o/a.webm  ", "bookmark": "  "}})),
        json!({}),
    )));
    let value = pasted.value();
    let row = array(&value, "/media")
        .iter()
        .find(|m| m["path"] == json!("/m/new.mov"))
        .cloned()
        .expect("the row appended");
    let added = project()
        .apply(&json!({"op": "add_media", "descriptor": {
            "path": "/m/added.mov", "kind": "video", "duration": 36_000_000,
            "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
            "has_audio": false,
            "original": {"path": "  /o/a.webm  ", "bookmark": "  "}}}))
        .value();
    let added_row = array(&added, "/media")
        .iter()
        .find(|m| m["path"] == json!("/m/added.mov"))
        .cloned()
        .expect("the row added");
    assert_eq!(row["original"]["path"], json!("/o/a.webm"));
    assert!(row["original"]["bookmark"].is_null(), "{row}");
    assert_eq!(row["original"], added_row["original"]);
}

#[test]
fn a_row_matched_by_path_is_not_checked_and_stays_the_projects() {
    let before = project().value();
    let mut row = video_row(7, "/m/talk.mov");
    row["width"] = json!(0);
    row["height"] = json!(0);
    let answer = project().try_apply(&paste(payload(row, json!({}))));
    let Ok(Outcome::Applied(pasted)) = answer else {
        panic!("a paste matched by path should apply: {answer:?}");
    };
    let value = pasted.value();
    assert_eq!(array(&value, "/media"), array(&before, "/media"));
}

#[test]
fn paste_attributes_refuses_an_appended_lut_row_carrying_a_duration() {
    let lut = json!({"id": 7, "path": "/l/a.cube", "kind": "lut", "duration": 600_000});
    let source = json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": SEC, "speed": 1.0,
                   "source": {"kind": "media", "media": 1, "in": 0},
                   "enabled": {"video": true, "audio": false},
                   "video": {"look": {"kind": "lut", "media": 7}}}],
        "media": [video_row(1, "/m/talk.mov"), lut]
    });
    let msg = project().errors(&json!({"op": "paste_attributes", "clips": [10],
                                       "payload": source, "groups": ["video"]}));
    assert_eq!(
        msg,
        "pasted media 7: a lut media has no video, audio, alpha or duration"
    );
}

#[test]
fn paste_attributes_of_an_identity_curve_onto_an_uncurved_clip_is_an_identity() {
    let source = payload(
        video_row(7, "/m/talk.mov"),
        json!({"curves": {"master": [[0, 0], [1, 1]]}}),
    );
    let answer = project().try_apply(&json!({"op": "paste_attributes", "clips": [10],
                                             "payload": source, "groups": ["video"]}));
    assert!(matches!(answer, Ok(Outcome::Identity)), "{answer:?}");
}

#[test]
fn a_pasted_identity_curve_is_stored_as_none() {
    let identity = json!({"master": [[0, 0], [1, 1]]});
    let pasted = project().apply(&paste(payload(
        video_row(7, "/m/talk.mov"),
        json!({"curves": identity}),
    )));
    let value = pasted.value();
    let landed = array(&value, "/clips")
        .iter()
        .map(|c| c["id"].as_u64().expect("an id"))
        .find(|id| *id != 10)
        .expect("the landed clip");
    assert!(
        by_id(&value, "/clips", landed)["video"]
            .get("curves")
            .is_none(),
        "{value}"
    );
    let answer = pasted.try_apply(&json!({"op": "set_video", "clips": [landed],
                                          "patch": {"curves": identity}}));
    assert!(matches!(answer, Ok(Outcome::Identity)), "{answer:?}");
}

#[test]
fn a_malformed_identity_shaped_curve_is_named_as_set_video_names_it() {
    let curves = json!({"master": [[0, 0], [0, 0], [1, 1]]});
    let patched = project().errors(&json!({"op": "set_video", "clips": [10],
                                           "patch": {"curves": curves}}));
    let source = payload(video_row(7, "/m/talk.mov"), json!({"curves": curves}));
    let pasted = project().errors(&json!({"op": "paste_attributes", "clips": [10],
                                          "payload": source, "groups": ["video"]}));
    assert_eq!(pasted, patched);
}
