//! Black-box tests for the plan's audio track labels and an audio export's
//! stems — spec §11 AU-107 and AU-108 (road map "audio" AP10 part 2a),
//! driven through `rc_project_plan`, `rc_export_presets` and
//! `rc_export_settings` as the export sheet and the `export` tool drive
//! them.
//!
//! Pinned here: every plan audio track names the timeline track it plays
//! under (two top-level tracks; a nest's contents labelled with the nest
//! clip's track; overlapping clips on one track both labelled with it);
//! `tracks` and `names` group, order and name their stems as AU-108 says
//! (`Track N` for an unnamed track, the ` (Track N)` suffix, `/` and `:` as
//! `-`, names compared Unicode-equivalent and ignoring case); a muted track,
//! a track silenced by another's solo and a track of pictures only have no
//! stem; every refusal names its cause; only the three audio rows list
//! `stems`; and settings not asked for stems carry no key.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, expect_string, int, parse_json, text, Handle};
use framejob_core::ffi_query::rc_export_presets;

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// The three rows `stems` applies to.
const AUDIO_ROWS: [&str; 3] = ["audio_m4a", "audio_wav", "audio_aiff"];

// ---- fixtures ------------------------------------------------------------

/// The media with picture and sound, and the one with picture alone.
const SOUND: u32 = 90;
const PICTURES: u32 = 91;

/// `SOUND`: 60 s of picture and sound. `PICTURES`: 60 s of picture alone.
fn media() -> Vec<Value> {
    vec![
        json!({
            "id": SOUND, "path": "/fixtures/1.mov", "kind": "video", "duration": 60 * SEC,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }),
        json!({
            "id": PICTURES, "path": "/fixtures/2.mov", "kind": "video", "duration": 60 * SEC,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": false
        }),
    ]
}

fn track(id: u32, name: &str) -> Value {
    json!({ "id": id, "name": name })
}

fn clip(id: u32, on: u32, start: i64, duration: i64, media: u32) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "media", "media": media, "in": 0 },
        "video": {}, "audio": {}
    })
}

fn project(tracks: Vec<Value>, clips: Vec<Value>, nests: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 35,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0] },
        "media": media(), "tracks": tracks, "clips": clips, "markers": [],
        "next_id": 100, "nests": nests
    }))
}

/// One audible clip on each of `tracks`, at 0–2 s.
fn one_each(tracks: Vec<Value>) -> Handle {
    let clips = tracks
        .iter()
        .enumerate()
        .map(|(i, t)| clip(50 + i as u32, int(t, "/id") as u32, 0, 2 * SEC, SOUND))
        .collect();
    project(tracks, clips, vec![])
}

// ---- reading -------------------------------------------------------------

/// The plan's `track` label of the audio track carrying `clip`'s segment.
fn label_of(plan: &Value, clip: i64) -> i64 {
    let carrying = array(plan, "/audio_tracks")
        .iter()
        .find(|t| {
            array(t, "/segments")
                .iter()
                .any(|s| int(s, "/clip") == clip)
        })
        .unwrap_or_else(|| panic!("no audio segment for clip {clip} in {plan}"));
    int(carrying, "/track")
}

fn stems(handle: &Handle, preset: &str, mode: &str) -> Vec<(String, Vec<i64>)> {
    let settings = handle
        .export_settings(preset, Some(&json!({ "stems": mode })))
        .unwrap_or_else(|msg| panic!("{preset} with stems {mode} was refused: {msg}"));
    let last = settings
        .as_object()
        .and_then(|o| o.keys().next_back().cloned())
        .unwrap_or_default();
    assert_eq!(last, "stems", "stems is the settings' last key: {settings}");
    array(&settings, "/stems")
        .iter()
        .map(|s| {
            let tracks = array(s, "/tracks")
                .iter()
                .map(|t| t.as_i64().unwrap())
                .collect();
            (text(s, "/name").to_string(), tracks)
        })
        .collect()
}

fn refusal(handle: &Handle, preset: &str, overrides: &Value) -> String {
    match handle.export_settings(preset, Some(overrides)) {
        Ok(value) => panic!("{preset} with {overrides} was expected to be refused: {value}"),
        Err(msg) => msg,
    }
}

fn named(list: &[(&str, &[i64])]) -> Vec<(String, Vec<i64>)> {
    list.iter()
        .map(|(n, t)| (n.to_string(), t.to_vec()))
        .collect()
}

// ---- the label (AU-107) --------------------------------------------------

#[test]
fn each_audio_track_names_its_timeline_track() {
    let handle = one_each(vec![track(2, "A"), track(3, "B")]);
    let plan = handle.plan();
    assert_eq!(label_of(&plan, 50), 2);
    assert_eq!(label_of(&plan, 51), 3);
    for entry in array(&plan, "/audio_tracks") {
        let keys: Vec<&String> = entry.as_object().unwrap().keys().collect();
        assert_eq!(keys[0], "id", "{entry}");
        assert_eq!(keys[1], "track", "track follows id: {entry}");
    }
}

#[test]
fn a_nests_contents_carry_the_nest_clips_track() {
    let nest = json!({
        "id": 10, "name": "Group", "width": 1920, "height": 1080,
        "tracks": [track(11, "Inner A"), track(12, "Inner B")],
        "clips": [clip(13, 11, 0, 2 * SEC, SOUND), clip(14, 12, 0, 2 * SEC, SOUND)]
    });
    let nest_clip = json!({
        "id": 4, "track": 3, "start": 0, "duration": 2 * SEC,
        "source": { "kind": "nest", "project": 10 }, "video": {}, "audio": {}
    });
    let handle = project(
        vec![track(2, "Top"), track(3, "Holds the nest")],
        vec![clip(5, 2, 0, 2 * SEC, SOUND), nest_clip],
        vec![nest],
    );
    let plan = handle.plan();
    assert_eq!(label_of(&plan, 5), 2);
    assert_eq!(
        label_of(&plan, 13),
        3,
        "nested clip under the nest clip's track"
    );
    assert_eq!(
        label_of(&plan, 14),
        3,
        "nested clip under the nest clip's track"
    );
}

#[test]
fn overlapping_clips_on_one_track_both_carry_it() {
    let handle = project(
        vec![track(2, "First"), track(3, "Overlaps")],
        vec![
            clip(5, 2, 0, 4 * SEC, SOUND),
            clip(6, 3, 0, 4 * SEC, SOUND),
            clip(7, 3, 3 * SEC, 4 * SEC, SOUND),
        ],
        vec![],
    );
    let plan = handle.plan();
    let carrying: Vec<i64> = array(&plan, "/audio_tracks")
        .iter()
        .filter(|t| {
            array(t, "/segments")
                .iter()
                .any(|s| [6, 7].contains(&int(s, "/clip")))
        })
        .map(|t| int(t, "/id"))
        .collect();
    assert_eq!(
        carrying.len(),
        2,
        "the overlap takes two composition tracks"
    );
    assert_eq!(label_of(&plan, 5), 2);
    assert_eq!(label_of(&plan, 6), 3);
    assert_eq!(label_of(&plan, 7), 3);
}

// ---- grouping, order and names (AU-108) -----------------------------------

#[test]
fn tracks_mode_is_one_stem_per_heard_track_in_timeline_order() {
    let handle = one_each(vec![
        track(2, " Dialogue "),
        track(3, ""),
        track(4, "Music"),
    ]);
    assert_eq!(
        stems(&handle, "audio_wav", "tracks"),
        named(&[("Dialogue", &[2]), ("Track 2", &[3]), ("Music", &[4])])
    );
}

#[test]
fn names_mode_groups_case_insensitively_by_the_first_spelling() {
    let handle = one_each(vec![
        track(2, "Music"),
        track(3, "Dialogue"),
        track(4, " music"),
        track(5, ""),
        track(6, "  "),
    ]);
    assert_eq!(
        stems(&handle, "audio_m4a", "names"),
        named(&[
            ("Music", &[2, 4]),
            ("Dialogue", &[3]),
            ("Track 4", &[5]),
            ("Track 5", &[6]),
        ])
    );
}

#[test]
fn names_differing_only_in_unicode_normalisation_are_one_name() {
    // APFS stores a precomposed and a decomposed é, in any case, as one file
    // name, so they group in `names` and take the suffix in `tracks` (#394).
    let grouped = one_each(vec![
        track(2, "caf\u{e9}"),
        track(3, "CAFE\u{301}"),
        track(4, "Music"),
    ]);
    assert_eq!(
        stems(&grouped, "audio_wav", "names"),
        named(&[("caf\u{e9}", &[2, 3]), ("Music", &[4])])
    );
    let apart = one_each(vec![track(2, "caf\u{e9}"), track(3, "cafe\u{301}")]);
    assert_eq!(
        stems(&apart, "audio_wav", "tracks"),
        named(&[("caf\u{e9}", &[2]), ("cafe\u{301} (Track 2)", &[3])])
    );
    // A letter precomposed only in lowercase against its decomposed capital.
    let caron = one_each(vec![track(2, "\u{1F0}"), track(3, "J\u{30C}")]);
    assert_eq!(
        stems(&caron, "audio_wav", "names"),
        named(&[("\u{1F0}", &[2, 3])])
    );
}

#[test]
fn a_name_an_earlier_stem_holds_gets_its_track_number() {
    let handle = one_each(vec![track(2, "VO"), track(3, "vo"), track(4, "Track 1")]);
    // `tracks` keeps "VO" and "vo" apart; the second is suffixed, and an
    // unnamed track's label is no exception.
    assert_eq!(
        stems(&handle, "audio_aiff", "tracks"),
        named(&[("VO", &[2]), ("vo (Track 2)", &[3]), ("Track 1", &[4])])
    );
    let unnamed_first = one_each(vec![track(2, ""), track(3, "track 1")]);
    assert_eq!(
        stems(&unnamed_first, "audio_wav", "tracks"),
        named(&[("Track 1", &[2]), ("track 1 (Track 2)", &[3])])
    );
}

#[test]
fn a_suffixed_name_an_earlier_stem_holds_gets_a_count() {
    // "a" (the third track) would take "a (Track 3)", which the first holds.
    let handle = one_each(vec![track(2, "a (Track 3)"), track(3, "A"), track(4, "a")]);
    assert_eq!(
        stems(&handle, "audio_wav", "tracks"),
        named(&[("a (Track 3)", &[2]), ("A", &[3]), ("a (Track 3, 2)", &[4])])
    );
    // The count climbs past one an earlier stem holds, ignoring case.
    let twice = one_each(vec![
        track(2, "a (Track 4)"),
        track(3, "a (track 4, 2)"),
        track(4, "A"),
        track(5, "a"),
    ]);
    assert_eq!(
        stems(&twice, "audio_wav", "tracks"),
        named(&[
            ("a (Track 4)", &[2]),
            ("a (track 4, 2)", &[3]),
            ("A", &[4]),
            ("a (Track 4, 3)", &[5]),
        ])
    );
}

#[test]
fn slashes_and_colons_become_dashes() {
    let handle = one_each(vec![track(2, "A/B: take 2")]);
    assert_eq!(
        stems(&handle, "audio_wav", "tracks"),
        named(&[("A-B- take 2", &[2])])
    );
}

// ---- who is heard ---------------------------------------------------------

#[test]
fn a_muted_track_has_no_stem() {
    let handle = one_each(vec![
        track(2, "Kept"),
        json!({ "id": 3, "name": "Muted", "muted": true }),
    ]);
    assert_eq!(
        stems(&handle, "audio_wav", "tracks"),
        named(&[("Kept", &[2])])
    );
}

#[test]
fn a_solo_silences_every_other_track() {
    let handle = one_each(vec![
        track(2, "Other"),
        json!({ "id": 3, "name": "Soloed", "solo": true }),
        track(4, "Another"),
    ]);
    assert_eq!(
        stems(&handle, "audio_wav", "names"),
        named(&[("Soloed", &[3])])
    );
}

#[test]
fn a_track_of_pictures_alone_has_no_stem() {
    let handle = project(
        vec![track(2, "Pictures"), track(3, "Sound"), track(4, "Empty")],
        vec![
            clip(5, 2, 0, 2 * SEC, PICTURES),
            clip(6, 3, 0, 2 * SEC, SOUND),
        ],
        vec![],
    );
    assert_eq!(
        stems(&handle, "audio_wav", "tracks"),
        named(&[("Sound", &[3])])
    );
}

// ---- refusals and the rows -------------------------------------------------

#[test]
fn every_refusal_names_its_cause() {
    let handle = one_each(vec![track(2, "A")]);
    let on_movie = refusal(&handle, "h264", &json!({ "stems": "tracks" }));
    assert_eq!(
        on_movie,
        "h264 has no stems; stems applies to audio_m4a, audio_wav and audio_aiff"
    );
    for preset in ["h264", "audio_wav"] {
        let bad = refusal(&handle, preset, &json!({ "stems": "both" }));
        assert_eq!(
            bad,
            "export stems must be \"tracks\" or \"names\", not \"both\""
        );
    }
    let wrong_type = refusal(&handle, "audio_wav", &json!({ "stems": 2 }));
    assert_contains(&wrong_type, "export stems must be");
    let all_muted = one_each(vec![json!({ "id": 2, "name": "A", "muted": true })]);
    assert_eq!(
        refusal(&all_muted, "audio_wav", &json!({ "stems": "tracks" })),
        "stems: no track is heard, so there is no stem to write"
    );
}

#[test]
fn only_the_three_audio_rows_list_stems() {
    let text = expect_string(unsafe { rc_export_presets() }, "rc_export_presets");
    let rows = match parse_json(&text, "rc_export_presets") {
        Value::Array(rows) => rows,
        other => panic!("rc_export_presets is not an array: {other}"),
    };
    let listing: Vec<String> = rows
        .iter()
        .filter(|row| row.get("stems").is_some())
        .map(|row| text_of(row, "/id"))
        .collect();
    assert_eq!(listing, AUDIO_ROWS.to_vec());
    for row in &rows {
        if let Some(modes) = row.get("stems") {
            assert_eq!(modes, &json!(["tracks", "names"]), "{row}");
        }
    }
}

fn text_of(value: &Value, pointer: &str) -> String {
    text(value, pointer).to_string()
}

#[test]
fn settings_not_asked_carry_no_key() {
    let handle = one_each(vec![track(2, "A")]);
    for preset in AUDIO_ROWS.iter().chain(["h264"].iter()) {
        let settings = handle
            .export_settings(preset, None)
            .unwrap_or_else(|msg| panic!("{preset}: {msg}"));
        assert!(settings.get("stems").is_none(), "{preset}: {settings}");
        let nulled = handle
            .export_settings(preset, Some(&json!({ "stems": null })))
            .unwrap_or_else(|msg| panic!("{preset}: {msg}"));
        assert_eq!(nulled, settings, "null is absent");
    }
}
