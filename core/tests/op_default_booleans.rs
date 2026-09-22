//! Four optional plain booleans default to false; nullable controls do not.
mod common;

use common::{Handle, Outcome};
use serde_json::{json, Value};

fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 8, "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
        "media": [{"id": 2, "path": "/fixtures/booleans.mov", "kind": "video",
            "duration": 6_000_000, "width": 640, "height": 360, "fps": [30, 1],
            "has_video": true, "has_audio": true}],
        "tracks": [{"id": 1, "name": "A"}, {"id": 3, "name": "B"}],
        "clips": [
            {"id": 10, "track": 1, "start": 0, "duration": 600_000,
                "source": {"kind": "media", "media": 2, "in": 1_000_000},
                "video": {"x": 100.0, "y": 50.0, "scale": 0.5}, "audio": {}},
            {"id": 11, "track": 1, "start": 600_000, "duration": 600_000,
                "source": {"kind": "media", "media": 2, "in": 2_000_000},
                "video": {}, "audio": {}}
        ], "markers": [], "nests": [], "next_id": 30
    }))
}

fn answer(handle: &Handle, op: &Value) -> String {
    match handle.try_apply(op) {
        Ok(Outcome::Applied(next)) => format!("applied:{}", next.value()),
        Ok(Outcome::Identity) => "identity".to_owned(),
        Ok(Outcome::Refused(reason)) => format!("refused:{reason}"),
        Err(error) => format!("error:{error}"),
    }
}

fn absent_false_null(base: Value, field: &str) -> (Handle, String) {
    let before = project();
    let original = before.to_json();
    let omitted = answer(&before, &base);
    let mut explicit = base.clone();
    explicit[field] = json!(false);
    assert_eq!(
        answer(&before, &explicit),
        omitted,
        "{field}: false differs from omission"
    );
    explicit[field] = Value::Null;
    let error = before.try_apply(&explicit).unwrap_err();
    assert!(
        error.starts_with(&format!(
            "op \"{}\" is not valid: ",
            base["op"].as_str().unwrap()
        )),
        "{error}"
    );
    assert_eq!(before.to_json(), original, "{field}: input handle changed");
    (before, omitted)
}

#[test]
fn ripple_changes_placement_but_omission_means_handle_mode() {
    let (before, default) = absent_false_null(
        json!({"op":"add_transition","clip":11,"duration":200_000}),
        "ripple",
    );
    assert!(default.starts_with("applied:"), "{default}");
    let normal = before
        .apply(&json!({"op":"add_transition","clip":11,"duration":200_000}))
        .value();
    assert_eq!(normal.pointer("/clips/1/start"), Some(&json!(500_000)));
    assert_eq!(normal.pointer("/clips/0/duration"), Some(&json!(700_000)));
    let ripple = before
        .apply(&json!({"op":"add_transition","clip":11,"duration":200_000,"ripple":true}))
        .value();
    assert_eq!(ripple.pointer("/clips/1/start"), Some(&json!(400_000)));
    assert_eq!(ripple.pointer("/clips/0/duration"), Some(&json!(600_000)));
}

#[test]
fn with_clips_controls_occupied_track_and_used_media_removal() {
    let (before, track_default) =
        absent_false_null(json!({"op":"remove_track","track":1}), "with_clips");
    assert_eq!(track_default, "refused:track 1 still holds clips 10 and 11; pass with_clips: true to remove the track and its clips");
    let removed = before
        .apply(&json!({"op":"remove_track","track":1,"with_clips":true}))
        .value();
    assert_eq!(removed["clips"], json!([]));
    assert_eq!(removed["tracks"].as_array().unwrap().len(), 1);

    let (before, media_default) =
        absent_false_null(json!({"op":"remove_media","media":2}), "with_clips");
    assert_eq!(media_default, "refused:media 2 is still used by clips 10 and 11; pass with_clips: true to remove the media and its clips");
    let removed = before
        .apply(&json!({"op":"remove_media","media":2,"with_clips":true}))
        .value();
    assert_eq!(removed["clips"], json!([]));
    assert_eq!(removed["media"], json!([]));
}

#[test]
fn rescale_clips_controls_existing_transform() {
    let base = json!({"op":"set_canvas","width":320,"height":180});
    let (before, default) = absent_false_null(base.clone(), "rescale_clips");
    assert!(default.starts_with("applied:"), "{default}");
    let plain = before.apply(&base).value();
    assert_eq!(plain.pointer("/clips/0/video/x"), Some(&json!(100.0)));
    assert_eq!(plain.pointer("/clips/0/video/scale"), Some(&json!(0.5)));
    let resized = before
        .apply(&json!({"op":"set_canvas","width":320,"height":180,"rescale_clips":true}))
        .value();
    assert_eq!(resized.pointer("/clips/0/video/x"), Some(&json!(50.0)));
    assert_eq!(resized.pointer("/clips/0/video/scale"), Some(&json!(0.25)));
}

#[test]
fn nullable_boolean_duration_and_enum_have_distinct_value_meaning() {
    let before = project();
    let enabled = json!({"op":"set_enabled","clip":10});
    let mut nulled = enabled.clone();
    nulled["video"] = Value::Null;
    assert_eq!(answer(&before, &enabled), answer(&before, &nulled));
    assert_eq!(answer(&before, &enabled), "identity");
    let off = before
        .apply(&json!({"op":"set_enabled","clip":10,"video":false}))
        .value();
    assert_eq!(off.pointer("/clips/0/enabled/video"), Some(&json!(false)));

    let action = json!({"op":"add_action","clip":10,"at":0});
    let mut nulled = action.clone();
    nulled["duration"] = Value::Null;
    assert_eq!(answer(&before, &action), answer(&before, &nulled));
    let explicit = before
        .apply(&json!({"op":"add_action","clip":10,"at":0,"duration":200_000}))
        .value();
    assert_eq!(
        explicit.pointer("/clips/0/actions/0/duration"),
        Some(&json!(200_000))
    );

    let stored = before.apply(&json!({"op":"set_transition","clip":11,"kind":"wipe"}));
    let clear = json!({"op":"set_transition","clip":11});
    let mut nulled = clear.clone();
    nulled["kind"] = Value::Null;
    assert_eq!(answer(&stored, &clear), answer(&stored, &nulled));
    let changed = stored
        .apply(&json!({"op":"set_transition","clip":11,"kind":"slide"}))
        .value();
    assert_eq!(
        changed.pointer("/clips/1/transition_in/kind"),
        Some(&json!("slide"))
    );
    assert_eq!(
        stored
            .apply(&clear)
            .value()
            .pointer("/clips/1/transition_in"),
        Some(&Value::Null)
    );
}
