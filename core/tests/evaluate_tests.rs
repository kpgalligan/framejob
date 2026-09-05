//! Black-box tests for the two things the platform actually consumes — the
//! composition plan (spec §7.2) and the frame recipe (spec §7.3) — plus the
//! inspector's `clip_state`, driven through the C FFI exactly as
//! `ReelCore.swift` will drive them.
//!
//! Everything here is checked against an oracle written out by hand in the
//! test: instruction boundaries are recomputed from the clip edges, ramp
//! tables are the arithmetic of spec §7.2's envelope rules done on paper,
//! and interpolated values are the §5.4 rule applied by hand. Nothing is
//! compared against a recorded output, so a change in behaviour has to be
//! argued against the spec rather than re-recorded.
//!
//! Two cross-checks run over most fixtures, because the plan and the recipe
//! are two views of one timeline and the whole design rests on them
//! agreeing:
//!
//! - [`assert_sources_agree`] — every `{"kind":"track"}` layer names a video
//!   composition track the plan actually has, with a segment for that clip
//!   covering that instant.
//! - [`assert_instructions_match_recipe`] — an instruction's
//!   `required_track_ids` is exactly the set of composition tracks the
//!   recipe asks for at the instruction's first tick. The plan computes it
//!   from the visible-clip list; the recipe is asked independently.

mod common;

use serde_json::{json, Value};

use common::{array, flag, int, num, parse_json, text, Handle};
use reelcut_core::model::Project;
use reelcut_core::{Clip, Enabled, Fps, Source, VideoProps};

// ---- the oracle's own constants ------------------------------------------

/// Ticks per second (spec §5.1). Written out here rather than imported, so a
/// change to `time::TIMESCALE` fails these tests instead of moving with them.
const SEC: i64 = 600_000;

/// One frame at the fixtures' canvas rate of 30 fps.
const FRAME_30: i64 = SEC / 30;

/// Comparison slack for gains and interpolated properties. Every expected
/// value below is exactly representable in binary floating point, so this
/// only absorbs the multiply-and-add the implementation does on the way.
const EPS: f64 = 1e-12;

// ---- fixtures ------------------------------------------------------------

/// A media descriptor with everything the plan reads. `fps` is the SOURCE
/// rate, which is where a `still` segment's one-frame length comes from.
fn media(
    id: u32,
    kind: &str,
    duration: i64,
    fps: [u32; 2],
    has_video: bool,
    has_audio: bool,
) -> Value {
    json!({
        "id": id,
        "path": format!("/fixtures/{id}.mov"),
        "bookmark": null,
        "kind": kind,
        "duration": duration,
        "width": if has_video { 1920 } else { 0 },
        "height": if has_video { 1080 } else { 0 },
        "fps": fps,
        "has_video": has_video,
        "has_audio": has_audio,
        "has_alpha": false
    })
}

/// The ordinary fixture media: 60 s of 1920x1080 at 30 fps with sound.
fn video_media(id: u32) -> Value {
    media(id, "video", 60 * SEC, [30, 1], true, true)
}

fn track(id: u32) -> Value {
    json!({ "id": id, "name": format!("Track {id}") })
}

/// A media clip carrying both property groups, which is what `set_video`,
/// `freeze_frame` and the envelope all need to see.
fn media_clip(id: u32, on_track: u32, start: i64, duration: i64, source_media: u32) -> Value {
    json!({
        "id": id,
        "track": on_track,
        "start": start,
        "duration": duration,
        "source": { "kind": "media", "media": source_media, "in": 0 },
        "video": {},
        "audio": {}
    })
}

fn project(media: Vec<Value>, tracks: Vec<Value>, clips: Vec<Value>, next_id: u32) -> Value {
    json!({
        "version": 1,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0.0, 0.0, 0.0, 1.0],
            "fit_new_clips": true, "timecode_frames": true
        },
        "media": media,
        "tracks": tracks,
        "clips": clips,
        "markers": [],
        "next_id": next_id
    })
}

/// One video media, one track, one clip filling `duration`.
fn one_clip_project(duration: i64) -> Value {
    project(
        vec![video_media(1)],
        vec![track(2)],
        vec![media_clip(11, 2, 0, duration, 1)],
        12,
    )
}

// ---- reading the plan and the recipe -------------------------------------

fn comp_track_ids(plan: &Value, group: &str) -> Vec<i64> {
    array(plan, &format!("/{group}"))
        .iter()
        .map(|t| int(t, "/id"))
        .collect()
}

fn comp_track<'a>(plan: &'a Value, group: &str, id: i64) -> &'a Value {
    array(plan, &format!("/{group}"))
        .iter()
        .find(|t| int(t, "/id") == id)
        .unwrap_or_else(|| panic!("no {group} entry with id {id} in {plan}"))
}

/// The segment for `clip` on the given side of the plan, wherever it landed.
fn segment_of(plan: &Value, group: &str, clip: i64) -> Value {
    for comp in array(plan, &format!("/{group}")) {
        for segment in array(comp, "/segments") {
            if int(segment, "/clip") == clip {
                return segment.clone();
            }
        }
    }
    panic!("no {group} segment for clip {clip} in {plan}");
}

/// Which composition track each clip's segments landed on, sorted by clip —
/// the A/B assignment, read back out of the plan.
fn clip_to_comp_track(plan: &Value, group: &str) -> Vec<(i64, i64)> {
    let mut out = Vec::new();
    for comp in array(plan, &format!("/{group}")) {
        let id = int(comp, "/id");
        for segment in array(comp, "/segments") {
            out.push((int(segment, "/clip"), id));
        }
    }
    out.sort_unstable();
    out
}

fn layer_ids(recipe: &Value) -> Vec<i64> {
    array(recipe, "/layers")
        .iter()
        .map(|l| int(l, "/clip"))
        .collect()
}

fn layer_of(recipe: &Value, clip: i64) -> Value {
    array(recipe, "/layers")
        .iter()
        .find(|l| int(l, "/clip") == clip)
        .unwrap_or_else(|| panic!("no layer for clip {clip} in {recipe}"))
        .clone()
}

/// The composition video tracks the recipe asks for at its own instant,
/// sorted and deduplicated — the independent oracle for an instruction's
/// `required_track_ids`.
fn required_by_recipe(recipe: &Value) -> Vec<i64> {
    let mut out: Vec<i64> = array(recipe, "/layers")
        .iter()
        .filter(|l| l["source"]["kind"] == json!("track"))
        .map(|l| int(l, "/source/track_id"))
        .collect();
    out.sort_unstable();
    out.dedup();
    out
}

// ---- shared assertions ---------------------------------------------------

/// The instruction tiling of spec §7.2: contiguous, non-overlapping, first
/// at 0, last ending at the project duration, every span positive. An empty
/// timeline has no instructions at all.
fn assert_tiles(plan: &Value) {
    let duration = int(plan, "/duration");
    let instructions = array(plan, "/instructions");
    if duration <= 0 {
        assert!(
            instructions.is_empty(),
            "a project of {duration} ticks got {} instructions",
            instructions.len()
        );
        return;
    }
    assert!(
        !instructions.is_empty(),
        "a project of {duration} ticks got no instructions"
    );
    let mut cursor = 0i64;
    for (i, instruction) in instructions.iter().enumerate() {
        let start = int(instruction, "/start");
        let span = int(instruction, "/duration");
        assert_eq!(
            start, cursor,
            "instruction {i} starts at {start}; the previous one ended at {cursor}"
        );
        assert!(span > 0, "instruction {i} has a duration of {span}");
        cursor = start + span;
    }
    assert_eq!(
        cursor, duration,
        "the tiling ends at {cursor}, not at the project duration {duration}"
    );
}

/// Every `track` layer names a composition track the plan has, with a
/// segment for that clip covering the recipe's instant.
fn assert_sources_agree(plan: &Value, recipe: &Value) {
    let t = int(recipe, "/t");
    for layer in array(recipe, "/layers") {
        if layer["source"]["kind"] != json!("track") {
            continue;
        }
        let clip = int(layer, "/clip");
        let track_id = int(layer, "/source/track_id");
        let comp = comp_track(plan, "video_tracks", track_id);
        let segment = array(comp, "/segments")
            .iter()
            .find(|s| int(s, "/clip") == clip)
            .unwrap_or_else(|| panic!("video track {track_id} carries no segment for clip {clip}"));
        let start = int(segment, "/start");
        let end = start + int(segment, "/duration");
        assert!(
            start <= t && t < end,
            "clip {clip} draws at {t} but its segment covers [{start}, {end})"
        );
    }
}

/// An instruction's `required_track_ids` is exactly what the recipe asks for
/// at the instruction's first tick — the two entry points computing one fact
/// from opposite ends.
fn assert_instructions_match_recipe(handle: &Handle, plan: &Value) {
    for instruction in array(plan, "/instructions") {
        let start = int(instruction, "/start");
        let recipe = handle.recipe(start);
        let required: Vec<i64> = array(instruction, "/required_track_ids")
            .iter()
            .map(|v| v.as_i64().expect("a track id is an integer"))
            .collect();
        assert_eq!(
            required,
            required_by_recipe(&recipe),
            "the instruction at {start} disagrees with the recipe there"
        );
        assert_sources_agree(plan, &recipe);
    }
}

/// Ramps against a hand-computed table, plus the promise that they tile the
/// track's extent with no gap.
fn assert_ramps(actual: &[Value], expected: &[(i64, i64, f64, f64)]) {
    assert_eq!(
        actual.len(),
        expected.len(),
        "ramp count; got {}",
        Value::Array(actual.to_vec())
    );
    let mut cursor: Option<i64> = None;
    for (i, (ramp, (start, span, from, to))) in actual.iter().zip(expected).enumerate() {
        assert_eq!(int(ramp, "/start"), *start, "ramp {i} start in {ramp}");
        assert_eq!(int(ramp, "/duration"), *span, "ramp {i} duration in {ramp}");
        assert!(
            (num(ramp, "/from") - from).abs() < EPS,
            "ramp {i} starts at {} not {from}",
            num(ramp, "/from")
        );
        assert!(
            (num(ramp, "/to") - to).abs() < EPS,
            "ramp {i} ends at {} not {to}",
            num(ramp, "/to")
        );
        if let Some(previous_end) = cursor {
            assert_eq!(
                *start, previous_end,
                "ramp {i} leaves a gap in the envelope"
            );
        }
        cursor = Some(start + span);
    }
}

// ---- instruction tiling --------------------------------------------------

#[test]
fn plan_instructions_tile_a_single_clip() {
    let handle = Handle::from_value(&one_clip_project(6 * SEC));
    let plan = handle.plan();

    assert_eq!(int(&plan, "/timescale"), SEC);
    assert_eq!(int(&plan, "/duration"), 6 * SEC);
    assert_eq!(plan["fps"], json!([30, 1]));
    assert_eq!(plan["render_size"], json!([1920, 1080]));
    assert_tiles(&plan);

    // One clip, one boundary pair: the whole timeline is one instruction.
    let instructions = array(&plan, "/instructions");
    assert_eq!(instructions.len(), 1, "got {instructions:?}");
    assert_eq!(instructions[0]["required_track_ids"], json!([1]));
    assert_eq!(plan["warnings"], json!([]));
    assert_instructions_match_recipe(&handle, &plan);
}

#[test]
fn plan_instructions_tile_three_staggered_tracks() {
    // Track 2 (back) 0..6 s, track 3 2..8 s, track 4 8..10 s. The boundaries
    // are therefore 0, 2, 6, 8, 10 s and the project is 10 s long.
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3), track(4)],
        vec![
            media_clip(11, 2, 0, 6 * SEC, 1),
            media_clip(12, 3, 2 * SEC, 6 * SEC, 1),
            media_clip(13, 4, 8 * SEC, 2 * SEC, 1),
        ],
        14,
    ));
    let plan = handle.plan();

    assert_eq!(int(&plan, "/duration"), 10 * SEC);
    assert_tiles(&plan);

    let bounds: Vec<(i64, i64)> = array(&plan, "/instructions")
        .iter()
        .map(|i| (int(i, "/start"), int(i, "/duration")))
        .collect();
    assert_eq!(
        bounds,
        vec![
            (0, 2 * SEC),
            (2 * SEC, 4 * SEC),
            (6 * SEC, 2 * SEC),
            (8 * SEC, 2 * SEC),
        ]
    );
    // Each timeline track gets its own composition track, back to front.
    let required: Vec<Value> = array(&plan, "/instructions")
        .iter()
        .map(|i| i["required_track_ids"].clone())
        .collect();
    assert_eq!(
        required,
        vec![json!([1]), json!([1, 2]), json!([2]), json!([3])]
    );
    assert_instructions_match_recipe(&handle, &plan);
}

#[test]
fn plan_instructions_tile_across_a_gap() {
    // 0..2 s, nothing, 4..6 s: the hole in the middle still gets an
    // instruction, with no required tracks — AVFoundation rejects a tiling
    // with a hole in it.
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            media_clip(11, 2, 0, 2 * SEC, 1),
            media_clip(12, 2, 4 * SEC, 2 * SEC, 1),
        ],
        13,
    ));
    let plan = handle.plan();

    assert_eq!(int(&plan, "/duration"), 6 * SEC);
    assert_tiles(&plan);

    let instructions = array(&plan, "/instructions");
    assert_eq!(instructions.len(), 3, "got {instructions:?}");
    assert_eq!(instructions[1]["start"], json!(2 * SEC));
    assert_eq!(instructions[1]["duration"], json!(2 * SEC));
    assert_eq!(
        instructions[1]["required_track_ids"],
        json!([]),
        "the gap requires nothing"
    );
    assert_instructions_match_recipe(&handle, &plan);
}

#[test]
fn plan_of_an_empty_project_has_no_instructions() {
    let handle = Handle::new(1920, 1080, 30, 1);
    assert_eq!(handle.duration(), 0);

    let plan = handle.plan();
    assert_eq!(int(&plan, "/duration"), 0);
    assert_tiles(&plan);
    assert_eq!(plan["video_tracks"], json!([]));
    assert_eq!(plan["audio_tracks"], json!([]));
    assert_eq!(plan["warnings"], json!([]));

    // And the recipe over an empty project is still valid JSON.
    assert_eq!(handle.recipe(0)["layers"], json!([]));
}

// ---- the A/B assignment --------------------------------------------------

#[test]
fn overlapping_clips_take_two_composition_tracks() {
    // 0..6 s and 5..11 s: a 1 s overlap, well under half the shorter clip,
    // so the overlap rule allows it and the A/B assignment must split them.
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            media_clip(11, 2, 0, 6 * SEC, 1),
            media_clip(12, 2, 5 * SEC, 6 * SEC, 1),
        ],
        13,
    ));
    let plan = handle.plan();

    assert_eq!(comp_track_ids(&plan, "video_tracks"), vec![1, 2]);
    assert_eq!(comp_track_ids(&plan, "audio_tracks"), vec![101, 102]);
    assert_eq!(
        clip_to_comp_track(&plan, "video_tracks"),
        vec![(11, 1), (12, 2)]
    );
    assert_eq!(
        clip_to_comp_track(&plan, "audio_tracks"),
        vec![(11, 101), (12, 102)]
    );
    assert_tiles(&plan);
    assert_instructions_match_recipe(&handle, &plan);
}

#[test]
fn sequential_clips_share_one_composition_track() {
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            media_clip(11, 2, 0, 2 * SEC, 1),
            media_clip(12, 2, 2 * SEC, 2 * SEC, 1),
            media_clip(13, 2, 4 * SEC, 2 * SEC, 1),
        ],
        14,
    ));
    let plan = handle.plan();

    assert_eq!(comp_track_ids(&plan, "video_tracks"), vec![1]);
    assert_eq!(comp_track_ids(&plan, "audio_tracks"), vec![101]);
    let starts: Vec<i64> = array(comp_track(&plan, "video_tracks", 1), "/segments")
        .iter()
        .map(|s| int(s, "/start"))
        .collect();
    assert_eq!(starts, vec![0, 2 * SEC, 4 * SEC], "segments in start order");
    assert_eq!(
        array(comp_track(&plan, "audio_tracks", 101), "/segments").len(),
        3
    );
}

#[test]
fn composition_track_ids_are_stable_across_calls() {
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3)],
        vec![
            media_clip(11, 2, 0, 6 * SEC, 1),
            media_clip(12, 2, 5 * SEC, 6 * SEC, 1),
            media_clip(13, 3, SEC, 4 * SEC, 1),
        ],
        14,
    ));

    let first = handle.plan();
    let second = handle.plan();
    assert_eq!(
        clip_to_comp_track(&first, "video_tracks"),
        clip_to_comp_track(&second, "video_tracks")
    );
    assert_eq!(
        clip_to_comp_track(&first, "audio_tracks"),
        clip_to_comp_track(&second, "audio_tracks")
    );
    // Timeline track 2 holds an overlapping pair (ids 1, 2); track 3 one
    // clip, which gets the next id.
    assert_eq!(comp_track_ids(&first, "video_tracks"), vec![1, 2, 3]);
    assert_eq!(comp_track_ids(&first, "audio_tracks"), vec![101, 102, 103]);
}

// ---- plan stability, which decides rebuild versus refresh (spec §7.6) ----

#[test]
fn plan_is_byte_identical_for_the_same_project() {
    let fixture = project(
        vec![video_media(1)],
        vec![track(2), track(3)],
        vec![
            media_clip(11, 2, 0, 6 * SEC, 1),
            media_clip(12, 3, SEC, 4 * SEC, 1),
        ],
        13,
    );
    let handle = Handle::from_value(&fixture);
    assert_eq!(handle.plan_text(), handle.plan_text());

    // A separately parsed handle, and a clone, must also agree to the byte:
    // Swift compares plan strings across document loads and undo steps.
    assert_eq!(handle.plan_text(), Handle::from_value(&fixture).plan_text());
    assert_eq!(handle.plan_text(), handle.duplicate().plan_text());
}

#[test]
fn plan_changes_after_a_structural_edit() {
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3)],
        vec![
            media_clip(11, 2, 0, 6 * SEC, 1),
            media_clip(12, 3, 0, 6 * SEC, 1),
        ],
        13,
    ));
    let before = handle.plan_text();

    let moved = handle.apply(&json!({ "op": "move_clip", "clips": [12], "delta": SEC }));
    assert_ne!(
        before,
        moved.plan_text(),
        "moving a clip must change the plan, or Swift never rebuilds"
    );

    // The move is exactly what changed: the clip's segment and the tiling.
    let plan = moved.plan();
    assert_eq!(int(&segment_of(&plan, "video_tracks", 12), "/start"), SEC);
    assert_tiles(&plan);
    assert_instructions_match_recipe(&moved, &plan);
}

#[test]
fn plan_is_unchanged_by_a_property_edit() {
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3)],
        vec![
            media_clip(11, 2, 0, 6 * SEC, 1),
            media_clip(12, 3, 0, 6 * SEC, 1),
        ],
        13,
    ));
    let before = handle.plan_text();

    let dimmed = handle.apply(&json!({
        "op": "set_video", "clips": [11], "patch": { "opacity": 0.5 }
    }));

    assert_eq!(
        before,
        dimmed.plan_text(),
        "an opacity change must not rebuild the composition"
    );
    // ...and it really did happen: the recipe, which is per-property, moved.
    assert!(
        (num(&layer_of(&dimmed.recipe(SEC), 11), "/opacity") - 0.5).abs() < EPS,
        "the opacity edit did not reach the recipe"
    );
    assert!((num(&layer_of(&handle.recipe(SEC), 11), "/opacity") - 1.0).abs() < EPS);
}

// ---- speed and freeze frames ---------------------------------------------

#[test]
fn a_double_speed_clip_consumes_twice_its_duration_of_source() {
    let mut clip = media_clip(11, 2, 0, 5 * SEC, 1);
    clip["speed"] = json!(2.0);
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![clip],
        12,
    ));
    let plan = handle.plan();

    let segment = segment_of(&plan, "video_tracks", 11);
    let duration = int(&segment, "/duration");
    let source_duration = int(&segment, "/source_duration");
    assert_eq!(duration, 5 * SEC);
    assert_eq!(
        duration,
        source_duration / 2,
        "at 2x a 5 s clip must consume 10 s of source"
    );
    assert_eq!(source_duration, 10 * SEC);

    // The audio side carries the same range plus the time-pitch flag.
    let audio = segment_of(&plan, "audio_tracks", 11);
    assert_eq!(int(&audio, "/source_duration"), 10 * SEC);
    assert_eq!(audio["pitch"], json!("spectral"), "keep_pitch defaults on");
}

#[test]
fn a_freeze_frame_segment_is_one_source_frame() {
    // The media runs at 30000/1001, so one source frame is
    // 600000 * 1001 / 30000 = 20020 ticks — computed here by hand.
    let one_source_frame = SEC * 1001 / 30_000;
    assert_eq!(one_source_frame, 20_020);

    let handle = Handle::from_value(&project(
        vec![media(1, "video", 60 * SEC, [30_000, 1001], true, true)],
        vec![track(2)],
        vec![media_clip(11, 2, 0, 10 * SEC, 1)],
        12,
    ));
    let frozen = handle.apply(&json!({
        "op": "freeze_frame", "clip": 11, "at": 5 * SEC, "duration": 2 * SEC
    }));

    let still = still_clip(&frozen);
    let still_id = int(&still, "/id");
    assert_eq!(int(&still, "/start"), 5 * SEC);
    assert_eq!(int(&still, "/duration"), 2 * SEC);

    let plan = frozen.plan();
    let segment = segment_of(&plan, "video_tracks", still_id);
    assert_eq!(
        int(&segment, "/source_duration"),
        one_source_frame,
        "a still is exactly one SOURCE frame, scaled to the clip"
    );
    assert_eq!(int(&segment, "/duration"), 2 * SEC);
    // in (0) + (at - start) * speed (1.0) is the source time of the frame.
    assert_eq!(int(&segment, "/source_in"), 5 * SEC);
    assert_tiles(&plan);
}

/// The one `still` clip a `freeze_frame` left behind.
fn still_clip(handle: &Handle) -> Value {
    let value = handle.value();
    array(&value, "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("still"))
        .expect("freeze_frame produced no still clip")
        .clone()
}

// ---- audio envelopes -----------------------------------------------------

#[test]
fn fades_produce_ramps_from_zero_and_to_zero() {
    let mut clip = media_clip(11, 2, 0, 10 * SEC, 1);
    clip["audio"] = json!({ "volume": 1.0, "fade_in": SEC, "fade_out": SEC });
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![clip],
        12,
    ));
    let plan = handle.plan();

    // By hand: silence at 0 rising to full at 1 s, full until 9 s, then back
    // to silence at 10 s — the envelope of spec §7.2's own example.
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", 101), "/ramps"),
        &[
            (0, SEC, 0.0, 1.0),
            (SEC, 8 * SEC, 1.0, 1.0),
            (9 * SEC, SEC, 1.0, 0.0),
        ],
    );
}

#[test]
fn a_muted_clip_and_a_muted_track_produce_a_zero_envelope() {
    let mut muted_clip = media_clip(11, 2, 0, 10 * SEC, 1);
    muted_clip["audio"] = json!({ "volume": 1.0, "muted": true });
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![muted_clip],
        12,
    ));
    let plan = handle.plan();

    let comp = comp_track(&plan, "audio_tracks", 101);
    assert_eq!(
        array(comp, "/segments").len(),
        1,
        "a muted clip keeps its segment: unmuting must not rebuild"
    );
    assert_ramps(array(comp, "/ramps"), &[(0, 10 * SEC, 0.0, 0.0)]);

    // A muted TRACK is the same envelope by a different route.
    let plain = Handle::from_value(&one_clip_project(10 * SEC));
    let silenced = plain.apply(&json!({ "op": "set_track", "track": 2, "muted": true }));
    let silenced_plan = silenced.plan();
    let silenced_comp = comp_track(&silenced_plan, "audio_tracks", 101);
    assert_eq!(array(silenced_comp, "/segments").len(), 1);
    assert_ramps(array(silenced_comp, "/ramps"), &[(0, 10 * SEC, 0.0, 0.0)]);
}

#[test]
fn a_ducking_clip_lowers_the_other_track_by_its_level() {
    // Bed: 0..20 s on track 3. Voice: 5..10 s on track 4, ducking to 0.25
    // with a 1 s attack and a 2 s release. By hand, the bed's gain is
    //   1.0            until 5 s          (before the ducker)
    //   1.0 -> 0.25    over 5..6 s        (the attack)
    //   0.25           held to 10 s       (the ducker's extent)
    //   0.25 -> 1.0    over 10..12 s      (the release, AFTER the ducker)
    //   1.0            to 20 s
    let mut voice = media_clip(12, 4, 5 * SEC, 5 * SEC, 2);
    voice["video"] = json!(null);
    voice["audio"] = json!({
        "volume": 1.0,
        "duck": { "level": 0.25, "attack": SEC, "release": 2 * SEC }
    });
    let handle = Handle::from_value(&project(
        vec![
            video_media(1),
            media(2, "audio", 60 * SEC, [30, 1], false, true),
        ],
        vec![track(3), track(4)],
        vec![media_clip(11, 3, 0, 20 * SEC, 1), voice],
        13,
    ));
    let plan = handle.plan();

    assert_eq!(comp_track_ids(&plan, "audio_tracks"), vec![101, 102]);
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", 101), "/ramps"),
        &[
            (0, 5 * SEC, 1.0, 1.0),
            (5 * SEC, SEC, 1.0, 0.25),
            (6 * SEC, 4 * SEC, 0.25, 0.25),
            (10 * SEC, 2 * SEC, 0.25, 1.0),
            (12 * SEC, 8 * SEC, 1.0, 1.0),
        ],
    );

    // A clip never ducks its own composition track.
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", 102), "/ramps"),
        &[(5 * SEC, 5 * SEC, 1.0, 1.0)],
    );

    // The audio-only voice draws nothing, so only the bed needs a decode.
    assert_eq!(comp_track_ids(&plan, "video_tracks"), vec![1]);
    assert_instructions_match_recipe(&handle, &plan);
}

#[test]
fn an_envelope_covers_a_gap_between_clips_with_silence() {
    // Two clips on one composition track with 2 s of nothing between them.
    // The envelope has to cover the hole, or the mix plays the track's last
    // level under it.
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            media_clip(11, 2, 0, 2 * SEC, 1),
            media_clip(12, 2, 4 * SEC, 2 * SEC, 1),
        ],
        13,
    ));
    let plan = handle.plan();

    let comp = comp_track(&plan, "audio_tracks", 101);
    assert_eq!(
        array(comp, "/segments").len(),
        2,
        "one A/B track, two segments"
    );
    assert_ramps(
        array(comp, "/ramps"),
        &[
            (0, 2 * SEC, 1.0, 1.0),
            (2 * SEC, 2 * SEC, 0.0, 0.0),
            (4 * SEC, 2 * SEC, 1.0, 1.0),
        ],
    );
}

/// A ten second clip whose volume runs 1.0 -> 0.0 over clip time 2..4 s.
fn volume_action_project(curve: &str) -> Value {
    let mut clip = media_clip(11, 2, 0, 10 * SEC, 1);
    clip["audio"] = json!({ "volume": 1.0 });
    clip["actions"] = json!([{
        "id": 21, "start": 2 * SEC, "duration": 2 * SEC, "curve": curve,
        "end": { "audio": { "volume": 0.0 } }
    }]);
    project(vec![video_media(1)], vec![track(2)], vec![clip], 22)
}

#[test]
fn a_linear_volume_action_collapses_to_one_ramp() {
    // audio.rs samples every action's span on a 1/30 s grid and then merges
    // collinear pieces, so a linear move must come back as ONE ramp — sixty
    // near-identical ramps in every plan would be compared and stored for
    // nothing.
    let handle = Handle::from_value(&volume_action_project("linear"));
    let plan = handle.plan();
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", 101), "/ramps"),
        &[
            (0, 2 * SEC, 1.0, 1.0),
            (2 * SEC, 2 * SEC, 1.0, 0.0),
            (4 * SEC, 6 * SEC, 0.0, 0.0),
        ],
    );
}

#[test]
fn an_eased_volume_action_keeps_the_samples_it_needs() {
    let handle = Handle::from_value(&volume_action_project("ease_in_out"));
    let plan = handle.plan();
    let ramps = array(comp_track(&plan, "audio_tracks", 101), "/ramps");

    assert!(
        ramps.len() > 3,
        "a curve cannot be one straight line; got {} ramps",
        ramps.len()
    );
    // Still an envelope: contiguous over the whole clip, starting at full
    // volume, ending in silence, and never rising on the way down.
    let mut cursor = 0i64;
    let mut previous = 1.0f64;
    for ramp in ramps {
        assert_eq!(int(ramp, "/start"), cursor, "gap before {ramp}");
        cursor = int(ramp, "/start") + int(ramp, "/duration");
        let from = num(ramp, "/from");
        let to = num(ramp, "/to");
        assert!(
            (0.0..=1.0).contains(&from) && (0.0..=1.0).contains(&to),
            "{ramp}"
        );
        assert!(to <= previous + EPS, "the envelope rose again at {ramp}");
        previous = to;
    }
    assert_eq!(cursor, 10 * SEC);
    assert!((num(&ramps[0], "/from") - 1.0).abs() < EPS);
    assert!(num(&ramps[ramps.len() - 1], "/to").abs() < EPS);
}

#[test]
fn a_frozen_still_contributes_no_audio() {
    // A `still` segment is one source frame scaled over the clip — the
    // freeze-frame idiom. On an audio track that is a 1/30 s fragment
    // smeared over seconds, so a still never gets one, even when its
    // `enabled.audio` is switched back on after the freeze.
    let handle = Handle::from_value(&one_clip_project(10 * SEC));
    let frozen = handle.apply(&json!({
        "op": "freeze_frame", "clip": 11, "at": 5 * SEC, "duration": 2 * SEC
    }));
    let still_id = int(&still_clip(&frozen), "/id");
    let unmuted = frozen.apply(&json!({
        "op": "set_enabled", "clip": still_id, "audio": true
    }));

    let plan = unmuted.plan();
    let audio_clips: Vec<i64> = clip_to_comp_track(&plan, "audio_tracks")
        .into_iter()
        .map(|(clip, _)| clip)
        .collect();
    assert!(
        !audio_clips.contains(&still_id),
        "the still landed on an audio track: {plan}"
    );
    // The picture is still frozen, though.
    assert_eq!(
        int(
            &segment_of(&plan, "video_tracks", still_id),
            "/source_duration"
        ),
        FRAME_30
    );
    assert_tiles(&plan);
}

#[test]
fn too_many_simultaneous_video_tracks_warn_in_the_plan() {
    // Nine timeline tracks all visible at once, then a tenth joining at 5 s:
    // two instructions over the eight-decode budget.
    let mut tracks = Vec::new();
    let mut clips = Vec::new();
    for i in 0..9u32 {
        tracks.push(track(2 + i));
        clips.push(media_clip(20 + i, 2 + i, 0, 10 * SEC, 1));
    }
    tracks.push(track(11));
    clips.push(media_clip(29, 11, 5 * SEC, 5 * SEC, 1));
    let handle = Handle::from_value(&project(vec![video_media(1)], tracks, clips, 40));
    let plan = handle.plan();

    assert_tiles(&plan);
    assert_eq!(
        array(&plan, "/instructions")[0]["required_track_ids"],
        json!([1, 2, 3, 4, 5, 6, 7, 8, 9])
    );
    let warnings = array(&plan, "/warnings");
    assert_eq!(warnings.len(), 2, "got {warnings:?}");
    assert_eq!(
        warnings[0],
        json!(
            "9 video tracks are required at once (at 0 ticks), more than the 8 \
             simultaneous decodes playback can keep up with"
        )
    );
    assert_eq!(
        warnings[1],
        json!("1 more instructions are over the video track budget")
    );
    assert_instructions_match_recipe(&handle, &plan);
}

// ---- action evaluation ---------------------------------------------------

/// A ten second clip whose x animates 0 -> 300 over clip time 2..4 s.
fn animated_x_project(curve: &str) -> Value {
    let mut clip = media_clip(11, 2, 0, 10 * SEC, 1);
    clip["actions"] = json!([{
        "id": 21, "start": 2 * SEC, "duration": 2 * SEC, "curve": curve,
        "end": { "video": { "x": 300.0 } }
    }]);
    project(vec![video_media(1)], vec![track(2)], vec![clip], 22)
}

fn x_at(handle: &Handle, t: i64) -> f64 {
    num(&layer_of(&handle.recipe(t), 11), "/x")
}

#[test]
fn a_linear_action_lands_on_its_end_value_without_a_jump() {
    let handle = Handle::from_value(&animated_x_project("linear"));
    let end = 4 * SEC;

    // A frame's worth of the total change: 300 px spread over 2 s, sampled
    // one 30 fps frame apart.
    let per_frame = 300.0 * FRAME_30 as f64 / (2 * SEC) as f64;
    assert!((per_frame - 5.0).abs() < EPS);

    let before = x_at(&handle, end - FRAME_30);
    let at_end = x_at(&handle, end);
    assert!(
        (at_end - 300.0).abs() < EPS,
        "the action must land exactly on 300, got {at_end}"
    );
    assert!(
        (at_end - before).abs() <= per_frame + EPS,
        "x jumped {} across the action boundary, more than one frame's {per_frame}",
        at_end - before
    );
    // Past the action the value simply holds.
    assert!((x_at(&handle, end + FRAME_30) - 300.0).abs() < EPS);
}

#[test]
fn an_eased_action_lands_on_its_end_value_without_a_jump() {
    let handle = Handle::from_value(&animated_x_project("ease_in_out"));
    let end = 4 * SEC;
    let per_frame = 300.0 * FRAME_30 as f64 / (2 * SEC) as f64;

    let before = x_at(&handle, end - FRAME_30);
    let at_end = x_at(&handle, end);
    assert!((at_end - 300.0).abs() < EPS, "got {at_end}");
    assert!(
        at_end - before < per_frame,
        "an eased action decelerates into its end; it moved {} in the last frame",
        at_end - before
    );
    // Smoothstep at u = 1180000/1200000, computed here rather than read off.
    let u = (2 * SEC - FRAME_30) as f64 / (2 * SEC) as f64;
    let expected = 300.0 * u * u * (3.0 - 2.0 * u);
    assert!(
        (before - expected).abs() < 1e-9,
        "expected {expected} one frame before the end, got {before}"
    );
}

#[test]
fn a_property_with_no_action_holds_its_base_value() {
    let mut clip = media_clip(11, 2, 0, 10 * SEC, 1);
    clip["video"] = json!({ "x": 42.0, "scale": 0.5 });
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![clip],
        12,
    ));

    for t in [0, 3 * SEC, 7 * SEC, 10 * SEC - 1] {
        let layer = layer_of(&handle.recipe(t), 11);
        assert!((num(&layer, "/x") - 42.0).abs() < EPS, "x at {t}");
        assert!((num(&layer, "/scale") - 0.5).abs() < EPS, "scale at {t}");
    }
}

#[test]
fn one_action_interpolates_between_base_and_end() {
    let handle = Handle::from_value(&animated_x_project("linear"));

    // Before the action, at its first tick, halfway, and after it.
    for (t, expected) in [
        (0, 0.0),
        (SEC, 0.0),
        (2 * SEC, 0.0),
        (3 * SEC, 150.0),
        (4 * SEC, 300.0),
        (8 * SEC, 300.0),
    ] {
        let x = x_at(&handle, t);
        assert!(
            (x - expected).abs() < 1e-9,
            "x at {t} is {x}, expected {expected}"
        );
    }
}

#[test]
fn two_sequential_actions_compose() {
    // x: 0 -> 300 over 2..4 s, then 300 -> -100 over 5..7 s. The second
    // action starts from what the first left behind, not from the base.
    let mut clip = media_clip(11, 2, 0, 10 * SEC, 1);
    clip["actions"] = json!([
        { "id": 21, "start": 2 * SEC, "duration": 2 * SEC, "curve": "linear",
          "end": { "video": { "x": 300.0 } } },
        { "id": 22, "start": 5 * SEC, "duration": 2 * SEC, "curve": "linear",
          "end": { "video": { "x": -100.0 } } }
    ]);
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![clip],
        23,
    ));

    for (t, expected) in [
        (SEC, 0.0),
        (3 * SEC, 150.0),
        (4 * SEC, 300.0),
        (5 * SEC, 300.0),
        (6 * SEC, 100.0),
        (7 * SEC, -100.0),
        (9 * SEC, -100.0),
    ] {
        let x = x_at(&handle, t);
        assert!(
            (x - expected).abs() < 1e-9,
            "x at {t} is {x}, expected {expected}"
        );
    }
}

#[test]
fn a_boolean_switches_only_at_the_action_end() {
    let mut clip = media_clip(11, 2, 0, 10 * SEC, 1);
    clip["actions"] = json!([{
        "id": 21, "start": 2 * SEC, "duration": 2 * SEC, "curve": "linear",
        "end": { "audio": { "muted": true } }
    }]);
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![clip],
        22,
    ));

    let muted_at = |t: i64| flag(&handle.clip_state(11, t).expect("clip 11"), "/audio/muted");
    assert!(!muted_at(0));
    assert!(
        !muted_at(3 * SEC),
        "halfway through, a boolean has not moved"
    );
    assert!(!muted_at(4 * SEC - 1), "one tick before the end");
    assert!(muted_at(4 * SEC), "the switch happens at the action's end");
    assert!(muted_at(9 * SEC));
}

#[test]
fn a_string_switches_only_at_the_action_end() {
    let clip = json!({
        "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
        "source": { "kind": "text" },
        "video": {},
        "text": { "content": "Hello", "align": "center" },
        "actions": [{
            "id": 21, "start": 2 * SEC, "duration": 2 * SEC, "curve": "linear",
            "end": { "text": { "align": "left" } }
        }]
    });
    let handle = Handle::from_value(&project(vec![], vec![track(2)], vec![clip], 22));

    let align_at = |t: i64| -> String {
        let layer = layer_of(&handle.recipe(t), 11);
        assert_eq!(layer["source"]["kind"], json!("text"));
        text(&layer, "/source/text/align").to_string()
    };
    assert_eq!(align_at(0), "center");
    assert_eq!(align_at(3 * SEC), "center", "strings do not interpolate");
    assert_eq!(align_at(4 * SEC - 1), "center");
    assert_eq!(align_at(4 * SEC), "left");

    // The texture cache key follows the description: same text, same hash.
    let hash_at = |t: i64| text(&handle.recipe(t), "/layers/0/source/hash").to_string();
    assert_eq!(hash_at(SEC), hash_at(2 * SEC));
    assert_ne!(
        hash_at(SEC),
        hash_at(5 * SEC),
        "a different description must not share a cached texture"
    );

    // A text clip needs no composition track at all (spec §7.2).
    let plan = handle.plan();
    assert_eq!(plan["video_tracks"], json!([]));
    assert_eq!(
        array(&plan, "/instructions")[0]["required_track_ids"],
        json!([])
    );
}

// ---- layer order, hidden and muted tracks --------------------------------

fn three_track_project() -> Value {
    project(
        vec![video_media(1)],
        vec![track(2), track(3), track(4)],
        vec![
            media_clip(11, 2, 0, 10 * SEC, 1),
            media_clip(12, 3, 0, 10 * SEC, 1),
            media_clip(13, 4, 0, 10 * SEC, 1),
        ],
        14,
    )
}

#[test]
fn layers_are_back_to_front_by_track_index() {
    let handle = Handle::from_value(&three_track_project());
    assert_eq!(layer_ids(&handle.recipe(5 * SEC)), vec![11, 12, 13]);

    // Restacking the timeline restacks the layers: track 4 to the back.
    let restacked = handle.apply(&json!({ "op": "move_track", "track": 4, "index": 0 }));
    assert_eq!(layer_ids(&restacked.recipe(5 * SEC)), vec![13, 11, 12]);
}

#[test]
fn a_hidden_track_draws_nothing_and_a_muted_track_still_draws() {
    let handle = Handle::from_value(&three_track_project());
    let hidden = handle.apply(&json!({ "op": "set_track", "track": 3, "hidden": true }));
    let both = hidden.apply(&json!({ "op": "set_track", "track": 4, "muted": true }));

    assert_eq!(
        layer_ids(&both.recipe(5 * SEC)),
        vec![11, 13],
        "a hidden track contributes no layer; a muted one still does"
    );

    let plan = both.plan();
    // Hiding track 3 frees a decode, so track 4's clip moves to id 2 — and
    // the recipe must name it by the same number.
    assert_eq!(comp_track_ids(&plan, "video_tracks"), vec![1, 2]);
    assert_eq!(
        clip_to_comp_track(&plan, "video_tracks"),
        vec![(11, 1), (13, 2)]
    );
    assert_sources_agree(&plan, &both.recipe(5 * SEC));
    assert_instructions_match_recipe(&both, &plan);

    // Hidden is video only: the hidden track's audio still plays at full
    // volume, while the muted track's is zeroed.
    assert_eq!(comp_track_ids(&plan, "audio_tracks"), vec![101, 102, 103]);
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", 102), "/ramps"),
        &[(0, 10 * SEC, 1.0, 1.0)],
    );
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", 103), "/ramps"),
        &[(0, 10 * SEC, 0.0, 0.0)],
    );
}

// ---- missing media -------------------------------------------------------

#[test]
fn a_clip_whose_media_is_absent_renders_a_slate() {
    // `validate` refuses a clip pointing at a media the project does not
    // hold, so this state cannot be reached through the FFI — it is built
    // here against the library directly to pin the `missing` source kind of
    // spec §7.3, and the refusal is asserted below.
    let mut value =
        Project::new(1920, 1080, Fps { num: 30, den: 1 }).expect("a 1080p30 project is valid");
    let on_track = value.tracks.first().expect("one track").id;
    value.clips.push(Clip {
        id: 11,
        track: on_track,
        start: 0,
        duration: 10 * SEC,
        source: Source::Media { media: 99, r#in: 0 },
        enabled: Enabled::default(),
        speed: 1.0,
        video: Some(VideoProps::default()),
        audio: None,
        text: None,
        shape: None,
        actions: Vec::new(),
        transition_in: None,
    });
    value.next_id = 12;

    let recipe = value.frame_recipe(5 * SEC);
    let layers = array(&recipe, "/layers");
    assert_eq!(layers.len(), 1, "a missing media still draws a slate");
    assert_eq!(layers[0]["source"], json!({ "kind": "missing" }));
    assert_eq!(layers[0]["source_size"], json!(null));

    // It needs no composition track, and the instruction covering it
    // requires none.
    let plan = value.composition_plan();
    assert_eq!(plan["video_tracks"], json!([]));
    assert_tiles(&plan);
    assert_eq!(
        array(&plan, "/instructions")[0]["required_track_ids"],
        json!([])
    );

    // And the FFI will not load such a project in the first place.
    let written = reelcut_core::format::write(&value).expect("writing does not validate");
    let refusal = Handle::try_from_value(&parse_json(&written, "format::write")).err();
    assert_eq!(
        refusal.as_deref(),
        Some("clip 11 refers to unknown media 99"),
        "a dangling media reference must be refused at load"
    );
}

// ---- transitions ---------------------------------------------------------

/// 0..6 s and 5..11 s on one track: a 1 s overlap the later clip calls a
/// push left.
fn transition_project() -> Value {
    let mut later = media_clip(12, 2, 5 * SEC, 6 * SEC, 1);
    later["transition_in"] = json!({ "kind": "push_left" });
    project(
        vec![video_media(1)],
        vec![track(2)],
        vec![media_clip(11, 2, 0, 6 * SEC, 1), later],
        13,
    )
}

#[test]
fn a_transition_puts_both_clips_in_the_recipe() {
    let handle = Handle::from_value(&transition_project());

    // Outside the overlap only one clip draws, with no transition.
    let before = handle.recipe(4 * SEC);
    assert_eq!(layer_ids(&before), vec![11]);
    assert_eq!(layer_of(&before, 11)["transition"], json!(null));

    let inside = handle.recipe(5 * SEC + SEC / 2);
    assert_eq!(
        layer_ids(&inside),
        vec![11, 12],
        "both clips are present and adjacent, earlier first"
    );
    let out = layer_of(&inside, 11);
    let incoming = layer_of(&inside, 12);
    assert_eq!(out["transition"]["kind"], json!("push_left"));
    assert_eq!(incoming["transition"]["kind"], json!("push_left"));
    assert_eq!(out["transition"]["role"], json!("out"));
    assert_eq!(incoming["transition"]["role"], json!("in"));
    assert_eq!(out["transition"]["partner"], json!(12));
    assert_eq!(incoming["transition"]["partner"], json!(11));
    assert!(
        (num(&out, "/transition/progress") - num(&incoming, "/transition/progress")).abs() < EPS,
        "both halves of a pair report one progress"
    );

    // The earlier clip's last tick is past the overlap: at 6 s it is gone.
    let after = handle.recipe(6 * SEC);
    assert_eq!(layer_ids(&after), vec![12]);
    assert_eq!(layer_of(&after, 12)["transition"], json!(null));
}

#[test]
fn transition_progress_runs_from_zero_to_one() {
    let handle = Handle::from_value(&transition_project());
    let start = 5 * SEC;
    let span = SEC;

    let mut previous = -1.0f64;
    for step in [0, SEC / 4, SEC / 2, 3 * SEC / 4, span - 1] {
        let recipe = handle.recipe(start + step);
        let progress = num(&layer_of(&recipe, 12), "/transition/progress");
        let expected = step as f64 / span as f64;
        assert!(
            (progress - expected).abs() < EPS,
            "progress at +{step} is {progress}, expected {expected}"
        );
        assert!(progress > previous, "progress must increase");
        assert!((0.0..1.0).contains(&progress), "progress stays in [0, 1)");
        previous = progress;
    }
    assert!(previous > 0.999, "the last tick of the overlap is near 1");
}

// ---- totality ------------------------------------------------------------

#[test]
fn the_recipe_is_valid_at_every_time() {
    let handle = Handle::from_value(&one_clip_project(10 * SEC));
    let duration = handle.duration();
    assert_eq!(duration, 10 * SEC);

    for t in [i64::MIN, -1, duration, duration + SEC, i64::MAX] {
        let recipe = handle.recipe(t);
        assert_eq!(int(&recipe, "/t"), t, "the recipe echoes its own time");
        assert_eq!(recipe["canvas"]["width"], json!(1920));
        assert_eq!(
            recipe["layers"],
            json!([]),
            "nothing draws at {t} in a project of {duration} ticks"
        );
    }

    // The half-open range: the last tick draws, the duration itself does not.
    assert_eq!(layer_ids(&handle.recipe(duration - 1)), vec![11]);
    assert_eq!(layer_ids(&handle.recipe(0)), vec![11]);

    // And an unknown clip has no state.
    assert!(handle.clip_state(999, 0).is_none());
}

// ---- the inspector agrees with the compositor ----------------------------

#[test]
fn clip_state_matches_the_recipe() {
    let mut clip = media_clip(11, 2, 0, 10 * SEC, 1);
    clip["video"] = json!({ "x": 10.0, "scale": 1.0, "opacity": 1.0 });
    clip["actions"] = json!([
        { "id": 21, "start": 2 * SEC, "duration": 2 * SEC, "curve": "ease_out",
          "end": { "video": { "x": 300.0, "opacity": 0.25 } } },
        { "id": 22, "start": 6 * SEC, "duration": SEC, "curve": "linear",
          "end": { "video": { "scale": 0.5 } } }
    ]);
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![clip],
        23,
    ));

    for t in [
        0,
        SEC,
        3 * SEC,
        4 * SEC,
        5 * SEC,
        6 * SEC + SEC / 2,
        9 * SEC,
    ] {
        let state = handle.clip_state(11, t).expect("clip 11 exists");
        let layer = layer_of(&handle.recipe(t), 11);
        assert_eq!(int(&state, "/t"), t);
        assert_eq!(int(&state, "/clip"), 11);
        for key in ["x", "y", "scale", "rotation", "opacity", "corner_radius"] {
            let from_state = num(&state, &format!("/video/{key}"));
            let from_recipe = num(&layer, &format!("/{key}"));
            assert!(
                (from_state - from_recipe).abs() < EPS,
                "{key} at {t}: inspector {from_state} vs recipe {from_recipe}"
            );
        }
        for key in ["crop", "shadow", "color", "chroma"] {
            assert_eq!(state["video"][key], layer[key], "{key} at {t}");
        }
    }

    // `in_action` is what tells the inspector an edit would set a keyframe.
    let in_action = |t: i64| handle.clip_state(11, t).expect("clip 11")["in_action"].clone();
    assert_eq!(in_action(SEC), json!(null));
    assert_eq!(in_action(3 * SEC), json!(21));
    assert_eq!(in_action(4 * SEC), json!(null), "half-open at the end");
    assert_eq!(in_action(6 * SEC), json!(22));
    assert_eq!(in_action(9 * SEC), json!(null));
}

#[test]
fn a_segment_never_names_source_time_outside_the_file() {
    // `validate` polices ids and spans, not source bounds, so a hand-edited
    // or third-party project can put a clip's `in` — or a still's `at` —
    // outside the media it names. AVFoundation THROWS on an insert whose
    // range starts or ends past an asset, so the plan clamps both ends into
    // the file: what was an unbuildable composition becomes a stretch of
    // the last frame, which renders.
    //
    // The fixture media is 60 s at 30 fps, so the last representable source
    // tick is 60*600000 - 1 = 35999999 and the last whole frame starts at
    // 60*600000 - 20000 = 35980000.
    let last_tick = 60 * SEC - 1;
    let last_frame = 60 * SEC - FRAME_30;

    let over = |source: Value| -> Value {
        let mut clip = media_clip(11, 2, 0, 4 * SEC, 1);
        clip["source"] = source;
        let handle = Handle::from_value(&project(
            vec![video_media(1)],
            vec![track(2)],
            vec![clip],
            12,
        ));
        segment_of(&handle.plan(), "video_tracks", 11)
    };

    // An `in` past the end of the file.
    let segment = over(json!({ "kind": "media", "media": 1, "in": 90 * SEC }));
    assert_eq!(int(&segment, "/source_in"), last_tick);
    assert_eq!(
        int(&segment, "/source_duration"),
        1,
        "one tick is all that is left, and an empty range is rejected"
    );

    // A negative `in`, which would make the insert start before the asset.
    let segment = over(json!({ "kind": "media", "media": 1, "in": -5 * SEC }));
    assert_eq!(int(&segment, "/source_in"), 0);
    assert_eq!(int(&segment, "/source_duration"), 4 * SEC);

    // A still's frozen frame, which needs a whole source frame to fit.
    let segment = over(json!({ "kind": "still", "media": 1, "at": 90 * SEC }));
    assert_eq!(int(&segment, "/source_in"), last_frame);
    assert_eq!(int(&segment, "/source_duration"), FRAME_30);

    let segment = over(json!({ "kind": "still", "media": 1, "at": -1 }));
    assert_eq!(int(&segment, "/source_in"), 0);

    // An in-point INSIDE the file is untouched — the clamp must not move a
    // legitimate source range.
    let segment = over(json!({ "kind": "media", "media": 1, "in": 10 * SEC }));
    assert_eq!(int(&segment, "/source_in"), 10 * SEC);
    assert_eq!(int(&segment, "/source_duration"), 4 * SEC);
}

/// An action's `end` patch is deliberately lenient — `set_action_end` merges
/// whatever it is handed — so the evaluator is the last line of defence
/// before a value reaches the Metal compositor's uniform block. It bounds
/// every evaluated field to the same table `edit_props.rs` enforces on a
/// direct edit, and collapses a NaN to the neutral value rather than
/// propagating it (one NaN blanks a whole frame).
///
/// The patch here is written straight into the project JSON, which is the
/// only way to produce it: `set_action_end` would accept these values too,
/// but going through the file proves an opened project cannot poison the
/// renderer either.
#[test]
fn an_out_of_range_action_patch_is_clamped_before_it_reaches_the_recipe() {
    let mut clip = media_clip(11, 2, 0, 6_000_000, 1);
    clip["actions"] = json!([{
        "id": 3, "start": 0, "duration": 3_000_000, "curve": "linear",
        "end": { "video": { "opacity": 5.0, "scale": 1.0e6, "corner_radius": -40.0 },
                 "audio": { "volume": 99.0 } }
    }]);
    let handle = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![clip],
        12,
    ));

    // At the action's end the patch is fully applied — the worst case.
    let layer = layer_of(&handle.recipe(3_000_000), 11);
    assert_eq!(num(&layer, "/opacity"), 1.0, "opacity must clamp to 1");
    assert_eq!(num(&layer, "/scale"), 10.0, "scale must clamp to SCALE_MAX");
    assert_eq!(
        num(&layer, "/corner_radius"),
        0.0,
        "a negative corner radius must clamp to 0"
    );

    let state = handle
        .clip_state(11, 3_000_000)
        .expect("clip_state for a live clip");
    assert_eq!(num(&state, "/audio/volume"), 4.0, "gain must clamp to 4");
    assert_eq!(num(&state, "/video/opacity"), 1.0);

    // Halfway through, interpolation is toward the UNCLAMPED target, so the
    // midpoint is also out of range and must be clamped the same way.
    let mid = layer_of(&handle.recipe(1_500_000), 11);
    assert!(
        num(&mid, "/opacity") <= 1.0 && num(&mid, "/opacity") >= 0.0,
        "an interpolated opacity must stay in 0..1, got {}",
        num(&mid, "/opacity")
    );
    assert!(
        num(&mid, "/scale") <= 10.0,
        "an interpolated scale must stay at or under SCALE_MAX"
    );
}
