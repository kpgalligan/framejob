//! `video.motion` at the EDGES the E2 reader review found — the inputs the
//! tables in `core/tests/motion.rs` do not sample, read off `frame_recipe`
//! through the FFI.
//!
//! Every fixture here is a concrete input that produced a wrong output, kept
//! so the input cannot come back. The numbers are computed from
//! `core/src/motion.rs`'s module doc and road map 5 §5b–§5c, never read off
//! a run.

mod common;

use serde_json::{json, Value};

use common::{num, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

const W: f64 = 1920.0;
const H: f64 = 1080.0;
const SW: f64 = 1280.0;
const SH: f64 = 800.0;

/// One media clip (id 11) on one track, `duration` long, placed off centre,
/// carrying whatever `video` says. `motion.rs`'s fixture shape, with the
/// clip's length a parameter because these edges are about long clips.
fn project(video: Value, duration: i64) -> Value {
    json!({
        "version": 8,
        "canvas": { "width": W as u32, "height": H as u32, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 10 * 60 * SEC, "width": SW as u32, "height": SH as u32,
            "fps": [30, 1], "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": duration,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": video, "audio": {}
        }],
        "next_id": 12
    })
}

fn with_motion(motion: Value, duration: i64) -> Handle {
    let video = json!({ "x": 100.0, "y": -60.0, "scale": 0.5, "opacity": 0.8, "motion": motion });
    Handle::from_value(&project(video, duration))
}

/// The one layer of the fixture's recipe at project time `t`.
fn layer(handle: &Handle, t: i64) -> Value {
    let recipe = handle.recipe(t);
    let layers = recipe["layers"].as_array().expect("layers").clone();
    assert_eq!(
        layers.len(),
        1,
        "the fixture draws exactly one layer at {t}"
    );
    layers[0].clone()
}

// ---- R1·1: the reduction's own 360 --------------------------------------

/// Road map 5 §5c: "`φ` is taken `rem_euclid(360)` before it is added, so a
/// whole turn is EXACTLY no turn" — because a rotation of 360 reaches Swift
/// as `Float(360·π/180)`, whose `sin` is ~1.7e-7 rather than 0, and
/// `partnerBox`'s `rotation == 0` guard would read the layer as rotated.
///
/// `f64::rem_euclid` cannot keep that promise on its own: it is
/// `let r = self % rhs; if r < 0.0 { r + rhs.abs() } else { r }`, and for a
/// φ of −1.998e-14 the addition ROUNDS UP to exactly 360.0 (the spacing of
/// doubles at 360 is 5.68e-14). An arrival `spin` produces exactly that φ
/// one tick before it ends: `φ = −180·(1 − ease_out(u))`, and the smallest
/// non-zero `1 − ease_out(u)` a double can hold is `2⁻⁵³ = 1.110e-16`.
///
/// `in.duration` 100,000,001 ticks on a clip longer than that puts the
/// frame at t = 100,000,000 — frame 5000 at 30 fps, an ordinary frame of an
/// ordinary three-minute screen recording — inside that window.
#[test]
fn an_arrival_spin_one_tick_from_its_end_reduces_to_zero_and_not_to_a_whole_turn() {
    // The window, written out again rather than read off a run: `q = 1 − u`
    // has to square to something that rounds to 2⁻⁵³.
    let arrive = 100_000_001_i64;
    let t = 100_000_000_i64;
    let u = t as f64 / arrive as f64;
    let a = 1.0 - (1.0 - u) * (1.0 - u);
    assert_eq!(
        1.0 - a,
        f64::powi(2.0, -53),
        "the fixture has to sit on the one φ the reduction rounds up"
    );

    let handle = with_motion(
        json!({ "in": { "kind": "spin", "duration": arrive } }),
        200 * SEC,
    );
    let rotation = num(&layer(&handle, t), "/rotation");
    assert_eq!(
        rotation, 0.0,
        "a φ of −1.998e-14 reduces to 0, not to the 360 the guard cannot see"
    );
}

/// The same edge reached the other way round, so a fix that special-cases
/// one arrival cannot pass: a `during: spin` whose total is a hair UNDER a
/// whole turn. `φ = 720·A·t/P`, so `A = 0.5`, `P = t` is exactly one turn
/// and `P = t + 100` is 0.001° under it — a shortfall an f32 of DEGREES can
/// see, which is the band `motion.rs` chose for "under a turn"
/// (`no_whole_turn` says why it is a choice). A shortfall NARROWER than that
/// is published as no turn at all, which is the property test below.
#[test]
fn a_during_spin_a_hair_under_a_whole_turn_still_reduces_to_a_small_angle() {
    let t = 60 * SEC;
    let handle = with_motion(
        json!({ "during": { "kind": "spin", "amount": 0.5, "period": t } }),
        200 * SEC,
    );
    // Exactly one turn is exactly no turn — `360 % 360` is 0, the arm that
    // already worked.
    assert_eq!(num(&layer(&handle, t), "/rotation"), 0.0);

    // And a hair under one turn is a hair under 360, never 360 itself —
    // and OUTSIDE the band the reduction publishes as no turn
    // (`no_whole_turn`).
    let handle = with_motion(
        json!({ "during": { "kind": "spin", "amount": 0.5, "period": t + 100 } }),
        200 * SEC,
    );
    let rotation = num(&layer(&handle, t), "/rotation");
    assert!(
        (359.0..360.0).contains(&rotation) && (rotation as f32) < 360.0,
        "a hair under a turn stays under it: got {rotation}"
    );
}

/// The assertion every spin in this file is held to, written once.
///
/// `Compositor.swift`'s `partnerBox` guard tests `rotation == 0` EXACTLY, on
/// the recipe's f64, so `motion.rs` publishes a BAND under a whole turn as no
/// turn, and the band it CHOSE is "rounds to 360 as an f32 of degrees": every
/// double from `360 − 2⁻¹⁶` up, `359.99999999999994` among them. This pins
/// that CHOSEN band, not a consumer's precision: nothing reads degrees into an
/// f32 (the Metal uniform is `Float(rotation · π/180)`, radians, and conflates
/// only 3.64e-6° under a turn), and a threshold decided in THAT precision
/// fails the `during` row below, which sits 1.0e-5° under a turn (measured by
/// the second sceptic pass, road map 5 §12).
fn no_whole_turn(rotation: f64, what: &str) {
    assert!(
        (rotation as f32) < 360.0,
        "{what} published a rotation of {rotation}, which is {} as an f32",
        rotation as f32
    );
}

/// And the reduction's promise as a property rather than as one fixture:
/// no `in.duration` anywhere near the window publishes a rotation of 360 —
/// and on the last two ticks of the arrival, where φ is a few times 1e-14
/// short of a whole turn, the published rotation is exactly 0.
#[test]
fn no_arrival_spin_anywhere_near_the_window_publishes_a_whole_turn() {
    for arrive in [
        79_999_999_i64,
        80_000_000,
        100_000_000,
        100_000_001,
        120_000_000,
        134_000_000,
        150_000_000,
    ] {
        let handle = with_motion(
            json!({ "in": { "kind": "spin", "duration": arrive } }),
            300 * SEC,
        );
        for t in [arrive - 1, arrive - 2, 100_000_000] {
            if t < 0 {
                continue;
            }
            let rotation = num(&layer(&handle, t), "/rotation");
            no_whole_turn(rotation, &format!("in.duration {arrive} at t {t}"));
            // The last two ticks: `φ = −180·(k/in)²` with `k` 1 or 2 and
            // `in` ≥ 8e7, so |φ| ≤ 1.2e-13 — a turn short of nothing, which
            // is nothing.
            if t >= arrive - 2 {
                assert_eq!(
                    rotation, 0.0,
                    "in.duration {arrive} at t {t}: a spin a tick from its end is no turn"
                );
            }
        }
    }
}

/// The other two slots and the other DIRECTION, against the same assertion,
/// so the arrival is not the only spin the reduction is proved on.
///
/// A departure's `φ = 180·ease_in(v)` is bounded by 180 and cannot reach a
/// turn by itself — the row says so by measuring it rather than by arguing
/// it. A `during` can: `φ = 720·A·t/P` lands a hair under a turn whenever
/// `t/P` lands a hair under `1/(2A)`. And the sum of a NEGATIVE arrival φ
/// with a during's whole turns is the reversed case — the arm `rem_euclid`
/// adds 360 to, one turn further out — which is where the reduction has to
/// see the TOTAL and not one slot.
#[test]
fn no_departure_no_during_and_no_reversed_sum_publishes_a_whole_turn() {
    let d = 200 * SEC;
    for leave in [SEC, 60 * SEC, 100_000_001] {
        let handle = with_motion(json!({ "out": { "kind": "spin", "duration": leave } }), d);
        for t in [d - leave, d - 2, d - 1] {
            let rotation = num(&layer(&handle, t), "/rotation");
            no_whole_turn(rotation, &format!("out.duration {leave} at t {t}"));
            assert!(
                (0.0..=180.0).contains(&rotation),
                "a departure spin is half a turn at most: got {rotation}"
            );
        }
    }

    // A during a hair under a turn, by a hair NARROWER than the chosen band:
    // `P = t + 1` leaves 1.0e-5°, where the band is 2⁻¹⁶ = 1.5259e-5° wide.
    let t = 60 * SEC;
    let handle = with_motion(
        json!({ "during": { "kind": "spin", "amount": 0.5, "period": t + 1 } }),
        d,
    );
    let rotation = num(&layer(&handle, t), "/rotation");
    no_whole_turn(rotation, "a during spin 1.0e-5° under a turn");
    assert_eq!(
        rotation, 0.0,
        "1.0e-5° under a turn is inside the band the reduction publishes as no turn"
    );

    // The reversed arm: at t = 99,999,998 the arrival contributes
    // φ = −180·(2/1e8)² = −7.2e-14 and the during contributes exactly two
    // turns (`P = t/2`), so the total is 719.999999999999886 and its
    // remainder 359.999999999999886.
    let handle = with_motion(
        json!({
            "in": { "kind": "spin", "duration": 100_000_000 },
            "during": { "kind": "spin", "amount": 0.5, "period": 49_999_999 }
        }),
        300 * SEC,
    );
    let rotation = num(&layer(&handle, 99_999_998), "/rotation");
    no_whole_turn(rotation, "a negative arrival φ added to two whole turns");
    assert_eq!(
        rotation, 0.0,
        "two turns less 7.2e-14 is two turns, and two turns is no turn"
    );
}

// ---- R2·1: paste_attributes' second spelling of "no motion" -------------

/// A payload clip whose `video` carries an EMPTY motion — `{}`, or three
/// explicit nulls, both of which serde reads as a `Motion` with three
/// `None`s — copied onto a target by `paste_attributes`.
fn paste_attributes_payload(motion: Value) -> Value {
    json!({
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": { "x": 5.0, "motion": motion },
            "audio": {}
        }],
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 10 * 60 * SEC, "width": SW as u32, "height": SH as u32,
            "fps": [30, 1], "has_video": true, "has_audio": true
        }],
        "fps": [30, 1]
    })
}

/// Road map 5 §5a: "a `Motion` whose three slots are all `None` is stored as
/// `None` — so one clip has one spelling of no motion". The patch path keeps
/// it (`edit_props.rs`) and the split rule keeps it (`edit_split.rs`);
/// `paste_attributes` is a third door for a `Motion`, and it copies the
/// payload's video group whole.
///
/// Without the normalisation the target stores
/// `{"in": null, "out": null, "during": null}`, which a save writes out and
/// which makes a clip with no motion compare unequal to a clip with no
/// motion.
#[test]
fn paste_attributes_stores_one_spelling_of_no_motion() {
    for payload in [
        json!({}),
        json!({ "in": null, "out": null, "during": null }),
    ] {
        let handle = with_motion(Value::Null, 6 * SEC);
        let after = handle.apply(&json!({
            "op": "paste_attributes",
            "clips": [11],
            "payload": paste_attributes_payload(payload.clone()),
            "groups": ["video"]
        }));
        let stored = after.value()["clips"][0]["video"]["motion"].clone();
        assert_eq!(
            stored,
            Value::Null,
            "a payload motion of {payload} must land as null, not as {stored}"
        );
        // …and the rest of the group still travelled, so the normalisation
        // did not eat the paste.
        assert_eq!(after.value()["clips"][0]["video"]["x"], json!(5.0));
    }
}

/// The same op with a motion that is NOT empty still copies it whole — the
/// normalisation is about the empty spelling only.
#[test]
fn paste_attributes_still_copies_a_real_motion() {
    let handle = with_motion(Value::Null, 6 * SEC);
    let after = handle.apply(&json!({
        "op": "paste_attributes",
        "clips": [11],
        "payload": paste_attributes_payload(json!({ "out": { "kind": "pop", "duration": 300_000 } })),
        "groups": ["video"]
    }));
    assert_eq!(
        after.value()["clips"][0]["video"]["motion"],
        json!({ "in": null, "out": { "kind": "pop", "duration": 300_000 }, "during": null })
    );
}

// ---- R3·1: what a motion patch answers on a clip already out of range ----

/// `paste` does not range-check its payload (it stores a `scale` of 500 as
/// readily as a legal one — R2·2, and true of every property, not of motion),
/// so a clip can be carrying a value `check_video` refuses. A later `set_video`
/// re-checks the WHOLE group, so a motion patch on such a clip is an `Err`
/// — the arm that THROWS in Swift, where an identity and a refusal only beep.
///
/// That is what makes `EditorViewController+Motion.swift`'s "a mixed one
/// lands" only two thirds of the story: a batch with one such clip in it
/// lands NOTHING and puts up the core's own message.
#[test]
fn a_motion_patch_on_a_clip_already_out_of_range_is_an_error() {
    let handle = with_motion(Value::Null, 6 * SEC);
    let payload = json!({
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": { "x": 0.0, "scale": 500.0 },
            "audio": {}
        }],
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 10 * 60 * SEC, "width": SW as u32, "height": SH as u32,
            "fps": [30, 1], "has_video": true, "has_audio": true
        }],
        "fps": [30, 1]
    });
    let pasted = handle.apply(&json!({
        "op": "paste", "payload": payload, "at": 60 * SEC, "track": 2
    }));
    let id = pasted.value()["clips"]
        .as_array()
        .expect("clips")
        .iter()
        .find(|c| c["start"] == json!(60 * SEC))
        .expect("the pasted clip")["id"]
        .as_u64()
        .expect("id");
    assert_eq!(pasted.value()["clips"][1]["video"]["scale"], json!(500.0));

    let message = pasted.errors(&json!({
        "op": "set_video", "clips": [id],
        "patch": { "motion": { "in": { "kind": "fade", "duration": 300_000 } } }
    }));
    assert!(
        message.contains("scale"),
        "the re-check names the stored value, not the motion: {message}"
    );
}
