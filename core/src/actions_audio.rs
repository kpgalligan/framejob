//! The audio group's two evaluation rules beside `actions.rs`'s `merge` and
//! `lerp` (road map "audio" AP8b, spec §11 AU-86): the group as JSON with
//! `isolation` present even at 0, and the four numbers that are switches.
//!
//! `isolation` is written only when not 0 in the file (format 31), so
//! `to_json` leaves a clip with none without the key — and `lerp` walks only
//! its FROM side's keys, so an action toward 0.8 would hold 0 for its whole
//! span and jump at the end. [`audio_json`] writes it, as `color_json` writes
//! tone's neutral keys.
//!
//! The EQ's two slopes (12 or 24 dB/octave), the hum's mains (50 or 60 Hz)
//! and its harmonics are integers in the schema, so `lerp_number` would
//! round them through every value between — a 12 → 24 slope passing 18,
//! which no stage designs, and a 50 → 60 mains passing 55. They are choices,
//! not quantities: [`hold_audio_steps`] holds each at its start value until
//! the action's end, which is §5.4's rule for a switch.

use serde_json::Value;

use crate::actions::to_json;
use crate::model::AudioProps;

/// A clip's audio group as JSON with `isolation` present at 0 (AU-86).
pub(crate) fn audio_json(audio: &AudioProps) -> Value {
    let mut value = to_json(audio);
    if let Value::Object(fields) = &mut value {
        if !fields.contains_key("isolation") {
            fields.insert("isolation".to_string(), to_json(&audio.isolation));
        }
    }
    value
}

/// The audio numbers that switch at an action's end rather than glide
/// (AU-86), as JSON pointers into the evaluated state.
pub(crate) const HELD_AUDIO_NUMBERS: [&str; 4] = [
    "/audio/eq/high_pass/slope",
    "/audio/eq/low_pass/slope",
    "/audio/hum/frequency",
    "/audio/hum/harmonics",
];

/// Puts each [`HELD_AUDIO_NUMBERS`] field of `lerped` back to its value in
/// `from`, the state the spanning action started from. Only where both have
/// it: a slot present on one side alone already holds or switches whole
/// through `lerp`'s mismatched-type rule.
pub(crate) fn hold_audio_steps(from: &Value, lerped: &mut Value) {
    for pointer in HELD_AUDIO_NUMBERS {
        let Some(start) = from.pointer(pointer) else {
            continue;
        };
        if let Some(slot) = lerped.pointer_mut(pointer) {
            *slot = start.clone();
        }
    }
}
