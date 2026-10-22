//! Black-box tests for a PQ file's peak on its media (spec §11 HD-12): the
//! `set_media_color` op's `peak`, `media.color.pq` through `add_media`, a
//! file, a LUT's removal and a paste, and the `peak` the recipe and the plan
//! publish in `input`; and a PQ still's (HD-20 (b)) — all through the C FFI,
//! as `ReelCore.swift` drives it.
//!
//! The oracle for every sentence is the sentence itself, written out here.

mod common;

use serde_json::{json, Value};

use common::{array, at, Handle, Outcome};

/// A PQ video whose import read MaxCLL 4,000; a PQ video whose import read
/// nothing; an SDR video; an audio file; a LUT; one track and one clip of the
/// first video.
const PQ: u32 = 1;
const PLAIN: u32 = 2;
const SDR: u32 = 3;
const AUDIO: u32 = 4;
const LUT: u32 = 5;
const TRACK: u32 = 6;
const CLIP: u32 = 7;

fn video(id: u32, color: Value) -> Value {
    let mut row = json!({"id": id, "path": format!("/fixtures/m{id}.mov"), "kind": "video",
        "duration": 600_000, "width": 1024, "height": 128, "fps": [30, 1],
        "has_video": true});
    if !color.is_null() {
        row["color"] = color;
    }
    row
}

fn project() -> Value {
    json!({
        "version": 22,
        "canvas": {"width": 1024, "height": 128, "fps": [30, 1]},
        "media": [video(PQ, json!({"pq": {"file": 4000, "from": "max_cll"}})),
                  video(PLAIN, json!({"pq": {}})),
                  video(SDR, Value::Null),
                  {"id": AUDIO, "path": "/fixtures/a.wav", "kind": "audio",
                   "duration": 600_000, "has_audio": true},
                  {"id": LUT, "path": "/fixtures/look.cube", "kind": "lut"}],
        "tracks": [{"id": TRACK, "name": "Track 1"}],
        "clips": [{"id": CLIP, "track": TRACK, "start": 0, "duration": 600_000,
                   "source": {"kind": "media", "media": PQ, "in": 0}}],
        "next_id": 20
    })
}

fn handle() -> Handle {
    Handle::from_value(&project())
}

fn set(media: u32, color: Value) -> Value {
    json!({"op": "set_media_color", "media": media, "color": color})
}

fn color_of(h: &Handle, media: u32) -> Value {
    array(&h.value(), "/media")
        .iter()
        .find(|m| m["id"] == json!(media))
        .map(|m| m.get("color").cloned().unwrap_or(Value::Null))
        .expect("the media")
}

fn input(h: &Handle) -> Value {
    array(&h.recipe(300_000), "/layers")
        .iter()
        .find(|l| l["clip"] == json!(CLIP))
        .map(|l| l["input"].clone())
        .expect("the clip's layer")
}

// ---- the op ----------------------------------------------------------------

#[test]
fn a_peak_is_the_override_and_import_s_reading_survives_it() {
    let h = handle();
    let set_to = h.apply(&set(PQ, json!({"peak": 1000})));
    assert_eq!(
        color_of(&set_to, PQ),
        json!({"pq": {"file": 4000, "from": "max_cll", "peak": 1000}})
    );
    let other = set_to.apply(&set(PQ, json!({"peak": 600})));
    assert_eq!(
        color_of(&other, PQ),
        json!({"pq": {"file": 4000, "from": "max_cll", "peak": 600}})
    );
    // The same peak again changes nothing.
    assert!(matches!(
        set_to.try_apply(&set(PQ, json!({"peak": 1000}))),
        Ok(Outcome::Identity)
    ));
    // A peak on a PQ file that read nothing.
    let plain = h.apply(&set(PLAIN, json!({"peak": 2000})));
    assert_eq!(color_of(&plain, PLAIN), json!({"pq": {"peak": 2000}}));
    for bound in [1, 10_000] {
        let edge = h.apply(&set(PQ, json!({"peak": bound})));
        assert_eq!(color_of(&edge, PQ)["pq"]["peak"], json!(bound));
    }
}

#[test]
fn colour_replaces_camera_log_and_the_override_together() {
    let h = handle().apply(&set(PQ, json!({"peak": 1000})));
    // A Camera Log alone drops the override and keeps the reading.
    let logged = h.apply(&set(PQ, json!({"lut": LUT})));
    assert_eq!(
        color_of(&logged, PQ),
        json!({"lut": LUT, "pq": {"file": 4000, "from": "max_cll"}})
    );
    // Both at once.
    let both = h.apply(&set(PQ, json!({"log": "slog3", "peak": 2000})));
    assert_eq!(
        color_of(&both, PQ),
        json!({"log": "slog3", "gamut": "s_gamut3_cine",
               "pq": {"file": 4000, "from": "max_cll", "peak": 2000}})
    );
    // The peak alone drops the Camera Log.
    let peak_only = both.apply(&set(PQ, json!({"peak": 600})));
    assert_eq!(
        color_of(&peak_only, PQ),
        json!({"pq": {"file": 4000, "from": "max_cll", "peak": 600}})
    );
}

#[test]
fn null_clears_both_and_keeps_the_reading() {
    let h = handle().apply(&set(PQ, json!({"log": "vlog", "peak": 1000})));
    let cleared = h.apply(&set(PQ, Value::Null));
    assert_eq!(
        color_of(&cleared, PQ),
        json!({"pq": {"file": 4000, "from": "max_cll"}})
    );
    // Nothing left to clear: an identity, and the reading stays.
    assert!(matches!(
        cleared.try_apply(&set(PQ, Value::Null)),
        Ok(Outcome::Identity)
    ));
    assert!(matches!(
        handle().try_apply(&set(PLAIN, Value::Null)),
        Ok(Outcome::Identity)
    ));
    // A media with no reading clears to no colour at all.
    let sdr = handle()
        .apply(&set(SDR, json!({"log": "slog3"})))
        .apply(&set(SDR, Value::Null));
    assert_eq!(color_of(&sdr, SDR), Value::Null);
}

#[test]
fn every_new_refusal_is_its_own_sentence() {
    let h = handle();
    let cases = [
        (
            SDR,
            json!({"peak": 1000}),
            "media 3 is not a PQ file; only a PQ file takes a peak",
        ),
        (
            AUDIO,
            json!({"peak": 1000}),
            "media 4 is not a PQ file; only a PQ file takes a peak",
        ),
        (
            PQ,
            json!({"peak": 0}),
            "color.peak must be 1–10000 cd/m², not 0",
        ),
        (
            PQ,
            json!({"peak": 10001}),
            "color.peak must be 1–10000 cd/m², not 10001",
        ),
        (
            PQ,
            json!({"peak": -5}),
            "color.peak must be 1–10000 cd/m², not -5",
        ),
        (
            PQ,
            json!({"pq": {"file": 1}}),
            "color.pq is read from the file at import, not set",
        ),
        (
            PQ,
            json!({"pq": {}, "peak": 1000}),
            "color.pq is read from the file at import, not set",
        ),
        (PQ, json!({}), "color needs log or lut; null clears it"),
        (
            PQ,
            json!({"gamut": "bt2020"}),
            "color needs log or lut; null clears it",
        ),
        (
            PQ,
            json!({"log": "slog3", "detected": true}),
            "color.detected is written by import, not set",
        ),
        (
            PQ,
            json!({"lut": LUT, "gamut": "bt2020", "peak": 1000}),
            "color.gamut goes with log",
        ),
    ];
    for (media, color, sentence) in cases {
        h.refuses_with(&set(media, color), sentence);
    }
}

#[test]
fn a_peak_that_is_not_a_whole_number_is_an_err() {
    let h = handle();
    for peak in [json!(1000.5), json!("1000"), json!(null), json!(true)] {
        let message = h.errors(&set(PQ, json!({ "peak": peak })));
        assert!(
            message.starts_with("color.peak must be a whole number of cd/m², not"),
            "{message}"
        );
    }
}

// ---- add_media and a file ----------------------------------------------------

fn descriptor(color: Value) -> Value {
    json!({"path": "/fixtures/new.mov", "kind": "video", "duration": 600_000,
        "width": 1024, "height": 128, "fps": [30, 1], "has_video": true, "color": color})
}

#[test]
fn add_media_and_a_file_take_a_reading_with_no_camera_log() {
    for color in [
        json!({"pq": {}}),
        json!({"pq": {"file": 4000, "from": "max_cll"}}),
        json!({"pq": {"file": 2000, "from": "mastering_display"}}),
    ] {
        let added =
            handle().apply(&json!({"op": "add_media", "descriptor": descriptor(color.clone())}));
        assert_eq!(color_of(&added, 20), color);
        let mut file = project();
        file["media"][2]["color"] = color.clone();
        let opened = Handle::from_value(&file);
        assert_eq!(color_of(&opened, SDR), color);
    }
}

#[test]
fn add_media_and_a_file_refuse_a_bad_reading() {
    let cases = [
        (
            json!({"pq": {"file": 0, "from": "max_cll"}}),
            "color.pq.file must be 1–10000 cd/m², not 0",
        ),
        (
            json!({"pq": {"file": 10001, "from": "max_cll"}}),
            "color.pq.file must be 1–10000 cd/m², not 10001",
        ),
        (
            json!({"pq": {"peak": 0}}),
            "color.pq.peak must be 1–10000 cd/m², not 0",
        ),
        (
            json!({"pq": {"file": 4000}}),
            "color.pq.from goes with color.pq.file",
        ),
        (
            json!({"pq": {"from": "max_cll"}}),
            "color.pq.from goes with color.pq.file",
        ),
        (
            json!({"detected": true, "pq": {"file": 4000, "from": "max_cll"}}),
            "color needs log or lut; null clears it",
        ),
    ];
    for (color, sentence) in cases {
        assert_eq!(
            handle().errors(&json!({"op": "add_media", "descriptor": descriptor(color.clone())})),
            sentence
        );
        let mut file = project();
        file["media"][2]["color"] = color;
        assert_eq!(
            Handle::try_from_value(&file).expect_err("refused"),
            format!("media 3: {sentence}")
        );
    }
    let mut sound = project();
    sound["media"][3]["color"] = json!({"pq": {}});
    assert_eq!(
        Handle::try_from_value(&sound).expect_err("refused"),
        "media 4 is an audio file; Camera Log is a setting on a video file"
    );
}

// ---- a LUT's removal and a paste -----------------------------------------------

#[test]
fn removing_a_converting_lut_keeps_the_reading() {
    let h = handle()
        .apply(&set(PQ, json!({"lut": LUT, "peak": 600})))
        .apply(&set(SDR, json!({"lut": LUT})));
    let removed = h.apply(&json!({"op": "remove_media", "media": LUT, "with_clips": true}));
    assert_eq!(
        color_of(&removed, PQ),
        json!({"pq": {"file": 4000, "from": "max_cll", "peak": 600}})
    );
    assert_eq!(color_of(&removed, SDR), Value::Null);
}

#[test]
fn a_paste_without_its_lut_keeps_the_reading() {
    let payload = json!({"clips": [{"id": 30, "track": 0, "start": 0, "duration": 600_000,
                                    "source": {"kind": "media", "media": 31, "in": 0}}],
        "media": [{"id": 31, "path": "/fixtures/pasted.mov", "kind": "video",
                   "duration": 600_000, "width": 1024, "height": 128, "fps": [30, 1],
                   "has_video": true,
                   "color": {"lut": 32, "pq": {"file": 4000, "from": "max_cll"}}}]});
    let pasted = handle().apply(&json!({"op": "paste", "at": 600_000, "payload": payload}));
    let row = array(&pasted.value(), "/media")
        .iter()
        .find(|m| m["path"] == json!("/fixtures/pasted.mov"))
        .cloned()
        .expect("the pasted video");
    assert_eq!(
        row["color"],
        json!({"pq": {"file": 4000, "from": "max_cll"}})
    );
}

// ---- what draws ------------------------------------------------------------------

#[test]
fn input_publishes_the_effective_peak_and_an_empty_reading_publishes_nothing() {
    let h = handle();
    assert_eq!(input(&h), json!({"peak": 4000}));
    let overridden = h.apply(&set(PQ, json!({"peak": 1000})));
    assert_eq!(input(&overridden), json!({"peak": 1000}));
    let logged = h.apply(&set(PQ, json!({"log": "slog3", "peak": 600})));
    assert_eq!(
        input(&logged),
        json!({"log": "slog3", "gamut": "s_gamut3_cine", "peak": 600})
    );
    let lut = h.apply(&set(PQ, json!({"lut": LUT})));
    assert_eq!(input(&lut), json!({"lut": LUT, "peak": 4000}));
    assert_eq!(
        at(&h.plan(), "/video_tracks/0/segments/0/input"),
        &json!({"peak": 4000})
    );
    // A PQ file whose import read nothing: no `input`, as before format 22.
    let mut file = project();
    file["clips"][0]["source"]["media"] = json!(PLAIN);
    let plain = Handle::from_value(&file);
    assert_eq!(input(&plain), Value::Null);
    let text = plain.plan_text();
    assert!(!text.contains("\"input\""), "{text}");
    let set_plain = plain.apply(&set(PLAIN, json!({"peak": 2000})));
    assert_eq!(input(&set_plain), json!({"peak": 2000}));
    assert_eq!(set_plain.apply(&set(PLAIN, Value::Null)).plan_text(), text);
}

// ---- a PQ still (spec §11 HD-20 (b)) ----------------------------------------------

/// A PQ still whose import read MaxCLL 4,000, an SDR still, and a clip of
/// the first.
const PQ_STILL: u32 = 8;
const SDR_STILL: u32 = 9;
const STILL_CLIP: u32 = 10;
const KIND: &str = "is an image; Camera Log is a setting on a video file";

fn image(id: u32, color: Value) -> Value {
    let mut row = json!({"id": id, "path": format!("/fixtures/s{id}.png"), "kind": "image",
        "width": 1024, "height": 128});
    if !color.is_null() {
        row["color"] = color;
    }
    row
}

fn still_project() -> Value {
    let mut file = project();
    file["version"] = json!(26);
    let media = file["media"].as_array_mut().expect("media");
    media.push(image(
        PQ_STILL,
        json!({"pq": {"file": 4000, "from": "max_cll"}}),
    ));
    media.push(image(SDR_STILL, Value::Null));
    file["tracks"]
        .as_array_mut()
        .expect("tracks")
        .push(json!({"id": 11, "name": "Track 2"}));
    file["clips"].as_array_mut().expect("clips").push(json!({
        "id": STILL_CLIP, "track": 11, "start": 0, "duration": 600_000,
        "source": {"kind": "image", "media": PQ_STILL}}));
    file
}

fn still_input(h: &Handle) -> Value {
    array(&h.recipe(300_000), "/layers")
        .iter()
        .find(|l| l["clip"] == json!(STILL_CLIP))
        .map(|l| l["input"].clone())
        .expect("the still's layer")
}

#[test]
fn an_image_takes_a_reading_by_add_media_a_file_and_a_peak() {
    let color = json!({"pq": {"file": 4000, "from": "max_cll"}});
    let mut descriptor = json!({"path": "/fixtures/new.png", "kind": "image",
        "width": 1024, "height": 128, "color": color.clone()});
    let added = handle().apply(&json!({"op": "add_media", "descriptor": descriptor.clone()}));
    assert_eq!(color_of(&added, 20), color);
    descriptor["color"] = json!({"pq": {}});
    let empty = handle().apply(&json!({"op": "add_media", "descriptor": descriptor}));
    assert_eq!(color_of(&empty, 20), json!({"pq": {}}));
    let h = Handle::from_value(&still_project());
    assert_eq!(color_of(&h, PQ_STILL), color);
    assert_eq!(still_input(&h), json!({"peak": 4000}));
    let set_to = h.apply(&set(PQ_STILL, json!({"peak": 600})));
    assert_eq!(
        color_of(&set_to, PQ_STILL),
        json!({"pq": {"file": 4000, "from": "max_cll", "peak": 600}})
    );
    assert_eq!(still_input(&set_to), json!({"peak": 600}));
}

#[test]
fn a_pq_image_keeps_its_reading_after_null() {
    let h = Handle::from_value(&still_project()).apply(&set(PQ_STILL, json!({"peak": 600})));
    let cleared = h.apply(&set(PQ_STILL, Value::Null));
    assert_eq!(
        color_of(&cleared, PQ_STILL),
        json!({"pq": {"file": 4000, "from": "max_cll"}})
    );
    assert_eq!(still_input(&cleared), json!({"peak": 4000}));
}

#[test]
fn an_image_refuses_camera_log_and_a_peak_without_a_reading() {
    let h = Handle::from_value(&still_project());
    let cases = [
        (
            PQ_STILL,
            json!({"log": "slog3"}),
            format!("media {PQ_STILL} {KIND}"),
        ),
        (PQ_STILL, json!({}), format!("media {PQ_STILL} {KIND}")),
        (SDR_STILL, json!({}), format!("media {SDR_STILL} {KIND}")),
        (
            SDR_STILL,
            json!({"peak": 600}),
            format!("media {SDR_STILL} is not a PQ file; only a PQ file takes a peak"),
        ),
    ];
    for (media, color, sentence) in cases {
        h.refuses_with(&set(media, color), &sentence);
    }
}
