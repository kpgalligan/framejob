# Grading tier 4: the grading extras (road map "grading-4")

- **Status:** Built and closed 2026-10-15. Each phase was one litecode pipeline with its own review, worked in `~/devel/framejob-grading4` on branch `grading-4` and merged into main alone after its gate (GR-25):
  - T4-0, the road map, GR-24…GR-30 and the curve types' pure move to `CurveProps.swift` (`31f3aa1`)
  - T4-1, the scopes: the vectorscope's same-bin add and its zoom (#265, GR-26, GR-31) (`a8ef6fd`)
  - T4-2, hue curves and the curve editor's extras (#267, #270, GR-32, format 20) (`510f181`)
  - T4-2b, Color's Hue by the exact HSV shift (GR-33) (`d22f8e2`)
  - T4-3, curves of different point counts blend their values (#271, GR-34) (`ac874f6`)
  - T4-4, the qualifier's cleanup blur (#268, GR-35, format 21) (`23832cf`)
  - T4-5, the close: this record (the commit that moved this record to `archive/`)
- **Original:** `archive/grading-4.md` is the full record. It has no section numbers, so it is cited by phase: "orig T4-2" is its "T4-2 — hue curves and the curve editor's extras" section.
- **Spec decisions:** GR-24..GR-35 in spec §11 (`designs/spec/11-decisions/grading-4.md`). They stay binding, and where the original words them differently, §11's text wins:
  - GR-24: tier 4 builds five extras and closes four (owner, 2026-10-14, every choice as recommended): the vectorscope zoom counted at the zoom (#265), Hue vs Hue and Hue vs Sat with the curve editor's hover readout and ⇧ axis lock (#267, #270), a blend between curves of different point counts (#271), the qualifier's cleanup blur at full resolution with GR-6 unchanged (#268); closes GR-27…GR-30.
  - GR-25: each phase gated in the `grading-4` worktree and merged into main alone; main's next format numbers and GR IDs, renumbered before a merge if main moved; no verdict phase; synthetic fixtures.
  - GR-26: a flat saturated colour (0.8, 0.1, 0.1) is GR-10's sixth timed fixture, and a non-central vectorscope bin shared by a whole SIMD group is added once.
  - GR-27: an Offset wheel is not wanted (#266).
  - GR-28: a qualifier on picture clips is not wanted (#269).
  - GR-29: 1,024-level scopes are not wanted (#273).
  - GR-30: a histogram behind the curve plot is not wanted (#270's first item).
  - GR-31: the vectorscope zoom, ×1, ×2, ×4 per slot and window, not persisted; `bin = 128 + round(255·zoom·c)`, clamped at ×1, not counted off the plot at ×2 and ×4; off-plot targets as rim ticks; the "1× 2× 4×" cells; `render_frame {vectorscope_zoom}` and the JSON's `zoom` and `off_plot`; no format change.
  - GR-32: hue curves, `video.curves.hue_hue` (a shift −180…180°) and `.hue_sat` (a gain 0…2), 2–16 points on a periodic Fritsch–Carlson spline in Swift only; after the channel curves at step 4c.2, an exact HSV-hue shift keeping Rec. 709 luma and a gain about it, behind GR-13's chroma guard; the strip 1,024 × 2 and `hueCurvesEnabled`; the Hue and Sat cells, the hover readout and the ⇧ axis lock; format 20.
  - GR-33: Color's Hue turns HSV hue by GR-32's exact shift, + red → yellow → green, Rec. 709 luma kept, the degrees wrapped, no chroma guard; `hueRotate` removed; old projects' Hue renders change with no migration.
  - GR-34: inside an action, two non-identity curves of different point counts render `(1−t)·a(x) + t·b(x)`, published as `{from, to, t}` only for 0 < t < 1 and never in a file; same counts keep the per-point lerp; a curve write with an action selected goes to the END.
  - GR-35: the qualifier's cleanup blur, `video.qualifier.blur` 0…1, σ = 24·blur canvas pixels ÷ `canvasPerDest`, q in an `r16Float` map blurred by `MPSImageGaussianBlur`, the coverage never blurred, Show Selection blurred, blur 0 today's inline pass byte-identical; format 21.
  - Amended: GR-2 (by GR-32, GR-33); GR-4, GR-6 and GR-7 (by GR-32: Show Ungraded neutralises the hue curves, the adjustment pass applies them, they come before the look); GR-10 (by GR-26, GR-29, GR-31); GR-12 (by GR-30, GR-32, GR-34); GR-13 (by GR-24, GR-28, GR-35); GR-32 (by GR-33, GR-34); and `designs/adr/grading-2.md`'s first decision by GR-26.

## Context

Tier 2 left the extras out on purpose: "each extra can be its own issue once there is feedback" (its choice 7). At its close (G2-5, 2026-10-11) eight were filed, each `ai-drafted` and `low-priority`: #265 vectorscope zoom, #266 an Offset wheel, #267 hue curves, #268 a cleanup blur of the qualifier's selection, #269 a qualifier on picture clips, #270 the curve editor's extras, #271 curves of different point counts and #273 1,024-level scopes. The feedback never came, since no real footage has been graded, but on 2026-10-14 the owner ordered "Grading extras, then HDR and color" and answered the tier-4 brief (`~/.claude/litecode/reelcut/grading-tier4/I-grading-tier4.md`, outside the repo) with every choice as recommended: build #265 with the solid-colour fix, #267 as two curves, #270's readout and ⇧ lock, #271 as a blend and #268 at full resolution; close #266, #269, #273 and #270's histogram. On 2026-10-15 the owner ruled on T4-2's H16 ("Fix with the new exact shift (Recommended)"), which became T4-2b. (orig "The owner's choices", "Tier 4 as answered", T4-2's Residue)

## Decisions

- **The vectorscope zoom is counted at the zoom, not drawn larger.** A one-level cast is half a bin at ×1, and drawing a bin larger cannot show half a bin; at ×4 it moves 2 bins. At ×2 and ×4 an off-plot pixel is not counted: clamped to the edge it measured 1.67 ms at ×4 on a gradient in the brief's bench and piled a false ring on the rim. The JSON's `off_plot` says how many were left out. (orig "Vectorscope zoom", T4-1; GR-31)
- **The same-bin add.** A flat saturated colour put every pixel of the shipped kernel into one non-central bin, one global atomic each: 7.29–7.33 ms per 4K frame in the brief's bench, reachable with a solid-colour slide and View ▸ Scopes. GR-10's five fixtures had no such frame. A SIMD group whose lanes share one non-central bin now adds its count once (`simd_broadcast_first`, `simd_sum`, `simd_all`); the app's own pass measured 0.357 ms on flat red at ×1. (orig "Found while reading" 1, T4-1; GR-26)
- **T3 has its own bound, 0.85.** T3 compares the ×1 vectorscope with its forced-global twin. Against the shared 0.75 it failed one run in three on the unchanged tree under heavy load (0.706–0.796), while under the `vectorscope-global` mutant the two builds are the same shader, a ratio of 1.0 by construction. The orchestrator's ruling (2026-10-15) set 0.85 between them; T2 keeps 0.75. It is not moved again without a new measurement. (orig T4-1 "T3, and its bound")
- **Hue curves are a periodic Fritsch–Carlson spline and an exact HSV shift.** The spline's secants wrap across 360°, so a curve passes through its points, never overshoots and joins through 0°. The shift turns the colour's HSV hue by the curve's angle while keeping its Rec. 709 luma, giving up chroma only to stay in 0…1; the gain mixes about that luma. Both are weighted by GR-13's chroma guard, so a grey, whose hue is noise, is never tinted. Row 0 of the strip is sampled at y 0.25, so every existing curves render stayed byte-identical. (orig "Hue curves", T4-2; GR-32)
- **Color's Hue moved onto the same shift** (T4-2b). T4-2's H16 recorded that Color's Hue, through `hueRotate`, turned +40 against its label's sign and by an amount that varied by hue (red −55.52°, green −22.63°). The owner chose the exact shift. Every picture with a non-zero Hue changes, Hue 0 is byte-identical, and there is no migration or format bump. (orig T4-2b; GR-33)
- **Curves of different counts blend their values**, `(1−t)·a(x) + t·b(x)`, exact at both ends. #271's own design, resampling the shorter curve onto the longer one's x's, was measured to jump at the action's start (median 27.7, max 775 ten-bit levels on 1,000 rising 3 → 5 pairs). The core publishes `{from, to, t}` and Swift's strip blends the two splines, so there is still no spline in Rust and no FFI; the form is never in a file. Same-count actions keep the per-point lerp, so every existing render is byte-identical. (orig "Curves of different point counts", T4-3; GR-34)
- **The cleanup blur blurs q only.** q is rendered into an `r16Float` map of the destination's size, blurred by `MPSImageGaussianBlur` (the shadow's kernel cache) and read at `texture(0)` behind the block's reserved float, now `blurred`. The coverage, a matte track's edge, is never blurred. Blur 0 takes today's inline pass, byte-identical. It works at full resolution (choice 6a), and GR-6's refusal of the blur FILTER on an adjustment clip is unchanged. (orig "The qualifier's cleanup blur", T4-4; GR-35)
- **Four closes.** The Offset wheel: its master is Color's Brightness, and a fourth disc narrows the row past the master field (GR-27). A qualifier on picture clips: a clip holds one grade, and Insert ▸ Adjustment Clip is the secondary (GR-28). 1,024-level scopes: about 2.5 levels per drawn pixel, and the float compositor never quantizes a grade (GR-29). A histogram behind the curve: the tap sees the frame after the curve (GR-30). (orig "Why the Offset wheel is closed", "Why a qualifier on picture clips is closed", "Why 1,024-level scopes are closed", "The curves editor's extras")
- **The Concat rule held** at design and build time: nothing of Concat was opened. The sources are the Rec. 709 Y′CbCr matrix (ITU-R BT.709-6), Fritsch and Carlson (1980) with its secants wrapped, the HSV hue and smoothstep of GR-13, and a Gaussian (`MPSImageGaussianBlur`). (orig "The Concat rule")

## What it built — where it lives now

- Core: `model_grade.rs` (`CurveDomain`, `Curves.hue_hue` / `.hue_sat`, `Qualifier.blur`, `QUALIFIER_BLUR_MAX`), `grade_check.rs` (the hue domain, the blur), `actions_curves.rs` (`CurveBlend`, `curve_blends`, `blended_curves_json`), `actions_clamp.rs`, `actions_qualifier.rs` (`qualifier_json`), wiring in `actions.rs`, `recipe_layer.rs`, `recipe.rs` and `recipe_text.rs`; `RC_FORMAT_VERSION` 20 (T4-2) and 21 (T4-4). Tests: `hue_curves.rs`, `schema_v20.rs`, `curve_blend.rs`, `qualifier_blur.rs`, `schema_v21.rs`. No op, op-table row, tool or FFI export.
- Metal: `Waveform.metal`'s `framejob_vectorscope_bin` (the zoom at `buffer(1)`, the same-bin add); `Compositor.metal`'s `hsvHue`, `gradeHueShift`, `gradeHueCurves`, `gradeCurves` at y 0.25, Color's Hue through `gradeHueShift` (`hueRotate` removed), `framejob_qualifier_map_fragment` and the adjust fragment's `texture(0)` arm.
- Swift: `ScopeTraces.swift` (`ScopePass`), `WaveformAnalyzer.swift`, `WaveformTap.swift`, `VectorscopeView.swift` (`VectorscopeZoomCells`, the rim ticks), `ScopeSlotView.swift`, `ScopesPanelView.swift`, `render_frame {vectorscope_zoom}` in `AgentServer+Render.swift` and `AgentServer+Scopes.swift`; `CurveProps.swift` (`CurveDomain`, six channels, `CurveBlend`), `CurveTable.swift` (the periodic spline, the strip's second row, the blend), `CurveTextures.swift` (1,024 × 2), `CurveEditorView.swift` (the hue plot, the ⇧ lock, the readout), `CurvePlotDecor.swift` (new), `VideoPane+Curves.swift`, `InspectorBinding+Writes.swift` (the END rule), `LayerUniforms.swift`'s `hueCurvesEnabled`; `QualifierProps.swift`, `Compositor+Selection.swift` (new), `Compositor+Adjustment.swift`, `MetalRenderer.swift`, `VideoPane+Qualifier.swift`; the prose in `AgentCatalog+Properties.swift` and `AgentCatalog+Render.swift`.
- Proofs: `scopes_proof.py` / `scopes_probe.swift` (S11–S14, T3, H4, the sixth fixture); `curves_proof.py` (H1–H19, B1–B4) / `curves_probe.swift` (P12–P21); `qualifier_proof.py` (Q1–Q6) / `qualifier_probe.swift` (K9, K10); `grading_spike.py`'s TB over `tree_bench.swift`'s SQ series; the harness's zoom arguments; screens `04b-preview-scopes`, `05g-clip-curves`, `05h-clip-qualifier`.
- Person checks: GRD-11 (T4-1: the zoom on a face and a grey card, the ticks, a solid-colour slide playing with the vectorscope shown), GRD-13 (T4-2, T4-2b, T4-3: steps 9–12), GRD-14 (T4-4: step 9), each extended in `docs/manual-checks.md`.
- Pure moves: T4-0's curve types out of `GradeProps.swift` into `CurveProps.swift` (526 → 343, the new file 184). `designs/adr/app-file-history.md` names the next seams.

**Headline numbers** (Apple M2 Max, `powermode 0`, AC power; the host was loaded by other sessions throughout).

| Measure | Bound | Measured | Command |
|---|---|---|---|
| T4-0's pure move | renders byte-identical, catalog equal | 29/29, N0's seven curve-less frames byte-identical; the parsed catalogs equal (97 tools) | `RC_PROOF_APP=release curves_proof.py compare tools/proof/work/t4-0/ctl` |
| The vectorscope on flat saturated red at 4K, ×1 (T4-1) | ≤ 1.1 ms (GR-10, GR-26) | 0.357 ms in the app's pass; 7.29–7.33 ms on the shipped kernel in the brief's bench | `RC_PROOF_APP=release scopes_proof.py` T1 |
| Each scope at 4K, worst of six fixtures (T4-1) | ≤ 1.1 ms at every zoom | vectorscope ×1 0.452, ×2 0.401, ×4 0.356; parade 0.688; histogram 0.668 (the repeat: 0.420, 0.353, 0.321, 0.625, 0.667) | `RC_PROOF_APP=release scopes_proof.py` T1 |
| The banded parade against a forced-global one (T4-1) | ≤ 0.75 | flat 0.442 / 1.150, ratio 0.385 (the repeat: flat-red 0.634 / 1.154, 0.549) | `… scopes_proof.py` T2 |
| The ×1 vectorscope against its forced-global twin (T4-1) | ≤ 0.85 | near-grey 0.411 / 0.578, ratio 0.712 (the repeat: 0.412 / 0.577, 0.713); under `vectorscope-global` 1.213 | `… scopes_proof.py` T3 |
| `render_frame {vectorscope_zoom}` (T4-1) | the script's count | `off_plot` 147960 against the script's 147960; 3 refused by name | `… scopes_proof.py` S13 (26/26) |
| Hue vs Hue ±40 over a 720-column sweep (T4-2) | its row | worst HSV-hue error 0.540° (+40) and 0.624° (−40, chroma ≥ 64; 1.176° over all 720) | `RC_PROOF_APP=release curves_proof.py compare tools/proof/work/t4-2/ctl` H15 (49/49) |
| Luma kept by the shift (T4-2) | its row | the (153, 102, 102) card 112.84 → 112.79 under +90°; the sweep's worst 0.488 levels | `… compare …` H12 |
| An uncurved layer, and the adjustment pass (T4-2) | TC caps 0.069 / 0.061 ms; TA 0.081 / 0.060 | TC 0.002 / −0.001 ms; TA 0.002 / 0.008 ms (1080p / 2160p) | `grading_spike.py --measure --tree --tree-base a8ef6fd` |
| Color's Hue +40 (T4-2b) | H16 (±40 by colorsys, luma kept) | worst 0.540°, luma worst 0.488 levels, red → 39.49°, green → 159.92° (control on the old tree: worst 98.225° off, red → 304.48°) | `RC_PROOF_APP=release curves_proof.py compare tools/proof/work/t4-2/ctl` H16 (53/53) |
| A near-grey turned by Color's Hue (T4-2b) | not left grey (no guard) | (132, 128, 128) → (130, 129, 126), hue 45.0° | `… compare …` H19 |
| A 3 → 5 action's blend (T4-3) | the mean strip within a 10-bit level; ends exact | worst 0.489 ten-bit levels at t 0.3, 0.499 at t 0.5; both ends byte-equal | `RC_PROOF_APP=release curves_proof.py compare tools/proof/work/t4-3/ctl` B1 (59/59, N0's 18 frames byte-identical) |
| A same-count action stays the lerp (T4-3) | the lerp | 0.495 levels from the lerp, 124.90 from the value blend | `… compare …` B3 |
| The selection's variance on a noisy card (T4-4) | falls as the blur rises | 16256.25 at 0, 799.70 at 0.05, 113.10 at 0.15, 19.78 at 0.4 | `RC_PROOF_APP=release qualifier_proof.py compare tools/proof/work/t4-4/ctl` Q1 (40/40, N0's eight frames byte-identical) |
| The selection against a scripted Gaussian (T4-4) | max 4, mean 1 levels | max 1.078, mean 0.336 | `… compare …` Q2 |
| The blurred qualifier's cost over the inline pass (T4-4) | recorded | VT:SQ 0.249 / 0.958 ms; σ 2 +0.121 / +0.480, σ 8 +0.098 / +0.355, σ 24 +0.095 / +0.323 ms (1080p / 2160p); unblurred TA −0.000 / −0.002 ms | `grading_spike.py --measure --tree --tree-base ac874f6` TB, TA |

Mutants, each run once on the final instrument and each answering MUTANT PASS (a list amended and re-run where a row failed by construction, as each phase records): T4-1 eight (`scopes_proof.py --mutant`), T4-2 nine, T4-2b six, T4-3 six (`curves_proof.py --mutant`), T4-4 eight (`qualifier_proof.py --mutant`, `blur-zero-breaks-pass` through `compare`); T4-0 none, a pure move. The gates passed in 364 s (T4-0), 263 s (T4-1), 249 s (T4-2), 227 s (T4-2b), 377 s (T4-3) and 282 s (T4-4).

## Known limits

- **Synthetic fixtures only.** How the zoom, the hue curves, Color's Hue, a blend and the blur look on real footage is GRD-11, GRD-13 and GRD-14's.
- **Every strength is a first number**: the hue curves' ranges, the chroma guard reused, the blur's 24-pixel σ at 100 %.
- **The scopes and passes were timed on one M2 Max**, heavily loaded, whose GPU changed clock state between sessions; only differences timed in the same rounds are read.
- **Old projects' Color Hue renders change** (GR-33), with no migration; Hue 0 is byte-identical.
- **A failed map-pass encoder leaves a stale map read as blurred** (the T4-4 review's left nit): it needs a device already failing, and the compositor's other passes share the exposure.
- **Other editors' behaviour** (Resolve's 2× scope, Matte Finesse, Lumetri's curves) is from general knowledge, not checked against the products.

## Open items

Filed at T4-1, each `ai-drafted` and `low-priority`, still open:
- #297: `designs/spec/07.9a-agent-tools.md` past the ~500-line split threshold.

Closed: #296 by measurement in clean-up 4 (GR-26: the central 64 × 64 threadgroup path kept, since dropping it raised the worst 4K fixture, near-grey 0.5306 ms against the path's worst, gradient 0.4038; T3 stays, now scored on near-grey by name); #265 as built (T4-1, GR-26, GR-31); #267 as built (T4-2, GR-32); #268 as built (T4-4, GR-35); #270's hover readout and ⇧ axis lock as built (T4-2, GR-32) and its histogram behind the plot as not wanted (GR-30); #271 as built (T4-3, GR-34). Not wanted: #266 (GR-27), #269 (GR-28), #273 (GR-29).

Not filed, each decided at the close:
- Hue vs Luma: choice 5a said "not now"; it follows on the strip's row with no new design, if asked.
- A second, qualified grade on a picture clip: "a later issue only if asked" (GR-28).
- Dragging a hue point across 0°/360°: GR-32's "Not".
- GPU clock state in T1 ("Found while reading" 4): T1 already warms with G2-1's burst, and T3 has its own bound.
- The per-tap cost of the shift on a blurred layer: GR-33 accepts it.
- The stale-map nit: a known limit above.
- Every "Not established" item is settled by a phase's spec or left to a GRD row.

## Where to look in the original

- "The owner's choices" and "Tier 4 as answered": the owner's answers verbatim, the eleven choices, and what each of the eight issues asked, with the corrections to #268 and #271.
- "How it fits the tree": each extra's design as planned (the zoom's spread table and the bench's vectorscope variants, the hue curves, the editor's extras, the blend and its resampling table, the blur and its bench) and the three "Why … is closed" sections.
- "The standard recipe, file by file, and the tolls": the toll and the per-file plan at `3c3ac36`.
- "Spec §11: the plan": what stands, what was amended when, and the new entries.
- "Costs": the brief's bench (`bench.swift`), its build keys and commands, the host's load, and what was reasoned from them.
- "Not established"; "Found while reading" (the solid-colour slowdown, #268's and #271's corrections, the GPU clock state).
- T4-0: the move, its diffs and the catalog comparison.
- T4-1: the kernel and the Swift, S6's tie band, T1's six-fixture table, T3's bound and its runs, the eight mutants, the residue filed as #296 and #297.
- T4-2: the hue curves' landed list, the deviations (10 pt cells, H3's ramp, H13's chroma), H15 and H12, H16 recorded, the nine mutants.
- T4-2b: Color's Hue, who else uses it, the control on the old tree, the six mutants, `adjustment_proof.py`'s re-anchored `WEIGHT`.
- T4-3: the blend in the core and the strip, the 0.3 s deviation, B1–B4, the six mutants.
- T4-4: the blur's pass, the owner's choices for the row, the deviations (N0's undo, `blur-zero-breaks-pass` through `compare`, the pipeline counts), Q1–Q6, TB, the eight mutants.
- T4-5: the close, the issues and what was not filed.
