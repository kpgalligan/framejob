# Spec §11 — decisions: Grading (road map "grading")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/grading.md`, and
the original, `archive/grading.md`, holds each phase's record (GR0 the spike and the route, GR1
the pure moves on main, GR2 onwards on the `grading` branch, GR7b the owner's verdict and the
merge's renumbering). GR-1,
GR-2, GR-3 and GR-9 were recorded in GR2, before its code, from the owner's answers of
2026-10-09 ("Start grading", then "All as recommended" to the brief's choices, and "All as
recommended" again to GR2's nine choices). GR-4 and GR-5 were recorded in GR3, before its code,
from the owner's "All as recommended" to GR3's eleven choices (2026-10-09). GR-6 was recorded in GR4a, before its code,
from the owner's "All as recommended" to GR4's twelve choices, both halves (2026-10-10). GR-7 was
recorded in GR5a, before its code, from the owner's "All as recommended" to GR5's thirteen choices,
with Black & White as the eighth look (2026-10-10). GR-8 was recorded in GR6a, before its code,
from the owner's "All as recommended" to GR6's eleven choices, both halves, with no log clip to
check (2026-10-10). The brief's D2 and D3 (from the effects survey) are not recorded as written: GR-1
stands in their place.

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies, never a runtime); G-1;
R5-5; §7.5's blending in encoded sRGB; MT-1..MT-9; PR-1..PR-5; "media by reference"; G-35.
**The Concat rule** (`designs/adr/effects-survey.md`, "Licensing") stands for every phase: tone's
formulas are textbook (the sRGB transfer functions of IEC 61966-2-1, Rec. 709 luma weights) and
Frame Job's own numbers, and nothing of Concat is opened, at design time or build time.

- **GR-1 — The grading experiment: tier 1 is IN, kept by the owner's verdict; tiers 2 and 3 are filed as issues.** Tier 1 is tone, adjustment clips, looks and `.cube` LUT import, with a way to see the
  grade: a before/after switch (View ▸ Show Ungraded, preview only) and one luma waveform. Flip and
  the shape mask leave the experiment (flip touches nothing about colour; a matte track over an
  adjustment clip does the mask's job). Wheels, curves, qualifiers, further scopes and the rest of
  tiers 2 and 3 are not OUT: they wait for the owner's verdict at GR7 (`archive/grading.md`, "Worth
  keeping"). **Amends spec §1**: its non-goal "color grading beyond per-clip controls" and the bar
  sentence's "scopes" no longer bind tier 1, and road map 2 §4's "LUTs (`.cube`)" exclusion
  (archived) is reversed by this entry. Risk accepted: the experiment costs the phases it takes,
  and a "no" leaves it unmerged. **Verdict (owner, 2026-10-10): kept**, merged into main; tiers 2
  and 3 are deferred as issues, not out. The owner: "I think we can merge this", and "T1 and T3
  look good to me. I'll get feedback later from others and we can adjust." T4 ran with test LUTs,
  not one of his own ("LUT worked"); T2, T5 and T6 were not run by him, and GRD-1…GRD-6 were not
  reported (they stay standing rows in `docs/manual-checks.md`, with GRD-7…GRD-10 added for T2,
  T5, T6 and other people's feedback).
- **GR-2 — Tone: nine keys under `video.color`, applied at step 4c behind a uniform flag;
  exposure and white balance in LOCAL linear light.**
  - The keys follow `hue` in this one order everywhere (the JSON, the uniforms, the inspector):
    `exposure` (−3…+3, in EV), `temperature`, `tint`, `highlights`, `shadows`, `whites`, `blacks`,
    `vibrance` (each −1…+1) and `fade` (0…1). Neutral is 0 for every one; a key is written only
    when not 0, so an untoned file's text is unchanged. Out of range is refused in the rule's own
    sentence (`video.color.exposure must be between -3 and 3, not 3.5`), never clamped by the
    patch; an action's end is clamped like the other colour keys. Set by `set_video {patch:
    {color: {…}}}` (no new op, no op-table row), animated by actions like every number (§5.4).
  - The strengths at ±1 are Frame Job's own (GR0's spike numbers, tunable at GR7): exposure ±1 is
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
  **Amended by GR-11** (grading-2 G2-2): `LayerUniforms` grows by the wheels' group of twelve,
  116 → 128 floats (512 bytes), as this entry grew it; the Color sub-tab gains a Wheels section
  after Color. The tone keys' rules (written only when not 0, refused not clamped, an action's
  end clamped) are copied for `video.wheels`.
  **Amended by GR-12** (grading-2 G2-3): `curvesEnabled`, reserved by GR-11, is read (the block
  stays 128 floats); the Color sub-tab gains a Curves section after Wheels. The tone keys' rules
  (an identity written absent, refused not clamped, an action's end clamped) are copied for
  `video.curves`.
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
  **Amended by GR-11** (grading-2 G2-2): `ungraded` also writes `video.wheels` neutral (all nine
  values 0) on every layer.
  **Amended by GR-12** (grading-2 G2-3): `ungraded` also writes `video.curves` as the identity
  (all four channels `[[0, 0], [1, 1]]`) on every layer.
  **Amended by GR-13** (grading-2 G2-4): `ungraded` keeps `video.qualifier`, so a neutral
  adjustment clip with a qualifier still draws nothing.
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
  **Amended by GR-10** (grading-2 G2-0): the header "Waveform" becomes a slot picker in each of
  two stacked slots, View ▸ Waveform is renamed View ▸ Scopes (⌃⌘W), "no other scope" is taken
  up (parade, vectorscope, histogram), and `render_frame` gains `parade`, `vectorscope` and
  `histogram` beside `waveform`. The tap, latest-wins, preview-only and 256-level rules stand.
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
  - **The pass.** The compositor's eighth pipeline, `framejob_adjust_fragment`, reads the target
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
  **Amended by GR-11** (grading-2 G2-2): the adjustment clip's Color sub-tab gains Wheels, and
  the adjustment pass runs the wheels (step 4c.1) after tone and before the look, as the layer
  stage does.
  **Amended by GR-12** (grading-2 G2-3): the adjustment clip's Color sub-tab gains Curves, and
  the adjustment pass runs the curves (step 4c.2) after the wheels and before the look, as the
  layer stage does.
  **Amended by GR-13** (grading-2 G2-4): the adjustment clip's Color sub-tab gains the
  Qualifier section after Adjustment; the pass's weight becomes `opacity × matte × q`, `q` the
  qualifier's reading of the destination before the grade; Paste Attributes drops a qualifier
  onto a picture clip and an adjustment target keeps its own from a picture clip.
  **Amended by NM-6** (rename R0): `reelcut_adjust_fragment` is now `framejob_adjust_fragment`.
- **GR-7 — Looks: `video.look {kind, amount}`, eight built-ins defined in the core as data,
  baked on the GPU into a 33³ `rgba16Float` lattice and mixed at step 4d.** The owner's thirteen
  choices of 2026-10-10, each as recommended, the eighth look Black & White (not Night); GR5a
  builds the model, the picture and the MCP mirror, GR5b the gallery, the Look section and the
  menu ([b] below).
  - **The eight** (choice 1), a closed `LookKind` in this order, which is the gallery's and the
    menu's (appended, never reordered): `warm` (Warm), `cool` (Cool), `teal_orange` (Teal &
    Orange), `vivid` (Vivid), `faded` (Faded), `vintage` (Vintage), `dramatic` (Dramatic),
    `black_white` (Black & White). Each is built from Color's four keys, Light's nine (GR-2's
    strengths) and a **split tone** — a shadow hue and a highlight hue in degrees, each with an
    amount 0…1 — with every unlisted value 0. Generic names and Frame Job's own first numbers, tuned
    by the owner by eye at GR7:
    | kind | in plain words | blocks |
    |---|---|---|
    | `warm` | golden, sunny | temperature 0.35, tint 0.05, vibrance 0.10; highlights split 40° 0.25 |
    | `cool` | crisp, cold | temperature −0.35, contrast 0.05; shadows split 215° 0.30 |
    | `teal_orange` | blockbuster: teal shadows, warm skin | contrast 0.15, vibrance 0.20; shadows 190° 0.60, highlights 35° 0.45 |
    | `vivid` | punchy, richer colour, deeper blacks | contrast 0.15, saturation 0.10, vibrance 0.40, whites 0.20, blacks −0.20 |
    | `faded` | soft matte, muted | contrast −0.15, saturation −0.25, highlights −0.15, fade 0.60 |
    | `vintage` | old print: warm, faded, green shadows, cream highlights | contrast −0.05, saturation −0.30, temperature 0.25, fade 0.40; shadows 160° 0.30, highlights 50° 0.35 |
    | `dramatic` | moody: darker, harder, drained, cold shadows | exposure −0.25, contrast 0.25, saturation −0.35, highlights −0.20, shadows −0.20; shadows 220° 0.20 |
    | `black_white` | monochrome with a little punch | saturation −1, contrast 0.20, whites 0.10, blacks −0.10 |
  - **Amount** (choice 2): 0…1 (0–100 %), 1 by default; outside it is refused in the rule's own
    sentence (`video.look.amount must be between 0 and 1, not 1.5`), never clamped by a patch; an
    action's end is clamped (NaN to 0). An unknown kind is refused by the patch read, naming the
    eight.
  - **Order** (choice 3): in a layer, Color's four, then Light, then **the look**, then the point
    filters, then opacity — correct first, then the look; on an adjustment clip the same, over what
    is behind it. **Split tone lives only inside looks** (choice 4): no Light row.
  - **The bake.** The core publishes each look's DEFINITION in the recipe (`look: {kind, amount,
    definition: {color, split}}`, or `null` when there is no look, its amount is 0 or the frame is
    ungraded), and the compositor bakes it once per definition on the GPU, by a compute kernel that
    runs the identity lattice through the layer stage's own functions — step 3's colour adjust
    (`gradeSample`, chroma off), step 4c's tone (`gradeTone`) and the split tone, `rgb += 0.2 ·
    (shadow amount · (1 − Y)² · chroma(shadow hue) + highlight amount · Y² · chroma(highlight
    hue))`, Y the saturated Rec. 709 luma and chroma(h) the fully saturated hue h less its own
    luma — into a **33³ `rgba16Float` 3D texture**, kept in a least-recently-used cache of eight
    keyed by the definition. A failed bake answers the identity.
  - **Step 4d** applies it once per pixel, right after 4c: the lattice sampled trilinearly at
    `saturate(rgb)·(n−1)/n + 0.5/n` and mixed in by `amount`. The texture is bound at
    **`texture(2)`** on every draw through the three fragments that run the stage
    (`framejob_layer_fragment`, `framejob_layer_blend_fragment`, `framejob_adjust_fragment`); a
    layer with no look binds a **2³ identity placeholder** and never samples it, because
    `LayerUniforms`' two reserved tone floats become `lookAmount` and `lookEnabled` (still 116
    floats, 464 bytes) and `lookEnabled` joins the effects gate's sum — GR0's route VF, so a
    look-less layer renders byte-identical.
  - **Seeing it** (choice 10): Show Ungraded and `render_frame {ungraded}` remove every look, an
    adjustment clip's included (GR-4 extended); an export never does; the chroma-key eyedropper
    removes the look while it picks, as it does Light and Color.
  - **Animation** (choice 11): `amount` animates like every number; a change of `kind` switches at
    the action's end (§5.4's discriminant rule); a look is faded in by animating `amount` from 0.
    An action's end that names a look with no `kind` on a clip that has none (and so does not read
    as a look) evaluates as no look, and never costs the end its other keys.
  - **No new op, tool or format number** (choices 12, 13): `set_video {patch: {look: {kind,
    amount?}}}` sets it — a new kind keeps the clip's amount, a clip with none gets 1 — and `look:
    null` removes it; a `look` with no `kind` on a clip that has none is refused. The key is
    optional and absent when there is no look, so the format stays 1015 (GR-9's rule): a branch
    build from before GR5 drops a look on save. Through MCP `set_video` reaches any clip, as
    Color's keys do (GR-2's parity).
  - **[b] The Look section** (choice 5), in the Color sub-tab after Color (Adjustment · Light ·
    Color · Look), closed by default. **The gallery** (choice 6): a 3×3 grid — None, then the
    eight in the table's order — each tile a thumbnail with its name beneath, the shared kind
    outlined in the accent (none when mixed); under it an Amount row (0–100 %, quick
    0/25/50/75/100) shown only when every selected clip has a look; the summary "Warm 80%",
    "none" or "mixed"; Reset removes the look. **Thumbnails** (choice 7): the composited frame at
    the playhead (inside the first selected clip, else its first frame) with that tile's look on
    every selected clip at the first clip's amount (100 % if it has none) — exactly what a click
    gives — through `render_frame`'s renderer at 256 px wide, refreshed 0.3 s after the selection,
    the project or the playhead stop changing (never mid-playback) and only while the section is
    open. **A tile click** (choice 8) sets the kind and keeps each clip's amount (100 % for a clip
    with none); None removes; undo "Look". **Clip ▸ Look ▸** (choice 9), after Motion ▸: the eight,
    a separator, None; a checkmark on the shared kind, a dash when mixed; for the selected clips
    that take a grade (video, image, still, adjustment), off when none do; no shortcut; undo
    "Look".
  - **[b] The four points choices 6–9 left open**, accepted by the owner "As described" on
    2026-10-10 (GR5b): (1) **with an action selected**, a tile, None, Reset and Clip ▸ Look ▸
    change the clip's OWN look (its base props), as Motion's section and menu do; only the
    Amount row writes the action's end — in an end, `look: null` only stops animating the look
    (`core/src/patch.rs`), so it could not remove one. (2) **A thumbnail renders the click's own
    op**, `set_video {look: {kind}}`: each clip keeps its amount, 1 if it has none — for one
    clip, or clips sharing an amount, that is choice 7's "the first clip's amount". (3)
    **Mixed:** the menu dashes each item that some but not all of the targets carry (None: a
    target with no look); the gallery outlines the shared kind, None when no target has a look,
    and nothing when mixed; the summary is "mixed" when the kinds OR the amounts differ. (4)
    **Thumbnails ignore Show Ungraded**, as an export does. Undo names: "Look" for a tile, None,
    Reset and every menu item; "Amount" for the Amount row. Two dev seams, both absent from
    Distribution (V-1): `select_inspector_tab`'s `section` scrolls the shown pane to a section
    and its answer carries `look_thumbnails_pending` while the gallery has renders owed, and the
    launch default `-RCDevLookGalleryDump <folder>` writes each completed generation's nine
    thumbnails and a manifest there.
  - **The Concat rule stands**: the looks are the table's numbers and the textbook formulas above
    (Rec. 709 luma, the HSV hue ramp, IEC 61966-2-1 inside 4c); no Core Image, and nothing of
    Concat is opened at design or build time.
  - Risk accepted: a looked layer costs one 3D sample more than a toned one, and the first frame
    of a new definition pays its bake (GR5a's record measures it); `.cube` import (GR-8) is how a
    person gets a look that is not one of the eight.
  **Amended by GR-11** (grading-2 G2-2): the order becomes Color's four, Light, the wheels (step
  4c.1), the look, the point filters. A look stays Color, Light and split tone; the bake is
  unchanged and the wheels are the clip's own.
  **Amended by GR-12** (grading-2 G2-3): the order becomes Color's four, Light, the wheels, the
  curves (step 4c.2), the look, the point filters. The bake is unchanged and the curves are the
  clip's own.
  **Amended by NM-6** (rename R0): `reelcut_layer_fragment` is now `framejob_layer_fragment`;
  `reelcut_layer_blend_fragment` is now `framejob_layer_blend_fragment`; `reelcut_adjust_fragment`
  is now `framejob_adjust_fragment`.
- **GR-8 — `.cube` LUTs: a LUT is MEDIA of kind `lut`, parsed by the core, applied as
  `video.look {kind: "lut", media, amount}` at step 4d to the layer's encoded values.** The
  owner's eleven choices (GR6, 2026-10-10, "all as recommended"); [b] marks what GR6b builds.
  - **Importing** (choice 1): File ▸ Add Media… lists `.cube`, and a Finder drop on the Media tab
    imports one, both through `MediaImporter.probe` (`import_media` mirrors them). A drop on the
    Dock or the window opens documents, as before. [b] An "Import LUT…" button under the Look
    gallery imports and applies to the selected clips as one undo step, "Import LUT".
  - **The media row** (choice 2): `media[].kind` gains `lut` — referenced where it lies (spec §11
    "media by reference"), relinked and consolidated like footage — with no video, audio, alpha or
    duration (`add_media` refuses a `lut` row carrying any). The Media tab draws it with a cube
    glyph and the meta "LUT", the existing missing badge, no thumbnail; it is never placed as a
    clip (no drag to the timeline, Insert and Overwrite at Playhead off; `add_clip`,
    `insert_clip` and `overwrite_clip` refuse it in the core's sentence, `media 7 is a LUT: apply
    it as a look (set_video {look: {kind: "lut", media: 7}}), it is not placed as a clip`, and
    `add_background` as a media with no pixel size). Reveal in Timeline selects the clips whose look it is.
  - **[b] Applying** (choice 3): the Look gallery gains an "Imported" group under its 3×3 grid,
    a tile per LUT in Media-tab order named by its file name without `.cube`, thumbnails by
    GR-7's rule; Clip ▸ Look ▸ lists them after the eight, under a separator, before None. No
    separate picker.
  - **[b] How GR6b reads choices 1 and 3** (recorded before its code; decided, not asked):
    "Media-tab order" is the media list's own order, the Media tab's default Import Order — the
    gallery and the menu do not follow the tab's sort or search, which are per-window view state
    (`MediaListFilter.swift`). Clip ▸ Look ▸ reads the eight · a separator · the LUTs · a
    separator · None, and with no LUT is unchanged (the eight · a separator · None). A LUT whose
    file is missing keeps its tile and its item; its thumbnail is the ungraded frame, as its
    picture is, and the Media tab badges it (choice 5). "Import LUT…" sits under the gallery
    (under the Imported group when there is one) and above the Amount row; it is off when no
    selected clip takes a grade; with an action selected it writes the clip's own look, as a tile
    does (GR-7 [b] (1)); a file already in the media list is reused, not added again; a refused
    file shows choice 7's sentence in the document's error sheet and changes nothing. A tile and
    a menu item are named by the media's name (a consolidated copy is named after its original)
    less a trailing `.cube` in any case; two LUTs with one name show two tiles and items with that
    title. The summary of a LUT look is "<name> 80%". A tile or item for a LUT writes `{kind:
    "lut", media}` with no amount, so each clip keeps its own (100 % for a clip with none); undo
    "Look".
  - **The look** (choice 4): `video.look` gains the kind `lut` and the key `media` (the LUT's
    media id, stored between `kind` and `amount` and written only with `lut`). `media` is
    required with `lut` and refused with a built-in kind, and must name a `lut` media of the
    project, each in its own sentence; a patch naming a built-in kind and no `media` drops a stored
    one, so a built-in kind on a LUT clip replaces the LUT. Amount is the look's own (0–100 %, 100 %
    by default), animatable; a change of LUT switches at an action's end, never interpolating the
    id. An action's end is not checked against the media list (`set_action_end` never was): an
    end naming a LUT that is not there evaluates as no look.
  - **A missing LUT** (choice 5): the clip draws ungraded (no slate over footage); the Media tab
    badges it and the open-time missing-media sheet lists it; a relink brings the look back. A LUT
    changed on disk is re-read at the next frame drawn (the texture cache keys by path, size and
    modification date).
  - **Removing a used LUT** (choice 6): Remove asks "It is the look of N clips, which keep their
    place and lose the look." with "Remove and Clear Looks"; the clips stay, undoable. `remove_media`
    without `with_clips` refuses naming the clips (`media 7 is the look of clip 3; pass with_clips:
    true to remove it and clear their looks`); with it, every base look naming the LUT, on the
    timeline and in every nest, is removed, and action ends are left alone (inert).
  - **What is read** (choice 7): 3D only; `LUT_3D_SIZE` 2–65; `TITLE`; `#` comments; blank lines;
    CRLF; a UTF-8 BOM; `DOMAIN_MIN 0 0 0`, `DOMAIN_MAX 1 1 1` and `LUT_3D_INPUT_RANGE 0 1` (the
    defaults); table values any finite number, red fastest, clamped to 0–1 when drawn. **Refused by
    name**: a 1D LUT (`LUT_1D_SIZE`, `LUT_1D_INPUT_RANGE`), a size outside 2–65, a non-default
    domain or input range, any other keyword, a keyword after the table, a short or long table, a
    non-number, a file over 32 MB (`RC_CUBE_MAX_BYTES`) or not text. The import refusal reads
    `“Film.cube” is not a LUT Frame Job reads: line 2: LUT_3D_SIZE 200 is outside 2–65.` — the file's
    name, then the parser's own sentence. Refuse rather than guess.
  - **Where it applies** (choice 8): to the layer's ENCODED values — what camera and creative LUTs
    expect — at step 4d like a built-in look (after Color and Light, before the point filters),
    sampled trilinearly from an `rgba16Float` `size³` 3D texture at `texture(2)`, mixed by
    `amount`. The recipe's look for a LUT is `{"kind": "lut", "amount": a, "media": id}` with no
    definition; the app reads the file through the media's URL, parses it with the core
    (`rc_cube_parse`), and keeps a least-recently-used cache of eight textures.
  - **Seeing it** (choice 9): Show Ungraded and `render_frame {ungraded}` remove a LUT look like
    every look; an export never does.
  - **Log and HDR footage** (choice 10): Frame Job converts nothing in GR6. **Measured (GR6a's T0,
    Release, 2026-10-10)**: one 10-bit ProRes 422 chart re-tagged by stream copy. AVFoundation
    ignores the tags in the ProRes frame headers (every header-only tag drew the untagged frame's
    bytes) and reads the container's `colr` atom: tagged there, HLG and PQ draw the grey ramp
    UNCHANGED (no transfer conversion; only the BT.2020 matrix moves a saturated patch, red 255 → 243),
    BT.2020 primaries with the BT.709 transfer draw grey 129 as 66 (the BT.709 inverse OETF of 0.506
    is 0.265, ≈ 67: those frames arrive linearised), and an untagged file differs from a
    `colr`-tagged BT.709 one by up to 22 levels on saturated patches. So a camera LUT meets HLG and
    PQ footage still in its transfer, as such LUTs expect, and a BT.2020/709 file in linear light,
    which no LUT expects. **Log footage (Apple Log and the rest) is unchecked**: ffmpeg cannot make
    it and the owner has no log clip.
  - **Copy and paste** (choice 11): Copy/Paste and Paste Attributes into another project bring the
    LUT's media row with the look, matched by path like any media; a look id the payload does not
    carry becomes no look rather than another media's id.
  - **No new op, tool or format number**: `set_video` and `add_media`/`import_media` carry it; the
    format stays 1015 (GR-9's rule, GR-6's precedent: a pre-GR6 branch build refuses a `lut` media
    kind by name). The core exports `rc_cube_parse`, `rc_cube_size`, `rc_cube_copy_rgb` and
    `rc_cube_free`.
  - **The Concat rule stands**: the parser is written from the `.cube` format's own description,
    and every test LUT is written by a script.
  - Risk accepted: a LUT that expects log or linear input draws wrong on Frame Job's encoded values
    unless the footage is what the LUT was made for, and nothing warns; non-default domains, 1D and
    shaper LUTs are refused, not read.
  **Amended by GR-15** (grading-3 T3-0): T0's "HLG and PQ draw the grey ramp UNCHANGED (no
  transfer conversion; …)" is true of the path T0 measured, `render_frame`'s
  `AVAssetImageGenerator`, and of the first frame a decoder delivers of each HLG or PQ clip; the
  export reader's later frames and the player convert them to SDR (the tier-3 brief, 2026-10-11:
  grey signal 0.5 → HLG 0.3843, PQ 0.7192; `archive/grading-3.md`, "How it fits the tree"). From
  T3-1 every source arrives native and honestly labelled (`canConformColorOfSourceFrames`), and
  Frame Job's step 0 converts HLG, PQ and BT.2020-with-BT.709-transfer sources to SDR Rec. 709
  before the layer stage, so a LUT at 4d meets them converted, on every path.
  **Amended by GR-16** (grading-3 T3-0): log is checked on a synthetic file. A ProRes file
  labelled Apple Log reads back with `LogTransferFunction = com.apple.rec2020.apple-log` (a
  `logs` atom; `colr` BT.2020 primaries, transfer unspecified, BT.2020 matrix) and arrives
  unconverted on every path, so a LUT meets its log values intact; a real iPhone file is owed
  (GRD-17). The accepted risk shrinks: from T3-2 a media's `color` setting converts camera log at
  step 0, before the chroma key and Color's four; a `lut` media can serve as that conversion (Use
  LUT…); and the Look section warns when a clip's media converts and its look is a LUT. A LUT
  applied as a look still meets encoded values at 4d.
  **Amended by NM-5** (rename R0): the import refusal `“Film.cube” is not a LUT Reelcut reads: …`
  is now `“Film.cube” is not a LUT Frame Job reads: …`.
- **GR-9 — The branch wrote project format 1015 and refused 15–1014 by name; at the merge 1015
  became 15.** The branch's `RC_FORMAT_VERSION` was **1015** (main's 14 plus a thousand), in
  `core/src/format.rs` and the header, so every main build refused a branch-made project as "made
  by a newer Frame Job" instead of opening it and dropping its grades on the next save.
  Its base version was 14: the branch read 1 to 14 and 1015, and refused a file numbered 15 to
  1014 in its own sentence (naming the numbers it reads), because a later main file
  would otherwise open and lose its new keys on save (owner choice 9). Above 1015 the existing
  "newer" sentence answered. The branch had no migrate step: 1015 is 14 plus optional keys (and, since GR-6,
  the `adjustment` source kind, which an older build refuses by name). **At the merge** (GR7b,
  2026-10-10) 1015 became **15**, main's next version. A file numbered 1015 is read as 15 by one
  migration step (`migrate_1015_to_15` in `format.rs`, run before the "newer" gate, mapping to the
  literal 15 so a later bump still runs its own steps from 15; `GRADING_BRANCH_VERSION` names
  the number), so branch-made projects still open. The base-version constant and the gap refusal
  are gone, and 16 and above, 1014 included, are "newer". Risk accepted: a project the owner saved on
  the grading branch opened only there until the merge (he kept his trial projects as copies).
  **Amended by NM-5** (rename R0): the "newer" refusal's "update Reelcut to open it" is now "update
  Frame Job to open it", so "made by a newer Reelcut" is now "made by a newer Frame Job".
