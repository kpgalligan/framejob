//! `add_transition` with `ripple: true`, through the FFI — spec §6 and spec
//! §11's R5-3 amendment (2026-09-16).
//!
//! The handle form (`add_transition.rs`) can never join two WHOLE files
//! placed back to back: neither has a frame beyond the cut, so it answers
//! `None`, and the Clip menu offered nothing better than a beep. The ripple
//! form makes the overlap the other way — by moving the incoming clip, and
//! everything after it on every unlocked track, left over the end of the
//! outgoing clip — so what is asserted here is the reverse of that file's
//! promise: the timeline gets SHORTER, clips downstream DO move, and no
//! clip's source window changes.

use serde_json::{json, Value};

mod common;
use common::{assert_contains, at, by_id, int, text, Handle};

/// One frame at 30 fps, written out rather than imported so a change to
/// `time::TIMESCALE` fails these tests instead of moving with them.
const FRAME: i64 = 20_000;
const SEC: i64 = 600_000;
/// The cut every fixture's pair meets at.
const CUT: i64 = 1_800_000;

// ---- fixtures ------------------------------------------------------------

/// Two whole 3-second files back to back, and the shift's neighbourhood.
///
/// - Track 1: clips 10 (0 – 3 s) and 11 (3 s – 6 s), each the WHOLE of media
///   5, so neither has a handle; clip 12, a title right after them.
/// - Track 2: clip 20 wholly before the cut, clip 22 STRADDLING it
///   (2.5 s – 3.5 s), and clip 21 after it (4 s – 5 s) — the three answers
///   to "does this clip move".
/// - Track 3: LOCKED, with clip 30 after the cut.
/// - A marker after the cut.
///
/// `locked` locks track 1 instead; `stored` gives clip 11 a stored
/// transition with a non-default style.
fn whole(locked: bool, stored: Option<Value>) -> Handle {
    let mut project = json!({
      "version": 8,
      "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
                 "fit_new_clips": true, "timecode_frames": true},
      "media": [
        {"id": 5, "path": "/m/take.mov", "kind": "video", "duration": 1_800_000,
         "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
      ],
      "tracks": [
        {"id": 1, "name": "Main", "locked": locked},
        {"id": 2, "name": "Other"},
        {"id": 3, "name": "Locked", "locked": true}
      ],
      "clips": [
        {"id": 10, "track": 1, "start": 0, "duration": CUT,
         "source": {"kind": "media", "media": 5, "in": 0}, "video": {}, "audio": {}},
        {"id": 11, "track": 1, "start": CUT, "duration": CUT,
         "source": {"kind": "media", "media": 5, "in": 0}, "video": {}, "audio": {},
         "actions": [{"id": 13, "start": 600_000, "duration": 600_000,
                      "curve": "linear", "end": {"video": {"scale": 2.0}}}]},
        {"id": 12, "track": 1, "start": 2 * CUT, "duration": 600_000,
         "source": {"kind": "text"}, "video": {}, "text": {"content": "After"}},
        {"id": 20, "track": 2, "start": 0, "duration": 600_000,
         "source": {"kind": "text"}, "video": {}, "text": {"content": "Before"}},
        {"id": 22, "track": 2, "start": 1_500_000, "duration": 600_000,
         "source": {"kind": "text"}, "video": {}, "text": {"content": "Straddle"}},
        {"id": 21, "track": 2, "start": 2_400_000, "duration": 600_000,
         "source": {"kind": "text"}, "video": {}, "text": {"content": "Later"}},
        {"id": 30, "track": 3, "start": 2_400_000, "duration": 600_000,
         "source": {"kind": "text"}, "video": {}, "text": {"content": "Locked"}}
      ],
      "markers": [{"id": 40, "time": 2_400_000, "name": "Later"}],
      "next_id": 50,
      "nests": []
    });
    if let Some(transition) = stored {
        project["clips"][1]["transition_in"] = transition;
    }
    Handle::from_value(&project)
}

fn ripple(clip: u32, duration: i64) -> Value {
    json!({"op": "add_transition", "clip": clip, "duration": duration, "ripple": true})
}

/// `(start, duration)` of a clip in a written project.
fn placement(project: &Value, id: u64) -> (i64, i64) {
    let clip = by_id(project, "/clips", id);
    (int(clip, "/start"), int(clip, "/duration"))
}

fn overlap(project: &Value, earlier: u64, later: u64) -> i64 {
    let (a_start, a_duration) = placement(project, earlier);
    a_start + a_duration - placement(project, later).0
}

// ---- the overlap it makes -------------------------------------------------

#[test]
fn without_ripple_two_whole_files_have_nothing_to_give() {
    // The case the flag exists for: the handle form clamps to nothing.
    // `ripple: false` is the handle form, spelled out.
    let project = whole(false, None);
    project.refuses(&json!({"op": "add_transition", "clip": 11, "duration": 15 * FRAME}));
    project.refuses(
        &json!({"op": "add_transition", "clip": 11, "duration": 15 * FRAME, "ripple": false}),
    );
}

#[test]
fn the_incoming_clip_slides_left_over_the_outgoing_one() {
    let after = whole(false, None).apply(&ripple(11, 15 * FRAME)).value();
    // The outgoing clip keeps every frame and its place.
    assert_eq!(placement(&after, 10), (0, CUT));
    // The incoming clip moves whole: same length, same source window, and
    // its actions stay in clip time.
    assert_eq!(placement(&after, 11), (CUT - 15 * FRAME, CUT));
    assert_eq!(int(by_id(&after, "/clips", 11), "/source/in"), 0);
    assert_eq!(
        int(by_id(&after, "/clips", 11), "/actions/0/start"),
        600_000
    );
    assert_eq!(overlap(&after, 10, 11), 15 * FRAME);
    // A new transition is minted: eased, crossfading.
    let transition = at(by_id(&after, "/clips", 11), "/transition_in");
    assert_eq!(text(transition, "/kind"), "cross_dissolve");
    assert_eq!(text(transition, "/curve"), "ease_in_out");
    assert_eq!(at(transition, "/audio"), &json!(true));
}

#[test]
fn everything_after_the_cut_moves_on_unlocked_tracks_and_nothing_else_does() {
    let before = whole(false, None);
    let after_handle = before.apply(&ripple(11, 15 * FRAME));
    let after = after_handle.value();
    let shift = 15 * FRAME;

    // At or after the cut, unlocked: moved by the overlap.
    assert_eq!(placement(&after, 12).0, 2 * CUT - shift);
    assert_eq!(placement(&after, 21).0, 2_400_000 - shift);
    // Before the cut, straddling it, or on a locked track: where they were.
    assert_eq!(placement(&after, 20).0, 0);
    assert_eq!(placement(&after, 22).0, 1_500_000);
    assert_eq!(placement(&after, 30).0, 2_400_000);
    // Markers do not move, as for `ripple_delete` and `close_gap`.
    assert_eq!(at(&after, "/markers"), at(&before.value(), "/markers"));
    // The timeline is shorter by exactly the overlap.
    assert_eq!(after_handle.duration(), before.duration() - shift);
    // Nothing gained an overlap it did not ask for.
    assert_eq!(
        at(by_id(&after, "/clips", 21), "/transition_in"),
        &Value::Null
    );
}

#[test]
fn align_means_nothing_to_the_shift() {
    let project = whole(false, None);
    let plain = project.apply(&ripple(11, 15 * FRAME)).to_json();
    for align in ["center", "before", "after"] {
        let aligned = project
            .apply(
                &json!({"op": "add_transition", "clip": 11, "duration": 15 * FRAME,
                           "align": align, "ripple": true}),
            )
            .to_json();
        assert_eq!(aligned, plain, "align {align} changed the shift");
    }
}

#[test]
fn handles_are_not_read_even_when_there_are_some() {
    // Media 5 made long, and both clips moved inside it: the handle form
    // would now extend them, and the ripple form still only slides.
    let mut project = whole(false, None).value();
    project["media"][0]["duration"] = json!(36 * SEC);
    project["clips"][0]["source"]["in"] = json!(6 * SEC);
    project["clips"][1]["source"]["in"] = json!(12 * SEC);
    let after = Handle::from_value(&project)
        .apply(&ripple(11, 15 * FRAME))
        .value();
    assert_eq!(placement(&after, 10), (0, CUT));
    assert_eq!(placement(&after, 11), (CUT - 15 * FRAME, CUT));
    assert_eq!(int(by_id(&after, "/clips", 11), "/source/in"), 12 * SEC);
}

// ---- clamps and refusals --------------------------------------------------

#[test]
fn the_overlap_is_capped_at_half_the_shorter_clip() {
    // Twenty seconds asked of two 3-second clips lands as 1.5 s. Clip 21
    // goes a long way out first: at 4 s a 1.5 s shift would push it a whole
    // second into clip 22, whose own rule would step the edit down to 1 s —
    // the case the next-but-one test is about, and not this one's.
    let mut project = whole(false, None).value();
    project["clips"][5]["start"] = json!(12 * SEC);
    let after = Handle::from_value(&project)
        .apply(&ripple(11, 20 * SEC))
        .value();
    assert_eq!(overlap(&after, 10, 11), CUT / 2);
}

#[test]
fn a_request_between_frames_is_snapped_down() {
    let after = whole(false, None)
        .apply(&ripple(11, 15 * FRAME + FRAME / 2))
        .value();
    assert_eq!(overlap(&after, 10, 11), 15 * FRAME);
}

#[test]
fn another_track_steps_the_shift_down_and_gains_a_dissolve() {
    // Track 2's clip 21 is moved to abut clip 22, and shortened to ten
    // frames: the shift pushes it INTO clip 22, whose overlap rule allows
    // five frames — so the whole edit lands at five, and clip 21 gains
    // `close_gap`'s minted dissolve.
    let mut project = whole(false, None).value();
    project["clips"][5]["start"] = json!(2_100_000);
    project["clips"][5]["duration"] = json!(10 * FRAME);
    let after = Handle::from_value(&project)
        .apply(&ripple(11, 15 * FRAME))
        .value();
    assert_eq!(overlap(&after, 10, 11), 5 * FRAME);
    assert_eq!(overlap(&after, 22, 21), 5 * FRAME);
    assert_eq!(
        text(by_id(&after, "/clips", 21), "/transition_in/kind"),
        "cross_dissolve"
    );
}

#[test]
fn an_incoming_clip_on_a_locked_track_changes_nothing() {
    whole(true, None).refuses(&ripple(11, 15 * FRAME));
}

#[test]
fn not_being_at_a_hard_cut_is_still_an_error() {
    let project = whole(false, None);
    // Clip 10 is the first on its track.
    assert_contains(&project.errors(&ripple(10, 15 * FRAME)), "first clip");
    // Clip 12 abuts clip 11; moved a second later, a gap is before it.
    let mut gapped = project.value();
    gapped["clips"][2]["start"] = json!(2 * CUT + SEC);
    assert_contains(
        &Handle::from_value(&gapped).errors(&ripple(12, 15 * FRAME)),
        "gap",
    );
    assert_contains(&project.errors(&ripple(11, 0)), "positive");
}

#[test]
fn a_mistyped_ripple_is_refused() {
    let project = whole(false, None);
    project.errors(
        &json!({"op": "add_transition", "clip": 11, "duration": 15 * FRAME, "ripple": "yes"}),
    );
}

// ---- the kind -------------------------------------------------------------

#[test]
fn a_named_kind_over_a_stored_transition_keeps_its_style() {
    let stored = json!({"kind": "wipe", "curve": "linear", "audio": false});
    let after = whole(false, Some(stored))
        .apply(
            &json!({"op": "add_transition", "clip": 11, "duration": 15 * FRAME,
                       "kind": "push_left", "ripple": true}),
        )
        .value();
    let transition = at(by_id(&after, "/clips", 11), "/transition_in");
    assert_eq!(text(transition, "/kind"), "push_left");
    assert_eq!(text(transition, "/curve"), "linear");
    assert_eq!(at(transition, "/audio"), &json!(false));
}

#[test]
fn the_original_document_is_untouched() {
    // The app's undo is the handle it kept, so applying must not mutate it.
    let before = whole(false, None);
    let text_before = before.to_json();
    let after = before.apply(&ripple(11, 15 * FRAME));
    assert_ne!(after.to_json(), text_before);
    assert_eq!(before.to_json(), text_before);
}
