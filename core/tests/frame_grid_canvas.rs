mod common;
#[path = "common/frame_grid.rs"]
mod fixture;

use common::{Handle, Outcome};
use fixture::{action, nest, nest_clip, project, text_clip};
use serde_json::{json, Value};

fn clip(list: &Value, id: u64) -> &Value {
    list.as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == id)
        .unwrap()
}

fn nest_row(project: &Value, id: u64) -> &Value {
    project["nests"]
        .as_array()
        .unwrap()
        .iter()
        .find(|n| n["id"] == id)
        .unwrap()
}

fn normalized(clip: &Value, start: i64) {
    assert_eq!(clip["start"], start);
    assert_eq!(clip["duration"], 50_000);
    assert_eq!(clip["video"]["motion"]["in"]["duration"], 0);
    assert_eq!(clip["video"]["motion"]["out"]["duration"], 25_000);
    assert_eq!(clip["video"]["motion"]["during"]["period"], 25_000);
    assert_eq!(clip["text"]["animation"]["in"], 25_000);
    assert_eq!(clip["text"]["animation"]["out"], 50_000);
    assert_eq!(clip["actions"][0]["start"], 0);
    assert_eq!(clip["actions"][0]["duration"], 25_000);
    assert_eq!(
        clip["actions"][0]["end"]["video"]["motion"]["in"]["duration"],
        12_500
    );
    assert_eq!(clip["audio"]["fade_in"], 10_001);
    assert_eq!(clip["audio"]["fade_out"], 12_501);
}

#[test]
fn canvas_normalizes_top_two_levels_orphan_and_shared_nest_once() {
    let inner = nest(20, 21, vec![text_clip(22, 21, 20_000, 60_000)]);
    let mut outer_child = nest_clip(12, 20_000, 60_000, 20);
    outer_child["track"] = json!(11);
    let outer = nest(10, 11, vec![text_clip(13, 11, 20_000, 60_000), outer_child]);
    let orphan = nest(30, 31, vec![text_clip(32, 31, 20_000, 60_000)]);
    let mut input = project(
        [30, 1],
        vec![
            nest_clip(2, 0, 60_000, 10),
            nest_clip(3, 200_000, 60_000, 10),
            text_clip(4, 1, 400_000, 60_000),
        ],
        vec![outer, inner, orphan],
        100,
    );
    input["markers"] = json!([
        {"id": 40, "time": 14_000, "name": "first"},
        {"id": 41, "time": 13_000, "name": "second"},
        {"id": 42, "time": 0, "name": "zero"}
    ]);
    let original = Handle::from_value(&input);
    let before = original.value();
    let after = original.apply(&json!({"op": "set_canvas", "fps": [24, 1]}));
    let value = after.value();
    normalized(clip(&value["clips"], 4), 400_000);
    normalized(clip(&nest_row(&value, 10)["clips"], 13), 25_000);
    normalized(clip(&nest_row(&value, 20)["clips"], 22), 25_000);
    normalized(clip(&nest_row(&value, 30)["clips"], 32), 25_000);
    assert_eq!(
        clip(&value["clips"], 2)["source"],
        before["clips"][0]["source"]
    );
    assert_eq!(clip(&value["clips"], 3)["track"], 1);
    assert_eq!(value["next_id"], 100);
    assert_eq!(value["nests"][0]["width"], 640);
    assert_eq!(value["markers"].as_array().unwrap().len(), 2);
    assert_eq!(value["markers"][0]["id"], 40);
    assert_eq!(value["markers"][0]["time"], 25_000);
    assert_eq!(value["markers"][1]["id"], 42);
    let scoped = after.scoped(10).value();
    normalized(clip(&scoped["clips"], 13), 25_000);
    assert_eq!(original.value(), before, "input handle is immutable");
}

#[test]
fn unchanged_rate_and_size_only_preserve_legacy_grid_and_empty_motion() {
    let mut off_grid = text_clip(2, 1, 20_000, 60_000);
    off_grid["video"]["motion"] = json!({});
    let input = project([30, 1], vec![off_grid], vec![], 10);
    let original = Handle::from_value(&input);
    assert!(matches!(
        original.try_apply(&json!({"op": "set_canvas", "fps": [30,1]})),
        Ok(Outcome::Identity)
    ));
    let resized = original.apply(&json!({"op": "set_canvas", "width": 800}));
    assert_eq!(resized.value()["clips"], original.value()["clips"]);
    assert_eq!(
        resized.value()["clips"][0]["video"]["motion"],
        json!({"in": null, "out": null, "during": null})
    );
    let rate = resized.apply(&json!({"op": "set_canvas", "fps": [24,1]}));
    assert_eq!(
        rate.value()["clips"][0]["video"]["motion"],
        json!({"in": null, "out": null, "during": null})
    );
}

#[test]
fn fractional_grid_source_tail_floor_and_non_dividing_rational_vocabulary() {
    let mut media_clip = json!({"id": 2, "track": 1, "start": 20_020,
        "duration": 100_100, "speed": 2.0,
        "source": {"kind": "media", "media": 9, "in": 0},
        "video": {"motion": {"in": {"kind": "fade", "duration": 0},
            "out": {"kind": "fade", "duration": 0},
            "during": {"kind": "pulse", "period": 1, "amount": 0.5}}}});
    let mut p = project([30_000, 1001], vec![media_clip.clone()], vec![], 10);
    // Ordinary snapping keeps 100_100; the 100_100-tick source at speed 2
    // leaves only 50_050 timeline ticks on the new grid.
    p["media"] = json!([fixture::media(9, 100_100)]);
    let changed = Handle::from_value(&p).apply(&json!({"op":"set_canvas","fps":[24_000,1001]}));
    let c = &changed.value()["clips"][0];
    assert_eq!(
        (c["start"].as_i64(), c["duration"].as_i64()),
        (Some(25_025), Some(50_050))
    );
    assert_eq!(c["video"]["motion"]["in"]["duration"], 0);
    assert_eq!(c["video"]["motion"]["during"]["period"], 25_025);
    media_clip["duration"] = json!(20_020);
    p["clips"] = json!([media_clip]);
    p["media"][0]["duration"] = json!(1_000);
    let floored = Handle::from_value(&p).apply(&json!({"op":"set_canvas","fps":[24_000,1001]}));
    assert_eq!(floored.value()["clips"][0]["duration"], 25_025);

    // At 7 fps the ideal frame is 600000/7 ticks. Values on opposite
    // sides of 300000/7 must land at 0 and round(600000/7)=85714.
    let mut odd = text_clip(2, 1, 0, 120_000);
    odd["video"]["motion"] = json!({"in": {"kind":"fade","duration":42_857},
        "out": {"kind":"fade","duration":42_858}});
    odd["text"]["animation"] = json!({"kind":"typewriter","in":42_857,"out":42_858});
    let odd = Handle::from_value(&project([30, 1], vec![odd], vec![], 10))
        .apply(&json!({"op":"set_canvas","fps":[7,1]}));
    let c = &odd.value()["clips"][0];
    assert_eq!(c["video"]["motion"]["in"]["duration"], 0);
    assert_eq!(c["video"]["motion"]["out"]["duration"], 85_714);
    assert_eq!(c["text"]["animation"]["in"], 0);
    assert_eq!(c["text"]["animation"]["out"], 85_714);
}

#[test]
fn shortened_clip_clamps_actions_preserves_order_and_overlap_style() {
    let mut a = text_clip(2, 1, 0, 60_000);
    a["actions"] = json!([action(3, 40_000, 20_000), action(4, 60_000, 20_000)]);
    a["transition_in"] = json!({"kind":"push_left"});
    let mut b = text_clip(5, 1, 40_000, 60_000);
    b["actions"] = json!([]);
    let input = project([30, 1], vec![a, b], vec![], 20);
    let after = Handle::from_value(&input).apply(&json!({"op":"set_canvas","fps":[24,1]}));
    let v = after.value();
    let a = clip(&v["clips"], 2);
    assert_eq!(a["duration"], 50_000);
    assert_eq!(a["actions"][0]["id"], 3);
    assert_eq!(a["actions"][1]["id"], 4);
    assert_eq!(a["actions"][0]["start"], 25_000);
    assert_eq!(a["actions"][1]["start"], 25_000);
    assert_eq!(a["actions"][0]["duration"], 25_000);
    assert_eq!(a["actions"][1]["duration"], 25_000);
    assert_eq!(a["transition_in"]["kind"], "push_left");
    assert_eq!(clip(&v["clips"], 5)["track"], 1);
    assert_eq!(clip(&v["clips"], 5)["start"], 50_000);
    assert_eq!(v["next_id"], 20);
}

#[test]
fn rate_change_can_grow_overlap_without_minting_a_transition() {
    let mut a = text_clip(2, 1, 0, 80_000);
    let mut b = text_clip(4, 1, 60_000, 80_000);
    a["actions"] = json!([]);
    b["actions"] = json!([]);
    b["transition_in"] = json!({"kind":"push_left"});
    let base = Handle::from_value(&project([30, 1], vec![a, b], vec![], 10));
    let after = base.apply(&json!({"op":"set_canvas","fps":[24,1]})).value();
    assert_eq!(after["clips"][0]["duration"], 75_000);
    assert_eq!(after["clips"][1]["start"], 50_000);
    assert_eq!(after["clips"][1]["transition_in"]["kind"], "push_left");
    assert_eq!(after["clips"][0]["transition_in"], Value::Null);
    assert_eq!(after["tracks"].as_array().unwrap().len(), 1);
}
