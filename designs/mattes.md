# Road map "mattes" — the matte track (#240)

**In progress.** Issue batch B89. The decisions are spec §11 MT-1..MT-7
(`designs/spec/11-decisions/mattes.md`); this file is the phases' record. When
the road map closes (MT5) it is condensed into `designs/adr/mattes.md` and
moved to `archive/`.

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
| MT1 | Tolls, pure moves: `recipe_layer.rs` out of `recipe.rs`, `Compositor+Shadow.swift` and `prepare` out of `Compositor.swift`, `FrameRecipe.swift` out of `ProjectSnapshot.swift` | — |
| MT2 | The matte end to end over MCP, top level and nested levels: `tracks[].matte` (format 14), `set_track {matte}`, the recipe's `matte` and `mattes`, the mask and resolve passes, `matte_proof.py` | — |
| MT3 | Nests (`nest` / `unnest`), dissolves, shadow, reflection, Preview Quality, every export | — |
| MT4 | The chrome (MT-7 recorded first): Track ▸ Matte, the context submenu, the header tag, the lane, the Clip tab's note | — |
| MT5 | Documents and figures; the spike re-run against the tree; the ADR; close | — |

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
