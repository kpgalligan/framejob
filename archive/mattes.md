# Road map "mattes" — the matte track (#240)

**Closed** 2026-10-08 (MT5). Issue batch B89. The decisions are spec §11
MT-1..MT-7 (`designs/spec/11-decisions/mattes.md`); this file is the phases'
record. It is condensed into `designs/adr/mattes.md` and was moved to
`archive/mattes.md` when the road map closed.

## Goal

A track can be switched to "matte for the track below": its clips are not
drawn, and what they show cuts the track directly behind, by alpha, inverted
alpha, luma or inverted luma, in preview, `render_frame` and every export. The
video-input half of #240 (video as an input to a graphic) is #251, iceboxed,
and nothing here decides it.

## The owner's choices

**2026-10-07**, on the research's seven (#240's latest comment):

1. Matte only.
2. Any clip that draws can be a matte — text, shape, image, graphic, video,
   nest.
3. A matte TRACK: a track switched to "matte for the track below"; nothing on
   it is drawn; whatever it shows at each moment cuts the track directly
   behind it.
4. All four kinds: alpha, inverted alpha, luma, inverted luma.
5. Where the matte track has no clip, the track below shows normally.
6. The matte clip's position, scale, rotation, crop, corner radius, opacity,
   actions, motion presets and transitions with other matte clips shape the
   window; its blend mode, drop shadow and reflection do nothing and the
   inspector says so; the matted clip's own drop shadow follows the cut-out
   shape.
7. The video-input half is NOT closed: split out to #251 and iceboxed while
   the matte is evaluated as a compromise.

**2026-10-08**, O1–O10, all as recommended:

- O1 A matte track's audio plays as on any track; Mute Audio silences it.
- O2 No fifth header toggle; an accent tag by the name, "Matte · Alpha"
  (dimmed "Matte · nothing behind" when it cuts nothing).
- O3 Track ▸ Matte ▸ Off / Alpha / Inverted Alpha / Luma / Inverted Luma, and
  the same submenu in the track's context menu after Solo.
- O4 No shortcut.
- O5 A matte track's clips at half opacity with a dashed outline, and an
  accent bracket to the track below.
- O6 A note at the top of every Clip sub-tab on a matte-track clip ("Matte for
  the track below (Alpha). Not drawn: its blend mode, drop shadow and
  reflection have no effect." / "Nothing is behind this matte track, so it
  cuts nothing."), every control live.
- O7 A matte clip is the topmost canvas hit inside its box.
- O8 The words Off / Alpha / Inverted Alpha / Luma / Inverted Luma; undo
  "Track Matte".
- O9 Nesting a matte without its target beside other clips is allowed.
- O10 The matted clip's reflection is cut where it lands.

## Phases

Each phase is committed alone, after its review.

| Phase | What | State |
|---|---|---|
| MT0 | MT-1..MT-6 recorded in spec §11 before any code; the matte spike (`tools/proof/matte_spike/`): the route for an unmatted layer and the matte's cost at 1080p and 4K | done (below) |
| MT1 | Tolls, pure moves: `recipe_layer.rs` out of `recipe.rs`, `Compositor+Shadow.swift` and `prepare` out of `Compositor.swift`, `FrameRecipe.swift` out of `ProjectSnapshot.swift` | done (below) |
| MT2 | The matte end to end over MCP, top level and nested levels: `tracks[].matte` (format 14), `set_track {matte}`, the recipe's `matte` and `mattes`, the mask and resolve passes, `matte_proof.py` | done (below) |
| MT3 | Nests (`nest` / `unnest`), dissolves, shadow, reflection, Preview Quality, every export | done (below) |
| MT4 | The chrome (MT-7 recorded first): Track ▸ Matte, the context submenu, the header tag, the lane, the Clip tab's note | done (below) |
| MT5 | Documents and figures; the spike re-run against the tree; the ADR; close | done (below) |

## MT0 — the decisions and the spike (2026-10-08)

**Decisions.** MT-1..MT-6 recorded in `designs/spec/11-decisions/mattes.md`
before any code, with their rows in that folder's README and the spec index's
`11-decisions/` cell. They are not G- decisions: a matte is a track relation
the compositor draws for any clip (road map 10's plan: "Mattes are compositor
features", `designs/adr/svg-motion-plan.md`). MT-6's route was filled from the
figures below.

**The instrument.** `tools/proof/matte_spike/matte_spike.py` makes three
shaders from the tree's `Compositor.metal` — V0 as it is, V1 the placeholder
route (every layer samples `texture(1)` at step 7, an unmatted one a 1×1 white
texture), V2 the function-constant route (the same multiply behind
`kMatte [[function_constant(1)]]`) — at anchors asserted to occur exactly once
(B0), compiles them with `xcrun metal` (B1), and builds `bench.swift` over
`app/Sources` with `-O` through `swift_build.build` (B2). Nothing is merged
into `app/`. Scenes, full bleed: S1 one picture layer; S2 the picture and a
white-text layer drawn normally; S3 the text as an alpha matte (mask pass,
resolve into an `r8Unorm` coverage cleared to 1, the picture cut); S4 S3 plus
a static gradient as a luma matte resolved into the same coverage. K3/K4 read
one pixel inside and one outside the matte in S3/S4 for both routes at both
sizes before anything is timed. A sample is 200 frames, one command buffer
each, `gpuEndTime − gpuStartTime`; three runs, every series interleaved; a
figure is the median of the runs' medians. C0, the CONTROL, is two
interleaved V0 series of S1; their |Δ| is the noise floor.

**Host** (H0, read only): Apple M2 Max, macOS 26.5.1; `pmset -g` printed
`powermode 0`, `pmset -g batt` "Now drawing from 'AC Power'".

**Figures** (`matte_spike.py --measure`, 2026-10-08 04:44 CEST, exit 0; ms;
the runs' range in brackets):

| | 1920×1080 | 3840×2160 |
|---|---|---|
| V0 S1 | 0.108 (0.105–0.147) | 0.387 (0.385–0.468) |
| V0 S1, second series (C0) | 0.146 (0.105–0.267) | 0.385 (0.384–0.385) |
| noise floor (C0) | 0.038 | 0.002 |
| V1 S1 / S2 / S3 / S4 | 0.123 / 0.365 / 0.283 / 0.405 | 0.439 / 0.887 / 0.953 / 1.429 |
| V2 S1 / S2 / S3 / S4 | 0.127 / 0.266 / 0.285 / 0.353 | 0.384 / 0.752 / 0.898 / 1.324 |
| S1 overhead over V0: V1, V2 | 0.014, 0.019 (bound 0.02 + noise) | 0.052, −0.003 (bound 0.08 + noise) |
| matte cost with V1: S3 − S2, S4 − S2 | −0.082, 0.040 (budget 0.50) | 0.066, 0.542 (budget 2.00) |
| memory per matte (bgra8), per coverage (r8) | 8.3 MB, 2.1 MB | 33.2 MB, 8.3 MB |

**Route: V1, the placeholder** (T1, recorded): V1's S1 overhead is within its
bound plus the noise floor at both sizes. **Cost: PASS** (T2) at both sizes,
so MT2 may proceed.

**What the figures do not settle.** The 1080p series are noisy: the C0
control's two V0 series differ by 0.038 ms, one series' runs span 0.105–0.267
ms, and S3 − S2 came out negative (S2's runs spanned 0.220–0.367 ms) — the C0
floor understates the 1080p noise (S3 − S2's −0.082 ms is twice it), so no
1080p difference above is resolved, and the 1080p frame (≈0.1 ms of
GPU work between waits) is short enough that the GPU's clock state shows. The
4K series are tight (C0 0.002 ms). At 4K the placeholder costs an unmatted
full-bleed layer 0.05–0.07 ms (S1 0.052; S2, two layers, 0.887 against V2's
0.752), which the route rule accepts and MT-6 records as its risk.
`Compositor.metal`'s cost notes quote 0.30–0.33 ms for the same no-effect
full-bleed 1080p layer and do not name their host; this run's S1 is 0.108 ms,
so those notes' absolute figures are not comparable with these.

**Mutants** (`--check --mutant NAME`, both killed): `resolve-writes-one` (the
resolve returns 1 everywhere) failed K3 and K4 at both sizes for both routes
(outside pixels read the picture, e.g. `[0, 140, 40, 255]` for
`[153, 102, 51, 255]`); `anchor-missing` (V1's step-7 anchor misspelt) failed
B0 ("the step 7 anchor occurs 0 times, not once").

## MT1 — tolls, pure moves, no behaviour (2026-10-08)

**What moved.** Three files over or at the size rule paid before MT2 adds to
them, each a pure move:

- `core/src/recipe.rs`: `RecipeLayer` and its `object()` went whole to the new
  `recipe_layer.rs` (with a `//!` doc and its own imports); `recipe.rs`
  re-exports it (`pub(crate) use crate::recipe_layer::RecipeLayer;`), so
  `recipe_text.rs`'s burn-in is unchanged, and lost the `VideoProps` import
  only the struct read.
- `app/Sources/Compositor.swift`: `// MARK: - Shadows` through `blurKernel`,
  with `ShadowSurfaces`, went whole into an `extension MetalRenderer` in the
  new `Compositor+Shadow.swift`; `render`'s per-layer block (the partner, the
  uniforms, the source switch) became `prepare` in `CompositorEffects.swift`,
  returning a `PreparedLayer` (nil where the loop used to `continue`), and
  `render` calls it. `private` came off what the moved code and `prepare`
  read: `DestinationPass`, `device`, `pipeline`, `shadowPipeline`, `sampler`,
  `placeholder`, `blurSupported`, `shadowSurfaces`, `blurKernels`, the two
  sigma constants, `uniforms(for:…)`, `source(for:…)`, `LayerSource`, and
  `encodeShadow` itself, which `render` calls across the file boundary.
- `app/Sources/ProjectSnapshot.swift`: `// MARK: - Frame recipe (spec §7.3)`
  went whole to the new `FrameRecipe.swift`.

Each moved block was diffed against the original lines: byte-identical but
for `encodeShadow`'s `private`. Two comments the move made false name the new
file: `recipe_layer.rs`'s pointer to `RecipeLayer.init(from:)` (now
`FrameRecipe.swift`) and `VideoPane.swift`'s to the shadow mask (now
`Compositor+Shadow.swift`).

| File | Before | After |
|---|---|---|
| `core/src/recipe.rs` | 596 | 511 |
| `core/src/recipe_layer.rs` | — | 94 |
| `core/src/lib.rs` | 111 | 112 |
| `app/Sources/Compositor.swift` | 1396 | 1120 |
| `app/Sources/Compositor+Shadow.swift` | — | 263 |
| `app/Sources/CompositorEffects.swift` | 371 | 418 |
| `app/Sources/ProjectSnapshot.swift` | 2182 | 1866 |
| `app/Sources/FrameRecipe.swift` | — | 317 |

**Scores** (a pure move adds no decision, so no mutants; passing is every
score equal to its last recorded run, 168/168 and 150/150 in road map 9):
`cargo test --release --test recipe` 15/15; `make lint` and `make typecheck`
clean (the four baseline warnings); on Debug, `phase6_proof.py` 168/168 and
`phase8_chrome.py` 150/150. `make gate` passed twice in the foreground, the
second after the two comment fixes (typecheck, fmt, lint, test 129 s, app;
221 s). The recorded run, on the gate's final Release build:
`phase6_proof.py` 168/168, no `Reelcut: ` line before or after;
`phase8_chrome.py` 150/150 (it builds its probes from `app/Sources` through
`swift_build.py` and drives no built app, so `RC_PROOF_APP` does not reach
it). Every score equals its last recorded run.

## MT2 — the matte end to end over MCP (2026-10-08)

**The core.** `TrackMatte` (`model_matte.rs`, re-exported through
`model_props.rs`; its order a shader discriminant) is `Track.matte`, after
`solo`, the model's first `skip_serializing_if`: an ordinary track writes no
key, so every older file round-trips byte for byte. `RC_FORMAT_VERSION` 14 in
`format.rs` and the header, no migrate step. `set_track` takes `matte` last
(`op_table.rs`'s new `Kind::Matte`, the nineteenth kind; an unchanged mode is
an identity through `finish`). `recipe_matte.rs` is MT-2 and MT-5's walk:
over the covering instances, a layer's levels inner to outer, each level's
cut asked before its own matte test so that `matte_target` alone says a
matte track is nobody's target; the first matte level is `into`. A group is
`MatteKey` (the enclosing nest-clip path, the matte track's id). `recipe.rs`
collects the covering instances once, writes `mattes` after `layers`, and a
layer drawn into a matte is the recipe's second override: `blend: "normal"`,
`shadow: null`, `reflection: null` (MT-4). `matte` is every layer's 21st key
(`recipe_layer.rs`), `null` on the burn-in. `nest` gives a nested track
`matte: none` and carries nothing until MT3: nesting a matte pair today draws
its matte clips inside the nest, ordinary.

**The app.** `TrackMatte.swift`; `TrackSnapshot.matte`; `RecipeLayerMatte`,
`RecipeMatteGroup`, `RecipeLayer.matte` and `FrameRecipe.mattes` in
`FrameRecipe.swift`; `ReelOps.setTrack(…, matte:)`; `set_track`'s handler
reads `matte` through `trackMatteArg` (an unknown name refused naming the
five) and its catalog entry teaches it. No menu: the chrome is MT4. The
shader takes route V1 (MT0): step 7c multiplies the coverage by the
`texture(1)` sample at the fragment's canvas-normalised position, and
`reelcut_matte_resolve_fragment` is the sixth pipeline (r8, source factor
zero, destination factor `sourceColor`). `Compositor+Matte.swift`'s
`encodeMattes` runs before the destination pass opens: each listed group's
members drawn into a pooled destination-sized target exactly as `render`
draws a layer (shadow, reflection, layer), each cut set resolved once into a
pooled r8 coverage. `render` skips a layer with a non-null `into`, binds the
coverage (or the placeholder) at `texture(1)` before the reflection and the
draw, and hands it to `encodeShadow`, whose silhouette pass binds it too. A
cut that names a matte not drawn before it is needed fails the frame
(`MatteError.unordered`) rather than drawing it uncut: a recipe from the core
never asks for one, and every matte throw happens before its encoder opens.

| File | Before | After |
|---|---|---|
| `core/src/recipe.rs` | 511 | 543 |
| `core/src/recipe_matte.rs` | — | 219 |
| `core/src/model_matte.rs` | — | 45 |
| `app/Sources/Compositor.swift` | 1120 | 1147 |
| `app/Sources/Compositor+Matte.swift` | — | 272 |
| `app/Sources/Compositor+Shadow.swift` | 263 | 267 |
| `app/Sources/FrameRecipe.swift` | 317 | 360 |
| `app/Sources/ProjectSnapshot.swift` | 1866 | 1871 |
| `app/Sources/TrackMatte.swift` | — | 34 |

**Scores.** `cargo test --release`: `matte` 8/8 (roles at a tick, top level
and through nests; the unlisted `into` of a back-most matte and of a matte
behind a matte; a hidden track, no clip at `t` and video off cut nothing; the
overrides with the model kept; the identity and the unknown name; the plan's
JSON unchanged by every mode; groups deepest first; the burn-in), `schema_v14`
4/4, `recipe` 15/15, `op_table` 8/8, `op_schemas` 10/10, `op_nullability` 2/2
(its optional inventory 66 → 67). `make lint`, `make typecheck` (the four
baseline warnings), `make app-debug`. On Debug: `matte_proof.py` 16/16,
`phase6_proof.py` 168/168, `phase8_chrome.py` 150/150. `make gate` passed
three times in the foreground, each after a Swift change the mutants forced
(below): 233 s, 198 s, 203 s (the last two with fmt and lint skipped, their
inputs unchanged). The recorded run, on the third gate's Release build:
`matte_proof.py` 16/16, `phase6_proof.py` 168/168 (no `Reelcut: ` line before
or after), `phase8_chrome.py` 150/150.

**Mutants** (eight, the spec's budget; `matte_proof.py --mutant NAME`, each on
a tree copy built by its own `make app-debug`, rule R; a core mutant naming
CT also runs `cargo test --release --test matte` in the copy's core). The
first pass caught six and found two holes:
- `source-drawn` survived MM: MM compared its frame only with A1's, which the
  mutant corrupts the same way (a white matte rectangle drawn under a white
  one). MM now draws C in red and makes A1's two region claims itself.
- `core-matte-behind-matte` survived MM: the mutated recipe lists the front
  matte's group after the group it cuts (both at depth 0, so by id), and the
  resolve skipped a matte not drawn yet, so nothing showed. The walk now asks
  a level's cut before its own matte test (so `matte_target` alone says a
  matte track is nobody's target), and a cut naming a matte not drawn before
  it fails the frame (`MatteError.unordered`). Run again, that failure was a
  Metal assertion that killed the instance — "Command encoder released
  without endEncoding": the throw left the resolve's encoder open — so every
  matte throw now precedes its encoder, and `render`'s suspends the
  destination pass first.
The second pass, on the final instrument, caught `shader-no-multiply` (A1 A2
L1), `source-drawn` (A1 B0 MM), `resolve-mode-ignored` (A2 L1 L2 L3),
`core-no-prune` (V5 H0), `core-untargeted-into-null` (B0 MM CT),
`core-no-override` (P6) and `handler-drops-matte` (A1 G0); after the encoder
fix, `core-matte-behind-matte` was run again alone and caught (MM: no frame;
the other fifteen rows passed, so the instance lived). The fix touched no
other mutant's anchor.

**Owed.** Nesting a matte pair draws its matte clips inside the nest,
ordinary, until MT3's carry rule (done in MT3, below).

## MT3 — nests, dissolves, shadow, reflection, Preview Quality, every export (2026-10-08)

**The core.** `edit_nest.rs` is MT-5's nesting half. `nest` puts the nest
clip on the front-most selected track that is not a matte track (the
front-most when all are); `nested_track` copies the source's `matte`, and
one pass over the mapping (the carry rule) keeps it only when the nested
track directly behind is the copy of `recipe_matte.rs`'s `matte_target` of
the source — so a matte pair nested together keeps cutting inside, and a
matte taken without its target (or a matte above a matte) is ordinary
there. `unnest` counts depth from the nest's front-most NON-matte track
(`front`; `len − 1` when all are), so a carried matte track's depth is
negative and it lands on the track in front of the nest clip's; with none
there it lands on a new ordinary track, as any clip the overlap rule
refuses. Nothing in the recipe changed: MT2's walk already keyed a group by
the enclosing nest-clip path, which is what gives each half of a split nest
clip in a dissolve its own matte. `core/tests/matte_nest.rs` (six tests):
the front track and carry for a pair, for the matte clips alone, for a matte
without its target and for a matte above a matte; unnest of a carried pair
(roles and `mattes` as before nesting); a carried matte with no track in
front; two groups for a split nest clip in a dissolve.

**The app.** One shader change: step 7c keeps the coverage sample as
`matteCover`, and the outgoing half of a dissolve multiplies its partner's
cover by it (MT-3) — on one matted track both halves read the same
coverage, so the pair composites to m·mix(out, in, p) + (1 − m)·bg under a
soft matte as under a hard one. An unmatted layer's `matteCover` is the
placeholder's exact 1.0, so no unmatted picture moves. The shadow's
silhouette pass and the reflection already bound the coverage (MT2); MT3
proves them.

| File | Before | After |
|---|---|---|
| `core/src/edit_nest.rs` | 321 | 366 |
| `core/tests/matte_nest.rs` | — | 273 |
| `app/Resources/Shaders/Compositor.metal` | 1611 | 1620 |
| `tools/proof/matte_proof.py` | 698 | 1395 |
| `tools/proof/matte_probe.py` | — | 294 |
| `tools/proof/matte_probe.swift` | — | 181 |

**The instruments.** `matte_proof.py` gains N1–N7, T1–T3, S1, RF1, E1–E7
and F1 (its docstring has every fixture); `matte_probe.py` builds
`matte_probe.swift` over `app/Sources` through `swift_build.py` and renders
two fixtures at Full, Half and Quarter through `Playback.previewComposition`
and `AVAssetImageGenerator` (Q1 the window's box and coverage, Q2 a matted
card's cut shape and its shadow, the cut shape offset, as fractions of the
frame; B0 the build, Q0 the three destinations as a control). Two claims
the spec put in the proof are read elsewhere, because no tool returns a
recipe: that N7's overlap lists two groups is `matte_nest.rs`'s
(`a_split_nest_clip_in_a_dissolve_has_one_group_per_half`), and the halves'
origins are read from `get_project` (a nest clip's origin is its start). T2
and T3 measure the dissolve at its overlap's midpoint (1 s, curve linear),
where the unmatted dissolve read (119, 0, 136) from red and blue — p a
little past 0.5 on the frame grid; T3's formula uses that measured
dissolve, so it holds whatever p is.

**Scores.** `cargo test --release --test matte_nest` 6/6 (with `matte` 8/8
and `nest` 35/35 beside it); `make lint` clean; `make app-debug`. On Debug:
`matte_proof.py --only N1,…,F1,Z1` 21/21; `matte_probe.py` 4/4 (B0, Q0, Q1
and Q2 at all three qualities: Q1's window at x 0.1667…0.5833, y
0.1852…0.5556, coverage 0.1543 at each; Q2's shadow at x 0.2562…0.3604, y
0.3074…0.5852 at each, against 0.2563…0.3605 and 0.3075…0.5853). `make gate`
passed in the foreground (typecheck skipped, its inputs unchanged; fmt, lint,
test 136 s, app; 146 s), and again after the mutants' CT change and these
records (test 71 s, the rest skipped; 72 s). The recorded run, on the gate's Release
build: `matte_proof.py` whole 36/36 (no `Reelcut: ` line; F1's line "1 hits,
0 mismatched"; E3 ran — this Mac has the HEVC-with-alpha encoder);
`matte_probe.py` drives no app (it builds from `app/Sources`, as
`phase8_chrome.py` does), so its run above, on the same tree, is its record.

**Mutants** (the spec's eight, once on the final instrument; each
`matte_proof.py --mutant NAME --only <its rows>,Z1` on a tree copy built by
its own `make app-debug`, and the probe's on a mutated copy of the shader
beside the same binary): `dissolve-no-cover` (T3: (131, 18, 78) against
(110.53, 25.4, 81.22) at (4, 4)), `nest-always-carries` (N4),
`nest-old-front-track` (N1: the nest clip on the matte track),
`unnest-old-depth` (N6: the tracks' mattes `none, none, alpha` after
unnest; CT), `core-group-by-track` (N7: 44 green in the left window, 63 red
in the right; CT), `resolve-overwrites` (N5: the outer window's own part
showed the movie), `reflection-placeholder` (RF1: the reflection white below
the card) and `coverage-destination-coords` (Q2 at Half and Quarter) — all
caught. The first pass showed CT stopping at the first failing test file
(`core-group-by-track` failed `matte.rs` before `matte_nest.rs` ran), so CT
became `--no-fail-fast` and names the failing files; the three mutants that
name CT were run again on it — `core-group-by-track` (`matte` and
`matte_nest`), `unnest-old-depth` (`matte_nest`), MT2's
`core-untargeted-into-null` (B0 MM, `matte`) — with MT2's
`shader-no-multiply` (A1 A2 L1), whose anchor this phase rewrote: all caught.

## MT4 — the chrome (2026-10-08)

**MT-7 first.** `designs/spec/11-decisions/mattes.md` gained MT-7 in the
spec's exact words, its index a row (the file 99 → 114 lines, the folder
5403 → 5419), before any code; `spec_index_proof.py` 144/144.

**What landed.** `TrackMatte.target(of:in:)` — the core's `matte_target`
for the chrome only. Track ▸ Matte ▸ Off / Alpha / Inverted Alpha / Luma /
Inverted Luma (`AppDelegate+Menus.swift`, `tagged` rows as Timeline Track
Height's) runs `EditorViewController+Matte.swift`'s `setTrackMatte` on
`currentTrack`, undo "Track Matte"; its validator arm sits beside Solo's in
`EditorViewController+Identity.swift` (checked by tag, enabled iff there is
a current track). The track context menu's Matte submenu follows Solo
(`TimelineView+TrackMenu.swift`: rows targeted at the view, the track by
`representedObject`, the mode by tag, checked; `trackMenuSetMatte` →
`onEdit("Track Matte", …)`). `TimelineView+Matte.swift` holds the header's
tag (`TimelineMatteTag`, `matteTagWidth`, `drawMatteTag`), the lane
(`drawMatteLane`: the body passes in one transparency layer at 0.5, then
dashed accent outlines, then the bracket) and `invalidateMatteBrackets`.
`TimelineView.swift` (frozen) took three lines of wiring: the name label's
width less `matteTagWidth`, the `drawMatteTag` call, and
`invalidateMatteBrackets` in `pinFloatingBands` (see Deviations).
`TimelineClipDrawing.swift`'s `drawClips` runs its bodies and transition
zones inside `drawMatteLane`; the selection rings stay whole on top.
`ClipPane+Matte.swift`'s `matteNote` is MT-7's rule; `ClipHeaderBlock`
shows it as a wrapping `InspectorNoteLabel` under the sub-tab strip, and
`ClipPane.structureSignature` carries whether it shows. `UIMenuTable.swift`
and `inventory.json` have the `setTrackMatte:` row; the `set_track` tool's
prose and its `matte` description name Track ▸ Matte.

**Where the tag goes.** The rule is the row's geometry, "room above the
toggles": the tag takes its own line when the first toggle's top is ≥ 10 pt
below the name's box. That is every Medium and Large row and the Small video
row (54 pt); the Small text (30 pt) and audio (40 pt) rows put it on the
name's line. Beside "Matte · Inverted Alpha" there a name had 6.0 pt left
and was not drawn (`TimelineDraw.label` draws nothing narrower than 6 pt);
the review's fix pass amended MT-7 (every Medium and Large row and the Small
video row; on the name's line the tag reads "Matte" alone when its full words
would leave the name less than 40 pt, `TimelineMatteTag.fitted`), so the
three long tags read "Matte" there and the name keeps 81 pt ("Matte · Alpha"
47 pt, "Matte · Luma" 48 pt).

**Scores** (each printed by a run on this tree). `make typecheck` 0 errors,
the four baseline warnings; `inventory.py --check` 5/5; `spec_index_proof.py`
144/144. `matte_chrome_probe.py` 8/8 (B0, M1, M2, M3, T1, LN, NT, HT; LN's
pixel (158, 185, 193) against the 0.5 mix (158.0, 185.5, 193.5) of the fill
(61, 116, 132) and the lane (255, 255, 255), in the capture's
`NSCalibratedRGBColorSpace`); `track_menu_probe.py` 25/25 (22 before, and
three Matte rows); `v2_menu.py --only H` 5/5 on the Debug loop;
`screens.py --only 10c-matte-track` 6 pass of 6, 0 new problems, light and
dark. `make gate` passed in the foreground once (typecheck 5 s, fmt and lint
skipped, test 109 s, app 85 s; 199 s). The recorded run, on the gate's
Release build: `v2_menu.py` whole 28/28 (H1/H2 99 rows each, no `Reelcut: `
line, no DEFAULTS MOVED); `matte_chrome_probe.py` and `track_menu_probe.py`
drive no app (they build from `app/Sources`), so their runs above, on the same
tree, are their record.

**Mutants** (the spec's seven, once on the final instrument, each
`matte_chrome_probe.py --mutant NAME` over a mutated copy of `app/Sources`):
`menu-current-track` (M3), `validator-always-off` (M2, all three current
tracks), `tag-never-dim` (T1), `lane-full-opacity` (LN), `note-every-clip`
(NT, the function and the shown note), `hit-skips-matte` (HT) and
`undo-name` (M3) — all caught, 7/8 each.

**The review's fix pass** (two should-fix findings and a nit). (1) The
Small-row tag: MT-7, §4.4 and MAT-2 amended (above); `TimelineMatteTag.fitted`
and `minimumNameWidth` (40 pt), applied by `matteTagWidth` and by
`drawMatteTag`'s name-line branch, which now answers the words and box it
drew. (2) The dimmed tag drew the accent at 0.45 alpha, about 1.8:1 in both
looks; it now draws `DS.textMuted` at its own alpha over the same faint box
(`TimelineMatteTag.textColor(dimmed:)`, `fillColor(dimmed:)`): 3.85:1 light,
5.57:1 dark; the undimmed accent tag then measured 3.01:1 light and 3.24:1
dark on the host's blue accent (the second fix pass, below, scores it). MAT-2 no longer excepts the dimmed tag.
New rows T2 (the five tags on the Small text and audio name lines) and T3 (the
contrast, both looks) and mutants `tag-never-short` (T2) and
`tag-dim-accent` (T3, both looks), both caught; no earlier mutant's anchor was
touched. `matte_chrome_probe.py` 10/10; `make typecheck` 0 errors, the four
baseline warnings; `spec_index_proof.py` 144/144; `screens.py --only
10c-matte-track` 6 pass of 6, 0 new problems (`tools/proof/work/screens/2026-10-08-073729/`);
`make gate` PASS (typecheck 4 s, fmt and lint skipped, test 118 s, app 83 s;
205 s).

**The second fix pass** (one should-fix and an orchestrator ruling). The
first pass's T3 control asked the undimmed accent tag for 3:1, which depends
on the owner's System Settings accent: about 1.3:1 under yellow, and under
3:1 for green, orange, red, pink and graphite. The probe would fail with no
code change, and the tag's words would be just as hard to read. The ruling:
the box keeps its accent tint, and the undimmed tag's words are drawn in
the primary label colour (`TimelineMatteTag.textColor(dimmed: false)` is
`DS.textStrong`), so their legibility no longer depends on the accent. MT-7,
§4.4, MT-7's index row and MAT-2 say so; Lines 117, 209 and 5422. T3 now
scores the undimmed tag at 4.5:1 or better in both looks, over the host's
accent (11.9:1 light, 9.79:1 dark) and over every corner of the sRGB cube
standing in for the accent at the box's 0.22 alpha (worst 9.8:1 light under
black, 6.4:1 dark under white). The control is replaced by two
host-independent controls: the header row's own colour as text over the
dimmed box measures 1.14:1 light and 1.1:1 dark (it must be under 1.5:1),
and the light row's luminance is above 0.5 and the dark row's below 0.1. The
dimmed tag is unchanged (3.85:1, 5.57:1). The new mutant is
`tag-accent-text` (T3: the undimmed words back in the accent, 3.01:1 and
3.24:1 on the host's accent, worst 2.37:1 and 2.02:1 over the corners).
It was caught, and so was `tag-dim-accent` with its anchor moved (1.76:1,
1.78:1). Results: `matte_chrome_probe.py` 10/10; `make typecheck` 0 errors
and the four baseline warnings; `spec_index_proof.py` 144/144; `screens.py
--only 10c-matte-track` 6 pass of 6, 0 new problems
(`tools/proof/work/screens/2026-10-08-074800/`); `make gate` PASS
(typecheck 4 s, fmt and lint skipped, test 103 s, app 78 s; 186 s).

**Deviations.** (1) The screen is `designs/screens/10c-matte-track.md`, not
`17-matte-track.md`: screens run in name order and `16-recorder-panel` must
be the last (`screens.py`'s `validate`: "New Recording… must be the last
screen run"), so a 17 would fail the whole catalog; it needed a fixture,
`matte`, in `screens.py` (no step tool sets a track's matte). (2) HT's
mutant is anchored in `CanvasLayerBox.boxes(recipe:snapshot:)`, the canvas's
live hit path (`PreviewCanvasView.hit(at:)`), not in
`FrameRecipe.layer(at:measuring:)`, which no app code calls; HT checks both.
(3) `TimelineView.swift` took a third wiring line, `invalidateMatteBrackets`
in `pinFloatingBands`: the bracket is pinned to the header column, and a
layer-backed scroll moves the content without redrawing it, which would
leave the bracket at its old place. (4) The note shows only when the matte
tracks share one mode, for both sentences (MT-7's grammar puts "share one
mode" before the choice of sentence).

## MT5 — documents, figures, close (2026-10-08)

**Documents.** `docs/graphics-api.md` gained "Video inside a graphic: the
matte": a graphic cannot read a video's pixels, so the way to show video
inside a shape it draws is a matte track above the video, with one `js`
window module that `graphic/tests/reference.rs` runs. `README.md`'s Looks
bullet names the matte track and its chrome. `designs/adr/roadmap-10-graphics.md`'s
"Deliberately not built" now lists only video input to a graphic (#251), the
matte half built here. The decision file's header points at the ADR and this
archived record. MAT-1 gained a step: a slow full-frame black-to-white
gradient as a luma matte on a 4K canvas, compared by eye with the gradient
drawn alone (the "Not established" r8 question; see below).

**The spike against the tree.** `matte_spike.py --tree` times VT, the tree's
own `Compositor.metal` unpatched (route V1 as MT2 built it, with MT3's
dissolve change), against the same pinned V0 by the same bench and scenes;
`bench.swift` now draws whichever matte variants it is given, so MT0's
`--check` and `--measure` are unchanged (`--check` exit 0 after the change).
Host (H0, read only): `pmset -g` `powermode 0`, `pmset -g batt` "AC Power";
Apple M2 Max, macOS 26.5.1. `--check --tree` exit 0 (K3/K4 for VT at both
sizes). `--measure --tree`, 2026-10-08 07:57 CEST, exit 0 (ms; the runs'
range in brackets):

| | 1920×1080 | 3840×2160 |
|---|---|---|
| V0 S1 | 0.108 (0.106–0.146) | 0.388 (0.387–0.388) |
| V0 S1, second series (C0) | 0.105 (0.105–0.107) | 0.387 (0.387–0.388) |
| noise floor (C0) | 0.002 | 0.001 |
| VT S1 / S2 / S3 / S4 | 0.120 / 0.222 / 0.254 / 0.376 | 0.442 / 0.891 / 0.960 / 1.440 |
| VT's S1 overhead over V0 | 0.013 (bound 0.02 + noise) | 0.054 (bound 0.08 + noise) |
| matte cost: S3 − S2, S4 − S2 | 0.033, 0.154 (budget 0.50) | 0.070, 0.549 (budget 2.00) |
| memory per matte (bgra8), per coverage (r8) | 8.3 MB, 2.1 MB | 33.2 MB, 8.3 MB |

These series are tight at both sizes (C0 0.002 and 0.001 ms), unlike MT0's
1080p ones, so they resolve what MT0's could not: the shipped placeholder
costs an unmatted full-bleed layer 0.013 ms at 1080p and 0.054 ms at 4K
(MT0's V1: 0.014 and 0.052), one alpha matte costs 0.033 ms at 1080p and
0.070 ms at 4K, and two mattes in one coverage plus the gradient layer's own
draw 0.154 and 0.549 ms, all within MT0's budget.

**The "Not established" list, reviewed against the tree.** (1) The route's
cost: measured, MT0 and above. (2) Whether r8 coverage bands on a slow luma
gradient at 4K: the matte is drawn into a bgra8 target, so the luma it
yields is already 8-bit; r8 adds at most one rounding, and L1 (MT2) holds
every sample of a gradient luma matte to ±1 of card × g + background ×
(1 − g). Whether that reads as banding to an eye is MAT-1's new step.
(3) A dissolve between two nest clips cut by different mattes: still an
approximation, drafted as an issue. (4) "Matte · Inverted Alpha" on a Small
row: settled in MT4's fix pass (the tag reads "Matte" there). (5) Other
editors' behaviour: general knowledge only; nothing owed. (6) The GIF
palette at a soft matte edge: not a matte question (the GIF writer quantises
any soft edge — a shadow, a feathered corner — the same way); nothing owed.
(7) Memory with many mattes: the pool has no cap, drafted as an issue. Also
from the reviews: MT4's T3 now sweeps the dimmed tag over every sRGB cube
corner too (07-review-MT4-3's nit; worst 3.77:1 light, 4.95:1 dark,
`matte_chrome_probe.py` 10/10), and `FrameRecipe.layer(at:measuring:)`,
which no app code called, was deleted (HT keeps the canvas's own path).
