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
//! One asymmetry is deliberate and worth stating: an action's `end` patch is
//! LENIENT where `set_video` and its siblings are strict. `set_action_end`
//! merges whatever it is given and keeps keys it does not know, because a
//! half-written animation must stay editable and a project from a newer
//! build must survive a round trip through this one. The evaluator is the
//! line of defence instead — it clamps every value it produces (spec §5.4).

use serde_json::Value;

use crate::actions::{self, MAX_PATCH_DEPTH};
use crate::export::describe;
use crate::model::{Action, Curve, Project};
use crate::time::{Ticks, TIMESCALE};

/// Default duration for `add_action`: one second of animation, the length
/// the Actions table offers before the user drags either edge.
const DEFAULT_ACTION_DURATION: Ticks = TIMESCALE;

/// Whether `[start, start+duration)` touches any action on the clip other
/// than `skip` (the action being edited). Actions on a clip may not overlap
/// (spec §5.4); this is the test both `add_action` and `set_action` refuse
/// on.
fn actions_overlap(actions: &[Action], skip: Option<u32>, start: Ticks, duration: Ticks) -> bool {
    let end = start.saturating_add(duration);
    actions
        .iter()
        .filter(|a| Some(a.id) != skip)
        .any(|a| start < a.start.saturating_add(a.duration) && a.start < end)
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

impl Project {
    // ---- actions ---------------------------------------------------------

    /// Adds an action to the clip at CLIP time `at` — the caller converts
    /// the playhead by subtracting the clip's start — one second long by
    /// default, with an empty end patch, so it changes nothing until the
    /// inspector edits it (spec §6).
    ///
    /// Refuses (`None`) when it would overlap another action on the clip or
    /// run past the clip's end. `Err` on a negative start or a non-positive
    /// duration.
    pub fn add_action(
        &self,
        clip: u32,
        at: Ticks,
        duration: Option<Ticks>,
    ) -> Result<Option<Project>, String> {
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
            return Ok(None);
        }
        if actions_overlap(&target.actions, None, at, duration) {
            return Ok(None);
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
    ) -> Result<Option<Project>, String> {
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
            return Ok(None);
        }
        if actions_overlap(&target.actions, Some(action), new_start, new_duration) {
            return Ok(None);
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
    /// Unknown keys are kept, not rejected: an end patch is evaluated
    /// leniently (`actions.rs`), and a project written by a newer build
    /// must survive a round trip through this one.
    pub fn set_action_end(
        &self,
        clip: u32,
        action: u32,
        patch: &Value,
    ) -> Result<Option<Project>, String> {
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
    pub fn remove_action(&self, clip: u32, action: u32) -> Result<Option<Project>, String> {
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
