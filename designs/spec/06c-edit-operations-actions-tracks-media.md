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
- **`set_action {clip, action, start?, duration?, curve?}`** — Same overlap checks.
- **`set_action_end {clip, action, patch, off?, schema?}`** — Merges into the end patch; a key set to `null`
  removes it, at any depth. `off` — a list of `"group.key"` paths, `group` one of `video`, `audio`,
  `text` and `key` a top-level key of it — writes a `null` at each AFTER the merge, which keys that
  optional property OFF at the end (§5.4, §11 CI-14); a malformed path, `video.motion`,
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
  9, §11 W-6): a word's times are anchored to speech, not a state to ramp toward. A `graphic` object
  is a graphic clip's props as a fourth target (format version 13, §11 G-34): `{props: {<key>:
  <value>}}`, each non-null prop checked as `set_graphic` checks it against `schema` — the module's
  CURRENT revision, which the app fills and never takes from a caller (G-4) — and refused under
  `graphic.props.<key>`; no schema (`graphic.props.<key> needs its module's schema to animate, and
  none came with the op`), a prop the schema lacks (an unknown key) and an `asset`
  (`graphic.props.<key> is an asset; an action does not animate an image — set it with
  set_graphic`) are each an **error**, and so are `name`, `width`, `height`, `in` and `length`
  (`graphic.<key> is not an animation target; an action animates graphic.props`). Each named prop's
  schema `type` is written into the end's `kinds`, and a `kinds` in the patch is read and discarded,
  so an end read back from `get_project` can be sent again. A number and a colour ramp; a string,
  a boolean and an enum switch at the end. A prop the clip's own `props` lacks gets the schema's
  CURRENT default appended to them in the same edit. `graphic: null` or `graphic.props: null`
  removes the group; a `null` prop removes the prop and its kind, unchecked. `graphic` in `off` is
  an **error**: `graphic props cannot be keyed off; name the value a prop ends at in patch`.
- **`remove_action {clip, action}`** —

## Tracks, markers, canvas, media

- **`add_track {index?, name?}`** — Inserts (index 0 = back).
- **`remove_track {track, with_clips=false}`** — Refuses on a non-empty track unless `with_clips`.
- **`move_track {track, index}` · `set_track {track, name?, hidden?, muted?, locked?, solo?,
  matte?}`** — Omitted fields keep their value. `solo` (format version 3) is §5.2's container
  rule — while any track in the set is soloed every other is treated as muted, mute wins, audio
  only, a nest's tracks judged among themselves — applied as a 0 envelope in `audio.rs` (§7.2) and
  never in the plan, so a solo toggle changes ramps and nothing else. `matte` (format version 14,
  §11 MT-1) is one of `none`, `alpha`, `alpha_inverted`, `luma`, `luma_inverted`; `"none"`
  switches a matte off, an unknown name is invalid input naming the five, and re-choosing the
  current mode is an identity. It changes the recipe alone (§7.3's `matte` and `mattes`), never
  the plan: a matte track's clips decode and sound as on any track. `move_track` and
  `remove_track` change which track is behind a matte, visibly (MT-2).
- **`remove_empty_tracks`** —
- **`add_marker {at, name?, chapter?, color?}` · `set_marker {marker, time?, name?, chapter?,
  color?}` · `remove_marker {marker}`** — Markers snap to frames; two markers may not share a time.
  Default color `red`.
- **`set_canvas {width?, height?, fps?, background?, rescale_clips?, fit_new_clips?,
  timecode_frames?, output?, blending?}`** — `rescale_clips` multiplies every clip's `x`, `y`, `scale` by the size
  ratio. Changing fps normalizes top-level and every stored nest's clip starts, source-bounded
  durations, action spans, present base motion/text timing and a graphic's `in` and `length`, plus
  top-level markers (§11, D7-3, G-18·b). Size-only and same-fps edits leave legacy timing alone.
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
  another kind is refused, and a media clip that runs past a shorter file's end is held to it; an
  absent `probe` keeps the record (§11, #63). The descriptor and the probe both carry `original`,
  the WebM or Matroska file a `.mov` copy was made from (§11 #228-O): `add_media` stores it, a
  probe with one replaces the stored one, a probe without one clears it, and no probe keeps it.
  A `lut` row (§11 GR-8) — a `.cube` file — carries no video, audio,
  alpha or duration (`a lut media has no video, audio, alpha or duration`), and `remove_media` of a
  LUT refuses while it is some clip's base look (`media 7 is the look of clip 3; pass with_clips:
  true to remove it and clear their looks`); `with_clips` then clears those looks, on the timeline
  and in every nest, and keeps the clips; an action's end naming it is left, inert. The
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
