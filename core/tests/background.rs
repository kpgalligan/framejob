//! `add_background` and `add_blurred_background`, through the FFI — spec §6
//! and the module doc of `core/src/edit_background.rs`.
//!
//! Both ops mint a track and a clip and touch nothing else, so the strongest
//! thing a test can say about them is a WHOLE-DOCUMENT comparison, and there
//! are two of those. `a_blurred_copy_is_the_clip_with_five_fields_changed`
//! builds the answer by hand — the project before, plus a back track, plus
//! clip 10 with exactly the fields the op's contract changes — and asserts
//! equality, which pins what is copied as hard as what is not. The plate has
//! no such source clip to derive from, so `a_plate_is_one_canvas_sized
//! _rectangle` runs the comparison the other way round, through
//! `without_what_was_added`: take the new track and the new clip back out
//! and what is left must be the project it started as. Every other test here
//! is one claim pulled out of those two, so that a failure names itself.
//!
//! Five of those claims are the five things a blurred copy DROPS, and they
//! have a test each on purpose. Three would show up in a rendered frame; two
//! — `enabled.audio` and `audio.duck` — would not, and a proof built on
//! comparing pictures would pass with a background playing its own source's
//! sound underneath the original at roughly +6 dB, or ducking the whole mix
//! including that original. They are the two defects in this feature a still
//! frame cannot see, so they are the two asserted by name.
//!
//! Every expected number is computed here from the op's contract, never read
//! off a run: the fill scale of the 1280×800 source is
//! `max(1920/1280, 1080/800)` = 1.5 where its FIT scale is 1.35, and the
//! fill scale of the 3840×2400 one is `max(1920/3840, 1080/2400)` = 0.5
//! where its fit scale is 0.45. Both fixtures are sized so that fit and fill
//! differ — a square source would let one be mistaken for the other — which
//! is what lets the plate's own scale be pinned as FILL rather than as
//! `add_clip`'s Fit.

use serde_json::{json, Value};

mod common;
use common::{array, assert_contains, at, by_id, flag, int, num, text, Handle};

/// One frame of the 30 fps canvas every fixture here uses (600 000 ticks per
/// second, spec §5.1).
const FRAME: i64 = 20_000;
const SECOND: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

/// One clip of every kind a background command can be pointed at.
///
/// - Media 1 is 1280×800 — a 16:10 source on a 16:9 canvas, so its Fit scale
///   (1.35) and its Fill scale (1.5) DIFFER, which a square source would
///   hide. Media 2 is audio only and carries no size at all; media 3 is an
///   image LARGER than the canvas, so a plate of it is actually fitted;
///   media 4 is 16×16, small enough that its fill scale runs past the layer
///   maximum and has to clamp.
/// - Clip 10 is the interesting one: a trimmed window (`in` at 2 s), a
///   non-default video group with a crop, an offset, a rotation, a filter
///   and a `multiply` BLEND of its own, an audio group carrying a DUCK, an
///   action, a transition and both identity fields. Everything a copy might
///   wrongly carry is on it — the last two by name, because a copy that
///   kept the blend would be a black plate and a copy that kept the duck
///   would lower the mix under the clip it was copied from.
/// - Clips 20, 21 and 22 are a text clip, an audio-only clip and the tiny
///   one; 23 and 24 are a DEGENERATE shape (width and height 0, which only a
///   hand-written file can hold, since `validate` never checks the property
///   vocabulary) and an ordinary one beside it, so the positivity guard is
///   tested in both directions; clip 30 shows a nest, which is refused.
fn backdrop_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 6,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/screen.mov", "kind": "video", "duration": 36000000,
     "width": 1280, "height": 800, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/music.m4a", "kind": "audio", "duration": 18000000,
     "has_audio": true},
    {"id": 3, "path": "/m/wall.png", "kind": "image", "width": 3840, "height": 2400,
     "fps": [30, 1]},
    {"id": 4, "path": "/m/pip.mov", "kind": "video", "duration": 6000000,
     "width": 16, "height": 16, "fps": [30, 1], "has_video": true, "has_audio": false}
  ],
  "tracks": [
    {"id": 5, "name": "Picture"},
    {"id": 6, "name": "Extras"}
  ],
  "clips": [
    {"id": 10, "track": 5, "start": 6000000, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 1200000},
     "video": {"x": 40, "y": -20, "scale": 0.6, "rotation": 5, "opacity": 0.8,
               "crop": {"l": 100, "t": 50, "r": 100, "b": 50}, "corner_radius": 12,
               "filters": [{"kind": "sepia", "amount": 0.4}], "blend": "multiply"},
     "audio": {"volume": 0.7, "duck": {"level": 0.3, "attack": 300000, "release": 600000}},
     "actions": [{"id": 11, "start": 600000, "duration": 600000, "curve": "linear",
                  "end": {"video": {"scale": 1.2}}}],
     "transition_in": {"kind": "wipe"},
     "name": "Talk", "label": "blue"},
    {"id": 20, "track": 6, "start": 0, "duration": 3000000,
     "source": {"kind": "text"}, "video": {}, "text": {"content": "Hello"}},
    {"id": 21, "track": 6, "start": 3000000, "duration": 3000000,
     "source": {"kind": "media", "media": 2, "in": 0}, "audio": {}},
    {"id": 22, "track": 6, "start": 6000000, "duration": 3000000,
     "source": {"kind": "media", "media": 4, "in": 0}, "video": {}},
    {"id": 23, "track": 6, "start": 9000000, "duration": 1200000,
     "source": {"kind": "shape"}, "video": {},
     "shape": {"kind": "rectangle", "width": 0, "height": 0}},
    {"id": 24, "track": 6, "start": 10200000, "duration": 1800000,
     "source": {"kind": "shape"}, "video": {},
     "shape": {"kind": "rectangle", "width": 640, "height": 360}},
    {"id": 30, "track": 5, "start": 0, "duration": 3000000,
     "source": {"kind": "nest", "project": 31}, "video": {}}
  ],
  "markers": [],
  "next_id": 40,
  "nests": [
    {"id": 31, "name": "Nest 1", "width": 1280, "height": 720,
     "tracks": [{"id": 32, "name": "Nested"}],
     "clips": [{"id": 33, "track": 32, "start": 0, "duration": 3000000,
                "source": {"kind": "text"}, "video": {},
                "text": {"content": "Inside"}}]}
  ]
}"#,
    )
}

/// The ids the two ops mint against [`backdrop_project`], whose `next_id` is
/// 40: the TRACK takes the first and the clip the second (spec §6, and the
/// order `with_back_track` documents).
const NEW_TRACK: u32 = 40;
const NEW_CLIP: u64 = 41;

/// The timeline's own length in [`backdrop_project`] — clip 10 ends at 20 s,
/// later than anything else — which is what a plate with no `duration` runs
/// for.
const TIMELINE: i64 = 20 * SECOND;

/// A project of `count` tracks with one media clip on the back one, for the
/// reader caps. The clip's media has a pixel size, so the op gets all the
/// way to `finish` and the refusal is the cap's rather than its own.
fn wide_project(count: usize) -> Handle {
    let tracks: Vec<Value> = (0..count)
        .map(|i| json!({"id": 100 + i, "name": "t"}))
        .collect();
    Handle::from_value(&json!({
        "version": 5,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
                   "fit_new_clips": true, "timecode_frames": true},
        "media": [{"id": 1, "path": "/m/screen.mov", "kind": "video", "duration": 36000000,
                   "width": 1280, "height": 800, "fps": [30, 1],
                   "has_video": true, "has_audio": true}],
        "tracks": tracks,
        "clips": [{"id": 2, "track": 100, "start": 0, "duration": SECOND,
                   "source": {"kind": "media", "media": 1, "in": 0},
                   "video": {}, "audio": {}}],
        "markers": [],
        "next_id": 1000
    }))
}

/// A project of `count` clips, end to end on one track, for the clip cap.
fn crowded_project(count: usize) -> Handle {
    let clips: Vec<Value> = (0..count)
        .map(|i| {
            json!({"id": 1000 + i, "track": 100, "start": i as i64 * SECOND,
                   "duration": SECOND, "source": {"kind": "media", "media": 1, "in": 0},
                   "video": {}, "audio": {}})
        })
        .collect();
    Handle::from_value(&json!({
        "version": 5,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
                   "fit_new_clips": true, "timecode_frames": true},
        "media": [{"id": 1, "path": "/m/screen.mov", "kind": "video", "duration": 36000000,
                   "width": 1280, "height": 800, "fps": [30, 1],
                   "has_video": true, "has_audio": true}],
        "tracks": [{"id": 100, "name": "t"}],
        "clips": clips,
        "markers": [],
        "next_id": 100000
    }))
}

// ---- reading -------------------------------------------------------------

/// The clip the op just added, in the project it produced.
fn added(project: &Value) -> &Value {
    by_id(project, "/clips", NEW_CLIP)
}

/// `after` with the new back track and the new clip taken back out, and its
/// `next_id` wound back — so what is left must equal the project before the
/// op ran. That comparison is how a test says "and NOTHING else moved"
/// without writing down the whole property vocabulary, which grows a key or
/// two every format version and would make the oracle stale rather than
/// wrong.
fn without_what_was_added(after: &Value, before: &Value) -> Value {
    let mut stripped = after.clone();
    let tracks = stripped["tracks"].as_array_mut().expect("the tracks array");
    let track = tracks.remove(0);
    assert_eq!(
        int(&track, "/id"),
        i64::from(NEW_TRACK),
        "the op's track is the back-most one"
    );
    let clips = stripped["clips"].as_array_mut().expect("the clips array");
    let clip = clips.pop().expect("the op appended a clip");
    assert_eq!(
        int(&clip, "/id"),
        NEW_CLIP as i64,
        "the op's clip is the last one"
    );
    stripped["next_id"] = before["next_id"].clone();
    stripped
}

// ---- the blurred copy: what it lands on -----------------------------------

#[test]
fn the_copy_lands_alone_on_a_new_back_most_track() {
    let project = backdrop_project();
    let before = project.value();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();

    // One more track than before, and the new one is at index 0 — the
    // back-most, which is the only place a background is behind everything
    // whatever the stack already held.
    assert_eq!(
        array(&after, "/tracks").len(),
        array(&before, "/tracks").len() + 1
    );
    assert_eq!(int(&after, "/tracks/0/id"), i64::from(NEW_TRACK));
    assert_eq!(text(&after, "/tracks/0/name"), "Track 3");
    // The tracks that were there keep their order behind it.
    assert_eq!(int(&after, "/tracks/1/id"), 5);
    assert_eq!(int(&after, "/tracks/2/id"), 6);

    // And it is alone there.
    let on_new: Vec<i64> = array(&after, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == i64::from(NEW_TRACK))
        .map(|c| int(c, "/id"))
        .collect();
    assert_eq!(on_new, vec![NEW_CLIP as i64]);
}

#[test]
fn the_copy_plays_the_same_frames_as_the_clip_it_copies() {
    // The whole reason this is a core op: re-placing the media with
    // `add_clip` would give the WHOLE media, and a backdrop showing
    // different frames from the foreground is the one thing it may not do.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    let copy = added(&after);

    assert_eq!(int(copy, "/start"), 10 * SECOND);
    assert_eq!(int(copy, "/duration"), 10 * SECOND);
    assert_eq!(text(copy, "/source/kind"), "media");
    assert_eq!(int(copy, "/source/media"), 1);
    assert_eq!(int(copy, "/source/in"), 2 * SECOND);
    assert_eq!(num(copy, "/speed"), 1.0);
}

#[test]
fn the_clip_it_copies_is_left_exactly_as_it_was() {
    let project = backdrop_project();
    let before = project.value();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    assert_eq!(by_id(&after, "/clips", 10), by_id(&before, "/clips", 10));
}

// ---- the blurred copy: the four drops -------------------------------------

#[test]
fn the_copy_is_muted_and_the_original_is_not() {
    // The drop no rendered frame can see. The copy carries the same media,
    // the same in point and the same span, so a mix that played both would
    // play one source twice — roughly +6 dB and comb filtering — and
    // `detect_silence` and the level meter would both read the wrong number.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    let copy = added(&after);

    assert!(!flag(copy, "/enabled/audio"), "the copy must be muted");
    // The other half of `detach_audio`'s pair: the copy exists to DRAW, so a
    // hidden foreground clip must not mint a hidden backdrop.
    assert!(flag(copy, "/enabled/video"), "the copy must draw");
    assert!(flag(by_id(&after, "/clips", 10), "/enabled/audio"));

    // The rest of the group travels — a volume is a fact about the clip and
    // is inert once nothing plays it, exactly as `detach_audio` carries it.
    assert_eq!(num(copy, "/audio/volume"), 0.7);
}

#[test]
fn the_copy_drops_the_duck_and_keeps_the_rest_of_the_audio_group() {
    // The second drop no rendered frame can see, and the one field of the
    // audio group that is not about this clip's OWN sound. `duckers` gathers
    // a duck from the flattened timeline with no test of `enabled.audio`, a
    // mute or a solo, and `audio_ramps` can only exclude a ducker that is a
    // voice on the track being ramped — the copy is a voice nowhere. So a
    // copy that kept the duck would lower every other track AND the clip it
    // was copied from: clip 10 ducked to 0.3 by its own backdrop, and a bed
    // on another track ducked twice, to 0.09.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    let copy = added(&after);

    assert!(
        at(copy, "/audio/duck").is_null(),
        "a picture command may not change the sound"
    );
    assert_eq!(num(copy, "/audio/volume"), 0.7, "and only the duck goes");
    // The original keeps the duck it was carrying: it is still audible, and
    // ducking is what its author asked for.
    assert_eq!(num(by_id(&after, "/clips", 10), "/audio/duck/level"), 0.3);
}

#[test]
fn the_copy_composites_normally_however_the_clip_in_front_blends() {
    // The back-most layer's destination is the CANVAS — black by default —
    // so a copy that inherited `multiply` would render solid black and the
    // command would look like it did nothing, and `screen`, `add` and
    // `lighten` over black would leave the backdrop unblended. A blend mode
    // is a choice about what is UNDER a picture, and the copy's destination
    // is not the one it was chosen against.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    assert_eq!(text(added(&after), "/video/blend"), "normal");
    // The clip in front keeps the mode its author picked.
    assert_eq!(text(&after, "/clips/0/video/blend"), "multiply");
    // And the two commands now agree: a plate's `VideoProps::default()` is
    // `normal` too, which is the property that decides whether a backdrop is
    // visible at all.
    let plate = project.apply(&json!({"op": "add_background"})).value();
    assert_eq!(text(added(&plate), "/video/blend"), "normal");
}

#[test]
fn the_copy_drops_its_transition() {
    // A `transition_in` describes an overlap on the ORIGINAL track; the copy
    // is alone on a new one and has no predecessor to dissolve from.
    let project = backdrop_project();
    let before = project.value();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    assert_eq!(text(&before, "/clips/0/transition_in/kind"), "wipe");
    assert!(at(added(&after), "/transition_in").is_null());
}

#[test]
fn the_copy_drops_its_actions() {
    // A zoom on the foreground would otherwise animate the backdrop out from
    // under it, which is the opposite of what a background is for.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    assert!(array(added(&after), "/actions").is_empty());
    // The original keeps its own.
    assert_eq!(array(&after, "/clips/0/actions").len(), 1);
}

#[test]
fn the_copy_is_named_and_unlabelled() {
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    let copy = added(&after);
    assert_eq!(text(copy, "/name"), "Blurred Background");
    // A label is a mark the user put on ONE clip; copying it would file the
    // backdrop under a category nobody chose for it.
    assert!(at(copy, "/label").is_null());
    assert_eq!(text(by_id(&after, "/clips", 10), "/label"), "blue");
}

// ---- the blurred copy: the derived values ---------------------------------

#[test]
fn the_copy_fills_the_canvas_uncropped_and_centred() {
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    let copy = added(&after);

    // Fill, not fit: max(1920/1280, 1080/800) = max(1.5, 1.35). The fit
    // scale of the same source is 1.35, so this number tells the two apart.
    assert_eq!(num(copy, "/video/scale"), 1.5);
    assert_eq!(num(copy, "/video/x"), 0.0);
    assert_eq!(num(copy, "/video/y"), 0.0);
    for edge in ["l", "t", "r", "b"] {
        assert_eq!(num(copy, &format!("/video/crop/{edge}")), 0.0);
    }
}

#[test]
fn the_copy_carries_one_full_strength_blur_and_nothing_else() {
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    let copy = added(&after);

    // REPLACED, not appended: the clip's own sepia would fight the blur, and
    // MAX_FILTERS is 4, so appending could overflow a full stack.
    let filters = array(copy, "/video/filters");
    assert_eq!(filters.len(), 1);
    assert_eq!(text(&filters[0], "/kind"), "blur");
    assert_eq!(num(&filters[0], "/amount"), 1.0);
    assert_eq!(text(&after, "/clips/0/video/filters/0/kind"), "sepia");
}

#[test]
fn the_copy_keeps_every_video_property_it_does_not_overwrite() {
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    let copy = added(&after);
    assert_eq!(num(copy, "/video/opacity"), 0.8);
    assert_eq!(num(copy, "/video/rotation"), 5.0);
    assert_eq!(num(copy, "/video/corner_radius"), 12.0);
}

#[test]
fn a_fill_scale_past_the_layer_maximum_clamps_rather_than_refusing() {
    // Clip 22 shows a 16×16 source: max(1920/16, 1080/16) is 120, well past
    // SCALE_MAX. The op gives back the biggest legal magnification, the
    // trade `edit_zoom.rs` makes for the same constant — a backdrop that is
    // as large as the schema allows beats a command that refuses.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 22}))
        .value();
    assert_eq!(num(added(&after), "/video/scale"), 10.0);
}

#[test]
fn a_shape_clip_fills_from_its_own_box() {
    // Clip 24 is a 640×360 rectangle on a 1920×1080 canvas: max(3, 3). The
    // positive half of the positivity guard below — a shape is an ordinary
    // source with a size the model can read, and only a degenerate one is
    // refused.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 24}))
        .value();
    assert_eq!(num(added(&after), "/video/scale"), 3.0);
}

// ---- the blurred copy: the whole document ---------------------------------

#[test]
fn a_blurred_copy_is_the_clip_with_five_fields_changed() {
    // The oracle is written from the op's contract, not captured from a run:
    // the project before, plus a back track, plus clip 10 with its identity,
    // its switches, its actions, its transition, its duck and six video keys
    // changed. Everything the op must NOT touch is inherited by
    // construction — which is exactly why the fixture carries a `multiply`
    // and a duck: an inherited one fails HERE as well as in its own test.
    let project = backdrop_project();
    let before = project.value();
    let after = project
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();

    let mut expected = before.clone();
    expected["tracks"]
        .as_array_mut()
        .expect("the tracks array")
        .insert(
            0,
            json!({"id": NEW_TRACK, "name": "Track 3", "hidden": false, "muted": false,
                   "locked": false, "solo": false}),
        );

    let mut copy = by_id(&before, "/clips", 10).clone();
    copy["id"] = json!(NEW_CLIP);
    copy["track"] = json!(NEW_TRACK);
    copy["enabled"] = json!({"video": true, "audio": false});
    copy["actions"] = json!([]);
    copy["transition_in"] = Value::Null;
    copy["name"] = json!("Blurred Background");
    copy["label"] = Value::Null;
    copy["video"]["scale"] = json!(1.5);
    copy["video"]["x"] = json!(0.0);
    copy["video"]["y"] = json!(0.0);
    copy["video"]["crop"] = json!({"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0});
    copy["video"]["filters"] = json!([{"kind": "blur", "amount": 1.0}]);
    copy["video"]["blend"] = json!("normal");
    copy["audio"]["duck"] = Value::Null;
    expected["clips"]
        .as_array_mut()
        .expect("the clips array")
        .push(copy);
    expected["next_id"] = json!(NEW_CLIP + 1);

    assert_eq!(after, expected);
}

#[test]
fn an_op_that_mints_two_objects_creates_the_track_first() {
    // The envelope's id promise (`edit.rs`) used to name "the TWO ops that
    // mint two objects", and it was wrong about a third: `detach_audio` on a
    // clip already on the BOTTOM track allocates a track and then a clip in
    // exactly this order, and `nest` mints a nest, a track per track it
    // swallows, and its clip last. So the rule is the ORDER — ids in the
    // order the op creates its objects — and this pins the two ops it was
    // written for against the one it forgot. A caller reading the old
    // sentence would have computed the detached audio clip's id as `next_id`
    // and got the new TRACK's.
    let project = backdrop_project();
    for op in [
        json!({"op": "add_blurred_background", "clip": 10}),
        json!({"op": "add_background"}),
        json!({"op": "detach_audio", "clip": 10}),
    ] {
        let after = project.apply(&op).value();
        assert_eq!(
            int(&after, "/tracks/0/id"),
            i64::from(NEW_TRACK),
            "the track takes the `next_id` the call was made with ({op})"
        );
        let minted = after
            .get("clips")
            .and_then(Value::as_array)
            .expect("the clips array")
            .last()
            .expect("the op appended a clip");
        assert_eq!(
            int(minted, "/id"),
            NEW_CLIP as i64,
            "and the clip takes the one after it ({op})"
        );
        assert_eq!(int(minted, "/track"), i64::from(NEW_TRACK));
    }
}

#[test]
fn each_call_adds_its_own_track_behind_the_last() {
    // Always a NEW track, never the back-most existing one: there is nothing
    // to overlap, nothing to push aside, and one undo step takes it away.
    let project = backdrop_project();
    let once = project.apply(&json!({"op": "add_blurred_background", "clip": 10}));
    let twice = once
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    assert_eq!(array(&twice, "/tracks").len(), 4);
    // The second copy is behind the first, which has moved up one.
    assert_eq!(int(&twice, "/tracks/0/id"), 42);
    assert_eq!(int(&twice, "/tracks/1/id"), i64::from(NEW_TRACK));
}

// ---- the blurred copy: the refusals ---------------------------------------

#[test]
fn a_source_with_no_pixel_size_is_refused_by_name() {
    let project = backdrop_project();
    // Text: only the platform can measure a layout (spec §5.3).
    let message = project.errors(&json!({"op": "add_blurred_background", "clip": 20}));
    assert_eq!(
        message,
        "clip 20's source has no pixel size, so nothing can be scaled to fill the canvas"
    );
    // Audio-only: the descriptor carries no size at all.
    let message = project.errors(&json!({"op": "add_blurred_background", "clip": 21}));
    assert_contains(&message, "clip 21's source has no pixel size");
}

#[test]
fn a_degenerate_shape_is_refused_rather_than_scaled_from_nothing() {
    // Clip 23 is a rectangle of width and height 0 — which only a
    // hand-written or third-party file can hold, since `validate` checks
    // ids, caps and the canvas and never the property vocabulary. Without
    // the positivity guard the shape arm hands `fill_scale` a zero, it
    // computes `inf.max(inf)`, fails `is_finite()` and answers 1.0, and the
    // op succeeds with a bogus scale instead of saying what is wrong. The
    // media and nest arms have always guarded; this one had not.
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_blurred_background", "clip": 23}));
    assert_eq!(
        message,
        "clip 23's source has no pixel size, so nothing can be scaled to fill the canvas"
    );
    assert_eq!(project.value(), backdrop_project().value());
}

#[test]
fn a_nest_clip_is_refused_because_the_blur_would_reach_no_layer() {
    // Not about the SIZE — a nest has a frozen canvas and the size reader
    // answers with it. It is about the BLUR. A nest clip never becomes a
    // layer: flattening folds its placement down onto the clips inside it
    // and drops every per-pixel property it carries, so `recipe.rs::layer`
    // reads `filters` off the INNER clip. The blur this op writes would
    // reach nothing and the command would report success having minted a
    // SHARP 1.5× duplicate behind the original, at double the render cost.
    // The same call `check_blend` makes about `video.blend` on a nest clip.
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_blurred_background", "clip": 30}));
    assert_eq!(
        message,
        "clip 30 shows a nest, whose own filters the flattening drops, \
         so a blurred copy of it would come out sharp"
    );
    assert_eq!(project.value(), backdrop_project().value());
}

#[test]
fn a_filter_on_a_nest_clip_reaches_no_layer_at_all() {
    // The fact the refusal above rests on, measured rather than asserted —
    // and the third of the four things `nest.rs`'s `Frame` doc records as
    // not surviving the flattening. Put a full-strength blur on the nest
    // clip itself and the frame recipe does not change by a byte: the walk
    // folds a nest clip's PLACEMENT down onto the clips inside it and drops
    // every per-pixel property it carries, so `recipe.rs::layer` reads
    // `filters` off the INNER clip and never off the container. That is why
    // `add_blurred_background` refuses a nest instead of writing a blur into
    // a field nothing reads, and it is the same reason `check_blend` refuses
    // `video.blend` there.
    let project = backdrop_project();
    let before = project.recipe(0);
    let blurred = project.apply(&json!({
        "op": "set_video", "clips": [30],
        "patch": {"filters": [{"kind": "blur", "amount": 1.0}]}
    }));
    // The model took it — this is not a refusal in disguise.
    let stored = blurred.value();
    assert_eq!(
        num(by_id(&stored, "/clips", 30), "/video/filters/0/amount"),
        1.0
    );
    assert_eq!(blurred.recipe(0), before, "and no layer heard about it");
}

#[test]
fn an_unknown_clip_is_refused_by_name() {
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_blurred_background", "clip": 99}));
    assert_eq!(message, "no clip with id 99");
}

#[test]
fn a_refused_blurred_background_places_nothing() {
    // Purity across the FFI: `rc_project_apply` hands back NULL and a
    // message, and the handle the caller still holds is the project it
    // always was — no half-added track, no minted id.
    let project = backdrop_project();
    let before = project.value();
    let _ = project.errors(&json!({"op": "add_blurred_background", "clip": 20}));
    assert_eq!(project.value(), before);
}

#[test]
fn the_track_cap_refuses_a_blurred_background() {
    // 64 tracks is the reader's cap, so the extra one is one too many. The
    // refusal comes from `finish` through `validate`, which is what makes it
    // impossible for any op to write a file the reader would reject.
    let project = wide_project(64);
    let message = project.errors(&json!({"op": "add_blurred_background", "clip": 2}));
    assert_eq!(message, "too many tracks: 65 (max 64)");
    // One track short of the cap, the same call works.
    let project = wide_project(63);
    assert_eq!(
        array(
            &project
                .apply(&json!({"op": "add_blurred_background", "clip": 2}))
                .value(),
            "/tracks"
        )
        .len(),
        64
    );
}

#[test]
fn the_clip_cap_refuses_a_blurred_background() {
    let project = crowded_project(4096);
    let message = project.errors(&json!({"op": "add_blurred_background", "clip": 1000}));
    assert_eq!(message, "too many clips: 4097 (max 4096)");
}

// ---- the plate ------------------------------------------------------------

#[test]
fn a_plate_is_one_canvas_sized_rectangle() {
    // The whole document again: a back track, and one shape clip from 0 to
    // the timeline's own end. Nothing else moves.
    let project = backdrop_project();
    let before = project.value();
    let after = project.apply(&json!({"op": "add_background"})).value();

    assert_eq!(without_what_was_added(&after, &before), before);
    assert_eq!(int(&after, "/next_id"), NEW_CLIP as i64 + 1);
    assert_eq!(text(&after, "/tracks/0/name"), "Track 3");

    let plate = added(&after);
    assert_eq!(int(plate, "/track"), i64::from(NEW_TRACK));
    assert_eq!(int(plate, "/start"), 0);
    assert_eq!(int(plate, "/duration"), TIMELINE);
    assert_eq!(text(plate, "/source/kind"), "shape");
    assert_eq!(text(plate, "/name"), "Background");
    assert_eq!(text(plate, "/shape/kind"), "rectangle");
    assert_eq!(num(plate, "/shape/width"), 1920.0);
    assert_eq!(num(plate, "/shape/height"), 1080.0);
    // No stroke: a plate is an area, and a border round the canvas is not
    // what anyone asked for. Scale 1 because the rectangle IS the canvas.
    assert!(at(plate, "/shape/stroke").is_null());
    assert_eq!(num(plate, "/video/scale"), 1.0);
    assert!(at(plate, "/audio").is_null());
    assert!(at(plate, "/text").is_null());
    assert!(array(plate, "/actions").is_empty());
}

#[test]
fn the_default_plate_is_white() {
    // Not black. The canvas background is already black, so a black plate is
    // a command that appears to do nothing; white is visible on arrival, it
    // is the neutral plate to re-colour, and it is `multiply`'s identity.
    let project = backdrop_project();
    let after = project.apply(&json!({"op": "add_background"})).value();
    let fill = array(added(&after), "/shape/fill");
    assert_eq!(
        fill.iter()
            .map(|c| c.as_f64().unwrap())
            .collect::<Vec<f64>>(),
        vec![1.0, 1.0, 1.0, 1.0]
    );
}

#[test]
fn a_named_colour_is_the_plates_fill() {
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_background", "color": [0.2, 0.4, 0.6, 1.0]}))
        .value();
    let plate = added(&after);
    assert_eq!(num(plate, "/shape/fill/0"), 0.2);
    assert_eq!(num(plate, "/shape/fill/1"), 0.4);
    assert_eq!(num(plate, "/shape/fill/2"), 0.6);
    assert_eq!(num(plate, "/shape/fill/3"), 1.0);
}

#[test]
fn a_colour_outside_the_unit_range_is_refused_by_name() {
    // The caller's colour reaches the same check a `set_shape` of it would,
    // so 0–255 units are named here rather than blown out on the canvas.
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_background", "color": [255, 0, 0, 1]}));
    assert_contains(&message, "shape.fill must be between 0 and 1, not 255");
}

#[test]
fn an_image_plate_covers_the_canvas_rather_than_fitting_inside_it() {
    // Media 3 is 3840×2400, larger than the canvas in both axes. FILL is
    // max(1920/3840, 1080/2400) = max(0.5, 0.45) = 0.5; `add_clip`'s FIT
    // would be 0.45 and would leave a 54-pixel bar top and bottom. The plate
    // is shaped as `add_clip` would shape it in every other respect, and
    // this number is the one difference.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_background", "media": 3}))
        .value();
    let plate = added(&after);
    assert_eq!(text(plate, "/source/kind"), "image");
    assert_eq!(int(plate, "/source/media"), 3);
    assert_eq!(num(plate, "/video/scale"), 0.5);
    assert_eq!(int(plate, "/duration"), TIMELINE);
    assert_eq!(text(plate, "/name"), "Background");
    assert!(at(plate, "/shape").is_null());
    // The image has no sound, so it gets no audio group — `add_clip`'s rule.
    assert!(at(plate, "/audio").is_null());
}

#[test]
fn a_plate_smaller_than_the_canvas_is_scaled_up_to_cover_it() {
    // The case Fit cannot serve at all: 1280×800 already fits inside
    // 1920×1080, and Fit is a rescue for oversized footage that never scales
    // UP, so it would answer 1.0 and leave the picture floating in the
    // middle of a black canvas — 320 pixels of it showing down each side.
    // FILL is max(1.5, 1.35) = 1.5.
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_background", "media": 1}))
        .value();
    let plate = added(&after);
    assert_eq!(text(plate, "/source/kind"), "media");
    assert_eq!(int(plate, "/source/in"), 0);
    assert_eq!(num(plate, "/video/scale"), 1.5);
    // A movie keeps the audio group `add_clip` would give it.
    assert!(!at(plate, "/audio").is_null());
}

#[test]
fn a_plates_scale_does_not_depend_on_fit_new_clips() {
    // The other half of the argument, and the part a Fit plate gets wrong
    // twice: `canvas.fit_new_clips` is a flag about NEW CLIPS and has no
    // opinion about backgrounds, but Fit consults it, so a plate's coverage
    // would turn on a setting nobody associates with this command. Fill
    // ignores it — the same scale with the flag off as with it on.
    let project = backdrop_project();
    let off = project
        .apply(&json!({"op": "set_canvas", "fit_new_clips": false}))
        .apply(&json!({"op": "add_background", "media": 3}))
        .value();
    assert_eq!(num(added(&off), "/video/scale"), 0.5);
    // And a blurred copy has always ignored it, which is what the two
    // commands now agree about.
    let off = project
        .apply(&json!({"op": "set_canvas", "fit_new_clips": false}))
        .apply(&json!({"op": "add_blurred_background", "clip": 10}))
        .value();
    assert_eq!(num(added(&off), "/video/scale"), 1.5);
}

#[test]
fn a_media_with_no_pictures_cannot_be_a_plate() {
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_background", "media": 2}));
    assert_eq!(
        message,
        "media 2 has no pixel size, so it cannot be a background"
    );
}

#[test]
fn a_media_and_a_colour_together_are_refused() {
    // Alternatives, not a pair: a caller that named both meant one of them,
    // and a precedence rule here is one nobody would remember.
    let project = backdrop_project();
    let message =
        project.errors(&json!({"op": "add_background", "media": 1, "color": [1, 0, 0, 1]}));
    assert_contains(&message, "takes a media or a color, not both");
    assert_contains(&message, "media 1");
}

#[test]
fn an_unknown_media_is_refused_by_name() {
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_background", "media": 99}));
    assert_eq!(message, "no media with id 99");
}

// ---- the plate's length ---------------------------------------------------

#[test]
fn a_given_duration_is_the_plates_length() {
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_background", "duration": 3 * SECOND}))
        .value();
    assert_eq!(int(added(&after), "/duration"), 3 * SECOND);
}

#[test]
fn a_plate_on_an_empty_timeline_is_one_frame_long() {
    // `duration()` is 0 with nothing on the timeline, and a zero-length clip
    // is not a thing the timeline can hold — `validate` refuses one.
    let project = Handle::new(1920, 1080, 30, 1);
    let after = project.apply(&json!({"op": "add_background"})).value();
    let plate = by_id(&after, "/clips", 3);
    assert_eq!(int(plate, "/duration"), FRAME);
    assert_eq!(int(plate, "/track"), 2);
    assert_eq!(int(&after, "/tracks/0/id"), 2);
}

#[test]
fn a_duration_under_a_frame_is_refused_rather_than_floored() {
    // The envelope's rule for a length (`edit.rs`): a negative or sub-frame
    // length is the caller's arithmetic mistake, and answering a bug with a
    // clip is worse than answering it with a message.
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_background", "duration": 0}));
    assert_eq!(
        message,
        "background duration must be at least one frame (20000 ticks), not 0"
    );
    let message = project.errors(&json!({"op": "add_background", "duration": -SECOND}));
    assert_contains(&message, "not -600000");
}

#[test]
fn a_duration_off_the_grid_is_snapped_like_every_other_length() {
    let project = backdrop_project();
    let after = project
        .apply(&json!({"op": "add_background", "duration": 3 * SECOND + 7}))
        .value();
    assert_eq!(int(added(&after), "/duration"), 3 * SECOND);
}

// ---- the envelope ---------------------------------------------------------

#[test]
fn a_misspelt_argument_is_refused_by_name() {
    // `deny_unknown_fields` on every op variant: a typo in a hand-written or
    // generated call is a mistake to report, not an argument to drop.
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_background", "colour": [1, 1, 1, 1]}));
    assert_contains(&message, "colour");
    let message = project.errors(&json!({"op": "add_blurred_background", "clips": [10]}));
    assert_contains(&message, "add_blurred_background");
    assert_contains(&message, "clips");
}

#[test]
fn both_ops_are_in_the_table_the_envelope_publishes() {
    let project = backdrop_project();
    let message = project.errors(&json!({"op": "add_backgroundd"}));
    assert_contains(&message, "unknown op \"add_backgroundd\"");
    assert_contains(&message, "add_background");
    assert_contains(&message, "add_blurred_background");
}
