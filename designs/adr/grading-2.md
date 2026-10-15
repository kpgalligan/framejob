# Grading tier 2: scopes, wheels, curves and qualifiers (road map "grading-2")

- **Status:** Built and closed 2026-10-11. Each phase was one litecode pipeline with its own review, worked in `~/devel/reelcut-grading` on branch `grading-2` and merged into main alone after its gate (GR-14):
  - G2-0, the road map, GR-10 and four pure moves (`9dec954`)
  - G2-1, the scopes (#263, GR-10) (`4f52ead`)
  - G2-2, the wheels (#260, GR-11, GR-14) (`b2fd1f9`)
  - G2-3, the curves (#261, GR-12) (`75ebf34`)
  - G2-4, the qualifier (#262, GR-13) (`c948fad`)
  - G2-5, the close: T2 and the `parade-global` mutant, this record (the commit that moved this record to `archive/`)
- **Original:** `archive/grading-2.md` is the full record. It has no section numbers, so it is cited by phase: "orig G2-3" is its "G2-3 — the curves" section.
- **Spec decisions:** GR-10..GR-14 in spec §11 (`designs/spec/11-decisions/grading-2.md`), with the amendments they wrote into tier 1's entries (`designs/spec/11-decisions/grading.md`). They stay binding, and where the original words them differently, §11's text wins:
  - GR-10: the scopes — an RGB parade, a Rec. 709 vectorscope (bins centred on neutral, the six 75 % targets and the skin line from the matrix) and an R′G′B′Y′ histogram beside the waveform, in two stacked slots of View ▸ Scopes (⌃⌘W), opening Waveform over Vectorscope, the bottom slot hidden below 360 pt of pane; the counting rule (never one global atomic per pixel into a shared bin); the time bound, ≤ 1.1 ms of GPU per analysed 4K frame per scope, the worst of five fixtures, replacing #263's; `render_frame {parade, vectorscope, histogram}`; 256 levels.
  - GR-11: wheels, `video.wheels {lift, gamma, gain}`, each a Cartesian push `{x, y}` inside the unit circle and a `master`, at step 4c.1 after tone and before the look, on encoded values; `LayerUniforms` 116 → 128 floats; ⌥ fine-drag (wheels only); no typed field for the push; format 16. Not: no Offset wheel, no linear-light wheels.
  - GR-12: curves, `video.curves {master, red, green, blue}`, 2–16 `[x, y]` points on a Fritsch–Carlson monotone spline, `channel(master(v))`, at step 4c.2 through a 1,024-texel `rgba32Float` strip at `texture(3)`; identity absent; the spline in Swift; format 17. Not: no hue-vs curves, no histogram behind the plot, no hover readout, no resampling between curves of different counts.
  - GR-13: qualifiers, `video.qualifier {hue, saturation, luma, invert}` on adjustment clips only, `q` read from the destination before the grade and multiplied into the pass's `w`; HSV S with a near-black guard and the hue's chroma guard; `QualifierUniforms` at `buffer(1)`; Show Selection (the `selection` option) and Pick from Canvas (the `behind` option); Paste Attributes drops a qualifier onto a picture clip; format 18. Not: no cleanup blur, no qualifier on picture clips.
  - GR-14: each phase merged into main alone, main's format numbers 16, 17, 18, no verdict phase.
  - Amended: GR-2 (`LayerUniforms` grows to 128; the Color sub-tab's sections), GR-4 (`ungraded` neutralises wheels and curves and keeps the qualifier), GR-5 (by GR-10: the slot picker, View ▸ Scopes, three more booleans), GR-6 (the adjustment clip's Color sub-tab gains Qualifier, Wheels and Curves; `w` gains `q`), GR-7 (the order gains the wheels and curves between Light and the look).

## Context

GR-1 kept tier 1 and deferred tiers 2 and 3 "as issues, not out"; tier 1's close filed tier 2 as #260 (wheels), #261 (curves), #262 (qualifiers) and #263 (scopes). On 2026-10-10 the owner answered the tier-2 brief's choices 1–9 "All as recommended": all four, scopes first and qualifiers last (1a); two stacked scope slots with View ▸ Scopes (2b); wheels and curves after Light and before the look (3a); a qualifier on adjustment clips only (4a); Show Selection and Pick from Canvas (5); the controls as more sections on the Color sub-tab (6a); three wheels, four curves and an H/S/L qualifier with no extras, "each extra can be its own issue once there is feedback" (7); one worktree, each phase merged when its gate passes (8b); no trial phase or keep-or-drop gate (9). #258 was closed by the owner and #257 left for after tier 2.

## Decisions

- **The scopes' cost is global atomics, so GR-10 bounds the worst fixture, not a ramp.** The brief's scratch spike put a global-atomic vectorscope at about 7 ms at 4K on a grey ramp or flat grey, and a global histogram at about 7 ms on flat and gradient pictures, while the arithmetic was cheap. The vectorscope counts its central 64 × 64 bins in threadgroup memory and the rest globally; the histogram counts per threadgroup. Bins are **centred on neutral**, so a grey lands mid-bin (the spike's edged bins defeated the merge on a ramp). #263's 0.168 / 0.331 ms was the waveform's figure on one ramp and was replaced by GR-10's 1.1 ms over five fixtures. (orig "Costs", G2-1)
  - Amended by GR-26 (grading-4 T4-0): a flat saturated colour, not among the five, takes the shipped vectorscope kernel 7.29–7.33 ms at 4K (the tier-4 brief's scratch bench); GR-10's bound gains it as a sixth fixture, and T4-1 adds the same-bin add.
- **The parade's banded fallback was taken at review, and is guarded since G2-5.** With T1 warmed and timed one pass at a time, the global parade scored 1.019–1.042 ms at 4K on flat over eleven runs, inside 1.1 ms by 5–7 % (in G2-5 a forced-global build measured 1.15 ms there, over it); the review called that a flaky row, so GR-10's per-band threadgroup counts replaced it (8 px wide groups, two column bins, two copies per cell; a group spanning more bins adds globally). T1 alone could not tell the two apart, so G2-5 added T2 (on the fixture where a forced-global build's parade is slowest, the banded parade's 4K time ≤ 0.75 × that build's, the same shader with its `bool banded = ` line forced false, timed back to back) and the `parade-global` mutant. (orig G2-1, G2-5)
- **The wheel's puck is Cartesian**, `{x, y}` inside the unit circle, not hue-and-amount, so an action from neutral to a push lerps in a straight line through the centre instead of sweeping every hue. The push is `lookHueChroma`, a hue less its own Rec. 709 luma. (orig "Wheels (#260), G2-2")
- **The wheels are analytic in the shader, not folded into the curve strip**: an animated wheel would re-bake the strip every frame, and the spike priced them at nothing measurable. One growth of `LayerUniforms`, twelve floats to 128 (512 bytes): the nine numbers, `wheelsEnabled`, `curvesEnabled` and one reserved. (orig G2-2)
- **Curves are a 1D `rgba32Float` strip of 1,024 texels at `texture(3)`, not the look's lattice and not uniforms.** The lattice slot holds the look or the LUT, so curves in it would need a bake per (curve, look) pair and an imported LUT would lose its size; a 33³ lattice is up to 3 levels off an analytic curve; uniforms would be 128 floats plus a segment search per pixel. The spike measured ≤ 0.154 of a 10-bit level for the strip on a steep curve against ≤ 0.5 for `rgba16Float`, half-float storage's floor. (orig "Curves (#261), G2-3: a 1D strip…")
- **The spline lives in Swift only** (`CurveTable.swift`), used by the editor's drawing and the strip's upload. The core stores, checks and interpolates the points and never samples the spline: no FFI export, `ReelCore.swift` untouched. The cost is GR-12's accepted risk: two non-identity curves of different counts cannot be resampled, so an action between them switches at its end. (orig G2-3)
- **An identity curve is absent**, and an action aligns identity channels before the lerp (`align_identity_curves`), so Reset leaves the file as it was and a curve animates from the identity. (orig G2-3)
- **The qualifier attaches to adjustment clips only** (choice 4a), and `q` is read from the DESTINATION before the grade: "the skin" means the skin as it is, not as the grade made it. Saturation is HSV S = C / max with a near-black guard, and the hue fades out below a small chroma, so a grey is never picked by hue. `QualifierUniforms` (sixteen floats) sits at `buffer(1)` of the adjustment pass, so `LayerUniforms` did not grow for it. The recipe gained two options, `selection` (Show Selection: the clip's `q` as grey, layers in front of it left out) and `behind` (Pick from Canvas samples the picture behind the clip). An action's hue centre goes the short way round (choice 11 as the owner changed it): 350 → 10 passes 0. (orig G2-4)
- **Each phase merged into main alone, at main's format numbers** (GR-14): 16 wheels, 17 curves, 18 qualifiers, optional keys with no migration step; the scopes changed no project file. Tier 1's branch format (GR-9) was not repeated, since tier 2 was not an experiment. (orig "Where the work happens")
- **Tier 2 closes nothing off for tier 3** (#256, #264): every stage is defined on ENCODED values and its §11 entry says so; the 0…1 domain is the stage's, not the stored model's; the scopes compute their targets from the Rec. 709 matrix, so a wide-gamut scope is a second matrix; `texture(2)` stays the look and `texture(3)` the strip, so an input LUT would be its own step before 4c; no colour-space concept was added. (orig "What tier 2 must not close off")
  - Amended by GR-16 (grading-3 T3-0): the input conversion must precede step 3 (`layerSample` runs the chroma key and Color's four), so it is step 0, a per-source pass before the layer stage, not a step before 4c; it takes no layer-stage texture slot.
- **The Concat rule held** at design and build time: none of Concat's code, shaders, chains or colour tables was opened or carried over. The sources are textbook: lift/gamma/gain and the ASC CDL's algebra, Fritsch and Carlson (1980), the HSV hue and smoothstep, ITU-R BT.709-6 and the ColorChecker "light skin" patch. (orig "The Concat rule")

## What it built — where it lives now

- Core: `model_grade.rs` (`Wheel`, `Wheels`, `CurvePoint`, `Curves`, `HueRange`, `LevelRange`, `Qualifier`), `grade_check.rs` (`check_wheels`, `check_curves`, `check_qualifier`), `VideoProps.wheels`, `.curves`, `.qualifier`; `actions_curves.rs`, `actions_qualifier.rs`, the clamps in `actions_clamp.rs`; `edit_adjustment.rs`'s `check_qualifier_clip`; Paste Attributes' qualifier rule; `recipe_options.rs` (`selection`, `behind`), `recipe_selection.rs`; the recipe's `wheels` and `curves` keys (twenty-five layer keys); `RC_FORMAT_VERSION` 18. Tests: `wheels.rs`, `curves.rs`, `qualifier.rs`, `selection.rs`, `schema_v16.rs`, `schema_v17.rs`, `schema_v18.rs`. No op, tool, FFI export or op-table row.
- Metal: `Waveform.metal`'s `framejob_parade_bin`, `framejob_vectorscope_bin`, `framejob_histogram_bin`; `Compositor.metal`'s `gradeWheels` (4c.1), `gradeCurves` (4c.2, `texture(3)`), `QualifierUniforms` and `qualifierWeight` in `framejob_adjust_fragment`, `LayerUniforms` at 128 floats.
- Swift: `ScopeTraces.swift`, `WaveformAnalyzer.swift` (four kinds), `WaveformTap.swift`, `ScopesPanelView.swift`, `ScopeSlotView.swift`, `WaveformTraceView.swift`, `ParadeView.swift`, `VectorscopeView.swift`, `HistogramView.swift`, `AgentServer+Scopes.swift`; `GradeProps.swift` (wheel types; the curve types are `CurveProps.swift`'s since grading-4 T4-0), `ColorWheelControl.swift`, `WheelStripControl.swift`, `VideoPane+Wheels.swift`; `CurveTable.swift`, `CurveTextures.swift` (held by `LookTextures`), `CurveEditorView.swift`, `VideoPane+Curves.swift`; `QualifierProps.swift`, `RangeStripControl.swift`, `VideoPane+Qualifier.swift`, `EditorViewController+Qualifier.swift`, View ▸ Show Selection in `+Seeing`; `set_video`'s prose; `render_frame {parade, vectorscope, histogram, selection}`.
- Proofs: `scopes_proof.py` / `scopes_probe.swift`, `wheels_proof.py` / `wheels_probe.swift`, `curves_proof.py` / `curves_probe.swift`, `qualifier_proof.py` / `qualifier_probe.swift`, each with its mutants; `grading_spike.py --measure --tree` (TC, and TA since G2-4); screens `04b-preview-scopes`, `05f-clip-wheels`, `05g-clip-curves`, `05h-clip-qualifier`.
- Person checks: GRD-11…GRD-15 in `docs/manual-checks.md`.
- Pure moves and splits: G2-0's four (`ColorAdjust` → `GradeProps.swift`; `writeWaveform` → `AgentServer+Scopes.swift`; the rendering rows → `AgentCatalog+Render.swift`; `RecipeOptions` → `recipe_options.rs`); `ScopeSlotView.swift` out of the renamed panel (G2-1), `WheelStripControl.swift` out of `ColorWheelControl.swift` (G2-2), `CurveEditorState` into `VideoPane+Curves.swift` (G2-3). `designs/adr/app-file-history.md` and `core-file-history.md` name the next seams.

**Headline numbers** (Apple M2 Max, macOS 26.5.1, `powermode 0`, AC power).

| Measure | Bound | Measured | Command |
|---|---|---|---|
| Each scope's GPU time at 4K, worst of five fixtures (G2-1) | ≤ 1.1 ms (GR-10) | parade 0.622 ms (near-grey), vectorscope 0.390 (gradient), histogram 0.668 (flat); recorded waveform 0.450, waveform + vectorscope 0.798; every 1080p figure ≤ 0.394 | `RC_PROOF_APP=release scopes_proof.py` T1 |
| The banded parade against a forced-global one at 4K (G2-5) | banded ≤ 0.75 × global, on the fixture where global is slowest | flat: banded 0.440 ms against forced-global 1.153, ratio 0.382 (0.381–0.384 over four runs of one probe build); under the `parade-global` mutant 0.995–0.999 | `RC_PROOF_APP=release scopes_proof.py` T2 |
| An unwheeled layer (G2-2) | +0.020 / +0.061 ms (1080p / 4K) | +0.003 / −0.001 ms | `grading_spike.py --measure --tree --tree-base 4f52ead` TC |
| An uncurved layer (G2-3) | +0.020 / +0.061 ms | +0.001 / +0.000 ms (the second run; the first missed at 1080p, +0.077, with the GPU changing clock state inside the run) | `grading_spike.py --measure --tree --tree-base b2fd1f9` TC |
| An unqualified layer (G2-4) | +0.020 / +0.061 ms | −0.066 / −0.000 ms | `grading_spike.py --measure --tree --tree-base 75ebf34` TC |
| An adjustment pass with the qualifier's reading (G2-4) | +0.036 / +0.061 ms | −0.023 / +0.044 ms (V0:SA 0.812, VT:SA 0.856 ms at 4K) | the same run's TA |
| A curve's points on a 16-bit `render_frame` (G2-3) | within a 10-bit level | 0, 0, 0.375 and 0 of a 10-bit level | `curves_proof.py compare` K1 |

Each phase's recorded proof, whole, on Release, and its mutants (each MUTANT PASS, no other row failing but `parade-global`'s tolerated T1, parade 1.151–1.153 ms on flat): G2-1 `scopes_proof.py` 19/19, ten mutants, and at G2-5 20/20 with T2 and the eleventh, `parade-global`; G2-2 `wheels_proof.py compare` 23/23, nine; G2-3 `curves_proof.py compare` 29/29, ten; G2-4 `qualifier_proof.py compare` 32/32, thirteen.

The brief's spike (a scratch shader, NOT the compositor's, uncommitted; only differences between its passes are read): a global-atomic vectorscope 6.993 ms at 4K on a grey ramp and 7.160 on flat; a global histogram 7.163 on flat; the threadgroup vectorscope ≤ 0.391 and histogram ≤ 0.652 at 4K on every fixture; the global parade 1.020 at 4K on flat; the strip `rgba32Float` at 1,024 within 0.154 of a 10-bit level on a steep curve; wheels +0.000–0.002 ms at 4K over a copy pass.

## Known limits

- **The scopes are timed on the M2 Max only.** T1 and T2 ran on one host; GR-10's bound on another GPU is not measured.
- **Two scopes shown** take up to about 1.7 ms of GPU per analysed 4K frame: REASONED from the spike (GR-10's accepted risk), not measured in the app.
- **32-bit float filtering on M1** is REASONED from the GPU family; the fallback to `rgba16Float` is in `CurveTextures.swift:33`, still under half a 10-bit level.
- **The strengths and guards are first numbers**: the wheels' factors and the qualifier's chroma and near-black guards were set from fixtures, for the owner to judge on footage (GRD-12, GRD-14).
- **A wheel's push moves a saturated pixel's luma** (GR-11's accepted risk): the push is luma-neutral on grey, not on every colour.
- **An action between two non-identity curves of different counts switches at its end** (GR-12's accepted risk; #271).
- **The master strip's off-knob double-click was two undo steps** (GR-11 (4), accepted at G2-2's review): fixed by #272's batch (owner, 2026-10-12), GR-11 (4) amended — it is one step on or off the knob.
- **Screen 05h shows the "Selection" tag and the switch, not the grey**: `snapshot_ui`'s well is `render_frame`'s picture, which the switch never reaches; `qualifier_proof.py` E1 and V1 prove the selection.
- **Other editors' behaviour** (wheels' feel, scope layouts, qualifier softness) is from general knowledge.

## Open items

Filed at the close, each `ai-drafted` and `low-priority`:
- #265: vectorscope zoom.
- #266: an Offset wheel.
- #267: hue-vs-hue and hue-vs-saturation curves.
- #268: a cleanup blur of the qualifier's selection.
- #269: a qualifier on picture clips.
- #270: the curves editor's extras (a histogram behind the plot, a hover readout, ⇧ axis lock).
- #271: animating between two non-identity curves of different point counts.
- #272: the wheels' master strip, a double-click off the knob is two undo steps — fixed by #272's batch (owner, 2026-10-12).
- #273: 1,024-level scopes for 10-bit work.

Commented: #256 (tier 3: what tier 2 defined on encoded values), #264 (the texture slots and where an input LUT would go), #124 (its cutout would take `texture(4)`). Left for after tier 2 (owner, 2026-10-10): #257, untouched. Closed as built: #260, #261, #262, #263.

## Where to look in the original

- "The owner's choices", "Tier 2 as answered" and "How it fits the tree": the nine choices, what each issue asked, what tier 1 left, the stage table (4c.1, 4c.2, the qualifier at step 7) and each tool's design as planned.
- "The editing surface": the sections' sketches, gestures and widths (corrected in G2-2).
- "The standard recipe, file by file, and the tolls": the four tolls and the per-file plan.
- "Costs": the brief's spike tables (scopes, the strip's precision, stage cost) with their commands, and what was reasoned from them.
- "What tier 2 must not close off": the tier-3 rules.
- G2-0: the four moves and their verification. G2-1: the scopes, the parade's fallback and T1's warm-burst method. G2-2–G2-4: each phase's landed list, deviations, recorded runs, mutants and review fixes.
- G2-5: T2, the `parade-global` mutant, the close's verification and the issues.
