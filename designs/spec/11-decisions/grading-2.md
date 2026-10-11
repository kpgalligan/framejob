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
    vectorscope is a square that fits its slot. Per window, not persisted (no `UserDefaults`
    key), off when a project opens. When the pane cannot hold both slots at their full sizes, both
    shrink to fit; below 360 pt of pane height only the top slot shows (amended in G2-1,
    owner 2026-10-10). View ▸ Waveform becomes **View ▸ Scopes** (⌃⌘W), the same checkmark
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
- **GR-11 — Wheels: `video.wheels {lift, gamma, gain}`, each a Cartesian colour push `{x, y}`
  and a `master`, applied at step 4c.1 after tone and before the look, in the layer stage and the
  adjustment pass; format 16.** Recorded in G2-2 before its code, from the owner's "All as
  recommended" to G2-2's choices 1–8 (2026-10-10; choice 9 internal).
  - **The keys.** `video.wheels` holds `lift`, `gamma` and `gain`, each `{x, y, master}`; every key
    is written only when not 0 and a neutral wheel (all three 0) is absent, so an unwheeled file's
    text is unchanged (GR-2's rule). Set by `set_video {patch: {wheels: {lift: {x: 0.2, y:
    -0.1}}}}`, an absent key keeping its value; no new op, no op-table row, no new tool (`set_video`
    already takes `patch` as an Object). `x`, `y` and `master` are each −1…1, and the point must
    lie inside the unit circle. Out of range is refused in the rule's own sentence, never clamped
    by a patch: `video.wheels.lift.x must be between -1 and 1, not 1.5` (and `.y`, `.master`), and
    `video.wheels.lift must lie inside the unit circle (x² + y² ≤ 1), not x 0.9, y 0.6`. The circle
    test is `x² + y² ≤ 1 + 1e-9` (`WHEEL_RIM_TOLERANCE`), so a rim point from `cos`/`sin` or
    divided by `hypot` (which can land one ulp over 1) is never refused; the sentence keeps `≤ 1`.
    An action's end is clamped: NaN to 0, master to ±1, a point outside the circle divided by its
    `hypot` onto the rim (which always passes the test).
  - **The puck is Cartesian**, not hue-and-amount, so an action from neutral to a push moves in a
    straight line through the centre (§5.4 lerps numbers). Its angle is the hue on the HSV ramp
    the split tone already uses (0° red, 120° green, 240° blue: `lookHueChroma`, a fully saturated
    hue less its own Rec. 709 luma), and its distance is the strength.
  - **Step 4c.1**, once per pixel, after tone (4c) and before the look (4d): exposure and white
    balance are what a wheel refines, and a look grades the corrected colour (amends GR-7's order).
    Per channel c, on encoded values: `o_c = master + k · hypot(x, y) · chroma(h)_c` for each
    wheel, h = atan2(y, x) in degrees normalised to [0, 360); then **lift** `v += o_lift · s_l ·
    (1 − v)` (pivots at white), then **gain** `v *= 1 + o_gain · s_g` (pivots at black), then
    **gamma** `v = max(v, 0)^(2^(−o_gamma · s_γ))` (holds both ends). This is the usual
    lift/gamma/gain form, lift then gain then the power; it is not cited as ASC CDL order (the
    CDL is slope, offset, power).
  - **Strengths** (owner choice 6, Reelcut's own first numbers, tuned later by amending this
    entry, as GR-2's): full push k = 1 at the rim; lift s_l = 0.25 (master +1 lifts black to
    25 %); gain s_g = 0.5 (+1 = white ×1.5, −1 = ×0.5); gamma s_γ = 1 (+1 = exponent ½: mid-grey
    0.5 → 0.71).
  - **Luma.** A push is luma-neutral on a NEUTRAL (grey) pixel: exactly for lift and gain, and for
    gamma within 2 levels of 255 at the rim (the power's curvature: 1.70 levels worst on mid-grey,
    computed in Python). It is not luma-neutral in general: a saturated pixel's Y′ moves (pure red
    pushed toward red at the rim by gain rises about 21 levels), because chroma's zero luma is
    weighted by the pixel's own channels.
  - **Uniforms** (amends GR-2's "116 floats" as GR-2 itself grew the block): `LayerUniforms` gains
    a group of twelve — the nine in model order (lift, gamma, gain, each x, y, master), then
    `wheelsEnabled`, `curvesEnabled` (reserved for G2-3, unread until then) and one reserved —
    116 → 128 floats, 464 → 512 bytes. `wheelsEnabled` is 1 exactly when any of the nine is not
    0 and joins the effects block's gate sum, so an unwheeled layer never enters 4c.1 and renders
    byte-identical. The shader maps the puck to RGB (one implementation, beside the split tone that
    shares `chroma`).
  - **Extends GR-4**: `ungraded` writes all nine neutral on every layer. **Extends GR-6**: an
    adjustment clip's Color sub-tab gains Wheels, and the adjustment pass runs 4c.1 where the layer
    stage does. **Extends GR-7**: the order becomes Color's four, Light, the wheels, the look, the
    point filters; a look stays Color, Light and split tone (the bake is unchanged), and wheels are
    the clip's own. The recipe writes all nine always (`"wheels"` between `color` and `look`), so
    Swift's lenient decoder never defaults a missing key silently.
  - **The Wheels section** (owner choices 1–8), on the Color sub-tab after Color and before Look
    (Adjustment · Light · Color · Wheels · Look; Qualifier and Curves join later), closed until
    opened, summary "neutral" or "adjusted", Reset zeroes all nine (undo "Wheels"). (1) One row,
    three columns — Lift · Gamma · Gain — each a title, a square-framed disc, a master strip and a
    master field. At the default 304 pt pane a row is 268 pt (244 at the 280 pt minimum); less
    the 14 pt mark gutter, a disc is the column less 4 pt: about 78 pt by default, 70 at the
    narrowest (measured in G2-2's screen 05f), capped at 112 at 440. (2) The disc: a 5 pt fully saturated hue ring at the rim;
    inside, the hue field at 35 % saturation fading to the well colour at the centre; a 1 pt
    crosshair; a 1 pt square frame; a 7 × 7 square puck (`DS.textStrong`, a 1 pt contrasting
    border). The disc is **rotated so each hue sits where the vectorscope draws it** (red at 103°
    counter-clockwise from 3 o'clock; every 75 % target within 12°), so dragging toward a target
    moves the trace toward it; the MCP x/y axes are not rotated (red is +x). (3) The puck: a press
    anywhere in the disc, then the puck moves by the pointer's delta (no jump); one disc radius of
    travel is the full push; **⌥ held moves at a tenth** (a convention new to Reelcut, for the
    wheels only); clamped to the rim, sliding along it (the clamped point is `(x, y) / hypot(x,
    y)`); no centre detent; a double-click resets the colour (x, y) only, one undo step named
    after the wheel. (4) The master strip: the slider's look (3 pt rail, 7 × 11 block knob, accent
    fill from the left end as Light's ±1 rows do); a press off the knob jumps like every inspector
    slider, one on the knob grabs it where it stands (no write); ⌥ held drags relative at a tenth;
    a double-click resets master to 0, one undo step on the knob — off it the first click's jump is
    a step of its own, so one Undo after that reset lands on the jumped value (G2-2's review,
    accepted). Its field: 2 decimals, no unit, −1…1. (5) **The push has no typed field** — the
    first inspector control without one, deliberately (two numbers per puck do not fit three
    across); it is exact through MCP. A hover tooltip on the disc reads "Hue 34° · 0.42" (or
    "Neutral"). (7) With an action selected that keys `video.wheels`: puck and knob in action ink,
    a hollow 7 × 7 square at the action's start value, a coral marker at the playhead's value when
    it differs (the slider's rule); one row mark and one mixed badge for the whole row (CI-7, CI-9
    per group key). (8) Undo names "Lift", "Gamma" and "Gain" (a drag is one step, the live trio);
    no menu item, no shortcut. A puck write sends only that wheel's `x, y`, a strip or field only
    its `master`, to every selected clip.
  - **Format 16**: the keys are optional, with no migration step; the bump stops an older build
    dropping them on save. A file numbered 1–15 (and 1015) opens and is stamped 16; 17 and above
    are newer.
  - **Not:** no Offset wheel (choice 7); no linear-light wheels (encoded values, tier 3 #256); no
    ⌥ fine-drag on any other slider.
  - Risk accepted: the strengths are first numbers, judged by GRD-12 on real footage, and the
    push moves a saturated pixel's luma.
- **GR-14 — Tier 2's working arrangement: each phase merged into main alone, main's format
  numbers, no verdict phase.** Recorded with GR-11 in G2-2, from the tier-2 brief's choices 8b
  and 9 (owner, 2026-10-10). Each phase is worked in `~/devel/reelcut-grading` on `grading-2`,
  gated, then merged into main before the next begins. Each takes main's next format number when
  its code is written (16 wheels, 17 curves, 18 qualifiers) and renumbers before its merge if
  main moved first. There is no experiment verdict or trial phase: grading is kept (GR-1), and
  the owner's feedback waits for real use.
