//! `add_zoom_action`, through the FFI — spec §6, and the placement equation
//! in `core/src/edit_zoom.rs`'s module doc.
//!
//! Every expected number here was computed BY HAND from that equation and
//! is written as arithmetic a reader can check without running anything —
//! `min(1920/480, 1080/270) = 4`, `−4 × 480 = −1920` — because the point of
//! the op is that the core owns the maths, and a test that echoed whatever
//! the implementation produced would prove only that it is deterministic.
//!
//! Two conventions worth knowing before reading a case:
//!
//! - The unrotated cases assert EXACT equality. Every one of them is a
//!   division and a multiplication of numbers whose results are exactly
//!   representable (or, for `1080/600`, correctly rounded to the same
//!   double the literal `1.8` is), and a tolerance there would hide the
//!   very drift the test exists to catch. The rotated cases go through
//!   `cos`/`sin` and use a tolerance far tighter than any real error.
//! - The first case is the load-bearing one: a region equal to the whole
//!   cropped source under `fit` must give exactly VideoPane's "Fit to
//!   Canvas" scale, `min(cw/sw, ch/sh)`, at `x = y = 0`. That button is
//!   deliberately NOT re-expressed through this op — it writes BASE props
//!   across a selection where a zoom writes one clip's action end — so the
//!   only thing keeping the two from drifting is this assertion.

use serde_json::{json, Value};

mod common;
use common::{array, assert_contains, by_id, num, text, Handle};

// ---- fixtures ------------------------------------------------------------

/// One clip per thing the op has to read, so no test has to set up its own
/// state first. Canvas 1920×1080 at 30 fps (one frame = 20 000 ticks); ids
/// are one space across media, tracks and clips (spec §5.2).
///
/// - Clip 10 is the plain case: unrotated, uncropped, base props untouched.
/// - Clip 11 shows the 800×600 card, which is the "whole cropped source"
///   case — a source whose aspect differs from the canvas's, so `min` has
///   something to choose between.
/// - Clips 20 and 21 are turned 90° and 45°.
/// - Clip 30 is cropped 400 px off the left and 200 off the bottom, so
///   `c = ((l − r)/2, (t − b)/2) = (200, −100)` is neither zero nor
///   symmetric.
/// - Clip 31 carries a non-default base transform, which is what a zoom
///   BACK has to restore.
/// - Clips 40 and 41 are a title and a shape: video props, no source size.
/// - Clip 50 is audio-only and has NO video group at all.
/// - Clip 51 already animates its rotation to 90° over its first second,
///   which is how "the props are read EVALUATED at `at`" is separated from
///   "the props are read from the base".
fn zoom_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 3,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/screen.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/card.png", "kind": "image", "width": 800, "height": 600,
     "fps": [30, 1]},
    {"id": 3, "path": "/m/music.m4a", "kind": "audio", "duration": 18000000,
     "has_audio": true}
  ],
  "tracks": [
    {"id": 4, "name": "Picture"},
    {"id": 5, "name": "Turned"},
    {"id": 6, "name": "Cropped"},
    {"id": 7, "name": "Titles"},
    {"id": 8, "name": "Sound"}
  ],
  "clips": [
    {"id": 10, "track": 4, "start": 0, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 11, "track": 4, "start": 6600000, "duration": 3000000,
     "source": {"kind": "media", "media": 2, "in": 0}, "video": {}},
    {"id": 20, "track": 5, "start": 0, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0},
     "video": {"rotation": 90}, "audio": {}},
    {"id": 21, "track": 5, "start": 6600000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 0},
     "video": {"rotation": 45}, "audio": {}},
    {"id": 30, "track": 6, "start": 0, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0},
     "video": {"crop": {"l": 400, "t": 0, "r": 0, "b": 200}}, "audio": {}},
    {"id": 31, "track": 6, "start": 6600000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 0},
     "video": {"x": 120.5, "y": -40.25, "scale": 0.75, "rotation": 30}, "audio": {}},
    {"id": 40, "track": 7, "start": 0, "duration": 3000000,
     "source": {"kind": "text"}, "video": {}, "text": {"content": "Hello"}},
    {"id": 41, "track": 7, "start": 3600000, "duration": 3000000,
     "source": {"kind": "shape"}, "video": {}, "shape": {"width": 320, "height": 120}},
    {"id": 50, "track": 8, "start": 0, "duration": 3000000,
     "source": {"kind": "media", "media": 3, "in": 0}, "audio": {}},
    {"id": 51, "track": 8, "start": 3600000, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {},
     "actions": [{"id": 52, "start": 0, "duration": 600000, "curve": "linear",
                  "end": {"video": {"rotation": 90}}}]}
  ],
  "markers": [],
  "next_id": 60
}"#,
    )
}

/// One second, and one frame, on this fixture's grid.
const SECOND: i64 = 600_000;
const FRAME: i64 = 20_000;

// ---- reading the answer --------------------------------------------------

/// The `scale`, `x`, `y` an action's end patch holds, and the assertion
/// that it holds those three and NOTHING else — no rotation, no crop, no
/// stray group. What the op does not write matters as much as what it does:
/// a patch carrying `rotation` would freeze the layer's angle for the whole
/// span of every zoom.
fn zoom_end(project: &Value, clip: u64, action: u64) -> (f64, f64, f64) {
    let target = by_id(project, "/clips", clip);
    let found = array(target, "/actions")
        .iter()
        .find(|a| a.get("id").and_then(Value::as_u64) == Some(action))
        .unwrap_or_else(|| panic!("no action with id {action} on clip {clip}"));
    let end = &found["end"];
    let groups = end
        .as_object()
        .unwrap_or_else(|| panic!("the end patch is not an object: {end}"));
    assert_eq!(
        groups.keys().collect::<Vec<_>>(),
        vec!["video"],
        "a zoom writes the video group and nothing else"
    );
    let video = end["video"]
        .as_object()
        .unwrap_or_else(|| panic!("the video patch is not an object: {end}"));
    let mut keys: Vec<&str> = video.keys().map(String::as_str).collect();
    keys.sort_unstable();
    assert_eq!(
        keys,
        vec!["scale", "x", "y"],
        "a zoom writes scale, x and y and nothing else"
    );
    (
        num(end, "/video/scale"),
        num(end, "/video/x"),
        num(end, "/video/y"),
    )
}

/// Applies one zoom to the fixture and reads back the end patch it wrote.
/// The action's id is `next_id` from before the call (spec §6), which is
/// 60 for every test that applies exactly one op.
fn zoom(project: &Handle, op: Value, clip: u64) -> (f64, f64, f64) {
    let next = project.apply(&op);
    let value = next.value();
    zoom_end(&value, clip, 60)
}

/// The rotated cases go through `cos` and `sin`, so they compare against
/// the hand-computed number with a tolerance a thousand times tighter than
/// any answer a wrong formula would give (the alternatives here differ by
/// hundreds of pixels, not by ulps).
fn close(what: &str, got: f64, want: f64) {
    assert!(
        (got - want).abs() < 1e-9,
        "{what}: expected {want}, got {got}"
    );
}

// ---- the scale: fit, fill, and the Fit button -----------------------------

/// A region equal to the whole cropped source, under `fit`, IS the
/// inspector's "Fit to Canvas": `min(cw/sw, ch/sh)` centred at the origin.
///
/// Card 800×600 on a 1920×1080 canvas: `min(1920/800, 1080/600) =
/// min(2.4, 1.8) = 1.8`, and with no crop and a centred region both offsets
/// are exactly zero.
#[test]
fn the_whole_cropped_source_under_fit_is_the_fit_button() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 11, "at": 0,
               "region": {"x": 0, "y": 0, "width": 800, "height": 600}}),
        11,
    );
    assert_eq!(scale, 1.8, "min(1920/800, 1080/600)");
    assert_eq!(x, 0.0);
    assert_eq!(y, 0.0);
}

/// The module doc's worked example, which is also the road map's proof:
/// region 480×270 centred 480 source px right of the cropped centre.
/// `min(1920/480, 1080/270) = 4`, and `(x, y) = −4 × (480, 0)`.
///
/// Checked against the placement rule the other way round: the anchor
/// becomes `(960 − 1920, 540)`, so the region's centre lands at
/// `−960 + 4 × 480 = 960`, the canvas centre, and its width becomes
/// `480 × 4 = 1920`, the canvas width.
#[test]
fn a_quarter_width_region_scales_by_four_and_offsets_by_the_scaled_centre() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0,
               "region": {"x": 480, "y": 0, "width": 480, "height": 270}}),
        10,
    );
    assert_eq!(scale, 4.0);
    assert_eq!(x, -1920.0);
    assert_eq!(y, 0.0);
}

/// Half the canvas in each direction doubles the scale, and the offset is
/// the region's centre times that scale, negated:
/// `min(1920/960, 1080/540) = 2`, `−2 × (240, −135) = (−480, 270)`.
#[test]
fn a_half_size_region_doubles_the_scale() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0,
               "region": {"x": 240, "y": -135, "width": 960, "height": 540}}),
        10,
    );
    assert_eq!(scale, 2.0);
    assert_eq!(x, -480.0);
    assert_eq!(y, 270.0);
}

/// `fit` and `fill` differ exactly when the region's aspect differs from
/// the canvas's, and they differ in both numbers, since the offsets are
/// computed from the resolved scale.
///
/// A 480×480 square on a 16:9 canvas: fit is `min(1920/480, 1080/480) =
/// min(4, 2.25) = 2.25` and fill is `max(…) = 4`. With the region's centre
/// at `(100, 50)` the offsets are `−2.25 × (100, 50) = (−225, −112.5)` and
/// `−4 × (100, 50) = (−400, −200)`.
#[test]
fn fill_takes_the_larger_scale_where_fit_takes_the_smaller() {
    let project = zoom_project();
    let region = json!({"x": 100, "y": 50, "width": 480, "height": 480});

    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0,
               "region": region, "fit": "fit"}),
        10,
    );
    assert_eq!(scale, 2.25, "min(1920/480, 1080/480)");
    assert_eq!(x, -225.0);
    assert_eq!(y, -112.5);

    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0,
               "region": region, "fit": "fill"}),
        10,
    );
    assert_eq!(scale, 4.0, "max(1920/480, 1080/480)");
    assert_eq!(x, -400.0);
    assert_eq!(y, -200.0);
}

/// An absent `fit` is `fit`, not `fill` — the default a user who drew a box
/// means.
#[test]
fn an_absent_fit_is_fit() {
    let project = zoom_project();
    let region = json!({"x": 100, "y": 50, "width": 480, "height": 480});
    let implied = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0, "region": region}),
        10,
    );
    let spelled = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0,
               "region": region, "fit": "fit"}),
        10,
    );
    assert_eq!(implied, spelled);
    assert_eq!(implied.0, 2.25);
}

// ---- rotation and crop ----------------------------------------------------

/// A clip turned 90°: the region's extents swap, so `fit` measures its
/// width against the canvas HEIGHT.
///
/// `k = |cos 90°| = 0`, `m = 1`, so the denominators are `480·0 + 270·1 =
/// 270` across and `480·1 + 270·0 = 480` down:
/// `min(1920/270, 1080/480) = min(7.11…, 2.25) = 2.25`. Measured on the
/// region's own axes instead it would be 4, and the region's corners would
/// hang 840 px off each end of the canvas.
///
/// The offset turns with it: `−R(90°) × 2.25 × (480, 0) = −(0, 1080)`.
#[test]
fn a_quarter_turned_clip_measures_the_region_through_its_rotation() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 20, "at": 0,
               "region": {"x": 480, "y": 0, "width": 480, "height": 270}}),
        20,
    );
    close("scale", scale, 2.25);
    close("x", x, 0.0);
    close("y", y, -1080.0);
}

/// 45°, where both `k` and `m` matter and the answer is still exact on
/// paper.
///
/// `k = m = 1/√2`, so both denominators are `(480 + 270)/√2 = 750/√2` and
/// `s = 1080·√2/750`. The offsets then collapse: with the region's centre
/// at `(200, 100)`,
/// `x = −s·(200 − 100)/√2 = −1080·100/750 = −144` and
/// `y = −s·(200 + 100)/√2 = −1080·300/750 = −432`, the √2 cancelling out.
#[test]
fn a_forty_five_degree_clip_carries_both_rotation_terms() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 21, "at": 0,
               "region": {"x": 200, "y": 100, "width": 480, "height": 270}}),
        21,
    );
    close("scale", scale, 1080.0 * std::f64::consts::SQRT_2 / 750.0);
    close("x", x, -144.0);
    close("y", y, -432.0);
}

/// Crop enters through `c`, the cropped rect's centre measured from the
/// uncropped one, and through nothing else — it does not change the scale,
/// because the region is already given in source pixels.
///
/// Crop `l = 400, b = 200` gives `c = ((400 − 0)/2, (0 − 200)/2) =
/// (200, −100)`. A 480×270 region centred on the cropped rect therefore
/// scales by 4 as it does uncropped, and offsets by `−4 × (200, −100) =
/// (−800, 400)`.
#[test]
fn crop_moves_the_zoom_by_the_cropped_rects_own_centre() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 30, "at": 0,
               "region": {"x": 0, "y": 0, "width": 480, "height": 270}}),
        30,
    );
    assert_eq!(scale, 4.0, "the crop does not change the fit scale");
    assert_eq!(x, -800.0);
    assert_eq!(y, 400.0);
}

/// The props are read EVALUATED at `at`, not from the clip's base.
///
/// Clip 51 animates its rotation from 0 to 90° over its first second, so at
/// clip time 2 s it is turned 90° — and the zoom there must be the turned
/// answer (2.25, 0, −1080), not the base-props answer (4, −1920, 0) the
/// same region gives on clip 10. The two differ by 1 920 px, so nothing
/// about this can pass by coincidence.
#[test]
fn rotation_is_read_from_the_state_at_the_actions_start() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 51, "at": 2 * SECOND,
               "duration": SECOND,
               "region": {"x": 480, "y": 0, "width": 480, "height": 270}}),
        51,
    );
    close("scale", scale, 2.25);
    close("x", x, 0.0);
    close("y", y, -1080.0);
}

// ---- the clamp ------------------------------------------------------------

/// A region too small to reach is clamped to the layer's maximum scale, and
/// the offsets are computed from the CLAMPED value so the region still
/// lands exactly centred.
///
/// A 100×100 region wants `min(1920/100, 1080/100) = 10.8`, above the
/// scale maximum of 10. At 10 the offsets are `−10 × (50, 25) =
/// (−500, −250)`; computed from 10.8 they would be `(−540, −270)` and the
/// rendered frame would be 40 px off centre with nothing reported.
/// `fill`, which wants 19.2, clamps to the same place.
#[test]
fn a_region_that_wants_more_than_the_maximum_scale_stays_centred() {
    let project = zoom_project();
    let region = json!({"x": 50, "y": 25, "width": 100, "height": 100});

    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0, "region": region}),
        10,
    );
    assert_eq!(scale, 10.0, "clamped down from min(19.2, 10.8)");
    assert_eq!(x, -500.0, "computed from the clamped scale, not from 10.8");
    assert_eq!(y, -250.0);

    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0,
               "region": region, "fit": "fill"}),
        10,
    );
    assert_eq!(scale, 10.0, "clamped down from max(19.2, 10.8)");
    assert_eq!(x, -500.0);
    assert_eq!(y, -250.0);
}

/// The other end of the same clamp: a region far larger than the source
/// wants a scale below the minimum of 0.01, and gets the minimum.
/// `min(1920, 1080)/1_000_000` is 0.00108.
#[test]
fn a_region_that_wants_less_than_the_minimum_scale_takes_the_minimum() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0,
               "region": {"x": 100, "y": 0, "width": 1000000, "height": 1000000}}),
        10,
    );
    assert_eq!(scale, 0.01);
    assert_eq!(x, -1.0, "−0.01 × 100");
    assert_eq!(y, 0.0);
}

// ---- zoom back ------------------------------------------------------------

/// A null region is a zoom BACK: the end patch is the clip's own BASE
/// transform, which is the only reading that survives whatever actions ran
/// before it. Clip 31 sits at scale 0.75, `(120.5, −40.25)`.
///
/// Its `rotation` of 30° is deliberately NOT in the patch: zooming back
/// restores the placement, not the whole video group.
#[test]
fn a_null_region_zooms_back_to_the_clips_base_transform() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 31, "at": 0, "region": null}),
        31,
    );
    assert_eq!(scale, 0.75);
    assert_eq!(x, 120.5);
    assert_eq!(y, -40.25);
}

/// An absent `region` and an explicit `null` mean the same thing — the
/// envelope's rule (`edit.rs`), which this op does not make an exception
/// to. The MCP tool is where an absent key is refused, so an agent that
/// forgets it is told rather than zoomed out.
#[test]
fn an_absent_region_is_the_same_zoom_back_as_an_explicit_null() {
    let project = zoom_project();
    let absent = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 31, "at": 0}),
        31,
    );
    let explicit = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 31, "at": 0, "region": null}),
        31,
    );
    assert_eq!(absent, explicit);
    assert_eq!(absent, (0.75, 120.5, -40.25));
}

/// A zoom back on a clip whose base props are the defaults writes the
/// defaults — scale 1 at the origin — rather than nothing at all. The
/// action still exists and still animates; it is the identity that is being
/// animated TO.
#[test]
fn a_zoom_back_on_an_untouched_clip_writes_the_default_transform() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 10, "at": 0}),
        10,
    );
    assert_eq!(scale, 1.0);
    assert_eq!(x, 0.0);
    assert_eq!(y, 0.0);
}

// ---- what kind of clip may zoom -------------------------------------------

/// A title zooms. The op needs no source size — `sw` and `sh` cancel out of
/// the derivation — and `Project::source_size` answers `None` for text, so
/// an op built on a measurement would have refused every title.
#[test]
fn a_text_clip_zooms() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 40, "at": 0,
               "region": {"x": 0, "y": 0, "width": 480, "height": 270}}),
        40,
    );
    assert_eq!(scale, 4.0);
    assert_eq!(x, 0.0);
    assert_eq!(y, 0.0);
}

/// So does a shape, for the same reason.
#[test]
fn a_shape_clip_zooms() {
    let project = zoom_project();
    let (scale, x, y) = zoom(
        &project,
        json!({"op": "add_zoom_action", "clip": 41, "at": 0,
               "region": {"x": -160, "y": 0, "width": 480, "height": 270}}),
        41,
    );
    assert_eq!(scale, 4.0);
    assert_eq!(x, 640.0, "−4 × −160");
    assert_eq!(y, 0.0);
}

/// A clip with no video group draws nothing, so there is no picture to zoom
/// and no base transform to zoom back to. That is an `Err` naming the clip,
/// in the wording `set_video` and `freeze_frame` already use, not a silent
/// refusal.
#[test]
fn a_clip_with_no_video_properties_is_an_error() {
    let project = zoom_project();
    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 50, "at": 0,
                                     "region": {"x": 0, "y": 0, "width": 480, "height": 270}}));
    assert_contains(&msg, "clip 50 has no video properties");

    // And for a zoom back too: the base transform is read from the same
    // group, so the check cannot be region-conditional.
    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 50, "at": 0}));
    assert_contains(&msg, "clip 50 has no video properties");
}

/// An unknown clip is the ordinary unknown-id error, from `require_clip`.
#[test]
fn an_unknown_clip_is_an_error() {
    let project = zoom_project();
    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 999, "at": 0,
                                     "region": {"x": 0, "y": 0, "width": 480, "height": 270}}));
    assert_contains(&msg, "no clip with id 999");
}

// ---- the region's own arguments -------------------------------------------

/// A region with no extent is the caller's mistake, named rather than
/// repaired: a zero width asks for an infinite scale and a zero height
/// divides by nothing.
#[test]
fn a_region_with_no_extent_is_an_error() {
    let project = zoom_project();
    for (width, height, key) in [
        (0.0, 270.0, "region.width"),
        (480.0, 0.0, "region.height"),
        (-480.0, 270.0, "region.width"),
        (480.0, -270.0, "region.height"),
    ] {
        let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                                         "region": {"x": 0, "y": 0,
                                                    "width": width, "height": height}}));
        assert_contains(&msg, &format!("{key} must be greater than 0"));
    }
}

/// The region is a fixed shape: a missing member, a misspelt one and a
/// member of the wrong type are each refused BY NAME, which is the
/// envelope's "unknown keys are an error" rule reaching one level in, and
/// what makes the region door answer the way a property patch does (D1·2,
/// kpgalligan/reelcut#3).
#[test]
fn the_region_takes_four_named_numbers_and_only_those() {
    let project = zoom_project();
    let zoom =
        |region: Value| json!({"op": "add_zoom_action", "clip": 10, "at": 0, "region": region});

    // A missing member: there is no defensible default for any of the four
    // — a region with no width is not a region — so the type carries none.
    let msg = project.errors(&zoom(json!({"x": 0, "y": 0, "width": 480})));
    assert_contains(&msg, "op \"add_zoom_action\" is not valid");
    assert_contains(&msg, "missing field `height`");

    // A misspelt one, named beside the four the region does take.
    let msg = project.errors(&zoom(
        json!({"x": 0, "y": 0, "width": 480, "height": 270, "widht": 1}),
    ));
    assert_contains(&msg, "unknown field `widht`");
    assert_contains(&msg, "`x`, `y`, `width`, `height`");

    // A member of the wrong type names the member, not just the op.
    let msg = project.errors(&zoom(
        json!({"x": 0, "y": 0, "width": "wide", "height": 270}),
    ));
    assert_contains(&msg, "width");

    // And the region is an OBJECT. serde reads a struct from a JSON array
    // of its fields in declaration order, so `[0, 0, 480, 270]` would zoom
    // to a region nobody spelled — a spelling no tool description offers
    // and `get_project` never gives back, which a caller could only land on
    // by accident. It is the hole `patch.rs`'s kind check closed for a
    // patch, closed here for the one argument that is a nested object.
    let msg = project.errors(&zoom(json!([0, 0, 480, 270])));
    assert_contains(&msg, "expected an object, not [0,0,480,270]");
    // The two spellings that mean "zoom back" are untouched by that.
    project.apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 0, "region": null}));
    project.apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 0}));
}

/// `fit` is a closed vocabulary; anything else is refused by name rather
/// than falling back to a default.
#[test]
fn an_unknown_fit_is_an_error() {
    let project = zoom_project();
    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                                     "region": {"x": 0, "y": 0, "width": 480, "height": 270},
                                     "fit": "cover"}));
    assert_contains(&msg, "op \"add_zoom_action\" is not valid");
}

// ---- the action it makes --------------------------------------------------

/// The action is an ordinary one: it starts at `at`, runs for `duration`,
/// takes the id `next_id` held before the call, and gets the eased-both-
/// ends curve rather than `Curve::default()`'s `linear` — a screencast zoom
/// that starts and stops abruptly is the thing this feature exists to
/// avoid.
#[test]
fn the_action_starts_where_it_was_asked_to_and_eases_both_ends() {
    let project = zoom_project();
    assert_eq!(num(&project.value(), "/next_id"), 60.0);

    let next = project.apply(&json!({"op": "add_zoom_action", "clip": 10,
                                     "at": 2 * SECOND, "duration": SECOND,
                                     "region": {"x": 0, "y": 0,
                                                "width": 480, "height": 270}}));
    let value = next.value();
    let action = &array(by_id(&value, "/clips", 10), "/actions")[0];
    assert_eq!(action["id"].as_u64(), Some(60));
    assert_eq!(action["start"].as_i64(), Some(2 * SECOND));
    assert_eq!(action["duration"].as_i64(), Some(SECOND));
    assert_eq!(text(action, "/curve"), "ease_in_out");
}

/// An explicit curve wins over the default, using `set_action`'s own
/// vocabulary and error strings.
#[test]
fn an_explicit_curve_wins() {
    let project = zoom_project();
    let next = project.apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                                     "curve": "ease_out",
                                     "region": {"x": 0, "y": 0,
                                                "width": 480, "height": 270}}));
    let value = next.value();
    let action = &array(by_id(&value, "/clips", 10), "/actions")[0];
    assert_eq!(text(action, "/curve"), "ease_out");

    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                                     "curve": "bounce"}));
    assert_contains(&msg, "op \"add_zoom_action\" is not valid");
}

/// An absent duration is `add_action`'s own default of one second — one
/// implementation of the default, not two.
#[test]
fn an_absent_duration_is_add_actions_default_second() {
    let project = zoom_project();
    let next = project.apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                                     "region": {"x": 0, "y": 0,
                                                "width": 480, "height": 270}}));
    let value = next.value();
    let action = &array(by_id(&value, "/clips", 10), "/actions")[0];
    assert_eq!(action["duration"].as_i64(), Some(SECOND));
}

/// Both time arguments snap to the frame grid before anything else, as
/// every op's do (spec §6) — a caller may hand over a tick computed from a
/// pixel position. Half a frame past 2 s rounds back to 2 s.
#[test]
fn the_times_snap_to_the_frame_grid() {
    let project = zoom_project();
    let next = project.apply(&json!({"op": "add_zoom_action", "clip": 10,
                                     "at": 2 * SECOND + FRAME / 2 - 1,
                                     "duration": SECOND + FRAME / 2 - 1,
                                     "region": {"x": 0, "y": 0,
                                                "width": 480, "height": 270}}));
    let value = next.value();
    let action = &array(by_id(&value, "/clips", 10), "/actions")[0];
    assert_eq!(action["start"].as_i64(), Some(2 * SECOND));
    assert_eq!(action["duration"].as_i64(), Some(SECOND));
}

// ---- the refusals it inherits ---------------------------------------------

/// The no-overlap rule is `add_action`'s, inherited by composing it rather
/// than restated: clip 51 already animates over `[0, 1 s)`, so a zoom
/// starting half a second in refuses — `Ok(None)`, no undo step.
#[test]
fn a_zoom_that_would_overlap_another_action_refuses() {
    let project = zoom_project();
    project.refuses(&json!({"op": "add_zoom_action", "clip": 51,
                            "at": SECOND / 2, "duration": SECOND,
                            "region": {"x": 0, "y": 0, "width": 480, "height": 270}}));
    // And a zoom back, which takes the same path and must refuse the same
    // way rather than writing an action nobody asked for.
    project.refuses(&json!({"op": "add_zoom_action", "clip": 51,
                            "at": SECOND / 2, "duration": SECOND}));
}

/// So is "past the end of the clip": clip 10 runs 10 s, so a one-second
/// zoom starting at 9.5 s has nowhere to finish.
#[test]
fn a_zoom_that_would_run_past_the_clip_refuses() {
    let project = zoom_project();
    project.refuses(&json!({"op": "add_zoom_action", "clip": 10,
                            "at": 19 * SECOND / 2, "duration": SECOND,
                            "region": {"x": 0, "y": 0, "width": 480, "height": 270}}));
}

/// A negative CLIP time is an `Err`, not a clamp — the caller computed it
/// as `playhead − clip.start`, so a negative one means the playhead is not
/// on the clip (`edit.rs`). The message is `add_action`'s.
#[test]
fn a_negative_start_is_an_error() {
    let project = zoom_project();
    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 10, "at": -SECOND,
                                     "region": {"x": 0, "y": 0,
                                                "width": 480, "height": 270}}));
    assert_contains(&msg, "action start must not be negative");
}

/// And so is a duration that snaps to nothing.
#[test]
fn a_non_positive_duration_is_an_error() {
    let project = zoom_project();
    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                                     "duration": 0,
                                     "region": {"x": 0, "y": 0,
                                                "width": 480, "height": 270}}));
    assert_contains(&msg, "action duration must be positive");
}

/// A bad argument is reported ahead of a refusal: the region is checked
/// before `add_action` runs, so a zero-width region on a span that also
/// overlaps another action is named rather than silently swallowed as
/// "changes nothing".
#[test]
fn a_bad_region_is_named_even_where_the_span_would_refuse() {
    let project = zoom_project();
    let msg = project.errors(&json!({"op": "add_zoom_action", "clip": 51,
                                     "at": SECOND / 2, "duration": SECOND,
                                     "region": {"x": 0, "y": 0,
                                                "width": 0, "height": 270}}));
    assert_contains(&msg, "region.width must be greater than 0");
}

// ---- what it leaves alone -------------------------------------------------

/// A zoom adds exactly one action and touches nothing else: not the clip's
/// base props, not its neighbours, not another clip's actions. Only the
/// target clip's `actions` list and the project's `next_id` may differ.
#[test]
fn a_zoom_changes_one_clips_actions_and_nothing_else() {
    let project = zoom_project();
    let before = project.value();
    let after = project
        .apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                       "region": {"x": 480, "y": 0, "width": 480, "height": 270}}))
        .value();

    assert_eq!(before["next_id"].as_u64(), Some(60));
    assert_eq!(after["next_id"].as_u64(), Some(61));

    let mut expected = before.clone();
    expected["next_id"] = json!(61);
    let target = array(&expected, "/clips")
        .iter()
        .position(|c| c.get("id").and_then(Value::as_u64) == Some(10))
        .expect("clip 10 is in the fixture");
    expected["clips"][target]["actions"] = after["clips"][target]["actions"].clone();
    assert_eq!(
        expected, after,
        "a zoom changed something other than clip 10's actions and next_id"
    );

    // The clip whose actions were replaced above still has its base props
    // untouched, which is what that splice could otherwise have hidden.
    let clip = by_id(&after, "/clips", 10);
    assert_eq!(num(clip, "/video/scale"), 1.0);
    assert_eq!(num(clip, "/video/x"), 0.0);
    assert_eq!(num(clip, "/video/y"), 0.0);
}

/// Two zooms on one clip are two actions, and the second reads the state
/// the first leaves behind. Clip 10 is unrotated so the geometry is the
/// same either way; what this pins is that the composite is re-entrant —
/// each call allocates its own id and neither overwrites the other.
#[test]
fn two_zooms_on_one_clip_are_two_actions() {
    let project = zoom_project();
    let once = project.apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 0,
                                     "duration": SECOND,
                                     "region": {"x": 480, "y": 0,
                                                "width": 480, "height": 270}}));
    let twice = once.apply(&json!({"op": "add_zoom_action", "clip": 10,
                                   "at": 4 * SECOND, "duration": SECOND}));
    let value = twice.value();
    let actions = array(by_id(&value, "/clips", 10), "/actions");
    assert_eq!(actions.len(), 2);

    assert_eq!(zoom_end(&value, 10, 60), (4.0, -1920.0, 0.0));
    assert_eq!(zoom_end(&value, 10, 61), (1.0, 0.0, 0.0), "the zoom back");
}
