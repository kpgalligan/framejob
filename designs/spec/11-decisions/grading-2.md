# Spec §11 — decisions: Grading tier 2 (road map "grading-2")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is `designs/grading-2.md`, open: each phase's record is there (G2-0
the road map, GR-10 and the pure moves; G2-1 scopes; G2-2 wheels; G2-3 curves; G2-4 qualifiers;
G2-5 the close). The IDs continue the GR- series of [`grading.md`](grading.md), so a citation never
has to say which file. GR-10 was recorded in G2-0, before G2-1's code, from the owner's "All as
recommended" (2026-10-10) to the tier-2 brief's choices 1a, 2b, 3a, 4a, 5 yes, 6a, 7 yes, 8b and
9 yes (`designs/grading-2.md`, "The owner's choices"). GR-11, GR-12 and GR-13 are recorded each
before its own phase's code (G2-2, G2-3, G2-4), and GR-14 (the working arrangement) with GR-11
in G2-2.

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies, never a runtime); R5-5;
G-1; §7.5's blending in encoded sRGB; MT-1..MT-9; PR-1..PR-5; GR-1 (tiers 2 and 3 deferred as
issues, not out: tier 2 is that deferral being taken up); GR-3; GR-8; GR-9.
**The Concat rule** (`designs/adr/effects-survey.md`, "Licensing") stands for every phase: the
scopes' maths is the Rec. 709 Y′CbCr matrix (ITU-R BT.709-6), the 75 % colour-bar targets
computed from it, a published ColorChecker patch, and histogram and parade counting; nothing of
Concat is opened, at design time or build time.

- **GR-10 — Scopes: an RGB parade, a vectorscope and a histogram beside the waveform, in two
  stacked slots of GR-5's panel, each held to 1.1 ms of GPU time per 4K frame at its worst.**
  - **It takes up GR-1's deferral and amends GR-5**: "no other scope (parade, vectorscope,
    histogram — tier 2)" is lifted, the panel's header becomes a slot picker, View ▸ Waveform is
    renamed, and `render_frame` gains three booleans (GR-5's amendment line says which of its
    rules stand).
  - **Input:** GR-5's frame, unchanged: the composited, encoded preview frame at Preview
    Quality's size, read by the same latest-wins tap and only while a scope is shown. With two
    scopes shown, both passes go in one command buffer per offered frame.
  - **Parade:** R′, G′ and B′, each binned as GR-5 bins Y′ (256 column bins × 256 levels, level
    = round(255·v)) of the saturated encoded values. Drawn side by side in red, green and blue
    tints, with GR-5's clip marks per channel.
  - **Vectorscope:** Rec. 709 `Cb = (B′−Y′)/1.8556`, `Cr = (R′−Y′)/1.5748` on the saturated
    encoded values, Y′ being GR-5's. 256 × 256 bins centred on neutral: `bin = clamp(128 +
    round(255·c), 0, 255)` for each of Cb and Cr, so a grey is mid-bin 128 and never on an edge
    between two bins. Cb runs right and Cr up, drawn with log density.
  - **Vectorscope targets:** the six 75 % targets come from the same matrix, as (Cb, Cr): R
    (−0.0859, 0.3750), Yl (−0.3750, 0.0344), G (−0.2891, −0.3406), Cy (0.0859, −0.3750), B
    (0.3750, −0.0344), Mg (0.2891, 0.3406).
  - **Skin line:** the hue of the ColorChecker Classic "light skin" patch's published sRGB
    (194, 150, 130) through that matrix: 123.3° counter-clockwise from +Cb. Its source is
    named here and the angle computed, not copied from another tool's graticule.
  - **Histogram:** R′, G′, B′ and Y′ counts per 256 levels (GR-5's level rule), drawn overlaid,
    with GR-5's two clipping readouts.
  - **Counting rule:** never one global atomic per pixel into a counter shared by a picture
    region. The histogram counts per threadgroup and merges once per group. The vectorscope
    counts the central 64 × 64 bins (where neutral and low-saturation pixels land) per
    threadgroup and the rest globally. The parade may count as the waveform does, with
    per-band threadgroup counts as its fallback should its time bound miss.
  - **Time bound** (it replaces #263's): each of parade, vectorscope and histogram takes
    ≤ 1.1 ms of GPU time per analysed 3840 × 2160 frame. The figure is the worst over five
    fixtures: flat mid-grey, G1's grey ramp, near-grey noise (mid-grey ±5/255 per channel), a
    red-across/green-down gradient, and random RGB noise. It is measured in the app's own pass,
    with the host and power state recorded. #263's 0.168 / 0.331 ms is the waveform's figure on
    one ramp and is not the bound, because a ramp is a naive vectorscope's worst case (6.99 ms
    at 4K in the tier-2 brief's scratch spike, `designs/grading-2.md` "Costs").
  - **Panel:** GR-5's 248 pt column holds two stacked slots, each with a picker in its header
    (Waveform, Parade, Vectorscope, Histogram). It opens as Waveform over Vectorscope, and the
    vectorscope is a square at the slot's width. Per window, not persisted (no `UserDefaults`
    key), off when a project opens. Below a pane height that G2-1 sets from screen `04b`, only
    the top slot shows. View ▸ Waveform becomes **View ▸ Scopes** (⌃⌘W), the same checkmark
    toggle in the same place.
  - **Mirror:** `render_frame {parade, vectorscope, histogram}` are booleans beside `waveform`.
    Each writes `<path>.<scope>.json` through the panel's own analyser on the rendered image, so
    the panel and the tool cannot count differently, with a sentence of its own before
    "Written to". The JSON keys (§7.9a) are G2-1's to write. The slot picks are view state with
    no tool (§7.9's exemption, as GR-5's panel).
  - **Not:** no scope over an export, and none in the Preview Window or of Save Frame…. The panel
    and this entry say "Rec. 709" and "encoded", so a wide-gamut or linear-light scope (#256)
    is a second matrix, not a reinterpretation; 256 levels is one constant
    (`WaveformTrace.levels`), so a 1,024-level scope stays possible.
  - Risk accepted: two scopes shown take up to about 1.7 ms of GPU per analysed 4K frame
    (REASONED from the brief's spike), off the render queue and latest-wins, so a slow pass
    drops scope frames rather than stalling playback, but it still takes GPU time from the
    compositor.
