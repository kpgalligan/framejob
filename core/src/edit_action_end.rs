//! `set_action_end`'s END patch door, moved whole out of `edit_action.rs`
//! (road map "creator-jobs" CO2a1's toll, a pure move): [`check_end_patch`],
//! the walk of an end patch's three groups; [`not_a_target`], the keys an
//! action may not animate; [`prune_removed`], a `null`'s removal from the
//! stored end; and `off` (spec §11 CI-14) — [`check_off`] reading its paths
//! and [`key_off`] writing each one's `null`. `edit_action.rs` composes them
//! in `set_action_end`; `END_PATCH` is also `edit_action_graphic.rs`'s.

use serde_json::{json, Map, Value};

use crate::actions::MAX_PATCH_DEPTH;
use crate::edit_action_graphic::GRAPHIC_NOT_KEYED_OFF;
use crate::model::{AudioProps, ShapeProps, TextProps, VideoProps};
use crate::patch::{check_group_patch, merge_group, unknown_key, Group};

/// Removes from `value` every key the incoming `patch` set to `null` —
/// `set_action_end`'s delete rule (spec §6). Only keys the patch mentions
/// are touched, so a `null` that was already in the end patch (animating a
/// shadow away, say) survives untouched. `shift_remove`, because under
/// `preserve_order` `Map::remove` swaps the last key into the hole.
pub(crate) fn prune_removed(value: &mut Value, patch: &Value, depth: u32) {
    let Value::Object(patched) = patch else {
        return;
    };
    let Value::Object(target) = value else {
        return;
    };
    if depth >= MAX_PATCH_DEPTH {
        return;
    }
    for (key, sub) in patched {
        if sub.is_null() {
            target.shift_remove(key);
        } else if let Some(slot) = target.get_mut(key) {
            prune_removed(slot, sub, depth + 1);
        }
    }
}

/// What a refusal calls this op's patch. It is not one group's — the paths
/// inside it carry the group's name (`video.filters[1].kind`) — so it
/// cannot be a `Group`'s own subject.
pub(crate) const END_PATCH: &str = "an action end patch";

/// The groups §5.4's end patch may name. `shape` is not among them, and its
/// absence is a refusal rather than an omission: `evaluate_clip` passes a
/// clip's shape through untouched, so the key would be stored, reported as
/// success and animate nothing.
const END_GROUPS: [Group; 3] = [Group::Video, Group::Audio, Group::Text];

/// Walks an end patch's keys, kinds and values the way every other patch
/// is walked (`patch.rs`'s `check_group_patch`), group by group, and
/// refuses by the dotted path.
///
/// What belongs to THIS door rather than to a property group, and is why
/// the walk is composed here rather than called:
///
/// - **Three groups and no fourth.** Spec §5.4's patch is a subset of
///   `video`, `audio` and `text`. `shape` is refused rather than kept,
///   because `evaluate_clip` passes a clip's shape through untouched: the
///   key would be stored, reported as success, and animate nothing.
/// - **A `null` is a REMOVAL at every depth**, not a clear. The walk sees
///   it (so `{"video": {"blurr": null}}` is still an unknown key) and the
///   typed read does not (so `{"video": {"crop": null}}` is "stop animating
///   the crop" rather than a required field being cleared) —
///   `check_group_patch` is where that split lives, and [`prune_removed`]
///   below applies the same rule to the STORED end state.
pub(crate) fn check_end_patch(patch: &Value) -> Result<(), String> {
    let Value::Object(groups) = patch else {
        return Ok(());
    };
    for (key, body) in groups {
        // `graphic` is `edit_action_graphic.rs`'s arm and `speed`
        // `edit_action_speed.rs`'s, each read after this walk.
        if key == "graphic" || key == "speed" {
            continue;
        }
        // The three groups, by their own names rather than by three string
        // literals: a group renamed in `patch.rs` cannot drift from the
        // door that lists it.
        let group = END_GROUPS
            .into_iter()
            .find(|group| group.name() == key)
            .ok_or_else(|| unknown_key(key, END_PATCH))?;
        // A group set to `null` removes the whole group from the end state,
        // which is the same removal one key deep.
        if body.is_null() {
            continue;
        }
        check_group_patch(body, group, END_PATCH, key)?;
    }
    Ok(())
}

/// The two refusals that are about this op rather than the vocabulary,
/// asked of a group and a key wherever they came from — a `patch`'s keys
/// and an `off` path go through the same two sentences. The third arm is
/// `off`'s alone: a cutout's presence is the clip's own (spec §11 CO-20),
/// so an end may not take it away; a `patch` naming `video.cutout` is
/// [`check_cutout_end`]'s.
pub(crate) fn not_a_target(group: &str, key: &str) -> Result<(), String> {
    match (group, key) {
        ("video", "motion") => Err("video.motion is not an animation target".to_string()),
        ("text", "words") => Err("text.words is not an animation target".to_string()),
        ("video", "cutout") => Err("video.cutout cannot be keyed off at an action's end; \
                                    set_video {cutout: null} removes it"
            .to_string()),
        _ => Ok(()),
    }
}

/// A `patch`'s `video.cutout` naming `subject` or `quality` — a `null`
/// included, `subject` asked first — refused by name (spec §11 CO-20): which
/// subject and which masks are the clip's own, and the evaluator restores
/// the base's over any end (`cutout_check.rs`'s `restore_base_cutout`).
/// `edge`, `feather` and `background` pass; anything that is not an object
/// is the walk's to judge.
pub(crate) fn check_cutout_end(patch: &Value) -> Result<(), String> {
    let Some(Value::Object(cutout)) = patch.get("video").and_then(|video| video.get("cutout"))
    else {
        return Ok(());
    };
    for key in ["subject", "quality"] {
        if cutout.contains_key(key) {
            return Err(format!("video.cutout.{key} is not an animation target"));
        }
    }
    Ok(())
}

/// The EQ's seven slots, the one group whose slot `off` may name (AU-88).
#[rustfmt::skip]
const EQ_SLOTS: [&str; 7] =
    ["high_pass", "low_shelf", "band_1", "band_2", "band_3", "high_shelf", "low_pass"];

/// One `off` path: `group.key`, or `audio.eq.<slot>` with its `slot`.
pub(crate) struct OffPath<'a> {
    group: &'a str,
    key: &'a str,
    slot: Option<&'a str>,
}

/// Reads `set_action_end`'s `off` list (spec §11 CI-14) into its paths,
/// refusing in this order: a path that is not `group.key` or
/// `audio.eq.<slot>` (AU-88; an unknown slot named against the seven), a
/// group an end patch may not name, `video.motion`, `text.words` and
/// `video.cutout` (spec §11 CO-20), a path
/// `patch` also names, and whatever the group's read says of a `null` there
/// — an unknown key, a REQUIRED key (`video.opacity`).
pub(crate) fn check_off<'a>(patch: &Value, off: &'a [String]) -> Result<Vec<OffPath<'a>>, String> {
    let mut paths = Vec::with_capacity(off.len());
    for path in off {
        let parts: Vec<&str> = path.split('.').collect();
        let (group_name, key, slot) = match parts.as_slice() {
            [g, k] if !g.is_empty() && !k.is_empty() => (*g, *k, None),
            ["audio", "eq", slot] if EQ_SLOTS.contains(slot) => ("audio", "eq", Some(*slot)),
            ["audio", "eq", slot] => {
                return Err(format!(
                    "off path \"{path}\" names no EQ slot: \"{slot}\" is not one of {}",
                    EQ_SLOTS.join(", ")
                ))
            }
            _ => {
                return Err(format!(
                    "off path \"{path}\" must be \"group.key\", a group of video, audio or \
                     text and one of its top-level keys"
                ))
            }
        };
        if group_name == "graphic" {
            return Err(GRAPHIC_NOT_KEYED_OFF.to_string());
        }
        let group = END_GROUPS
            .into_iter()
            .find(|group| group.name() == group_name)
            .ok_or_else(|| unknown_key(group_name, END_PATCH))?;
        not_a_target(group_name, key)?;
        let named = patch.get(group_name).and_then(|body| body.get(key));
        if slot
            .map_or(named, |slot| named.and_then(|eq| eq.get(slot)))
            .is_some()
        {
            return Err(format!(
                "\"{path}\" is named in both the patch and off; an end state cannot both \
                 hold it and key it off"
            ));
        }
        let probe = slot.map_or(json!({ key: null }), |slot| json!({ key: { slot: null } }));
        let read = match group {
            Group::Video => merge_group(&VideoProps::default(), &probe, group).map(|_| ()),
            Group::Audio => merge_group(&AudioProps::default(), &probe, group).map(|_| ()),
            Group::Text => merge_group(&TextProps::default(), &probe, group).map(|_| ()),
            Group::Shape => merge_group(&ShapeProps::default(), &probe, group).map(|_| ()),
        };
        read.map_err(|why| format!("cannot key \"{path}\" off: {why}"))?;
        paths.push(OffPath {
            group: group_name,
            key,
            slot,
        });
    }
    Ok(paths)
}

/// The object at `key` of `map`, made `{}` when absent or not an object.
fn object_at<'v>(map: &'v mut Map<String, Value>, key: &str) -> Option<&'v mut Map<String, Value>> {
    let slot = map
        .entry(key.to_string())
        .or_insert_with(|| Value::Object(Map::new()));
    if !slot.is_object() {
        *slot = Value::Object(Map::new());
    }
    slot.as_object_mut()
}

/// Writes `null` at `group.key` of an end state, or at `audio.eq.<slot>`
/// (AU-88) — the property keyed OFF. A group or `eq` slot that is not an
/// object (`end` is stored as the file had it) is replaced by `{}`.
pub(crate) fn key_off(end: &mut Value, path: &OffPath<'_>) {
    let Value::Object(groups) = end else {
        return;
    };
    let Some(fields) = object_at(groups, path.group) else {
        return;
    };
    let (target, key) = match path.slot {
        Some(slot) => (object_at(fields, path.key), slot),
        None => (Some(fields), path.key),
    };
    if let Some(target) = target {
        target.insert(key.to_string(), Value::Null);
    }
}
