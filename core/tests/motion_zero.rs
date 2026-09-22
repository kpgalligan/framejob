//! Zero-duration edge presets at the public write boundary (E2-27).

mod common;

use common::{num, Handle};
use serde_json::{json, Value};

const SECOND: i64 = 600_000;
const FRAME: i64 = 20_000;
const DURATION: i64 = 4 * SECOND;

fn fixture() -> Handle {
    Handle::from_value(&json!({
        "version": 8,
        "canvas": { "width": 640, "height": 360, "fps": [30, 1] },
        "media": [],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": DURATION,
            "source": { "kind": "shape" },
            "shape": { "kind": "rectangle", "width": 200, "height": 100 },
            "video": { "opacity": 0.75 }
        }],
        "next_id": 12
    }))
}

fn set_edge(handle: &Handle, slot: &str, duration: i64) -> Handle {
    handle.apply(&json!({
        "op": "set_video", "clips": [11],
        "patch": { "motion": { slot: { "kind": "fade", "duration": duration } } }
    }))
}

fn clear_edge(handle: &Handle, slot: &str) -> Handle {
    handle.apply(&json!({
        "op": "set_video", "clips": [11],
        "patch": { "motion": { slot: Value::Null } }
    }))
}

fn assert_same_recipe(control: &Handle, candidate: &Handle) {
    for tick in [0, 2 * SECOND, DURATION - FRAME] {
        assert_eq!(
            candidate.recipe_text(tick),
            control.recipe_text(tick),
            "tick {tick}"
        );
    }
}

#[test]
fn zero_and_snapped_subframe_edges_keep_their_kind_without_affecting_recipes() {
    let control = fixture();
    let zero_in = set_edge(&control, "in", 0);
    let both_zero = set_edge(&zero_in, "out", 0);
    for slot in ["in", "out"] {
        assert_eq!(
            both_zero.value()["clips"][0]["video"]["motion"][slot]["kind"],
            "fade"
        );
        assert_eq!(
            both_zero.value()["clips"][0]["video"]["motion"][slot]["duration"],
            0
        );
    }
    assert_same_recipe(&control, &zero_in);
    assert_same_recipe(&control, &both_zero);

    let subframe_in = set_edge(&control, "in", 1);
    let subframe_both = set_edge(&subframe_in, "out", 1);
    for slot in ["in", "out"] {
        assert_eq!(
            subframe_both.value()["clips"][0]["video"]["motion"][slot]["kind"],
            "fade"
        );
        assert_eq!(
            subframe_both.value()["clips"][0]["video"]["motion"][slot]["duration"],
            0
        );
    }
    assert_same_recipe(&control, &subframe_both);

    let reloaded = Handle::from_json(&both_zero.to_json());
    assert_eq!(
        reloaded.value()["clips"][0]["video"]["motion"],
        both_zero.value()["clips"][0]["video"]["motion"]
    );
    assert_same_recipe(&control, &reloaded);

    let out_only = clear_edge(&both_zero, "in");
    assert_eq!(
        out_only.value()["clips"][0]["video"]["motion"]["out"]["duration"],
        0
    );
    let cleared = clear_edge(&out_only, "out");
    assert!(cleared.value()["clips"][0]["video"]["motion"].is_null());
}

#[test]
fn positive_fade_edges_follow_the_exclusive_end_frame_rule() {
    let control = fixture();
    let one_in = set_edge(&control, "in", FRAME);
    assert_ne!(one_in.recipe_text(0), control.recipe_text(0));
    let one_out = set_edge(&control, "out", FRAME);
    assert_eq!(
        one_out.recipe_text(DURATION - FRAME),
        control.recipe_text(DURATION - FRAME)
    );
    let two_out = set_edge(&control, "out", 2 * FRAME);
    assert_ne!(
        two_out.recipe_text(DURATION - FRAME),
        control.recipe_text(DURATION - FRAME)
    );
    let layer = &two_out.recipe(DURATION - FRAME)["layers"][0];
    assert!((num(layer, "/opacity") - 0.75 * 0.75).abs() < 1e-9);
}
