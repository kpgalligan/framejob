//! Black-box tests for the envelope's `scope` key — editing INSIDE a nest
//! (spec §6, `core/src/scope.rs`) — driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! `nest.rs` owns what a nest IS and what it does to the plan, the recipe
//! and the envelopes; `schema_v2.rs` owns its shape. This file owns the one
//! new question: what does an op mean when it is told which container to
//! resolve its ids against.
//!
//! The oracle is the round trip, and it is written so that neither half can
//! be believed on its own account:
//!
//! > **"apply inside with `scope`, then `unnest`" equals "`unnest`, then
//! > apply at the top level"**, on clip content, ids aside.
//!
//! That is `nest.rs`'s own identity claim (`nest` then `unnest` is the
//! identity on clip content) with an edit dropped into the middle, and it
//! is compared by the SAME comparator — `common::contents`, which strips
//! every id and orders by start and track INDEX, so a difference in
//! stacking is a difference. Every op in the table below is run through it,
//! and each is also checked to have MOVED the needle: a scoped op that
//! quietly did nothing would otherwise make both sides agree for the wrong
//! reason.
//!
//! Around the oracle sit the cases the oracle cannot see, and they are the
//! phase's real content: the seven refusals, the invariants a view is BLIND
//! to (the document-wide caps and the nesting depth, which is why a scoped
//! op has a wider `Err` arm than any other), and the two write-back rules
//! that only a shared object can test — a `paste` that appends media, and
//! an `unnest` inside a nest that must not drop a nest a timeline clip
//! still shows.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, by_id, contents, int, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with them.
const SEC: i64 = 600_000;

/// One frame at the fixtures' 30 fps.
const FRAME: i64 = SEC / 30;

// ---- fixtures ------------------------------------------------------------

fn video_media(id: u32, path: &str) -> Value {
    json!({
        "id": id, "path": path, "kind": "video",
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

fn nest(id: u32, width: u32, height: u32, tracks: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "id": id, "name": format!("Nest {id}"), "width": width, "height": height,
        "tracks": tracks, "clips": clips
    })
}

fn project(
    media: Vec<Value>,
    tracks: Vec<Value>,
    clips: Vec<Value>,
    markers: Vec<Value>,
    nests: Vec<Value>,
    next_id: u32,
) -> Value {
    json!({
        "version": 2,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": media, "tracks": tracks, "clips": clips, "markers": markers,
        "next_id": next_id, "nests": nests
    })
}

/// The oracle fixture. One timeline track holding ONE nest clip at 0 for
/// 4 s; nest 4 holds two clips on one track, a media clip at 0 – 2 s and a
/// text clip at 2 – 4 s.
///
/// **The nest clip starts at 0 deliberately.** Nest-local time is
/// `t − nest_clip.start`, so a nest clip at zero makes inside-time and
/// project-time the same number and the two halves of the oracle can send
/// the SAME time arguments. The mapping itself is not what this file is
/// testing, and a fixture that made every op's arguments differ would hide
/// a real disagreement behind arithmetic.
///
/// The nest's canvas matches the parent's for the same reason: `add_*` ops
/// read a canvas, so a difference there would show up as an oracle failure
/// rather than as what it is. `the_view_is_composited_at_the_nests_frozen_size`
/// is where that reading is checked on its own.
fn one_nest() -> Handle {
    Handle::from_value(&project(
        vec![video_media(1, "/fixtures/1.mov")],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 4 * SEC, 4)],
        vec![],
        vec![nest(
            4,
            1920,
            1080,
            vec![track(5)],
            vec![
                media_clip(6, 5, 0, 2 * SEC, 1),
                text_clip(7, 5, 2 * SEC, 2 * SEC),
            ],
        )],
        8,
    ))
}

/// The id of the only clip starting at `start` — how the top-level half of
/// the oracle names the clip the scoped half named by its stable fixture
/// id, since `unnest` re-mints every one of them.
fn clip_at(project: &Value, start: i64) -> u64 {
    let found: Vec<&Value> = array(project, "/clips")
        .iter()
        .filter(|c| int(c, "/start") == start)
        .collect();
    assert_eq!(
        found.len(),
        1,
        "expected exactly one clip starting at {start} in {project}"
    );
    int(found[0], "/id") as u64
}

/// The nest with this id, out of a written project.
fn nest_of(project: &Value, id: u64) -> Value {
    array(project, "/nests")
        .iter()
        .find(|n| int(n, "/id") == id as i64)
        .unwrap_or_else(|| panic!("no nest with id {id} in {project}"))
        .clone()
}

fn nest_ids(project: &Value) -> Vec<i64> {
    array(project, "/nests")
        .iter()
        .map(|n| int(n, "/id"))
        .collect()
}

// ---- the oracle ----------------------------------------------------------

/// One row of the table: a name, the op sent with `"scope": 4`, and the
/// same op built against the OPENED project, whose ids and track are its
/// own.
struct Row {
    name: &'static str,
    inside: Value,
    outside: Box<dyn Fn(&Value) -> Value>,
}

fn row(name: &'static str, inside: Value, outside: impl Fn(&Value) -> Value + 'static) -> Row {
    Row {
        name,
        inside,
        outside: Box::new(outside),
    }
}

/// The ops the road map names, plus five it does not: an action op (whose
/// ids are re-minted too, so the comparator has to strip them), a range
/// cut, an insert, a `duplicate` and a `detach_audio` — the last because it
/// INSERTS A TRACK, which is the one thing that could make the two halves
/// disagree about stacking while agreeing about every clip.
fn table() -> Vec<Row> {
    vec![
        row(
            "slip",
            json!({"op": "slip", "clip": 6, "delta": SEC, "scope": 4}),
            |opened| json!({"op": "slip", "clip": clip_at(opened, 0), "delta": SEC}),
        ),
        row(
            "trim_start",
            json!({"op": "trim_start", "clip": 6, "to": SEC / 2, "scope": 4}),
            |opened| json!({"op": "trim_start", "clip": clip_at(opened, 0), "to": SEC / 2}),
        ),
        row(
            "trim_end",
            json!({"op": "trim_end", "clip": 6, "to": SEC + SEC / 2, "scope": 4}),
            |opened| json!({"op": "trim_end", "clip": clip_at(opened, 0), "to": SEC + SEC / 2}),
        ),
        row(
            "split",
            json!({"op": "split", "clips": [6], "at": SEC, "scope": 4}),
            |opened| json!({"op": "split", "clips": [clip_at(opened, 0)], "at": SEC}),
        ),
        row(
            "set_video",
            json!({"op": "set_video", "clips": [6], "patch": {"opacity": 0.5}, "scope": 4}),
            |opened| {
                json!({"op": "set_video", "clips": [clip_at(opened, 0)],
                       "patch": {"opacity": 0.5}})
            },
        ),
        row(
            "set_clip",
            json!({"op": "set_clip", "clips": [7], "patch": {"name": "Chapter"}, "scope": 4}),
            |opened| {
                json!({"op": "set_clip", "clips": [clip_at(opened, 2 * SEC)],
                       "patch": {"name": "Chapter"}})
            },
        ),
        row(
            "add_text_clip",
            json!({"op": "add_text_clip", "track": 5, "at": 4 * SEC, "duration": SEC,
                   "scope": 4}),
            |_| json!({"op": "add_text_clip", "track": 2, "at": 4 * SEC, "duration": SEC}),
        ),
        row(
            "delete",
            json!({"op": "delete", "clips": [6], "scope": 4}),
            |opened| json!({"op": "delete", "clips": [clip_at(opened, 0)]}),
        ),
        row(
            "move_clip",
            json!({"op": "move_clip", "clips": [7], "delta": SEC, "scope": 4}),
            |opened| json!({"op": "move_clip", "clips": [clip_at(opened, 2 * SEC)], "delta": SEC}),
        ),
        row(
            "duplicate",
            json!({"op": "duplicate", "clips": [7], "scope": 4}),
            |opened| json!({"op": "duplicate", "clips": [clip_at(opened, 2 * SEC)]}),
        ),
        row(
            "add_action",
            json!({"op": "add_action", "clip": 6, "at": 0, "duration": SEC, "scope": 4}),
            |opened| {
                json!({"op": "add_action", "clip": clip_at(opened, 0), "at": 0,
                       "duration": SEC})
            },
        ),
        row(
            "ripple_delete_range",
            json!({"op": "ripple_delete_range", "from": SEC / 2, "to": SEC, "scope": 4}),
            |_| json!({"op": "ripple_delete_range", "from": SEC / 2, "to": SEC}),
        ),
        row(
            "insert_time",
            json!({"op": "insert_time", "at": SEC, "length": SEC, "scope": 4}),
            |_| json!({"op": "insert_time", "at": SEC, "length": SEC}),
        ),
        row(
            "detach_audio",
            json!({"op": "detach_audio", "clip": 6, "scope": 4}),
            |opened| json!({"op": "detach_audio", "clip": clip_at(opened, 0)}),
        ),
    ]
}

#[test]
fn editing_inside_then_opening_equals_opening_then_editing() {
    let base = one_nest();
    let open = json!({"op": "unnest", "clip": 3});
    // What the group looks like opened and UNEDITED, so every row below can
    // be checked to have changed something. Without it a scoped op that
    // silently did nothing would agree with a top-level op that silently
    // did nothing, and the whole table would pass against a broken build.
    let untouched = contents(&base.apply(&open).value());

    for Row {
        name,
        inside,
        outside,
    } in table()
    {
        let edited_then_opened = base.apply(&inside).apply(&open);
        let opened = base.apply(&open);
        let opened_then_edited = opened.apply(&outside(&opened.value()));

        let a = contents(&edited_then_opened.value());
        let b = contents(&opened_then_edited.value());
        assert_eq!(
            a, b,
            "{name}: editing inside the nest and then opening it differs from \
             opening it and then editing"
        );
        assert_ne!(
            a, untouched,
            "{name}: neither half of the oracle changed anything, so it \
             proves nothing"
        );
    }
}

// ---- the scope resolves ids, and only inside ------------------------------

#[test]
fn a_scoped_op_names_the_nests_clips_and_an_unscoped_one_names_the_timelines() {
    let base = one_nest();

    // Clip 6 lives inside nest 4. With the scope it is found; without it,
    // it does not exist — which is the limit spec §4.4 recorded, still true
    // for every op that does not say otherwise.
    base.apply(&json!({"op": "trim_start", "clip": 6, "to": SEC / 2, "scope": 4}));
    assert_contains(
        &base.errors(&json!({"op": "trim_start", "clip": 6, "to": SEC / 2})),
        "no clip with id 6",
    );

    // And the other way round: clip 3 is the nest CLIP, a timeline object,
    // so a scoped op cannot see it either. A scope is a change of
    // container, not an extension of one.
    assert_contains(
        &base.errors(&json!({"op": "trim_start", "clip": 3, "to": SEC / 2, "scope": 4})),
        "no clip with id 3",
    );
}

#[test]
fn a_scoped_edit_lands_in_the_nest_and_leaves_the_timeline_alone() {
    let base = one_nest();
    let before = base.value();
    let after = base
        .apply(&json!({"op": "move_clip", "clips": [7], "delta": SEC, "scope": 4}))
        .value();

    // The nest's own clip moved...
    let inside = nest_of(&after, 4);
    assert_eq!(int(by_id(&inside, "/clips", 7), "/start"), 3 * SEC);
    // ...and nothing about the container did: the nest clip's place, the
    // nest's frozen size and its name are all untouched.
    assert_eq!(
        array(&after, "/clips"),
        array(&before, "/clips"),
        "a scoped edit must not touch the timeline's clips"
    );
    assert_eq!(int(&inside, "/width"), 1920);
    assert_eq!(int(&inside, "/height"), 1080);
    assert_eq!(text(&inside, "/name"), "Nest 4");
    assert_eq!(
        array(&after, "/tracks"),
        array(&before, "/tracks"),
        "a scoped edit must not touch the timeline's tracks"
    );
}

#[test]
fn a_scoped_edit_does_not_move_the_timelines_markers() {
    // `insert_time` is the op that moves markers, and the view has none —
    // a nest has no `markers[]`, and the timeline's are PROJECT time. So a
    // hole opened inside a nest shifts what is in the nest and nothing on
    // the ruler.
    let base = Handle::from_value(&project(
        vec![video_media(1, "/fixtures/1.mov")],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 4 * SEC, 4)],
        vec![json!({"id": 9, "time": SEC, "name": "M", "chapter": false, "color": "red"})],
        vec![nest(
            4,
            1920,
            1080,
            vec![track(5)],
            vec![
                media_clip(6, 5, 0, 2 * SEC, 1),
                text_clip(7, 5, 2 * SEC, 2 * SEC),
            ],
        )],
        10,
    ));
    let after = base
        .apply(&json!({"op": "insert_time", "at": SEC, "length": SEC, "scope": 4}))
        .value();

    assert_eq!(
        int(by_id(&nest_of(&after, 4), "/clips", 7), "/start"),
        3 * SEC,
        "the nest's own clip rode the insert"
    );
    assert_eq!(
        int(by_id(&after, "/markers", 9), "/time"),
        SEC,
        "the timeline's marker did not"
    );
}

#[test]
fn the_view_is_composited_at_the_nests_frozen_size() {
    // A nest's canvas is frozen at the size the parent had when it was made
    // (§5.2), and that is the size its contents are placed against — so a
    // 640x360 nest inside a 1920x1080 document gets a 640x360 backdrop, not
    // the document's. `add_background` is the op that reads the canvas most
    // directly: its colour plate is a canvas-sized rectangle.
    let base = Handle::from_value(&project(
        vec![video_media(1, "/fixtures/1.mov")],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 2 * SEC, 4)],
        vec![],
        vec![nest(
            4,
            640,
            360,
            vec![track(5)],
            vec![media_clip(6, 5, 0, 2 * SEC, 1)],
        )],
        8,
    ));
    let after = base
        .apply(&json!({"op": "add_background", "duration": SEC, "scope": 4}))
        .value();

    let inside = nest_of(&after, 4);
    let plate = array(&inside, "/clips")
        .iter()
        .find(|c| c.pointer("/shape").is_some_and(|s| !s.is_null()))
        .expect("add_background places a shape clip")
        .clone();
    assert_eq!(num(&plate, "/shape/width"), 640.0);
    assert_eq!(num(&plate, "/shape/height"), 360.0);

    // And the same op at the top level takes the DOCUMENT's canvas, which
    // is what says the 640x360 above came from the nest and not from a
    // coincidence.
    let outside = base
        .apply(&json!({"op": "add_background", "duration": SEC}))
        .value();
    let outer = array(&outside, "/clips")
        .iter()
        .find(|c| c.pointer("/shape").is_some_and(|s| !s.is_null()))
        .expect("add_background places a shape clip")
        .clone();
    assert_eq!(num(&outer, "/shape/width"), 1920.0);
    assert_eq!(num(&outer, "/shape/height"), 1080.0);
}

#[test]
fn a_scoped_time_snaps_to_the_documents_frame_grid() {
    // A `Nest` has no rate of its own, so the view takes the parent's — and
    // every time argument snaps to it, exactly as it does outside. A third
    // of a frame past 1 s rounds back onto the grid; two thirds rounds on
    // to the next one, which is what says the number was snapped rather
    // than truncated.
    let base = one_nest();
    for (asked, landed) in [(SEC + FRAME / 3, SEC), (SEC + 2 * FRAME / 3, SEC + FRAME)] {
        let after = base
            .apply(&json!({"op": "trim_end", "clip": 6, "to": asked, "scope": 4}))
            .value();
        assert_eq!(
            int(by_id(&nest_of(&after, 4), "/clips", 6), "/duration"),
            landed,
            "a trim to {asked} lands on the parent's 30 fps grid"
        );
    }
}

#[test]
fn a_scoped_op_that_changes_nothing_reports_no_change() {
    // The two non-applied arms, which must register no undo step (spec
    // §5.5). An identity and a rule's refusal both land here, inside a scope
    // exactly as outside — `refuses` is the claim they share.
    let base = one_nest();
    base.refuses(&json!({"op": "move_clip", "clips": [6], "delta": 0, "scope": 4}));
    base.refuses(&json!({"op": "set_video", "clips": [6], "patch": {"opacity": 1.0}, "scope": 4}));
    base.refuses(&json!({"op": "nest", "clips": [], "scope": 4}));
    // A refusal that is the nest's own rule rather than an identity: the
    // nest has one track and it is not empty.
    base.refuses(&json!({"op": "remove_track", "track": 5, "scope": 4}));
}

// ---- the scope argument itself -------------------------------------------

#[test]
fn an_unknown_scope_is_an_error_naming_it() {
    let base = one_nest();
    assert_eq!(
        base.errors(&json!({"op": "trim_start", "clip": 6, "to": SEC / 2, "scope": 99})),
        "no nest with id 99"
    );
    // Ids are one space (§5.2), so a scope naming a clip, a track or a
    // media is the same mistake and gets the same sentence.
    for id in [1, 2, 3, 5, 6, 0] {
        assert_eq!(
            base.errors(&json!({"op": "delete", "clips": [6], "scope": id})),
            format!("no nest with id {id}")
        );
    }
}

#[test]
fn an_unknown_scope_is_reported_ahead_of_everything_else() {
    // The scope decides which document the caller thinks it is editing, so
    // a mistake there is answered before the op is classified and before
    // its own arguments are looked at.
    let base = one_nest();
    assert_eq!(
        base.errors(&json!({"op": "add_marker", "at": 0, "scope": 99})),
        "no nest with id 99",
        "an unknown scope outranks the refusal list"
    );
    assert_eq!(
        base.errors(&json!({"op": "delete", "clips": [4242], "scope": 99})),
        "no nest with id 99",
        "an unknown scope outranks an unknown clip"
    );
}

#[test]
fn a_scope_that_is_not_a_nest_id_is_an_error_naming_the_value() {
    let base = one_nest();
    let cases = [
        (json!("4"), "\"4\""),
        (json!(-1), "-1"),
        (json!(1.5), "1.5"),
        (json!(true), "true"),
        (json!([4]), "[4]"),
        (json!({"nest": 4}), "{\"nest\":4}"),
        (json!(4294967296u64), "4294967296"),
    ];
    for (value, spelled) in cases {
        let mut op = json!({"op": "delete", "clips": [6]});
        op["scope"] = value.clone();
        assert_eq!(
            base.errors(&op),
            format!("scope must be a nest id, not {spelled}"),
            "for scope {value}"
        );
    }
}

#[test]
fn an_absent_scope_and_an_explicit_null_are_the_same_thing() {
    // The envelope's standing rule. `null` therefore edits the TIMELINE,
    // which is what makes an app that always writes the key safe.
    let base = one_nest();
    let with_null = base
        .apply(&json!({"op": "trim_end", "clip": 3, "to": 3 * SEC, "scope": null}))
        .value();
    let without = base
        .apply(&json!({"op": "trim_end", "clip": 3, "to": 3 * SEC}))
        .value();
    assert_eq!(with_null, without);
}

#[test]
fn a_misspelt_argument_is_still_refused_beside_a_scope() {
    // Taking `scope` out of the envelope must not cost the `deny_unknown_fields`
    // that catches a typo in an argument — the whole reason it comes out in
    // the first pass rather than through a `flatten`.
    let base = one_nest();
    assert_contains(
        &base.errors(&json!({"op": "trim_start", "clip": 6, "two": SEC, "scope": 4})),
        "unknown field `two`",
    );
    assert_contains(
        &base.errors(&json!({"op": "trim_start", "clip": 6, "to": SEC, "scopes": 4})),
        "unknown field `scopes`",
    );
}

// ---- the refusal list ----------------------------------------------------

/// The seven ops with no meaning inside a nest, with an argument list each
/// that would otherwise be valid — so what the message reports is the
/// refusal and not a bad argument.
fn refused() -> Vec<(&'static str, Value)> {
    vec![
        ("add_marker", json!({"op": "add_marker", "at": SEC})),
        (
            "set_marker",
            json!({"op": "set_marker", "marker": 9, "time": SEC}),
        ),
        ("remove_marker", json!({"op": "remove_marker", "marker": 9})),
        ("set_canvas", json!({"op": "set_canvas", "width": 1280})),
        (
            "add_media",
            json!({"op": "add_media",
                   "descriptor": {"path": "/fixtures/2.mov", "kind": "video"}}),
        ),
        (
            "relink_media",
            json!({"op": "relink_media", "media": 1, "path": "/fixtures/moved.mov"}),
        ),
        ("remove_media", json!({"op": "remove_media", "media": 1})),
    ]
}

#[test]
fn the_seven_ops_with_no_meaning_inside_a_nest_are_errors_naming_themselves() {
    let base = one_nest();
    for (name, op) in refused() {
        let mut scoped = op.clone();
        scoped["scope"] = json!(4);
        assert_eq!(
            base.errors(&scoped),
            format!("{name} has no meaning inside nest 4"),
            "for {name}"
        );
    }
}

#[test]
fn every_refused_name_is_an_op_the_table_knows() {
    // The refusal message quotes a name, and a name that is not in the op
    // table would be a lie the compiler cannot catch. `rc_op_names` is the
    // table as the host reads it.
    use reelcut_core::OP_NAMES;
    assert_eq!(OP_NAMES.len(), 57, "a scope is an envelope key, not an op");
    for (name, _) in refused() {
        assert!(
            OP_NAMES.contains(&name),
            "{name} is refused inside a scope but is not an op"
        );
    }
}

// ---- every op in the table, under a scope --------------------------------

/// A nest with something of every kind in it: two tracks, a media clip
/// carrying an action, a text clip, a shape clip and a nest clip showing an
/// inner nest a TIMELINE clip also shows, and — for `add_transition` — a
/// HARD CUT with handles on both sides of it (clip 13 abuts clip 7 and both
/// show media 1 with source left over). Rich enough that a plausible
/// envelope exists for all fifty-seven ops.
fn every_kind() -> Handle {
    Handle::from_value(&json!({
      "version": 6,
      "canvas": {"width":1920,"height":1080,"fps":[30,1],"background":[0.0,0.0,0.0,1.0],
                 "fit_new_clips":true,"timecode_frames":true},
      "media": [{"id":1,"path":"/f/1.mov","kind":"video","duration":60*SEC,"width":1920,
                 "height":1080,"fps":[30,1],"has_video":true,"has_audio":true}],
      "tracks": [{"id":2,"name":"T"}],
      "clips": [{"id":3,"track":2,"start":0,"duration":10*SEC,
                 "source":{"kind":"nest","project":4},"video":{}},
                {"id":40,"track":2,"start":12*SEC,"duration":2*SEC,
                 "source":{"kind":"nest","project":30},"video":{}}],
      "markers": [{"id":9,"time":SEC,"name":"M","chapter":false,"color":"red"}],
      "next_id": 100,
      "nests": [
        {"id":4,"name":"N","width":1920,"height":1080,
         "tracks":[{"id":5,"name":"A"},{"id":6,"name":"B"}],
         "clips":[
           {"id":7,"track":5,"start":0,"duration":2*SEC,
            "source":{"kind":"media","media":1,"in":0},"video":{},"audio":{},
            "actions":[{"id":8,"start":0,"duration":SEC,"curve":"linear","end":{}}]},
           {"id":10,"track":6,"start":0,"duration":2*SEC,"source":{"kind":"text"},
            "video":{},"text":{"content":"hi"}},
           {"id":11,"track":6,"start":3*SEC,"duration":SEC,"source":{"kind":"shape"},
            "video":{},"shape":{}},
           {"id":12,"track":5,"start":4*SEC,"duration":SEC,
            "source":{"kind":"nest","project":30},"video":{}},
           {"id":13,"track":5,"start":2*SEC,"duration":2*SEC,
            "source":{"kind":"media","media":1,"in":10*SEC},"video":{},"audio":{}}
         ]},
        {"id":30,"name":"Inner","width":1920,"height":1080,
         "tracks":[{"id":31,"name":"C"}],
         "clips":[{"id":32,"track":31,"start":0,"duration":SEC,
                   "source":{"kind":"text"},"video":{},"text":{"content":"in"}}]}
      ]
    }))
}

/// One plausible envelope per op, in `OP_NAMES` order. Plausible is the
/// point: an op handed arguments it would refuse on its own terms proves
/// nothing about whether it works inside a nest.
fn every_op() -> Vec<(&'static str, Value)> {
    let payload = json!({"clips":[{"id":1,"track":0,"start":0,"duration":SEC,
        "source":{"kind":"text"},"video":{},"text":{"content":"p"}}],"media":[]});
    vec![
        (
            "add_clip",
            json!({"op":"add_clip","track":5,"media":1,"at":20*SEC}),
        ),
        (
            "add_text_clip",
            json!({"op":"add_text_clip","track":5,"at":20*SEC}),
        ),
        (
            "add_shape_clip",
            json!({"op":"add_shape_clip","track":5,"at":20*SEC}),
        ),
        ("add_background", json!({"op":"add_background"})),
        (
            "add_blurred_background",
            json!({"op":"add_blurred_background","clip":7}),
        ),
        (
            "insert_clip",
            json!({"op":"insert_clip","track":5,"media":1,"at":SEC}),
        ),
        (
            "overwrite_clip",
            json!({"op":"overwrite_clip","track":5,"media":1,"at":0}),
        ),
        (
            "move_clip",
            json!({"op":"move_clip","clips":[10],"delta":6*SEC}),
        ),
        ("trim_start", json!({"op":"trim_start","clip":7,"to":SEC/2})),
        ("trim_end", json!({"op":"trim_end","clip":7,"to":SEC})),
        (
            "rate_stretch",
            json!({"op":"rate_stretch","clip":7,"to_end":4*SEC}),
        ),
        ("slip", json!({"op":"slip","clip":7,"delta":SEC})),
        ("roll", json!({"op":"roll","clip":11,"to":2*SEC+SEC/2})),
        ("split", json!({"op":"split","clips":[7],"at":SEC})),
        ("delete", json!({"op":"delete","clips":[11]})),
        ("ripple_delete", json!({"op":"ripple_delete","clips":[11]})),
        (
            "ripple_delete_range",
            json!({"op":"ripple_delete_range","from":SEC/2,"to":SEC}),
        ),
        (
            "ripple_delete_ranges",
            json!({"op":"ripple_delete_ranges","ranges":[[SEC/2,SEC]]}),
        ),
        (
            "lift_range",
            json!({"op":"lift_range","from":SEC/2,"to":SEC}),
        ),
        (
            "insert_time",
            json!({"op":"insert_time","at":SEC,"length":SEC}),
        ),
        (
            "close_gap",
            json!({"op":"close_gap","track":6,"at":2*SEC+SEC/2}),
        ),
        ("set_speed", json!({"op":"set_speed","clip":7,"rate":2.0})),
        (
            "set_reversed",
            json!({"op":"set_reversed","clip":7,"reversed":true}),
        ),
        (
            "freeze_frame",
            json!({"op":"freeze_frame","clip":7,"at":SEC}),
        ),
        ("detach_audio", json!({"op":"detach_audio","clip":7})),
        ("duplicate", json!({"op":"duplicate","clips":[11]})),
        ("paste", json!({"op":"paste","at":20*SEC,"payload":payload})),
        (
            "paste_attributes",
            json!({"op":"paste_attributes","clips":[10],
          "payload":{"clips":[{"id":1,"track":0,"start":0,"duration":SEC,
             "source":{"kind":"text"},"video":{"opacity":0.5},"text":{"content":"q"}}],
             "media":[]},"groups":["video"]}),
        ),
        ("nest", json!({"op":"nest","clips":[10,11]})),
        ("unnest", json!({"op":"unnest","clip":12})),
        (
            "set_video",
            json!({"op":"set_video","clips":[7],"patch":{"opacity":0.5}}),
        ),
        (
            "set_audio",
            json!({"op":"set_audio","clips":[7],"patch":{"volume":0.5}}),
        ),
        (
            "set_text",
            json!({"op":"set_text","clips":[10],"patch":{"size":40.0}}),
        ),
        (
            "set_shape",
            json!({"op":"set_shape","clips":[11],"patch":{"radius":4.0}}),
        ),
        (
            "set_clip",
            json!({"op":"set_clip","clips":[7],"patch":{"name":"n"}}),
        ),
        (
            "set_enabled",
            json!({"op":"set_enabled","clip":7,"video":false}),
        ),
        (
            "set_transition",
            json!({"op":"set_transition","clip":11,"kind":"wipe"}),
        ),
        (
            "set_transition_duration",
            json!({"op":"set_transition_duration","clip":11,"duration":SEC/2}),
        ),
        (
            "add_transition",
            json!({"op":"add_transition","clip":13,"duration":SEC}),
        ),
        (
            "set_transition_style",
            json!({"op":"set_transition_style","clip":13,"curve":"ease_in"}),
        ),
        ("add_action", json!({"op":"add_action","clip":10,"at":0})),
        (
            "add_zoom_action",
            json!({"op":"add_zoom_action","clip":10,"at":0,
          "region":{"x":0.0,"y":0.0,"width":100.0,"height":100.0}}),
        ),
        (
            "set_action",
            json!({"op":"set_action","clip":7,"action":8,"duration":SEC/2}),
        ),
        (
            "set_action_end",
            // The group is named, because an end patch is a subset of
            // `video` / `audio` / `text` (spec §5.4) and a bare `opacity`
            // is an unknown key. It read as one here for as long as the op
            // validated nothing: the op "worked" and animated nothing.
            json!({"op":"set_action_end","clip":7,"action":8,
          "patch":{"video":{"opacity":0.0}}}),
        ),
        (
            "remove_action",
            json!({"op":"remove_action","clip":7,"action":8}),
        ),
        ("add_track", json!({"op":"add_track"})),
        (
            "remove_track",
            json!({"op":"remove_track","track":6,"with_clips":true}),
        ),
        ("move_track", json!({"op":"move_track","track":6,"index":0})),
        ("set_track", json!({"op":"set_track","track":5,"solo":true})),
        ("remove_empty_tracks", json!({"op":"remove_empty_tracks"})),
        ("add_marker", json!({"op":"add_marker","at":SEC})),
        (
            "set_marker",
            json!({"op":"set_marker","marker":9,"time":2*SEC}),
        ),
        ("remove_marker", json!({"op":"remove_marker","marker":9})),
        ("set_canvas", json!({"op":"set_canvas","width":1280})),
        (
            "add_media",
            json!({"op":"add_media","descriptor":{"path":"/f/2.mov","kind":"video"}}),
        ),
        (
            "relink_media",
            json!({"op":"relink_media","media":1,"path":"/f/3.mov"}),
        ),
        (
            "remove_media",
            json!({"op":"remove_media","media":1,"with_clips":true}),
        ),
    ]
}

#[test]
fn every_op_in_the_table_works_inside_a_nest_except_the_seven() {
    // The empirical half of `scope.rs`'s exhaustive `refused_inside` match.
    // The match makes the compiler classify every op; this makes the
    // CLASSIFICATION true — that the fifty actually apply against a
    // real nest and come back through `validate` on the merged parent, and
    // that exactly seven do not.
    use reelcut_core::OP_NAMES;
    let base = every_kind();
    let table = every_op();

    let mut names: Vec<&str> = table.iter().map(|(name, _)| *name).collect();
    let mut expected: Vec<&str> = OP_NAMES.to_vec();
    names.sort_unstable();
    expected.sort_unstable();
    assert_eq!(
        names, expected,
        "the sweep must cover the op table exactly, with nothing missing \
         and nothing invented"
    );

    let refusals: Vec<&str> = refused().iter().map(|(name, _)| *name).collect();
    for (name, op) in table {
        let mut scoped = op.clone();
        scoped["scope"] = json!(4);
        let answer = base.try_apply(&scoped);
        if refusals.contains(&name) {
            assert_eq!(
                answer.err(),
                Some(format!("{name} has no meaning inside nest 4")),
                "{name} must refuse a scope"
            );
        } else {
            assert!(answer.is_ok(), "{name} inside a nest: {:?}", answer.err());
        }
    }
}

#[test]
fn the_same_seven_ops_still_work_without_a_scope() {
    // The refusal is about the scope and not about the op: each of these is
    // an ordinary edit on the timeline, which is what says the list bounds
    // a container rather than disabling a feature.
    let base = one_nest();
    base.apply(&json!({"op": "add_marker", "at": SEC}));
    base.apply(&json!({"op": "set_canvas", "width": 1280}));
    base.apply(&json!({"op": "add_media",
                       "descriptor": {"path": "/fixtures/2.mov", "kind": "video"}}));
    base.apply(&json!({"op": "relink_media", "media": 1, "path": "/fixtures/moved.mov"}));
    // `remove_media` refuses while a clip still shows the file, which is
    // its own documented rule — `with_clips` is the way through it.
    base.apply(&json!({"op": "remove_media", "media": 1, "with_clips": true}));
}

// ---- what the view cannot see: the caps ----------------------------------

/// A project holding `timeline` clips on one timeline track beside a nest
/// clip, and `inside` clips on the nest's one track.
fn packed(timeline: usize, inside: usize) -> Value {
    let mut clips: Vec<Value> = vec![nest_clip(3, 2, 0, 2 * SEC, 4)];
    let mut id = 100u32;
    for i in 0..timeline {
        clips.push(text_clip(id, 2, (3 + i as i64) * SEC, SEC));
        id += 1;
    }
    let mut nested: Vec<Value> = Vec::new();
    for i in 0..inside {
        nested.push(text_clip(id, 5, i as i64 * SEC, SEC));
        id += 1;
    }
    project(
        vec![video_media(1, "/fixtures/1.mov")],
        vec![track(2)],
        clips,
        vec![],
        vec![nest(4, 1920, 1080, vec![track(5)], nested)],
        id + 1,
    )
}

#[test]
fn the_clip_cap_is_the_documents_and_not_the_views() {
    // `check_caps` sums the timeline's clips with every nest's,
    // deliberately, so 64 nests of 64 tracks cannot slip past a cap that
    // exists to bound exactly that. A view holds the nest's clips and the
    // timeline's nowhere, so its own total is strictly lower — and this is
    // the case where the op succeeds against the view and the scoped apply
    // still answers `Err`.
    //
    // 4096 is MAX_CLIPS (RC_MAX_CLIPS in the header). One nest clip + 4090
    // timeline clips + 5 nested ones is exactly the cap.
    let full = Handle::from_value(&packed(4090, 5));
    assert_eq!(
        full.errors(&json!({"op": "add_text_clip", "track": 5, "at": 30 * SEC, "scope": 4})),
        "too many clips: 4097 (max 4096)"
    );
    // With room, the same op inside the same scope lands.
    let room = Handle::from_value(&packed(4089, 5));
    room.apply(&json!({"op": "add_text_clip", "track": 5, "at": 30 * SEC, "scope": 4}));
}

#[test]
fn the_track_cap_is_the_documents_and_not_the_views() {
    // 64 is MAX_TRACKS. The fixture's one timeline track and the nest's one
    // leave 62 to fill.
    let mut value = packed(0, 1);
    let mut tracks: Vec<Value> = vec![track(5)];
    for id in 200..262u32 {
        tracks.push(track(id));
    }
    value["nests"][0]["tracks"] = json!(tracks);
    value["next_id"] = json!(1000);
    let full = Handle::from_value(&value);
    assert_eq!(
        full.errors(&json!({"op": "add_track", "scope": 4})),
        "too many tracks: 65 (max 64)"
    );
}

// ---- what the view cannot see: the depth ---------------------------------

/// `depth` nests in a chain, each showing the next, with a timeline clip
/// showing the first — so the innermost sits at level `depth`.
/// `schema_v2.rs`'s own `chain`, rebuilt here because these tests need to
/// EDIT it rather than only read it.
fn chain(depth: u32) -> Value {
    let id = |level: u32| 100 + level * 10;
    let nests: Vec<Value> = (1..=depth)
        .map(|level| {
            let (nest_id, track_id, clip_id) = (id(level), id(level) + 1, id(level) + 2);
            let inner = if level == depth {
                text_clip(clip_id, track_id, 0, 2 * SEC)
            } else {
                nest_clip(clip_id, track_id, 0, 2 * SEC, id(level + 1))
            };
            nest(nest_id, 1920, 1080, vec![track(track_id)], vec![inner])
        })
        .collect();
    project(
        vec![],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 2 * SEC, id(1))],
        vec![],
        nests,
        1000,
    )
}

#[test]
fn the_nesting_depth_is_measured_from_the_timeline_and_not_from_the_view() {
    // `check_nesting` starts every walk at level 1, so a view cannot see
    // how deep the nest it is already sits: nesting inside the innermost
    // nest of an eight-deep chain is a level-9 stack the view validates
    // happily. Eight is MAX_NEST_DEPTH.
    let deep = Handle::from_value(&chain(8));
    let innermost = 180; // the eighth nest
    let msg = deep.errors(&json!({"op": "nest", "clips": [182], "scope": innermost}));
    assert_contains(&msg, "nests are more than 8 deep");

    // And one level shallower it lands, which is what says the refusal is
    // the depth and not a blanket ban on grouping inside a group.
    let shallow = Handle::from_value(&chain(7));
    let after = shallow
        .apply(&json!({"op": "nest", "clips": [172], "scope": 170}))
        .value();
    assert_eq!(
        nest_ids(&after).len(),
        8,
        "the new group is the eighth level"
    );
}

#[test]
fn nesting_the_whole_of_a_scope_is_a_legal_extra_level() {
    // Worth pinning, because "`nest` of the whole scope into itself" reads
    // like a cycle and is not one: `nest` mints a FRESH id and puts the new
    // nest clip INSIDE the scoped nest, so no clip ever points at its own
    // container.
    let base = one_nest();
    let after = base
        .apply(&json!({"op": "nest", "clips": [6, 7], "scope": 4}))
        .value();
    let inside = nest_of(&after, 4);
    let clips = array(&inside, "/clips");
    assert_eq!(clips.len(), 1, "the scope now holds one nest clip");
    let shows = int(&clips[0], "/source/project");
    assert_ne!(shows, 4, "a nest never shows itself");
    assert_eq!(nest_ids(&after).len(), 2);
    assert!(nest_ids(&after).contains(&shows));
}

// ---- the write-back: media -----------------------------------------------

fn payload_media(id: u32, path: &str) -> Value {
    json!({
        "id": id, "path": path, "kind": "video", "duration": 60 * SEC,
        "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

#[test]
fn a_paste_inside_a_scope_keeps_the_media_row_it_appended() {
    // `paste` appends a `media[]` row for every payload path the project
    // does not already carry. A write-back that dropped the view's media
    // would leave the pasted clip naming a media the parent has not got,
    // and the merged parent would fail `check_clips` — so this test is
    // green only because `media` is one of the four things merged back.
    let base = one_nest();
    let payload = json!({
        "clips": [{
            "id": 1, "track": 0, "start": 0, "duration": 2 * SEC,
            "source": {"kind": "media", "media": 9, "in": 0},
            "video": {}, "audio": {}
        }],
        "media": [payload_media(9, "/fixtures/pasted.mov")]
    });
    let after = base
        .apply(&json!({"op": "paste", "at": 4 * SEC, "payload": payload, "scope": 4}))
        .value();

    let rows = array(&after, "/media");
    assert_eq!(rows.len(), 2, "the parent gained the pasted row");
    let appended = rows
        .iter()
        .find(|m| text(m, "/path") == "/fixtures/pasted.mov")
        .expect("the pasted media is in the parent's list");
    let landed = array(&nest_of(&after, 4), "/clips")
        .iter()
        .find(|c| int(c, "/start") == 4 * SEC)
        .expect("the pasted clip landed inside the nest")
        .clone();
    assert_eq!(
        int(&landed, "/source/media"),
        int(appended, "/id"),
        "the pasted clip names the row the parent now holds"
    );
}

#[test]
fn a_paste_inside_a_scope_that_reuses_a_path_appends_nothing() {
    // The other half of `paste`'s media rule — matched by PATH — read
    // through a scope, so the straight replace cannot be hiding a duplicate.
    let base = one_nest();
    let payload = json!({
        "clips": [{
            "id": 1, "track": 0, "start": 0, "duration": 2 * SEC,
            "source": {"kind": "media", "media": 9, "in": 0},
            "video": {}, "audio": {}
        }],
        "media": [payload_media(9, "/fixtures/1.mov")]
    });
    let after = base
        .apply(&json!({"op": "paste", "at": 4 * SEC, "payload": payload, "scope": 4}))
        .value();
    assert_eq!(array(&after, "/media").len(), 1);
}

#[test]
fn a_paste_inside_a_scope_keeps_a_nest_it_brought_with_it() {
    // A payload's own nests are COPIED with fresh ids (`edit_paste.rs`), so
    // a paste inside a scope mints a nest the parent has never seen — the
    // merge's "appended by the view" arm, which the media test does not
    // reach.
    let base = one_nest();
    let payload = json!({
        "clips": [{
            "id": 1, "track": 0, "start": 0, "duration": 2 * SEC,
            "source": {"kind": "nest", "project": 50}, "video": {}
        }],
        "media": [],
        "nests": [{
            "id": 50, "name": "Brought", "width": 1920, "height": 1080,
            "tracks": [{"id": 51, "name": "T"}],
            "clips": [text_clip(52, 51, 0, 2 * SEC)]
        }]
    });
    let after = base
        .apply(&json!({"op": "paste", "at": 4 * SEC, "payload": payload, "scope": 4}))
        .value();

    assert_eq!(
        array(&after, "/nests").len(),
        2,
        "the parent holds the scoped nest and the pasted copy"
    );
    let brought = array(&after, "/nests")
        .iter()
        .find(|n| text(n, "/name") == "Brought")
        .expect("the pasted nest is in the parent's list")
        .clone();
    let landed = array(&nest_of(&after, 4), "/clips")
        .iter()
        .find(|c| int(c, "/start") == 4 * SEC)
        .expect("the pasted clip landed inside the scope")
        .clone();
    assert_eq!(
        int(&landed, "/source/project"),
        int(&brought, "/id"),
        "the pasted nest clip shows the copy the parent now holds"
    );
}

// ---- the write-back: nests -----------------------------------------------

/// A nest inside a nest, optionally shown by a timeline clip as well.
///
/// Nest 10 is the scope and holds one clip showing nest 20; nest 20 holds a
/// text clip. With `shared`, the TIMELINE also holds a clip showing nest 20
/// — two clips sharing one nest, which `duplicate` produces and
/// `nest.rs` pins.
fn inner_nest(shared: bool) -> Handle {
    let mut clips = vec![nest_clip(3, 2, 0, 2 * SEC, 10)];
    if shared {
        clips.push(nest_clip(4, 2, 2 * SEC, 2 * SEC, 20));
    }
    Handle::from_value(&project(
        vec![],
        vec![track(2)],
        clips,
        vec![],
        vec![
            nest(
                10,
                1920,
                1080,
                vec![track(11)],
                vec![
                    nest_clip(12, 11, 0, 2 * SEC, 20),
                    text_clip(13, 11, 2 * SEC, 2 * SEC),
                ],
            ),
            nest(
                20,
                1920,
                1080,
                vec![track(21)],
                vec![text_clip(22, 21, 0, 2 * SEC)],
            ),
        ],
        30,
    ))
}

#[test]
fn unnest_inside_a_scope_keeps_a_nest_a_timeline_clip_still_shows() {
    // `unnest` drops the nest it opened when `nest_is_shown` says nothing
    // else shows it, and `nest_is_shown` asks the project's own clips plus
    // every nest's. In a VIEW the project's own clips are the scoped nest's
    // and the timeline's are absent, so the view judges nest 20 unused and
    // drops it. The merge takes the union and re-asks the MERGED parent,
    // which can see the timeline clip that still shows it.
    //
    // Without that, this project comes back as
    // `clip 4 refers to unknown nest 20`.
    let base = inner_nest(true);
    let after = base
        .apply(&json!({"op": "unnest", "clip": 12, "scope": 10}))
        .value();

    let mut ids = nest_ids(&after);
    ids.sort_unstable();
    assert_eq!(ids, vec![10, 20], "the shared nest survived");
    // The scope did open: its nest clip became the text clip that was
    // inside nest 20, beside the text clip it already held.
    let inside = nest_of(&after, 10);
    let clips = array(&inside, "/clips");
    assert_eq!(clips.len(), 2);
    assert!(
        clips.iter().all(|c| text(c, "/source/kind") == "text"),
        "no nest clip is left inside the scope"
    );
    // And the timeline's own clip still shows nest 20, unchanged.
    assert_eq!(int(by_id(&after, "/clips", 4), "/source/project"), 20);
}

#[test]
fn unnest_inside_a_scope_still_drops_a_nest_nothing_shows() {
    // The other side of the same rule — "keep everything" would be a leak,
    // not a fix. With no timeline clip showing nest 20, the scoped unnest
    // takes it away exactly as an unscoped one would.
    let base = inner_nest(false);
    let after = base
        .apply(&json!({"op": "unnest", "clip": 12, "scope": 10}))
        .value();
    assert_eq!(nest_ids(&after), vec![10], "the orphaned nest went");
}

#[test]
fn a_scoped_edit_leaves_every_other_nest_exactly_as_it_was() {
    // The merge writes the scoped nest's tracks and clips and takes the
    // rest of `nests[]` from the parent, so an edit inside nest 10 must not
    // touch nest 20's own contents.
    let base = inner_nest(true);
    let before = nest_of(&base.value(), 20);
    let after = base
        .apply(&json!({"op": "add_text_clip", "track": 11, "at": 4 * SEC, "scope": 10}))
        .value();
    assert_eq!(nest_of(&after, 20), before);
}

#[test]
fn a_nest_that_another_nest_shows_can_still_be_scoped_into() {
    // The scoped nest's ROW has to stay in the view — emptied, not removed
    // — or `check_clips` refuses every OTHER nest that shows it, and "a
    // nest inside a nest" is what going one level in usually means. Nest 20
    // here is shown by nest 10's clip 12 AND by the timeline's clip 4. With
    // the row taken out of the view rather than emptied, the FIRST op
    // applied inside it comes back as
    // `clip 12 in nest 10 refers to unknown nest 20`.
    let base = inner_nest(true);
    let after = base
        .apply(&json!({"op": "add_text_clip", "track": 21, "at": 4 * SEC, "scope": 20}))
        .value();
    assert_eq!(
        array(&nest_of(&after, 20), "/clips").len(),
        2,
        "the edit landed inside the scope"
    );
    // Both clips that show it still show it, and the row came back with its
    // contents rather than with the view's emptied placeholder.
    assert_eq!(
        int(by_id(&nest_of(&after, 10), "/clips", 12), "/source/project"),
        20
    );
    assert_eq!(int(by_id(&after, "/clips", 4), "/source/project"), 20);
    assert_eq!(
        array(&nest_of(&after, 10), "/clips").len(),
        2,
        "the nest that shows the scope is untouched"
    );
}

#[test]
fn a_nest_made_inside_a_scope_is_appended_to_the_parents_list() {
    // Order matters for a diff of two saved files: the parent's own nests
    // keep their places and anything minted inside a scope goes on the end,
    // which is where `nest` and `paste` put one at the top level.
    let base = inner_nest(true);
    let after = base
        .apply(&json!({"op": "nest", "clips": [12, 13], "scope": 10}))
        .value();
    let ids = nest_ids(&after);
    assert_eq!(ids.len(), 3);
    assert_eq!(&ids[..2], &[10, 20], "the parent's order is untouched");
    assert!(ids[2] >= 30, "the new nest took an id from next_id");
}

// ---- ids, and the file --------------------------------------------------

#[test]
fn a_scoped_op_mints_ids_from_the_documents_one_counter() {
    // A nest holds its clips in the PARENT's id space (§5.2), so an id
    // minted inside a scope is minted for the whole document — and
    // `validate` demands `next_id` be past every id in it, which is what
    // makes this observable rather than a matter of taste.
    let base = one_nest();
    let before = int(&base.value(), "/next_id");
    let after = base
        .apply(&json!({"op": "duplicate", "clips": [7], "scope": 4}))
        .value();
    let copy = array(&nest_of(&after, 4), "/clips")
        .iter()
        .map(|c| int(c, "/id"))
        .max()
        .expect("the nest holds clips");
    assert_eq!(copy, before, "the copy took the next id");
    assert!(
        int(&after, "/next_id") > copy,
        "the counter advanced in the parent"
    );
}

#[test]
fn a_file_from_an_earlier_version_edits_through_a_scope() {
    // `scope` is an envelope key and persists nothing, so the phase's quiet
    // promise is that every earlier file still opens — and, since a nest
    // arrived in version 2, that a version-2 file can be edited through one.
    let mut value = project(
        vec![video_media(1, "/fixtures/1.mov")],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 4 * SEC, 4)],
        vec![],
        vec![nest(
            4,
            1920,
            1080,
            vec![track(5)],
            vec![media_clip(6, 5, 0, 2 * SEC, 1)],
        )],
        8,
    );
    for version in [2, 3, 4, 5, 6] {
        value["version"] = json!(version);
        let base = Handle::from_value(&value);
        let after = base
            .apply(&json!({"op": "trim_end", "clip": 6, "to": SEC, "scope": 4}))
            .value();
        assert_eq!(
            int(by_id(&nest_of(&after, 4), "/clips", 6), "/duration"),
            SEC,
            "a version-{version} file edits through a scope"
        );
    }
}

// ---- the read half: `rc_project_scoped` ----------------------------------
//
// A scope has to be LOOKED at as well as edited. `rc_project_scoped` hands
// the view over as an ordinary immutable handle so the app can play, plan,
// render and snapshot what is inside a nest while its edits still go to the
// parent's handle with `scope` set (spec §7.1, §7.4).
//
// The claim that matters is not that the export answers something plausible;
// it is that it answers the SAME project the edit path applies its op to.
// One function builds both (`Project::scoped_view`), and the first test
// below is what says so from the outside, without reading the source: a read
// view edited directly and an edit made through a scope and then read back
// come out equal, key for key.

#[test]
fn the_read_view_is_the_project_a_scoped_op_is_applied_to() {
    let base = one_nest();

    // The read view, edited with a PLAIN op — no scope, because inside this
    // handle the nest's clips are already the top level.
    let read = base
        .scoped(4)
        .apply(&json!({"op": "trim_end", "clip": 6, "to": SEC}))
        .value();

    // The same edit made the app's way — through the parent, with a scope —
    // and then read back out of the merged parent.
    let edited = base
        .apply(&json!({"op": "trim_end", "clip": 6, "to": SEC, "scope": 4}))
        .scoped(4)
        .value();

    assert_eq!(
        read, edited,
        "the read view and the edit view are one function"
    );
}

#[test]
fn the_read_view_is_the_nest_at_the_top_level() {
    let view = one_nest().scoped(4).value();

    // Its tracks and clips are the nest's, by id — not the timeline's.
    assert_eq!(
        array(&view, "/tracks")
            .iter()
            .map(|t| int(t, "/id"))
            .collect::<Vec<_>>(),
        vec![5]
    );
    assert_eq!(
        array(&view, "/clips")
            .iter()
            .map(|c| int(c, "/id"))
            .collect::<Vec<_>>(),
        vec![6, 7]
    );
    // The nest clip that SHOWS the nest is nowhere in it: it belongs to the
    // container, which is the whole point of going in.
    assert!(array(&view, "/clips").iter().all(|c| int(c, "/id") != 3));

    // The media is the parent's, in the parent's one id space, so a clip
    // inside can still name a file (spec §5.2).
    assert_eq!(
        array(&view, "/media")
            .iter()
            .map(|m| int(m, "/id"))
            .collect::<Vec<_>>(),
        vec![1]
    );

    // No markers: a nest has none, and the timeline's are project time.
    assert!(array(&view, "/markers").is_empty());

    // One id space, so the counter is the document's — which is what makes
    // an id minted inside unique across the whole file.
    assert_eq!(int(&view, "/next_id"), 8);
}

#[test]
fn the_read_views_canvas_is_the_nests_size_at_the_documents_rate() {
    // The half of a canvas a nest HAS is its frozen size; the half it has
    // not — the rate, the background and the two switches — comes from the
    // parent, and the rate matters most: there is one frame grid.
    let base = Handle::from_value(&project(
        vec![video_media(1, "/fixtures/1.mov")],
        vec![track(2)],
        vec![nest_clip(3, 2, 0, 2 * SEC, 4)],
        vec![],
        vec![nest(
            4,
            640,
            360,
            vec![track(5)],
            vec![media_clip(6, 5, 0, 2 * SEC, 1)],
        )],
        8,
    ));
    let view = base.scoped(4).value();
    assert_eq!(int(&view, "/canvas/width"), 640);
    assert_eq!(int(&view, "/canvas/height"), 360);
    assert_eq!(
        view.pointer("/canvas/fps"),
        base.value().pointer("/canvas/fps"),
        "the rate is the document's"
    );
    assert_eq!(
        view.pointer("/canvas/background"),
        base.value().pointer("/canvas/background")
    );
    assert_eq!(
        view.pointer("/canvas/fit_new_clips"),
        base.value().pointer("/canvas/fit_new_clips")
    );
    assert_eq!(
        view.pointer("/canvas/timecode_frames"),
        base.value().pointer("/canvas/timecode_frames")
    );
}

#[test]
fn the_read_view_keeps_the_scoped_nests_row_and_empties_it() {
    // `core/src/scope.rs` argues this at length and it is the one shape a
    // reader will otherwise "tidy up": the row has to stay, or a nest clip
    // elsewhere in the document dangles; its contents have to go, or every
    // id in it is counted twice by `validate`'s one uniqueness sweep. The
    // export answers a live handle, so the fact that it parsed at all is
    // half the proof; this pins the shape.
    let view = one_nest().scoped(4).value();
    let row = nest_of(&view, 4);
    assert!(
        array(&row, "/tracks").is_empty(),
        "the scoped row is emptied"
    );
    assert!(
        array(&row, "/clips").is_empty(),
        "the scoped row is emptied"
    );
    assert_eq!(int(&row, "/width"), 1920, "and keeps everything else");
}

#[test]
fn a_read_view_of_a_nest_inside_a_nest_keeps_the_other_nests_whole() {
    // The case the phase exists for. Scoping into the OUTER nest leaves the
    // inner one whole, because a clip in the view shows it; scoping into the
    // inner one leaves the outer one whole for the same reason it leaves
    // every other nest whole.
    let base = inner_nest(false);
    let outer = base.scoped(10).value();
    let inner = nest_of(&outer, 20);
    assert!(
        !array(&inner, "/clips").is_empty(),
        "the nest a view's own clip shows is whole"
    );
    assert_eq!(nest_ids(&outer), vec![10, 20]);

    let deep = base.scoped(20).value();
    let outer_row = nest_of(&deep, 10);
    assert!(
        !array(&outer_row, "/clips").is_empty(),
        "the nest that shows this one is whole"
    );
    assert!(array(&nest_of(&deep, 20), "/clips").is_empty());
}

#[test]
fn a_read_view_answers_the_questions_the_app_asks_a_project() {
    // The point of a handle rather than a JSON blob: everything the editor
    // draws from goes through the query exports, and they take a project.
    let view = one_nest().scoped(4);

    // The nest's own duration, measured from the nest's zero — NOT the
    // timeline's, and not the nest clip's.
    assert_eq!(view.duration(), 4 * SEC);

    // A plan and a recipe, naming the clips inside. The recipe at 1 s is the
    // media clip's, which on the timeline would be one layer inside a
    // flattened nest instead.
    let recipe = view.recipe(SEC);
    let layers = array(&recipe, "/layers");
    assert_eq!(layers.len(), 1);
    assert_eq!(int(&layers[0], "/clip"), 6);
    assert!(!view.plan_text().is_empty());
}

#[test]
fn a_read_view_of_an_unknown_nest_is_the_edit_paths_own_sentence() {
    // Byte for byte the message `apply` answers, because the two are the
    // same refusal about the same argument and a caller that learned one
    // must not have to learn the other.
    let base = one_nest();
    let read = base.try_scoped(99).expect_err("no nest 99");
    assert_contains(&read, "no nest with id 99");
    let edited = base.errors(&json!({"op": "trim_end", "clip": 6, "to": SEC, "scope": 99}));
    assert_eq!(read, edited);
}

#[test]
fn a_read_view_does_not_disturb_the_project_it_came_from() {
    // The handle is a new project, not a window onto this one: it is dropped
    // at the end of this test while `base` is read afterwards, which under
    // Miri or a double-free would not survive.
    let base = one_nest();
    let before = base.value();
    {
        let view = base.scoped(4);
        assert_eq!(view.duration(), 4 * SEC);
    }
    assert_eq!(base.value(), before);
}
