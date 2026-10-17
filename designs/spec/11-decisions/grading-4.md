# Spec §11 — decisions: Grading tier 4 (road map "grading-4")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/grading-4.md`,
and the original, `archive/grading-4.md`, holds each phase's record (T4-0 the road map, these
decisions and the pure move; T4-1 the scopes; T4-2 the hue curves and the curve editor's extras;
T4-2b Color's Hue; T4-3 curves of different counts; T4-4 the qualifier's cleanup blur; T4-5 the
close). The IDs continue the GR- series of
[`grading.md`](grading.md), [`grading-2.md`](grading-2.md) and [`grading-3.md`](grading-3.md), so
a citation never has to say which file. GR-24…GR-30 were recorded in T4-0, before any tier-4
code, from the owner's answers of 2026-10-14 to the tier-4 brief's choices, every one the
recommended answer (`archive/grading-4.md`, "The owner's choices"; the brief is
`~/.claude/litecode/reelcut/grading-tier4/I-grading-tier4.md` and the answers `answers.md` beside
it, outside the repo). T4-1…T4-4 each record their numbers as a new entry (GR-31 on; T4-4's is
GR-35) or as Amended-by lines before their code.

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies, never a runtime);
PR-1…PR-12; MT-1…MT-9; GR-1; GR-3 (blending stays encoded); GR-6 (the blur FILTER on an
adjustment clip stays refused); GR-10…GR-23 except as amended below and by the phases.
**The Concat rule** (`designs/adr/effects-survey.md`, "Licensing") stands for every phase: the
scopes' maths stays the Rec. 709 Y′CbCr matrix (ITU-R BT.709-6), the hue curves' spline is
Fritsch and Carlson (1980) with its secants wrapped, and the selection's blur is a Gaussian;
nothing of Concat is opened, at design time or build time.

- **GR-24 — Tier 4 builds five extras and closes four.** Choices 1a, 3a, 5a, 6a, 8a and 9a
  (owner, 2026-10-14). Each build is as the brief's §0 chose it:
  - **T4-1, #265 — vectorscope zoom:** ×1, ×2 and ×4, counted at the zoom (`bin = 128 +
    round(255·zoom·c)`), not drawn larger: a one-level cast is half a bin at ×1, which a larger
    drawing cannot show, and at ×4 it moves 2 bins. At zoom > 1 an off-plot pixel is not
    counted (clamped to the edge it measured 1.67 ms at ×4 on a gradient and piles a false
    ring on the rim). The JSON gains `zoom` and `off_plot`. The six 75 % targets show as rim
    ticks toward them, since none fits from ×2; three cells "1× 2× 4×" sit in the square's
    bottom-right corner. The zoom is per slot, per window, not persisted, ×1 when a project
    opens (GR-10's rules for the slot picks). `render_frame {vectorscope_zoom}` takes 1, 2 or 4
    and refuses anything else by name. No format change.
  - **T4-2, #267 — hue curves:** Hue vs Hue and Hue vs Sat, the picker Master · Red · Green ·
    Blue · Hue · Sat, weighted by GR-13's chroma guard so a grey is never tinted; Hue vs Luma
    not now. With them #270's hover readout and ⇧ axis lock.
  - **T4-3, #271 — curves of different counts:** a channel whose two ends are non-identity
    curves of different counts is `(1−t)·a(x) + t·b(x)`, exact at both ends; no spline in Rust,
    no FFI, no format change; same-count actions keep §5.4's per-point lerp, so every existing
    render stays byte-identical. The issue's resampling is not built: measured, it moves the
    curve at the action's start (median 27.7 ten-bit levels, max 775, on 1,000 random 3 → 5
    rising pairs).
  - **T4-4, #268 — the qualifier's cleanup blur:** `video.qualifier.blur` at full resolution;
    0 is today's path, byte-identical; only q is blurred, never the matte coverage. GR-6 is
    unchanged: a blur of the selection is a key inside `video.qualifier`, not the blur filter
    GR-6 refuses.
  - **Closes:** GR-27…GR-30.
  - Risk accepted: no real footage has been graded yet, so every strength this tier adds is a
    first number, judged by GRD-11, GRD-13 and GRD-14.
- **GR-25 — Tier 4's working arrangement: each phase merged into main alone, main's numbers, no
  verdict phase.** Choice 11 (owner, 2026-10-14). GR-14 and GR-17 again: the worktree
  `~/devel/framejob-grading4` on branch `grading-4`; each phase merged into main alone after its
  `make gate`. Main's next format numbers (20 for T4-2 and 21 for T4-4 at T4-0) and main's next
  GR IDs, each renumbered before a merge if main moved. No verdict phase: each phase is kept when
  its proofs pass. Synthetic fixtures now; the GRD rows wait for real footage.
- **GR-26 — A flat saturated colour is GR-10's sixth timed fixture, and a non-central
  vectorscope bin shared by a whole SIMD group is added once.** Choice 2 (owner, 2026-10-14).
  - **Why:** a flat (0.8, 0.1, 0.1) frame puts every pixel in one bin outside the central
    64 × 64, so every pixel is one global atomic on one counter, the contention GR-10's counting
    rule exists to prevent. The shipped `framejob_vectorscope_bin` measured 7.29–7.33 ms at 4K
    on it, and 0.281–0.282 ms with the same-bin add (`simd_all`, `simd_sum`), its counts equal
    to the per-pixel kernel's (the tier-4 brief's §2 and §12; a scratch bench, M2 Max, a loaded
    host). GR-10's five fixtures have no flat saturated colour, so its T1 never met the case,
    which a solid-colour slide or title reaches in ordinary use.
  - **The bound** holds over the six fixtures at every zoom (GR-24's T4-1).
  - **When:** the code and the app-pass T1 land in T4-1.
  - Risk accepted: until T4-1 lands, the shipped kernel misses the bound on that fixture (one
    phase).
  - **#296 (clean-up 4, 2026-10-17): kept (worst fixture).** Does the central 64 × 64
    threadgroup path still pay after the same-bin add? `python3 tools/proof/scopes_proof.py
    --central-ab` times the ×1 vectorscope of `base` (`c7c0dbf`'s shader, the central path),
    `tree` (the kernel a drop would ship: every bin global with the same-bin add, no threadgroup
    array) and `twin` (`base` with `bool central = false`, T3's twin, a record only) on the six
    4K fixtures, 60 rounds each, round r in `[base, tree, twin]` rotated by r mod 3, each a T1
    `gpuMedian`. The rule, declared before the run, with m a fixture's median and S the larger of
    base's and tree's IQR: STOP when any S > 10 % of the smaller median; KEEP (pays) when
    near-grey's m_tree − m_base > S and no fixture's m_base − m_tree > S; else KEEP (worst
    fixture) when the worst m_tree > the worst m_base + S_W (GR-10 bounds the worst fixture);
    else DROP. Apple M2 Max, AC power.
    - The CONTROL (the tree's shader identical to base): near-grey base 0.2897 ms, tree 0.2891
      (S 0.0026); `worst: base 0.4070 (gradient) tree 0.4071 (gradient) S_W 0.0043`; `CONTROL
      PASS`. Load 23.92 37.44 81.25 before, 146.81 69.08 90.25 after.
    - The run (the drop candidate in the tree): near-grey base 0.2877 ms (IQR 0.0008), tree
      0.5306 (IQR 0.0004), twin 0.5326; paired tree − base +0.2429 ms. The worst loss is flat:
      base 0.3220, tree 0.2565, paired −0.0654 (S 0.0011), so KEEP (pays) fails (ramp −0.0648,
      noise −0.0631 and flat-red −0.0303 too; on flat, ramp and noise most of the loss is the
      central counts themselves, base − twin, the 16 KB zero and merge the rest, twin − tree:
      flat 0.0496 and 0.0159 ms). `worst: base 0.4038 (gradient) tree 0.5306 (near-grey) S_W
      0.0049`: dropping would raise the worst fixture GR-10 bounds, so `VERDICT: KEEP (worst
      fixture)` (the twin under the same rule: KEEP (worst fixture), 0.5326 on near-grey). Load
      77.41 62.70 86.72 before, 56.99 58.99 84.83 after.
    - The path stays, and T3 and its mutant `vectorscope-global` with it. T3 now scores
      near-grey by name: the slowest forced-global fixture, its old pick, let a loaded gradient
      sample (base/twin about 0.9 at rest, above) fail it at 1.139 in this batch's Release run.
- **GR-27 — An Offset wheel is not wanted: #266 closed.** Choice 4a. Its master is Color's
  Brightness, Temperature and Tint already shift every level, and a fourth disc squeezes the row
  past the master field at the 280 pt pane.
- **GR-28 — A qualifier on picture clips is not wanted: #269 closed.** Choice 7a. A clip holds
  one grade, so a qualifier there would limit its only grade; Insert ▸ Adjustment Clip is the
  secondary.
- **GR-29 — 1,024-level scopes are not wanted: #273 closed.** Choice 10a. About 2.5 levels per
  drawn pixel, the 16-bit-float compositor never quantizes a grade, and `render_frame`'s PNG is
  already 16-bit for a deep source (PR-4).
- **GR-30 — A histogram behind the curve plot is not wanted: #270's first item closed.** Choice
  8a. The tap sees the frame after the curve, so it moves as the curve is dragged.
- **GR-31 — The vectorscope zoom: ×1, ×2 and ×4 per slot, counted at the zoom, off-plot pixels
  not counted, the targets as rim ticks, three corner cells and `render_frame
  {vectorscope_zoom}`.** Recorded in T4-1 before its code; it settles GR-24's T4-1 item to the
  point and amends GR-10.
  - **The count.** The zooms are 1, 2 and 4 (`VectorscopeTrace.zooms`). Each of Cb and Cr is
    binned `bin = 128 + round(255·zoom·c)`: at ×1 clamped to 0…255 as GR-10 says, so every ×1
    trace is the one the T4-0 tree counted; at ×2 and ×4 a pixel whose Cb or Cr bin falls outside
    0…255 is not counted. The kernel takes the zoom as a uniform and branches on it, ×1 keeping
    GR-10's expression as it was. `off_plot` is the pixels not counted, `width·height − Σcounts`:
    0 at ×1. GR-26's same-bin add holds at every zoom, and GR-10's 1.1 ms bound holds over GR-26's
    six fixtures at every zoom.
  - **The drawing.** At a zoom where a 75 % target's bin is off the plot, the target is a rim tick:
    a 6 pt line from the square's edge inward along the ray from the centre toward the target,
    its label just inside the tick's inner end; a target still on the plot keeps GR-10's box. The
    skin line is unchanged (it runs through the centre). Three square cells "1×", "2×" and "4×",
    16 pt each, sharing 1 pt borders, sit 4 pt in from the square's bottom-right corner, mono 9 in
    the well's fixed inks, the current zoom's cell filled; a click on a cell is the zoom. Their
    accessibility id is `scopes.<slot>.zoom`. No menu item and no key.
  - **What it belongs to.** The zoom is per slot and per window, with no `UserDefaults` key, ×1 for
    a new window (GR-10's rules for the slot picks); it is kept across hiding and showing the
    panel and across picking another scope and back (owner choice 1, as recommended). Two
    vectorscope slots at different zooms cost two passes in one command buffer, at one zoom one.
    A zoom change clears the slot's body until the next reading and asks for a frame, as a pick
    does. No zoom in the Preview Window, an export or another scope.
  - **The mirror.** `render_frame {vectorscope_zoom}` takes 1, 2 or 4 (an integer, default 1),
    refused before the render as `vectorscope_zoom must be 1, 2 or 4 (got 3).`, and as
    `vectorscope_zoom needs vectorscope: true.` when given without `vectorscope: true` (owner
    choice 2, as recommended: refused by name rather than ignored or implying the scope). The
    vectorscope JSON gains `zoom` and `off_plot` at every zoom, and `targets` holds each target's
    `[cb, cr]` at the trace's zoom, JSON `null` for one off the plot (owner choice 3, as
    recommended). At ×1 the sentence is GR-10's, byte for byte; zoomed it is `Vectorscope at ×4
    (Rec. 709 Cb and Cr of the encoded values): N % of pixels are neutral and M % lie off the
    plot; its 256 × 256 counts are in <path>.vectorscope.json.`, one decimal each.
  - **Not:** no format, op, FFI or tool-count change.
  - Risk accepted: a pixel whose `255·zoom·c` lies within 1e-3 of 127.5 or −128.5 may fall
    either side of the edge between the GPU and a CPU count; S6 allows that band, nothing else.
- **GR-32 — Hue curves: `video.curves.hue_hue` (Hue vs Hue) and `.hue_sat` (Hue vs Sat) on a
  periodic Fritsch–Carlson spline, applied after the channel curves at step 4c.2 through the
  strip's second row behind `hueCurvesEnabled`; the Hue and Sat cells, the hover readout and the
  ⇧ axis lock; format 20.** Recorded in T4-2 before its code; it settles GR-24's T4-2 item to the
  point and amends GR-2, GR-4, GR-6, GR-7 and GR-12. The owner's choices (2026-10-14, every one
  as recommended): (1) a hue identity is spelled `[[0, n], [180, n]]` and its two points are
  drawn; (2) the spectrum strip sits inside the square's bottom 10 pt, so the row's height and
  every tone capture are unchanged; (3) six equal cells at 11 pt, 10 pt only if a label does not
  fit; (4) the readout's text and placement below; (5) the hue grid every 60°; (6) points do not
  cross the wrap; (7) hue nudges 1° (⇧ 10°), gain 0.01 (⇧ 0.1), the minimum gap 0.1°.
  - **The keys.** `video.curves.hue_hue` and `video.curves.hue_sat`, each 2–16 points `[hue,
    value]`, hue in degrees, 0 ≤ hue < 360, strictly rising. Hue vs Hue's value is a shift in
    degrees, −180…180 (0 none); Hue vs Sat's a gain, 0…2 (1 none). Model and JSON order: master,
    red, green, blue, hue_hue, hue_sat. A hue curve is the identity when it has at least one
    point and every value is its neutral, whatever its x's; it is written absent and normalised
    away by `set_video` (an identity patch on an uncurved clip "made no change"), and kept in an
    action's END as "animate to neutral" (GR-12's rule). An absent hue curve is spelled
    `IDENTITY_HUE_SHIFT` `[[0, 0], [180, 0]]` / `IDENTITY_HUE_GAIN` `[[0, 1], [180, 1]]` in the
    recipe and in an action's `clip_state`. No op, no op-table row, no tool, no FFI export.
  - **Refusals**, in model order then point order, never clamped by a patch: the count sentence
    as GR-12's (`video.curves.hue_hue needs 2 to 16 points, not 17`); `video.curves.hue_hue[2].x
    must be at least 0 and below 360, not 360`; the values by the range sentence
    (`video.curves.hue_hue[1].y must be between -180 and 180, not 200`;
    `video.curves.hue_sat[0].y must be between 0 and 2, not 2.5`); the rising sentence as GR-12's.
  - **An action's end is clamped:** NaN removes the channel; x to 0…360, then a channel whose last
    x is 360 or whose x's do not strictly rise is removed; values to their range; identities
    removed. Two hue curves of the same count lerp per point (x linearly, no wrap); an identity
    meeting a curve of another count takes that curve's x's with the neutral value; any other
    count change switches at the end (T4-3 changes that).
  - **The spline**: Fritsch–Carlson made periodic: secants δk for k = 0…n−1, δ(n−1) from
    (x(n−1), y(n−1)) to (x0 + 360, y0); every tangent is interior (indices mod n): 0 where
    δ(k−1)·δk ≤ 0, else their mean; then for k = 0…n−1 in order (the wrap segment last) the
    flat-secant and α² + β² > 9 rules; cubic Hermite inside a segment (x < x0 or ≥ x(n−1) uses
    the wrap segment); clamped to the domain's value range. The tone spline is unchanged bit for
    bit. Swift only (`CurveTable.swift`), as GR-12.
  - **The strip** becomes 1,024 × 2 (`rgba32Float`, or `rgba16Float` without 32-bit filtering).
    Row 0 is GR-12's composites, sampled at y 0.25 (exact in y, so every tone render is
    unchanged); row 1's texel i is (shift(i·360/1023)/360 turns, gain(i·360/1023), 0, 1), sampled
    at x `(h/360)·(n−1)/n + 0.5/n`, y 0.75. The placeholder is 2 × 2: row 0 (0,0,0,1), (1,1,1,1);
    row 1 (0,1,0,1) twice, bound when all six channels are the identity or an upload fails (then
    both flags are 0).
  - **The step**: step 4c.2's second half, after the channel curves and before the look, in the
    layer stage and the adjustment pass, on encoded values. c = saturate(rgb); h its HSV hue
    (GR-13's formula, one helper shared with `qualifierWeight`), C = max − min of c; row 1 is
    sampled at h once, so the gain is read at the ORIGINAL hue. The shift applies only when |turns|
    > 1e-6, then `mix(Y709, out, gain)` only when |gain − 1| > 1e-6, and the result is
    `mix(rgb, out, smoothstep(0.02, 0.06, C))` (GR-13's chroma guard: a grey is never tinted).
    `hueCurvesEnabled` (GR-11's reserved float, the block stays 128 floats) is 1 exactly when a
    hue curve is not the identity and joins the effects gate's sum; `curvesEnabled` now means "a
    tone curve is not the identity".
  - **The shift is an HSV-hue move in the curve's direction** (+ = red → yellow → green, the
    spectrum strip's left to right), not Color's `hueRotate`, which turns HSV hue against its
    label's sign and by an amount that varies by hue. With Y the Rec. 709 luma of rgb and Cr =
    max(rgb) − min(rgb): d = Cr·`lookHueChroma`(h + degrees); k is the largest value in [0, 1]
    keeping every channel of Y + k·d inside [min(0, min rgb), max(1, max rgb)]; out = Y + k·d.
    Where C ≥ 0.06 the step's float output has HSV hue exactly h + degrees (mod 360) and exactly
    the input's Y; k < 1 gives up only chroma (toward the same-luma grey, which keeps hue), and
    only where the shifted colour at that luma would leave [0, 1]. The gain then scales chroma
    about the same Y (Color's Saturation; hue kept for gain > 0). In 8-bit output the measured
    HSV hue is within ±1° of h + degrees at output chroma ≥ 64/255 and within ±2° on every column
    of a hue sweep under ±40° (a spec-time model over 720 columns: worst 0.54° at +40 and 0.47° at
    −40 at chroma ≥ 64, 1.18° at −40 over all; luma within 0.46 levels). The readout's "+12°" is
    therefore the pixel's HSV shift.
  - **Extends GR-4**: `ungraded` neutralises all six. **GR-6**: the adjustment pass applies them,
    and a neutral adjustment clip is one whose six curves are the identity. **GR-7**: the order
    is Color's four, Light, the wheels, the channel curves, the hue curves, the look. Paste
    Attributes carries them with `video.curves`.
  - **The editor.** The picker is Master · Red · Green · Blue · Hue · Sat, six equal cells. A hue
    channel's plot is the view's square less its bottom 10 pt (an 8 pt spectrum strip, 2 pt gap):
    the strip draws `NSColor(hue: t, saturation: 1, brightness: 1)` per column, 0° left and 360°
    right; the grid has verticals every 60°, horizontals at quarters and the neutral middle line
    in place of the diagonal; the faint other channels are only those of the same domain; points
    never cross 0°/360°; an identity hue channel's two points are drawn, and a press adds a point
    at the neutral (GR-12's working-list rule). The In/Out fields: tone 3 decimals 0–1; In on a
    hue curve "°", 1 decimal, 0–359.9; Out on Hue "°", 1 decimal, −180…180; Out on Sat "×", 2
    decimals, 0–2.
  - **The hover readout** (#270): while the pointer is over the plot (and during a drag), a label
    in mono 9 on the chrome background at 0.85 with 2 pt padding sits at the pointer + (8, 8),
    flipped inward at the plot's edges; x is the pointer's model x, y the curve's value there:
    `In 0.42 → Out 0.47` (2 decimals) on a tone curve, `Hue 34° → +12°` (whole degrees, "+" for
    ≥ 0, "−" U+2212 below) on Hue, `Hue 34° → ×0.80` on Sat. None outside the plot, the strip
    included. View state: no model, no format, no tool (§7.9's exemption).
  - **The ⇧ axis lock**: the first drag event with ⇧ held whose travel from the press is ≥ 4 pt
    picks the axis (|Δx| ≥ |Δy| horizontal) for the rest of the gesture; while ⇧ is held the other
    coordinate is the grabbed point's origin (before the axis is picked the point stays put);
    without ⇧ the point follows the pointer. ⌥ and ⇧ combine. The arrow keys' ⇧ is unchanged.
  - **Format 20**: the keys are optional, with no migration step; the bump stops an older build
    dropping them on save. A file numbered 1–19 (and 1015) opens and is stamped 20; 21 and above,
    1014 included, are newer.
  - **Not:** Hue vs Luma; dragging a point across 0°/360°; a change to Color's Hue (`hueRotate`).
  - Risk accepted: the hue curves' strengths are first numbers, judged by GRD-13 on real
    footage; a hue curve between two counts switches at the action's end until T4-3.
  **Amended by GR-33** (grading-4 T4-2b): its "Not: … a change to Color's Hue (`hueRotate`)" is
  lifted; Color's Hue now calls this entry's `gradeHueShift`, wrapped and unguarded, and
  `hueRotate` is gone.
  **Amended by GR-34** (grading-4 T4-3): "any other count change switches at the end (T4-3
  changes that)" and the risk's last clause are replaced: inside an action two non-identity hue
  curves of different counts blend their values, `(1−t)·a(h) + t·b(h)`, in their units.
- **GR-33 — Color's Hue turns HSV hue by GR-32's exact shift: + is red → yellow → green, Rec. 709
  luma kept.** Recorded in T4-2b before its code, from the owner's answer of 2026-10-15 to
  T4-2's H16 ("Fix with the new exact shift (Recommended)"); it amends GR-2 and GR-32.
  - **Why:** `hueRotate`, the matrix Color's Hue (`video.color.hue`) ran at step 3 since M3,
    turns HSV hue AGAINST its label's sign and by an amount that varies by hue (T4-2's H16 for
    the record: +40 moved red −55.52° and green −22.63°), so the Color tab's Hue and Hue vs Hue
    disagreed about which way is +.
  - **The step.** Color's Hue is GR-32's exact HSV-hue shift wherever step 3's colour adjust
    runs, all through `gradeSample`: the layer stage (every blur, sharpen, pixelate and region
    tap, and the missing-media slate), the adjustment pass and the look bake. +h moves every
    pixel's HSV hue +h° (red → yellow → green), keeping its Rec. 709 luma; chroma is given up
    only to stay in range (GR-32's k).
  - **The value** stays degrees in the model, the uniform stays radians, and any finite value is
    taken modulo 360 in `gradeSample` before the shift (`degrees − 360·floor(degrees/360)`, into
    [0, 360)); an action lerps degrees as before. The hue is read ONCE, by GR-13's formula, from
    the colour as step 3's saturation leaves it, unclamped (the formula holds for any colour with
    chroma > 0, and degrees 0 is the identity for any colour). No chroma guard: a constant turn
    tints nothing, and a grey (chroma 0) is returned as its luma. |hue| ≤ 1e-4 rad skips the step,
    so a layer whose Hue is 0 renders byte-identical.
  - **What follows with no edit.** Every built-in look has hue 0 (`core/src/model_look.rs`'s
    `definition`), so every look lattice is unchanged; the Look gallery's thumbnails render
    through `Exporter.renderFrame` and follow. Old projects' Color Hue renders change, with no
    migration and no format bump (owner, 2026-10-15: old files need no compatibility care), since
    the stored meaning (degrees) does not.
  - **Scored** by `tools/proof/curves_proof.py` H16–H19: ±40 by colorsys (direction, amount and
    luma), ±40 against a constant Hue vs Hue curve, −500 against −140 (both wrap to 220°;
    unwrapped, the shift's argument falls below −60 for hues under 80°, where `lookHueChroma`'s
    sign-keeping `fmod` differs; a pair like −400/−40 never leaves (−60, 360) and cannot score the
    wrap), and a near-grey (132, 128, 128) still turned.
  - **Not:** no core, FFI, format, op, tool, `LayerUniforms` or Swift-model change; no change to
    `gradeHueShift`'s body or to the hue curves.
  - Risk accepted: the shift costs more than the matrix per tap on a blurred layer (13 taps); not
    measured.
- **GR-34 — Inside an action, a curve channel whose two ends are non-identity curves of
  different point counts renders `(1−t)·a(x) + t·b(x)`, the two curves' VALUES blended; the core
  publishes the pair and t, Swift's strip blends the two splines; a count change inside an action
  lands on its END.** Recorded in T4-3 before its code; it settles GR-24's T4-3 item (#271) to
  the point and amends GR-12 and GR-32. The owner's choices (as recommended): (1) a split inside a
  blending action keeps the start curve on the head; (2) a point added or deleted with an action
  selected goes to the END.
  - **The rule.** In an action whose eased progress is t = `ease(action.curve, progress)`, a
    channel whose held (start) curve `a` and whose clamped end curve `b` are both non-identity and
    have different point counts renders, at every x, `(1 − t)·a(x) + t·b(x)`, a and b each its own
    spline (GR-12's, or GR-32's periodic one for a hue curve, in its units: degrees for Hue vs
    Hue, a gain for Hue vs Sat). It is exact at both ends: t = 0 is a, t = 1 is b. Two curves of
    the same count keep §5.4's per-point lerp, and an identity meeting another count keeps
    GR-12's alignment, so every render those reach is byte-identical.
  - **Where the blend lives.** Only in the recipe's `curves` and in `clip_state`'s
    `video.curves`, and only for 0 < t < 1: the channel is `{"from": [[x, y], …], "to": [[x, y],
    …], "t": t}` (keys in that order) where it is otherwise a point list. Outside an action, at
    t = 0 and from the action's end on, the channel is plain points, so t = 0 is today's bytes
    and the end is `b`. The blend is never in a file: the model, `get_project`, a split, a paste
    and the patch template hold points. The evaluated `VideoProps` holds `from` (the list rule
    holds the list at its start value), so the inspector and every other reader of the evaluated
    props see `a` until the end. `ungraded` publishes no blend (GR-4). Swift decodes a blended
    channel as its `from` points plus the blend, and the strip samples it as the blend of its two
    splines, in Double before the Float store; a channel's strip at t = 0 and t = 1 is the plain
    strip of `from` and of `to`, bit for bit.
  - **The inspector's write rule** (owner choice 2): with an action selected, every curve write
    goes to the action's END, a count change included (CI-2's rule for every other edit); the
    curve is then keyed and blends over the action. GR-12's BASE branch for a count change between
    two curves is gone.
  - **A split** (owner choice 1) inside a blending action writes the evaluated points as the
    head's end (`state_patch`), which is `a`, so the head holds `a` and no longer changes; the
    tail's base is `a` and its action blends `a → b` over the remainder. No jump at the cut.
  - **Not:** no format, FFI, op, op-table, tool or `LayerUniforms` change; no spline in Rust; no
    resampling of either curve (#271's resampling moves the curve at the action's start: GR-24's
    measurement); no blend for `video.filters` or `video.obscure`; the editor does not draw the
    blended curve.
  - Risk accepted: the halfway frames of a mismatch differ from what a per-point lerp of a
    resampled pair would give (the tier-4 brief measured p95 190 ten-bit levels on random pairs);
    a split's head no longer changes.
- **GR-35 — The qualifier's cleanup blur: `video.qualifier.blur` 0…1, a Gaussian of q with
  σ = 24·blur canvas pixels; format 21.** Recorded in T4-4 before its code; it settles GR-24's
  T4-4 item (#268) and amends GR-13. The owner's choices (as recommended): (1) the inspector shows
  0–100 %, like every Amount row; (2) 100 % is σ 24 canvas pixels, the blur filter's 24 px reach
  and the brief's largest measured σ; (3) the row is the house slider and field, reset by its
  default and the section's Reset (no ⌥-fine drag, no double-click to 0: only the range strips
  have them); (4) a blur set with no range is kept and saved and draws nothing.
  - **The key.** `video.qualifier.blur`, 0 off, bounds 0…1 inclusive, refused never clamped, in
    `in_range`'s sentence (`video.qualifier.blur must be between 0 and 1, not 1.5`), checked after
    luma. Written only when above 0, after `invert`. Neutral is no range, not inverted and blur 0,
    so a blur alone is kept, saved, refused on a picture clip like any non-neutral qualifier, and
    draws nothing.
  - **Actions.** An action's end is clamped (non-finite → 0, then 0…1). Inside an action the blur
    interpolates whenever both states hold a qualifier, an absent blur reading 0; a qualifier
    turned on switches at the end, as a range does.
  - **Follows the qualifier.** Show Ungraded, Paste Attributes and Pick from Canvas: the blur goes
    where the qualifier goes, and a pick leaves it alone.
  - **The unit.** σ = 24·blur CANVAS pixels; Swift divides by `canvasPerDest`, so a Half or Quarter
    preview blurs the same share of the picture as an export. The core never computes σ.
  - **The path.** The map path runs when a range is on, blur > 0, σ_dest = 24·blur/canvasPerDest
    ≥ 0.5 and MPS is supported (σ capped at 100); otherwise the pass is today's inline path,
    byte-identical. On the map path the adjustment pass suspends the destination pass, renders q
    from the target into an `r16Float` destination-sized map, blurs it with
    `MPSImageGaussianBlur` (`.clamp`, the shadow's kernel cache, σ quantised to a quarter pixel)
    into its pair, and resumes with `.load`; the adjust fragment then reads the blurred q at
    `texture(0)` instead of computing it, behind `blurred` (the block's reserved float, so
    `QualifierUniforms` stays 64 bytes). Full resolution, not half (choice 6a).
  - **Only q is blurred, never the coverage.** The matte coverage is multiplied after, unblurred:
    a matte track's edge is its own. Show Selection and `render_frame {selection}` draw the blurred
    q × coverage.
  - **Memory and cost.** The pair, 2 × 16.6 MB at 4K, is held per renderer once drawn and replaced
    when the destination's size changes. The pass's cost is `grading_spike.py`'s TB (the
    adjustment pass with the blur on, over the inline qualifier), recorded in T4-4's record.
  - **GR-6 is unchanged:** the blur FILTER on an adjustment clip stays refused; this is a key
    inside `video.qualifier`.
  - **Format 21:** the key is optional, with no migration step; the bump stops an older build
    dropping it on save. A file numbered 1–20 (and 1015) opens and is stamped 21; 22 and above,
    1014 included, are newer.
  - **Not:** no half-resolution map; no denoise, clean black or clean white (Resolve's other
    Matte Finesse controls); no blur of the matte; no ⌥-fine or double-click on the house slider.
  - Risk accepted: 24 px is a first number, judged by GRD-14 on real footage; a blurred qualifier
    is a real share of a heavy 4K frame's headroom, paid only by a clip that uses it.
