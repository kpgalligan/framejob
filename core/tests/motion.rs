//! `video.motion` turned into placement — road map 5 §5b–§5c's arithmetic,
//! read off `frame_recipe` through the FFI.
//!
//! Every expected number here is computed from the tables in
//! `core/src/motion.rs`'s module doc and road map 5 §5b, never read off a
//! run: the eases are written out again (`ease_out(u) = 1 − (1−u)²`,
//! `ease_in(v) = v²`, `back_out(u) = 1 + 2.70158(u−1)³ + 1.70158(u−1)²`),
//! so a change to `actions::ease` fails these tests rather than moving with
//! them. The fixtures are built so that a mistake cannot pass: the clip is
//! placed OFF centre, at a scale that is not 1 and (where it matters) at a
//! rotation and a crop that are not symmetric, because a centred,
//! unrotated, uncropped layer would make the pivot compensation, the crop
//! centre and the slide geometry all agree with doing nothing.
//!
//! Three claims here are about the SHORT-CIRCUIT rather than about a
//! number, and they are the ones a careless implementation fails: a clip
//! whose motion is `null` renders a recipe byte-identical to the same
//! project before the field existed; a clip at exactly `in′` — the first
//! frame past its arrival, with no `out` and no `during` — renders
//! byte-identical to the same clip with no motion at all; and one turn of
//! `during: spin` does too, because the total rotation is reduced
//! `rem_euclid(360)` and 360 reduces to exactly 0.
//!
//! What a preset LOOKS like is not a claim this file can make — the pixels
//! are the compositor's. What is pinned here is the placement the recipe
//! publishes, which is the one description every renderer draws from.

mod common;

use serde_json::{json, Value};

use common::{array, num, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

/// The canvas every fixture uses. 1920 × 1080 rather than a square, so a
/// horizontal slide and a vertical one cannot be confused.
const W: f64 = 1920.0;
const H: f64 = 1080.0;

/// The clip's own length in every fixture: six seconds.
const D: i64 = 6 * SEC;

/// The source's pixel size in every media fixture. 1280 × 800 is a 16∶10
/// source on a 16∶9 canvas, so `cw` and `ch` differ from `W` and `H` and a
/// slide distance computed from the wrong one is visible.
const SW: f64 = 1280.0;
const SH: f64 = 800.0;

// ---- the formulas, written out again -------------------------------------

fn ease_out(u: f64) -> f64 {
    let u = u.clamp(0.0, 1.0);
    1.0 - (1.0 - u) * (1.0 - u)
}

fn ease_in(v: f64) -> f64 {
    let v = v.clamp(0.0, 1.0);
    v * v
}

fn back_out(u: f64) -> f64 {
    let p = u - 1.0;
    1.0 + 2.70158 * p * p * p + 1.70158 * p * p
}

fn close(actual: f64, expected: f64, what: &str) {
    assert!(
        (actual - expected).abs() < 1e-9,
        "{what}: got {actual}, expected {expected}"
    );
}

// ---- fixtures ------------------------------------------------------------

/// One media clip (id 11) on one track, six seconds long, placed OFF centre
/// at a scale that is not 1, carrying whatever `video` says.
fn project(video: Value) -> Value {
    json!({
        "version": 8,
        "canvas": { "width": W as u32, "height": H as u32, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 60 * SEC, "width": SW as u32, "height": SH as u32,
            "fps": [30, 1], "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": D,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": video, "audio": {}
        }],
        "next_id": 12
    })
}

/// The placement base every fixture starts from: off centre, scaled down,
/// slightly transparent — so an identity is distinguishable from a default.
fn base() -> Value {
    json!({ "x": 100.0, "y": -60.0, "scale": 0.5, "opacity": 0.8 })
}

fn with_motion(motion: Value) -> Handle {
    let mut video = base();
    video["motion"] = motion;
    Handle::from_value(&project(video))
}

/// The one layer of the fixture's recipe at project time `t`.
fn layer(handle: &Handle, t: i64) -> Value {
    let recipe = handle.recipe(t);
    let layers = array(&recipe, "/layers");
    assert_eq!(
        layers.len(),
        1,
        "the fixture draws exactly one layer at {t}"
    );
    layers[0].clone()
}

/// An `in` slot of `kind` lasting `duration`.
fn arrive(kind: &str, duration: i64) -> Value {
    json!({ "in": { "kind": kind, "duration": duration } })
}

/// An `out` slot of `kind` lasting `duration`.
fn leave(kind: &str, duration: i64) -> Value {
    json!({ "out": { "kind": kind, "duration": duration } })
}

// ---- the two edge tables -------------------------------------------------

/// The three sample points every row of both tables is read at: the first
/// frame, half way, and the frame the slot ends on.
const IN: i64 = 2 * SEC;

#[test]
fn every_arrival_scales_turns_and_fades_by_its_row() {
    // Road map 5 §5b's arrival table, at u = 0, 0.5 and 1 — the last being
    // the frame the slot ENDS on, where the short-circuit takes over and
    // every row must agree with doing nothing.
    let base_scale = 0.5;
    let base_opacity = 0.8;
    for (kind, factor, phi, opacity) in [
        (
            "fade",
            (1.0, 1.0) as (f64, f64),
            (0.0, 0.0) as (f64, f64),
            true,
        ),
        (
            "zoom_in",
            (0.6, 0.6 + 0.4 * ease_out(0.5)),
            (0.0, 0.0),
            true,
        ),
        (
            "zoom_out",
            (1.4, 1.4 - 0.4 * ease_out(0.5)),
            (0.0, 0.0),
            true,
        ),
        (
            "spin",
            (0.3, 0.3 + 0.7 * ease_out(0.5)),
            (-180.0, -180.0 * (1.0 - ease_out(0.5))),
            true,
        ),
        ("pop", (back_out(0.0), back_out(0.5)), (0.0, 0.0), false),
    ] {
        let handle = with_motion(arrive(kind, IN));
        for (step, f, degrees) in [(0, factor.0, phi.0), (IN / 2, factor.1, phi.1)] {
            let l = layer(&handle, step);
            // Clamped, because `pop`'s own curve is exactly 0 at u = 0 —
            // `back_out(0)` is `1 − 2.70158 + 1.70158` — and a scale of 0
            // is not drawable. SCALE_MIN is what a layer that has not
            // arrived yet is drawn at; the fade covers it.
            close(
                num(&l, "/scale"),
                (base_scale * f).clamp(0.01, 10.0),
                &format!("{kind} scale at {step}"),
            );
            // The model's rotation is reduced `rem_euclid(360)`, so a
            // negative phi comes back as its positive congruent angle.
            close(
                num(&l, "/rotation"),
                degrees.rem_euclid(360.0),
                &format!("{kind} rotation at {step}"),
            );
            let expected = if opacity {
                base_opacity * ease_out(step as f64 / IN as f64)
            } else {
                base_opacity * (step as f64 / IN as f64 / 0.25).min(1.0)
            };
            close(
                num(&l, "/opacity"),
                expected,
                &format!("{kind} opacity at {step}"),
            );
        }
        // At u = 1 the slot is over and the short-circuit returns the clip
        // untouched — which is what makes the frame at `in′` identical to
        // the clip with no motion at all.
        let ended = layer(&handle, IN);
        close(
            num(&ended, "/scale"),
            base_scale,
            &format!("{kind} scale at in"),
        );
        close(
            num(&ended, "/rotation"),
            0.0,
            &format!("{kind} rotation at in"),
        );
        close(
            num(&ended, "/opacity"),
            base_opacity,
            &format!("{kind} opacity at in"),
        );
    }
}

#[test]
fn every_departure_scales_turns_and_fades_by_its_row() {
    // The departure table, measured back from the EXCLUSIVE end so the last
    // drawn frame still shows a sliver. v = 0 at `D − out′`, and the last
    // FRAME of a 30 fps clip is at D − 20_000, where v = 1 − 20000/out′.
    let out = 2 * SEC;
    let start = D - out;
    let base_scale = 0.5;
    let base_opacity = 0.8;
    for kind in ["fade", "zoom_in", "zoom_out", "spin", "pop"] {
        let handle = with_motion(leave(kind, out));
        for step in [0, out / 2, out - 20_000] {
            let v = step as f64 / out as f64;
            let d = ease_in(v);
            let (f, phi, o) = match kind {
                "fade" => (1.0, 0.0, 1.0 - d),
                "zoom_in" => (1.0 + 0.4 * d, 0.0, 1.0 - d),
                "zoom_out" => (1.0 - 0.4 * d, 0.0, 1.0 - d),
                "spin" => (1.0 - 0.7 * d, 180.0 * d, 1.0 - d),
                _ => (back_out(1.0 - v), 0.0, ((1.0 - v) / 0.25).min(1.0)),
            };
            let l = layer(&handle, start + step);
            close(
                num(&l, "/scale"),
                base_scale * f,
                &format!("{kind} scale at +{step}"),
            );
            close(
                num(&l, "/rotation"),
                phi.rem_euclid(360.0),
                &format!("{kind} rotation at +{step}"),
            );
            close(
                num(&l, "/opacity"),
                base_opacity * o,
                &format!("{kind} opacity at +{step}"),
            );
        }
        // One frame BEFORE the departure begins, nothing is running.
        let before = layer(&handle, start - 20_000);
        close(
            num(&before, "/scale"),
            base_scale,
            &format!("{kind} scale before out"),
        );
        close(
            num(&before, "/opacity"),
            base_opacity,
            &format!("{kind} opacity before out"),
        );
    }
}

// ---- slides --------------------------------------------------------------

/// The visible half-extents and the base visible centre of a fixture, per
/// road map 5 §5b — written out here so the expected slide distance is
/// derived from the rule rather than from the implementation.
fn geometry(
    crop: (f64, f64, f64, f64),
    scale: f64,
    rotation: f64,
    x: f64,
    y: f64,
) -> (f64, f64, f64, f64) {
    let (l, t, r, b) = crop;
    let cw = SW - l - r;
    let ch = SH - t - b;
    let k = rotation.to_radians().cos().abs();
    let n = rotation.to_radians().sin().abs();
    let hx = scale * (cw * k + ch * n) / 2.0;
    let hy = scale * (cw * n + ch * k) / 2.0;
    // c = ((l − r)/2, (t − b)/2), turned by R(θ) and scaled.
    let (cx, cy) = ((l - r) / 2.0 * scale, (t - b) / 2.0 * scale);
    let (rad_sin, rad_cos) = rotation.to_radians().sin_cos();
    let px = x + rad_cos * cx - rad_sin * cy;
    let py = y + rad_sin * cx + rad_cos * cy;
    (hx, hy, px, py)
}

#[test]
fn a_slide_starts_with_the_near_edge_exactly_on_the_container_edge() {
    // An unrotated, uncropped layer. At the FIRST frame of `slide_left` the
    // whole box is just outside the RIGHT edge, so its LEFT edge sits
    // exactly on the canvas's right edge.
    let handle = with_motion(arrive("slide_left", IN));
    let (hx, _, px, _) = geometry((0.0, 0.0, 0.0, 0.0), 0.5, 0.0, 100.0, -60.0);
    let first = layer(&handle, 0);
    close(
        num(&first, "/x"),
        100.0 + (W / 2.0 + hx - px),
        "slide_left at u = 0",
    );
    // The left edge of the drawn box, in canvas-centre coordinates:
    let left_edge = num(&first, "/x") - hx;
    close(
        left_edge,
        W / 2.0,
        "the box's left edge is on the canvas's right edge",
    );
    // Nothing else moved.
    close(
        num(&first, "/y"),
        -60.0,
        "a horizontal slide does not move y",
    );
    close(num(&first, "/scale"), 0.5, "a slide does not scale");
    close(num(&first, "/opacity"), 0.8, "a slide does not fade");

    // Half way, the offset is `(1 − ease_out(0.5)) · S_right`.
    let half = layer(&handle, IN / 2);
    close(
        num(&half, "/x"),
        100.0 + (1.0 - ease_out(0.5)) * (W / 2.0 + hx - px),
        "slide_left at u = 0.5",
    );
}

#[test]
fn a_rotated_layer_slides_by_its_rotated_bounding_box() {
    // 30°, so `k` and `n` are both non-zero and the half-extents mix the
    // source's width and height — a slide measured from the unrotated box
    // would leave a corner on screen.
    let mut video = base();
    video["rotation"] = json!(30.0);
    video["motion"] = arrive("slide_up", IN);
    let handle = Handle::from_value(&project(video));
    let (_, hy, _, py) = geometry((0.0, 0.0, 0.0, 0.0), 0.5, 30.0, 100.0, -60.0);
    let first = layer(&handle, 0);
    close(
        num(&first, "/y"),
        -60.0 + (H / 2.0 + hy - py),
        "slide_up at u = 0",
    );
    close(
        num(&first, "/y") - hy,
        H / 2.0,
        "the box's top edge is on the canvas's bottom edge",
    );
    close(
        num(&first, "/rotation"),
        30.0,
        "a slide does not turn the layer",
    );
}

#[test]
fn a_cropped_layer_slides_by_its_visible_box_from_its_visible_centre() {
    // An ASYMMETRIC crop, so both halves of the rule bite: the visible size
    // is smaller than the source's AND the visible centre is not the
    // anchor. Measured against `geometry`, which is §5b's formula written
    // out here.
    let mut video = base();
    video["crop"] = json!({ "l": 200.0, "t": 0.0, "r": 40.0, "b": 100.0 });
    video["motion"] = arrive("slide_right", IN);
    let handle = Handle::from_value(&project(video));
    let (hx, _, px, _) = geometry((200.0, 0.0, 40.0, 100.0), 0.5, 0.0, 100.0, -60.0);
    let first = layer(&handle, 0);
    close(
        num(&first, "/x"),
        100.0 + (-(W / 2.0 + hx) - px),
        "slide_right at u = 0",
    );
    // The VISIBLE right edge sits on the canvas's left edge — the visible
    // centre is `x + s·R(θ)·c`, which for an unrotated layer is `x + s·cx`.
    let visible_centre = num(&first, "/x") + 0.5 * (200.0 - 40.0) / 2.0;
    close(
        visible_centre + hx,
        -W / 2.0,
        "the visible box's right edge is on the canvas's left edge",
    );
}

#[test]
fn text_slides_from_half_a_canvas_beyond_the_edge() {
    // The core has no measured text size (spec §11), so `hx = W/2`,
    // `hy = H/2` and `c = 0`: the anchor starts half a canvas out, which
    // clears any text narrower than the canvas. A limit, pinned so a later
    // reader does not "fix" it into the media rule and break every caption.
    let text = json!({
        "version": 8,
        "canvas": { "width": W as u32, "height": H as u32, "fps": [30, 1] },
        "media": [],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": D,
            "source": { "kind": "text" },
            "video": { "x": 100.0, "y": -60.0, "scale": 0.5, "opacity": 0.8,
                       "motion": { "in": { "kind": "slide_left", "duration": IN } } },
            "text": { "content": "Hello" }
        }],
        "next_id": 12
    });
    let handle = Handle::from_value(&text);
    let first = layer(&handle, 0);
    // hx = W/2, p = (x, y), so S_right = W/2 + W/2 − x = W − x.
    close(
        num(&first, "/x"),
        100.0 + (W - 100.0),
        "a text slide clears the canvas",
    );
    close(num(&first, "/y"), -60.0, "and moves in one axis only");
}

// ---- during --------------------------------------------------------------

#[test]
fn every_during_kind_is_the_identity_at_the_clips_first_frame() {
    // The property the whole table is built to have: a clip starts where it
    // is placed, whatever it goes on to do. Read as an exact equality
    // rather than a tolerance, because the pivot compensation cancels to
    // the bit when `F` is 1 and `φ` is 0.
    let control = Handle::from_value(&project(base()));
    let plain = layer(&control, 0);
    for kind in ["pulse", "shake", "spin", "bounce", "drift"] {
        let handle = with_motion(json!({
            "during": { "kind": kind, "amount": 1.0, "period": SEC }
        }));
        assert_eq!(
            layer(&handle, 0),
            plain,
            "during {kind} is not the identity at t = 0"
        );
    }
}

#[test]
fn a_spin_of_one_whole_turn_is_exactly_no_turn() {
    // `amount` 0.5 is one turn per period, and the TOTAL rotation is
    // reduced `rem_euclid(360)` before it is added — so at exactly one
    // period the layer is byte-identical to the unmoved clip. Without the
    // reduction the rotation would reach Swift as `Float(360·π/180)`, whose
    // `sin` is ~1.7e-7, and `partnerBox`'s `rotation == 0` guard would read
    // the layer as rotated.
    let control = Handle::from_value(&project(base()));
    let handle = with_motion(json!({
        "during": { "kind": "spin", "amount": 0.5, "period": SEC }
    }));
    assert_eq!(layer(&handle, SEC), layer(&control, SEC));
    // At a QUARTER period it really is turning, which is what stops the row
    // above passing against a build whose spin does nothing.
    close(
        num(&layer(&handle, SEC / 4), "/rotation"),
        90.0,
        "a quarter turn",
    );
}

#[test]
fn the_during_table_is_road_map_five_section_five_b() {
    let amount = 0.75;
    let period = 2 * SEC;
    let t = 3 * SEC;
    let cycles = t as f64 / period as f64;
    let tau = std::f64::consts::TAU;

    let pulse = with_motion(json!({
        "during": { "kind": "pulse", "amount": amount, "period": period }
    }));
    close(
        num(&layer(&pulse, t), "/scale"),
        0.5 * (1.0 + 0.2 * amount * (1.0 - (tau * cycles).cos()) / 2.0),
        "pulse",
    );

    let spin = with_motion(json!({
        "during": { "kind": "spin", "amount": amount, "period": period }
    }));
    close(
        num(&layer(&spin, t), "/rotation"),
        (720.0 * amount * cycles).rem_euclid(360.0),
        "spin",
    );

    let shake = with_motion(json!({
        "during": { "kind": "shake", "amount": amount, "period": period }
    }));
    let m = W.min(H);
    let wave = |k: f64| (tau * k * cycles).sin();
    let l = layer(&shake, t);
    close(
        num(&l, "/x"),
        100.0 + 0.04 * amount * m * (0.6 * wave(1.0) + 0.4 * wave(2.7)),
        "shake x",
    );
    close(
        num(&l, "/y"),
        -60.0 + 0.04 * amount * m * (0.6 * wave(1.3) + 0.4 * wave(3.1)),
        "shake y",
    );

    let bounce = with_motion(json!({
        "during": { "kind": "bounce", "amount": amount, "period": period }
    }));
    close(
        num(&layer(&bounce, t), "/y"),
        -60.0 - 0.08 * amount * H * (std::f64::consts::PI * cycles).sin().abs(),
        "bounce",
    );

    // A drift ignores `period` entirely and runs off the clip's DURATION,
    // so it is the one row whose expected value moves with `D`.
    let drift = with_motion(json!({
        "during": { "kind": "drift", "amount": amount, "period": period }
    }));
    close(
        num(&layer(&drift, t), "/scale"),
        0.5 * (1.0 + 0.24 * amount * t as f64 / D as f64),
        "drift",
    );
    // At `amount` 0.5 the documented end point is ×1.12 — the last FRAME,
    // since a clip's exclusive end is never drawn.
    let half = with_motion(json!({
        "during": { "kind": "drift", "amount": 0.5, "period": period }
    }));
    let last = D - 20_000;
    close(
        num(&layer(&half, last), "/scale"),
        0.5 * (1.0 + 0.24 * 0.5 * last as f64 / D as f64),
        "drift at the last frame",
    );
}

#[test]
fn a_shake_is_the_same_displacement_at_the_same_clip_time_whatever_the_clip_length() {
    // A shake's clock is its PERIOD, not the clip, so a 60 s clip and a 6 s
    // one shake identically — which is what separates it from a drift.
    let short = with_motion(json!({
        "during": { "kind": "shake", "amount": 0.5, "period": SEC }
    }));
    let mut long_source = project({
        let mut video = base();
        video["motion"] = json!({ "during": { "kind": "shake", "amount": 0.5, "period": SEC } });
        video
    });
    long_source["clips"][0]["duration"] = json!(60 * SEC);
    let long = Handle::from_value(&long_source);
    for t in [SEC / 3, 2 * SEC, 5 * SEC] {
        close(
            num(&layer(&short, t), "/x"),
            num(&layer(&long, t), "/x"),
            "shake x",
        );
        close(
            num(&layer(&short, t), "/y"),
            num(&layer(&long, t), "/y"),
            "shake y",
        );
    }
}

// ---- the tent ------------------------------------------------------------

#[test]
fn an_in_and_an_out_longer_than_the_clip_meet_in_the_middle() {
    // `in` 4 s and `out` 4 s on a 6 s clip: in′ = 4·6/8 = 3 s, out′ = 3 s,
    // so the arrival ends on the frame the departure begins and nothing
    // refuses. The FIELD still reads what was written — the tent is
    // render-time arithmetic, not a rewrite of the clip.
    let handle = with_motion(json!({
        "in": { "kind": "fade", "duration": 4 * SEC },
        "out": { "kind": "fade", "duration": 4 * SEC }
    }));
    let stored = handle.value();
    assert_eq!(
        stored["clips"][0]["video"]["motion"]["in"]["duration"],
        json!(4 * SEC)
    );
    // Half way through the arrival, u = 0.5 of a THREE-second ramp.
    close(
        num(&layer(&handle, 3 * SEC / 2), "/opacity"),
        0.8 * ease_out(0.5),
        "the tent's arrival is measured on in′",
    );
    // The frame the two meet on is the departure's v = 0, opacity full.
    close(
        num(&layer(&handle, 3 * SEC), "/opacity"),
        0.8,
        "the tent's apex",
    );
    // And half way through the departure, v = 0.5 of a three-second ramp.
    close(
        num(&layer(&handle, 3 * SEC + 3 * SEC / 2), "/opacity"),
        0.8 * (1.0 - ease_in(0.5)),
        "the tent's departure is measured on out′",
    );
}

// ---- composition ---------------------------------------------------------

#[test]
fn an_action_moving_x_still_moves_under_a_slide() {
    // Motion is applied to the EVALUATED props, so an action and a preset
    // compose rather than one winning: the action decides where the clip is
    // placed and the preset decides where it is drawn relative to that.
    let mut source = project({
        let mut video = base();
        video["motion"] = arrive("slide_up", IN);
        video
    });
    source["clips"][0]["actions"] = json!([{
        "id": 20, "start": 0, "duration": 2 * SEC, "curve": "linear",
        "end": { "video": { "x": 500.0 } }
    }]);
    source["next_id"] = json!(21);
    let handle = Handle::from_value(&source);
    // At half the action, x has reached 300; the slide adds its own offset
    // to THAT, and the slide's own geometry is measured from it.
    let t = SEC;
    let (_, hy, _, py) = geometry((0.0, 0.0, 0.0, 0.0), 0.5, 0.0, 300.0, -60.0);
    let l = layer(&handle, t);
    close(num(&l, "/x"), 300.0, "the action still moves x");
    close(
        num(&l, "/y"),
        -60.0 + (1.0 - ease_out(0.5)) * (H / 2.0 + hy - py),
        "and the slide is measured from where the action put it",
    );
}

#[test]
fn a_zoom_holds_the_visible_centre_of_a_cropped_layer() {
    // The core's placement rule pivots on the UNCROPPED anchor, so a zoom
    // about it would make a cropped layer drift across its own preset. The
    // compensation holds the VISIBLE centre fixed, which is what this
    // measures: the visible centre under `zoom_in` at u = 0.5 is exactly
    // where it is with no motion at all.
    let crop = (200.0, 0.0, 40.0, 100.0);
    let mut moving = base();
    moving["crop"] = json!({ "l": crop.0, "t": crop.1, "r": crop.2, "b": crop.3 });
    let mut still = moving.clone();
    moving["motion"] = arrive("zoom_in", IN);
    let handle = Handle::from_value(&project(moving));
    let control = Handle::from_value(&project(still.take()));

    let visible_centre = |l: &Value| {
        let scale = num(l, "/scale");
        (
            num(l, "/x") + scale * (crop.0 - crop.2) / 2.0,
            num(l, "/y") + scale * (crop.1 - crop.3) / 2.0,
        )
    };
    let moved = visible_centre(&layer(&handle, IN / 2));
    let fixed = visible_centre(&layer(&control, IN / 2));
    close(moved.0, fixed.0, "the visible centre's x is held");
    close(moved.1, fixed.1, "the visible centre's y is held");
    // ...and the layer really is smaller, so the row above is not vacuous.
    close(
        num(&layer(&handle, IN / 2), "/scale"),
        0.5 * (0.6 + 0.4 * ease_out(0.5)),
        "zoom_in at u = 0.5",
    );
}

#[test]
fn a_factor_past_the_scale_ceiling_clamps_and_the_offsets_follow_it() {
    // `zoom_out`'s arrival opens at ×1.4, which on a layer at ×8 is 11.2 —
    // past SCALE_MAX. The scale is clamped BEFORE the offsets are derived
    // from it, so the layer still sits where the compensation put it and
    // only the magnification degrades (`add_zoom_action`'s rule).
    let mut video = base();
    video["scale"] = json!(8.0);
    video["motion"] = arrive("zoom_out", IN);
    let handle = Handle::from_value(&project(video));
    close(num(&layer(&handle, 0), "/scale"), 10.0, "the ceiling holds");
    // With no crop the compensation is zero either way, so the offset is
    // the base one and nothing has run away.
    close(
        num(&layer(&handle, 0), "/x"),
        100.0,
        "x is unmoved by the clamp",
    );
}

// ---- nests ---------------------------------------------------------------

/// A project whose timeline clip 11 shows nest 60, with `video` on the NEST
/// clip and one image clip inside.
fn nested(outer: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 8,
        "canvas": { "width": W as u32, "height": H as u32, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.png", "kind": "image",
            "width": 640, "height": 360, "fps": [30, 1]
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": D,
            "source": { "kind": "nest", "project": 60 },
            "video": outer
        }],
        "markers": [],
        "next_id": 70,
        "nests": [{
            "id": 60, "name": "Group", "width": 1280, "height": 720,
            "tracks": [{ "id": 61, "name": "Inner" }],
            "clips": [{
                "id": 62, "track": 61, "start": 0, "duration": D,
                "source": { "kind": "image", "media": 1 },
                "video": { "x": 80.0, "y": 40.0, "scale": 2.0 }
            }]
        }]
    }))
}

#[test]
fn a_nest_clips_motion_scales_every_layer_inside_it_about_its_placed_centre() {
    // The second call site: `frame_of` moves each enclosing clip's
    // evaluated video before folding it, so a preset on a nest clip carries
    // everything inside it. Measured against the same nest with no motion,
    // through the factor the table promises.
    let mut outer = json!({ "x": 60.0, "y": -30.0, "scale": 0.75 });
    let control = nested(outer.clone());
    outer["motion"] = arrive("zoom_in", IN);
    let handle = nested(outer);

    let f = 0.6 + 0.4 * ease_out(0.5);
    let moved = layer(&handle, IN / 2);
    let fixed = layer(&control, IN / 2);
    close(
        num(&moved, "/scale"),
        num(&fixed, "/scale") * f,
        "the inner layer scales by the nest clip's factor",
    );
    // The nest clip has no crop, so its visible centre IS its anchor: every
    // inner layer scales about the point the nest clip is placed at.
    let anchor = (60.0, -30.0);
    close(
        num(&moved, "/x") - anchor.0,
        (num(&fixed, "/x") - anchor.0) * f,
        "and about the nest clip's placed centre in x",
    );
    close(
        num(&moved, "/y") - anchor.1,
        (num(&fixed, "/y") - anchor.1) * f,
        "and in y",
    );
    // The inner clip's own opacity is untouched: the nest clip's fade is
    // the FRAME's, folded by `Frame::place`.
    close(
        num(&moved, "/opacity"),
        ease_out(0.5),
        "the nest clip's fade multiplies through",
    );
}

#[test]
fn a_nest_inside_a_nest_measures_each_level_against_its_own_container() {
    // The `container` argument of `frame_of`'s call: an inner nest clip's
    // slide is measured against the nest ENCLOSING it, not against the
    // project canvas. Pinned by the slide distance, which is the only
    // observable that depends on the container's size.
    let deep = json!({
        "version": 8,
        "canvas": { "width": W as u32, "height": H as u32, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.png", "kind": "image",
            "width": 640, "height": 360, "fps": [30, 1]
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": D,
            "source": { "kind": "nest", "project": 60 }, "video": {}
        }],
        "markers": [],
        "next_id": 80,
        "nests": [
            {
                "id": 60, "name": "Outer", "width": 1280, "height": 720,
                "tracks": [{ "id": 61, "name": "A" }],
                "clips": [{
                    "id": 62, "track": 61, "start": 0, "duration": D,
                    "source": { "kind": "nest", "project": 70 },
                    "video": { "motion": { "in": { "kind": "slide_left", "duration": IN } } }
                }]
            },
            {
                "id": 70, "name": "Inner", "width": 640, "height": 360,
                "tracks": [{ "id": 71, "name": "B" }],
                "clips": [{
                    "id": 72, "track": 71, "start": 0, "duration": D,
                    "source": { "kind": "image", "media": 1 }, "video": {}
                }]
            }
        ]
    });
    let handle = Handle::from_value(&deep);
    let control = {
        let mut without = deep.clone();
        without["nests"][0]["clips"][0]["video"] = json!({});
        Handle::from_value(&without)
    };
    // Clip 62's own box is nest 70's canvas, 640 × 360, at scale 1 and no
    // crop, inside a 1280 × 720 container: S_right = 1280/2 + 320 − 0 = 960.
    // A container of 1920 would give 1280, so the row discriminates.
    let moved = num(&layer(&handle, 0), "/x");
    let fixed = num(&layer(&control, 0), "/x");
    close(
        moved - fixed,
        960.0,
        "the inner slide is measured in its own nest",
    );
}

// ---- the short circuit ---------------------------------------------------

#[test]
fn a_clip_with_no_motion_renders_the_recipe_it_always_did() {
    // The claim the whole feature rests on: `motion: null` costs nothing.
    // A byte comparison of the recipe TEXT, which is what a shipped project
    // opening unchanged means.
    let plain = Handle::from_value(&project(base()));
    let explicit = Handle::from_value(&project({
        let mut video = base();
        video["motion"] = Value::Null;
        video
    }));
    for t in [0, SEC, 3 * SEC, D - 20_000] {
        assert_eq!(
            plain.recipe_text(t),
            explicit.recipe_text(t),
            "an explicit null motion changed the recipe at {t}"
        );
    }
}

#[test]
fn a_clip_past_its_arrival_renders_the_recipe_it_always_did() {
    // `x + b − b` is not `x` in floats, so an implementation that computed
    // an identity instead of short-circuiting would answer a recipe that
    // differs in the last bits — invisible on screen and fatal to every
    // byte comparison the proofs are built on. The crop is asymmetric here
    // on purpose: it is what makes the pivot terms non-zero.
    let mut video = base();
    video["crop"] = json!({ "l": 200.0, "t": 0.0, "r": 40.0, "b": 100.0 });
    video["rotation"] = json!(30.0);
    let plain = Handle::from_value(&project(video.clone()));
    video["motion"] = arrive("spin", IN);
    let moving = Handle::from_value(&project(video));
    for t in [IN, IN + SEC, D - 20_000] {
        assert_eq!(
            plain.recipe_text(t),
            moving.recipe_text(t),
            "the frame at {t} is not byte-identical to the unmoved clip"
        );
    }
    // And inside the arrival it really does differ, so the row is not
    // measuring an implementation that does nothing at all.
    assert_ne!(plain.recipe_text(IN / 2), moving.recipe_text(IN / 2));
}

// ---- the file is never trusted -------------------------------------------

#[test]
fn a_hand_written_degenerate_preset_is_inactive_rather_than_a_nan() {
    // `validate` range-checks no property and `evaluate_clip`'s restore
    // copies the base motion past `clamp_video`, so these reach `apply`
    // however the op path would have refused them. Each must leave the clip
    // exactly where it is rather than poisoning the frame.
    let plain = Handle::from_value(&project(base()));
    for motion in [
        json!({ "in": { "kind": "slide_left", "duration": -600000 } }),
        json!({ "out": { "kind": "fade", "duration": 0 } }),
        json!({ "during": { "kind": "pulse", "amount": 0.5, "period": 0 } }),
        json!({ "during": { "kind": "spin", "amount": 0.5, "period": -600000 } }),
    ] {
        let handle = with_motion(motion.clone());
        assert_eq!(
            handle.recipe_text(SEC),
            plain.recipe_text(SEC),
            "a degenerate {motion} was not inactive"
        );
    }
    // An `amount` out of range is CLAMPED rather than ignored, which is the
    // one of the four that still moves the clip.
    let hot = with_motion(json!({ "during": { "kind": "drift", "amount": 5.0, "period": SEC } }));
    let one = with_motion(json!({ "during": { "kind": "drift", "amount": 1.0, "period": SEC } }));
    assert_eq!(hot.recipe_text(3 * SEC), one.recipe_text(3 * SEC));
}
