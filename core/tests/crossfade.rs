//! The transition's two version-7 terms, through the FFI: the CURVE the
//! compositor's progress is eased by, and the constant-power AUDIO
//! crossfade under it (road map 5's E1, spec §7.2 and §7.3).
//!
//! Both are computed in the core and neither has an op of its own, so what
//! is asserted here is what the core HANDS OVER — the recipe's `progress`
//! at a tick, and the plan's `ramps` at every breakpoint — rather than
//! anything about pixels or samples, which the core never touches (spec
//! §7).
//!
//! The claims, and why each one:
//!
//! - **A linear curve is byte-identical to no curve at all.** `ease` is the
//!   identity on `Curve::Linear`, which is what makes every project written
//!   before version 7 render exactly what it rendered — and a build that
//!   eased unconditionally would pass a spot check at p = 0.5, where three
//!   of the four curves agree.
//! - **`audio: false` leaves the envelope exactly as it was.** A
//!   hand-written expectation, not a comparison against another build:
//!   a pair of overlapping clips with no crossfade produces the two flat
//!   ramps it always did.
//! - **A crossfade tracks `cos`/`sin` of the EASED progress at every
//!   breakpoint**, which is stronger than sampling it: the ramps tile the
//!   whole extent, so every endpoint of every ramp is checked.
//! - **The outgoing clip's LAST breakpoint is 0.** `progress_in` is
//!   half-open, right for the picture; an envelope read from the LEFT at
//!   the overlap's end would find no transition there and report gain 1,
//!   undoing the whole fade on the last ramp. `crossfade_among` closes the
//!   span on `Side::Left` for exactly that, and this is the test that
//!   fails without it.
//! - **Mute, solo and the fades keep their precedence**, because the term
//!   MULTIPLIES like ducking rather than replacing anything.
//! - **A pair inside a nest fades, and a nest pair fades everything inside
//!   it — including both at once.** The sound parts company with the
//!   picture here on purpose (`audio.rs`'s module doc).
//! - **A long overlap does not explode the breakpoint list.** The sampling
//!   step is the action loop's own, so a twenty-minute crossfade costs
//!   ~4096 points and not 36,000.

use serde_json::{json, Value};

mod common;
use common::{array, at, int, num, Handle};

const SEC: i64 = 600_000;
const FRAME: i64 = SEC / 30;

/// Comparison slack. The expectations below are transcendental
/// (`cos`, `sin`) rather than exactly representable, so this is looser than
/// `evaluate_tests.rs`'s 1e-12 and still some seven orders of magnitude
/// below what any sample resolves.
const EPS: f64 = 1e-9;

// ---- fixtures ------------------------------------------------------------

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// Two clips on one track, 0…6 s and 5…11 s, overlapping by a second, with
/// `transition_in` spelled exactly as `transition` says.
fn pair(transition: Value) -> Value {
    json!({
        "version": 7,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": [video_media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            { "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
              "source": { "kind": "media", "media": 1, "in": 0 },
              "video": {}, "audio": {} },
            { "id": 12, "track": 2, "start": 5 * SEC, "duration": 6 * SEC,
              "source": { "kind": "media", "media": 1, "in": 5 * SEC },
              "video": {}, "audio": {},
              "transition_in": transition }
        ],
        "markers": [],
        "next_id": 13
    })
}

fn crossfading(curve: &str) -> Value {
    pair(json!({ "kind": "cross_dissolve", "curve": curve, "audio": true }))
}

/// Every ramp of the composition audio track that carries `clip`.
fn ramps_for(plan: &Value, clip: i64) -> Vec<Value> {
    for comp in array(plan, "/audio_tracks") {
        if array(comp, "/segments")
            .iter()
            .any(|s| int(s, "/clip") == clip)
        {
            return array(comp, "/ramps").clone();
        }
    }
    panic!("no audio track carries clip {clip} in {plan}");
}

/// The gain at `t` approached from the LEFT — the `to` of the ramp that
/// ends exactly there — and from the RIGHT, the `from` of the one that
/// starts there.
///
/// Read this way rather than off the ends of the list, because a
/// composition audio track carries every segment the A/B assignment put on
/// it and the clip asked about need not be the last of them.
fn gain_approaching(plan: &Value, clip: i64, t: i64) -> f64 {
    ramps_for(plan, clip)
        .iter()
        .find(|r| int(r, "/start") + int(r, "/duration") == t)
        .map(|r| num(r, "/to"))
        .unwrap_or_else(|| panic!("no ramp ends at {t} on the track carrying clip {clip}"))
}

fn gain_leaving(plan: &Value, clip: i64, t: i64) -> f64 {
    ramps_for(plan, clip)
        .iter()
        .find(|r| int(r, "/start") == t)
        .map(|r| num(r, "/from"))
        .unwrap_or_else(|| panic!("no ramp starts at {t} on the track carrying clip {clip}"))
}

/// The four curves as `actions::ease` computes them, restated here so a
/// change to the implementation fails this file rather than moving with it.
///
/// The CLAMP is part of the definition and not a convenience: `ease_out` of
/// 6 is −24, so a helper that took its input on trust would expect silence
/// where the implementation expects full gain.
fn ease(curve: &str, u: f64) -> f64 {
    let u = if u.is_nan() { 0.0 } else { u.clamp(0.0, 1.0) };
    match curve {
        "linear" => u,
        "ease_in" => u * u,
        "ease_out" => 1.0 - (1.0 - u) * (1.0 - u),
        "ease_in_out" => u * u * (3.0 - 2.0 * u),
        other => panic!("unknown curve {other}"),
    }
}

/// The gain the constant-power law asks for at progress `p`.
fn expected_gain(p: f64, incoming: bool) -> f64 {
    let angle = p.clamp(0.0, 1.0) * std::f64::consts::FRAC_PI_2;
    if incoming {
        angle.sin()
    } else {
        angle.cos()
    }
}

/// Walks a clip's ramps and asserts every endpoint against the law, for the
/// span of the 5…6 s overlap and for the flat stretches outside it.
fn assert_follows_the_law(plan: &Value, clip: i64, incoming: bool, curve: &str) {
    let ramps = ramps_for(plan, clip);
    assert!(!ramps.is_empty(), "clip {clip} produced no ramps");
    let overlap_start = 5 * SEC;
    let overlap_end = 6 * SEC;
    let (clip_start, clip_end) = if incoming {
        (5 * SEC, 11 * SEC)
    } else {
        (0, 6 * SEC)
    };

    let gain_at = |t: i64| -> f64 {
        if t < clip_start || t > clip_end {
            return 0.0;
        }
        if t < overlap_start {
            return 1.0;
        }
        let p = ease(
            curve,
            (t - overlap_start) as f64 / (overlap_end - overlap_start) as f64,
        );
        expected_gain(p, incoming)
    };

    for (i, ramp) in ramps.iter().enumerate() {
        let start = int(ramp, "/start");
        let span = int(ramp, "/duration");
        // A ramp that straddles a clip edge is a jump the envelope is
        // entitled to make (gain 0 in a gap), so only the endpoints INSIDE
        // the clip's own extent are the law's.
        if start >= clip_start && start < clip_end {
            assert!(
                (num(ramp, "/from") - gain_at(start)).abs() < EPS,
                "clip {clip} ramp {i} starts at {} not {} (t = {start})",
                num(ramp, "/from"),
                gain_at(start)
            );
        }
        let end = start + span;
        if end > clip_start && end <= clip_end {
            assert!(
                (num(ramp, "/to") - gain_at(end)).abs() < EPS,
                "clip {clip} ramp {i} ends at {} not {} (t = {end})",
                num(ramp, "/to"),
                gain_at(end)
            );
        }
    }
}

// ---- the eased progress the compositor is handed -------------------------

#[test]
fn a_linear_curve_hands_over_the_raw_fraction() {
    // `ease(Linear, u)` is `u`, which is the whole reason a version-6
    // project's transitions are byte-identical to what they were.
    let handle = Handle::from_value(&crossfading("linear"));
    for step in [0, SEC / 4, SEC / 2, 3 * SEC / 4, SEC - FRAME] {
        let recipe = handle.recipe(5 * SEC + step);
        let incoming = array(&recipe, "/layers")
            .iter()
            .find(|l| l["clip"] == json!(12))
            .expect("the incoming clip draws inside the overlap")
            .clone();
        let expected = step as f64 / SEC as f64;
        assert!(
            (num(&incoming, "/transition/progress") - expected).abs() < EPS,
            "progress at +{step} is {} not {expected}",
            num(&incoming, "/transition/progress")
        );
    }
}

#[test]
fn every_curve_shapes_the_progress_and_both_halves_agree() {
    // Both clips of a pair report ONE progress — the compositor draws them
    // as one pair (spec §7.3) — so the easing has to be applied where both
    // read it, and not in one of the two call sites.
    for curve in ["linear", "ease_in", "ease_out", "ease_in_out"] {
        let handle = Handle::from_value(&crossfading(curve));
        for step in [SEC / 4, SEC / 2, 3 * SEC / 4] {
            let recipe = handle.recipe(5 * SEC + step);
            let layers = array(&recipe, "/layers");
            let outgoing = layers.iter().find(|l| l["clip"] == json!(11)).unwrap();
            let incoming = layers.iter().find(|l| l["clip"] == json!(12)).unwrap();
            let raw = step as f64 / SEC as f64;
            let expected = ease(curve, raw);
            assert!(
                (num(incoming, "/transition/progress") - expected).abs() < EPS,
                "{curve} at +{step} gave {} not {expected}",
                num(incoming, "/transition/progress")
            );
            assert!(
                (num(outgoing, "/transition/progress") - num(incoming, "/transition/progress"))
                    .abs()
                    < EPS,
                "the two halves of the pair disagree under {curve}"
            );
        }
    }
}

#[test]
fn an_eased_curve_differs_from_the_raw_one_where_it_should() {
    // The guard against a build that computes the curve and throws it away:
    // at a quarter of the way through, all four answers are distinct.
    let mut seen: Vec<f64> = Vec::new();
    for curve in ["linear", "ease_in", "ease_out", "ease_in_out"] {
        let handle = Handle::from_value(&crossfading(curve));
        let recipe = handle.recipe(5 * SEC + SEC / 4);
        let incoming = array(&recipe, "/layers")
            .iter()
            .find(|l| l["clip"] == json!(12))
            .unwrap()
            .clone();
        seen.push(num(&incoming, "/transition/progress"));
    }
    for (i, a) in seen.iter().enumerate() {
        for b in seen.iter().skip(i + 1) {
            assert!(
                (a - b).abs() > 1e-3,
                "two curves gave the same progress: {a} and {b}"
            );
        }
    }
}

// ---- the envelope, with and without a crossfade --------------------------

#[test]
fn a_silent_transition_leaves_the_envelope_exactly_as_it_was() {
    // The hand-written expectation, and the promise a version-6 file leans
    // on: two overlapping clips with `audio: false` produce the two flat
    // ramps they always did, one per composition track, each covering its
    // own clip's extent at gain 1.
    let plan = Handle::from_value(&pair(json!({ "kind": "cross_dissolve" }))).plan();
    let outgoing = ramps_for(&plan, 11);
    assert_eq!(outgoing.len(), 1);
    assert_eq!(int(&outgoing[0], "/start"), 0);
    assert_eq!(int(&outgoing[0], "/duration"), 6 * SEC);
    assert!((num(&outgoing[0], "/from") - 1.0).abs() < EPS);
    assert!((num(&outgoing[0], "/to") - 1.0).abs() < EPS);

    let incoming = ramps_for(&plan, 12);
    assert_eq!(incoming.len(), 1);
    assert_eq!(int(&incoming[0], "/start"), 5 * SEC);
    assert_eq!(int(&incoming[0], "/duration"), 6 * SEC);
    assert!((num(&incoming[0], "/from") - 1.0).abs() < EPS);
    assert!((num(&incoming[0], "/to") - 1.0).abs() < EPS);
}

#[test]
fn an_absent_transition_object_is_silent_too() {
    // An overlap with no `transition_in` at all — only reachable in
    // hand-written JSON — takes the FILE default, which is linear and
    // silent, so the envelope is the same two flat ramps.
    let mut source = pair(json!({ "kind": "cross_dissolve" }));
    source["clips"][1]["transition_in"] = Value::Null;
    let plan = Handle::from_value(&source).plan();
    assert_eq!(ramps_for(&plan, 11).len(), 1);
    assert_eq!(ramps_for(&plan, 12).len(), 1);
}

#[test]
fn a_crossfade_follows_the_constant_power_law_at_every_breakpoint() {
    for curve in ["linear", "ease_in", "ease_out", "ease_in_out"] {
        let plan = Handle::from_value(&crossfading(curve)).plan();
        assert_follows_the_law(&plan, 11, false, curve);
        assert_follows_the_law(&plan, 12, true, curve);
    }
}

#[test]
fn the_summed_power_is_flat_across_the_overlap() {
    // What constant power MEANS: `cos² + sin² = 1` at every instant, so two
    // uncorrelated takes cross over with no dip. Equal-gain ramps would sum
    // to 0.5 at the middle — 3 dB down — which is the failure the law
    // exists to avoid (spec §11, R5-2).
    let plan = Handle::from_value(&crossfading("linear")).plan();
    for step in [0, SEC / 8, SEC / 4, SEC / 2, 3 * SEC / 4, SEC] {
        let p = step as f64 / SEC as f64;
        let power = expected_gain(p, false).powi(2) + expected_gain(p, true).powi(2);
        assert!((power - 1.0).abs() < EPS, "power at +{step} is {power}");
    }
    // ...and the ramps the plan actually carries agree with that law,
    // which the check above measures endpoint by endpoint.
    assert_follows_the_law(&plan, 11, false, "linear");
    assert_follows_the_law(&plan, 12, true, "linear");
}

#[test]
fn the_outgoing_clips_last_breakpoint_is_zero() {
    // `progress_in` is half-open, so an envelope read from the LEFT at the
    // overlap's end finds no transition there and would report gain 1,
    // undoing the whole fade on the last ramp. `crossfade_among` closes the
    // span on `Side::Left`; without that this is 1.0.
    let plan = Handle::from_value(&crossfading("linear")).plan();
    let ramps = ramps_for(&plan, 11);
    let last = ramps.last().expect("the outgoing clip has ramps");
    assert_eq!(
        int(last, "/start") + int(last, "/duration"),
        6 * SEC,
        "the last ramp must end at the clip's end"
    );
    assert!(
        num(last, "/to").abs() < EPS,
        "the outgoing clip ends at {} rather than silence",
        num(last, "/to")
    );
}

#[test]
fn the_incoming_clip_starts_at_silence_and_reaches_full_gain() {
    let plan = Handle::from_value(&crossfading("linear")).plan();
    let ramps = ramps_for(&plan, 12);
    let first = ramps.first().expect("the incoming clip has ramps");
    assert_eq!(int(first, "/start"), 5 * SEC);
    assert!(
        num(first, "/from").abs() < EPS,
        "the incoming clip starts at {} rather than silence",
        num(first, "/from")
    );
    // ...and by the overlap's end it is at 1 and stays there.
    let last = ramps.last().unwrap();
    assert!((num(last, "/to") - 1.0).abs() < EPS);
}

#[test]
fn an_eased_crossfade_moves_the_breakpoints() {
    // The sine law is not linear and neither is an eased progress, so a
    // curve has to change the SHAPE of the envelope and not only its
    // endpoints. A build that sampled the crossfade but eased nothing would
    // produce the same ramp values under all four curves.
    let linear = Handle::from_value(&crossfading("linear")).plan();
    let eased = Handle::from_value(&crossfading("ease_in_out")).plan();
    let a = ramps_for(&linear, 12);
    let b = ramps_for(&eased, 12);
    let differs = a.iter().zip(b.iter()).any(|(x, y)| {
        (num(x, "/from") - num(y, "/from")).abs() > 1e-6
            || (num(x, "/to") - num(y, "/to")).abs() > 1e-6
    }) || a.len() != b.len();
    assert!(differs, "the curve made no difference to the envelope");
}

// ---- precedence ----------------------------------------------------------

#[test]
fn a_muted_incoming_clip_stays_silent_through_the_crossfade() {
    // The term MULTIPLIES, as ducking does, so a zero envelope stays zero.
    let mut source = crossfading("linear");
    source["clips"][1]["audio"] = json!({ "muted": true });
    let plan = Handle::from_value(&source).plan();
    for ramp in ramps_for(&plan, 12) {
        assert!(num(&ramp, "/from").abs() < EPS, "{ramp}");
        assert!(num(&ramp, "/to").abs() < EPS, "{ramp}");
    }
    // ...and the OUTGOING clip still fades out, because the pair's two
    // halves are two voices and neither reads the other's gain.
    let outgoing = ramps_for(&plan, 11);
    assert!(outgoing.last().map(|r| num(r, "/to")).unwrap().abs() < EPS);
}

#[test]
fn a_solo_elsewhere_silences_a_crossfading_pair() {
    let mut source = crossfading("linear");
    source["tracks"] = json!([
        { "id": 2, "name": "Track 1" },
        { "id": 3, "name": "Track 2", "solo": true }
    ]);
    let plan = Handle::from_value(&source).plan();
    for clip in [11, 12] {
        for ramp in ramps_for(&plan, clip) {
            assert!(num(&ramp, "/from").abs() < EPS, "clip {clip}: {ramp}");
            assert!(num(&ramp, "/to").abs() < EPS, "clip {clip}: {ramp}");
        }
    }
}

#[test]
fn a_clip_volume_scales_the_crossfade_rather_than_replacing_it() {
    let mut source = crossfading("linear");
    source["clips"][0]["audio"] = json!({ "volume": 0.5 });
    let plan = Handle::from_value(&source).plan();
    let ramps = ramps_for(&plan, 11);
    // Before the overlap the clip sits at its own volume...
    assert!((num(&ramps[0], "/from") - 0.5).abs() < EPS);
    // ...and the crossfade takes it from there to silence.
    let last = ramps.last().unwrap();
    assert!(num(last, "/to").abs() < EPS);
    // At the middle of the overlap the law says cos(π/4) = √2/2 of 0.5.
    let middle = ramps
        .iter()
        .find(|r| {
            int(r, "/start") <= 5 * SEC + SEC / 2
                && 5 * SEC + SEC / 2 < int(r, "/start") + int(r, "/duration")
        })
        .expect("a ramp covers the middle of the overlap");
    let expected = 0.5 * expected_gain(0.5, false);
    let t = 5 * SEC + SEC / 2;
    let travelled = (t - int(middle, "/start")) as f64 / int(middle, "/duration") as f64;
    let at_t = num(middle, "/from") + (num(middle, "/to") - num(middle, "/from")) * travelled;
    assert!(
        (at_t - expected).abs() < 1e-4,
        "the middle of the overlap reads {at_t} not {expected}"
    );
}

#[test]
fn a_pair_where_only_one_clip_has_audio_still_fades_that_one() {
    // `enabled.audio` off on the incoming clip: its own gain is 0 at every
    // tick, and the outgoing clip's fade is unaffected by the fact that
    // nothing is coming in under it.
    let mut source = crossfading("linear");
    source["clips"][1]["enabled"] = json!({ "video": true, "audio": false });
    let plan = Handle::from_value(&source).plan();
    let outgoing = ramps_for(&plan, 11);
    assert!(outgoing.last().map(|r| num(r, "/to")).unwrap().abs() < EPS);
    assert!((num(&outgoing[0], "/from") - 1.0).abs() < EPS);
}

// ---- nests ---------------------------------------------------------------

/// A nest holding the overlapping pair, shown by one timeline clip.
fn nested_pair(inner_audio: bool, outer: Option<Value>) -> Value {
    json!({
        "version": 7,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": [video_media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            { "id": 20, "track": 2, "start": 0, "duration": 11 * SEC,
              "source": { "kind": "nest", "project": 30 }, "video": {}, "audio": {} },
            { "id": 21, "track": 2, "start": 10 * SEC, "duration": 6 * SEC,
              "source": { "kind": "media", "media": 1, "in": 0 },
              "video": {}, "audio": {},
              "transition_in": outer }
        ],
        "markers": [],
        "next_id": 40,
        "nests": [
            { "id": 30, "name": "Inner", "width": 1920, "height": 1080,
              "tracks": [{ "id": 31, "name": "Inside" }],
              "clips": [
                { "id": 32, "track": 31, "start": 0, "duration": 6 * SEC,
                  "source": { "kind": "media", "media": 1, "in": 0 },
                  "video": {}, "audio": {} },
                { "id": 33, "track": 31, "start": 5 * SEC, "duration": 6 * SEC,
                  "source": { "kind": "media", "media": 1, "in": 5 * SEC },
                  "video": {}, "audio": {},
                  "transition_in": { "kind": "cross_dissolve", "curve": "linear",
                                     "audio": inner_audio } }
              ] }
        ]
    })
}

#[test]
fn a_pair_inside_a_nest_fades_in_the_nests_own_time_base() {
    // The overlap is a fact about the NEST's clips, at the NEST's zero —
    // which here happens to coincide with the timeline's, so the second
    // half of the claim is the fixture below, where the nest clip is
    // offset.
    let plan = Handle::from_value(&nested_pair(true, None)).plan();
    // Read at the overlap's own edges rather than off the ends of the ramp
    // list: a composition audio track carries every segment assigned to it,
    // and here the one holding clip 32 holds the timeline clip after the
    // nest as well.
    assert!(
        gain_approaching(&plan, 32, 6 * SEC).abs() < EPS,
        "the nested outgoing clip did not fade to silence"
    );
    assert!(
        gain_leaving(&plan, 33, 5 * SEC).abs() < EPS,
        "the nested incoming clip did not fade up from silence"
    );

    // With the crossfade off, both clips are at full gain at the very edges
    // the fade would have taken to zero.
    let silent = Handle::from_value(&nested_pair(false, None)).plan();
    assert!((gain_approaching(&silent, 32, 6 * SEC) - 1.0).abs() < EPS);
    assert!((gain_leaving(&silent, 33, 5 * SEC) - 1.0).abs() < EPS);
}

#[test]
fn a_nest_clips_own_transition_fades_everything_inside_it() {
    // And BOTH fades apply where the two overlaps meet: a clip inside an
    // overlap inside a nest that is itself in a transition gets its own
    // term and its container's. That is where the sound parts company with
    // the picture (`audio.rs`'s module doc), and it is deliberate.
    let outer = json!({ "kind": "cross_dissolve", "curve": "linear", "audio": true });
    let plan = Handle::from_value(&nested_pair(true, Some(outer))).plan();

    // The nest clip runs 0…11 s and clip 21 starts at 10 s, so the outer
    // overlap is 10…11 s — which is inside the INNER pair's clip 33 and
    // past the inner overlap.
    assert!(
        gain_approaching(&plan, 33, 11 * SEC).abs() < EPS,
        "the nest's own transition did not fade its contents out: {}",
        gain_approaching(&plan, 33, 11 * SEC)
    );
}

// ---- the breakpoint ceiling ----------------------------------------------

/// Two clips overlapping by `overlap` ticks on one track, crossfading.
fn long_overlap(overlap: i64) -> Value {
    let span = overlap * 3;
    json!({
        "version": 7,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": [json!({
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 10 * span, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        })],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            { "id": 11, "track": 2, "start": 0, "duration": span,
              "source": { "kind": "media", "media": 1, "in": 0 },
              "video": {}, "audio": {} },
            { "id": 12, "track": 2, "start": span - overlap, "duration": span,
              "source": { "kind": "media", "media": 1, "in": span },
              "video": {}, "audio": {},
              "transition_in": { "kind": "cross_dissolve", "curve": "ease_in_out",
                                 "audio": true } }
        ],
        "markers": [],
        "next_id": 13
    })
}

#[test]
fn a_very_long_crossfade_widens_its_step_instead_of_adding_points() {
    // `MAX_ACTION_SAMPLES` is 4096 and `ACTION_SAMPLE` is 1/30 s, so a span
    // longer than 4096 × 1/30 s — about two and a quarter minutes — has to
    // widen its grid. Twenty minutes at the fine grid would be 36,000
    // points per stage; this pins that it is not.
    let overlap = 20 * 60 * SEC;
    let plan = Handle::from_value(&long_overlap(overlap)).plan();
    for clip in [11, 12] {
        let count = ramps_for(&plan, clip).len();
        assert!(
            count <= 4200,
            "clip {clip} produced {count} ramps for a twenty-minute crossfade"
        );
        // ...and it is still sampled finely enough to be a curve rather
        // than a straight line.
        assert!(
            count > 100,
            "clip {clip} produced only {count} ramps — the curve was not sampled"
        );
    }
}

#[test]
fn a_short_crossfade_is_sampled_on_the_fine_grid() {
    // One second at 1/30 s is thirty steps, which coalescing then reduces
    // where the curve is straight — so the count is bounded above, not
    // pinned. What matters is that it is MORE than one: a single ramp would
    // be a straight line across a sine.
    let plan = Handle::from_value(&crossfading("linear")).plan();
    let count = ramps_for(&plan, 12).len();
    assert!(
        (5..=40).contains(&count),
        "a one-second crossfade produced {count} ramps"
    );
}

#[test]
fn the_plan_is_the_same_twice() {
    // The envelope is a pure function of the model, so two plans of one
    // project are byte-identical — which is what lets `Playback` key its
    // rebuild on the plan text.
    let handle = Handle::from_value(&crossfading("ease_in_out"));
    assert_eq!(handle.plan_text(), handle.plan_text());
    // ...and a second handle over the same JSON agrees with the first.
    let twin = Handle::from_value(&crossfading("ease_in_out"));
    assert_eq!(handle.plan_text(), twin.plan_text());
}

#[test]
fn the_transition_object_is_not_in_the_plan() {
    // The plan carries ramps, not a description of what shaped them: the
    // crossfade is already folded in, and a second opinion on the Swift
    // side is exactly what `audio.rs` exists to prevent.
    let plan = Handle::from_value(&crossfading("ease_in_out")).plan();
    let text = serde_json::to_string(&plan).expect("the plan serialises");
    assert!(!text.contains("crossfade"), "{text}");
    assert_eq!(at(&plan, "/timescale"), &json!(SEC));
}
