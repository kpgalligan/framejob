# 6c Edit operations — actions, tracks, markers, canvas, media

The rules every op shares are §6a; the clip ops are §6b.

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
- **`switch_layout {camera, screen?, layout, shape="square", corner="bottom_right", at,
  duration=0.5 s, curve="ease_in_out", focus=[0, 0], nest=false, through?}`** — A camera layout at
  `at` (road map creator-jobs CO6, §11 CO-60…CO-65): the `camera` clip and the `screen` behind it
  placed in `layout` — `corner` (`shape` square, rounded or circle; `corner` bottom_right,
  bottom_left, top_right, top_left), `side_by_side`, `stacked`, `camera_full` or `screen_only` —
  each role written all six placement keys (`x`, `y`, `scale`, `crop`, `corner_radius`,
  `opacity`) as `core/src/layout.rs` solves them. Per role the clip under `at` gets a LAYOUT
  ACTION at clip time `at − start` of `duration`, clamped to the clip and the next later layout
  action on it, at least one frame; at its first frame the layout is its base plus a one-frame
  layout action ending there. One starting at `at` is replaced, one running at `at` is shortened
  to end there. The REACH runs to the first later layout action on the role's track, `through`,
  or the track's end; every picture clip starting inside it takes the layout as its base and keeps
  its actions. `screen` absent is the clip playing at `at` on the front-most shown, non-matte
  track behind the camera's with a drawn picture; none lays out the camera alone. `focus` is the
  camera crop's centre in source pixels from the uncropped centre, y down. **Errors**: a negative
  `at`, a non-positive `duration`, `through` not after `at`, a non-finite `focus`. **Refused**, in
  order: `clip {id} has no picture to lay out`, `clip {id} does not play at {timecode}` (the
  camera, then a given screen), `the screen (clip {s}) must be on a track behind the camera's
  (clip {c})`, `no clip draws behind clip {c} at {timecode} to be the screen` (side_by_side and
  stacked), `clip {id} is a nest clip, which cannot draw a rounded corner or a circle.`, a role
  clip in the reach with a non-layout action that moves it and ends after `at` — `The {screen|
  camera} clip {id} at {timecode} {zooms|moves} (action {a}); nest the {role}'s clips so the
  layout moves the nest and the {zoom|action} stays inside it.` (a screen at its full placement
  is exempt in corner, camera_full and screen_only) — then `add_action`'s own. `nest: true`
  nests the moving role's clips first and lays out the nest clip, refused `clip {id} is already
  laid out; a nest would lay it out twice.` when one is. One undo step.
- **`reframe_clip {clip, follow, zoom=1, where_empty="fit", from_width?, from_height?, backdrop?,
  replace=false, subjects?}`** — Frames one clip on the current canvas (road map creator-jobs
  VR2a2 and VR2b1, §11 VR-20…VR-27). `follow` `subject` (faces, then people, then salient regions), `face`, `person` or
  `salient` follows the analysed `subjects` — `{samples: [{t, faces?, people?, salient?: [{x, y, w,
  h, c}]}], shots: [t]}` in forward-media SOURCE ticks, boxes 0–1 of the upright picture from its
  top-left, read strictly (an object at every level, a stray, missing or wrong-typed member an
  **error** naming its path) — with the core's planner: eased moves out of a dead zone, a hard cut
  at each shot change (a one-frame linear segment onto the new shot's first-second median), a lost
  subject held 1 s then another followed or an 0.8 s ease to `where_empty` (`fit`, the whole
  picture; `center`, the window on the picture's centre), a return after 0.6 s seen, two people
  framed together when both widened boxes fit. `cursor` (§11 VR-50) follows `subjects.cursor`,
  `[{t, x, y, click?, typing?}]` in the same ticks and frame (`click` and `typing` false when
  absent; `samples` and `shots` still required), with `reframe_cursor.rs`'s planner: the points
  in the played window, one per clip tick; the window centred on the point clamped into the
  picture, no headroom; the first key on the first point; a dead zone ±0.20 of the window's width
  and ±0.12 of its height (0.8 window widths a second, a move at least 0.4 s); a down click
  outside it ARRIVES — a move ending on the click's frame, planned back from it and started no
  earlier than the last move's end, so a running move shortens it; any other point outside it
  starts VR-23's move unless one runs, it is within 0.5 s of the last move's end with the
  pointer in the window, it would end after a pending arrival's start, or the point is `typing`;
  no cut and no `fit`, so `where_empty` and `backdrop` never act. A face follow never reads
  `cursor`. `center` holds the window (fill × `zoom`) on the
  picture's centre and `fit` the whole picture; `keep` rescales the base from `from_width ×
  from_height` (the canvas when absent) by `set_canvas`'s rule, and each `x`, `y` and `scale` an
  action's end names with it. The path F is COMPOSED into the clip (VR-27), its placement P(t)
  the clip's evaluated `video`: the planner reads each sample through P at its tick and clamps
  the window inside the common cropped rect of the base and every action end, raising the zoom
  until it fits (at most `SCALE_MAX` at every placement); the base becomes F′(0)∘P(0), and an
  action end naming `x`, `y` or `scale` (or one F′ changes across) writes `video.{scale, x, y}` =
  F′(end)∘P(end). A cut splits the action it lands in into a head (its id, curve and the
  evaluated state at `c − frame`, narrowed to its keys), a one-frame `linear` piece (the state at
  `c`) and a tail (its end and curve) — so a linear action plays unchanged and an eased one is
  re-eased on each side — except an action naming `speed` or running past the clip's end, which
  carries the cut. Then each move is its own action (ends `{video: {scale, x, y}}`) in a gap,
  shifted up to 0.5 s earlier to end where the action it overlaps starts, or else carried by that
  action: the framing holds to its start and reaches the move's value at its end along its curve,
  later moves inside it chaining. New actions and tails take ids in time order; the actions are
  written in start order. `replace: true` (every follow but `keep`) first removes `x`, `y` and
  `scale` from every end's `video` (an emptied group, then an emptied end's action, removed) and
  sets the base to the picture fitted. With no actions this is one action per later change of
  value from the base, as VR2a2 wrote it. `backdrop`: when the framing shows `fit` anywhere, one blurred copy of the whole
  clip (`add_blurred_background`'s builder) on that track when it is unlocked, not a matte and
  free over the clip, else on a new back-most track (ids: actions, track, copy), keeping the
  clip's actions that name `speed`, each end narrowed to `speed`. Only `keep` reads
  `from_*`; `fit` and `keep` ignore `zoom`; only the following kinds read `where_empty`, and they
  and `cursor` read `subjects`. **Errors**, in order: an unknown clip; `zoom must be between 1 and 4 times fill, not
  {z}`; `from_width must be greater than 0, not 0` (and `from_height`); an unknown `backdrop`
  track. **Refused**, in order: `clip {id} is a {text|shape|graphic|adjustment} clip, with no
  picture to frame; only keep reframes it`; `clip {id}'s media has no picture to frame`, `clip
  {id}'s crop or scale leaves no picture to frame`; with a following kind or `cursor` `clip {id}
  shows a nest, …` then `clip {id} shows a still picture, …`, then `cursor` on a media clip whose
  media has no cursor file, `clip {id}'s media has no cursor file, so there is no cursor to
  follow; frame it with subject, center, fit or keep`, and a following kind on one whose media
  has one (§11 VR-51), `clip {id}'s media has a cursor file, so it follows the cursor, not faces;
  frame it with cursor, center, fit or keep`; unless `keep`, a matte (`clip {id} is on a matte
  track, …`, `clip {id} is cut by the matte on track {t}, …`), then a turn (`clip {id} is turned
  {r}°, …`, `clip {id}'s action {a} turns it, …`, `clip {id} spins in its motion, …`); bad
  `subjects` (over 100,000 samples, over 8 boxes of a kind, times
  not strictly increasing, a value outside 0…1, a size ≤ 0; over 100,000 cursor points, cursor
  times not strictly increasing, a cursor `x` or `y` outside 0…1, each naming `cursor[i]`); when a copy would be made,
  `add_blurred_background`'s nest sentence or `track {t} is not behind clip {id}'s track, so a
  backdrop there would cover it`; LAST, `clip {id} has no subjects to follow; analyze it first`
  (for `cursor`, no `subjects` or no cursor point in the played window). A
  result equal to the clip is an identity. Allowed inside a nest, whose canvas is the view's. One
  undo step. Its UI path is Clip ▸ Follow Subject… (§11 VR-29): this op with `replace: true` on
  each selected movie clip and a "Backgrounds" track added at index 0 as `backdrop`, removed
  when no copy needed it, as one undo step "Follow Subject".
- **`add_speed_ramp {clip, shape, rate, from?, to?, curve="ease_in_out", hold=0.5}`** — A speed
  ramp preset in one step, made of ordinary Speed actions (§11 SR-23, #340): `shape` is `ramp_up`,
  `ramp_down`, `speed_dip` or `speed_burst`; `from` and `to` are CLIP time, both or neither (the
  whole clip). The base b is the rate the clip plays at `from` before the edit. Up and Down are one
  action [from, to) ending at `rate`; Dip and Burst are two of r = max(snapped_down((to − from)·(1 −
  hold)/2), one frame) each, [from, from + r) ending at `rate` and [to − r, to) ending at b, the
  target held between. `hold` (Dip and Burst only) is clamped to 0–0.9. Up and Burst need a rate
  above b, Down and Dip one below it. **Errors**: a non-media clip (the end-rate door's sentence),
  `rate must be a positive number`, one of `from`/`to` alone, a negative `from`, `to` not after
  `from`, `hold is for speed_dip and speed_burst only`. **Refused**, in order: `to` past the clip
  (`add_action`'s sentence); any action the span runs into, named, a hold gap included; a Dip or
  Burst under two frames; the direction (`a ramp up needs a rate above ×{b}, the rate clip {c}
  plays at {from} ticks into it; ×{rate} is not`); and a preset that would read past the end of
  its media (SR-2), `{name} to ×{rate} would read clip {c} {over} ticks past the end of its media;
  the largest rate that fits is ×{fit}`. One undo step. The app's doors append, in the same step,
  the re-time of the caption clips over a clip with sound (§11 SR-27, #341: the tool's answer adds
  `captions_retimed` / `captions_removed`); the op itself moves no caption.
- **`set_action {clip, action, start?, duration?, curve?}`** — Same overlap checks. **Refused**
  (`add_action`'s past-end sentence) only when the new end is past the clip's end AND later than
  the action's end before the edit (§11 SR-22, #338): an action already running past the end — a
  trim or a ramp scale can leave one there — can be re-curved, moved earlier or shortened, and one
  inside the clip still cannot be pushed past it. When the
  action's end names a `speed` (§11 SR-10) and the change would make the clip read past the end of
  its media it is **refused** (SR-2): `retiming action {a} would read clip {c} {over} ticks past
  the end of its media; the latest clip end that fits is {end} ticks`. The app's doors append, in
  the same step, the re-time of the caption clips over a clip with sound (§11 SR-27, #341: the
  tool's answer adds `captions_retimed` / `captions_removed`); the op itself moves no caption.
- **`set_action_end {clip, action, patch, off?, schema?}`** — Merges into the end patch; a key set to `null`
  removes it, at any depth. `off` — a list of `"group.key"` paths, `group` one of `video`, `audio`,
  `text` and `key` a top-level key of it — writes a `null` at each AFTER the merge, which keys that
  optional property OFF at the end (§5.4, §11 CI-14), and `audio.eq.<slot>` — `high_pass`,
  `low_shelf`, `band_1`, `band_2`, `band_3`, `high_shelf` or `low_pass` — writes it at that slot
  of the end's `eq`, one EQ slot keyed off (§11 AU-88), the only three-part path (an unknown slot
  is an **error** naming the seven, any other deeper path the `"group.key"` one); a malformed
  path, `video.motion`, `video.cutout` (format 39, §11 CO-20: `video.cutout cannot be keyed off
  at an action's end; set_video {cutout: null} removes it`), `video.hide_silent` (format 43,
  §11 CO-92: `video.hide_silent is not an animation target`, as a `patch` naming it — a `null`
  included — is too),
  `text.words`, a required key (`video.opacity`), a key the group does not have and a path the patch
  also names are each an **error**. Absent or `null` is none. The patch is walked like every other
  one (§5.4): the three groups it may name are `video`, `audio` and `text`, and an unknown key, a
  value of the wrong JSON kind or a misspelt variant anywhere in it is an **error** naming the
  dotted path with the group in it — `unknown key "video.filters[1].kindd" in an action end patch` —
  and a `shape` object is an unknown key, because a shape is not animatable and the key would be
  stored, reported as success and animate nothing. VALUES are not range-checked (except a graphic prop's end, §11 G-34 (c)), so an end state may
  name what no stored group could hold and the evaluator clamps it (§5.4's `clamp_video`). One
  refusal is about the op rather than the vocabulary: a `video` object naming `motion` is an
  **error** (format version 8, §5.4), because a preset is anchored to the clip's two ends rather
  than being a value to ramp between two states, and the evaluator would restore the base value
  anyway. A `text` object naming `words` — a `null` included — is an **error** too (format version
  9, §11 W-6): a word's times are anchored to speech, not a state to ramp toward. A
  `video.cutout` object naming `subject` or `quality` — a `null` included, `subject` first — is an
  **error** (format 39, §11 CO-20: `video.cutout.subject is not an animation target`): which
  subject and which masks are the clip's own, and the evaluator restores the base's; `edge`,
  `feather` and `background` animate. A `graphic` object
  is a graphic clip's props as a fourth target (format version 13, §11 G-34): `{props: {<key>:
  <value>}}`, each non-null prop checked as `set_graphic` checks it against `schema` — the module's
  CURRENT revision, which the app fills and never takes from a caller (G-4) — and refused under
  `graphic.props.<key>`; no schema (`graphic.props.<key> needs its module's schema to animate, and
  none came with the op`), a prop the schema lacks (an unknown key), a prop whose schema entry says
  `animate: false` (§11 G-41; `graphic.props.<key> is marked animate: false by its module; an
  action does not animate it — set it with set_graphic`) are each an **error**, and so are `name`,
  `width`, `height`, `in` and `length`
  (`graphic.<key> is not an animation target; an action animates graphic.props`). Each named prop's
  schema `type` is written into the end's `kinds`, and a `kinds` in the patch is read and discarded,
  so an end read back from `get_project` can be sent again. A number and a colour ramp; a string,
  a boolean, an enum and an asset switch at the end, and `""` names no image (§11 G-42). A prop the clip's own `props` lacks gets the schema's
  CURRENT default appended to them in the same edit. `graphic: null` or `graphic.props: null`
  removes the group; a `null` prop removes the prop and its kind, unchecked. `graphic` in `off` is
  an **error**: `graphic props cannot be keyed off; name the value a prop ends at in patch`.
  `speed` (format version 27, §11 SR-10) is a media clip's rate as a fifth target, a number at the
  patch's top beside the groups, stored clamped to ×0.1–×1000; `null` removes it, and `off`
  cannot name it (a path is `group.key`). Any other JSON kind is an **error** (`speed must be a
  number, not "fast"`), and so is a clip that is not a media clip (`clip {c} is not a media clip,
  and only a media clip's action can end at a speed`). The clip keeps its start and duration
  (SR-2); an end rate that would read past the end of its media is **refused**, naming the
  largest end rate that fits, floored to 0.001: `ending action {a} at ×{x} would read clip {c}
  {over} ticks past the end of its media; the largest end rate that fits is ×{fit}` — or, when no
  rate down to ×0.1 fits, `…, and no end rate down to ×0.1 fits; at ×0.1 the latest clip end that
  fits is {end} ticks`; and a `null` that would do so is refused as `removing action {a}'s end
  rate would read clip {c} {over} ticks past the end of its media; the latest clip end that fits
  is {end} ticks`. `over` is `in + round(S(duration))` less the media's duration; `end` is the
  clip's start plus the latest clip time whose S fits, snapped down to the frame grid. Above ×12
  the clip's audio is left out of the plan (#190), and an agent's answer carries
  `audio_left_out` and `audio_note`. When the patch names `speed`, the app's doors append, in the
  same step, the re-time of the caption clips over a clip with sound (§11 SR-27, #341: the tool's
  answer adds `captions_retimed` / `captions_removed`); the op itself moves no caption.
- **`remove_action {clip, action}`** — Removing an action whose end names a `speed` is
  **refused** when the clip would then read past the end of its media: `removing action {a}
  would read clip {c} {over} ticks past the end of its media; the latest clip end that fits is
  {end} ticks`. The app's doors append, in the same step, the re-time of the caption clips over a
  clip with sound (§11 SR-27, #341: the tool's answer adds `captions_retimed` / `captions_removed`);
  the op itself moves no caption.

## Tracks, markers, canvas, media

- **`add_track {index?, name?}`** — Inserts (index 0 = back).
- **`remove_track {track, with_clips=false}`** — Refuses on a non-empty track unless `with_clips`.
- **`move_track {track, index}` · `set_track {track, name?, hidden?, muted?, locked?, solo?,
  matte?, volume?, pan?, compressor?, limiter?}`** — Omitted fields keep their value. `solo` (format version 3) is §5.2's container
  rule — while any track in the set is soloed every other is treated as muted, mute wins, audio
  only, a nest's tracks judged among themselves — applied as a 0 envelope in `audio.rs` (§7.2) and
  never in the plan, so a solo toggle changes ramps and nothing else. `matte` (format version 14,
  §11 MT-1) is one of `none`, `alpha`, `alpha_inverted`, `luma`, `luma_inverted`; `"none"`
  switches a matte off, an unknown name is invalid input naming the five, and re-choosing the
  current mode is an identity. It changes the recipe alone (§7.3's `matte` and `mattes`), never
  the plan: a matte track's clips decode and sound as on any track. `move_track` and
  `remove_track` change which track is behind a matte, visibly (MT-2). `volume` (linear, 0–4)
  and `pan` (−1–1) are the track's fader and balance (format version 35, §11 AU-102): a value
  outside its range is invalid input in `in_range`'s sentence (`volume must be between 0 and 4,
  not 5`). Volume is an envelope term after mute (AU-103); pan is the plan's `track_pans`
  (§7.2, AU-104). `nest` copies both from every source track but the nest clip's destination,
  whose copy is unity and centre; `unnest` keeps neither. `compressor` and `limiter` (format
  version 36, §11 AU-150) are the track's dynamics, post-fader on its sub-mix (AU-151): an object
  REPLACES the whole value, its missing keys the clip type's defaults; `null` clears it. Refused
  as invalid input, each in its own sentence: a value neither an object nor `null` (`compressor
  must be a json object or null, not 5`), an unknown key (`unknown key "compressor.knee" in
  set_track`), a mistyped member (`bad value at "limiter.release" in set_track: …`), and a value
  outside the clip's ranges under the track's key (`compressor.ratio must be between 1 and 20,
  not 30`). Inside a `scope` either key is invalid input (`a track's compressor or limiter has no
  meaning inside nest 5`), and `nest` gives the nest's tracks none.
- **`remove_empty_tracks`** —
- **`add_marker {at, name?, chapter?, color?}` · `set_marker {marker, time?, name?, chapter?,
  color?}` · `remove_marker {marker}`** — Markers snap to frames; two markers may not share a time.
  Default color `red`.
- **`set_canvas {width?, height?, fps?, background?, rescale_clips?, fit_new_clips?,
  timecode_frames?, output?, blending?}`** — `rescale_clips` multiplies every clip's `x`, `y`, `scale` by the size
  ratio. Changing fps normalizes top-level and every stored nest's clip starts, source-bounded
  durations, action spans, present base motion/text timing and a graphic's `in` and `length`, plus
  top-level markers (§11, D7-3, G-18·b); a ramped clip's speed actions are snapped but not clamped
  into it, and its duration is held again against them (§11 SR-19 (g)). Size-only and same-fps
  edits leave legacy timing alone.
  `output` (`sdr` or `hlg`, format 23, §11 HD-2, HD-13) sets the project's dynamic range and
  changes no clip or grade; the output the canvas has is an identity, and another value is
  invalid input naming serde's list (`unknown variant \`pq\`, expected \`sdr\` or \`hlg\``).
  `blending` (`encoded` or `linear`, format 24, §11 GR-18, HD-16) sets how layers blend and
  changes no clip or grade; the blending the canvas has is an identity, and another value is
  invalid input naming both (`unknown variant \`gamma\`, expected \`encoded\` or \`linear\``).
- **`add_media {descriptor}` → returns the id · `relink_media {media, path, bookmark?, probe?}` ·
  `remove_media {media, with_clips=false}`** — The descriptor is the `media[]` element minus `id`;
  the host probes the file. `relink_media`'s `probe` is the new file's descriptor minus `path` and
  `bookmark`, filled by the host: the media takes its duration, size, rate and flags, a file of
  another kind is refused, and a media clip that runs past a shorter file's end is held to it (a
  ramped one through S∞, its actions unchanged, §11 SR-19 (h)); an absent `probe` keeps the
  record (§11, #63). The descriptor and the probe both carry `original`,
  the WebM or Matroska file a `.mov` copy was made from (§11 #228-O): `add_media` stores it, a
  probe with one replaces the stored one, a probe without one clears it, and no probe keeps it.
  They carry `cursor` the same way (format 38, §11 CU-39): `{path, bookmark?, in_picture}`, the
  cursor file recorded beside a video, stored, replaced, cleared and kept as `original` is; an
  empty path and any media but a video with a picture are errors in `check_media_fields`' words.
  A `lut` row (§11 GR-8) — a `.cube` file — carries no video, audio,
  alpha or duration (`a lut media has no video, audio, alpha or duration`), and `remove_media` of a
  LUT refuses while it is some clip's base look (`media 7 is the look of clip 3; pass with_clips:
  true to remove it and clear their looks`); `with_clips` then clears those looks, on the timeline
  and in every nest, and keeps the clips; an action's end naming it is left, inert. Removing any
  other media clears every `video.hide_silent` naming it, on the timeline and in every nest, with
  no refusal of its own (format 43, §11 CO-92): a gate does not use its media. The
  descriptor may carry `color` (format 19, §11 GR-16), the Camera Log import detected (`{log:
  "apple_log", gamut: "bt2020", detected: true}`) or a PQ file's peak (`{pq: {file: 4000, from:
  "max_cll"}}`, format 22, §11 HD-12), held to `set_media_color`'s rules as an error; a relink's probe may NOT carry it (`unknown key "color" in a relink probe`), and a relink
  keeps the stored one. A LUT that is a media's Camera Log refuses `remove_media` too (`media 7
  is the Camera Log of media 3; pass with_clips: true to remove it and clear it`, or, with looks,
  `media 7 is the look of clip 5 and the Camera Log of media 3; pass with_clips: true to remove
  it and clear both`); `with_clips` clears those conversions as well.
- **`set_media_color {media, color}`** — A video media's Camera Log (§11 GR-16): `color` is
  `{log, gamut?}` — `apple_log` (gamut `bt2020`), `apple_log2` (`apple_wide_gamut`), `slog3`
  (`s_gamut3_cine` or `s_gamut3`), `vlog` (`v_gamut`), `canon_log2` or `canon_log3` (Canon Log
  2 and 3, §11 HD-17: `cinema_gamut` or `bt2020`), an absent `gamut` stored as the curve's
  first — or `{lut}`, a `lut` media converting the file instead; `null` clears it (an identity
  with none). Every clip of the media, its stills and its reverse are converted at step 0
  (§7.5), before the chroma key and every grade. What is stored has no `detected`. `Err` for an
  unknown media (`no media with id 9`), a `color` that is not an object or `null` (`color must
  be a json object or null, not a number`), an unknown key (`unknown key "foo" in color`) or a
  word outside the vocabulary (serde's `unknown variant`); refused, each in its own sentence:
  `media 2 is an audio file; Camera Log is a setting on a video file` (`an image`, `a LUT`
  likewise), `color needs log or lut; null clears it`, `color takes log or lut, not both`,
  `color.gamut goes with log`, `slog3 takes gamut s_gamut3_cine or s_gamut3, not v_gamut`
  (`canon_log2 takes gamut cinema_gamut or bt2020, not s_gamut3` likewise),
  `color.lut 9 is not a media of this project`, `color.lut 5 is a video media, not a lut`,
  `color.detected is written by import, not set`. A PQ file's **`peak`** (§11 HD-12, a whole
  number of cd/m²) overrides the peak import read into `pq`, beside `log` or `lut` or alone:
  `color` replaces the Camera Log and the override together, import's `pq.file` and `pq.from`
  survive every op, and `null` clears both, keeping the reading (an identity with neither).
  Refused besides: `color.pq is read from the file at import, not set`, `media 3 is not a PQ
  file; only a PQ file takes a peak`, `color.peak must be 1–10000 cd/m², not 0`; an asked
  `color` with none of `log`, `lut` and `peak` keeps `color needs log or lut; null clears it`.
  A PQ still (§11 HD-20 (b): an image media import gave `pq`) takes `peak` alone; any other
  `color` on an image, `{}` included, keeps the kind sentence `media 5 is an image; Camera
  Log is a setting on a video file` (a `peak` on a non-PQ image keeps its own sentence);
  a `peak` that is not a whole number is an `Err` (`color.peak must be a whole number of
  cd/m², not a string`). A `scope` is an `Err` (`set_media_color has no meaning inside nest
  4`): a nest shares the document's media.
- **`set_media_speech {media, spans}`** — A media's speech spans (format version 29, §11 AU-110,
  AU-111): `spans` is `[[start, end], …]` in SOURCE ticks of the file played forward, stored as
  `media.speech` exactly as given (never snapped: the voice cache's grid is 19,200 ticks), and read
  by every clip of the media whose `audio.duck.mode` is `speech`. An empty list is stored too — a
  file with no speech found. Spans equal to the stored ones are an IDENTITY. `Err` for an unknown
  media (`no media with id 9`); refused, each in its own sentence: `media 2 has no audio, so it has
  no speech to duck by`, `media 1 speech span 0 starts at -1, before 0`, `media 1 speech span 0 ends
  at 600000, not after its start 600000`, `media 1 speech span 0 ends at 12600000, past the media's
  duration 12000000`, `media 1 speech span 1 starts at 600000, before span 0 ends at 1800000: speech
  spans are sorted and do not overlap`, `media 1 carries 100001 speech spans, more than 100000`.
  The app's Duck by Speech writes it in the same undo step as the `set_audio` that turns the mode
  on, only for a media without spans. A `scope` is an `Err` (`set_media_speech has no meaning inside
  nest 4`).
- **`set_media_cursor {media, cursor}`** — A media's cursor file (road map "creator-jobs" CU5, §11
  CU-50): `cursor` is `{path, bookmark?, in_picture}`, the `media.cursor` record of §5.2a, stored as
  given, or `null`, which clears it. `null` on a media with none and a value equal to the stored one
  are IDENTITIES. Read strictly: neither an object nor `null` (`cursor must be a json object or
  null, not "a.fjcursor"`), a key other than the three (`unknown key "movie_size" in cursor`), a
  value the record's shape refuses (``cursor does not match the schema: missing field
  `in_picture` …``) and an unknown media are each an `Err`. Refused, each in its own sentence: `media
  cursor path must not be empty`, `media.cursor needs a video media with a picture, not an audio
  media`. The core opens no file; the tool and the Media tab's Locate… check the file first
  (§11 CU-50 (b)). Locate… and Remove write it, Consolidate's second copy and the open-time
  re-anchor too (CU-51, CU-52). A `scope` is an `Err` (`set_media_cursor has no meaning inside
  nest 4`).

**This table is the SEMANTICS half of the op table, and it has a second
half.** What an op MEANS is written here and in `core/src/edit.rs`'s module
doc — including what an absent argument means, which is why the defaults are
spelled in the rows of §6b and §6c. What an op TAKES — every argument's name, its JSON
kind and whether the decoder requires it — is DATA, in `core/src/op_table.rs`,
one row per op and one `Argument` per argument, published as one JSON Schema
per op by `rc_op_schemas` (road map 7's D3). An argument carries a range there
only where the core REFUSES outside it, sourced from the constant that
enforces it; a range the core merely clamps to is not a promise and is not
published. `OP_NAMES` is a projection of that table rather than a list beside
it, so the op count is one number in one place.

Every op is also an MCP tool with the same name, and that tool PRINTS the
arguments half rather than restating it (§7.9).
