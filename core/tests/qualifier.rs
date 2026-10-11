//! Black-box tests for the qualifier (spec §11 GR-13, format 18):
//! `video.qualifier {hue, saturation, luma, invert}` on an adjustment clip,
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the key absent when neutral, a range ticked on at its
//! default by `{}`, a partial range merged, `null` turning one off and an
//! all-null patch an identity; the three sentences, in hue then saturation
//! then luma order, and every bound exactly accepted; the refusal on any
//! other clip, and a neutral qualifier there an identity; the recipe's
//! adjustment source carrying `qualifier` only when not neutral, a picture
//! clip's qualifier from a file never published, and `ungraded` keeping it;
//! an action's hue centre the short way round (350 → 10 through 0, 10 → 350
//! through 0, exactly 180 apart linearly), a range turned on and `invert`
//! switching at the end, an end clamped; and Paste Attributes' rule. What a
//! qualifier does to a pixel is `tools/proof/qualifier_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, at, by_id, Handle, Outcome};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// A shape (10) on track 1 and an adjustment clip (11) on track 2 in front,
/// both four seconds long.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 18,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
        "tracks": [{"id": 1, "name": "Picture"}, {"id": 2, "name": "Adjustment"}],
        "clips": [
            {"id": 10, "track": 1, "start": 0, "duration": 4 * SEC,
             "source": {"kind": "shape"}, "video": {},
             "shape": {"kind": "rectangle", "width": 100, "height": 50}},
            {"id": 11, "track": 2, "start": 0, "duration": 4 * SEC,
             "source": {"kind": "adjustment"}, "video": {}}
        ],
        "next_id": 20
    }))
}

fn set_qualifier(clip: u32, qualifier: Value) -> Value {
    json!({"op": "set_video", "clips": [clip], "patch": {"qualifier": qualifier}})
}

/// Clip `id`'s stored `video.qualifier`, or `null` when the file has none.
fn stored(handle: &Handle, id: u64) -> Value {
    by_id(&handle.value(), "/clips", id)["video"]
        .get("qualifier")
        .cloned()
        .unwrap_or(Value::Null)
}

/// Clip `id`'s layer in the recipe at `t`, under `opts`.
fn layer(handle: &Handle, id: u64, t: i64, opts: &str) -> Value {
    array(&handle.recipe_opts(t, opts), "/layers")
        .iter()
        .find(|l| l["clip"] == json!(id))
        .cloned()
        .unwrap_or_else(|| panic!("clip {id}'s layer"))
}

/// Clip 11's evaluated hue centre at `t`.
fn centre(handle: &Handle, t: i64) -> f64 {
    at(
        &handle.clip_state(11, t).expect("clip 11"),
        "/video/qualifier/hue/center",
    )
    .as_f64()
    .expect("a centre")
}

/// Clip 11 with hue `base`, and a one-second linear action at 0 whose end
/// patch is `end`.
fn acting(base: Value, end: Value) -> Handle {
    project()
        .apply(&set_qualifier(11, json!({"hue": base})))
        .apply(&json!({"op": "add_action", "clip": 11, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 11, "action": 20,
                        "patch": {"video": {"qualifier": end}}}))
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-9
}

#[test]
fn neutral_is_absent_and_a_range_ticks_on_at_its_default() {
    let base = project();
    let written = base.to_json();
    assert!(!written.contains("\"qualifier\""), "{written}");
    for identity in [
        json!({"hue": null, "saturation": null, "luma": null}),
        json!({"invert": false}),
        json!({}),
    ] {
        assert!(
            matches!(
                base.try_apply(&set_qualifier(11, identity.clone())),
                Ok(Outcome::Identity)
            ),
            "{identity}"
        );
    }
    let on = base.apply(&set_qualifier(11, json!({"hue": {}, "luma": {}})));
    assert_eq!(
        stored(&on, 11),
        json!({"hue": {"center": 30.0, "width": 50.0, "softness": 25.0},
               "luma": {"low": 0.0, "high": 1.0, "softness": 0.1}})
    );
    // A partial range merges; `null` turns one off; `invert` is written only
    // when true; and everything off is the base's text again.
    let merged = on.apply(&set_qualifier(
        11,
        json!({"hue": {"center": 120}, "invert": true}),
    ));
    assert_eq!(
        stored(&merged, 11),
        json!({"hue": {"center": 120.0, "width": 50.0, "softness": 25.0},
               "luma": {"low": 0.0, "high": 1.0, "softness": 0.1}, "invert": true})
    );
    let off = merged.apply(&set_qualifier(
        11,
        json!({"hue": null, "luma": null, "invert": false}),
    ));
    assert_eq!(off.to_json(), written);
}

#[test]
fn the_three_sentences_in_order_and_every_bound_accepted() {
    let base = project();
    assert_contains(
        &base.errors(&set_qualifier(11, json!({"hue": {"center": 400}}))),
        "video.qualifier.hue.center must be between 0 and 360, not 400",
    );
    assert_contains(
        &base.errors(&set_qualifier(11, json!({"hue": {"width": -1}}))),
        "video.qualifier.hue.width must be between 0 and 360, not -1",
    );
    assert_contains(
        &base.errors(&set_qualifier(11, json!({"hue": {"softness": 181}}))),
        "video.qualifier.hue.softness must be between 0 and 180, not 181",
    );
    assert_contains(
        &base.errors(&set_qualifier(
            11,
            json!({"saturation": {"low": 0.8, "high": 0.2}}),
        )),
        "video.qualifier.saturation.low (0.8) must not be greater than \
         video.qualifier.saturation.high (0.2)",
    );
    assert_contains(
        &base.errors(&set_qualifier(11, json!({"luma": {"softness": 1.5}}))),
        "video.qualifier.luma.softness must be between 0 and 1, not 1.5",
    );
    // Hue before saturation before luma, whatever the patch names first; a
    // bound before the order.
    assert_contains(
        &base.errors(&set_qualifier(
            11,
            json!({"luma": {"low": 2}, "saturation": {"high": -1}, "hue": {"center": -5}}),
        )),
        "video.qualifier.hue.center must be between 0 and 360, not -5",
    );
    assert_contains(
        &base.errors(&set_qualifier(
            11,
            json!({"luma": {"low": 2}, "saturation": {"low": 0.9, "high": 1.2}}),
        )),
        "video.qualifier.saturation.high must be between 0 and 1, not 1.2",
    );
    let edges = base.apply(&set_qualifier(
        11,
        json!({"hue": {"center": 360, "width": 360, "softness": 180},
               "saturation": {"low": 0, "high": 1, "softness": 1},
               "luma": {"low": 0.5, "high": 0.5, "softness": 0}}),
    ));
    assert_eq!(
        stored(&edges, 11)["hue"],
        json!({"center": 360.0, "width": 360.0, "softness": 180.0})
    );
}

#[test]
fn only_an_adjustment_clip_takes_one() {
    let base = project();
    let message = base.errors(&set_qualifier(10, json!({"hue": {}})));
    assert_contains(
        &message,
        "clip 10 is not an adjustment clip and cannot take a qualifier",
    );
    assert!(matches!(
        base.try_apply(&set_qualifier(10, json!({"hue": null, "invert": false}))),
        Ok(Outcome::Identity)
    ));
    // Both clips at once: the shape refuses the whole edit.
    let both = json!({"op": "set_video", "clips": [11, 10],
                      "patch": {"qualifier": {"saturation": {}}}});
    assert_contains(&base.errors(&both), "clip 10 is not an adjustment clip");
}

#[test]
fn the_recipe_publishes_it_only_on_an_adjustment_source() {
    let base = project();
    assert_eq!(
        layer(&base, 11, SEC, "{}")["source"],
        json!({"kind": "adjustment"})
    );
    let ranged = base.apply(&set_qualifier(
        11,
        json!({"hue": {"center": 120, "width": 40, "softness": 20}, "invert": true}),
    ));
    assert_eq!(
        layer(&ranged, 11, SEC, "{}")["source"],
        json!({"kind": "adjustment",
               "qualifier": {"hue": {"center": 120.0, "width": 40.0, "softness": 20.0},
                             "invert": true}})
    );
    // `ungraded` keeps it (GR-13 extends GR-4).
    assert_eq!(
        layer(&ranged, 11, SEC, r#"{"ungraded": true}"#)["source"],
        layer(&ranged, 11, SEC, "{}")["source"]
    );
    // No layer key moves: the qualifier is a source key, not a layer key.
    let plain = layer(&base, 11, SEC, "{}");
    let keyed = layer(&ranged, 11, SEC, "{}");
    let keys = |v: &Value| v.as_object().map(|o| o.keys().cloned().collect::<Vec<_>>());
    assert_eq!(keys(&plain), keys(&keyed));
}

#[test]
fn a_picture_clips_qualifier_from_a_file_is_inert() {
    let mut value = project().value();
    value["clips"][0]["video"]["qualifier"] = json!({"hue": {"center": 0}});
    let opened = Handle::from_value(&value);
    let shape = layer(&opened, 10, SEC, "{}");
    assert_eq!(shape["source"]["kind"], json!("shape"));
    assert!(shape["source"].get("qualifier").is_none(), "{shape}");
    assert!(!shape.to_string().contains("qualifier"), "{shape}");
}

#[test]
fn the_hue_centre_animates_the_short_way_round() {
    let wide = |c: f64| json!({"center": c, "width": 20, "softness": 0});
    let over_zero = acting(wide(350.0), json!({"hue": {"center": 10}}));
    assert!(close(centre(&over_zero, SEC / 2), 0.0), "350 → 10 at 0.5");
    assert!(
        close(centre(&over_zero, SEC / 4), 355.0),
        "350 → 10 at 0.25"
    );
    assert!(close(centre(&over_zero, 2 * SEC), 10.0), "350 → 10 after");
    let back = acting(wide(10.0), json!({"hue": {"center": 350}}));
    assert!(close(centre(&back, SEC / 4), 5.0), "10 → 350 at 0.25");
    assert!(close(centre(&back, SEC / 2), 0.0), "10 → 350 at 0.5");
    assert!(close(centre(&back, 2 * SEC), 350.0), "10 → 350 after");
    let half = acting(wide(0.0), json!({"hue": {"center": 180}}));
    assert!(close(centre(&half, SEC / 2), 90.0), "0 → 180 at 0.5");
    let near = acting(wide(100.0), json!({"hue": {"center": 140}}));
    assert!(close(centre(&near, SEC / 2), 120.0), "100 → 140 at 0.5");
    // The recipe carries the same centre.
    let source = &layer(&over_zero, 11, SEC / 2, "{}")["source"];
    assert!(close(
        source["qualifier"]["hue"]["center"]
            .as_f64()
            .expect("a centre"),
        0.0
    ));
    // The stored end is as written: only the interpolation target moved.
    let stored_value = over_zero.value();
    let end = &by_id(&stored_value, "/clips", 11)["actions"][0]["end"];
    assert_eq!(end["video"]["qualifier"]["hue"]["center"], json!(10));
}

#[test]
fn a_range_turned_on_and_invert_switch_at_the_end() {
    let handle = acting(
        json!({"center": 100, "width": 40, "softness": 20}),
        json!({"saturation": {"low": 0.2}, "invert": true}),
    );
    let mid = handle.clip_state(11, SEC / 2).expect("clip 11");
    assert!(at(&mid, "/video/qualifier").get("saturation").is_none());
    assert!(at(&mid, "/video/qualifier").get("invert").is_none());
    let after = handle.clip_state(11, 2 * SEC).expect("clip 11");
    assert_eq!(
        at(&after, "/video/qualifier/saturation"),
        &json!({"low": 0.2, "high": 1.0, "softness": 0.1})
    );
    assert_eq!(at(&after, "/video/qualifier/invert"), &json!(true));
}

#[test]
fn an_actions_end_is_clamped() {
    let handle = acting(
        json!({"center": 100, "width": 40, "softness": 20}),
        json!({"hue": {"width": 500, "softness": -4},
               "luma": {"low": 0.9, "high": 0.3, "softness": 3}}),
    );
    let after = handle.clip_state(11, 2 * SEC).expect("clip 11");
    assert_eq!(
        at(&after, "/video/qualifier/hue"),
        &json!({"center": 100.0, "width": 360.0, "softness": 0.0})
    );
    assert_eq!(
        at(&after, "/video/qualifier/luma"),
        &json!({"low": 0.9, "high": 0.9, "softness": 1.0})
    );
}

#[test]
fn paste_attributes_follows_the_clip_kind() {
    let ranged = json!({"hue": {"center": 120.0, "width": 40.0, "softness": 20.0}});
    let own = json!({"luma": {"low": 0.2, "high": 0.8, "softness": 0.05}});
    let payload = |kind: &str, video: Value| {
        let mut clip = json!({"id": 1, "track": 0, "start": 0, "duration": SEC,
                              "source": {"kind": kind}, "video": video});
        if kind == "shape" {
            clip["shape"] = json!({"kind": "rectangle", "width": 10, "height": 10});
        }
        json!({"clips": [clip]})
    };
    let base = project().apply(&set_qualifier(11, own.clone()));
    // Adjustment → picture: the colour lands, the qualifier does not.
    let onto_picture = base.apply(&json!({"op": "paste_attributes", "clips": [10],
        "payload": payload("adjustment", json!({"color": {"brightness": 0.1},
                                                 "qualifier": ranged}))}));
    assert_eq!(stored(&onto_picture, 10), Value::Null);
    assert_eq!(
        by_id(&onto_picture.value(), "/clips", 10)["video"]["color"]["brightness"],
        json!(0.1)
    );
    // Picture → adjustment: the target keeps its own.
    let from_picture = base.apply(&json!({"op": "paste_attributes", "clips": [11],
        "payload": payload("shape", json!({"color": {"brightness": 0.2}}))}));
    assert_eq!(stored(&from_picture, 11), own);
    assert_eq!(
        by_id(&from_picture.value(), "/clips", 11)["video"]["color"]["brightness"],
        json!(0.2)
    );
    // Adjustment → adjustment: copied.
    let between = base.apply(&json!({"op": "paste_attributes", "clips": [11],
        "payload": payload("adjustment", json!({"qualifier": ranged}))}));
    assert_eq!(stored(&between, 11), ranged);
}

#[test]
fn an_unknown_key_inside_a_range_is_named() {
    assert_contains(
        &project().errors(&set_qualifier(11, json!({"hue": {"centre": 10}}))),
        "unknown key \"qualifier.hue.centre\" in a video patch",
    );
}
