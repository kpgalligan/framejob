# Spec §11 — decisions: Grading (road map "grading", on the `grading` branch)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is open: `designs/grading.md` holds each phase's record (GR0 the
spike and the route, GR1 the pure moves on main, GR2 onwards on the `grading` branch). GR-1,
GR-2, GR-3 and GR-9 were recorded in GR2, before its code, from the owner's answers of
2026-10-09 ("Start grading", then "All as recommended" to the brief's choices, and "All as
recommended" again to GR2's nine choices). GR-4..GR-8 are later phases' and are recorded at
their start. The brief's D2 and D3 (from the effects survey) are not recorded as written: GR-1
stands in their place.

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies, never a runtime); G-1;
R5-5; §7.5's blending in encoded sRGB; MT-1..MT-9; PR-1..PR-5; "media by reference"; G-35.
**The Concat rule** (`designs/adr/effects-survey.md`, "Licensing") stands for every phase: tone's
formulas are textbook (the sRGB transfer functions of IEC 61966-2-1, Rec. 709 luma weights) and
Reelcut's own numbers, and nothing of Concat is opened, at design time or build time.

- **GR-1 — The grading experiment: tier 1 is IN on the branch; tiers 2 and 3 wait for the
  verdict.** Tier 1 is tone, adjustment clips, looks and `.cube` LUT import, with a way to see the
  grade: a before/after switch (View ▸ Show Ungraded, preview only) and one luma waveform. Flip and
  the shape mask leave the experiment (flip touches nothing about colour; a matte track over an
  adjustment clip does the mask's job). Wheels, curves, qualifiers, further scopes and the rest of
  tiers 2 and 3 are not OUT: they wait for the owner's verdict at GR7 (`designs/grading.md`, "Worth
  keeping"). **Amends spec §1**: its non-goal "color grading beyond per-clip controls" and the bar
  sentence's "scopes" no longer bind the branch, and road map 2 §4's "LUTs (`.cube`)" exclusion
  (archived) is reversed by this entry. On main both stand until a merge. Risk accepted: the
  experiment costs the phases it takes, and a "no" leaves the branch unmerged.
- **GR-2 — Tone: nine keys under `video.color`, applied at step 4c behind a uniform flag;
  exposure and white balance in LOCAL linear light.**
  - The keys follow `hue` in this one order everywhere (the JSON, the uniforms, the inspector):
    `exposure` (−3…+3, in EV), `temperature`, `tint`, `highlights`, `shadows`, `whites`, `blacks`,
    `vibrance` (each −1…+1) and `fade` (0…1). Neutral is 0 for every one; a key is written only
    when not 0, so an untoned file's text is unchanged. Out of range is refused in the rule's own
    sentence (`video.color.exposure must be between -3 and 3, not 3.5`), never clamped by the
    patch; an action's end is clamped like the other colour keys. Set by `set_video {patch:
    {color: {…}}}` (no new op, no op-table row), animated by actions like every number (§5.4).
  - The strengths at ±1 are Reelcut's own (GR0's spike numbers, tunable at GR7): exposure ±1 is
    ×2 / ×½ on linear light; temperature ±1 is red ×2^±0.3 and blue ×2^∓0.3 on linear light; tint
    +1 is green ×2^−0.3 (towards magenta); highlights and shadows ±1 lift by ±0.25 weighted to the
    top and bottom halves of luma; whites and blacks ±1 stretch by ±15 % held at black and at
    white; vibrance ±1 scales saturation by 1 ± 1 on low-saturation colours and not at all at full
    saturation; fade 1 takes black to 10 % and white to 95 %.
  - **Step 4c** applies them once per pixel, after the obscure regions (4b) and before the point
    filters (5): obscured content is toned like the picture around it, and sepia and noir act on
    the toned colour. Exposure and the white-balance gains decode to linear light (IEC 61966-2-1),
    multiply, and re-encode INSIDE 4c; highlights, shadows, whites, blacks, vibrance and fade work
    on encoded values. This is a local colour transform like `hueRotate`: it does **not** amend
    §7.5 (blending stays encoded) or PR-5's "linear light deferred", which is about the whole
    pipeline.
  - **The route is GR0's VF**: `LayerUniforms` gains a tone group of twelve floats (the nine, then
    `toneEnabled` and two reserved), 104 → 116 floats, 416 → 464 bytes; `toneEnabled` is 1 exactly
    when any of the nine is not 0 and joins the effects block's gate sum, so an untoned layer never
    enters 4c and renders byte-identical. MT-6's "104 floats" described the matte's route; the block
    growing is this decision's consequence. GR0's figures: the flag costs an ungraded layer
    0.000 ms at 1080p and 0.001 ms at 4K; a toned layer about 0.05 / 0.2 ms.
  - **The inspector** (owner, 2026-10-09, GR2's choices 1–8, each as recommended): a **Color**
    sub-tab after Picture (Text/Shape/Graphic · Picture · Color · Sound · Clip), shown when the
    selection has clips that draw and every selected clip has source pixels (media, image, still)
    — never for text, shape, graphic, nest or audio-only media clips; Picture stays the default.
    Its sections are **Light** (new, `video.light`) then **Color** (moved from Picture, its four
    rows unchanged); with no stored preference the tab opens Light. Light's rows, in the key order
    above, are a slider and a field each, 2 decimals, Exposure's unit "EV"; its summary reads
    "neutral" or "adjusted"; its Reset zeroes only its nine (Color's only its four), undo names
    are the row labels and Reset's "Light". Color's `◆N` is 1 when the selected action's end holds
    `video.color`, and Picture stops counting `color` (amends CI-5 and CI-6). Row marks stay per
    group key (CI-7, CI-9): every Light and Color row shares one mark, and a row's Clear removes
    the action's whole `color` end — accepted for the experiment. The chroma-key eyedropper
    neutralises Light as well as Color while it picks. No menu items and no shortcuts in GR2.
  - **Through MCP** `set_video` reaches any clip, as Color's four keys do; only the inspector is
    limited to source-pixel clips (§7.9's parity stands: the tool is the mirror of the rows).
  - Risk accepted: a graded layer under VF costs more than under function constants (GR0 T2, tone only,
    0.197 against 0.084 ms at 4K), well inside the 8 ms budget.
- **GR-3 — Precision: grading runs on PR-1's float pipeline; blending stays encoded (§7.5).**
  Every stage between layers is `rgba16Float` and every video source decodes deep (PR-1, PR-2),
  so a stacked grade keeps its levels by construction (GR0's P1: −1 EV then +1 EV through
  `rgba16Float` kept 256 distinct levels of 256). The brief's dither fallback falls away. Linear
  light stays local to step 4c (GR-2); the blend, the dissolve and the matte stay in encoded sRGB.
- **GR-9 — The branch writes project format 1015, refuses 15–1014 by name, and the merge
  renumbers.** The branch's `RC_FORMAT_VERSION` is **1015** (main's 14 plus a thousand), in
  `core/src/format.rs` and the header, so every main build refuses a branch-made project as "made
  by a newer Reelcut" instead of opening it and dropping its grades on the next save.
  `BRANCH_BASE_VERSION` is 14: the branch reads 1 to 14 and 1015, and refuses a file numbered 15
  to 1014 in its own sentence ("not one this grading build reads"), because a later main file
  would otherwise open and lose its new keys on save (owner choice 9). Above 1015 the existing
  "newer" sentence answers. No migrate step: 1015 is 14 plus optional keys. **At the merge** 1015
  is renumbered to main's next version, with one migration arm mapping 1015 to it, so branch-made
  projects still open; the gap refusal and `BRANCH_BASE_VERSION` go with it. Risk accepted: a
  project the owner saves on the branch opens only on the branch until the merge (he keeps his
  trial projects as copies).
