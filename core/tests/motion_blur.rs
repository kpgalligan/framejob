//! Motion blur in the model and the recipe (format 42, spec §11 CU-111,
//! CU-113, CU-114), through the FFI.
//!
//! Every sample is checked against a second recipe: the same project with
//! `motion_blur` removed, asked at the sample's own time, the times written
//! out here from CU-114's formula. Pinned: the centred samples at 30 and at
//! 30000/1001 fps; the clamp at the clip's first tick; `blur` null on an
//! unmoving layer, on each sharp arm (a cross dissolve's pair, a nested
//! pair's routed dissolve, a track matte's member and its cut layer, a
//! shadow, an adjustment clip, Behind Subject's copy and cut layer) and on
//! the burn-in; a nested layer following its moving nest's fold and
//! `clip_rect`; an end animating the shutter from 0 and an end of 2 clamped
//! to 1; the sentences; `{motion_blur: 0}` removing the key; a blurred
//! background copy without it; and the cursor's `shutter`.

mod common;

use serde_json::{json, Value};

use common::{array, int, Handle};
use framejob_core::motion_blur::MOTION_BLUR_SAMPLES;

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
/// Clip 11's start: one second in, so a sample before it is clamped to it.
const START: i64 = SEC;
const N: usize = MOTION_BLUR_SAMPLES;

fn media(cursor: bool) -> Value {
    let mut media = json!({
        "id": 1, "path": "/fixtures/screen.mov", "kind": "video", "duration": 600 * SEC,
        "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true
    });
    if cursor {
        media["cursor"] = json!({ "path": "/fixtures/screen.fjcursor", "in_picture": false });
    }
    media
}

/// The spike's zoom: over [0, 1 s) of clip time, eased in and out to 2×.
fn zoom() -> Value {
    json!([{ "id": 21, "start": 0, "duration": SEC, "curve": "ease_in_out",
             "end": { "video": { "scale": 2.0 } } }])
}

/// Media clip `id` of media 1 on `track` at `start` for 2 s, `video` its
/// video group and `actions` its actions.
/// Each action's id moves by 10 per clip id past 11, so two clips' actions
/// never share one.
fn clip(id: u32, track: u32, start: i64, video: Value, mut actions: Value) -> Value {
    for action in actions.as_array_mut().expect("actions") {
        action["id"] = json!(int(action, "/id") + (i64::from(id) - 11) * 10);
    }
    json!({ "id": id, "track": track, "start": start, "duration": 2 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "speed": 1.0, "video": video, "audio": {}, "actions": actions })
}

fn blurred() -> Value {
    json!({ "motion_blur": 0.5 })
}

fn project_at(fps: [u32; 2], tracks: Value, clips: Value, nests: Value, cursor: bool) -> Handle {
    Handle::from_value(&json!({
        "canvas": { "width": 1920, "height": 1080, "fps": fps },
        "media": [media(cursor)],
        "tracks": tracks,
        "clips": clips,
        "nests": nests,
        "next_id": 100
    }))
}

fn project(tracks: Value, clips: Value) -> Handle {
    project_at([30, 1], tracks, clips, json!([]), false)
}

fn one_track() -> Value {
    json!([{ "id": 2, "name": "Track 1" }])
}

/// The zooming, blurred clip 11 alone.
fn zooming() -> Handle {
    project(one_track(), json!([clip(11, 2, START, blurred(), zoom())]))
}

/// The same project with every clip's `motion_blur` removed: the oracle.
fn without_blur(handle: &Handle) -> Handle {
    let mut value = handle.value();
    let strip = |clips: &mut Value| {
        for clip in clips.as_array_mut().expect("clips") {
            if let Some(video) = clip["video"].as_object_mut() {
                video.remove("motion_blur");
            }
        }
    };
    strip(&mut value["clips"]);
    if let Some(nests) = value["nests"].as_array_mut() {
        for nest in nests {
            strip(&mut nest["clips"]);
        }
    }
    Handle::from_value(&value)
}

/// Every layer of `clip` at `t`, in order.
fn layers_of(handle: &Handle, t: i64, clip: i64) -> Vec<Value> {
    let recipe = handle.recipe(t);
    array(&recipe, "/layers")
        .iter()
        .filter(|l| int(l, "/clip") == clip)
        .cloned()
        .collect()
}

fn layer(handle: &Handle, t: i64, clip: i64) -> Value {
    layers_of(handle, t, clip)
        .into_iter()
        .next()
        .unwrap_or_else(|| panic!("no layer of clip {clip} at {t}"))
}

/// A layer's placement as a sample publishes it.
fn placed(layer: &Value) -> Value {
    json!({ "x": layer["x"], "y": layer["y"], "scale": layer["scale"],
            "rotation": layer["rotation"], "clip_rect": layer["clip_rect"] })
}

/// CU-114's offsets for a shutter of `s` frames of `frame` ticks.
fn offsets(frame: f64, s: f64) -> Vec<i64> {
    let n = N as f64;
    (0..N)
        .map(|k| ((2.0 * k as f64 + 1.0 - n) / (2.0 * n) * s * frame).round() as i64)
        .collect()
}

/// `blur.samples` of clip `id` at `t` against the oracle's layer at each of
/// `times`.
fn assert_samples(handle: &Handle, t: i64, id: i64, times: &[i64]) {
    let oracle = without_blur(handle);
    let blur = &layer(handle, t, id)["blur"];
    let samples = array(blur, "/samples");
    assert_eq!(samples.len(), N, "{blur}");
    for (k, (sample, at)) in samples.iter().zip(times).enumerate() {
        assert_eq!(
            sample,
            &placed(&layer(&oracle, *at, id)),
            "sample {k} at {at}"
        );
    }
}

// ---- the samples -----------------------------------------------------------

#[test]
fn the_samples_are_the_placements_at_the_centred_sub_frame_times() {
    let handle = zooming();
    let t = START + SEC / 2;
    assert_eq!(layer(&handle, t, 11)["blur"]["shutter"], json!(0.5));
    let times: Vec<i64> = offsets(20_000.0, 0.5).iter().map(|o| t + o).collect();
    assert_eq!(times[0], t - 4_688);
    assert_eq!(times[N - 1], t + 4_688);
    assert_samples(&handle, t, 11, &times);
}

#[test]
fn at_30000_over_1001_the_frame_is_20020_ticks() {
    let handle = project_at(
        [30000, 1001],
        one_track(),
        json!([clip(11, 2, START, blurred(), zoom())]),
        json!([]),
        false,
    );
    let t = START + SEC / 2;
    let times: Vec<i64> = offsets(20_020.0, 0.5).iter().map(|o| t + o).collect();
    assert_samples(&handle, t, 11, &times);
}

#[test]
fn at_the_clips_first_tick_the_early_samples_are_its_start() {
    let handle = zooming();
    let times: Vec<i64> = offsets(20_000.0, 0.5)
        .iter()
        .map(|o| (START + o).max(START))
        .collect();
    assert_eq!(times[0], START);
    assert_eq!(times[N / 2 - 1], START);
    assert!(times[N / 2] > START);
    assert_samples(&handle, START, 11, &times);
}

#[test]
fn an_unmoving_layer_has_no_blur() {
    let handle = project(
        one_track(),
        json!([clip(11, 2, START, blurred(), json!([]))]),
    );
    assert_eq!(layer(&handle, START + SEC / 2, 11)["blur"], Value::Null);
    // After the zoom has finished, the zooming clip stands still too.
    assert_eq!(
        layer(&zooming(), START + 3 * SEC / 2, 11)["blur"],
        Value::Null
    );
}

// ---- what blur skips (CU-111) ------------------------------------------------

#[test]
fn a_cross_dissolves_pair_is_sharp() {
    let mut incoming = clip(12, 2, START + 2 * SEC / 5, blurred(), zoom());
    incoming["transition_in"] = json!({ "kind": "cross_dissolve", "curve": "linear" });
    let handle = project(
        one_track(),
        json!([clip(11, 2, START, blurred(), zoom()), incoming]),
    );
    let t = START + SEC / 2;
    for id in [11, 12] {
        let layer = layer(&handle, t, id);
        assert!(!layer["transition"].is_null(), "{layer}");
        assert_eq!(layer["blur"], Value::Null, "clip {id}");
    }
    // Before the overlap clip 11 blurs.
    assert!(!layer(&handle, START + SEC / 5, 11)["blur"].is_null());
}

#[test]
fn a_nested_pairs_routed_dissolve_is_sharp() {
    let text = |id: u32, start: i64, duration: i64| {
        json!({ "id": id, "track": 5, "start": start, "duration": duration,
                "source": { "kind": "text" }, "text": { "content": "A" },
                "video": { "motion_blur": 0.5 },
                "actions": [{ "id": id + 20, "start": 0, "duration": SEC / 2,
                              "curve": "linear", "end": { "video": { "x": 200.0 } } }] })
    };
    let mut second = text(7, SEC, SEC);
    second["transition_in"] = json!({ "kind": "cross_dissolve", "curve": "linear" });
    let nest = json!({ "id": 4, "name": "Nest 4", "width": 1920, "height": 1080,
                       "tracks": [{ "id": 5, "name": "Track 5" }],
                       "clips": [text(6, 0, 3 * SEC / 2), second] });
    let handle = project_at(
        [30, 1],
        one_track(),
        json!([{ "id": 3, "track": 2, "start": 0, "duration": 2 * SEC,
                 "source": { "kind": "nest", "project": 4 }, "video": {} }]),
        json!([nest]),
        false,
    );
    let mid = SEC + SEC / 4;
    let six = layer(&handle, mid, 6);
    assert!(!six["dissolve"].is_null(), "{six}");
    assert_eq!(six["blur"], Value::Null);
    let seven = layer(&handle, SEC + SEC / 10, 7);
    assert!(!seven["dissolve"].is_null(), "{seven}");
    assert_eq!(seven["blur"], Value::Null);
    // Before the overlap clip 6 blurs.
    assert!(!layer(&handle, SEC / 4, 6)["blur"].is_null());
}

#[test]
fn a_track_mattes_member_and_its_cut_layer_are_sharp() {
    let tracks = |matte: bool| {
        let mut front = json!({ "id": 3, "name": "Matte" });
        if matte {
            front["matte"] = json!("luma");
        }
        json!([{ "id": 2, "name": "Target" }, front])
    };
    let clips = json!([
        clip(11, 2, START, blurred(), zoom()),
        clip(12, 3, START, blurred(), zoom())
    ]);
    let t = START + SEC / 2;
    let matted = project(tracks(true), clips.clone());
    for id in [11, 12] {
        let layer = layer(&matted, t, id);
        assert!(!layer["matte"].is_null(), "{layer}");
        assert_eq!(layer["blur"], Value::Null, "clip {id}");
    }
    let plain = project(tracks(false), clips);
    for id in [11, 12] {
        assert!(!layer(&plain, t, id)["blur"].is_null(), "clip {id}");
    }
}

#[test]
fn a_shadowed_layer_is_sharp() {
    let handle = project(
        one_track(),
        json!([clip(
            11,
            2,
            START,
            json!({ "motion_blur": 0.5, "shadow": {} }),
            zoom()
        )]),
    );
    assert_eq!(layer(&handle, START + SEC / 2, 11)["blur"], Value::Null);
}

#[test]
fn an_adjustment_clip_from_a_file_is_sharp() {
    let adjustment = json!({ "id": 12, "track": 3, "start": START, "duration": 2 * SEC,
                             "source": { "kind": "adjustment" }, "video": blurred(),
                             "actions": zoom() });
    let handle = project(
        json!([{ "id": 2, "name": "Track 1" }, { "id": 3, "name": "Track 2" }]),
        json!([clip(11, 2, START, json!({}), json!([])), adjustment]),
    );
    assert_eq!(layer(&handle, START + SEC / 2, 12)["blur"], Value::Null);
}

#[test]
fn behind_subjects_copy_and_cut_layer_are_sharp_and_lose_the_cursors_shutter() {
    let camera = clip(
        11,
        2,
        START,
        json!({ "motion_blur": 0.5, "cutout": {} }),
        zoom(),
    );
    let title = clip(
        12,
        3,
        START,
        json!({ "motion_blur": 0.5, "behind_subject": true }),
        zoom(),
    );
    let handle = project_at(
        [30, 1],
        json!([{ "id": 2, "name": "Camera" }, { "id": 3, "name": "Title" }]),
        json!([camera, title]),
        json!([]),
        true,
    );
    let t = START + SEC / 2;
    let cameras = layers_of(&handle, t, 11);
    assert_eq!(cameras.len(), 2, "the original and its copy");
    let (original, copy) = (&cameras[0], &cameras[1]);
    assert_eq!(copy["cutout"]["subject_copy"], json!(true), "{copy}");
    // The original subject is not matted: it blurs and its cursor has a shutter.
    assert!(!original["blur"].is_null(), "{original}");
    assert!(original["cursor"]["shutter"].is_object(), "{original}");
    let cut = layer(&handle, t, 12);
    assert!(!cut["matte"].is_null(), "{cut}");
    for matted in [copy, &cut] {
        assert_eq!(matted["blur"], Value::Null, "{matted}");
        assert!(matted["cursor"].get("shutter").is_none(), "{matted}");
    }
}

#[test]
fn the_burn_in_has_no_blur() {
    let recipe = zooming().recipe_opts(START + SEC / 2, &json!({ "burn_in_timecode": true }));
    let layers = array(&recipe, "/layers");
    let burn_in = layers.last().expect("the burn-in");
    assert!(burn_in.as_object().expect("a layer").contains_key("blur"));
    assert_eq!(burn_in["blur"], Value::Null);
    assert!(!layers[0]["blur"].is_null());
}

// ---- a nest's fold -----------------------------------------------------------

#[test]
fn a_nested_layer_follows_its_moving_nests_fold_and_clip_rect() {
    let inner = json!({ "id": 6, "track": 5, "start": 0, "duration": 2 * SEC,
                        "source": { "kind": "media", "media": 1, "in": 0 }, "speed": 1.0,
                        "video": { "motion_blur": 0.5, "scale": 0.5 }, "audio": {} });
    let nest = json!({ "id": 4, "name": "Nest 4", "width": 1920, "height": 1080,
                       "tracks": [{ "id": 5, "name": "Track 5" }], "clips": [inner] });
    let nest_clip = json!({
        "id": 3, "track": 2, "start": START, "duration": 2 * SEC,
        "source": { "kind": "nest", "project": 4 }, "video": {},
        "actions": [{ "id": 21, "start": 0, "duration": SEC, "curve": "ease_in_out",
                      "end": { "video": { "x": 300.0, "scale": 0.75, "rotation": 10.0 } } }]
    });
    let handle = project_at(
        [30, 1],
        one_track(),
        json!([nest_clip]),
        json!([nest]),
        false,
    );
    let t = START + SEC / 2;
    assert!(!layer(&handle, t, 6)["clip_rect"].is_null());
    let times: Vec<i64> = offsets(20_000.0, 0.5).iter().map(|o| t + o).collect();
    assert_samples(&handle, t, 6, &times);
}

// ---- the key's value ----------------------------------------------------------

#[test]
fn an_end_animates_the_shutter_from_zero_and_an_end_of_two_is_one() {
    let animated = json!([{ "id": 21, "start": 0, "duration": SEC, "curve": "linear",
                            "end": { "video": { "motion_blur": 1.0, "scale": 2.0 } } }]);
    let handle = project(
        one_track(),
        json!([clip(11, 2, START, json!({}), animated)]),
    );
    assert_eq!(
        layer(&handle, START + SEC / 2, 11)["blur"]["shutter"],
        json!(0.5)
    );
    let two = json!([
        { "id": 21, "start": 0, "duration": SEC / 2, "curve": "linear",
          "end": { "video": { "motion_blur": 1.0 } } },
        { "id": 22, "start": SEC / 2, "duration": SEC, "curve": "linear",
          "end": { "video": { "scale": 2.0 } } }
    ]);
    let handle = project(one_track(), json!([clip(11, 2, START, json!({}), two)]))
        .apply(&json!({ "op": "set_action_end", "clip": 11, "action": 21,
                        "patch": { "video": { "motion_blur": 2.0 } } }));
    assert_eq!(
        layer(&handle, START + SEC, 11)["blur"]["shutter"],
        json!(1.0)
    );
}

#[test]
fn the_sentences_and_zero_removing_the_key() {
    let handle = project(
        json!([{ "id": 2, "name": "Track 1" }, { "id": 3, "name": "Track 2" },
               { "id": 4, "name": "Track 3" }]),
        json!([
            clip(11, 2, 0, json!({}), json!([])),
            clip(13, 3, 0, json!({}), json!([]))
        ]),
    )
    .apply(&json!({ "op": "add_adjustment_clip", "track": 4, "at": 0 }));
    let set = |id: i64, v: f64| {
        json!({ "op": "set_video", "clips": [id],
                                        "patch": { "motion_blur": v } })
    };
    assert_eq!(
        handle.errors(&set(11, 1.5)),
        "video.motion_blur must be between 0 and 1, not 1.5"
    );
    let adjustment = int(&handle.value(), "/clips/2/id");
    assert_eq!(
        handle.errors(&set(adjustment, 0.5)),
        format!("clip {adjustment} is an adjustment clip and cannot take motion blur")
    );
    // 0 is always taken (an identity: nothing to change).
    handle.try_apply(&set(adjustment, 0.0)).expect("0 is taken");
    let nested = handle.apply(&json!({ "op": "nest", "clips": [13] }));
    let nest = array(&nested.value(), "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| int(c, "/id"))
        .expect("a nest clip");
    assert_eq!(
        nested.errors(&set(nest, 0.5)),
        format!("clip {nest} shows a nest and cannot take motion blur: set it on the clips inside")
    );
    // A pasted video group meets the same rule through `settle_video`.
    let source = clip(40, 2, 0, blurred(), json!([]));
    let error = handle.errors(&json!({ "op": "paste_attributes", "clips": [adjustment],
        "payload": { "clips": [source], "media": [] }, "groups": ["video"] }));
    assert!(
        error.contains(&format!(
            "clip {adjustment} is an adjustment clip and cannot take motion blur"
        )),
        "{error}"
    );
    let on = handle.apply(&set(11, 0.5));
    assert_eq!(on.value()["clips"][0]["video"]["motion_blur"], json!(0.5));
    let off = on.apply(&set(11, 0.0));
    assert!(!off.to_json().contains("motion_blur"), "{}", off.to_json());
}

#[test]
fn a_blurred_background_copy_drops_motion_blur() {
    let handle = zooming().apply(&json!({ "op": "add_blurred_background", "clip": 11 }));
    let value = handle.value();
    let clips = array(&value, "/clips");
    assert_eq!(clips.len(), 2);
    for clip in clips {
        let expected = if int(clip, "/id") == 11 {
            json!(0.5)
        } else {
            Value::Null
        };
        assert_eq!(clip["video"]["motion_blur"], expected, "{clip}");
    }
}

// ---- the cursor's shutter -----------------------------------------------------

#[test]
fn the_cursors_shutter_reads_the_ends_in_source_ticks() {
    const IN: i64 = SEC / 2;
    let cursor_clip = |speed: f64, video: Value| {
        json!([{ "id": 11, "track": 2, "start": START, "duration": 2 * SEC,
                 "source": { "kind": "media", "media": 1, "in": IN },
                 "speed": speed, "video": video, "audio": {} }])
    };
    let t = START + SEC / 2;
    for (speed, half) in [(1.0, 5_000), (2.0, 10_000)] {
        let handle = project_at(
            [30, 1],
            one_track(),
            cursor_clip(speed, blurred()),
            json!([]),
            true,
        );
        let cursor = layer(&handle, t, 11)["cursor"].clone();
        let at = IN + ((t - START) as f64 * speed) as i64;
        assert_eq!(cursor["at"], json!(at));
        assert_eq!(
            cursor["shutter"],
            json!({ "from": at - half, "to": at + half, "samples": N }),
            "×{speed}"
        );
        // The layer itself stands still, so it has no blur.
        assert_eq!(layer(&handle, t, 11)["blur"], Value::Null);
    }
    let off = project_at(
        [30, 1],
        one_track(),
        cursor_clip(1.0, json!({})),
        json!([]),
        true,
    );
    let cursor = layer(&off, t, 11)["cursor"].clone();
    assert!(
        cursor.is_object() && cursor.get("shutter").is_none(),
        "{cursor}"
    );
    let still = json!([{ "id": 11, "track": 2, "start": START, "duration": 2 * SEC,
                         "source": { "kind": "still", "media": 1, "at": IN },
                         "video": blurred() }]);
    let still = project_at([30, 1], one_track(), still, json!([]), true);
    let cursor = layer(&still, t, 11)["cursor"].clone();
    assert!(
        cursor.is_object() && cursor.get("shutter").is_none(),
        "{cursor}"
    );
}
