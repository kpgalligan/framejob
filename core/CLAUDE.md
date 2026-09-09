# core/CLAUDE.md — Rust core rules

Applies to everything under `core/`. Build commands and the FFI three-file
lockstep are in the root `CLAUDE.md`; the full design is
`designs/reelcut-design.md` (§5–7 are the schemas, §7.10 this module map).

## Module map

- `lib.rs` — module declarations and re-exports only. No implementation code.
- `model.rs` — the spec §5.2 types with serde derives and the serde
  defaults that say what an absent key means. The struct field names ARE
  the JSON keys, and the file is only the schema — its SHAPE: the project,
  its tracks, clips, sources, actions, markers and nests.
- `model_props.rs` — the schema's VOCABULARY: the §5.2 per-clip property
  types (`VideoProps`, `Crop`, `Shadow`, `ColorAdjust`, `Chroma`,
  `Filter`, `Reflection`, `BlendMode`, `AudioProps`, `Compressor`, `Duck`,
  `ShapeProps`, `Stroke`, `Gradient`, `GradientKind`, `GradientStop` and
  their enums) with their
  defaults. Re-exported whole by `model.rs`, so every `crate::model::X`
  path and the `lib.rs` re-exports are unchanged; it is a separate file
  because of the size rule, not a separate concern.
  `BlendMode`'s declaration ORDER **is** load-bearing — it is the shader
  discriminant, as `ObscureKind`'s is: `ProjectSnapshot.swift` derives
  `shaderCode` from the case index and `Compositor.metal` compares against
  integer constants in the same order, so a mode may be appended and the
  eight may never be reordered. `Normal` is 0 with no `+1`, unlike the
  filter and obscure discriminants where 0 is reserved for "empty slot":
  a layer has exactly one blend mode, and 0 meaning source-over is what
  makes a zeroed uniform block, a recipe from an older core and a file
  with no `blend` key all render what every project drew before the key
  existed.
- `model_text.rs` — the text vocabulary: `TextProps`, the `TextAlign` and
  `TextVAlign` it is placed by, the `Outline` and `Backdrop` drawn with
  it, and the `TextAnimation` and `TextAnimationKind` that reveal it. Cut
  out of `model_props.rs` in road map 2's phase 6, when that file stood at
  592 owing `video.blend` and `shape.gradient`, and cut HERE because text is
  the one property group the model cannot MEASURE: every other group is
  quantities the core bounds, interpolates and solves geometry against,
  while only the platform can lay a string out and the measurement comes
  back the other way, through a cache the renderer fills. Nothing in this
  file is ever a measured size, and that is a standing rule rather than an
  omission. Re-exported whole by `model_props.rs`, which `model.rs`
  re-exports whole in turn, so `crate::model::TextProps` and every other
  path is unchanged; `VideoProps.blend` and `ShapeProps.gradient`, the
  fields phase 6 added, stay with their own groups.
  `TextAnimationKind` is closed at three for `ObscureKind`'s reason — each
  variant is a different drawing routine and there is no neutral one to
  fall back to — but its declaration ORDER is not load-bearing, where
  `ObscureKind`'s and `BlendMode`'s are shader discriminants: the recipe
  carries a reveal's kind by NAME. The JSON spelling of a variant still
  is, so a rename needs a migration step.
- `model_regions.rs` — the boxes drawn ON the picture: `Spotlight`,
  `ObscureRegion`, the `SpotShape` both are drawn with and the
  `MAX_OBSCURE` budget on the second. Cut out of `model_props.rs` in road
  map 2's phase 3c, when `video.obscure` took that file to 633 lines, and
  cut HERE because these are one concern and not three adjacent ones: they
  share one coordinate frame — `x`/`y` the region's CENTRE, as an offset in
  SOURCE pixels from the centre of the layer's CROPPED rect, `width`/
  `height` its size in the same pixels, which is what makes a region ride
  with its layer through scale, move and rotation — and one shape enum,
  reused rather than copied because shared vocabulary has one home.
  `edit_zoom.rs` calls that frame Q and writes the equation out; nothing
  else repeats it. Re-exported whole by `model_props.rs`, which `model.rs`
  re-exports whole in turn, so `crate::model::Spotlight` and every other
  path is unchanged. The FIELDS that hold these values
  (`VideoProps.spotlight`, `VideoProps.obscure`) stay with the video group
  in `model_props.rs`.
- `model_query.rs` — reading a project: `Project::new`, id allocation, the
  `clip`/`track`/`media`/`marker`/`nest` lookups, `clips_on`,
  `is_missing_media`, `duration`, `validate` with its nesting walk, and the
  three source-window measurements every placement op clamps against —
  `source_head` (what lies before the window), `content_length` (the window)
  and `source_length` (what a window starting at `in` could grow to).
- `time.rs` — `Ticks`, `TIMESCALE`, `Fps`, frame snapping, timecode
  format/parse (non-drop `HH:MM:SS:FF` and `HH:MM:SS.mmm`).
- `edit.rs` — the op enum + serde and `apply`. **Its module doc IS the op
  schema table** (the `adjust.rs` pattern in Rasterize) and
  `app/Sources/ReelCore.swift`'s typed builders mirror it.
- `edit_clip.rs` / `edit_props.rs` / `edit_track.rs` / `edit_time.rs` — the
  §6 ops in `impl Project` blocks: clip placement (with `fit_scale` and,
  since phase 6, its sibling `fill_scale` — Fit is a RESCUE for oversized
  footage and Fill is a REQUIREMENT, so Fill ignores `canvas.fit_new_clips`,
  scales up as readily as down, and clamps to `SCALE_MAX` here rather than
  leaving a caller to); the five property
  patches (the four groups, and `set_clip` for the clip's own name and
  label), `check_blend` — the one check that is about a CLIP rather than a
  value, refusing a non-normal blend on a nest clip — and `Group`, the
  vocabulary the patches and `paste_attributes`
  share; tracks, markers, canvas, media; ripple, insert time, range delete
  (one range or several — `ripple_delete_ranges` merges its pairs and cuts
  right to left as ONE edit, and the singular delegates to it), freeze
  frame.
- `props_check.rs` — the range checks every value written into a property
  group passes first: `check_video` / `check_audio` / `check_text` /
  `check_shape`, the `finite` / `in_range` family they are built from, and
  the bounds they check against (`SCALE_MIN`, `SPOT_ZOOM_MAX`, the
  compressor's…), which `actions.rs`'s `clamp_video` reads too. Cut out of
  `edit_props.rs` in road map 2's phase 2, and cut THERE because a range
  check is a fact about the vocabulary, not about an edit: it neither knows
  nor cares whether a patch, a paste, a new title or a canvas colour
  produced the struct it reads. `Project::check_group` (still in
  `edit_props.rs`) is how a patch and a `paste_attributes` copy run the
  same check, so a hand-written payload cannot smuggle in a value the
  inspector would refuse. `check_shape`'s `shape.gradient` arm (format
  version 6) is where the file's one deliberate ABSENCE is argued: the
  stops are checked for count, range and colour and NOT for order, because
  `CGGradient` needs monotonic locations but a refusal would make dragging
  one stop past another stop working half way through the gesture — so the
  renderer sorts, `video.filters` is the precedent for an ordered list the
  core does not police, and the comment says so where the check would have
  gone. One check does NOT live here at all: `check_blend`, which refuses
  a blend mode on a nest clip, is `edit_props.rs`'s, because it is a fact
  about the CLIP and nothing in this file is handed one.
- `edit_edge.rs` / `edit_insert.rs` — the cutting moves that keep something
  fixed on purpose: `slip` and `roll` (the clip's place, and the pair's
  outer edges), `insert_clip` and `overwrite_clip` (the other tracks, and
  the whole timeline's length). `edit_edge.rs` clamps against
  `model_query.rs`'s three source measurements rather than restating them;
  `edit_insert.rs` takes its one length from `edit_clip.rs`'s
  `whole_media_length`, which is the length `add_clip` itself uses, so the
  room an insert opens is exactly the room the clip needs.
- `edit_action.rs` / `edit_nest.rs` / `edit_paste.rs` — the ops with a
  concern of their own: the action ops and their no-overlap rule; `nest` and
  `unnest`; `paste`, which has to make another document's clips fit, and
  `paste_attributes`, which reads the same payload and places nothing —
  the EARLIEST clip's property groups (then the front-most, then the
  lower id; never the array's first, which is creation order) replaced
  whole onto clips already there, never merged.
  (Spec §7.10's table is the same list. Each of these was split out of
  `edit_clip.rs` under the "a new concern is a new module" rule, which is
  also how `edit_props.rs` came about; `edit_clip.rs` was 1736 lines and is
  still 1226 — see "Modules and size" below.)
- `edit_zoom.rs` — `add_zoom_action`, the screencast zoom (road map 2,
  phase 3b): the one op whose substance is GEOMETRY rather than
  bookkeeping, which is why it is not a fifth function in
  `edit_action.rs`. **Its module doc IS the placement equation** — the two
  frames it works between (Q, `model_regions.rs`'s source pixels from the
  cropped rect's centre; C, canvas pixels) and the solve that turns a
  rectangle drawn on the picture into the `scale`/`x`/`y` an action's end
  patch carries, rotation and crop included. The op composes `add_action` +
  `set_action` + `set_action_end` so a drag is one undo step and every
  refusal `add_action` documents is inherited rather than re-copied; the
  canvas band, the inspector's button and the MCP tool all reach the same
  arithmetic here rather than deriving it three times.
- `edit_background.rs` — `add_background` and `add_blurred_background`,
  what goes BEHIND the picture (road map 2, phase 6c): a plate (a colour,
  or an image) or a blurred copy of a clip, each ONE clip on a NEW track
  at index 0 — not on the back-most EXISTING track, because a fresh track
  is the only place "behind everything" is true whatever the stack already
  holds, and it means no overlap to check and one undo step to take it all
  away. They are OPS rather than the app-side composite the road map
  planned, and the module doc argues it: the proposed recipe cannot be
  built (the clipboard payload carries no `nests` key), its repair with
  `add_clip` loses the source WINDOW so a backdrop drifts out of sync with
  the clip it copies, and here it is `clip.clone()` with six VIDEO fields
  overwritten — `scale`, `x`, `y`, `crop`, `filters`, `blend` — over
  vocabulary the app lacks: the source's pixel size,
  `edit_clip.rs`'s `fill_scale`, and the `SCALE_MAX` clamp on it. The rule
  `insert_clip`, `overwrite_clip` and `add_zoom_action` already name: a
  composite becomes an op when composing it carries a constraint no single
  half states. The doc's second half is what a blurred copy does NOT keep —
  its audio switch and its `audio.duck` (first, because both are INVISIBLE
  in a still frame and a frame proof passes with them wrong: the switch
  plays one recording twice, and a duck is not gated by the switch, so a
  copy carrying one would duck the whole mix including the clip it came
  from), its transition, its actions and its label. It refuses a NEST by
  name for the reason `nest.rs`'s `Frame` doc gives as its third limit —
  the flattening drops a nest clip's own filters, so the copy would come
  out sharp — and `add_background`'s media plate takes `fill_scale` where
  `add_clip` takes Fit, since a plate leaving the canvas showing down one
  side has failed at its one job.
- `actions.rs` — action evaluation and interpolation; `clip_state`; and
  `clamp_video`, the evaluator's last line of defence, which bounds every
  value an end patch can carry (`set_action_end` is deliberately lenient,
  so this is the only thing between a hand-written project file and the
  uniform block). The LIST rule lives here too and is stated once as the
  CRATE's rather than one list's: an end patch interpolates a list per
  index when the lengths match and each pair of entries agrees on its
  discrete fields, and switches at the end otherwise. `video.filters` and
  `video.obscure` are both governed by it and neither carries a line of its
  own code. The widened discriminant set (`ENTRY_DISCRIMINANTS`, `kind`
  and `shape`) is confined to list ENTRIES — in a list an entry's only
  identity is its index, so a changed `shape` gives no way to tell a
  reshaped region from a replaced one, while `video.spotlight` is one named
  object whose `shape` is a property of it. Widening the object rule too
  would have frozen the geometry of every spotlight animation: a silent
  change to shipped behaviour, which `core/tests/schema_v2.rs` now pins
  against.
  `clamp_video` carries one bound that is not a range: a NEST clip's
  evaluated `blend` is forced to `normal` (format version 6). It takes an
  `is_nest` argument for it, decided from the clip's source at the one
  call site, because `set_action_end` validates nothing beyond "is it an
  object" and an end patch would otherwise carry a blend onto a nest clip
  past every check the op path has. Closing it in the evaluator closes the
  recipe, `clip_state` and both export writers at once, which no per-op
  check can.
- `transition.rs` — overlap detection, the overlap rule, progress at *t*.
- `evaluate.rs` — `composition_plan()` (A/B assignment, instruction
  tiling) and the `assign()` the recipe shares with it.
- `recipe.rs` — `frame_recipe(t)`: the layer list at one instant, and the
  keys of each layer in it. Where a `text.animation` becomes a NUMBER is
  `recipe_text.rs` now, below; what stays here is the `Source::Text` arm
  that digs the description out of an evaluated clip, and `content_hash`
  with the FNV under it — `pub(crate)` since that cut, because a SHAPE
  layer hashes its description through the same function, so the hash is
  the recipe's texture-cache primitive and not a text concern.
  It is also where a layer's `blend` is emitted, and the ONE place a model
  value is deliberately OVERRIDDEN rather than only evaluated: a layer
  whose `transition` is non-null is written as `"normal"` whatever the
  clip says, because the outgoing half of a dissolve divides its weight by
  the attenuation the incoming pass applies, which is the exact algebraic
  inverse of a FIXED-FUNCTION destination factor — and `add_clip` onto an
  overlap mints a `cross_dissolve` by default, so the wrong picture is a
  minute away. The decision is the core's for `Reveal`'s reason: one
  description, so preview, `render_frame` and both export writers cannot
  disagree, and a core test can read the layer's `blend` at a tick inside
  the overlap where the shader's version would need two PNGs. Say the
  consequence rather than hiding it — the recipe's `blend` is what DRAWS
  while the inspector reads the MODEL's value through `clip_state`, so the
  two legitimately differ during an overlap.
  Two things road map 2's phase 7 added here. `RecipeOptions` is what a
  caller wanted BESIDES `t` — one member, `burn_in_timecode` — and
  `frame_recipe(t)` is now `frame_recipe_opts(t, RecipeOptions::default())`,
  ONE implementation so the two cannot drift; an absent, wrongly typed or
  non-object option means OFF, because the query FFI has no `err_out` and
  NULL at frame rate is a black preview, and the layer that refuses a
  mistyped one by NAME is the MCP handler above. It is deliberately NOT an
  `export_settings` override: that table IGNORES an unknown key, so an
  option sent that way would vanish and an export would report success on a
  file it had not changed. And `RecipeLayer` is the twenty keys of a layer
  written in ONE place, which is what phase 7 owed the file before adding a
  second producer of layers: `RecipeLayer.init(from:)` on the Swift side
  DEFAULTS a missing key silently, so a copied skeleton drifts with no
  diagnostic anywhere.
  Watch the key ORDER trap when reading it: the insertions follow spec
  §7.3's listing for a reader, but `serde_json`'s `Map` is a `BTreeMap`
  here, so every object comes out sorted — which is the property
  `content_hash` leans on, and it means a key inserted in the wrong place
  is a readability bug, not a wire change.
- `recipe_text.rs` — what a text layer SHOWS at one instant: `Reveal::of`
  turns the animation, the clip time and the clip's own duration into the
  `reveal`, `reveal_phase` and `reveal_kind` a text layer's source object
  carries (spec §7.3), `text_hash` folds all three into that layer's
  content hash — the only thing between a per-frame picture and Swift's
  hash-keyed texture cache — and `text_source` assembles the source object
  itself. Cut out of `recipe.rs` under the size rule in road map 2's phase
  7, when that file stood at exactly 600 owing a burn-in timecode layer,
  and cut HERE because placement is the same question for every layer
  while text is the one kind that is not finished when its placement is:
  the model can only state an intent — `model_text.rs` argues that seam in
  the schema, and this is the same seam one stage downstream — and an
  ANIMATED intent is not even fixed, so the recipe must compute a number
  no property of the clip holds and then get it into the texture cache's
  KEY. `text_source` takes a description, a clip time and a duration and
  nothing else — no clip, no instance, no `Evaluated` — so a text layer
  the core SYNTHESIZES is a text layer like any other; `recipe.rs`
  re-exports it, so `crate::recipe::text_source` still resolves. The
  recipe STRIPS `animation` out of the text description it hands over, so
  the computed reveal is the renderer's one account of it; a layer with no
  animation hashes the bare description, byte for byte as it did before
  version 5.
  **The phase is the ORDER the renderer draws in, not a label on the
  amount**, and `Reveal::of` is shaped by that: `word_fade` and
  `line_rise` count their stagger from the far end while a layer is
  leaving, so the frame the phase turns on is a frame the picture mirrors
  on, and the one amount at which the mirror is invisible is 1. The turn
  therefore belongs to the PLATEAU an animation that fits its clip has
  between its two ramps (`in + out <= duration`; a tie goes to the
  arrival). A tent has none — its ramps cross below 1 — so it keeps the
  phase it began in for its whole life, the arrival's unless `in` is 0,
  which leaves the clip nothing but a departure. The limit is documented
  rather than fixed: a tent whose `in` is tiny but not zero reports `"in"`
  from its first frame to its last. `evaluate_tests.rs` sweeps ten timings
  frame by frame and asserts that the phase turns only where the frame
  before it was fully revealed.
  The cut paid for itself immediately: `burn_in_layer` — the timecode
  burn-in `RecipeOptions.burn_in_timecode` appends, phase 7's own — lives
  here, because a burn-in IS a text layer and `text_source` takes a
  description, a clip time and a duration and nothing else. It has no
  animation, so `Reveal::of` answers `WHOLE` and the two time arguments are
  never read; `Reveal`'s own doc sentence was written for exactly this, "a
  layer the core synthesizes rather than reads off a clip can simply not
  have one". Three things about it a reader will otherwise file as bugs, and
  the doc comment argues all three at length: its placement is a FRACTION of
  the canvas height with `valign: middle` and NOT "bottom-centre", because
  the core has no measured text size to subtract from a bottom edge (spec
  §5.3, §11) and a layer's `y` is the offset of the box's CENTRE — the
  Caption preset's `yFraction` is the precedent; the timecode is NON-DROP
  like every other this crate writes, so a 29.97 burn-in reads ~3.6 s behind
  wall clock at the hour, which is the definition and is what the toolbar
  shows; and it reads PROJECT time, so an in/out range export writes a file
  beginning at 00:00 whose burn-in reads the range's start.
- `nest.rs` — flattening a nest into the clips it stands for, and the
  transform they inherit. Every walk over "what actually plays" goes
  through it: `evaluate.rs`, `recipe.rs` and `audio.rs` all consume its
  instances rather than `Project::clips`.
- `audio.rs` — envelopes: fades, volume actions, ducking, mute and solo.
  Solo is judged per container — the timeline, or one nest's own tracks —
  in `Voice::of` against that container's track set (`silenced`: muted, or
  some track in the set soloed and this one not; mute wins), and it is an
  envelope exactly like mute: the plan's segments, `plays_audio` and
  `assign` never see it.
- `snap.rs` — candidates and `resolve`.
- `format.rs` — `RC_FORMAT_VERSION`, the `MAX_*` caps (four of them
  `RC_MAX_*` in the header), read-any-version / write-current.
- `export.rs` — settings resolution: `Project::export_settings`, the one
  thing that reads a canvas, a duration, a rate and an override and meets
  a preset row against them. Still the file whose module doc explains the
  whole export design, and it re-exports `preset` and `presets` beside
  `describe` at their old paths, so nothing outside it had to learn where
  the pieces went.
- `export_overrides.rs` — how an override value is READ and REFUSED, where
  `export_table.rs` is the table and `export.rs` the resolution:
  `describe`, the overrides
  object itself, and the readers for a positive integer, a boolean, a rate,
  a range and a decibel figure, each refusing with a message that names the
  key and the value. Cut out of `export.rs` in road map 2's phase 5, and
  cut THERE for `props_check.rs`'s reason — how a value is spelled is a
  fact about the vocabulary, not about the resolution; nothing in it knows
  which preset asked or what the canvas is. `describe` was never an export
  function at all (five modules import it for their own messages), so
  `export.rs` re-exports it and `crate::export::describe` still resolves.
  The one rule with an exception is the loudness pair: `peak_dbtp` without
  `loudness_lufs` is an `Err`, because normalisation is gain-only and a
  ceiling with nothing to cap would be the crate's first key accepted,
  echoed and silently inert.
- `export_size.rs` — `export_sizes(preset)`: the sizes the export sheet
  offers for a document and a format — the format's cap, the document's
  own size, then the standard sizes named by their SHORT edge and fitted to
  the document's aspect, rounded to even; rows may repeat and the sheet
  hides them. Also `fit_within`, what a size MEANS on an image format (the
  picture fitted inside it, never upscaled), which `export_settings` uses
  so the resolved numbers are the file's.
- `export_table.rs` — the rows themselves: the `Container` enum with the
  four questions a container answers about ITSELF (its extension, its UTI,
  whether a leading index is worth rewriting, whether it can hold sound at
  all), `Preset`, the `PRESETS` set one row per encoding in menu order, and
  the `preset(id)` lookup both resolvers share. Cut out of `export.rs` in
  road map 2's phase 7 — the second cut that file has paid, after
  `export_overrides.rs` — and cut HERE because everything in it is a
  constant no project can influence: an APNG's type identifier is PNG's
  whatever the timeline holds, and GIF caps its size because of what a
  palettised frame-by-frame format costs. `export.rs` keeps the half with a
  `&self` and re-exports both functions, so `crate::export::presets()` and
  `crate::export::preset(id)` resolve as they did. A row's `avf_preset`
  means only "AVFoundation can write this row" since road map 2's phase 5 —
  `null` is what routes an export to the ImageIO writer, so the two LPCM
  rows (`audio_wav`, `audio_aiff`) repeat `audio_m4a`'s name rather than
  carrying a null AVFoundation has no LPCM name to fill.
  A row's `alpha` (phase 7, with the `prores_4444` row) is the other
  capability flag and the one to read carefully: it means "this ENCODING
  carries an alpha channel", true for `prores_4444` and `apng`, and never "the
  canvas is translucent" — `export_settings` emits one flat object for
  every row, so a project-derived flag would say `alpha: true` on an
  H.264, a GIF and a WAV. It is a `Preset` field where `carries_audio` is
  a `Container` one, and the difference is the point: a container decides
  whether a file has an audio track at all, while a fourth channel is the
  CODEC's, and `Container::Mov` holds both `prores_422`, which cannot
  carry alpha, and `prores_4444`, which can. The pair that looks wrong and
  is not: **`gif` is false while `apng` is true**, although both can show a
  transparent pixel. APNG has a real fourth channel and a pixel may be any
  fraction of opaque; a GIF nominates ONE palette index as transparent and
  has no partial value to store, so a soft edge against nothing comes out
  hard. Both readings were measured against the built app — an `apng` of a
  transparent canvas decodes `pix_fmt=rgba` with its corner at alpha 0 —
  rather than reasoned from the format names.
- `agent.rs` — embedded MCP server (streamable HTTP, tools only).
  **Generic** — knows nothing about video; the host registers the catalog
  and a callback. Copied from Rasterize; do not add domain knowledge.
- `ffi.rs` / `ffi_edit.rs` / `ffi_query.rs` / `ffi_agent.rs` — thin shims
  only; shared plumbing lives in `ffi_util.rs`, never copy-pasted.

## Rules

**Modules and size.** New feature area = new module with its own
`impl Project` block. Soft cap ~600 lines; needing a new `// ---- name --`
banner section is the signal to split. Every module keeps a `//!` doc;
numeric/algorithmic choices get prose "why" comments.

Three modules are over the cap today and are known debt, not licence:
`edit_clip.rs` (1252 — the placement ops are one concern and every further
cut fragments it; the action ops were the M3 cut, into `edit_action.rs`),
`edit.rs` (760 — a module doc that IS the op table and grows a row per op,
which is what took it over in phase 3 and what phase 6's two background
rows added to again) and `edit_track.rs` (674 — tracks, markers, canvas and
media, four small concerns in one block). Do not add to
any of them without taking something out: a new placement op goes in a new
module (`edit_edge.rs`, `edit_insert.rs`), a new op with a concern of its
own goes in one too (`edit_zoom.rs` was phase 3's and
`edit_background.rs` phase 6's), and the next cut in
`edit_track.rs` is `set_canvas` with its `rescale` / `resnap` /
`check_dimension` helpers into an `edit_canvas.rs`.

**Two modules now sit exactly AT the line and take nothing further
without a cut of their own**: `edit_paste.rs` (600) and `model_props.rs`
(600, which is the worked example below). `recipe.rs` was the third and
paid the rule in road map 2's phase 7 the way `export.rs` and
`model_props.rs` had — 331 before phase 4c put the reveal there, 567
after it, 600 once phase 6 added the layer's `blend`, and **381** once
the reveal, the hash over it and a text layer's whole `source` object
went out to `recipe_text.rs` (306), BEFORE the burn-in layer that phase
owed it. With the phase's own additions in — `RecipeOptions`, the
`RecipeLayer` skeleton and `frame_recipe_opts` — it is at **537**, and
`recipe_text.rs` is at **510** with `burn_in_layer` in it (456 at the
landing; the review's answer to "does a burn-in clear a caption?" is
fifty lines of arithmetic under `BURN_IN_Y_FRACTION`, and it says NO):
both back under the line with room, which is the whole point of paying
first. The others
phase 6 touched are still under: `actions.rs` 573
(the list rule, `clamp_video`'s region block and its nest-blend bound),
`props_check.rs` 355 (the gradient's four checks and the ordering check
it argues instead of making), `edit_props.rs` 450 (`check_blend`),
`edit_time.rs` 526 and `edit_zoom.rs` 390. Those, and the two at the
line, are the files to weigh a phase-7 addition against next.

**`export.rs` paid the rule in phase 5 and is the worked example.** It
stood at 578 against the cap, and phase 5 owed it two container variants,
two preset rows, a decibel validator, two override reads and two echo
lines — about 690. So it gave something up BEFORE it took anything on:
`describe`, the overrides object and every per-type reader went out to
`export_overrides.rs` (266), and `export.rs` came back to **579** with the
phase's additions already in it. The cut is by CONCERN, `props_check.rs`'s
own: how a value is SPELLED and what makes it a refusal is a fact about
the vocabulary, where the table and the resolution were both
`export.rs`'s until phase 7 took the table out too (next paragraph).
Nothing in the new file knows which preset asked or what the canvas is.
And the re-export is what made the cut free — five modules name
`crate::export::describe` for their own messages, so `export.rs` re-exports
it and not one of them changed.

**It paid the rule a SECOND time in phase 7**, before 7b's ProRes 4444 row
and its `alpha` capability, and the second cut is worth reading beside the
first: the same file, the same rule, a different nameable seam. The
`Container` enum and the whole preset table went out to `export_table.rs`
(422 at the cut, **518** with 7b's `prores_4444` row and the `alpha` field
in it), leaving `export.rs` at 222, and **241** once the `alpha` echo
landed beside `audio` and `video` — the resolver, and the module doc that
explains the design the table serves. Both numbers are given for the
reason the `recipe.rs` paragraph above gives both of its: a phase-8 author
weighing an export-table addition is working against 82 lines of headroom,
not 178. The seam is that everything in the
table is a constant no project can influence, where `export_settings` is
the only half handed a `&self`; the visibility it cost is the fields the
resolver reads and the four `Container` questions it asks, and `presets`
and `preset` are re-exported, so `ffi_query.rs` and `export_size.rs` were
untouched.

`model.rs` is OFF the list: it came DOWN from 1330 to 940 when the lookups
and `validate` moved to `model_query.rs` (454), and to 462 in road map 2's
phase 2 when the §5.2 property types moved to `model_props.rs`;
`edit_props.rs` (395) came back under the cap in the same phase when its
range checks moved to `props_check.rs` (305); `evaluate.rs` (588) came off
the list the same way, its recipe half moving to `recipe.rs` and the nest
walk to `nest.rs`. `model_props.rs` then paid the rule itself: 531 at the
phase-2 cut, 633 once phase 3c added `video.obscure`'s types, and 498 once
the region vocabulary went out to `model_regions.rs` (218).

**`model_props.rs` made that cut in phase 6 and is at 600 today.** It stood
at 592 and owed `video.blend` and `shape.gradient`, so it gave something up
BEFORE it took anything on — the warning phase 3 had already handed it, and
the cut both this file and the road map had named in advance. The text
vocabulary (`TextProps`, `TextAlign`, `TextVAlign`, `Outline`, `Backdrop`,
`TextAnimation`, `TextAnimationKind`) went to `model_text.rs` (252),
re-exported whole, and the seam is nameable rather than convenient: text is
the one property group the model cannot MEASURE. The shape vocabulary was
the alternative and was refused — it leaves about 27 lines of headroom, and
`Gradient` belongs beside the `ShapeProps` that holds it. So the file is
back AT the line with the phase's additions in it, and the next phase to
add a property here owes it another cut first.

**One implementation per algorithm.** Before writing time math, find the
existing implementation and route through it. Shared constants have exactly
one home (`TIMESCALE` in `time.rs`; `RC_*` caps in `format.rs`; the
inspector's bounds in `props_check.rs`).

**Purity.** Every edit takes `&self` and returns a new value — internally
clone-then-mutate. An op that would change nothing returns `None`, never an
identical copy: an identical copy registers a phantom undo step in the app.

**Errors.** Two tiers, no error enum: `Option<T>` = the op is valid but
changes nothing, or a domain refusal, with the reason in the doc comment;
`Err(String)` = invalid arguments, unknown ids, parse failures — lowercase
messages naming the offending value. No input may panic. FFI mapping:
`None` → NULL with `err_out` untouched; `Err` → `set_err(err_out, …)`;
caught panic → `"internal error: <what>"`.

**Times.** Every tick value that reaches the model is snapped to the
document's frame grid first (`time::snap_to_frame`). Never store a
sub-frame time.

**FFI exports.** Every export: `#[no_mangle] pub unsafe extern "C"`, a `///`
comment restating the header contract, a `/// # Safety` paragraph, NULL
tolerance first, narrow `unsafe {}` blocks. Route through the shared helpers
in `ffi_util.rs` — a freshly hand-rolled `catch_unwind` is a review flag.
Export names mirror the Rust method exactly.

**Format changes.** Any change to persisted project state bumps
`RC_FORMAT_VERSION` in `format.rs` **and** the `#define` in
`core/include/reelcut_core.h`; the reader must keep accepting every prior
version; the writer enforces the reader's caps. The version is 6. A bump
whose new fields all carry a serde default needs no migrate step —
version 3 (a clip's `name` and `label`, a track's `solo`), version 4
(`video.obscure`, the hidden regions of phase 3c), version 5
(`text.animation`, phase 4c's reveal) and version 6 (`video.blend` and
`shape.gradient`, phase 6's two looks) have none, and
`format.rs`'s MIGRATION HOOK comment says so — but they still bump, so an
older build refuses a file whose fields it would otherwise silently drop;
a bump that changes a field's SHAPE adds a step there (`migrate_1_to_2`).
It is the fields needing NO migration whose loss is the quietest, which is
why `format.rs`'s version-5 and version-6 paragraphs each restate the
argument in their own words rather than pointing back at version 3's:
unknown keys are ignored at every level by
design, so without the gate an older build would open the file, drop every
animation — or every blend and every gradient — on read, and write the loss
back on the next save with the text still on screen. Version 6's is quieter
still, and its paragraph says so: a dropped blend takes nothing OUT of the
picture, since the layer is still drawn, just source-over.

**And a trap the bump to 6 walked into, recorded so the next one does
not.** `{"version": 6}` was the tree's "too new, refuse" fixture in
`core/tests/schema_v3.rs` and `core/tests/model_tests.rs`; the moment
`RC_FORMAT_VERSION` reached 6 those three tests stopped testing the gate
and started testing that a CURRENT file opens — green either way. They are
at 7 now, and the comment beside each says "one past the current version"
rather than naming a number. Two more sites in that sweep are not
substitutions: `schema_v3.rs`'s gate hard-codes both numbers inside a
literal message string, and `schema_v4.rs` asserted BY LITERAL TEXT that
`obscure` closes the video object, which appending `blend` falsifies by
design — that assertion moved onto the pair rather than being deleted,
because what it pins is that a new key lands at the END.
Either way a `schema_vN.rs` test opens the previous versions' fixtures
and reads the new keys' ORDER off the written text, since a parsed
`serde_json::Value` sorts them.

**Tests.** All tests are black-box in `core/tests/` (no `#[cfg(test)]` in
`src/`), exercised **through the FFI** wherever possible, and verified
against independently written oracles — never golden files. Shared helpers
live in `tests/common/`; new feature area = new test file. Every new export
gets at least one test plus inclusion in the null-safety sweep. Finish Rust
work with `cargo fmt` and a clean `make lint`.
