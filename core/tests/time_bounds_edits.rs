//! Core edit admission through the FFI: an applied control and a crossing
//! with its exact error or pre-existing refusal for each placement family.
//! Every applied result is inspected independently of the core validator.

use serde_json::{json, Value};

mod common;
use common::Handle;
#[path = "common/extreme_time.rs"]
mod extreme_time;
use extreme_time::{assert_boundary_error, assert_boundary_refusal, assert_safe};

const M: i64 = 9_000_000_000_000_000;
const FRAME: i64 = 20_000;

fn empty() -> Handle {
    Handle::from_value(&json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 2, "path": "/missing.mov", "kind": "video",
                   "duration": M, "width": 1920, "height": 1080,
                   "fps": [30, 1], "has_video": true, "has_audio": true}],
        "tracks": [{"id": 1}], "next_id": 10
    }))
}

fn near(source: Value) -> Handle {
    let mut project = empty().value();
    project["clips"] = json!([{
        "id": 3, "track": 1, "start": M - 3 * FRAME,
        "duration": 2 * FRAME, "source": source, "video": {}
    }]);
    Handle::from_value(&project)
}

#[test]
fn direct_placement_and_cumulative_writers_obey_the_boundary() {
    let generated = near(json!({"kind": "text"}));
    let media = near(json!({"kind": "media", "media": 2, "in": 0}));
    let cases = [
        (
            "move",
            &generated,
            json!({"op": "move_clip", "clips": [3], "delta": FRAME}),
            json!({"op": "move_clip", "clips": [3], "delta": 2 * FRAME}),
            "clip 3.end",
            M + FRAME,
        ),
        (
            "insert_time",
            &generated,
            json!({"op": "insert_time", "at": M - 3 * FRAME,
                                           "length": FRAME}),
            json!({"op": "insert_time", "at": M - 3 * FRAME,
                "length": 2 * FRAME}),
            "clip 3.end",
            M + FRAME,
        ),
        (
            "trim_end",
            &generated,
            json!({"op": "trim_end", "clip": 3, "to": M}),
            json!({"op": "trim_end", "clip": 3, "to": M + FRAME}),
            "clip 3.end",
            M + FRAME,
        ),
        (
            "duplicate",
            &generated,
            json!({"op": "duplicate", "clips": [3]}),
            json!({"op": "duplicate", "clips": [3]}),
            "clip 10.end",
            M + FRAME,
        ),
        (
            "speed",
            &media,
            json!({"op": "set_speed", "clip": 3, "rate": 2.0}),
            json!({"op": "set_speed", "clip": 3, "rate": 0.1}),
            "clip 3.end",
            M + 17 * FRAME,
        ),
        (
            "rate_stretch",
            &media,
            json!({"op": "rate_stretch", "clip": 3,
                                        "to_end": M}),
            json!({"op": "rate_stretch", "clip": 3, "to_end": M + FRAME}),
            "clip 3.end",
            M + FRAME,
        ),
        (
            "freeze",
            &media,
            json!({"op": "freeze_frame", "clip": 3,
                                  "at": M - 2 * FRAME, "duration": FRAME}),
            json!({"op": "freeze_frame", "clip": 3,
                "at": M - 2 * FRAME, "duration": 3 * FRAME}),
            "clip 10.start",
            M + FRAME,
        ),
    ];
    for (label, handle, control, crossing, path, value) in cases {
        if label != "duplicate" {
            assert!(
                assert_safe(&format!("{label} control"), handle, &control),
                "{label} control must apply"
            );
        }
        assert_boundary_error(
            &format!("{label} crossing"),
            handle,
            &crossing,
            path,
            value.into(),
        );
    }
    let mut duplicate_control = generated.value();
    duplicate_control["clips"][0]["start"] = json!(M - 5 * FRAME);
    let control = Handle::from_value(&duplicate_control);
    assert!(assert_safe(
        "duplicate admitted control",
        &control,
        &json!({"op": "duplicate", "clips": [3]})
    ));
    assert_eq!(
        generated.errors(&json!({"op": "move_clip", "clips": [3], "delta": 2 * FRAME})),
        format!(
            "clip 3.end must be between -{M} and {M} ticks, not {}",
            M + FRAME
        )
    );
}

#[test]
fn constructors_paste_actions_and_markers_share_admission() {
    let empty = empty();
    let payload = json!({"clips": [{"id": 100, "track": 0, "start": 0,
                                     "duration": 2 * FRAME,
                                     "source": {"kind": "text"}}], "media": []});
    let cases = [
        (
            "text",
            json!({"op": "add_text_clip", "track": 1, "at": M - 2 * FRAME,
                        "duration": 2 * FRAME, "text": {"content": "x"}}),
            json!({"op": "add_text_clip", "track": 1, "at": M - FRAME,
                "duration": 2 * FRAME, "text": {"content": "x"}}),
            "clip 10.end",
            M + FRAME,
        ),
        (
            "shape",
            json!({"op": "add_shape_clip", "track": 1, "at": M - 2 * FRAME,
                         "duration": 2 * FRAME}),
            json!({"op": "add_shape_clip", "track": 1, "at": M - FRAME,
                "duration": 2 * FRAME}),
            "clip 10.end",
            M + FRAME,
        ),
        (
            "clip",
            json!({"op": "add_clip", "track": 1, "media": 2, "at": 0}),
            json!({"op": "add_clip", "track": 1, "media": 2, "at": M - FRAME}),
            "clip 10.end",
            2 * M - FRAME,
        ),
        (
            "background",
            json!({"op": "add_background", "duration": M}),
            json!({"op": "add_background", "duration": M + FRAME}),
            "clip 11.duration",
            M + FRAME,
        ),
        (
            "paste",
            json!({"op": "paste", "at": M - 2 * FRAME,
                         "payload": payload}),
            json!({"op": "paste", "at": M - FRAME, "payload": payload}),
            "clip 10.end",
            M + FRAME,
        ),
        (
            "marker",
            json!({"op": "add_marker", "at": M}),
            json!({"op": "add_marker", "at": M + FRAME}),
            "marker 10.time",
            M + FRAME,
        ),
    ];
    for (label, control, crossing, path, value) in cases {
        assert!(
            assert_safe(&format!("{label} control"), &empty, &control),
            "{label} control must apply"
        );
        assert_boundary_error(
            &format!("{label} crossing"),
            &empty,
            &crossing,
            path,
            value.into(),
        );
    }

    let target = Handle::from_value(&json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 1}],
        "clips": [{"id": 3, "track": 1, "start": 0, "duration": M,
                   "source": {"kind": "text"}, "video": {}}],
        "next_id": 4
    }));
    assert!(assert_safe(
        "action admitted control",
        &target,
        &json!({"op": "add_action", "clip": 3, "at": M - FRAME, "duration": FRAME}),
    ));
    let action_refusal = format!(
        "an action of {} ticks at {} would end at {}, past clip 3's own end at {M} ticks",
        2 * FRAME,
        M - FRAME,
        M + FRAME
    );
    for (label, op) in [
        (
            "action crossing",
            json!({"op": "add_action", "clip": 3,
                                    "at": M - FRAME, "duration": 2 * FRAME}),
        ),
        (
            "zoom crossing",
            json!({"op": "add_zoom_action", "clip": 3,
                                  "at": M - FRAME, "duration": 2 * FRAME}),
        ),
    ] {
        assert_boundary_refusal(label, &target, &op, &action_refusal);
    }
    assert!(assert_safe(
        "fps at cap",
        &target,
        &json!({"op": "set_canvas", "fps": [7, 1]})
    ));
    let fps_control = near(json!({"kind": "text"}));
    assert!(assert_safe(
        "fps resnap control",
        &fps_control,
        &json!({"op": "set_canvas", "fps": [7, 1]}),
    ));
}

#[test]
fn media_descriptor_itself_is_admitted() {
    let empty = Handle::new(1920, 1080, 30, 1);
    let descriptor = |duration| {
        json!({"op": "add_media", "descriptor": {
            "path": "/missing.mov", "kind": "video", "duration": duration,
            "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true
        }})
    };
    assert!(assert_safe("media control", &empty, &descriptor(M)));
    assert_boundary_error(
        "media crossing",
        &empty,
        &descriptor(M + 1),
        "media 2.duration",
        i128::from(M + 1),
    );
}

#[test]
fn insert_overwrite_paste_and_nest_boundaries() {
    let empty = empty();
    for name in ["insert_clip", "overwrite_clip"] {
        assert!(assert_safe(
            name,
            &empty,
            &json!({"op": name, "track": 1, "media": 2, "at": 0})
        ));
        assert_boundary_error(
            name,
            &empty,
            &json!({"op": name, "track": 1, "media": 2, "at": M - FRAME}),
            "clip 10.end",
            i128::from(2 * M - FRAME),
        );
    }
    let nested_payload = |duration| {
        json!({
            "clips": [{"id": 100, "track": 0, "start": 0, "duration": FRAME,
                       "source": {"kind": "nest", "project": 101}}],
            "media": [],
            "nests": [{"id": 101, "tracks": [{"id": 102}],
                       "clips": [{"id": 103, "track": 102, "start": 0,
                                  "duration": duration, "source": {"kind": "text"}}]}]
        })
    };
    assert!(assert_safe(
        "paste absorbed nest control",
        &empty,
        &json!({"op": "paste", "at": 0,
                                "payload": nested_payload(M)})
    ));
    assert_boundary_error(
        "paste absorbed nest crossing",
        &empty,
        &json!({"op": "paste", "at": 0,
                        "payload": nested_payload(M + FRAME)}),
        "clip 12 in nest 10.duration",
        i128::from(M + FRAME),
    );

    let nest = Handle::from_value(&json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 1}],
        "clips": [{"id": 3, "track": 1, "start": M - 2 * FRAME,
                   "duration": 2 * FRAME,
                   "source": {"kind": "nest", "project": 4}}],
        "nests": [{"id": 4, "tracks": [{"id": 5}],
                   "clips": [{"id": 6, "track": 5, "start": FRAME,
                              "duration": 2 * FRAME,
                              "source": {"kind": "text"}}]}],
        "next_id": 7
    }));
    assert_boundary_error(
        "unnest crossing",
        &nest,
        &json!({"op": "unnest", "clip": 3}),
        "clip 7.end",
        i128::from(M + FRAME),
    );
    let mut allowed = nest.value();
    allowed["nests"][0]["clips"][0]["start"] = json!(0);
    let allowed = Handle::from_value(&allowed);
    assert!(assert_safe(
        "unnest admitted control",
        &allowed,
        &json!({"op": "unnest", "clip": 3})
    ));
    let scoped = json!({"op": "move_clip", "clips": [6], "delta": M - 3 * FRAME,
                        "scope": 4});
    assert!(assert_safe("scoped control", &nest, &scoped));
    assert_boundary_error(
        "scoped crossing",
        &nest,
        &json!({"op": "move_clip", "clips": [6],
                        "delta": M - FRAME, "scope": 4}),
        "clip 6.end",
        i128::from(M + 2 * FRAME),
    );
}

#[test]
fn action_retime_and_marker_retime_are_admitted() {
    let mut project = near(json!({"kind": "text"})).value();
    project["clips"][0]["start"] = json!(0);
    project["clips"][0]["duration"] = json!(M);
    project["clips"][0]["actions"] = json!([{
        "id": 11, "start": 0, "duration": FRAME, "end": {}
    }]);
    project["markers"] = json!([{"id": 12, "time": 0}]);
    project["next_id"] = json!(13);
    let handle = Handle::from_value(&project);
    assert!(assert_safe(
        "action retime control",
        &handle,
        &json!({"op": "set_action", "clip": 3, "action": 11,
                        "start": M - FRAME, "duration": FRAME}),
    ));
    assert_boundary_refusal(
        "action retime crossing",
        &handle,
        &json!({"op": "set_action", "clip": 3, "action": 11,
                        "start": M - FRAME, "duration": 2 * FRAME}),
        &format!(
            "an action of {} ticks at {} would end at {}, past clip 3's own end at {M} ticks",
            2 * FRAME,
            M - FRAME,
            M + FRAME
        ),
    );
    assert!(assert_safe(
        "marker retime control",
        &handle,
        &json!({"op": "set_marker", "marker": 12, "time": M}),
    ));
    assert_boundary_error(
        "marker retime crossing",
        &handle,
        &json!({"op": "set_marker", "marker": 12, "time": M + FRAME}),
        "marker 12.time",
        i128::from(M + FRAME),
    );
}
