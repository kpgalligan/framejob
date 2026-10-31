//! An audio segment's automation (road map "audio" AP8b, spec §7.2, §11
//! AU-85): the tap's settings as the clip's actions move them, published in
//! the plan as points the app interpolates between.
//!
//! The envelope (`audio.rs`) already carries volume, the fades, the duck
//! and every silencing as ramps. What the tap runs — the pan, the fold, the
//! channel pick, the EQ and hum, noise reduction, the gate, the de-esser,
//! the compressor, the limiter and isolation's Amount — is read off
//! [`TAP_KEYS`] here instead. Evaluation stays the core's: each point is
//! [`Project::evaluate_clip`] at its time, so a switch, a clamp and an
//! eased curve are decided in one place and Swift only draws straight lines
//! between points the core already evaluated.
//!
//! A segment whose innermost clip has no action naming a tap key gets no
//! points, and the plan carries no key, so every other plan is the text it
//! was. The segment names the INNERMOST clip, so a nest clip's own tap keys
//! reach nothing here, as its base values reach nothing in the tap.

use serde::Serialize;
use serde_json::{Map, Value};

use crate::actions_audio::audio_json;
use crate::audio::{Voice, ACTION_SAMPLE, MAX_ACTION_SAMPLES};
use crate::model::{Action, Curve, Project};
use crate::time::Ticks;

/// The audio keys the tap reads (AU-85), in the plan's order. Volume, mute,
/// the fades, the duck and its shapes are the envelope's; `keep_pitch` is
/// the segment's `pitch`; `voice` is an offline render.
pub(crate) const TAP_KEYS: [&str; 11] = [
    "mono",
    "pan",
    "compressor",
    "noise_reduction",
    "limiter",
    "isolation",
    "eq",
    "hum",
    "channels",
    "gate",
    "de_esser",
];

/// One point of a segment's automation: the tap keys of the clip's
/// evaluated audio at `at`, in PROJECT ticks.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub(crate) struct AutomationPoint {
    pub(crate) at: Ticks,
    pub(crate) audio: Value,
}

/// Whether `action`'s end names any tap key in its `audio` object.
pub(crate) fn names_tap_key(action: &Action) -> bool {
    action
        .end
        .get("audio")
        .and_then(Value::as_object)
        .is_some_and(|audio| TAP_KEYS.iter().any(|key| audio.contains_key(*key)))
}

/// `audio` cut to [`TAP_KEYS`], in their order.
fn tap_keys(audio: &Value) -> Value {
    let mut out = Map::new();
    for key in TAP_KEYS {
        if let Some(value) = audio.get(key) {
            out.insert(key.to_string(), value.clone());
        }
    }
    Value::Object(out)
}

impl Project {
    /// The automation of the segment `voice` plays (AU-85): empty when its
    /// innermost clip has no action naming a tap key. The points are the
    /// voice's two ends, each such action's two ends and, inside a
    /// non-linear one, the envelope's own 1/30 s grid (`audio.rs`'s
    /// `breakpoints`), clipped to the voice, sorted and deduplicated.
    pub(crate) fn automation(&self, voice: &Voice<'_>) -> Vec<AutomationPoint> {
        let Some(stage) = voice.stages.first() else {
            return Vec::new();
        };
        let clip = stage.clip;
        let actions: Vec<&Action> = clip
            .actions
            .iter()
            .filter(|a| a.duration > 0 && names_tap_key(a))
            .collect();
        if actions.is_empty() || voice.end <= voice.start {
            return Vec::new();
        }
        let mut ticks: Vec<Ticks> = vec![voice.start, voice.end];
        for action in actions {
            let start = stage.origin.saturating_add(action.start);
            let end = start.saturating_add(action.duration);
            ticks.push(start);
            ticks.push(end);
            if action.curve == Curve::Linear {
                continue;
            }
            let step = ACTION_SAMPLE.max(action.duration / MAX_ACTION_SAMPLES + 1);
            let mut t = start.saturating_add(step);
            while t < end {
                ticks.push(t);
                t = t.saturating_add(step);
            }
        }
        ticks.retain(|t| *t >= voice.start && *t <= voice.end);
        ticks.sort_unstable();
        ticks.dedup();
        ticks
            .into_iter()
            .map(|at| {
                let evaluated = self.evaluate_clip(clip, at.saturating_sub(stage.origin));
                AutomationPoint {
                    at,
                    audio: tap_keys(&audio_json(&evaluated.audio)),
                }
            })
            .collect()
    }
}
