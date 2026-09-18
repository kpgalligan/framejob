//! The action ops — spec §6, table "Actions".
//!
//! An action is a span of CLIP time with an end patch: the clip's props
//! interpolate from whatever they are toward that patch across it (spec
//! §5.4). `actions.rs` evaluates them; this file is the four edits that put
//! one on a clip, retime it, change what it animates, and take it off
//! again.
//!
//! Split out of `edit_clip.rs` (which owns placement) because they are a
//! separate concern with one rule of their own — **actions on a clip may
//! not overlap**, and both `add_action` and `set_action` refuse rather than
//! repair, exactly as placement refuses rather than pushes. The lookups,
//! the frame snapping and [`Project::finish`] are `edit_clip.rs`'s
//! `pub(crate)` helpers, called and never restated.
//!
//! One asymmetry is deliberate and worth stating, and D1·2 moved where it
//! falls. An end patch is walked for keys and types like every other patch
//! ([`check_end_patch`], over `patch.rs`'s walk), so a misspelt key here is
//! refused by its path rather than stored and silently ignored; what stays
//! LENIENT is the VALUE, because the state a clip interpolates toward may
//! name something no stored group could hold, and because a half-written
//! animation must stay editable. The evaluator is the line of defence for
//! that — it clamps every value it produces (spec §5.4). The forward
//! compatibility the old leniency was for lives in the FILE reader, which
//! keeps an `end` object exactly as it found it.
//!
//! It has exactly ONE refusal beyond "the patch must be an object", and it
//! is about a key that is not a value at all: `video.motion` (format
//! version 8) names a PRESET anchored to the clip's two ends, not a
//! quantity to ramp between two states, so an action cannot target it and
//! `set_action_end` says so by name. The refusal is a courtesy rather than
//! the enforcement — `evaluate_clip` restores the base motion over whatever
//! any end patch carries, which is what closes a hand-written file, a
//! pasted action and a project from another tool at once.

use serde_json::Value;

use crate::actions::{self, MAX_PATCH_DEPTH};
use crate::export::describe;
use crate::model::{Action, Curve, Project};
use crate::outcome::Outcome;
use crate::patch::{check_group_patch, unknown_key, Group};
use crate::time::{Ticks, TIMESCALE};

/// Default duration for `add_action`: one second of animation, the length
/// the Actions table offers before the user drags either edge.
const DEFAULT_ACTION_DURATION: Ticks = TIMESCALE;

/// Whether `[start, start+duration)` touches any action on the clip other
/// than `skip` (the action being edited). Actions on a clip may not overlap
/// (spec §5.4); this is the test both `add_action` and `set_action` refuse
/// on.
fn actions_overlap(
    actions: &[Action],
    skip: Option<u32>,
    start: Ticks,
    duration: Ticks,
) -> Option<&Action> {
    let end = start.saturating_add(duration);
    actions
        .iter()
        .filter(|a| Some(a.id) != skip)
        .find(|a| start < a.start.saturating_add(a.duration) && a.start < end)
}

/// The two action refusals, written once because `add_action` and
/// `set_action` ask exactly the same two questions of the same numbers
/// (deepening D2·3). Each names the span the caller asked for and the span
/// in its way, which is the pair of numbers a caller needs to pick another
/// one without asking the project again.
fn action_overlaps(clip: u32, other: &Action) -> String {
    format!(
        "action {} on clip {clip} already runs from {} to {} ticks, and two actions on one \
         clip may not overlap",
        other.id,
        other.start,
        other.start.saturating_add(other.duration)
    )
}

fn action_past_end(clip: u32, start: Ticks, duration: Ticks, length: Ticks) -> String {
    format!(
        "an action at {start} ticks for {duration} would end at {}, past clip {clip}'s own \
         end at {length} ticks",
        start.saturating_add(duration)
    )
}

/// Removes from `value` every key the incoming `patch` set to `null` —
/// `set_action_end`'s delete rule (spec §6). Only keys the patch mentions
/// are touched, so a `null` that was already in the end patch (animating a
/// shadow away, say) survives untouched.
fn prune_removed(value: &mut Value, patch: &Value, depth: u32) {
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
            target.remove(key);
        } else if let Some(slot) = target.get_mut(key) {
            prune_removed(slot, sub, depth + 1);
        }
    }
}

/// What a refusal calls this op's patch. It is not one group's — the paths
/// inside it carry the group's name (`video.filters[1].kind`) — so it
/// cannot be a `Group`'s own subject.
const END_PATCH: &str = "an action end patch";

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
fn check_end_patch(patch: &Value) -> Result<(), String> {
    let Value::Object(groups) = patch else {
        return Ok(());
    };
    for (key, body) in groups {
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

impl Project {
    // ---- actions ---------------------------------------------------------

    /// Adds an action to the clip at CLIP time `at` — the caller converts
    /// the playhead by subtracting the clip's start — one second long by
    /// default, with an empty end patch, so it changes nothing until the
    /// inspector edits it (spec §6).
    ///
    /// Refuses when it would overlap another action on the clip
    /// ([`action_overlaps`]) or run past the clip's end
    /// ([`action_past_end`]). `Err` on a negative start or a non-positive
    /// duration.
    pub fn add_action(
        &self,
        clip: u32,
        at: Ticks,
        duration: Option<Ticks>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let at = self.snapped(at);
        if at < 0 {
            return Err(format!("action start must not be negative, not {at}"));
        }
        let duration = match duration {
            None => DEFAULT_ACTION_DURATION,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped <= 0 {
                    return Err(format!("action duration must be positive, not {given}"));
                }
                snapped
            }
        };
        if at.saturating_add(duration) > target.duration {
            return Ok(Outcome::Refused(action_past_end(
                clip,
                at,
                duration,
                target.duration,
            )));
        }
        if let Some(other) = actions_overlap(&target.actions, None, at, duration) {
            return Ok(Outcome::Refused(action_overlaps(clip, other)));
        }

        let mut next = self.clone();
        let id = next.allocate_id();
        if let Some(slot) = next.clip_mut(clip) {
            slot.actions.push(Action {
                id,
                start: at,
                duration,
                curve: Curve::default(),
                end: Value::Object(serde_json::Map::new()),
            });
        }
        self.finish(next)
    }

    /// Retimes or re-curves one action; every argument left `None` keeps
    /// its current value (spec §6). Same overlap and clip-end checks as
    /// `add_action`.
    pub fn set_action(
        &self,
        clip: u32,
        action: u32,
        start: Option<Ticks>,
        duration: Option<Ticks>,
        curve: Option<Curve>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let existing = target
            .actions
            .iter()
            .find(|a| a.id == action)
            .ok_or_else(|| format!("no action with id {action} on clip {clip}"))?
            .clone();

        let new_start = match start {
            None => existing.start,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped < 0 {
                    return Err(format!("action start must not be negative, not {given}"));
                }
                snapped
            }
        };
        let new_duration = match duration {
            None => existing.duration,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped <= 0 {
                    return Err(format!("action duration must be positive, not {given}"));
                }
                snapped
            }
        };
        if new_start.saturating_add(new_duration) > target.duration {
            return Ok(Outcome::Refused(action_past_end(
                clip,
                new_start,
                new_duration,
                target.duration,
            )));
        }
        if let Some(other) = actions_overlap(&target.actions, Some(action), new_start, new_duration)
        {
            return Ok(Outcome::Refused(action_overlaps(clip, other)));
        }

        let mut next = self.clone();
        if let Some(slot) = next
            .clip_mut(clip)
            .and_then(|c| c.actions.iter_mut().find(|a| a.id == action))
        {
            slot.start = new_start;
            slot.duration = new_duration;
            if let Some(curve) = curve {
                slot.curve = curve;
            }
        }
        self.finish(next)
    }

    /// Merges `patch` into the action's end state; a key set to `null`
    /// REMOVES it, which is how the inspector stops animating one property
    /// without deleting the action (spec §6).
    ///
    /// The patch is walked like every other one (`patch.rs`'s
    /// `check_end_patch`): an unknown key, a value of the wrong JSON kind
    /// and a misspelt variant are each refused, naming the dotted path with
    /// the group's name in it and the value sent. What it does NOT do is
    /// range-check — the state a clip interpolates toward may legitimately
    /// name a value no stored group could hold, and `actions.rs`'s
    /// `clamp_video` bounds the evaluated value instead (spec §5.4).
    ///
    /// A `null` is the one value the walk lets past at any depth, because
    /// here it is a REMOVAL rather than a clear.
    ///
    /// The refusal that is about this op rather than about the vocabulary:
    /// a `video` object naming `motion` is an `Err`. A preset is anchored to
    /// the clip's two ends and an action is a ramp between two states, so
    /// there is nothing to interpolate — half a slide into half a spin is
    /// not a picture anybody asked for — and the evaluator would put the
    /// base value back anyway, leaving a control that reported success and
    /// did nothing.
    pub fn set_action_end(&self, clip: u32, action: u32, patch: &Value) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?;
        let existing = target
            .actions
            .iter()
            .find(|a| a.id == action)
            .ok_or_else(|| format!("no action with id {action} on clip {clip}"))?;
        if !patch.is_object() {
            return Err(format!(
                "action end patch must be a json object, not {}",
                describe(patch)
            ));
        }
        // Present at all — a `null` included, since writing `motion: null`
        // into an end patch is still asking an action to decide a preset.
        if patch
            .get("video")
            .and_then(|video| video.get("motion"))
            .is_some()
        {
            return Err("video.motion is not an animation target".to_string());
        }
        check_end_patch(patch)?;
        let mut merged = actions::merge(&existing.end, patch);
        prune_removed(&mut merged, patch, 0);

        let mut next = self.clone();
        if let Some(slot) = next
            .clip_mut(clip)
            .and_then(|c| c.actions.iter_mut().find(|a| a.id == action))
        {
            slot.end = merged;
        }
        self.finish(next)
    }

    /// Removes one action from a clip (spec §6).
    pub fn remove_action(&self, clip: u32, action: u32) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?;
        if !target.actions.iter().any(|a| a.id == action) {
            return Err(format!("no action with id {action} on clip {clip}"));
        }
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.actions.retain(|a| a.id != action);
        }
        self.finish(next)
    }
}
