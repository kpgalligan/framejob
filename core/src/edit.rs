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
//! - **Caller-supplied timeline time arguments are snapped to the canvas frame
//!   grid** (usually round to nearest; `add_transition` floors its requested
//!   overlap), durations included, so a caller may pass a value
//!   computed from a pixel position without rounding it itself. A negative
//!   PROJECT time is clamped to 0 — a drag can start left of the timeline
//!   and there is no negative time there — while a negative LENGTH is an
//!   `Err`, and so is a negative CLIP time (`add_action`, `set_action`):
//!   the caller computes those as `playhead − clip.start`, so a negative
//!   one means the playhead is not on the clip, which is a caller bug and
//!   not a gesture to round off.
//! - **A shift moves every clip it moves by ONE delta** (spec §11 #42):
//!   the ripples, `close_gap`, `insert_time` and `move_clip` keep relative
//!   placement exact, so at a rate whose frame is not a whole number of
//!   ticks (7 fps) a moved start may sit a tick off the grid.
//! - **A linked pair moves as one in time** (spec §11 AU-90…AU-96):
//!   `clips[].linked` names a clip's partner, mutually and in one container.
//!   Every placement op takes the partner on an unlocked track with the clip
//!   it was given (its row says how), and `finish` clears any link left
//!   one-sided, so an op that removes or replaces half a pair needs no rule
//!   of its own. A linked clip's speed and direction are refused.
//! - **What an absent optional argument MEANS is said here**, in the
//!   Semantics column, and which arguments are optional at all is
//!   [`crate::op_table`]. An optional argument may be omitted. Most are
//!   `Option<T>` and decode an explicit `null` like absence; the eight
//!   defaulted plain booleans reject null and default to false when omitted.
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
//!   the three groups it may name are `video`, `audio` and `text` (and a
//!   graphic's props through a door of its own, G-34), and its
//!   paths carry the group (`unknown key "video.filters[1].kindd" in an
//!   action end patch`) — but its VALUES are not range-checked (a graphic
//!   prop's excepted, G-34 (c)), because an end state may name what no
//!   stored group could hold.
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
//! **Twelve ops are an `Err` with a scope**, naming themselves and the nest:
//! `add_marker`, `set_marker`, `remove_marker` (a nest has no markers of
//! its own — spec §5.2), `set_canvas` (a nest's size is FROZEN at the size
//! the parent had when it was made, deliberately, and the rest of a canvas
//! — the rate, the background, the two switches — is the document's), and
//! `add_media`, `relink_media`, `remove_media`, `set_media_color`,
//! `set_media_speech`, `set_media_cursor` (a nest
//! references the parent's `media[]` in the parent's one id space, so a
//! media edit inside a scope is an edit OUTSIDE it wearing a scope, which is
//! the one thing a scope exists to prevent), `add_adjustment_clip` (an adjustment clip
//! grades what is behind it at the top level only, spec §11 GR-6), and
//! `keep_range` (it keeps a range of the DOCUMENT's timeline, and is
//! applied only to a derived document, spec §11 CJ-50).
//! Everything else — all fifty-six — works
//! inside a nest as it works on the timeline, `nest` and `unnest`
//! included.
//!
//! ### Clips
//!
//! | Op | Semantics |
//! |---|---|
//! | `add_clip` | Whole media as one clip at `at`; source in 0, Fit scale when `canvas.fit_new_clips` and the source exceeds the canvas. The length is the media's snapped DOWN to whole frames, so the window stays inside the file and the segment plays at rate 1 (spec §11); a timed media shorter than one canvas frame is an `Err` naming the frame. A `lut` media is an `Err`: it is applied as a look, never placed (spec §11 GR-8). |
//! | `add_text_clip` | White, centered text in Source Sans 3 Bold at 72 px reading "Title", 5 s long when `duration` is absent; `text` patches it exactly as `set_text` would. |
//! | `add_shape_clip` | The default rectangle, 5 s long when `duration` is absent — an `arrow` kind gets `arrow_end` on, since a headless arrow is a diagonal line; `shape` patches that preset exactly as `set_shape` would, so an explicit `arrow_end: false` still wins. |
//! | `add_graphic_clip` | A clip drawn by the module `graphics/<name>.js` in the package, 5 s long when `duration` is absent, at `width` × `height` — the canvas's when absent, and an `Err` naming the canvas when a canvas side is over 8192 — with Fit scale as a shape's box has, `in` 0 and no `length`. `name` must match `^[a-z0-9][a-z0-9-]{0,62}$` (G-3); the core has no filesystem and never checks the module exists. `props` (absent: none) is checked against `schema` when one is given — key by key, by dotted path, type, range and membership, a colour normalised to lowercase `#rrggbb[aa]` — and for shape only without one (G-4); a `null` prop is dropped, and more than 64 is an `Err`. |
//! | `add_adjustment_clip` | A clip with no picture of its own (`{"kind":"adjustment"}`), 5 s long when `duration` is absent, at scale 1 with default `video`: while it lasts its `video.color`, point filters and opacity (the strength) grade everything drawn behind it in its container, the canvas background included, never a track in front; on a track cut by a matte only inside the matte, and on a matte track nothing (spec §11 GR-6). An `Err` inside a scope; refused onto an overlap in the overlap rule's sentence. It takes no transition, nest, blur, sharpen, pixelate or blend (`edit_adjustment.rs`). |
//! | `add_background` | A backdrop on a NEW back-most track, starting at 0, named "Background" and as long as the timeline unless `duration` says otherwise. With `media`, that file placed as `add_clip` would place it but for its SCALE — the right source kind, audio props when it has sound, and a FILL scale where `add_clip` takes a Fit one, because a plate that leaves the canvas showing down one side has failed at the one thing a background is for; with `color`, or with neither, a canvas-sized filled rectangle with no stroke at scale 1. The plate default is WHITE, not black: the canvas is already black, so a black plate is a command that appears to do nothing. `Err` for `media` and `color` together, an unknown media, a media with no pictures, a colour outside 0–1, a duration under a frame, or a timed media shorter than one canvas frame — a plate of a video or an audio file is held to that file's own whole length, given duration or default, so it never outruns what it shows (spec §11, D4-4). A `lut` media has no pictures (GR-8). |
//! | `add_blurred_background` | The screencast backdrop: `clip` copied onto a NEW back-most track at the same start, duration, speed and source window — so the two play the same frames — scaled to FILL the canvas, centred, uncropped, blended `normal` and blurred at full strength. The copy is muted (`enabled` becomes `{video: true, audio: false}`, `detach_audio`'s pair read the other way) and drops its `audio.duck` — the one field of that group that lowers OTHER material, so a copy keeping it would duck the mix including the clip it came from — along with its transition, its actions and its label; it is named "Blurred Background". `Err` for an unknown clip, a NEST (flattening drops a nest clip's own filters, so the copy would come out sharp), a source with no pixel size (text, audio-only), or a clip with no video properties. |
//! | `insert_clip` | The insert edit: the clip `at` is strictly inside on `track` is split, every unlocked track opens by the media's whole length, then that media lands at `at`. Only the destination track is cut — straddlers elsewhere ride the shift whole — but for a cut clip's linked partner on an unlocked track, which is cut at the same `at` and its second half paired with the cut clip's (AU-92). A `lut` media is `add_clip`'s `Err`. |
//! | `overwrite_clip` | The overwrite edit: `[at, at + media length)` is cleared on `track` ALONE — cut at both bounds, the middles removed — and the media lands there. Nothing shifts and no other track is touched but for a cut clip's linked partner on an unlocked track, which is cut at the same bounds and paired (AU-92); the partner's middle piece stays, unlinked. A `lut` media is `add_clip`'s `Err`. |
//! | `move_clip` | Shifts the selection by `delta`, clamped so the earliest clip stops at 0; `track` retargets by track-index delta, keeping relative offsets. A linked partner on an unlocked track moves with its clip by the same delta, the clamp at 0 taken over both so a sound lead is kept; only the clips named change track, so a partner keeps its own (spec §11 AU-91). |
//! | `trim_start` | New start `to`; a media `in` advances by `(to − start) × speed`. Clamped to the source head — snapped UP to a whole frame, so a floored `in / speed` cannot write a sub-frame start (spec §11, D4-5) — and to one frame before the end. `text.words` are rebased by `to − start`, unlike actions: a word stays on its speech (spec §11, W-3). A graphic's `in` advances by `to − start` (no speed, no head bound), never below 0 (G-9). On a ramped clip the speed actions stay in clip time, `in` advances by round(S(to − start)) moving in and at the base rate moving out, and the edge is held at a fitting frame between `to` and the clip's current start, found by bisection on the frame grid (SR-18 (c)). `alone` (false when absent): without it, a linked partner on an unlocked track whose start equals this clip's is trimmed to the same `to` after it, by its own clamps, and a refusal from either is the answer; with it, the clip moves alone — the J-cut (AU-93). |
//! | `trim_end` | New end `to`, clamped to `start + one frame` and to the source's remaining length, that bound snapped DOWN to a whole frame so a trim cannot put the end past the file (spec §11). A graphic's `length` is untouched (G-9). On a ramped clip the bound reads S∞, the map run on past the end; the speed actions are untouched (SR-18 (a)). `alone` as `trim_start`'s, for a linked partner whose end equals this clip's — with it, the L-cut (AU-93). |
//! | `rate_stretch` | `speed = content length / (to_end − start)`; duration follows and actions rescale. On a ramped clip the whole rate profile scales by f = D ÷ (to_end − start) — base, end rates and the speed actions' spans, unclamped — and an f taking any rate past the limits is an identity (spec §11 SR-19 (a), (b)). A non-media source is an `Err`, not a refusal. Refused on a linked clip (AU-94). |
//! | `slip` | Slides the source under a fixed clip: `in += delta × speed`, start and duration unchanged, clamped so the window stays inside the media. A `still` moves its `at` instead. A slip the clamps reduce to nothing is an identity; a source with nothing to slip is an `Err`. On a ramped clip the delta is at the base rate, the tail clamp `file − S(D)`, the speed actions unmoved (SR-18 (d)). A linked partner on an unlocked track slips with it, both by the smaller in magnitude of the two clamped amounts (AU-94). |
//! | `roll` | Moves a hard cut: this clip's start and its predecessor's end both become `to`. The predecessor is the clip on the track ending EXACTLY at this one's start; with none — a gap, or an overlap, whose length is `set_transition_duration`'s — it refuses. Clamped to one frame and to the source available on each side. This clip's `text.words` are rebased by the move (W-3). This clip's `graphic.in` advances by the move as `trim_start`'s does; the predecessor's `length` is untouched (G-9). Ramped clips keep their speed actions: this clip's `in` moves and its edge is held as `trim_start`'s, the predecessor's bound reads S∞ (SR-18). `alone` (false when absent): without it, a linked partner on an unlocked track whose start equals this clip's and which has a hard-cut predecessor of its own is rolled to the same `to` after it (AU-93). |
//! | `split` | Cuts at project time `at`. With `clips` absent, cuts every clip on an unlocked track that `at` is strictly inside. The second half keeps every `text.words` entry rebased by the cut (a negative start is legal); a second half whose evaluated content has a different token count stores `words: []` instead — a half is a clip the door must accept again (W-3). The first half's words are untouched. A graphic's second half gets `in + (at − start)` and BOTH halves' `length` are pinned to the original's effective length (`length`, or `in + duration` when null) — G-9. On a ramped clip the halves meet at the source read by the cut, `in + round(S(at − start))`, the second half at the rate there; a straddled speed action's first half ends at the solved rate that reads it, its second half at the original end rate, an `ease_in`/`ease_in_out` one lowered to the largest that fits when it would read past the file (SR-18 (e)). A linked partner on an unlocked track is cut too: both cut, the second halves are linked; the partner not cut, it stays linked to the half sharing more of its time, the first on a tie (AU-92). |
//! | `delete` | Removes the clips; the gaps stay. A picture takes its linked sound on an unlocked track with it; a linked sound half (picture off) named alone goes alone, its picture staying silent (AU-91). |
//! | `ripple_delete` | Removes, then closes each removed span across every unlocked track. Markers do not move. Each clip's linked partner on an unlocked track is removed too, either half named (AU-91). |
//! | `ripple_delete_range` | Splits every unlocked clip at both bounds, removes the middles, then closes the hole. A reversed range is the same range. Every shift (this, `ripple_delete`, `ripple_delete_ranges`, `close_gap`, `insert_time`, `add_transition`'s ripple form) moves each moved clip's linked partner on an unlocked track too, and refuses, nothing moved, when that would take a partner below 0: "clip S would start before 0: it leads its linked clip P by N ticks" (AU-91). |
//! | `ripple_delete_ranges` | Several `[from, to]` pairs as one edit — the silence cut. Each pair is snapped, clamped and ordered as `ripple_delete_range`'s one is, the pairs are then MERGED (touching as well as overlapping) and the survivors cut and closed right to left, so the op is merge-then-cut and not N `ripple_delete_range`s. Markers do not move. An empty list, and one that merges to nothing, change nothing. Refuses as `ripple_delete_range` does when a shift would take a linked partner below 0. |
//! | `lift_range` | `ripple_delete_range` without the close: every unlocked clip is split at both bounds and the middles removed, and nothing moves. A reversed range is the same range. |
//! | `keep_range` | The project as `[from, to)` of its top-level timeline, moved to start at 0 (spec §11 CJ-50, `edit_keep_range.rs`): both bounds snapped and clamped to 0, `to` not after `from` an `Err`; every clip on every track, locked or not, cut at both bounds by `split`'s rules; at an edge inside a transition the piece beyond the edge is dropped and the incoming piece starting at `from` hard-starts (no `transition_in`), the incoming piece kept when both bounds lie in one overlap; clips not wholly inside removed, the rest and the markers inside moved by −`from`, markers outside removed; nests no kept clip reaches and media no kept clip plays, names in a look or converts through removed; tracks and canvas unchanged. Refused: a nest clip across an edge, nothing left to play, and a transition inside the range whose clip an edge cut too short for it. Document-level, with no tool: it is applied to a derived document only (CJ5b). |
//! | `insert_time` | Opens a hole: every unlocked clip, and every marker, at or after `at` moves right by `length`. |
//! | `close_gap` | Closes the empty span on `track` that contains `at`, bounded by the nearest clip edges there: everything from its far side shifts left by its length, across every unlocked track. Refuses on a locked `track`, on an `at` that is on a clip, with no clip after the gap, and when the shift would break the overlap rule — a gap closes fully or not at all. A linked partner of a moved clip moves too, and a partner the shift would take below 0 refuses (AU-91). |
//! | `retime_range` | Plays `[from, to)` at `rate` on every unlocked track and moves everything after it up or back to stay in step, one undo step (spec §11 CU-90). Both bounds are snapped and clamped to 0; `f(t) = snapped(from + round((t − from) ÷ rate))`. Both bounds are cut by `split_under_playhead`; each piece wholly inside starts at `f(s)` and lasts `f(e) − f(s)`: a constant media piece plays at speed × `rate`, held to its media, a ramped one scales its whole profile by `rate` (SR-19), and a text, shape, still, image, graphic (its `length` kept) or adjustment piece scales its start and duration; actions keep their fraction; `keep_pitch`, when given, is set on each media piece's audio. Everything at or after `to` moves by `to′ − to` with its linked partners (AU-91); markers inside map through `f` and markers after move with the shift (none inside a nest). A `rate` of 1 is an identity. `Err` for a rate that is not a positive number and a `to` not after `from` on the grid. Refused, in this order: a rate past ×0.1–×1000; a range under two frames; a locked track holding a clip that ends after `from`; a nest clip, a caption page with timed words or a linked clip (AU-94) in the range; a transition touching `[from, to]`; two markers landing on one tick; a piece whose rate would pass the speed limits (naming the rate) or that would last under one frame. |
//! | `set_speed` | Two arms, exactly one given: a `rate`, or a `duration` to fit, which is snapped, held to a frame and turned into `content length / duration` (the current duration keeps the current rate). Both or neither is an `Err`. Either rate is clamped to `SPEED_MIN`–`SPEED_MAX`; then `duration = content length / rate`, snapped NEAREST and held to what the file still holds AT THAT RATE, so the segment plays at exactly `rate` (spec §11, D4-3); actions keep their clip-relative fraction. Above `AUDIO_SPEED_MAX` (×12, both pitch modes) the plan leaves the clip's audio out (spec §11, #190). On a ramped clip one factor f (the clamped rate ÷ `speed`, or D ÷ d), clamped so no rate the clip names passes a limit, scales the base, every end rate and every speed action's span, unclamped into the clip, and the duration is held through S∞ (spec §11 SR-19 (a)–(c)). A non-media source is an `Err`, not a refusal — see "The non-media rule" under Results. Refused on a linked clip when its rate would change (AU-94). |
//! | `set_reversed` | Plays the media back to front, or forward again. A FACT about the clip, not a plan change: Swift substitutes a pre-rendered reversed asset (spec §11). The in point is measured in the direction the clip plays, so reversing keeps `in` and therefore shows different frames. A non-media source is an `Err`, not a refusal. Refused on a linked clip (AU-94). |
//! | `freeze_frame` | `split` at `at`, `insert_time(at, duration)` (2 s when absent), then a `still` of that source frame with the clip's video props evaluated at `at`. On a ramped clip the still holds `in + round(S(at − start))`, where the split's halves meet (SR-18 (f)). |
//! | `detach_audio` | Clears the clip's `enabled.audio` and puts an audio-only twin on the track below, inserting a track when there is none. Refuses, naming why, on a clip with no audio to detach: not a media clip, media with no audio track, or audio already switched off. A ramped clip's twin copies every action whole, so it reads the same map (spec §11 SR-19 (e)). The two clips name each other in `linked` (spec §11 AU-90) and are a linked pair from then on. |
//! | `attach_audio` | Merges a linked picture and its detached sound back into one clip; either half may be named (spec §11 AU-95). Refuses, each in its own sentence: a clip not linked to a detached sound ("clip C is not linked to a detached sound"); a pair that is not one half with its audio off and one with it on ("clips A and B are not a picture and its detached sound"); and a pair whose start, duration, source, speed or actions' spans and curves differ ("clip V's picture and clip S's sound do not cover the same time; trim them to match before Attach Audio"). Otherwise the picture's `enabled.audio` turns on and it takes the sound's `audio` group and, action by action at the same index, its `end.audio` (removed where the sound's action has none); its `linked` is cleared and the sound clip is removed, its track staying. |
//! | `duplicate` | Copies each clip, with fresh ids: one selection-span later on its own track, or by `delta` and to `track`, which `move_clip` reads the same way (spec §11 #465). The overlap rule is asked once, at the landing. A linked partner on an unlocked track is copied too and the copies are linked to each other (AU-96); only the clips named change track, so a partner's copy keeps its own, and it counts for the rule. |
//! | `copy_pieces` | Copies `clip`'s pieces between each of `ranges`' project times onto `track` at the same times (spec §11 SW-11, SW-12), each piece exactly the middle a `split` at its two ends would leave, with fresh ids, no transition and no link; `video` and `audio`, when given, set each piece's `enabled`. Each pair is put in order and snapped, a range empty on the grid dropped (none left is an identity), the rest sorted. `Err` for an unknown clip, then track. Refused, in order: a nest clip, a range outside the clip, overlapping ranges (touching is allowed), a locked destination, a destination holding a clip over a range. Allowed inside a nest. |
//! | `paste` | Inserts the clips of a clipboard payload — `{"clips": […], "media": […], "nests": […]}`, what Copy wrote, `nests` only when a clip shows one — with fresh ids, the earliest landing at `at` and the rest keeping their offsets. A payload clip's `track` is a DEPTH from the front (0 = front-most), so `track` says where depth 0 lands (default: the front) and the rest follow by the same index delta; tracks missing behind it are added. Media is matched to `media[]` by path and appended when absent. A clip the overlap rule refuses goes on a new track in front; an empty clip list changes nothing. Every landed clip — the payload's own and those inside the nests it brings — first has every group pass `paste_attributes`' normalise-and-check on what the payload sent (an empty motion lands null; a value out of range is an Err, `pasted clip N: …`, N the payload's id; a speed outside ×0.1–×1000 gets the same `pasted clip N: …` Err), then has its start, source-bounded duration, action spans, present base motion/text timings and a graphic's `in` and `length` re-snapped to this document's grid (spec §11, D7-3, G-18); a ramped clip's speed actions are snapped, not clamped, and its duration held again (SR-19 (f), (g)). A payload clip's `linked` is mapped to its partner's fresh id, top level and in each copied nest; one whose partner the payload lacks is cleared (AU-96). |
//! | `paste_attributes` | Copies the payload's EARLIEST clip's property groups (at one start the front-most, then the lower id — never the array's first, which is creation order) onto each clip: video and audio whole, text but content and the `words` that time it (W-6), shape but kind, width, height, from and to. Default (no `groups`): each of those four both sides have, and `skip_missing` changes nothing; a named group either side lacks is an Err. Copied video motion and text animation pass their original-value range checks, then snap to the target grid; audio envelopes keep sample precision. Speed, enabled, actions, transition and identity stay, so a ramp is never carried and no window changes (spec §11 SR-19 (f)). `graphic` is a fifth group a caller NAMES, never a default (G-32, amending G-10): a side has it when it is a graphic clip, and a target takes it when its module is the payload clip's. It copies `props` whole — a key the payload lacks is removed unless an action on the target names it (G-34 (d)), a key both have keeps its slot, new keys are appended — and the target keeps its module, size, `in` and `length`; a target that is not a graphic is `clip N has no graphic properties`, and one drawn by another module an Err naming both modules. `skip_missing: true` (with `groups` named) drops a named group the payload clip lacks and skips, for that group, a target that cannot take it, for all five groups — no Err for a missing group. The copied props are checked for shape only (strings, numbers and booleans, at most 64 keys, `null`s dropped), once, the first time a target takes them: a paste in which no target takes `graphic` never reads them, and a malformed map onto a target that takes it is `model_graphic.rs`'s own Err in both modes. An identity when nothing changes. |
//! | `nest` | Collapses the selection into ONE clip showing a nest named `Nest <n>` unless `name` says otherwise, on the front-most track the selection occupied, running from the earliest start to the latest end. The clips move whole — ids, props, actions, transitions — keeping their relative times (earliest → 0) and their track order; the nest's canvas is frozen at the project's current size. Refuses on an empty selection, on a lone nest clip, and when the nest clip would break the overlap rule. A linked partner on an unlocked track goes into the nest with its clip (AU-91). |
//! | `unnest` | The inverse: the nest's clips return at `clip.start + their own start`, with fresh ids, on tracks counted back from the nest clip's own (front-most nest track first), and the nest clip goes. `nest` then `unnest` is the identity on clip content, ids aside. A clip the overlap rule refuses lands on a new track in front, as `paste` does; a nest clip trimmed shorter than its contents gives ALL of them back (a nest has no in point); the nest is dropped when nothing else shows it. Returning clips have translated start, source-bounded duration, action spans and present base motion/text timings normalized on the document grid (spec §11, D7-3); a ramped clip's speed actions are snapped, not clamped, and its duration held again (SR-19 (g)). `Err` when `clip` is not a nest clip. The returning clips' links are mapped to their fresh ids (AU-96). |
//! | `set_video` | Merges the patch into each clip's video props (spec §5.2). |
//! | `set_audio` | Merges the patch into each clip's audio props. |
//! | `set_text` | Merges the patch into each clip's text props. It can patch `case`, `words` and `word_style` like any declared key (W-10); a non-empty `words` whose length is not the content's `split_whitespace` count, a word time outside D7-1's envelope, an `end` before its `start`, a start before the previous word's, or a `word_style` value out of range is an `Err` naming the key and the number sent, before the times are snapped to the grid (W-2, W-3). |
//! | `set_shape` | Merges the patch into each clip's shape props. |
//! | `set_graphic` | Patches each graphic clip's `name`, `width`, `height`, `length` (`null`: it ends with the clip, `in` + the clip's duration; else snapped, at least one frame) and `props` — merged key by key, a `null` removing its key and the others keeping their order, checked as `add_graphic_clip` checks them against `schema` when one is given, and at most 64 once merged. With a `schema`, a `null` for a prop an action on the clip names stores the schema's default instead, so the ramp keeps its start (G-34 (d)); without one it removes. `in` is an `Err` (`trim_start`, `roll`, `split` and `add_transition` move it), and so is a clip that is not a graphic. An identity when nothing changes, a colour re-sent in another spelling included. |
//! | `set_clip` | Sets or clears the clip's own name and label; absent keeps, null or an empty string clears. Unknown keys are an Err. A split, duplicate, detach or paste carries both. An identity when nothing changes. |
//! | `set_enabled` | The per-clip hide and mute switches; omitted fields keep their value. |
//! | `set_transition` | Sets `transition_in`; absent or `null` clears it. The overlap with the predecessor IS the duration. |
//! | `set_transition_duration` | Moves the clip so its overlap with its predecessor is exactly `duration`. Refuses on the first clip of its track, and on a duration past the pair's overlap limit (half the shorter clip, snapped down), naming the limit. |
//! | `add_transition` | Makes an overlap at the HARD CUT before `clip` out of the two clips' unused handles and puts a transition on it — nothing else on the timeline moves. `align` is `center` when absent: half from each side (the odd frame to the incoming clip) and passes a side's shortfall to the other; `before` takes it all from the incoming clip's head, `after` all from the outgoing clip's tail. The duration is snapped down to whole frames and CLAMPED — to each handle, to the neighbours on the track, and to the overlap rule — so a request too long for the material lands shorter rather than refusing; a request under one frame of the canvas's grid refuses first, naming the shortest duration that passes, and one that clamps below a frame refuses. A nest gives no head, and a nest tail ends at the nest's own length. The incoming clip's actions and `text.words` move with its new first frame; a graphic's `in` moves back by the head, saturating at 0 (a graphic's head is unbounded, G-18). `kind` absent uses the clip's stored kind if it has one, else cross_dissolve; a stored transition keeps its curve and crossfade, a new one is minted (eased, crossfading). A ramped incoming clip's head reads at its base rate and its speed actions move with its first frame; a ramped outgoing clip's tail reads S∞ (SR-18 (a), (b)). Err for a non-positive duration, an unknown clip, and for not being at a hard cut — naming which of no predecessor, a gap, an existing overlap. `ripple` (false when absent): when true no handle is read and `align` is ignored — the overlap is made by SHIFTING the incoming clip and every clip at or after it on every unlocked track left by the duration counted in whole frames of the canvas's grid and landed on it (§11 #42), so the timeline gets shorter and no source window changes; the duration is capped at half the shorter of the two clips and the greatest passing whole-frame shift is selected without enumerating frames, even when a crossing makes a larger shift valid again, another track's clip that gains an overlap gets a minted cross_dissolve (`close_gap`'s rule), markers do not move, and an incoming clip on a locked track refuses. An already-invalid affected track refuses by the overlap rule before fitting; an unrelated track is ignored. |
//! | `set_transition_style` | Sets the transition's easing, whether it crossfades the two clips' sound, and the crossfade's shape (`audio_shape`, format 29, spec §11 AU-115: `plus_3db`, R5-2's constant power, by default; `linear`, `s_curve`, `minus_3db`); an absent key keeps. A clip with no stored transition and at least one key given gets a minted `cross_dissolve` with the style applied; NO key given is an identity and never mints. A separate op from `set_transition` because that one reads an absent `kind` as a clear and so cannot spell "keep". |
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
//! | `add_speed_ramp` | A speed ramp preset in one step (spec §11 SR-23, #340), made of ordinary Speed actions (`end.speed`, SR-10). `shape` is `ramp_up`, `ramp_down`, `speed_dip` or `speed_burst`; `from` and `to` are CLIP time, both given or both absent (the whole clip, [0, D)). The base b is the rate the clip plays at `from` before the edit. Up and Down are one action [from, to) ending at `rate`; Dip and Burst are two, of r = max(snapped_down((to − from)·(1 − hold)/2), one frame) each, [from, from + r) ending at `rate` and [to − r, to) ending at b, the span between holding the target. `hold` (Dip and Burst only) is clamped to 0–0.9, 0.5 when absent; `curve` is every new action's, `ease_in_out` when absent. A positive `rate` is clamped to ×0.1–×1000. `Err` on an unknown or non-media clip, a non-positive rate, one of `from`/`to` alone, a negative `from`, `to` not after `from`, and a `hold` on Up or Down. Refused, in order: `to` past the clip (`add_action`'s sentence); any action the span [from, to) runs into, named — a hold gap included; a Dip or Burst under two frames; a rate not above b (Up, Burst) or not below it (Down, Dip); and a preset that would read past the end of the media (SR-2), naming the largest rate that fits. `edit_action_ramp.rs`'s module doc. |
//! | `switch_layout` | Camera layouts at the playhead (spec §11 CO-60…CO-65, `edit_layout.rs`'s module doc): the `camera` clip and the `screen` behind it placed in `layout` — `corner` (`shape` `square` (absent), `rounded` or `circle`; `corner` `bottom_right` (absent), `bottom_left`, `top_right`, `top_left`), `side_by_side`, `stacked`, `camera_full` or `screen_only` — each role written all six placement keys (`x`, `y`, `scale`, `crop`, `corner_radius`, `opacity`) solved by `layout.rs`. Per role the clip under `at` gets a LAYOUT ACTION at clip time `at − start` of `duration` (0.5 s when absent) and `curve` (`ease_in_out` when absent), clamped to the clip and the next later layout action on it, at least one frame; at the clip's first frame the layout is its base plus a one-frame layout action at 0 ending there. A layout action on it starting at `at` is replaced; one running at `at` is shortened to end there. The REACH runs to the first later layout action on the role's track, `through`, or the track's end: every picture clip starting inside it takes the layout as its base and keeps its actions. `screen` absent: the clip playing at `at` on the front-most shown, non-matte track behind the camera's with a drawn picture; none leaves the camera alone (`side_by_side` and `stacked` refuse). `focus` is the camera crop's centre in source pixels from the uncropped centre, y down, `[0, 0]` when absent. `Err` on a negative `at`, a non-positive `duration`, `through` not after `at`, a non-finite `focus`. Refused, in order: a camera (then a screen) with no picture or not playing at `at`, a screen not behind the camera; no screen for `side_by_side`/`stacked`; a nest-clip camera asked for `rounded` or `circle`; a role clip in the reach with a non-layout action that moves it and ends after `at` (a screen at its full placement exempt in `corner`, `camera_full` and `screen_only`), naming it — with `nest: true` the moving role's clips are nested first, refused when one is already laid out; then `add_action`'s own. One undo step. |
//! | `reframe_clip` | Frames one clip on the current canvas (spec §11 VR-20…VR-27, `edit_reframe.rs`'s module doc): `follow` `subject` (faces, then people, then salient regions), `face`, `person` or `salient` follows the analysed `subjects` (`{samples: [{t, faces?, people?, salient?: [{x, y, w, h, c}]}], shots: [t]}` in forward-media SOURCE ticks, boxes 0–1 of the upright picture from its top-left; read strictly, an object at every level) with `reframe.rs`'s planner — eased moves out of a dead zone, a hard cut at each shot change, a lost subject held 1 s then another followed or an 0.8 s ease to `where_empty` (`fit`, the whole picture, when absent; `center`, the window on the picture's centre), two people framed together when they fit; `cursor` (VR-50) follows `subjects.cursor` (`[{t, x, y, click?, typing?}]`, the same ticks and frame, `click` and `typing` false when absent) with `reframe_cursor.rs`'s planner — the window on the pointer clamped to the picture, a dead zone ±0.20 of its width and ±0.12 of its height, a down click outside it arriving in a move that ends on the click's frame, a typing stretch holding the window, no cut and no `fit`; `speaker` (VR-60, VR-61) frames a wide shot on whoever speaks with `reframe_speaker.rs`'s planner: `mics` (2–4 media clips with sound, each on its own track, not the clip) and `subjects.turns` (`[{from, to, mic}]` in CONTAINER timeline ticks, `mic` one of `mics`; `from` < `to`, starts never going back) say who speaks when, and each face box's `mouth` (gap ÷ width, ≥ 0, faces only) says whose mouth moves; the faces are the clip's face tracks chained across gaps (IoU ≥ 0.3), each in at least a quarter of the samples, at most four, numbered 1… left to right; each microphone is matched to the face whose mouth activity (its standard deviation over ±0.25 s) agrees best with its turns (Pearson's r, the injective map with the greatest sum, ties to the lowest face numbers), or to `mic_faces[i]` (its face number, in `mics`' order) when given; the turns cut the clip into segments — one speaker frames their face, nobody holds the last, two or more frame the pair when both widened faces fit, else the one already framed — and a segment under 2 s joins the one before it (the first, the one after); each segment start is a hard cut, VR-23's moves within; `zoom`, `where_empty`, `backdrop` and `replace` read as for `face`; `center` holds the window (fill × `zoom`, 1 when absent) on the picture's centre and `fit` the whole picture for the whole clip; `keep` rescales the base from `from_width × from_height` (the canvas when absent) by `set_canvas`'s rule; `layout` (VR-53) re-lays a camera clip's camera layouts and its screen's on the current canvas: the group is the closure over pairing (a camera action at T with the layout action starting at T on the front-most track behind it holding one; a laid-out clip is a screen when one in front holds a layout action at one of its starts) plus each switch's pieces (same source, `in` ignored, on a role's track after its action and before the track's next one, the base within tolerance of its end); each switch is recognised on `from_width × from_height` (the layout, shape and corner whose solve gives the camera end and the screen end within 1 px in x, y, crop and radius and 0.001 in scale and opacity, the camera's crop centre as `focus`), every member's base takes `keep`'s rescale, the layout actions are removed and the switches composed again as `switch_layout` composes them, in time order at the camera action's start, with the duration and curve of the longest role action not at its clip's first frame (else the camera's), `side_by_side` as `stacked` on a canvas taller than wide, each role's pieces as its later clips; every other moving end of a member is re-based from the placement in effect at its start to the new one (r = new scale ÷ old: x' = new x + r·(x − old x), y likewise, scale·r). The path is composed into the clip (`reframe_compose.rs`): the base takes its first key composed with the placement, an action end naming `x`, `y` or `scale` (or one the framing changes across) takes the framing at its end composed with the clip's placement there, and each later change of value is one action, ends `{video: {scale, x, y}}`, scheduled around the clip's actions — its own in a gap, shifted up to 0.5 s earlier, else carried by the action it overlaps along that action's curve; a cut splits the action it lands in (head, a one-frame `linear` piece, tail, each other key narrowed from the evaluated state), except one naming `speed` or running past the clip's end, which carries it; new ids in time order. `replace: true` (absent `false`; every follow but `keep`) first removes `x`, `y` and `scale` from every end (an end left empty removes its action) and sets the base to the picture fitted. `keep` also rescales each `x`, `y` and `scale` an end names. `backdrop`: when the framing shows `fit` anywhere, one blurred copy of the whole clip (`add_blurred_background`'s builder) on that track when it is unlocked, not a matte and free over the clip, else on a new back-most track (ids: actions, track, copy), keeping the clip's speed actions narrowed to `speed`. Only `keep` and `layout` read `from_*`; `layout` reads no `zoom`, `where_empty`, `backdrop`, `replace` or `subjects`; `fit` and `keep` ignore `zoom`; only the following kinds and `speaker` read `where_empty`, and they and `cursor` read `subjects` (a face follow never reads its `cursor`); only `speaker` reads `mics` and `mic_faces`. `Err`, in order: an unknown clip; `zoom` not finite or outside 1–4; a `from_*` of 0; an unknown `backdrop` track; `subjects` not the strict object; for `speaker`, an unknown clip in `mics`. Refused, in order: a follow other than `keep` on a text, shape, graphic or adjustment clip; a media with no picture, or a crop or scale leaving none; for `layout`, no layout action on the clip ("clip {id} holds no camera layout to re-lay; frame it with subject, center, fit or keep"), a group clip both a camera and a screen, a screen action with no camera switch in front of it (the earliest), the first switch not recognised, then a composed op's own refusal; a nest clip, then a still or image clip, with a following kind, `cursor` or `speaker`; `cursor` on a media clip whose media has no cursor file, and a following kind on one whose media has one (VR-51); unless `keep` or `layout`, a clip on a matte track or cut by a matte, then a base rotation, an action end turning it, or a `spin` motion; for `speaker`, `mics` not 2–4 clips, a clip named twice, the clip itself or a clip with no sound from a media file, a clip whose sound is off, two on one track, `mic_faces` not one per microphone, a 0 or a face named twice; bad `subjects` (over 100,000 samples, over 8 boxes of a kind, times not strictly increasing, a value outside 0–1, a size ≤ 0; over 100,000 cursor points, cursor times not strictly increasing, a cursor `x` or `y` outside 0–1); when a copy would be made, a nest clip or a `backdrop` track not behind the clip's; last, a following kind, `cursor` or `speaker` with no `subjects`, or no sample (no cursor point) in the played window; then for `speaker`, a turn naming a clip not in `mics`, a shot change inside the played window, fewer faces than microphones, a `mic_faces` number past the faces found, no turn inside the clip, and with no `mic_faces` a match whose weakest pair agrees under 0.2, naming each face's place across the picture. A result equal to the clip is an identity. Allowed inside a nest, whose canvas is the view's. |
//! | `set_action` | Retimes or re-curves one action; omitted fields keep their value, same overlap checks. Refused (`action_past_end`) only when the new end is past the clip's end AND later than the action's end before the edit (spec §11 SR-22, #338): an action already past the end can be re-curved, moved earlier or shortened, and one inside the clip cannot be pushed past it. When the action's end names a `speed` (spec §11 SR-10) and the change would make the clip read past the end of its media it is refused (SR-2, R3), naming the latest clip end that fits. |
//! | `set_action_end` | Merges into the action's `end` patch; a key set to `null` is removed from it, at any depth. Walked for keys and kinds like every other patch, over the three groups §5.4 allows (a `shape` object is an unknown key); values are NOT range-checked, except a graphic prop's (G-34 (c)). A `video` object naming `motion` is an `Err`, and so is a `text` object naming `words`, a `null` included (W-6). `off` (absent or `null`: none) is a list of `"group.key"` paths written as `null` AFTER the merge — the optional property keyed OFF at the end, where a `null` in `patch` removes (spec §11 CI-14); each is an `Err` when malformed, when it is `video.motion` or `text.words` (the same two sentences), when it names a key the group lacks or a required key, and when `patch` names it too. Two three-part paths are taken beside them: `audio.eq.<slot>` (AU-88) and `video.qualifier.<range>` (GR-36), a range of `hue`, `saturation` or `luma`, each stored as a `null` inside that object; an unknown slot or range is an `Err` naming the list. A `graphic` object is a graphic clip's props as a fourth target (G-34): `{props: {<key>: <value>}}`, each non-null prop checked as `set_graphic` checks it against `schema` (the module's current revision, which the app fills) under `graphic.props.<key>` — no schema, a prop the schema lacks and a prop its module marks `animate: false` (G-41) are each an `Err` naming the prop, and so are `name`, `width`, `height`, `in` and `length` — and its schema `type` written into `kinds`; a `kinds` in the patch is discarded. A number and a colour ramp, anything else — an `asset` included, `""` naming no image (G-42) — switches at the end. A prop the clip's own `props` lacks gets the schema's current default appended in the same step. `graphic: null` or `graphic.props: null` removes the group; a `null` prop removes it and its kind, unchecked. `graphic` in `off` is an `Err`: "graphic props cannot be keyed off; name the value a prop ends at in patch". `speed` (format 27, SR-10) is a media clip's rate as a fifth target, a number at the patch's top beside the groups, stored clamped to ×0.1–×1000; `null` removes it and `off` cannot name it. Any other JSON kind is an `Err` (`speed must be a number, not "fast"`), and so is a clip that is not a media clip. The clip keeps its start and duration (SR-2): an end rate that would read past the end of its media is refused naming the largest end rate that fits, floored to 0.001 (R1), or, when no rate down to ×0.1 fits, the latest clip end that fits at ×0.1 (R2); a `null` that would do so is refused naming the latest clip end that fits (R3). |
//! | `remove_action` | Removes the action. Refused when the action's end names a `speed` and the clip would then read past the end of its media (R3, spec §11 SR-10), naming the latest clip end that fits. |
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
//! | `set_track` | Omitted fields keep their value. `matte: "none"` switches a matte off (MT-1). `volume` (linear, 0–4, +12.04 dB at 4) and `pan` (−1–1) are the track's fader and balance, refused outside their ranges (spec §11 AU-102). `compressor` and `limiter` (format 36, AU-150) are the track's dynamics, post-fader on its sub-mix (AU-151): an object replaces the whole value, its missing keys the clip type's defaults, and `null` clears it; a value that is not an object or `null`, an unknown key and a mistyped member are each an `Err` naming the key, and a value outside the clip's ranges is one in `in_range`'s sentence under `compressor.` or `limiter.`. Inside a `scope` either is an `Err` (a nest's tracks have none). |
//! | `remove_empty_tracks` | Drops every track with no clips, keeping the back-most if that would empty the stack. |
//! | `add_marker` | A marker at `at`, clamped to ≥ 0, named `Marker <n>` and red unless `name` and `color` say otherwise. Two markers may not share a tick: a second on a held tick is refused, naming the marker. |
//! | `set_marker` | Omitted fields keep their value; the same one-marker-per-tick rule: a second on a held tick is refused, naming the marker. |
//! | `remove_marker` | Removes the marker. |
//! | `set_canvas` | `rescale_clips`, false when absent, multiplies every clip's `x`, `y` and `scale` by the size ratio; an fps change re-snaps top-level and stored-nest clip starts, source-bounded durations, action spans, present base motion/text timings and a graphic's `in` and `length`, plus top-level markers, to the new grid (spec §11, D7-3, G-18); a ramped clip's speed actions are snapped, not clamped, and its duration held again (SR-19 (g)). A marker a coarser grid lands on a tick an earlier stored marker already holds is dropped; size-only and same-fps edits do not resnap. `output` (`sdr` or `hlg`, spec §11 HD-2, HD-13) sets the project's dynamic range and changes no clip; the output the canvas already has is an identity. `blending` (`encoded` or `linear`, spec §11 GR-18, HD-16) sets how layers blend, the same way. |
//! | `add_media` | Appends the `media[]` element of spec §5.2 minus its `id` (the host probes the file). A path already in the list changes nothing. An `original` (the WebM or Matroska file a playable copy was made from, spec §11 #228-O) is stored with its path trimmed; an empty one is an `Err`. A `lut` row (a `.cube` file, spec §11 GR-8) carries no video, audio, alpha or duration, or is an `Err`. |
//! | `relink_media` | Points a media at another file; an absent or `null` bookmark clears the stale one. The `probe` the host fills is the new file's descriptor minus `path` and `bookmark`: the media takes its duration, size, rate and flags, a file of another kind is refused, and a media clip running past a shorter file's end is held to it (spec §11, #63), a ramped one through S∞ with its actions unchanged (SR-19 (h)). The probe's `original` replaces the stored one, so a probe without one clears it (#228-O). No `probe` keeps the record. |
//! | `remove_media` | Refuses while clips still reference it unless `with_clips`, which removes those clips too. A `lut` media is no clip's source: it refuses while it is a clip's base look or a media's Camera Log unless `with_clips`, which clears those looks and conversions and keeps the clips and the media (spec §11 GR-8, GR-16). |
//! | `set_media_color` | A video media's Camera Log (spec §11 GR-16): `color` is `{log, gamut}` (a built-in curve, its gamut defaulting to the curve's first) or `{lut}` (a `lut` media as the input conversion), converted at step 0 for every clip of the media; `null` clears it. A PQ file's `peak` (spec §11 HD-12, 1–10000 cd/m²) is the override of the peak import read into `pq`, beside either or alone; a PQ still (spec §11 HD-20 (b)) takes `peak` alone. `color` replaces the Camera Log and the override together, and `null` clears both, keeping import's reading. Refused, each in its own sentence: an audio or LUT media, and an image unless the colour is a PQ still's `peak` alone; neither or both of `log` and `lut` (and no `peak`); a `gamut` without `log` or outside the curve's pairings; a `lut` that names no `lut` media; `detected` and `pq`, which import writes; a `peak` outside 1–10000 or on media that is not a PQ file. `media_color.rs` holds the rules. |
//! | `set_media_speech` | A media's speech spans (format 29, spec §11 AU-110, AU-111): `spans` is `[start, end]` pairs in forward-file SOURCE ticks, stored as `media.speech` and read by every clip of the media whose `audio.duck.mode` is `speech`. An empty list is a media with no speech found, stored as such; spans equal to the stored ones are an identity. Refused, each in its own sentence: a media without audio; a span starting before 0, ending at or before its start, or ending past the media's `duration`; spans unsorted or overlapping (touching is allowed); more than 100,000. `Err` for an unknown media. `media_speech.rs` holds the rules. |
//! | `set_media_cursor` | A media's cursor file (road map "creator-jobs" CU5, spec §11 CU-50): `cursor` is `{path, bookmark?, in_picture}`, the `media.cursor` record of spec §5.2a, stored as given; `null` clears it, and `null` on a media with none or a value equal to the stored one is an identity. `cursor` is read strictly: neither an object nor `null`, a key other than the three, and a value the record's shape refuses (`in_picture` is required) are each an `Err` naming it, as is an unknown media. Refused, each in its own sentence: an empty path; a media that is not a video with a picture. The core opens no file and makes no `movie_size` check; the app's tool and the Media tab's Locate… do (CU-50 (b)). Consolidate's second copy and the open-time re-anchor write through it (CU-51, CU-52). `media_cursor.rs` holds the rules. |
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

use crate::edit_action_ramp::RampShape;
use crate::edit_layout::LayoutSwitch;
use crate::edit_paste_attributes::PasteGroup;
use crate::edit_reframe::{FramingFollow, Reframe};
use crate::edit_transition::TransitionAlign;
use crate::edit_zoom::{ZoomFit, ZoomRegion};
use crate::export::describe;
use crate::layout::{CameraLayout, LayoutCorner, LayoutShape};
use crate::model::{
    CanvasBlending, CanvasOutput, Color, Curve, FadeShape, Project, TrackMatte, TransitionKind,
};
use crate::outcome::Outcome;
use crate::reframe::{Subjects, WhereEmpty};
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
    /// `schema` is what the module declares, filled by the app (G-4); the
    /// core never reads the module, so a props patch is checked against the
    /// schema the op carries, or for shape only when it carries none.
    AddGraphicClip {
        track: u32,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
        name: String,
        #[serde(default)]
        width: Option<u32>,
        #[serde(default)]
        height: Option<u32>,
        #[serde(default)]
        props: Option<Value>,
        #[serde(default)]
        schema: Option<Value>,
    },
    /// No picture of its own: grades what is behind it (spec §11 GR-6).
    AddAdjustmentClip {
        track: u32,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
    },
    /// `media` and `color` are alternatives, not a pair: a plate is either
    /// a picture or a colour, and naming both is an `Err` rather than a
    /// precedence rule nobody would remember. Both carry a serde default so
    /// that an absent key and an explicit `null` mean the same thing for
    /// these `Option<T>` fields, which makes the no-argument call — the
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
        #[serde(default)]
        alone: bool,
    },
    TrimEnd {
        clip: u32,
        to: Ticks,
        #[serde(default)]
        alone: bool,
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
        #[serde(default)]
        alone: bool,
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
    KeepRange {
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
    RetimeRange {
        from: Ticks,
        to: Ticks,
        rate: f64,
        #[serde(default)]
        keep_pitch: Option<bool>,
    },
    SetSpeed {
        clip: u32,
        #[serde(default)]
        rate: Option<f64>,
        #[serde(default)]
        duration: Option<Ticks>,
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
    AttachAudio {
        clip: u32,
    },
    Duplicate {
        clips: Vec<u32>,
        #[serde(default)]
        delta: Option<Ticks>,
        #[serde(default)]
        track: Option<u32>,
    },
    CopyPieces {
        clip: u32,
        track: u32,
        ranges: Vec<[Ticks; 2]>,
        #[serde(default)]
        video: Option<bool>,
        #[serde(default)]
        audio: Option<bool>,
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
    /// The same opaque `payload` as `paste`. `groups` absent means "each of
    /// video, audio, text and shape both sides have" — never `graphic`,
    /// which a caller names (G-32); an unknown group name is a serde error
    /// from the envelope, like any other bad enum value. `skip_missing` is
    /// a plain boolean: absent is false, and `null` is a decode error.
    PasteAttributes {
        clips: Vec<u32>,
        payload: Value,
        #[serde(default)]
        groups: Option<Vec<PasteGroup>>,
        #[serde(default)]
        skip_missing: bool,
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
    SetGraphic {
        clips: Vec<u32>,
        patch: Value,
        #[serde(default)]
        schema: Option<Value>,
    },
    /// The fifth patch op: `patch` is `{name?, label?}`, each a string or
    /// `null`, read by `edit_props.rs`. A patch rather than two envelope
    /// arguments because optional `Option<T>` envelope fields decode absent
    /// and null alike, while this patch needs them to differ.
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
    /// The core decodes null like absence for this `Option`; the app's tool
    /// schema deliberately requires a non-null value when the key is present.
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
    /// Both arguments mean "keep" when absent or null at the core decoder;
    /// the app's tool schema requires non-null values when keys are present.
    SetTransitionStyle {
        clip: u32,
        #[serde(default)]
        curve: Option<Curve>,
        #[serde(default)]
        audio: Option<bool>,
        #[serde(default)]
        audio_shape: Option<FadeShape>,
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
    /// and an explicit `null` mean the same thing for these `Option<T>` fields —
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
    /// The speed ramp presets (spec §11 SR-23): `from` and `to` CLIP time,
    /// both or neither; `hold` for a dip or a burst only.
    AddSpeedRamp {
        clip: u32,
        shape: RampShape,
        rate: f64,
        #[serde(default)]
        from: Option<Ticks>,
        #[serde(default)]
        to: Option<Ticks>,
        #[serde(default)]
        curve: Option<Curve>,
        #[serde(default)]
        hold: Option<f64>,
    },
    /// Camera layouts at the playhead (spec §11 CO-61): the fields are
    /// `edit_layout.rs`'s `LayoutSwitch`, in the row's order.
    SwitchLayout {
        camera: u32,
        #[serde(default)]
        screen: Option<u32>,
        layout: CameraLayout,
        #[serde(default)]
        shape: Option<LayoutShape>,
        #[serde(default)]
        corner: Option<LayoutCorner>,
        at: Ticks,
        #[serde(default)]
        duration: Option<Ticks>,
        #[serde(default)]
        curve: Option<Curve>,
        #[serde(default)]
        focus: Option<[f64; 2]>,
        #[serde(default)]
        nest: Option<bool>,
        #[serde(default)]
        through: Option<Ticks>,
    },
    /// One clip framed on the current canvas (spec §11 VR-26): the fields
    /// are `edit_reframe.rs`'s `Reframe`, in the row's order.
    ReframeClip {
        clip: u32,
        follow: FramingFollow,
        #[serde(default)]
        zoom: Option<f64>,
        #[serde(default)]
        where_empty: Option<WhereEmpty>,
        #[serde(default)]
        from_width: Option<u32>,
        #[serde(default)]
        from_height: Option<u32>,
        #[serde(default)]
        backdrop: Option<u32>,
        #[serde(default)]
        replace: Option<bool>,
        #[serde(default)]
        mics: Option<Vec<u32>>,
        #[serde(default)]
        mic_faces: Option<Vec<u32>>,
        #[serde(default)]
        subjects: Option<Subjects>,
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
        #[serde(default)]
        off: Option<Vec<String>>,
        #[serde(default)]
        schema: Option<Value>,
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
        #[serde(default)]
        matte: Option<TrackMatte>,
        #[serde(default)]
        volume: Option<f64>,
        #[serde(default)]
        pan: Option<f64>,
        #[serde(default, deserialize_with = "crate::track_dynamics::present")]
        compressor: Option<Value>,
        #[serde(default, deserialize_with = "crate::track_dynamics::present")]
        limiter: Option<Value>,
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
        #[serde(default)]
        output: Option<CanvasOutput>,
        #[serde(default)]
        blending: Option<CanvasBlending>,
    },
    AddMedia {
        descriptor: Value,
    },
    RelinkMedia {
        media: u32,
        path: String,
        #[serde(default)]
        bookmark: Option<String>,
        #[serde(default)]
        probe: Option<Value>,
    },
    RemoveMedia {
        media: u32,
        #[serde(default)]
        with_clips: bool,
    },
    SetMediaColor {
        media: u32,
        color: Value,
    },
    /// `[start, end]` pairs, `RippleDeleteRanges`' spelling.
    SetMediaSpeech {
        media: u32,
        spans: Vec<[Ticks; 2]>,
    },
    /// `{path, bookmark?, in_picture}` or `null`, read strictly by
    /// `media_cursor.rs`.
    SetMediaCursor {
        media: u32,
        cursor: Value,
    },
}

/// One parsed envelope: the op, and the nest it applies INSIDE.
///
/// A struct rather than a bare [`Op`] because `scope` is the envelope's
/// key and not any op's argument — it is spelled once, it means the same
/// thing over all sixty-four, and folding it into the enum would mean
/// sixty-four copies of one optional field. [`Project::apply_op`] still
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
/// before the typed decode keeps all three — the refusal, all sixty-four
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
            Op::AddGraphicClip {
                track,
                at,
                duration,
                name,
                width,
                height,
                props,
                schema,
            } => self.add_graphic_clip(
                *track,
                *at,
                *duration,
                name,
                *width,
                *height,
                props.as_ref(),
                schema.as_ref(),
            ),
            Op::AddAdjustmentClip {
                track,
                at,
                duration,
            } => self.add_adjustment_clip(*track, *at, *duration),
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
            Op::TrimStart { clip, to, alone } => self.trim_start(*clip, *to, *alone),
            Op::TrimEnd { clip, to, alone } => self.trim_end(*clip, *to, *alone),
            Op::RateStretch { clip, to_end } => self.rate_stretch(*clip, *to_end),
            Op::Slip { clip, delta } => self.slip(*clip, *delta),
            Op::Roll { clip, to, alone } => self.roll(*clip, *to, *alone),
            Op::Split { clips, at } => match clips.as_deref() {
                Some(ids) => self.split_clips(ids, *at),
                None => self.split_under_playhead(*at),
            },
            Op::Delete { clips } => self.delete_clips(clips),
            Op::RippleDelete { clips } => self.ripple_delete(clips),
            Op::RippleDeleteRange { from, to } => self.ripple_delete_range(*from, *to),
            Op::RippleDeleteRanges { ranges } => self.ripple_delete_ranges(ranges),
            Op::LiftRange { from, to } => self.lift_range(*from, *to),
            Op::KeepRange { from, to } => self.keep_range(*from, *to),
            Op::InsertTime { at, length } => self.insert_time(*at, *length),
            Op::CloseGap { track, at } => self.close_gap(*track, *at),
            Op::RetimeRange {
                from,
                to,
                rate,
                keep_pitch,
            } => self.retime_range(*from, *to, *rate, *keep_pitch),
            Op::SetSpeed {
                clip,
                rate,
                duration,
                keep_pitch,
            } => self.set_speed(*clip, *rate, *duration, *keep_pitch),
            Op::SetReversed { clip, reversed } => self.set_reversed(*clip, *reversed),
            Op::FreezeFrame { clip, at, duration } => self.freeze_frame(*clip, *at, *duration),
            Op::DetachAudio { clip } => self.detach_audio(*clip),
            Op::AttachAudio { clip } => self.attach_audio(*clip),
            Op::Duplicate {
                clips,
                delta,
                track,
            } => self.duplicate_clips(clips, *delta, *track),
            Op::CopyPieces {
                clip,
                track,
                ranges,
                video,
                audio,
            } => self.copy_pieces(*clip, *track, ranges, *video, *audio),
            Op::Paste { at, track, payload } => self.paste(*at, *track, payload),
            Op::PasteAttributes {
                clips,
                payload,
                groups,
                skip_missing,
            } => self.paste_attributes(clips, payload, groups.as_deref(), *skip_missing),
            Op::Nest { clips, name } => self.nest_clips(clips, name.as_deref()),
            Op::Unnest { clip } => self.unnest_clip(*clip),
            Op::SetVideo { clips, patch } => self.set_video(clips, patch),
            Op::SetAudio { clips, patch } => self.set_audio(clips, patch),
            Op::SetText { clips, patch } => self.set_text(clips, patch),
            Op::SetShape { clips, patch } => self.set_shape(clips, patch),
            Op::SetGraphic {
                clips,
                patch,
                schema,
            } => self.set_graphic(clips, patch, schema.as_ref()),
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
            Op::SetTransitionStyle {
                clip,
                curve,
                audio,
                audio_shape,
            } => self.set_transition_style(*clip, *curve, *audio, *audio_shape),

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
            Op::AddSpeedRamp {
                clip,
                shape,
                rate,
                from,
                to,
                curve,
                hold,
            } => self.add_speed_ramp(*clip, *shape, *rate, *from, *to, *curve, *hold),
            Op::SwitchLayout {
                camera,
                screen,
                layout,
                shape,
                corner,
                at,
                duration,
                curve,
                focus,
                nest,
                through,
            } => self.switch_layout(&LayoutSwitch {
                camera: *camera,
                screen: *screen,
                layout: *layout,
                shape: *shape,
                corner: *corner,
                at: *at,
                duration: *duration,
                curve: *curve,
                focus: *focus,
                nest: *nest,
                through: *through,
            }),
            Op::ReframeClip {
                clip,
                follow,
                zoom,
                where_empty,
                from_width,
                from_height,
                backdrop,
                replace,
                mics,
                mic_faces,
                subjects,
            } => self.reframe_clip(&Reframe {
                clip: *clip,
                follow: *follow,
                zoom: *zoom,
                where_empty: *where_empty,
                from_width: *from_width,
                from_height: *from_height,
                backdrop: *backdrop,
                replace: *replace,
                mics: mics.clone(),
                mic_faces: mic_faces.clone(),
                subjects: subjects.clone(),
            }),
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
                off,
                schema,
            } => self.set_action_end(
                *clip,
                *action,
                patch,
                off.as_deref().unwrap_or_default(),
                schema.as_ref(),
            ),
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
                matte,
                volume,
                pan,
                compressor,
                limiter,
            } => self.set_track(
                *track,
                name.as_deref(),
                *hidden,
                *muted,
                *locked,
                *solo,
                *matte,
                *volume,
                *pan,
                compressor.as_ref(),
                limiter.as_ref(),
            ),
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
                output,
                blending,
            } => self.set_canvas(
                *width,
                *height,
                *fps,
                *background,
                *rescale_clips,
                *fit_new_clips,
                *timecode_frames,
                *output,
                *blending,
            ),
            Op::AddMedia { descriptor } => self.add_media(descriptor),
            Op::RelinkMedia {
                media,
                path,
                bookmark,
                probe,
            } => self.relink_media(*media, path, bookmark.as_deref(), probe.as_ref()),
            Op::RemoveMedia { media, with_clips } => self.remove_media(*media, *with_clips),
            Op::SetMediaColor { media, color } => self.set_media_color(*media, color),
            Op::SetMediaSpeech { media, spans } => self.set_media_speech(*media, spans),
            Op::SetMediaCursor { media, cursor } => self.set_media_cursor(*media, cursor),
        }
    }
}
