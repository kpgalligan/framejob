# Core file history — why the Rust core's seams fall where they do

- **Status:** Closed (2026-09-26) — a history file, not a road map. Nothing in it is
  in flight; its last entry is road map 10's G1d (2026-09-25).
- **Original:** `archive/reelcut-core-notes.md` (1,108 lines) — the full record; sections
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
Line counts are omitted: they go stale, and `wc -l` plus `designs/reelcut-remaining.md`
§3 is the ledger.

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
  1/30 s.** `add_transition_by_shift` shifts by `frames * frame`
  (`edit_transition_shift.rs:95`), and `close_gap` shifts by one delta. Either can leave
  clips off the real grid. Judged the ripple family's posture (road map 5 §12, R1·1),
  not fixed.
- **A text-animation tent whose `in` is tiny but nonzero reports phase `"in"` for its
  whole life.** Documented rather than fixed (`recipe_text.rs` `Reveal::of`).
- **The burn-in covers the bottom of a two-line caption at every canvas size.**
  `BURN_IN_Y_FRACTION`'s doc carries the arithmetic. At 29.97 fps the non-drop timecode
  reads about 3.6 s behind wall clock at the hour. A range export's burn-in starts at
  the range's project time.
- **`paste` stores its payload whole.** A pasted text clip with a `words`/token-count
  mismatch is refused at its next `set_text` until `words: []` is sent (road map 8
  §10.5).

## Open items

- `actions.rs` is at 592 of ~600 (and `recipe.rs` 596, `evaluate.rs` 593). The original's plan is that the next addition first cuts
  `clamp_video` and its helpers to an `actions_clamp.rs` — tracked in
  `designs/reelcut-remaining.md` §3 ("At the edge").
- The off-grid shift at an inexact canvas rate (`add_transition_by_shift`, `close_gap`)
  is unfixed — tracked in `designs/reelcut-remaining.md` §5a.

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
