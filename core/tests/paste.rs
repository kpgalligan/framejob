//! Black-box tests for `paste` — spec §6's clipboard op, driven through
//! `rc_project_apply` exactly as the app drives it.
//!
//! The oracle every test here leans on is [`payload_for`]: an independent
//! re-implementation of what `EditorViewController+Clipboard.swift`'s Copy
//! writes to the pasteboard, derived from the op's documented payload shape
//! (the module doc of `core/src/edit_paste.rs`) rather than captured from a
//! run. If the two ever disagree about what a payload is, these tests fail —
//! which is the point, since nothing else connects the two sides.
//!
//! What the file is built to catch, in rough order of value:
//!
//! 1. **A paste losing something.** [`a_pasted_selection_reproduces_the_originals`]
//!    compares each pasted clip against its original as a WHOLE JSON object,
//!    with only the ids, the track and the start rewritten — so any field
//!    the op forgot to carry (an action's curve, an end patch, a fade, a
//!    transition) fails it without the test having to name that field.
//! 2. **Ids.** Everything the op mints must be fresh and unique, or the next
//!    edit addresses two things with one number.
//! 3. **Placement.** The earliest clip lands exactly on `at`, the rest keep
//!    their offsets, depth keeps its lane, and a clip the overlap rule
//!    refuses lands on a new track instead of beeping.
//! 4. **The document boundary.** Media travels by PATH: a paste into a
//!    project that has never seen the file brings the row, a paste into one
//!    that has reuses it.
//! 5. **The refusals and the errors**, each named.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, at, int, num, text, Handle};

/// One frame of the 30 fps canvas every fixture uses: 600 000 ticks per
/// second (spec §5.1), so 30 fps is 20 000 ticks.
const FRAME: i64 = 20_000;

/// One second, for the fixtures that read better in seconds.
const SECOND: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

/// The project a copy comes OUT of: three tracks, so depth has somewhere to
/// be lost; a media clip with an action, an image clip and a text clip, so
/// every kind of source and every property group is in the payload.
///
/// Clip 10 is on the BACK track (depth 2), clip 20 one lane up (depth 1),
/// clip 30 on the front (depth 0).
fn source() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/logo.png", "kind": "image", "width": 800, "height": 600,
     "fps": [30, 1]}
  ],
  "tracks": [
    {"id": 4, "name": "Track 1"},
    {"id": 5, "name": "Track 2"},
    {"id": 6, "name": "Track 3"}
  ],
  "clips": [
    {"id": 10, "track": 4, "start": 0, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 600000}, "speed": 1.0,
     "video": {"x": 40, "scale": 0.8, "rotation": 12},
     "audio": {"volume": 0.9, "fade_in": 120000},
     "transition_in": {"kind": "push_left"},
     "actions": [{"id": 11, "start": 600000, "duration": 600000, "curve": "ease_in_out",
                  "end": {"video": {"scale": 0.6, "x": 520}}}]},
    {"id": 20, "track": 5, "start": 1200000, "duration": 2400000,
     "source": {"kind": "image", "media": 2}, "video": {"y": -60}},
    {"id": 30, "track": 6, "start": 0, "duration": 1200000,
     "source": {"kind": "text"}, "video": {},
     "text": {"content": "Hi", "size": 96}}
  ],
  "markers": [],
  "next_id": 40
}"#,
    )
}

/// The project a paste goes INTO when the test is about crossing a document
/// boundary: one track, no media, nothing on the timeline.
fn destination() -> Handle {
    Handle::new(1920, 1080, 30, 1)
}

// ---- the copy oracle -----------------------------------------------------

/// What Copy puts on the pasteboard for `selection`: the selected clips
/// verbatim out of the project's own JSON with each clip's `track` rewritten
/// to its DEPTH from the front of the stack (0 = front-most), plus the media
/// rows those clips name.
///
/// Written from the payload contract, not from the implementation: this is
/// the test's independent statement of what the Swift side owes the op.
fn payload_for(project: &Value, selection: &[i64]) -> Value {
    let tracks = array(project, "/tracks");
    let front = tracks.len() as i64 - 1;
    let depth_of = |track: i64| -> i64 {
        let index = tracks
            .iter()
            .position(|t| t["id"].as_i64() == Some(track))
            .unwrap_or_else(|| panic!("no track {track} in the fixture"));
        front - index as i64
    };

    let mut clips: Vec<Value> = Vec::new();
    let mut wanted: Vec<i64> = Vec::new();
    for clip in array(project, "/clips") {
        let id = clip["id"].as_i64().expect("every clip has an id");
        if !selection.contains(&id) {
            continue;
        }
        let mut copied = clip.clone();
        copied["track"] = json!(depth_of(
            clip["track"].as_i64().expect("every clip names a track")
        ));
        clips.push(copied);
        if let Some(media) = clip.pointer("/source/media").and_then(Value::as_i64) {
            if !wanted.contains(&media) {
                wanted.push(media);
            }
        }
    }
    let media: Vec<Value> = array(project, "/media")
        .iter()
        .filter(|m| m["id"].as_i64().is_some_and(|id| wanted.contains(&id)))
        .cloned()
        .collect();
    json!({"clips": clips, "media": media})
}

/// The `paste` envelope, with `track` left out (its default: the front).
fn paste_at(at: i64, payload: &Value) -> Value {
    json!({"op": "paste", "at": at, "payload": payload})
}

// ---- reading a result ----------------------------------------------------

/// The clips of `after` that were not in `before`, in the order the project
/// lists them. Compared by id rather than by position: `paste` appends, but
/// a test that assumed so would be asserting the storage order.
fn added_clips(before: &Value, after: &Value) -> Vec<Value> {
    let existing: Vec<i64> = array(before, "/clips")
        .iter()
        .filter_map(|c| c["id"].as_i64())
        .collect();
    array(after, "/clips")
        .iter()
        .filter(|c| !c["id"].as_i64().is_some_and(|id| existing.contains(&id)))
        .cloned()
        .collect()
}

/// The stacking index of a track id, 0 being the back-most (spec §6).
fn track_index(project: &Value, track: i64) -> usize {
    array(project, "/tracks")
        .iter()
        .position(|t| t["id"].as_i64() == Some(track))
        .unwrap_or_else(|| panic!("no track {track} in {project}"))
}

/// Every id the project hands out, so a test can assert the op minted fresh
/// ones and left none doubled.
fn all_ids(project: &Value) -> Vec<i64> {
    let mut ids: Vec<i64> = Vec::new();
    for key in ["/media", "/tracks", "/clips", "/markers"] {
        for item in array(project, key) {
            if let Some(id) = item["id"].as_i64() {
                ids.push(id);
            }
        }
    }
    for clip in array(project, "/clips") {
        for action in clip["actions"].as_array().unwrap_or(&Vec::new()) {
            if let Some(id) = action["id"].as_i64() {
                ids.push(id);
            }
        }
    }
    ids
}

// ---- the round trip ------------------------------------------------------

#[test]
fn a_pasted_selection_reproduces_the_originals() {
    let project = source();
    let before = project.value();
    let payload = payload_for(&before, &[10, 20]);
    // 20 s: far enough right that neither copy touches its original, so the
    // comparison is against clips no placement rule had to adjust.
    let at = 20 * SECOND;

    let pasted = project.apply(&paste_at(at, &payload));
    let after = pasted.value();
    assert_eq!(
        project.value(),
        before,
        "an edit must not touch the project it was applied to (spec §5.5)"
    );

    let copies = added_clips(&before, &after);
    assert_eq!(copies.len(), 2, "two clips were pasted: {after}");

    // The oracle: each copy IS its original with three things rewritten —
    // its id, the track it landed on, and its start. Comparing the whole
    // object is what makes this catch a field nobody thought to name.
    for (original_id, offset) in [(10i64, 0i64), (20, 1_200_000)] {
        let original = array(&before, "/clips")
            .iter()
            .find(|c| c["id"].as_i64() == Some(original_id))
            .expect("the fixture has this clip")
            .clone();
        let copy = copies
            .iter()
            .find(|c| c["start"].as_i64() == Some(at + offset))
            .unwrap_or_else(|| panic!("no pasted clip starts at {}", at + offset));

        let mut expected = original.clone();
        expected["id"] = copy["id"].clone();
        expected["track"] = copy["track"].clone();
        expected["start"] = json!(at + offset);
        // Actions are re-minted too; their spans and patches are not, which
        // is what the rest of the object comparison then checks.
        if let (Some(from), Some(to)) = (
            expected["actions"].as_array_mut(),
            copy["actions"].as_array(),
        ) {
            assert_eq!(from.len(), to.len(), "a pasted clip lost an action");
            for (action, minted) in from.iter_mut().zip(to) {
                action["id"] = minted["id"].clone();
            }
        }
        assert_eq!(&expected, copy, "the pasted clip is not its original");

        // …and the lane it landed in is the lane it was copied from, which
        // the object comparison above cannot check because the ids differ
        // only by accident of this fixture pasting into its own project.
        assert_eq!(
            track_index(&after, copy["track"].as_i64().expect("a track id")),
            track_index(&before, original["track"].as_i64().expect("a track id")),
            "a pasted clip changed lanes"
        );
    }
}

#[test]
fn the_earliest_clip_lands_on_at_and_the_rest_keep_their_offsets() {
    let project = source();
    let before = project.value();
    // Clips 20 and 30 start 1 200 000 apart, and 30 is the earlier of the
    // two — so 30 lands ON `at` and 20 lands 1 200 000 later, regardless of
    // where either of them sat in the source project.
    let payload = payload_for(&before, &[20, 30]);
    let at = 9 * SECOND;

    let after = project.apply(&paste_at(at, &payload)).value();
    let starts: Vec<i64> = added_clips(&before, &after)
        .iter()
        .filter_map(|c| c["start"].as_i64())
        .collect();
    let mut sorted = starts.clone();
    sorted.sort_unstable();
    assert_eq!(sorted, vec![at, at + 1_200_000], "got starts {starts:?}");
}

#[test]
fn every_id_a_paste_mints_is_fresh() {
    let project = source();
    let before = project.value();
    let payload = payload_for(&before, &[10, 20, 30]);
    let next_id = int(&before, "/next_id");

    // Twice, into the same project: the second paste is the one that would
    // collide if the op ever reused an id from the payload.
    let once = project.apply(&paste_at(20 * SECOND, &payload));
    let twice = once.apply(&paste_at(30 * SECOND, &payload));
    let after = twice.value();

    let copies = added_clips(&before, &after);
    assert_eq!(copies.len(), 6, "two pastes of three clips: {after}");
    for copy in &copies {
        let id = copy["id"].as_i64().expect("a pasted clip has an id");
        assert!(id >= next_id, "pasted clip {id} reused an id from before");
        for action in copy["actions"].as_array().unwrap_or(&Vec::new()) {
            let action_id = action["id"].as_i64().expect("an action has an id");
            assert!(
                action_id >= next_id,
                "pasted action {action_id} is not fresh"
            );
        }
    }

    let ids = all_ids(&after);
    let mut unique = ids.clone();
    unique.sort_unstable();
    unique.dedup();
    assert_eq!(ids.len(), unique.len(), "a paste doubled an id: {ids:?}");
    assert!(
        int(&after, "/next_id") > *unique.last().expect("the project has ids"),
        "next_id did not advance past the ids the paste minted"
    );
}

// ---- placement -----------------------------------------------------------

#[test]
fn a_paste_at_a_busy_playhead_lands_on_a_new_track() {
    let project = source();
    let before = project.value();
    // Clip 30 is the whole of its (front) track from 0 to 1 200 000, so a
    // copy of it pasted at 0 overlaps it completely — far past half the
    // shorter clip, which is what the overlap rule refuses (spec §11).
    let payload = payload_for(&before, &[30]);

    let after = project.apply(&paste_at(0, &payload)).value();
    let tracks = array(&after, "/tracks");
    assert_eq!(
        tracks.len(),
        array(&before, "/tracks").len() + 1,
        "the refused clip should have been given a track of its own"
    );

    let copies = added_clips(&before, &after);
    assert_eq!(copies.len(), 1, "one clip was pasted: {after}");
    let landed = copies[0]["track"].as_i64().expect("a track id");
    assert_eq!(
        track_index(&after, landed),
        tracks.len() - 1,
        "the fallback track goes in FRONT of everything (spec §4.1's Add Text)"
    );
    assert_eq!(
        copies[0]["start"].as_i64(),
        Some(0),
        "it still lands at `at`"
    );
    // The clip it could not sit beside is untouched — clips never push.
    assert_eq!(int(&after, "/clips/2/start"), 0);
    assert_eq!(int(&after, "/clips/2/duration"), 1_200_000);
}

#[test]
fn a_legal_overlap_is_kept_and_gains_a_transition() {
    let project = source();
    let before = project.value();
    let payload = payload_for(&before, &[30]);
    // Clip 30 runs 0 – 1 200 000 on the front track. Pasting a copy at
    // 800 000 overlaps it by 400 000 — a third of the shorter clip, so the
    // rule allows it and the copy stays on the same lane.
    let after = project.apply(&paste_at(800_000, &payload)).value();
    assert_eq!(
        array(&after, "/tracks").len(),
        array(&before, "/tracks").len(),
        "a legal overlap needs no new track"
    );

    let copies = added_clips(&before, &after);
    assert_eq!(copies.len(), 1);
    assert_eq!(copies[0]["track"].as_i64(), Some(6), "same lane");
    // An overlap IS a transition (spec §5.2), so the later clip gains the
    // default one — the same rule every other placement op obeys.
    assert_eq!(
        text(&copies[0], "/transition_in/kind"),
        "cross_dissolve",
        "a clip that gains a predecessor overlap gains a cross dissolve"
    );
}

#[test]
fn depth_is_measured_from_the_front_and_missing_tracks_are_added() {
    let project = source();
    let payload = payload_for(&project.value(), &[10, 30]);
    // Clip 30 is at depth 0 and clip 10 at depth 2, and the destination has
    // exactly one track — so two more have to appear BEHIND it.
    let empty = destination();
    let before = empty.value();
    assert_eq!(array(&before, "/tracks").len(), 1);

    let after = empty.apply(&paste_at(0, &payload)).value();
    let tracks = array(&after, "/tracks");
    assert_eq!(tracks.len(), 3, "two tracks were missing behind: {after}");

    let copies = added_clips(&before, &after);
    let front = copies
        .iter()
        .find(|c| text(c, "/source/kind") == "text")
        .expect("the text clip was pasted");
    let back = copies
        .iter()
        .find(|c| text(c, "/source/kind") == "media")
        .expect("the media clip was pasted");
    assert_eq!(
        track_index(&after, front["track"].as_i64().expect("a track id")),
        2,
        "depth 0 is the FRONT of the stack"
    );
    assert_eq!(
        track_index(&after, back["track"].as_i64().expect("a track id")),
        0,
        "depth 2 is two lanes behind it"
    );
    // The track that was already there was the front of the stack, so it is
    // the one depth 0 landed on: the new lanes went BEHIND it, never over it.
    assert_eq!(front["track"].as_i64(), Some(int(&before, "/tracks/0/id")));
}

#[test]
fn the_track_argument_retargets_the_whole_payload() {
    let project = source();
    let payload = payload_for(&project.value(), &[20, 30]);
    // Depths 1 and 0. Naming the BACK track of a two-track destination puts
    // depth 0 there and asks for one more lane behind it for depth 1.
    let empty = destination().apply(&json!({"op": "add_track"}));
    let before = empty.value();
    let back = int(&before, "/tracks/0/id");

    let after = empty
        .apply(&json!({"op": "paste", "at": 0, "track": back, "payload": payload}))
        .value();
    assert_eq!(array(&after, "/tracks").len(), 3);
    assert_eq!(
        track_index(&after, back),
        1,
        "the named track slid up when the missing lane was inserted behind it"
    );

    let copies = added_clips(&before, &after);
    let depth0 = copies
        .iter()
        .find(|c| text(c, "/source/kind") == "text")
        .expect("the text clip was pasted");
    let depth1 = copies
        .iter()
        .find(|c| text(c, "/source/kind") == "image")
        .expect("the image clip was pasted");
    assert_eq!(
        depth0["track"].as_i64(),
        Some(back),
        "depth 0 goes where told"
    );
    assert_eq!(
        track_index(&after, depth1["track"].as_i64().expect("a track id")),
        0,
        "depth 1 goes one lane behind it"
    );
}

#[test]
fn an_unknown_destination_track_is_an_error() {
    let project = source();
    let payload = payload_for(&project.value(), &[30]);
    let msg = project.errors(&json!(
        {"op": "paste", "at": 0, "track": 999, "payload": payload}));
    assert_contains(&msg, "no track with id 999");
}

// ---- crossing a document boundary ----------------------------------------

#[test]
fn a_paste_brings_the_media_it_needs_and_reuses_a_path_it_finds() {
    let project = source();
    let payload = payload_for(&project.value(), &[10]);
    let empty = destination();
    assert!(array(&empty.value(), "/media").is_empty());

    let first = empty.apply(&paste_at(0, &payload));
    let after = first.value();
    let media = array(&after, "/media");
    assert_eq!(media.len(), 1, "the media row travelled with the clip");
    assert_eq!(text(&after, "/media/0/path"), "/m/talk.mov");
    assert_eq!(text(&after, "/media/0/kind"), "video");
    assert_eq!(int(&after, "/media/0/duration"), 36_000_000);
    assert_eq!(int(&after, "/media/0/width"), 1920);
    assert!(
        int(&after, "/media/0/id") >= int(&empty.value(), "/next_id"),
        "the pasted media row gets a FRESH id, not the payload's"
    );

    let copy = &added_clips(&empty.value(), &after)[0];
    assert_eq!(
        copy.pointer("/source/media").and_then(Value::as_i64),
        Some(int(&after, "/media/0/id")),
        "the pasted clip points at the row that was added for it"
    );
    // The in point is source time, not project time, so it travels exactly.
    assert_eq!(int(copy, "/source/in"), 600_000);

    // Pasting it again finds the same path and adds no second row — the
    // one-entry-per-path rule `add_media` keeps.
    let twice = first.apply(&paste_at(10 * SECOND, &payload)).value();
    assert_eq!(array(&twice, "/media").len(), 1, "a second row appeared");
    let second = added_clips(&after, &twice);
    assert_eq!(second.len(), 1);
    assert_eq!(
        second[0].pointer("/source/media").and_then(Value::as_i64),
        Some(int(&after, "/media/0/id")),
        "the second paste reuses the row already there"
    );
}

#[test]
fn project_times_are_re_snapped_to_this_documents_frame_grid() {
    // A payload written by a 24 fps document: 25 000 ticks per frame, so
    // nothing in it lands on this project's 20 000-tick grid. The second
    // clip starts 25 000 after the first, which is 1¼ frames here and rounds
    // to one; the action's 1-tick duration is under a frame and is clamped
    // up to one.
    let payload = json!({
        "clips": [
            {"id": 1, "track": 0, "start": 100_000, "duration": 275_000,
             "source": {"kind": "text"}, "video": {}, "text": {"content": "A"},
             "actions": [{"id": 2, "start": 12_345, "duration": 1, "curve": "linear",
                          "end": {"video": {"opacity": 0}}}]},
            {"id": 3, "track": 0, "start": 125_000, "duration": 275_000,
             "source": {"kind": "text"}, "video": {}, "text": {"content": "B"}}
        ],
        "media": []
    });
    let project = destination();
    // `at` is off the grid too, and is snapped like every other tick
    // argument (spec §6): 990 000 is 49½ frames, rounded away from zero.
    let after = project.apply(&paste_at(990_000, &payload)).value();

    let clips = added_clips(&project.value(), &after);
    assert_eq!(clips.len(), 2);
    for clip in &clips {
        let start = clip["start"].as_i64().expect("a start");
        let duration = clip["duration"].as_i64().expect("a duration");
        assert_eq!(start % FRAME, 0, "start {start} is not on the frame grid");
        assert_eq!(duration % FRAME, 0, "duration {duration} is off the grid");
        assert!(duration >= FRAME, "a clip is shorter than one frame");
    }
    let mut starts: Vec<i64> = clips.iter().filter_map(|c| c["start"].as_i64()).collect();
    starts.sort_unstable();
    assert_eq!(starts, vec![1_000_000, 1_020_000], "got {starts:?}");

    let animated = clips
        .iter()
        .find(|c| !c["actions"].as_array().unwrap_or(&Vec::new()).is_empty())
        .expect("the first clip kept its action");
    assert_eq!(int(animated, "/actions/0/start"), 20_000);
    assert_eq!(int(animated, "/actions/0/duration"), FRAME);
    assert!(
        int(animated, "/actions/0/start") + int(animated, "/actions/0/duration")
            <= int(animated, "/duration"),
        "the action was left hanging off the end of its clip"
    );
    // Everything else about the action survived the re-snap untouched.
    assert_eq!(text(animated, "/actions/0/curve"), "linear");
    assert_eq!(num(animated, "/actions/0/end/video/opacity"), 0.0);
}

// ---- refusals and errors -------------------------------------------------

#[test]
fn an_empty_clip_list_changes_nothing() {
    let project = source();
    project.refuses(&paste_at(0, &json!({"clips": [], "media": []})));
    // …and so does a payload of nothing but media: there is no clip to place.
    project.refuses(&paste_at(
        0,
        &json!({"clips": [], "media": [{"id": 1, "path": "/m/talk.mov", "kind": "video"}]}),
    ));
}

#[test]
fn a_malformed_payload_names_what_was_wrong() {
    let project = source();

    assert_contains(
        &project.errors(&paste_at(0, &json!(5))),
        "a paste payload must be a json object",
    );
    assert_contains(
        &project.errors(&paste_at(0, &json!([]))),
        "a paste payload must be a json object",
    );
    assert_contains(
        &project.errors(&paste_at(0, &json!({"media": []}))),
        "missing field `clips`",
    );
    assert_contains(
        &project.errors(&paste_at(0, &json!({"clips": "everything"}))),
        "paste payload does not match the schema",
    );
    // A clip object missing a required key of the §5.2 schema.
    assert_contains(
        &project.errors(&paste_at(
            0,
            &json!({"clips": [{"id": 1, "track": 0, "start": 0,
                               "source": {"kind": "text"}}]}),
        )),
        "missing field `duration`",
    );
    // A clip whose media the payload forgot to carry — a truncated payload,
    // and the one thing that would leave a dangling media reference behind.
    assert_contains(
        &project.errors(&paste_at(
            0,
            &json!({"clips": [{"id": 1, "track": 0, "start": 0, "duration": 600000,
                               "source": {"kind": "media", "media": 77, "in": 0}}],
                    "media": []}),
        )),
        "media 77, which the payload does not carry",
    );
    assert_contains(
        &project.errors(&paste_at(
            0,
            &json!({"clips": [{"id": 1, "track": 0, "start": 0, "duration": 600000,
                               "source": {"kind": "image", "media": 7}}],
                    "media": [{"id": 7, "path": "   ", "kind": "image"}]}),
        )),
        "must not be empty",
    );
    // A depth past the track cap, which would otherwise ask for that many
    // tracks before the cap check ever ran.
    let deep = project.errors(&paste_at(
        0,
        &json!({"clips": [{"id": 1, "track": 5000, "start": 0, "duration": 600000,
                           "source": {"kind": "text"}}]}),
    ));
    assert_contains(&deep, "5000 tracks deep");
    assert_contains(&deep, "64-track limit");
}

#[test]
fn an_unknown_key_in_the_payload_is_ignored() {
    // The payload is machine-written and a newer build will add keys to it
    // (nests, for one). Ignoring what this build does not know is the same
    // rule the project schema itself follows (`model.rs`), and the opposite
    // of the op ENVELOPE, whose unknown keys are an error.
    let project = source();
    let mut payload = payload_for(&project.value(), &[30]);
    payload["nests"] = json!([]);
    payload["written_by"] = json!("a future build");
    let after = project.apply(&paste_at(20 * SECOND, &payload)).value();
    assert_eq!(added_clips(&project.value(), &after).len(), 1);

    let envelope = project.errors(&json!(
        {"op": "paste", "at": 0, "payload": {"clips": []}, "bogus": 1}));
    assert_contains(&envelope, "bogus");
}

#[test]
fn the_pasted_project_is_still_valid() {
    // `finish` validates, so an accepted paste is already a valid project —
    // but a round trip through the reader is what proves the JSON it wrote
    // can be opened again, which is the property a user sees.
    let project = source();
    let payload = payload_for(&project.value(), &[10, 20, 30]);
    let pasted = project.apply(&paste_at(20 * SECOND, &payload));
    let reopened = Handle::from_json(&pasted.to_json());
    assert_eq!(reopened.value(), pasted.value());
    assert_eq!(
        at(&reopened.value(), "/clips").as_array().map(Vec::len),
        Some(6)
    );
}
