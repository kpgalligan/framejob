//! `reframe_clip` (road map "creator-jobs" VR2a2, spec §11 VR-24…VR-26),
//! through the FFI: the path written as base and actions, `center`, `fit`
//! and `keep`, the backdrop, the ids, every error and refusal in order, the
//! identity, a scope and the strict `subjects` reader.
//!
//! The fixture: a 1080 × 1920 canvas at 30 fps, a 1920 × 1080 video media
//! 20 s long, tracks 5 (back), 6 and 7 (front), clip 10 on track 6 from 0 for
//! 10 s at scale 1, x = y = 0. Every offset is measured from the canvas
//! centre, so with zoom 1 the window is 607.5 × 1080 source px at k = 16/9
//! and a face at x px of the picture puts the base at `x′ = K·(960 − x)`
//! (clamped so the window stays on the picture); `fit` is scale 0.5625 at
//! the centre. Faces are 0.2 × 0.14 of the picture (384 px wide), so a
//! 100 px step stays one track; samples every 100 ms. `FRAMING_TUNING`
//! (0.15, 0.12, 0.8): a dead zone of 91.125 px, 486 px a second.

mod common;

use framejob_core::edit_reframe::no_subjects;
use serde_json::{json, Value};

use common::{array, by_id, num, Handle, Outcome};

const SEC: i64 = 600_000;
const K: f64 = 1920.0 / 1080.0;

fn project(extra_clips: Vec<Value>, clip: Value) -> Handle {
    let mut c = json!({"id": 10, "track": 6, "start": 0, "duration": 10 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0},
                       "video": {}, "audio": {}});
    for (k, v) in clip.as_object().unwrap() {
        c[k] = v.clone();
    }
    let mut clips = vec![c];
    clips.extend(extra_clips);
    Handle::from_value(&json!({
        "canvas": {"width": 1080, "height": 1920, "fps": [30, 1]},
        "media": [
            {"id": 1, "path": "/m.mov", "kind": "video", "duration": 20 * SEC,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
             "has_audio": true},
            {"id": 2, "path": "/a.m4a", "kind": "audio", "duration": 20 * SEC,
             "has_audio": true}
        ],
        "tracks": [{"id": 5}, {"id": 6}, {"id": 7}],
        "clips": clips,
        "nests": [
            {"id": 50, "name": "Nest", "width": 1920, "height": 1080,
             "tracks": [{"id": 51}],
             "clips": [{"id": 52, "track": 51, "start": 0, "duration": 3 * SEC,
                        "source": {"kind": "media", "media": 1, "in": 0}, "video": {}}]}
        ],
        "next_id": 100
    }))
}

fn plain() -> Handle {
    project(vec![], json!({}))
}

/// A face box centred at x px of the picture, y 432 px.
fn face(x: f64) -> Value {
    json!({"x": x / 1920.0 - 0.1, "y": 0.33, "w": 0.2, "h": 0.14, "c": 0.9})
}

/// `subjects` with samples every 100 ms over [0, to] s of the media.
fn subjects(to: f64, faces: impl Fn(f64) -> Vec<Value>) -> Value {
    let samples: Vec<Value> = (0..=(to * 10.0).round() as i64)
        .map(|n| json!({"t": n * 60_000, "faces": faces(n as f64 / 10.0)}))
        .collect();
    json!({"samples": samples, "shots": []})
}

fn reframe(args: Value) -> Value {
    let mut op = json!({"op": "reframe_clip", "clip": 10});
    for (k, v) in args.as_object().unwrap() {
        op[k] = v.clone();
    }
    op
}

fn clip(h: &Handle, id: u64) -> Value {
    by_id(&h.value(), "/clips", id).clone()
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-6
}

/// The clip's base (scale, x, y).
fn base(c: &Value) -> (f64, f64, f64) {
    (
        num(c, "/video/scale"),
        num(c, "/video/x"),
        num(c, "/video/y"),
    )
}

fn assert_base(c: &Value, want: (f64, f64, f64)) {
    let got = base(c);
    assert!(
        close(got.0, want.0) && close(got.1, want.1) && close(got.2, want.2),
        "base {got:?}, want {want:?}"
    );
}

#[test]
fn the_no_subjects_sentence_is_the_one_the_tool_matches() {
    // `AgentServer+Framing.swift`'s `FramingWant.noSubjects` builds the same
    // text (spec §11 VR-28).
    assert_eq!(
        no_subjects(12),
        "clip 12 has no subjects to follow; analyze it first"
    );
}

#[test]
fn a_still_subject_gets_a_base_and_no_action() {
    let h = plain().apply(&reframe(
        json!({"follow": "face", "subjects": subjects(10.0, |_| vec![face(600.0)])}),
    ));
    let c = clip(&h, 10);
    assert_base(&c, (K, K * 360.0, 0.0));
    assert!(array(&c, "/actions").is_empty());
}

#[test]
fn a_pans_actions_are_the_composed_path() {
    // 600 → 700 at 2 s: past the 91.125 px dead zone, 100/486 s under the
    // 0.4 s floor: one action [1 200 000, 1 440 000), ease_in_out.
    let s = subjects(10.0, |t| vec![face(if t < 2.0 { 600.0 } else { 700.0 })]);
    let check = |h: &Handle| {
        let c = clip(h, 10);
        assert_base(&c, (K, K * 360.0, 0.0));
        let actions = array(&c, "/actions");
        assert_eq!(actions.len(), 1, "{actions:?}");
        let a = &actions[0];
        assert_eq!(
            (
                a["id"].as_i64(),
                a["start"].as_i64(),
                a["duration"].as_i64()
            ),
            (Some(100), Some(1_200_000), Some(240_000))
        );
        assert_eq!(a["curve"], "ease_in_out");
        let end = &a["end"]["video"];
        assert_eq!(end.as_object().unwrap().len(), 3, "{end}");
        assert!(close(num(end, "/scale"), K) && close(num(end, "/x"), K * 260.0));
        assert!(close(num(end, "/y"), 0.0));
    };
    check(&plain().apply(&reframe(
        json!({"follow": "subject", "subjects": s.clone()}),
    )));
    // Composed into the clip's own placement: a base at scale 2, x 100,
    // y −50 frames to the same numbers, since F is measured from it.
    let moved = project(
        vec![],
        json!({"video": {"scale": 2.0, "x": 100.0, "y": -50.0}}),
    );
    check(&moved.apply(&reframe(json!({"follow": "subject", "subjects": s}))));
}

#[test]
fn center_fit_and_keep() {
    let h = plain().apply(&reframe(json!({"follow": "center", "zoom": 2.0})));
    assert_base(&clip(&h, 10), (2.0 * K, 0.0, 0.0));
    let h = plain().apply(&reframe(json!({"follow": "fit", "zoom": 3.0})));
    assert_base(&clip(&h, 10), (0.5625, 0.0, 0.0));
    assert!(array(&clip(&h, 10), "/actions").is_empty());
    // keep: x by 1080/1920, y by 1920/1080, scale by the smaller.
    let placed = project(vec![], json!({"video": {"x": 100.0, "y": 50.0}}));
    let h = placed.apply(&reframe(
        json!({"follow": "keep", "from_width": 1920, "from_height": 1080, "zoom": 4.0}),
    ));
    assert_base(&clip(&h, 10), (0.5625, 56.25, 50.0 * 1920.0 / 1080.0));
}

#[test]
fn center_and_fit_on_a_nest_clip() {
    let nest = json!({"id": 40, "track": 7, "start": 0, "duration": 3 * SEC,
                      "source": {"kind": "nest", "project": 50}, "video": {}});
    let h = project(vec![nest], json!({}));
    let fit = h.apply(&json!({"op": "reframe_clip", "clip": 40, "follow": "fit"}));
    assert_base(&clip(&fit, 40), (0.5625, 0.0, 0.0));
    let centre = h.apply(&json!({"op": "reframe_clip", "clip": 40, "follow": "center"}));
    assert_base(&clip(&centre, 40), (K, 0.0, 0.0));
}

#[test]
fn a_double_speed_a_reversed_and_a_cropped_clip() {
    // ×2: media 4 s is clip 2 s, so the same action as the pan's.
    let s = subjects(10.0, |t| vec![face(if t < 4.0 { 600.0 } else { 700.0 })]);
    let fast = project(vec![], json!({"speed": 2.0, "duration": 5 * SEC}));
    let fast_clip = clip(
        &fast.apply(&reframe(json!({"follow": "face", "subjects": s}))),
        10,
    );
    let a = &array(&fast_clip, "/actions")[0];
    assert_eq!(
        (a["start"].as_i64(), a["duration"].as_i64()),
        (Some(1_200_000), Some(240_000))
    );
    // Reversed over 20 s of media: clip t shows forward 20 − t; 700 up to
    // forward 12 s is clip 8 s on.
    let s = subjects(20.0, |t| vec![face(if t <= 12.0 { 700.0 } else { 600.0 })]);
    let back = project(
        vec![],
        json!({"source": {"kind": "media", "media": 1, "in": 0, "reversed": true}}),
    );
    let c = clip(
        &back.apply(&reframe(json!({"follow": "face", "subjects": s}))),
        10,
    );
    assert_base(&c, (K, K * 360.0, 0.0));
    let a = &array(&c, "/actions")[0];
    assert_eq!(
        (a["start"].as_i64(), a["duration"].as_i64()),
        (Some(4_800_000), Some(240_000))
    );
    // 400 px cropped off the left: the face at 500 stays, the window's left
    // edge no further left than the crop: its centre at 703.75 px.
    let cropped = project(
        vec![],
        json!({"video": {"crop": {"l": 400.0, "t": 0.0, "r": 0.0, "b": 0.0}}}),
    );
    let h = cropped.apply(&reframe(
        json!({"follow": "face", "subjects": subjects(10.0, |_| vec![face(500.0)])}),
    ));
    assert_base(&clip(&h, 10), (K, K * (960.0 - 703.75), 0.0));
}

#[test]
fn a_slide_left_arrival_is_kept() {
    let motion = json!({"in": {"kind": "slide_left", "duration": 300_000}});
    let h = project(vec![], json!({"video": {"motion": motion}}));
    let c = clip(
        &h.apply(&reframe(json!({"follow": "center", "zoom": 2.0}))),
        10,
    );
    assert_eq!(c["video"]["motion"]["in"]["kind"], "slide_left");
    assert_base(&c, (2.0 * K, 0.0, 0.0));
}

/// A face at 600 to 1.9 s, then gone until 5 s: held to 3 s, eased to fit
/// by 3.8 s (action 100), back from 5 s and returned at 5.6 s (action 101,
/// 360 px from the centre, 0.7407 s, ending on frame 190).
fn exits() -> Value {
    subjects(10.0, |t| {
        if !(1.95..4.95).contains(&t) {
            vec![face(600.0)]
        } else {
            vec![]
        }
    })
}

#[test]
fn an_exit_eases_to_fit_and_back_with_a_backdrop_on_the_named_track() {
    let h = plain().apply(&reframe(
        json!({"follow": "face", "subjects": exits(), "backdrop": 5}),
    ));
    let c = clip(&h, 10);
    let actions = array(&c, "/actions");
    let spans: Vec<(i64, i64, i64)> = actions
        .iter()
        .map(|a| {
            (
                a["id"].as_i64().unwrap(),
                a["start"].as_i64().unwrap(),
                a["duration"].as_i64().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        spans,
        vec![(100, 1_800_000, 480_000), (101, 3_360_000, 440_000)]
    );
    assert!(close(num(&actions[0], "/end/video/scale"), 0.5625));
    let v = h.value();
    let copies: Vec<&Value> = array(&v, "/clips")
        .iter()
        .filter(|c| c["track"] == 5)
        .collect();
    assert_eq!(copies.len(), 1);
    let copy = copies[0];
    assert_eq!(copy["id"], 102);
    assert_eq!(copy["name"], "Blurred Background");
    assert_eq!(
        (copy["start"].as_i64(), copy["duration"].as_i64()),
        (Some(0), Some(10 * SEC))
    );
    assert_eq!(array(&h.value(), "/tracks").len(), 3);
}

#[test]
fn a_busy_or_locked_backdrop_track_gets_a_new_back_most_track_and_the_ids_keep_order() {
    let busy = json!({"id": 30, "track": 5, "start": 9 * SEC, "duration": 2 * SEC,
                      "source": {"kind": "media", "media": 1, "in": 0}, "video": {}});
    let touching = json!({"id": 31, "track": 5, "start": 10 * SEC, "duration": SEC,
                          "source": {"kind": "media", "media": 1, "in": 0}, "video": {}});
    for (name, h) in [
        ("busy", project(vec![busy], json!({}))),
        ("locked", {
            let p = plain();
            p.apply(&json!({"op": "set_track", "track": 5, "locked": true}))
        }),
    ] {
        let h = h.apply(&reframe(
            json!({"follow": "face", "subjects": exits(), "backdrop": 5}),
        ));
        let v = h.value();
        let tracks = array(&v, "/tracks");
        assert_eq!(tracks.len(), 4, "{name}");
        // Actions 100 and 101, then the track, then the copy.
        assert_eq!(tracks[0]["id"], 102, "{name}");
        let copy = by_id(&v, "/clips", 103);
        assert_eq!(copy["track"], 102, "{name}");
    }
    // A clip only touching the span leaves the track free.
    let h =
        project(vec![touching], json!({})).apply(&reframe(json!({"follow": "fit", "backdrop": 5})));
    assert_eq!(by_id(&h.value(), "/clips", 100)["track"], 5);
    // No backdrop, no copy; a path that never shows fit makes none either.
    let h = plain().apply(&reframe(json!({"follow": "face", "subjects": exits()})));
    assert_eq!(array(&h.value(), "/clips").len(), 1);
    let h = plain().apply(&reframe(
        json!({"follow": "center", "zoom": 2.0, "backdrop": 5}),
    ));
    assert_eq!(array(&h.value(), "/clips").len(), 1);
}

#[test]
fn every_error_in_order() {
    let p = plain();
    assert_eq!(
        p.errors(&json!({"op": "reframe_clip", "clip": 99, "follow": "fit", "zoom": 9.0})),
        "no clip with id 99"
    );
    assert_eq!(
        p.errors(&reframe(
            json!({"follow": "fit", "zoom": 0.5, "from_width": 0})
        )),
        "zoom must be between 1 and 4 times fill, not 0.5"
    );
    assert_eq!(
        p.errors(&reframe(json!({"follow": "fit", "zoom": 4.5}))),
        "zoom must be between 1 and 4 times fill, not 4.5"
    );
    assert_eq!(
        p.errors(&reframe(
            json!({"follow": "keep", "from_width": 0, "backdrop": 77})
        )),
        "from_width must be greater than 0, not 0"
    );
    assert_eq!(
        p.errors(&reframe(json!({"follow": "keep", "from_height": 0}))),
        "from_height must be greater than 0, not 0"
    );
    assert_eq!(
        p.errors(&reframe(json!({"follow": "fit", "backdrop": 77}))),
        "no track with id 77"
    );
    let unknown = p.errors(&reframe(json!({"follow": "nearest"})));
    assert!(unknown.contains("unknown variant `nearest`"), "{unknown}");
}

#[test]
fn the_strict_subjects_reader() {
    let p = plain();
    let list = p.errors(&reframe(json!({"follow": "face", "subjects": [1]})));
    assert!(list.contains("expected an object, not"), "{list}");
    let sample = p.errors(&reframe(json!({"follow": "face",
        "subjects": {"samples": [[0]], "shots": []}})));
    assert!(
        sample.contains("bad value at \"subjects.samples[0]\": expected an object"),
        "{sample}"
    );
    let typed = p.errors(&reframe(json!({"follow": "face",
        "subjects": {"samples": [{"t": 0, "faces": [{"x": 0.1, "y": 0.1, "w": 0.1, "h": "big",
                                                    "c": 1.0}]}], "shots": []}})));
    assert!(
        typed.contains("bad value at \"subjects.samples[0].faces[0].h\""),
        "{typed}"
    );
    let stray = p.errors(&reframe(json!({"follow": "face",
        "subjects": {"samples": [{"t": 0, "hands": []}], "shots": []}})));
    assert!(
        stray.contains("subjects.samples[0]") && stray.contains("hands"),
        "{stray}"
    );
    let missing = p.errors(&reframe(
        json!({"follow": "face", "subjects": {"samples": []}}),
    ));
    assert!(missing.contains("shots"), "{missing}");
}

#[test]
fn every_refusal_in_order() {
    let id = |n: u32| n;
    let text = json!({"id": 20, "track": 7, "start": 0, "duration": SEC,
                      "source": {"kind": "text"}, "video": {}, "text": {"content": "t"}});
    let sound = json!({"id": 21, "track": 7, "start": SEC, "duration": SEC,
                       "source": {"kind": "media", "media": 2, "in": 0}, "audio": {}});
    let nest = json!({"id": 22, "track": 7, "start": 2 * SEC, "duration": SEC,
                      "source": {"kind": "nest", "project": 50}, "video": {},
                      "actions": [{"id": 90, "start": 0, "duration": SEC / 2,
                                   "end": {"video": {"scale": 2.0}}}]});
    let still = json!({"id": 23, "track": 7, "start": 3 * SEC, "duration": SEC,
                       "source": {"kind": "still", "media": 1, "at": 0}, "video": {}});
    let h = project(vec![text, sound, nest, still], json!({}));
    let on = |clip: u32, args: Value| {
        let mut op = reframe(args);
        op["clip"] = json!(clip);
        op
    };
    let following = || json!({"follow": "face", "subjects": subjects(1.0, |_| vec![face(600.0)])});
    // (1) a described clip, but keep reads it.
    h.refuses_with(
        &on(id(20), json!({"follow": "fit"})),
        "clip 20 is a text clip, with no picture to frame; only keep reframes it",
    );
    assert!(matches!(
        h.try_apply(&on(20, json!({"follow": "keep", "from_width": 2160}))),
        Ok(Outcome::Applied(_))
    ));
    // (2) no picture, then a crop that leaves none.
    h.refuses_with(
        &on(21, json!({"follow": "keep"})),
        "clip 21's media has no picture to frame",
    );
    let cropped = project(
        vec![],
        json!({"video": {"crop": {"l": 1000.0, "t": 0.0, "r": 920.0,
                                                           "b": 0.0}}}),
    );
    cropped.refuses_with(
        &reframe(json!({"follow": "fit"})),
        "clip 10's crop or scale leaves no picture to frame",
    );
    // (3) a nest with a following kind, before its actions (7).
    h.refuses_with(
        &on(22, following()),
        "clip 22 shows a nest, which has no subjects to follow; frame it with center, fit or keep",
    );
    // (4) a still.
    h.refuses_with(
        &on(23, following()),
        "clip 23 shows a still picture, which has no subjects to follow; frame it with center, \
         fit or keep",
    );
    // (5) a matte track's clip, and the clip a matte cuts; keep reads both.
    let matte = plain().apply(&json!({"op": "set_track", "track": 6, "matte": "alpha"}));
    matte.refuses_with(
        &reframe(json!({"follow": "fit"})),
        "clip 10 is on a matte track, which framing would move; only keep reframes it",
    );
    let cut = plain().apply(&json!({"op": "set_track", "track": 7, "matte": "alpha"}));
    cut.refuses_with(
        &reframe(json!({"follow": "center", "zoom": 2.0})),
        "clip 10 is cut by the matte on track 7, which framing would move it out of; only keep \
         reframes it",
    );
    assert!(matches!(
        cut.try_apply(&reframe(json!({"follow": "keep", "from_width": 2160}))),
        Ok(Outcome::Applied(_))
    ));
    // (6) turned, before an action (7): the base, an action end, a spin.
    let turned = project(
        vec![],
        json!({"video": {"rotation": 90.0},
        "actions": [{"id": 91, "start": 0, "duration": SEC, "end": {"audio": {"volume": 0.5}}}]}),
    );
    turned.refuses_with(
        &reframe(json!({"follow": "fit"})),
        "clip 10 is turned 90°, and framing works on an upright picture; only keep reframes it",
    );
    let turning = project(
        vec![],
        json!({"actions": [{"id": 91, "start": 0, "duration": SEC,
                                                     "end": {"video": {"rotation": 45.0}}}]}),
    );
    turning.refuses_with(
        &reframe(json!({"follow": "fit"})),
        "clip 10's action 91 turns it, and framing works on an upright picture; only keep \
         reframes it",
    );
    let spin = project(
        vec![],
        json!({"video": {"motion": {"during": {"kind": "spin",
                                                                       "amount": 0.5,
                                                                       "period": SEC}}}}),
    );
    spin.refuses_with(
        &reframe(json!({"follow": "fit"})),
        "clip 10 spins in its motion, and framing works on an upright picture; only keep \
         reframes it",
    );
    // (7) removed by VR-27: a clip with actions is framed by composing
    // into them, whatever the follow and whatever its ends name.
    let volume = project(
        vec![],
        json!({"actions": [{"id": 91, "start": 0, "duration": SEC,
                                                    "end": {"audio": {"volume": 0.5}}}]}),
    );
    assert!(matches!(
        volume.try_apply(&reframe(json!({"follow": "center"}))),
        Ok(Outcome::Applied(_))
    ));
    assert!(matches!(
        volume.try_apply(&reframe(json!({"follow": "keep", "from_width": 2160}))),
        Ok(Outcome::Applied(_))
    ));
    let zoomed = project(
        vec![],
        json!({"actions": [{"id": 91, "start": 0, "duration": SEC,
                                                    "end": {"video": {"x": 10.0}}}]}),
    );
    assert!(matches!(
        zoomed.try_apply(&reframe(json!({"follow": "keep", "from_width": 2160}))),
        Ok(Outcome::Applied(_))
    ));
    // (8) bad subjects, before the backdrop (9).
    let p = plain();
    let many = json!({"samples": [{"t": 0, "faces": (0..9).map(|_| face(600.0)).collect::<Vec<_>>()}],
                      "shots": []});
    p.refuses_with(
        &reframe(json!({"follow": "face", "subjects": many, "backdrop": 7})),
        "subjects sample 0 holds 9 faces, more than 8",
    );
    let order = json!({"samples": [{"t": 60_000}, {"t": 60_000}], "shots": []});
    p.refuses_with(
        &reframe(json!({"follow": "face", "subjects": order})),
        "subjects sample 1 is at 60000, not after the one before it (60000); sample times must \
         be strictly increasing",
    );
    let outside = json!({"samples": [{"t": 0, "people": [{"x": 1.5, "y": 0.1, "w": 0.1,
                                                         "h": 0.1, "c": 0.9}]}], "shots": []});
    p.refuses_with(
        &reframe(json!({"follow": "person", "subjects": outside})),
        "subjects sample 0's people[0].x is 1.5, outside 0…1",
    );
    let flat = json!({"samples": [{"t": 0, "salient": [{"x": 0.1, "y": 0.1, "w": 0.0,
                                                       "h": 0.1, "c": 0.9}]}], "shots": []});
    p.refuses_with(
        &reframe(json!({"follow": "salient", "subjects": flat})),
        "subjects sample 0's salient[0].w is 0; a box's size must be greater than 0",
    );
    // A following kind's subjects are read; `fit`'s are not.
    assert!(matches!(
        p.try_apply(&reframe(json!({"follow": "fit", "subjects": order_free()}))),
        Ok(Outcome::Applied(_))
    ));
    // (9) only when a copy would be made: a nest, a track not behind.
    let nested = project(
        vec![
            json!({"id": 40, "track": 7, "start": 0, "duration": 3 * SEC,
                                     "source": {"kind": "nest", "project": 50}, "video": {}}),
        ],
        json!({}),
    );
    nested.refuses_with(
        &json!({"op": "reframe_clip", "clip": 40, "follow": "fit", "backdrop": 5}),
        "clip 40 shows a nest, whose own filters the flattening drops, so a blurred copy of it \
         would come out sharp",
    );
    p.refuses_with(
        &reframe(json!({"follow": "fit", "backdrop": 7})),
        "track 7 is not behind clip 10's track, so a backdrop there would cover it",
    );
    p.refuses_with(
        &reframe(json!({"follow": "fit", "backdrop": 6})),
        "track 6 is not behind clip 10's track, so a backdrop there would cover it",
    );
    assert!(matches!(
        p.try_apply(&reframe(
            json!({"follow": "center", "zoom": 2.0, "backdrop": 7})
        )),
        Ok(Outcome::Applied(_))
    ));
    // (10) last: no subjects, or none in the played window.
    p.refuses_with(&reframe(json!({"follow": "subject"})), &no_subjects(10));
    let late = json!({"samples": [{"t": 15 * SEC, "faces": [face(600.0)]}], "shots": []});
    p.refuses_with(
        &reframe(json!({"follow": "face", "subjects": late})),
        &no_subjects(10),
    );
    // …after every other refusal: a turned clip with no subjects is turned.
    turned.refuses_with(
        &reframe(json!({"follow": "face"})),
        "clip 10 is turned 90°, and framing works on an upright picture; only keep reframes it",
    );
}

/// A `subjects` a following kind would refuse (times not increasing).
fn order_free() -> Value {
    json!({"samples": [{"t": 60_000}, {"t": 0}], "shots": []})
}

#[test]
fn an_unchanged_clip_is_an_identity() {
    // Already at the centre window at zoom 1 (K, 0, 0); keep from the
    // canvas itself.
    let framed = project(vec![], json!({"video": {"scale": K}}));
    assert!(matches!(
        framed.try_apply(&reframe(json!({"follow": "center"}))),
        Ok(Outcome::Identity)
    ));
    assert!(matches!(
        plain().try_apply(&reframe(json!({"follow": "keep"}))),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn inside_a_scope_the_nests_canvas_is_the_canvas() {
    // Nest 50 is 1920 × 1080 and its clip 1920 × 1080: fit is scale 1, an
    // identity; center at zoom 2 doubles it inside the nest.
    let p = plain();
    assert!(matches!(
        p.try_apply(&json!({"op": "reframe_clip", "clip": 52, "follow": "fit", "scope": 50})),
        Ok(Outcome::Identity)
    ));
    let h = p.apply(
        &json!({"op": "reframe_clip", "clip": 52, "follow": "center", "zoom": 2.0,
                            "scope": 50}),
    );
    let inner = by_id(&h.value(), "/nests", 50).clone();
    let c = by_id(&inner, "/clips", 52);
    assert_base(c, (2.0, 0.0, 0.0));
}
