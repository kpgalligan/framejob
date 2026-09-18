# core/CLAUDE.md — Rust core rules

Applies to everything under `core/`. Build commands and the FFI three-file
lockstep are in the root `CLAUDE.md`; the full design is
`designs/reelcut-design.md` (§5 the schemas, §6 the op table, §7 the
architecture, §7.10 this module map in the spec's words). The long form of
each entry below — the history of every cut, with its line counts and the
argument for where the seam fell — is `designs/reelcut-core-notes.md`; this
file is what governs a module now.

## Module map

- `lib.rs` — module declarations and re-exports only. No implementation code.
- `model.rs` — the spec §5.2 SHAPE: the project, its tracks, clips, sources,
  actions, markers and nests, with the serde defaults that say what an absent
  key means. The struct field names ARE the JSON keys. Nothing else lives here.
- `model_props.rs` — the schema's VOCABULARY: the per-clip property types
  (`VideoProps`, `AudioProps`, `Crop`, `Shadow`, `ColorAdjust`, `Chroma`,
  `Filter`, `Reflection`, `BlendMode`, `Compressor`, `Duck`) and their
  defaults, re-exported whole by `model.rs` so every `crate::model::X` path
  holds. **`BlendMode`'s and `ObscureKind`'s declaration ORDER are shader
  discriminants** (`ProjectSnapshot.swift` derives the code from the case
  index, `Compositor.metal` compares against the same integers): append,
  never reorder. `Normal` is 0 with no `+1`, so a zeroed uniform block, an
  older recipe and a file with no `blend` key all render source-over.
- `model_text.rs` · `model_shape.rs` · `model_regions.rs` · `model_motion.rs`
  — the text, shape, region and motion vocabularies, each re-exported through
  `model_props.rs`. Text and shape are the two sources the model only
  DESCRIBES and the platform draws and measures: nothing in either file is
  ever a measured size. Regions (`Spotlight`, `ObscureRegion`, `SpotShape`,
  `MAX_OBSCURE`) share one coordinate frame — the centre as an offset in
  SOURCE pixels from the centre of the layer's cropped rect — which
  `edit_zoom.rs` writes out as an equation and nothing else restates. No
  declaration order in these four is load-bearing; the JSON spelling of every
  variant is, so a rename needs a migration step. The enums are closed:
  there is no neutral kind to fall back to.
- `model_query.rs` — reading a project: `Project::new`, id allocation, the
  `clip`/`track`/`media`/`marker`/`nest` lookups, `clips_on`, `duration`,
  `validate` with its nesting walk, `source_size`, and the three
  source-window measurements every placement op clamps against —
  `source_head`, `content_length`, `source_length`.
- `time.rs` — `Ticks`, `TIMESCALE`, `Fps`, frame snapping, timecode
  format/parse (non-drop `HH:MM:SS:FF` and `HH:MM:SS.mmm`).
- `outcome.rs` — `Outcome`, the THREE arms every edit answers with
  (spec §5.5): applied with the new project, an identity, or refused with
  the rule's own sentence. An enum and its doc, nothing else. It is an enum
  rather than a side channel so that a site which has not decided which
  answer it gives does not compile; the fourth possibility, a request that
  could not be read, stays the `Err(String)` beside it. Its `Identity` doc
  is also the one place that says which refusals can say why yet.
- `edit.rs` — the op enum, `parse` and `apply`. **Its module doc IS the op
  table's SEMANTICS half** — what each op means, and what an absent
  optional argument means — where `op_table.rs` is the ARGUMENTS half;
  `app/Sources/ReelOps.swift`'s typed builders, `AgentCatalog*.swift`'s
  tools and spec §6 mirror the two together. `OP_NAMES` is re-exported from
  here, at the path it has always had. `parse` answers an `Envelope` — the
  op AND the envelope's `scope` — and `apply_op(&Op)` knows nothing about
  nests. The semantics table is the reason this file is over the size cap
  and stays exempt (below).
- `op_table.rs` — the op table as DATA (road map 7's D3): one `OpRow` per
  op and one `Argument` per argument — its name, its `Kind` and whether the
  decoder requires it — and `OP_NAMES` as a projection of it, re-exported by
  `edit.rs` so no caller moved. A published interface, where the `Op` enum
  and the dispatch are its implementation. Nothing outside this module and
  its test reads a row YET — the catalog and the startup check are the later
  D3 tickets; `OP_NAMES` is the one part of it already consumed. A row holds no prose, no semantics and no default
  spelled twice; `Kind` is closed, carries each vocabulary's members, and
  has exactly ONE kind per answer serde gives, because a distinction the
  decoder cannot see is one no test could prove. Nothing here is the
  authority — the enum's fields are, and `core/tests/op_table.rs` proves
  every row by asking the decoder. Capped at 400 lines like any new module:
  it does NOT inherit `edit.rs`'s table exemption.
- `scope.rs` — editing INSIDE a nest: the envelope's `scope` key. Builds a
  VIEW project from the nest (its tracks and clips at top level, its frozen
  size as the canvas, the parent's rate, media, `next_id` and nests, no
  markers), applies the op to it UNCHANGED, merges back. So `Project::clip`
  keeps its one meaning and no op has a nest-aware branch. Three things are
  counter-intuitive and measured: the scoped nest's own row stays in the view
  with its tracks and clips EMPTIED (removing it dangles every other nest's
  reference; leaving it whole doubles every id under `validate`); the nests
  write-back is union first, orphans after; and **a scoped apply has a wider
  `Err` arm than any unscoped op** — `check_caps` and `check_nesting` are
  document-wide and run on the MERGED parent, so an op valid inside the nest
  can still return `Err`. `refused_inside` is an EXHAUSTIVE match over every
  op, so a new op does not compile until it is classified. The READ half is
  `rc_project_scoped` in `ffi.rs`, which calls the same `scoped_view`.
- `edit_clip.rs` — clip placement: `add_clip`, move, trim, duplicate, delete,
  join, detach, `fit_scale` and `fill_scale` (Fit is a RESCUE for oversized
  footage and honours `canvas.fit_new_clips`; Fill is a REQUIREMENT, ignores
  it, scales up as readily as down and clamps to `SCALE_MAX`). Over the cap,
  known debt (below).
- `edit_split.rs` — `split_clip` and what the SECOND clip inherits: base
  props from the evaluation at the cut, unfinished actions rebased, a
  straddled one narrowed, presets and motion halves anchored to the two
  ends. Every splitter in the crate routes here, so a rule stated once is a
  rule they all obey. A free function over `&mut Project` because it is
  called mid-edit on a clone the caller is still assembling.
- `edit_props.rs` — the five patches (`set_video`, `set_audio`, `set_text`,
  `set_shape`, `set_clip`), `Project::check_group` (how a patch and a
  `paste_attributes` copy run the same range check), `check_blend`, the one
  check about a CLIP rather than a value (a nest clip cannot blend), and
  `snap_motion` / `snap_animation`, which put the ticks a patch carries on
  the frame grid AFTER the range check, so a refusal names what the caller
  sent. What a patch may CARRY is `patch.rs`'s and nothing here restates it.
- `patch.rs` — reading a caller-authored patch, cut out of `edit_props.rs`
  under the size rule: `Group` and its per-group template, `check_keys` (the
  walk of keys and JSON kinds, array indices in the path) and `merge_group`
  (the one read of a group patch — the walk, the deep merge and the
  path-tracking deserialise — the new text and shape clips' patches
  included), so every refusal names the path, indices included, and the
  value. `check_group_patch` is the same walk and read for a group that is
  NOT being merged into a stored one (an action's end state), and
  `unknown_key` is that refusal's one spelling. A patch merges key by key at
  every depth, an array replaces its list, and `null` clears an optional key
  (a required one refuses it). `COMPLETE_ENTRIES` is the one exception to
  "absent keeps": a `video.filters` entry must name both its keys, because a
  list replaces whole and the type's defaults would invent a filter.
  Nothing here is handed a clip or a project: what a patch may carry is a
  fact about the vocabulary, which is `props_check.rs`'s reason for existing
  one step further on.
- `props_check.rs` — the range checks every value written into a property
  group passes first (`check_video` / `check_audio` / `check_text` /
  `check_shape`, the `finite` / `in_range` family, the bounds `actions.rs`'s
  `clamp_video` reads too). A range check is a fact about the vocabulary, not
  about an edit — and it runs BEFORE `edit_props.rs` snaps a patch's ticks,
  which is what lets a refusal name the number the caller sent rather than
  the one a snap rounded it to. Gradient stops are deliberately NOT order-checked: a refusal
  would break dragging one stop past another mid-gesture, so the renderer
  sorts, and the comment says so where the check would have gone.
- `edit_track.rs` — tracks, markers and the media list: the three lists a
  clip sits in. The canvas left here at road map 7's D2·3 toll. `clip_list`
  is the ONE spelling of the clips a `with_clips` refusal names — three ids
  and then a count, so a media used by two hundred clips still answers a
  sentence a caller can read — shared by `remove_track` and `remove_media`.
- `edit_canvas.rs` — the document's own shape: `set_canvas` and the three
  things it does to the rest of the document — `check_dimension` (a
  dimension is even, because H.264 encodes in macroblocks), `rescale` (a
  size change moves every clip's `x`, `y` and `scale`, each axis by its own
  ratio and `scale` by the smaller of the two) and `resnap` (a rate change
  moves every stored time to the new grid, and drops the second of two
  markers a coarser grid lands on one tick).
- `edit_time.rs` — ripple, insert time, `ripple_delete_ranges` (the pairs are
  ordered, MERGED — touching as well as overlapping — then cut and closed
  right to left as ONE edit; the singular delegates to it), `lift_range`
  (the hole left open), `close_gap` (refuses rather than closing part way),
  freeze frame, `shift_clips`, and `locked_track` — THE locked-track
  refusal's sentence, written once here for its three callers
  (`close_gap`, `edit_insert.rs`'s `insert_clip`, `edit_transition.rs`'s
  rippled form), each passing the clause after the comma.
- `edit_edge.rs` · `edit_insert.rs` — the cutting moves that keep something
  fixed on purpose: `slip` and `roll` (a `still` slips the frame it holds;
  any other non-media source is an `Err`; roll's predecessor must end
  EXACTLY at the clip's start); `insert_clip` and `overwrite_clip`,
  compositions of split + insert time + add made ONE op so a drop is one
  undo step and carries the rule neither half states — an insert cuts only
  the destination track and then shifts every unlocked one.
- `edit_transition.rs` — the WRITE half of a transition: `set_transition`,
  `set_transition_duration`, `set_gained_transitions` (a clip that gains an
  overlap gains a transition), `add_transition` (an overlap built from the
  two clips' handles at a hard cut, or with `ripple` by sliding the incoming
  clip and everything after it left through `shift_clips`) and
  `set_transition_style` (curve and audio crossfade). `transition.rs` is the
  READ half and nothing here restates it.
- `edit_action.rs` · `edit_nest.rs` · `edit_paste.rs` — the action ops and
  their no-overlap rule, plus `check_end_patch`, the END patch's door: the
  three groups §5.4 allows (a `shape` is an unknown key), a `null` that
  REMOVES at every depth rather than clearing, and `patch.rs`'s walk and
  read per group. The door is composed here because which groups an end
  patch names, and what a `null` in one means, are facts about an ACTION;
  values are deliberately not range-checked, and `actions.rs`'s
  `clamp_video` is the last line of defence for them. `nest` and `unnest`
  (fresh ids, content byte-equal);
  `paste`, whose payload schema is its module doc, and `paste_attributes`,
  which copies the EARLIEST clip's property groups (then the front-most, then
  the lower id — never the array's first) onto each target, replaced whole
  and never merged.
- `edit_zoom.rs` — `add_zoom_action`, the screencast zoom, and `ZoomRegion`,
  the one op ARGUMENT that is a caller-authored object: its `Deserialize` is
  written out rather than derived so it answers as a patch does — an object
  required (a list is not read member by member), an unknown or missing
  member named, a wrong-typed one named by its path. **Its module doc
  IS the placement equation** between the region frame and canvas pixels,
  rotation and crop included; it composes `add_action` + `set_action` +
  `set_action_end` so a drag is one undo step and every refusal is inherited.
- `edit_background.rs` — `add_background` and `add_blurred_background`: one
  clip on a NEW back-most track, OPS rather than app-side composites because
  the composite carries constraints no half states. A blurred copy drops
  `enabled.audio`, `audio.duck`, the transition, the actions and the label
  (each a wrong picture or a wrong sound if carried) and refuses a nest.
  Default plate colour is white: the canvas is already black.
- `actions.rs` — action evaluation and interpolation, `clip_state`, and
  `clamp_video`, the evaluator's last line of defence (`set_action_end`
  checks an end patch's keys and kinds but deliberately not its VALUES, and
  never sees the clip; this bounds every value an end patch can carry and
  forces `normal` on a nest clip). **The LIST rule is stated here once as the
  crate's**: an end patch interpolates a list per index when the lengths
  match and each pair of entries agrees on its discrete fields (`kind`,
  `shape`), and switches at the end otherwise; `video.filters` and
  `video.obscure` are both governed by it and carry no code of their own.
- `transition.rs` — overlap detection, THE overlap rule (spec §11), eased
  progress at *t*. An overlap with no kind still dissolves
  (`unwrap_or_default`), and `add_clip` onto an overlap mints a
  `cross_dissolve`, so a no-transition baseline is built by moving clips
  apart, not by clearing the kind.
- `evaluate.rs` — `composition_plan()` (A/B assignment, instruction tiling)
  and the `assign()` the recipe shares with it.
- `recipe.rs` · `recipe_text.rs` — `frame_recipe(t)`: the layer list at one
  instant. `RecipeLayer` is the twenty keys of a layer written in ONE place
  (`RecipeLayer.init(from:)` on the Swift side defaults a missing key
  silently, so a copied skeleton drifts with no diagnostic). `RecipeOptions`
  is what a caller wanted besides `t` — the burn-in timecode — and is a
  recipe option, never an export override, because the override table drops
  an unknown key in silence. A layer whose `transition` is non-null is
  emitted `blend: "normal"` whatever the clip says: the core's ONE deliberate
  override of a model value, because the dissolve's weight correction is the
  inverse of a fixed-function destination factor. The inspector therefore
  shows the model's value while the frame draws `normal` during an overlap.
  `recipe_text.rs` computes what a text layer SHOWS — `Reveal::of` turns
  `text.animation` into `reveal`, `reveal_phase` (the ORDER the renderer draws
  in, not a label on the amount) and `reveal_kind`, folded into the content
  hash so an animating layer is never served a stale texture — and
  `burn_in_layer`. `serde_json`'s `Map` is a `BTreeMap` here: keys come out
  sorted, which `content_hash` leans on.
- `motion.rs` — `video.motion` turned into PLACEMENT: presets to `scale`,
  `rotation`, `opacity`, `x`, `y` from the clip time, its duration, the
  source size and the container's canvas. **Its only callers are
  `recipe.rs`'s `layer` and `frame_of`**: every edit path — `evaluate_clip`,
  `clip_state`, `get_project`, splitting, zooming, freezing, the audio plan
  — reads the clip un-moved. It never trusts the file (a non-positive
  duration or period is inactive, amounts clamp) and short-circuits to
  `video.clone()` when no slot runs, because `x + b − b` is not `x` in
  floats.
- `nest.rs` — flattening a nest into the clips it stands for and the
  transform they inherit; `evaluate.rs`, `recipe.rs` and `audio.rs` all
  consume its instances rather than `Project::clips`.
- `audio.rs` · `audio_duck.rs` · `audio_crossfade.rs` — envelopes: fades,
  volume actions, mute and solo (both ZERO envelopes; solo is judged per
  container in `Voice::of` — muted, or some track in the set soloed and this
  one not; mute wins — so the plan's segments never see it); ducking, the
  one term imposed by a clip on ANOTHER track; and the constant-power
  crossfade with the breakpoints it must be sampled at to survive coalescing.
- `snap.rs` — candidates and `resolve`.
- `format.rs` — `RC_FORMAT_VERSION`, the `MAX_*` caps (four of them
  `RC_MAX_*` in the header), read-any-version / write-current, the migration
  hook.
- `export.rs` · `export_overrides.rs` · `export_size.rs` · `export_table.rs`
  — settings resolution (`Project::export_settings`, the one thing that reads
  a canvas, a duration, a rate and an override against a preset row); how an
  override is READ and REFUSED, naming the key and the value (`peak_dbtp`
  without `loudness_lufs` is an `Err`, because a ceiling with nothing to cap
  would be a key accepted and silently inert); the sizes the sheet offers and
  `fit_within`; and the rows themselves. In a row, `avf_preset: null` routes
  an export to the ImageIO writer (so the two LPCM rows repeat `audio_m4a`'s
  name), and `alpha` means "this ENCODING carries an alpha channel" — true for
  `prores_4444` and `apng`, false for `gif`, which has one palette index and
  no partial value — never "the canvas is translucent".
- `agent.rs` — embedded MCP server (streamable HTTP, tools only).
  **Generic** — knows nothing about video; the host registers the catalog
  and a callback. Copied from Rasterize; do not add domain knowledge.
- `ffi.rs` / `ffi_edit.rs` / `ffi_query.rs` / `ffi_agent.rs` — thin shims
  only; shared plumbing lives in `ffi_util.rs`, never copy-pasted.
  `ffi_query.rs`'s rule: a query never allocates a handle and has no
  `err_out`, which is why `rc_project_scoped` lives in `ffi.rs`.

## Rules

**Modules and size.** New feature area = new module with its own
`impl Project` block. Soft cap ~600 lines; needing a new `// ---- name --`
banner section is the signal to split. Every module keeps a `//!` doc;
numeric and algorithmic choices get prose "why" comments. **A file at the cap
gives something up BEFORE it takes anything on**: the cut is a PURE MOVE,
landed and gated alone, so the feature's diff is attributable; budget the cut
against the pessimistic number, because an estimate here has run about two
thirds of the truth. Over the cap today and known debt, not licence:
`edit_clip.rs` and `edit.rs`, whose
standing exemption is that its module doc IS the op table's semantics half
(the cut there, if ever forced, is the `Op` enum into an `edit_ops.rs`, and
never in the same phase as a feature). The current list is `wc -l` and
`designs/reelcut-remaining.md` §3.

**Dependencies.** `serde` and `serde_json` (the JSON the FFI speaks),
`tiny_http` (the agent's socket), and `serde_path_to_error`, which is there
so a patch refusal names the path to what only the type can refuse (a
misspelt variant, a `null` a required field cannot take), where serde alone
names only the value.

**One implementation per algorithm.** Before writing time math, find the
existing implementation and route through it. Shared constants have exactly
one home (`TIMESCALE` in `time.rs`; `RC_*` caps in `format.rs`; the
inspector's bounds in `props_check.rs`).

**Purity.** Every edit takes `&self` and returns a new value — internally
clone-then-mutate. An op that would change nothing returns
`Outcome::Identity`, never an identical copy: an identical copy registers a
phantom undo step in the app.

**Errors.** Every edit answers `Result<Outcome, String>` — three arms and
one tier, no error enum. `Outcome::Applied` = the new project;
`Outcome::Identity` = the op is valid and nothing needed to change;
`Outcome::Refused(String)` = a rule declined it, carrying the rule's OWN
sentence rather than a second one written at the call site; `Err(String)` =
invalid arguments, unknown ids, parse failures — lowercase messages naming
the offending value. A refusal is not an error tier: both middle arms leave
the project untouched and register no undo step. No input may panic. FFI
mapping (`ffi_edit.rs`): `Applied` → a new handle; `Identity` → NULL with
neither channel written; `Refused` → NULL with the sentence through
`reason_out`; `Err` → NULL with the message through `err_out`; caught panic
→ `"internal error: <what>"`. The two channels are never both written.

**Times.** Every tick value that reaches the model is snapped to the
document's frame grid before it is stored (`time::snap_to_frame`). Never
store a sub-frame time. Where a range check names the value, the check runs
on what the CALLER sent and the snap follows it, so a refusal never names a
number the door rounded to (`props_check.rs`, `edit_props.rs`'s
`snap_motion` / `snap_animation`). The one family that is deliberately NOT
on the grid is the audio ramps — `audio.fade_in` / `fade_out`, the duck's
and the compressor's attack and release — because they are envelope lengths
sampled at the audio rate, not positions in the picture, and quantising
them to a video frame would round a 10 ms attack to nothing.

**FFI exports.** Every export: `#[no_mangle] pub unsafe extern "C"`, a `///`
comment restating the header contract, a `/// # Safety` paragraph, NULL
tolerance first, narrow `unsafe {}` blocks. Route through the shared helpers
in `ffi_util.rs` — a freshly hand-rolled `catch_unwind` is a review flag.
Export names mirror the Rust method exactly.

**Format changes.** Any change to persisted project state bumps
`RC_FORMAT_VERSION` in `format.rs` **and** the `#define` in
`core/include/reelcut_core.h`; the reader must keep accepting every prior
version; the writer enforces the reader's caps. A bump whose new fields all
carry a serde default needs no migrate step (versions 3 through 8 have none)
but still bumps, because unknown keys are ignored at every level by design
and an older build would otherwise open the file, drop the new fields on read
and write the loss back on the next save; a bump that changes a field's
SHAPE adds a step at the migration hook (`migrate_1_to_2`). Each bump gets a
`schema_vN.rs` test that opens the previous versions' fixtures and reads the
new keys' ORDER off the written text, since a parsed `Value` sorts them.
**Trap:** the "one past the current version, refuse" fixtures in
`core/tests/schema_v3.rs`, `core/tests/model_tests.rs` and
`tools/proof/phase9_proof.py` must be walked forward with every bump, or they
stop testing the gate and pass either way; each says "one past the current
version" in its comment rather than a number, and `schema_v4.rs`'s claim
about which key closes the video object travels to the newest key.

**Tests.** All tests are black-box in `core/tests/` (no `#[cfg(test)]` in
`src/`), exercised **through the FFI** wherever possible, and verified
against independently written oracles — never golden files. Shared helpers
live in `tests/common/` (`content` / `contents` — "the same clips, ids
aside" — is the one spelling of that comparison, used by `nest`'s identity
claim and `scope`'s oracle alike); new feature area = new test file. Every
new export gets at least one test plus inclusion in the null-safety sweep.
Finish Rust work with `cargo fmt` and a clean `make lint`.
