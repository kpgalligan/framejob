//! Independent structural-time assertions for the FFI edit boundary tests.

use super::common::{Handle, Outcome};
use serde_json::Value;

const LIMIT: i128 = 9_000_000_000_000_000;

fn tick(value: &Value, context: &str) -> i128 {
    let n = i128::from(
        value
            .as_i64()
            .unwrap_or_else(|| panic!("{context}: missing tick")),
    );
    assert!(
        (-LIMIT..=LIMIT).contains(&n),
        "{context}: {n} outside ±{LIMIT}"
    );
    n
}

fn clips(clips: &Value, context: &str) {
    for clip in clips.as_array().expect("clips array") {
        let id = clip["id"].as_u64().expect("clip id");
        let label = format!("{context} clip {id}");
        let start = tick(&clip["start"], &format!("{label}.start"));
        let duration = tick(&clip["duration"], &format!("{label}.duration"));
        let end = start + duration;
        assert!(
            (-LIMIT..=LIMIT).contains(&end),
            "{label}.end: {end} outside ±{LIMIT}"
        );
        if let Some(source) = clip.get("source") {
            for field in ["in", "at"] {
                if let Some(value) = source.get(field) {
                    tick(value, &format!("{label}.source.{field}"));
                }
            }
        }
        if let Some(actions) = clip.get("actions") {
            for action in actions.as_array().expect("actions array") {
                let action_id = action["id"].as_u64().expect("action id");
                let label = format!("{label}.action {action_id}");
                let start = tick(&action["start"], &format!("{label}.start"));
                let duration = tick(&action["duration"], &format!("{label}.duration"));
                let end = start + duration;
                assert!(
                    (-LIMIT..=LIMIT).contains(&end),
                    "{label}.end: {end} outside ±{LIMIT}"
                );
            }
        }
    }
}

/// Checks the JSON structure directly; it does not call the core validator
/// or reopen the same handle, so omitting admission cannot make it pass.
pub(super) fn assert_structural_times(project: &Value) {
    if let Some(media) = project.get("media") {
        for item in media.as_array().expect("media array") {
            let id = item["id"].as_u64().expect("media id");
            tick(&item["duration"], &format!("media {id}.duration"));
        }
    }
    if let Some(markers) = project.get("markers") {
        for marker in markers.as_array().expect("markers array") {
            let id = marker["id"].as_u64().expect("marker id");
            tick(&marker["time"], &format!("marker {id}.time"));
        }
    }
    if let Some(top) = project.get("clips") {
        clips(top, "top-level");
    }
    if let Some(nests) = project.get("nests") {
        for nest in nests.as_array().expect("nests array") {
            let id = nest["id"].as_u64().expect("nest id");
            clips(&nest["clips"], &format!("nest {id}"));
        }
    }
}

pub(super) fn assert_safe(label: &str, handle: &Handle, op: &Value) -> bool {
    let before = handle.to_json();
    let applied = match handle.try_apply(op) {
        Ok(Outcome::Applied(next)) => {
            let text = next.to_json();
            Handle::from_json(&text);
            assert_structural_times(&next.value());
            true
        }
        Ok(Outcome::Identity | Outcome::Refused(_)) => false,
        Err(message) => {
            assert!(
                !message.starts_with("internal error:"),
                "{label}: {message}"
            );
            false
        }
    };
    assert_eq!(handle.to_json(), before, "{label} changed the old handle");
    applied
}

pub(super) fn assert_boundary_error(
    label: &str,
    handle: &Handle,
    op: &Value,
    path: &str,
    value: i128,
) {
    let before = handle.to_json();
    let expected = format!("{path} must be between -{LIMIT} and {LIMIT} ticks, not {value}");
    assert_eq!(handle.try_apply(op).unwrap_err(), expected, "{label}");
    assert_eq!(handle.to_json(), before, "{label} changed the old handle");
}

pub(super) fn assert_boundary_refusal(label: &str, handle: &Handle, op: &Value, expected: &str) {
    let before = handle.to_json();
    match handle.try_apply(op).unwrap() {
        Outcome::Refused(why) => assert_eq!(why, expected, "{label}"),
        other => panic!("{label}: expected refusal, got {other:?}"),
    }
    assert_eq!(handle.to_json(), before, "{label} changed the old handle");
}
