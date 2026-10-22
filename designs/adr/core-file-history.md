# Core file history — why the Rust core's seams fall where they do

- **Status:** Closed (2026-09-26) — a history file, not a road map. Nothing in it is
  in flight; its last entry is road map 10's G1d (2026-09-25).
- **Original:** `archive/core-notes.md` (1,108 lines) — the full record; sections
  cited below as "orig §x" refer to it (section map at the end).
- **Spec decisions:** relies on, does not introduce: #22 (a media clip's window stays
  inside its file, snapped DOWN); D4-1 (content length is one function, the plan obeys
  it); D4-2..D4-5 (every writer of a media window reads one bound; `trim_end` on an
  `Unmeasured` window stays unbounded; `set_speed` snaps nearest then is held; one
  re-snap function; head bounds snap UP); R5-3's amendment (the `ripple` form of
  `add_transition`); R5-4 (motion is a presentation term); W-2, W-3, W-5, W-6 (word
  captions); G-2, G-9 (graphics).

## Context

`core/CLAUDE.md` once carried, per module, the argument for where each seam fell and a
size ledger of which file paid which toll at what line count. On 2026-09-17 it was cut
back to a module map plus rules, and the long form moved verbatim into the original,
which then collected dated entries through 2026-09-25.

**`core/CLAUDE.md` is the live rulebook.** It already states the module map, the size
rule (a file at the cap gives something up first, as a pure move), purity, the three-arm
`Outcome`, times, FFI exports, format versioning and tests. None of that is repeated
here. The original's own Purity and Errors paragraphs (`None`, two tiers) are
**superseded** by D2's three arms (`core/src/outcome.rs`, spec §5.5). Do not read them as
current. What follows is only the "why" that the rulebook compresses or leaves out.
Line counts are omitted: they go stale, and `wc -l` is the ledger. The seams a record
named for the next cut are under "Named next cuts".

## Decisions, by module

### The model vocabulary (`model_props.rs` and the files cut from it)

- **Every vocabulary split re-exports whole, so no `crate::model::X` path ever moved.**
  `model.rs` re-exports `model_props.rs`, which re-exports `model_regions`, `model_text`,
  `model_words`, `model_shape`, `model_graphic` and `model_motion`. A split under the
  size rule therefore costs callers nothing. The FIELD that holds each group stays with
  its owner (`Clip.shape`, `Clip.graphic` in `model.rs`; `VideoProps.spotlight` and
  `.obscure` in `model_props.rs`). (orig §Module map)
- **`model_regions.rs` was cut on a shared coordinate frame, not on adjacency.**
  `Spotlight` and `ObscureRegion` share one frame, Q: the centre is an offset in SOURCE
  pixels from the centre of the CROPPED rect. That frame is what lets a region ride
  through scale, move and rotation. They also share one `SpotShape`.
  `edit_zoom.rs` writes Q out as an equation, and nothing else restates it.
- **`model_text.rs` was cut on "the one group the model cannot MEASURE".** Only the
  platform lays a string out, so the measurement flows back through a renderer cache.
  Nothing in the file is ever a measured size. That is a standing rule, not an
  omission.
- **Shape was the refused alternative at the text cut (phase 6), then taken at E2.**
  Phase 6 refused to cut shape because it left only about 27 lines, and `Gradient`
  belongs beside `ShapeProps`. E2 took the cut when `model_props.rs` sat at the cap
  owing `video.motion`. The seam is the same one read twice: text and shape are the two
  sources the model only DESCRIBES, drawn on the CPU and keyed by the recipe's content
  hash. Everything left in `model_props.rs` goes straight into the compositor's uniform
  block.
- **Shader-discriminant enums may only be appended to.** `BlendMode` is in
  `model_props.rs`. `Normal` is 0 with no `+1`, so a zeroed uniform, an older recipe and
  a file with no `blend` key all draw source-over. `ObscureKind` is in
  `model_regions.rs`, and its codes are case index `+1`, with 0 meaning an empty slot.
  The Swift `FilterKind.shaderCode` follows the same `+1` rule. `TextAnimationKind`,
  `GradientKind` and both motion enums are NOT discriminants: the recipe carries them
  by NAME, so only their JSON spelling is load-bearing.
- **`model_motion.rs` is its own module for a SEAM, not for room.** Motion says what a
  clip should DO, and `motion.rs` computes the placement at render time. `recipe.rs`
  publishes no `motion` key. `spin` is spelled in both `EdgeMotion` and
  `DuringMotion`. That is why `model_tests.rs`'s enum sweep reads the during kinds off
  the fixture rather than off the source text.
- **`source_size` kept the STRICTER of two readers when they merged (T0f).** Every arm
  must be positive, and the shape arm is read in floats so a `NaN` fails. Pinned in
  `core/tests/background.rs`: a crop on a hand-written 0-width shape clip is now
  accepted, because its size reads `None`.

### The source window (`source_window.rs`, #22, road map 7 §10 phases A–B)

- **Media durations snap DOWN, never to the nearest frame (#22).** A nearest snap
  rounds up past the file's end. `segment_of` then clamped the range, so the plan's
  rate came out just under 1 and AVFoundation resampled material nobody retimed. It
  was found as a 17-sample (later 8-sample) drift between two exports.
- **The "shorter than a frame" sentence quotes `snapped_up(1)`, not `frame()`.** At a
  rate the timescale does not divide (24981/1000, the recorder's), `frame()` falls back
  to 1/30 s. The sentence would then name a threshold the media did not fall short of.
  `core/tests/media_window.rs` pins the 24,018-tick figure.
- **`paste` has two load-bearing orderings (phase B).** The nonsense-speed fallback runs
  BEFORE the duration line, because the bound is measured at that speed. The bound is
  measured against `next`, the project the payload's media was absorbed into, not
  `self`.
- **`add_background`'s timed plate is held to its file.** Phase B measured the old claim
  that the plate "does not clamp and shows nothing" and found it false: 12,000,000
  ticks at rate 0.5 became 6,000,000 at rate 1.

### Edits (`edit_*.rs`)

- **`edit_clip.rs` is over the cap as one concern, and every cut out of it is a
  different concern.** Actions went at M3, transitions at E1, `split_clip` at E2, and
  commit and timing later. `edit_split.rs` was cut because a split decides what the
  SECOND clip INHERITS rather than where a clip sits. It stays a free function over
  `&mut Project` because callers use it mid-edit on a clone.
- **`edit_transition_shift.rs` is a pure move (the E1 review's toll).** The handle form
  spends unused SOURCE and moves nothing. The shift form spends TIMELINE and moves
  `close_gap`'s set. The shift form's off-grid result at an inexact rate was judged the
  ripple family's posture, not E1's defect (see Known limits).
- **`normalise_and_check_group` lives in `edit_props.rs` because `edit_paste.rs` was
  full.** A copied `{"motion": {}}` or three nulls must become §5a's one spelling of "no
  motion". This is the shape the size rule asks for when a fix lands beside a file at
  the cap.
- **`edit_paste_attributes.rs` is a pure move out of `edit_paste.rs` (issue batch B85
  phase 2, 2026-10-05), made ahead of spec §11 G-32 under the size rule.** What moved:
  `paste_attributes`, its two helpers `has_group` and `copy_group`, and the module doc's
  "Paste Attributes" section; `Payload`, its three fields and `parse_payload` stayed and
  became `pub(crate)`, because the payload's shape is still `edit_paste.rs`'s to know.
  `wc -l` printed 593 for `edit_paste.rs` before the cut, and 467 and 143 for the two
  files at the move's own gate (`cargo fmt --check`, `cargo test --release`, `make lint`
  with nothing else in `core/` changed). The seam is the clipboard's two uses: `paste`
  makes another document's clips fit and places them, and `paste_attributes` copies
  properties onto clips already there and places nothing. G-32's `graphic` group, its
  `PasteGroup` and `skip_missing` then landed in the new file alone.
- **Background and blurred background are OPS, not app composites.** The clipboard
  payload has no `nests` key. Repairing with `add_clip` would lose the source window,
  so the backdrop would drift out of sync. The op also needs `fill_scale`, `SCALE_MAX`
  and the source size, which the app lacks. Rule: a composite becomes an op when
  composing it carries a constraint that neither half states.
- **A blurred copy drops its audio switch and `audio.duck` first.** Both are invisible
  in a still frame, so a frame proof passes with them wrong. A kept duck would duck the
  whole mix, including the original clip. The copy also refuses a nest, because
  flattening drops a nest clip's own filters and the copy would come out sharp. The
  media plate uses Fill, not Fit.
- **Word timings (`model_words.rs`, W1b).** `snap_animation` was *widened*, not joined:
  its four existing callers (`set_text`, `add_text_clip`, `paste_attributes`, and
  `frame_grid.rs`'s resnap) now cover words with no new call site. The snap is nearest
  and never clamped. On split, a second half whose evaluated content has a different
  token count stores `words: []`, because otherwise every later `set_text` on it would
  be refused.

### Evaluation, recipe, motion, audio

- **The LIST interpolation rule is the crate's, in `actions.rs`, and its widened
  discriminants (`kind`, `shape`) apply to list ENTRIES only.** A list entry's only
  identity is its index. `video.spotlight` is one named object, and widening the rule
  to it would have frozen every spotlight's shape animation. `schema_v2.rs` pins this.
- **`RecipeOptions`: an absent, mistyped or non-object option means OFF.** The query FFI
  has no `err_out`, and NULL at frame rate would be a black preview. The MCP handler is
  the layer that refuses a mistyped option by name. It is deliberately not an export
  override, because that table ignores unknown keys silently.
- **`recipe_text.rs` was cut because text is the one layer not finished by its
  placement.** An animated intent needs a computed number in the texture-cache KEY.
  `text_source` takes only a description, a clip time and a duration, so a
  core-synthesised layer (`burn_in_layer`) is an ordinary text layer.
- **The reveal PHASE is draw order, not a label.** It turns only on a plateau
  (`in + out <= duration`, ties go to the arrival). A tent keeps the phase it began
  in, because turning below 1 visibly mirrors the stagger.
- **Burn-in placement:** `BURN_IN_Y_FRACTION` (0.44) of the canvas height, with
  `valign: middle`, not "bottom". The core has no measured text size to subtract. The
  timecode is NON-DROP and reads PROJECT time.
- **`recipe_words.rs` is separate from `recipe_text.rs`** because it is a second,
  independent account of a text layer over time, and W-5 says the two do not compose.
  It is total (a count and clamps) because `paste` and the file reader store `words`
  unchecked.
- **`motion.rs`'s rotation reduction uses a BAND, not an equality.**
  `f64::rem_euclid(360)` rounds a tiny negative up to exactly 360.0, or to
  359.99999999999994 one tick earlier. Both fail `partnerBox`'s exact `rotation == 0`
  guard. Every total that rounds to 360 as an f32 of degrees maps to 0. The band is
  2⁻¹⁶°, at most 5.87e-4 px at a 4K corner. The first justification written for it was
  false: no consumer reads degrees as f32. The width is *chosen*, and
  `core/tests/motion_edges.rs` pins it. The no-motion short-circuit returns
  `video.clone()`, because `x + b − b ≠ x` in floats.
- **`audio_duck.rs` and `audio_crossfade.rs` are one seam read twice.** Each is an
  envelope term that the voice's own properties do not decide. The crossfade's gain and
  breakpoints share one module because a gain without breakpoints coalesces into one
  linear ramp, and the constant-power curve degenerates to the equal-gain one it exists
  to avoid.

### Export

- **`export.rs` was cut twice, by concern, re-exporting so no caller moved.**
  `export_overrides.rs` holds how a value is SPELLED and REFUSED. `export_table.rs` holds
  constants no project can influence. `export.rs` keeps the half that takes a `&self`,
  and re-exports `describe`, `preset` and `presets`.

## What it built — where it lives now

Every module named above exists under `core/src/` today (checked with `ls`); the
`edit_track.rs` cut the original planned is `edit_canvas.rs`, and `trim_start` /
`trim_end` / `set_speed` / `rate_stretch` have since moved from `edit_clip.rs` to
`edit_clip_timing.rs`. `set_gained_transitions` is no longer re-exported through
`edit_clip.rs`; `edit_commit.rs` imports it from `edit_transition.rs`. The pinning
tests are in `core/tests/`: `media_window.rs`, `source_window.rs`, `motion_edges.rs`,
`background.rs`, `schema_v2.rs`.

## Known limits (verified against the tree 2026-09-26)

- **`segment_of` keeps its own clamps (roadmap 7 §10.8, decided).** It uses
  `duration − 1` (the tick AVFoundation can be handed) and a MEDIA-frame still margin.
  This is the last line of defence for hand-written JSON, pre-#22 documents and the
  one-frame floor. Do not swap in `last_in_point`, which would re-frame old files.
- **At a canvas rate the timescale does not divide (e.g. 7 fps), `frame()` falls back to
  1/30 s.** `add_transition_by_shift` counts whole frames of the real grid
  (`time::frames_in` / `frames_back` / `frames_within`) and lands the incoming clip on it;
  every shift (`close_gap`, the ripples) moves its clips by ONE delta, so a moved start can
  sit a tick off the grid while abutments stay exact — decided in spec §11 #42.
- **A text-animation tent whose `in` is tiny but nonzero reports phase `"in"` for its
  whole life.** Documented rather than fixed (`recipe_text.rs` `Reveal::of`).
- **The burn-in covers the bottom of a two-line caption at every canvas size.**
  `BURN_IN_Y_FRACTION`'s doc carries the arithmetic. At 29.97 fps the non-drop timecode
  reads about 3.6 s behind wall clock at the hour. A range export's burn-in starts at
  the range's project time.
- **`paste` stores its payload whole.** A pasted text clip with a `words`/token-count
  mismatch is refused at its next `set_text` until `words: []` is sent (road map 8
  §10.5).

## Named next cuts

The size rule is in the root `CLAUDE.md` and `core/CLAUDE.md`; which modules are over it is
`wc -l`, never a table here. What follows is only the seam a record named.

- `edit.rs`: exempt, its module doc being the op table's semantics half. If a cut is ever forced,
  the `Op` enum goes to `edit_ops.rs`, never in a feature phase.
- `edit_clip.rs`: grading L3 (on the `grading` branch) moved `detach_audio` and `set_enabled`,
  with the `// ---- enablement` banner, to `edit_detach.rs`, a pure move; nothing widened. `wc -l
  core/src/edit_clip.rs`: 757 before, 661 after; `edit_detach.rs` is 108. Still over the cap,
  known debt. The next seam: `fit_scale` and `fill_scale` (the Fit and Fill rules, read by
  `add_clip`, `add_shape_clip`, `edit_graphic.rs` and `edit_background.rs`) out whole.
- `evaluate.rs`: none named (the composition plan left for `plan.rs` in grading GR1).
- `recipe.rs`: grading-2's G2-0 moved the block from `// ---- what a caller asked for` through
  `impl RecipeOptions` (`RecipeOptions` and its reader `of`) to the new `recipe_options.rs`,
  re-exported by `recipe.rs` (`pub use crate::recipe_options::RecipeOptions`), so
  `ffi_query.rs` and `recipe_text.rs`'s doc link still name `crate::recipe::RecipeOptions`; a pure
  move gated with G2-0's other three, its body identical after `cargo fmt`. Nothing widened. `wc
  -l core/src/recipe.rs`: 548 before, 484 after; `recipe_options.rs` is 76. The next seam: the
  content hash (`FNV_OFFSET`, `FNV_PRIME`, `fnv1a`, `content_hash`, `sorted`) out to
  `recipe_hash.rs`.
- `actions.rs`: 532 at grading-2's G2-2, near the cap, so G2-3's curve helpers went to a new
  module rather than into it: `actions_curves.rs` (85) holds `curves_json` (all four channels,
  an absent one as the identity, inserted by `video_json`) and `align_identity_curves` (called
  by `evaluate_clip` before the lerp), and `actions.rs` took two lines of wiring and the import
  (532 → 538). G2-3's other core file is `core/tests/curves.rs`; `model_grade.rs` (179) and
  `grade_check.rs` (71) took the curve types and `check_curves` beside the wheels'. The next
  seam, should `actions.rs` need one: the per-group JSON writers (`color_json`, `wheels_json`,
  `video_json`) out to `actions_json.rs`, beside `curves_json`.
  G2-4 followed the same rule: the qualifier's action rule went to a new module,
  `actions_qualifier.rs` (51: `align_hue_center`, the hue centre the short way round), and
  `actions.rs` took one call, its comment and the import (538 → 541). `clamp_qualifier` went
  beside `clamp_curves` in `actions_clamp.rs` (243 → 287), `check_qualifier` beside
  `check_curves` in `grade_check.rs` (71 → 108), the types in `model_grade.rs` (179 → 271), and
  `check_qualifier_clip` in `edit_adjustment.rs` (185 → 212).
- `recipe.rs`: grading-2's G2-4 put the qualifier's two options (`selection`, `behind`) in a new
  module, `recipe_selection.rs` (83: `LayerFacts`, `select_layers`), and `recipe.rs` took the
  facts' collection, the one call, the black background and the adjustment source's `qualifier`
  (486 → 513). The named seam (the content hash out to `recipe_hash.rs`) is unchanged.
- `ffi_graphic.rs`: at the new-module cap (399 of 400) before #127 G6 phase 5's
  `rc_graphic_image_cache` (spec §11 G-39), it paid toll T1 first, a pure move gated alone: the
  builder's crate-free half — `FROZEN`, `Pending`, `lock`, `rc_graphic_library_new` and
  `rc_graphic_library_add_asset` — went whole to the new `ffi_graphic_pending.rs`, which names no
  `graphic` item, so `only_ffi_graphic_names_the_graphic_crate` (G-2) passes unchanged. T1's
  widenings: `RcGraphicLibrary`'s two fields (`pending`, `built`), `FROZEN`, `Pending` and its
  fields `fonts` and `assets`, and `lock` became `pub(crate)`, because `frozen` and
  `rc_graphic_library_add_font` stay behind and reach them; nothing else changed visibility.
  `ffi_graphic.rs` imports `lock`, `Pending` and `FROZEN` back and `pub use`s the two exports, so
  every test's `framejob_core::ffi_graphic::` path is unchanged. `wc -l core/src/ffi_graphic.rs`:
  399 before, 333 after; `ffi_graphic_pending.rs` is 83. The next seam: `rc_graphic_library_free`
  and `rc_graphic_free`, which name only the two handles and `free_boxed`, out to
  `ffi_graphic_pending.rs`; `diag_json` and `diag_error` stay, since they name `Diagnostic` (road
  map 10 §10.7).
- `core/tests/add_transition_edges.rs`: at the new-file cap; gives something up before it takes
  anything on.

## Open items

- `evaluate.rs` was at 590 of ~600 (since B52b moved `lifted` to `nest.rs`). The grading road
  map's GR1 paid the toll, a pure move gated before any grading code landed, because GR4's
  `Source::Adjustment` must edit both of its exhaustive `Source` matches (`segment_of`, `draws`):
  the composition plan (`MAX_CONCURRENT_VIDEO_TRACKS`, `Instruction`, `composition_plan`,
  `instructions`, `warnings_for`) went whole to `plan.rs`; `Segment`, its `to_json`, `CompTrack`
  and its three fields, and `Assignment`'s `video` and `audio` became `pub(crate)`. 590 → 381
  lines; `plan.rs` is 221.
- `recipe.rs` paid its toll in the mattes road map's MT1 (issue batch B89), a pure move gated
  alone before the matte keys landed: `RecipeLayer` and its `object()` went whole to
  `recipe_layer.rs`, which `recipe.rs` re-exports, taking it from 596 to 511 lines.
  Issue batch B90 phase 4 (#252, spec §11 MT-8) moved `recipe.rs`'s `transition_of` out:
  its level walk lives on in the new `recipe_dissolve.rs` (`frame_transitions`, asked once
  per frame over the covering instances, as `recipe_matte.rs`'s `frame_mattes` is), which
  answers each layer's `transition` and the new `dissolve`; `layer` takes them with its matte
  roles as one `LayerRoles`, and `placement` and `frame_of` are `pub(crate)` for the routed
  half's anchor (the clip's own `motion::apply` call moved into `moved`, which `layer` and
  `placement` both read, so it stays one of two call sites). `recipe.rs` went from 543 to 521
  lines.

## Where to look in the original

- **orig §Module map** (lines 22–541): the long-form entry per module. Seam arguments
  for the `model_*` splits, `scope.rs`'s three measured counter-intuitions,
  `edit_background.rs`'s op-versus-composite argument, `recipe.rs`'s blend override and
  key-order note (now superseded by `preserve_order`), `recipe_text.rs`'s phase and
  burn-in, `export_table.rs`'s `alpha`.
- **orig §Rules** (543–762): the size ledger per phase, with line counts; the
  `export.rs` and `audio.rs` worked examples of paying the toll; the Purity and Errors
  text (superseded); format bumps v3–v8 and why each needs no migration; the "one past
  current" fixture trap, now computed.
- **orig §2026-09-19 #22** (764–826): `whole_media_length`, `resnap`, `trim_end` snapped
  down; the two error sentences; the six test vectors.
- **orig §source_window phase A** (828–907): what moved from where, `SourceBound`, four
  mutants.
- **orig §phase B** (909–965): the five bound functions, the measured answers that moved,
  `paste`'s orderings.
- **orig §edit_transition_shift** (967–983), **§motion/edit_props E2 review** (985–1027):
  the rotation band's derivation.
- **orig §word captions W1b** (1029–1077), **§ffi_graphic / preserve_order G1d**
  (1079–1108).
