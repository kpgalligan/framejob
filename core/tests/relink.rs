//! `relink_media` with the new file's probe (spec §11 #63), through the FFI.
//!
//! A relink that is handed the file's probe takes its duration, size, rate
//! and flags; without one it keeps the record. A media clip whose window now
//! runs past a SHORTER file's end is held to it by `duration_resnapped`, on
//! the timeline and in every stored nest, and nothing else on any clip moves.
//! The probe is checked in a fixed order, each answer pinned word for word
//! here, and a file of another kind is a refusal in the rule's own sentence.

use serde_json::{json, Value};

mod common;
use common::{at, by_id, int, Handle, Outcome};

/// One frame at 30 fps, written out so a change to the timescale fails
/// these tests instead of moving with them.
const FRAME: i64 = 20_000;

// ---- fixtures ------------------------------------------------------------

/// Media 1 is a 10 s video with sound; media 3 is another video nobody
/// relinks. On track 50:
///
/// - 10: the whole of media 1, with an action at 8 s — past a 5 s file;
/// - 11: media 1 from 0 for 2 s, inside a 5 s file;
/// - 12: media 1 from 7 s for 2 s, its `in` past a 5 s file's end;
/// - 13: media 1 from 0 at ×2, showing all 10 s in 5 s of timeline;
/// - 14: a still of media 1 at 9 s;
/// - 15: media 3, whole.
///
/// Nest 60 (shown by clip 16) and nest 70 (an orphan) each hold a whole
/// clip of media 1.
fn doc(fps: [u32; 2]) -> Value {
    json!({
        "version": 10,
        "canvas": {"width": 1920, "height": 1080, "fps": fps, "background": [0, 0, 0, 1]},
        "media": [
            {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 6_000_000,
             "width": 1920, "height": 1080, "fps": [30, 1],
             "has_video": true, "has_audio": true, "has_alpha": false},
            {"id": 3, "path": "/m/other.mov", "kind": "video", "duration": 6_000_000,
             "width": 1920, "height": 1080, "fps": [30, 1],
             "has_video": true, "has_audio": true, "has_alpha": false}
        ],
        "tracks": [{"id": 50, "name": "A"}, {"id": 51, "name": "B"}],
        "clips": [
            {"id": 10, "track": 50, "start": 0, "duration": 6_000_000,
             "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {},
             "actions": [{"id": 20, "start": 4_800_000, "duration": 600_000,
                          "curve": "linear", "end": {"video": {"opacity": 0.5}}}]},
            {"id": 11, "track": 50, "start": 6_000_000, "duration": 1_200_000,
             "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
            {"id": 12, "track": 50, "start": 7_200_000, "duration": 1_200_000,
             "source": {"kind": "media", "media": 1, "in": 4_200_000},
             "video": {}, "audio": {}},
            {"id": 13, "track": 50, "start": 8_400_000, "duration": 3_000_000, "speed": 2.0,
             "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
            {"id": 14, "track": 50, "start": 11_400_000, "duration": 600_000,
             "source": {"kind": "still", "media": 1, "at": 5_400_000}, "video": {}},
            {"id": 15, "track": 51, "start": 0, "duration": 6_000_000,
             "source": {"kind": "media", "media": 3, "in": 0}, "video": {}, "audio": {}},
            {"id": 16, "track": 51, "start": 6_000_000, "duration": 6_000_000,
             "source": {"kind": "nest", "project": 60}, "video": {}, "audio": {}}
        ],
        "nests": [
            {"id": 60, "name": "Shown", "width": 1920, "height": 1080,
             "tracks": [{"id": 61}],
             "clips": [{"id": 62, "track": 61, "start": 0, "duration": 6_000_000,
                        "source": {"kind": "media", "media": 1, "in": 0},
                        "video": {}, "audio": {}}]},
            {"id": 70, "name": "Orphan", "width": 1920, "height": 1080,
             "tracks": [{"id": 71}],
             "clips": [{"id": 72, "track": 71, "start": 0, "duration": 6_000_000,
                        "source": {"kind": "media", "media": 1, "in": 0},
                        "video": {}, "audio": {}}]}
        ],
        "markers": [], "next_id": 90
    })
}

/// A 5 s video of another size, rate and sound — every probed field moves.
fn five_seconds() -> Value {
    json!({"kind": "video", "duration": 3_000_000, "width": 1280, "height": 720,
           "fps": [25, 1], "has_video": true, "has_audio": false, "has_alpha": true})
}

fn relink(probe: Value) -> Value {
    json!({"op": "relink_media", "media": 1, "path": "/m/short.mov",
           "bookmark": "BM", "probe": probe})
}

fn project() -> Handle {
    Handle::from_value(&doc([30, 1]))
}

fn clip(project: &Value, id: u64) -> Value {
    by_id(project, "/clips", id).clone()
}

fn nested(project: &Value, nest: usize, id: u64) -> Value {
    by_id(project, &format!("/nests/{nest}/clips"), id).clone()
}

fn media_one(project: &Value) -> Value {
    by_id(project, "/media", 1).clone()
}

fn relinked() -> Value {
    project().apply(&relink(five_seconds())).value()
}

// ---- the record ----------------------------------------------------------

#[test]
fn a_probe_sets_every_probed_field() {
    assert_eq!(
        media_one(&relinked()),
        json!({"id": 1, "path": "/m/short.mov", "bookmark": "BM", "kind": "video",
               "duration": 3_000_000, "width": 1280, "height": 720, "fps": [25, 1],
               "has_video": true, "has_audio": false, "has_alpha": true,
               "original": null})
    );
}

#[test]
fn with_no_probe_the_fields_are_kept_and_no_clip_moves() {
    let before = project().value();
    let after = project()
        .apply(&json!({"op": "relink_media", "media": 1, "path": "/m/short.mov"}))
        .value();
    let mut expected = media_one(&before);
    expected["path"] = json!("/m/short.mov");
    assert_eq!(media_one(&after), expected);
    assert_eq!(after["clips"], before["clips"]);
    assert_eq!(after["nests"], before["nests"]);
}

// ---- the hold --------------------------------------------------------------

#[test]
fn a_whole_clip_is_held_to_the_shorter_end() {
    let after = relinked();
    let mut expected = clip(&project().value(), 10);
    expected["duration"] = json!(3_000_000);
    assert_eq!(clip(&after, 10), expected);
}

#[test]
fn a_clip_whose_in_is_past_the_new_end_is_one_frame_with_its_in_kept() {
    let after = relinked();
    let mut expected = clip(&project().value(), 12);
    expected["duration"] = json!(FRAME);
    assert_eq!(clip(&after, 12), expected);
    assert_eq!(int(&clip(&after, 12), "/source/in"), 4_200_000);
}

#[test]
fn a_nested_clip_is_held_in_a_shown_nest_and_in_an_orphan() {
    let before = project().value();
    let after = relinked();
    for (nest, id) in [(0, 62), (1, 72)] {
        let mut expected = nested(&before, nest, id);
        expected["duration"] = json!(3_000_000);
        assert_eq!(nested(&after, nest, id), expected, "nested clip {id}");
    }
    // The nest CLIP shows a group, not the file, and keeps its length.
    assert_eq!(clip(&after, 16), clip(&before, 16));
}

#[test]
fn a_clip_at_double_speed_is_held_to_the_window_at_its_speed() {
    let after = relinked();
    let mut expected = clip(&project().value(), 13);
    expected["duration"] = json!(1_500_000);
    assert_eq!(clip(&after, 13), expected);
}

#[test]
fn a_clip_inside_the_file_a_still_another_media_and_the_actions_are_byte_equal() {
    let before = project().value();
    let after = relinked();
    for id in [11, 14, 15] {
        assert_eq!(clip(&after, id), clip(&before, id), "clip {id}");
    }
    // The action at 8 s now lies past the held clip's end, and stays
    // where it was: `trim_end`'s posture.
    assert_eq!(
        at(&clip(&after, 10), "/actions"),
        at(&clip(&before, 10), "/actions")
    );
}

#[test]
fn a_longer_file_changes_no_clip() {
    let before = project().value();
    let mut longer = five_seconds();
    longer["duration"] = json!(12_000_000);
    let after = project().apply(&relink(longer)).value();
    assert_eq!(int(&media_one(&after), "/duration"), 12_000_000);
    assert_eq!(after["clips"], before["clips"]);
    assert_eq!(after["nests"], before["nests"]);
}

#[test]
fn at_seven_fps_a_held_duration_is_on_the_grid() {
    let project = Handle::from_value(&doc([7, 1]));
    let mut probe = five_seconds();
    // 3 100 000 ticks is frame 36.17 at 7 fps; the hold snaps DOWN to
    // frame 36, round(36 × 600 000 / 7).
    probe["duration"] = json!(3_100_000);
    let after = project.apply(&relink(probe)).value();
    assert_eq!(int(&clip(&after, 10), "/duration"), 3_085_714);
}

// ---- the answers, in order -------------------------------------------------

#[test]
fn an_unknown_media_or_an_empty_path_is_answered_first() {
    let project = project();
    assert_eq!(
        project.errors(
            &json!({"op": "relink_media", "media": 999, "path": "/m/x.mov",
                               "probe": "not an object"})
        ),
        "no media with id 999"
    );
    assert_eq!(
        project.errors(&json!({"op": "relink_media", "media": 1, "path": "  ",
                               "probe": "not an object"})),
        "media path must not be empty"
    );
}

#[test]
fn a_probe_that_is_not_an_object_names_what_it_is() {
    assert_eq!(
        project().errors(&relink(json!("a string"))),
        "a relink probe must be a json object, not \"a string\""
    );
    assert_eq!(
        project().errors(&relink(json!([1, 2]))),
        "a relink probe must be a json object, not [1,2]"
    );
}

#[test]
fn an_unknown_key_and_path_bookmark_and_id_are_named() {
    for key in ["widht", "path", "bookmark", "id"] {
        let mut probe = five_seconds();
        probe[key] = json!(1);
        // A bad kind as well, so the key is shown to be checked FIRST.
        probe["kind"] = json!("film");
        assert_eq!(
            project().errors(&relink(probe)),
            format!("unknown key \"{key}\" in a relink probe")
        );
    }
}

#[test]
fn a_value_that_does_not_match_the_schema_is_serdes_sentence() {
    let mut probe = five_seconds();
    probe["kind"] = json!("film");
    assert_eq!(
        project().errors(&relink(probe)),
        "relink probe does not match the schema: unknown variant `film`, expected one of \
         `video`, `audio`, `image`, `lut`"
    );
}

#[test]
fn the_media_field_checks_are_add_medias_own() {
    let cases = [
        (
            "duration",
            json!(-1),
            "media duration must not be negative, not -1",
        ),
        (
            "width",
            json!(0),
            "a media with pixels must have a positive width and height, not 0x720",
        ),
        (
            "height",
            json!(70_000),
            "media dimensions must be at most 65536, not 1280x70000",
        ),
        (
            "fps",
            json!([0, 1]),
            "a media with video must have a frame rate with non-zero terms, not [0, 1]",
        ),
    ];
    for (key, value, message) in cases {
        let mut probe = five_seconds();
        probe[key] = value;
        // Of another kind as well: a field check is an `Err` before the
        // kind rule is asked.
        probe["kind"] = json!("image");
        assert_eq!(project().errors(&relink(probe)), message, "{key}");
    }
}

#[test]
fn a_file_of_another_kind_is_refused_in_the_rules_sentence() {
    let probe = json!({"kind": "audio", "duration": 3_000_000, "has_audio": true});
    project().refuses_with(
        &json!({"op": "relink_media", "media": 1, "path": " /m/tone.m4a ", "probe": probe}),
        "media 1 is video media and /m/tone.m4a is audio: relink it to a file of the same \
         kind, or import this one as new media",
    );
}

#[test]
fn the_same_path_bookmark_and_probe_is_an_identity() {
    let once = project().apply(&relink(five_seconds()));
    assert!(matches!(
        once.try_apply(&relink(five_seconds())),
        Ok(Outcome::Identity)
    ));
}
