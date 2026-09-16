# Reelcut — transitions, effects and filters, after Concat: the survey

**Status: a SURVEY, and two thirds of it DEFERRED.** Road map 5
(`designs/reelcut-roadmap-5.md`) builds E1 and E2 from this document and
plans them in build detail there; where the two disagree, road map 5 is the
later word. **E3–E9 are deferred by the user's decision of 2026-09-15**:
colour grading and LUT import (E3, E5–E7) are expected eventually, "but not
now", and E4, E8 and E9 wait with them. Their designs, the two spikes' measured
answers (§5a, §5b) and the review's findings are kept here so a later road
map starts from them rather than from scratch — none of it is planned, and
D2–D7 in §4 are proposals, not recorded decisions.

On 2026-09-15 the user asked for a review
of the transitions, effects and filters in `~/devel/Concat` — another video
editor, a Rust/wgpu engine under a Slint UI, sold as "the truly free and
open-source CapCut replacement" — a comparison against what Reelcut has, and
equivalent features designed. Four read-only scouts read Concat's
transitions and animations, its effect runtime and 66 picture packages, its
20 audio packages and its vision crate, and Reelcut's own inventory and the
limits a new effect runs into. Two spikes then measured the Apple frameworks
the two heaviest phases lean on, before any plan leaned on them (§5). Nothing
in this document is in the tree except those spikes' instruments
(`tools/proof/effects_spike/`).

**Concat is AGPL-3.0.** Everything below was taken from reading its
BEHAVIOUR. No shader, Rust, filter chain, colour-matrix number, curve table
or LUT data is carried over, and none may be at build time: the numbers each
phase needs are Reelcut's own, chosen against Reelcut's own fixtures. Two of
Concat's downloaded models are also licence hazards of their own (its
"Person" matting model is GPL-3.0); nothing here ships a model. §9 says it
again for whoever builds a phase.

The short version of the comparison: **Reelcut already out-renders Concat
on transitions** — ten kinds that look the same in preview and export,
where three of Concat's seven render as a hard cut or as a dissolve in its
own preview — and has whole families Concat lacks (obscure regions,
spotlight, shadow, reflection, eight blend modes, text reveal animations, a
keyer with a picker and spill). **Concat is ahead on breadth**: a
thirteen-slider Adjust panel, 39 named colour looks, 27 stylised effects,
masks, flip, adjustment layers, CapCut-style In/Out/Combo clip animations,
twenty voice filters and ML background removal. This road map closes that
breadth gap in nine phases, each sized to Reelcut's rules — one Metal
pipeline that preview, export and `render_frame` share, Rust deciding and
Swift doing, a recorded decision wherever a spec §1 non-goal is touched, and
a byte-level proof per claim.

---

## 0. The decision, in one paragraph

**Close the breadth gap as PER-CLIP PROPERTIES rendered by the one
compositor, never as a plugin runtime.** Concat's effect system is a
data-driven package format with user-installable WGSL; spec §1's "a plugin
system" non-goal stands, and Reelcut instead grows closed, versioned
vocabularies the core range-checks and the MCP catalog mirrors. In order of
value per cost: transitions learn direction, easing, an audio crossfade and
a way to be ADDED at a hard cut (E1); clips get In / Out / During motion
presets computed by the core (E2); colour controls gain Concat's tone
sliders, and layers gain flip and a mask (E3); the filter vocabulary grows
thirteen kinds and the shader gets a deterministic clock (E4); a closed set
of named LOOKS renders through a 3D LUT that Swift bakes (E5); an
ADJUSTMENT clip applies colour work to everything beneath it (E6); `.cube`
import rides E5's texture (E7, its own decision); voice effects render
offline through Apple's audio units into a cache keyed by each clip's
source window (E8); and Remove Background runs Vision's person segmentation
into a per-media mask cache (E9). Two §1 lines move
and are recorded before code (§4): "color grading beyond per-clip controls"
is re-drawn around a GRADING SUITE rather than around looks, and road map
2's "LUTs" exclusion is reversed by E7 alone. Everything else Concat has
that this document does not build is listed in §8 with the reason.

---

## 1. What Concat has — read, not run

All paths are under `~/devel/Concat/engine/crates/` at HEAD `042688f`.
Nothing was run; every parity claim is from reading, and the scouts named
tests where tests pin a behaviour.

### 1a. Transitions — seven, hard-coded

`Clip.transition_in: Option<{id: String, duration}>` on the INCOMING clip
(`concat-project/src/model.rs:738-750`), resolved at render time by one
string match (`concat-export/src/lib.rs:320-539`). The manifest has a
`transition` kind (`concat-effects/src/manifest.rs:96`) but no package uses
it and the shader prelude binds one texture and no progress, so there is
nothing to write one against.

| Kind | What it does | Preview | Export |
|---|---|---|---|
| `cross-fade` | incoming opacity 0→1, linear, over an overlap taken ENTIRELY from the incoming clip's head handle | real | real |
| `fade-black` / `fade-white` | FFmpeg fade out on A, in on B, half the duration each | **hard cut** | real |
| `push` | right-to-left only; both offset a frame width, CSS ease-in-out | real | real |
| `zoom` | dissolve + B 1.25→1 ease-out, A 1→1.4 ease-in | real | real |
| `wipe-left` / `wipe-right` | hard-edged alpha mask on B's decoded picture | **dissolve** | real |

Applied by clicking a Library card with ONE clip selected (it becomes the
clip the transition leads into): fixed 0.5 s, no inspector, no duration or
remove control except undo. The incoming clip's audio fades in linearly over
the overlap in export only; preview plays no transition sound. Push and zoom
fall back to a dissolve when either clip has keys on that property.

### 1b. Clip animations — CapCut's In / Out / Combo

`Clip.animation_in`, `animation_out`, `animation_combo:
Option<{preset, duration}>` (`concat-project/src/animation.rs`), re-expanded
into relative keys for the clip's current length every time:

- **In** (eased out), 0.1 s…min(10 s, half the clip), default 0.5 s: Fade,
  Zoom In (0.5→1 + fade), Zoom Out (1.6→1 + fade), Slide Up/Down/Left/Right
  (0.6 of the frame), Spin (−180°, 0.3→1, fade).
- **Out** (eased in): the same eight, run backwards.
- **Combo**, always the whole clip: Pulse (one 1.08 beat), Shake (±0.02 of
  the frame width, nine swings PER CLIP — so a long clip shakes slowly),
  Spin (one turn), Bounce (two hops), Drift (a 1→1.12 push-in).

Values are relative — scale and opacity multiply, offsets and rotation add
— but slots keying one property are MERGED into one track rather than
composed (In Zoom + Combo Pulse loses the zoom), and a user key on a
property DROPS that property's preset entirely.

Around them: keyframes on six clip properties (scale, x, y, rotation,
opacity, volume) with cubic-Bézier eases no shipped UI can edit; six
speed-curve presets (Montage, Hero, Bullet, Jump Cut, Flash In/Out); nine
static text presets; no text animation.

### 1c. The effect runtime

A package is `effect.toml` (`kind` effect | filter | audio | transition |
generator, a category, typed parameters with ranges) plus a WGSL body
`effect(uv) -> vec4` and an FFmpeg-chain fallback, compiled in or loaded
from a user folder (`concat-effects/src/{manifest,catalogue,shader}.rs`). A
prelude hands the shader one texture, the layer size, TIMELINE seconds and
an intensity, plus a shared grading library (white balance, split tone,
film curve, matte, hue bands, a skin mask, halation, Sobel edges, a hashed
grain). Effects attach per clip as an ordered, unlimited stack, and run in
clip-local space at the fitted decode resolution BEFORE the transform — so
every pixel-valued parameter changes with export size and preview quality.
Colour work is in encoded 8-bit, as Reelcut's is.

**Filters are adjustment layers.** A Filters-library card becomes a
`ClipKind::Layer` clip that treats the composite of every lower track;
its strength is its opacity, with ramp-in and ramp-out. That clip's
inspector shows only Strength and Ramps, so a look's own sliders (warmth,
grain, "Protect skin") are unreachable from the desktop UI. A `.cube` LUT
import writes a user filter package, quantised to 8 bits per channel.

### 1d. The 66 picture packages

**Effects (27).** Basic: Black & White, Sepia, Invert, Sharpen, Hue Shift,
Threshold. Blur: Gaussian, Box, "Motion" (a single-frame HORIZONTAL blur).
Stylize: Vignette, Film Grain, Glow, Posterize, Emboss, Sketch (FFmpeg
only), Solarize, Scanlines. Distort: Pixelate, Mirror (left half onto
right), Fisheye, Shake (sine offset, transparent edges), Chromatic
Aberration (horizontal). Cutout: Green Screen, Blue Screen (fixed key
colour, no spill, no picker). Mask: Circle, Rectangle, Linear (vertical
edge only) — each MULTIPLIES the layer's alpha; there is no mask that limits
another effect.

**Filters (39)**, all colour looks, most colour-only (a 3D LUT could hold
them), some adding halation, a skin-only soften, grain, a vignette or a
light leak. Everyday: Fresh, Vivid, Clean, Soft Light, Golden Hour,
Cloudless Sky, Lagoon, Milk, Ivory, Umber. Portrait: Peach, Fair. Color:
Warm, Cool, Vibrance, Contrast Pop. Cinematic: Teal & Orange, Moody, Cool
Blue, Night, Film, Daydream, Sage, Midnight, "Rain" (a grade with bloom — no
rain). Retro: Vintage, Polaroid, Bronze, Mono, VHS, Digicam, Falling Dust.
Stylised: Pink Fuzz, Neon, Marquee, Matcha, Spooky, Retro Cartoon.

### 1e. Adjust

Thirteen sliders in three groups: **Color** — temperature (2000–11000 K),
tint, saturation; **Lightness** — exposure (±3 EV), brightness, contrast,
highlights, shadows, whites, blacks; **Effects** — sharpen, fade, vignette.
No HSL, curves or vibrance. Saturation at −100 inverts chroma (grey is at
−50) — a defect not to copy.

### 1f. Audio — twenty FFmpeg chains, rendered ahead

No DSP code of its own: each "voice filter" is a libavfilter chain template,
and preview renders each clip's filtered span to a cached WAV before playing
it. Voice: Pitch (±12 st, a resample then a time-stretch back, formants
move), Sweet, Deep, Chipmunk, Robot (phaser + flanger). Tone: Bass, Treble,
Bright (shelves), Telephone and Radio (band-passes; Radio's "noise" is a
bit-crush), Lo-fi, Distorted. Space: Echo (one tap), Room, Hall, Plate,
Cathedral (each FOUR discrete echo taps — no reverb network). Clean:
Normalize Loudness (per clip), Noise Reduction (FFT denoiser), Enhance Voice
(high-pass, denoise, de-ess, compressor, limiter). Per clip, stackable, not
keyframable; filter state restarts every 0.1 s on a speed-curved clip.

### 1g. Vision

**Remove Background ships**: three ONNX models (a 462 KB selfie model
compiled in, a 15 MB GPL person matting model and a 179 MB object model,
both downloaded, two without a checksum), masks computed at 10 per second of
source and cached per media and subject as 8-bit PNGs, nearest within
250 ms, feathered, multiplied into the decoded frame's alpha on the CPU
before compositing. A SAM-based smart brush refines it and follows the
region through the clip. Face blur, scene detection and black-frame
detection exist only as Python prototypes.

### 1h. What Concat promises and does not deliver

Worth knowing so none of it is copied: fades to colour are cuts and wipes
are dissolves in its preview; transitions have no duration control; a
look's parameters are unreachable; card thumbnails are rendered by the
FFmpeg twin, which differs from the shader for several looks; grain uses
one pattern for every clip at an instant; pixel parameters change with
preview quality; Rain has no rain and Motion Blur no motion; Enhance Voice's
note promises presence EQ its chain lacks; audio keys are stored and
ignored.

---

## 2. The comparison

**Verdict** says what this road map does: *have* (Reelcut already has an
equivalent), *better* (Reelcut's is stronger — no work), a phase (the gap
is designed there), or *out* (§8 says why).

### 2a. Transitions and animation

| Capability | Concat | Reelcut today | Verdict |
|---|---|---|---|
| Cross dissolve, fade to black/white | 3 (fades cut in preview) | 3, same in preview and export | better |
| Push | right-to-left only | four directions | better |
| Slide (incoming over a still outgoing) | — | from the right | better |
| Zoom | eased dissolve + scale | linear dissolve + scale | E1 (curve) |
| Wipe | left, right, hard edge, export only | one direction, soft edge | E1 (four directions) |
| Easing | fixed per kind | linear only | E1 (`curve`) |
| Duration control | none (0.5 s fixed) | inspector + `set_transition_duration` | better |
| Add at a hard cut from handles | yes (incoming head only) | no — the overlap must be dragged, shortening the timeline | E1 (`add_transition`, centred) |
| Audio under the transition | incoming fades in (export only) | none: both play whole, a doubled voice | E1 (crossfade) |
| Clip In / Out / Combo presets | 8 / 8 / 5 | none (actions only; no presets) | E2 |
| Keyframes | 6 props, Bézier | actions over every numeric prop, 4 curves | have |
| Text animation | none | typewriter, word fade, line rise | better |
| Speed-curve presets | 6 | none (speed is not animatable) | out (§8) |

### 2b. Picture

| Capability | Concat | Reelcut today | Verdict |
|---|---|---|---|
| Brightness, contrast, saturation, hue | Adjust (no hue) | `video.color` | have |
| Exposure, temperature, tint, highlights, shadows, whites, blacks, fade, vibrance | Adjust + Vibrance filter | none | E3 |
| Sharpen, vignette | Adjust + effects | filters | have |
| Blur (Gaussian, box) | 2 effects | `blur` filter | have |
| Pixelate, sepia, B&W, invert | effects | filters (`noir`) | have |
| Threshold, posterize, solarize | effects | none | E4 |
| Emboss, sketch/edges, glow | effects | none | E4 |
| Directional ("motion") blur | horizontal only | none | E4 (any angle) |
| Fisheye, mirror, chromatic aberration | effects | none | E4 |
| Film grain, scanlines, VHS | effects + look | none (no clock in the shader) | E4 |
| Shake | effect (picture) + combo (layer) | none | E2 (`during: shake`) |
| Flip horizontal / vertical | clip property | none | E3 |
| Masks (circle, rectangle, linear) | 3 effects, alpha | corner radius, crop only | E3 (`video.mask`, one per layer, any angle) |
| Named colour looks | 39 | none | E5 (a closed set) |
| LUT import | `.cube`, 8-bit | none; a road map 2 non-goal | E7 (own decision) |
| Adjustment layer | the Layer clip | none | E6 |
| Green / blue screen | fixed colour | chroma key, picker, spill | better |
| Background removal (ML) | 3 models + brush | none | E9 (Vision: person for video, foreground for pictures) |
| Blend modes | 6 | 8 | better |
| Obscure regions, spotlight, shadow, reflection, rounded corners, gradients | — | all | better |

### 2c. Sound

| Capability | Concat | Reelcut today | Verdict |
|---|---|---|---|
| Volume, fades, ducking | volume keys, fades | volume, fades, ducking, volume actions | better |
| Loudness normalisation | per clip | on export (BS.1770-4, true peak) + Normalize Clip | better |
| Noise reduction, compressor | FFT denoiser; compressor inside Enhance Voice | both, live in the tap | have |
| Pan, mono, solo, meters | — | all | better |
| Pitch shift, chipmunk, deep | 4 | none | E8 |
| EQ presets (bass, treble, bright, telephone, radio) | 5 | none | E8 |
| Lo-fi, distortion, robot | 3 | none | E8 |
| Echo, room, hall, plate, cathedral | 5 (discrete taps) | none | E8 (real reverb units) |
| De-ess, "enhance voice" | yes | none | out (§8) |

---

## 3. The architecture the gaps run into

From the Reelcut scout, with file:line in the tree as of 2026-09-15. Each
row names the phase that pays it.

| Limit | Where | Paid by |
|---|---|---|
| `Transition` is `{kind}` alone — no duration (the overlap is the duration), direction, curve or audio flag | `core/src/model.rs:396-400` | E1 |
| Progress is linear; the recipe hands Metal `{kind, progress, role, partner}` and nothing is baked into transforms — a new kind is a shader branch plus Swift's exhaustive `TransitionCode` switches | `transition.rs:72-79`, `recipe.rs:319-332`, `Compositor.swift:487-515` | E1 |
| The wipe edge is in each layer's own 0…1 space, so two layers of different size do not meet | `Compositor.metal:1303-1312` | E1 records it; canvas space would break the same-size pair |
| Audio ignores transitions entirely — two overlapping clips play at their own envelopes | `audio.rs` (no reference), `evaluate.rs:155-180` | E1 |
| Actions reach an end state and HOLD it; an "in" preset built from actions would have to rewrite base props, after which inspector edits look dead | `actions.rs:490-505`, `InspectorPane.swift:1426-1437` | E2 (a first-class `motion`, not actions) |
| `LayerUniforms` is 104 floats / 416 bytes with an EMPTY padding tail; a field is appended in groups of four and mirrored field for field; `phase8_chrome.py:3188-3197` asserts 416 | `Compositor.metal:125-318`, `Compositor.swift:270-449` | E3, E4, E5, E9 (each grows it and moves the assertion) |
| `Filter` is `{kind, amount}`; `MAX_FILTERS` = 4 slots; new kinds cost no slot, new FIELDS do | `model_props.rs:196-235` | E4 |
| No time or seed uniform; a layer carries no clip time | `recipe.rs:201-234` | E4 |
| A layer samples ONE texture — no 3D LUT, no mask texture | `Compositor.metal:1336-1339, 1456-1460` | E5 (LUT), E9 (mask) |
| Output is confined to the layer's quad — nothing bleeds past it | `Compositor.metal:417-421` | E4 records it as a limit (glow, aberration) |
| A new neighbour-sampling effect must join `needsGather` or silently renders unfiltered | `CompositorEffects.swift:240-271` | E4 |
| The compositor is stateless per request: no previous frame | `Compositor.swift:176-217, 801-914` | §8 (echo/trails stay out) |
| The live audio tap is ONE PreEffects tap per track; a time-pitch shifter cannot run in it | `AudioTap.swift:30-52` | E8 (offline render instead) |
| Size: `model_props.rs` AT 600; `recipe.rs` 537, `actions.rs` 573, `evaluate.rs` 588, `audio.rs` 587 near; `CompositionBuilder.swift` AT 601; `VideoPane.swift` 1465, `ProjectSnapshot.swift` 2484, `AgentServer+Clips.swift` 1196 over; `Compositor.metal` 1548 | `designs/reelcut-remaining.md` §3 | a toll per phase, §6 |

Doc drift the Reelcut scout found on the way, to fix in the first phase that
touches each file: spec §4.3 says filters have "Core Image behind them"
(`reelcut-design.md:327` — nothing in the app uses Core Image, and §5.2 says
so); spec §4.4 says double-clicking an overlap sets its kind (it renames the
clip, `TimelineView.swift:620-626`); `ShadowUniforms`' comment says 8 floats
/ 32 bytes (`Compositor.metal:1483` — it is 12 / 48); spec §7.5 calls the
shadow's texture "small" (it is canvas-sized); `RecipeClipRect`'s doc says
"always nil today" (nests set it).

---

## 4. Decisions for spec §11 — proposed, recorded before the first line of each phase

Road map 3's shape applies: each decision is written into spec §11 (and §1
amended in place with a bold sentence where a non-goal moves) BEFORE the
phase that needs it writes code.

**D1 — No effect runtime.** Every effect in this road map is a closed
vocabulary in the core's schema: an enum variant or a struct with ranges,
range-checked by `props_check.rs`, carried by the recipe, mirrored by the
MCP catalog, rendered by the one compositor. There is no package format, no
user shader, no expression language and no per-effect pipeline. Spec §1's
"a plugin system" stands. *Why:* Concat's own runtime shows the price — a
second (FFmpeg) rendering of every effect that disagrees with the first,
fixtures that pin a filter STRING rather than a picture, parameters the UI
cannot reach — and Reelcut's standing rule that "a second renderer would be
a second thing for export to disagree with" (spec §5.2) already decided it.

**D2 — "Color grading beyond per-clip controls" is re-drawn around a
grading SUITE.** IN: tone controls (E3), named looks (E5), adjustment clips
(E6) and LUT application (E7) — each a property of a clip. OUT, still: color
wheels, curves, HSL qualifiers, scopes, node graphs, log or HDR workflows,
and a linear-light pipeline (spec §7.5 already says linear light is a
decision for the WHOLE pipeline, not one stage). An adjustment clip is a
clip, not a grading node: it has a start, a duration, a track, a strength
and a mask, and nothing routes to or from it.

**D3 — LUTs are IN, as media (E7 only).** Reverses the "LUTs (`.cube`)"
line of road map 2 §4. A `.cube` file is a `Media` of a fourth kind, `lut`,
so relink, consolidate, missing-file handling and "is this media used" come
from paths that exist; it is applied to ENCODED sRGB values, which is what a
display-referred Rec.709 LUT expects, and a log or scene-referred LUT will
look wrong — recorded as a limit, not fixed. Declining E7 leaves D2 intact.

**D4 — Voice effects are rendered, not live (E8).** The tap cannot host a
pitch shifter and a reverb's tail outlives the clip, so a clip with a voice
effect plays a cached, offline-rendered file, exactly as a reversed clip
plays `cache/reversed/…`. Spec §1's "audio beyond volume/fade/duck" was
already overtaken by M3's compressor, pan and noise reduction; this records
that the line now reads "a mixing desk or an audio plugin host".

**D5 — Remove Background uses Vision and ships no model (E9).** Masks are
computed by `VNGeneratePersonSegmentationRequest` for video and
`VNGenerateForegroundInstanceMaskRequest` for pictures only (§5b), cached per media under the
stamp / marker / ledger discipline of `thumbs/` and `peaks/`, and sampled by
the compositor as a second texture. No download, no ONNX Runtime, no GPL
weight; it is road map 2 §4's "ML" exclusion narrowed to "a model the app
ships or downloads".

**D6 — Every time-varying effect is a pure function of (clip, frame).**
Grain, scanline crawl and shake take a clip-local frame index and a seed
derived from the clip id through the recipe — never wall-clock time, never
a previous frame — so `render_frame` at a tick is byte-identical run after
run, preview and export agree, and two grained clips do not share a
pattern. Multi-frame effects (echo, trails, true motion blur) stay out.

**D7 — Nothing moves content out from under an obscure region.** A region
hides what a person asked it to hide, so every stage that moves pixels
either carries the region with it — flip is a transform of the quad, not of
the sampling coordinate (E3) — or hides by BOTH positions, the fragment's own
and the one its colour was sampled from (E4's remaps and mirror). Written
because the review found the plan breaking it twice: once designed around
(flip) and once not (mirror), in the same document.

---

## 5. E0 — the spikes, run on 2026-09-15 before the plan

Two framework questions carry E8 and E9, and each was measured by a program
tracked in `tools/proof/effects_spike/` (its README has the build lines and
fixtures). Everything else in this road map rests on machinery the tree
already runs — the recipe, the uniform block, programmable blending — and
is left to each phase's own first step.

### 5a. V — offline voice rendering through Apple's audio units

Measured 2026-09-15 on macOS 26.5.1 (25F80), Apple M2 Max, by the
`fx_*.swift` programs. **The machine was loaded** (load average 58–66 on 12
cores from other work), so every ×-realtime figure is a floor and runs varied
by up to 1.6×.

1. **Synchronous offline rendering works with no `async`.**
   `enableManualRenderingMode(.offline, …)` + `AVAudioPlayerNode.scheduleFile`
   + a `renderOffline` loop ran on the main thread with no run loop (704 calls
   for 60 s, all `.success`) and on a global queue, byte-identical. ×realtime:
   dry 3,680–5,924; `TimePitch` ±7 to ±12 st 143–212 (+12 st at overlap 32:
   40–49); reverb 116–180; delay 1,123–1,515; EQ 715–925; distortion
   804–1,029; a four-unit chain 61–101; file → chain → float CAF 58–91.
2. **Presets.** Reverb 13, distortion 22, EQ filter types 11; delay, EQ and
   `TimePitch` have none. **Reverb's `loadFactoryPreset` is silently ignored
   before `engine.start()`** (four presets rendered one identical digest — the
   unit's power-on state) **and lands 2,069 frames late after it**;
   `auAudioUnit.currentPreset` set before start takes effect from sample 0.
   Tails to −60 dBFS on speech: smallRoom 11 ms, mediumRoom 239 ms, plate
   246 ms, mediumHall 2.17 s, largeHall 2.20 s, cathedral 5.79 s. No preset
   band-limits (telephone needs an EQ high-pass and low-pass);
   `speechRadioTower` is ring modulation plus a 28 ms delay, not a band-pass;
   `multiDecimated1–4` crush; no preset is a robot, and the distortion unit
   exposes only 2 of its 16 parameters by property (the rest by
   parameter-tree address, deterministically). Distortion presets add +0.9 to
   +19 dB RMS and exceed full scale in float.
3. **Determinism: byte-identical** for all 13 cases across two fresh engines,
   across two process runs, and across four concurrent renders; file and
   buffer sources identical; float CAF and 16-bit WAV written twice
   byte-identical. **But the render CALL SIZE is part of the output:** at
   1,024 or 333 frames per call instead of 4,096, distortion's ring-mod and
   decimation presets diverge from the first boundary (up to +5.5 dBFS), EQ
   at −162 dBFS; dry, `TimePitch`, reverb and delay are unaffected. A source
   node differs from a player only in distortion's tail.
4. **Alignment.** Every unit reports latency 0. `TimePitch` at ±700 and
   ±1200 cents and at overlaps 3, 8 and 32 lags a median 0.0 frames (±1),
   output exactly the requested length, transients smeared symmetrically by
   4–12 frames; pitch 0 at rate 1 is NOT a passthrough (−90 dBFS). Reverb and
   delay at wet 0 are byte-identical to dry. Tails are had by rendering on
   after the player runs out; output reaches hard zero at `tailTime` (10.09 s
   for every reverb preset, 21 s for the default delay).
5. **Pitch at the extremes.** On a 220 Hz tone every setting from −2400 to
   +2400 cents landed within 0.5 cent; ±3000 renders as ±2400 but reads back
   3000. Speech loses 1.5–4.9 dB depending on `overlap`, which changes the
   waveform (−21 to −24 dBFS difference) and not the pitch. Artifacts were
   not judged by ear.
6. **Re-render cost.** A 10 s window 30 s into the file, fresh engine,
   setup + render + write: `TimePitch` 49–115 ms, reverb with a 3 s tail
   78–131 ms, the four-unit chain 182–268 ms. **A window render is not a
   slice of a whole-file render**: identical for dry, settling to −168 dBFS
   for EQ, but different everywhere for `TimePitch` (up to +0.34 dBFS) — the
   cache key must hold the window.
7. **What breaks.** Reverb given MONO input raises an Objective-C exception
   (−10868) that aborts the process — connect at stereo, which upmixes
   deterministically. `play()` before `start()` renders silence; scheduling
   after `play()` starts at a random offset (12,288, 0, 18,432, 0 frames);
   schedule → start → play is deterministic across eight concurrent renders.
   Header defaults are wrong for three units (delay wet 50 not 100,
   distortion wet 44.6 and pre-gain −0.9, reverb wet 100) and out-of-range
   writes read back unclamped; EQ bands start bypassed. `bypass` is dry for
   four units but not `TimePitch` (−138 dBFS); distortion at wet 0 is not dry
   (−28 dBFS). `AVAudioFile` opens `.mov` and `.m4a` directly.

**Could not measure:** switching output devices, audible quality, the macOS
15 deployment target, multi-track or variable-rate `.mov` audio, an
`AVComposition` playing the cached file. E8's first build steps take the
last three.

**Verdict: E8 is buildable, as a per-clip WINDOW cache with a fixed render
contract** — the plan's whole-media cache was overturned by q6, and q2, q3
and q7 each became a rule in E8.

### 5b. C — Vision segmentation for a cached mask

Measured 2026-09-15 on the same host (macOS 26.5.1, M2 Max, 16-core Neural
Engine) by `vision_stills.swift` and `vision_job.swift`, fixtures by
`vision_fixtures.sh`, run from a shell under the terminal's attribution.
The machine was busy (load 5–60), so times are upper bounds (±1.3×).

1. **API.** Both requests are synchronous through `VNImageRequestHandler`
   (the newer Swift `perform(on:)` is `async`-only). One revision each, no
   required setting, **no TCC grant**. Person segmentation always returns ONE
   `VNPixelBufferObservation`, even with no person, at a size that ignores
   the input: fast 256×192, balanced 512×384, accurate 2016×1512 — always
   4:3 (portrait input gives the transposed sizes; a square input is
   inconsistent between qualities). Foreground returns zero or one
   `VNInstanceMaskObservation`, labels at 512×512. Every mask covers the
   whole frame in normalised coordinates, stretched, y down. Foreground
   cannot run on the CPU (`unsupported compute device`).
2. **Speed**, warm medians at 1080p: person fast 6.6 ms, balanced 28.3 ms,
   accurate 65.1 ms; foreground 18.0 ms for its 512² mask; 4K is within a
   few ms of 1080p. Cold first call 99–299 ms. The realistic job, a 60 s
   1080p30 H.264 decoded at 10 frames per second of source: decode alone
   21–25× realtime; **person balanced 4.2–5.5×**; foreground 5.4–7.0×;
   person fast 13.6–16.5×; accurate 1.6–1.7×; balanced on the CPU 0.7×.
3. **Determinism.** On ONE device, byte-identical: fresh against fresh in a
   process, 54 of 54 stills across two processes, 600 of 600 masks across two
   whole-job runs for balanced (ANE and CPU) and foreground. Across DEVICES,
   different: balanced up to 25 levels (GPU) and 11 (CPU), accurate up to
   32, foreground ANE against GPU up to 255 on 0.04–0.8 % of pixels. Auto
   equals ANE. **`.fast` is stateful**: a reused request or a sequence
   handler matched a fresh request on 5 of 600 masks (mean difference 46);
   balanced, accurate and foreground carry no state (600 of 600).
4. **No person.** Person segmentation on cards, text and Reelcut's own UI:
   0.00 % of pixels above 127, maxima 0–31, on every one of 600 masks of a
   scrolling-UI recording; a faint haze up to value 75 on a photo; a test
   pattern under accurate put 0.63 % above 127. **Foreground returns no
   observation at all** on cards, text, test patterns and the UI (900 of 900
   frames) and cuts anything salient otherwise — a circle, a sheet of paper,
   a monitor. A screen recording showing a film: both cut out the actors.
5. **Person content** (system-shipped images and road map 3's film
   recordings — no personal files): a frontal portrait 29.2–29.3 % in every
   mode; arms raised under dramatic light 3.9 % person (part of an arm)
   against 15.6 % foreground (the whole figure); a person from behind 0 %
   person against 39 % foreground; a small silhouette 0 % against 1.8 %.
   Quality on real camera footage — hair, motion blur — unmeasured.
6. **Cache.** Per mask raw: person balanced 196,608 B (112.5 MB per 60 s
   at 10/s), foreground 262,144 B. As PNG: balanced 12.4–32.9 KB (16.2 MB
   for the 60 s film job), foreground 4.6–7.2 KB (3.7 MB). Accurate raw is
   1.70 GiB per 60 s.
7. **Stability.** A static portrait at 30 fps: mean consecutive difference
   0.16 (balanced), 0.09 (accurate), 0.05 (foreground) levels. A static shot
   from behind under foreground: 5.3, 3.4 % of pixels flipping. **A slow
   push-in under foreground: coverage swinging 10–85 %, up to 57 % of pixels
   flipping between masks 0.1 s apart** — the monitor pops in and out.

**Could not measure:** the first-ever Neural Engine compile, masks across
machines or OS versions, real camera footage of a person, concurrent
requests, YUV input, TCC in the signed bundle, an idle host.

**Verdict: E9 is buildable as PERSON segmentation at `.balanced` for video,
with foreground for pictures only, a pinned device, and a per-window "no
subject" rule** — the plan's two-subject design for video was overturned by
q7, and q4 is why the rule exists.

### 5c. Questions left for build time, each a phase's first step

- **E3** — the tone group's per-pixel cost at the 8 ms budget with the fast
  path's flag; and the `kGatherFilters` register counts re-measured after the
  header move.
- **E4** — each new gather's tap cost; whether the specialization's dead-code
  cost crosses the budget (the fallback is a constant per gather class); and
  whether the spotlight lens can already carry obscured content out of a
  region (D7).
- **E5** — a two-texel gradient through a `rgba16Float` 3D texture with the
  linear sampler, before the looks are written.
- **E6** — none: the reviewer verified by reading that `DestinationPass.open()`
  resumes a suspended pass with `.load`, so framebuffer fetch sees every
  earlier layer and shadow.
- **E8** — the three unmeasured rows above.
- **E9** — the first-ever Neural Engine compile cost, and a mask-quality
  check on real camera footage by a person at the machine.
- Two reviewers read this plan against the tree before it was trusted (§10).

## 6. The phases

Each phase lists what it adds, the schema, the core, the Swift and Metal,
the UI, the MCP mirror, the files and tolls, the proof and the limits. The
tolls are PURE MOVES landed and gated alone, before feature code, per
road map 2's rule. Ops counts assume road map 4's S1 (in progress in the
tree as this is written) adds none.

### E1 — Transitions, second pass

**Adds:** three more wipe directions, easing, an audio crossfade, and adding a
transition at a hard cut. Schema **v7**. TWO new ops, `add_transition` and
`set_transition_style` (`OP_NAMES` 55 → 57, catalog 75 → 77).

**Schema.** `Transition` gains two keys, both defaulting so a version-6
file renders and SOUNDS exactly as before:

```json
"transition_in": { "kind": "wipe_up", "curve": "ease_in_out", "audio": true }
```

- `curve`: the existing `Curve` (linear, ease_in, ease_out, ease_in_out);
  absent reads `linear`. Evaluated by `actions::ease` (`actions.rs:75`,
  already `pub`), never a second copy.
- `audio`: crossfade the pair's sound across the overlap; absent reads
  `false`.
- `TransitionKind` gains `wipe_left`, `wipe_up`, `wipe_down`, APPENDED;
  `wipe` keeps its meaning (the edge travels rightward) and its name, so no
  migrate step. (Four push variants are the precedent for direction as
  variants rather than a field.)
- The core creates a transition in exactly two places today —
  `set_gained_transitions` (`edit_clip.rs:98`, `Transition::default()`) and
  `set_transition` (`edit_clip.rs:1197`); paste keeps a payload's, and
  split, nest, background, detach and freeze set `None`. Both, and the new
  `add_transition`, go through one constructor, `Transition::minted(kind)`,
  writing `curve: ease_in_out, audio: true`. A file's missing keys and a new
  edit's values therefore differ on purpose, and `format.rs`'s paragraph says
  so: the default is what every existing file drew and sounded like; the
  minted value is what a transition should be. `transition.rs:87`'s
  `unwrap_or_default` for an overlap with no `transition_in` correctly stays
  the FILE default.

**Toll first.** `edit_clip.rs` is 1252 lines and takes nothing without a cut:
`set_transition`, `set_transition_duration` and `set_gained_transitions`
move to a new `core/src/edit_transition.rs` as a pure move, gated alone;
`add_transition` and `set_transition_style` then land there. `audio.rs`
(587) pays too: the ducking arithmetic moves to `audio_duck.rs`.

**Ops.**
- **`set_transition` is unchanged.** Its `kind` absent or `null` CLEARS the
  transition (`edit.rs:119`), and an op's arguments cannot tell absent from
  null (`edit.rs:28`), so `{clip, curve}` on it would clear. Style is a
  separate op instead:
- **`set_transition_style`** `{clip: u32, curve?: curve, audio?: bool}` —
  absent keeps (neither is nullable, so absent is unambiguous). On an overlap
  with no stored transition it mints one and applies the style. `None` when
  nothing changes.
- **`add_transition`** `{clip: u32, kind?: transition, duration: ticks,
  align?: center | before | after = center}`. `clip` must meet its
  predecessor at a HARD CUT — `roll`'s test (`edit_edge.rs:141-148`): the
  predecessor ends exactly at `clip`'s start.
  - **The overlap is made from HANDLES and nothing else on the timeline
    moves.** `center` extends the predecessor's tail by half and pulls
    `clip`'s head back by half, so the overlap straddles the cut; `before`
    lies wholly before the cut, all from `clip`'s head (Concat's only
    placement); `after` wholly after it, all from the predecessor's tail.
  - **Handles are already timeline ticks.** The tail handle is
    `source_length(A) − A.duration` and the head handle is `source_head(B)`
    (`model_query.rs:155-185` divide by speed already — applying speed again
    would be the bug). Both measure the reversed stream for a reversed clip.
    `None` from those helpers is NOT "unbounded": it is unbounded only for a
    still, text, shape or image source, decided by the source kind; for a
    media clip `None` (a bad speed, an unknown media) is no handle.
  - **A nest has no head handle.** Trimming a nest clip's head MOVES its
    contents (`nest.rs:22-28`), so `center` and `before` on an incoming nest
    clip refuse; `after` works. A nest PREDECESSOR's tail handle is
    `max(0, nest duration − clip duration)` — past that the nest draws
    nothing (`nest.rs:29-33`).
  - **The frame grid.** Each side is snapped separately with `roll`'s
    snap-inward bounds (`edit_edge.rs:159-166`); an odd frame count gives the
    extra frame to the side with more handle, ties to the incoming head.
  - **The clamp.** The landed duration is the requested one clamped to the
    handles, to the overlap rule (at most half the shorter clip; the rule is
    checked over the whole resulting track, so a tail reaching a THIRD clip
    is caught), and to the grid; `center` with one side short takes the
    shortfall from the other before shrinking. *Why clamp when `close_gap`
    refuses rather than closing part of the way:* a gap closed part-way is a
    different edit, while a shorter transition is the same edit at a size the
    media allows, and every editor a person has used behaves that way.
  - **The incoming clip's actions are rebased** by its head extension, so a
    screencast zoom stays on the click it was drawn for (`trim_start` leaves
    actions alone on purpose, `edit_clip.rs:750-754`; a transition is not a
    trim). Its `fade_in`, text reveal and (E2) motion `in` are measured from
    its new first frame, so they begin under the transition — which is what
    a transition is.
  - **`kind` absent keeps a stored kind.** Clip ▸ Transition ▸ already
    validates for any selection and, at a hard cut, stores an undrawn
    `transition_in` (`edit_clip.rs:1185-1199`); `add_transition` without
    `kind` uses that stored kind and style, and mints `cross_dissolve`
    otherwise.
  - **Refusals.** Not at a hard cut — no predecessor, a gap, an existing
    overlap — and a head handle asked of a nest are `Err` naming the case.
    That departs from `roll`, whose gap refusal is `Ok(None)`, and the
    argument goes in the module doc: `roll` is reached by a DRAG that can
    land on any edge, while `add_transition` is pointed at one cut by a
    caller who meant that cut, so a wrong cut is a wrong argument
    (core/CLAUDE.md's `Err` class). A cut with less than a frame of handle is
    `Ok(None)` — a domain refusal — and the tool reports it as "made no
    change: neither side of the cut has media to give".
- `refused_inside` classifies both ops as allowed inside a scope (the match
  is exhaustive, so the compiler insists).

**The audio crossfade** (`audio.rs`).
- **Where it lives.** Not in `Voice::of`, which sees only the top-level
  tracks (`audio.rs:199`) and whose `Stage` carries no container. The term
  goes per STAGE in `stage_gain`, over the stage's own container clips —
  `inside[d-1].nest.clips` or the project's — at CONTAINER time, the way
  `recipe.rs:409-445` already finds a transition. That is what lets an
  overlap between two nest clips fade everything inside both.
- **The law is CONSTANT POWER** — the outgoing clip's gain × cos(p·π/2), the
  incoming's × sin(p·π/2), `p` the EASED progress — because the overlap a
  person adds a transition at is two DIFFERENT moments (a Remove Silences
  cut, a jump between takes), which is uncorrelated material, where equal
  gain dips −3 dB mid-fade and constant power holds level. A pure split with
  nothing removed is the correlated case, where constant power bumps +3 dB;
  nobody adds a transition there. Premiere's and Final Cut's default
  crossfades are the same law.
- **The envelope has no grid to ride.** `breakpoints()` samples only inside
  actions that touch `audio` (`audio.rs:465-483`), so the transition adds
  its own: the overlap's two edges plus samples every 1/30 s across it (the
  sine law is not linear, and neither is an eased `p`).
- **The outgoing clip's LAST sample.** `progress_in` is half-open
  (`transition.rs:72-79`) and `audio_ramps` evaluates a voice at its end
  from the left (`Side::Left`, `audio.rs:123-128, 390-391`), where
  `transition_among` answers `None` — which would read as gain 1 and undo
  the fade on the last breakpoint. The term honours `Side`: at the
  outgoing clip's end the limit is p → 1, gain 0.
- Mute, solo, ducking and volume keep their precedence; the term
  multiplies like ducking does. A pair where only one clip has audio still
  fades that one (Concat's shape).
- **What follows automatically, and what must be told.** The level meter
  and export loudness read the envelope, so they follow. Normalize Clip is
  pre-fader and is correctly unaffected. **Remove Silences' level mode is
  not**: `peak × (1 − p)` mid-fade can fall under the threshold where the
  material did not (`SilenceDetector.swift:510-524`), proposing a cut INSIDE
  a transition. The detector learns that a tick inside an overlap is never
  a candidate — a transition is not dead air, the rule that already keeps a
  hole in the timeline from being one. `SilenceDetector.swift` is being
  rebuilt by road map 4's S1 in the working tree as this is written, so E1
  lands after S1.

**Swift and Metal.**
- `TransitionCode.direction` gains the three wipes: `(−1,0)`, `(0,−1)`,
  `(0,1)`. The shader's wipe branch already reads a direction vector and the
  `1 − axis` rule sweeps each correctly (`Compositor.metal:1306-1309`), so
  no shader change.
- **The wipe edge stays in LAYER space.** Moving it to canvas space would
  mend a different-size pair and break the common one: two same-size
  picture-in-picture cards (a 480 px card at x 1340–1820 of 1920 would wipe
  only between p ≈ 0.70 and 0.95 — a late, quick cut), every nested layer
  inheriting its nest clip's wipe (`recipe.rs:398-446`), and a vertical wipe
  over a reflection. The measure that is right for all of them is the PAIR's
  union box (and the `clip_rect` frame inside a nest), which costs uniforms
  and nests — recorded as a limit and left for a later pass.
- The Transition section (`VideoPane.swift:1414-1463`) moves to
  `VideoPane+Transition.swift` first, alone, then gains a Curve popup and a
  "Crossfade audio" switch.
- Clip ▸ Transition ▸ `<kind>` on a clip at a hard cut calls `add_transition`
  (0.5 s, centred); on an overlap it stays `set_transition`. Its validator
  stops answering true for any selection: at a gap or on a first clip it is
  disabled.

**MCP.** `add_transition` and `set_transition_style` are new tools in
`AgentCatalog+Transitions.swift` and `AgentServer+Transitions.swift`, both
new, because `+Clips` is over the cap. The op table, spec §6, `ReelOps.swift`
and the catalog move in lockstep.

**Proof** (`tools/proof/e1_proof.py` over MCP, `e1_chrome.py` offscreen):
- the three new wipes at p = 0.25 on two full-canvas cards: the incoming
  colour exactly on the named side, the boundary within one pixel of the
  eased position;
- easing: `ease_in_out` at progress 0.25 puts the boundary where smoothstep
  says; a v6 fixture with no `curve` or `audio` renders AND exports
  byte-identical against the pre-phase binary;
- audio: two different tones overlapping by 1 s with `audio: true` export
  with the summed RMS within 0.2 dB of the constant-power line across the
  overlap, the outgoing tone reaching exactly zero at its last sample (the
  `Side` row); `audio: false` byte-identical to the pre-phase export; a
  nested pair fades everything inside both nests;
- `add_transition`: timeline end, every other clip and the pair's outer
  edges unchanged (`get_project`); the landed duration clamps to the shorter
  handle and centres; an odd frame count lands on the grid; a nest incoming
  clip refuses `center` and accepts `after`; a zoom action on the incoming
  clip stays on the same source frame; the four `Err` refusals by name and
  the no-handle `made no change`; one undo restores the document byte for
  byte; Remove Silences proposes nothing inside the overlap.
- Mutants: `cos` and `sin` swapped; the `Side` limit removed (the last
  sample swells back); `minted` writing linear; `align` ignored; speed
  applied twice to a handle; the action rebase removed; the detector's
  overlap rule removed.

**Limits.** Wipes are measured in each layer's own box, so a different-size
pair does not meet at one edge. A video pair whose audio is DETACHED has
`enabled.audio` off, so `audio: true` does nothing and the detached clips
below stay a hard cut unless they get a transition of their own. An
adjustment clip (E6) renders every kind as a dissolve of its strength. Fades
to colour still fade the layer's own RGB, so a picture-in-picture clip fades
to a black box rather than to the backdrop (Concat has the same limit).

### E2 — Motion presets: In, Out, During

**Adds:** CapCut's In / Out / Combo, as a first-class property computed by
the core. Schema **v8**. No new op (it is a `set_video` key), no new tool.

**Schema.** `video.motion`, the last key of `VideoProps`:

```json
"motion": {
  "in":     { "kind": "slide_up", "duration": 12000 },
  "out":    { "kind": "fade",     "duration": 12000 },
  "during": { "kind": "pulse", "amount": 0.5, "period": 24000 }
}
```

- `in` / `out`: `null` or `{kind, duration}`; kinds `fade`, `zoom_in`,
  `zoom_out`, `slide_up`, `slide_down`, `slide_left`, `slide_right`, `spin`,
  `pop` (a scale overshoot that settles — the one kind Concat does not
  have, and the one a screencast callout most wants). `duration` in ticks,
  from the clip's own first frame (`in`) or back from its last (`out`),
  exactly `text.animation`'s convention.
- `during`: `null` or `{kind, amount 0–1, period}`; kinds `pulse`, `shake`,
  `spin`, `bounce`, `drift`. `period` in ticks (default 1 s; `drift` ignores
  it and runs the whole clip). A PERIOD, not "per clip": Concat's shake
  swings nine times whatever the clip's length, so a long clip shakes
  slowly.
- The types live in a new `core/src/model_motion.rs`. `model_props.rs` is AT
  600, so its toll comes first: the picture vocabulary (`ColorAdjust`,
  `Chroma`, `Filter`, `FilterKind` — blur and pixelate are not colour, hence
  the name) moves out to `core/src/model_picture.rs` as a pure move — which
  is also where E3 and E4 will add their fields.
- `motion` is not an animation target, and saying so in `set_action_end`
  alone would not hold: a pasted or hand-written end patch reaches
  `evaluate_clip`'s merge without passing that op. So `clamp_video` restores
  the BASE `motion` after the merge (the blend-on-nest precedent,
  `actions.rs:420-434`), and `set_action_end` refuses the key by name as the
  courtesy on top. `Group::template` (`edit_props.rs:92-102`) grows
  `motion.in`, `out` and `during` entries, or `check_keys` cannot see a
  misspelt key inside a null motion and serde drops it.
- `paste_attributes` replaces the video group whole
  (`edit_paste.rs:357-360`), so copying a clip's look copies its motion with
  no code.
- **Every op that copies a clip must decide about motion**, because a
  preset is anchored to the clip's two ends and a copy has new ends.
  `split_clip` clears `out` on the first half and `in` on the second — and
  every splitter inherits that (`ripple_delete_ranges`, `lift_range`,
  `insert_clip`, `overwrite_clip`), which is the difference between Remove
  Silences on a clip with `in: fade` giving one fade-in and giving
  twenty-four. `join_clips` takes the first half's `in` and the second's
  `out`. `freeze_frame` drops motion from the still and
  `add_blurred_background` from the backdrop. `text.animation` has had the
  split half of this defect since phase 4 and it is recorded nowhere; E2
  fixes it with the same rule in the same function, with its own test.

**Core — the semantics are the point.**
- `core/src/motion.rs` (new) is one pure function over a clip's EVALUATED
  video props at clip time `t`, returning the props a layer draws with.
  Everything is RELATIVE to what the clip already is — scale and opacity
  multiply, offsets and rotation add — and the three slots COMPOSE (their
  factors multiply and their offsets add), so In Zoom plus During Pulse is
  both, and an action moving the clip keeps moving it while it slides in.
  This is the defect in Concat's design (slots merged into one track, user
  keys dropping presets) designed out.
- Each kind's easing is part of its definition — arrivals ease out,
  departures ease in, `pop` overshoots — computed inside `motion.rs`, so
  `Curve` gains nothing.
- **A slide enters from just outside the canvas edge**, computed from the
  layer's bounding box through its rotation (`edit_zoom.rs`'s corner test is
  the precedent) wherever the core knows the layer's size — media, image,
  still, shape, nest — and from one canvas dimension for TEXT, whose
  measured size the core never has (spec §11). That limit is recorded rather
  than worked around. For a layer inside a nest the canvas is the nest's
  frozen canvas. The pixel size lives today in two private twins
  (`edit_props.rs:237`, `edit_background.rs:207`, whose doc already asks for
  them to be collapsed); E2 would be a third, so they collapse into one
  `model_query.rs` reader first, as E2's toll.
- **The tent rule is motion's own**, because `text.animation`'s `min` of two
  ramps has no meaning for two different transforms (a `slide_up` arrival
  and a `zoom_out` departure). When `in + out > duration` both durations
  scale by `duration / (in + out)`, so the arrival ends on the frame the
  departure begins and neither is refused — the same refusal-free argument
  (too big for THIS clip is a fact about a clip, which a trim could change),
  a different arithmetic.
- The moved scale is re-clamped to `clamp_video`'s bounds and opacity to
  0…1, so a clip already at the scale ceiling pops without growing past it.
- It is applied where a layer's placement is produced, and both places are
  in `recipe.rs`: the layer's own props (`recipe.rs:313-317`) and a nest
  clip's props in `frame_of` (`recipe.rs:389-396`) before `Frame::enter`
  folds them into every inner layer — `nest.rs` itself is arithmetic and
  never evaluates a clip. It is NOT applied in `evaluate_clip`, so every
  EDIT reads un-moved props: the inspector's fields, `get_project`, the
  canvas handles' drag origin. The only precedent for the recipe drawing
  something the model does not say is the forced `normal` blend under a
  transition (`recipe.rs:354-363`); motion is the second, and spec §5.3 says
  so. A clip inside an overlap composes its motion with the transition's
  vertex offsets.
- `add_zoom_action` solves against un-moved props, and on a clip with a
  `during` preset that is a recorded LIMIT rather than a fixable defect: its
  doc promises the region lands as drawn on the frame the person drew on
  (`edit_zoom.rs:110-118`), but the action writes BASE props that the preset
  keeps moving afterwards, so no base value is right at every frame. The
  canvas band says "this clip has a During motion" while armed.
- `recipe.rs` 537 gains two calls and `actions.rs` 573 gains the
  `clamp_video` restore; either crossing the cap pays its cut first (the
  recipe's placement block to `recipe_place.rs`; `clamp_video` and its
  helpers to `actions_clamp.rs`).

**UI.** A **Motion** section in the Video group (`VideoPane+Motion.swift`,
new): three rows — In, Out, During — each a kind popup (None first), a
duration or period stepper and, for During, an amount slider; a "Preview"
button that sets the range to the clip and plays. The timeline name strip
draws a small in-wedge and out-wedge whose widths ARE the durations (Concat's
fixed wedge is the thing not to copy). Clip ▸ Motion ▸ In / Out / During
submenus mirror the popups for a multi-clip selection (each clip gets the
same preset; durations clamp per clip by the degrade rule, not by refusal).

**MCP.** `set_video`'s schema gains `motion`, decoded by a HAND-BUILT
`motionPatchArg` (the `shapePatchArg` / gradient precedent) so a misspelt
key inside it is refused by name rather than silently replaced by the
generic decoder.

**Proof** (`e2_proof.py`): on a full-canvas card, `render_frame` at the
first frame of `slide_left` is the backdrop alone (the card entirely
off-canvas — the bounding-box rule), at `in` it is byte-identical to the
clip with no motion, and midway the card's leading edge is where the eased
offset puts it; `fade` at half its duration draws the card at the eased
opacity (±1); `during: spin` at one period is byte-identical to zero; a
60 s and a 5 s clip with `shake` at one period show the same displacement
at the same clip time (the period rule); an action moving x keeps moving
under `in: slide_up` (composition); a nest clip with `in: zoom_in` scales
every inner layer about the nest clip's placed centre; `get_project`'s props
are un-moved while `render_frame` moves; a tent (`in` 2 s, `out` 2 s, clip
3 s) arrives by 1.5 s and departs from there; `split_clip` at the middle
leaves one `in` and one `out`, and `ripple_delete_ranges` over three spans
leaves ONE fade-in; an end patch carrying `motion`, written straight into
the file, draws the base motion. Fixture cards carry no shadow or
reflection, which would otherwise stay on canvas at a slide's first frame.
Mutants: `motion` applied in `evaluate_clip`; slots merged by replacement;
the text fallback used for a shape; `period` read as a fraction of the clip;
the split rule removed; the `clamp_video` restore removed.

**Limits.** Text slides from one canvas dimension away, not from its own
edge. A preset has no per-kind parameters beyond duration, amount and
period. Motion is not drawn on the canvas as a path.

### E3 — Tone, flip and a mask

**Adds:** Concat's Adjust panel, flip, and an alpha mask. Schema **v9**. No
new op, no new tool (`set_video` keys).

**Schema.**
- `video.color` (`ColorAdjust`, in `model_picture.rs` since E2's toll)
  gains, all defaulting to 0 = no change: `exposure` (−3…3 EV),
  `temperature` and `tint` (−1…1, cool/warm and green/magenta),
  `highlights`, `shadows`, `whites`, `blacks` (−1…1), `vibrance` (−1…1) and
  `fade` (0…1, a lifted black point). Saturation keeps its meaning and
  range; −1 is grey (Concat's inverted-chroma −100 is the defect not to
  copy).
- `video.flip_x` and `video.flip_y`: booleans.
- `video.mask`: `null` or `{shape: rect | ellipse | linear, x, y, width,
  height, angle, feather, invert}` in the REGION FRAME (spec §5.3) that
  `obscure` and `spotlight` use. `shape` is its OWN enum, `MaskShape` —
  widening `SpotShape` would leak `linear` into the spotlight and obscure
  popups (`VideoPane.swift:861, 1012`), past `checkVideoEnums`
  (`AgentServer+Clips.swift:605, 619`), and into two renderers that map
  anything not an ellipse to a rect (`CompositorEffects.swift:84, 180`).
  `linear` is a straight edge through `(x, y)` keeping the side `angle`
  POINTS TOWARD (degrees counter-clockwise from the right, `Shadow.angle`'s
  convention on the y-down canvas — so 90° keeps the top), with `width` and
  `height` stored and ignored (the `shape.radius` precedent). One mask per
  layer: `invert` covers "cut a hole", and a second mask would cost a second
  uniform group for a case nobody asked for. Numbers animate through
  actions; `shape` and `invert` switch at the end.

**Metal — the order of operations** (`Compositor.metal`'s comment at
:858-878 moves with each stage):
- **Tone runs ONCE per pixel as step 4c**, inside the `if (effects)` block
  after the obscure regions (:1177) and before the point filters (:1179) —
  not in `gradeSample`, which runs on every one of a blur's thirteen taps.
  Brightness, contrast, saturation and hue stay where they are, so a layer
  with the new fields at zero is byte-identical to today's BY CONSTRUCTION.
  Two sentences go in the comment: the new fields are non-linear, so running
  them after the blur is a CHOICE (the exact-reorder argument at :921-929
  covers only the linear ones), and tone is not slate-guarded, matching
  brightness on the missing-media slate (:498-502).
- **The fast path's gate is a sum of NON-NEGATIVE terms** (:993-1004) and
  every new tone field is signed — `exposure: 0.5` with `blacks: −0.5` sums
  to zero and would skip step 4c. Swift writes a `toneEnabled` flag (1 when
  any tone field is non-zero) and the flag joins the sum; the mask gets a
  `maskEnabled` flag for the same reason, because shape code 0 is `rect`.
- **Flip is a TRANSFORM of the quad, applied BEFORE `rotate2`, about the
  CROPPED centre.** Not a mirror of the sampling coordinate — the design's
  trap: obscure regions are masked in `localPx` and sampled through `uv`
  (:1122-1127), so mirroring the texture coordinate would slide a hidden
  password out from under its region. Mirroring the quad while keeping
  `local` makes obscure, spotlight, corner radius, vignette, the mask and the
  shadow's mask pass all follow the picture. Before `rotate2`, or a rotated
  clip mirrors about the canvas axes; about the cropped centre, or an
  asymmetric crop moves the visible rect and every mapping built on the
  anchor breaks. Crop insets stay named in SOURCE orientation (a left crop
  removes the source's left, shown on the right when flipped). Flip is
  independent of the source's coded orientation (`sourceMirrored`), which is
  corrected at the sample before any stage sees the picture.
- **The reflection needs its own flip arm.** Its branch (:397-416)
  hard-codes the source's bottom strip; with `flip_y` the reflected edge is
  the picture's new bottom, which is the source's top.
- **The mask multiplies coverage at step 7c**, beside corner radius, through
  `regionMask` (:700-721) widened with a rotation and the linear case.
  Because it is coverage, the shadow casts the masked shape and the
  reflection mirrors the masked picture for free.
- **The dissolve's partner box over-claims** for a masked partner, and would
  brighten the outgoing layer mid-dissolve; `partnerBox`'s guard
  (`Compositor.swift:1340-1351`), which already refuses rotated, rounded and
  clipped partners, adds masked ones (and E9's cut-out ones).
- **Uniforms:** tone 9 + `toneEnabled` in a group of 12; flip 2 + mask 8 +
  `maskEnabled` in a group of 12 — 24 floats, with three spare that E4 and
  E5 spend before opening a group of their own (the `blendMode`
  precedent). `phase8_chrome.py`'s `== 416` assertion moves with every phase
  that grows the block and says which; the numbers are stated as INCREMENTS
  because the phase order in §7 is not the only buildable one.

**Every canvas mapping learns flip** — the vertex stage is one place, but
four Swift readers mirror it and none negates today:
- `CanvasLayerBox.sourcePoint` / `canvasPoint` (`CanvasSessions.swift:274-288`),
  or a region, band or mask drawn on a flipped clip lands mirrored;
- the crop handles' inset arithmetic (`CanvasSessions.swift:718-770`);
- a line or arrow shape's endpoint handles (`CanvasSessions.swift:234-251`);
- `RecipeLayer.videoProps` (`ProjectSnapshot.swift:2312-2317`) and
  `CanvasLayerBox.uncropped` (`:166-171`), which silently DROP any
  `VideoProps` field they do not pass through — every new field in this
  road map must be added there, and a probe test says so.
- In the core, `edit_zoom.rs` pans toward an off-centre region; on a flipped
  clip that direction reverses.

**The shader-file toll** (`Compositor.metal` 1548). The stages this road map
adds move into HEADERS — `CompositorShared.h` (`LayerUniforms` and the
helpers), `CompositorTone.h`, later `CompositorFilters.h` — `#include`d by
the one `Compositor.metal`, not into sibling `.metal` files: a `static
inline` helper cannot cross a translation unit into `layerColorPremultiplied`,
and an extern one links in Xcode's default library but NOT in the two proof
probes that compile `Compositor.metal` alone into a metallib
(`phase7_chrome.py:1040-1049`, `phase8_chrome.py:1819-1827`). Three things
land with the move, before a line of tone code: both probes cache on EVERY
file in `app/Resources/Shaders/` rather than on `Compositor.metal`'s mtime
(or an edited header is measured stale); `project.yml:28`'s Shaders source
gives `.h` files build phase `none`; and the `kGatherFilters`
register-count measurement (:106-122) is RE-MEASURED, since moving code can
change inlining. Then every earlier proof re-runs, as phase 6 did for the
blend refactor. `ProjectSnapshot.swift` (2484) pays its own: the video-props
colour decode moves to `ProjectSnapshot+Color.swift`.

**UI.** The Color section becomes **Color** (the four existing sliders plus
temperature, tint, vibrance) and **Light** (exposure, highlights, shadows,
whites, blacks, fade), each with its Reset, in `VideoPane+Tone.swift`. Flip
is two toggles in the Transform section's header plus Clip ▸ Flip
Horizontal / Flip Vertical. **Mask** is a section (`VideoPane+Mask.swift`)
with Shape, the region fields, Angle, Feather and Invert, and "Draw on
Canvas", which arms a band modelled on `ZoomRegionSession` but with its OWN
modifiers — ⇧ constrains to a square or circle, ⌥ picks the ellipse —
because the zoom band's ⇧ already means fill.

**MCP.** `set_video` gains the keys; `mask` decodes through a hand-built
`maskPatchArg` that refuses a misspelt key by name.

**Proof** (`e3_proof.py`): every tone field at 0 on a decoded 4:4:4 card
(phase 6's section 8 fixture) byte-identical to the pre-phase binary;
**`exposure: 0.5, blacks: −0.5` on an otherwise plain layer CHANGES the
frame** (the signed-sum gate, with the flag mutant failing); each field moves
a mid-grey card in its named direction, `exposure: 1` doubles an 8-bit value
below 128 within ±1; highlights leave a value below 64 untouched and shadows
one above 192; `flip_x` on an asymmetric card equals the mirrored PNG byte
for byte; **flip with an obscure region hides the same picture pixels** (the
texture-coordinate mutant failing); flip of an asymmetrically CROPPED,
ROTATED card keeps its bounding box and mirrors about its own axis; a mask
drawn through `CanvasLayerBox` on a flipped clip covers the pixels drawn
over (a probe); a rect mask with feather 0 makes exactly its region opaque
and inverted the complement; a linear mask at 90° keeps the top half;
`flip_y` with a reflection reflects the picture's new bottom. Mutants: the
flags removed; the flip in sample space; the flip after `rotate2`; the
anchor as pivot; `sourcePoint` not negated; the reflection arm removed.

**Limits.** No curves, HSL or scopes (D2). The mask's handles appear only
while the band is armed (obscure's existing limit). One mask per layer.

### E4 — Thirteen filter kinds and a clock

**Adds:** Concat's stylised effects. Schema **v10**. No op, no tool.

**Schema.** `FilterKind` gains, APPENDED (declaration order is the shader
code): `posterize`, `threshold`, `solarize`, `emboss`, `edges`, `glow`,
`directional_blur`, `fisheye`, `mirror`, `chromatic_aberration`, `grain`,
`scanlines`, `vhs`. `Filter` gains ONE field, `angle` (degrees, default 0),
read by `directional_blur` (the streak) and `mirror` (the fold line through
the centre), stored and ignored by every other kind. `amount` keeps its one
meaning — 0 is present and does nothing — for every kind. `blur` and
`directional_blur` on ONE layer are refused by name (below).

**The clock (D6).** The recipe's layer gains `frame` (the clip-local frame
index at the project rate) and `seed` (a hash of the clip id — for a nested
layer, of the nest clip and the inner id together, so two instances of one
nest do not share grain — reduced below 2²⁴ so a `Float` carries it
exactly). No other time reaches the shader. `RecipeLayer` decodes leniently
(`ProjectSnapshot.swift:2273-2297`), so older Swift ignores both.

**Metal.** Each kind joins the stage its class belongs to:
- **Point kinds** (`posterize`, `threshold`, `solarize`) join step 5, in slot
  order.
- **`fisheye`** is a coordinate remap at step 2, beside pixelate.
- **`mirror` is NOT a coordinate remap** — a coordinate cannot be mixed by
  `amount`. It is a second colour sample at the folded position after step 3,
  mixed in by `amount`: obscure's resample shape, with obscure's limit (the
  mirrored sample is unblurred on a blurred layer).
- **Gathers** (`emboss`, `edges`, `glow`, `directional_blur`,
  `chromatic_aberration`, and `vhs`, whose chroma offset is a gather) join
  step 4 and `needsGather` (`CompositorEffects.swift:240-271`); a kind missing
  from it compiles out silently. There is no intermediate buffer, so **every
  gather reads the RAW texture** and the combination rule is stated per class
  in the comment: the detail kinds (`edges`, `emboss`) are built from raw luma
  and applied after the base sample, like sharpen's detail term, so blur +
  edges outlines the UNBLURRED picture; `glow` adds a blurred bright-pass of
  the raw texture; `chromatic_aberration`'s red and blue samples are raw, so
  sharp on a blurred layer; and `directional_blur` REPLACES the base gather
  with a streak, so it cannot be combined with `blur` in one pass (variance
  does not add in quadrature across two differently shaped kernels) — the
  pair is refused by name rather than drawn wrong. All five compile into the
  `kGatherFilters` specialization, which already costs every blurred layer
  about 0.05 ms for code it does not run (:115-122); each kind's taps are
  measured against the 8 ms budget before it lands, and if the
  specialization's cost crosses it, a second function constant per gather
  class is the fallback (four more pipeline states).
- **Clocked kinds** (`grain`, `scanlines`, and `vhs`'s lines and noise) hash
  (frame, seed, CANVAS pixel) through `canvasPixels`, so grain is one canvas
  pixel wide at every scale and every Preview Quality. Canvas-anchored grain
  does not travel with a moving layer (a push, a slide, E2 motion) — screen
  grain rather than film grain, recorded.
- **Nothing moves content out from under an obscure region (D7).** A remap
  changes `uv` while obscure masks in `localPx`, so `mirror` at amount 1
  would copy a hidden password into the un-obscured half and `fisheye` would
  magnify it past its box. With a remap or a mirror on the layer, a fragment
  is hidden when EITHER its own position OR the source position its colour
  came from lies inside a region — the greater hiding wins, obscure's own
  rule; with neither kind present the two positions are equal and the render
  is byte-identical. The spotlight lens (step 1) remaps `uv` before obscure
  too; whether a zoomed spotlight can already carry obscured content out of
  a region is checked at E4's first step and fixed by the same rule if so.
- **Uniforms:** four filter angles and the clock (`frame`, `seed`) — spend
  E3's spares first.

**UI.** The filter popup groups the twenty kinds under separators (Blur &
Sharpen · Stylize · Distort · Texture · Colour); a slot shows an Angle dial
only for the two kinds that read it.

**Proof** (`e4_proof.py` over MCP, `e4_chrome.py` for the probe rows): each
of the twenty at amount 0 byte-identical to no filter; each at 1 changes the
frame where its class says (a remap moves edges, a point kind keeps every
edge, a gather softens or lifts them); `grain` at one tick twice
byte-identical, at the next frame different, on two clips at one tick
different; **at Preview Quality Half, grain through the probe's compositor
matches the decimated Full render** (an export at Half proves nothing — its
`canvasPerDest` is 1 regardless, `Compositor.swift:1265-1266`, so a
destination-pixel mutant would survive it); `posterize` at 1 yields at most
its level count of distinct values per channel; `mirror` at 1 on an
asymmetric card equals the folded PNG; `directional_blur` at 90° smears
vertical edges only; **an obscure region with `mirror` at 1 leaves no
pixel of the region's content visible anywhere in the frame**; blur +
directional_blur refused by name. Mutants: seed from the track; `frame` from
wall-clock; a gather kind missing from `needsGather`; `angle` ignored; the
obscure either-position rule removed; grain on destination pixels.

**Limits.** No multi-frame effects (D6). Glow and aberration cannot bleed
past the layer's quad (§3). Detail gathers read the unblurred picture. `vhs`
is one look at one amount; grain is screen-anchored.

### E5 — Looks

**Adds:** named colour looks. Schema **v11**. No op, no tool.

**Schema.** `video.look`: `null` or `{kind: LookKind, amount 0–1}`. A CLOSED
set of 24 kinds, the names Reelcut's own and generic, in six groups —
Everyday (clean, bright, soft, vivid, warm, cool), Portrait (fair, rosy),
Cinematic (teal_orange, cold_shadows, golden_hour, moody, night, bleach),
Retro (faded_film, vintage, bronze, instant, cross_process), Mono (silver,
high_key_mono, noir_contrast) and Stylised (neon, mint) — with E7's `lut`
appended later. The list is a starting set tuned by eye at build time, not
a contract; its declaration ORDER is not load-bearing (the recipe carries the
kind by name, `TextAnimationKind`'s precedent).

**Rust decides, Swift does.** The core names the look and its amount and
nothing else. **`Looks.swift`** (new) holds each look as a small table of
Reelcut's own primitive parameters — white balance, split tone (shadow and
highlight colours, balance), a film curve (toe, shoulder), a matte (black
and white points), saturation and vibrance, up to two hue bands with a skin
guard — and bakes it into a 33³ `rgba16Float` 3D texture on first use
(35,937 evaluations; milliseconds), kept in an LRU beside the text texture
cache (`LayerRenderers`' 64-entry LRU is the reusable shape). A look is
COLOUR ONLY: Concat's looks that add halation, grain or a vignette are, here,
a look plus a filter, and the gallery says so. Half float, because Concat's
8-bit table bands on a smooth gradient.

**Metal.** Fragment `texture(1)`, a `texture3d<float>`, bound with a 2³
identity placeholder at EVERY site that uses a layer fragment function —
the layer draw (`Compositor.swift:896-901`), the reflection
(`CompositorEffects.swift:340-343`), the shadow mask (`Compositor.swift:1180-1185`)
and, from E6, the adjustment pass. Sampled at texel centres
(`(rgb · (N−1) + 0.5) / N`) through the shared linear, clamp-to-edge sampler,
mixed with the input by `amount` at a new **step 4d** after tone and before
the point filters, so sepia and noir act on the graded picture. Uniforms: a
look flag and the amount, from spares. (Linear filtering of a
`rgba16Float` 3D texture on Apple-silicon Macs is taken from Metal's feature
tables, not measured; the first build step renders a two-texel gradient
through it.)

**UI.** A **Look** section: a gallery of the 24 as thumbnails rendered
through the REAL compositor over the clip's frame at the playhead (never a
second renderer — Concat's FFmpeg-drawn cards are the defect), an Amount
slider, a Reset. Clip ▸ Look ▸ for a selection.

**Proof** (`e5_proof.py`): amount 0 byte-identical to no look; a grey ramp
through `silver` has R = G = B everywhere; each look at 1 differs from none;
an IDENTITY table (a test-only look behind `-RCLookIdentity`, the
`-ReelcutPreviewQuality` precedent) is within ±1 of no look on every 8-bit
value — trilinear filtering reproduces an affine table exactly in principle,
so the tolerance is argued from half-float storage and the sampler's
sub-texel precision, not from lattice points; `amount` 0.5 is the mean of 0
and 1 within ±1. **The unbound-site mutant is detectable only at the layer
and reflection sites**: the shadow-mask pass returns alpha alone and runs no
colour stage (:1315-1323), so an unbound texture there changes no pixel and
only Metal's validation layer — off in Release — would see it; the proof
says so rather than claiming a check it cannot make. The gallery's
thumbnails are real compositor output and are checked through a probe that
compiles the shaders (`phase8_chrome.py`'s route).

### E6 — Adjustment clips

**Adds:** Concat's Layer clip, done as a clip. Schema **v12** (a new
`Source` variant). ONE new op, `add_adjustment_clip` (`OP_NAMES` +1,
catalog +1).

**Schema and op.** `Source::Adjustment` — no media. `add_clip` cannot make
one (it takes a media id and chooses `Image` or `Media` from its kind,
`edit_clip.rs:426-440`), so the op is **`add_adjustment_clip {track: u32,
at: ticks, duration?: ticks = 5 s}`** in `add_shape_clip`'s shape
(`edit.rs:275-290`). An adjustment clip's `video.color`, `look`, POINT and
CLOCKED `filters` (not `vhs`), `mask` and `opacity` — its STRENGTH — apply to
everything already composited beneath it for its span. Its region frame is
the CANVAS with identity placement: the pixel-size reader answers the canvas
size, so the mask is in canvas pixels, and x, y, scale and rotation are
stored and not drawn.

**Where the refusals live.**
- **Filters, blend.** A gather or remap filter kind (framebuffer fetch reads
  one pixel) and a non-normal `blend` are refused by name in `check_group`,
  AND `clamp_video` (`actions.rs:343, 530`), whose `is_nest` flag becomes a
  source kind, strips them from an evaluated end patch — the two paths are
  the op and the file, as for blend on a nest (`edit_props.rs:216-224`).
- **Inside a nest.** Not in `refused_inside` — it classifies whole ops, and
  a paste inside a scope, a pasted payload's `nests` or a hand-written file
  would each get past it. `validate`'s nest-container check
  (`model_query.rs:303-306`) refuses a `Source::Adjustment` in any nest, and
  the merged parent of every scoped op is validated by `finish`
  (`scope.rs:280`), so every path meets it. A nest flattens into instances
  drawn straight onto the canvas, so an adjustment inside one would reach
  every layer below the nest, not the nest's own.
- **Mixed overlaps.** An overlap between an adjustment clip and any other
  kind is refused by the overlap rule: the outgoing dissolve's partner
  correction assumes a fixed-function incoming pass, and `partnerBox`
  answers nil for a sizeless source, so the media clip would fade to the
  backdrop instead. Two adjustment clips overlapping dissolve their
  strengths, whatever the kind.
- **Every `Source` match is classified.** Exhaustive ones that will not
  compile until answered: `model_query.rs:348`, `evaluate.rs:223-271` (no
  segment), `evaluate.rs:376-383` (`draws` → true), `recipe.rs:480-529` (a
  new recipe source kind), `edit_paste.rs:105-111`, `edit_props.rs:237-257`,
  `edit_background.rs:211-227`. Silent acceptors that compile unchanged and
  must be read: `source_head`/`source_length` (`None` — unbounded, like a
  shape), `add_zoom_action` (refuse: it writes a scale that is never drawn),
  `add_blurred_background` (already refuses a sizeless clip,
  `edit_background.rs:456-460`), `nest` (refuses, the validate rule).
- **The recipe nulls** an adjustment layer's shadow, reflection, spotlight,
  chroma and obscure, or `encodeShadow` (`Compositor.swift:881`) would draw a
  silhouette for a clip with no picture.

**Metal.** A new fragment entry, `reelcut_adjust_fragment`, drawn over a
full-canvas quad at the clip's place in the layer order with fixed-function
blending OFF. It reads the destination through `[[color(0)]]` — the blend
pipelines' programmable blending on the same `.bgra8Unorm` IOSurface target,
no copy, no ping-pong texture — and a shadow pass drawn earlier is already
in it: `DestinationPass.open()` resumes the pass with `.load` after a shadow
suspends it (`Compositor.swift:529-580`), so this was verified by reading and
needs no spike. It un-premultiplies (the canvas can be translucent — ProRes
4444 exports it), runs the colour stages factored out of
`layerColorPremultiplied` into a helper both entries call (the phase 6
refactor's shape, landed and gated alone), re-premultiplies, and mixes with
the destination by strength × mask coverage. The helper does not reference
`kGatherFilters`, so the adjust pipeline needs no specialization; its vertex
function supplies a canvas-spanning `local` for the vignette and the mask. It
is the fourth `texture(1)` site.

**UI.** Clip ▸ Add Adjustment Clip, placing on the front track over the
playhead for the selection's span or five seconds with the
`EditorViewController+AddClips.swift` fallback to a new track. No timeline
bar button: the bar's fixed content is 880 pt against a 900 pt minimum
window (892 with the meter's gap, `TimelineBar.swift:74-80`), so another
button breaks its constraints at the minimum size. The clip draws with its
own tint and symbol (`ClipKindStyle`), and the Clip tab shows Color, Light,
Look, Filters, Mask and a new **Strength** section (Opacity is a row inside
the Transform section, `VideoPane.swift:155`, not a section to rename).

**Proof** (`e6_proof.py`): an adjustment with `noir` over two cards on two
tracks turns both grey and a card ABOVE it is untouched; strength 0.5 is the
mean of 0 and 1 within ±1; its mask limits it to its canvas region; an
adjustment over a lone card is byte-identical to the same look set on the
card (the pass reads the right pixels); a shadowed card under an adjustment
has its shadow graded too; the refusals — a blur kind, `multiply`, an
adjustment inside a nest by `paste` under a scope, a mixed overlap — each by
name; an end patch carrying `blend: multiply` onto an adjustment draws
normal. Mutants: blending left on; the pass drawn at the front instead of at
its track; the `validate` nest rule removed; the `clamp_video` strip removed.

**Limits.** No blur, sharpen, pixelate, emboss, glow, fisheye or mirror on an
adjustment clip (each needs neighbours of the destination — a canvas copy,
a later phase if asked). No adjustment inside a nest, and no transition
between an adjustment clip and a picture.

### E7 — LUT import (its own decision, D3)

**Adds:** `.cube` files as looks. Schema **v13**. No op beyond
`import_media` (which learns the extension), no new tool.

**Schema.** `Media.kind` gains `lut`; `LookKind` gains `lut`, which requires
`look.media` naming a `lut` media (refused by name otherwise). A MISSING LUT
file skips the look — the clip draws ungraded — and the Look section and the
Media row both say which file is missing; it is not slated, because a slate
replaces a picture that is still there.

**A reference outside `source` is new to the model, and every path that
walks media references learns it** — none does today:
- `uses_media` (`edit_track.rs:67-73`), and so `remove_media`: a LUT used
  only by looks is USED, and removing it with `with_clips` CLEARS those
  looks rather than deleting their clips; Swift's `MediaUsage.swift:31-42`
  follows.
- `validate`'s reference check (`model_query.rs:348-361`) checks
  `look.media` exists and is a `lut`, so a broken document is refused on
  open rather than rendering an unknown texture.
- `paste` imports and renumbers media through `source` only
  (`edit_paste.rs:105-150`): it must renumber `look.media` too, and
  `paste_attributes` from a foreign payload must refuse a look naming media
  the project lacks.
- Every `MediaKind` match: the exhaustive ones (`edit_clip.rs:314, 433`,
  `edit_background.rs:348`) refuse a `lut` media by name in `add_clip`,
  `insert_clip`, `overwrite_clip` and `add_background` (`Err`, a caller
  mistake); the non-exhaustive ones (`edit_clip.rs:442`,
  `edit_background.rs:341`, `edit_track.rs:582`) are read and each given a
  stated answer; and `validate` refuses a `Source::Media` naming a LUT.
- **An action never interpolates `look.media`.** The generic merge would
  lerp and round it as an integer (`actions.rs:263-278`), naming some other
  media mid-action; `look` joins the discriminant rule so a differing
  `kind` OR `media` switches at the end and only `amount` interpolates.

**Swift.** `CubeLUT.swift` (new) parses a 3D `.cube` (`LUT_3D_SIZE` 2–65,
`DOMAIN_MIN`/`MAX` rescaled, 1D refused by name), uploads `rgba16Float`
into E5's `texture(1)`; `MediaImporter` accepts `.cube` without an
`AVURLAsset`; Consolidate copies it; the Media tab shows it with a LUT
glyph and "used by N clips". The Look gallery gains an Imported group.

**Proof.** An identity `.cube` written by the script is within ±1 of no
look; a channel-swap LUT swaps R and B exactly on the lattice values; a
LUT of size 2 and one of size 65 both load; a 1D file and `LUT_3D_SIZE 200`
refuse by name; relink to a different LUT changes the frame; Consolidate
carries it and the moved package still renders the look.

### E8 — Voice effects (D4)

**Adds:** pitch, tone, character and space effects on a clip's sound.
Schema **v14**. No op, no tool beyond a `set_audio` key. Written against
§5a's measurements; every rule below that looks arbitrary is one of them.

**Schema.** `audio.voice`: `null` or `{kind: VoiceKind, amount 0–1, pitch:
semitones −12…12}` — kinds `pitch`, `high`, `deep`, `robot`, `bass`,
`treble`, `bright`, `telephone`, `radio`, `lofi`, `distorted`, `echo`,
`room`, `hall`, `plate`, `cathedral`. One effect per clip. Each kind is a
FIXED chain of Apple units whose settings are Reelcut's own functions of
`amount` (and `pitch` for the three pitch kinds), never a user-built graph
(D1). What §5a says each is built from: the pitch kinds a `TimePitch`
(omitted at 0 semitones — it is never a clean passthrough) plus EQ; bass,
treble and bright EQ shelves; telephone an EQ band-pass (no preset
band-limits); radio a band-pass into the `speechRadioTower` distortion
preset; lo-fi a `multiDecimated` preset; robot a ring modulator set through
the distortion unit's parameter tree (14 of its 16 parameters exist only by
address, and no preset is a robot); distorted a distortion preset with makeup
gain; echo the delay unit; room, hall, plate and cathedral the reverb
presets (`mediumRoom` for room — `smallRoom` measured nearly dry).
`paste_attributes` carries `voice` with the audio group; `set_audio`'s MCP
decode is a hand-built `voicePatchArg`.

**The render — `VoiceRenderer.swift`** (new, `ReverseRenderer.swift`'s
shape, synchronous, off the main thread):
- **A clip WINDOW, not a whole media.** `TimePitch`'s output depends on the
  frame its render starts at (§5a q6 — a window render differs from a slice
  of a whole-file render by up to +0.34 dBFS), so a cached whole-media render
  cannot be sliced the way the reversed asset is. The unit of work is the
  clip's source window, from the reversed file when the clip is reversed.
- **Content-addressed cache.** `cache/voiced/<digest>.caf`, the digest over
  the media's `CacheStamp`, `reversed`, the window (`in` and length in source
  ticks), `kind`, `amount`, `pitch` and a CHAIN VERSION constant that also
  names the render contract below; the marker rule of `thumbs/` and `peaks/`
  (the file is written, then its marker). Two clips with one window share a
  file; a trim or a split renders the new windows (§5a q6: 50–270 ms for a
  10 s window, so Remove Silences' two dozen cuts cost a few seconds); files
  no clip names are swept on open.
- **The render contract — every line measured.** Connect at 48 kHz STEREO
  whatever the source (reverb aborts the process on mono input, an
  Objective-C exception Swift cannot catch); feed from an `AVAudioPlayerNode`
  (a source node changes distortion's tail); call in the order schedule →
  `engine.start()` → `play()` (the other orders render silence or start at a
  random offset); render in fixed 4,096-frame calls (distortion's output
  depends on the call size by up to +5.5 dBFS); load reverb presets through
  `auAudioUnit.currentPreset` (`loadFactoryPreset` is ignored before start
  and lands 43 ms late after it); set and clamp EVERY parameter explicitly
  (three units' header defaults are wrong and out-of-range writes read back
  unclamped; EQ bands start bypassed); remove a unit rather than setting wet
  to 0 (distortion at wet 0 is not dry). Write float CAF: distortion presets
  go over full scale, and the CAF round-trips the exact rendered floats.
- **Length and tails.** The rendered file is exactly the window's length
  (`TimePitch` is aligned to within a frame, §5a q4). A reverb's or echo's
  tail past the clip's end is CUT at the clip's end, where the clip's own
  fade-out applies — `tailTime` is no stopping rule (10 s for every reverb,
  66 s for a delay at feedback 90), and a tail that outlived its clip would
  need a timeline span nothing owns. Recorded as a limit, with "let it ring"
  left out.
- **Makeup gain.** Each kind's output is loudness-matched to its dry input:
  a per-kind constant measured at build over the speech fixture with
  `Loudness.swift`'s integrated measure, so switching a voice on does not
  jump the level by up to +19 dB.

**Playback.** `CompositionBuilder` substitutes the voiced file per CLIP,
exactly as it substitutes a reversed asset: the window's `[0, length)` where
the source's `[in, in + length)` would have gone, speed and `keep_pitch`
applied after. The tap's noise reduction, compressor, mono and pan run on the
voiced samples, and volume, fades, ducking and E1's crossfade after them.
While a render is pending the clip plays DRY — not silent: a person
adjusting an effect should keep hearing the clip — and the Voice section
says "Rendering…". `CompositionBuilder.swift` is AT 601 and pays its cut
first.

**UI.** A **Voice** section in the Audio group: a kind popup in four groups
(Voice · Tone · Character · Space), Amount, and Pitch for the three pitch
kinds. Clip ▸ Voice ▸ for a selection.

**First build steps** (§5a could not measure them): a `.mov` with several
audio tracks and a variable-rate recording through `AVAudioFile`; an
`AVComposition` playing a voiced CAF in place of the source with the tap on
it; one determinism row on the macOS 15 deployment target.

**Proof** (`e8_proof.py`, promoting the spike's `fx_common.swift` into a
probe): an export of a voiced clip decodes sample-for-sample equal to the
probe's direct render of the same window through the same contract on the
same machine (determinism is measured on one host; the proof never compares
across machines); a dry export byte-identical to the pre-phase binary; a
clip trimmed by one frame re-renders and the untouched clip beside it does
not (the cache key); a reversed clip renders from the reversed file; `pitch`
+12 on a 220 Hz tone measures 440 Hz within a cent; a pending render plays
the dry samples. Mutants: the call size changed; `loadFactoryPreset`
restored; a mono connection (detected as a process abort — a worse
detection than a failed row, and still a kill); the window left out of the
digest; `TimePitch` left in at 0.

**Limits.** Tails end with the clip. One voice effect per clip. Waveforms
and Remove Silences read the DRY media, so an echo does not fill a pause the
detector finds. Quality is unjudged by ear (§5a): robot's character and the
pitch shifter's artifacts need a person at the machine.

### E9 — Remove Background (D5)

**Adds:** cutting a person out of a picture without a green screen. Schema
**v15**. No op, no tool beyond a `set_video` key. Written against §5b.

**Schema.** `video.cutout`: `null` or `{subject: person | foreground,
feather 0–1}`.
- **`person`** — `VNGeneratePersonSegmentationRequest` at `.balanced`, a
  FRESH request per frame. Not `.fast`, which carries state from earlier
  frames (a reused request matched a fresh one on 5 of 600 masks), so a
  partial or random-access rebuild could never reproduce it; not
  `.accurate`, which runs at 1.7× realtime, stores 1.7 GiB per minute at
  native size and was no better on the portraits measured.
- **`foreground`** — `VNGenerateForegroundInstanceMaskRequest`, allowed on
  IMAGE and STILL sources only and refused by name on a media clip. On video
  it picks whatever is salient per frame — a monitor merging into the
  subject, up to 57 % of pixels flipping between masks 0.1 s apart on a slow
  push-in — which no cache can make steady; on a single picture it is the
  better request (the whole figure where person segmentation found part of
  an arm, or nothing, from behind).

**The analysis — `MediaImporter+Masks.swift`** (new):
- Requested by the first clip that asks, and only for the source windows
  clips with a cutout show (Concat's shape), at **10 masks per second of
  source**, written as 8-bit PNG at the request's native size (512×384 for
  `person`, 12–33 KB each — about 16 MB per minute on the film recording
  measured) under `cache/masks/<media id>-<subject>/`, with `CacheStamp`,
  the marker written last, the vouching rule of `thumbs/`, and the ledger.
  Decoding is `AVAssetReader` of the CODED buffer, so a mask is in the coded
  orientation.
- **Synchronous and grant-free**: the `VN*` classes' `perform` is
  synchronous (the newer Swift `perform(on:)` is `async`-only and is not
  used) and no TCC grant was requested. At ~5× realtime a minute of source
  takes ~12 s; an hour, ~12 min — a background pass with progress in the
  section, cancelled with the document.
- **The compute device is PINNED** (`setComputeDevice`, Neural Engine where
  present, else GPU) and written into the marker, because masks are
  byte-identical across processes on one device but differ across devices
  (up to 25 levels GPU against ANE on `.balanced`). **The marker never
  promises byte-identical REGENERATION**: a package opened on another Mac
  uses the masks it carries, and every proof compares a render against the
  CACHED mask, never against a recomputation.

**The "no subject" rule — the one that keeps a screencast.** Person
segmentation returns a mask for every frame, about zero on cards, text and
the app's own UI (0.00 % of pixels above 127 on all 600 masks of a
scrolling-UI recording), and foreground returns no observation at all.
Multiplied straight into alpha, that would erase a screencast. So the
decision is made per CLIP WINDOW, not per frame: when no mask in the window
has at least 0.5 % of its pixels above 127, the cutout draws NOTHING — the
clip renders uncut — and the section says "No person found". Per frame it
would flicker: a person leaving the shot would switch the background in and
out. Within a window that has a subject, every frame's mask is honoured, so
a person walking out of frame leaves an empty picture, which is what was
asked for. A screencast showing a film is cut down to the film's actors —
correct by the rule and surprising to a person; the section's note says
what was found.

**Metal.** The core emits `source_t` on a layer (it knows `in`, speed and
the reversed mirror); Swift binds the NEAREST mask as fragment `texture(2)`
(a 1×1 opaque placeholder; balanced masks move 0.16 levels per frame on a
static shot, so nearest-of-10-per-second does not visibly step, and a blend
of two would cost a third texture), sampled by NORMALISED coordinate — the
mask is 4:3 or square whatever the frame, stretched over it — at the SAME
coordinate as the picture: after the spotlight lens and pixelate snap, and
through `orientedUV(uv, quarterTurns, mirrored)` (`Compositor.metal:533-534`),
because the mask is built from the coded buffer. Feathered, and multiplied
into coverage at step 7 beside E3's mask, so shadow and reflection follow.
A frame whose mask is not computed yet draws UNCUT, never blank.
`partnerBox`'s guard adds cut-out partners (E3's list). Uniforms: a flag,
the feather and two spares, one group of four.

**UI.** A **Background** section beside Chroma Key: Remove (None / Person /
Foreground, the last enabled for pictures only), Feather, and the analysis's
progress and its finding.

**Proof** (`e9_proof.py` over MCP, `e9_probe.py`): the "no subject" rule on
a UI recording — cut and uncut byte-identical; a still of a person
(`/System/Library/Photos/Resources/FlexAudio/` and Adobe CEP's hero image
exist on this host and carry no personal data — the spike's fixtures) cut
with `foreground` makes the masked pixels transparent and the rest the
backdrop; registration through a crop, a spotlight zoom and a portrait
(rotated) source; a pending instant draws uncut; the cache survives a moved
package and a relink rebuilds it; `foreground` on a media clip refused by
name; two runs of the analysis write byte-identical PNGs on the proof
machine. Mutants: the window rule made per-frame; `orientedUV` skipped; the
device left unpinned; `.fast` substituted.

**Limits.** Person segmentation misses backlit, from-behind and small
figures (0–3.9 % where foreground found the whole figure, §5b). Mask quality
on real camera footage — hair, motion blur — is unmeasured and is a check
for a person at the machine. No brush refinement and no tracking of a
chosen subject (D5). An hour of source is about twelve minutes of analysis.

## 7. Order, dependencies and cost

| Phase | Depends on | Schema | Ops / tools | Shader | Risk |
|---|---|---|---|---|---|
| E1 transitions | road map 4's S1 landed (both touch `SilenceDetector`) | v7 | +2 / +2 | none (Swift directions) | low |
| E2 motion | — | v8 | 0 / 0 | none | low |
| E3 tone, flip, mask | E2's `model_picture.rs` toll | v9 | 0 / 0 | two groups of 12; the header toll | medium (the flip trap, the canvas mappings) |
| E4 filters + clock | E3's headers | v10 | 0 / 0 | spares, then a group of 4; gathers | medium (the 8 ms budget) |
| E5 looks | E3 | v11 | 0 / 0 | spares; `texture(1)` | medium |
| E6 adjustment | E5 (its `texture(1)`) | v12 | +1 / +1 | a new fragment entry | medium |
| E7 LUT import | E5 | v13 | 0 / 0 | none | low; D3 is the user's call |
| E8 voice | — (§5a) | v14 | 0 / 0 | none | medium (the render contract) |
| E9 cutout | E5's texture plumbing | v15 | 0 / 0 | a group of 4; `texture(2)` | per §5b |

After all nine: `OP_NAMES` 58, the catalog 78, `RC_FORMAT_VERSION` 15.
E1 and E2 carry most of the visible value and touch no shader; E8 is
independent of the picture phases and can run beside them. Uniform growth is
stated per phase as INCREMENTS and each phase spends the previous one's
spare floats before opening a group, because E5 can build before E4 and an
absolute byte count in a plan would then be wrong.

**Two costs every bump repeats.** The "one past the current version"
fixtures (`model_tests.rs:958, 970`, `schema_v3.rs:118-122`, message text
included) become CURRENT files the moment the version moves, which
core/CLAUDE.md records as a trap — each phase moves them. And each bump owes
`format.rs` a paragraph in its own words. Seven bumps in one road map is a
lot of both; a build that lands two adjacent phases together may share one
version, and the paragraph then argues both keys.

---

## 8. Found in Concat, not designed here — and why

- **An effect package runtime, user WGSL, a Transition / Effect / Voice
  Mixer, a registry.** D1; spec §1's plugin non-goal.
- **Echo / trails / true motion blur.** No previous frame (§3); D6.
- **Speed-curve presets (Montage, Bullet…).** `speed` is not an action
  target; road map 2 §4 "feasible, not asked for" still describes it, and
  it is a retiming feature rather than an effect. The natural next road map
  item if asked.
- **Bézier keyframe eases.** Actions' four curves cover the transitions and
  motion presets here; a graph editor is a grading-suite-class UI.
- **Non-uniform stretch** (`stretch_x/y`). A transform feature, not an
  effect; small, and unasked.
- **Smart-brush mask refinement (SAM) and subject tracking.** A model the
  app would ship (D5).
- **De-ess and "Enhance Voice".** No Apple unit de-esses; the compressor and
  noise reduction exist.
- **Face blur, scene detection, black-frame detection.** Prototypes in
  Concat; face-tracked obscure regions would be a Vision phase of their own.
- **Nine text style presets and caption styles.** Text presets, not effects;
  Reelcut has four and text animations Concat lacks.

## 9. Licence and provenance

Concat is AGPL-3.0-or-later. This document was written from four read-only
reports that describe Concat's behaviour in their own words, and every
phase above specifies Reelcut's own formulas, tables and names. A builder
must not open Concat's `effect.wgsl`, `effect.toml` chains, colour matrices
or curve tables to "match" a look, and must not import any of its assets;
where a phase says "Concat's" it means the feature a person sees, never its
implementation. Concat's Person matting model (Robust Video Matting) is
GPL-3.0, which is one more reason E9 uses Vision.

## 10. The review, before anyone trusted the plan

Two read-only reviewers read the first draft against the tree on the day it
was written, one over the core and model claims (E1, E2, E6, E7, §3, §7) and
one over the rendering and Swift claims (E1, E3–E6, E9, the uniform
arithmetic). Between them: **3 blockers, 16 wrong claims, 28 gaps, 11
nits** — 58 findings, every one folded into the phases above. The ones that changed a design
rather than a sentence:

- **E6 needed an op.** `add_clip` takes a media id; an adjustment clip has
  none. `add_adjustment_clip` exists because of that.
- **`set_transition` cannot carry style.** Its absent `kind` clears, and an
  op cannot tell absent from null — hence `set_transition_style`.
- **A nest has no head handle**, so `add_transition` pulling one back would
  have shifted a nest's whole contents; the helpers' `None` reads as "no
  limit" and would have hidden it.
- **The crossfade law.** The draft argued equal gain from "two cuts of one
  recording"; the overlap a transition is added at is two DIFFERENT moments,
  which is constant power's case. The draft's term also sat where it could
  not see nests and would have left the outgoing clip's last sample at full
  gain.
- **Split, freeze and the blurred backdrop would have copied motion** — one
  Remove Silences pass turning a fade-in into twenty-four — and
  `text.animation` has had the split half of that since phase 4.
- **The fast path's gate** is a sum of non-negative terms; signed tone fields
  summing to zero would have skipped the stage.
- **The canvas-space wipe** would have mended a different-size pair and
  broken the common same-size one, so it was withdrawn.
- **Flip** needed a named pivot, an order against rotation, a reflection arm
  and four Swift canvas mappings the draft never mentioned.
- **`mirror` as a coordinate remap** could not cross-fade and would have
  copied an obscured password into plain view (D7).
- **A shader split into sibling `.metal` files** would have left two proof
  probes compiling one file and caching on its mtime — measuring a stale
  shader and passing.
- **A LUT referenced from `look.media`** is the first media reference outside
  `source`, and usage, removal, validation, paste and action interpolation all
  walk `source` alone.

The spikes overturned two more. §5a: E8's whole-media voice cache, because
the pitch shifter's output depends on where its render starts. §5b: E9's
foreground subject on VIDEO, which flickers up to 57 % of its pixels
between masks a tenth of a second apart — it survives for pictures only —
and the draft had no rule at all for a frame with nobody in it, which on
this app's main material would have erased the screencast.
