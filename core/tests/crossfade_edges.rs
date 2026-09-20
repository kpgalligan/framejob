//! The crossfade's edges, through the FFI — the rows road map 5's E1
//! reader review (§12) added, in a file of their own because
//! `crossfade.rs` is over the size cap and takes nothing on.
//!
//! §3e's last bullet promises that "mute, solo, ducking and volume keep
//! their precedence: the term multiplies, as ducking does". `crossfade.rs`
//! has a row for mute, one for solo and one for volume, and none for a
//! DUCKER — the one term of the envelope that comes from another track
//! entirely (`audio_duck.rs`), applied in `gain_at` AFTER the voice's own
//! gain rather than inside it. So the only factor the promise names that
//! is computed somewhere else is the one nothing measured.
//!
//! The second row is the shape §3e never draws: a MIDDLE clip with an
//! overlap at BOTH ends, each exactly half of it — the most the overlap
//! rule allows — so the two overlaps ABUT at one tick. Every other row in
//! the suite has one transition per clip; here one clip is the INCOMING
//! half of one and the OUTGOING half of the other, and it has to go up
//! over the first and down over the second without the two readings of the
//! seam disagreeing.
//!
//! What the seam row does NOT prove, measured: disabling
//! `crossfade_among`'s `Side::Left` closure leaves it passing, because a
//! `None` there reads as gain 1 and 1 is the right answer at that tick
//! anyway. The closure's own guard is `crossfade.rs`'s
//! `the_outgoing_clips_last_breakpoint_is_zero`, where the right answer is
//! 0; this row is about the two halves, not about the closure.

use serde_json::{json, Value};

mod common;
use common::{array, int, num, Handle};

const SEC: i64 = 600_000;

/// Comparison slack, `crossfade.rs`'s: the expectations are `cos` and
/// `sin` rather than exactly representable numbers.
const EPS: f64 = 1e-9;

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// `crossfade.rs`'s pair — 0…6 s and 5…11 s, a one-second linear
/// crossfade — with a DUCKING clip on a second track covering all of it.
///
/// A step duck (no attack, no release) so the expected multiplier is one
/// number across the whole overlap and the row is about precedence rather
/// than about the duck's own curve, which `audio_tests.rs` owns.
fn ducked_pair() -> Value {
    json!({
        "version": 7,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": [video_media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }, { "id": 3, "name": "Voice" }],
        "clips": [
            { "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
              "source": { "kind": "media", "media": 1, "in": 0 },
              "video": {}, "audio": {} },
            { "id": 12, "track": 2, "start": 5 * SEC, "duration": 6 * SEC,
              "source": { "kind": "media", "media": 1, "in": 5 * SEC },
              "video": {}, "audio": {},
              "transition_in": { "kind": "cross_dissolve", "curve": "linear",
                                 "audio": true } },
            { "id": 13, "track": 3, "start": 0, "duration": 11 * SEC,
              "source": { "kind": "media", "media": 1, "in": 0 }, "video": {},
              "audio": { "duck": { "level": 0.25, "attack": 0, "release": 0,
                                   "targets": [] } } }
        ],
        "markers": [],
        "next_id": 14
    })
}

/// A middle clip with an overlap at BOTH ends, each exactly half of it —
/// the most the overlap rule allows — so the two abut at 6 s.
///
/// Clip 11 is 0…6 s, clip 12 is 4…8 s (four seconds, so two seconds is its
/// half), clip 13 is 6…12 s. Both transitions crossfade, linearly, so the
/// expectation is `cos` and `sin` of the raw fraction.
fn middle_clip() -> Value {
    let crossfade = json!({ "kind": "cross_dissolve", "curve": "linear", "audio": true });
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
            { "id": 12, "track": 2, "start": 4 * SEC, "duration": 4 * SEC,
              "source": { "kind": "media", "media": 1, "in": 5 * SEC },
              "video": {}, "audio": {}, "transition_in": crossfade },
            { "id": 13, "track": 2, "start": 6 * SEC, "duration": 6 * SEC,
              "source": { "kind": "media", "media": 1, "in": 10 * SEC },
              "video": {}, "audio": {}, "transition_in": crossfade }
        ],
        "markers": [],
        "next_id": 14
    })
}

/// `crossfade.rs`'s pair with a FADE OUT on the outgoing clip as long as
/// the overlap, so the two shapes cover exactly the same span.
fn faded_pair() -> Value {
    let mut project = ducked_pair();
    project["clips"] = json!([
        { "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
          "source": { "kind": "media", "media": 1, "in": 0 },
          "video": {}, "audio": { "fade_out": SEC } },
        { "id": 12, "track": 2, "start": 5 * SEC, "duration": 6 * SEC,
          "source": { "kind": "media", "media": 1, "in": 5 * SEC },
          "video": {}, "audio": {},
          "transition_in": { "kind": "cross_dissolve", "curve": "linear",
                             "audio": true } }
    ]);
    project
}

/// Every ramp of the composition audio track that carries `clip`.
///
/// `crossfade.rs`'s helper, copied rather than moved to `tests/common/`:
/// it reads the plan's shape and belongs beside the tests that read plans,
/// where `common` is the pointer dance and the ids.
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
/// ends exactly there.
fn gain_approaching(plan: &Value, clip: i64, t: i64) -> f64 {
    ramps_for(plan, clip)
        .iter()
        .find(|r| int(r, "/start") + int(r, "/duration") == t)
        .map(|r| num(r, "/to"))
        .unwrap_or_else(|| panic!("no ramp ends at {t} on the track carrying clip {clip}"))
}

/// The gain at `t` approached from the RIGHT — the `from` of the ramp that
/// starts exactly there.
fn gain_leaving(plan: &Value, clip: i64, t: i64) -> f64 {
    ramps_for(plan, clip)
        .iter()
        .find(|r| int(r, "/start") == t)
        .map(|r| num(r, "/from"))
        .unwrap_or_else(|| panic!("no ramp starts at {t} on the track carrying clip {clip}"))
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

fn close(got: f64, want: f64, what: &str) {
    assert!((got - want).abs() < EPS, "{what}: got {got}, want {want}");
}

// ---- the ducker keeps its precedence -------------------------------------

#[test]
fn a_ducker_on_another_track_multiplies_the_crossfade_rather_than_replacing_it() {
    // §3e: "mute, solo, ducking and volume keep their precedence: the term
    // multiplies, as ducking does." Ducking is the only one of the four
    // computed OUTSIDE the voice — `gain_at` applies it after
    // `voice_gain` — so it is the only one where "multiplies" could be
    // wrong without any of `crossfade.rs`'s rows noticing.
    let plan = Handle::from_value(&ducked_pair()).plan();
    let level = 0.25;
    // Fifths rather than quarters: a quarter of a second is 150 000 ticks
    // and the envelope is sampled on the 1/30 s grid, so 5.25 s is not a
    // breakpoint and 5.2 s is.
    for step in [0, 1, 2, 3, 4, 5] {
        let p = f64::from(step) / 5.0;
        let t = 5 * SEC + (SEC / 5) * i64::from(step);
        // At p = 1 the outgoing clip's last tick is read from the LEFT and
        // the incoming clip's from the RIGHT; everywhere else both ramps
        // meet at the same value, so `leaving` is the one to ask.
        let outgoing = if step == 5 {
            gain_approaching(&plan, 11, t)
        } else {
            gain_leaving(&plan, 11, t)
        };
        let incoming = if step == 5 {
            gain_approaching(&plan, 12, t)
        } else {
            gain_leaving(&plan, 12, t)
        };
        close(
            outgoing,
            level * expected_gain(p, false),
            &format!("outgoing at p = {p}"),
        );
        close(
            incoming,
            level * expected_gain(p, true),
            &format!("incoming at p = {p}"),
        );
    }
}

#[test]
fn the_ducked_pair_still_sums_to_the_ducked_level() {
    // The whole point of constant power: `cos² + sin² = 1`, so the ducked
    // pair holds at exactly the duck's own level across the overlap rather
    // than dipping under it.
    let plan = Handle::from_value(&ducked_pair()).plan();
    for step in 1..5 {
        let t = 5 * SEC + (SEC / 5) * i64::from(step);
        let a = gain_leaving(&plan, 11, t);
        let b = gain_leaving(&plan, 12, t);
        close(
            (a * a + b * b).sqrt(),
            0.25,
            &format!("summed power at t = {t}"),
        );
    }
}

// ---- an overlap at both ends ---------------------------------------------

#[test]
fn a_middle_clips_two_overlaps_meet_at_full_gain() {
    // The two overlaps abut at 6 s. Approached from the LEFT the middle
    // clip is the INCOMING one of the first transition at p = 1;
    // approached from the RIGHT it is the OUTGOING one of the second at
    // p = 0. Both are 1, and they have to be the same 1 or the envelope
    // steps at the seam — a click between two transitions that were each
    // measured as correct on their own.
    let plan = Handle::from_value(&middle_clip()).plan();
    close(
        gain_approaching(&plan, 12, 6 * SEC),
        1.0,
        "middle from the left",
    );
    close(
        gain_leaving(&plan, 12, 6 * SEC),
        1.0,
        "middle from the right",
    );
}

#[test]
fn a_middle_clip_fades_in_over_one_overlap_and_out_over_the_other() {
    // Both halves, at the quarter points of each overlap, so a build that
    // read one overlap for both ends would have to get `cos` and `sin`
    // right at four places by accident.
    let plan = Handle::from_value(&middle_clip()).plan();
    for step in 1..4 {
        let p = f64::from(step) / 4.0;
        let rising = 4 * SEC + (SEC / 2) * i64::from(step);
        close(
            gain_leaving(&plan, 12, rising),
            expected_gain(p, true),
            &format!("middle rising at p = {p}"),
        );
        let falling = 6 * SEC + (SEC / 2) * i64::from(step);
        close(
            gain_leaving(&plan, 12, falling),
            expected_gain(p, false),
            &format!("middle falling at p = {p}"),
        );
    }
}

#[test]
fn the_middle_clips_neighbours_still_follow_the_law_around_it() {
    // Clip 11 goes out over the first overlap and clip 13 comes in over
    // the second; the A/B assignment puts both on the SAME composition
    // track, one after the other, so this also asserts that the two
    // crossfades tile that track without a gap.
    let plan = Handle::from_value(&middle_clip()).plan();
    for step in 1..4 {
        let p = f64::from(step) / 4.0;
        close(
            gain_leaving(&plan, 11, 4 * SEC + (SEC / 2) * i64::from(step)),
            expected_gain(p, false),
            &format!("clip 11 leaving at p = {p}"),
        );
        close(
            gain_leaving(&plan, 13, 6 * SEC + (SEC / 2) * i64::from(step)),
            expected_gain(p, true),
            &format!("clip 13 arriving at p = {p}"),
        );
    }
}

// ---- a fade and a crossfade over the same span ---------------------------

#[test]
fn a_fade_out_as_long_as_the_overlap_multiplies_the_crossfade() {
    // `audio.rs` says a fade and a crossfade both apply — "the honest
    // reading of both are in effect here" — and this is the one shape
    // where that is visible rather than arguable: the linear fade and the
    // cosine cover exactly the same second, so the product is neither of
    // them and the clip reaches zero from a steeper curve than either.
    let plan = Handle::from_value(&faded_pair()).plan();
    for step in 1..5 {
        let p = f64::from(step) / 5.0;
        let t = 5 * SEC + (SEC / 5) * i64::from(step);
        close(
            gain_leaving(&plan, 11, t),
            (1.0 - p) * expected_gain(p, false),
            &format!("faded outgoing at p = {p}"),
        );
    }
    // …and the pair no longer holds its power, which is what a person is
    // choosing when they leave a fade on a clip they then put in a
    // transition.
    let a = gain_leaving(&plan, 11, 5 * SEC + SEC / 2);
    let b = gain_leaving(&plan, 12, 5 * SEC + SEC / 2);
    assert!(
        (a * a + b * b).sqrt() < 0.9,
        "the faded pair summed to {}, which is not a dip",
        (a * a + b * b).sqrt()
    );
}
