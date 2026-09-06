//! Black-box tests for nests: the two grouping ops (`nest`, `unnest`) and
//! what a nest does to the composition plan, the frame recipe and the audio
//! envelope — driven through the C FFI exactly as `ReelCore.swift` drives
//! them.
//!
//! `schema_v2.rs` owns the SHAPE of a nest (what `validate` refuses, what the
//! caps count, what a version-1 file migrates to). This file owns its
//! BEHAVIOUR, and the oracles are written out by hand here rather than
//! recorded: every expected placement, transform and gain below is the spec
//! §5.3 / §7.2 / §7.3 rule applied on paper to numbers chosen to come out
//! exactly in binary floating point.
//!
//! Three claims run through it, and they are the ones the whole feature
//! rests on:
//!
//! - **A nest clip is one clip and many layers.** It never draws itself; the
//!   clips inside it draw, in the slot the nest clip occupies, with its
//!   transform folded into each of them and its canvas rect as their
//!   `clip_rect`.
//! - **The plan and the recipe still agree.** A nested media clip gets a
//!   real composition track, the recipe names that same track, and the
//!   instruction tiling has a boundary at every INNER clip edge — without
//!   which a span's first tick would not describe the rest of it.
//! - **`nest` then `unnest` is the identity on clip content**, ids aside.
//!   That is asserted by comparing the clips before and after with their ids
//!   stripped, not by trusting either op's own account of itself.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, at, by_id, flag, int, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with them.
const SEC: i64 = 600_000;

/// The first composition audio track id (spec §7.2).
const FIRST_AUDIO: i64 = 1001;

/// Slack for the folded transform. The fold is two multiplies and an add on
/// values chosen to be exact in binary floating point; all this absorbs is
/// `cos(90°)`, which is 6e-17 rather than 0.
const EPS: f64 = 1e-9;

// ---- fixtures ------------------------------------------------------------

/// 60 s of 1920x1080 at 30 fps with sound.
fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn track(id: u32) -> Value {
    json!({ "id": id, "name": format!("Track {id}") })
}

fn media_clip(id: u32, on: u32, start: i64, duration: i64, media: u32) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "media", "media": media, "in": 0 },
        "video": {}, "audio": {}
    })
}

fn text_clip(id: u32, on: u32, start: i64, duration: i64) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "text" }, "video": {}, "text": { "content": "Inside" }
    })
}

fn nest_clip(id: u32, on: u32, start: i64, duration: i64, shows: u32) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "nest", "project": shows }, "video": {}
    })
}

fn nest(id: u32, tracks: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "id": id, "name": format!("Nest {id}"), "width": 1920, "height": 1080,
        "tracks": tracks, "clips": clips
    })
}

fn project(
    media: Vec<Value>,
    tracks: Vec<Value>,
    clips: Vec<Value>,
    nests: Vec<Value>,
    next_id: u32,
) -> Value {
    json!({
        "version": 2,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": media, "tracks": tracks, "clips": clips, "markers": [],
        "next_id": next_id, "nests": nests
    })
}

/// One timeline track holding a nest clip at 3 s for 4 s, over a nest whose
/// own track carries one media clip at 1 s for 2 s. The inner clip therefore
/// plays 4 s – 6 s of project time.
fn nested_media() -> Handle {
    Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 3 * SEC, 4 * SEC, 4)],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(6, 5, SEC, 2 * SEC, 1)],
        )],
        7,
    ))
}

/// Two clips on two tracks, 0 – 2 s and 1 s – 4 s, for the grouping ops.
fn two_tracks() -> Handle {
    Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3)],
        vec![
            media_clip(4, 2, 0, 2 * SEC, 1),
            text_clip(5, 3, SEC, 3 * SEC),
        ],
        vec![],
        6,
    ))
}

// ---- reading a plan and a recipe -----------------------------------------

fn comp_track<'a>(plan: &'a Value, group: &str, id: i64) -> &'a Value {
    array(plan, &format!("/{group}"))
        .iter()
        .find(|t| int(t, "/id") == id)
        .unwrap_or_else(|| panic!("no {group} entry with id {id} in {plan}"))
}

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

fn layer_of(recipe: &Value, clip: i64) -> Value {
    array(recipe, "/layers")
        .iter()
        .find(|l| int(l, "/clip") == clip)
        .unwrap_or_else(|| panic!("no layer for clip {clip} in {recipe}"))
        .clone()
}

fn layer_ids(recipe: &Value) -> Vec<i64> {
    array(recipe, "/layers")
        .iter()
        .map(|l| int(l, "/clip"))
        .collect()
}

fn close(actual: f64, expected: f64, what: &str) {
    assert!(
        (actual - expected).abs() < EPS,
        "{what}: expected {expected}, got {actual}"
    );
}

/// A clip with everything that names an id stripped out — what "the same
/// clips" means across a `nest` / `unnest` round trip, where every id is
/// re-minted and the tracks are new objects.
fn content(clip: &Value) -> Value {
    let mut out = clip.clone();
    let object = out.as_object_mut().expect("a clip is an object");
    object.remove("id");
    object.remove("track");
    if let Some(actions) = object.get_mut("actions").and_then(Value::as_array_mut) {
        for action in actions {
            if let Some(entry) = action.as_object_mut() {
                entry.remove("id");
            }
        }
    }
    out
}

/// Every clip's content, ordered by start then by the track INDEX it sits
/// on, so two projects compare equal only if their stacking agrees too.
fn contents(project: &Value) -> Vec<(i64, usize, Value)> {
    let order: Vec<i64> = array(project, "/tracks")
        .iter()
        .map(|t| int(t, "/id"))
        .collect();
    let mut out: Vec<(i64, usize, Value)> = array(project, "/clips")
        .iter()
        .map(|c| {
            let index = order
                .iter()
                .position(|id| *id == int(c, "/track"))
                .unwrap_or(0);
            (int(c, "/start"), index, content(c))
        })
        .collect();
    out.sort_by(|a, b| (a.0, a.1).cmp(&(b.0, b.1)));
    out
}

// ---- the grouping ops ----------------------------------------------------

#[test]
fn nest_collapses_the_selection_into_one_clip_on_the_front_track() {
    let project = two_tracks();
    let nest_id = int(&project.value(), "/next_id") as u64;
    let after = project
        .apply(&json!({"op": "nest", "clips": [4, 5]}))
        .value();

    // One clip is left on the timeline, on the FRONT-most track the
    // selection covered (track 3), spanning the selection's whole extent.
    let clips = array(&after, "/clips");
    assert_eq!(clips.len(), 1, "two clips became one");
    let clip = &clips[0];
    assert_eq!(int(clip, "/track"), 3);
    assert_eq!(int(clip, "/start"), 0);
    assert_eq!(
        int(clip, "/duration"),
        4 * SEC,
        "earliest start to latest end"
    );
    assert_eq!(text(clip, "/source/kind"), "nest");
    assert_eq!(int(clip, "/source/project"), nest_id as i64);
    assert!(
        at(clip, "/video").is_object(),
        "a nest clip is transformable"
    );
    assert!(
        at(clip, "/audio").is_object(),
        "one of the clips inside has sound, so the nest has a volume"
    );

    // The nest holds both clips, with their own ids, rebased so the
    // earliest starts at 0, on tracks of its own in the timeline's order.
    let nest = by_id(&after, "/nests", nest_id);
    assert_eq!(text(nest, "/name"), "Nest 1", "named by the count");
    assert_eq!(int(nest, "/width"), 1920);
    assert_eq!(int(nest, "/height"), 1080);
    let tracks = array(nest, "/tracks");
    assert_eq!(tracks.len(), 2, "one nest track per source track");
    assert_eq!(text(&tracks[0], "/name"), "Track 2", "back-most first");
    assert_eq!(text(&tracks[1], "/name"), "Track 3");
    let inner = array(nest, "/clips");
    assert_eq!(inner.len(), 2);
    assert_eq!(int(by_id(nest, "/clips", 4), "/start"), 0);
    assert_eq!(
        int(by_id(nest, "/clips", 5), "/start"),
        SEC,
        "kept its offset"
    );
    assert_eq!(
        int(by_id(nest, "/clips", 4), "/track"),
        int(&tracks[0], "/id"),
        "the back-most clip is on the back-most nest track"
    );
}

#[test]
fn nest_then_unnest_is_the_identity_on_clip_content() {
    let project = two_tracks();
    let before = contents(&project.value());

    let grouped = project.apply(&json!({"op": "nest", "clips": [4, 5]}));
    let nest_clip = int(&grouped.value(), "/clips/0/id");
    let after = grouped.apply(&json!({"op": "unnest", "clip": nest_clip}));

    assert_eq!(
        contents(&after.value()),
        before,
        "the clips came back with the same sources, times, props and stacking"
    );
    // Ids differ, as they do across split-then-join: `unnest` mints fresh
    // ones because a second clip may still show the nest.
    let ids: Vec<i64> = array(&after.value(), "/clips")
        .iter()
        .map(|c| int(c, "/id"))
        .collect();
    assert!(
        !ids.contains(&4) && !ids.contains(&5),
        "unnest re-mints ids, got {ids:?}"
    );
    // And the nest itself is gone: nothing shows it any more.
    assert!(
        array(&after.value(), "/nests").is_empty(),
        "an orphaned nest is dropped"
    );
}

#[test]
fn nest_refuses_an_empty_selection_and_a_lone_nest_clip() {
    let project = two_tracks();
    project.refuses(&json!({"op": "nest", "clips": []}));
    assert_contains(
        &project.errors(&json!({"op": "nest", "clips": [4, 99]})),
        "no clip with id 99",
    );

    // Grouping one group alone would only add a level nobody asked for.
    let nested = nested_media();
    nested.refuses(&json!({"op": "nest", "clips": [3]}));
    // Two clips, one of them a nest, is a real group and is allowed.
    let wider = nested.apply(&json!({"op": "add_text_clip", "track": 2, "at": 8000000}));
    let text_id = int(&nested.value(), "/next_id");
    wider.apply(&json!({"op": "nest", "clips": [3, text_id]}));
}

#[test]
fn nest_refuses_when_the_group_would_overlap_what_was_left_behind() {
    // Three clips in a row on one track; nesting the OUTER two would put a
    // clip over the middle one, which the overlap rule refuses (spec §11) —
    // a refusal, not an error, so the UI animates it back.
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            media_clip(3, 2, 0, 2 * SEC, 1),
            media_clip(4, 2, 3 * SEC, 2 * SEC, 1),
            media_clip(5, 2, 6 * SEC, 2 * SEC, 1),
        ],
        vec![],
        6,
    ));
    project.refuses(&json!({"op": "nest", "clips": [3, 5]}));
    // The neighbours themselves group happily.
    project.apply(&json!({"op": "nest", "clips": [3, 4]}));
}

#[test]
fn unnest_of_a_clip_that_is_not_a_nest_is_an_error() {
    let project = two_tracks();
    assert_contains(
        &project.errors(&json!({"op": "unnest", "clip": 4})),
        "clip 4 is not a nest clip",
    );
    assert_contains(
        &project.errors(&json!({"op": "unnest", "clip": 99})),
        "no clip with id 99",
    );
}

#[test]
fn unnest_puts_a_clip_the_overlap_rule_refuses_on_a_new_track() {
    // The nest clip runs 3 s – 7 s and its content lands at 4 s – 6 s, right
    // where another clip already sits. Rather than refuse — which would
    // leave the user with a group they cannot open — the clip goes on a new
    // track in front, the fallback `paste` uses.
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            nest_clip(3, 2, 3 * SEC, 4 * SEC, 4),
            media_clip(7, 2, 8 * SEC, 4 * SEC, 1),
        ],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(6, 5, 5 * SEC, 4 * SEC, 1)],
        )],
        8,
    ));
    let after = project.apply(&json!({"op": "unnest", "clip": 3})).value();

    let tracks = array(&after, "/tracks");
    assert_eq!(tracks.len(), 2, "a track was added in front");
    let freed: Vec<&Value> = array(&after, "/clips")
        .iter()
        .filter(|c| int(c, "/id") != 7)
        .collect();
    assert_eq!(freed.len(), 1);
    assert_eq!(
        int(freed[0], "/track"),
        int(&tracks[1], "/id"),
        "the front-most track is the new one"
    );
    // Its time is unchanged by the fallback: only the track moved.
    assert_eq!(int(freed[0], "/start"), 8 * SEC);
}

#[test]
fn unnest_keeps_a_nest_a_second_clip_still_shows() {
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            nest_clip(3, 2, 0, 2 * SEC, 4),
            nest_clip(7, 2, 4 * SEC, 2 * SEC, 4),
        ],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(6, 5, 0, 2 * SEC, 1)],
        )],
        8,
    ));
    let after = project.apply(&json!({"op": "unnest", "clip": 3})).value();
    assert_eq!(
        array(&after, "/nests").len(),
        1,
        "clip 7 still shows the nest"
    );
    // The clips that came out are COPIES: the nest's own are untouched.
    assert_eq!(int(by_id(&after, "/nests", 4), "/clips/0/id"), 6);
    assert!(
        array(&after, "/clips").iter().all(|c| int(c, "/id") != 6),
        "the clip on the timeline is a copy with a fresh id"
    );
}

#[test]
fn a_trimmed_nest_clip_gives_all_of_its_contents_back() {
    // The nest clip shows only the first second of a two-second clip. Unnest
    // is the inverse of `nest`, not of the trim: nothing is destroyed.
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, SEC, 4)],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(6, 5, 0, 2 * SEC, 1)],
        )],
        7,
    ));
    let after = project.apply(&json!({"op": "unnest", "clip": 3})).value();
    let clips = array(&after, "/clips");
    assert_eq!(clips.len(), 1);
    assert_eq!(
        int(&clips[0], "/duration"),
        2 * SEC,
        "the whole clip is back"
    );
}

#[test]
fn set_reversed_flips_the_flag_and_leaves_the_in_point_alone() {
    let project = two_tracks();
    let after = project
        .apply(&json!({"op": "set_reversed", "clip": 4, "reversed": true}))
        .value();
    assert!(flag(by_id(&after, "/clips", 4), "/source/reversed"));
    assert_eq!(
        int(by_id(&after, "/clips", 4), "/source/in"),
        0,
        "`in` is measured in the direction the clip plays, so it does not move"
    );
    // Setting it again changes nothing, and no undo step is registered.
    Handle::from_value(&after).refuses(&json!({"op": "set_reversed", "clip": 4, "reversed": true}));
    project.refuses(&json!({"op": "set_reversed", "clip": 4, "reversed": false}));
    // A non-media source is an error, not a refusal — the non-media rule.
    assert_contains(
        &project.errors(&json!({"op": "set_reversed", "clip": 5, "reversed": true})),
        "clip 5 is not a media clip",
    );
}

#[test]
fn reversing_changes_neither_the_plan_nor_the_recipe() {
    // The core does no pixel work: `reversed` is a fact Swift resolves by
    // substituting a pre-rendered asset (spec §11).
    let project = two_tracks();
    let before = project.plan_text();
    let after = project.apply(&json!({"op": "set_reversed", "clip": 4, "reversed": true}));
    assert_eq!(after.plan_text(), before, "the plan is unchanged");
    assert_eq!(after.recipe(SEC), project.recipe(SEC));
}

// ---- the plan ------------------------------------------------------------

#[test]
fn a_nested_media_clip_gets_a_composition_segment_at_project_time() {
    let project = nested_media();
    let plan = project.plan();

    // The nest clip itself needs no track; the clip inside it does.
    let segment = segment_of(&plan, "video_tracks", 6);
    assert_eq!(
        int(&segment, "/start"),
        4 * SEC,
        "3 s (the nest clip) + 1 s (its own start)"
    );
    assert_eq!(int(&segment, "/duration"), 2 * SEC);
    assert_eq!(int(&segment, "/source_in"), 0);
    assert_eq!(int(&segment, "/source_duration"), 2 * SEC);
    assert_eq!(int(&segment, "/media"), 1);

    // And the recipe names the same composition track at an instant inside
    // it — the one thing the plan and the recipe must agree on.
    let recipe = project.recipe(5 * SEC);
    let layer = layer_of(&recipe, 6);
    assert_eq!(text(&layer, "/source/kind"), "track");
    let comp = comp_track(&plan, "video_tracks", int(&layer, "/source/track_id"));
    assert_eq!(int(comp, "/segments/0/clip"), 6);
}

#[test]
fn a_nest_clip_cuts_the_tail_off_what_it_is_too_short_for() {
    // The nest clip runs 0 – 1 s over a two-second clip: half of it plays,
    // and the segment is the half that does.
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, SEC, 4)],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(6, 5, 0, 2 * SEC, 1)],
        )],
        7,
    ));
    let segment = segment_of(&project.plan(), "video_tracks", 6);
    assert_eq!(int(&segment, "/start"), 0);
    assert_eq!(
        int(&segment, "/duration"),
        SEC,
        "cut at the nest clip's end"
    );
    assert_eq!(
        int(&segment, "/source_duration"),
        SEC,
        "and only that much source is inserted"
    );
    // Past the nest clip's end nothing is drawn at all.
    assert!(layer_ids(&project.recipe(SEC + 1)).is_empty());
    assert_eq!(layer_ids(&project.recipe(0)), vec![6]);
}

#[test]
fn a_clip_the_nest_clip_never_reaches_plays_nowhere() {
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, SEC, 4)],
        vec![nest(
            4,
            vec![track(5)],
            vec![
                media_clip(6, 5, 0, SEC, 1),
                // Starts after the nest clip has already ended.
                media_clip(7, 5, 2 * SEC, SEC, 1),
            ],
        )],
        8,
    ));
    let plan = project.plan();
    let clips: Vec<i64> = array(&plan, "/video_tracks")
        .iter()
        .flat_map(|t| array(t, "/segments").iter().map(|s| int(s, "/clip")))
        .collect();
    assert_eq!(clips, vec![6], "clip 7 is outside the nest clip's extent");
}

#[test]
fn the_instruction_tiling_has_a_boundary_at_every_inner_clip_edge() {
    // Without one, the set of visible layers would change inside a span and
    // the span's first tick would stop describing the rest of it — the
    // invariant `instructions` is built on.
    let project = nested_media();
    let plan = project.plan();
    let bounds: Vec<i64> = array(&plan, "/instructions")
        .iter()
        .map(|i| int(i, "/start"))
        .collect();
    assert_eq!(
        bounds,
        vec![0, 4 * SEC, 6 * SEC],
        "0, the inner clip's start and its end"
    );

    // And each span's `required_track_ids` is what the recipe asks for at
    // its first tick, computed from the other end.
    for instruction in array(&plan, "/instructions") {
        let start = int(instruction, "/start");
        let mut wanted: Vec<i64> = array(&project.recipe(start), "/layers")
            .iter()
            .filter(|l| l["source"]["kind"] == json!("track"))
            .map(|l| int(l, "/source/track_id"))
            .collect();
        wanted.sort_unstable();
        wanted.dedup();
        let declared: Vec<i64> = array(instruction, "/required_track_ids")
            .iter()
            .map(|v| v.as_i64().unwrap_or(-1))
            .collect();
        assert_eq!(declared, wanted, "at {start} ticks");
    }
}

#[test]
fn one_nest_shown_twice_plays_at_both_places() {
    // Two clips showing one nest: the SAME inner clip id plays at two
    // times, which is exactly why the plan keys its clip → track map by the
    // path through the nests and not by the clip id.
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3)],
        vec![
            nest_clip(6, 2, 0, 2 * SEC, 4),
            // On another track, overlapping in time, so the two need two
            // composition tracks.
            nest_clip(7, 3, SEC, 2 * SEC, 4),
        ],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(8, 5, 0, 2 * SEC, 1)],
        )],
        9,
    ));
    let plan = project.plan();
    let starts: Vec<i64> = array(&plan, "/video_tracks")
        .iter()
        .flat_map(|t| array(t, "/segments").iter().map(|s| int(s, "/start")))
        .collect();
    assert_eq!(starts, vec![0, SEC], "one segment per placement");
    assert_eq!(
        array(&plan, "/video_tracks").len(),
        2,
        "they overlap in time, so they cannot share a composition track"
    );

    // At 1.5 s both are on screen, each naming its own composition track.
    let recipe = project.recipe(SEC + SEC / 2);
    let tracks: Vec<i64> = array(&recipe, "/layers")
        .iter()
        .map(|l| int(l, "/source/track_id"))
        .collect();
    assert_eq!(tracks.len(), 2);
    assert_ne!(tracks[0], tracks[1], "two placements, two tracks");
    for layer in array(&recipe, "/layers") {
        let comp = comp_track(&plan, "video_tracks", int(layer, "/source/track_id"));
        let segment = &array(comp, "/segments")[0];
        let start = int(segment, "/start");
        let end = start + int(segment, "/duration");
        assert!(
            start <= SEC + SEC / 2 && SEC + SEC / 2 < end,
            "the track named at 1.5 s carries a segment covering it"
        );
    }
}

// ---- the recipe ----------------------------------------------------------

#[test]
fn a_nest_contributes_its_own_clips_as_layers_in_its_own_slot() {
    // Back to front: the clip behind the nest clip, then the nest's own
    // stack in the nest's order, then the clip in front of it.
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3), track(4)],
        vec![
            text_clip(5, 2, 0, 2 * SEC),
            nest_clip(6, 3, 0, 2 * SEC, 7),
            text_clip(8, 4, 0, 2 * SEC),
        ],
        vec![nest(
            7,
            vec![track(9), track(10)],
            vec![text_clip(11, 9, 0, 2 * SEC), text_clip(12, 10, 0, 2 * SEC)],
        )],
        13,
    ));
    assert_eq!(
        layer_ids(&project.recipe(0)),
        vec![5, 11, 12, 8],
        "the nest's layers fill the slot its clip occupied"
    );
}

#[test]
fn the_nest_clips_transform_folds_into_every_layer() {
    // Outer: half size, a quarter turn clockwise, 100 right and 50 down,
    // half opacity. Inner: double size, 30° more, 200 right of the NEST's
    // centre, half opacity.
    //
    // By hand (spec §5.3, canvas pixels, y down):
    //   scale    = 0.5 × 2   = 1
    //   rotation = 90 + 30   = 120
    //   opacity  = 0.5 × 0.5 = 0.25
    //   offset   = (100, 50) + rotate((200, 0) × 0.5, 90°)
    //            = (100, 50) + (0, 100) = (100, 150)
    let mut outer = nest_clip(3, 2, 0, 2 * SEC, 4);
    outer["video"] = json!({"x": 100.0, "y": 50.0, "scale": 0.5,
                            "rotation": 90.0, "opacity": 0.5});
    let mut inner = media_clip(6, 5, 0, 2 * SEC, 1);
    inner["video"] = json!({"x": 200.0, "y": 0.0, "scale": 2.0,
                            "rotation": 30.0, "opacity": 0.5});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![outer],
        vec![nest(4, vec![track(5)], vec![inner])],
        7,
    ));

    let layer = layer_of(&project.recipe(SEC), 6);
    close(num(&layer, "/x"), 100.0, "x");
    close(num(&layer, "/y"), 150.0, "y");
    close(num(&layer, "/scale"), 1.0, "scale");
    close(num(&layer, "/rotation"), 120.0, "rotation");
    close(num(&layer, "/opacity"), 0.25, "opacity");

    // The clip rect is the NEST's canvas where the nest clip put it, with
    // its centre measured from the canvas's top-left corner (spec §7.3).
    let rect = at(&layer, "/clip_rect").clone();
    close(num(&rect, "/x"), 960.0 + 100.0, "clip_rect.x");
    close(num(&rect, "/y"), 540.0 + 50.0, "clip_rect.y");
    close(num(&rect, "/w"), 960.0, "clip_rect.w");
    close(num(&rect, "/h"), 540.0, "clip_rect.h");
    close(num(&rect, "/rotation"), 90.0, "clip_rect.rotation");

    // Source-pixel properties are NOT folded: they are applied before the
    // layer reaches canvas space.
    assert_eq!(num(&layer, "/crop/l"), 0.0);
    assert_eq!(at(&layer, "/source_size"), &json!([1920, 1080]));
}

#[test]
fn a_timeline_clip_carries_no_clip_rect_and_no_fold() {
    let project = two_tracks();
    let layer = layer_of(&project.recipe(SEC), 4);
    assert_eq!(at(&layer, "/clip_rect"), &Value::Null);
    assert_eq!(num(&layer, "/scale"), 1.0);
    assert_eq!(num(&layer, "/x"), 0.0);
}

#[test]
fn two_levels_of_nesting_compose() {
    // A nest inside a nest, each half size and 200 to the right of its own
    // canvas centre:
    //   scale  = 0.5 × 0.5      = 0.25
    //   offset = (200, 0) + (200 × 0.5, 0) + … the innermost layer sits at
    //            (100, 0) of the middle nest, which is (50, 0) of the outer
    //   x      = 200 + 100 + 50 = 350
    // and the clip rect is the INNERMOST nest's canvas, 1920 × 0.25 wide.
    let mut outer = nest_clip(3, 2, 0, 2 * SEC, 4);
    outer["video"] = json!({"x": 200.0, "scale": 0.5});
    let mut middle = nest_clip(6, 5, 0, 2 * SEC, 7);
    middle["video"] = json!({"x": 200.0, "scale": 0.5});
    let mut inner = text_clip(9, 8, 0, 2 * SEC);
    inner["video"] = json!({"x": 200.0});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![outer],
        vec![
            nest(4, vec![track(5)], vec![middle]),
            nest(7, vec![track(8)], vec![inner]),
        ],
        10,
    ));

    let layer = layer_of(&project.recipe(SEC), 9);
    close(num(&layer, "/x"), 350.0, "x");
    close(num(&layer, "/scale"), 0.25, "scale");
    let rect = at(&layer, "/clip_rect").clone();
    close(num(&rect, "/w"), 1920.0 * 0.25, "clip_rect.w");
    close(
        num(&rect, "/x"),
        960.0 + 300.0,
        "the innermost nest's centre, in canvas pixels",
    );
}

#[test]
fn a_hidden_nest_track_and_a_disabled_nest_clip_both_draw_nothing() {
    let mut hidden = track(5);
    hidden["hidden"] = json!(true);
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 2 * SEC, 4)],
        vec![nest(
            4,
            vec![hidden, track(6)],
            vec![text_clip(7, 5, 0, 2 * SEC), text_clip(8, 6, 0, 2 * SEC)],
        )],
        9,
    ));
    assert_eq!(
        layer_ids(&project.recipe(0)),
        vec![8],
        "the clip on the hidden nest track is not drawn"
    );

    let off = project.apply(&json!({"op": "set_enabled", "clip": 3, "video": false}));
    assert!(
        layer_ids(&off.recipe(0)).is_empty(),
        "hiding the nest clip hides everything in it"
    );
}

#[test]
fn a_transition_inside_a_nest_still_renders() {
    // Two clips overlapping by half a second inside a nest: the group was
    // made out of clips that already had a transition, so it has to survive
    // being grouped.
    let mut later = text_clip(7, 5, SEC + SEC / 2, 2 * SEC);
    later["transition_in"] = json!({"kind": "wipe"});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 4 * SEC, 4)],
        vec![nest(
            4,
            vec![track(5)],
            vec![text_clip(6, 5, 0, 2 * SEC), later],
        )],
        8,
    ));
    // Nest time 1.75 s is project time 1.75 s here, a quarter of the way
    // through the 0.5 s overlap that runs 1.5 s – 2 s.
    let recipe = project.recipe(SEC + SEC * 3 / 4);
    let out = layer_of(&recipe, 6);
    let incoming = layer_of(&recipe, 7);
    assert_eq!(text(&out, "/transition/kind"), "wipe");
    assert_eq!(text(&out, "/transition/role"), "out");
    assert_eq!(text(&incoming, "/transition/role"), "in");
    close(num(&incoming, "/transition/progress"), 0.5, "progress");
}

#[test]
fn a_transition_on_the_nest_clip_is_inherited_by_everything_inside() {
    // Otherwise a dissolve INTO a nest would cut its layers in at full
    // opacity while the neighbour faded.
    let mut nested = nest_clip(6, 2, 2 * SEC, 2 * SEC, 4);
    nested["transition_in"] = json!({"kind": "cross_dissolve"});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![media_clip(3, 2, 0, 3 * SEC, 1), nested],
        vec![nest(4, vec![track(5)], vec![text_clip(7, 5, 0, 2 * SEC)])],
        8,
    ));
    // The overlap runs 2 s – 3 s; half way through it is 2.5 s.
    let layer = layer_of(&project.recipe(2 * SEC + SEC / 2), 7);
    assert_eq!(text(&layer, "/transition/kind"), "cross_dissolve");
    assert_eq!(text(&layer, "/transition/role"), "in");
    close(num(&layer, "/transition/progress"), 0.5, "progress");
}

// ---- the envelope --------------------------------------------------------

#[test]
fn a_nested_clips_envelope_is_multiplied_by_the_nest_clips_volume() {
    // Half of a half. Without the fold a nested clip would play at full
    // gain — an empty ramp array is not "no envelope", it is 1.0.
    let mut outer = nest_clip(3, 2, 0, 2 * SEC, 4);
    outer["audio"] = json!({"volume": 0.5});
    let mut inner = media_clip(6, 5, 0, 2 * SEC, 1);
    inner["audio"] = json!({"volume": 0.5});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![outer],
        vec![nest(4, vec![track(5)], vec![inner])],
        7,
    ));

    let plan = project.plan();
    let ramps = array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps");
    assert_eq!(ramps.len(), 1, "a constant gain is one ramp");
    assert_eq!(int(&ramps[0], "/start"), 0);
    assert_eq!(int(&ramps[0], "/duration"), 2 * SEC);
    close(num(&ramps[0], "/from"), 0.25, "gain");
    close(num(&ramps[0], "/to"), 0.25, "gain");
}

#[test]
fn muting_a_nest_clip_or_its_track_silences_everything_inside() {
    let base = |outer: Value, nest_track: Value| {
        Handle::from_value(&project(
            vec![video_media(1)],
            vec![track(2)],
            vec![outer],
            vec![nest(
                4,
                vec![nest_track],
                vec![media_clip(6, 5, 0, 2 * SEC, 1)],
            )],
            7,
        ))
    };
    let zero = |handle: &Handle| {
        let plan = handle.plan();
        let ramps = array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps").clone();
        assert!(
            ramps
                .iter()
                .all(|r| num(r, "/from") == 0.0 && num(r, "/to") == 0.0),
            "expected a zero envelope, got {ramps:?}"
        );
        // The SEGMENT is still there: a mute is an envelope, not a
        // rebuild (spec §7.2).
        assert_eq!(
            array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/segments").len(),
            1
        );
    };

    let mut muted_clip = nest_clip(3, 2, 0, 2 * SEC, 4);
    muted_clip["audio"] = json!({"muted": true});
    zero(&base(muted_clip, track(5)));

    let mut muted_track = track(5);
    muted_track["muted"] = json!(true);
    zero(&base(nest_clip(3, 2, 0, 2 * SEC, 4), muted_track));
}

#[test]
fn a_nested_clip_fades_on_its_own_edges_not_the_nest_clips() {
    // A one-second fade-in on a clip that starts one second into the nest:
    // it runs 1 s – 2 s of project time, where the clip's own first frame
    // is, and not at the nest clip's start.
    let mut inner = media_clip(6, 5, SEC, 2 * SEC, 1);
    inner["audio"] = json!({"fade_in": SEC});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 4 * SEC, 4)],
        vec![nest(4, vec![track(5)], vec![inner])],
        7,
    ));
    let plan = project.plan();
    let ramps = array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps");
    assert_eq!(ramps.len(), 2, "the fade, then the body");
    assert_eq!(int(&ramps[0], "/start"), SEC);
    assert_eq!(int(&ramps[0], "/duration"), SEC);
    close(num(&ramps[0], "/from"), 0.0, "the fade starts at silence");
    close(
        num(&ramps[0], "/to"),
        1.0,
        "and reaches full gain at its end",
    );
    assert_eq!(int(&ramps[1], "/start"), 2 * SEC);
    close(num(&ramps[1], "/from"), 1.0, "the body");
}

#[test]
fn a_duck_inside_a_nest_ducks_the_rest_of_the_project() {
    // The ducker plays 1 s – 2 s inside a nest that starts at 1 s, so it
    // pushes the other track down over 2 s – 3 s of PROJECT time.
    let mut ducker = media_clip(8, 7, SEC, SEC, 1);
    ducker["audio"] = json!({"duck": {"level": 0.5, "attack": 0, "release": 0}});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2), track(3)],
        vec![
            media_clip(4, 2, 0, 5 * SEC, 1),
            nest_clip(5, 3, SEC, 4 * SEC, 6),
        ],
        vec![nest(6, vec![track(7)], vec![ducker])],
        9,
    ));
    let plan = project.plan();
    // The ducked track is the one carrying clip 4.
    let ducked = array(&plan, "/audio_tracks")
        .iter()
        .find(|t| int(t, "/segments/0/clip") == 4)
        .expect("clip 4 has an audio track")
        .clone();
    let ramps = array(&ducked, "/ramps");
    let dipped: Vec<&Value> = ramps.iter().filter(|r| num(r, "/from") < 1.0).collect();
    assert_eq!(dipped.len(), 1, "one dip, in {ramps:?}");
    assert_eq!(int(dipped[0], "/start"), 2 * SEC);
    assert_eq!(int(dipped[0], "/duration"), SEC);
    close(num(dipped[0], "/from"), 0.5, "the duck level");
}

// ---- the clipboard -------------------------------------------------------

#[test]
fn pasting_a_nest_clip_copies_the_nest_with_fresh_ids() {
    let project = two_tracks();
    let payload = json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": 2000000,
                   "source": {"kind": "nest", "project": 4}, "video": {}}],
        "media": [video_media(1)],
        "nests": [{
            "id": 4, "name": "Group", "width": 1920, "height": 1080,
            "tracks": [{"id": 5, "name": "Nested"}],
            "clips": [media_clip(6, 5, 0, 2000000, 1)]
        }]
    });
    let after = project
        .apply(&json!({"op": "paste", "at": 8000000, "payload": payload}))
        .value();

    let nests = array(&after, "/nests");
    assert_eq!(nests.len(), 1, "the nest came with the clip");
    let copied = nests[0].clone();
    assert_eq!(text(&copied, "/name"), "Group");
    assert_ne!(int(&copied, "/id"), 4, "every id is re-minted");
    assert_ne!(int(&copied, "/clips/0/id"), 6);
    assert_eq!(
        int(&copied, "/clips/0/track"),
        int(&copied, "/tracks/0/id"),
        "its clip follows its track's new id"
    );
    // The pasted clip points at the copy, and the media it names was matched
    // to the row the project already had.
    let pasted = array(&after, "/clips")
        .iter()
        .find(|c| text(c, "/source/kind") == "nest")
        .expect("a nest clip landed")
        .clone();
    assert_eq!(int(&pasted, "/source/project"), int(&copied, "/id"));
    assert_eq!(int(&pasted, "/start"), 8_000_000);
    assert_eq!(
        array(&after, "/media").len(),
        1,
        "the payload's media matched the project's by path"
    );
    assert_eq!(int(&copied, "/clips/0/source/media"), 1);

    // And it plays: the copy is a real nest, not a decoration.
    let handle = Handle::from_value(&after);
    assert_eq!(layer_ids(&handle.recipe(8_000_000 + SEC)).len(), 1);
}

#[test]
fn pasting_a_nest_clip_whose_nest_is_missing_is_an_error() {
    let project = two_tracks();
    let payload = json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": 2000000,
                   "source": {"kind": "nest", "project": 44}, "video": {}}]
    });
    assert_contains(
        &project.errors(&json!({"op": "paste", "at": 0, "payload": payload})),
        "shows nest 44, which the payload does not carry",
    );
}

// ---- media ---------------------------------------------------------------

#[test]
fn remove_media_sees_a_clip_inside_a_nest() {
    let project = nested_media();
    // The only clip using media 1 is inside the nest, and it counts.
    project.refuses(&json!({"op": "remove_media", "media": 1}));
    let after = project
        .apply(&json!({"op": "remove_media", "media": 1, "with_clips": true}))
        .value();
    assert!(array(&after, "/media").is_empty());
    assert!(
        array(by_id(&after, "/nests", 4), "/clips").is_empty(),
        "the nested clip went with the media"
    );
    assert_eq!(
        array(&after, "/clips").len(),
        1,
        "the nest CLIP stays: it does not show the media, its contents did"
    );
}

#[test]
fn nesting_two_clips_that_dissolve_keeps_the_dissolve() {
    // The flow that matters: a pair with a transition between them is
    // grouped, and the group goes on playing what it played. The overlap
    // moves into the nest with the clips, so `transition_in` still describes
    // it there.
    let mut later = media_clip(4, 2, 2 * SEC, 2 * SEC, 1);
    later["transition_in"] = json!({"kind": "fade_black"});
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![media_clip(3, 2, 0, 3 * SEC, 1), later],
        vec![],
        5,
    ));
    // 2.5 s is half way through the 2 s – 3 s overlap.
    let before = layer_of(&project.recipe(2 * SEC + SEC / 2), 4);
    assert_eq!(text(&before, "/transition/kind"), "fade_black");

    let grouped = project.apply(&json!({"op": "nest", "clips": [3, 4]}));
    let after = layer_of(&grouped.recipe(2 * SEC + SEC / 2), 4);
    assert_eq!(text(&after, "/transition/kind"), "fade_black");
    assert_eq!(text(&after, "/transition/role"), "in");
    close(
        num(&after, "/transition/progress"),
        num(&before, "/transition/progress"),
        "progress",
    );
}

#[test]
fn nesting_carries_a_muted_track_into_the_nest() {
    // The mute belongs to the track, and the timeline's track stays behind
    // holding whatever was not selected — so the nest's own track takes a
    // copy of the state, and the clips inside go on sounding as they did.
    let mut muted = track(2);
    muted["muted"] = json!(true);
    let project = Handle::from_value(&project(
        vec![video_media(1)],
        vec![muted],
        vec![media_clip(3, 2, 0, 2 * SEC, 1)],
        vec![],
        4,
    ));
    let nest_id = int(&project.value(), "/next_id") as u64;
    let after = project.apply(&json!({"op": "nest", "clips": [3]}));

    let value = after.value();
    let nest = by_id(&value, "/nests", nest_id);
    assert!(
        flag(&array(nest, "/tracks")[0], "/muted"),
        "the mute came too"
    );
    let plan = after.plan();
    let ramps = array(comp_track(&plan, "audio_tracks", FIRST_AUDIO), "/ramps");
    assert!(
        ramps.iter().all(|r| num(r, "/from") == 0.0),
        "still silent, in {ramps:?}"
    );
}
