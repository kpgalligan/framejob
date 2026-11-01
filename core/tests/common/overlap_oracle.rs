//! THE overlap rule's half-shorter limit, written as the tests' own oracle
//! rather than read from the core: for every two distinct clips of
//! `project["clips"]` on one track, the time both cover is at most half of
//! the shorter clip (integer halving, as the rule truncates).
//!
//! `serde_json` only and no `super::` import, so any test binary may
//! include it by `#[path]` without dragging another file's `#[test]`s in.

use serde_json::Value;

fn tick(clip: &Value, key: &str) -> i64 {
    clip[key]
        .as_i64()
        .unwrap_or_else(|| panic!("clip {} has no {key}", clip["id"]))
}

/// True when no two clips on one track overlap by more than half of the
/// shorter one. Pairs that do not meet answer a negative overlap and pass.
pub fn overlap_rule_holds(project: &Value) -> bool {
    let empty = Vec::new();
    let clips = project["clips"].as_array().unwrap_or(&empty);
    for a in clips {
        for b in clips {
            if a["id"] == b["id"] || a["track"] != b["track"] {
                continue;
            }
            let (a_start, a_len) = (tick(a, "start"), tick(a, "duration"));
            let (b_start, b_len) = (tick(b, "start"), tick(b, "duration"));
            let overlap = (a_start + a_len).min(b_start + b_len) - a_start.max(b_start);
            if overlap > a_len.min(b_len) / 2 {
                return false;
            }
        }
    }
    true
}
