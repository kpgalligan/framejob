# Spec §11 — decisions: Grading (road map "grading", on the `grading` branch)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is open: `designs/grading.md` holds each phase's record (GR0 the
spike and the route, GR1 the pure moves on main, GR2 onwards on the `grading` branch). GR-1,
GR-2, GR-3 and GR-9 were recorded in GR2, before its code, from the owner's answers of
2026-10-09 ("Start grading", then "All as recommended" to the brief's choices, and "All as
recommended" again to GR2's nine choices). GR-4 and GR-5 were recorded in GR3, before its code,
from the owner's "All as recommended" to GR3's eleven choices (2026-10-09). GR-6 was recorded in GR4a, before its code,
from the owner's "All as recommended" to GR4's twelve choices, both halves (2026-10-10). GR-7 and
GR-8 are later phases' and are recorded at their start. The brief's D2 and D3 (from the effects survey) are not recorded as written: GR-1
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
- **GR-4 — The `ungraded` recipe option: the preview and `render_frame` only, never an
  export.** `RecipeOptions` (spec §7.3) gains `ungraded`: every layer's `video.color` (all
  thirteen keys, Color's four and Light's nine) is written neutral, on every layer — nested
  clips, matte clips and an action's end included — so the frame is the picture as if no clip
  were graded. Chroma key, filters, opacity, blend, shadow, crop and every other key are kept.
  GR4 and GR5 extend the same neutralising to adjustment clips and looks. The option travels on
  the KEY (`RecipeSource`, §7.3's rule), never as an export override; the un-optioned recipe is
  byte-identical to the one before it existed, and a non-boolean `ungraded` means off in the core
  (the MCP door refuses it by name).
  - **View ▸ Show Ungraded** (⌃⌘U), a checkmark toggle in the preview group after Preview
    Window, sets it on the window's document key: the editor's preview and the Preview Window
    (one player). A small "Ungraded" tag sits at the preview pane's top-left, inside the 24 pt
    void, while it is on, and takes no clicks.
  - **Never reached by the switch:** an export, Save Frame… (a deliverable, like an export), the
    chroma-key eyedropper and `render_frame` — each mints or passes its own options.
    `render_frame {ungraded: true}` asks for it explicitly.
  - **Not persisted:** per window, off when a project opens, no `UserDefaults` key — so
    `perform_menu_item` can drive it and no proof moves the defaults. It is view state with no
    tool of its own (§7.9's Preview Quality exemption).
- **GR-5 — The luma waveform: the composited preview frame, in a panel beside the preview, and
  no export path.**
  - **What it reads:** the composited, encoded (sRGB) preview frame at Preview Quality's size —
    what the person sees, so ungraded while Show Ungraded is on — taken after the compositor has
    finished it, by a tap that runs only while the panel is shown. Y′ is Rec. 709 luma
    (0.2126 R′ + 0.7152 G′ + 0.0722 B′) of the saturated encoded values; x is the picture's
    columns in 256 bins, y is Y′ in 256 levels (level = round(255 Y′)). Paused it is exact and
    follows every edit; while playing it may lead the shown frame by the few frames AVFoundation
    composes ahead. The tap is latest-wins: at most one pass in flight per window and ONE pending
    frame, each newer frame replacing it and analysed when the pass in flight completes, so the
    last frame composed after an edit is always the one shown.
  - **What it shows:** a white trace with log density on a near-black well in both appearances;
    graticule lines at 0/25/50/75/100 %, labelled 0, 50 and 100; the header "Waveform". A pixel
    clips HIGH at level 255 (Y′ ≥ 254.5/255, what an 8-bit file writes as 255) and LOW at level
    0 (Y′ < 0.5/255); a red 3 pt mark sits on the trace's top edge over each column where at
    least 0.5 % of that column's pixels clip high, and on its bottom edge for low; two readouts
    under the trace, "Highlights clipped 12.5 %" and "Shadows clipped 0.0 %" (the whole frame, one
    decimal; "—" before the first frame).
  - **Where:** **View ▸ Waveform** (⌃⌘W), a checkmark toggle after Show Ungraded: a fixed 248 pt
    column at the right edge of the preview pane (between the picture and the inspector), the
    pane's full height, not resizable; the picture shrinks to the rest, and off is zero width. Not
    persisted, per window, off when a project opens.
  - **What it is not:** no waveform over an export, in the Preview Window or of Save Frame…; no
    other scope (parade, vectorscope, histogram — tier 2). Its MCP mirror is `render_frame
    {waveform: true}`, which writes the same trace's counts beside the PNG; the panel itself is
    view state with no tool (§7.9's exemption).
- **GR-6 — Adjustment clips: a clip kind with no picture that grades everything drawn behind it
  in its container, by its opacity; inert on a matte track; refused in a nest, in any transition,
  and with a neighbourhood filter or a blend.** The owner's twelve choices of 2026-10-10, each as
  recommended; GR4a builds the core, the compositor, the MCP tool and the timeline, GR4b the menu
  item and the inspector ([b] below).
  - **The kind.** `Source::Adjustment`, written `{"kind":"adjustment"}`, with no media, size or
    window. It is added by the op **`add_adjustment_clip {track, at, duration?}`** (an absent
    `duration` is 5 s, as `add_text_clip`'s); the new clip's `video` is the defaults at scale 1.
    While it lasts, its `video.color` (all thirteen keys), its point filters (sepia, noir,
    vignette, invert) and its opacity, the **strength**, apply to what is already drawn behind it.
  - **Reach.** Everything drawn behind it at that instant in its container: every lower track
    and the canvas background, the whole frame; never a track in front. Its stored transform,
    crop, corner, shadow, reflection, chroma, spotlight, obscure and motion placement are kept
    and do nothing (refusing them would make Paste Attributes fail from any moved clip); a
    motion preset's fades fade the grade.
  - **The pass.** The compositor's eighth pipeline, `reelcut_adjust_fragment`, reads the target
    it is drawing into (`[[color(0)]]`) with blending OFF and writes `mix(dst, graded, w)`, where
    `graded` is the un-premultiplied destination through step 4c's colour and tone and the point
    filters (the canvas's uv as their local position), re-premultiplied by the destination's own
    alpha, and `w` is the opacity times the matte coverage. Alpha is preserved. An adjustment
    layer whose colour is neutral and that has no point filter draws nothing.
  - **Mattes (a correction to the road map).** On a track cut by a matte it grades only inside
    the matte: the power window. On a matte track it is **inert**: it draws nothing and cuts
    nothing (the core leaves it out of the recipe), because a matte group is one track and two
    clips on one track share an instant only in a transition, which this entry refuses, so it
    could only be the group's sole member and would act as an empty matte. [b] The Clip tab's
    note says "An adjustment clip on a matte track has no effect."
  - **Commands.** Split (two adjustment clips, actions divided), trim to any length, move,
    ripple, insert time, close gap, and copy, paste and duplicate at the top level all work.
    Refused: nest, a paste into an open nest, and every transition — `add_transition`,
    `set_transition`, `set_transition_style` (which would otherwise mint a `cross_dissolve`) and
    any overlap on its track, a neighbour trimmed or moved over it included, through the overlap
    rule's one door (`check_overlap_rule`). Speed, reverse, freeze and detach audio keep their
    media-only answers. Paste Attributes onto it lands unless the copied video group has blur,
    sharpen, pixelate or a blend, and then the whole paste is refused (`check_blend`'s
    precedent); an action's end carrying them is clamped by the evaluator.
  - **The sentences** (exact; channel in brackets): nest [refused] "clip 12 is an adjustment
    clip, and an adjustment clip cannot go inside a nest"; validate, for a file or a paste into a
    scope [error] "clip 12 in nest 4 is an adjustment clip, and an adjustment clip cannot be
    inside a nest"; the op inside a scope [error] "add_adjustment_clip has no meaning inside nest
    4"; transition [refused] "clip 12 is an adjustment clip and cannot take a transition; fade it
    with opacity instead"; overlap [refused] "clips 7 and 12 would overlap, and clip 12 is an
    adjustment clip, which cannot take a transition; fade it with opacity instead"; filter
    [error] "clip 12 is an adjustment clip and cannot take the blur filter" (or sharpen,
    pixelate); blend [error] "clip 12 is an adjustment clip and cannot take a blend mode".
  - **Show Ungraded (GR-4)** neutralises its colour as any clip's, so a neutral adjustment clip
    with no point filter draws nothing and the frame is byte-identical to one without it; point
    filters stay (GR-4 keeps filters).
  - **The timeline.** A rose ink, `DS.clipAdjustment` (#8C3A5E), in both appearances; the symbol
    `camera.filters` (fallback "◐"); the kind word "adjustment" and the fallback name
    "Adjustment"; a flat body (a name strip and the action lane, no filmstrip or waveform), the
    lane sized as picture. Selected, it has no frame and no handles in the preview (it has no
    box); a click on the picture selects what is behind it.
  - **[b] The menu.** Insert ▸ **Adjustment Clip**, the first item, above Graphic ▸; no toolbar
    button, no context-menu item and no shortcut (bare letters belong to `keyDown`, §9). Its
    span is the In/Out range if one is set, otherwise the selected clips' span, otherwise the
    whole timeline; disabled while a nest is open and on an empty timeline with no range. Its
    track is the front-most track if that is not a matte track and is free over the span,
    otherwise a new front track named "Adjustment"; one undo step; the new clip is selected and
    the inspector opens on Color.
  - **[b] The inspector** (choice 4b): only Color and Clip. Color holds an **Adjustment** section
    with one row, "Strength" (0–100 %, `video.opacity`), then Light, then Color; Clip holds
    Timing and Motion (Motion's fades fade the grade; slide, zoom and spin do nothing). The point
    filters are reachable through MCP and Paste Attributes only. A selection mixing in video
    clips gets no Picture tab, and its Color tab no Strength row.
  - **The format stays 1015 (amends GR-9's "1015 is 14 plus optional keys").** The kind is a new
    `Source` variant, not an optional key: a build that does not know it refuses the file with
    serde's "unknown variant `adjustment`" (`format::read`), so nothing is dropped silently.
  - Not in it: adjustment clips inside nests, an adjustment clip's own transform or shape, and
    refusing the transform keys. Risk accepted: an adjustment clip's stored placement keys are
    inert and shown nowhere in the inspector; they stay reachable through MCP and Paste
    Attributes.
- **GR-9 — The branch writes project format 1015, refuses 15–1014 by name, and the merge
  renumbers.** The branch's `RC_FORMAT_VERSION` is **1015** (main's 14 plus a thousand), in
  `core/src/format.rs` and the header, so every main build refuses a branch-made project as "made
  by a newer Reelcut" instead of opening it and dropping its grades on the next save.
  `BRANCH_BASE_VERSION` is 14: the branch reads 1 to 14 and 1015, and refuses a file numbered 15
  to 1014 in its own sentence ("not one this grading build reads"), because a later main file
  would otherwise open and lose its new keys on save (owner choice 9). Above 1015 the existing
  "newer" sentence answers. No migrate step: 1015 is 14 plus optional keys (and, since GR-6,
  the `adjustment` source kind, which an older build refuses by name). **At the merge** 1015
  is renumbered to main's next version, with one migration arm mapping 1015 to it, so branch-made
  projects still open; the gap refusal and `BRANCH_BASE_VERSION` go with it. Risk accepted: a
  project the owner saves on the branch opens only on the branch until the merge (he keeps his
  trial projects as copies).
