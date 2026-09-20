//! Cutting one clip in two — `split_clip` and the two helpers only it has
//! ever needed, `state_patch` and `narrow_to`.
//!
//! Cut out of `edit_clip.rs` in road map 5's E2, which owed it a rule about
//! `video.motion` and found a 1171-line file, and cut HERE because a split
//! is not a placement: every other op in `edit_clip.rs` decides where a
//! clip sits or what it is made of, while this one has to decide what the
//! SECOND clip inherits — its base props from the evaluation at the cut, so
//! the join is invisible; the actions that had not finished, rebased to its
//! own clip time, with a straddled one narrowed to the keys it animated;
//! and, since E2, the halves of a preset anchored to the clip's two ends.
//! That inheritance question is the whole of this module and appears
//! nowhere else in the crate.
//!
//! Every splitter in the crate routes here — `split_clips`,
//! `split_under_playhead`, `clear_range` (so `ripple_delete_range(s)` and
//! `lift_range`), `insert_clip`, `overwrite_clip` and `freeze_frame` — so a
//! rule stated once is a rule they all obey. It is a free function taking
//! `&mut Project` rather than a `Project` method for the reason it always
//! was: it is called mid-edit on a clone the caller is still assembling,
//! after `finish` would be too late and before it has anything to hand
//! back.

use serde_json::Value;

use crate::actions::{self, Evaluated, MAX_PATCH_DEPTH};
use crate::edit_clip::clip_end;
use crate::model::{Action, Project, VideoProps};
use crate::source_window::source_advanced;
use crate::time::Ticks;

/// The evaluated state as an action-style patch object, so `split` can hand
/// the first half of a straddled action the state it must reach.
fn state_patch(evaluated: &Evaluated) -> Value {
    let mut out = serde_json::Map::new();
    out.insert("video".to_string(), actions::to_json(&evaluated.video));
    out.insert("audio".to_string(), actions::to_json(&evaluated.audio));
    if let Some(text) = &evaluated.text {
        out.insert("text".to_string(), actions::to_json(text));
    }
    Value::Object(out)
}

/// `state` narrowed to the keys `shape` mentions — the minimal patch with
/// the same reach as the original. Keeping the shape means a split action's
/// first half animates exactly the fields the whole action animated, rather
/// than pinning every property of the clip.
fn narrow_to(state: &Value, shape: &Value, depth: u32) -> Value {
    let (Value::Object(from), Value::Object(keys)) = (state, shape) else {
        return shape.clone();
    };
    if depth >= MAX_PATCH_DEPTH {
        return shape.clone();
    }
    let mut out = serde_json::Map::new();
    for (key, sub) in keys {
        match from.get(key) {
            Some(value) if value.is_object() && sub.is_object() => {
                out.insert(key.clone(), narrow_to(value, sub, depth + 1));
            }
            Some(value) => {
                out.insert(key.clone(), value.clone());
            }
            // A key the state does not have (an unknown patch key): carry
            // the original through untouched, exactly as evaluation would.
            None => {
                out.insert(key.clone(), sub.clone());
            }
        }
    }
    Value::Object(out)
}

/// Cuts `clip_id` in two at project time `at`, in place. Returns false —
/// and changes nothing — when `at` is not strictly inside the clip, which
/// is the spec's refusal.
///
/// The second clip's BASE props are the evaluated state at the cut, so the
/// join is invisible; its actions are the ones that had not finished,
/// rebased to its own clip time.
pub(crate) fn split_clip(project: &mut Project, clip_id: u32, at: Ticks) -> bool {
    let Some(original) = project.clip(clip_id).cloned() else {
        return false;
    };
    let clip_t = at.saturating_sub(original.start);
    if clip_t <= 0 || clip_t >= original.duration {
        return false;
    }
    let state = project.evaluate_clip(&original, clip_t);
    let patch_source = state_patch(&state);

    let mut second = original.clone();
    second.id = project.allocate_id();
    second.start = at;
    second.duration = clip_end(&original).saturating_sub(at);
    // The cut consumes `clip_t` of timeline, which is `clip_t * speed` of
    // source; a still's frozen frame and the sourceless kinds do not move,
    // which is `source_advanced`'s own rule.
    second.source = source_advanced(&original.source, clip_t, original.speed);
    // Presence of a group is a fact about the clip, so an audio-only clip
    // stays audio-only; only the values come from the evaluation.
    second.video = original.video.as_ref().map(|_| state.video.clone());
    second.audio = original.audio.map(|_| state.audio);
    second.text = state.text.clone();
    second.shape = original.shape.clone();
    // The transition covers the join with the PREVIOUS clip, which is still
    // the first half's business (spec §6).
    second.transition_in = None;

    // A preset anchored to the clip's two ends, cut in two: the FIRST half
    // keeps the entrance and gives up the exit, the SECOND keeps the exit
    // and gives up the entrance (format version 8). Carrying both to both
    // halves — which is what a bare clone does, and what `text.animation`
    // had done since format version 5 — makes the first half leave at the
    // cut and the second arrive again there, so a join a viewer is not
    // supposed to see becomes the most visible thing in the shot. Neither
    // half's kept slot is rescaled: a preset is a duration, and the tent
    // rule (`motion.rs`) is what handles one now too long for the half it
    // landed on.
    //
    // Both are normalised to the field's "nothing" — `None` for a motion
    // whose slots are all empty, `None` for an animation with no ramp at
    // either end — so a split leaves one spelling of it, `edit_props.rs`'s
    // patch path's rule applied to the other writer that can produce one.
    let motion_of = |video: &mut Option<VideoProps>, keep_in: bool| {
        if let Some(video) = video.as_mut() {
            if let Some(motion) = video.motion.as_mut() {
                if keep_in {
                    motion.out = None;
                } else {
                    motion.r#in = None;
                }
                if motion.is_empty() {
                    video.motion = None;
                }
            }
        }
    };
    motion_of(&mut second.video, false);
    if let Some(animation) = second.text.as_mut().and_then(|t| t.animation.as_mut()) {
        animation.r#in = 0;
        if animation.out == 0 {
            if let Some(text) = second.text.as_mut() {
                text.animation = None;
            }
        }
    }

    let mut first_actions: Vec<Action> = Vec::new();
    let mut second_actions: Vec<Action> = Vec::new();
    for action in &original.actions {
        let end = action.start.saturating_add(action.duration);
        if end <= clip_t {
            first_actions.push(action.clone());
        } else if action.start >= clip_t {
            let mut moved = action.clone();
            moved.start = action.start.saturating_sub(clip_t);
            second_actions.push(moved);
        } else {
            // Straddles the cut. The first half ends at the state the
            // evaluation reached there, narrowed to the keys the action
            // animated; the second half keeps the original target. The
            // curve is kept on both halves: re-deriving an exact sub-curve
            // is impossible for the eased forms, and the endpoints — which
            // is what a viewer sees at the join — are exact either way.
            let mut head = action.clone();
            head.duration = clip_t.saturating_sub(action.start);
            head.end = narrow_to(&patch_source, &action.end, 0);
            first_actions.push(head);

            let mut tail = action.clone();
            tail.id = project.allocate_id();
            tail.start = 0;
            tail.duration = end.saturating_sub(clip_t);
            second_actions.push(tail);
        }
    }
    second.actions = second_actions;

    if let Some(first) = project.clip_mut(clip_id) {
        first.duration = clip_t;
        first.actions = first_actions;
        motion_of(&mut first.video, true);
        if let Some(animation) = first.text.as_mut().and_then(|t| t.animation.as_mut()) {
            animation.out = 0;
            if animation.r#in == 0 {
                if let Some(text) = first.text.as_mut() {
                    text.animation = None;
                }
            }
        }
    }
    project.clips.push(second);
    true
}
