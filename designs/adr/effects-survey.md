# Effects survey: transitions, effects and filters after Concat

- **Status:** Survey, 2026-09-15. E1 and E2 were built by road map 5
  (`archive/roadmap-5.md`), which overrides this survey wherever
  the two disagree. **E3–E9 were DEFERRED by the user the same day**: "we'll
  eventually add color grading and LUT import, but not now". Nothing from
  E3–E9 is in the tree.
- **Original:** `archive/effects-survey.md` (1629 lines) is the full
  record. "orig §x" below refers to it.
- **Spec decisions:** R5-1 is this survey's D1 (effects are closed
  vocabularies, never a runtime). R5-2..R5-5 and E2-27 came from road map 5
  and cover E1/E2. The survey's D2–D7 are **proposals only**; none is in
  spec §11. A phase that takes one up records it there before writing code.

## Licensing: read this first

**Concat (`~/devel/Concat`) is AGPL-3.0-or-later. Its behaviour was studied,
and none of its code, shaders, chains or colour tables may be carried over.**
The survey read it only through four read-only scout reports written in the
scouts' own words. Nothing may be carried over at design time or at build
time: no Rust, no `effect.wgsl`, no `effect.toml` or FFmpeg filter chain, no
colour matrix, curve table, LUT data or other asset. A builder must not open
those files to "match" a look. Every number a phase needs is Frame Job's own,
chosen against Frame Job's own fixtures. When a phase says "Concat's", it means
the feature a person sees, never how Concat implements it. Concat's
downloaded "Person" matting model (Robust Video Matting) is GPL-3.0, which is
one more reason E9 uses Vision and ships no model. (orig §9, preamble)

## Context

The user asked for a review of Concat's transitions, effects and filters, a
comparison with Frame Job, and designs for the equivalents. Concat is a
Rust/wgpu editor with a Slint UI, sold as a free CapCut replacement.

What the comparison found (orig §2): **Transitions:** Frame Job was already
ahead. Its ten kinds look the same in preview and export, while three of
Concat's seven render as a cut or a dissolve in Concat's own preview;
**Whole families:** Frame Job had obscure regions, spotlight, shadow,
reflection, blend modes, text reveals, and a keyer with a picker and spill.
Concat has none of them; **Breadth:** Concat was ahead, with a 13-slider
Adjust panel, 39 named looks, 27 stylised effects, masks, flip, adjustment
layers, In/Out/Combo clip animations, 20 voice filters and ML background
removal.

The survey designed nine phases, E1–E9, to close the breadth gap, and ran
two spikes (E0) on the Apple frameworks behind the two heaviest phases.

## Decisions

**D1 — No effect runtime; every effect is a closed, versioned vocabulary**
(spec §11 R5-1). Each effect is an enum variant or a struct with ranges. It
is range-checked by `props_check.rs`, carried by the recipe, mirrored by the
MCP catalog and drawn by the one compositor. There is no package format, no
user shader and no expression language.

Rejected: Concat's package runtime, which shows what one costs: every effect
is rendered twice, once by FFmpeg, and the two disagree; fixtures pin filter
strings, not pictures; the UI cannot reach the parameters.

Spec §1's plugin non-goal stands, amended only by road map 10's G-1.
(orig §0, §4)

**E1 and E2 were built from road map 5, not from this text.** Road map 5 §9
lists where it departs from the survey. Three departures matter when reading
the archive: E2's toll moved the SHAPE group to `model_shape.rs`. There is
no `model_picture.rs`; `ColorAdjust` and `Filter` still live in
`model_props.rs`; shake is unseeded (R5-5); `add_transition` gained `ripple`
(R5-3, amended).

**Proposed D2 — re-draw "color grading beyond per-clip controls" around a
grading SUITE.** IN, each as a clip property: tone (E3), looks (E5), adjustment clips (E6)
and LUTs (E7); still OUT: colour wheels, curves, HSL qualifiers, scopes,
node graphs, log or HDR workflows, and linear light, which is a
whole-pipeline decision (spec §7.5).

An adjustment clip is a clip, not a grading node. Spec §1 is unchanged.
(orig §4)

**Proposed D3 — LUTs are IN, as media, through E7 only.** A `.cube` file
becomes a `Media` of kind `lut`, so relink, consolidate and usage come from
paths that already exist. The LUT is applied to ENCODED sRGB, which suits a
display-referred Rec.709 LUT. A log or scene-referred LUT will look wrong,
and that is a stated limit. D3 reverses road map 2 §4's "LUTs" exclusion;
the user has since called LUTs deferred, not a non-goal (#122). Declining E7 leaves D2 intact. (orig §4)

**Proposed D4 — voice effects are rendered offline, not live.** The live
tap (`AudioTap.swift`, one PreEffects tap per track) cannot host a pitch
shifter, and a reverb tail outlives its clip. So a voiced clip plays a
cached render, the way a reversed clip plays `cache/reversed/`. D4 also
notes that spec §1's "audio beyond volume/fade/duck" was already overtaken
by M3's compressor, pan and noise reduction. The line would read "a mixing
desk or an audio plugin host". (orig §4)

**Proposed D5 — Remove Background uses Vision and ships no model.** Video uses `VNGeneratePersonSegmentationRequest`; pictures use
`VNGenerateForegroundInstanceMaskRequest`; masks are cached per media, under
the stamp, marker and ledger discipline of `thumbs/` and `peaks/`.

This narrows road map 2's "ML" exclusion to "a model the app ships or
downloads". Rejected: ONNX Runtime, and downloaded or GPL weights.
(orig §4, §1g)

**Proposed D6 — every time-varying effect is a pure function of (clip,
frame).** Grain, scanlines and shake use a clip-local frame index and a
seed taken from the clip id. They never read the wall clock or a previous
frame. Echo, trails and true motion blur stay out. R5-5 already made motion
unseeded; a seed arrives only with E4's clock. (orig §4)

**Proposed D7 — nothing moves content out from under an obscure region.** A
stage that moves pixels either carries the region with it, or hides by BOTH
positions.
Carrying the region: flip transforms the quad, not the sampling coordinate;
Hiding by both positions: a fragment is hidden if its own position or its
colour's source position lies in the region. This covers E4's remaps and
mirror.

The review caught the draft breaking this rule twice. (orig §4, §10)

**Overturned by measurement** (orig §5, §10): E8's whole-media cache became
a per-clip WINDOW cache; E9's foreground subject on video was dropped
because it flickers; E9 gained a "no subject" rule, without which a
screencast would be erased.

## The deferred candidates, E3–E9: what each proposed

The original's schema versions (v9–v15) and op counts are stale. The format
is at 10, so the first deferred phase is v11.

Still true of the tree: `LayerUniforms` is 104 floats / 416 bytes with an
empty tail; `Compositor.metal` is 1548 lines in one file; a layer samples
one texture; `MAX_FILTERS` is 4, and `FilterKind` has 7 kinds.

Dependencies (orig §7): E3 needs the picture-vocabulary move and the
shader-header toll; E4 and E5 need E3's headers; E6, E7 and E9 need E5's
texture plumbing; E8 is independent of the picture phases.

Every version bump moves the "one past current" fixtures and owes
`format.rs` a paragraph.

### E3 — Tone, flip and a mask (orig §6 E3)

No new op, only new keys on `set_video`: **Tone:** `video.color` gains
`exposure` (±3 EV); `temperature`, `tint`, `highlights`, `shadows`,
`whites`, `blacks` and `vibrance` (−1…1); and `fade` (0…1). Saturation −1 is
grey; do not copy Concat's inverted −100; **Flip:** `flip_x` and `flip_y`;
**Mask:** `video.mask` is `{shape: rect|ellipse|linear, x, y, width, height,
angle, feather, invert}` in the region frame, one per layer. It gets its own
`MaskShape` enum, because widening `SpotShape` would leak `linear` into
spotlight and obscure.

Metal: Tone runs ONCE per pixel at a new step 4c, after obscure and before
the point filters. It stays out of `gradeSample`, which runs on every blur
tap; the fast-path gate sums non-negative terms, but tone fields are signed.
Swift therefore writes `toneEnabled` and `maskEnabled` flags; flip is a quad
transform, applied BEFORE `rotate2` and about the CROPPED centre, so obscure
regions follow the picture (D7). The reflection needs its own flip arm; the
mask multiplies coverage at step 7c, so shadow and reflection follow.
`partnerBox` refuses masked partners; uniforms: two groups of 12 floats.

Four Swift canvas mappings must learn flip: `CanvasLayerBox.sourcePoint` /
`canvasPoint`; the crop handles; the line and arrow endpoint handles;
`RecipeLayer.videoProps` / `uncropped`, which silently drop unknown fields.

In the core, `edit_zoom.rs`'s pan direction reverses on a flipped clip.

**Toll first:** split `Compositor.metal` into `#include`d HEADERS, not
sibling `.metal` files, because two proof probes compile the file alone. The
same toll: makes the probes cache on every Shaders file; gives `.h` files
build phase `none` in `project.yml`; re-measures the `kGatherFilters`
register counts.

UI: Color and Light sections, Clip ▸ Flip, and a Mask section with Draw on
Canvas.

### E4 — Thirteen filter kinds and a clock (orig §6 E4)

`FilterKind` appends `posterize`, `threshold`, `solarize`, `emboss`,
`edges`, `glow`, `directional_blur`, `fisheye`, `mirror`,
`chromatic_aberration`, `grain`, `scanlines` and `vhs`. `Filter` gains
`angle`. The recipe layer gains `frame` and `seed`; the seed hashes the clip
id (or the nest clip plus the inner id) and stays below 2²⁴.

How each kind is drawn: Point kinds go at step 5, `fisheye` at step 2;
`mirror` is a second sample mixed by amount, not a remap; every gather reads
the RAW texture and must join `needsGather`; a gather left out compiles out
silently; `blur` and `directional_blur` on the same layer are refused by
name; grain hashes on the CANVAS pixel, so it is screen grain; D7's
either-position rule covers remaps and mirror.

First step: measure each gather against the 8 ms budget (the fallback is
one function constant per gather class), and check whether the spotlight
lens already leaks obscured content.

### E5 — Looks (orig §6 E5)

`video.look` is `{kind, amount}`, a closed set of about 24 generic names in
six groups, tuned by eye. The core names the look and does nothing else.

A new `Looks.swift` builds each look from Frame Job's own primitives and bakes
it into a 33³ `rgba16Float` 3D texture held in an LRU. The primitives: white
balance; split tone; film curve; matte; saturation and vibrance; hue bands
with a skin guard.

Rendering: A look is colour only. Halation, grain and vignette are filters;
`texture(1)` needs a 2³ identity placeholder at EVERY layer-fragment site;
the look is mixed at step 4d; gallery thumbnails come from the real
compositor, never a second renderer.

First step: pass a two-texel gradient through the linear-filtered 3D
texture.

### E6 — Adjustment clips (orig §6 E6)

A new op, `add_adjustment_clip {track, at, duration?=5 s}`, makes a
`Source::Adjustment` clip; `add_clip` cannot, because it needs a media id.
The clip's colour, look, point and clocked filters, mask and opacity (its
strength) apply to everything composited beneath it.

Refused: gather and remap filters, and a non-normal blend (in `check_group`,
and stripped by `clamp_video`); any nest (in `validate`, not
`refused_inside`); a mixed overlap with a picture clip.

Every `Source` match must be classified. A new `framejob_adjust_fragment`
reads `[[color(0)]]` with blending off and runs colour stages factored out
of `layerColorPremultiplied`. The timeline bar gets no button: at the
900 pt minimum width there is no room for one.

### E7 — LUT import (orig §6 E7; D3)

`Media.kind` gains `lut`, and `LookKind::Lut` names `look.media`. A missing
file draws the clip ungraded, without a slate.

This is the first media reference outside `source`, so each of these must
learn about it: `uses_media` and `remove_media` (a removal clears the
looks); `validate`; `paste` renumbering and `paste_attributes`; every
`MediaKind` match; action interpolation, where `look.media` switches and
never lerps.

A new `CubeLUT.swift` reads 3D `.cube` files of size 2–65 (1D is refused)
into E5's texture. `MediaImporter` accepts `.cube` without an `AVURLAsset`,
and Consolidate copies it.

### E8 — Voice effects (orig §6 E8, §5a; D4)

`audio.voice` is `{kind, amount, pitch −12…12}`, one per clip, with 16
kinds: voice: pitch, high, deep, robot; tone: bass, treble, bright,
telephone, radio; character: lofi, distorted; space: echo, room, hall,
plate, cathedral.

Each kind is a FIXED chain of Apple units: TimePitch, EQ, Distortion, Delay
and Reverb. A new `VoiceRenderer.swift` renders the clip's source WINDOW to
`cache/voiced/<digest>.caf`. The digest covers stamp, reversed, window,
kind, amount, pitch and a chain version.

The render contract, every line of it measured: 48 kHz STEREO, because
reverb given mono aborts the process; an `AVAudioPlayerNode`; schedule →
`start()` → `play()`; fixed 4,096-frame calls; presets through
`auAudioUnit.currentPreset`; every parameter set and clamped; a unit removed
rather than set to wet 0; no TimePitch at 0 semitones; float CAF; per-kind
makeup gain.

Tails are cut at the clip end. `CompositionBuilder` substitutes the file per
clip, and plays DRY while a render is pending.

### E9 — Remove Background (orig §6 E9, §5b; D5)

`video.cutout` is `{subject: person|foreground, feather}`.

`person` uses `VNGeneratePersonSegmentationRequest` at `.balanced`, with a
FRESH request per frame. `.fast` is stateful; `.accurate` runs at 1.7×
realtime and needs 1.7 GiB per minute; `foreground` applies to images and
stills only.

A new `MediaImporter+Masks.swift` computes 10 masks per second of source,
only for the windows that clips show. They are written as 8-bit PNGs under
`cache/masks/<media>-<subject>/`, made from the CODED buffer. The compute
device is pinned in the marker, and proofs compare against the cached masks,
never a recomputation.

**"No subject" rule, per CLIP WINDOW:** if no mask has at least 0.5 % of its
pixels above 127, the clip draws UNCUT.

In the compositor: the core emits `source_t`; Swift binds the nearest mask
as `texture(2)`, sampled through `orientedUV`; the mask multiplies coverage
at step 7; a frame whose mask is pending draws uncut.

## What it built: where it lives now

- **`tools/proof/effects_spike/`:** the E0 instruments, `fx_*.swift` for
  voice and `vision_*.swift` for segmentation. The README has the build
  lines and fixtures.
- **E1 (road map 5):** `core/src/edit_transition.rs`,
  `core/src/audio_crossfade.rs`, `app/Sources/VideoPane+Transition.swift`,
  `AgentCatalog+Transitions.swift`, `AgentServer+Transitions.swift`,
  `tools/proof/e1_proof.py` and `e1_chrome.py`.
- **E2 (road map 5):** `core/src/model_motion.rs`, `core/src/motion.rs`,
  `core/src/edit_split.rs` (the split rule for motion and
  `text.animation`), `app/Sources/VideoPane+Motion.swift`,
  `MotionProps.swift`, `EditorViewController+Motion.swift`,
  `tools/proof/e2_proof.py` and `e2_chrome.py`.
- **E3–E9:** nothing exists. `flip_x`, `exposure`, `LookKind`, `VoiceKind`,
  `MaskShape`, `cutout` and `.cube` appear nowhere in `core/src` or
  `app/Sources`.

## Known limits

**Architecture a deferred phase will meet** (orig §3, re-checked
2026-09-26): `LayerUniforms` has an empty tail, and `phase8_chrome.py:3259`
asserts 416; a layer samples one texture, and there is no time or seed
uniform; output is confined to the layer's quad, so glow and aberration
cannot bleed past it; there is no previous frame; there is one PreEffects
tap per track; file sizes have moved since orig §3; measure with `wc -l` and read
the file-history ADRs' "Named next cuts" before paying a toll.

**Wipes are measured in each layer's own box**, so a different-size pair
does not meet at one edge (spec §7.5). A canvas-space wipe was withdrawn
because it broke the common same-size pair, nested wipes, and vertical wipes
over a reflection. The right measure, the pair's union box, was left for
later.

**E0 spike numbers — do not re-measure them blind.**

Voice (§5a): Offline rendering works synchronously. It is byte-identical
across engines, processes and concurrent runs, but only at a fixed call
size; a window render is not a slice of a whole-file render: TimePitch
differs by up to +0.34 dBFS; a 10 s window re-renders in 50–270 ms; reverb
tails run 11 ms (smallRoom) to 5.79 s (cathedral); no preset band-limits,
and no preset makes a robot; distortion presets add +0.9 to +19 dB RMS.

Vision (§5b): Calls are synchronous and need no TCC grant; person masks are
always 4:3: fast 256×192, balanced 512×384, accurate 2016×1512; balanced
runs at 4.2–5.5× realtime at 10 masks/s, about 16 MB of PNG per minute;
output is byte-identical on one device, but GPU and ANE differ by up to 25
levels; person coverage is 0.00 % on UI, text and cards; foreground on video
flips up to 57 % of pixels between masks 0.1 s apart; person segmentation
misses backlit, from-behind and small figures.

Not measured: audible quality; multi-track or variable-rate `.mov` audio
through `AVAudioFile`; an `AVComposition` playing a cached CAF; the
first-ever Neural Engine compile; masks on real camera footage, or across
machines and OS versions.

The spike's "macOS 15 target" row is moot, because the minimum is macOS 26
(W-8).

**Not designed, and why** (orig §8):

| Item | Why not |
|---|---|
| A package runtime, user WGSL | D1 |
| Echo, trails, motion blur | No previous frame (D6) |
| Speed-curve presets | Speed is not an action target; the natural next item if asked |
| Bézier eases | Grading-suite UI |
| Non-uniform stretch | Unasked |
| SAM brush, subject tracking | Would need a shipped model (D5) |
| De-ess, "Enhance Voice" | No Apple unit de-esses |
| Face blur, scene and black-frame detection | A Vision phase of its own |
| Text style presets | Not effects |

**Not to copy from Concat** (orig §1e, §1h): fades that cut in preview;
wipes that dissolve; parameters the UI cannot reach; thumbnails from a
second renderer; one grain pattern for every clip; pixel parameters that
change with preview quality; saturation −100 inverting chroma.

## Open items

- **E3–E9** (tone/flip/mask, filters and clock, looks, adjustment clips, LUT
  import, voice effects, background removal): DEFERRED by the user. Tracked
  in #118–#124, one per phase.
- **D2–D7 are unrecorded proposals.** Recording them moves spec §1's "color
  grading beyond per-clip controls" and "audio beyond volume/fade/duck". The
  user now calls LUTs deferred (E7), not a non-goal. The audio line is
  already stale against M3. Tracked in #118–#124.
- **Doc drift the survey's scout found.** Fixed by 2026-09-26: none of the
  four strings is left in the spec or the code.
  - spec §4.3 "Core Image behind them";
  - spec §7.5 "small offscreen texture";
  - the `ShadowUniforms` comment "8 floats = 32 bytes";
  - `RecipeClipRect`'s "always nil today".
- **The wipe union-box measure** for a different-size pair. Tracked in #110.
- **Speed-curve presets:** tracked in #111 (speed ramps).

## Where to look in the original

| Section | What it holds |
|---|---|
| Preamble, §0 | Status, the licence warning, the one-paragraph decision |
| §1 | Concat read at `042688f`: transitions (1a), In/Out/Combo (1b), effect runtime (1c), the 66 packages (1d), Adjust (1e), audio (1f), vision (1g), promises it does not deliver (1h) |
| §2 | The comparison tables, with a verdict per row |
| §3 | Frame Job's architecture limits (file:line as of 2026-09-15) and doc drift |
| §4 | D1–D7 in full |
| §5 | The E0 spikes: voice (5a, q1–q7), vision (5b, q1–q7), build-time questions per phase (5c) |
| §6 | E1–E9 in full: schema, core, Metal, UI, MCP, proof rows and mutants, limits. E1 and E2 are superseded by road map 5 |
| §7 | Order, dependencies, cost, version-bump costs |
| §8 | Found in Concat, not designed, and why |
| §9 | Licence and provenance |
| §10 | The review: 58 findings, and the design changes they forced |
