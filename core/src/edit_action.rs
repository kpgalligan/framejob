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
//! that — it clamps every value it produces (spec §5.4). The one exception
//! is a graphic prop's end (spec §11 G-34 (c)), checked against the op's
//! `schema`: nothing clamps a prop, and a curve between two in-range ends
//! stays in range. The forward
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
//! pasted action and a project from another tool at once. A `graphic`
//! group in `patch` is `edit_action_graphic.rs`'s arm (spec §11 G-34); in
//! `off` it is an `Err`.

use serde_json::Value;

use crate::actions;
use crate::edit_action_end::{
    check_cutout_end, check_end_patch, check_off, key_off, not_a_target, prune_removed,
};
use crate::edit_action_graphic::{read_graphic_end, write_graphic_end};
use crate::edit_action_speed::read_speed_end;
use crate::export::describe;
use crate::model::{Action, Curve, Project};
use crate::model_graphic::{check_count, check_schema};
use crate::outcome::Outcome;
use crate::speed_map::end_speed;
use crate::time::{Ticks, TIMESCALE};

/// Default duration for `add_action`: one second of animation, the length
/// the Actions table offers before the user drags either edge.
const DEFAULT_ACTION_DURATION: Ticks = TIMESCALE;

/// The action on the clip, other than `skip` (the one being edited), that
/// `[start, start+duration)` runs into — `None` when the span is free.
/// Actions on a clip may not overlap (spec §5.4); this is the question both
/// `add_action` and `set_action` refuse on, and it answers the offender
/// rather than a yes, because the refusal names it.
pub(crate) fn overlapping_action(
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
pub(crate) fn action_overlaps(clip: u32, other: &Action) -> String {
    format!(
        "action {} on clip {clip} already runs from {} to {} ticks, and two actions on one \
         clip may not overlap",
        other.id,
        other.start,
        other.start.saturating_add(other.duration)
    )
}

pub(crate) fn action_past_end(clip: u32, start: Ticks, duration: Ticks, length: Ticks) -> String {
    format!(
        "an action of {duration} ticks at {start} would end at {}, past clip {clip}'s own \
         end at {length} ticks",
        start.saturating_add(duration)
    )
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
        let given = at;
        let at = self.snapped(at);
        if at < 0 {
            return Err(format!("action start must not be negative, not {given}"));
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
        if let Some(other) = overlapping_action(&target.actions, None, at, duration) {
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
    /// its current value (spec §6). The same overlap check as `add_action`;
    /// the clip-end check refuses ([`action_past_end`]) only an edit that
    /// ends the action past the clip's end AND later than it ended before
    /// (spec §11 SR-22, #338), so an action already running past the end —
    /// a trim or a ramp scale leaves one there — can be re-curved, moved
    /// earlier or shortened, and one inside the clip still cannot be pushed
    /// past it.
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
        let new_end = new_start.saturating_add(new_duration);
        let old_end = existing.start.saturating_add(existing.duration);
        if new_end > target.duration && new_end > old_end {
            return Ok(Outcome::Refused(action_past_end(
                clip,
                new_start,
                new_duration,
                target.duration,
            )));
        }
        if let Some(other) =
            overlapping_action(&target.actions, Some(action), new_start, new_duration)
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
        // A linked clip's rate is refused (spec §11 AU-94).
        if let Some(why) = next
            .clip(clip)
            .and_then(|after| self.linked_rate_refusal(&target, after))
        {
            return Ok(Outcome::Refused(why));
        }
        // A rate action moves the out point when it moves (SR-2).
        if end_speed(&existing).is_some() {
            let what = format!("retiming action {action}");
            if let Some(why) = next.clip(clip).and_then(|c| self.overrun_refusal(c, &what)) {
                return Ok(Outcome::Refused(why));
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
    /// name a value no stored group could hold, and `actions_clamp.rs`'s
    /// `clamp_video`, `clamp_audio` and `clamp_text` bound the evaluated
    /// value instead (spec §5.4); a graphic prop's end is the exception,
    /// checked against the op's `schema` (G-34 (c)).
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
    /// did nothing. A `text` object naming `words` is an `Err` too (format
    /// version 9, spec §11 W-6): a word's times are anchored to speech, not
    /// a state a clip ramps toward, and interpolating two lists of ticks
    /// would move every word off what it times. A `video.cutout` naming
    /// `subject` or `quality`, a `null` included, is an `Err` as well
    /// ([`check_cutout_end`], spec §11 CO-20): both are the clip's base.
    ///
    /// `off` (spec §11 CI-14) is the one way to STORE a `null`: each
    /// `"group.key"` path is written as `null` after the merge and the
    /// prune, which keys that optional property off at the action's end.
    /// It refuses what `patch` refuses ([`check_off`]).
    ///
    /// `graphic` is `edit_action_graphic.rs`'s (G-34), read against
    /// `schema`; a prop the clip's map lacks gets its start in this edit.
    pub fn set_action_end(
        &self,
        clip: u32,
        action: u32,
        patch: &Value,
        off: &[String],
        schema: Option<&Value>,
    ) -> Result<Outcome, String> {
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
        if let Some(schema) = schema {
            check_schema(schema)?;
        }
        // Present at all — a `null` included, since writing `motion: null`
        // into an end patch is still asking an action to decide a preset.
        for (group, key) in [
            ("video", "motion"),
            ("video", "hide_silent"),
            ("text", "words"),
        ] {
            if patch.get(group).and_then(|body| body.get(key)).is_some() {
                not_a_target(group, key)?;
            }
        }
        check_cutout_end(patch)?;
        check_end_patch(patch)?;
        let graphic = match patch.get("graphic") {
            Some(body) => Some(read_graphic_end(target, body, schema)?),
            None => None,
        };
        let speed = match patch.get("speed") {
            Some(value) => Some(read_speed_end(target, value)?),
            None => None,
        };
        let off = check_off(patch, off)?;
        let mut rest = patch.clone();
        if let Value::Object(groups) = &mut rest {
            groups.shift_remove("graphic");
            // The CLAMPED rate is what is stored (SR-10).
            if let Some(Some(rate)) = speed {
                groups.insert("speed".to_string(), Value::from(rate));
            }
        }
        let mut merged = actions::merge(&existing.end, &rest);
        prune_removed(&mut merged, &rest, 0);
        if let Some(read) = &graphic {
            write_graphic_end(&mut merged, read);
        }
        for path in &off {
            key_off(&mut merged, path);
        }

        let mut next = self.clone();
        let Some(slot) = next.clip_mut(clip) else {
            return self.finish(next);
        };
        if let Some(found) = slot.actions.iter_mut().find(|a| a.id == action) {
            found.end = merged;
        }
        if let (Some(read), Some(stored)) = (&graphic, slot.graphic.as_mut()) {
            for (key, start) in &read.starts {
                stored.props.insert(key.clone(), start.clone());
            }
            check_count(&stored.props)?;
        }
        if let Some(why) = next
            .clip(clip)
            .and_then(|after| self.linked_rate_refusal(target, after))
        {
            return Ok(Outcome::Refused(why));
        }
        // The out point the new end rate reads to (SR-2): R1/R2 for a rate,
        // R3 for one taken away.
        if let (Some(read), Some(after)) = (speed, next.clip(clip)) {
            let why = match read {
                Some(rate) => self.end_rate_refusal(after, action, rate),
                None => {
                    self.overrun_refusal(after, &format!("removing action {action}'s end rate"))
                }
            };
            if let Some(why) = why {
                return Ok(Outcome::Refused(why));
            }
        }
        self.finish(next)
    }

    /// Removes one action from a clip (spec §6).
    pub fn remove_action(&self, clip: u32, action: u32) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?;
        if !target.actions.iter().any(|a| a.id == action) {
            return Err(format!("no action with id {action} on clip {clip}"));
        }
        let names_speed = target
            .actions
            .iter()
            .any(|a| a.id == action && end_speed(a).is_some());
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.actions.retain(|a| a.id != action);
        }
        if let Some(why) = next
            .clip(clip)
            .and_then(|after| self.linked_rate_refusal(target, after))
        {
            return Ok(Outcome::Refused(why));
        }
        if names_speed {
            let what = format!("removing action {action}");
            if let Some(why) = next.clip(clip).and_then(|c| self.overrun_refusal(c, &what)) {
                return Ok(Outcome::Refused(why));
            }
        }
        self.finish(next)
    }
}
