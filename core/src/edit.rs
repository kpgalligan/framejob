//! The op envelope — the ONE edit entry point (spec §6, spec §7.1).
//!
//! Every edit the app or the agent makes arrives here as one JSON object,
//! `{"op": "<name>", ...arguments}`, and leaves as a new project. This
//! module owns the envelope and nothing else: [`Op`] is the schema, and
//! [`Project::apply`] is a flat dispatch table with no logic in it. The
//! semantics live in `edit_clip.rs`, `edit_props.rs`, `edit_track.rs` and
//! `edit_time.rs`.
//!
//! **The table below IS what an op MEANS**, and [`crate::op_table`] is
//! what one TAKES: its rows are the argument names, kinds and required-ness
//! that used to be a markdown column here, as data a caller can read.
//! `app/Sources/ReelOps.swift`'s typed builders mirror the two together, and
//! `AgentCatalog*.swift`'s tools PRINT the arguments half (`rc_op_schemas`).
//!
//! Reading the table:
//!
//! - **Times are ticks**: `i64` at 600 000 per second ([`crate::TIMESCALE`]),
//!   the timescale that divides every common frame duration exactly.
//! - **Every time argument is snapped to the canvas frame grid first**
//!   (round to nearest), durations included, so a caller may pass a value
//!   computed from a pixel position without rounding it itself. A negative
//!   PROJECT time is clamped to 0 — a drag can start left of the timeline
//!   and there is no negative time there — while a negative LENGTH is an
//!   `Err`, and so is a negative CLIP time (`add_action`, `set_action`):
//!   the caller computes those as `playhead − clip.start`, so a negative
//!   one means the playhead is not on the clip, which is a caller bug and
//!   not a gesture to round off.
//! - **What an absent optional argument MEANS is said here**, in the
//!   Semantics column, and which arguments are optional at all is
//!   [`crate::op_table`]. An absent optional and an explicit `null` mean
//!   the same thing.
//! - **A new id is the project's `next_id` from BEFORE the call.** An op
//!   returns a project, not a value, so a caller that needs the id of the
//!   clip, track, marker or media it just added reads `next_id` first. An
//!   op minting MORE than one gives them ids in the order it CREATES them —
//!   the rule is that order and never a closed list of such ops, which was
//!   wrong on the third of them: `add_background` and
//!   `add_blurred_background` create the TRACK and then the clip on it;
//!   `detach_audio` on a bottom-track clip does the same and then re-mints
//!   an id per action it carried; `nest` mints the nest, a track per track
//!   it swallows, then the nest clip.
//! - Unknown keys are an error, in the envelope and in every property
//!   patch: a typo in a hand-written op or an agent call is a mistake to
//!   report, not a silent no-op. In a property patch a value of the wrong
//!   kind and a misspelt variant are errors too — never read as a clear,
//!   and a list or an object is never read field by field as something
//!   else — and the refusal names the dotted path to the mistake, array
//!   indices included, and the value sent: `unknown key "filters[1].kindd"
//!   in a video patch`, `bad value at "shadow" in a video patch: expected
//!   an object, not 5`. An action's `end` patch is walked the same way —
//!   the three groups it may name are `video`, `audio` and `text`, and its
//!   paths carry the group (`unknown key "video.filters[1].kindd" in an
//!   action end patch`) — but its VALUES are not range-checked, because an
//!   end state may name what no stored group could hold.
//!   `set_clip` is the fifth patch op. In every patch an absent key keeps
//!   and a `null` clears an OPTIONAL field (a shadow, a duck, a text
//!   `width`; a required one refuses it by name) — in `set_clip` the field
//!   itself, and there an EMPTY string clears too: an unnamed clip is
//!   `None`, not `""`.
//!
//! ### `scope` — the one envelope key that is not an argument
//!
//! `{"op": "trim_start", "clip": 6, "to": 600000, "scope": 4}` trims a clip
//! **inside nest 4**. `scope` is optional, a nest id, and it belongs to the
//! envelope rather than to any op: with it absent (or `null`, the
//! envelope's rule) every id in the op resolves against the timeline
//! exactly as it always did, and with it present every id in the op —
//! clips, tracks, actions — resolves against that nest's own tracks and
//! clips. Nothing about an op's arguments changes, and no op gained a
//! nest-aware code path: [`crate::scope`] builds a VIEW project out of the
//! nest, runs the op against it unchanged, and merges the answer back. That
//! module's doc is the view, the merge and everything the merge is
//! responsible for; `OP_NAMES` is unchanged, because a scope is not an op.
//!
//! Times inside a scope are the NEST's own, measured from its zero — the
//! same times its `clips[]` are written in — not project time. A nest has
//! no speed, so `t − nest_clip.start` is the whole mapping.
//!
//! **Seven ops are an `Err` with a scope**, naming themselves and the nest:
//! `add_marker`, `set_marker`, `remove_marker` (a nest has no markers of
//! its own — spec §5.2), `set_canvas` (a nest's size is FROZEN at the size
//! the parent had when it was made, deliberately, and the rest of a canvas
//! — the rate, the background, the two switches — is the document's), and
//! `add_media`, `relink_media`, `remove_media` (a nest references the
//! parent's `media[]` in the parent's one id space, so a media edit inside
//! a scope is an edit OUTSIDE it wearing a scope, which is the one thing a
//! scope exists to prevent). Everything else — all fifty — works
//! inside a nest as it works on the timeline, `nest` and `unnest`
//! included.
//!
//! ### Clips
//!
//! | Op | Semantics |
//! |---|---|
//! | `add_clip` | Whole media as one clip at `at`; source in 0, Fit scale when `canvas.fit_new_clips` and the source exceeds the canvas. |
//! | `add_text_clip` | The Title preset, centered, 5 s long when `duration` is absent; `text` patches it exactly as `set_text` would. |
//! | `add_shape_clip` | The default rectangle, 5 s long when `duration` is absent — an `arrow` kind gets `arrow_end` on, since a headless arrow is a diagonal line; `shape` patches that preset exactly as `set_shape` would, so an explicit `arrow_end: false` still wins. |
//! | `add_background` | A backdrop on a NEW back-most track, starting at 0, named "Background" and as long as the timeline unless `duration` says otherwise. With `media`, that file placed as `add_clip` would place it but for its SCALE — the right source kind, audio props when it has sound, and a FILL scale where `add_clip` takes a Fit one, because a plate that leaves the canvas showing down one side has failed at the one thing a background is for; with `color`, or with neither, a canvas-sized filled rectangle with no stroke at scale 1. The plate default is WHITE, not black: the canvas is already black, so a black plate is a command that appears to do nothing. `Err` for `media` and `color` together, an unknown media, a media with no pictures, a colour outside 0–1, or a duration under a frame. |
//! | `add_blurred_background` | The screencast backdrop: `clip` copied onto a NEW back-most track at the same start, duration, speed and source window — so the two play the same frames — scaled to FILL the canvas, centred, uncropped, blended `normal` and blurred at full strength. The copy is muted (`enabled` becomes `{video: true, audio: false}`, `detach_audio`'s pair read the other way) and drops its `audio.duck` — the one field of that group that lowers OTHER material, so a copy keeping it would duck the mix including the clip it came from — along with its transition, its actions and its label; it is named "Blurred Background". `Err` for an unknown clip, a NEST (flattening drops a nest clip's own filters, so the copy would come out sharp), a source with no pixel size (text, audio-only), or a clip with no video properties. |
//! | `insert_clip` | The insert edit: the clip `at` is strictly inside on `track` is split, every unlocked track opens by the media's whole length, then that media lands at `at`. Only the destination track is cut — straddlers elsewhere ride the shift whole. |
//! | `overwrite_clip` | The overwrite edit: `[at, at + media length)` is cleared on `track` ALONE — cut at both bounds, the middles removed — and the media lands there. Nothing shifts and no other track is touched. |
//! | `move_clip` | Shifts the selection by `delta`, clamped so the earliest clip stops at 0; `track` retargets by track-index delta, keeping relative offsets. |
//! | `trim_start` | New start `to`; a media `in` advances by `(to − start) × speed`. Clamped to the source head and to one frame before the end. |
//! | `trim_end` | New end `to`, clamped to `start + one frame` and to the source's remaining length. |
//! | `rate_stretch` | `speed = content length / (to_end − start)`; duration follows and actions rescale. A non-media source is an `Err`, not a refusal. |
//! | `slip` | Slides the source under a fixed clip: `in += delta × speed`, start and duration unchanged, clamped so the window stays inside the media. A `still` moves its `at` instead. A slip the clamps reduce to nothing is an identity; a source with nothing to slip is an `Err`. |
//! | `roll` | Moves a hard cut: this clip's start and its predecessor's end both become `to`. The predecessor is the clip on the track ending EXACTLY at this one's start; with none — a gap, or an overlap, whose length is `set_transition_duration`'s — it refuses. Clamped to one frame and to the source available on each side. |
//! | `split` | Cuts at project time `at`. With `clips` absent, cuts every clip on an unlocked track that `at` is strictly inside. |
//! | `delete` | Removes the clips; the gaps stay. |
//! | `ripple_delete` | Removes, then closes each removed span across every unlocked track. Markers do not move. |
//! | `ripple_delete_range` | Splits every unlocked clip at both bounds, removes the middles, then closes the hole. A reversed range is the same range. |
//! | `ripple_delete_ranges` | Several `[from, to]` pairs as one edit — the silence cut. Each pair is snapped, clamped and ordered as `ripple_delete_range`'s one is, the pairs are then MERGED (touching as well as overlapping) and the survivors cut and closed right to left, so the op is merge-then-cut and not N `ripple_delete_range`s. Markers do not move. An empty list, and one that merges to nothing, change nothing. |
//! | `lift_range` | `ripple_delete_range` without the close: every unlocked clip is split at both bounds and the middles removed, and nothing moves. A reversed range is the same range. |
//! | `insert_time` | Opens a hole: every unlocked clip, and every marker, at or after `at` moves right by `length`. |
//! | `close_gap` | Closes the empty span on `track` that contains `at`, bounded by the nearest clip edges there: everything from its far side shifts left by its length, across every unlocked track. Refuses on a locked `track`, on an `at` that is on a clip, with no clip after the gap, and when the shift would break the overlap rule — a gap closes fully or not at all. |
//! | `set_speed` | `duration = content length / rate` (rate clamped to 0.1–10); actions keep their clip-relative fraction. A non-media source is an `Err`, not a refusal — see "The non-media rule" under Results. |
//! | `set_reversed` | Plays the media back to front, or forward again. A FACT about the clip, not a plan change: Swift substitutes a pre-rendered reversed asset (spec §11). The in point is measured in the direction the clip plays, so reversing keeps `in` and therefore shows different frames. A non-media source is an `Err`, not a refusal. |
//! | `freeze_frame` | `split` at `at`, `insert_time(at, duration)` (2 s when absent), then a `still` of that source frame with the clip's video props evaluated at `at`. |
//! | `detach_audio` | Clears the clip's `enabled.audio` and puts an audio-only twin on the track below, inserting a track when there is none. |
//! | `duplicate` | Copies each clip one selection-span later on its own track, with fresh ids. |
//! | `paste` | Inserts the clips of a clipboard payload — `{"clips": […], "media": […]}`, what Copy wrote — with fresh ids, the earliest landing at `at` and the rest keeping their offsets. A payload clip's `track` is a DEPTH from the front (0 = front-most), so `track` says where depth 0 lands (default: the front) and the rest follow by the same index delta; tracks missing behind it are added. Media is matched to `media[]` by path and appended when absent. A clip the overlap rule refuses goes on a new track in front; an empty clip list changes nothing. |
//! | `paste_attributes` | Copies the payload's EARLIEST clip's property groups (at one start the front-most, then the lower id — never the array's first, which is creation order) onto each clip: video and audio whole, text but content, shape but kind, width, height, from and to. Default: every group both sides have; a named group either side lacks is an Err. Speed, enabled, actions, transition and identity stay. An identity when nothing changes. |
//! | `nest` | Collapses the selection into ONE clip showing a nest named `Nest <n>` unless `name` says otherwise, on the front-most track the selection occupied, running from the earliest start to the latest end. The clips move whole — ids, props, actions, transitions — keeping their relative times (earliest → 0) and their track order; the nest's canvas is frozen at the project's current size. Refuses on an empty selection, on a lone nest clip, and when the nest clip would break the overlap rule. |
//! | `unnest` | The inverse: the nest's clips return at `clip.start + their own start`, with fresh ids, on tracks counted back from the nest clip's own (front-most nest track first), and the nest clip goes. `nest` then `unnest` is the identity on clip content, ids aside. A clip the overlap rule refuses lands on a new track in front, as `paste` does; a nest clip trimmed shorter than its contents gives ALL of them back (a nest has no in point); the nest is dropped when nothing else shows it. `Err` when `clip` is not a nest clip. |
//! | `set_video` | Merges the patch into each clip's video props (spec §5.2). |
//! | `set_audio` | Merges the patch into each clip's audio props. |
//! | `set_text` | Merges the patch into each clip's text props. |
//! | `set_shape` | Merges the patch into each clip's shape props. |
//! | `set_clip` | Sets or clears the clip's own name and label; absent keeps, null or an empty string clears. Unknown keys are an Err. A split, duplicate, detach or paste carries both. An identity when nothing changes. |
//! | `set_enabled` | The per-clip hide and mute switches; omitted fields keep their value. |
//! | `set_transition` | Sets `transition_in`; absent or `null` clears it. The overlap with the predecessor IS the duration. |
//! | `set_transition_duration` | Moves the clip so its overlap with its predecessor is exactly `duration`. |
//! | `add_transition` | Makes an overlap at the HARD CUT before `clip` out of the two clips' unused handles and puts a transition on it — nothing else on the timeline moves. `align` is `center` when absent: half from each side (the odd frame to the incoming clip) and passes a side's shortfall to the other; `before` takes it all from the incoming clip's head, `after` all from the outgoing clip's tail. The duration is snapped down to whole frames and CLAMPED — to each handle, to the neighbours on the track, and to the overlap rule — so a request too long for the material lands shorter rather than refusing; below one frame refuses. A nest gives no head, and a nest tail ends at the nest's own length. The incoming clip's actions move with its new first frame. `kind` absent uses the clip's stored kind if it has one, else cross_dissolve; a stored transition keeps its curve and crossfade, a new one is minted (eased, crossfading). Err for a non-positive duration, an unknown clip, and for not being at a hard cut — naming which of no predecessor, a gap, an existing overlap. `ripple` (false when absent): when true no handle is read and `align` is ignored — the overlap is made by SHIFTING the incoming clip and every clip at or after it on every unlocked track left by the snapped duration, so the timeline gets shorter and no source window changes; the duration is capped at half the shorter of the two clips and stepped down a frame at a time until every track something moved on passes the overlap rule, another track's clip that gains an overlap gets a minted cross_dissolve (`close_gap`'s rule), markers do not move, and an incoming clip on a locked track refuses. |
//! | `set_transition_style` | Sets the transition's easing and whether it crossfades the two clips' sound; an absent key keeps. A clip with no stored transition and at least one key given gets a minted `cross_dissolve` with the style applied; NEITHER key given is an identity and never mints. A separate op from `set_transition` because that one reads an absent `kind` as a clear and so cannot spell "keep". |
//!
//! The closed vocabularies an argument may take — a transition kind, a
//! curve, an alignment, a zoom fit — are [`crate::op_table::Kind::values`],
//! which publishes each list where the argument is declared.
//!
//! ### Actions
//!
//! | Op | Semantics |
//! |---|---|
//! | `add_action` | A new action at CLIP time `at` (the caller subtracts `clip.start`), 1 s long when `duration` is absent, end patch empty. Refuses when it would overlap another action or run past the clip. |
//! | `add_zoom_action` | An `add_action` whose end patch is the `scale`, `x` and `y` that bring `region` to the canvas — the screencast zoom. An absent `duration` is 1 s, an absent `fit` is `fit` and an absent `curve` is `ease_in_out`. `region`'s `x`/`y` are its **CENTRE** and `width`/`height` its size, both SOURCE pixels from the centre of the clip's cropped rect (the spotlight's frame); `fit` shows the whole region, `fill` covers the whole canvas, both measured THROUGH the clip's rotation. Rotation and crop are read from the clip evaluated at `at`; the scale clamps to the layer maximum and the offsets follow the CLAMPED value, so a region too small to fill the canvas still lands centred. `region` absent or `null` is a zoom BACK: the end patch is the clip's base `scale`, `x`, `y`. The region is read the way a patch is: it must BE an object (a four-number list is refused, not read member by member), and an unknown, missing or wrong-typed member is an `Err` naming it. Same refusals as `add_action`; a clip with no video properties is an `Err`. |
//! | `set_action` | Retimes or re-curves one action; omitted fields keep their value, same overlap checks. |
//! | `set_action_end` | Merges into the action's `end` patch; a key set to `null` is removed from it, at any depth. Walked for keys and kinds like every other patch, over the three groups §5.4 allows (a `shape` object is an unknown key); values are NOT range-checked. A `video` object naming `motion` is an `Err`. |
//! | `remove_action` | Removes the action. |
//!
//! The placement equation `add_zoom_action` solves, and the two limits it
//! carries, are `edit_zoom.rs`'s module doc.
//!
//! ### Tracks, markers, canvas, media
//!
//! | Op | Semantics |
//! |---|---|
//! | `add_track` | Inserts a track at `index`, or at the front when it is absent; index 0 is the back-most. The default name is `Track <count + 1>`. |
//! | `remove_track` | Refuses on a track that still holds clips unless `with_clips`, and on the last remaining track. |
//! | `move_track` | Reorders the stack; index 0 is the back-most. |
//! | `set_track` | Omitted fields keep their value. |
//! | `remove_empty_tracks` | Drops every track with no clips, keeping the back-most if that would empty the stack. |
//! | `add_marker` | A marker at `at`, clamped to ≥ 0, named `Marker <n>` and red unless `name` and `color` say otherwise. Two markers may not share a tick. |
//! | `set_marker` | Omitted fields keep their value; the same one-marker-per-tick rule. |
//! | `remove_marker` | Removes the marker. |
//! | `set_canvas` | `rescale_clips`, false when absent, multiplies every clip's `x`, `y` and `scale` by the size ratio; an fps change re-snaps every clip, action and marker time to the new grid, and DROPS a marker a coarser grid lands on a tick another marker already holds. |
//! | `add_media` | Appends the `media[]` element of spec §5.2 minus its `id` (the host probes the file). A path already in the list changes nothing. |
//! | `relink_media` | Points a media at another file; an absent or `null` bookmark clears the stale one. |
//! | `remove_media` | Refuses while clips still reference it unless `with_clips`, which removes those clips too. |
//!
//! ### Results
//!
//! [`Project::apply`] returns the answer the whole editor is built on
//! (spec §5.5): [`Outcome`]'s three arms for an op that was understood, and
//! `Err` for a request that was not.
//!
//! - `Ok(Outcome::Applied(project))` — the new project; the app pushes an
//!   undo step.
//! - `Ok(Outcome::Identity)` — valid, nothing needed to change. **No undo
//!   step** (one is a phantom step), and no sentence: no rule to name.
//! - `Ok(Outcome::Refused(why))` — a rule declined the op, in the rule's
//!   own words (the overlap rule's names the two clips and the tick
//!   counts). **No undo step either**, and the project is exactly as it
//!   was: a refusal is not an error tier, it is an answer that can say why.
//! - `Err(message)` — an unknown id, an out-of-range value, a malformed
//!   envelope. Lowercase, naming the offending value.
//!
//! **A "refuses" in the table names the RULE**; which rules say so out
//! loud, and which are really identities, is [`Outcome::Identity`]'s doc.
//!
//! **A `scope` widens the `Err` arm and nothing else.** An op applied
//! inside a nest can succeed against the view and STILL be refused, because
//! two invariants are invisible from in there: the caps count the whole
//! document, and the nesting depth is measured from the timeline down. Both
//! are checked once, at the end, on the merged parent — see
//! [`crate::scope`], which states the contract in full.
//!
//! **The non-media rule.** `set_speed`, `rate_stretch`, `freeze_frame` and
//! `slip` return `Err("clip N is not a media clip")` rather than refusing:
//! a `clip` argument naming a text or shape clip for a speed op is an
//! invalid argument — the same class as an unknown id — and an identity
//! there is indistinguishable from "the rate was already that", which is a
//! bad answer to give the MCP agent. Spec §6 originally worded the first
//! three rows "refuses" and was amended to match, so the siblings, the spec
//! and `core/CLAUDE.md`'s error tiers agree. `slip` draws the line one step
//! further out: a `still` has a source TIME and slipping that is exactly
//! what the op means, so the question there is "has this clip a source at
//! all", not "is this a media source".

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::edit_transition::TransitionAlign;
use crate::edit_zoom::{ZoomFit, ZoomRegion};
use crate::export::describe;
use crate::model::{Color, Curve, Project, TransitionKind};
use crate::outcome::Outcome;
use crate::patch::Group;
use crate::scope;
use crate::time::{Fps, Ticks};

/// Every op name, in the order of the table above — [`crate::op_table`]'s
/// names, re-exported here under the name and path every caller in the
/// core, the FFI, the tests and the app already uses.
pub use crate::op_table::OP_NAMES;

/// One edit, parsed from its JSON envelope. The arguments and their
/// defaults are the module table; every variant denies unknown fields, so a
/// misspelt argument is an `Err` rather than an argument silently ignored.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum Op {
    // ---- clips ----------------------------------------------------------
    AddClip {
        track: u32,
        media: u32,
        at: Ticks,
    },
    AddTextClip {
        track: u32,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
        #[serde(default)]
        text: Option<Value>,
    },
    AddShapeClip {
        track: u32,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
        #[serde(default)]
        shape: Option<Value>,
    },
    /// `media` and `color` are alternatives, not a pair: a plate is either
    /// a picture or a colour, and naming both is an `Err` rather than a
    /// precedence rule nobody would remember. Both carry a serde default so
    /// that an absent key and an explicit `null` mean the same thing (the
    /// envelope's rule), which is what makes the no-argument call — the
    /// "Solid Color" command — legal and white.
    AddBackground {
        #[serde(default)]
        media: Option<u32>,
        #[serde(default)]
        color: Option<Color>,
        #[serde(default)]
        duration: Option<Ticks>,
    },
    AddBlurredBackground {
        clip: u32,
    },
    InsertClip {
        track: u32,
        media: u32,
        at: Ticks,
    },
    OverwriteClip {
        track: u32,
        media: u32,
        at: Ticks,
    },
    MoveClip {
        clips: Vec<u32>,
        delta: Ticks,
        #[serde(default)]
        track: Option<u32>,
    },
    TrimStart {
        clip: u32,
        to: Ticks,
    },
    TrimEnd {
        clip: u32,
        to: Ticks,
    },
    RateStretch {
        clip: u32,
        to_end: Ticks,
    },
    Slip {
        clip: u32,
        delta: Ticks,
    },
    Roll {
        clip: u32,
        to: Ticks,
    },
    /// `clips` absent means "every unlocked clip the playhead is inside".
    Split {
        #[serde(default)]
        clips: Option<Vec<u32>>,
        at: Ticks,
    },
    Delete {
        clips: Vec<u32>,
    },
    RippleDelete {
        clips: Vec<u32>,
    },
    RippleDeleteRange {
        from: Ticks,
        to: Ticks,
    },
    /// `[from, to]` pairs rather than objects — the spelling `Color` and
    /// `Fps` already use for a fixed-shape array, and the one serde refuses
    /// at any other length rather than reading a stray third number.
    RippleDeleteRanges {
        ranges: Vec<[Ticks; 2]>,
    },
    LiftRange {
        from: Ticks,
        to: Ticks,
    },
    InsertTime {
        at: Ticks,
        length: Ticks,
    },
    CloseGap {
        track: u32,
        at: Ticks,
    },
    SetSpeed {
        clip: u32,
        rate: f64,
        #[serde(default)]
        keep_pitch: Option<bool>,
    },
    SetReversed {
        clip: u32,
        reversed: bool,
    },
    FreezeFrame {
        clip: u32,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
    },
    DetachAudio {
        clip: u32,
    },
    Duplicate {
        clips: Vec<u32>,
    },
    /// `payload` is opaque here and parsed by `edit_paste.rs`: it is the
    /// clipboard's own JSON, not an argument list, and the one place that
    /// knows its shape is the module that has to make it fit.
    Paste {
        at: Ticks,
        #[serde(default)]
        track: Option<u32>,
        payload: Value,
    },
    /// The same opaque `payload` as `paste`. `groups` absent means "every
    /// group both sides have"; an unknown group name is a serde error from
    /// the envelope, like any other bad enum value.
    PasteAttributes {
        clips: Vec<u32>,
        payload: Value,
        #[serde(default)]
        groups: Option<Vec<Group>>,
    },
    Nest {
        clips: Vec<u32>,
        #[serde(default)]
        name: Option<String>,
    },
    Unnest {
        clip: u32,
    },
    SetVideo {
        clips: Vec<u32>,
        patch: Value,
    },
    SetAudio {
        clips: Vec<u32>,
        patch: Value,
    },
    SetText {
        clips: Vec<u32>,
        patch: Value,
    },
    SetShape {
        clips: Vec<u32>,
        patch: Value,
    },
    /// The fifth patch op: `patch` is `{name?, label?}`, each a string or
    /// `null`, read by `edit_props.rs`. A patch rather than two envelope
    /// arguments because an envelope's absent and null mean the same thing
    /// and this op needs them to differ.
    SetClip {
        clips: Vec<u32>,
        patch: Value,
    },
    SetEnabled {
        clip: u32,
        #[serde(default)]
        video: Option<bool>,
        #[serde(default)]
        audio: Option<bool>,
    },
    /// An absent or null `kind` clears the transition.
    SetTransition {
        clip: u32,
        #[serde(default)]
        kind: Option<TransitionKind>,
    },
    SetTransitionDuration {
        clip: u32,
        duration: Ticks,
    },
    /// An absent `kind` means the clip's own stored kind if it has one, and
    /// `cross_dissolve` otherwise — never a clear, unlike `set_transition`,
    /// which is why this variant's `kind` is not nullable in the schema
    /// even though serde would accept a null into the `Option`.
    AddTransition {
        clip: u32,
        #[serde(default)]
        kind: Option<TransitionKind>,
        duration: Ticks,
        #[serde(default)]
        align: Option<TransitionAlign>,
        #[serde(default)]
        ripple: bool,
    },
    /// Both arguments are "absent means keep", so neither is nullable and
    /// an op carrying neither changes nothing.
    SetTransitionStyle {
        clip: u32,
        #[serde(default)]
        curve: Option<Curve>,
        #[serde(default)]
        audio: Option<bool>,
    },

    // ---- actions --------------------------------------------------------
    AddAction {
        clip: u32,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
    },
    /// The zoom's arguments are `add_action`'s plus the region it lands
    /// on. `region` is `Option` with a serde default so that an absent key
    /// and an explicit `null` mean the same thing — the envelope's rule —
    /// and here they mean a zoom BACK; a caller that wants an absent region
    /// REFUSED (the MCP tool does) says so in its own schema.
    AddZoomAction {
        clip: u32,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
        #[serde(default)]
        region: Option<ZoomRegion>,
        #[serde(default)]
        fit: Option<ZoomFit>,
        #[serde(default)]
        curve: Option<Curve>,
    },
    SetAction {
        clip: u32,
        action: u32,
        #[serde(default)]
        start: Option<Ticks>,
        #[serde(default)]
        duration: Option<Ticks>,
        #[serde(default)]
        curve: Option<Curve>,
    },
    SetActionEnd {
        clip: u32,
        action: u32,
        patch: Value,
    },
    RemoveAction {
        clip: u32,
        action: u32,
    },

    // ---- tracks, markers, canvas, media ---------------------------------
    AddTrack {
        #[serde(default)]
        index: Option<usize>,
        #[serde(default)]
        name: Option<String>,
    },
    RemoveTrack {
        track: u32,
        #[serde(default)]
        with_clips: bool,
    },
    MoveTrack {
        track: u32,
        index: usize,
    },
    SetTrack {
        track: u32,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        hidden: Option<bool>,
        #[serde(default)]
        muted: Option<bool>,
        #[serde(default)]
        locked: Option<bool>,
        #[serde(default)]
        solo: Option<bool>,
    },
    /// A struct variant with no fields, not a unit one, so that
    /// `deny_unknown_fields` applies to it like every other op.
    RemoveEmptyTracks {},
    AddMarker {
        at: Ticks,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        chapter: Option<bool>,
        #[serde(default)]
        color: Option<String>,
    },
    SetMarker {
        marker: u32,
        #[serde(default)]
        time: Option<Ticks>,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        chapter: Option<bool>,
        #[serde(default)]
        color: Option<String>,
    },
    RemoveMarker {
        marker: u32,
    },
    SetCanvas {
        #[serde(default)]
        width: Option<u32>,
        #[serde(default)]
        height: Option<u32>,
        #[serde(default)]
        fps: Option<Fps>,
        #[serde(default)]
        background: Option<Color>,
        #[serde(default)]
        rescale_clips: bool,
        #[serde(default)]
        fit_new_clips: Option<bool>,
        #[serde(default)]
        timecode_frames: Option<bool>,
    },
    AddMedia {
        descriptor: Value,
    },
    RelinkMedia {
        media: u32,
        path: String,
        #[serde(default)]
        bookmark: Option<String>,
    },
    RemoveMedia {
        media: u32,
        #[serde(default)]
        with_clips: bool,
    },
}

/// One parsed envelope: the op, and the nest it applies INSIDE.
///
/// A struct rather than a bare [`Op`] because `scope` is the envelope's
/// key and not any op's argument — it is spelled once, it means the same
/// thing over all fifty-seven, and folding it into the enum would mean
/// fifty-seven copies of one optional field. [`Project::apply_op`] still
/// takes an `&Op` and knows nothing about nests.
#[derive(Debug, Clone, PartialEq)]
pub struct Envelope {
    pub op: Op,
    /// The nest every id in `op` resolves against; `None` is the timeline.
    pub scope: Option<u32>,
}

/// Parses one op envelope.
///
/// Two passes on purpose. The first reads the `"op"` key out of a generic
/// value so that a missing, non-string or unknown name can be answered with
/// the list of names — the mistake a hand-written or generated op makes
/// most often, and the one serde's own "unknown variant" message states in
/// terms of the Rust enum rather than the wire format. The second is the
/// real deserialize, whose errors (missing field, wrong type, unknown
/// field) are already precise and are quoted under the op's name.
///
/// **`"scope"` comes out in that same first pass**, and it has to. [`Op`]
/// is internally tagged with `deny_unknown_fields` on every variant, so a
/// key the enum does not declare is an `Err` — that is the property a
/// misspelt argument is caught by, and it is not one to give up for an
/// envelope key. A `#[serde(flatten)]` wrapper is not the way round it
/// either: serde documents `deny_unknown_fields` as unsupported with
/// `flatten`, and it would silently stop refusing typos. Removing the key
/// before the typed decode keeps all three — the refusal, all fifty-seven
/// variants, and an envelope key that is not an argument.
pub fn parse(op_json: &str) -> Result<Envelope, String> {
    let mut value: Value =
        serde_json::from_str(op_json).map_err(|e| format!("op is not valid json: {e}"))?;
    let Some(object) = value.as_object() else {
        return Err(format!(
            "an op must be a json object, not {}",
            describe(&value)
        ));
    };
    let name = match object.get("op") {
        None => {
            return Err(format!(
                "an op must have an \"op\" name; known ops are {}",
                OP_NAMES.join(", ")
            ))
        }
        Some(Value::String(name)) => name.clone(),
        Some(other) => {
            return Err(format!(
                "an op name must be a string, not {}",
                describe(other)
            ))
        }
    };
    if !OP_NAMES.contains(&name.as_str()) {
        return Err(format!(
            "unknown op \"{name}\"; known ops are {}",
            OP_NAMES.join(", ")
        ));
    }
    let taken = value
        .as_object_mut()
        .and_then(|object| object.remove("scope"));
    let scope = scope::read(taken.as_ref())?;
    let op =
        serde_json::from_value(value).map_err(|e| format!("op \"{name}\" is not valid: {e}"))?;
    Ok(Envelope { op, scope })
}

impl Project {
    /// Applies one op envelope (the module table) and returns the new
    /// project, the arm of [`Outcome`] that says why it did not, or `Err`
    /// when the
    /// envelope or its arguments are invalid.
    ///
    /// With a `scope` the op runs inside that nest instead
    /// ([`crate::scope`]); without one this is the dispatch below and
    /// nothing more.
    pub fn apply(&self, op_json: &str) -> Result<Outcome, String> {
        let envelope = parse(op_json)?;
        match envelope.scope {
            None => self.apply_op(&envelope.op),
            Some(nest) => self.apply_scoped(&envelope.op, nest),
        }
    }

    /// The dispatch table. Deliberately nothing but calls: an op that needs
    /// adaptation gets it in the `edit_*` module that owns it, so that the
    /// JSON envelope and the semantics can never drift apart here.
    pub fn apply_op(&self, op: &Op) -> Result<Outcome, String> {
        match op {
            // ---- clips ---------------------------------------------------
            Op::AddClip { track, media, at } => self.add_clip(*track, *media, *at),
            Op::AddTextClip {
                track,
                at,
                duration,
                text,
            } => self.add_text_clip(*track, *at, *duration, text.as_ref()),
            Op::AddShapeClip {
                track,
                at,
                duration,
                shape,
            } => self.add_shape_clip(*track, *at, *duration, shape.as_ref()),
            Op::AddBackground {
                media,
                color,
                duration,
            } => self.add_background(*media, *color, *duration),
            Op::AddBlurredBackground { clip } => self.add_blurred_background(*clip),
            Op::InsertClip { track, media, at } => self.insert_clip(*track, *media, *at),
            Op::OverwriteClip { track, media, at } => self.overwrite_clip(*track, *media, *at),
            Op::MoveClip {
                clips,
                delta,
                track,
            } => self.move_clips(clips, *delta, *track),
            Op::TrimStart { clip, to } => self.trim_start(*clip, *to),
            Op::TrimEnd { clip, to } => self.trim_end(*clip, *to),
            Op::RateStretch { clip, to_end } => self.rate_stretch(*clip, *to_end),
            Op::Slip { clip, delta } => self.slip(*clip, *delta),
            Op::Roll { clip, to } => self.roll(*clip, *to),
            Op::Split { clips, at } => match clips.as_deref() {
                Some(ids) => self.split_clips(ids, *at),
                None => self.split_under_playhead(*at),
            },
            Op::Delete { clips } => self.delete_clips(clips),
            Op::RippleDelete { clips } => self.ripple_delete(clips),
            Op::RippleDeleteRange { from, to } => self.ripple_delete_range(*from, *to),
            Op::RippleDeleteRanges { ranges } => self.ripple_delete_ranges(ranges),
            Op::LiftRange { from, to } => self.lift_range(*from, *to),
            Op::InsertTime { at, length } => self.insert_time(*at, *length),
            Op::CloseGap { track, at } => self.close_gap(*track, *at),
            Op::SetSpeed {
                clip,
                rate,
                keep_pitch,
            } => self.set_speed(*clip, *rate, *keep_pitch),
            Op::SetReversed { clip, reversed } => self.set_reversed(*clip, *reversed),
            Op::FreezeFrame { clip, at, duration } => self.freeze_frame(*clip, *at, *duration),
            Op::DetachAudio { clip } => self.detach_audio(*clip),
            Op::Duplicate { clips } => self.duplicate_clips(clips),
            Op::Paste { at, track, payload } => self.paste(*at, *track, payload),
            Op::PasteAttributes {
                clips,
                payload,
                groups,
            } => self.paste_attributes(clips, payload, groups.as_deref()),
            Op::Nest { clips, name } => self.nest_clips(clips, name.as_deref()),
            Op::Unnest { clip } => self.unnest_clip(*clip),
            Op::SetVideo { clips, patch } => self.set_video(clips, patch),
            Op::SetAudio { clips, patch } => self.set_audio(clips, patch),
            Op::SetText { clips, patch } => self.set_text(clips, patch),
            Op::SetShape { clips, patch } => self.set_shape(clips, patch),
            Op::SetClip { clips, patch } => self.set_clip(clips, patch),
            Op::SetEnabled { clip, video, audio } => self.set_enabled(*clip, *video, *audio),
            Op::SetTransition { clip, kind } => self.set_transition(*clip, *kind),
            Op::SetTransitionDuration { clip, duration } => {
                self.set_transition_duration(*clip, *duration)
            }
            Op::AddTransition {
                clip,
                kind,
                duration,
                align,
                ripple,
            } => self.add_transition(*clip, *kind, *duration, *align, *ripple),
            Op::SetTransitionStyle { clip, curve, audio } => {
                self.set_transition_style(*clip, *curve, *audio)
            }

            // ---- actions -------------------------------------------------
            Op::AddAction { clip, at, duration } => self.add_action(*clip, *at, *duration),
            Op::AddZoomAction {
                clip,
                at,
                duration,
                region,
                fit,
                curve,
            } => self.add_zoom_action(*clip, *at, *duration, *region, *fit, *curve),
            Op::SetAction {
                clip,
                action,
                start,
                duration,
                curve,
            } => self.set_action(*clip, *action, *start, *duration, *curve),
            Op::SetActionEnd {
                clip,
                action,
                patch,
            } => self.set_action_end(*clip, *action, patch),
            Op::RemoveAction { clip, action } => self.remove_action(*clip, *action),

            // ---- tracks, markers, canvas, media --------------------------
            Op::AddTrack { index, name } => self.add_track(*index, name.as_deref()),
            Op::RemoveTrack { track, with_clips } => self.remove_track(*track, *with_clips),
            Op::MoveTrack { track, index } => self.move_track(*track, *index),
            Op::SetTrack {
                track,
                name,
                hidden,
                muted,
                locked,
                solo,
            } => self.set_track(*track, name.as_deref(), *hidden, *muted, *locked, *solo),
            Op::RemoveEmptyTracks {} => self.remove_empty_tracks(),
            Op::AddMarker {
                at,
                name,
                chapter,
                color,
            } => self.add_marker(*at, name.as_deref(), *chapter, color.as_deref()),
            Op::SetMarker {
                marker,
                time,
                name,
                chapter,
                color,
            } => self.set_marker(*marker, *time, name.as_deref(), *chapter, color.as_deref()),
            Op::RemoveMarker { marker } => self.remove_marker(*marker),
            Op::SetCanvas {
                width,
                height,
                fps,
                background,
                rescale_clips,
                fit_new_clips,
                timecode_frames,
            } => self.set_canvas(
                *width,
                *height,
                *fps,
                *background,
                *rescale_clips,
                *fit_new_clips,
                *timecode_frames,
            ),
            Op::AddMedia { descriptor } => self.add_media(descriptor),
            Op::RelinkMedia {
                media,
                path,
                bookmark,
            } => self.relink_media(*media, path, bookmark.as_deref()),
            Op::RemoveMedia { media, with_clips } => self.remove_media(*media, *with_clips),
        }
    }
}
