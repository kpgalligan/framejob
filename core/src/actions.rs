//! Action evaluation: a clip's properties as they actually are at a clip
//! time, after every [`Action`] on it has had its say (spec §5.4).
//!
//! The rule, exactly: start from the clip's base props, apply the `end`
//! patch of every action that ENDED at or before the time, in start order,
//! then — if the time falls inside an action — interpolate from that
//! accumulated state toward that action's patch along the action's curve.
//!
//! Everything routes through TWO routines, [`merge`] and [`lerp`], over
//! `serde_json::Value`. That is deliberate. The patch schema is "any subset
//! of the `video`, `audio` and `text` keys, each any subset of that group's
//! keys", so per-field Rust would be a hundred-arm match that has to be
//! edited every time §5.2 gains a field — and that would silently forget
//! one. Going through the serde representation means a field is animatable
//! the moment `model.rs` declares it, and unknown patch keys are ignored
//! for free, which is the forward compatibility a project written by a
//! newer build needs.
//!
//! The cost is a serialize/deserialize per evaluation: a handful of small
//! maps, asked for once per visible clip per frame. That is nothing next to
//! decoding one video frame, and it is never on the audio path.
//!
//! Nothing here edits. Evaluation is a pure read of a [`Clip`], so it can
//! be called from the recipe, the inspector and `split` alike.
//!
//! A graphic clip's props are the fourth target (format version 13, spec
//! §11 G-34) and are NOT this file's `merge` / `lerp`: `actions_graphic.rs`
//! evaluates them by the props' kinds, into [`Evaluated::graphic`].

use serde::Serialize;
use serde_json::{Map, Number, Value};

use crate::actions_clamp::{clamp_audio, clamp_video};
use crate::actions_curves::{align_identity_curves, curves_json};
use crate::actions_graphic::evaluate_graphic;
use crate::actions_qualifier::align_hue_center;
use crate::edit_adjustment::{clamp_adjustment, is_adjustment};
use crate::model::{
    Action, AudioProps, Clip, ColorAdjust, Curve, GraphicProps, Project, ShapeProps, Source,
    TextProps, VideoProps, Wheels,
};
use crate::time::Ticks;

/// How deep [`merge`] and [`lerp`] will walk a patch. The deepest real path
/// in the §5.2 schema is `video.shadow.color` — three levels — so 8 leaves
/// generous room while bounding the recursion, which is what keeps a
/// hand-written or generated patch from driving these routines down an
/// arbitrarily deep tree. (`serde_json` already caps parse nesting at 128;
/// this is the cheaper, local guarantee.)
pub(crate) const MAX_PATCH_DEPTH: u32 = 8;

/// A clip's properties resolved at one instant. `video` and `audio` are
/// never absent: a clip whose JSON has `"video": null` (an audio-only clip)
/// evaluates to the defaults, and `enabled` — not the presence of the
/// props — decides whether the layer is drawn or heard.
///
/// `text` and `shape` stay `Option`, because "this clip is a text clip" is
/// a fact about the clip that evaluation must not invent.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Evaluated {
    pub video: VideoProps,
    pub audio: AudioProps,
    pub text: Option<TextProps>,
    pub shape: Option<ShapeProps>,
    /// The clip's graphic with its `props` evaluated (G-34), its other
    /// fields as stored; `None` on a clip that is not a graphic.
    pub graphic: Option<GraphicProps>,
}

// ---- curves --------------------------------------------------------------

/// Maps linear progress `u` (clamped to 0..1) to eased progress.
///
/// Quadratics and smoothstep, not cubic Béziers. A CSS-style Bézier is
/// defined as y over x with x itself a cubic, so every evaluation needs a
/// Newton solve for the parameter — per animated field, per frame — and the
/// schema would have to carry four more numbers per action. These four
/// closed forms hit 0 and 1 exactly, are monotone on 0..1, and cover what an
/// action is for (a move, a scale, a fade that does not start and stop
/// abruptly). If a later milestone wants arbitrary curves, `Curve` gains a
/// variant and this function gains an arm; nothing else changes.
pub fn ease(curve: Curve, u: f64) -> f64 {
    // NaN would propagate through every interpolated field, so it collapses
    // to the start of the action rather than poisoning the frame.
    let u = if u.is_nan() { 0.0 } else { u.clamp(0.0, 1.0) };
    match curve {
        Curve::Linear => u,
        Curve::EaseIn => u * u,
        // The mirror of ease_in, so an in/out pair is symmetric.
        Curve::EaseOut => 1.0 - (1.0 - u) * (1.0 - u),
        // Smoothstep: zero slope at both ends, which is what "ease in and
        // out" means, in one multiply-add more than the quadratics.
        Curve::EaseInOut => u * u * (3.0 - 2.0 * u),
    }
}

// ---- the two routines ----------------------------------------------------

/// Deep-merges `patch` into `base`: objects merge key by key, anything else
/// replaces. Keys `base` does not have are added, so a patch may introduce
/// a whole group (`"shadow": {...}` over a `null`); keys `patch` does not
/// mention are untouched. Unknown keys survive the merge and are dropped
/// later by serde, which is exactly the forward-compatible behaviour §5.4
/// asks for: never an error.
pub(crate) fn merge(base: &Value, patch: &Value) -> Value {
    merge_at(base, patch, 0)
}

fn merge_at(base: &Value, patch: &Value, depth: u32) -> Value {
    match (base, patch) {
        (Value::Object(b), Value::Object(p)) if depth < MAX_PATCH_DEPTH => {
            let mut out = b.clone();
            for (key, patch_value) in p {
                let merged = match out.get(key) {
                    Some(base_value) => merge_at(base_value, patch_value, depth + 1),
                    None => patch_value.clone(),
                };
                out.insert(key.clone(), merged);
            }
            Value::Object(out)
        }
        _ => patch.clone(),
    }
}

/// Interpolates `from` toward `to` by eased progress `u`.
///
/// Numbers interpolate; arrays (colors, `key`, `from`/`to` points, the
/// filter and obscure lists) interpolate element by element when the
/// lengths match; objects interpolate key by key. **Booleans, strings,
/// enums, `null`s and any pair of mismatched types switch at the END** —
/// they hold the `from` value until `u` reaches 1 — which is the §5.4 rule
/// and the only sane reading of "interpolate `left` to `center`".
///
/// # The list rule
///
/// Written out here because it is now the CRATE's rule rather than one
/// list's: **an end patch interpolates a list PER INDEX when the lengths
/// match and each pair of entries agrees on its discrete fields, and
/// switches at the end otherwise.** `video.filters` was the schema's first
/// array of objects and `video.obscure` (format version 4) is the second,
/// both governed by exactly this and neither carrying a line of its own
/// code. An animation over a list is invisible until somebody writes one,
/// so the two consequences are worth stating outright:
///
///  - **Lists of different lengths switch at the end.** Blur alone toward
///    blur-plus-vignette has no correspondence between the elements: the
///    only alternative is to invent an off-strength vignette to grow from,
///    which is a guess about what the second list means, and a wrong guess
///    would animate a filter the user never asked to see.
///  - **Entries that NAME different things switch at the end too**, even
///    when the lengths match — the [`ENTRY_DISCRIMINANTS`] rule, applied by
///    [`lerp_entry`]. Entries that agree, and entries whose patch side
///    names neither key, interpolate their numbers, which is the case that
///    matters: an action that ramps a blur from 0 to 1 is exactly "grow
///    this filter", and it works. The hold is PER ENTRY — a list in which
///    one region changes shape still interpolates every region beside it,
///    because the list's correspondence is intact and only that one
///    entry's is not.
fn lerp(from: &Value, to: &Value, u: f64) -> Value {
    lerp_at(from, to, u, 0)
}

/// The keys that name WHAT a list entry is rather than how much of it there
/// is: a filter's `kind`, an obscure region's `kind` and its `shape`.
///
/// The wider set is deliberately confined to LIST ENTRIES; the object rule
/// in [`lerp_at`] still knows `kind` alone. That is not a compromise, it is
/// the distinction the two cases actually have. In a list, an entry's only
/// identity is its INDEX: when entry 1 comes back as a different shape of
/// region there is nothing to say whether the user reshaped that region or
/// replaced it, so morphing one into the other invents a correspondence.
/// On a named object there is no such doubt — `video.spotlight` is one
/// spotlight, `shape` is a property OF it, and an action that moves it from
/// a rect to an ellipse is still moving that spotlight's centre and box.
/// Widening the object rule to `shape` would have frozen the geometry of
/// every such animation until the last instant and then jumped it: a silent
/// change to shipped behaviour, in a feature phase 3 has nothing to do
/// with. `core/tests/schema_v2.rs` pins both halves.
const ENTRY_DISCRIMINANTS: [&str; 2] = ["kind", "shape"];

/// The keys that name WHAT a named object is: `kind` (a filter's, a
/// shape's, a transition's, a look's) and `media`, a LUT look's file (spec
/// §11 GR-8). An id is a name, not a quantity: a LUT A → B interpolated
/// would pass through whichever media sits between the two ids, so the
/// look switches at the end instead, as a change of kind does. The rule
/// applies to any object at any depth of an action's state; `video.look` is
/// the only object with a `media` key today, so a group that adds one
/// switches it at the end too.
const OBJECT_DISCRIMINANTS: [&str; 2] = ["kind", "media"];

/// One entry of a list toward the entry at the same index —
/// [`lerp_at`] under the wider [`ENTRY_DISCRIMINANTS`] set.
///
/// Only [`lerp_at`]'s array arm calls this, which is what keeps the switch
/// point in ONE place: by the time an entry is reached `u` is strictly
/// inside the span, because the whole list has already gone to `to` at
/// `u >= 1.0` and held at `from` at `u <= 0.0`. So holding an entry here
/// holds it for the whole span, and the end still switches — no second copy
/// of the two guards, which would be a second place to get them wrong.
fn lerp_entry(from: &Value, to: &Value, u: f64, depth: u32) -> Value {
    if let (Value::Object(a), Value::Object(b)) = (from, to) {
        // Both sides must name a discriminant for this to fire, so a patch
        // entry that leaves them out — `{"filters": [{"amount": 1}]}`,
        // "same filter, more of it" — still interpolates, key by key.
        let names_another_thing = ENTRY_DISCRIMINANTS
            .iter()
            .any(|key| matches!((a.get(*key), b.get(*key)), (Some(x), Some(y)) if x != y));
        if names_another_thing {
            return from.clone();
        }
    }
    lerp_at(from, to, u, depth)
}

fn lerp_at(from: &Value, to: &Value, u: f64, depth: u32) -> Value {
    // The two switch points. `u >= 1.0` is what makes non-numeric fields
    // take their new value at the action's end and not one tick earlier.
    if u >= 1.0 {
        return to.clone();
    }
    if u <= 0.0 || depth >= MAX_PATCH_DEPTH {
        return from.clone();
    }
    match (from, to) {
        (Value::Number(a), Value::Number(b)) => lerp_number(a, b, u),
        // Elements go through `lerp_entry`, which is this function under a
        // wider discriminant set — the list rule, stated in full on [`lerp`].
        (Value::Array(a), Value::Array(b)) if a.len() == b.len() => Value::Array(
            a.iter()
                .zip(b.iter())
                .map(|(x, y)| lerp_entry(x, y, u, depth + 1))
                .collect(),
        ),
        // A `kind` is a DISCRIMINANT everywhere in §5.2 — a filter's kind,
        // a shape's, a transition's — so two objects that NAME different
        // ones are two different things, and the numbers beside them do not
        // measure the same quantity. Interpolating them would read a blur's
        // strength as a sepia's. The whole object switches at the end
        // instead, exactly as the string naming it would on its own.
        //
        // Both sides must name one for this to fire, so a patch element
        // that leaves `kind` out — `{"filters": [{"amount": 1}]}`, "same
        // filter, more of it" — still interpolates, key by key, below.
        //
        // `kind` and a look's `media` are the discriminants here
        // ([`OBJECT_DISCRIMINANTS`]). A list ENTRY is judged against
        // [`ENTRY_DISCRIMINANTS`] before it ever reaches this arm, and that
        // constant argues why the two sets differ.
        (Value::Object(a), Value::Object(b))
            if OBJECT_DISCRIMINANTS
                .iter()
                .any(|key| matches!((a.get(*key), b.get(*key)), (Some(x), Some(y)) if x != y)) =>
        {
            from.clone()
        }
        (Value::Object(a), Value::Object(b)) => {
            let mut out = Map::new();
            for (key, from_value) in a {
                let value = match b.get(key) {
                    Some(to_value) => lerp_at(from_value, to_value, u, depth + 1),
                    // A key the target lost: nothing to move toward.
                    None => from_value.clone(),
                };
                out.insert(key.clone(), value);
            }
            Value::Object(out)
        }
        _ => from.clone(),
    }
}

/// One number toward another.
///
/// The integer case matters: `fade_in`, `fade_out` and the duck ramps are
/// `Ticks` (i64) in the schema, and writing 12.5 back into one of those
/// would fail to deserialize. So a pair that is integral on BOTH sides
/// stays integral (rounded), and anything touching a float stays float —
/// which is always the case for the f64 fields, because the base state is
/// serialized from the typed structs.
fn lerp_number(from: &Number, to: &Number, u: f64) -> Value {
    let (Some(a), Some(b)) = (from.as_f64(), to.as_f64()) else {
        return Value::Number(from.clone());
    };
    let value = a + (b - a) * u;
    if from.is_f64() || to.is_f64() {
        // from_f64 rejects NaN and infinities; falling back to `from` keeps
        // a nonsense patch from turning the whole frame into null.
        Number::from_f64(value)
            .map(Value::Number)
            .unwrap_or_else(|| Value::Number(from.clone()))
    } else {
        // Rust's float-to-int cast saturates, so an absurd patch cannot
        // panic here.
        Value::Number(Number::from(value.round() as i64))
    }
}

// ---- evaluation ----------------------------------------------------------

/// True when `clip_t` is inside `action`'s span, half-open at the end so
/// the instant an action finishes belongs to the "already applied" set and
/// the value is continuous across the boundary.
pub(crate) fn spans(action: &Action, clip_t: Ticks) -> bool {
    action.duration > 0
        && action.start <= clip_t
        && clip_t < action.start.saturating_add(action.duration)
}

/// The clip's actions in start order. Actions on a clip may not overlap
/// (`edit_clip` refuses to create an overlap), but a hand-written project
/// can still contain one, so the id tiebreak keeps evaluation deterministic
/// rather than dependent on the order they happen to sit in the array.
pub(crate) fn ordered_actions(clip: &Clip) -> Vec<&Action> {
    let mut actions: Vec<&Action> = clip.actions.iter().collect();
    actions.sort_by_key(|a| (a.start, a.id));
    actions
}

/// Serializes a value, or `null` if it somehow cannot be — these types are
/// plain data, so the fallback is unreachable, but nothing here may panic.
pub(crate) fn to_json<T: Serialize>(value: &T) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}

/// A clip's `color` with ALL thirteen keys, tone's nine included at 0 —
/// where `to_json` leaves a neutral tone key out, as the file does (spec §11
/// GR-2). Every reader that walks keys needs them present: an action's
/// [`lerp_at`] walks only its FROM side's keys, so a neutral key absent
/// there would drop out mid-action and jump at the end; `patch.rs`'s
/// template would refuse `color.exposure` as unknown; and the recipe's
/// `color` is the compositor's, which `clip_state` must equal.
pub(crate) fn color_json(color: &ColorAdjust) -> Value {
    let keys = [
        ("brightness", color.brightness),
        ("contrast", color.contrast),
        ("saturation", color.saturation),
        ("hue", color.hue),
        ("exposure", color.exposure),
        ("temperature", color.temperature),
        ("tint", color.tint),
        ("highlights", color.highlights),
        ("shadows", color.shadows),
        ("whites", color.whites),
        ("blacks", color.blacks),
        ("vibrance", color.vibrance),
        ("fade", color.fade),
    ];
    let mut out = Map::new();
    for (key, value) in keys {
        out.insert(key.to_string(), to_json(&value));
    }
    Value::Object(out)
}

/// The wheels with every key present (spec §11 GR-11): all three wheels and
/// each one's `x`, `y` and `master`, even at 0, which the file leaves out.
pub(crate) fn wheels_json(wheels: &Wheels) -> Value {
    let mut out = Map::new();
    for (name, wheel) in wheels.named() {
        let mut keys = Map::new();
        keys.insert("x".to_string(), to_json(&wheel.x));
        keys.insert("y".to_string(), to_json(&wheel.y));
        keys.insert("master".to_string(), to_json(&wheel.master));
        out.insert(name.to_string(), Value::Object(keys));
    }
    Value::Object(out)
}

/// A video group as JSON with its `color` through [`color_json`], its
/// `wheels` through [`wheels_json`] and its `curves` through `curves_json`
/// (all six, an absent one as its identity, GR-12, GR-32), so every tone,
/// wheel and curve key is present: what an action interpolates from, what a patch
/// is checked against and what a split writes back.
pub(crate) fn video_json(video: &VideoProps) -> Value {
    let mut value = to_json(video);
    if let Value::Object(fields) = &mut value {
        fields.insert("color".to_string(), color_json(&video.color));
        fields.insert("wheels".to_string(), wheels_json(&video.wheels));
        fields.insert("curves".to_string(), curves_json(&video.curves));
    }
    value
}

impl Project {
    /// The clip's properties at `clip_t` — CLIP time, so 0 is the clip's
    /// first frame — with every action applied and, if `clip_t` lands
    /// inside one, interpolated.
    ///
    /// Total: any clip, any time, no failure mode. A time before the clip
    /// or past its end evaluates as the start or end state respectively,
    /// which is what a scrubbing inspector wants.
    pub fn evaluate_clip(&self, clip: &Clip, clip_t: Ticks) -> Evaluated {
        let base_video = clip.video.clone().unwrap_or_default();
        let base_audio = clip.audio.unwrap_or_default();

        let mut fields = Map::new();
        fields.insert("video".to_string(), video_json(&base_video));
        fields.insert("audio".to_string(), to_json(&base_audio));
        // A patch may only reach `text` on a clip that HAS text: evaluation
        // resolves properties, it never decides what kind of layer a clip
        // is. Leaving the key out makes a stray text patch a no-op.
        if let Some(text) = &clip.text {
            fields.insert("text".to_string(), to_json(text));
        }
        let mut state = Value::Object(fields);

        let actions = ordered_actions(clip);
        for action in &actions {
            let end = action.start.saturating_add(action.duration);
            if action.duration > 0 && end <= clip_t {
                state = merge(&state, &action.end);
            }
        }
        if let Some(action) = actions.iter().find(|a| spans(a, clip_t)) {
            // Interpolating the WHOLE state toward the patched state, not
            // just the patched keys, is what keeps this to one routine:
            // an untouched field lerps from itself to itself, exactly.
            let mut target = merge(&state, &action.end);
            // An identity curve meeting a curve of another count takes its
            // x's, so a grade animates from (or to) neutral (spec §11 GR-12).
            align_identity_curves(&mut state, &mut target);
            // The hue centre the short way round (spec §11 GR-13).
            align_hue_center(&mut state, &mut target);
            let elapsed = clip_t.saturating_sub(action.start) as f64;
            let progress = elapsed / action.duration as f64;
            state = lerp(&state, &target, ease(action.curve, progress));
        }

        // Motion is NOT an animation target (format version 8, spec §5.4).
        // `set_action_end` refuses a patch naming it, but a hand-written
        // file, a pasted action or another tool's project reaches here
        // without passing that op, so the BASE value goes back over what
        // the loop reached — at the `Value` level, since `clamp_video` is
        // never handed the base props and a malformed `motion` would fail the
        // WHOLE video group's decode below, losing every other animated one. The guard is "no input may panic" applied to a value
        // nothing validates: `merge_at` REPLACES on a type mismatch, and
        // `set_action_end` checks only the patch's top level, so
        // `state["video"]` may be a number, string, array, bool or null
        // here — and `IndexMut<&str>` panics on all but null, where it would
        // MINT `{"motion": …}` and decode as DEFAULT props rather than base.
        // With the `if let` each keeps falling through to
        // `.ok().unwrap_or(base_video)`, as it always did.
        //
        // A look that does not read as one becomes no look (spec §11 GR-7),
        // in the same place and for the same reason. `set_action_end` checks
        // an end against the patch TEMPLATE, whose look has a kind, so an end
        // of `{"look": {"amount": 1}}` is accepted — and on a clip with no
        // look (or one whose look was removed after the end was written) the
        // merge leaves a kind-less look, which would fail the whole group's
        // decode below and snap every animated key back to base. Inert
        // instead: no kind, no look; every other key keeps its value. The
        // same for a LUT look whose `media` is not a LUT of the project
        // (GR-8: an end is never checked against the media list).
        if let Some(Value::Object(video)) = state.get_mut("video") {
            video.insert("motion".to_string(), to_json(&base_video.motion));
            if video
                .get("look")
                .is_some_and(|look| !look.is_null() && !self.evaluates_as_look(look))
            {
                video.insert("look".to_string(), Value::Null);
            }
        }
        // A patch that writes a bad type into a field (12.5 into a tick
        // count, say) loses that whole group rather than failing: the
        // evaluator has no way to report, and a base-props frame is far
        // better than a missing one.
        let evaluated_video = state
            .get("video")
            .and_then(|v| serde_json::from_value::<VideoProps>(v.clone()).ok())
            .unwrap_or(base_video);
        let evaluated_audio = state
            .get("audio")
            .and_then(|v| serde_json::from_value::<AudioProps>(v.clone()).ok())
            .unwrap_or(base_audio);
        let evaluated_text = clip.text.clone().map(|base| {
            state
                .get("text")
                .and_then(|v| serde_json::from_value::<TextProps>(v.clone()).ok())
                .unwrap_or(base)
        });

        Evaluated {
            // The clip is in hand here, so the one non-range bound
            // `clamp_video` applies — a nest may not blend — is decided from
            // the source rather than guessed from the props.
            // An adjustment clip's end is closed the same way (spec §11 GR-6).
            video: {
                let video =
                    clamp_video(evaluated_video, matches!(clip.source, Source::Nest { .. }));
                if is_adjustment(clip) {
                    clamp_adjustment(video)
                } else {
                    video
                }
            },
            audio: clamp_audio(evaluated_audio),
            text: evaluated_text,
            // Shapes are not animatable in version 1: the §5.4 patch is a
            // subset of video/audio/text only, so the description passes
            // through untouched.
            shape: clip.shape.clone(),
            graphic: evaluate_graphic(clip, clip_t),
        }
    }

    /// One clip's evaluated state as JSON, for the inspector
    /// (`rc_project_clip_state`). `t` is PROJECT time — the playhead —
    /// which this converts to clip time.
    ///
    /// The keys are the project schema's own (`video`, `audio`, `text`,
    /// `shape`, `graphic`), so the inspector binds to this exactly as it binds to the
    /// clip itself; `in_action` is the action the playhead is inside, or
    /// `null`, which is how the inspector knows an edit would set a
    /// keyframe rather than the base value.
    ///
    /// `None` for an unknown clip id — the header's NULL return.
    pub fn clip_state(&self, clip_id: u32, t: Ticks) -> Option<Value> {
        let clip = self.clip(clip_id)?;
        let clip_t = t.saturating_sub(clip.start);
        let evaluated = self.evaluate_clip(clip, clip_t);
        let in_action = ordered_actions(clip)
            .into_iter()
            .find(|a| spans(a, clip_t))
            .map(|a| a.id);

        let mut out = Map::new();
        out.insert("clip".to_string(), Value::from(clip.id));
        out.insert("t".to_string(), Value::from(t));
        out.insert(
            "in_action".to_string(),
            in_action.map(Value::from).unwrap_or(Value::Null),
        );
        out.insert("video".to_string(), video_json(&evaluated.video));
        out.insert("audio".to_string(), to_json(&evaluated.audio));
        out.insert("text".to_string(), to_json(&evaluated.text));
        out.insert("shape".to_string(), to_json(&evaluated.shape));
        out.insert("graphic".to_string(), to_json(&evaluated.graphic));
        Some(Value::Object(out))
    }
}
