//! Black-box tests for what format version 13 added — a graphic clip's
//! props as action targets, stored in an action's `end` as `graphic:
//! {props, kinds}` (spec §11 G-34 (a), (c), (h), (k)) — driven through the
//! C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: older files (12, 11 and 10) open stamped the current
//! version with every end as written, and a version-12 end that already
//! names `graphic` animates by the new rules, its colours switching at the
//! end for want of `kinds`; the KEY ORDER read off the written text
//! (`props` before `kinds`); the ROUND TRIP (the same bytes twice); a
//! MALFORMED end, which no frame fails on; and a stored end outside a range
//! the module has since narrowed, which opens and draws as stored and is
//! never re-checked. What versions 3 to 12 themselves hold is
//! `schema_v3.rs`..`schema_v12.rs`'s.

mod common;
#[path = "common/graphic_actions.rs"]
mod fixture;

use reelcut_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::Handle;
use fixture::{base, clip, keys, props_at, schema, written, FRAME, SEC};

/// [`base`] stamped `version`, clip 11 carrying `actions`.
fn file(version: u32, actions: Value) -> Value {
    let mut project = base();
    project["version"] = json!(version);
    project["clips"][0]["actions"] = actions;
    project
}

/// One linear action, id 14, at 1 s for 1 s, ending at `end`.
fn one_action(end: Value) -> Value {
    json!([{"id": 14, "start": SEC, "duration": SEC, "curve": "linear", "end": end}])
}

#[test]
fn older_files_open_stamped_current_with_their_ends_as_written() {
    // Hand-written or pasted before version 13: G-10 kept it inert.
    let end = json!({"video": {"opacity": 0.5},
                     "graphic": {"props": {"size": 129, "accent": "#ffffff"}}});
    for version in [12, 11, 10] {
        let opened = Handle::from_value(&file(version, one_action(end.clone())));
        let value = opened.value();
        assert_eq!(
            value["version"],
            json!(RC_FORMAT_VERSION),
            "version {version}"
        );
        assert_eq!(
            clip(&opened, 11)["actions"][0]["end"],
            end,
            "version {version}"
        );
        // It animates now: `size` ramps; `accent` has no `kinds`, so it
        // holds and switches at the end.
        let mid = props_at(&opened, SEC + SEC / 2);
        assert_eq!(mid["size"], json!(96.5), "version {version}");
        assert_eq!(mid["accent"], json!("#00000000"), "version {version}");
        let before = props_at(&opened, 2 * SEC - FRAME);
        assert_eq!(before["accent"], json!("#00000000"), "version {version}");
        assert_eq!(props_at(&opened, 2 * SEC)["accent"], json!("#ffffff"));
    }
}

#[test]
fn props_are_written_before_kinds_and_the_bytes_round_trip() {
    let opened = Handle::from_value(&file(RC_FORMAT_VERSION, one_action(json!({}))));
    let op = json!({"op": "set_action_end", "clip": 11, "action": 14,
                    "patch": {"graphic": {"props": {"size": 129, "accent": "#ffffff"}}},
                    "schema": schema()});
    let animated = opened.apply(&op);
    let text = written(&animated);
    assert_eq!(
        keys(&text, "/clips/0/actions/0/end/graphic"),
        ["props", "kinds"]
    );
    let bytes = animated.to_json();
    assert_eq!(Handle::from_json(&bytes).to_json(), bytes);
}

#[test]
fn a_malformed_end_holds_then_switches_and_no_frame_fails() {
    let ends = [
        json!({"graphic": 5}),
        json!({"graphic": {"props": []}}),
        json!({"graphic": {"props": {"size": "big"}, "kinds": "x"}}),
        json!({"graphic": {"props": {"accent": "nope"}, "kinds": {"accent": "color"}}}),
    ];
    let actions: Vec<Value> = ends
        .iter()
        .enumerate()
        .map(|(i, end)| json!({"id": 14 + i, "start": i as i64 * SEC, "duration": SEC, "end": end}))
        .collect();
    let opened = Handle::from_value(&file(RC_FORMAT_VERSION, json!(actions)));
    for frame in 0..150 {
        let t = frame * FRAME;
        let props = props_at(&opened, t);
        // A number toward a string: held, then switched at 3 s.
        let size = if t < 3 * SEC { json!(64) } else { json!("big") };
        assert_eq!(props["size"], size, "frame {frame}");
        // A colour it cannot read: held, then switched at 4 s.
        let accent = if t < 4 * SEC {
            json!("#00000000")
        } else {
            json!("nope")
        };
        assert_eq!(props["accent"], accent, "frame {frame}");
        let state = opened.clip_state(11, t).expect("clip 11");
        assert_eq!(state["graphic"]["props"], props, "frame {frame}");
    }
    let split = opened.apply(&json!({"op": "split", "clips": [11], "at": 3 * SEC + SEC / 2}));
    assert_eq!(common::array(&split.value(), "/clips").len(), 3);
}

#[test]
fn a_stored_end_outside_a_narrowed_range_draws_as_stored_and_is_not_rechecked() {
    // The schema's `size` max is 400; this end was written when it was not.
    let end = json!({"graphic": {"props": {"size": 500}, "kinds": {"size": "number"}}});
    let opened = Handle::from_value(&file(RC_FORMAT_VERSION, one_action(end)));
    assert_eq!(props_at(&opened, 2 * SEC)["size"], json!(500));
    let op = |props: Value| {
        json!({"op": "set_action_end", "clip": 11, "action": 14,
               "patch": {"graphic": {"props": props}}, "schema": schema()})
    };
    let titled = opened.apply(&op(json!({"title": "B"})));
    let stored = &clip(&titled, 11)["actions"][0]["end"]["graphic"]["props"];
    assert_eq!(stored, &json!({"size": 500, "title": "B"}));
    assert_eq!(
        opened.errors(&op(json!({"size": 500}))),
        "graphic.props.size must be between 0 and 400, not 500"
    );
}
