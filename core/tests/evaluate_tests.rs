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

use common::{array, at, flag, int, num, parse_json, text, Handle};
use reelcut_core::model::Project;
use reelcut_core::{Clip, Enabled, Fps, Source, VideoProps};

// ---- the oracle's own constants ------------------------------------------

/// Ticks per second (spec §5.1). Written out here rather than imported, so a
/// change to `time::TIMESCALE` fails these tests instead of moving with them.
const SEC: i64 = 600_000;

/// One frame at the fixtures' canvas rate of 30 fps.
const FRAME_30: i64 = SEC / 30;

/// The first composition AUDIO track id (spec §7.2). Written out here
/// rather than imported for the same reason `SEC` is: a change to
/// `evaluate.rs`'s range has to fail these tests, not move with them.
const FIRST_AUDIO: i64 = 1001;

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
    assert_eq!(
        comp_track_ids(&plan, "audio_tracks"),
        vec![FIRST_AUDIO, FIRST_AUDIO + 1]
    );
    assert_eq!(
        clip_to_comp_track(&plan, "video_tracks"),
        vec![(11, 1), (12, 2)]
    );
    assert_eq!(
        clip_to_comp_track(&plan, "audio_tracks"),
        vec![(11, FIRST_AUDIO), (12, FIRST_AUDIO + 1)]
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
    assert_eq!(comp_track_ids(&plan, "audio_tracks"), vec![FIRST_AUDIO]);
    let starts: Vec<i64> = array(comp_track(&plan, "video_tracks", 1), "/segments")
        .iter()
        .map(|s| int(s, "/start"))
        .collect();
    assert_eq!(starts, vec![0, 2 * SEC, 4 * SEC], "segments in start order");
    assert_eq!(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/segments").len(),
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
    assert_eq!(
        comp_track_ids(&first, "audio_tracks"),
        vec![FIRST_AUDIO, FIRST_AUDIO + 1, FIRST_AUDIO + 2]
    );
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
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps"),
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

    let comp = comp_track(&plan, "audio_tracks", FIRST_AUDIO);
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
    let silenced_comp = comp_track(&silenced_plan, "audio_tracks", FIRST_AUDIO);
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

    assert_eq!(
        comp_track_ids(&plan, "audio_tracks"),
        vec![FIRST_AUDIO, FIRST_AUDIO + 1]
    );
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps"),
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
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO + 1), "/ramps"),
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

    let comp = comp_track(&plan, "audio_tracks", FIRST_AUDIO);
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
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps"),
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
    let ramps = array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps");

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

// ---- text animations: the computed reveal --------------------------------
//
// `text.animation` says what the animation IS (format version 5, and
// `schema_v5.rs` owns its shape and its ranges); the recipe says what is
// SHOWING at one instant — `source.reveal`, 0 through 1, `source.reveal_phase`,
// "in", "out" or null, and `source.reveal_kind`, which of the three routines
// is drawing. Everything that draws a frame reads that one description, so
// this is the only place the arithmetic exists and the only place it can be
// asserted: no MCP tool returns a recipe, and the pixels are the platform's.
//
// Every number below is the ramp rule done on paper against tick counts
// chosen to come out exactly in binary floating point.

/// A 10 s text clip on track 2, `animation` spliced into its text group when
/// it is not null. The text group is spelled out rather than defaulted so
/// the description the hash is taken over is one this file can write down.
fn text_clip(id: u32, start: i64, duration: i64, animation: Value) -> Value {
    let mut clip = json!({
        "id": id,
        "track": 2,
        "start": start,
        "duration": duration,
        "source": { "kind": "text" },
        "video": {},
        "text": { "content": "Hello" }
    });
    if !animation.is_null() {
        clip["text"]["animation"] = animation;
    }
    clip
}

/// A typewriter that arrives over `arrive` and leaves over `leave`. The
/// AMOUNT is the same arithmetic for all three kinds — the core computes one
/// number and the renderer decides what to draw with it — so the ramp tests
/// below all use this one and say so; the kind matters only where it is
/// asserted directly.
fn typewriter(arrive: i64, leave: i64) -> Value {
    json!({ "kind": "typewriter", "in": arrive, "out": leave })
}

/// The same timings under a different kind, for the claims that are about
/// the kind rather than the ramp.
fn word_fade(arrive: i64, leave: i64) -> Value {
    json!({ "kind": "word_fade", "in": arrive, "out": leave })
}

/// One text clip, alone, at `start`.
fn text_project(clip: Value, next_id: u32) -> Handle {
    Handle::from_value(&project(vec![], vec![track(2)], vec![clip], next_id))
}

/// The reveal and its phase on clip `id`'s layer at project time `t`.
fn reveal_of(handle: &Handle, id: i64, t: i64) -> (f64, Value) {
    let layer = layer_of(&handle.recipe(t), id);
    assert_eq!(layer["source"]["kind"], json!("text"));
    (
        num(&layer, "/source/reveal"),
        at(&layer, "/source/reveal_phase").clone(),
    )
}

/// The reveal's kind on clip `id`'s layer at project time `t`.
fn reveal_kind_of(handle: &Handle, id: i64, t: i64) -> Value {
    at(&layer_of(&handle.recipe(t), id), "/source/reveal_kind").clone()
}

/// The texture cache key on clip `id`'s layer at project time `t`.
fn hash_of(handle: &Handle, id: i64, t: i64) -> String {
    text(&layer_of(&handle.recipe(t), id), "/source/hash").to_string()
}

/// FNV-1a, 64-bit, hex — the algorithm `recipe.rs` documents, written out
/// again here because an oracle that imported the implementation would only
/// prove the implementation equals itself. The claim it serves is that the
/// hash is taken over a description this test can spell out in full.
fn fnv1a_hex(bytes: &[u8]) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!("{hash:016x}")
}

/// [`text_clip`]'s text group, serialized exactly as a core WITHOUT
/// `text.animation` wrote it: every field of `TextProps` at its default but
/// `content`, keys in the order `serde_json` puts a map in — sorted, since
/// the crate does not enable `preserve_order`.
///
/// This literal is the whole of the byte-identity claim. It was written from
/// the struct, not copied from a run.
const DESCRIPTION_BEFORE_VERSION_5: &str = concat!(
    r#"{"align":"center","backdrop":null,"color":[1.0,1.0,1.0,1.0],"#,
    r#""content":"Hello","font":"SourceSans3-SemiBold","line_spacing":1.0,"#,
    r#""outline":null,"size":72.0,"tracking":0.0,"valign":"middle","width":null}"#
);

#[test]
fn an_unanimated_text_layer_shows_all_of_itself_and_hashes_as_it_always_did() {
    let handle = text_project(text_clip(11, 0, 10 * SEC, Value::Null), 12);

    // All three keys are emitted whether the clip animates or not: an absent
    // one would mean two things — no animation here, or an older core that
    // never computed a reveal — which is the argument `obscure` settled. The
    // two nulls travel together, and the amount is then 1.
    for t in [0, 5 * SEC] {
        assert_eq!(reveal_of(&handle, 11, t), (1.0, json!(null)));
        assert_eq!(reveal_kind_of(&handle, 11, t), json!(null));
    }

    // The description carries no `animation` key at all, so a renderer has
    // exactly one account of the animation: the computed reveal.
    let layer = layer_of(&handle.recipe(0), 11);
    assert_eq!(
        at(&layer, "/source/text").get("animation"),
        None,
        "the recipe must not carry the animation field itself"
    );

    // The byte-identity claim: an unanimated clip's cache key is the hash of
    // the description a version-4 core wrote, to the byte, so no shipped
    // project's texture cache behaves differently after this phase.
    assert_eq!(
        hash_of(&handle, 11, 0),
        fnv1a_hex(DESCRIPTION_BEFORE_VERSION_5.as_bytes()),
        "the hash of an unanimated text layer is the hash of its bare description"
    );
    assert_eq!(hash_of(&handle, 11, 0), hash_of(&handle, 11, 5 * SEC));

    // And no other source kind grows the keys — they live inside the text
    // source, where the kind-specific description is, not on the layer.
    let media = Handle::from_value(&one_clip_project(10 * SEC));
    let source = at(&layer_of(&media.recipe(SEC), 11), "/source").clone();
    assert_eq!(source.get("reveal"), None);
    assert_eq!(source.get("reveal_phase"), None);
    assert_eq!(source.get("reveal_kind"), None);
}

#[test]
fn the_kind_travels_with_the_reveal_and_is_part_of_the_cache_key() {
    // The description no longer carries `animation`, so `reveal_kind` is the
    // renderer's only word for WHICH routine to run — each of the three is a
    // different drawing routine, not a parameter of a shared one.
    let typed = text_project(text_clip(11, 0, 10 * SEC, typewriter(4 * SEC, 0)), 12);
    let faded = text_project(text_clip(11, 0, 10 * SEC, word_fade(4 * SEC, 0)), 12);

    assert_eq!(reveal_kind_of(&typed, 11, SEC), json!("typewriter"));
    assert_eq!(reveal_kind_of(&faded, 11, SEC), json!("word_fade"));

    // Same text, same amount, same phase, different picture — so the two
    // must not share a cached texture either.
    assert_eq!(reveal_of(&typed, 11, SEC), reveal_of(&faded, 11, SEC));
    assert_ne!(
        hash_of(&typed, 11, SEC),
        hash_of(&faded, 11, SEC),
        "two kinds half done are two pictures and cannot share a texture"
    );
}

#[test]
fn the_reveal_runs_from_nothing_at_the_first_frame_to_all_of_it_at_in() {
    // Two seconds of typewriter on a clip that starts at 3 s, so the test
    // also fails if the ramp is measured from project time rather than from
    // the clip's own first frame.
    let start = 3 * SEC;
    let handle = text_project(text_clip(11, start, 10 * SEC, typewriter(2 * SEC, 0)), 12);

    assert_eq!(
        reveal_of(&handle, 11, start),
        (0.0, json!("in")),
        "nothing is showing on the clip's first frame"
    );
    assert_eq!(reveal_of(&handle, 11, start + SEC), (0.5, json!("in")));

    // One tick short of the arrival it is not there yet: 1_199_999/1_200_000.
    let (nearly, _) = reveal_of(&handle, 11, start + 2 * SEC - 1);
    assert!(
        nearly < 1.0 && nearly > 0.999_999,
        "one tick before `in` the reveal is not yet complete, got {nearly}"
    );

    assert_eq!(
        reveal_of(&handle, 11, start + 2 * SEC),
        (1.0, json!("in")),
        "the reveal is complete exactly at `in`"
    );
    // `out` is 0, so the text never leaves: it stays whole to the last frame.
    assert_eq!(reveal_of(&handle, 11, start + 5 * SEC), (1.0, json!("in")));
    assert_eq!(
        reveal_of(&handle, 11, start + 10 * SEC - FRAME_30),
        (1.0, json!("in"))
    );
}

#[test]
fn the_un_reveal_runs_back_from_the_clips_own_last_frame() {
    // No arrival at all and a two-second departure. A zero-length phase is
    // complete from the first frame rather than a division by zero.
    let start = 3 * SEC;
    let handle = text_project(text_clip(11, start, 10 * SEC, typewriter(0, 2 * SEC)), 12);

    assert_eq!(
        reveal_of(&handle, 11, start),
        (1.0, json!("in")),
        "an arrival of zero is over before the first frame is drawn"
    );
    assert_eq!(
        reveal_of(&handle, 11, start + 8 * SEC),
        (1.0, json!("in")),
        "the departure has not bitten yet at exactly `duration - out`"
    );
    assert_eq!(
        reveal_of(&handle, 11, start + 9 * SEC),
        (0.5, json!("out")),
        "one second left of a two-second departure: half gone, and the phase has turned"
    );

    // The departure is measured back from the clip's EXCLUSIVE end, so it
    // reaches 0 one tick past the last tick anybody draws: 1/1_200_000.
    let (last, phase) = reveal_of(&handle, 11, start + 10 * SEC - 1);
    assert_eq!(phase, json!("out"));
    assert!(
        last > 0.0 && last < 1e-6,
        "the last tick of an un-revealing clip still shows a sliver, got {last}"
    );
}

/// One nest clip (id 3) at 2 s for 3 s over a nest (id 4) whose own track
/// carries a 10 s animated text clip (id 11) at its time 0. The nest clip is
/// deliberately SHORTER than what is inside it, so the inner clip is visible
/// for 2 s – 5 s of project time and its own last 7 s are never drawn.
fn nested_text(animation: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 2,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0.0, 0.0, 0.0, 1.0],
            "fit_new_clips": true, "timecode_frames": true
        },
        "media": [],
        "tracks": [track(2)],
        "clips": [{
            "id": 3, "track": 2, "start": 2 * SEC, "duration": 3 * SEC,
            "source": { "kind": "nest", "project": 4 },
            "video": {}
        }],
        "markers": [],
        "next_id": 12,
        "nests": [{
            "id": 4, "name": "Nest 4", "width": 1920, "height": 1080,
            "tracks": [track(5)],
            "clips": [{
                "id": 11, "track": 5, "start": 0, "duration": 10 * SEC,
                "source": { "kind": "text" },
                "video": {},
                "text": { "content": "Hello", "animation": animation }
            }]
        }]
    }))
}

#[test]
fn a_nested_text_clip_animates_on_its_own_clock() {
    // Four seconds each way on a clip whose enclosing nest clip only shows
    // its first three. Measured against the INSTANCE this would read 0.25 on
    // the way out at the same instant, so the assertion below is the one
    // that tells the two clocks apart.
    let handle = nested_text(typewriter(4 * SEC, 4 * SEC));

    assert_eq!(
        reveal_of(&handle, 11, 4 * SEC),
        (0.5, json!("in")),
        "two seconds into a four-second arrival, still arriving"
    );

    // The last frame the nest clip lets through is 3 s − one frame into the
    // inner clip: 1_780_000 / 2_400_000, still on the way in. A nest clip's
    // edge cuts a caption off mid-reveal rather than making it leave early.
    let (cut_off, phase) = reveal_of(&handle, 11, 5 * SEC - FRAME_30);
    assert_eq!(phase, json!("in"));
    assert!(
        (cut_off - 1_780_000.0 / 2_400_000.0).abs() < EPS,
        "the reveal at the nest clip's last frame is the clip's own, got {cut_off}"
    );

    // And the instance is gone at the nest clip's end, mid-animation.
    assert_eq!(array(&handle.recipe(5 * SEC), "/layers").len(), 0);
}

#[test]
fn two_phases_longer_than_the_clip_make_a_tent_rather_than_a_refusal() {
    // Eight seconds each way on a ten-second clip. The reveal is the minimum
    // of the two ramps, so it degrades to a tent that never reaches 1 — no
    // refusal, no clamp, and a clip trimmed under an animation that used to
    // fit simply shows a partial reveal.
    let handle = text_project(text_clip(11, 0, 10 * SEC, typewriter(8 * SEC, 8 * SEC)), 12);

    assert_eq!(reveal_of(&handle, 11, 4 * SEC), (0.5, json!("in")));
    assert_eq!(
        reveal_of(&handle, 11, 5 * SEC),
        (0.625, json!("in")),
        "the peak: 5/8 either way, and a tie belongs to the arrival"
    );
    assert_eq!(
        reveal_of(&handle, 11, 6 * SEC),
        (0.5, json!("in")),
        "past the peak the departure holds the amount back, but the WORD does \
         not turn: a tent that never arrived cannot begin to leave"
    );

    // Whatever the numbers, the amount stays inside 0..1 on every frame the
    // clip is drawn — the property that lets the renderer treat it as an
    // alpha without checking it.
    let mut frame = 0;
    while frame < 10 * SEC {
        let (amount, phase) = reveal_of(&handle, 11, frame);
        assert!(
            (0.0..=1.0).contains(&amount),
            "the reveal at {frame} is {amount}, outside 0..1"
        );
        assert!(phase == json!("in") || phase == json!("out"));
        frame += FRAME_30;
    }
}

#[test]
fn the_phase_turns_only_where_both_orders_draw_the_same_picture() {
    // The phase is the ORDER the renderer staggers by — `staggerIndex`
    // counts a word_fade's words and a line_rise's lines from the other end
    // while a layer is leaving — so the frame on which the word turns is a
    // frame on which the picture MIRRORS end for end. The only amount at
    // which that mirror is invisible is 1, where every item is whole
    // whichever end the count started from.
    //
    // So: on every frame of every timing, if the phase differs from the
    // previous frame's, the previous frame was fully revealed. Without it a
    // tent turns at its peak and a four-word cue swaps [1, 1, .83, .33] for
    // [.33, .83, 1, 1] in one frame, at an amount that did not change.
    //
    // The pairs below are frame-aligned on purpose: the plateau of a fitting
    // animation is `[in, duration - out]`, and a frame lands on its far end
    // only if `duration - out` is on the grid, which is the arithmetic the
    // claim is about rather than a fact about these numbers.
    const DURATION: i64 = 10 * SEC;
    let timings = [
        (2 * SEC, 2 * SEC),   // fits, with a plateau in the middle
        (5 * SEC, 5 * SEC),   // fits exactly: the plateau is one instant
        (0, 3 * SEC),         // a departure only
        (3 * SEC, 0),         // an arrival only
        (8 * SEC, 8 * SEC),   // a tent, crossing at 0.625
        (9 * SEC, 4 * SEC),   // a lopsided tent, crossing on the way up
        (4 * SEC, 9 * SEC),   // and the other way about
        (0, 15 * SEC),        // longer than the clip, and nothing but leaving
        (15 * SEC, 0),        // longer than the clip, and nothing but arriving
        (FRAME_30, FRAME_30), // one frame each way, the shortest that draws
    ];

    for (arrive, leave) in timings {
        let handle = text_project(text_clip(11, 0, DURATION, word_fade(arrive, leave)), 12);
        let mut previous: Option<(f64, Value)> = None;
        let mut frame = 0;
        while frame < DURATION {
            let (amount, phase) = reveal_of(&handle, 11, frame);
            if let Some((was_amount, was_phase)) = previous {
                if was_phase != phase {
                    assert_eq!(
                        was_amount, 1.0,
                        "in {arrive}/{leave} the phase turned at {frame}, from \
                         {was_phase} to {phase}, with the frame before it at \
                         {was_amount}: the words mirror on a picture that is \
                         not whole"
                    );
                }
            }
            previous = Some((amount, phase));
            frame += FRAME_30;
        }
    }
}

#[test]
fn a_tent_that_is_all_departure_still_reports_itself_leaving() {
    // A tent holds the phase it began in, and an arrival of zero begins in
    // the departure: an `out` longer than the whole clip is a caption that
    // starts half gone and goes, with no arrival order for the stagger to
    // contradict. Reading this one as "in" would run its words out
    // last-first — the fix for the tent must not silence a departure.
    let handle = text_project(text_clip(11, 0, 10 * SEC, word_fade(0, 20 * SEC)), 12);

    assert_eq!(
        reveal_of(&handle, 11, 0),
        (0.5, json!("out")),
        "half the departure is already spent on the clip's first frame"
    );
    assert_eq!(reveal_of(&handle, 11, 5 * SEC), (0.25, json!("out")));
}

#[test]
fn the_hash_follows_the_reveal_so_no_frame_can_reuse_a_stale_texture() {
    // The layer's hash is the only thing standing between a per-frame value
    // and a stale texture: Swift caches a rendered paragraph under
    // "text:" + hash and consults nothing else, so two frames that draw
    // different pictures must not share a key.
    let handle = text_project(text_clip(11, 0, 10 * SEC, typewriter(4 * SEC, 4 * SEC)), 12);

    assert_ne!(
        hash_of(&handle, 11, SEC),
        hash_of(&handle, 11, 2 * SEC),
        "two amounts inside one ramp must not share a cached texture"
    );

    // ... and the DESCRIPTION is identical at those two instants, which is
    // why the hash cannot be taken over the description alone.
    let description = |t: i64| at(&layer_of(&handle.recipe(t), 11), "/source/text").clone();
    assert_eq!(description(SEC), description(2 * SEC));

    // The same amount in the two different phases is two different pictures
    // — a typewriter typing is not one un-typing — so the phase is in the
    // key too. Both of these are 0.5.
    assert_eq!(
        num(&layer_of(&handle.recipe(2 * SEC), 11), "/source/reveal"),
        0.5
    );
    assert_eq!(
        num(&layer_of(&handle.recipe(8 * SEC), 11), "/source/reveal"),
        0.5
    );
    assert_ne!(
        hash_of(&handle, 11, 2 * SEC),
        hash_of(&handle, 11, 8 * SEC),
        "an arriving half and a departing half must not share a cached texture"
    );

    // Nothing changes for the whole middle of a clip that has arrived and is
    // not yet leaving, so a fully revealed frame costs one cache entry, not
    // one per frame.
    let still = text_project(text_clip(11, 0, 10 * SEC, typewriter(2 * SEC, 0)), 12);
    assert_eq!(hash_of(&still, 11, 5 * SEC), hash_of(&still, 11, 6 * SEC));

    // An animated layer keeps its own key even when it is fully revealed:
    // whether a full reveal draws exactly what no animation draws is the
    // renderer's promise, and a cache key does not lean on one.
    let plain = text_project(text_clip(11, 0, 10 * SEC, Value::Null), 12);
    assert_ne!(hash_of(&still, 11, 5 * SEC), hash_of(&plain, 11, 5 * SEC));
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
    assert_eq!(
        comp_track_ids(&plan, "audio_tracks"),
        vec![FIRST_AUDIO, FIRST_AUDIO + 1, FIRST_AUDIO + 2]
    );
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO + 1), "/ramps"),
        &[(0, 10 * SEC, 1.0, 1.0)],
    );
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO + 2), "/ramps"),
        &[(0, 10 * SEC, 0.0, 0.0)],
    );
}

// ---- solo ----------------------------------------------------------------

/// Sets a track flag the way a FILE carries it, on the track at `index`.
/// A fixture edit rather than a `set_track` op, so two variants of one base
/// share every id and every track position and their plans compare as text.
fn set_track_flag(project: &mut Value, index: usize, flag: &str) {
    project["tracks"][index][flag] = json!(true);
}

#[test]
fn a_soloed_track_silences_every_other_track_and_nothing_else() {
    // Track 3 soloed among three. By hand: tracks 2 and 4 are treated as
    // muted — a zero envelope over their clips' extent — and track 3 plays
    // exactly as it did. Every segment stays, since a solo is an envelope
    // and never a rebuild (spec §7.2).
    let base = Handle::from_value(&three_track_project()).plan();
    let mut soloed = three_track_project();
    set_track_flag(&mut soloed, 1, "solo");
    let handle = Handle::from_value(&soloed);
    let plan = handle.plan();

    assert_eq!(
        comp_track_ids(&plan, "audio_tracks"),
        vec![FIRST_AUDIO, FIRST_AUDIO + 1, FIRST_AUDIO + 2]
    );
    for id in [FIRST_AUDIO, FIRST_AUDIO + 1, FIRST_AUDIO + 2] {
        assert_eq!(
            array(comp_track(&plan, "audio_tracks", id), "/segments").len(),
            1,
            "a solo keeps every segment: un-soloing must not rebuild"
        );
    }
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps"),
        &[(0, 10 * SEC, 0.0, 0.0)],
    );
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO + 1), "/ramps"),
        &[(0, 10 * SEC, 1.0, 1.0)],
    );
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO + 2), "/ramps"),
        &[(0, 10 * SEC, 0.0, 0.0)],
    );
    // The soloed track's own envelope is what it was without the solo.
    assert_eq!(
        comp_track(&plan, "audio_tracks", FIRST_AUDIO + 1)["ramps"],
        comp_track(&base, "audio_tracks", FIRST_AUDIO + 1)["ramps"]
    );

    // Audio only: every layer still draws, and the picture side of the plan
    // is untouched.
    assert_eq!(layer_ids(&handle.recipe(5 * SEC)), vec![11, 12, 13]);
    assert_eq!(plan["video_tracks"], base["video_tracks"]);
    assert_eq!(plan["instructions"], base["instructions"]);
}

#[test]
fn a_track_that_is_both_muted_and_soloed_is_silent() {
    // Mute wins. Track 3 carries both flags: its mute silences it, and its
    // solo silences tracks 2 and 4 — all three are zero, segments intact.
    let mut both = three_track_project();
    set_track_flag(&mut both, 1, "muted");
    set_track_flag(&mut both, 1, "solo");
    let plan = Handle::from_value(&both).plan();

    for id in [FIRST_AUDIO, FIRST_AUDIO + 1, FIRST_AUDIO + 2] {
        let comp = comp_track(&plan, "audio_tracks", id);
        assert_eq!(array(comp, "/segments").len(), 1);
        assert_ramps(array(comp, "/ramps"), &[(0, 10 * SEC, 0.0, 0.0)]);
    }
}

#[test]
fn a_solo_on_a_track_with_nothing_audible_still_silences_the_others() {
    // The rule is on the track SET, not on what plays: track 3 holds one
    // clip of a silent movie, and soloing it mutes the two tracks that do
    // have sound. Clip 12 gets no audio segment at all, so the two
    // composition audio tracks are track 2's and track 4's. (Media 5: the
    // project has one id space, and 2 is the first track's.)
    let silent_movie = media(5, "video", 60 * SEC, [30, 1], true, false);
    let mut value = project(
        vec![video_media(1), silent_movie],
        vec![track(2), track(3), track(4)],
        vec![
            media_clip(11, 2, 0, 10 * SEC, 1),
            media_clip(12, 3, 0, 10 * SEC, 5),
            media_clip(13, 4, 0, 10 * SEC, 1),
        ],
        14,
    );
    set_track_flag(&mut value, 1, "solo");
    let handle = Handle::from_value(&value);
    let plan = handle.plan();

    assert_eq!(
        clip_to_comp_track(&plan, "audio_tracks"),
        vec![(11, FIRST_AUDIO), (13, FIRST_AUDIO + 1)]
    );
    for id in [FIRST_AUDIO, FIRST_AUDIO + 1] {
        assert_ramps(
            array(comp_track(&plan, "audio_tracks", id), "/ramps"),
            &[(0, 10 * SEC, 0.0, 0.0)],
        );
    }
    // The silent movie still draws: solo is a mixing word.
    assert_eq!(layer_ids(&handle.recipe(5 * SEC)), vec![11, 12, 13]);
}

#[test]
fn soloing_one_track_is_the_same_plan_as_muting_every_other() {
    // Two documents from ONE base, so every id and every track position
    // agrees and the plans compare as the bytes Swift compares (spec §7.6):
    // "solo track 3" and "mute tracks 2 and 4" must be one plan, or the app
    // would build two different audio mixes for one mix.
    let mut soloed = three_track_project();
    set_track_flag(&mut soloed, 1, "solo");
    let mut others_muted = three_track_project();
    set_track_flag(&mut others_muted, 0, "muted");
    set_track_flag(&mut others_muted, 2, "muted");
    let soloed = Handle::from_value(&soloed);
    let others_muted = Handle::from_value(&others_muted);

    assert_eq!(soloed.plan_text(), others_muted.plan_text());

    // And that plan is neither "everything silent" nor the base's: the
    // track in question plays and the equality is not vacuous.
    let plan = soloed.plan();
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO + 1), "/ramps"),
        &[(0, 10 * SEC, 1.0, 1.0)],
    );
    assert_ramps(
        array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps"),
        &[(0, 10 * SEC, 0.0, 0.0)],
    );
    assert_ne!(
        soloed.plan_text(),
        Handle::from_value(&three_track_project()).plan_text()
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
        source: Source::Media {
            media: 99,
            r#in: 0,
            reversed: false,
        },
        enabled: Enabled::default(),
        speed: 1.0,
        video: Some(VideoProps::default()),
        audio: None,
        text: None,
        shape: None,
        actions: Vec::new(),
        transition_in: None,
        name: None,
        label: None,
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
/// every evaluated field to the same table `props_check.rs` enforces on a
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
