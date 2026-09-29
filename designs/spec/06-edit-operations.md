# 6. Edit operations — exact semantics

All ops take clip/track/marker *ids*. Caller-supplied timeline tick arguments
are snapped to the document's frame grid before placement or storage, usually
to the nearest frame; `add_transition.duration` instead floors a positive
overlap request to whole frames in both modes. A negative project position
may snap and then clamp to zero; negative clip-relative starts and lengths
follow their op's checks. Source positions and measured media durations stay
in source ticks, and audio envelopes keep sample precision. The tick values
a PATCH carries are also snapped — a motion
preset's two edge durations and its `during` period, and a text animation's
`in` and `out` — which the core snaps after the range checks, so a refusal
names the number the caller sent.

An optional op argument may be omitted; this alone does not make JSON `null`
valid. `add_transition.ripple`, both `with_clips` arguments and
`set_canvas.rescale_clips` are plain booleans: omission means `false`, while
`null` is a decode error. Every other optional core enum field is `Option<T>`
and decodes absence and null alike. The separate `scope` envelope key accepts
absence or null; a present value must be a nest id. The app's MCP schemas may
apply stricter present-value rules for transition arguments (§7.9).

**How to read a "refuses" below.** An op the core understood answers one of
three ways (§5.5): it applies, it is an **identity**, or a rule **refuses**
it and hands back that rule's own sentence. The rows below name the RULE,
which is what a reader needs — a row that says an op refuses on an empty
selection or when nothing changes is naming an identity, which carries no
sentence, and every other "refuses" is a rule that either speaks already or
is a candidate to. §5.5 says where the one list of the ones that speak is
kept. Either way the project is exactly as it was and no undo step is made,
and the UI beeps or animates back; "error" = `Err`, the request itself could
not be read.

**Every op that takes a caller-authored PATCH reads it the one way** (§5.2):
a nested object MERGES key by key at every depth, a key set to `null` CLEARS
it, and an array REPLACES its whole list. The core is the one validator of
what a patch may carry — an unknown key, a value of the wrong JSON kind or a
misspelt variant at any depth is an error naming the dotted path with array
indices and the value sent, the project is untouched and no undo step is
made. The agent door forwards the caller's own object unread (§7.9), so an
agent and the app's own writers meet exactly the same rules.

**The envelope's one non-argument key: `scope?: u32`.** A nest id. Absent
(or `null` — the envelope reads the two the same way), every id in the op
resolves against the timeline, as it always did. Present, every id in the
op — clips, tracks, actions — resolves against that nest's own tracks and
clips, and the op itself is unchanged: `Project::apply` builds a **view
project** out of the nest (`tracks` / `clips` the nest's, the canvas SIZE
its frozen pair, the rate / background / switches and the `media[]` and
`next_id` the parent's, no markers, and the nest's own row kept in
`nests[]` with its contents emptied so ids resolve without being counted
twice), applies the op to it, and merges `tracks`, `clips`, `next_id`,
`media` and `nests` back. So `Project::clip` keeps its one meaning, no op
gained a nest-aware code path, undo is still one stack of parent handles,
and `rc_op_names` gains no name — a scope is an envelope key, not an op.
Times inside a scope are the nest's own, measured from its zero; a nest has
no speed, so `t − nest_clip.start` is the whole mapping.

**Seven ops are an error with a scope**, each naming itself and the nest
(`add_marker has no meaning inside nest 4`): `add_marker`, `set_marker`,
`remove_marker` — a nest has no `markers[]`, and the timeline's are project
time and chapter points on the file; `set_canvas` — a nest's size is frozen
at the size the parent had when it was made (§5.2), deliberately, and the
rest of a canvas is the document's; and `add_media`, `relink_media`,
`remove_media` — a nest references the parent's `media[]` in the parent's
one id space, so a media edit inside a scope is a media edit on the
document wearing a scope. An unknown `scope` is `no nest with id N`,
answered ahead of everything else; a `scope` that is not a nest id is
`scope must be a nest id, not <value>`. Everything else works inside a nest
as it works on the timeline, `nest` and `unnest` included: nesting the
whole of a scope mints a fresh id and puts the new nest clip INSIDE the
scoped nest, which is a legal extra level and not a cycle.

**A scope widens §5.5's invalid-argument answer and nothing else.** Two
invariants are invisible from inside a view — the caps count the whole
document (§5.6) and the nesting depth is measured from the timeline down —
so both are checked once, at the end, on the MERGED parent. *An op may
succeed against the view and the scoped apply still return `Err`*: `too
many clips`, `too many tracks`, `nests are more than 8 deep at nest N`.
`core/src/scope.rs`'s module doc is the full contract.

## Clips

- **`add_clip {track, media, at}`** — Whole media as one clip at `at`; source in 0; Fit scale if
  `fit_new_clips` and the source exceeds the canvas. The length is the media's, snapped DOWN to
  whole frames, so the window stays inside the file and the segment plays at rate 1 (§11); a timed
  media shorter than one canvas frame is an `Err` naming the frame. Refuses if the overlap rule
  fails.
- **`add_text_clip {track, at, duration=5 s, text?}` / `add_shape_clip {…, shape?}`** — Same
  placement rules; default text is the Title preset centered, default shape the rectangle — except
  that `shape.kind = "arrow"` is created with `arrow_end` on, since an arrow with no head is a
  diagonal line. `text` and `shape` are **patch objects** in the `set_text` / `set_shape` shape,
  merged over that default — not a bare string or kind — so an explicit `arrow_end: false` still
  wins. (The MCP tools additionally accept a bare string as shorthand: the words for `text`, a kind
  name for `shape`.)
- **`add_graphic_clip {track, at, duration=5 s, name, width?, height?, props?, schema?}`** — Same
  placement rules; a clip drawn by the module `graphics/<name>.js`, at `width` × `height` — the
  canvas's when absent, an **error** naming the canvas when a side taken from it is over 8192 (a
  side the caller gave is not tested against the canvas) — with Fit scale as a shape's box has, `in`
  0 and no `length`. `name` must match `^[a-z0-9][a-z0-9-]{0,62}$` (§11 G-3); the core has no
  filesystem and never checks the module exists. `props` is checked against `schema` when the op
  carries one — every key by its dotted path, `props.accent`, for its type, `min`/`max` and enum
  membership, a colour normalised to lowercase hex (§11 G-4, G-12) — and for shape only without one
  (a string of at most 4096 characters, a number or a boolean, under a key matching
  `^[A-Za-z_][A-Za-z0-9_]{0,31}$`); a `null` prop is dropped unchecked, and more than 64 is an
  **error**. Every check runs before the placement.
- **`add_background {media?, color?=white, duration?=the timeline's length}`** — A backdrop on a NEW
  back-most track, starting at 0 and named "Background". With `media`, that file placed as
  `add_clip` would place it but for its SCALE — the right source kind, audio props when it has
  sound, and a FILL scale where `add_clip` takes a Fit one, because a plate that leaves the canvas
  showing down one side has failed at the one thing a background is for; with `color`, or with
  neither, a canvas-sized filled rectangle with no stroke at scale 1. The plate default is WHITE,
  not black: the canvas is already black, so a black plate is a command that appears to do nothing.
  A plate of a TIMED media — video or audio — is held to that file's own whole length, default
  duration or given, so it never outruns what it shows (§11, D4-4); an image plate has no source
  bound and runs as long as it was asked to. `Err` for `media` and `color` together, an unknown
  media, a media with no pictures, a colour outside 0–1, a duration under a frame, or a timed media
  shorter than one canvas frame (`add_clip`'s own sentence, through the same function). A
  full-canvas GRADIENT is this clip and a `set_shape {gradient}` after it — the canvas background
  stays one colour (§5.2).
- **`add_blurred_background {clip}`** — The screencast backdrop: `clip` copied onto a NEW back-most
  track at the same start, duration, speed and source window — so the two play the same frames —
  scaled to FILL the canvas, centred, uncropped, blended `normal` and blurred at full strength. The
  copy is muted (`enabled` becomes `{video: true, audio: false}`, `detach_audio`'s pair read the
  other way) and drops its `audio.duck` — the one field of that group that lowers OTHER material, so
  a copy keeping it would duck the mix including the clip it came from — along with its transition,
  its actions, its label and its `video.motion` (format version 8 — a backdrop that slid in or
  pulsed behind the clip it copies would be two pictures of one recording disagreeing about where
  they are, and a slide would leave the canvas showing down one side, which is the one thing a
  background exists to prevent); it is named "Blurred Background". `Err` for an unknown clip, a NEST
  (flattening drops a nest clip's own filters, so the copy would come out sharp), a source with no
  pixel size (text, audio-only), or a clip with no video properties. Both of these mint TWO objects
  — a track and the clip on it — and the TRACK takes the `next_id` the call was made with, the clip
  the one after.
- **`insert_clip {track, media, at}`** — The INSERT edit: the clip `at` is strictly inside on
  `track` is split, every unlocked track opens by the media's whole length (`insert_time`), then the
  media lands at `at`. Only the destination track is cut — a straddler on another track rides the
  shift whole, which is what keeps a bed unbroken. One op, so one undo step and one tool. Refuses
  when the clip could not be placed after the room was made, which is what a locked destination
  track gives.
- **`overwrite_clip {track, media, at}`** — The OVERWRITE edit: `[at, at + media length)` is cleared
  on `track` ALONE — cut at both bounds, whatever is left inside removed — and the media lands
  there. Nothing shifts and no other track is touched; the named track is cleared whether or not it
  is locked, exactly as `ripple_delete` removes the clips it was given.
- **`move_clip {clips, delta, track?}`** — Shifts by `delta` ticks (may be negative; clamps at 0)
  and optionally to another track (all selected clips keep their relative track offsets). **Overlap
  rule** on the destination track: a clip may overlap at most one neighbour on each side, and each
  overlap must be ≤ half of the shorter of the two clips; anything else refuses. An overlap is a
  transition; a clip that gains a predecessor overlap gets `transition_in = cross_dissolve` if it
  had none.
- **`trim_start {clip, to}`** — New start `to`; source in advances by `(to − start) × speed`.
  Clamps: `to ≥ start − in/speed` snapped UP to a whole frame (source bound — `in/speed` is a
  floored division and is not on the grid, so an un-snapped clamp could write a sub-frame start, §11
  D4-5), `to < end − one frame`. A text clip's `text.words` are rebased by `to − start` — unlike its
  actions, because a word is anchored to speech that stays where it is on the timeline (§11 W-3). A
  graphic clip's `graphic.in` advances by `to − start` — no speed and no head bound, so a start can
  be dragged to 0 and `in` saturates at 0 (§11 G-9).
- **`trim_end {clip, to}`** — New end `to`; clamps to the source's remaining length (`media`
  sources), snapped DOWN to a whole frame so the clamp cannot put the end past the file (§11), and
  `> start`. A graphic's `length` is untouched: `null` keeps ending with the clip, a number stays
  (§11 G-9).
- **`rate_stretch {clip, to_end}`** — `speed = source_len / (to_end − start)`; duration follows.
  Media sources only — a non-media clip is an **error**, not a refusal, so an MCP caller gets a
  message it can correct from (the UI never offers it).
- **`slip {clip, delta}`** — Slides the source under a fixed clip: `in += delta × speed`, start and
  duration unchanged, so nothing downstream moves. `delta` is TIMELINE ticks; positive shows later
  material. Clamped so the window stays inside the media (`in ≥ 0`, `in + duration × speed ≤
  media.duration`), and a slip the clamps reduce to nothing refuses. A `still` moves its `at`
  instead — it has a source time if not a window. Any other source is an **error**, as
  `rate_stretch` is. Actions are clip-relative and do not move.
- **`roll {clip, to}`** — Moves a hard cut: this clip's start and its predecessor's end both become
  `to`, and nothing else moves — the pair's outer edges and its total length are invariants. The
  predecessor is the clip on the same track ending EXACTLY at this one's start; with a gap or an
  overlap there instead it refuses (an overlap is a transition, and its length is
  `set_transition_duration`'s). Clamped four ways: one frame kept on each side, this clip's own
  source head, and the predecessor's remaining source. Front-trim semantics here (`in` follows), a
  plain end trim there. This clip's `text.words` are rebased by the move, as `trim_start` rebases
  them (§11 W-3), and its `graphic.in` advances by the move as `trim_start`'s does; the
  predecessor's `length` is untouched (§11 G-9).
- **`split {clips?, at}`** — Two clips. Second: `start = at`, `in += (at − start) × speed`, base
  props = the evaluated state at `at`. Actions before `at` stay with the first; after go to the
  second (start rebased); a straddling action becomes two — the first half's end patch is the
  evaluated state at `at`. `transition_in` stays with the first. A graphic's second half gets
  `graphic.in + (at − start)`, and BOTH halves' `graphic.length` are pinned to the original's
  effective length — `length`, or `in + duration` when `null` — so the animation continues across
  the cut and plays its outro once, at the true end (§11 G-9). The second keeps every `text.words`
  entry rebased by the cut — a negative start is legal and means "already said", so the split is
  invisible — and the first half's words are untouched; a second half whose EVALUATED content (a
  finished action may have switched it) has a different token count stores `words: []` instead,
  because a half is a clip the door must accept again (format version 9, §11 W-3). A PRESET anchored
  to the clip's two ends is divided rather than copied (format version 8): the first half keeps
  `video.motion.in` and loses `out`, the second keeps `out` and loses `in`, each normalised to
  `null` when nothing is left, and `text.animation` is split the same way — `out` zeroed on the
  first half, `in` on the second, the pair becoming `null` when both are 0. Carrying both to both
  halves, which is what a clone does and what version 5 did, makes the first half leave at the cut
  and the second arrive again there. A `during` slot survives on both, since it is anchored to
  neither end, and restarts at each cut. Every splitter in the crate routes through this — `split`,
  `delete` and the two range cuts, `lift_range`, `insert_clip`, `overwrite_clip` and `freeze_frame`
  — so the rule is stated once (`edit_split.rs`, §7.10). Refuses when `at` is not strictly inside.
  **Omitting** `clips` — not passing a flag — means every unlocked clip `at` is strictly inside, the
  ⌘T-with-no-selection case.
- **`delete {clips}`** — Removes; gaps stay.
- **`ripple_delete {clips}` / `ripple_delete_range {from, to}`** — Removes; then for each removed
  span (union of the removed clips' spans, processed right-to-left) shifts every clip on
  **unlocked** tracks whose start ≥ span end left by the span length. Clips on other tracks that
  straddle a span are left in place. Range form: every unlocked clip is split at both bounds first,
  the middle pieces removed, then the shift. Every clip a shift moves moves by that ONE delta, so
  clips that abutted still abut — at a rate whose frame is not a whole number of ticks (7 fps) a
  moved start may sit a tick off the grid (§11 #42).
- **`ripple_delete_ranges {ranges: [[from, to], …]}`** — Several ranges as ONE edit — the silence
  cut. Each pair is snapped, clamped and ordered exactly as `ripple_delete_range`'s one is (a
  reversed pair is the same range), the pairs are then MERGED — touching as well as overlapping —
  and the survivors cut and closed right to left. So the op is **merge-then-cut and not N
  `ripple_delete_range`s**, and the difference is visible in the document: a cut at a boundary that
  no longer exists would mint a fragment and burn an id. `set_gained_transitions` runs once at the
  end, over the unlocked tracks. Markers do not move, as they do not for the singular. An empty
  list, and a list that merges to nothing, change nothing. Written by Clip ▸ Remove Silences… as one
  undo step, whatever the number of cuts.
- **`lift_range {from, to}`** — `ripple_delete_range` without the close: every unlocked clip is
  split at both bounds and the middles removed, and NOTHING moves — every clip after the range keeps
  the moment it had, and so do the markers. ⌫ with a range and nothing selected, where ⌘⌫ ripples.
- **`insert_time {at, length}`** — Shifts every unlocked clip whose start ≥ `at` right by `length`.
  Straddling clips are left in place.
- **`close_gap {track, at}`** — Closes the empty span on `track` that contains `at`, bounded by the
  nearest clip edges there (0 in front when nothing precedes it): everything from the gap's far side
  shifts left by its length, across every unlocked track, straddlers staying put. Refuses on a
  locked `track`, on an `at` that is on a clip, when there is no clip after the gap, and when the
  shift would break the overlap rule — a gap closes fully or not at all, because a partial close
  leaves the user unable to tell whether the op ran. Markers do not move.
- **`set_speed {clip, rate, keep_pitch?}`** — `duration = source_len / rate`, snapped to the NEAREST
  frame and then held to what the file still holds AT THE NEW RATE, so `in + duration × rate ≤
  media.duration` and the segment plays at exactly `rate` (§11, D4-3); the one-frame floor still
  wins over that bound. Actions keep their clip-relative *fraction* of the clip. Media sources only,
  an **error** on any other kind (as `rate_stretch`). Rate is clamped to ×0.1–×10.
- **`set_reversed {clip, reversed}`** — Plays the media back to front, or forward again. The core
  does no pixel work, so this changes neither the plan nor the recipe: Swift substitutes a
  pre-rendered reversed asset for that media's segments (§11). `in` is measured in the direction the
  clip PLAYS, so reversing keeps the in point and therefore shows different frames; the alternative
  would put two conventions into every trim and split. Media sources only, an **error** on any other
  kind.
- **`freeze_frame {clip, at, duration=2 s}`** — `split` at `at`, `insert_time(at, duration)`, then a
  `still {media, at: source time}` clip filling the gap on the same track with the original's video
  props, LESS its `video.motion` (format version 8): a still is a new clip with new ends, so one
  taken mid-arrival would otherwise arrive again and one taken anywhere would carry a departure onto
  a frame that is meant to hold. The placement it keeps is the un-moved one, since evaluation never
  applies a preset, so a freeze taken mid-motion jumps to where the inspector said the clip was.
  Media sources only, an **error** on any other kind (as `rate_stretch`).
- **`detach_audio {clip}`** — `enabled.audio = false` on the clip; a new clip with `enabled =
  {video: false, audio: true}`, same source/in/duration/speed and the audio props, on the track
  below (a track is inserted at index 0 if needed). Refuses, naming why (§11 #88), on a clip that
  is not media, whose media has no audio, or whose audio is already detached.
- **`duplicate {clips}`** — Copies placed after the originals' span on the same tracks (⌥-drag then
  moves them).
- **`paste {at, track?, payload}`** — Inserts the clips of a clipboard payload — `{"clips": [...],
  "media": [...]}`, what ⌘C wrote to `com.kgalligan.reelcut.clips` — with fresh ids for the clips,
  their actions and any media row added. The EARLIEST clip lands exactly at `at` and the rest keep
  their offsets from it. A payload clip's `track` is a **depth from the front** (0 = front-most),
  not an id, since the ids belong to the document copied from: `track` names where depth 0 lands
  (default: the front-most track), the rest follow by the same index delta, and tracks missing
  behind it are added. Media is matched to `media[]` **by path** — reused when it is there, appended
  when it is not — so a paste between documents brings the entry with it. A clip the overlap rule
  refuses on its target track goes on a new track in front (as Add Text does, §4.1), so the only
  refusal is an empty clip list; a malformed payload is an **error**. Every landed clip — the
  payload's own and those inside the nests it brings — first has every group pass
  `paste_attributes`' normalise-and-check on the values the payload sent (an empty motion lands as
  `null`; a value out of range is an **error**, `pasted clip N: …`, N the payload's id), then has its
  start, source-bounded duration, action spans, present base motion/text timings and a graphic's
  `in` and `length` normalized to this document's grid, since the payload may come from another
  frame rate (§11, D7-3, G-18·b).
- **`paste_attributes {clips, payload, groups?}`** — Copies the payload's EARLIEST clip's property
  groups onto each clip (at one start the front-most, then the lower id — never the array's first,
  which is Copy's creation order) — `payload` is the same Copy payload `paste` takes, and only that
  clip's `video`, `audio`, `text` and `shape` are read; its ids, times, media rows and nests do not
  matter and nothing is minted. A group is REPLACED whole, never merged: video and audio whole,
  transform included (`audio.muted` and `keep_pitch` travel — they are properties like opacity);
  text but its `content` and the `words` that time it (§11 W-6); a shape but its `kind`, `width`,
  `height`, `from` and `to`. `groups` ∈ `video`, `audio`, `text`, `shape`: absent, it means every
  group BOTH sides have, silently skipping the rest; a NAMED group the payload clip lacks, or a
  target lacks, is an **error**, all-or-nothing, and so is a copied value the inspector would refuse
  — each copied group passes the patches' range checks. Copied video motion and text animation pass
  the same original-value range checks as a patch, then snap to the target grid; audio envelopes
  retain sample precision. Speed, enabled, actions, the transition, the source and the clip's own
  name and label stay; `graphic` is not a group, so a graphic target keeps its module, size,
  timeline and props (§11 G-10). One value is NORMALISED on the way in, not merely checked: a copied
  `video.motion` whose three slots are all null lands as `null`, the same one spelling of "no
  motion" `set_video` and `split` keep — this op's payload is a third door for a `Motion`, and
  `{"motion": {}}` means the same thing; the file reader does NOT normalise
  (`core/tests/schema_v8.rs`). Refuses when nothing changes, and on an empty
  `groups` list.
- **`nest {clips, name?}`** — Collapses the selection into ONE clip showing a nest (§5.2), on the
  front-most track the selection occupied, running from the earliest start to the latest end. The
  clips move whole — ids, props, actions, transitions — keeping their relative times (the earliest
  starts at 0 inside) and their track order, onto fresh tracks of the nest's own that copy the
  source tracks' names and their hidden/muted/locked/solo state (a copied solo is then judged among
  the nest's own tracks, §5.2). The nest's canvas is frozen at the project's current size, so a
  later `set_canvas` cannot re-lay-out what is inside it. Media is untouched: a nest references the
  project's `media[]` in the same one id space. Refuses on an empty selection, on a selection of one
  nest clip, and when the nest clip would break the overlap rule against what was left behind.
- **`unnest {clip}`** — The inverse: the nest's clips return at `clip.start + their own start` with
  fresh ids (as `split` then a re-join mints fresh ones), on tracks counted back from the nest
  clip's own — the nest's front-most track lands where the nest clip was — with tracks missing
  behind added, and the nest clip goes. A clip the overlap rule refuses lands on a new track in
  front, as `paste` does, so a group can always be opened. A nest clip trimmed shorter than its
  contents gives **all** of them back: there is no in point on a nest, so this is the inverse of
  `nest`, not of the trim. The nest is dropped from `nests[]` when no clip anywhere still shows it.
  Each returning clip has its translated start, source-bounded duration, action spans and present
  base motion/text timings normalized to the document's grid (§11, D7-3), including a legacy
  off-grid nest. An **error** when `clip` is not a nest clip.
- **`set_video {clips, patch}` / `set_audio` / `set_text` / `set_shape`** — Merge the patch into the
  base props. Refuses if nothing changes. An unknown key, a value of the wrong JSON kind or a
  misspelt variant anywhere in the patch is an **error** that names the dotted path to it, array
  indices included, and the value sent — `unknown key "filters[1].kindd" in a video patch`, `bad
  value at "shadow" in a video patch: expected an object, not 5`, ``bad value at "filters[1].kind"
  in a video patch: unknown variant `glw`, expected one of `blur`, …`` — so a number where a shadow
  belongs is refused rather than read as a clear, and a list where an object belongs (or an object
  where a string belongs) is refused rather than read field by field; `add_text_clip`'s `text` and
  `add_shape_clip`'s `shape` answer in the same words. One value is refused by the CLIP rather than
  by the vocabulary: `video.blend` on a nest clip is an **error** naming it (format version 6),
  because a nest is flattened rather than composited offscreen and there is no group picture for a
  blend to combine with. It fires on the MERGED value only, so `{"blend": "normal"}` on a nest clip
  is the identity and refuses instead — otherwise an all-or-nothing `paste_attributes` of an
  ordinary look onto a nest clip would fail over a value that changes nothing. `set_action_end` does
  not range-check, so the same rule is enforced again in the evaluator (§5.4's `clamp_video`), which
  closes the recipe, `clip_state` and both export writers at once. A `video.filters` entry must name
  BOTH `kind` and `amount` — `missing key "filters[0].kind" in a video patch` — because a list
  replaces whole, so an entry is merged over nothing and the keys it leaves out would be completed
  from the type's defaults into a half-strength blur nobody asked for; the file reader keeps that
  completion, so an older file still opens with the defaults it always had. `video.obscure` and
  `shape.gradient.stops` entries are NOT held to it: their omitted keys leave the entry recognisably
  the thing the caller named. `video.motion` (format version 8) deep-merges like every other nested
  object — `{"motion": {"in": …}}` keeps a stored `out`, and `{"motion": {"in": null}}` clears that
  slot alone. The APP's two writers still send the WHOLE object with nil slots as `null` (the
  inspector's Motion section and Clip ▸ Motion ▸ know all three slots), which is the same rule
  spelled out rather than a second one; an AGENT's patch is the caller's own object, forwarded
  unread (§7.9). `{"motion": null}` clears the field, and a motion whose three slots are all null is
  normalised to `null` before the range checks run, so one clip has one spelling of "no motion".
  `set_text` can patch `case`, `words` and `word_style` like any declared key (format version 9, §11
  W-10); a `words` entry must name both `start` and `end`, and a non-empty `words` whose length is
  not the content's token count is an **error** in the rule's own words — `this text is timed word
  by word: 4 timings for 5 words` — as are a word time outside D7-1's envelope, an `end` before its
  `start`, a `start` before the previous word's, and a `word_style` value out of range
  (`active_scale` 1.0–1.5, colours 0–1, a negative pill padding or radius). The check runs on what
  the caller sent; the word times are then snapped to the grid, nearest, a negative one staying
  negative. A content edit that changes the count sends `words: []` in the same patch.
- **`set_graphic {clips, patch, schema?}`** — Patches each graphic clip's `name`, `width`, `height`,
  `length` (`null`: it ends with the clip, `in` + the clip's duration — G-9·c; else snapped nearest,
  at least one frame) and `props`, which merges key by key: a value is stored in the key's own slot
  or appended, a `null` removes its key and the rest keep their order — unchecked, so a key the
  schema no longer has can still be removed — each other value checked as `add_graphic_clip` checks
  them, and the merged map holds at most 64 (an **error** naming the count). `in` is an **error** —
  the trims and `split` own it (road map 10's G-9, recorded here by G2b) — and so is a clip that is
  not a graphic, an unknown key and a malformed `schema`. The identity when nothing changes, a
  colour re-sent in another spelling included.
- **`set_clip {clips, patch: {name?: string | null, label?: string | null}}`** — The fifth patch op:
  sets or clears the clip's own name and label (§5.2). Inside the patch an absent key keeps, `null`
  clears, and so does an empty string — after the trim a name gets on its way in — because an
  unnamed clip is `null`, not `""`. Any other key is an **error**, checked before the clip ids. A
  patch rather than two optional `Option<T>` envelope arguments lets "keep" and "clear" differ. A
  `split`, `duplicate`, `detach_audio` or `paste` carries both along (they clone the clip);
  `paste_attributes` never does. Refuses if nothing changes.
- **`set_enabled {clip, video?, audio?}`** — Visibility/mute per clip.
- **`set_transition {clip, kind|null}`** — Sets `transition_in`. With a kind on a clip that already
  HAS a transition only the `kind` moves — its `curve` and `audio` stay where the person put them
  (format version 7), because a kind chosen from the popup, the menu or MCP must not reset a curve;
  a clip that had none gets a minted one (§11, R5-2). `set_transition_duration {clip, duration}`
  moves the clip so the overlap equals `duration` (subject to the overlap rule). It refuses, in its
  own sentence (§11 #88), on the first clip of a track, and on a duration past the pair's overlap
  limit — half the shorter clip, snapped down — naming the limit and saying when the start would be
  before the timeline or in front of the predecessor (#175).
- **`add_transition {clip, kind?, duration, align="center", ripple=false}`** — Makes an overlap at
  the HARD CUT before `clip` out of the two clips' unused handles and puts a transition on it —
  **nothing else on the timeline moves** and the pair's outer edges stay (§11, R5-3). `align`
  `center` takes half from each side (the odd frame to the incoming clip, and a side that cannot
  supply its share passes it to the other before the total shrinks), `before` takes it all from the
  incoming clip's head, `after` all from the outgoing clip's tail. The duration is snapped DOWN to
  whole frames before the split — snapping two halves separately would lose the odd frame — and then
  clamped: to each side's handle (a media clip's source window; UNBOUNDED for a still, an image,
  text, a shape or a graphic; **0 for a nest's head**, since trimming a nest clip's head moves its contents,
  and the nest's own remaining length for its tail), to the neighbours on the track, and to the
  overlap rule, which is held FIRST to `(A.duration + B.duration) / 3 frames` — the most that rule
  can pass at any split, so the step-down walks the CLIPS and not the caller's number — and then
  searched on that same larger-side reduction path without enumerating frames (D7-2). An
  already-invalid affected track refuses with the overlap rule before fitting. Each trial's two
  extensions are read off the frame GRID rather than taken as a multiple of one frame, because the
  canvas frame is a FALLBACK of 1/30 s at a rate that does not divide the timescale (7 fps) and a
  multiple of it is not a grid position there. A request under one frame of the real grid (in the
  handle form, also under that fallback, which its arithmetic still divides by) is REFUSED FIRST in
  both modes, right after
  the lock check (ripple) or the overlap-rule preflight (handles), naming the shortest duration that
  passes (§11 #88). A request that clamps below one frame of the real
  grid is REFUSED, in a sentence naming the cut, the frames asked for and `ripple: true` as the way
  past it. The incoming clip's `in` moves back by the extension times its speed, and its ACTIONS
  move with it, as do its `text.words` (§11 W-3) — where `trim_start` deliberately leaves actions
  alone, because a transition reveals material in front of a first frame nobody asked to move. A
  graphic's own `in` moves back by the extension too, saturating at 0 (UNBOUNDED like a still;
  §11 G-18·a).
  `kind` absent uses the clip's own stored kind if it has one, else `cross_dissolve`; a stored
  transition keeps its style and a new one is minted. **Error** for a non-positive duration, an
  unknown clip, and for not being at a hard cut — naming which of: no predecessor, a gap, an overlap
  that already exists. **`ripple: true` makes the overlap by MOVING instead** (§11, R5-3's
  amendment): no handle is read and `align` is ignored; the incoming clip and every clip at or after
  the cut on every UNLOCKED track slide left by the duration counted in whole frames of the canvas's
  own grid, the incoming clip landing on the grid that many frames back from the cut (§11 #42) —
  `close_gap`'s set, through
  the same shift — so the timeline gets shorter, the outgoing clip keeps every frame and its place,
  and no source window or action moves. The duration is capped at half the shorter of the two clips
  and limited to the greatest whole-frame shift outside exact forbidden overlap intervals, including
  a feasible shift after clips cross; an already-invalid affected track refuses with the overlap
  rule before fitting; a clip on another track pushed into its neighbour gains a minted
  `cross_dissolve` (`close_gap`'s rule); markers do not move; an incoming clip on a locked track, or
  nothing left above one frame, is REFUSED, each in its own sentence. The same hard-cut `Err`s
  apply.
- **`set_transition_style {clip, curve?, audio?}`** — Sets the transition's easing and whether it
  crossfades the sound; an absent key KEEPS. A separate op rather than two more arguments on
  `set_transition`, because that one reads an absent `kind` and an explicit `null` as the same thing
  and so cannot spell "keep". It stores on the same terms — any clip, with or without an overlap —
  and a clip with no stored transition and at least one key given gets a minted `cross_dissolve`
  with the style applied. NEITHER key given is an IDENTITY whatever the clip holds, and never mints
  — nothing was asked for, so there is nothing to explain. **Error** for an unknown clip.

## Actions

- **`add_action {clip, at, duration=1 s}`** — Refuses if it would overlap another action or run past
  the clip end. End patch starts empty (= no change until edited).
- **`add_zoom_action {clip, at, duration=1 s, region: {x, y, width, height} | null, fit="fit",
  curve="ease_in_out"}`** — An `add_action` whose end patch is the `scale`, `x` and `y` that bring
  `region` to the canvas — the screencast zoom. **`region`'s `x` and `y` are its CENTRE** and
  `width`/`height` its size, both source pixels from the centre of the cropped rect (§5.3's one
  region frame); the field names say neither, so the tool description and the core's doc say it too.
  `fit` shows the whole region, `fill` covers the whole canvas, both measured THROUGH the clip's
  rotation — a rectangle contains a rotated rectangle exactly when it contains its four corners, and
  the test collapses to the naive form at 0°. Rotation and crop — and nothing else — are read from
  the clip evaluated at `at`, the frame the rectangle was drawn on: the `scale`, `x` and `y` it
  writes are absolute, so the placement never reads a transform, base or evaluated. A rotation
  animated between `at` and `at + duration` is not tracked. The scale clamps to the layer maximum
  and the offsets are derived from the CLAMPED value, so a region too small to reach it still lands
  centred and only the magnification degrades. `region` absent or `null` is a zoom BACK: the end
  patch is the clip's STORED base `scale`, `x`, `y` — the one thing here that is NOT read evaluated,
  because "back" means where the clip sits when nothing is animating it, which is also what a later
  zoom on the same clip measures from. It composes `add_action` + `set_action` + `set_action_end`,
  so it is one undo step and inherits every `add_action` refusal rather than restating it; a clip
  with no video properties is an **error**. The region is read the way a patch is: it must BE an
  object (a four-number LIST is refused rather than read member by member), an unknown member and a
  missing member are **errors** naming the member beside the four it takes, and a wrong-typed one
  names its path (`bad value at "region.width"`). A non-finite or non-positive number is an
  **error** too — `region.width must be greater than 0` — because a zero-width region asks for an
  infinite scale.
- **`set_action {clip, action, start?, duration?, curve?}`** — Same overlap checks.
- **`set_action_end {clip, action, patch, off?}`** — Merges into the end patch; a key set to `null`
  removes it, at any depth. `off` — a list of `"group.key"` paths, `group` one of `video`, `audio`,
  `text` and `key` a top-level key of it — writes a `null` at each AFTER the merge, which keys that
  optional property OFF at the end (§5.4, §11 CI-14); a malformed path, `video.motion`,
  `text.words`, a required key (`video.opacity`), a key the group does not have and a path the patch
  also names are each an **error**. Absent or `null` is none. The patch is walked like every other
  one (§5.4): the three groups it may name are `video`, `audio` and `text`, and an unknown key, a
  value of the wrong JSON kind or a misspelt variant anywhere in it is an **error** naming the
  dotted path with the group in it — `unknown key "video.filters[1].kindd" in an action end patch` —
  and a `shape` object is an unknown key, because a shape is not animatable and the key would be
  stored, reported as success and animate nothing. VALUES are not range-checked, so an end state may
  name what no stored group could hold and the evaluator clamps it (§5.4's `clamp_video`). One
  refusal is about the op rather than the vocabulary: a `video` object naming `motion` is an
  **error** (format version 8, §5.4), because a preset is anchored to the clip's two ends rather
  than being a value to ramp between two states, and the evaluator would restore the base value
  anyway. A `text` object naming `words` — a `null` included — is an **error** too (format version
  9, §11 W-6): a word's times are anchored to speech, not a state to ramp toward. A `graphic` object
  — a `null` included — or `graphic` in `off` is an **error** in G-10's sentence, `props are not
  animated by actions; a graphic animates itself — change the module or its props` (§11 G-10).
- **`remove_action {clip, action}`** —

## Tracks, markers, canvas, media

- **`add_track {index?, name?}`** — Inserts (index 0 = back).
- **`remove_track {track, with_clips=false}`** — Refuses on a non-empty track unless `with_clips`.
- **`move_track {track, index}` · `set_track {track, name?, hidden?, muted?, locked?, solo?}`** —
  Omitted fields keep their value. `solo` (format version 3) is §5.2's container rule — while any
  track in the set is soloed every other is treated as muted, mute wins, audio only, a nest's tracks
  judged among themselves — applied as a 0 envelope in `audio.rs` (§7.2) and never in the plan, so a
  solo toggle changes ramps and nothing else.
- **`remove_empty_tracks`** —
- **`add_marker {at, name?, chapter?, color?}` · `set_marker {marker, time?, name?, chapter?,
  color?}` · `remove_marker {marker}`** — Markers snap to frames; two markers may not share a time.
  Default color `red`.
- **`set_canvas {width?, height?, fps?, background?, rescale_clips?, fit_new_clips?,
  timecode_frames?}`** — `rescale_clips` multiplies every clip's `x`, `y`, `scale` by the size
  ratio. Changing fps normalizes top-level and every stored nest's clip starts, source-bounded
  durations, action spans, present base motion/text timing and a graphic's `in` and `length`, plus
  top-level markers (§11, D7-3, G-18·b). Size-only and same-fps edits leave legacy timing alone.
- **`add_media {descriptor}` → returns the id · `relink_media {media, path, bookmark?}` ·
  `remove_media {media, with_clips=false}`** — The descriptor is the `media[]` element minus `id`;
  the host probes the file.

**This table is the SEMANTICS half of the op table, and it has a second
half.** What an op MEANS is written here and in `core/src/edit.rs`'s module
doc — including what an absent argument means, which is why the defaults are
spelled in the rows above. What an op TAKES — every argument's name, its JSON
kind and whether the decoder requires it — is DATA, in `core/src/op_table.rs`,
one row per op and one `Argument` per argument, published as one JSON Schema
per op by `rc_op_schemas` (road map 7's D3). An argument carries a range there
only where the core REFUSES outside it, sourced from the constant that
enforces it; a range the core merely clamps to is not a promise and is not
published. `OP_NAMES` is a projection of that table rather than a list beside
it, so the op count is one number in one place.

Every op is also an MCP tool with the same name, and that tool PRINTS the
arguments half rather than restating it (§7.9).
