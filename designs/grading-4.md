# Road map "grading-4" — colour grading, tier 4: the grading extras

**Opened 2026-10-14** (T4-0, in the worktree `~/devel/framejob-grading4` on branch `grading-4`,
from `3c3ac36`, merged into main after its gate). The design brief this road map answers is
`~/.claude/litecode/reelcut/grading-tier4/I-grading-tier4.md` (2026-10-14, tree `3c3ac36`), with
the owner's answers beside it in `~/.claude/litecode/reelcut/grading-tier4/answers.md`; both live
outside the repo, so everything a later phase needs from them is written here. Where the brief
and this file differ, this file wins. Tier 1's road map is closed (`designs/adr/grading.md`,
`archive/grading.md`, spec §11 GR-1..GR-9 in `designs/spec/11-decisions/grading.md`), and so are
tier 2's (`designs/adr/grading-2.md`, `archive/grading-2.md`, GR-10..GR-14 in
`designs/spec/11-decisions/grading-2.md`) and tier 3's (`designs/adr/grading-3.md`,
`archive/grading-3.md`, GR-15..GR-23 in `designs/spec/11-decisions/grading-3.md`). Tier 4's
decisions are GR-24 onwards, in `designs/spec/11-decisions/grading-4.md`.

## Goal

Build the grading extras tier 2 left out on purpose ("each extra can be its own issue once there
is feedback", tier 2's choice 7) as the owner chose them on 2026-10-14: **vectorscope zoom** with
the solid-colour slowdown fixed first (#265, T4-1), **hue curves** with the curve editor's hover
readout and ⇧ axis lock (#267, #270's second and third items, T4-2), **a blend between curves of
different point counts** (#271, T4-3) and **a cleanup blur of the qualifier's selection** (#268,
T4-4). The Offset wheel (#266), a qualifier on picture clips (#269), 1,024-level scopes (#273)
and a histogram behind the curve plot (#270's first item) are closed as not wanted. Each phase
lands whole on main, judged by its own proofs on synthetic fixtures. No real footage has been
graded yet, so every strength this tier adds is a first number, judged later by GRD-11, GRD-13
and GRD-14. There is no verdict phase.

## The owner's choices

**2026-10-14**, verbatim (`answers.md`):

> Owner, 2026-10-14, on I-grading-tier4.md (asked as four questions; every answer was the recommended one):
> - Choice 1 (scope): "Recommended set" — build #265 vectorscope zoom (with the solid-colour fix, choice 2), #267 hue curves, #270's hover readout and ⇧ axis lock, #271 the blend between different point counts, #268 the qualifier's cleanup blur. Close #266 (Offset wheel), #269 (qualifier on picture clips), #273 (1,024-level scopes) and #270's histogram behind the plot.
> - Choice 3 (zoom): "Count at the zoom (Recommended)" — 3(a) as the brief describes.
> - Choice 6 (blur): "Full resolution (Recommended)" — 6(a).
> - Choice 9 (#271): "Blend the two curves (Recommended)" — 9(a).
> - Not asked separately, taken as recommended (the owner took every recommendation offered, and the scope answer's description named them): choice 2 yes (fix the solid-colour slowdown in T4-1, a sixth fixture in GR-10's time limit); choice 5(a) two hue curves, Hue vs Hue and Hue vs Saturation (Hue vs Luma not now); choice 8(a) readout and ⇧ lock, no histogram; choices 4(a), 7(a), 10(a) close; choice 11 yes — the tier-2/3 arrangement: one worktree outside the repo (~/devel/framejob-grading4, branch grading-4), each phase merged into main when its gate passes, main's next format numbers, synthetic fixtures, no verdict phase.

The choices therefore read:

1. **(a)** Build vectorscope zoom with the solid-colour fix (#265), hue curves (#267), the hover
   readout and ⇧ lock (#270), the blend between different point counts (#271) and the
   qualifier's cleanup blur (#268). Close the Offset wheel (#266), the qualifier on picture clips
   (#269), 1,024-level scopes (#273) and the histogram behind the curve (#270's first item)
   (GR-24).
2. **Yes**: the vectorscope's solid-colour slowdown is fixed in T4-1 (a SIMD group whose pixels
   share one non-central bin adds once), and a flat saturated colour becomes GR-10's sixth timed
   fixture (GR-26).
3. **(a)** ×1, ×2 and ×4, counted at the zoom; off-plot colours not counted; the six targets as
   rim ticks; three cells "1× 2× 4×" in the square's bottom-right corner; per slot, per window,
   not saved, ×1 when a project opens; `render_frame` gains an optional `vectorscope_zoom` (1, 2
   or 4) (GR-24, T4-1).
4. **(a)** The Offset wheel closed as not wanted (GR-27).
5. **(a)** Two hue curves, Hue vs Hue and Hue vs Saturation, as two more cells in the Curves
   picker: Master · Red · Green · Blue · Hue · Sat; Hue vs Luma not now (GR-24, T4-2).
6. **(a)** The qualifier's cleanup blur, worked at full resolution (GR-24, T4-4).
7. **(a)** A qualifier on picture clips closed as not wanted (GR-28).
8. **(a)** The hover readout and the ⇧ axis lock; no histogram behind the plot (GR-24, GR-30,
   T4-2).
9. **(a)** Curves of different point counts blended by their values over the action; same-count
   actions keep today's per-point animation (GR-24, T4-3).
10. **(a)** 1,024-level scopes closed as not wanted (GR-29).
11. **Yes**: tiers 2 and 3's arrangement — one worktree outside the repo, each phase merged into
    main when its gate passes, main's next format numbers, no verdict phase, synthetic fixtures
    (GR-25).

## Tier 4 as answered

All eight were filed at tier 2's close (G2-5, 2026-10-11) as `ai-drafted`, `low-priority`, with
no comments. Each one cites the "Not" line it lifts: GR-10 (#265, #273), GR-11 (#266), GR-12
(#267, #270, #271) and GR-13 (#267, #268, #269). Each issue's "Decision needed" said "the
owner's, after feedback (choice 7)". That feedback has not come: the owner has not graded real
footage (GRD-11…GRD-15 are open person checks), and the project is not in real use yet. On
2026-10-14 the owner ordered "Grading extras, then HDR and color", so building now is the
owner's call.

- **#265** (vectorscope zoom): **built by T4-1** (GR-24, GR-26), counted at the zoom rather than
  drawn larger, which the issue proposed ("applied in drawing only; the counts stay 256 × 256, so
  `render_frame`'s JSON is unchanged"): a one-level cast is half a bin at ×1, and drawing a bin
  larger cannot show half a bin. The counts stay 256 × 256, counted at the zoom.
- **#266** (Offset wheel): **closed** (GR-27).
- **#267** (hue curves): **built by T4-2** (GR-24), the two curves Hue vs Hue and Hue vs Sat.
- **#268** (the qualifier's cleanup blur): **built by T4-4** (GR-24). **Correction to the
  issue:** it says "GR-6's refusal of blur on an adjustment clip … change[s]". It does not. GR-6
  refuses the blur FILTER (`video.filters`); a blur of the qualifier's selection is a key inside
  `video.qualifier`, so only GR-13's "Not" changes, and GR-6 is unchanged.
- **#269** (a qualifier on picture clips): **closed** (GR-28).
- **#270** (the curves editor's extras): the hover readout and the ⇧ axis lock **built by T4-2**
  (GR-24); the histogram behind the plot **closed** (GR-30).
- **#271** (curves of different counts): **built by T4-3** (GR-24) as a blend of the two curves'
  values. **Correction to the issue:** its "What it would take" (resample the shorter curve onto
  the longer one's x's) is measured to move the curve at the action's start, so the picture
  jumps when the action starts (below, "Curves of different counts"). Its design is replaced by
  the blend; the issue's body is rewritten by the orchestrator at T4-3.
- **#273** (1,024-level scopes): **closed** (GR-29).

## How it fits the tree

### Vectorscope zoom and the solid-colour slowdown (#265, GR-24, GR-26, T4-1; the brief's §2)

**What the user sees and does.** Today the vectorscope square (224 pt by default) shows the whole
Cb/Cr plane at one scale, and a near-grey picture (skin, a grey wall, a screen recording's UI) is
a small blob in the middle. T4-1 adds three small square cells "1× 2× 4×" in the square's
bottom-right corner, which a vectorscope never fills; the slot's header has no room left (248 pt,
full). At ×2 and ×4 the blob grows and its shape and lean show.
- The 75 % targets all fall off the plot from ×2, so each is drawn as a short tick on the rim in
  its direction, still labelled.
- The skin line stays, since it runs through the centre.
- The zoom belongs to each slot, per window, is not saved and is ×1 when a project opens: GR-10's
  rules for the slot picks.
- Resolve's vectorscope has a 2× option and Final Cut's a zoom setting (general knowledge, not
  checked against the products).

**What zooming the drawing cannot show** (computed by the brief's `zoom_bins.py`). GR-10's bins
are `128 + round(255·c)`, so one bin is 1/255 of Cb or Cr.

| | ×1 | ×2 | ×4 |
|---|---|---|---|
| A near-grey card (mid-grey ±5/255 per channel) spans | 11 × 11 bins (4.3 % of the width) | 21 × 21 | 41 × 41 |
| +1/255 on R moves Cr by | 0.50 bin | 1.00 | 2.00 |
| +1/255 on B moves Cb by | 0.50 bin | 1.00 | 2.00 |
| +1/255 on G moves (Cb, Cr) by | (−0.39, −0.45) | (−0.77, −0.91) | (−1.54, −1.82) |
| The six 75 % targets | on the plot | all off it | all off it |
| "Light skin" (194, 150, 130) reaches radius | 27 of 128 bins | 55 | 110 (inside) |

So the zoom is applied where the pixel is binned, `bin = 128 + round(255·zoom·c)`, not in
`VectorscopeView`.

**The time limit at zoom, and the slowdown it found.** The brief's scratch bench ran the tree's
own `Waveform.metal` kernels and zoom variants at 4K on GR-10's five fixtures, plus a sixth, a
flat saturated red (0.8, 0.1, 0.1). Seeds 3 and 4, in ms; the middle column is each variant's
worst of the five:

| Vectorscope pass, 4K | worst of GR-10's five | flat red |
|---|---|---|
| The tree's `framejob_vectorscope_bin` | 0.392–0.404 ms | **7.312–7.317 ms** (7.29–7.33 over all four seeds) |
| The same, plus a same-bin add per SIMD group | 0.399–0.412 | 0.281–0.282 |
| Zoom ×2, off-plot clamped to the edge (the ×1 rule) | 1.021–1.027 (gradient) | 7.318–7.345 |
| Zoom ×4, off-plot clamped | 1.667–1.669 (gradient) | 7.323–7.324 |
| Zoom ×2, off-plot not counted | 0.319–0.335 | 0.214–0.216 |
| Zoom ×4, off-plot not counted | 0.339–0.341 | 0.215 |
| Zoom ×4, not counted, plus the same-bin add | 0.404–0.407 | 0.271 |

- **The slowdown is in the shipped kernel, at ×1.** A flat saturated colour puts every pixel in
  one bin outside the central 64 × 64 that the kernel counts per threadgroup, so every pixel is
  one global atomic on one counter: the contention GR-10's counting rule exists to prevent.
  GR-10's five fixtures (flat grey, a ramp, near-grey noise, a gradient, RGB noise) have no flat
  saturated colour, so T1 never met it. It is reachable in ordinary use: a solid-colour slide or
  title with View ▸ Scopes showing the vectorscope, or `render_frame {vectorscope}`. It costs
  about 7 ms of GPU per analysed 4K frame, latest-wins off the render queue but on the same GPU.
- **The fix (GR-26):** each SIMD group whose 32 lanes share one non-central bin adds their count
  once (`simd_all`, `simd_sum`), and any other lane adds alone. The brief verified the counts
  equal to the per-pixel kernel's (8,294,400 on every fixture), with no cost elsewhere.
- **The zoom rule:** at ×2 and ×4 a pixel off the plot is NOT counted. Clamped to the edge, it
  breaks the limit on a gradient (1.67 ms) and piles a false ring on the rim. Resolve's zoom
  likewise just loses what falls outside. The JSON says how many were left out (`off_plot`), so a
  script can still total them. The dropping variants counted, at ×2/×4, 6,209,795/2,129,423 on
  the gradient, 5,088,951/1,700,600 on noise and 0 on red.

**What it takes.** No recipe step (the scopes read the finished frame, GR-5, GR-10); no op and
no format change.
- `render_frame` gains `vectorscope_zoom`, an integer 1, 2 or 4, anything else refused by name
  through `AgentServer+Arguments.swift`'s throwing helpers. It is a catalog row in
  `AgentCatalog+Render.swift`, and the argument gate picks it up from the schema. The JSON gains
  `"zoom"` and `"off_plot"`, and the sentence says "at ×4" when zoomed.
- Metal: `framejob_vectorscope_bin` takes the zoom (a `setBytes` at `buffer(1)`), drops
  off-plot pixels when zoom > 1, and gains the same-bin add.
- Swift: `WaveformAnalyzer.encode` passes a zoom; `WaveformTaps.attach` carries it beside the
  kinds, one tap per document key as today; `VectorscopeTrace` gains `zoom` and `offPlot`, its
  `bin(_:)` takes the zoom, and the targets become rim ticks when off the plot;
  `VectorscopeView` draws the ticks and hosts the three cells; `ScopeSlotView` holds the zoom;
  `ScopesPanelView` re-attaches on a change.
- Not measured by the brief: the app's own pass on the M2 Max, at 1080p, and on other GPUs
  (GR-10's known limit stands), and the drawn ticks' legibility (a harness capture).

### Hue curves (#267, GR-24, T4-2; the brief's §4)

**What the user sees and does.** The Curves picker gains two cells: Master · Red · Green · Blue ·
**Hue** · **Sat**. On those the plot shows a different kind of curve: the x axis is hue, with a
hue spectrum strip under the plot that wraps at 0°/360°; the curve is flat at the middle (no
change) until points are added; dragging a point up or down turns that hue (Hue vs Hue: "make the
greens more teal") or saturates or desaturates it (Hue vs Sat: "mute the reds"). The editor's
gestures carry over: press to add on the curve, drag, ⌥ fine, ⌫ to delete, the arrow keys, Reset
per cell. Resolve, Premiere's Lumetri and Final Cut all have at least these two (general
knowledge); Hue vs Luma can follow on the same texture row with no new design, if asked.

**Design** (proposed by the brief and accepted with choice 5a; T4-2's spec settles the numbers
listed under "Not established"):
- **Keys:** `video.curves.hue_hue` and `video.curves.hue_sat`, each 2–16 points `[hue, value]`,
  hue in degrees, 0 ≤ hue < 360, strictly rising. Hue vs Hue's value is a shift in degrees
  (−180…180, 0 = none, proposed); Hue vs Sat's a gain (0…2, 1 = none, proposed). A curve whose
  every value is neutral is the identity, written absent (GR-12's rule). Written through
  `set_video {patch: {curves: {hue_hue: [...]}}}`: no op, no tool, no FFI. Refused in the rule's
  own sentence, never clamped by a patch.
- **The spline:** Fritsch–Carlson with its secants wrapped across 360°, so the curve is periodic.
  It still passes through each point and never overshoots between two, so a hue-vs-sat curve
  never dips below its points and a flat stretch stays flat. It goes in `CurveTable.swift` beside
  the monotone one, the same rule, so the editor and the strip share it. It is not "monotone": a
  hue curve rises and falls.
- **Step 4c.2, after the channel curves and before the look,** in the layer stage and the
  adjustment pass, on encoded values. h is the qualifier's HSV hue of the colour (GR-13's
  formula, one helper shared with `qualifierWeight`). The shift turns the colour by Color's own
  `hueRotate` (its luma-keeping matrix) at the curve's angle, so a hue change does not jump
  brightness; a plain HSV turn would (yellow to blue at the same V is a large luma drop). The gain
  mixes around Rec. 709 luma as Color's Saturation does. Both are weighted by GR-13's chroma guard
  (`smoothstep(0.02, 0.06, C)`), so a grey or near-grey, whose hue is noise, is never tinted.
- **The texture:** the curves strip becomes 1,024 × **2**. Row 0 is today's composites, sampled
  at the row's centre (y = 0.25), exact in y, so today's results are unchanged. Row 1 holds r = the
  shift in turns and g = the gain, sampled at the hue. No new texture slot: `texture(4)` stays
  free for #124's cutout, as tier 2's ADR noted. The 2 × 1 identity placeholder becomes 2 × 2.
- **The uniforms:** `gradeReserved0` becomes `hueCurvesEnabled` and joins the effects gate's sum,
  so a layer without hue curves never enters the step. The block stays 128 floats.
- **Actions:** two hue curves of the same count lerp per point (§5.4). An identity meeting a curve
  is aligned on its x's with neutral values (`align_identity_curves`, extended). A count mismatch
  is #271's blend (T4-3).
- **Show Ungraded** writes them neutral (GR-4). **Paste Attributes** copies them with
  `video.curves`.

**What it takes.**
- Core: `model_grade.rs` (`Curves` gains two channels; `named()`, `is_identity` and
  `drop_identities` gain the per-channel neutral); `grade_check.rs` (`check_curves` gains the hue
  domain); `actions_curves.rs` (`curves_json` and the alignment); `actions_clamp.rs`; `recipe.rs`
  (the recipe writes all six always); `format.rs` and the header (format 20); tests in
  `core/tests/curves.rs` and `schema_v20.rs`.
- Swift: `CurveProps.swift` (after T4-0's toll; `ColorCurves` gains the two); `CurveTable.swift`
  (the periodic spline and row 1); `CurveTextures.swift` (two rows and its LRU key);
  `CurveEditorView.swift` (the wrapped axis, the spectrum strip and the centred y);
  `VideoPane+Curves.swift` (two cells and the In/Out fields' units, degrees and ×);
  `LayerUniforms.swift`, `Compositor+Uniforms.swift`, `Compositor+Adjustment.swift` (the flag);
  `set_video`'s prose.
- Metal: a `gradeHueCurves` after `gradeCurves` in both stages; `gradeCurves` samples row 0 at
  y = 0.25.
- Size: `CurveEditorView.swift` (398) will pass 400; its cap as an existing file is ~600. If the
  hue axis pushes it near that, the spectrum strip and the axis labels go to a file of their own
  (T4-2 decides, with `wc -l`).

**Measured** (the brief's scratch adjustment-like pass at 4K: HSV, a strip sample, the conversion
back, always on): **+0.012–0.023 ms** in one GPU state and **+0.225 ms** in a slower one. It is
behind its own gate, so an unused layer pays one comparison (tier 2's TC method holds it). T4-2
measures the real pass with `grading_spike.py --measure --tree`'s TC and TA rows.

### The curves editor's extras (#270, GR-24, GR-30, T4-2; the brief's §7)

- **Hover readout:** over the plot, a small label at the pointer reads "In 0.42 → Out 0.47" for
  the edited channel, and "Hue 34° → +12°" or "Hue 34° → ×0.80" on the hue curves, whether a
  point is selected or not.
- **⇧ axis lock:** ⇧ held during a drag locks it to the axis it started along (chosen after the
  first few points of travel), so a black point slides along the bottom without drifting up. ⇧
  today only enlarges the arrow keys' nudge, so there is no conflict; ⌥ (fine) and ⇧ combine.
- Chrome only, in `CurveEditorView.swift` (a tracking area, the label, the lock in the drag): no
  model, no format, no MCP (§7.9's exemption for view state; a drag's result is already a
  `set_video` write). The lock and the readout's text are probe rows (`curves_probe.swift`).
- **Why the histogram behind the plot is closed (GR-30):** a useful one shows what ENTERS the
  curve, so a point placed on a peak acts on those pixels. The scopes' tap sees the composited
  preview frame, which is after this clip's curve, its look, every layer in front and every other
  clip, so that histogram moves as the curve is dragged. The clip's own picture before its curve
  needs a render per edit with that clip's curves neutral (a recipe option in the shape of GR-13's
  `behind`), and `WaveformTaps` holds one tap per document key, so attaching one beside the panel
  means multiplexing the tap.

### Curves of different point counts (#271, GR-24, T4-3; the brief's §8)

**Today:** an action from a 3-point curve to a 5-point curve, neither the identity, holds the
start and jumps to the end at the action's end (GR-12's accepted risk), and a point added or
deleted on such a keyed curve lands on the clip's base.

**Why the issue's design does not work** (measured by the brief's `curves_resample.py`, a port of
`CurveTable.swift`'s Fritsch–Carlson). GR-12's spline goes through its points with tangents
computed from its neighbours. Resample a curve at new x's and re-spline it, and the curve changes
between the points, so the action's first frame would not be the curve the clip shows: a jump at
the start instead of the end. In 10-bit levels:

| Rule | 3 → 5 points, rising curves (1,000 pairs) | 4 → 16 |
|---|---|---|
| The issue's: the shorter curve resampled onto the longer one's x's | start jump median 27.7, p95 355, max 775 | median 8.4, max 443 |
| Both resampled onto the union of their x's | median 13.1, p95 38.3, max 84.8 | median 5.8, max 46.4; the union passes 16 points in 1,000 of 1,000 pairs |
| A gentle pair (mid lift → S curve) | 3.2 under either | — |

The first rule loses the shorter curve's own knees; the union keeps every point and still moves,
because the tangents change; at 4 → 16 the union is over `CURVE_POINTS_MAX`, and today's clamp
removes a channel with more than 16 points. On "any" (not only rising) curves the union's start
jump was median 12.3 (3 → 5) and 14.8 (4 → 16).

**The design that works: blend the two curves' values.** At fraction t, a channel whose two ends
are non-identity curves of different counts is `(1 − t)·a(x) + t·b(x)`.
- It is exact at both ends: t = 0 is the clip's curve, t = 1 the end's. A blend of two rising
  curves still rises.
- The core does not sample. It publishes the pair and t, and Swift's strip blends the two
  splines' values, so GR-12's "the spline lives in Swift only" holds: no spline in Rust, no FFI.
- **Where it differs from today:** only actions whose ends hold non-identity curves of different
  counts. Same-count actions keep §5.4's per-point lerp, so every existing render, and
  `curves_proof.py`'s A rows, stay byte-identical. The two rules give different halfway frames
  (p95 190 levels apart on the random set); neither is "right", and keeping per-point for same
  counts is what keeps today's renders.
- **Core:** the evaluated state is a `VideoProps`, whose `Curves` holds only point lists, so the
  blend needs an evaluation-only form the recipe writes for a mismatched channel, for example
  `{"from": [...], "to": [...], "t": 0.5}`, which a file never holds. `actions_curves.rs` gains
  the mismatch detection beside `align_identity_curves`; `actions.rs`' `lerp_at` stays; the
  recipe layer writes the blend form only then, so every other recipe is byte-identical.
- **Swift:** `CurveProps.swift` decodes the blend form, and `CurveTextures.swift` builds that
  channel's strip as the blend. Each frame of such an action is a new strip, as any animated curve
  already is (LRU of eight).
- **Inspector:** a point added or deleted on a keyed non-identity curve can now go to the
  action's END. GR-12's write rule is amended, and its "(the filters' rule)" exception removed.
- **No format change:** the file is unchanged. The hue curves (T4-2) use the same rule.

### The qualifier's cleanup blur (#268, GR-24, T4-4; the brief's §5)

**What the user sees and does.** The Qualifier section on an adjustment clip gains a **Blur** row
(strip, field, ⌥ fine, double-click to 0). Turned up, the speckled edges of a selection on noisy
footage melt into a smooth matte. Show Selection shows the smoothed grey, and `render_frame
{selection}` writes it. Resolve's qualifier has "Matte Finesse" and Premiere's HSL Secondary has
Denoise and Blur (general knowledge).

**Design** (proposed by the brief and accepted with choice 6a):
- **Key:** `video.qualifier.blur`, 0 = off. The unit is T4-4's to settle (proposed: a 0…1 amount
  like the blur filter's, mapped to a Gaussian σ in canvas pixels). The σ is divided by
  `canvasPerDest`, so a reduced preview blurs as much of the picture as an export does.
- **The pass:** when an adjustment layer is qualified and blurred, `drawAdjustment` (1) suspends
  the destination pass (`DestinationPass.suspend`, the shadow's precedent); (2) renders q from
  the target into an `r16Float` texture of the destination's size; (3) blurs it with
  `MPSImageGaussianBlur` (the kernel cache `Compositor+Shadow.swift` keeps by σ); (4) resumes the
  pass with `.load`. The adjust fragment then reads the blurred q from `texture(0)`, which that
  pass leaves unused, instead of computing it. `QualifierUniforms`' one reserved float becomes
  the "blurred" flag, so the block stays 64 bytes.
- **Full resolution** (choice 6a), not half.
- **Only q is blurred, never the matte coverage.** A matte track's edge is its own.
- **Blur 0 is today's path,** with no pass break, so it renders byte-identical.
- **GR-6 is unchanged:** the blur FILTER on an adjustment clip is still refused. Only GR-13's
  "Not: no cleanup blur" is lifted.
- Memory: two pooled `r16Float` textures of the destination's size (16.6 MB each at 4K).

**What it takes.** Core: `model_grade.rs` (`Qualifier.blur`), `grade_check.rs`
(`check_qualifier`), `actions_qualifier.rs` and the clamp, the recipe source's `qualifier`, format
21, `core/tests/qualifier.rs`, `schema_v21.rs`. Swift: `QualifierProps.swift` (the field and the
flag); `Compositor+Adjustment.swift` (the suspend, the q map, the blur, the resume) or a new
`Compositor+Selection.swift`; a q-map pipeline built beside `adjustPipeline`;
`VideoPane+Qualifier.swift` (the row); Pick from Canvas leaves the blur alone. Metal: a
`framejob_qualifier_map_fragment` writing q, and the adjust fragment's sampled-q arm.

**Measured** (the brief's scratch bench; GPU time added over an inline-qualifier adjustment pass;
a layer drawn first, so the pass break stores and reloads a real target):

| Variant | 4K, session 2 (3 seeds) | 4K, session 1 | 1080p |
|---|---|---|---|
| The pass break and q map, no blur | +0.254–0.266 ms | +0.379 | +0.050–0.130 |
| + Gaussian σ 2 px | +0.645–0.650 | +1.381–1.405 | +0.196–0.386 |
| + Gaussian σ 8 px | +0.490–0.501 | +1.038–1.047 | +0.163–0.332 |
| + Gaussian σ 24 px | +0.452–0.461 | +0.927–0.942 | +0.154–0.318 |
| Half-resolution q map, σ 4 at half (8 px full) | +0.234–0.239 | — | +0.090–0.159 |

The host was heavily loaded (load average 25–73), and session 1's GPU ran about twice as slow on
these passes as session 2's; both are kept. Small σ costs more than large (MPS picks its own
method by σ). Against the frame: a heavy 4K frame is 7.38–7.585 ms against the 8 ms limit
(precision's record), so a blurred qualifier is a real share of the headroom, paid only by a clip
that uses it. T4-4 records it in the app's pass through `grading_spike.py`'s TA row with the blur
on, and holds the unblurred TA unchanged.

### Why the Offset wheel is closed (#266, GR-27; the brief's §3)

A fourth disc, Offset, beside Lift · Gamma · Gain: a colour push and a master adding the same
amount to every level (the ASC CDL's offset). Resolve has it; Final Cut's "Master" is a global
push; Premiere has three wheels. In Resolve it does most of its work on log footage before the
display transform, and Frame Job converts log at step 0 (GR-16), so every wheel here works on
display-referred Rec. 709.
- Its master, `v += o·s`, is Color's Brightness (`rgb += u.brightness`, step 3 in `gradeSample`);
  only the place in the order differs. Its colour push is an additive cast on every level, and
  Temperature and Tint already shift every level's colour; Lift and Gain cover the ends.
- Its cost: three floats where one is free, so `LayerUniforms` would grow 128 → 132 floats (512 →
  528 bytes), moving the instruments that pin the block; a format bump; and the layout. The row is
  268 pt at the default pane; four columns are about 56 pt discs instead of 78, and at the 280 pt
  minimum pane a column is 54.5 pt, narrower than the 58 pt master field
  (`InspectorMetrics.fieldWidth`).

### Why a qualifier on picture clips is closed (#269, GR-28; the brief's §6)

All three big editors put the secondary on the clip, but beside the primary: a SECOND correction.
A Frame Job clip holds one grade, so a qualifier there would limit that one grade, and the clip
could not also have an unqualified primary. Insert ▸ Adjustment Clip spans the selected clips (or
In/Out) on the front track in one undo step (`EditorViewController+Adjustment.swift`), and the
adjustment clip qualifies what is behind it. The issue's design also carried tier 2's named cost:
Color's four run inside each blur sample (step 3 inside `gatherBlur`), so the "ungraded" colour of
a blurred clip means a second gather. A "second, qualified grade on a clip" (Premiere's shape) is
a bigger design, a later issue only if asked.

### Why 1,024-level scopes are closed (#273, GR-29; the brief's §9)

The waveform and parade wells are 200 pt tall, 400 px on a Retina display, so 1,024 levels are
2.56 levels per pixel; the histogram is 224 pt wide, 448 px, 2.3 levels per pixel. The one
visible change would be an 8-bit source's histogram combing. In a 16-bit-float compositor (PR-1)
a grade never quantizes a picture, so finer bins would show the SOURCE's depth, not damage done
by the grade. An agent or a proof that needs 10-bit truth already reads `render_frame`'s PNG,
which is 16-bit whenever a source is deep (PR-4), as `curves_proof.py`'s K1 "within a 10-bit
level" does. Measured at 4K, worst of GR-10's five:

| Scope | 256 levels (the tree) | 1,024 levels |
|---|---|---|
| Waveform | 0.448–0.449 ms | 0.460 |
| Histogram (per threadgroup, 16 KB at 1,024) | 0.652–0.680 | 0.728–0.759 |
| Parade, banded, one copy per cell (24 KB at 1,024) | 0.623 (the tree, two copies) | 0.871–0.907 |
| Parade, global atomics | — | 1.172–1.187 (over 1.1) |

In a slower GPU state (seed 2) the 1,024 banded parade took 1.370 ms against the tree's 0.986, and
the tree's own histogram took 1.134 on flat, over GR-10's 1.1 too: GR-10's limit depends on the
GPU's clock state as well ("Found while reading", item 4).

## The standard recipe, file by file, and the tolls

The ledger is `wc -l app/Sources/*.swift core/src/*.rs graphic/src/*.rs | sort -rn`, here at
`3c3ac36` (the brief's §10, 2026-10-14). The cap is ~600 lines, new files 400, and frozen files
take wiring only. Size is per file only (root `CLAUDE.md`): nothing here is a budget on a feature
or a phase.

### Tolls (T4-0, a pure move gated alone)

| File | Lines at `3c3ac36` | Why it is touched | The move |
|---|---|---|---|
| `GradeProps.swift` | 526 | T4-2 and T4-3 both add to the curve types | Its named seam, the curve types (`// MARK: - The curves`) out whole to `CurveProps.swift`. **Paid in T4-0**: 526 → 343, `CurveProps.swift` 184 (below, "T4-0"). Its next named seams: `GradeProps.swift`'s `// MARK: - The wheels` block out whole to `WheelProps.swift`, and `CurveProps.swift`'s `ColorCurvesPatch` out whole to `CurvePatch.swift` should T4-2/T4-3 carry it past ~400 (`designs/adr/app-file-history.md`). |

### The other files the phases touch (`wc -l` at `3c3ac36`; none at the cap)

| Area | Files |
|---|---|
| Scopes (T4-1) | `VectorscopeView` 97, `ScopeSlotView` 216, `ScopesPanelView` 242, `ScopeTraces` 214, `WaveformAnalyzer` 276, `WaveformTap` 189, `AgentServer+Scopes` 72, `AgentCatalog+Render` 275 |
| Curves (T4-2, T4-3) | `CurveTable` 135, `CurveTextures` 98, `CurveEditorView` 398, `VideoPane+Curves` 351 |
| Qualifier (T4-4) | `QualifierProps` 305, `VideoPane+Qualifier` 160, `Compositor+Adjustment` 110 |
| Shared Swift | `LayerUniforms` 305, `Compositor+Uniforms` 160 |
| Core | `model_grade.rs` 271, `grade_check.rs` 108, `actions_curves.rs` 85, `actions_qualifier.rs` 51, `actions_clamp.rs` 287, `recipe.rs` 522, `actions.rs` 541 |

- `recipe.rs` and `actions.rs` take wiring only. Their named seams (the content hash out to
  `recipe_hash.rs`; the per-group JSON writers) are paid only if a phase's wiring would carry them
  past ~600.
- `ProjectSnapshot.swift` (1,523) and `CanvasSessions.swift` (1,090) take wiring only, as in
  tier 2.
- Shaders: `Compositor.metal` (2,336) and `Waveform.metal` (192) are outside the ledger (root
  `CLAUDE.md`'s `wc -l` covers `*.swift` and `*.rs`).

### Core

- **Format 20 (T4-2):** the two hue curve keys. **Format 21 (T4-4):** `qualifier.blur`. Each is
  optional with no migration step, as 16–19 were; each takes main's next number when its code is
  written and renumbers before its merge if main moved first (GR-25).
- T4-1 and T4-3 change no file format.
- No new op, op-table row or tool: `set_video {patch}` carries every key.
  `render_frame {vectorscope_zoom}` is an app-side argument.

### Documents (each phase's own)

Spec §6's `set_video` prose and §7.9a's `render_frame` JSON keys; `app/CLAUDE.md`'s map lines for
the touched files, and its `LayerUniforms` line if the reserved float is spent; the README's
grading bullets; the screens `04b-preview-scopes`, `05g-clip-curves` and `05h-clip-qualifier`;
`docs/manual-checks.md` ("Person checks" below).

## Spec §11: the plan

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies, never a runtime);
PR-1…PR-12; MT-1…MT-9; GR-1; GR-3 (blending stays encoded); GR-6 (the blur FILTER on an
adjustment clip stays refused); GR-10…GR-23, except as amended below.

**Amended now (T4-0), each by an "Amended by" line under the original, never rewriting it:**
- **GR-10** by GR-26: the time bound's fixtures become six (a flat saturated colour added), and
  the counting rule gains "a non-central bin shared by a whole SIMD group is added once".
- **GR-10** by GR-29: "so a 1,024-level scope stays possible" is closed as not wanted.
- **GR-13** by GR-24: its "Not" line's cleanup blur is lifted (T4-4) and its hue curves lifted
  (T4-2). GR-6 is unchanged.
- **GR-13** by GR-28: "no qualifier on picture clips (later issues)" is closed as not wanted.
- `designs/adr/grading-2.md`'s first decision ("The scopes' cost is global atomics…") by GR-26,
  as an Amended-by sub-bullet (`designs/adr/` is not §11, but the line is a record a later reader
  trusts).

**Amended later, each by its own phase before its code** (an Amended-by line, or a new GR entry
from GR-31 on):
- **T4-1:** GR-10's zoom — the bin rule gains the zoom (`bin = 128 + round(255·zoom·c)`), "at
  zoom > 1 an off-plot pixel is not counted", the bound holds at every zoom, the mirror gains
  `vectorscope_zoom` and the JSON's `zoom` and `off_plot`; the zoom's steps, the ticks and the
  argument.
- **T4-2:** GR-12 (the hue domain, the periodic spline, the strip's second row, the step and its
  place after the channel curves; its "Not" line's hue curves and hover readout lifted, and "no ⇧
  axis lock" in its editor rules); GR-4 (Show Ungraded neutralises the hue curves); GR-6 (the
  adjustment pass applies them); GR-7 (the order: the hue curves before the look).
- **T4-2b:** GR-33 (new, from the owner's answer of 2026-10-15 to T4-2's H16): Color's Hue turns
  HSV hue by GR-32's exact shift, + red → yellow → green, Rec. 709 luma kept, the degrees wrapped,
  no chroma guard; Amended-by lines on GR-2 (`grading.md`) and GR-32.
- **T4-3:** GR-12's accepted risk ("switches at its end"), its "Not … resampling" line and its
  inspector write rule, replaced by the blend.
- **T4-4:** GR-13's key (`video.qualifier.blur`, the pass, its cost, Show Selection blurred).

**New, in `designs/spec/11-decisions/grading-4.md`**, each with its README row and the Lines
cells, all recorded in T4-0 before any tier-4 code:
- **GR-24 — Tier 4 builds five extras and closes four.**
- **GR-25 — Tier 4's working arrangement.**
- **GR-26 — A flat saturated colour is GR-10's sixth timed fixture, and the same-bin add.**
- **GR-27 — An Offset wheel is not wanted** (#266).
- **GR-28 — A qualifier on picture clips is not wanted** (#269).
- **GR-29 — 1,024-level scopes are not wanted** (#273).
- **GR-30 — A histogram behind the curve plot is not wanted** (#270's first item).

## Where the work happens (GR-25)

- One worktree, `~/devel/framejob-grading4` on branch `grading-4`, outside the repo folder. Each
  phase: start from main, write the code, `make gate` in the worktree; when it passes, commit and
  merge into main (a fast-forward when main has not moved), then start the next phase from main.
  Nothing is built in or switched in the main tree, which other sessions use.
- Per worktree: `core/target/`, `build/`, `tools/proof/work/`, the generated project. Shared: the
  git objects, and the Debug and Release apps' identities and defaults domains (V-5) — harmless,
  since proofs run under scratch homes and never move defaults.
- **Format numbers**: main's next when a phase's code is written (20 for T4-2 and 21 for T4-4 at
  T4-0), renumbered before a merge if main moved first. **GR IDs** likewise: main's next, renumbered
  before a merge if main moved.
- **No verdict phase**: each phase is kept when its proofs pass.
- **Fixtures**: synthetic; the GRD rows wait for real footage, as they do now.

## Phases

Each phase is one implement-review cycle, gated and merged into main alone, ending with the root
`CLAUDE.md`'s "Verification": targeted tests in the loop, `make gate` once when the code is
complete, the phase's proof recorded whole on Release, mutants about one per new decision (3–8).

| Phase | What lands | Its proof holds |
|---|---|---|
| T4-0 | This road map; `11-decisions/grading-4.md` with GR-24…GR-30, its README rows and Lines cells; the Amended-by lines on GR-10 and GR-13 and tier 2's ADR; the toll: `GradeProps.swift`'s curve types out to `CurveProps.swift` | Renders byte-identical; `make test` unchanged; the Debug catalog equal. No mutants: a pure move adds no decision. |
| T4-1 | **Scopes** (#265, GR-26): the vectorscope's same-bin add; zoom ×1/×2/×4 counted at the zoom, off-plot pixels not counted; rim ticks; the corner cells; `render_frame {vectorscope_zoom}`; GR-10 amended; no format change | A near-grey card spreads ×2 and ×4; off-plot not counted; T1 with six fixtures at every zoom ≤ 1.1 ms; every ×1 trace identical to today's |
| T4-2 | **Hue curves and the editor extras** (#267, #270 (2)(3)): `video.curves.hue_hue`, `.hue_sat`; the strip's second row; `hueCurvesEnabled`; the periodic spline; Hue and Sat cells; the hover readout; ⇧ lock; format 20 | A hue-wheel card moves only its wedge; a grey ramp unchanged; the wrap at 0°; an uncurved layer byte-identical; the ⇧ lock and readout in the probe |
| T4-2b | **Color's Hue by the exact HSV shift** (GR-33, the owner's answer to T4-2's H16): `gradeSample`'s hue calls `gradeHueShift`, wrapped, unguarded; `hueRotate` removed; no core, format or tool change | H16 scored (±40 by colorsys, luma kept), H17 = a constant Hue vs Hue, H18 −500 = −140, H19 a near-grey turned; the control fails H16 H17 H19 on the unchanged tree; Hue 0 byte-identical (N0) |
| T4-3 | **Curves of different counts** (#271): the evaluator's blend for a count mismatch, the recipe's blend form, the strip's blend, the inspector's write rule; no format change | Start and end exact; the halfway strip = the mean of the two; same-count actions byte-identical to T4-2 |
| T4-4 | **The qualifier's cleanup blur** (#268): `video.qualifier.blur`, the q-map pass and its Gaussian, Show Selection blurred; format 21 | A noisy card's selection smoothed; blur 0 byte-identical; `render_frame {selection}` = the blurred q; the adjustment pass's cost recorded |
| T4-5 | **The close**: ADR, archive, `archive/INDEX.md`; #265 #267 #268 #270 #271 closed as built; #266 #269 #273 closed per the choices | — |

### T4-1 — scopes (#265, the solid-colour fix; GR-26)

- **Lands**: the same-bin add first, then the zoom, the rim ticks, the corner cells and
  `render_frame {vectorscope_zoom}` ("Vectorscope zoom" above). Before its code, GR-10 gains its
  zoom amendment (or a new GR entry records the zoom's steps, the ticks and the argument).
- **Proof** (`scopes_proof.py` / `scopes_probe.swift`):
  - **S11**: a near-grey card's Cb and Cr spread is ×2 and ×4 of ×1's, ±1 bin.
  - **S12**: at ×2 a pure red frame counts 0 and reports its off-plot total; at ×1 every trace is
    identical to the T4-0 tree's (counts byte-equal).
  - **S13**: `render_frame {vectorscope_zoom: 4}`'s JSON says its zoom and equals the panel's
    analyser; a 3 is refused by name.
  - **T1** with the sixth fixture (flat saturated red) at ×1, ×2 and ×4, each ≤ 1.1 ms. A note
    for T1 ("Found while reading", item 4): the limit depends on the GPU's clock state, so T1
    might record the GPU's state, or warm it as G2-1's warm burst does.
  - Harness captures, light and dark, at each zoom.
- **Mutants**: `zoom-in-drawing-only` (S11); `off-plot-clamped` (S12, T1 at ×4 on the gradient);
  `same-bin-add-dropped` (T1 on red); `zoom-persisted` (the pick-persisted precedent);
  `render-ignores-zoom` (S13).

### T4-2 — hue curves and the editor extras (#267, #270 (2)(3))

- **Lands**: "Hue curves" and "The curves editor's extras" above, with format 20 (main's next at
  T4-0). Before its code: GR-12's, GR-4's, GR-6's and GR-7's amendments, with the values the brief
  left to this phase ("Not established").
- **Proof** (`curves_proof.py` / `curves_probe.swift`):
  - a hue-wheel card through a Hue vs Hue curve moves only its wedge;
  - Hue vs Sat at 0 greys only its wedge;
  - a grey ramp is unchanged under both (the chroma guard);
  - the wrap: a point at 350° and one at 10° join through 0°;
  - the periodic spline against a Python oracle;
  - row 0 sampled exactly: K1 unchanged, and every existing curves render byte-identical (N0);
  - an unused layer byte-identical, and TC holds;
  - the adjustment pass applies them (J);
  - the refusals by name;
  - the probe's ⇧ lock: a diagonal drag moves one coordinate;
  - the readout's text at three points.
- **Mutants** (seven, one per decision): `hue-wrap-dropped`; `hue-from-graded` (the hue read
  after the shift); `hsv-turn` (an HSV rotation in place of `hueRotate`: a luma row fails);
  `chroma-guard-dropped`; `hue-before-channel-curves`; `row-0-at-centre` (row 0 sampled at 0.5:
  N0 fails); `shift-lock-ignored`.

### T4-3 — curves of different counts (#271)

- **Lands**: "Curves of different point counts" above; no format change. Before its code,
  GR-12's accepted risk, "Not … resampling" and write rule are amended. #271's body is rewritten
  to the blend by the orchestrator.
- **Proof**: `core/tests/curves.rs` — a 3 → 5 action's recipe at the start, the middle and the
  end; the blend form only for a mismatch; every other recipe byte-identical. `curves_proof.py`'s
  A rows and the probe — t = 0 and t = 1 equal the two curves' renders; the halfway render equals
  the mean strip within a 10-bit level; same-count actions byte-identical to T4-2's; the inspector
  writes an added point to the END.
- **Mutants**: `blend-t-inverted`; `same-count-blended` (the A rows fail);
  `mismatch-still-switches`; `blend-written-to-file`.

### T4-4 — the qualifier's cleanup blur (#268)

- **Lands**: "The qualifier's cleanup blur" above, with format 21 (main's next at T4-0). Before
  its code: GR-13's key amendment, with the blur's unit.
- **Proof** (`qualifier_proof.py` / `qualifier_probe.swift`):
  - a noisy card's selection: its variance falls as the blur rises, measured on
    `render_frame {selection}`;
  - the selection equals a scripted Gaussian of the unblurred selection within a bound written
    before measuring;
  - blur 0 byte-identical (N0);
  - a half-quality preview blurs the same share of the picture;
  - the matte's edge is not blurred;
  - TA with the blur on recorded, and the unblurred TA unchanged.
- **Mutants**: `colour-blurred-not-q`; `sigma-not-scaled`; `selection-shows-unblurred`;
  `blur-zero-breaks-pass` (TA, or N0's bytes); `coverage-blurred`.

### T4-5 — the close

`designs/adr/grading-4.md`; this road map `git mv`'d to `archive/`, with its `archive/INDEX.md`
row; root `CLAUDE.md`'s ADR list. The issues closed per the choices, each closing comment naming
its GR entry: #265, #267, #268, #270 and #271 as built; #266, #269 and #273 as not wanted.

## Person checks

No new row: each phase extends the tier-2 row for its tool in `docs/manual-checks.md`, in the
change that creates the check. No footage is needed from the owner: every proof row is
synthetic, and the GRD rows wait for real footage as they do now.
- **GRD-11** (T4-1) gains: the vectorscope at ×2 and ×4 on a face and a grey card, and the rim
  ticks' legibility; and a solid-colour slide playing smoothly with the vectorscope shown (the
  GPU time is T1's; the smoothness is a person's).
- **GRD-13** (T4-2, T4-3) gains: a sky turned toward cyan with Hue vs Hue, one colour muted with
  Hue vs Sat, the hover readout and ⇧ lock by hand, and an action between a 3-point and a 5-point
  curve easing smoothly.
- **GRD-14** (T4-4) gains: the blur cleaning a skin pick on noisy footage, and playback with it
  on at 4K.

## Costs: recorded, measured, reasoned

### Recorded in the repo

- A heavy 4K frame's compositor average: 7.38–7.585 ms against the 8 ms budget (precision).
- GR-10's bound: 1.1 ms of GPU per scope per analysed 4K frame, over five fixtures (six from
  T4-1, GR-26).
- Tier 2 measured the wheels at +0.000–0.002 ms at 4K.

### Measured for the brief (its scratch spike, gitignored)

These are the brief's figures, quoted with its commands; this road map ran none of them.

**Host:** Apple M2 Max (`sysctl machdep.cpu.brand_string`), macOS 26.5.1 (25F80); `pmset -g`:
`powermode 0`; `pmset -g batt`: AC power, charged; read before the runs, 2026-10-14 21:59–22:03
EDT. **The host was heavily loaded:** `vm.loadavg` 25.6–72.9 across the runs, with other
sessions' Rasterize builds and two Rasterize apps running, one GPU-heavy. The GPU changed clock
state between sessions (the blur's two columns; scopes seed 2 against seeds 1, 3, 4). Only
differences between variants timed in the same rounds are read. Each variant is shuffled per
frame, the first five frames are dropped, and each figure is the median of three runs' medians.

**Folder:** `~/devel/framejob/tools/proof/work/grading-tier4-spike/` (gitignored, in the main
tree). `results.txt` lists the build keys and commands, and `*-host.txt` the load before and
after each run.

**The instrument, `bench.swift`**: a scratch Metal bench. The 256-level scope rows compile the
tree's own `app/Resources/Shaders/Waveform.metal` at runtime; every other kernel is scratch, NOT
the compositor's.
- Build: `python3 -c "import sys; sys.path.insert(0,'tools/proof'); import swift_build;
  print(swift_build.build(sources=['tools/proof/work/grading-tier4-spike/bench.swift'],
  output='tools/proof/work/grading-tier4-spike/bench', optimize=True))"`.
- Keys: `b02297bfd7ca0a83` (the first passes session, without the half-resolution row; its JSON
  was overwritten, and its figures were copied from the terminal into the blur's table);
  `71241f72a6137193` (passes seeds 1–3 and scopes seeds 1–2); `177ab716c031fa26` (scopes seeds
  3–4, with the same-bin rows, after a counting bug in them was fixed and the counts verified).
- **`./bench --mode passes --frames 60 --runs 3 --seed S --sizes all`**
  (`passes-seed{1,2,3}.json`):
  - L0: a full-frame layer drawn into an `rgba16Float` target. A0: L0 then an adjustment-like
    pass with GR-13's qualifier inline (`[[color(0)]]`). AH: A0 with a hue-vs-hue and hue-vs-sat
    step through a 1,024 × 2 strip. B0: L0, suspend, a q map into `r16Float`, resume, the
    adjustment reading q. B2, B8, B24: B0 plus `MPSImageGaussianBlur` at σ 2, 8, 24. B8h: the q
    map at half size, σ 4.
  - Session 2's 4K deltas over A0, seeds 1/2/3: AH +0.023 / +0.018 / +0.012; B0 +0.266 / +0.261 /
    +0.254; B2 +0.650 / +0.649 / +0.645; B8 +0.491 / +0.490 / +0.501; B24 +0.461 / +0.458 /
    +0.452; B8h +0.239 / +0.236 / +0.234.
  - Session 1's 4K (two seeds): A0 0.58; B0 0.959; B2 1.961 / 1.985; B8 1.618 / 1.627; B24
    1.507 / 1.522; AH 0.806 / 0.805. Its 1080p (seed 1): A0 0.163, B0 0.255, B2 0.520, B8 0.459,
    B24 0.443, AH 0.220.
- **`./bench --mode scopes --waveform app/Resources/Shaders/Waveform.metal --frames 30 --runs 3
  --seed S`** (4K only, `scopes-seed{1,2,3,4}.json`):
  - Fixtures: GR-10's five (flat 0.5, the `x % 256` ramp, near-grey ±5/255, the red-across
    green-down gradient, RGB noise) plus flat (0.8, 0.1, 0.1).
  - Variants: the tree's four kernels; a 1,024-level waveform, histogram, banded one-copy parade
    and global parade; a one-copy 256 parade (control); the vectorscope at ×1, ×2 and ×4 clamped
    or dropping off-plot pixels; the same-bin add at ×1 and at ×4 drop.
  - The zoom's and the 1,024 levels' tables above are seeds 3 and 4. Seed 1 lies within 0.06 ms
    of seeds 3–4 on every common row except the ramp's 1,024 banded parade (0.798 against
    0.594–0.639); its ramp column ran high throughout, and no worst-of-five changes. Seed 2 is
    the slower state.
  - Each vectorscope total was checked: 8,294,400 for every non-dropping variant; the dropping
    ones as "Vectorscope zoom" says.
- **`python3 -I zoom_bins.py`** (`zoom-bins.txt`): the zoom's spread table.
- **`python3 -I curves_resample.py --pairs 1000 --seed 1`** (`curves-resample.txt`): a port of
  `CurveTable.swift`'s Fritsch–Carlson; random curves with ends at x 0 and 1, interior x's at
  least 0.02 apart, "rising" or "any" y; the resampling table above, plus the "any" rows.

### Reasoned from those

- Every GPU figure is a scratch dispatch on one loaded M2 Max; each phase measures its own pass
  in the app (T1, TC, TA), as tiers 2 and 3 did.

## Not established

- **Other editors' behaviour** is general knowledge, not checked against the products.
- **The app's own passes were not timed.** The 256-level scope rows ran the tree's own kernel
  source with the app's dispatch shape, outside the app. Each phase measures its pass in the app
  (T1, TC, TA).
- **Whether the 7.3 ms vectorscope case shows as dropped preview frames.** The tap is latest-wins
  off the render queue, but shares the GPU. GRD-11's added step is the person's half.
- **Whether `MPSImageGaussianBlur` on `r16Float` is the format T4-4 uses.** The bench used it;
  the shadow uses the working format, `rgba16Float`, whose cost was not measured here.
- **The hue curves' shift range, gain range and the picker's labels** — T4-2's spec settles them,
  from the proposals the owner accepted with choice 5a: a shift of −180…180° (0 = none), a gain of
  0…2 (1 = none), the cells "Hue" and "Sat".
- **The blur's unit** — T4-4's spec settles it, from the proposal the owner accepted with choice
  6a: a 0…1 amount like the blur filter's, mapped to a Gaussian σ in canvas pixels, divided by
  `canvasPerDest`.
- **Whether the periodic Fritsch–Carlson variant is the best feel for hue curves.** Its
  no-overshoot property is the reason, and GRD-13 judges the feel.

## Found while reading

The brief's §14, each with where it is handled:

1. **The vectorscope's flat-saturated-colour time**: `framejob_vectorscope_bin` takes 7.29–7.33
   ms per 4K frame on a flat (0.8, 0.1, 0.1) frame, against GR-10's 1.1 ms; GR-10's T1 fixtures
   lack the case; reachable with View ▸ Scopes over any solid-colour slide or title and through
   `render_frame {vectorscope}`; the fix measured at 0.281–0.282 ms. **Handled by T4-1 and GR-26**
   (recorded now, its code T4-1's first change; until then the shipped kernel misses the bound on
   that fixture, an accepted one-phase gap).
2. **#268's "GR-6 … change[s]"** is not so: the blur filter's refusal is untouched by a blur of q.
   **Handled here** ("Tier 4 as answered") and in GR-24.
3. **#271's proposed design is measured to jump at the action's start.** **The orchestrator's, at
   T4-3**: the issue's body is rewritten to the blend.
4. **GR-10's limit depends on the GPU's clock state.** In the slower state the tree's own
   histogram measured 1.134 ms on flat (seed 2), over 1.1, where T1 recorded 0.668. T1 records
   host and power; it might also record the GPU's state, or warm it as G2-1's warm burst does.
   **A note for T4-1's T1**, not a defect.

## The Concat rule

**Concat (`~/devel/Concat`) is AGPL-3.0-or-later. None of its code, shaders, chains or colour
tables may be carried over** (root `CLAUDE.md`; `designs/adr/effects-survey.md`), at design time
and build time. The brief consulted nothing of Concat, and neither did this road map. The sources
instead: the Rec. 709 Y′CbCr matrix (ITU-R BT.709-6) for the vectorscope and its targets;
Fritsch and Carlson (1980) for the spline, wrapped for the hue curves; the HSV hue and smoothstep
of GR-13 for the hue read and its guard; Color's own `hueRotate` and Saturation for the turn and
the gain; a Gaussian (Apple's `MPSImageGaussianBlur`) for the selection's blur. Every fixture is
written by a script.

## T4-0 — the road map, GR-24…GR-30 and the move

**What landed** (2026-10-14, in the worktree on `grading-4`, from `3c3ac36`). This road map;
`designs/spec/11-decisions/grading-4.md` with GR-24…GR-30, its Files row and seven ID rows in
`11-decisions/README.md`, and the Lines cells; two "Amended by" lines at the end of GR-10 (GR-26,
GR-29) and two at the end of GR-13 (GR-24, GR-28) in `grading-2.md`, and "— amended by GR-26,
amended by GR-29" / "— amended by GR-24, amended by GR-28" on their index rows; one Amended-by
sub-bullet (GR-26) under `designs/adr/grading-2.md`'s first decision, and its Swift line naming
`CurveProps.swift`; spec §7.4's Clip-inspector row naming `CurveProps.swift`;
`ProjectSnapshot.swift`'s `curves` doc comment naming `CurveProps.swift`; and one pure move, gated
alone with no tier-4 code and no behaviour change. The moved block was diffed against `git show
HEAD:app/Sources/GradeProps.swift` (lines 345–526): identical, and the kept part against its
lines 1–343: identical.

| Move | `wc -l` before → after | New file | What widened |
|---|---|---|---|
| `GradeProps.swift` → `CurveProps.swift`: `// MARK: - The curves (spec §11 GR-12, grading-2 G2-3)` through the `apply(curves:)` extension's closing brace (`CurvePoint`, `CurveChannel`, `ColorCurves`, `ColorCurvesPatch`, `LayerUniforms.apply(curves:)`), with `import AppKit` and nothing else; the blank line before it went too | 526 → 343 | 184 | nothing (every moved type and member keeps its access; `KeyedDecodingContainer.lenient`/`.nullable`, `DS.textStrong` and `ParadeView.tints` were already internal; `CurveEditorView.swift`, `CurveTable.swift`, `CurveTextures.swift`, `FrameRecipe.swift`, `InspectorBinding+Writes.swift`, `OpDictionaries.swift`, `ProjectSnapshot.swift`, `TypedPatches.swift`, `VideoPane+Curves.swift` and `tools/proof/curves_probe.swift` compile unchanged) |

No proof anchor lay inside the moved block (`tone_proof.py:157` and `wheels_proof.py:191` anchor
`GradeProps.swift`'s tone and wheel lines, which stay), and no comment was edited but
`ProjectSnapshot.swift`'s `curves` doc. `designs/adr/app-file-history.md` ("Named next cuts")
records the move and names the next seams: `GradeProps.swift`'s `// MARK: - The wheels` block out
whole to `WheelProps.swift`, and `CurveProps.swift`'s `ColorCurvesPatch` out whole to
`CurvePatch.swift` should T4-2/T4-3 carry it past ~400.

**Verification**, 2026-10-14 (`pmset -g ps` at the orchestrator's review: "Now drawing from 'AC Power'"):
- Controls from the untouched worktree before any edit, never by stashing: `make app-debug`
  (BUILD SUCCEEDED), its `agent-catalog.json` copied to `tools/proof/work/t4-0/catalog-before.json`;
  `make app` (BUILD SUCCEEDED); `RC_PROOF_APP=release python3 tools/proof/curves_proof.py capture
  tools/proof/work/t4-0/ctl`: exit 0, 7 uncurved frames captured (`card-adjusted`, `card-toned`,
  `card-wheeled`, `card`, `movie`, `ramp-looked`, `ramp`), Z1 no `Frame Job: ` line
  (`tools/proof/work/t4-0/control-curves-capture.txt`).
- After the move: `make typecheck` exit 0, 0 errors, exactly the 4 baseline warnings; `diff <(git
  show HEAD:app/Sources/GradeProps.swift | sed -n '345,526p') <(sed -n '3,$p'
  app/Sources/CurveProps.swift)` exit 0; `diff <(git show HEAD:app/Sources/GradeProps.swift | sed
  -n '1,343p') app/Sources/GradeProps.swift` exit 0.
- `python3 tools/proof/spec_index_proof.py` after the last doc edit: 162/162. The cells:
  `grading-2.md` 391 → 402, `grading-4.md` new at 82, and the spec README's `11-decisions/` cell
  8062 in 21 files → 8163 in 22. `python3 tools/proof/name_residue.py`: exit 0.
- `make app-debug` (BUILD SUCCEEDED), then `python3 -c "import json,sys; a,b=(json.load(open(p))
  for p in sys.argv[1:]); sys.exit(a!=b)" tools/proof/work/t4-0/catalog-before.json
  "build/Build/Products/Debug/Frame Job Debug.app/Contents/Resources/agent-catalog.json"`: exit 0,
  the parsed catalogs equal (97 tools).
- `make gate`: PASS in 364 s (names 1 s, typecheck 7 s, fmt 4 s, lint 31 s, test 223 s, app 98 s,
  with D25 and D26 ok). The cargo suites passed 1,388 tests in 121 result lines and failed none;
  `spec_index_proof.py` 162/162 among its proof steps. No test file was added or removed.
- On the gate's Release build: `RC_PROOF_APP=release python3 tools/proof/curves_proof.py compare
  tools/proof/work/t4-0/ctl`: exit 0, 29/29, N0 the seven curve-less frames byte-identical (16
  bits a channel) to the control, P1–P11 (the probe over `app/Sources`, now compiling
  `CurveProps.swift`) ok, Z1 no `Frame Job: ` line
  (`tools/proof/work/t4-0/after-curves-compare-release.txt`). No `DEFAULTS MOVED` in either
  curves run or the gate's test log.
- No mutants: a pure move adds no decision.

**Owed.** The `app/CLAUDE.md` edits (applied by the orchestrator): lines 33–35 (from
"`LayerUniforms.apply(wheels:)` (GR-11), and the curves' …" to "… `LayerUniforms.apply(curves:)`
(GR-12); `VideoPatch.qualifier` is") become

```
  `LayerUniforms.apply(wheels:)` (GR-11)); `VideoPatch.curves` is
  `CurveProps.swift`'s `ColorCurvesPatch`, beside `CurvePoint`,
  `CurveChannel`, `ColorCurves` and `LayerUniforms.apply(curves:)` (GR-12; a
  pure move out of `GradeProps.swift`, grading-4 T4-0); `VideoPatch.qualifier` is
```

and, since the new text closes the "(`GradeProps.swift`, which holds …" parenthesis at
"(GR-11))", line 37's `` `QualifierUniforms` and the pick's `QualifierSample` (GR-13)), so a row
writes `` loses one ")" (`` (GR-13), so a row writes ``); line 112's
`` · `GradeProps.swift` — `` becomes `` · `GradeProps.swift` · `CurveProps.swift` — ``. All three
applied by the orchestrator. T4-1 (scopes, GR-26) is next, from main after this phase's merge.

**Review.** One lc-reviewer pass, verdict pass: no blockers, no should-fixes. Two nits, both
applied by the orchestrator: this record's Verification line now cites a printed `pmset -g ps`
line instead of an unrecorded power claim, and the `names` gate step re-ran after this file's last
edit. The adversary raised no objection; its one note (the extra ")" the owed `app/CLAUDE.md`
text leaves on line 37) was carried into the owed edit.

## T4-1 — scopes: the same-bin add and the vectorscope zoom

**What landed** (2026-10-14, in the worktree on `grading-4`, from `31f3aa1`). GR-31 in
`designs/spec/11-decisions/grading-4.md`, written before any code, with its index row, the
"Amended by GR-31" line under GR-10 in `grading-2.md` and ", amended by GR-31" on GR-10's index row;
then:
- **The kernel** (`Waveform.metal`): `framejob_vectorscope_bin` takes `constant uint &zoom
  [[buffer(1)]]`. `chromaBins(rgb, zoom)` branches on the uniform: ×1 keeps GR-10's clamped
  `int2(round(255.0 * c))` verbatim, ×2 and ×4 bin `int2(round(255.0 * float(zoom) * c))`
  unclamped, and the kernel drops a pixel whose bin is off 0…255. GR-26's same-bin add: a lane
  with a non-central bin carries it (else a `kNoBin` sentinel: off the frame, off the plot or
  counted in the centre), and outside the in-frame branch `simd_broadcast_first`, `simd_sum` and
  `simd_all` add a SIMD group's shared bin once; the central 64 × 64 threadgroup path is
  unchanged. The waveform, parade and histogram kernels are untouched.
- **Swift**: `ScopePass` (a kind and, for the vectorscope, its zoom) in `ScopeTraces.swift`;
  `VectorscopeTrace` gains `zoom`, `offPlot`, `zooms`, `bin(_:zoom:)`, `targetBins`,
  `offPlotPercent` and the JSON's `zoom`, `off_plot` and null off-plot `targets`;
  `WaveformAnalyzer`'s `encode`, `trace` and `analyze` are pass-keyed (the zoom a `setBytes` at
  index 1 for a vectorscope pass), the kind-keyed forms kept as ×1 wrappers (`byKind`);
  `WaveformTaps` carries passes (`attach(key:passes:)`, `attachedPasses`; the kind forms kept);
  `VectorscopeView` draws an off-plot target as a 6 pt rim tick and hosts
  `VectorscopeZoomCells`; `ScopeSlotView` holds `zoom`, `onZoom` and `pass` (its dev-tools
  snapshot part `scopes.<slot>.zoom`); `ScopesPanelView` gains `zoom(_:slot:)`, `shownPasses` and
  a pass-keyed `show`. `render_frame {vectorscope_zoom}` (`AgentServer+Render.swift`,
  `writeScopes` in `AgentServer+Scopes.swift`, the catalog row in `AgentCatalog+Render.swift`).
- **No** core, FFI, op, format or tool-count change; no file at the cap (`wc -l` after:
  `ScopeTraces.swift` 269, `WaveformAnalyzer.swift` 312, `WaveformTap.swift` 207,
  `VectorscopeView.swift` 236, `ScopeSlotView.swift` 244, `ScopesPanelView.swift` 264,
  `AgentServer+Render.swift` 310, `AgentServer+Scopes.swift` 81, `AgentCatalog+Render.swift` 286).
- **Instruments**: `scopes_probe.swift` (the sixth fixture; S6 at ×2 and ×4 against a CPU count;
  S11, S12, S14; T1's ×2 and ×4 variants; T3; T2 and T3 share one `forcedGlobal` helper);
  `scopes_proof.py` (rows S11–S14, T3, H4; five mutants; `vectorscope-global` now T3's;
  `tap-first-kind-only` re-anchored on `analyzer.encode(passes, frame: texture, into: buffer)`);
  the harness's `topzoom=`/`bottomzoom=`, pass-keyed `rampTraces` (a vectorscope trace per zoom,
  its lines stopping at the plot's edge) and `seeing cells`.
- **Documents**: spec §4.2's Vectorscope paragraph, §7.9a's `render_frame`, the spec index's
  Lines cells, the README's Scopes bullet, the screen catalog's 04b prose, GRD-11's two added
  steps, and `tools/proof/README.md`'s scopes section.

**Deviation from the spec, recorded**: S6's tie band sits at the plot's two real edges,
`255·zoom·c` = 127.5 and −128.5 (`128 + round(v)` leaves 0…255 past them; round halves away from
zero), not "±127.5".

**Verification** (2026-10-14, M2 Max; `pmset -g` as T1 printed it: "powermode 0 | Now drawing
from 'AC Power'"; `vm.loadavg` 49.56 40.71 26.34 before the recorded run: other sessions' builds
were running):
- In the loop: `make typecheck` exit 0, 0 errors, the 4 baseline warnings;
  `swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS` of `scopes_probe.swift` and
  `waveform_probe.swift` exit 0; `make app-debug` BUILD SUCCEEDED; `scopes_proof.py --only
  S1,S2,S6,S11,S12,S13,S14,T1,T2,T3,M1,M3` on Debug: 10/12 (S14 FAILED: the app's shared tap has
  no analyser in a probe, so the instrument now drives a tap over the probe's own; T3 FAILED, see
  below); then `--only S14,T3` 2/2; `--only H1,H2,H3,H4` 4/4. `spec_index_proof.py` 162/162,
  `name_residue.py` exit 0.
- `make gate`: PASS in 263 s (names 1 s, typecheck 6 s, fmt and lint skipped as unchanged, test
  124 s, app 131 s with D25 and D26 ok); the test log has 121 `test result: ok` lines and no
  FAILED, and `spec_index_proof.py` 162/162 among its proof steps.
- Recorded, on the gate's Release build: `RC_PROOF_APP=release python3
  tools/proof/scopes_proof.py`: exit 0, **26/26**, Z1 no `Frame Job: ` line, no `DEFAULTS MOVED`.
  S13: `off_plot` 147960 against this script's 147960, every target null, the refusals
  "render_frame: vectorscope_zoom must be 1, 2 or 4 (got 3)." and "render_frame:
  vectorscope_zoom needs vectorscope: true." H4: the cells at [1073, 288, 46, 16] in a
  [899, 84, 224, 224] square, light and dark, each zoom byte-identical twice and unlike ×1.
- `RC_PROOF_APP=release python3 tools/proof/seeing_proof.py --only P1,…,P7`: exit 0, 7/7 (the
  tap's kind wrapper, `waveform_probe.swift`).

**T1 at 4K, the recorded run** (ms; GR-26's six fixtures, flat · flat-red · gradient · near-grey
· noise · ramp):

| Pass | flat | flat-red | gradient | near-grey | noise | ramp | worst |
|---|---|---|---|---|---|---|---|
| vectorscope ×1 | 0.322 | 0.357 | 0.400 | 0.407 | 0.417 | 0.452 | 0.452 |
| vectorscope ×2 | 0.319 | 0.332 | 0.318 | 0.401 | 0.320 | 0.394 | 0.401 |
| vectorscope ×4 | 0.320 | 0.332 | 0.278 | 0.354 | 0.313 | 0.356 | 0.356 |
| parade | 0.445 | 0.628 | 0.438 | 0.688 | 0.624 | 0.675 | 0.688 |
| histogram | 0.668 | 0.563 | 0.374 | 0.216 | 0.189 | 0.194 | 0.668 |

The flat saturated red, 7.29–7.33 ms in the brief's bench on the shipped kernel, is 0.357 ms at
×1 in the app's pass. T2 (flat): banded 0.442, global 1.150, ratio 0.385.

**T3, and its bound.** The tree's ×1 vectorscope against its `bool central = false;` twin, on
the six 4K fixtures, scored on the one where the forced-global build is slowest. Before the
review, three runs on the tree against the then-shared 0.75 bound:

| Run | load (`vm.loadavg`) | slowest forced-global fixture | tree | global | ratio | row at 0.75 |
|---|---|---|---|---|---|---|
| Debug loop, first | not recorded (the ruling: about 50) | near-grey | 0.455 | 0.571 | 0.796 | FAILED |
| Debug loop, `--only S14,T3` | not recorded (the ruling: about 50) | near-grey | 0.408 | 0.578 | 0.706 | ok |
| Release, first recorded | 49.56 40.71 26.34 | near-grey | 0.411 | 0.578 | 0.712 | ok |

A row that fails one run in three on the unchanged tree is a flaky instrument, so the
orchestrator's ruling (2026-10-15) gave T3 its own bound, **0.85** (`T3_RATIO_MAX` in
`scopes_proof.py`; T2 keeps 0.75): under the `vectorscope-global` mutant the two builds are the
same shader, so its ratio is 1.0 by construction and only its noise spreads it, while the tree
measured 0.706–0.796 under heavy load; 0.85 sits between them with margin on both sides. It is
not moved again without a new measurement. After the change (fix pass 1, 2026-10-15, after a
`make app-debug` the stale-app refusal asked for):

| Run | load (`vm.loadavg`) before | slowest forced-global fixture | tree | global | ratio | row at 0.85 |
|---|---|---|---|---|---|---|
| Debug `--only T3`, 1 | 6.48 18.55 27.48 | near-grey | 0.411 | 0.532 | 0.772 | ok |
| Debug `--only T3`, 2 | 5.24 16.14 26.02 | near-grey | 0.411 | 0.567 | 0.725 | ok |
| Debug `--only T3`, 3 | 24.86 19.54 26.55 | near-grey | 0.412 | 0.579 | 0.712 | ok |
| `--mutant vectorscope-global` | 22.45 20.25 26.36 | near-grey | 0.645 | 0.532 | 1.213 | FAILED: MUTANT PASS (21/22, T3 alone) |
| Release, recorded (repeat) | 21.55 25.37 27.91 | near-grey | 0.412 | 0.577 | 0.713 | ok, run 26/26 |

The repeated recorded run (`RC_PROOF_APP=release python3 tools/proof/scopes_proof.py`, after
the fix pass's `make gate`): exit 0, **26/26**, Z1 no `Frame Job: ` line, no `DEFAULTS MOVED`;
T1's worst 4K figures parade 0.625 (noise), vectorscope ×1 0.420 (noise), ×2 0.353 (noise), ×4
0.321 (flat), histogram 0.667 (flat); T2 (flat-red) banded 0.634, global 1.154, ratio 0.549.

In the first recorded run the forced-global vectorscope was FASTER than the tree's on four
fixtures (flat 0.273 against 0.325, flat-red 0.383 / 0.411, noise 0.310 / 0.366, ramp 0.383 /
0.457) and slower only on near-grey and the gradient; the repeat agrees (flat 0.386 / 0.541,
noise 0.348 / 0.476, ramp 0.457 / 0.712, near-grey 0.577 / 0.412).

**Mutants** (`python3 tools/proof/scopes_proof.py --mutant NAME`, each on its own tree copy's
Debug build, bounded; the five new and the three the spec named, once at the end):

| Mutant | Must fail | Answer |
|---|---|---|
| `zoom-in-drawing-only` | S11 S12 S13 | MUTANT PASS (S6 tolerated, failed) |
| `off-plot-clamped` | S6 S12 S13 | MUTANT PASS (T1 tolerated, passed) |
| `same-bin-add-dropped` | T1 | MUTANT PASS (T3 tolerated, failed: flat-red 7.172 tree / 7.248 global, ratio 0.99; T1's ×1 flat-red 7.166 ms) |
| `zoom-persisted` | S14 | MUTANT PASS |
| `render-ignores-zoom` | S13 | MUTANT PASS |
| `bins-edged` | S1 S2 | MUTANT PASS (S11 and S12 tolerated, both failed: ×1's extent 9 bins against ×2's 20) |
| `tap-first-kind-only` (re-anchored) | S7 S8 | MUTANT PASS (S14 tolerated, failed) |
| `vectorscope-global` | T3 | MUTANT PASS (T1 tolerated, passed) |

`same-bin-add-dropped` and `bins-edged` first answered MUTANT FAILURE, each for a row its edit
fails by construction (T3; S11); both were added to `TOLERATED` with their reasons and the two
re-run. The other eight old mutants (`cb-cr-swapped`, `bt601`, `histogram-global`,
`histogram-luma-601`, `pick-persisted`, `slots-not-shrunk`, `parade-band-misplaced`,
`parade-global`) were not re-run; S12 is tolerated for the ×1-counting ones by reasoning, unrun.

**Owed.**
- The `app/CLAUDE.md` edits (the orchestrator's): the scopes entry, lines 1172–1184 (from
  "- `WaveformAnalyzer.swift` (the four scopes' GPU passes over" to "`HistogramView.swift` (the
  slot bodies) ·"), becomes

```
- `WaveformAnalyzer.swift` (the four scopes' GPU passes over
  `Resources/Shaders/Waveform.metal`: waveform, parade, vectorscope, histogram;
  `WaveformTrace`; pass-keyed, the kind-keyed forms ×1 wrappers) ·
  `ScopeTraces.swift` (`ScopeKind`, `ScopePass` — a kind and, for the
  vectorscope, its zoom, spec §11 GR-31 — `ParadeTrace`, `VectorscopeTrace`
  with its zoom and off-plot count, `HistogramTrace`, `ScopeTrace`, their
  JSON; spec §11 GR-10) · `WaveformTap.swift` (`WaveformTaps`:
  `Compositor.serve` offers each composed frame by recipe key; one command
  buffer per frame for the shown passes, not kinds, so two vectorscope zooms
  are two passes; one pass in flight per key and one pending slot the newest
  frame replaces) · `ScopesPanelView.swift` (View ▸ Scopes' panel: two slots
  with pickers, the shrink-to-fit layout and its 360 pt floor,
  `zoom(_:slot:)`, `UngradedTagView`, `SelectionTagView`) ·
  `ScopeSlotView.swift` (a slot: the picker, the caption, the body and its
  readouts, and the vectorscope's zoom, kept across a pick away and back) ·
  `WaveformTraceView.swift` · `ParadeView.swift` · `VectorscopeView.swift`
  (its rim ticks, and `VectorscopeZoomCells`, the "1× 2× 4×" cells) ·
  `HistogramView.swift` (the slot bodies) ·
```

  and the Agent-parity rule's lines 2518–2519, from "Scopes panel and its slot picks (spec §11
  GR-4, GR-5, GR-10;" to "is the capability), the export queue, the", become

```
Scopes panel and its slot picks and zooms (spec §11 GR-4, GR-5, GR-10, GR-31;
`render_frame {ungraded, waveform, parade, vectorscope, vectorscope_zoom,
histogram}` is the capability), the export queue, the
```
- GRD-11's two added steps (the zoom on a face and a grey card, the ticks' legibility; a
  solid-colour slide playing with the vectorscope shown) are the owner's, before the release.

**Residue** (for the orchestrator to file; not this phase's, by the ruling).
- Whether the vectorscope's central 64 × 64 threadgroup path still pays for itself now that
  GR-26's same-bin add makes flat frames cheap: in both recorded runs the forced-global build
  was faster on flat, noise and ramp (and on flat-red in the first), the tree faster only on
  near-grey (tree 0.411 against global 0.578, then 0.412 against 0.577) and, in the first
  run, slightly on the gradient; every figure is well under GR-10's 1.1 ms (T1's worst
  vectorscope ×1 at 4K 0.452 and 0.420). Filed as #296.
- `designs/spec/07.9a-agent-tools.md` at 572 lines (562 before), past the spec README's ~500-line
  split threshold. Filed as #297.

**Review.** Two lc-reviewer passes. The first: fix-required, two should-fixes (T3 still scored
at 0.75 against the orchestrator's 0.85 ruling, and this record still calling the bound
unmoved) and two nits; fix pass 1 closed all four. The second: pass, two nits (the proof
README's T3 paragraph now states its 0.85 bound; this Residue's near-grey pairs say which is
the tree's), both applied by the orchestrator with the owed `app/CLAUDE.md` edits above.

## T4-2 — hue curves and the curve editor's extras

**What landed** (2026-10-15, in the worktree on `grading-4`, from `a8ef6fd`). First the control:
`curves_proof.py`'s N0 gained four tone-curved frames (M1's card, J1's adjustment clip, K1's
ramp, X1's movie) and `RC_PROOF_APP=release python3 tools/proof/curves_proof.py capture
tools/proof/work/t4-2/ctl` took all eleven on `make app` of the untouched product (exit 0, Z1
ok). Then GR-32 in `designs/spec/11-decisions/grading-4.md`, written before any code, with its
index row and the "Amended by GR-32" lines under GR-2, GR-4, GR-6 and GR-7 (`grading.md`) and
GR-12 (`grading-2.md`); then:
- **Core** (format 20): `model_grade.rs` gains `CurveDomain` (`Tone`, `HueShift`, `HueGain`:
  identity, neutral, value range), `HUE_SHIFT_MAX`, `HUE_GAIN_MAX`, `IDENTITY_HUE_SHIFT`,
  `IDENTITY_HUE_GAIN`, `Curves.hue_hue` / `.hue_sat` with their serde skip functions, and
  domain-aware `named()`, `named_mut()`, `is_identity()` and `drop_identities()`;
  `grade_check.rs`'s `check_curves` refuses a hue x outside 0 ≤ x < 360 and a value outside its
  domain; `actions_clamp.rs` clamps per domain (x to 0…360, a last x of 360 removes the channel);
  `actions_curves.rs` writes six and aligns a hue identity on the other's x's at the neutral;
  `RC_FORMAT_VERSION` 20 in `format.rs` and the header. No op, op-table row, tool or FFI export.
- **Swift**: `CurveProps.swift` (`CurveDomain`, six `CurveChannel`s with "Hue" and "Sat",
  `ColorCurves.hueHue` / `.hueSat`, `toneIsIdentity`, `hueIsIdentity`, `ColorCurvesPatch`'s two,
  `apply(curves:)` setting both flags); `CurveTable.swift` (the periodic spline,
  `periodicTangents`, `Spline(_:domain:)`, the strip's second row); `CurveTextures.swift`
  (1,024 × 2, the 2 × 2 placeholder, `upload(height:)`); `LayerUniforms.swift`
  (`gradeReserved0` → `hueCurvesEnabled`); both placeholder fallbacks zero both flags;
  `Compositor.metal` (`hsvHue`, shared with `qualifierWeight`; `gradeCurves` at y 0.25;
  `gradeHueShift`, `gradeHueCurves`; the gate's sum; the layer stage and the adjustment pass;
  the order-of-operations comment); `CurvePlotDecor.swift` (new: the hue grid, the spectrum
  strip, the readout); `CurveEditorView.swift` (model units per domain, the hue plot over its
  strip, the ⇧ lock, the hover readout); `VideoPane+Curves.swift` (`CurvePointField` with one
  `OptionFieldControl` per domain, `CurveAxis`, six cells, `curvesReset` per domain);
  `InspectorBinding+Writes.swift` (the END/BASE rule per domain);
  `AgentCatalog+Properties.swift`'s `curvesClause`.
- **Sizes** (`wc -l` after): `CurveEditorView.swift` 531, `CurvePlotDecor.swift` 107,
  `CurveProps.swift` 322 (no `CurvePatch.swift` move needed), `CurveTable.swift` 242,
  `CurveTextures.swift` 103, `VideoPane+Curves.swift` 392, `InspectorBinding+Writes.swift` 303,
  `LayerUniforms.swift` 307, `CompositorEffects.swift` 449, `Compositor+Adjustment.swift` 113,
  `AgentCatalog+Properties.swift` 320; `model_grade.rs` 377, `grade_check.rs` 119,
  `actions_curves.rs` 91, `actions_clamp.rs` 293, `model_props.rs` 551 (+1), `format.rs` 499.
- **Instruments**: `curves_proof.py` H1–H16 (H16 a RECORD) over a 720 × 120 hue sweep and three
  small cards, N0's four new frames, nine mutants; `curves_probe.swift` P7 amended, P12–P19;
  `core/tests/hue_curves.rs` and `schema_v20.rs` (new), `schema_v19.rs`'s pin a `const`
  assertion, `curves.rs`, `ungraded.rs` (its adjustment clip also carries a hue curve) and
  `schema_v8.rs` at six channels. Moved by the rename of the block's last float:
  `wheels_probe.swift` P3 and `grading_spike/tree_bench.swift` (and its README line).
- **Documents**: spec §5.2 (format 20), §5.4, §7.3, §7.5, §7.9a, §4.3a, §7.10, §7.4 and the spec
  index's Lines cells; the screen catalog's 05g prose; GRD-13's steps 9–11; the README's Curves
  bullet; `tools/proof/README.md`'s G2-3 section.

**Deviations from the spec, recorded.**
- P19 failed at 11 pt ("Master" 37.9 pt in a 38 pt cell at the 230 pt plot, against the 36 it
  may take), so the cells are 10 pt (owner choice 3's fallback); P19 passes at 10 pt.
- H3's ramp is a 720 × 120 grey ramp in a project of its own (GREY), not project R's 1,920-wide
  RAMP over the deep clip; the near-grey card is beside it, as the spec says.
- H13's "not grey" is chroma > 32 levels: red turned +60° with its luma kept is (58, 58, 0), whose
  chroma is 58, under the 64 first written.
- P15's hue-shift string is a negative one ("Hue 90° → −12°"), so it also pins U+2212.
- The readout shows a hue's whole degree modulo 360 (359.6 reads "0°").
- `CurveTable.value(_:at:domain:)` is one function with `domain` defaulting to `.tone`, so every
  existing `value(_:at:)` call is unchanged.

**Verification** (2026-10-15, M2 Max; `pmset -g`: "powermode 0", "Now drawing from 'AC
Power'"):
- In the loop: `cd core && cargo fmt && cargo test --release --test hue_curves --test
  schema_v20 --test schema_v19 --test curves --test ungraded --test schema_v8` exit 0 (9, 8, 5,
  6, 18 and 5 passed); `make lint` exit 0 (after one `is_none_or` clippy fix); `make
  typecheck` exit 0 with the four baseline warnings; `swift_build.py typecheck --define
  FRAMEJOB_DEV_TOOLS tools/proof/curves_probe.swift` exit 0; `make app-debug` then
  `curves_proof.py --only …` (the spec's list) 17/26 at first — every H row and K1 C1 M1 J1 passed,
  and the probe crashed on a released `Plot` (an `unowned` capture), fixed — then P19 failed at
  11 pt (above); the whole script on Debug then 48/48. `spec_index_proof.py` 162/162,
  `name_residue.py` exit 0.
- `make gate`: PASS in 249 s (names 1 s, typecheck 6 s, fmt 2 s, lint 1 s, test 139 s, app 99 s
  with D25 and D26 ok); the test log has 123 `test result: ok` lines and no FAILED, and
  `spec_index_proof.py` 162/162 among its steps. After the mutants' lists and this record, a
  second `make gate`: PASS in 96 s (names 1 s, test 94 s; typecheck, fmt, lint and app skipped
  as unchanged).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release python3
  tools/proof/curves_proof.py compare tools/proof/work/t4-2/ctl`: exit 0, **49/49**, N0 the
  eleven frames byte-identical at 16 bits, Z1 no `Frame Job: ` line, no `DEFAULTS MOVED`.
  H15: under +40 the worst HSV-hue error 0.540° over all 720 columns (all at output chroma ≥ 64),
  green → 159.92°; under −40 0.624° over the 651 columns at output chroma ≥ 64 and 1.176° over
  all 720, green → 80.00°. H12: the (153, 102, 102) card's luma 112.84 → 112.79 under +90°
  (its hue moved +90.59°), the sweep's worst luma change 0.488 levels. H4: the oracle's shifts
  10.0° at 0°, 30.625° at 5°, −10.625° at 355°.
- `RC_PROOF_APP=release python3 tools/proof/qualifier_proof.py`: exit 0, 31/31 (`qualifierWeight`
  reading its hue through `hsvHue`).
- `python3 tools/proof/grading_spike/grading_spike.py --measure --tree --tree-base a8ef6fd`:
  exit 0, every scored row PASS; KT and KA max |Δ| 0.0 at 1080p and 2160p; TC 0.002 ms
  (1080p, cap 0.069) and −0.001 ms (2160p, cap 0.061); TA 0.002 ms (1080p, cap 0.081) and
  0.008 ms (2160p, cap 0.060). `vm.loadavg` 96.36 57.31 38.59 before and 161.04 81.10 48.54
  after (other sessions' builds).

**H16, Color's Hue, for the record**: on the gate's Release build Color's Hue +40 moves the 0°
column −55.52° and the 120° column −22.63°, both against the label's sign (the spec's
`hueRotate` model: −55.5°, −22.6°). Unchanged here (see Residue).

**Mutants** (`python3 tools/proof/curves_proof.py --mutant NAME`, each on its own tree copy's
Debug build, once, at the end):

| Mutant | Must fail | Answer |
|---|---|---|
| `hue-wrap-dropped` | H4 P12 | MUTANT PASS (46/48; P12's worst 332.37) |
| `hue-from-graded` | H13 | MUTANT PASS (47/48; red → (54, 54, 54)) |
| `hue-shift-reversed` | H15 H1 H4 H13 | MUTANT PASS (44/48) |
| `luma-not-kept` | H12 H1 H4 H13 | MUTANT PASS (44/48; the card's luma 112.84 → 143.79, the sweep's worst 121.584 levels) |
| `gamut-limit-dropped` | H15 H12 H1 H4 H13 | MUTANT PASS (43/48; the sweep's worst luma change 26.236 levels) |
| `chroma-guard-dropped` | H3 | MUTANT PASS (47/48) |
| `hue-before-channel-curves` | H14 | MUTANT PASS (47/48; yellow → (0, 255, 0)) |
| `row-0-at-centre` | K1 C1 M1 O1 | MUTANT PASS (44/48) |
| `shift-lock-ignored` | P14 | MUTANT PASS (47/48) |

`hue-shift-reversed`, `luma-not-kept`, `gamut-limit-dropped` and `row-0-at-centre` first answered
MUTANT FAILURE with every row the spec named failed, because other rows failed by construction:
each turn edit also fails H1, H4 and H13 (their oracle turns a colour), and row 0 at y 0.5 also
fails O1 (a tone row). Those rows were added to the four's must-fail lists (a deviation from the
spec's lists) and the four re-run, each MUTANT PASS as above.

**Owed.**
- The `app/CLAUDE.md` and `core/CLAUDE.md` edits, exact text in the phase's notes (the
  orchestrator's): the Curves files' map lines (`CurveProps.swift`, `CurveTable.swift`,
  `CurveTextures.swift`, `CurveEditorView.swift`, `VideoPane+Curves.swift`, the new
  `CurvePlotDecor.swift`), the `LayerUniforms` block line, and `core/CLAUDE.md`'s
  `model_grade.rs`, `grade_check.rs` and `actions_curves.rs` entries.
- GRD-13's steps 9–11 are the owner's, on real footage.

**Residue** (for the orchestrator to file).
- Color's Hue turns HSV hue against its label's sign and by an amount that varies by hue (H16
  above: +40 moves red −55.52° and green −22.63°), against every other hue degree in the app
  (the qualifier, the wheels, the split tone, these hue curves, the spectrum strip) and CSS
  `hue-rotate`. Changing it changes every existing project's Color Hue render, so it is the
  owner's call, not this phase's.
  The owner chose (2026-10-15): fix it with this phase's exact HSV shift (`gradeHueShift`), so
  +40 moves every hue +40° keeping luma; old projects' Color Hue renders change. It lands as
  phase T4-2b, its decision first (done in T4-2b).
- `designs/spec/07.9a-agent-tools.md` grew to 576 lines (#297).

**Review.** One lc-reviewer pass, verdict pass: no blockers, no should-fixes. Two nits, both
applied by the orchestrator: `CurveEditorView`'s dead `nudge` / `bigNudge` statics removed
(`minGap` kept, `curves_probe.swift` reads it), and the curves catalog clause now says a grey
or near-grey up to chroma 0.02 is left alone and the effect fades in up to 0.06. The owed
`app/CLAUDE.md` and `core/CLAUDE.md` edits above were applied by the orchestrator.

## T4-2b — Color's Hue by the exact HSV shift

**What landed** (2026-10-15, in the worktree on `grading-4`, from `510f181`), from the owner's
answer to T4-2's H16 ("Fix with the new exact shift (Recommended)"). First GR-33 in
`designs/spec/11-decisions/grading-4.md`, written before any code, with its index row, the
"Amended by GR-33" lines under GR-32 (its "Not: … a change to Color's Hue" lifted) and GR-2
(`grading.md`), and the index's GR-2 and GR-32 rows; then the instrument and its control on the
unchanged product (below); then:
- **Shader** (`Compositor.metal`): `hueRotate` deleted; `lookHueChroma`, `hsvHue` and
  `gradeHueShift` moved, their code unchanged, from the Looks, Wheels and curves sections to
  where `hueRotate` stood, under `// MARK: - Hue (spec §11 GR-13, GR-32, GR-33)`; `gradeSample`'s
  hue branch, still behind |hue| > 1e-4 rad, takes the uniform's radians to degrees, wraps them
  by `degrees − 360·floor(degrees/360)` into [0, 360), reads the HSV hue once from the colour as
  the saturation leaves it (unclamped) and calls `gradeHueShift`, with no chroma guard. Comments:
  `LayerSample`'s doc (the hue turn is a continuous function of the colour, like the spill),
  `gradeTone`'s ("like Color's hue turn"), `hsvHue`'s (step 3 passes an unclamped colour),
  `gradeHueShift`'s last line (Color's Hue calls it too, wrapped, unguarded) and the
  order-of-operations step 3 line (GR-33). Every `gradeSample` caller follows with no edit: the
  layer stage's every tap (blur, sharpen, pixelate, regions), the slate, the adjustment pass and
  the look bake (which runs it only when the hue is not 0; no built-in look sets one).
- **Swift**: `AgentCatalog+Properties.swift`'s `video.color` clause says hue is in degrees and a
  positive hue turns every colour's HSV hue that far, red → yellow → green, keeping its Rec. 709
  luma (321 lines). No model, uniform, core, FFI, format, op or tool change: the value stays
  degrees, the uniform radians.
- **Instruments**: `curves_proof.py` H16 scored (out of `RECORDS`, now empty), H17–H19 new, the
  NEAR fixture (a 720 × 120 card of (132, 128, 128)), three mutants, and H17 added to
  `hue-shift-reversed`'s list, H16 to `luma-not-kept`'s and `gamut-limit-dropped`'s.
- **Documents**: spec §7.5 (the tone line's "like Color's hue turn"; step 3's Hue calls the same
  `gradeHueShift`), §4.3a (the Color section's hue row), §5.2 (`hue` is degrees of HSV-hue turn,
  taken modulo 360), the spec index's Lines cells; the README's Color bullet;
  `tools/proof/README.md`'s T4-2b paragraph.

**Who else uses Color's Hue, and whether it changes.** Every renderer of `video.color.hue` goes
through `gradeSample`, so every picture with a non-zero Hue changes and every picture with Hue 0
is byte-identical (N0 below): the preview, `render_frame`, Save Frame, every export, the
adjustment pass and the Look gallery's thumbnails (through `Exporter.renderFrame`). Unchanged,
no edit: the built-in looks (all hue 0, `core/src/model_look.rs`'s `definition`, so every
lattice is the same), `core/src/actions.rs` (lerps degrees), `actions_clamp.rs` and
`props_check.rs` (any finite value), `VideoPane+Color.swift`'s −180…180 row,
`Compositor+Uniforms.swift` and `LookTextures.swift` (degrees to radians), the chroma-key
eyedropper (it neutralises Color while it picks), `seeing_proof.py` (asserts only graded ≠
neutral) and `qualifier_proof.py`'s D1 (self-consistent). No frozen byte reference holds a
non-zero Color Hue, so nothing is recaptured.

**The control** (on the unchanged product's Debug build, after the instrument edit and before
the shader edit): `make app-debug`, then `python3 tools/proof/curves_proof.py --only
H16,H17,H18,H19,Z1`: exit 1, 2/5 — H16 FAIL (+40: the worst column 98.225° off, red → 304.48°,
green → 97.37°, luma worst 33.199 levels; −40: worst 97.009°, red → 23.23°, green → 175.20°,
luma worst 36.825), H17 FAIL (+40: x 0 (241, 0, 223) against the curve's (79, 52, 0)), H18 ok
(the matrix is periodic in 360°), H19 FAIL ((132, 128, 128) → (132, 127, 131), hue 312.0°), Z1
ok. As expected: H16, H17 and H19 fail and H18 passes.

**Verification** (2026-10-15, M2 Max; `pmset -g`: "powermode 0", "Now drawing from 'AC
Power'"):
- In the loop: `make typecheck` exit 0 with the four baseline warnings; `make app-debug` exit 0
  (the shader compiled); `python3 tools/proof/curves_proof.py --only
  H12,H15,H16,H17,H18,H19,Z1` exit 0, 7/7; `spec_index_proof.py` 162/162; `name_residue.py`
  exit 0.
- `make gate`: PASS in 227 s (names 1 s, typecheck 5 s, fmt and lint skipped as unchanged,
  test 117 s, app 104 s).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release python3
  tools/proof/curves_proof.py compare tools/proof/work/t4-2/ctl`: exit 0, **53/53**, N0 the
  eleven Hue-0 frames byte-identical at 16 bits to T4-2's control, Z1 no `Frame Job: ` line, no
  `DEFAULTS MOVED`. H16: under +40 the worst HSV-hue error 0.540° over all 720 columns (all at
  output chroma ≥ 64), luma worst 0.488 levels, red → 39.49°, green → 159.92°; under −40 0.624°
  over the 651 columns at output chroma ≥ 64 and 1.176° over all 720, luma worst 0.465, red →
  319.90°, green → 80.00° — H15's numbers to the thousandth, as H17 (all 720 columns within ±1
  of the constant curve's, both signs) says they must be. H18: −500 and −140 within ±1 at every
  column. H19: (132, 128, 128) → (130, 129, 126), hue 45.0°.
- `RC_PROOF_APP=release python3 tools/proof/qualifier_proof.py`: exit 0, 31/31 (D1, Color's
  Hue +120 in the adjustment pass, ok).

**Mutants** (`python3 tools/proof/curves_proof.py --mutant NAME`, each on its own tree copy's
Debug build, once, at the end; every one MUTANT PASS at its first run, no list changed after):

| Mutant | Must fail | Answer |
|---|---|---|
| `color-hue-reversed` | H16 H17 H19 | MUTANT PASS (49/52; +40 sends red to 319.90°, the near-grey to hue 330.0°) |
| `color-hue-unwrapped` | H18 | MUTANT PASS (51/52; at x 0 −500 gives (176, 6, 176) against −140's (0, 58, 174)) |
| `color-hue-guarded` | H19 | MUTANT PASS (51/52; the near-grey stays (132, 128, 128)) |
| `hue-shift-reversed` | H15 H1 H4 H13 H17 | MUTANT PASS (47/52) |
| `luma-not-kept` | H12 H1 H4 H13 H16 | MUTANT PASS (47/52; H16's hues exact, its luma worst 121.584 levels) |
| `gamut-limit-dropped` | H15 H12 H1 H4 H13 H16 | MUTANT PASS (46/52; H16's worst 18.346°, luma worst 26.236 levels) |

The three changed lists are as the spec set them: `hue-shift-reversed` turns only the curve, so
H17's comparison fails by construction; `luma-not-kept` and `gamut-limit-dropped` edit
`gradeHueShift`, which Color's Hue now calls, so H16 fails by construction.

**Owed.**
- No `CLAUDE.md` edit: no map entry or rule names `hueRotate` or Color's hue.
- How a Color Hue turn looks on footage is GRD-13's step 9 (the same function); no new
  `docs/manual-checks.md` row.

**Residue.** Nothing to file.
- Not measured: the shift's cost per tap against the matrix's on a blurred layer (13 taps), the
  risk GR-33 accepts; not filed, since the decision accepts it.
- Found while checking every proof's mutant anchors against the edited shader, and done in this
  phase (fix pass 1, the orchestrator's ruling): `adjustment_proof.py`'s `WEIGHT` anchor
  (`float w = saturate(u.opacity * matte.sample(samp, local).r);`, used by its `ignores-matte`
  and `ignores-opacity` mutants) occurred 0 times in `Compositor.metal` at `510f181` too — the
  adjustment pass reads `saturate(u.opacity * coverage * selected)` since G2-4 (`c948fad`), so
  those two mutants could not build. `WEIGHT` is re-anchored on that line (once in the shader;
  every other `adjustment_proof` anchor occurs exactly once), `ignores-matte` writing
  `saturate(u.opacity * selected)` and `ignores-opacity` `saturate(coverage * selected)`. Each
  ran once on its tree copy's Debug build: `ignores-matte` MUTANT PASS (34/36, M1 and Q1
  failed, no other row), `ignores-opacity` MUTANT PASS (34/36, O1 and O2 failed, no other row);
  no list changed. `GradeProps.swift`'s `hue` doc comment now names GR-33's HSV-hue shift.

**Review.** Two lc-reviewer passes. The first: fix-required, two should-fixes, both the
orchestrator's ruling adding them to this phase (the rotted `WEIGHT` anchor, the `hue` doc
comment); fix pass 1 closed both. The second: pass, one nit (this Residue heading), applied by
the orchestrator. The adversary's one objection (−400 against −40 could not score the wrap; H18
is −500 against −140) was taken into the final spec. No `CLAUDE.md` edit was owed.

## T4-3 — curves of different point counts blend their values

**What landed** (2026-10-15, in the worktree on `grading-4`, from `d22f8e2`), #271. First GR-34
in `designs/spec/11-decisions/grading-4.md`, written before any code, with its index row, the
"Amended by GR-34" lines under GR-32 and GR-12 (`grading-2.md`) and the index's GR-12 and GR-32
rows; then the instrument and its control on the untouched product (below); then:
- **Core**: `actions_curves.rs` gains `CurveBlend`, `curve_blends` (the channels whose held and
  clamped end curves are both non-identity with different counts, empty unless 0 < t < 1 or when
  the end's curves do not decode) and `blended_curves_json` (`curves_json` with each blended
  channel as `{from, to, t}`, byte-identical with no blends), and its module doc;
  `actions_clamp.rs`'s `clamp_curves` is `pub(crate)`; `actions.rs` (wiring, 570 lines) keeps the
  spanning action's merged target and eased t, fills `Evaluated.curve_blends` (`#[serde(skip)]`)
  only when the state decoded as `VideoProps`, and writes `clip_state`'s `video.curves` through
  `blended_curves_json`; `recipe_layer.rs`'s `RecipeLayer.curve_blends` feeds `object()`'s
  `curves`; `recipe.rs` (wiring, 528) passes `&[]` when `ungraded`; `recipe_text.rs`'s burn-in
  passes `&[]` (550). `patch.rs`'s template, `edit_split.rs`'s `state_patch` and the evaluator's
  base state stay on `curves_json`.
- **Core tests**: `core/tests/curve_blend.rs` (new, nine tests: a 3 → 5 Master action at 0, SEC/2
  and 2·SEC with `clip_state` equal to the layer; ease_in's t 0.25; a 3 → 5 `hue_hue`; a
  same-count pair whose SEC/2 lerp is asserted not the identity, and an identity-aligned one,
  publishing only points; a 17-point end never blending; `ungraded` the identity six; an
  adjustment clip's layer; a split mid-blend storing only point lists with the tail starting on
  `from` and still blending; Master same-count beside Red mismatched). `curves.rs`'s and
  `hue_curves.rs`'s `other_count_changes_switch_at_the_end` became
  `other_count_changes_blend_their_values`.
- **Swift**: `CurveProps.swift` (357 lines) gains `CurveBlend`, `ColorCurves.blends` with explicit
  `CodingKeys`, the blend's decoding (both lists ≥ 2 points, t finite, clamped to 0…1; malformed
  is the identity) and the identity tests reading blends; `CurveTable.swift`'s strip samples a
  blended channel as `(1 − t)·A(x) + t·B(x)` through a private `Channel`; `CurveTextures.swift`'s
  doc (the LRU key includes the blends); `InspectorBinding+Writes.swift` drops the curves BASE
  branch (owner choice 2); docs in `VideoPane+Curves.swift` and `FrameRecipe.swift` (400 lines);
  `AgentCatalog+Properties.swift`'s curves clause ("two curves of different point counts blend
  their values across the action", 322 lines).
- **Instruments**: `curves_proof.py` B1–B4, `BlendStrip`, N0's seven new frames, CT running
  `--test curve_blend --test hue_curves` too, six mutants; `curves_probe.swift` P20, P21 and P10
  amended.
- **Documents**: spec §5.4, §7.3, §7.5, §7.10 (`actions_curves.rs`), §4.3a, §7.9a (one sentence
  replaced, no line added), the spec indexes' Lines cells; GRD-13's step 12; the README's Curves
  bullet; `tools/proof/README.md`'s T4-3 paragraph.

**Deviations.**
- B1's and B2's blend frames are at 0.3 s (t 0.3), not 0.25 s: `render_frame` snaps `t` to the
  30 fps grid (`AgentServer+Arguments.swift`'s `snappedTick`), so 0.25 s (7.5 frames) would
  render at 0.2667 s. The 1 s linear action and the 0.5 s frame are as specified; `blend-t-inverted`
  is still caught (B1 at 0.3 s was 122.397 ten-bit levels off), and the core's ease_in test pins
  t 0.25.
- `same-count-blended`'s list gained A1, A2 and H8 (its first run: MUTANT FAILURE, those three the
  only other rows failing): the mutant blends every same-count and aligned action, whose oracles
  are the per-point lerp, so they fail by construction. Rerun once with the list amended: MUTANT
  PASS.
- The probe's P20 decodes with `.convertFromSnakeCase`, the app's own key strategy
  (`ProjectSnapshot.swift`); its first targeted run used a plain `JSONDecoder` and failed on
  `hue_hue`, an instrument error fixed before any scored run.

**The control** (on the untouched product, after the instrument edit and before any product
edit): `make app` exit 0, then `RC_PROOF_APP=release python3 tools/proof/curves_proof.py capture
tools/proof/work/t4-3/ctl`: exit 0, 18 frames captured, Z1 ok, no `DEFAULTS MOVED`.

**Verification** (2026-10-15, M2 Max; `pmset -g`: "powermode 0", "Now drawing from 'AC
Power'"):
- In the loop: `cargo test --release --test curve_blend --test curves --test hue_curves --test
  ungraded` 9 + 9 + 8 + 5 passed; `make lint` exit 0; `make typecheck` exit 0, the four baseline
  warnings; the probe's `swift_build.py typecheck` exit 0; `make app-debug` then
  `curves_proof.py --only N1,A1,A2,A3,H8,B1,B2,B3,B4,P10,P20,P21,Z1` 12/13 (P20's instrument
  error, above), then `--only P20,Z1` 2/2; `spec_index_proof.py` 162/162.
- `make gate`: PASS in 377 s (names 1 s, typecheck 7 s, fmt 2 s, lint 2 s, test 211 s, app
  153 s); after the mutant list and the documents changed, `make gate` again: PASS in 85 s
  (names 1 s, test 82 s, the rest skipped as unchanged).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release python3
  tools/proof/curves_proof.py compare tools/proof/work/t4-3/ctl`: exit 0, **59/59**, N0's 18
  frames byte-identical at 16 bits to the control (A1–A3's and H8's 0.5 s frames and B1's ends
  among them), Z1 no `Frame Job: ` line, no `DEFAULTS MOVED`. B1: worst 0.489 ten-bit levels at
  t 0.3 and 0.499 at t 0.5, both ends byte-equal; B2: every column within ±1, ends byte-equal;
  B3: worst 0.495 levels from the lerp, 124.90 levels from the value blend; B4: 4 channels live
  and 4 filed, all point lists.

**Mutants** (`python3 tools/proof/curves_proof.py --mutant NAME`, each on its own tree copy's
Debug build, once, at the end):

| Mutant | Must fail | Answer |
|---|---|---|
| `blend-t-inverted` | B1 B2 CT | MUTANT PASS (56/59; CT `--test curve_blend`) |
| `same-count-blended` | B3 CT A1 A2 H8 | first run MUTANT FAILURE (B3 CT failed, A1 A2 H8 too); list amended, rerun MUTANT PASS (54/59) |
| `mismatch-still-switches` | B1 B2 CT | MUTANT PASS (56/59; CT `--test curve_blend`, `--test curves`, `--test hue_curves`) |
| `blend-written-to-file` | B4 CT | MUTANT PASS (57/59; the head's end master stored as `{from, to, t}`) |
| `strip-ignores-blend` | B1 B2 P21 | MUTANT PASS (55/58) |
| `write-rule-kept` | P10 | MUTANT PASS (57/58) |

**Owed.**
- `CLAUDE.md` edits (the orchestrator's): `core/CLAUDE.md`'s `actions_curves.rs` entry, and
  `app/CLAUDE.md`'s `InspectorBinding+Writes.swift` line and `CurveProps.swift` types line (the
  exact text is in the phase's implementation notes).
- How a blend looks on footage is GRD-13's step 12.

**Residue.** Nothing to file.

**Review.** One lc-reviewer pass, verdict pass: no blockers, no should-fixes. Its one nit (that
§7.3's `curves` bullet should say `clip_state` carries the same object) was already met — the
bullet's next sentence says so — so nothing changed. The adversary's one objection (B3's pair
lerped to the identity at 0.5 s, so it could not catch `same-count-blended`) was taken into the
final spec. The three owed `CLAUDE.md` edits were applied by the orchestrator.
