//! Preservation vectors for placement candidate commits through the FFI.
mod common;
#[path = "common/commit_placement.rs"]
mod fixtures;

use common::Outcome;
use fixtures::{clip, clip_mut, cross_dissolve, media_clip, project, track};
use serde_json::json;

#[test]
fn four_single_replacements_preserve_unrelated_document_bytes() {
    let vectors = [
        (
            json!({"op":"trim_start","clip":10,"to":100000}),
            "start",
            json!(100000),
            900000,
            100000,
            1.0,
        ),
        (
            json!({"op":"trim_end","clip":10,"to":1200000}),
            "duration",
            json!(1200000),
            1200000,
            0,
            1.0,
        ),
        (
            json!({"op":"rate_stretch","clip":10,"to_end":1200000}),
            "duration",
            json!(1200000),
            1200000,
            0,
            1_000_000.0 / 1_200_000.0,
        ),
        (
            json!({"op":"set_speed","clip":10,"rate":2.0}),
            "speed",
            json!(2.0),
            500000,
            0,
            2.0,
        ),
    ];
    for (op, field, expected, duration, source_in, speed) in vectors {
        let before = project();
        let after = before.apply(&op);
        let a = after.value();
        let b = before.value();
        assert_eq!(clip(&a, 10)[field], expected, "{op}");
        assert_eq!(clip(&a, 11), clip(&b, 11), "{op}");
        assert_eq!(clip(&a, 12), clip(&b, 12), "{op}");
        assert_eq!(a["tracks"], b["tracks"], "{op}");
        assert_eq!(a["next_id"], b["next_id"], "{op}");
        let mut complete = b;
        let target = clip_mut(&mut complete, 10);
        target["start"] = json!(if source_in == 0 { 0 } else { 100000 });
        target["duration"] = json!(duration);
        target["source"]["in"] = json!(source_in);
        target["speed"] = json!(speed);
        assert_eq!(a, complete, "full document for {op}");
    }
}

#[test]
fn move_and_transition_duration_keep_order_and_ids() {
    let before = project();
    let moved = before.apply(&json!({"op":"move_clip","clips":[11],"delta":-500000}));
    let b = before.value();
    let a = moved.value();
    assert_eq!(clip(&a, 11)["start"], 1500000);
    assert_eq!(clip(&a, 10), clip(&b, 10));
    assert_eq!(clip(&a, 12), clip(&b, 12));
    assert_eq!(a["next_id"], 50);
    let mut expected = b.clone();
    clip_mut(&mut expected, 11)["start"] = json!(1_500_000);
    assert_eq!(a, expected, "whole moved document");

    let transitioned =
        before.apply(&json!({"op":"set_transition_duration","clip":11,"duration":200000}));
    let a = transitioned.value();
    assert_eq!(clip(&a, 11)["start"], 800000);
    assert_eq!(clip(&a, 11)["transition_in"]["kind"], "cross_dissolve");
    assert_eq!(a["next_id"], 50);
    assert_eq!(
        a["clips"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["id"].as_u64().unwrap())
            .collect::<Vec<_>>(),
        vec![10, 11, 12]
    );
    let mut expected = b;
    let clip = clip_mut(&mut expected, 11);
    clip["start"] = json!(800_000);
    clip["transition_in"] = cross_dissolve();
    assert_eq!(a, expected, "whole transition-duration document");
}

#[test]
fn four_addition_callers_append_in_id_order() {
    let vectors = [
        (json!({"op":"add_clip","track":4,"media":1,"at":4000000}), 4),
        (
            json!({"op":"add_text_clip","track":4,"at":4000000,"duration":1000000}),
            4,
        ),
        (
            json!({"op":"add_shape_clip","track":4,"at":4000000,"duration":1000000}),
            4,
        ),
        (json!({"op":"duplicate","clips":[10]}), 2),
    ];
    for (op, expected_track) in vectors {
        let before = project();
        let after = before.apply(&op);
        let b = before.value();
        let a = after.value();
        assert_eq!(a["clips"].as_array().unwrap().len(), 4, "{op}");
        assert_eq!(a["clips"][3]["id"], 50, "{op}");
        assert_eq!(a["clips"][3]["track"], expected_track, "{op}");
        assert_eq!(a["next_id"], 51, "{op}");
        assert_eq!(
            &a["clips"].as_array().unwrap()[..3],
            &b["clips"].as_array().unwrap()[..],
            "{op}"
        );
        let mut complete = b;
        let mut added = media_clip(&complete, 50, expected_track, 4_000_000, 1_000_000);
        match op["op"].as_str().unwrap() {
            "add_clip" => added["duration"] = json!(6_000_000),
            "add_text_clip" => {
                added["source"] = json!({"kind":"text"});
                added["audio"] = serde_json::Value::Null;
                added["text"] = json!({
                    "align":"center", "animation":null, "backdrop":null,
                    "color":[1.0,1.0,1.0,1.0], "content":"Title",
                    "font":"SourceSans3-Bold", "line_spacing":1.0,
                    "outline":null, "size":72.0, "tracking":0.0,
                    "valign":"middle", "width":null
                });
            }
            "add_shape_clip" => {
                added["source"] = json!({"kind":"shape"});
                added["audio"] = serde_json::Value::Null;
                added["shape"] = json!({
                    "arrow_end":false, "arrow_start":false, "fill":null,
                    "from":[0.0,1.0], "gradient":null, "height":120.0,
                    "kind":"rectangle", "radius":0.0,
                    "stroke":{"color":[1.0,1.0,1.0,1.0],"width":6.0},
                    "to":[1.0,0.0], "width":320.0
                });
            }
            "duplicate" => added["start"] = json!(1_000_000),
            _ => unreachable!(),
        }
        complete["clips"].as_array_mut().unwrap().push(added);
        complete["next_id"] = json!(51);
        assert_eq!(a, complete, "full document for {op}");
    }

    let before = project();
    let detached = before.apply(&json!({"op":"detach_audio","clip":10}));
    let a = detached.value();
    assert_eq!(a["tracks"][0]["id"], 50);
    assert_eq!(a["clips"][3]["id"], 51);
    assert_eq!(a["clips"][3]["track"], 50);
    assert_eq!(a["clips"][0]["enabled"]["audio"], false);
    assert_eq!(a["next_id"], 52);
    let mut expected = before.value();
    let new_track = track(&expected, 50, "Track 4");
    expected["tracks"]
        .as_array_mut()
        .unwrap()
        .insert(0, new_track);
    clip_mut(&mut expected, 10)["enabled"]["audio"] = json!(false);
    let mut audio = media_clip(&expected, 51, 50, 0, 1_000_000);
    audio["enabled"]["video"] = json!(false);
    audio["enabled"]["audio"] = json!(true);
    expected["clips"].as_array_mut().unwrap().push(audio);
    expected["next_id"] = json!(52);
    assert_eq!(a, expected, "whole detached document");
}

#[test]
fn refusal_after_draft_allocation_does_not_consume_ids() {
    let before = project();
    let original = before.value();
    let op = json!({"op":"add_clip","track":2,"media":1,"at":0});
    assert!(matches!(before.try_apply(&op), Ok(Outcome::Refused(_))));
    assert_eq!(before.value(), original);
    let after = before.apply(&json!({"op":"duplicate","clips":[10]}));
    assert_eq!(after.value()["clips"][3]["id"], 50);
    let mut expected = original;
    let mut copy = clip(&expected, 10).clone();
    copy["id"] = json!(50);
    copy["start"] = json!(1_000_000);
    expected["clips"].as_array_mut().unwrap().push(copy);
    expected["next_id"] = json!(51);
    assert_eq!(
        after.value(),
        expected,
        "whole document after refused allocation"
    );
}

#[test]
fn zero_delta_mints_unselected_overlap_and_is_applied() {
    let mut value = project().value();
    value["clips"][1]["start"] = json!(900000);
    value["clips"][1]["transition_in"] = serde_json::Value::Null;
    let before = common::Handle::from_value(&value);
    let after = before.apply(&json!({"op":"move_clip","clips":[10],"delta":0}));
    let a = after.value();
    assert_eq!(clip(&a, 11)["transition_in"]["kind"], "cross_dissolve");
    assert_eq!(clip(&a, 10), clip(&value, 10));
    assert_eq!(clip(&a, 12), clip(&value, 12));
    assert_eq!(a["next_id"], value["next_id"]);
    let mut expected = value;
    clip_mut(&mut expected, 11)["transition_in"] = cross_dissolve();
    assert_eq!(a, expected, "whole zero-delta document");
}

#[test]
fn old_track_refusal_precedes_destination_track_on_a_multi_selection() {
    let mut value = project().value();
    for (id, track, start) in [
        (20, 2, 4_000_000),
        (21, 2, 4_400_000),
        (30, 4, 4_000_000),
        (31, 4, 4_400_000),
    ] {
        let mut extra = clip(&value, 10).clone();
        extra["id"] = json!(id);
        extra["track"] = json!(track);
        extra["start"] = json!(start);
        value["clips"].as_array_mut().unwrap().push(extra);
    }
    let before = common::Handle::from_value(&value);
    let op = json!({"op":"move_clip","clips":[10,12],"delta":0,"track":3});
    before.refuses_with(
        &op,
        "clips 20 and 21 would overlap by 600000 ticks, more than half of the shorter clip (500000 ticks)",
    );
    assert_eq!(before.value(), value);
    assert_eq!(before.value()["next_id"], 50);
}

#[test]
fn affected_old_and_new_tracks_mint_unselected_overlaps_only() {
    let mut value = project().value();
    for (id, track, start) in [
        (20, 2, 4_000_000),
        (21, 2, 4_900_000),
        (22, 3, 3_900_000),
        (23, 3, 900_000),
        (30, 4, 4_000_000),
        (31, 4, 4_900_000),
    ] {
        let mut extra = clip(&value, 10).clone();
        extra["id"] = json!(id);
        extra["track"] = json!(track);
        extra["start"] = json!(start);
        value["clips"].as_array_mut().unwrap().push(extra);
    }
    let stored = json!({"kind":"wipe","curve":"linear","audio":false});
    value["clips"][1]["transition_in"] = stored.clone();
    value["clips"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|c| c["id"] == 22)
        .unwrap()["transition_in"] = stored.clone();
    let before = common::Handle::from_value(&value);
    let after = before.apply(&json!({"op":"move_clip","clips":[10],"delta":3000000,"track":3}));
    let a = after.value();
    assert_eq!(clip(&a, 10)["track"], 3);
    assert_eq!(clip(&a, 10)["start"], 3_000_000);
    assert_eq!(clip(&a, 21)["transition_in"]["kind"], "cross_dissolve");
    assert_eq!(clip(&a, 23)["transition_in"]["kind"], "cross_dissolve");
    assert_eq!(
        clip(&a, 22)["transition_in"],
        clip(&before.value(), 22)["transition_in"]
    );
    assert_eq!(clip(&a, 31)["transition_in"], serde_json::Value::Null);
    assert_eq!(
        clip(&a, 11)["transition_in"],
        clip(&value, 11)["transition_in"]
    );
    assert_eq!(a["next_id"], value["next_id"]);
    let mut expected = value;
    let moved = clip_mut(&mut expected, 10);
    moved["track"] = json!(3);
    moved["start"] = json!(3_000_000);
    clip_mut(&mut expected, 21)["transition_in"] = cross_dissolve();
    clip_mut(&mut expected, 23)["transition_in"] = cross_dissolve();
    assert_eq!(a, expected, "whole affected-track document");
}

#[test]
fn duplicate_and_detach_remint_actions_after_clip_and_track_ids() {
    let mut value = project().value();
    value["clips"][0]["actions"] = json!([{"id":40,"start":0,"duration":400000,"end":{}}]);
    let before = common::Handle::from_value(&value);
    let value = before.value();

    let doubled = before.apply(&json!({"op":"duplicate","clips":[10]}));
    let d = doubled.value();
    assert_eq!(d["clips"][3]["id"], 50);
    assert_eq!(d["clips"][3]["actions"][0]["id"], 51);
    assert_eq!(d["next_id"], 52);
    assert_eq!(clip(&d, 10), clip(&value, 10));
    let mut expected = value.clone();
    let mut copy = clip(&value, 10).clone();
    copy["id"] = json!(50);
    copy["start"] = json!(1_000_000);
    copy["actions"][0]["id"] = json!(51);
    expected["clips"].as_array_mut().unwrap().push(copy);
    expected["next_id"] = json!(52);
    assert_eq!(d, expected, "whole duplicate-with-action document");

    let detached = before.apply(&json!({"op":"detach_audio","clip":10}));
    let d = detached.value();
    assert_eq!(d["tracks"][0]["id"], 50);
    assert_eq!(d["clips"][3]["id"], 51);
    assert_eq!(d["clips"][3]["actions"][0]["id"], 52);
    assert_eq!(d["next_id"], 53);
    assert_eq!(d["clips"][0]["actions"], value["clips"][0]["actions"]);
    let mut expected = value.clone();
    let new_track = track(&expected, 50, "Track 4");
    expected["tracks"]
        .as_array_mut()
        .unwrap()
        .insert(0, new_track);
    clip_mut(&mut expected, 10)["enabled"]["audio"] = json!(false);
    let mut audio = clip(&value, 10).clone();
    audio["id"] = json!(51);
    audio["track"] = json!(50);
    audio["enabled"]["video"] = json!(false);
    audio["actions"][0]["id"] = json!(52);
    expected["clips"].as_array_mut().unwrap().push(audio);
    expected["next_id"] = json!(53);
    assert_eq!(d, expected, "whole detach-with-action document");
}
