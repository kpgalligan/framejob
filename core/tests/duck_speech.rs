//! Ducking by speech (format 29, spec §11 AU-110..AU-113, AU-116), through
//! the FFI: `set_media_speech` and its rules, `set_audio`'s one refusal, the
//! gain a speech ducker puts on the rest of the mix (pre-roll, hold, attack,
//! release, merging, the minimum over spans, reversed, ×2, ramped and nested
//! duckers), the plan's `ducks`, a relink over spans, and an extent duck
//! planned exactly as before.
//!
//! The gain is read off the BED's plan ramps — the track a voice ducks — and
//! compared with an oracle written here from the decision's words: each
//! widened span ducks as an extent duck over it would, and the ducker's
//! multiplier is the minimum over its spans. Every ramp endpoint and every
//! ramp's midpoint is checked, so a missed breakpoint (a crossing, an edge)
//! shows as a midpoint off the oracle.

use serde_json::{json, Value};

mod common;
use common::{array, at, int, num, Handle};

const SEC: i64 = 600_000;
const EPS: f64 = 1e-9;
/// The slack for a ramp against the oracle: a crossing lands on a whole
/// tick and a speed map floors, so a curve may sit a tick off — some 1e-5 of
/// gain on these slopes — where a wrong rule is off by tenths.
const TOL: f64 = 1e-4;

/// The duck the speech fixtures use: down to 0.2, 0.1 s attack, 0.2 s
/// release, 0.3 s pre-roll and 0.4 s hold — round numbers so the expected
/// edges read off as tenths of a second.
const ATTACK: i64 = SEC / 10;
const RELEASE: i64 = SEC / 5;
const PRE_ROLL: i64 = 3 * SEC / 10;
const HOLD: i64 = 4 * SEC / 10;

fn duck(mode: &str) -> Value {
    json!({"level": 0.2, "attack": ATTACK, "release": RELEASE, "mode": mode,
           "pre_roll": PRE_ROLL, "hold": HOLD})
}

fn media(id: u32, duration: i64, speech: Option<Value>) -> Value {
    let mut m = json!({"id": id, "path": format!("/fixtures/{id}.m4a"), "kind": "audio",
                       "duration": duration, "has_audio": true});
    if let Some(speech) = speech {
        m["speech"] = speech;
    }
    m
}

/// A voice (clip 10, media 1, track 3) with `voice` merged over its fields,
/// over a 20 s bed (clip 20, media 2, track 4). Media 1 is 20 s long and
/// speaks over `speech`.
fn fixture(speech: Value, voice: Value) -> Value {
    let mut clip = json!({"id": 10, "track": 3, "start": 2 * SEC, "duration": 10 * SEC,
                          "source": {"kind": "media", "media": 1, "in": 0},
                          "audio": {"duck": duck("speech")}});
    if let (Some(clip), Some(fields)) = (clip.as_object_mut(), voice.as_object()) {
        for (key, value) in fields {
            clip.insert(key.clone(), value.clone());
        }
    }
    json!({
        "version": 29,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [media(1, 20 * SEC, Some(speech)), media(2, 60 * SEC, None)],
        "tracks": [{"id": 3, "name": "Voice"}, {"id": 4, "name": "Bed"}],
        "clips": [clip,
                  {"id": 20, "track": 4, "start": 0, "duration": 20 * SEC,
                   "source": {"kind": "media", "media": 2, "in": 0}, "audio": {}}],
        "next_id": 100
    })
}

/// The ramps of the composition audio track carrying clip `clip`.
fn ramps_of(plan: &Value, clip: u32) -> Vec<Value> {
    for track in array(plan, "/audio_tracks") {
        if array(track, "/segments")
            .iter()
            .any(|s| s["clip"] == json!(clip))
        {
            return array(track, "/ramps").clone();
        }
    }
    panic!("no audio track carries clip {clip}: {plan}");
}

/// One duck's extent curve over `[s, e)` at `t` (from the right): 1 → level
/// over the attack from `s`, the level held, back to 1 over the release
/// after `e`, the release starting where the attack got to.
fn extent(s: i64, e: i64, t: i64, level: f64) -> f64 {
    let reached = |elapsed: i64| {
        let u = (elapsed.max(0) as f64 / ATTACK as f64).clamp(0.0, 1.0);
        1.0 + (level - 1.0) * u
    };
    if t < s || t >= e + RELEASE {
        1.0
    } else if t < e {
        reached(t - s)
    } else {
        let held = reached(e - s);
        held + (1.0 - held) * ((t - e) as f64 / RELEASE as f64)
    }
}

/// The oracle: the minimum over `spans` (project time, already widened).
fn oracle(spans: &[(i64, i64)], t: i64) -> f64 {
    spans
        .iter()
        .map(|&(s, e)| extent(s, e, t, 0.2))
        .fold(1.0, f64::min)
}

/// Every endpoint and midpoint of `ramps` against the oracle, and the gain
/// they give every 1/100 s across their whole extent — so a ramp that runs
/// flat over a span it should have ducked cannot pass on its ends alone.
fn assert_follows(ramps: &[Value], spans: &[(i64, i64)]) {
    let end = ramps
        .last()
        .map_or(0, |r| int(r, "/start") + int(r, "/duration"));
    let mut t = ramps.first().map_or(0, |r| int(r, "/start"));
    while t < end {
        let (got, want) = (gain(ramps, t), oracle(spans, t));
        assert!((got - want).abs() < TOL, "gain at {t}: {got} vs {want}");
        t += SEC / 100;
    }
    for ramp in ramps {
        let (start, duration) = (int(ramp, "/start"), int(ramp, "/duration"));
        let (from, to) = (num(ramp, "/from"), num(ramp, "/to"));
        assert!(
            (from - oracle(spans, start)).abs() < TOL,
            "from at {start}: {ramp}"
        );
        let end = start + duration;
        let left = oracle(spans, end - 1) + (oracle(spans, end - 1) - oracle(spans, end - 2));
        assert!((to - left).abs() < TOL, "to at {end}: {ramp} vs {left}");
        let mid = start + duration / 2;
        let between = from + (to - from) * ((mid - start) as f64 / duration as f64);
        assert!(
            (between - oracle(spans, mid)).abs() < TOL,
            "midpoint {mid} of {ramp}: {between} vs {}",
            oracle(spans, mid)
        );
    }
}

/// The gain the ramps give at `t`, from the right.
fn gain(ramps: &[Value], t: i64) -> f64 {
    for ramp in ramps {
        let (start, duration) = (int(ramp, "/start"), int(ramp, "/duration"));
        if start <= t && t < start + duration {
            let (from, to) = (num(ramp, "/from"), num(ramp, "/to"));
            return from + (to - from) * ((t - start) as f64 / duration as f64);
        }
    }
    panic!("no ramp covers {t}");
}

// ---- the gain ------------------------------------------------------------

#[test]
fn pre_roll_hold_attack_and_release_fall_where_the_spans_say() {
    // Source speech 1–3 s and 6–7 s; the voice starts at 2 s with `in` 0, so
    // it speaks 3–5 s and 8–9 s, widened to 2.7–5.4 s and 7.7–9.4 s.
    let handle = Handle::from_value(&fixture(
        json!([[SEC, 3 * SEC], [6 * SEC, 7 * SEC]]),
        json!({}),
    ));
    let bed = ramps_of(&handle.plan(), 20);
    let spans = [
        (27 * SEC / 10, 54 * SEC / 10),
        (77 * SEC / 10, 94 * SEC / 10),
    ];
    assert_follows(&bed, &spans);
    let tenth = SEC / 10;
    assert_eq!(gain(&bed, 27 * tenth - 1), 1.0, "before the pre-roll");
    assert_eq!(
        gain(&bed, 27 * tenth),
        1.0,
        "the attack starts at the pre-roll"
    );
    assert!(
        (gain(&bed, 28 * tenth) - 0.2).abs() < EPS,
        "down after the attack"
    );
    assert!(
        (gain(&bed, 54 * tenth - 1) - 0.2).abs() < 1e-5,
        "held through the hold"
    );
    assert!(
        (gain(&bed, 55 * tenth) - 0.6).abs() < 1e-6,
        "half-way up the release"
    );
    assert_eq!(gain(&bed, 56 * tenth), 1.0, "back after the release");
    assert_eq!(gain(&bed, 7 * SEC), 1.0, "up between the words");
    assert!(
        (gain(&bed, 9 * SEC) - 0.2).abs() < EPS,
        "down in the second span"
    );
}

#[test]
fn touching_and_overlapping_spans_merge_into_one_duck() {
    // 1–2 s and 2–3 s touch, 3.5–4 s is within pre-roll + hold of them: all
    // three merge into one span, 2.7 s (3 − 0.3) to 6.4 s (6 + 0.4).
    let speech = json!([[SEC, 2 * SEC], [2 * SEC, 3 * SEC], [35 * SEC / 10, 4 * SEC]]);
    let handle = Handle::from_value(&fixture(speech, json!({})));
    let bed = ramps_of(&handle.plan(), 20);
    assert_follows(&bed, &[(27 * SEC / 10, 64 * SEC / 10)]);
    for t in [3 * SEC, 5 * SEC, 6 * SEC] {
        assert!((gain(&bed, t) - 0.2).abs() < EPS, "held at {t}");
    }
}

#[test]
fn a_release_meeting_the_next_attack_takes_the_minimum() {
    // Speech 1–2 s and 2.75–3 s: widened to 2.7–4.4 s and 4.45–5.4 s, which
    // do not touch, so the release of the first (4.4–4.6 s) runs into the
    // attack of the second (4.45–4.55 s). The minimum, never the product.
    let speech = json!([[SEC, 2 * SEC], [275 * SEC / 100, 3 * SEC]]);
    let handle = Handle::from_value(&fixture(speech, json!({})));
    let bed = ramps_of(&handle.plan(), 20);
    let spans = [
        (27 * SEC / 10, 44 * SEC / 10),
        (445 * SEC / 100, 54 * SEC / 10),
    ];
    assert_follows(&bed, &spans);
    let t = 45 * SEC / 10;
    let product: f64 = spans.iter().map(|&(s, e)| extent(s, e, t, 0.2)).product();
    assert!((gain(&bed, t) - oracle(&spans, t)).abs() < 1e-6);
    assert!(
        gain(&bed, t) > product + 0.1,
        "the two curves must not multiply"
    );
    // Continuous at the crossing: no ramp ends at one value and the next
    // starts at another.
    for pair in bed.windows(2) {
        assert!((num(&pair[0], "/to") - num(&pair[1], "/from")).abs() < EPS);
    }
}

#[test]
fn a_reversed_ducker_reads_its_spans_reflected() {
    // Media 20 s, speech 1–3 s forward = 17–19 s of the reversed stream. A
    // reversed clip from `in` 15 s plays it at clip time 2–4 s, project 4–6 s.
    let voice = json!({"source": {"kind": "media", "media": 1, "in": 15 * SEC, "reversed": true},
                       "duration": 5 * SEC});
    let handle = Handle::from_value(&fixture(json!([[SEC, 3 * SEC]]), voice));
    let bed = ramps_of(&handle.plan(), 20);
    assert_follows(&bed, &[(37 * SEC / 10, 64 * SEC / 10)]);
}

#[test]
fn a_double_speed_ducker_reads_its_spans_at_its_rate() {
    // ×2 from `in` 0: source 2–4 s plays at clip time 1–2 s, project 3–4 s.
    let voice = json!({"speed": 2.0, "duration": 5 * SEC});
    let handle = Handle::from_value(&fixture(json!([[2 * SEC, 4 * SEC]]), voice));
    let bed = ramps_of(&handle.plan(), 20);
    assert_follows(&bed, &[(27 * SEC / 10, 44 * SEC / 10)]);
}

#[test]
fn a_ramped_ducker_reads_its_spans_through_the_speed_map() {
    // Rate 1 → 2 linearly over the first 2 s, then held at 2: S(2 s) = 3 s,
    // so source 4–5 s plays at clip time 2.5–3 s, project 4.5–5 s.
    let voice = json!({"duration": 5 * SEC,
                       "actions": [{"id": 11, "start": 0, "duration": 2 * SEC,
                                    "curve": "linear", "end": {"speed": 2.0}}]});
    let handle = Handle::from_value(&fixture(json!([[4 * SEC, 5 * SEC]]), voice));
    let bed = ramps_of(&handle.plan(), 20);
    assert_follows(&bed, &[(42 * SEC / 10, 54 * SEC / 10)]);
}

#[test]
fn a_nested_ducker_ducks_where_its_nest_clip_plays_it() {
    // The voice inside nest 30 at nest time 0, shown by nest clip 31 at 4 s
    // for 3 s: speech 1–3 s and 5–6 s of the media is nest time 1–3 s and
    // 5–6 s, project 5–7 s and 9–10 s — the second past the nest clip's end
    // (7 s), so only the first plays: 5 s to 7 s, widened to 4.7–7.4 s.
    let mut value = fixture(json!([[SEC, 3 * SEC], [5 * SEC, 6 * SEC]]), json!({}));
    let mut voice = value["clips"][0].clone();
    voice["track"] = json!(32);
    voice["start"] = json!(0);
    value["clips"][0] = json!({"id": 31, "track": 3, "start": 4 * SEC, "duration": 3 * SEC,
                               "source": {"kind": "nest", "project": 30}, "audio": {}});
    value["nests"] = json!([{"id": 30, "name": "Voice", "width": 1920, "height": 1080,
                             "tracks": [{"id": 32, "name": "V"}], "clips": [voice]}]);
    let handle = Handle::from_value(&value);
    let bed = ramps_of(&handle.plan(), 20);
    assert_follows(&bed, &[(47 * SEC / 10, 74 * SEC / 10)]);
}

#[test]
fn a_speech_duck_with_no_spans_or_no_media_ducks_nowhere() {
    let mut value = fixture(json!([]), json!({}));
    let handle = Handle::from_value(&value);
    assert_follows(&ramps_of(&handle.plan(), 20), &[]);
    if let Some(m) = value["media"][0].as_object_mut() {
        m.remove("speech");
    }
    let handle = Handle::from_value(&value);
    assert_follows(&ramps_of(&handle.plan(), 20), &[]);
    assert_eq!(array(&handle.plan(), "/ducks")[0]["ramps"], json!([]));
}

// ---- the extent mode, unchanged -------------------------------------------

#[test]
fn an_extent_duck_plans_exactly_as_before() {
    // The voice at 2–12 s with the default duck: the bed's ramps are the
    // pinned text the extent path wrote before format 29, and the plan has
    // no `ducks`.
    let voice = json!({"audio": {"duck": {"level": 0.2, "attack": 300000, "release": 600000}}});
    let handle = Handle::from_value(&fixture(json!([[SEC, 3 * SEC]]), voice));
    let plan = handle.plan();
    assert!(plan.get("ducks").is_none(), "{plan}");
    let pinned = json!([
        {"start": 0, "duration": 1200000, "from": 1.0, "to": 1.0},
        {"start": 1200000, "duration": 300000, "from": 1.0, "to": 0.2},
        {"start": 1500000, "duration": 5700000, "from": 0.2, "to": 0.2},
        {"start": 7200000, "duration": 600000, "from": 0.2, "to": 1.0},
        {"start": 7800000, "duration": 4200000, "from": 1.0, "to": 1.0}
    ]);
    assert_eq!(json!(ramps_of(&plan, 20)), pinned);
    assert!(!handle.plan_text().contains("\"ducks\""));
}

// ---- the plan's ducks ----------------------------------------------------

#[test]
fn the_plan_carries_a_speech_ducker_s_own_multiplier() {
    let handle = Handle::from_value(&fixture(json!([[SEC, 3 * SEC]]), json!({})));
    let plan = handle.plan();
    let ducks = array(&plan, "/ducks");
    assert_eq!(ducks.len(), 1);
    assert_eq!(ducks[0]["clip"], json!(10));
    let ramps = array(&ducks[0], "/ramps");
    let spans = [(27 * SEC / 10, 54 * SEC / 10)];
    assert_follows(ramps, &spans);
    assert_eq!(int(&ramps[0], "/start"), 27 * SEC / 10);
    let last = ramps.last().expect("a ramp");
    assert_eq!(
        int(last, "/start") + int(last, "/duration"),
        54 * SEC / 10 + RELEASE
    );
}

// ---- the ops -------------------------------------------------------------

fn silent_fixture() -> Value {
    let mut value = fixture(json!([[SEC, 3 * SEC]]), json!({"audio": {}}));
    if let Some(m) = value["media"][0].as_object_mut() {
        m.remove("speech");
    }
    value
}

#[test]
fn set_audio_refuses_a_patch_turning_speech_on_without_spans() {
    let handle = Handle::from_value(&silent_fixture());
    let speech = json!({"op": "set_audio", "clips": [10], "patch": {"duck": {"mode": "speech"}}});
    handle.refuses_with(
        &speech,
        "audio.duck.mode speech needs the clip's media to carry speech spans (set_media_speech)",
    );
    // With spans on the media the same patch applies.
    let spanned = handle.apply(&json!({"op": "set_media_speech", "media": 1, "spans": [[0, SEC]]}));
    let applied = spanned.apply(&speech);
    assert_eq!(
        at(&applied.value(), "/clips/0/audio/duck/mode"),
        &json!("speech")
    );
    // The extent mode and every other key are not refused.
    handle.apply(&json!({"op": "set_audio", "clips": [10],
                         "patch": {"duck": {"level": 0.3, "pre_roll": 60000}}}));
}

#[test]
fn a_pasted_spanless_speech_duck_keeps_every_other_audio_edit() {
    // Clip 10's speech duck pasted onto the bed, whose media has no spans:
    // the paste lands, the bed ducks nowhere, and a volume edit applies.
    let handle = Handle::from_value(&fixture(json!([[SEC, 3 * SEC]]), json!({})));
    let voice = array(&handle.value(), "/clips")[0].clone();
    let pasted = handle.apply(&json!({"op": "paste_attributes", "clips": [20],
        "payload": {"clips": [voice], "media": []}, "groups": ["audio"]}));
    assert_eq!(
        at(&pasted.value(), "/clips/1/audio/duck/mode"),
        &json!("speech")
    );
    let louder = pasted.apply(&json!({"op": "set_audio", "clips": [20], "patch": {"volume": 0.5}}));
    assert_eq!(num(&louder.value(), "/clips/1/audio/volume"), 0.5);
}

#[test]
fn set_media_speech_stores_and_refuses_in_its_own_sentences() {
    let handle = Handle::from_value(&silent_fixture());
    let set = |spans: Value| json!({"op": "set_media_speech", "media": 1, "spans": spans});
    let stored = handle.apply(&set(json!([[SEC, 2 * SEC], [2 * SEC, 3 * SEC]])));
    assert_eq!(
        at(&stored.value(), "/media/0/speech"),
        &json!([[SEC, 2 * SEC], [2 * SEC, 3 * SEC]])
    );
    stored.refuses(&set(json!([[SEC, 2 * SEC], [2 * SEC, 3 * SEC]])));
    let empty = handle.apply(&set(json!([])));
    assert_eq!(at(&empty.value(), "/media/0/speech"), &json!([]));
    handle.refuses_with(
        &set(json!([[-1, SEC]])),
        "media 1 speech span 0 starts at -1, before 0",
    );
    handle.refuses_with(
        &set(json!([[SEC, SEC]])),
        "media 1 speech span 0 ends at 600000, not after its start 600000",
    );
    handle.refuses_with(
        &set(json!([[SEC, 21 * SEC]])),
        "media 1 speech span 0 ends at 12600000, past the media's duration 12000000",
    );
    handle.refuses_with(
        &set(json!([[2 * SEC, 3 * SEC], [SEC, 4 * SEC]])),
        "media 1 speech span 1 starts at 600000, before span 0 ends at 1800000: speech spans \
         are sorted and do not overlap",
    );
    let many: Vec<Value> = (0..100_001i64).map(|i| json!([i * 2, i * 2 + 1])).collect();
    handle.refuses_with(
        &set(json!(many)),
        "media 1 carries 100001 speech spans, more than 100000",
    );
    assert_eq!(
        handle.errors(&json!({"op": "set_media_speech", "media": 9, "spans": []})),
        "no media with id 9"
    );
    let mut mute = silent_fixture();
    mute["media"][0]["has_audio"] = json!(false);
    Handle::from_value(&mute).refuses_with(
        &set(json!([[0, SEC]])),
        "media 1 has no audio, so it has no speech to duck by",
    );
}

#[test]
fn a_file_with_bad_spans_is_refused_by_validate() {
    let value = fixture(json!([[3 * SEC, 2 * SEC]]), json!({}));
    let message = Handle::try_from_value(&value).expect_err("bad spans");
    assert!(
        message.contains("media 1 speech span 0 ends at 1200000, not after its start 1800000"),
        "{message}"
    );
}

#[test]
fn a_relink_clips_spans_to_a_shorter_file_and_drops_them_without_audio() {
    let handle = Handle::from_value(&fixture(
        json!([[SEC, 3 * SEC], [8 * SEC, 9 * SEC]]),
        json!({}),
    ));
    let probe = |duration: i64, audio: bool| {
        json!({"op": "relink_media", "media": 1, "path": "/fixtures/new.m4a",
               "probe": {"kind": "audio", "duration": duration, "has_audio": audio}})
    };
    let shorter = handle.apply(&probe(2 * SEC, true));
    assert_eq!(
        at(&shorter.value(), "/media/0/speech"),
        &json!([[SEC, 2 * SEC]])
    );
    let silent = handle.apply(&probe(20 * SEC, false));
    assert!(silent.value()["media"][0].get("speech").is_none());
    let before = handle.apply(&probe(SEC, true));
    assert!(before.value()["media"][0].get("speech").is_none());
}

#[test]
fn pre_roll_and_hold_on_an_extent_duck_survive_a_save() {
    let handle = Handle::from_value(&silent_fixture());
    let set = handle.apply(&json!({"op": "set_audio", "clips": [10],
        "patch": {"duck": {"pre_roll": 120000, "hold": 0}}}));
    let reopened = Handle::from_json(&set.to_json());
    let duck = at(&reopened.value(), "/clips/0/audio/duck").clone();
    assert_eq!(
        duck["mode"],
        Value::Null,
        "extent is the default and not written"
    );
    assert_eq!(duck["pre_roll"], json!(120000));
    assert_eq!(duck["hold"], json!(0));
}
