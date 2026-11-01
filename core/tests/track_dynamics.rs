//! Black-box tests for a track's compressor and limiter (format 36, spec §11
//! AU-150), through the C FFI as `ReelCore.swift` drives it.
//!
//! Pinned here: `set_track` stores an object WHOLE (missing keys the clip
//! type's defaults, never the stored value's), `null` clears, an absent key
//! keeps the track's value, and the same value again is an identity; the
//! refusals in their own sentences — not an object or null, an unknown key,
//! a mistyped member, a value outside the clip's ranges under `compressor.`
//! or `limiter.`; inside a scope either key is an `Err` and the rest of
//! `set_track` still applies; `nest` gives the nest's tracks none, and the
//! timeline's tracks keep theirs; and a clip's own compressor and limiter
//! sentences are the ones they were.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, int, Handle};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

fn media() -> Value {
    json!({
        "id": 1, "path": "/fixtures/1.mov", "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn clip(id: u32, on: u32, start: i64) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": 2 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "video": {}, "audio": {}
    })
}

/// Tracks 2 (back, clip 4) and 3 (front, clip 5).
fn two_tracks(back: Value, front: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 36,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0] },
        "media": [media()], "tracks": [back, front],
        "clips": [clip(4, 2, 0), clip(5, 3, SEC)], "markers": [],
        "next_id": 6
    }))
}

fn plain() -> Handle {
    two_tracks(
        json!({"id": 2, "name": "Back"}),
        json!({"id": 3, "name": "Front"}),
    )
}

fn set(args: Value) -> Value {
    let mut op = json!({"op": "set_track", "track": 2});
    for (key, value) in args.as_object().expect("object") {
        op[key] = value.clone();
    }
    op
}

#[test]
fn an_object_is_stored_whole_with_the_clip_types_defaults() {
    let after = plain()
        .apply(&set(
            json!({"compressor": {"threshold_db": -20.0, "ratio": 4.0}}),
        ))
        .value();
    assert_eq!(
        after["tracks"][0]["compressor"],
        json!({"threshold_db": -20.0, "ratio": 4.0, "attack": 6000,
               "release": 120000, "makeup_db": 0.0})
    );
    assert!(after["tracks"][0].get("limiter").is_none(), "{after}");
    let limited = plain()
        .apply(&set(json!({"limiter": {"ceiling_db": -6.0}})))
        .value();
    assert_eq!(
        limited["tracks"][0]["limiter"],
        json!({"ceiling_db": -6.0, "release": 60000})
    );
}

#[test]
fn an_object_replaces_and_never_merges_into_the_stored_value() {
    let first = plain().apply(&set(json!({
        "compressor": {"threshold_db": -30.0, "ratio": 8.0, "makeup_db": 6.0}
    })));
    let second = first
        .apply(&set(json!({"compressor": {"ratio": 2.0}})))
        .value();
    assert_eq!(
        second["tracks"][0]["compressor"],
        json!({"threshold_db": -18.0, "ratio": 2.0, "attack": 6000,
               "release": 120000, "makeup_db": 0.0})
    );
}

#[test]
fn null_clears_absent_keeps_and_the_same_value_is_an_identity() {
    let both = plain().apply(&set(json!({
        "compressor": {"ratio": 4.0}, "limiter": {"ceiling_db": -3.0}
    })));
    // Absent keeps both.
    let renamed = both.apply(&set(json!({"name": "Bus"}))).value();
    assert!(
        renamed["tracks"][0].get("compressor").is_some(),
        "{renamed}"
    );
    assert!(renamed["tracks"][0].get("limiter").is_some(), "{renamed}");
    // The same value again changes nothing.
    both.refuses(&set(json!({"limiter": {"ceiling_db": -3.0}})));
    // Null clears one and keeps the other.
    let cleared = both.apply(&set(json!({"compressor": null}))).value();
    assert!(
        cleared["tracks"][0].get("compressor").is_none(),
        "{cleared}"
    );
    assert!(cleared["tracks"][0].get("limiter").is_some(), "{cleared}");
    // Null on a track with none is an identity.
    plain().refuses(&set(json!({"limiter": null})));
}

#[test]
fn a_value_that_is_not_an_object_or_null_is_refused_by_name() {
    assert_eq!(
        plain().errors(&set(json!({"compressor": 5}))),
        "compressor must be a json object or null, not 5"
    );
    assert_eq!(
        plain().errors(&set(json!({"limiter": [-1.0, 60000]}))),
        "limiter must be a json object or null, not [-1.0,60000]"
    );
}

#[test]
fn an_unknown_key_and_a_mistyped_member_are_refused_by_path() {
    assert_eq!(
        plain().errors(&set(json!({"compressor": {"knee": 6.0}}))),
        "unknown key \"compressor.knee\" in set_track"
    );
    let message = plain().errors(&set(json!({"limiter": {"release": "slow"}})));
    assert!(
        message.starts_with("bad value at \"limiter.release\" in set_track: "),
        "{message}"
    );
}

#[test]
fn a_value_outside_the_clips_ranges_is_refused_under_the_tracks_key() {
    for (args, sentence) in [
        (
            json!({"compressor": {"ratio": 30.0}}),
            "compressor.ratio must be between 1 and 20, not 30",
        ),
        (
            json!({"compressor": {"threshold_db": -70.0}}),
            "compressor.threshold_db must be between -60 and 0, not -70",
        ),
        (
            json!({"compressor": {"attack": -1}}),
            "compressor.attack must not be negative, not -1",
        ),
        (
            json!({"compressor": {"makeup_db": 30.0}}),
            "compressor.makeup_db must be between 0 and 24, not 30",
        ),
        (
            json!({"limiter": {"ceiling_db": 1.0}}),
            "limiter.ceiling_db must be between -24 and 0, not 1",
        ),
        (
            json!({"limiter": {"release": 10}}),
            "limiter.release must be between 600 and 600000 ticks, not 10",
        ),
    ] {
        assert_eq!(plain().errors(&set(args)), sentence);
    }
}

#[test]
fn a_clips_compressor_and_limiter_keep_their_sentences() {
    assert_eq!(
        plain().errors(&json!({"op": "set_audio", "clips": [4],
                               "patch": {"compressor": {"ratio": 30.0}}})),
        "audio.compressor.ratio must be between 1 and 20, not 30"
    );
    assert_eq!(
        plain().errors(&json!({"op": "set_audio", "clips": [4],
                               "patch": {"limiter": {"release": 10}}})),
        "audio.limiter.release must be between 600 and 600000 ticks, not 10"
    );
}

#[test]
fn inside_a_scope_the_dynamics_are_refused_and_the_rest_applies() {
    let nested = plain().apply(&json!({"op": "nest", "clips": [4, 5]}));
    let value = nested.value();
    let nest_id = int(&array(&value, "/nests")[0], "/id") as u32;
    let inner = int(&array(&array(&value, "/nests")[0], "/tracks")[0], "/id");
    for args in [
        json!({"compressor": {"ratio": 4.0}}),
        json!({"limiter": null}),
    ] {
        let mut op = json!({"op": "set_track", "track": inner, "scope": nest_id});
        for (key, v) in args.as_object().expect("object") {
            op[key] = v.clone();
        }
        assert_eq!(
            nested.errors(&op),
            format!("a track's compressor or limiter has no meaning inside nest {nest_id}")
        );
    }
    nested.apply(&json!({"op": "set_track", "track": inner, "scope": nest_id,
                         "volume": 0.5}));
}

#[test]
fn nest_gives_its_tracks_none_and_the_timelines_keep_theirs() {
    let dynamic = json!({"threshold_db": -20.0, "ratio": 4.0});
    let before = two_tracks(
        json!({"id": 2, "name": "Back", "compressor": dynamic}),
        json!({"id": 3, "name": "Front", "limiter": {"ceiling_db": -6.0}}),
    );
    let nest_id = int(&before.value(), "/next_id") as u64;
    let after = before
        .apply(&json!({"op": "nest", "clips": [4, 5]}))
        .value();
    let nest = by_id(&after, "/nests", nest_id);
    for track in array(nest, "/tracks") {
        assert!(track.get("compressor").is_none(), "{track}");
        assert!(track.get("limiter").is_none(), "{track}");
    }
    assert!(after["tracks"][0].get("compressor").is_some(), "{after}");
    assert!(after["tracks"][1].get("limiter").is_some(), "{after}");
}
