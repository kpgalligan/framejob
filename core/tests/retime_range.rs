//! `retime_range` (road map "creator-jobs" CU9a, spec §11 CU-90): one range
//! played faster or slower on every unlocked track, everything after it
//! moved up or back, through the FFI. Every oracle here is arithmetic on the
//! fixture's own numbers or another op's answer (`split`, `set_speed`), never
//! the op's own code.

mod common;

use common::{array, by_id, int, num, Handle, Outcome};
use serde_json::{json, Value};

const SEC: i64 = 600_000;
const FRAME: i64 = SEC / 30;

fn media() -> Value {
    json!([
        {"id": 51, "path": "/fixtures/screen.mov", "kind": "video", "duration": 120 * SEC,
         "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false},
        {"id": 52, "path": "/fixtures/mic.wav", "kind": "audio", "duration": 120 * SEC,
         "has_audio": true},
        {"id": 53, "path": "/fixtures/camera.mov", "kind": "video", "duration": 120 * SEC,
         "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
    ])
}

/// A media clip of media `50 + media`: 1 the screen, 2 the microphone, 3
/// the camera (ids apart from the tracks', which share the one id space).
fn media_clip(id: u32, track: u32, start: i64, duration: i64, media: u32, r#in: i64) -> Value {
    let mut clip = json!({"id": id, "track": track, "start": start, "duration": duration,
                          "source": {"kind": "media", "media": 50 + media, "in": r#in},
                          "audio": {}});
    if media != 2 {
        clip["video"] = json!({});
    }
    clip
}

fn tracks(count: u32) -> Vec<Value> {
    (1..=count)
        .map(|id| json!({"id": id, "name": format!("T{id}")}))
        .collect()
}

fn document(tracks: Vec<Value>, clips: Vec<Value>, markers: Value) -> Value {
    json!({
        "version": 28,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": media(),
        "tracks": tracks,
        "clips": clips,
        "markers": markers,
        "next_id": 200
    })
}

fn project(tracks: Vec<Value>, clips: Vec<Value>, markers: Value) -> Handle {
    Handle::from_value(&document(tracks, clips, markers))
}

fn retime(from: i64, to: i64, rate: f64) -> Value {
    json!({"op": "retime_range", "from": from, "to": to, "rate": rate})
}

/// Applies `op`, asserting it changed the project and that no two markers
/// share a tick afterwards (CU-90 (b) refusal 6's promise, on every case).
fn applied(handle: &Handle, op: &Value) -> Value {
    let value = handle.apply(op).value();
    let mut times: Vec<i64> = array(&value, "/markers")
        .iter()
        .map(|m| m["time"].as_i64().unwrap())
        .collect();
    let count = times.len();
    times.sort_unstable();
    times.dedup();
    assert_eq!(times.len(), count, "two markers share a tick: {value}");
    value
}

/// The source tick a media clip on `track` shows at project time `t`.
fn source_at(project: &Value, track: i64, t: i64) -> Option<f64> {
    array(project, "/clips").iter().find_map(|c| {
        let (start, duration) = (c["start"].as_i64()?, c["duration"].as_i64()?);
        let speed = c.get("speed").and_then(Value::as_f64).unwrap_or(1.0);
        (c["track"].as_i64()? == track && start <= t && t < start + duration)
            .then(|| c["source"]["in"].as_i64().unwrap() as f64 + (t - start) as f64 * speed)
    })
}

fn clip_on(project: &Value, track: i64, start: i64) -> Value {
    array(project, "/clips")
        .iter()
        .find(|c| c["track"].as_i64() == Some(track) && c["start"].as_i64() == Some(start))
        .unwrap_or_else(|| panic!("no clip on track {track} at {start}: {project}"))
        .clone()
}

/// Screen, microphone and camera across 0–20 s, each from its own `in`.
fn three_tracks() -> Handle {
    project(
        tracks(3),
        vec![
            media_clip(10, 1, 0, 20 * SEC, 1, 5 * SEC),
            media_clip(20, 2, 0, 20 * SEC, 2, 2 * SEC),
            media_clip(30, 3, 0, 20 * SEC, 3, SEC),
        ],
        json!([]),
    )
}

// ---- errors and refusals --------------------------------------------------

#[test]
fn errors_name_the_rate_and_the_range() {
    let p = three_tracks();
    assert_eq!(
        p.errors(&retime(SEC, 2 * SEC, 0.0)),
        "rate must be a positive number, not 0"
    );
    assert_eq!(
        p.errors(&retime(SEC, 2 * SEC, -2.0)),
        "rate must be a positive number, not -2"
    );
    // The rate is checked before the range.
    assert_eq!(
        p.errors(&retime(2 * SEC, SEC, 0.0)),
        "rate must be a positive number, not 0"
    );
    assert_eq!(
        p.errors(&retime(2 * SEC + 3, 2 * SEC + 7, 2.0)),
        "retime_range's to must be after its from (from 1200000, to 1200000 ticks, on the frame \
         grid)"
    );
}

#[test]
fn a_rate_past_the_speed_range_is_refused_before_a_short_range() {
    let p = three_tracks();
    p.refuses_with(
        &retime(SEC, SEC + FRAME, 2000.0),
        "a range can be retimed by ×0.1 to ×1000, not ×2000",
    );
    p.refuses_with(
        &retime(SEC, 2 * SEC, 0.05),
        "a range can be retimed by ×0.1 to ×1000, not ×0.05",
    );
    p.refuses_with(
        &retime(SEC, SEC + FRAME, 2.0),
        "the range from 600000 to 620000 ticks is shorter than two frames",
    );
}

#[test]
fn times_one_is_an_identity() {
    assert!(matches!(
        three_tracks().try_apply(&retime(SEC, 5 * SEC, 1.0)),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn a_locked_track_past_the_start_is_refused_before_a_nest() {
    let mut t = tracks(3);
    t[2]["locked"] = json!(true);
    let clips = vec![
        media_clip(10, 1, 0, 20 * SEC, 1, 0),
        json!({"id": 20, "track": 2, "start": 0, "duration": 10 * SEC,
               "source": {"kind": "nest", "project": 90}, "video": {}}),
        media_clip(30, 3, 0, 4 * SEC + FRAME, 3, 0),
    ];
    let mut value = document(t, clips, json!([]));
    value["nests"] = json!([{"id": 90, "name": "N", "width": 1920, "height": 1080,
                             "tracks": [], "clips": []}]);
    let p = Handle::from_value(&value);
    p.refuses_with(
        &retime(4 * SEC, 8 * SEC, 2.0),
        "track 3 is locked, so its clips after the range's start would fall out of step with \
         the retimed range",
    );
    // A locked clip that ends at `from` is out of the way; the nest is next.
    p.refuses_with(
        &retime(4 * SEC + FRAME, 8 * SEC, 2.0),
        "clip 20 is a nest, which has no speed; move the range off it, or retime inside the nest",
    );
}

#[test]
fn a_timed_caption_page_and_a_linked_clip_are_refused_in_clip_order() {
    let mut page = json!({"id": 15, "track": 1, "start": 6 * SEC, "duration": 2 * SEC,
                          "source": {"kind": "text"}, "video": {},
                          "text": {"content": "Hello there",
                                   "words": [{"start": 0, "end": SEC},
                                             {"start": SEC, "end": 2 * SEC}]}});
    let mut picture = media_clip(25, 2, 5 * SEC, 4 * SEC, 3, 0);
    picture["enabled"] = json!({"video": true, "audio": false});
    picture["linked"] = json!(26);
    let mut sound = media_clip(26, 3, 5 * SEC, 4 * SEC, 3, 0);
    sound.as_object_mut().unwrap().remove("video");
    sound["enabled"] = json!({"video": false, "audio": true});
    sound["linked"] = json!(25);
    let p = project(
        tracks(3),
        vec![page.clone(), picture.clone(), sound.clone()],
        json!([]),
    );
    p.refuses_with(
        &retime(4 * SEC, 10 * SEC, 2.0),
        "clip 15 is a caption page with timed words, which a retime cannot move; move the \
         range off it",
    );
    page["text"]["words"] = json!([]);
    let p = project(tracks(3), vec![page, picture, sound], json!([]));
    p.refuses_with(
        &retime(4 * SEC, 10 * SEC, 2.0),
        "clip 25 is linked to clip 26: Attach Audio before changing its speed or direction",
    );
}

#[test]
fn a_transition_touching_the_closed_range_is_refused_before_markers() {
    let mut later = media_clip(11, 1, 3 * SEC, 5 * SEC, 1, 10 * SEC);
    later["transition_in"] = json!({"kind": "cross_dissolve"});
    let clips = vec![media_clip(10, 1, 0, 4 * SEC, 1, 0), later];
    let markers = json!([{"id": 70, "time": 4 * SEC}, {"id": 71, "time": 4 * SEC + FRAME}]);
    let p = project(tracks(1), clips.clone(), markers);
    // The overlap runs 3 s – 4 s; a range starting at 4 s meets its end.
    let sentence = "clip 11 has a transition from clip 10 from 1800000 to 2400000 ticks, which \
                    touches the range; move the range off it or remove the transition";
    p.refuses_with(&retime(4 * SEC, 6 * SEC, 4.0), sentence);
    p.refuses_with(&retime(SEC, 3 * SEC, 4.0), sentence);
    // Clear of it by a frame the transition is no reason; the markers are.
    let p = project(tracks(1), clips, json!([]));
    applied(&p, &retime(4 * SEC + FRAME, 6 * SEC, 2.0));
}

#[test]
fn two_markers_landing_on_one_tick_are_refused_naming_both() {
    let p = project(
        tracks(1),
        vec![media_clip(10, 1, 0, 30 * SEC, 1, 0)],
        json!([{"id": 70, "time": 4 * SEC}, {"id": 71, "time": 4 * SEC + FRAME}]),
    );
    p.refuses_with(
        &retime(4 * SEC, 10 * SEC, 4.0),
        "markers 70 and 71 would both be at 2400000 ticks after a retime by ×4, and two markers \
         may not share a time; move one of them first",
    );
    // One frame before `to` and one at `to`, at ×8 over ten frames: both
    // land on to′ = from + 1 frame.
    let (from, to) = (4 * SEC, 4 * SEC + 10 * FRAME);
    let p = project(
        tracks(1),
        vec![media_clip(10, 1, 0, 30 * SEC, 1, 0)],
        json!([{"id": 72, "time": to - FRAME}, {"id": 73, "time": to}]),
    );
    p.refuses_with(
        &retime(from, to, 8.0),
        "markers 72 and 73 would both be at 2420000 ticks after a retime by ×8, and two markers \
         may not share a time; move one of them first",
    );
}

#[test]
fn a_piece_past_the_speed_limits_is_named_by_its_source_clip() {
    // Nine frames at ×300 read 90 s of the 120 s file.
    let mut fast = media_clip(10, 1, 0, 9 * FRAME, 1, 0);
    fast["speed"] = json!(300.0);
    let mut slow = media_clip(20, 2, 0, 10 * SEC, 1, 0);
    slow["speed"] = json!(0.2);
    // Clip 10 straddles `from`, so its piece is a new id; the sentence still
    // names clip 10.
    let p = project(tracks(2), vec![fast], json!([]));
    p.refuses_with(
        &retime(3 * FRAME, 6 * FRAME, 4.0),
        "clip 10 would play at ×1200, past ×1000, the fastest a clip can play",
    );
    let p = project(tracks(2), vec![slow], json!([]));
    p.refuses_with(
        &retime(2 * SEC, 4 * SEC, 0.25),
        "clip 20 would play at ×0.05, past ×0.1, the slowest a clip can play",
    );
    let tiny = json!({"id": 30, "track": 1, "start": 2 * SEC, "duration": FRAME,
                      "source": {"kind": "shape"}, "video": {},
                      "shape": {"width": 320, "height": 120}});
    let p = project(tracks(1), vec![tiny], json!([]));
    p.refuses_with(
        &retime(2 * SEC, 4 * SEC, 4.0),
        "clip 30 would last under one frame at ×4",
    );
}

#[test]
fn a_marker_collision_is_refused_before_a_piece() {
    let mut fast = media_clip(10, 1, 0, 9 * FRAME, 1, 0);
    fast["speed"] = json!(300.0);
    let p = project(
        tracks(1),
        vec![fast],
        json!([{"id": 70, "time": 3 * FRAME}, {"id": 71, "time": 4 * FRAME}]),
    );
    p.refuses_with(
        &retime(3 * FRAME, 7 * FRAME, 4.0),
        "markers 70 and 71 would both be at 60000 ticks after a retime by ×4, and two markers \
         may not share a time; move one of them first",
    );
}

// ---- what it does ----------------------------------------------------------

#[test]
fn three_tracks_at_four_times_stay_in_sync_and_lose_seven_and_a_half_seconds() {
    let before = three_tracks();
    let after = applied(&before, &retime(5 * SEC, 15 * SEC, 4.0));
    let before_value = before.value();
    assert_eq!(before.duration(), 20 * SEC);
    assert_eq!(
        Handle::from_value(&after).duration(),
        20 * SEC - 15 * SEC / 2
    );
    let lost = 15 * SEC / 2;
    for track in 1..=3 {
        let mut t = 15 * SEC - lost;
        while t < 20 * SEC - lost {
            let now = source_at(&after, track, t).expect("a clip after the range");
            let was = source_at(&before_value, track, t + lost).expect("a clip before");
            assert!(
                (now - was).abs() <= 1.0,
                "track {track} at {t}: {now} vs {was}"
            );
            t += SEC / 4;
        }
        // Inside, the piece plays the same source four times as fast.
        let piece = clip_on(&after, track, 5 * SEC);
        assert_eq!(int(&piece, "/duration"), 10 * SEC / 4);
        assert_eq!(num(&piece, "/speed"), 4.0);
        let head = source_at(&before_value, track, 5 * SEC).unwrap();
        assert_eq!(piece["source"]["in"].as_i64().unwrap() as f64, head);
    }
}

#[test]
fn straddlers_split_as_split_does() {
    let before = three_tracks();
    let after = applied(&before, &retime(5 * SEC, 15 * SEC, 4.0));
    let split = before
        .apply(&json!({"op": "split", "clips": [10, 20, 30], "at": 5 * SEC}))
        .value();
    let split_value = Handle::from_value(&split)
        .apply(
            &json!({"op": "split", "clips": array(&split, "/clips").iter()
                        .filter(|c| c["start"].as_i64() == Some(5 * SEC))
                        .map(|c| c["id"].clone()).collect::<Vec<_>>(), "at": 15 * SEC}),
        )
        .value();
    for track in 1..=3 {
        // The head is the split's head, whole.
        assert_eq!(
            clip_on(&after, track, 0),
            clip_on(&split_value, track, 0),
            "head on {track}"
        );
        // The tail is the split's tail, moved by the range's lost length.
        let mut tail = clip_on(&split_value, track, 15 * SEC);
        tail["start"] = json!(15 * SEC - 15 * SEC / 2);
        let mut got = clip_on(&after, track, 15 * SEC - 15 * SEC / 2);
        got["id"] = tail["id"].clone();
        assert_eq!(got, tail, "tail on {track}");
    }
}

#[test]
fn a_ramped_piece_is_scaled_as_set_speed_scales_it() {
    let base = project(
        tracks(1),
        vec![media_clip(10, 1, 2 * SEC, 6 * SEC, 1, 0)],
        json!([]),
    );
    let ramped = base.apply(&json!({"op": "add_speed_ramp", "clip": 10,
                                    "shape": "ramp_up", "rate": 2.0}));
    let after = applied(&ramped, &retime(2 * SEC, 8 * SEC, 2.0));
    let oracle = ramped
        .apply(&json!({"op": "set_speed", "clip": 10, "rate": 2.0}))
        .value();
    assert_eq!(by_id(&after, "/clips", 10), by_id(&oracle, "/clips", 10));
}

#[test]
fn text_shape_still_and_graphic_pieces_scale_and_a_graphic_keeps_its_length() {
    let clips = vec![
        json!({"id": 10, "track": 1, "start": 3 * SEC, "duration": 2 * SEC,
               "source": {"kind": "text"}, "video": {}, "text": {"content": "Hi"}}),
        json!({"id": 11, "track": 2, "start": 4 * SEC, "duration": 2 * SEC,
               "source": {"kind": "shape"}, "video": {},
               "shape": {"width": 320, "height": 120}}),
        json!({"id": 12, "track": 3, "start": 2 * SEC, "duration": 4 * SEC,
               "source": {"kind": "still", "media": 51, "at": SEC}, "video": {}}),
        json!({"id": 13, "track": 4, "start": 5 * SEC, "duration": 3 * SEC,
               "source": {"kind": "graphic"}, "video": {},
               "graphic": {"name": "lower-third", "width": 1920, "height": 1080,
                           "length": 90 * FRAME}}),
    ];
    let p = project(tracks(4), clips, json!([]));
    let after = applied(&p, &retime(2 * SEC, 8 * SEC, 2.0));
    // f(t) = 2 s + (t − 2 s) / 2.
    for (id, start, duration) in [
        (10, 5 * SEC / 2, SEC),
        (11, 3 * SEC, SEC),
        (12, 2 * SEC, 2 * SEC),
        (13, 7 * SEC / 2, 3 * SEC / 2),
    ] {
        let clip = by_id(&after, "/clips", id);
        assert_eq!(int(clip, "/start"), start, "clip {id}");
        assert_eq!(int(clip, "/duration"), duration, "clip {id}");
    }
    assert_eq!(
        int(by_id(&after, "/clips", 13), "/graphic/length"),
        90 * FRAME
    );
}

#[test]
fn markers_inside_scale_and_markers_after_move() {
    let p = project(
        tracks(1),
        vec![media_clip(10, 1, 0, 30 * SEC, 1, 0)],
        json!([{"id": 70, "time": SEC}, {"id": 71, "time": 6 * SEC},
               {"id": 72, "time": 10 * SEC}, {"id": 73, "time": 20 * SEC}]),
    );
    let after = applied(&p, &retime(2 * SEC, 10 * SEC, 4.0));
    let times: Vec<i64> = array(&after, "/markers")
        .iter()
        .map(|m| m["time"].as_i64().unwrap())
        .collect();
    // Before the range: still; 6 s → 2 s + 4 s / 4; at and after `to`: −6 s.
    assert_eq!(times, vec![SEC, 3 * SEC, 4 * SEC, 14 * SEC]);
}

#[test]
fn half_speed_pushes_later_clips_right() {
    let p = project(
        tracks(2),
        vec![
            media_clip(10, 1, 2 * SEC, 4 * SEC, 1, 0),
            media_clip(11, 1, 8 * SEC, 2 * SEC, 1, 0),
            media_clip(20, 2, 9 * SEC, 2 * SEC, 2, 0),
        ],
        json!([{"id": 70, "time": 8 * SEC}]),
    );
    let after = applied(&p, &retime(2 * SEC, 6 * SEC, 0.5));
    let piece = by_id(&after, "/clips", 10);
    assert_eq!(int(piece, "/duration"), 8 * SEC);
    assert_eq!(num(piece, "/speed"), 0.5);
    assert_eq!(int(by_id(&after, "/clips", 11), "/start"), 12 * SEC);
    assert_eq!(int(by_id(&after, "/clips", 20), "/start"), 13 * SEC);
    assert_eq!(int(&after, "/markers/0/time"), 12 * SEC);
}

#[test]
fn a_moved_clips_linked_partner_moves_with_it() {
    let mut picture = media_clip(10, 1, 8 * SEC, 2 * SEC, 3, 0);
    picture["enabled"] = json!({"video": true, "audio": false});
    picture["linked"] = json!(11);
    let mut sound = media_clip(11, 2, SEC / 2, SEC, 3, 0);
    sound.as_object_mut().unwrap().remove("video");
    sound["enabled"] = json!({"video": false, "audio": true});
    sound["linked"] = json!(10);
    let p = project(tracks(2), vec![picture, sound], json!([]));
    // ×0.5 over 2 s – 6 s: the range gains 4 s, and the sound before it,
    // linked to the picture after it, is carried with the picture.
    let after = applied(&p, &retime(2 * SEC, 6 * SEC, 0.5));
    assert_eq!(int(by_id(&after, "/clips", 10), "/start"), 12 * SEC);
    assert_eq!(
        int(by_id(&after, "/clips", 11), "/start"),
        SEC / 2 + 4 * SEC
    );
}

#[test]
fn keep_pitch_is_written_only_when_given() {
    let mut clip = media_clip(10, 1, 2 * SEC, 4 * SEC, 3, 0);
    clip["audio"] = json!({"keep_pitch": false});
    let outside = media_clip(11, 2, 8 * SEC, 2 * SEC, 3, 0);
    let p = project(tracks(2), vec![clip, outside], json!([]));
    let kept = applied(&p, &retime(2 * SEC, 6 * SEC, 2.0));
    assert_eq!(
        by_id(&kept, "/clips", 10)["audio"]["keep_pitch"],
        json!(false)
    );
    let mut op = retime(2 * SEC, 6 * SEC, 2.0);
    op["keep_pitch"] = json!(true);
    let set = applied(&p, &op);
    assert_eq!(
        by_id(&set, "/clips", 10)["audio"]["keep_pitch"],
        json!(true)
    );
    // A clip after the range is moved, never re-pitched.
    assert_eq!(
        by_id(&set, "/clips", 11)["audio"]["keep_pitch"],
        json!(true)
    );
    op["keep_pitch"] = json!(false);
    let unset = applied(&p, &op);
    assert_eq!(
        by_id(&unset, "/clips", 11)["audio"]["keep_pitch"],
        json!(true)
    );
}

#[test]
fn scoped_the_nest_is_retimed_and_the_documents_markers_stay() {
    let mut value = document(
        tracks(1),
        vec![
            json!({"id": 10, "track": 1, "start": 0, "duration": 20 * SEC,
                    "source": {"kind": "nest", "project": 90}, "video": {}}),
        ],
        json!([{"id": 70, "time": 4 * SEC}, {"id": 71, "time": 4 * SEC + FRAME}]),
    );
    value["nests"] = json!([{"id": 90, "name": "N", "width": 1920, "height": 1080,
                             "tracks": [{"id": 91, "name": "In"}],
                             "clips": [media_clip(92, 91, 0, 20 * SEC, 1, 0)]}]);
    let p = Handle::from_value(&value);
    let mut op = retime(4 * SEC, 12 * SEC, 4.0);
    op["scope"] = json!(90);
    // Unscoped, the two markers would collide; scoped, no marker is read.
    let after = applied(&p, &op);
    assert_eq!(array(&after, "/markers"), array(&p.value(), "/markers"));
    let inner = array(&after, "/nests/0/clips");
    let piece = inner
        .iter()
        .find(|c| c["start"].as_i64() == Some(4 * SEC))
        .expect("the piece");
    assert_eq!(int(piece, "/duration"), 2 * SEC);
    assert!(inner.iter().any(|c| c["start"].as_i64() == Some(6 * SEC)));
}
