# Road map "grading-2" — colour grading, tier 2: scopes, wheels, curves, qualifiers

**Opened 2026-10-10** (G2-0, in the worktree `~/devel/reelcut-grading` on branch `grading-2`,
merged into main after its gate). The design brief this road map answers is
`~/.claude/litecode/reelcut/grading-tier2/I-grading-tier2.md` (2026-10-10, tree `7f6d112`); it
lives outside the repo, so everything a later phase needs from it is written here. Where the
brief and this file differ, this file wins. Tier 1's road map is closed: its condensed record is
`designs/adr/grading.md`, the original `archive/grading.md`, and its decisions are spec §11
GR-1..GR-9 (`designs/spec/11-decisions/grading.md`). Tier 2's decisions are GR-10 onwards, in
`designs/spec/11-decisions/grading-2.md`.

## Goal

Build tier 2 of colour grading, the tools GR-1 deferred as issues: **scopes** (#263), **wheels**
(#260), **curves** (#261) and **qualifiers** (#262), in that order. Each is a phase that lands
whole on main, judged by its own proofs. There is no experiment verdict and no trial phase:
grading is already kept (GR-1), and the owner's feedback waits until he is live. Each phase's
person checks (GRD-11…GRD-15) join `docs/manual-checks.md`'s standing list in the phase that
creates them.

## The owner's choices

**2026-10-10**, verbatim: "choices 1–9 of I-grading-tier2.md section 0 "All as recommended" (1a,
2b, 3a, 4a, 5 yes, 6a, 7 yes, 8b, 9 yes). #258 closed (owner); #257 left for after tier 2." The
choices therefore read:

1. **(a)** All four, in this order: scopes, wheels, curves, qualifiers. The scopes are how the
   other three are judged; qualifiers come last because they use everything before them.
2. **(b)** The scopes panel is two scopes stacked, each picked in its own header (Waveform,
   Parade, Vectorscope, Histogram), opening as Waveform over Vectorscope. View ▸ Waveform becomes
   **View ▸ Scopes**, with the same ⌃⌘W.
3. **(a)** Wheels and curves act after Light and before the look: correct first, then the look
   (GR-7's rule). A look or a LUT then sees the corrected picture.
4. **(a)** A qualifier attaches only to adjustment clips. "Make the skin warmer" is an adjustment
   clip over the footage with a colour range picked; with a shape on a matte track above it, it
   is also limited to a region.
5. **Yes**: a **Show Selection** switch in the Qualifier section (and View ▸ Show Selection, no
   shortcut) draws the picked range white and the rest black in the preview, never in an export,
   not saved, off when a project opens (Show Ungraded's rules); and a **Pick from Canvas** button
   centres the hue, saturation and luma ranges on a clicked pixel.
6. **(a)** The controls are more sections on the Color sub-tab, in this order: Adjustment ·
   Qualifier · Light · Color · Wheels · Curves · Look. Qualifier appears only on adjustment clips;
   every section opens and closes as today.
7. **Yes**: three wheels (Lift, Gamma, Gain), no Offset wheel; curves Master, Red, Green and Blue,
   with no hue-against-hue or hue-against-saturation curves; a qualifier of hue, saturation and
   luma ranges with softness and Invert, with no cleanup blur of the selection. Each extra can be
   its own issue once there is feedback.
8. **(b)** One worktree outside the repo folder (`~/devel/reelcut-grading`, branch `grading-2`).
   Each phase is merged into main as soon as its `make gate` passes, and the branch starts the
   next phase from main.
9. **Yes**: no trial phase and no keep-or-drop gate. Each phase is kept when its proofs pass.

## Tier 2 as answered

- **Scopes first** (#263): grading colour without seeing it is guesswork, and wheels are read on
  the parade and the vectorscope. They change no project file and no picture: no project key, no
  format number. Tier 1 moved one scope up for the same reason.
- **Wheels second** (#260): lift, gamma and gain, each a colour push and a brightness strip. Nine
  numbers per clip, applied right after Light. The most-used tier-2 control, the smallest model,
  and the phase that grows `LayerUniforms` (once, with room for the curves' flag).
- **Curves third** (#261): Master, Red, Green and Blue, drawn as points on a smooth curve that
  never overshoots, sampled through a 1D lookup strip, not the look's 3D lattice. A texture slot,
  a cache and the hardest editor, but no new concept in the core beyond a list of points.
- **Qualifiers last** (#262): "grade only the skin" or "only the sky". A qualifier lives on an
  adjustment clip, so a secondary correction is an adjustment clip with a colour range. Tier 1's
  power window (an adjustment clip under a matte) is already the same thing for a shape. They
  depend on adjustment clips, the eyedropper machinery, the vectorscope (to see a hue), and wheels
  and curves (to be worth qualifying).
- **All four belong**: each is in every editor's primary/secondary toolset, and none needs tier 3.
  The narrowest cuts were choice 7's; dropping a whole tool was choice 1(b), not taken.
- **Qualifiers need the selection view** (choice 5): softness and edges cannot be judged on a
  graded picture, and an agent needs `render_frame {selection}` to check one.

What each issue asks (all four filed 2026-10-10 at tier 1's merge, `ai-drafted`, `low-priority`,
each quoting GR-1's "tiers 2 and 3 are deferred as issues, not out"; each says "done" is a §11
entry before code, a `render_frame`-bytes or probe proof on a fixture, and a GRD row on footage):
- **#260 wheels**: lift, gamma and gain (shadows, midtones, highlights) as three colour offsets
  plus a master each, "applied in the layer stage beside step 4c on straight colour". It notes
  that tier 1's inspector held four sections, so more is a new decision (choice 6). Adjustment
  clips and actions carry it for free.
- **#261 curves**: "a master curve and per-channel red, green and blue curves (control points, a
  monotone spline)", "either a 1D lookup texture per curve or a bake into the layer's 3D look
  lattice" (answered: a 1D strip, below), and "an action interpolating a curve needs a rule for
  lists of points (spec §5.4's LIST rule)".
- **#262 qualifiers**: "select a range of hue, saturation and luma (with softness) and grade only
  that range", "multiplied into the grade's weight the way the matte coverage is", plus "a 'show
  the selection' view … preview only, never an export".
- **#263 scopes**: "a vectorscope, an RGB parade and a histogram" on "the same tap and panel",
  with `render_frame`'s mirror extended. **Its time bound is replaced by GR-10's** (below,
  "Costs"): it held a further scope to the waveform's "0.168 ms at 1080p and 0.331 ms at 4K",
  which is the wrong yardstick for a vectorscope.

## How it fits the tree

### What tier 1 left (read in the tree at `7f6d112`)

- **The stage order** (`Compositor.metal`, the comment above `layerColorPremultiplied`): 1 zoom
  remap, 2 pixelate, 3 sample (chroma key, then Color's four — brightness, contrast, saturation,
  hue — inside `gradeSample`, once per blur tap), 4 blur/sharpen, 4b obscure, **4c tone**
  (`gradeTone`, behind `toneEnabled`), **4d the look** (`gradeLook`, `texture(2)`, behind
  `lookEnabled`), 5 point filters, 6 spotlight dim, 7 coverage (corner × nest × matte at
  `texture(1)`), 8 transition weight, 9 opacity, 10 premultiply, 11 blend.
- **`video.color`** holds Color's four and Light's nine, each written only when not 0 (GR-2).
  `toneEnabled` and `lookEnabled` join the effects block's gate sum, so an ungraded layer never
  enters 4c or 4d and renders byte-identical (GR0's route VF).
- **`LayerUniforms`** is 116 floats / 464 bytes (`LayerUniforms.swift`, mirrored field for field in
  `Compositor.metal`); the tone group's last two floats became `lookAmount` and `lookEnabled`, so
  **there is no spare float left**.
- **The 4d lattice**: a 33³ `rgba16Float` 3D texture at `texture(2)`, baked on the GPU by
  `reelcut_look_bake` from a look's definition, or uploaded from a `.cube` (`LookTextures`,
  `LutTextures`, LRUs of eight); a 2³ identity placeholder is bound and never sampled when there
  is no look.
- **Adjustment clips**: `reelcut_adjust_fragment` reads `[[color(0)]]` with blending off,
  un-premultiplies, runs `gradeSample` (chroma off), tone, look and the point filters, and writes
  `mix(dst, graded, w)` with `w = saturate(opacity × matte)`.
- **Seeing**: `Waveform.metal` (`reelcut_waveform_bin`, one global atomic add per pixel into 256 ×
  256 counts), `WaveformAnalyzer.swift` (`WaveformTrace`, the pass, `analyze(image:)` for
  `render_frame`), `WaveformTap.swift` (`WaveformTaps`: own queue and texture cache, one pass in
  flight per window, ONE pending frame replaced by each newer one), `WaveformPanelView.swift` (a
  fixed 248 pt column), `EditorViewController+Seeing.swift` (View ▸ Show Ungraded ⌃⌘U, View ▸
  Waveform ⌃⌘W), `render_frame {ungraded, waveform}`.
- **The Color sub-tab**: `ClipPane.makeSections()` `case .color`: Light, Color, then Look; with
  Adjustment's Strength first when every selected clip is an adjustment clip.
- **Inspector rows** drag live: `inspectorValueRow`'s slider calls the binding's `liveBegin` /
  `liveUpdate` / `liveEnd(name)`, and each tick applies to the handle the gesture started from, so
  **a drag is one undo step** named after the row (`ProjectDocument`'s live-edit trio).

### Where each new stage runs, and why

| Step | What | Why there |
|---|---|---|
| 4c | tone (Light), unchanged | — |
| **4c.1** | **wheels**: lift, gamma, gain, analytic, behind `wheelsEnabled` | After tone, because exposure and white balance are the corrections a wheel refines (a cast is judged after white balance). Before the look: choice 3. |
| **4c.2** | **curves**: three samples of a 1D strip at `texture(3)`, behind `curvesEnabled` | After the wheels, as their fine trim. Before the look: choice 3. |
| 4d | the look, unchanged | — |
| 7 (adjustment pass only) | **the qualifier weight** `q`, computed from the destination colour BEFORE the grade | `w = saturate(opacity × matte × q)`: the pass's existing weight, computed on what is behind, because "the skin" means the skin as it is, not as the grade has made it. |

The adjustment pass gains 4c.1 and 4c.2 in the same place as the layer stage (after tone, before
the look), so a grade on an adjustment clip means what it means on a clip. The look bake
(`reelcut_look_bake`) is unchanged: a look is still Color, Light and split tone (GR-7), and wheels
and curves are the clip's own, not part of a look.

### Wheels (#260), G2-2

- **The model**: `video.wheels: {lift, gamma, gain}`, each `{x, y, master}`, each key written only
  when not 0. `x, y` is the puck's position in the wheel (−1…1, inside the unit circle: refused
  when x² + y² > 1); its angle is the hue on the HSV ramp the split tone already uses (0° red,
  120° green, 240° blue, `lookHueChroma`), and its distance is the strength. `master` is −1…1.
  Cartesian, not hue-and-amount, so an action from neutral to a push moves in a straight line
  through the centre; hue-and-amount would sweep through every hue on its way (§5.4 lerps
  numbers).
- **The maths** per channel c, on encoded values (Reelcut's own strengths, first numbers from the
  phase's spike, tuned later like GR-2's): `push_c = k · hypot(x, y) · chroma(atan2(y, x))_c`,
  where `chroma` is `lookHueChroma` (a fully saturated hue less its own Rec. 709 luma, so a push
  moves no brightness) and k is the strength; `o_c = master + push_c` for each wheel; then lift
  `v = v + o_lift · s_l · (1 − v)` (moves black, holds white), gain `v = v · (1 + o_gain · s_g)`
  (moves white, holds black), gamma `v = max(v, 0)^(2^(−o_gamma · s_γ))` (moves the middle, holds
  both ends). That is the textbook lift/gamma/gain shape, the same algebra as the ASC CDL's slope,
  offset and power.
- **Uniforms**: the nine model numbers in model order, then `wheelsEnabled`, `curvesEnabled` and
  one reserved: a group of twelve, **116 → 128 floats, 464 → 512 bytes** (32 × 16). The shader
  does the puck-to-RGB mapping (one implementation, beside the split tone that shares `chroma`).
- **Not folded into the curve strip** (they are per-channel too): an animated wheel would re-bake
  the strip on every frame of the action. Analytic, they cost nothing measurable in the brief's
  spike ("Costs").

### Curves (#261), G2-3: a 1D strip, not the lattice, not uniforms

- **The model**: `video.curves: {master?, red?, green?, blue?}`, each a list of `[x, y]` points,
  2–16 of them, x strictly rising in 0…1, y in 0…1. A curve equal to the identity is written
  absent (so Reset leaves the file as it was). Refusals in the rule's own sentence
  ("video.curves.red needs 2 to 16 points, not 17"; "video.curves.master: point 3's x (0.4) must
  be after point 2's (0.5)").
- **Interpolation**: a monotone cubic Hermite spline (Fritsch and Carlson, 1980). It passes
  through every point and never overshoots between them, so a curve that only rises never dips.
  Per channel, the composite is `channel(master(v))`: the master sets contrast for all three, and
  a channel curve trims one colour of the contrasted picture.
- **The texture**: one `rgba32Float` strip of 1,024 texels at **`texture(3)`**, r, g and b holding
  the three composites, sampled linearly at `v·(n−1)/n + 0.5/n` (4d's texel-centre rule); a 2×1
  identity placeholder is bound and never sampled behind `curvesEnabled`. Cached by the curves'
  JSON in an LRU of eight, beside the looks' cache. The brief's spike measured ≤ 0.154 of a 10-bit
  level from the exact curve even on a steep one, against ≤ 0.5 for `rgba16Float`, half-float
  storage's own floor ("Costs"). `rgba32Float` filtering was supported on the measured M2 Max;
  every Apple-silicon Mac is Apple GPU family 7 or later, and the app is arm64 on macOS 26
  (`project.yml`), so it is REASONED to hold on every Mac Reelcut runs on. `rgba16Float` is the
  fallback, still under one 10-bit level.
- **Why not the 3D lattice**: the lattice slot holds the look or the LUT, so a clip with both
  would need a bake per (curve, look) pair, and an imported LUT would lose its own size. A 33³
  lattice is up to 3 levels off an analytic curve (tier 1's C3) where the strip is within a sixth
  of a 10-bit level. And curves are per channel, which is exactly what a strip holds.
- **Why not uniforms**: four curves × 16 points × 2 is 128 floats, plus a segment search per
  channel per pixel.
- **Where the spline lives: Swift, one implementation** (`CurveTable.swift`), used by both the
  editor's drawing and the strip's upload. The core stores, checks and interpolates the points
  (actions) and publishes them in the recipe; it never samples the spline. That keeps "no pixel
  or sample work in Rust", needs no new FFI export, and leaves `ReelCore.swift` untouched (it is
  over the cap with no seam named, and the only file allowed to call `rc_*`). A probe over
  `app/Sources` proves the maths. The alternative (the spline in the core as `rc_curve_table`,
  testable with `cargo test`) would cost that file a toll first.
- **Actions**: §5.4's list rule already covers it with no new code (`actions.rs` `lerp_at`: arrays
  of the same length interpolate per index, recursively, so `[x, y]` pairs interpolate; different
  lengths switch at the end). A convex mix of two rising x sequences still rises, so an
  interpolated curve stays valid; the evaluator's clamp is the last guard.

### Qualifiers (#262), G2-4, on adjustment clips (choice 4)

- **The model**: `video.qualifier: {hue?, saturation?, luma?, invert?}`, on an adjustment clip
  only. `hue: {center, width, softness}` in degrees (the HSV ramp the wheels and split tone use);
  `saturation` and `luma: {low, high, softness}` in 0…1. A missing range passes everything.
  Saturation is chroma, max − min of the encoded RGB; luma is Rec. 709 Y′ of the encoded values,
  the waveform's.
- **The weight**: `q = q_hue · q_sat · q_luma`, each 1 inside its range and falling to 0 across
  `softness` by a smoothstep, then `1 − q` when inverted. **A pixel with almost no colour has no
  hue**, so a hue range fades out below a small chroma (a fixed guard, about 0.02–0.06, set by the
  phase's fixture). Without it every grey reads as hue 0° and a red range would grade every grey.
  `q` multiplies into the adjustment pass's existing `w`. A matte track over the adjustment clip
  still cuts it, so shape × colour range is the classic secondary.
- **Uniforms**: a small `QualifierUniforms` block at `buffer(1)` of the adjustment pass only,
  about twelve floats. `LayerUniforms` does not grow for it.
- **On other clips**: `set_video {qualifier}` on a clip that is not an adjustment clip is refused
  in the rule's own sentence. For Paste Attributes FROM an adjustment clip ONTO a picture clip,
  GR-6's precedent (stored placement keys kept and inert) points to "dropped from the paste, said
  in its answer"; G2-4's design settles it, with a row.
- **Show Selection** (choice 5): a recipe option `selection: <clip id>`, Show Ungraded's pattern
  (GR-4): on the preview's KEY only, never an export override, not persisted, and taken by
  `render_frame {selection}` for agent parity. The core marks that adjustment clip's layer and
  leaves out every layer in front of it; the pass then writes `q` as grey.
- **Pick from Canvas**: a third `CanvasModalMode` beside the chroma eyedropper and the region band
  (`armCanvasMode` already ends the others). It samples the picture BEHIND the adjustment clip,
  rendered with that clip left out (the eyedropper already renders without the grade), and centres
  the three ranges on the pixel with default widths. One undo step, "Qualifier".

### Scopes (#263), G2-1

Spec §11 GR-10 is the decision; this is its summary.
- **What they read**: GR-5's frame, unchanged: the composited, encoded preview frame at Preview
  Quality's size, after the compositor, by the same latest-wins tap, only while shown. When two
  are shown, both passes go into the one command buffer per offered frame.
- **The three**: the **parade** (R′, G′ and B′ each binned as the waveform bins Y′, 256 column
  bins × 256 levels, drawn side by side in red, green and blue tints with the waveform's clip
  marks per channel); the **vectorscope** (Rec. 709 `Cb = (B′ − Y′)/1.8556`, `Cr = (R′ −
  Y′)/1.5748`, 256 × 256 bins **centred on neutral** so a grey lands mid-bin, log density, the six
  75 % targets from the same matrix, and the skin line from the ColorChecker "light skin" patch);
  the **histogram** (R′, G′, B′ and Y′ counts per 256 levels, overlaid, with the waveform's two
  clipping readouts).
- **How they count**: never one global atomic per pixel into a shared counter. The histogram
  counts per threadgroup and merges once per group; the vectorscope counts the central 64 × 64
  bins per threadgroup and the rest globally; the parade may stay as the waveform is, with a
  per-band threadgroup count as the fallback if its time row misses.
- **The panel**: the 248 pt column stays; two slots stacked, each with a picker in its header; the
  vectorscope square at the slot's width; below a pane height G2-1 sets from screen `04b`, only
  the top slot shows. Not persisted, per window, as GR-5. View ▸ Waveform becomes View ▸ Scopes
  (⌃⌘W kept).
- **The mirror**: `render_frame {parade, vectorscope, histogram}`, three booleans beside
  `waveform`, each writing `<path>.<scope>.json` through the panel's own analyser on the rendered
  image, so the panel and the tool cannot count differently (GR-5's rule).

## The editing surface

All at the inspector's real width: the panel is 304 pt by default (`DS.panelWidth`), resizable
280–440 (`EditorViewController.minInspectorWidth` / `maxInspectorWidth`); the section inset is 10
pt each side, so the content is **284 pt** wide by default and 260 pt at the minimum. **Corrected
in G2-2:** a section's row is 268 pt at the default pane and 244 pt at the minimum (the pane's
scroller and insets, `DocumentPane.swift:353`, come off as well), so the 84 / 76 pt discs below
were never available; GR-11 records the measured layout (a disc about 78 pt at the default pane). The sharp
handoff: every chrome component square (`controlRadius`, `buttonRadius` 0); the slider knob a 7 ×
11 pt block. A colour wheel is round because it is a picture of the hue circle, but its frame, its
puck and its strip's knob follow the square rule.

### Wheels section (closed until used)

```
▾ Wheels                                         adjusted  ↺
   Lift              Gamma             Gain
  ┌────────┐        ┌────────┐        ┌────────┐
  │  (◯·)  │        │  (◯ )  │        │  (◯ )  │   84 pt discs (76 at the minimum):
  └────────┘        └────────┘        └────────┘   hue ring, a 7×7 square puck
  ━━━▮━━━━━         ━━━━▮━━━━         ━━━━▮━━━━    master strip, 7×11 block knob
  [ 0.05 ]          [ 0.00 ]          [ 0.00 ]     master field, 2 decimals
```
- **Gestures**: drag the puck (the live trio: one undo step, named "Lift", "Gamma" or "Gain");
  drag the strip (one step, the same name); double-click a puck to reset its colour, double-click
  a strip to reset its master; the section's Reset zeroes all nine (undo "Wheels"). ⌥-drag moves
  at a tenth of the speed, a convention new to Reelcut (`InspectorSlider` has none), so it is
  written into GR-11.
- **Mixed selection**: the puck and strip show the first clip's value with the mixed badge. A drag
  writes absolute values to every selected clip, as the sliders do.
- **Row marks**: one per group key (CI-7, CI-9), so `wheels` has one mark for all three.
- **Numbers**: the master is typed in its field. The colour push has no field (two numbers per
  puck would not fit three across at 284 pt); it is exact through MCP. This is the first
  inspector control without a typed entry, so it is a deliberate line in GR-11.

### Curves section (closed until used)

```
▾ Curves                                         adjusted  ↺
  [Master][ Red ][Green][ Blue ]                     square segmented cells
  ┌──────────────────────────────────────┐
  │ · · · · · · · · · · · · · · · · · ·  │   264 × 264 pt (240 at the minimum):
  │       grid at 25 %, the diagonal     │   a 4 × 4 grid, the identity diagonal,
  │       ■ points, 7×7 square handles   │   the curve in the channel's colour
  └──────────────────────────────────────┘
  Point   In [ 0.250 ]   Out [ 0.180 ]   Delete
```
- **Gestures**: click on the curve to add a point (one step, "Curves"); drag a point (the live
  trio, one step); ⌫ or a double-click deletes the selected point (one step); the arrow keys nudge
  the selected point by 0.01 (⇧ 0.1), one step each; the In/Out fields type it exactly. The two
  end points move too (setting black and white points), but no point passes its neighbour: a drag
  is held between them. The section's Reset clears all four curves; the picker's channel has its
  own "Reset Red" in the cell's context menu.
- **The other channels** are drawn faintly behind the one being edited. A histogram behind the
  curve (from the scopes' tap) is a later nicety, not in G2-3.

### Qualifier section (adjustment clips only, after Adjustment)

```
▾ Qualifier                                           on   ↺
  ☑ Hue          [ hue spectrum strip, centre/width/soft handles ]
                 Centre [ 30° ]  Width [ 40° ]  Soft [ 20° ]
  ☑ Saturation   [ grey→colour strip, low/high/soft handles     ]
                 Low [ 0.15 ]  High [ 1.00 ]  Soft [ 0.05 ]
  ☐ Luma         [ black→white strip                            ]
  ☐ Invert
  [ Pick from Canvas ]   ☐ Show Selection
```
- Three fields at 58 pt plus gaps need about 194 pt, the width left beside a 76 pt label, so each
  range is two rows: the strip, then its fields. A row's checkbox turns that range off (stored
  absent). Drags on a strip use the live trio; undo names are the row labels.

### What the agent sees (the MCP mirror)

No new op and no new tool, as tone and looks did (GR-2, GR-7): `set_video` already takes `patch`
as an Object (`op_table.rs`), so the new keys cost prose in `AgentCatalog+Properties.swift` and
nothing in the argument half.
- A wheel: `set_video {clips, patch: {wheels: {lift: {x: 0.2, y: -0.1}}}}` (an absent key keeps
  its value; `master` alone is fine).
- A curve: `set_video {patch: {curves: {master: [[0,0],[0.25,0.18],[0.75,0.82],[1,1]]}}}`. An
  array replaces its list whole (`patch.rs`), so an agent sends the whole curve. `curves: {red:
  null}` removes one.
- A qualifier: `set_video {patch: {qualifier: {hue: {center: 25, width: 30, softness: 15}}}}`.
- Seeing: `render_frame {selection: <clip id>}`, `render_frame {parade|vectorscope|histogram:
  true}`.
- Each call is one undo step, as every op is. An agent never drags, so the live trio is the
  inspector's alone, and the end state of a drag is one `set_video`, exactly what the agent would
  send.
- The panel's slot pick and Show Selection are view state with no tool, as GR-4's and GR-5's are
  (§7.9's exemption); the eyedropper's result is a `set_video`.

## The standard recipe, file by file, and the tolls

The ledger is `wc -l app/Sources/*.swift core/src/*.rs graphic/src/*.rs | sort -rn`. The cap is
~600 lines, new files 400, and frozen files (`EditorViewController.swift`, `TimelineView.swift`,
`PreviewCanvasView.swift`, `AgentServer.swift`) take wiring only. Size is per file only (root
`CLAUDE.md`): nothing here is a budget on a feature or a phase, and a feature takes as much code
as it needs.

### Tolls (G2-0, pure moves gated before any tier-2 code)

| File | Lines at `7f6d112` | Why it is touched later | The move |
|---|---|---|---|
| `ProjectSnapshot.swift` | 1,570 | `VideoProps` gains `wheels`, `curves`, `qualifier` | Its named next seam: `ColorAdjust` out whole to `GradeProps.swift`. New snapshot types go there. |
| `AgentServer+Render.swift` | 584 | `render_frame` gains `parade`, `vectorscope`, `histogram`, `selection` | No seam was named; the brief named one: `writeWaveform` (the scope writers' home) out to a new `AgentServer+Scopes.swift`. |
| `AgentCatalog+Files.swift` | 579 | `render_frame`'s four new argument rows | No seam was named; the brief named one: the rows under `// MARK: Rendering and export` out whole to `AgentCatalog+Render.swift` (the file's own MARK seams are its precedent). |
| `core/src/recipe.rs` | 548 | the `selection` option, and the new keys' neutralising under `ungraded` | No seam was named; the brief named one: `RecipeOptions` and its reader out to `recipe_options.rs`, as the Swift side already did (`RecipeOptions.swift`). |
| `Compositor.swift` | 723 | only if the curve cache must be a stored property of `MetalRenderer` | Its named seam: `DestinationPass` out whole. **Avoided** if the strip cache hangs off `LookTextures` (both are grade textures keyed by a definition); G2-3's design picks. |

Not tolls: `VideoPane.swift` (904) is not touched (each new section is an extension in its own
file, `VideoPane+Light.swift`'s pattern), and its named seam (`chromaSection`) is paid only if it
must change. `ReelCore.swift` (989) is not touched, because the spline is Swift.

### Core

| Step | Files | Note |
|---|---|---|
| Model | new `model_grade.rs` (`Wheels`, `Wheel`, `Curves`, `Qualifier`, `HueRange`, `Range`), re-exported whole (the `model_look.rs` pattern); `model_props.rs` gains three `VideoProps` fields | serde defaults; written only when not neutral |
| Checks | new `grade_check.rs`, called from `props_check.rs` | ranges, point count and order, x² + y² ≤ 1, a qualifier only on `Source::Adjustment` |
| Evaluate | `actions_clamp.rs`: clamp each new value; the list rule needs no code (`actions.rs`) | a NaN to neutral; a curve whose x no longer rises becomes absent |
| Recipe | `recipe_layer.rs`: `wheels`, `curves` always present (Swift's lenient decoder would default a missing key silently); the qualifier on adjustment layers; `recipe_options.rs`: `selection`; `ungraded` neutralises wheels and curves | |
| Format | `format.rs` + the header's `#define`: **16** (wheels), **17** (curves), **18** (qualifiers); `core/tests/schema_v16.rs`… | optional keys, no migration step; the bump stops an older build dropping them on save |
| Ops | none: `set_video {patch}` carries all three; `edit.rs` and `op_table.rs` unchanged | the parity check sees nothing new |
| Tests | new `core/tests/wheels.rs`, `curves.rs`, `qualifier.rs`, `selection.rs` | each range's refusal; neutral = absent; actions (curves per index, switch on a count change); `paste_attributes`; the recipe at a tick |

### Swift and Metal

| Step | Files | Note |
|---|---|---|
| Snapshot | `GradeProps.swift`: `Wheels`, `Curves`, `Qualifier`; `VideoProps` fields in `ProjectSnapshot.swift` (wiring) | |
| Recipe decode | `FrameRecipe.swift` | |
| Uniforms | `LayerUniforms.swift` and `Compositor.metal`'s struct: +12 floats → 128 / 512 bytes; `Compositor+Uniforms.swift` fills them | the block's size is asserted in about ten instruments (`grep -rln '464\|layerUniformsSize\|blockBytes' tools/proof`; some hits are other numbers); each moves in the same change, GR2's precedent |
| Shader | `Compositor.metal`: `gradeWheels`, `gradeCurves` in the stage and the adjustment pass, the qualifier weight, the selection output | a split into headers stays optional |
| Strip | new `CurveTable.swift` (the spline, the composite), new `CurveTextures.swift` or a section of `LookTextures.swift`; bound at `texture(3)` in `Compositor+Dissolve.swift` and `Compositor+Adjustment.swift` | |
| Scopes | `Waveform.metal` → a `Scopes.metal` beside it (or grown); `WaveformAnalyzer.swift` generalised to the four, `WaveformTrace` kept; new `ScopeTraces.swift` (parade, vectorscope, histogram types and `json()`); `WaveformTap.swift` passes the shown set; `WaveformPanelView.swift` becomes the two-slot panel, with new `VectorscopeView.swift`, `ParadeView.swift`, `HistogramView.swift` | |
| Inspector | new `VideoPane+Wheels.swift`, `VideoPane+Curves.swift`, `VideoPane+Qualifier.swift`; new controls `ColorWheelControl.swift`, `CurveEditorView.swift`, `RangeStripControl.swift`; `ClipPane.makeSections()` registers them | an unregistered section is invisible (a measured tier-1 pitfall) |
| Patches | `TypedPatches.swift`: `VideoPatch` gains three; `OpDictionaries.swift` | |
| Menus | `AppDelegate+Menus.swift`: View ▸ Waveform → Scopes; View ▸ Show Selection; `EditorViewController+Seeing.swift` | the menu inventory (`capture_spike/inventory.py --check`, in `make test`) gains or renames rows |
| Eyedropper | `EditorViewController+Eyedropper.swift`: Pick from Canvas as a third mode, or a new `EditorViewController+Qualifier.swift` | |
| MCP | `AgentCatalog+Properties.swift`: `set_video`'s prose; `AgentServer+Scopes.swift`; `AgentCatalog+Render.swift` | the root `CLAUDE.md`'s "ninety product tools" is unchanged |

### Documents (each phase's own)

Spec §4.2 (the scopes panel, Show Selection), §4.3a (the Color sub-tab's sections), §5.2 (the
fields, formats 16–18), §5.4 (a sentence: curves interpolate per point), §7.3 (the recipe keys,
the `selection` option), §7.5 (steps 4c.1 and 4c.2, `texture(3)`, the qualifier weight, the scope
kernels and their counting rule), §7.9a (`render_frame`'s arguments, `set_video`'s keys), §9 (View
▸ Scopes, Show Selection); the spec index's Lines cells; `app/CLAUDE.md` and `core/CLAUDE.md` map
entries; the README's grading bullet; `docs/manual-checks.md` rows; the screen catalog
(`04b-preview-waveform` becomes scopes; new `05f-clip-wheels`, `05g-clip-curves`,
`05h-clip-qualifier`).

## Preview, export and `render_frame`; precision

- **Parity by construction.** Wheels, curves and the qualifier are recipe keys and uniforms drawn
  by the one compositor that serves the preview (`AVVideoCompositing`), `render_frame` and both
  export writers (spec §7.3, §7.5). Each phase's proof still checks it: an export frame against
  `render_frame` at the same tick.
- **View state never reaches an export**: Show Selection (like Show Ungraded) travels on the
  preview's key; an export, Save Frame…, the look gallery's thumbnails and the eyedropper mint
  their own options. The scopes read the preview frame and have no export path (GR-5, GR-10).
- **Precision.** Every new stage runs in 32-bit float inside the fragment, between `rgba16Float`
  targets (PR-1), on sources decoded deep (PR-2). The curve strip is `rgba32Float`; a stacked
  grade keeps its levels by construction (GR-3). The wheels' gamma is a `pow` on a value clamped
  at 0. A 10-bit export of a graded clip is as deep as tier 1's.
- **What the scopes read**: the composited preview frame, `64RGBAHalf` or `32BGRA` (the tap wraps
  both), at Preview Quality's size: 3840 × 2160 at Full on a 4K canvas, a quarter of that at Half.
  The bins are 256 levels, so a scope shows no detail finer than 8 bits: GR-5's stance, and a
  1,024-level scope is a later choice.
- **An ungraded layer's cost** is the real risk, as in tier 1: the new flags join the gate sum
  (GR0's route VF), so an unwheeled, uncurved layer should not move. G2-2 and G2-3 each re-run
  `grading_spike.py --measure --tree`'s TC row and hold tier 1's bound (+0.02 ms at 1080p, +0.06
  ms at 4K over the commit before).

## The Concat rule

**Concat (`~/devel/Concat`) is AGPL-3.0-or-later. None of its code, shaders, chains or colour
tables may be carried over** (root `CLAUDE.md`; `designs/adr/effects-survey.md`). That holds at
design time and build time: no curve table, matrix, wheel response or qualifier shape, and no
opening its files to "match" one. The brief consulted nothing of Concat.

Instead, public and textbook sources, plus Reelcut's own numbers:
- **Wheels**: the lift/gamma/gain formula as found in any colour-correction text (lift a linear
  offset held at white, gain a slope held at black, gamma a power held at both ends), the same
  algebra as the ASC Color Decision List (`out = (in × slope + offset)^power`), a published ASC
  specification. The colour push reuses tier 1's own `lookHueChroma`. The strengths are Reelcut's
  own, first set by the phase's spike and tuned by eye later (GR-2's precedent).
- **Curves**: monotone cubic Hermite interpolation, F. N. Fritsch and R. E. Carlson, "Monotone
  Piecewise Cubic Interpolation", SIAM Journal on Numerical Analysis 17(2), 1980.
- **Qualifiers**: the HSV hue (textbook), chroma as max − min, Rec. 709 luma, and a smoothstep
  (the Hermite `3t² − 2t³`, Metal's own `smoothstep`) for softness.
- **Scopes**: Rec. 709 Y′ weights (already in the tree), the Rec. 709 Y′CbCr matrix (ITU-R
  BT.709-6), the 75 % colour-bar targets computed from it, and histogram and parade counting. The
  skin line's angle is computed from the matrix and the ColorChecker Classic "light skin" patch,
  and written in GR-10 with its source.
- **Fixtures** (hue wheels, grey ramps, 75 % bars, near-grey noise) are drawn by the proof
  scripts.

## Spec §11: the plan

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies: wheels, curves and the
qualifier are data the core checks, not a runtime), R5-5, G-1, §7.5's encoded blending, MT-1..MT-9,
PR-1..PR-5, GR-1 (this is its deferral being taken up), GR-3, GR-8, GR-9.

**Extended or amended by the new entries, each saying so in its text:**
- **GR-2**: `LayerUniforms` 116 → 128 floats (the block grows as GR-2 itself grew it, a
  consequence and not a reversal); the Color sub-tab's sections grow (choice 6). Its own rules
  (keys written only when not 0, refused not clamped, the action's end clamped) are copied for the
  new keys.
- **GR-4**: `ungraded` also neutralises wheels and curves. A neutral adjustment clip with a
  qualifier still draws nothing.
- **GR-5**: amended by GR-10 in G2-0 (the slot picker, View ▸ Scopes, "no other scope" taken up,
  `render_frame`'s three booleans; its tap, latest-wins, preview-only and 256-level rules stand).
- **GR-6**: the adjustment clip's Color sub-tab gains Qualifier, Wheels and Curves; the pass's
  weight gains `q`. Its refusals stand (no blur, so no selection cleanup blur either).
- **GR-7**: the order "Color's four, then Light, then the look, then the point filters" gains
  wheels and curves between Light and the look (choice 3). Looks stay Color, Light and split tone.

**New, in `designs/spec/11-decisions/grading-2.md`**, each with its README row and the Lines
cells, each recorded before its phase's code. The IDs continue the GR- series:
- **GR-10 — Scopes**: recorded in G2-0.
- **GR-11 — Wheels** (G2-2): the keys, ranges and Cartesian puck; step 4c.1; the formula and
  strengths; the uniform group; ⌥ fine-drag; no typed field for the push.
- **GR-12 — Curves** (G2-3): the shape (2–16 points, rising x, identity absent); the monotone
  spline and `channel(master(v))`; step 4c.2; the `rgba32Float` 1,024 strip at `texture(3)` and
  its placeholder; the spline in Swift and not the core; per-point interpolation under §5.4.
- **GR-13 — Qualifiers** (G2-4): adjustment clips only; the three ranges, softness, Invert and the
  chroma guard; where the weight is applied (on the destination, before the grade, times opacity
  and matte); `QualifierUniforms`; the `selection` option and Show Selection; Pick from Canvas;
  Paste Attributes onto a picture clip.
- **GR-14 — Tier 2's working arrangement** (with GR-11, in G2-2): phases merged into main one by
  one, main's format numbers (16, 17, 18), no verdict phase (choices 8 and 9). Kept short.

## Where the work happens

Tier 1 lived in `~/devel/reelcut-grading` on branch `grading`, wrote format 1015 so no main build
could drop its grades, and was merged and renumbered at the end (GR-9). That fitted an experiment
whose "no" would leave it unmerged. Tier 2 is not an experiment (choice 8b):
- One worktree, `~/devel/reelcut-grading` on branch `grading-2`, outside the repo folder and
  outside `.claude/worktrees/`. Each phase: `git merge main` first, then the code, then `make
  gate` in the worktree. When it passes, merge into main (a fast-forward when main has not moved,
  otherwise a merge commit), then start the next phase from main.
- Per worktree: `core/target/` (one cold Rust build), `build/`, `tools/proof/work/`, the generated
  project. Shared: the git objects, and the Debug and Release apps' identities and defaults
  domains (V-5) — harmless, since proofs run under scratch homes and never move defaults.
- **Format numbers**: each phase takes main's next number when its code is written (16, 17, 18).
  If another session bumps main first, the phase renumbers before its merge, which is mechanical
  (the constant, the header, one `schema_vN.rs`, the one-past-current fixtures). The owner has no
  real use yet (2026-10-09), so these optional keys need no migration step.
- **The pure moves** (G2-0) land on main first, as tier 1's GR1 did, so no merge has a moved file
  against an edited one.

## Phases

Each phase is one implement-review cycle, gated and merged into main alone, ending with the root
`CLAUDE.md`'s "Verification" (targeted tests in the loop, `make gate` once when the code is
complete, the phase's proof recorded whole on Release, mutants about one per new decision,
usually 3–8). Criteria are user-facing tasks, speed and correctness.

| Phase | What lands | Its proof holds |
|---|---|---|
| G2-0 | This road map; `11-decisions/grading-2.md` with GR-10; four pure moves (the tolls above): `ColorAdjust` → `GradeProps.swift`; `writeWaveform` → `AgentServer+Scopes.swift`; `AgentCatalog+Files.swift`'s rendering rows → `AgentCatalog+Render.swift`; `RecipeOptions` → `core/src/recipe_options.rs`. The history files record each and name the next seam. | Renders byte-identical before and after; `make test` unchanged; the Debug catalog equal before and after. No mutants: a pure move adds no decision. |
| G2-1 | **Scopes** (#263, GR-10): the kernels with the counting rule; the analyser for four; the tap passing the shown set; the two-slot panel; View ▸ Scopes; `render_frame {parade, vectorscope, histogram}`. | `scopes_proof.py` with a `scopes_probe.swift` over `app/Sources` (as `seeing_proof.py` and `waveform_probe.swift` are): pure R, G, B, C, M, Y cards at 75 % land in the vectorscope bins the matrix gives; a grey card lands in ONE bin (the centring); a channel ramp's parade has its shape in its channel only; a ramp's histogram is flat; the clip readouts; the panel's trace equals `render_frame`'s JSON on the same frame; latest-wins with two scopes shown; harness captures light and dark, each slot pick; the screen `04b` updated. **A time row per scope at 1080p and 4K on GR-10's five fixtures, held to GR-10's bound: ≤ 1.1 ms of GPU per analysed 4K frame, the worst fixture's figure, in the app's own pass, host and power recorded** (it replaces #263's 0.168 / 0.331 ms). Mutants: Cb and Cr swapped; the BT.601 matrix for 709; bins not centred (the grey card splits); global atomics restored (the time row fails); histogram luma weights wrong; a slot pick written to `UserDefaults`. Manual check **GRD-11 — the scopes read right on real footage**: the parade shows a warm cast as red high and blue low; the vectorscope's skin sits near the skin line; the histogram moves with Exposure; both slots while playing; both appearances; Preview Quality Quarter. |
| G2-2 | GR-11 and GR-14 first, then **wheels** (#260): `Wheels`, checks, clamp, recipe, format 16, `core/tests/wheels.rs`; the uniform group (128 floats), step 4c.1 in the stage and the adjustment pass, `ColorWheelControl`, `VideoPane+Wheels.swift`, `set_video`'s prose, `ungraded` neutralising. | `wheels_proof.py`, over MCP, by PNG bytes: neutral wheels byte-identical to the commit before; a grey ramp through each wheel matches the formula (±1); lift moves black and holds white, gain the reverse, gamma holds both ends; a colour push leaves mid-grey's Y′ unchanged (±1); an adjustment clip applies the same wheel as a clip does; export = `render_frame`; undo per op; `ungraded` removes them; Paste Attributes carries them; `grading_spike.py --measure --tree` TC held; a probe that a puck drag is one undo step. Mutants: wheels before tone; gamma's exponent sign; a push that is not luma-neutral; the flag ignoring a negative master; the x² + y² check dropped; `ungraded` missing the wheels. Manual check **GRD-12 — wheels on real footage**: remove a cast with Gain alone while reading the parade; warm the shadows with Lift; ⌥-drag is fine; Reset; both appearances. |
| G2-3 | GR-12 first, then **curves** (#261): `Curves`, checks, identity absent, clamp, recipe, format 17, `core/tests/curves.rs` (with an action between two curves of equal and unequal counts); `CurveTable.swift`, the strip and its cache, step 4c.2, `CurveEditorView`, `VideoPane+Curves.swift`. | A three-point identity curve renders byte-identical to none; a known curve hits its points on a grey ramp (±1 at 8 bits, and within a 10-bit level on a 16-bit `render_frame`); a steep curve never overshoots (output never falls along the ramp); a red curve moves only red; master then channel, read on a two-curve card; an action halfway lands halfway per point; export parity; the editor's add, drag, delete and nudge each one undo step (probe); TC held. Mutants: Catmull–Rom instead of monotone (the overshoot row fails); channel and master swapped; the strip sampled without the half-texel offset (identity fails); an `rgba16Float` strip (the 10-bit row); the rising-x check dropped. Manual check **GRD-13 — curves on real footage**: an S-curve on Master; lift the blue shadows; set black and white points by moving the ends; delete and nudge points; both appearances. |
| G2-4 | GR-13 first, then **qualifiers** (#262): `Qualifier` on adjustment clips, the refusal elsewhere, Paste Attributes' rule, `selection` in `recipe_options.rs`, format 18, `core/tests/qualifier.rs`, `selection.rs`; `QualifierUniforms`, `q` in the adjustment pass, the selection output, Pick from Canvas, `RangeStripControl`, `VideoPane+Qualifier.swift`, View ▸ Show Selection. | Over MCP, on a hue-wheel card imported as media: a 40° hue range selects exactly its wedge (inside fully graded, outside the softness untouched, a monotone ramp between); a range across 0° works (the wrap); a grey ramp is never selected by hue (the chroma guard); saturation and luma ranges on ramps; Invert; with a matte the weight is the product; `render_frame {selection}` bytes equal `q` as grey; an export with Show Selection on is graded, never the matte; Pick from Canvas centres the ranges on the clicked pixel of the picture BEHIND; undo. Mutants: the hue wrap broken; softness on the inside; the chroma guard removed (greys picked); `q` from the graded colour instead of the destination; the matte not multiplied; the selection option leaking into an export. Manual checks **GRD-14 — pick and grade skin on real footage** (Pick from Canvas on a face, Show Selection, widen the softness until the edge is clean, warm it, play) and **GRD-15 — a sky inside a shape** (a qualifier plus a matte shape over the adjustment clip). |
| G2-5 | **The close**: condense this road map into `designs/adr/grading-2.md`, `git mv` it to `archive/`, add its `archive/INDEX.md` row, close #260–#263 as built, and file any residue as issues (reviewed against the tree first). GRD-11…GRD-15 stay as standing rows for the owner. | — |

## Costs: recorded, measured, reasoned

### Recorded in the repo

- The frame budget: a 1080p frame in under 8 ms (spec §7.5).
- The waveform pass: 0.168 ms at 1080p and 0.331 ms at 4K, GPU time, median of ten, on
  `waveform_probe.swift`'s ramp (`archive/grading.md` GR3, G1). **This is the waveform's figure on
  one ramp, not a bound for another scope**: #263 proposed it as one, and GR-10 replaces it.
- Tier 1 on the tree's shader (`designs/adr/grading.md`, GR0 T2): a toned layer +0.049 / +0.197 ms
  (1080p / 4K); tone and a 33³ look +0.057 / +0.226; one adjustment pass +0.045 / +0.174. An
  ungraded layer under the flag route: +0.000 / +0.001; at GR7a, +0.009 / +0.002 against the caps
  +0.02 / +0.06.
- A graded 1080p frame at GR7a: 2.724 ms median compositor average (`grading_verdict.py` F4).
- A 33³ lattice against the same look computed per pixel: at most 3 levels off (I-grading's C3).

### Measured for the brief (its scratch spike, uncommitted)

These are the brief's figures, quoted with its commands; this road map ran none of them. The
instrument is `~/devel/reelcut/tools/proof/work/grading-tier2-spike/main.swift` (scratch,
gitignored, in the main tree, not in the repo), with a scratch shader of its own (NOT the
compositor's), so only the DIFFERENCES between its passes are read. The tree's own
`Waveform.metal` is compiled from source as the control (row W). Built with
`python3 -c "import sys; sys.path.insert(0,'tools/proof'); import swift_build; print(swift_build.build(sources=['tools/proof/work/grading-tier2-spike/main.swift'], output='tools/proof/work/grading-tier2-spike/spike', optimize=True))"`
(the table figures on key `3e8e2670ee4df253`, the scope and stage figures on key
`875d641504ae023a`; the table kernels are identical in both). Host: Apple M2 Max, macOS 26.5.1,
`pmset -g` powermode 0 and AC power, read before each run, 2026-10-10.

**Scopes** (`spike --mode scopes --frames 40 --runs 3 --seed 4 --waveform
app/Resources/Shaders/Waveform.metal`). One compute pass per command buffer and a fresh zeroed
counts buffer each time, as `WaveformAnalyzer.encode` does; the kernels interleaved in a seeded
shuffled order each cycle; the figure is the median over three runs of each run's median (the
first three frames of each run dropped). Every row's counts summed to the pixel count (×3 for the
parade, ×4 for the histogram). In ms:

| Kernel | 1080p ramp | flat | near-grey | gradient | noise | 4K ramp | flat | near-grey | gradient | noise |
|---|---|---|---|---|---|---|---|---|---|---|
| W the tree's waveform (control) | 0.105 | 0.110 | 0.132 | 0.130 | 0.200 | 0.175 | 0.448 | 0.180 | 0.407 | 0.263 |
| P parade, global atomics | 0.163 | 0.277 | 0.325 | 0.336 | 0.554 | 0.213 | **1.020** | 0.406 | 1.009 | 0.738 |
| V vectorscope, global atomics | **3.002** | **2.165** | 0.302 | 0.139 | 0.217 | **6.993** | **7.160** | 0.427 | 0.442 | 0.300 |
| Vs + SIMD-group merge, bins edged at neutral | 1.018 | 0.082 | 0.302 | 0.137 | 0.217 | **2.676** | 0.254 | 0.453 | 0.441 | 0.301 |
| Vc + SIMD-group merge, bins centred | 0.104 | 0.082 | 0.376 | 0.138 | 0.217 | 0.255 | 0.254 | 0.529 | 0.441 | 0.301 |
| Vt centre 64×64 in threadgroup, centred | 0.132 | 0.110 | 0.158 | 0.128 | 0.261 | 0.296 | 0.296 | **0.208** | 0.391 | 0.354 |
| H histogram, global atomics | 0.069 | **2.166** | 1.035 | **2.807** | 0.572 | 0.175 | **7.163** | **1.472** | **7.166** | 0.808 |
| Ht histogram, threadgroup counts | 0.052 | 0.246 | 0.131 | 0.152 | 0.086 | 0.175 | 0.652 | 0.172 | 0.377 | 0.171 |

Fixtures: `ramp` is G1's (grey `x mod 256`), `flat` mid-grey, `near-grey` mid-grey ±5/255 per
channel at random (a camera's grey wall), `gradient` red across and green down, `noise` random RGB.
Two earlier sessions (seeds 2 and 3, before `near-grey` was added) agreed within 0.03 ms on every
4K figure; at 1080p the global-atomic rows moved between sessions (the vectorscope on the ramp
1.75–3.00 ms, the histogram on the gradient 2.81–3.36, on flat 1.80–2.17) and every other row
within 0.1 ms.

What it says, and why GR-10's bound replaces #263's:
- **Global atomics into a shared bin are the cost**, not the scope's arithmetic. A grey picture
  sends every pixel to the vectorscope's centre bin (about 7 ms at 4K); a flat or two-axis
  gradient picture sends whole regions to a few histogram bins (about 7 ms). Reelcut's own
  material, screen recordings and flat UI, is exactly that kind of picture. A grey ramp, the
  waveform's G1 fixture, is a naive vectorscope's WORST case (6.993 ms at 4K), so a bound measured
  on that ramp alone says nothing about a scope on grey content.
- **A grey on a bin EDGE defeats the SIMD merge** (row Vs on the ramp); centring the bins on
  neutral fixes it (Vc), but near-grey noise still scatters across a few hot central bins. **Vt**
  (the centre in threadgroup memory) is the most even: ≤ 0.391 ms at 4K on every fixture. **Ht**
  ≤ 0.652 ms. The parade as the waveform counts peaks at 1.020 ms.
- Hence **GR-10's bound: each scope ≤ 1.1 ms of GPU per analysed 3840 × 2160 frame, the worst
  over five fixtures (flat mid-grey, G1's ramp, near-grey noise, the red/green gradient, random
  noise), measured in the app's own pass** with the host and power state recorded, by G2-1's time
  rows. The spike's figures are a scratch shader's, not the app's (below, "Not established").
- The waveform that ships spreads by column and stays ≤ 0.448 ms at 4K in this instrument (whose
  absolute waveform figures are not G1's: different fixtures and timing loop).

**1D curve strip precision** (`spike --mode table`). An `n`×1 texture through a linear sampler,
sampled at all 65,536 16-bit inputs at `x·(n−1)/n + 0.5/n`, against the curve computed in
`Double`. `supports32BitFloatFiltering` was true. Max error in 10-bit levels:

| Curve | n | `rgba16Float` | `rgba32Float` | float32 buffer, hand lerp |
|---|---|---|---|---|
| identity | 256 / 1024 / 4096 | 0.491 / 0.496 / 0.359 | 0.008 / 0.002 / 0.001 | 0 / 0 / 0 |
| S-curve (5 points) | 256 / 1024 / 4096 | 0.486 / 0.471 / 0.415 | 0.017 / 0.003 / 0.001 | 0.009 / 0.001 / 0 |
| steep (rises 0.58 over 0.05 in x) | 256 / 1024 / 4096 | 2.325 / 0.498 / 0.456 | 2.213 / **0.154** / 0.011 | 2.175 / 0.150 / 0.010 |

Half-float storage is the floor (about half a 10-bit level); `rgba32Float` at 1,024 is within
0.154 even on a steep curve. 256 texels are too few for a steep curve. Hence GR-12's planned
`rgba32Float` strip of 1,024.

**Stage cost** (`spike --mode stage --frames 200 --runs 3 --seed S`, S = 1, 2, 3, three
sessions). One full-frame pass of a red/green gradient into `rgba16Float`; each variant
interleaved in a seeded shuffled order. Differences over the copy pass (ms, 1080p / 4K):

| Pass | session 1 | sessions 2 and 3 |
|---|---|---|
| copy (baseline) | 0.074 / 0.261 | 0.035–0.036 / 0.211 |
| control (copy again) | +0.000 / +0.001 | +0.000 / +0.000–0.001 |
| + lift, gamma, gain (analytic) | +0.002 / +0.002 | +0.001 / +0.000 |
| + three samples of a 1,024 strip | +0.024 / +0.086 | +0.007–0.008 / +0.018 |
| + the qualifier weight | +0.017 / +0.043 | +0.001 / +0.001 |
| + all three | +0.062 / +0.219 | +0.011–0.014 / +0.005 |

Session 1 ran at a different GPU clock state, so the absolute figures move between sessions and
only the shape is read. Wheels are free; the strip and the qualifier cost at most about what tier
1's tone does on the tree.

### Reasoned from those

- **A fully graded tier-2 layer** (tone, wheels, curves, a look) should cost about tier 1's tone and
  look plus 0.02–0.09 ms at 4K (REASONED: the strip row added to GR0 T2), far inside the 8 ms
  budget.
- **An adjustment clip with a qualifier** adds the qualifier's few dozen operations to one
  full-frame pass (+0.174 ms at 4K recorded for the pass itself).
- **Two scopes shown** with the counting rule: about 0.4–1.7 ms of GPU per analysed 4K frame
  (REASONED: two of the Vt, Ht, P and W rows added; the worst pair is parade plus histogram on a
  flat frame), off the render queue, latest-wins. Without the rule, one vectorscope on a screen
  recording would take about 7 ms.
- **Memory**: a curve strip is 1,024 × 16 B = 16 KB, so a cache of eight is 128 KB; a scope's
  counts buffer is 256 KB (vectorscope), 768 KB (parade) or 4 KB (histogram) per pass.
- **Export speed**: tier 1 found exports encoder-bound (`grading_verdict.py` E1, E2: ±0.3 %). A few
  hundredths of a millisecond per frame will not show (REASONED; each phase's proof can record it).

## What tier 2 must not close off (tier 3: #264, #256)

- **Every new stage is defined on ENCODED values**, and its §11 entry says so. If tier 3 makes
  linear light the working space (#256), the wheels' and curves' meaning would change; saying
  "encoded" now makes that a visible decision with its own migration, never a silent
  reinterpretation.
- **The 0…1 domain is a property of the stage, not the model.** Curve points live in 0…1 of "the
  working range", and the `saturate` that clamps is in the shader. An HDR working range (#256)
  could then add a headroom key and widen the strip's domain without rewriting stored curves.
- **The look stays the one 3D slot at 4d, and an input transform gets room of its own.** #264's
  camera log LUT wants to run BEFORE the correction (log → Rec. 709, then grade). `texture(2)`
  stays the look, `texture(3)` the curve strip, and a future input LUT would be its own step
  before 4c with its own slot. (E9's cutout, once pencilled in at `texture(3)` by #124, would move
  to the next free slot; E9 is deferred.)
- **Scopes say "Rec. 709"** in the panel and in GR-10, and compute their targets from a matrix, so a
  wide-gamut scope (#256) is a second matrix, not a rewrite. The 256-level bins are one constant
  (`WaveformTrace.levels`), so a 1,024-level scope for 10-bit work stays possible.
- **The qualifier reads encoded values too**, and its hue is the HSV ramp every other hue key uses.
  A log picture qualified before its LUT (#264) would select log values, which is what a colourist
  expects at that point.
- **No "colour space" concept** enters tier 2: nothing to undo when tier 3 adds one.

## Not established

- **The real shader's figures.** Everything the brief measured is a scratch shader. The ungraded
  layer's cost with the new flags, and what 4c.1 and 4c.2 do to the stage's registers, are G2-2's
  and G2-3's (`grading_spike.py --measure --tree`).
- **The scopes' cost inside the app**, with the tap's IOSurface wrap and the readback, at Preview
  Quality Full on a real 4K timeline. G2-1's time rows measure it against GR-10's bound.
- **`supports32BitFloatFiltering` on M1** is REASONED from the GPU family, not measured. The
  fallback (`rgba16Float`, ≤ 0.5 of a 10-bit level) needs no design change.
- **The wheels' and qualifier's first strengths** (the lift, gain and gamma factors, the chroma
  guard's numbers) are the phases' to set from a fixture, then the owner's to tune on footage
  (GRD-12, GRD-14), as GR-2's were.
- **Whether two scope slots fit a short window**: the preview pane's height at the 900 pt minimum
  window was not measured. G2-1's design and screen `04b` set the height below which only the top
  slot shows (GR-10).
- **Paste Attributes of a qualifier onto a picture clip** (dropped vs refused) is G2-4's design.
- **Other editors' behaviour** (wheels' feel, scope layouts, qualifier softness conventions) is
  from general knowledge, as tier 1's was.

## G2-0 — the road map, GR-10 and four pure moves

**What landed** (2026-10-10, in the worktree on `grading-2`, from `7f6d112`). This road map;
`designs/spec/11-decisions/grading-2.md` with GR-10, its README rows, GR-5's "Amended by GR-10"
line and the Lines cells; and four pure moves, gated as one change with no tier-2 code and no
behaviour change. Each moved block was diffed against `git show HEAD:<file>`: identical apart
from the doc lines listed (the Rust block after `cargo fmt`, which changed nothing).

| Move | `wc -l` before → after | New file | What widened |
|---|---|---|---|
| `ProjectSnapshot.swift` → `GradeProps.swift`: `ColorAdjust` (its doc line through its closing brace), after `// MARK: - Grading's value types` and before `ColorPatch`; its doc's "`GradeProps.swift` has their helpers." became "Their helpers are below." | 1,570 → 1,509 | `GradeProps.swift` 120 → 181 | nothing |
| `AgentServer+Render.swift` → `AgentServer+Scopes.swift`: `writeWaveform` (its two-line doc and body); `renderFrame`'s doc names the new file | 584 → 563 | 37 | nothing (both are members of the same internal extension of `AgentServer`) |
| `AgentCatalog+Files.swift` → `AgentCatalog+Render.swift`: the rows under `// MARK: Rendering and export` (`render_frame` and `export`) and the five hoisted locals only they read (`frameFormatNames`, `frameFormatProperty`, `burnInProperty`, `exportPresetProperty`, `exportSizeProperty`), as `renderTools(ticks:)`, spliced back as `rows += renderTools(ticks: ticks)` after `captionTools()` and before the `// MARK: Recording` array; the header doc names the rows' new home and drops its stale list of six hoisted locals; `AgentCatalog.swift`'s `tool` doc and splice comment name the new file | 579 → 377 | 239 | nothing (`renderTools` is internal, as `fileTools` is) |
| `core/src/recipe.rs` → `recipe_options.rs`: `// ---- what a caller asked for` through `impl RecipeOptions`'s closing brace, re-exported by `pub use crate::recipe_options::RecipeOptions;` beside `RecipeLayer`'s; `mod recipe_options;` in `lib.rs` | 548 → 484 | 76 | nothing (`RecipeOptions` and `of` were already `pub`) |

`AgentServer.swift` (frozen) was not touched. The mutant anchors named before the moves still
match once each: `assistant_session_proof.py`'s `no-export-stop` (`exportProject`, still in
`AgentServer+Render.swift`) and the `recipe.rs` anchors of `adjustment_proof.py`, `look_proof.py`,
`matte_proof.py` and `seeing_proof.py` (in `frame_recipe_opts` and `layer`, neither of which
moved). The history files (`designs/adr/app-file-history.md`, `core-file-history.md`, "Named next
cuts") record each move and name the next seams: `ProjectSnapshot.swift`'s audio group
(`DuckProps`, `CompressorProps`, `AudioProps`) to `AudioProps.swift`; `AgentServer+Render.swift`'s
`// MARK: - Export` (`exportProject` through `spelled`) to `AgentServer+Export.swift`;
`AgentCatalog+Files.swift`'s `// MARK: Recording` (`record_screen` and its four hoisted clauses) to
`AgentCatalog+Recording.swift`; `recipe.rs`'s content hash (`FNV_OFFSET`, `FNV_PRIME`, `fnv1a`,
`content_hash`, `sorted`) to `recipe_hash.rs`. Spec §7.10's module map gained the
`recipe_options.rs` row. GR-10's six 75 % targets and its 123.3° skin line were checked by
computing them from the Rec. 709 matrix in Python before they were written (the line printed
123.278°; the targets matched to four places).

**Verification**, 2026-10-10, AC power (`pmset -g`: powermode 0, AC Power):
- Controls taken from the untouched worktree before any edit, never by stashing: `make
  app-debug` (BUILD SUCCEEDED), its catalog copied to `tools/proof/work/g2-0/catalog-before.json`;
  `word_looks_proof.py --only B1` on that Debug build: 3/3, B1 `moved: []`
  (`tools/proof/work/g2-0/control-word_looks-B1.txt`); `seeing_proof.py --only U1,U2,U4,W1,Z1`:
  5/5 (`control-seeing.txt`).
- `make typecheck` after each Swift move: exit 0, 0 errors, exactly the 4 baseline warnings.
- `cd core && cargo fmt --check && cargo test --release --test recipe --test ungraded && cargo
  clippy --all-targets -- -D warnings`: exit 0 (recipe 15 passed, ungraded 5 passed, clippy
  clean).
- `python3 tools/proof/spec_index_proof.py`: 153/153. The `07.10-rust-module-map.md` cell went
  from 91 to 92, `grading.md`'s from 409 to 413, and the `11-decisions/` cell from 6269 in 18
  files to 6352 in 19.
- `make app-debug`, then the catalog compared parsed with `catalog-before.json`: equal (exit 0),
  96 tools in the same order, the last eleven `import_media` … `record_screen` as before. The
  two files are not byte-identical: the catalog is written by `JSONSerialization` without sorted
  keys, so its dictionaries' key order differs between builds; compared with sorted keys the
  two are identical.
- `seeing_proof.py --only U1,U2,U4,W1,Z1` on the Debug build after the moves: 5/5, as the
  control (`after-seeing-debug.txt`).
- `make gate` on the final tree (after the orchestrator's comment-only edit to `AgentCatalog+Files.swift` and the review's comment nits): PASS in 261 s. The first run, cold, before those edits: PASS in 281 s (typecheck 4 s with the 4 baseline warnings, fmt 2 s, lint
  10 s, test 174 s, app 91 s, with D25 and D26 ok). The cargo suites passed 1,316 tests in 112
  result lines and failed none; `spec_index_proof.py` 153/153 and `inventory.py --check` 5/5
  among its proof steps. No test file was added or removed.
- `RC_PROOF_APP=release python3 tools/proof/seeing_proof.py`, whole, on the gate's Release
  build: 19/19, no `Reelcut: ` line (`after-seeing-release.txt`).
- `RC_PROOF_APP=release python3 tools/proof/word_looks_proof.py --only B1` on the gate's Release
  build: 3/3, B1 `moved: []`, the same as the control
  (`after-word_looks-B1-release.txt`): the 41 frames of fixture B still match the digests
  recorded from `914b56a`.
- No mutants: a pure move adds no decision.

**Owed.** Nothing; the `app/CLAUDE.md` and `core/CLAUDE.md` map entries for the four moves are
applied. G2-1 (scopes, GR-10) is next, from main after this phase's merge.

## G2-1 — the scopes (#263, GR-10)

**What landed** (2026-10-10, in the worktree on `grading-2`, from `9d5c659`). The RGB parade,
the Rec. 709 vectorscope and the R′G′B′Y′ histogram beside the luma waveform, in the two stacked
slots of View ▸ Scopes (⌃⌘W, renamed from View ▸ Waveform), and `render_frame {parade,
vectorscope, histogram}`; the owner's choices 1–10 as settled before the code (choice 5 option B:
shrink both slots to fit, the bottom slot hidden below 360 pt of pane).
- `Waveform.metal`: `reelcut_parade_bin` (GR-10's per-band threadgroup counts: an 8 px wide
  group's two column bins in threadgroup memory, two copies per cell, a group spanning more
  bins adding globally; dispatched 8 wide by `WaveformAnalyzer.paradeAcross`),
  `reelcut_vectorscope_bin` (the central 64 × 64 bins in threadgroup memory, the rest global) and
  `reelcut_histogram_bin` (threadgroup counts), each merging once per group with its pixel read
  guarded; `scopeLevel`; the waveform kernel and `kLumaWeights` untouched (`seeing_proof.py`'s
  anchors hold once each).
- `ScopeTraces.swift` (new): `ScopeKind`, `ParadeTrace`, `VectorscopeTrace` (targets and the skin
  line computed through `chroma`: 123.278°), `HistogramTrace`, `ScopeTrace`, their JSON.
- `WaveformAnalyzer.swift`: four pipelines (`init` fails unless all four exist), multi-kind
  `encode` / `trace` / `analyze`, every kind set iterated in `ScopeKind.allCases` order; the
  waveform-only methods stay.
- `WaveformTap.swift`: `attach(key:kinds:onTraces:)`, one command buffer per offered frame for the
  shown kinds, and `attachedKinds(key:)` (a reader for the probe's S9; not in the spec's interface).
- `ScopesPanelView.swift` (`git mv` of `WaveformPanelView.swift`): the panel, `ScopeSlotLayout`
  and `layout(picks:paneHeight:)`, `UngradedTagView` unchanged; 216 lines. `ScopeSlotView.swift`
  (new, 216): a slot and its `UISnapshotParts` extension, split out at review because the renamed
  file had reached 431 lines with about 112 of the old 243 surviving (git's similarity 20 %),
  so the 400-line cap of a new file held. `WaveformTraceView.swift` (the
  waveform body moved whole, and `ScopeWell`, the well, graticule, marks and density the parade
  shares), `ParadeView.swift`, `VectorscopeView.swift`, `HistogramView.swift` (new).
- `+Seeing` (`scopesPanel`, `toggleScopes`, `onNeedsFrame` → `refreshSeeing`), the menu, the
  allow-table, the inventory, `screens.py`'s `VIEW_SELECTORS`; `AgentServer+Scopes.swift`
  (`writeScopes`, one analyse for every kind asked, the waveform's sentence byte-identical),
  `+Render` and the catalog's three rows; the harness's `seeing` items `scopes`, `top=`,
  `bottom=`, `ramp` for every kind, and its `seeing panel` / `seeing slot` lines.
- Documents: GR-10's Panel bullet amended (owner, 2026-10-10); spec §1, §4.2, §7.5, §7.9a, §9 and
  the two indexes; README; GRD-2 step 3 and the new GRD-11; screen `04b-preview-waveform` →
  `04b-preview-scopes`; the proofs README's section; `grading_verdict.py`'s menu paths (text only,
  not re-run).

**The parade's fallback was taken** (at review). The first T1 run, timing each pass alone
straight after the last with no warm-up, missed: 4K parade 2.046 ms (noise), histogram 1.666
(flat), with figures moving two- to threefold between runs. Scratch instruments (scratchpad, not
committed) found why: a cold GPU's clock, and — when the passes were committed back to back
instead — two command buffers running at once, so each one's own time doubled. T1 now commits a
burst of sixteen passes first, unread, then times twelve one at a time (median of the last ten),
which reproduced the brief's spike within a few hundredths and was stable between runs. On that
instrument the global parade (the spec's primary design, global atomics as the waveform) scored
1.019–1.042 ms at 4K on the flat fixture over eleven recorded runs: inside GR-10's 1.1 ms, but by
5–7 %, on an M2 Max alone, on a row every whole run and every mutant run scores. The review
(finding 1) called that a flaky row waiting to happen, so the spec's fallback replaced it: GR-10's
per-band threadgroup counts, same kernel name and counts layout, 8 px wide groups (two column
bins each at 1792 px wide or more), two copies of each threadgroup cell for alternate threads;
a group spanning more bins (some groups of a narrower frame) adds globally. Measured on the same
host: 4K parade 0.433–0.442 ms on Debug; on the recorded Release run 0.433–0.440, near-grey
0.622 (1.8× headroom). S3 now also runs its red ramp at 1920, 1999 (a last group 7 px across) and
3840 wide, where every group counts per band, so a band merged into the wrong column fails it
(the tenth mutant, `parade-band-misplaced`, below). A mutant forcing `banded` off would survive
T1, since the global parade's 1.02–1.04 ms is also under 1.1 ms: an accepted limit of T1, so no
such mutant is written.

**Verification**, 2026-10-10, AC power (`pmset -g`: powermode 0, AC Power), Apple M2 Max:
- In the loop: `make typecheck` (0 errors, the 4 baseline warnings); `swift_build.py typecheck`
  of `scopes_probe.swift` and `waveform_probe.swift`; `inventory.py --check` 5/5;
  `spec_index_proof.py` 153/153 (cells: `04.2` 94 → 120, `07.5` 237 → 247, `07.9a` 507 → 524,
  `11-decisions/` 6352 → 6353, `grading-2.md` 77 → 78); `scopes_proof.py` 19/19 and
  `seeing_proof.py` 19/19 on Debug; `screens.py --only 04b-preview-scopes` 6/6, both looks, 0 new
  problems (its first run found the header's picker and caption ambiguous — 12 + 120 + 8 + 102 +
  12 > 248 — fixed by a 2 pt gap and the caption giving way first).
- `make gate`: PASS in 192 s (typecheck 5 s, test 105 s, app 82 s; fmt and lint skipped as
  unchanged).
- `RC_PROOF_APP=release python3 tools/proof/scopes_proof.py`, whole, on the gate's Release build:
  19/19, no `Reelcut: ` line. T1 at 4K, worst of five fixtures: parade 1.026 ms (flat), vectorscope
  0.424 (ramp), histogram 0.751 (flat); recorded: waveform 0.451 (flat), waveform + vectorscope
  0.802 (gradient). At 1080p every scope ≤ 0.638 ms.
- `RC_PROOF_APP=release python3 tools/proof/seeing_proof.py`, whole: 19/19 (View ▸ Scopes, the
  `scopes.*` ids, the new `attach`).
- Mutants, nine, once each on the final instrument (Debug copies): `cb-cr-swapped` (S1 M1),
  `bt601` (S1 M1), `bins-edged` (S1 S2), `vectorscope-global` (T1: vectorscope 7.165 ms on flat),
  `histogram-global` (T1: histogram 7.165 ms on flat), `histogram-luma-601` (S5), `pick-persisted`
  (S9), `tap-first-kind-only` (S7 S8), `slots-not-shrunk` (S10): every one MUTANT PASS, no other
  row failing.
- Review fixes (findings 1–5 of the G2-1 review, the same day): the banded parade above,
  `ScopeSlotView.swift` split out, this record and the file history, `ParadeView` caching each
  channel's clip marks per trace instead of per draw, and `screens.py`'s comment. `make
  typecheck` (the 4 baseline warnings); `swift_build.py typecheck` of both probes;
  `spec_index_proof.py` 153/153 (`07.5` 247 → 249); `scopes_proof.py --only S3,S5,S6,S8,T1` 5/5
  on Debug; `screens.py --only 04b-preview-scopes` 6/6, 0 new problems; `make gate` PASS in
  187 s (typecheck 4 s, test 101 s, app 81 s); `RC_PROOF_APP=release` `scopes_proof.py`, whole,
  19/19, T1 at 4K worst of five: parade 0.622 ms (near-grey; 0.433–0.440 on the other four),
  vectorscope 0.390 (gradient), histogram 0.668 (flat), recorded waveform 0.450, waveform +
  vectorscope 0.798, every 1080p figure ≤ 0.394; `RC_PROOF_APP=release` `seeing_proof.py`
  19/19. The nine mutants were not re-run: no mutant's anchor line changed.
- Second review (findings 1–3, the same day): a tenth mutant, `parade-band-misplaced` (the
  merge's `first + band` → `first`), run once on a Debug copy: MUTANT PASS, S3 failed (`1920
  R[1][2]=64`, …) and no other row (15/16; T1's 4K parade 0.619 ms); S3 also runs 1999 × 64;
  this record's 4K parade figures corrected to the Release run's. `swift_build.py typecheck` of
  `scopes_probe.swift`; `scopes_proof.py --only S3` 1/1 on Debug; `make gate` PASS in 67 s (test
  66 s, every other step skipped as unchanged); `RC_PROOF_APP=release` `scopes_proof.py --only
  S3,Z1` 2/2.

**Owed.** GRD-11, the owner's standing row in `docs/manual-checks.md`. Nothing else: the
`app/CLAUDE.md` map and parity entries (`ScopeSlotView.swift` among them) are applied, and
`designs/adr/app-file-history.md` has the panel's entry and its next seam.

## G2-2 — the wheels (#260, GR-11, GR-14)

**What landed** (2026-10-10, in the worktree on `grading-2`, from `3eecaad`). GR-11 and GR-14
first (`designs/spec/11-decisions/grading-2.md`, README rows, "Amended by GR-11" lines on GR-2,
GR-4, GR-6 and GR-7, the Lines cells), from the owner's "All as recommended" to G2-2's choices
1–8 (choice 9 internal); then `video.wheels {lift, gamma, gain}`, each `{x, y, master}`, at format
16.
- Core: `model_grade.rs` (new: `Wheel`, `Wheels`, `WHEEL_MAX`, `WHEEL_RIM_TOLERANCE` 1e-9),
  `grade_check.rs` (new: `check_wheels`, the two sentences, called from `check_video` after the
  look), `VideoProps.wheels` before `look`, `actions::wheels_json` (all nine) inserted by
  `video_json`, so the patch template, the evaluator and `split` see every key with no `patch.rs`
  edit; `clamp_wheels` (NaN to 0, ±1, a push past the rim divided by its `hypot`); the recipe's
  `wheels` key between `color` and `look` (twenty-four keys); `ungraded` writes it neutral on its
  own line; `RC_FORMAT_VERSION` 16 and the header. No op, tool, FFI export or op-table row.
- Metal: twelve uniforms after `lookEnabled` (116 → 128 floats, 512 bytes; `liftX` at 464,
  `wheelsEnabled` at 500, `curvesEnabled` reserved for G2-3), `kWheelPush`/`kLift`/`kGain`/
  `kGamma`, `wheelOffset` (the hue normalised to [0, 360) before `lookHueChroma`) and
  `gradeWheels` (lift, then gain, then gamma) after `lookHueChroma`; step 4c.1 as a new block
  between 4c and 4d in `layerColorPremultiplied` and between the tone `if` and the look's in
  `reelcut_adjust_fragment`; `+ u.wheelsEnabled` in the gate sum; the stage table. Metal has no
  `degrees()`: the angle is `atan2(y, x) * (180 / M_PI_F)`.
- Swift: `GradeProps.swift` (`ColorWheel`, `ColorWheels`, `ColorWheelPatch`, `ColorWheelsPatch`,
  `ColorWheelKind`, `LayerUniforms.apply(wheels:)`), `VideoProps.wheels` (wiring),
  `RecipeLayer.wheels`, `u.apply(wheels:)`, `isNeutralAdjustment` requiring neutral wheels,
  `VideoPatch.wheels` and its sparse dictionaries, the `◆N` count (Color counts `wheels`, Picture
  does not), the eyedropper's suppression (`wheels: .neutral`, net 0 lines), `inspectorRow` giving
  a `ColorWheelsView` row no trailing spacer, `ClipPane`'s `.color` registering
  `wheelsSection()` after Color; `VideoPane+Wheels.swift` (new, 190: the section and
  `ColorWheelsView`), `ColorWheelControl.swift` (new, 308: the disc) and
  `WheelStripControl.swift` (new, 182: the master strip — split out of `ColorWheelControl.swift`,
  which had reached 489 lines, so each new file holds the 400-line cap); `set_video`'s prose
  (`wheelsClause`, and the adjustment sentence names wheels).
- Measured layout (screen `05f`, both looks): a row's `ColorWheelsView` is 253 pt at the default
  pane, so a column is 81.7 pt and a disc 78 pt (the spec's "≈ 72" estimate assumed a badge and
  spacing the row does not take); about 70 pt at the 280 pt minimum, and the 112 pt cap at 440. The
  first capture had 26 pt columns: an `InspectorRowLabel` hugs at 250, above the row stack's pull,
  and held each column to its title; the titles hug at 1 now.
- Proofs: `wheels_proof.py` and `wheels_probe.swift` (new); the 464 → 512 instruments
  (`tone_probe.swift` P3, `look_probe.swift` L3 and B4's section list, `clip_inspector2_probe.swift`
  T2, `phase8_chrome.py`, `grading_spike/tree_bench.swift`) and `grading_spike.py --tree-base`;
  `screens.py` (`video.wheels` pinned open, the `wheels` fixture) and screens `05f` (new), `05b`,
  `05c`; tests outside the phase's list that the new recipe key moved: `core/tests/recipe.rs`'s
  `LAYER_KEYS` (23 → 24) and `core/tests/schema_v8.rs`'s fall-through base (`clip_state` carries
  `wheels`).
- Documents: spec §4.3a, §5.2 (format 16), §7.3, §7.4, §7.5, §7.9a, §7.10 and the index; the
  README's grading bullet; GRD-12 in `docs/manual-checks.md`; the proofs README's section.

**Deviations from the phase's spec, each measured.** (1) O1 adds **lift** master 0.5 on top of
exposure +1, not gain: gain and exposure nearly commute on encoded values (the mutant
`wheels-before-tone` drew 218 where the right order draws 219, inside ±1, so the gain row let it
survive); lift does not (185 against about 197). (2) `gamma-sign` also fails C1, and
`flag-ignores-negative` also fails C1 (its 240° push has x and y both negative): both are named.
(3) C1's "the pushed hue's channel rises" is "every channel the hue holds at full rises and every
other falls": a yellow push lifts R and G by only 2–4 levels (yellow's luma is near white's).
(4) `WheelStripControl.swift` is its own file (above). (5) The disc is 78 pt, not ≈ 72 (above).

**Verification**, 2026-10-10, AC power (`pmset -g`: powermode 0, AC Power), Apple M2 Max:
- Control first: `make app` on the untouched tree (only the decision documents edited), then
  `RC_PROOF_APP=release wheels_proof.py capture tools/proof/work/wheels-control`: six frames,
  Z1 ok.
- In the loop: `cargo test --release --test wheels --test schema_v16 --test schema_v15 --test
  ungraded --test patch_door` (11, 5, 5, 5, 9 passed); `make lint` (clean after one clippy fix:
  `FRAC_1_SQRT_2` for a written-out 0.7071…); `make typecheck` (0 errors, the 4 baseline
  warnings); `swift_build.py typecheck tools/proof/wheels_probe.swift`; `wheels_proof.py` on
  Debug 22/22 (N0 printed only); `spec_index_proof.py` 153/153.
- `make gate`: the first run failed `--test recipe` (`LAYER_KEYS`), the second `--test
  schema_v8` (`clip_state`'s `wheels`); after both, `cd core && cargo test --release
  --no-fail-fast` passed every binary, and the third run PASSED in 223 s (typecheck skipped as
  unchanged, fmt 2 s, lint 1 s, test 89 s, app 130 s with D25 and D26). After it changed:
  `wheels_proof.py` (O1, the mutant list; `make test` does not run it), one doc comment in
  `VideoPane+Wheels.swift` (the disc's 72 → 78 pt, with GR-11's sentence; `make typecheck` after
  it: 0 errors, the 4 baseline warnings), screen prose and this record. So the gate's stamps
  for typecheck, test and app are stale by a comment and a proof script, and one more `make
  gate` is owed.
- `RC_PROOF_APP=release python3 tools/proof/wheels_proof.py compare tools/proof/work/wheels-control`,
  whole, on the gate's Release build and the final instrument: 23/23 — N0 the six wheel-less
  frames byte-identical at 16 bits; no `Reelcut: ` line, no `DEFAULTS MOVED`
  (`tools/proof/work/g2-2/wheels-release.txt`).
- `RC_PROOF_APP=release tone_proof.py --only P1,P2,P3,P4` 4/4; `look_proof.py --only L3,B4` 2/2;
  `clip_inspector2_proof.py` 33/33; `phase8_chrome.py` 145/150 — its uniform-size row passes at
  512/128/32 × 16, and its five failures are the View menu's last group (Show Ungraded and Scopes
  now follow Preview Window), rows this phase does not touch.
- `grading_spike.py --measure --tree --tree-base 3eecaad`: KT 0/1023 at both sizes; TC held —
  1080p T0 +0.003 ms against 0.020, 2160p −0.001 ms against 0.061 (V0 0.346 / 0.630 ms; load
  before 48.1, another session's).
- `screens.py --only 05b-clip-color,05c-clip-adjustment,05f-clip-wheels`: 8/8, both looks, 0 new
  problems.
- Mutants, nine, once each on the final instrument (Debug copies): `wheels-before-tone` (O1),
  `gamma-sign` (Y1 C1), `push-not-luma-neutral` (C1), `flag-ignores-negative` (G1 C1 P2),
  `circle-check-dropped` (R1 CT), `rim-tolerance-dropped` (CT: `--test wheels`, the rim and split
  cases), `ungraded-misses-wheels` (V1 CT), `adjust-without-wheels` (J1), `puck-writes-group`
  (P1): every one MUTANT PASS, no other row failing.

**Review fixes** (fix pass 1, 2026-10-11). `phase8_chrome.py` takes the View menu's preview
group as the rows after its last separator (Preview Quality, Preview Window, Show Ungraded,
Scopes): 150/150. `matte_proof.py`'s `mix-weights-swapped` anchors on `return saturate(mix(o, i,
p));` (precision PR1's wrap) and names D0–D8, every row that reads the mix: MUTANT PASS, no other
row failing. Spec §7.3's burn-in says twenty-four layer keys; §7.5's 116 floats read as the tone
group's history. The master strip: a press on its knob grabs it with no write, so a double-click
there is one undo step; off the knob it stays a jump and a reset, two steps, accepted in GR-11
(4); P5 checks the grab. `wheels_proof.py` P1–P7 on Debug 7/7, and P1–P7 with Z1 on the gate's
Release build 8/8. The owed `make gate` PASSED in 234 s (typecheck 5 s, fmt and lint
skipped as unchanged, test 114 s, app 115 s).

**Owed.** GRD-12, the owner's standing row, only. Done, not owed: the `app/CLAUDE.md` and `core/CLAUDE.md` entries
(the compositor's 128 floats, the Wheels section, the three new Swift files, `GradeProps.swift`'s
wheel types, `model_grade.rs`, `grade_check.rs`), applied by the orchestrator.


## G2-3 — the curves (#261, GR-12)

**What landed** (2026-10-11, in the worktree on `grading-2`, from `f952e88`). GR-12 first
(`designs/spec/11-decisions/grading-2.md`, its README rows, "Amended by GR-12" lines on GR-2,
GR-4, GR-6 and GR-7 and their README cells, the Lines cells), from the owner's answers to G2-3's
choices 1–10 ("All as recommended", choice 9 (a)) and 11–13 (internal); then `video.curves
{master, red, green, blue}`, each 2–16 `[x, y]` points, at format 17. GR-12's three refusal
sentences replace the draft sentence in "Curves (#261), G2-3" above.
- Core: `model_grade.rs` (`CurvePoint`, `Curves`, `CURVE_POINTS_MIN`/`MAX`, `IDENTITY_CURVE`,
  `curve_is_identity`, `points_are_identity`, `Curves::drop_identities`), `VideoProps.curves`
  after `wheels`, `grade_check.rs`'s `check_curves` (called after `check_wheels`), the new
  `actions_curves.rs` (`curves_json`, inserted by `video_json`, so the template, the evaluator,
  `split` and the recipe see all four with no `patch.rs` edit; `align_identity_curves`, called by
  `evaluate_clip` before the lerp), `clamp_curves` in `clamp_video`, `patch_clips`' `Video` arm
  dropping identity channels after `check_video`, the recipe's `curves` key after `wheels`
  (twenty-five keys), `ungraded` writing the identity, `RC_FORMAT_VERSION` 17 and the header. No
  op, tool, FFI export or op-table row.
- Metal: `gradeCurves` (each channel through the strip at `texture(3)`, sampled at
  `saturate(v)·(n−1)/n + 0.5/n`), step 4c.2 between the wheels' block and the look's in
  `layerColorPremultiplied` and `reelcut_adjust_fragment`, `texture2d<float> curves
  [[texture(3)]]` on both layer fragments and the adjust fragment, `+ u.curvesEnabled` in the
  gate sum, the stage table and the struct comment. `LayerUniforms` stays 128 floats:
  `curvesEnabled` is GR-11's reserved float, now read.
- Swift: `GradeProps.swift` (`CurvePoint` coded as `[x, y]`, `CurveChannel`, `ColorCurves`,
  `ColorCurvesPatch` with `reset`, `neutral`, `channel`, `setting`, and `apply(curves:)`);
  `CurveTable.swift` (new, 98: the Fritsch–Carlson spline and the strip's texels);
  `CurveTextures.swift` (new, 98: the strip's upload, an LRU of eight, the 2 × 1 placeholder),
  held by `LookTextures` as `curves`, so `Compositor.swift` took nothing; `prepare`'s strip and
  `PreparedLayer.curves`; `texture(3)` bound in `drawLayer`, the shadow's mask pass and the
  adjustment pass; `isNeutralAdjustment` requiring the identity; `RecipeLayer.curves`,
  `VideoProps.curves`, `VideoPatch.curves` and its dictionary; `structural(video:for:)`'s curves
  arm and `editedCurve`; `CurveEditorView.swift` (new, 397: the plot) and
  `VideoPane+Curves.swift` (new, 351: `curvesSection(_:)`, `InspectorBinding.curvesReset`,
  `CurveEditorState`, `CurvesView`, `CurvePointField`, `CurveChannelPicker`); `ClipPane`'s
  `curveState` (cleared by `forgetSubTab()`) and the `.color` list; `keyedCount`; the row's
  spacer; the eyedropper's `curves: .reset`; the Delete item's validator; `set_video`'s
  `curvesClause` and the adjustment sentence (which now names curves and the look).
- Measured layout (screen `05g`, both looks): the plot is 254 pt at the default pane (246 pt of
  well inside its 4 pt inset), the picker and the point row aligned with the well's frame.
- Proofs: `curves_proof.py` and `curves_probe.swift` (new); `wheels_proof.py` N2 reads the
  header's version; the Color section lists of `wheels_probe.swift` P1, `look_probe.swift` B4 and
  `clip_inspector2_probe.swift`; `grading_spike/tree_bench.swift` binds an identity strip at
  `texture(3)` and its README names `--tree-base f952e88`; `screens.py` (`video.curves` pinned
  open, the `curves` fixture) and screens `05g` (new), `05b`, `05c`, `05f`; tests the new key
  moved: `core/tests/recipe.rs` (`LAYER_KEYS` 24 → 25), `schema_v8.rs` (`clip_state`'s
  `curves`), `ungraded.rs` (curves stripped and neutralised), `wheels.rs` (the recipe's key
  order: `curves` now sits between `wheels` and `look`), `schema_v16.rs` (its current-number
  literals now `RC_FORMAT_VERSION`; its "is 16" test a `const` assertion that 16 is at most the
  current, clippy's `assertions_on_constants`).
- Documents: spec §4.3a, §5.2 (format 17), §5.4, §7.3, §7.4, §7.5, §7.9a, §7.10 and the index;
  the README's Curves bullet; GRD-13 in `docs/manual-checks.md`; the proofs README's section; the
  two file-history ADRs.

**Deviations from the phase's spec, each measured.** (1) K1 and C1 read a column's INPUT as the
code the ramp wrote there (`round(255·x/1919)`) and its 8-bit OUTPUT as the 16-bit sample / 257,
rounded: ffmpeg's `rgba` decode of a 16-bit PNG truncates, so the first Debug run found "v 192"
at a column the ramp wrote 191 and failed K1 by 4.4 levels. (2) A1's "clip_state holds y 0.6" is
`core/tests/curves.rs`' (`an_action_between_curves_of_one_count_lerps_per_point`): no MCP tool
reads `clip_state`, so the proof row holds the frame only. (3) `CurveEditorState` lives in
`VideoPane+Curves.swift`, not beside the plot: `CurveEditorView.swift` was 442 lines, and the
move (with a few compactions) brought it to 397, under the 400 cap. (4) `CurvePointField` (the
blank, disabled box with no point selected) is a small view of the section's own:
`OptionFieldControl` has no blank, disabled state, and `OptionControls.swift` (1,082 lines) is
past the ~600 cap, so it takes nothing on before a pure move.
(5) Screen 05g expects the "Out" label: the picker draws its titles, so "Master" is no view's
text. (6) `wheels_probe.swift` and `core/tests/wheels.rs` were outside the spec's list; the new
section and key moved them, as G2-2's `LAYER_KEYS` did.

**Verification**, 2026-10-11, AC power (`pmset -g`: powermode 0, AC Power), Apple M2 Max:
- Control first: `make app` on the untouched tree (only the decision documents edited), its
  bundle copied out of `build/` before the first code edit, then `RC_PROOF_APP=release
  curves_proof.py capture tools/proof/work/curves-control --app <the copy>`: seven frames, Z1
  ok; the ramp's frame a 16-bit PNG.
- In the loop: `cargo test --release --test curves --test schema_v17 --test schema_v16 --test
  recipe --test schema_v8 --test ungraded --test wheels --test patch_door` (9, 6, 4, 15, 18, 5,
  11, 9 passed, after `wheels.rs`' key order); `make lint` (clean after clippy's constant
  assertion); `make typecheck` (0 errors, the 4 baseline warnings); `swift_build.py typecheck
  tools/proof/curves_probe.swift`; `curves_proof.py` on Debug 28/28 (N0 printed only: equal);
  `spec_index_proof.py` 153/153.
- `make gate`: PASSED in 278 s on the first run (typecheck 4 s, fmt 2 s, lint 1 s, test 170 s,
  app 100 s); after the picker's alignment and the blank field's appearance it PASSED again in
  260 s (typecheck 10 s, fmt and lint skipped as unchanged, test 143 s, app 106 s).
- `RC_PROOF_APP=release python3 tools/proof/curves_proof.py compare
  tools/proof/work/curves-control`, whole, on the second gate's Release build and the final
  instrument: 29/29 — N0 the seven curve-less frames byte-identical at 16 bits; K1's points 0,
  0, 0.375 and 0 of a 10-bit level off; no `Reelcut: ` line, no `DEFAULTS MOVED`
  (`tools/proof/work/g2-3/curves-release.txt`).
- `RC_PROOF_APP=release wheels_proof.py` 22/22 (P1 after its section list); `look_proof.py
  --only B4` 1/1; `clip_inspector2_proof.py` 33/33.
- `grading_spike.py --measure --tree --tree-base f952e88`, twice. The first (load before 27, a
  rustc of another session at 96 %): KT 0/1023 at both sizes; 2160p T0 +0.001 ms against 0.061
  (held); 1080p T0 +0.077 ms against 0.020, MISSED — but the GPU changed clock state inside the
  run: V0b's first series and VT's third ran at 0.35 ms where every other series ran at 0.120, so
  the medians of three put VT at 0.198, while VT's full-clock series (0.1204) equals V0's (0.1203).
  The second, on the final tree (load before 22, another session's tests): every 1080p series at
  the slower state, T0 +0.001 ms (0.352 against 0.351), held; 2160p +0.000 ms, held. The flag adds
  one term to a sum, as GR-11's did (+0.003 / −0.001 ms in G2-2).
- `screens.py --only 05b-clip-color,05c-clip-adjustment,05f-clip-wheels,05g-clip-curves` on the
  final Debug build: 9/9, both looks, 0 new problems.
- Mutants, ten, once each on the final instrument (Debug copies; `catmull-rom`'s copy predates
  the blank field's appearance fix, which no row reads): `catmull-rom` (K3 P6; K3's worst fall
  3592 16-bit levels, P6 0.20 off), `master-channel-swapped` (M1: 220 for 192),
  `strip-without-half-texel` (C1: 948 G/B samples off), `strip-rgba16` (P7),
  `rising-check-dropped` (R1, CT `--test curves`), `curves-before-wheels` (O1: 88 for 82),
  `ungraded-misses-curves` (V1, CT `--test ungraded`), `adjust-without-curves` (J1),
  `identity-kept` (N1, CT `--test curves`), `identity-not-aligned` (A2 A3, CT `--test curves`):
  every one MUTANT PASS, no other row failing.

**Owed.** GRD-13, the owner's standing row, only. Done, not owed: the `app/CLAUDE.md` and `core/CLAUDE.md` entries
(`model_grade.rs`'s curves, `grade_check.rs`'s `check_curves`, the new `actions_curves.rs`, the
recipe's twenty-five keys, `GradeProps.swift`'s curve types, `CurveEditorView.swift`, the
`VideoPane` entry's `+Curves` and the Color sub-tab's order, the compositor's `curvesEnabled`
and the strip at `texture(3)`), applied by the orchestrator.

**After review (G2-3).** The review passed with four nits, all applied: the record's reason for
`CurvePointField`, the Owed wording, a stub line in `app/CLAUDE.md`, and `CurveTable`'s tangents,
now computed once per curve (`CurveTable.Spline`; `strip` builds the four channels' splines once,
the editor's stroke once per curve) instead of on every sample. Re-run on the change: `make gate`
PASS (232 s); `RC_PROOF_APP=release curves_proof.py compare` 29/29; `catmull-rom` (K3, P6) and
`master-channel-swapped` (M1) MUTANT PASS, no other row failing.

## G2-4 — the qualifier (#262, GR-13)

**What landed** (2026-10-11, in the worktree on `grading-2`, from `12f5e81`). GR-13 first
(`designs/spec/11-decisions/grading-2.md`, its README row and Lines cells, "Amended by GR-13" on
GR-4 and GR-6 and their README cells), from the owner's answers of 2026-10-11 to G2-4's choices
1–13 (1–10 and 12–13 as recommended, 11 changed to the short way round) and the orchestrator's
calls on the spec's objections 1 (a pick SHIFTS a level range inside 0–1) and 3 (Saturation
reads HSV S = C / max with a near-black guard). GR-13 supersedes this road map's draft above
("Qualifiers (#262), G2-4"): Saturation is not chroma, and a qualifier dropped by Paste
Attributes is said in the tool's description, not its answer. Then `video.qualifier {hue,
saturation, luma, invert}` on adjustment clips only, at format 18.
- Core: `model_grade.rs` (`HueRange`, `LevelRange`, `Qualifier`, `HUE_TURN`,
  `HUE_SOFTNESS_MAX`), `VideoProps.qualifier` after `curves`, `grade_check.rs`'s
  `check_qualifier` (after `check_curves`), `edit_adjustment.rs`'s `check_qualifier_clip` (beside
  `check_adjustment_video` in `patch_clips` and `check_group`), `copy_group`'s rule in
  `edit_paste_attributes.rs`, `clamp_qualifier` in `clamp_video`, the new `actions_qualifier.rs`
  (`align_hue_center`, called by `evaluate_clip` after `align_identity_curves`), the patch
  template's qualifier (every range present, `invert` true), the adjustment source's `qualifier`
  in `layer_source`, the new `recipe_selection.rs` (`LayerFacts`, `select_layers`, called by
  `frame_recipe_opts` before the burn-in), `selection` and `behind` in `recipe_options.rs`,
  `RC_FORMAT_VERSION` 18 and the header (its `opts_json` comment too). `LAYER_KEYS` stays 25 and
  `video_json` takes nothing (the qualifier is skipped when neutral). No op, tool, FFI export or
  op-table row.
- Metal: `QualifierUniforms` (sixteen floats), `qualifierFall`, `qualifierLevel`,
  `qualifierWeight`; `reelcut_adjust_fragment` reads `q` from the destination before step 3,
  returns `q` × coverage as grey for a `selection` layer, and weighs `w = saturate(opacity ×
  coverage × q)`; the stage table's step 7 names it.
- Swift: `QualifierProps.swift` (new, 305), `RangeStripControl.swift` (new, 317),
  `VideoPane+Qualifier.swift` (new, 160), `EditorViewController+Qualifier.swift` (new, 155:
  `pickQualifier`, `QualifierPick`, `QualifierPickView`), `CanvasPickOverlay` extracted from
  `CanvasEyedropperView` in `+Eyedropper`, `+Seeing`'s `toggleShowSelection`,
  `syncShowSelection`, validator arm and tag stack (`SeeingTagStack`), `SelectionTagView`, the
  adjustment source's `qualifier` and `selection` in `FrameRecipe.swift`, `RecipeOptions`'
  `selection` and `behind`, `VideoProps.qualifier`, `VideoPatch.qualifier` and its dictionary,
  `keyedCount`, the row spacer, `ClipPane`'s `.color` list, `uniforms(for:…, ignoringOpacity:)`,
  `drawAdjustment`'s `buffer(1)`, View ▸ Show Selection and its `UIMenuTable` row, `set_video`'s
  `qualifierClause`, `render_frame`'s `selection`, `paste_attributes`' sentence.
- Proofs: `qualifier_proof.py` and `qualifier_probe.swift` (new); `look_probe.swift` B4 and
  `look_proof.py`'s doc; `phase8_chrome.py`'s View group; `capture_spike/inventory.json`;
  `screens.py` and screens `05h` (new) and `05c`; `grading_spike/tree_bench.swift`,
  `grading_spike.py` and its README (the SA scene, KA, TA); `core/tests/qualifier.rs`,
  `selection.rs`, `schema_v18.rs` (new) and `schema_v17.rs` (its "is 17" a `const` assertion).
- Documents: spec §4.2, §4.3a, §5.2 (format 18), §5.4, §6 (`paste_attributes`, the adjustment
  clip's row), §7.3, §7.4, §7.5, §7.9a, §7.10, §9 and the index; the README's Qualifiers bullet;
  GRD-14 and GRD-15 in `docs/manual-checks.md`; the proofs README's section; the two
  file-history ADRs; `designs/screens/README.md` (the fixture, the third view toggle).

**Deviations from the phase's spec, each measured.** (1) The fields are 41 pt, not 40: at 40 a
two-decimal value ("0.00", "1.00") measured 27 pt of text in a 26 pt frame, which screen 05c's
layout dump named as truncated (24 problems); at 41, 0. (2) A2 reads its early frame at 0.3 s
(frame 9, centre 356), not 0.25 s: 0.25 s is frame 7.5 at 30 fps, renders a frame either side,
and the first Debug run found the band a column off (centre 355.33). (3) M1's matte covers the
left THIRD (480 px, hues 0–120), not the left half: H1's band (80–160) lies wholly in the left
half, so with a half-width matte the first `matte-not-multiplied` run SURVIVED — nothing selected
lay outside the matte. Across the band's edge the mutant fails M1. (4) Three mutants name more
rows than the spec's list, each measured: `hue-wrap-broken` W1 G1 (G1's 360° band needs the wrap
too), `softness-inside` H1 S1 S1b L1 W1 D1 (W1 and D1 read the band's full-in columns),
`q-from-graded` D1 H1 (Q's grade, saturation −1, makes the graded colour grey, so `q` from it is
0 and H1's graded columns stay B). (5) `S` and Y′ are saturated in the shader: on the first Debug
run S2 failed on single rows at V 0.106–0.212 because Metal's fast division put C / max an ulp past
1, which the hard edge at 1 refused. (6) K3's probe runs beside a `default.metallib` of the tree's
shader and `Blank.mp4`, `matte_probe.py`'s arrangement: a probe has no app bundle, so neither the
compositor's library nor the placeholder track resolved (the first run threw in
`AVAssetReaderVideoCompositionOutput`). (7) `ClipPane` inserts the Qualifier with a second
`if videoPane.allAdjustment` line rather than a block, so `adjustment_proof.py`'s
`strength-in-mixed` anchor still occurs once. (8) The 05h capture's well is `snapshot_ui`'s fill
(`render_frame`'s picture, which the switch never reaches), so the screen shows the "Selection"
tag and the switch, not the grey; E1 and V1 are the selection's proof. (9) `ffi_query.rs`'s
`rc_project_frame_recipe_opts` doc, which named only the two older keys, now names all four, as the
header's comment, the contract, does (the review's fix pass).

**Verification**, 2026-10-11, AC power (`pmset -g`: powermode 0, AC Power), Apple M2 Max:
- Control first: `make app` on the untouched tree (only GR-13's documents and the new proof
  written), its bundle copied out of `build/` before the first code edit, then `RC_PROOF_APP=release
  qualifier_proof.py capture tools/proof/work/qualifier-control --app <the copy>`: six frames, Z1
  ok (B, B50 and BD equal the fixtures' bytes).
- In the loop: `cargo test --release --test qualifier --test selection --test schema_v18 --test
  schema_v17 --test adjustment --test recipe --test ungraded --test patch_door --test curves --test
  schema_v2` (10, 6, 6, 5, 18, 15, 5, 9, 9, 40 passed, first run); `make lint` clean; `make
  typecheck` (0 errors, the 4 baseline warnings); `swift_build.py typecheck
  tools/proof/qualifier_probe.swift`; `qualifier_proof.py` on Debug, the MCP rows 23/23 and
  K1–K8 8/8 after deviations (2), (5) and (6) (N0 is scored on Release only);
  `seeing_proof.py --only V4,U2` (the tag stack keeps V4's hidden tag in the dump); `inventory.py
  --check` and `spec_index_proof.py` 153/153.
- `make gate`: PASSED in 238 s (typecheck 5 s, fmt 2 s, lint 1 s, test 139 s, app 91 s).
- `RC_PROOF_APP=release python3 tools/proof/qualifier_proof.py compare
  tools/proof/work/qualifier-control`, whole, on the gate's Release build and the final
  instrument: 32/32 — N0 the six unqualified frames byte-identical at 16 bits; no `Reelcut: `
  line, no `DEFAULTS MOVED` (`tools/proof/work/g2-4/qualifier-release.txt`).
- Release: `adjustment_proof.py` 36/36, `seeing_proof.py` 19/19 (G1 recorded: 0.096 / 0.195
  ms), `look_proof.py --only B4` 1/1, `phase8_chrome.py` 150/150.
- `grading_spike.py --measure --tree --tree-base 12f5e81`, once, under heavy host load (load
  67 before, 81 after — another session's build): KT and KA 0/1023 at both sizes; TC held
  (1080p −0.066 ms, 2160p −0.000 ms); **TA held**: 1080p VT:SA − V0:SA −0.023 ms against 0.036,
  2160p +0.044 ms against 0.061 (V0:SA 0.812, VT:SA 0.856 ms, its runs 0.855–0.856: a real
  cost at 4K, inside the bound, from the reading's branch and the moved matte sample).
- `screens.py --only 05c-clip-adjustment,05h-clip-qualifier` on the final Debug build: 7/7, both
  looks, 0 new problems.
- Mutants, thirteen, once each on the final instrument (Debug copies, after M1's matte moved and
  the named rows were widened): every one MUTANT PASS, no other row failing — `hue-wrap-broken`
  (W1 G1), `softness-inside` (H1 S1 S1b L1 W1 D1), `chroma-guard-removed` (G1),
  `saturation-reads-chroma` (S1b S2), `near-black-guard-removed` (S2), `hue-long-way` (A2, CT
  `--test qualifier`), `q-from-graded` (D1 H1), `matte-not-multiplied` (M1),
  `selection-reaches-export` (E1), `qualifier-on-any-clip` (R1, CT `--test qualifier`),
  `paste-keeps-qualifier` (P0, CT `--test qualifier`), `selection-drops-mattes` (M1, CT `--test
  selection`), `pick-not-behind` (K3).

**Owed.** GRD-14 and GRD-15, the owner's standing rows, only. Done, not owed: the `core/CLAUDE.md`
and `app/CLAUDE.md` entries (G2-4's spec, "CLAUDE.md edits owed").

**After review (G2-4).** Review 1 found three should-fixes and two nits, all applied:
`ffi_query.rs`'s `rc_project_frame_recipe_opts` doc names all four options; the Owed line's form;
`app/CLAUDE.md`'s canvas-mode sentence (`+ZoomRegion` is on `CanvasRegionView`, a fourth mode)
and the eighth pipeline's GR-13 clause; `selectionArg` moved above `renderFrame`'s doc;
`core/CLAUDE.md`'s recipe-options list. Review 2 passed. `make gate` PASS (313 s); no proof row or
mutant re-run, since no instrument changed.

## G2-5 — the close (2026-10-11)

**What landed** (2026-10-11, in the worktree on `grading-2`, from `fea3435`). G2-1's accepted
limit, "a mutant forcing `banded` off would survive T1", is closed here rather than filed, with an
instrument row and no product code:
- `scopes_probe.swift`: T1's inner loop factored into `gpuMedian(_:_:_:_:)`, unchanged in
  behaviour (the burst of sixteen, then twelve passes one at a time, the median of the last ten);
  **T2** builds a second library from the tree's `Waveform.metal` with the one line whose trimmed
  text starts `bool banded = ` replaced by `bool banded = false;`, and times the tree's parade and
  that forced-global parade back to back on each of the five 4K fixtures. Zero or several such
  lines is recorded as `anchor`, a compile failure or a nil analyser as `error`; either is a
  FAILURE, never a skip.
- `scopes_proof.py`: `score_t2` (T2 passes when, on the fixture where the forced-global parade
  is slowest, the banded time ≤ `RATIO_MAX` 0.75 × the global one, an instrument threshold, not
  a §11 bound; it first compared the banded worst with the global worst across fixtures,
  and the review moved it, "Review" below); the eleventh mutant,
  `parade-global` (`bool banded = last - first < kParadeBands;` → `bool banded = false;`, must
  fail T2); `TOLERATED = {"parade-global": ["T1"]}`, since the forced-global parade measured
  1.15 ms at 4K on flat in G2-5 (1.019–1.042 in G2-1), at or over T1's 1.1 ms, and fails it
  because of the mutant, and the MUTANT line names any tolerated row that failed; the
  docstring.
- The close's documents: this road map condensed into `designs/adr/grading-2.md`; this file
  moved to `archive/grading-2.md` with its `archive/INDEX.md` row;
  `designs/spec/11-decisions/grading-2.md`'s opening paragraph (the road map closed) and its two
  paths; spec §1's non-goals sentence (wheels, curves and qualifiers are in, GR-10…GR-13; colour
  management deferred, #256); the proofs README's G2-1 section (T2, the eleventh mutant, its
  record) and its four record paths. No Lines cell moved: both spec files kept their line counts.

**Verification**, 2026-10-11, AC power (`pmset -g`: powermode 0, AC Power), Apple M2 Max, macOS
26.5.1:
- `python3 tools/proof/swift_build.py typecheck tools/proof/scopes_probe.swift`: exit 0, the 4
  baseline warnings.
- `make app-debug`: BUILD SUCCEEDED.
- `python3 tools/proof/scopes_proof.py --only T1,T2` on Debug: 2/2. T1 at 4K, worst of five:
  parade 0.624 ms (noise), vectorscope 0.449 (noise), histogram 0.668 (flat). T2 at 4K, banded /
  forced-global ms: flat 0.442 / 1.154, gradient 0.627 / 1.134, near-grey 0.748 / 0.448, noise
  0.624 / 0.672, ramp 0.748 / 0.363; worst 0.748 against 1.154, ratio 0.649. (The global parade is
  slower only where few bins take many pixels, flat and gradient, and faster than the banded one
  on near-grey and the ramp; the row then compared worsts across fixtures, which "Review" below
  changed.)
- `python3 tools/proof/scopes_proof.py --mutant parade-global` (a Debug copy): **MUTANT PASS** —
  T2 failed, banded worst 1.152 ms against global 1.154 (ratio 0.999; both libraries global);
  no other row failed but the tolerated T1 (parade 1.151 ms on flat); 15/17. The other ten
  mutants were not re-run: no anchor line of theirs changed.
- `python3 tools/proof/spec_index_proof.py`: 153/153 (no Lines cell moved).
  `python3 tools/proof/capture_spike/inventory.py --check`: 5/5, exit 0. `git grep -n
  "designs/grading-2\.md" -- . ':!archive'`: nothing.
- `make gate`: PASS in 69 s (test 68 s; typecheck, fmt, lint and app skipped as unchanged, since
  no product input moved: the Release app is the one G2-4's gate built at identical inputs).
- `RC_PROOF_APP=release python3 tools/proof/scopes_proof.py`, whole, on that Release build: 20/20,
  no `Reelcut: ` line, no `DEFAULTS MOVED`. T1 at 4K, worst of five: parade 0.623 ms
  (near-grey), vectorscope 0.392 (gradient), histogram 0.668 (flat); recorded waveform 0.449,
  waveform + vectorscope 0.794; every 1080p figure ≤ 0.541 (the histogram on flat). T2 at 4K,
  banded / forced-global ms: flat 0.440 / 1.155, gradient 0.436 / 1.118, near-grey 0.433 / 0.368,
  noise 0.433 / 0.670, ramp 0.433 / 0.227; worst 0.440 against 1.155, ratio 0.381.

**Review.** T2 as first written scored the banded worst against the global worst, across
fixtures, so it scored the banded parade's near-grey and ramp figures, which moved 0.433 → 0.748
ms between the two runs above. Both runs used one probe build (`277f1e2ff0a67d82`, reused), so
the move is run-to-run GPU clock variance, not Debug against Release. On near-grey and the ramp
banding gains nothing, and 0.649 sat 13 % under 0.75 with the code correct. T2 now scores the
fixture where the forced-global parade is slowest (flat on this host), the one banding is for:
banded ≤ 0.75 × global there. The proof's, the proofs README's, the ADR's and this record's
`TOLERATED` reason also moved off G2-1's "5–7 % under 1.1 ms" to the figure measured here.
Re-verified 2026-10-11, AC power (powermode 0), Apple M2 Max:
- `python3 tools/proof/scopes_proof.py --only T1,T2` on Debug (probe `277f1e2ff0a67d82`
  reused): 2/2. T1 at 4K, worst of five: parade 0.746 ms (noise), vectorscope 0.398 (noise),
  histogram 0.667 (flat). T2 at 4K, banded / forced-global ms: flat 0.442 / 1.149, gradient
  0.436 / 1.121, near-grey 0.433 / 0.362, noise 0.433 / 0.670, ramp 0.433 / 0.219; at flat,
  ratio 0.384.
- `python3 tools/proof/scopes_proof.py --mutant parade-global`: **MUTANT PASS**, 15/17. T2 failed
  at flat, banded 1.152 ms against global 1.157, ratio 0.995. No other row failed but the
  tolerated T1 (parade 1.153 ms on flat).
- `make gate`: PASS in 70 s (test 70 s; typecheck, fmt, lint and app skipped as unchanged).
- `RC_PROOF_APP=release python3 tools/proof/scopes_proof.py`, whole: 20/20, no `Reelcut: ` line,
  no `DEFAULTS MOVED`. T1 at 4K, worst of five: parade 0.624 ms (noise), vectorscope 0.447
  (noise), histogram 0.667 (flat). T2 at 4K, banded / forced-global ms: flat 0.440 / 1.153,
  gradient 0.436 / 1.130, near-grey 0.433 / 0.367, noise 0.434 / 0.670, ramp 0.433 / 0.221;
  at flat, ratio 0.382.

**Issues.** Filed at the close, each `ai-drafted` and `low-priority` (all but #272 also
`enhancement`), after a search of every issue, open and closed, found none of them: #265
(vectorscope zoom), #266 (an Offset wheel), #267 (hue-vs-hue and hue-vs-saturation
curves), #268 (a cleanup blur of the qualifier's selection), #269 (a qualifier on picture
clips), #270 (the curves editor's extras), #271 (animating between curves of different point
counts), #272 (the master strip's off-knob double-click, two undo steps), #273 (1,024-level
scopes for 10-bit work). Commented: #256 (tier 3: what tier 2 defined on encoded values), #264
(the texture slots; an input LUT's place before 4c; the qualifier reads encoded values), #124
(its cutout would take `texture(4)`). #260, #261, #262 and #263 were already CLOSED
(`gh issue view`). #257 stays for after tier 2 (owner, 2026-10-10), untouched.

**Owed.** GRD-11…GRD-15, the owner's standing rows in `docs/manual-checks.md`. The root
`CLAUDE.md`'s "Where to look" `designs/adr/` cell gains a `grading-2` entry, the orchestrator's.

**Reviews (G2-5).** Three reviews: the first's two should-fixes (T2 scored at the fixture where
the forced-global parade is slowest; the tolerated-T1 reason) and three nits applied; the second's
probe comment and two record figures applied, `make gate` PASS (67 s); the third passed. Filed:
#265–#273. Commented: #256, #264 (corrected: a qualifier reads the picture an input LUT has
already converted), #124.
