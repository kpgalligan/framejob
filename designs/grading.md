# Road map "grading" — colour grading, tier 1, as an experiment on a branch

**Opened 2026-10-09** (GR0, on main). The design brief this road map answers is
`~/.claude/litecode/reelcut/grading/I-grading.md` (2026-10-09, tree `7ef96c5`);
it lives outside the repo, so everything a later phase needs from it is
written here. Where the brief and this file differ, this file wins: the brief
was written before the precision road map closed (`3cc61e7`,
`designs/adr/precision.md`, spec §11 PR-1..PR-5) and before `LayerUniforms`
left `Compositor.swift` (`7b80810`).

## Goal

Find out whether colour grading is worth having in Reelcut, by building tier 1
on a branch and letting the owner try it on his own footage against criteria
agreed before any code. Tier 1 is: tone, adjustment clips, looks and `.cube`
LUT import, plus a way to SEE the grade (a before/after switch and one luma
waveform). The issues it answers are #118 (E3), #120 (E5), #121 (E6) and #122
(E7), all `icebox`, all filed 2026-09-26 from the effects survey
(`designs/adr/effects-survey.md`), each quoting the owner on 2026-09-15: "we'll
eventually add color grading and LUT import, but not now".

## The owner's choices

**2026-10-09**, verbatim: "Start grading", and then "All as recommended" — to
the brief's choices 1b, 2c, 4b, 5b, 6a, 7, 8 and 9. Choice 3 (8-bit pixels for
tier 1) was settled by the precision road map instead: the compositor is
`rgba16Float` end to end and every video source decodes to `64RGBAHalf` (spec
§11 PR-1, PR-2). The choices therefore read:

1. **(b)** Tier 1 is tone, adjustment clips, looks and LUT import. Flip and the
   shape mask leave the experiment.
2. **(c)** Seeing comes into tier 1: a before/after switch (View ▸ Show
   Ungraded, preview only) and one scope, a luma waveform with marks where
   highlights and shadows clip, in a panel beside the preview.
3. Settled by precision: grading runs on PR-1's float pipeline (below).
4. **(b)** A new **Color** sub-tab beside Picture: today's Color section moves
   there, and Light (tone) and Look join it. An adjustment clip shows only
   Color and Clip.
5. **(b)** About eight built-in looks, Reelcut's own, built from the same
   building blocks as the tone controls and tuned by the owner by eye; LUT
   import is how a person gets more.
6. **(a)** An imported LUT is media, like a video file: in the Media tab,
   referenced where it lies, relinked and consolidated like footage.
7. **Yes** to the adjustment-clip rule: an adjustment clip changes everything
   drawn BEHIND it in its own container, on every track. Its strength is its
   opacity (animatable). On a track cut by a matte it grades only inside the
   matte. It is refused inside a nest and as either half of a transition (fade
   it with opacity instead), and it refuses the blur, sharpen and pixelate
   filters and any blend mode.
8. **Yes** to the branch plan (below).
9. **Yes** to agreeing "worth keeping" now, before code (below).

## Tier 1 as answered — keep, cut, reorder

**Four things, not six.** Tier 1 is tone, adjustment clips, looks and LUT
import, plus seeing, moved up from tier 2.

- **Keep tone (E3's first third), first.** It is the most-used grading control
  on camera footage (white balance and exposure), and the looks reuse its
  building blocks. No new op: `video.color` gains `exposure` (±3 EV),
  `temperature`, `tint`, `highlights`, `shadows`, `whites`, `blacks`,
  `vibrance` (−1…1) and `fade` (0…1), through `set_video`.
- **Cut flip** from the experiment. It touches `CanvasLayerBox.sourcePoint` /
  `canvasPoint`, the crop handles, the line and arrow endpoint handles,
  `RecipeLayer.videoProps` / `uncropped`, the reflection and `edit_zoom.rs`'s
  pan direction (#118), and none of that is about colour. It is a reasonable
  small feature on main whenever it is wanted.
- **Cut the shape mask.** Mattes shipped after E3 was designed (MT-1..MT-9): a
  rectangle, ellipse or gradient on a matte track does its job over any clip,
  and over an adjustment clip it limits the grade to the shape — a "power
  window", a tier-2 idea that falls out of tier 1 for free. What the mask would
  add is convenience. If the two-clip way proves clumsy in the trial (task T6),
  it is the first thing to add back, multiplying at the same step 7 as the
  matte and sharing the inspector's words.
- **Adjustment clips before looks.** E6 needs only the destination read, not
  E5's texture, when it applies tone alone; looks then apply to clips and
  adjustment clips in one phase. This order lets the owner try "grade the whole
  video once" with tone alone, the likeliest reason the experiment is kept.
- **LUT import last**, after looks have built the 3D-texture slot it needs.
- **Bring one scope forward**, right after tone.
- **E4 (thirteen filters), E8 (voice), E9 (background removal)** stay out of
  the experiment; none is grading.

What changed in the tree since the four issues were written (re-read at
`3cc61e7`):

| The issues say | The tree |
|---|---|
| `RC_FORMAT_VERSION` is 10; the first phase is v11 | **14** (`core/src/format.rs:211`); the branch takes its own number (GR-9, below) |
| Looks take `texture(1)`, the cutout `texture(2)` | **`texture(1)` is the matte coverage** (MT-6), a 1×1 white placeholder on every unmatted draw. The look takes `texture(2)`; E9's cutout would take `texture(3)` |
| `Compositor.metal` is 1,548 lines | **1,691**; many instruments under `tools/proof/` name it and several compile it alone or copy it, so an `#include` split needs one helper that builds the shader for all of them |
| `LayerUniforms` is 416 bytes, asserted at `phase8_chrome.py:3259` | Still 104 floats, 416 bytes, now in `app/Sources/LayerUniforms.swift`; asserted at `tools/proof/phase8_chrome.py:3240-3246`, `tools/proof/matte_spike/bench.swift:73` and `tools/proof/grading_spike/bench.swift` (GR0). Growing the block fails all three, and a historical instrument's failure is scored, never skipped |
| E3's mask is how to cut a layer to a shape | Mattes shipped |
| D2 proposes "still OUT: wheels, curves, qualifiers, scopes, … linear light" | The owner's 2026-10-01 plan puts those in tiers 2 and 3. D2 is not recorded as written: GR-1 says they wait for the experiment's verdict |
| Everything between layers is 8-bit | **16-bit float** (PR-1), and sources decode deep (PR-2) |

## How it fits the tree

**Colour per clip today.** `VideoProps.color: ColorAdjust {brightness,
contrast, saturation, hue}`, all offsets from neutral (`core/src/model_props.rs`);
`chroma`; `filters` (at most `MAX_FILTERS` = 4, a shader budget) of seven
`FilterKind`s. The op is `set_video {clips, patch}`, `patch` an Object, so a new
key under `video` costs no op-table row; the MCP tool's prose names the keys
(`AgentCatalog+Clips.swift`). Actions already animate it: numbers interpolate,
strings switch at the end, lists per index (spec §5.4), so
`video.color.exposure` and `video.look.amount` animate for free and
`video.look.kind` switches. The Picture sub-tab's sections are Transform, Crop,
Corner Radius, Color, Chroma Key, Shadow, Filters, Reflection, Spotlight,
Obscure (`ClipPane.swift`); Color is `VideoPane.colorSection()`.

**The shader.** `gradeSample` (`Compositor.metal:514`) does the chroma key, then
brightness, contrast, saturation and hue on STRAIGHT colour, for the centre
sample and for every blur tap. The order of operations is written above
`layerColorPremultiplied` (`Compositor.metal:872-893`): remap, pixelate,
sample-and-grade, blur/sharpen, obscure (4b), point filters (5), spotlight dim
(6), coverage = corner × nest rectangle × matte (7), transition weight,
opacity, premultiply, blend. The fast-path gate is one sum of non-negative
uniforms (`Compositor.metal:1019-1021`).

**Where tone and looks go.**
- **Tone at a new step 4c**, after the obscure regions and before the point
  filters: once per pixel, not per blur tap; obscured content is toned like the
  picture around it; sepia and noir act on the toned colour. (If GR0's route is
  "always on", GR2's design moves the always-on stage back before step 5; the
  spike times it before step 7b, see GR0.)
- **The look at 4d**, right after tone: `mix(c, lut(c), amount)`. A look is
  colour only.
- **Exposure and white balance in linear light, locally.** The compositor
  blends in encoded sRGB on purpose (spec §7.5: "if linear light is ever wanted
  it is a decision for the WHOLE pipeline"), and that stands. But exposure in
  EV means "twice the light", a multiply on LINEAR values. Decoding to linear
  (IEC 61966-2-1), applying exposure and the white-balance gains and
  re-encoding INSIDE step 4c changes no blend and no other stage, the same way
  `hueRotate` is a local colour transform. It is written into GR-2 so nobody
  reads it as the §7.5 change. GR0 prices it (T2's linear step).
- **Highlights, shadows, whites, blacks, vibrance, fade** stay in encoded
  space: they are curve and saturation shapes, defined by Reelcut's own numbers.
- **The route for an UNGRADED layer is GR0's question.** The tree has learned
  twice that code a layer never runs can still cost it: the gather loops cost
  every layer about 0.05 ms until compiled out (`kGatherFilters`,
  `Compositor.metal:110-133`), and the matte placeholder costs every unmatted
  full-bleed layer 0.054 ms at 4K (`designs/adr/mattes.md`). Three routes: a
  uniform flag (`toneEnabled`, as E3 planned), a function constant (doubling the
  layer pipelines again), or tone and look always on at neutral values (no
  branch; every layer pays the arithmetic).

**Precision: PR-1's float pipeline, replacing the brief's "8-bit pipeline".**
- The working depth is `rgba16Float` (`MetalRenderer.workingFormat`, PR-1):
  every layer, blend, shadow and dissolve pipeline's attachment, the
  destination, each matte composite and dissolve half. The coverage stays
  `r8Unorm`.
- Every video source decodes to `64RGBAHalf` (`Compositor.sourcePixelFormat`,
  PR-2), clamped to 0…1 where the shader samples it.
- So stacked grades — an adjustment clip over a graded clip, two adjustment
  clips — keep their levels by construction: nothing between layers is rounded
  to 8 bits. The brief's scratch C4 (−1 EV then +1 EV through a `bgra8Unorm`
  intermediate kept 129 of 256 grey levels, through `rgba16Float` all 256) is
  re-measured on the tree's shader by GR0's P1.
- **The dither fallback falls away**, and so does GR-3 as the brief worded it.
  GR-3 becomes: **grading runs on PR-1's float pipeline; blending stays encoded
  (§7.5).**
- **A 3D LUT's own precision is not the problem.** The brief's scratch
  measurements (a scratch shader, not the compositor; not re-run): an identity
  lattice of 2³, 17³, 33³ or 65³ in `rgba16Float` through the linear sampler
  returned every one of the 16,777,216 8-bit colours exactly (C1, C2); a baked
  smooth look against the same look per pixel differed by at most 5 levels at
  17³, 3 at 33³ and 1 at 65³ (C3).
- **Log footage.** A camera's log-to-Rec. 709 LUT expects the file's encoded
  code values, which is what the compositor sees if AVFoundation passes them
  through untouched, so such a LUT should look right in SHAPE; its limit is
  precision, not shape. Whether AVFoundation converts Apple Log or HLG-tagged
  files before the compositor is not established (below).

**Textures.** `texture(0)` the source, `texture(1)` the matte coverage (MT-6),
**`texture(2)` the look**, and E9's cutout would take `texture(3)`.

**Mattes and nests.**
- Tone and looks on a matte clip shape the matte, by MT-4: a luma matte with
  exposure pushed opens a wider window. Nothing to build; one proof row.
- An adjustment clip on a MATTED track: the adjustment fragment multiplies its
  mix weight by the coverage at `texture(1)`, as every layer's step 7 does. The
  grade applies only inside the matte — the power window, for one multiply.
- An adjustment clip ON a matte track grades the matte group's own earlier
  members (MT-1 draws them into the group's target). Allowed with that meaning
  rather than refused in `move_clip`, `set_track {matte}` and paste.
- An adjustment clip inside a nest is refused (in `validate`, and in `nest`
  when the selection holds one): nests are flattened (spec §7.3), so it would
  also grade the layers behind the nest clip on the outer timeline. MT-8's
  routed-dissolve targets are the start of drawing a group alone.
- An adjustment clip over a nest clip grades the nest's flattened layers with
  everything else behind it. Correct as is.
- Transitions on adjustment clips are refused: a dissolve's outgoing half
  divides its weight by the incoming pass's fixed-function attenuation, and an
  adjustment pass has no picture of its own to weigh. Fades are opacity
  actions.

**Preview, `render_frame` and export agree by construction**, through one
recipe and one compositor (spec §7.3, §7.5). Two things need care: the "show
ungraded" switch is a recipe option set only on the preview's key and taken by
`render_frame` as a parameter (as `burn_in_timecode` is), never an export
override; and the waveform reads the composited preview frame at Preview
Quality's size and never touches an export.

**The Rust/Swift split.** Core: every key, range and refusal; `LookKind` and
each look's definition as data; the adjustment clip as a `Source` variant and
its op; the `.cube` parser (text in, a size and floats out, or a refusal); the
`ungraded` recipe option. FFI: one export for the parse, returning a float
buffer (three files in lockstep). Swift and Metal: the 3D textures and their
LRU; baking built-in looks by running the SAME Metal functions the tone stage
uses over a lattice; the tone and look stages; the adjustment pass; the
scope's compute pass and view. Rejected: baking looks from Core Image's photo
effects (not Reelcut's own, and able to change with a macOS update, against
R5-5's spirit).

## The standard recipe, file by file

Counts are `wc -l` at `3cc61e7`. The cap is ~600 lines, new files 400, frozen
files wiring only. `Compositor.metal` (1,691) is not on the ledger, so a shader
split is a choice, not a toll.

**Core.**

| Step | Files | Note |
|---|---|---|
| Fields | `model_props.rs` (471): `ColorAdjust` gains the tone fields; `VideoProps.look: Option<Look>`. A new `model_look.rs` for `LookKind` and `Look`, re-exported (the `model_matte.rs` pattern). `model.rs` (532): `Source::Adjustment`, `MediaKind::Lut`. | Serde defaults; written only when not default. |
| Format | `format.rs` (419): the version and its paragraph; a `schema_vN.rs`; the header's `#define`. | The branch's number is GR-9's. |
| Checks | `props_check.rs` (485): ranges. `edit_props.rs` (417): adjustment refusals (gather filters, blend), `clamp_video`. | Refusals in the rule's own sentence. |
| Ops | New `edit_adjustment.rs`: `add_adjustment_clip`. `edit.rs` (exempt): its enum row and doc-table line. `op_table.rs` (348): its arguments. | `edit_clip.rs` (755) is over the cap with no seam named, so the op does not go there. |
| `Source` classification | 92 `Source::` sites across 26 core files (`grep -c 'Source::' core/src/*.rs`). `evaluate.rs` is at **590**. | **Paid in GR1:** the composition plan out to `plan.rs` (590 → 381), because GR4's `Source::Adjustment` edits both of its exhaustive `Source` matches. |
| LUT media | `edit_track.rs` (534): `uses_media`, `remove_media`; the 11 `MediaKind::` sites (`edit_clip.rs` 7, `edit_background.rs` 3, `edit_track.rs` 1); `validate`; `edit_paste.rs` (468), `edit_paste_attributes.rs` (306); `actions.rs`: `look.media` switches. New `cube.rs` (the parser) and an `ffi_*.rs` export. | |
| Recipe | `recipe_layer.rs` (102): `look` and the tone fields, always present; `recipe.rs` (521): the adjustment layer's role and the `ungraded` option. | |
| Tests | New `core/tests/tone.rs`, `adjustment.rs`, `look.rs`, `cube.rs`. | |

**Swift and Metal.**

| Step | Files | Toll first? |
|---|---|---|
| Snapshot | `ProjectSnapshot.swift` (**1,871**): `ColorAdjust`, `VideoProps`, `ClipSource`, `MediaKind`. | **Paid in GR1:** the composition plan out whole to `CompositionPlan.swift` (1,871 → 1,750). New grading types in a new `GradeProps.swift`. |
| Recipe decode | `FrameRecipe.swift` (365). | No. |
| Uniforms | `LayerUniforms.swift` (267; out of `Compositor.swift`, now 724, in `7b80810`). A tone group (12 floats) and a look group (4) take it from 104 to 120 floats, 480 bytes. | **No longer a toll** (paid). The three 416 assertions above move in the same change. |
| Fill and bind | `Compositor+Uniforms.swift` (152), `CompositorEffects.swift` (430), `Compositor+Dissolve.swift` (190, `drawLayer`: binds `texture(2)`). New `LookTextures.swift` (the 3D textures, the LRU, the bake). | No. |
| Shader | `Compositor.metal`: steps 4c and 4d by GR0's route; `reelcut_adjust_fragment`, the eighth pipeline; the LUT at `texture(2)` with a placeholder. | A split into headers is optional; if made, one helper builds the shader for every instrument and lands on main first. |
| Inspector | A seventh `ClipSubTab` case, `color` (`ClipPinnedBlock.swift`, 235); `ClipPane.makeSections()` (`ClipPane.swift`, 221) registers its sections (an unregistered section is invisible); `VideoPane.swift` (**959**) holds `colorSection`. New `VideoPane+Light.swift`, `VideoPane+Look.swift`. | **Paid in GR1 for `VideoPane.swift`:** `colorSection` to `VideoPane+Color.swift` (959 → 904), pure, before Light joins it. |
| Typed builders | `ReelOps.swift` (exempt): `addAdjustmentClip`; `OpDictionaries.swift` (109). | No. |
| Menus | `AppDelegate+Menus.swift` (579): Clip ▸ Look ▸; Insert ▸ Adjustment Clip (Insert is `AppDelegate+GraphicMenu.swift`'s); View ▸ Show Ungraded, View ▸ Waveform. | **Paid in GR1:** the Clip menu's submenu builders out to `AppDelegate+ClipMenus.swift` (579 → 494). The menu inventory gains rows. |
| Timeline | `ClipKindStyle.swift`: the adjustment clip's body. `TimelineView.swift` is frozen: wiring only. | No. |
| MCP | `AgentCatalog+Clips.swift` (**706**): `set_video`'s prose gains the keys; `AgentServer+Clips.swift` (**636**). New `AgentServer+Grading.swift` and a catalog entry for `add_adjustment_clip`; `import_media` accepts `.cube`; `render_frame {ungraded}` (`AgentServer+Render.swift`, 545). | **Paid in GR1 for `AgentCatalog+Clips.swift`:** the property rows and their vocabularies together, to `AgentCatalog+Properties.swift` (706 → 513). The root `CLAUDE.md`'s "eighty-nine product tools" becomes ninety then. |
| Import | `MediaImporter.swift` (591): `.cube` in a new `MediaImporter+LUT.swift`. `MediaConsolidator.swift` (321), `MediaRowView.swift` (520): the LUT glyph and "used by N clips". `CompositionBuilder.swift` (536): a LUT media is never an asset. | The `MediaKind`-shaped Swift sites each classified. |
| Scope | New `ScopeView.swift` and a compute pass run only while the panel is open. | No. |

**Documents, each phase's own:** spec §1 (the non-goal line and "scopes"),
§4.3a, §4.4, §5.2, §5.4, §6b, §7.3, §7.5, §7.7, §7.9a, §9; `app/CLAUDE.md` and
`core/CLAUDE.md` map entries; the README's feature bullets;
`docs/manual-checks.md` rows; the screen catalog (a Color sub-tab screen and
an adjustment clip).

## The Concat rule

**Concat (`~/devel/Concat`) is AGPL-3.0-or-later. None of its code, shaders,
chains or colour tables may be carried over** (root `CLAUDE.md`;
`designs/adr/effects-survey.md` "Licensing"). That covers design time and build
time: no colour matrix, curve table, LUT data or asset, and a builder must not
open its files to "match" a look. Instead:
- **Built-in looks are Reelcut's own,** each a short list of Reelcut's own
  building blocks (white balance, a tone curve, split tone, saturation and
  vibrance, a lifted black) with numbers chosen against Reelcut's own fixtures
  and tuned by the owner by eye. Generic names. Their definitions live in the
  core as data.
- **Imported LUTs are the person's own files.** Reelcut ships none, and bundles
  no third-party pack, free or not.
- **Not baked from Core Image's photo effects.**
- **Test LUTs are written by the proof scripts:** identity, a channel swap,
  size-2 and size-65 lattices, a 1D file and a `LUT_3D_SIZE 200` file to refuse.
- **The maths is textbook,** not anyone's code: trilinear lattice sampling, the
  sRGB transfer functions (IEC 61966-2-1), Rec. 709 luma weights, the `.cube`
  text format (`TITLE`, `LUT_3D_SIZE`, `DOMAIN_MIN` / `DOMAIN_MAX`, red varying
  fastest). GR0's spike follows the same rule: its tone arithmetic and its look
  are written from those formulas only.

## Spec §11: the plan, GR-1..GR-9

Recorded **on the branch in GR2**, before the code that needs them, in a new
`designs/spec/11-decisions/grading.md` with README rows. Not now: GR0 records
no §11 entry.

**Stands, and the entries say so:** R5-1 (closed vocabularies, never a runtime —
an imported LUT is DATA, a table the one compositor applies through one fixed
operation); G-1; R5-5 (looks are baked from their definitions, never from the
clock or the OS); the encoded-sRGB blend (§7.5); MT-1..MT-9 (MT-6's "104
floats" described the matte's route; the block growing is a new decision's
consequence and the entry names MT-6); "media by reference"; G-35.

**Amended:** spec §1's non-goal "color grading beyond per-clip controls" and the
bar sentence's "scopes", explicitly by GR-1; road map 2 §4's "LUTs (`.cube`)"
exclusion, archived, reversed by the same entry.

- **GR-1** — The grading experiment: tier 1 IN on the branch (tone, adjustment
  clips, looks, LUT import, the ungraded switch, one waveform); flip and the
  shape mask out of it; tiers 2 and 3 wait for the verdict rather than being
  out; amends spec §1. (In place of the survey's D2 and D3, not recorded as
  written.)
- **GR-2** — Tone: the keys, ranges and neutral values; step 4c; exposure and
  white balance in local linear light; the ungraded-layer route GR0 chose.
- **GR-3** — Precision: grading runs on PR-1's float pipeline; blending stays
  encoded (§7.5).
- **GR-4** — The ungraded option: preview and `render_frame` only, never an
  export.
- **GR-5** — The waveform: what it reads (the composited preview frame) and
  what it is not (no export path).
- **GR-6** — Adjustment clips: everything behind, in its container, on every
  track; strength = opacity; inside the matte when matted; allowed on a matte
  track with that meaning; refused in a nest and in any transition; the refused
  filters and blend.
- **GR-7** — Looks: a closed `LookKind`, defined in the core as data, baked on
  the GPU with the tone stage's own functions into a 33³ `rgba16Float` lattice,
  mixed at 4d by `amount`; Reelcut's own numbers; the Concat rule restated.
- **GR-8** — LUTs are media of kind `lut`, parsed by the core, applied to
  encoded values; sizes 2–65; 1D and larger refused by name; a missing file
  draws ungraded; R5-1 stands.
- **GR-9** — The branch's format number and the merge's migration.

E3's D7 (nothing moves content out from under an obscure region) is not
needed: with flip cut, nothing in tier 1 moves pixels.

## The branch plan

**The worktree.** `git worktree add ~/devel/reelcut-grading -b grading main`,
outside the repo folder and outside `.claude/worktrees/` (which other sessions
own), cut in GR2. The main tree's branch is never switched. Road map 14 was
built this way.

**Per worktree:** `core/target/` (a cold Rust build on the first `make`),
`build/` (Xcode products and the gate's stamps), `tools/proof/work/`,
`Reelcut.xcodeproj`. **Shared:** the git objects and refs; the Debug app's
identity `com.kgalligan.Reelcut.debug` and its defaults domain, and the Release
app's `com.kgalligan.Reelcut` (spec §11 V-5). The owner trying the branch's
Release build shares his preferences with main's build, which is harmless, and
should launch it from its path, not by name.

**The project-file number.** The branch's `RC_FORMAT_VERSION` is **1015**
(main's 14 plus a thousand), so every main build refuses a branch-made project
by name ("made by a newer Reelcut") instead of opening it, dropping its grades
and writing the loss back on the next save. At the merge it is renumbered to
main's next, with one migration arm mapping 1015 to it, so branch-made
projects still open. The owner keeps his trial projects as copies anyway.

**Main's later fixes reach the branch** by `git merge main` at the START of
each phase (never a rebase: records cite hashes), then `make gate` there before
the phase's code. **Every pure move the branch needs lands on MAIN first**
(GR1). Expected conflicts are mechanical: the spec README's Lines cells and
`11-decisions/README.md`'s rows, `CLAUDE.md` map entries, the format constant.
The `GR-` prefix keeps §11 IDs from colliding.

**At the end.** Kept: merge `grading` into main through a throwaway worktree
and a fast-forward, renumbering the format. Dropped: condense this road map
into `designs/adr/` on main with what was learned, archive it, keep the branch
unmerged for reference, and re-ice or close the issues with the reason.

## "Worth keeping": the experiment's yes or no

Agreed before code (choice 9), verbatim from the brief §7. The verdict is the
owner's; the numbers are what he decides with.

### What the owner tries (GR7, on his own footage, the branch's Release build)

| # | Task | Done when |
|---|---|---|
| T1 | Fix one camera clip that is too warm and too dark. | Done with Light alone in under two minutes, looking right to him on the waveform and by eye. |
| T2 | Grade a whole video once: every camera clip in a real project. | One adjustment clip over the camera track does it, and trimming or moving clips under it needs no re-grade. |
| T3 | Give a video a look. | He picks a built-in look and sets its amount, and would use one of the eight again. |
| T4 | Use a LUT he already has (a camera maker's or a bought one). | It imports and applies, and matches the same LUT in another app on the same frame within ±2 levels (one fixture frame, measured by script), or the record names why not. |
| T5 | Ask the Assistant: "make the camera clips warmer and a bit brighter". | It does it through the tools, each op one undo step. |
| T6 | A power window: brighten a face inside an ellipse. | Done with a shape on a matte track over an adjustment clip, without being shown how. If he needs showing, the mask comes back (section 1). |

### What it may cost (checked by script at GR7)

| Measure | Cap | Measured (GR7a) |
|---|---|---|
| Frozen files | Wiring only; no frozen file grows by more than ~50 lines in total | `EditorViewController.swift` 1,139 → 1,142 (+3); the other four net 0: held. (L2) |
| Files over the cap | None left unpaid | Held after the L3 payment (6f68daa): `ProjectSnapshot.swift` 1,750 → 1,570, `edit_clip.rs` 755 → 661, both paid by pure moves. GR7a had measured them at 1,769 and 757. (`grading_verdict.py sizes` L3) |
| Inspector | One new sub-tab (Color) of at most four sections; Picture loses one section (Color) and gains none | Color added, 4 sections (Light, Color, Adjustment, Look); Picture lost Color and gained none: held. (L4) |
| Menus | Clip ▸ Look ▸, Insert ▸ Adjustment Clip, View ▸ Show Ungraded, View ▸ Waveform; nothing else | 175 → 187 leaves: Clip ▸ Look ▸ (9: the eight and None), Insert ▸ Adjustment Clip, View ▸ Show Ungraded, View ▸ Waveform; none removed: held. (`measure` M1) |
| An UNGRADED layer | At most +0.02 ms at 1080p and +0.06 ms at 4K over main, by the matte spike's method (the placeholder's 0.054 ms at 4K is the precedent) | +0.009 ms at 1080p, +0.002 ms at 4K (C0 noise 0.000 at both): held. (`grading_spike.py --measure --tree` TC) |
| An ungraded project's export | Within 2 % of main's time on one fixture, three runs | +0.33 % (medians 6.00 s against main's 5.98 s, 60 s at 1080p): held. (`measure` E1) |
| A graded frame | Four graded full-frame layers and one adjustment clip at 1080p within the 8 ms budget; a graded 60 s 1080p fixture exports at most 10 % slower than ungraded | 2.724 ms median compositor average (worst window 7.07–7.70 ms): held; graded export −0.17 % against ungraded (5.99 s against 6.00 s): held. (`measure` F4, E2) |

Each figure's command, host, power and load are in the GR7a record below.

Kept if T1–T5 succeed, the owner says he would reach for it again, and every
cap holds. A missed cap is a conversation, not an automatic no: the record says
which cap and by how much.

("Section 1" and "section 9" are the brief's: section 1 is "Tier 1 as answered"
above, section 9 the brief's cost figures, quoted under GR0.)

### The owner's trial guide (GR7)

**The build.** The branch's Release build is
`/Users/kevingalligan/devel/reelcut-grading/build/Build/Products/Release/Reelcut.app`.
Quit every other Reelcut first — main's Release build has the same identity
(`com.kgalligan.Reelcut`) and the same preferences — then open this one BY PATH:
from the Finder, or `open /Users/kevingalligan/devel/reelcut-grading/build/Build/Products/Release/Reelcut.app`,
never by name.

**Work only on COPIES of projects.** A save on the branch writes format 1015,
which every main build refuses to open. Duplicate a `.reelcut` package in the
Finder and open the copy; keep the original for main.

**In the same sitting**, run GRD-1…GRD-6 (`docs/manual-checks.md`, "Grading").

- **T1 — a warm, dark clip.** Open a copy of a project with a camera clip that
  is too warm and too dark; open View ▸ Waveform (⌃⌘W). Select the clip and, on
  the Clip tab's Color sub-tab, use Light alone (Exposure, Temperature, Tint,
  then Highlights … Fade if you want them) until it looks right on the waveform
  and by eye; flip View ▸ Show Ungraded (⌃⌘U) to compare. Time it from
  selecting the clip.
- **T2 — one grade for a whole video.** In a copy of a real project, select
  nothing and choose Insert ▸ Adjustment Clip (it covers the whole timeline),
  then grade it on the Color sub-tab. Trim, move and reorder a few camera
  clips under it and play across them.
- **T3 — a look.** Select a clip (or the adjustment clip), open Color ▸ Look,
  pick a built-in look in the gallery (or Clip ▸ Look ▸) and set Amount. Try a
  few of the eight.
- **T4 — your own LUT.** In the Look section, Import LUT… a `.cube` you already
  have (a camera maker's or a bought one); it applies at 100 %. Look at the same
  frame through the same LUT in another app. For the script's figure, give an
  agent the file's path; it runs `RC_PROOF_APP=release python3
  tools/proof/grading_verdict.py measure --only T4 --lut PATH` in the worktree
  (Reelcut's frame against ffmpeg's `lut3d`, ±2 levels). That needs no main
  build.
- **T5 — the Assistant.** With your own key (Settings ▸ Assistant; it spends
  from your own budget), open View ▸ Assistant and ask "make the camera clips
  warmer and a bit brighter". Then look at Edit ▸ Undo: each op is one step.
- **T6 — the task only: brighten a face inside an ellipse.** No steps are
  given here, on purpose. Needing to be shown how is the answer.

**What GR7b records**, from your answers: for each of T1–T6, done or not (T1:
the time, under two minutes or not; T2: whether any edit needed a re-grade; T3:
which look, and whether you would use one of the eight again; T4: imported and
applied or not, how it compared by eye, and the script's figure on your file;
T5: done through the tools, one undo step per op or not; T6: done without being
shown or not); GRD-1…GRD-6, each pass or what you saw; whether you would reach
for grading again; and the verdict — kept (the merge) or dropped — with any
cap the measured column misses weighed as "a conversation, not an automatic
no". Code size is not one of them: the owner removed the product-lines budget
on 2026-10-10 (root CLAUDE.md, "Size rules are per FILE").

## Phases

Each phase is one implement-review cycle, committed alone, ending with the
root `CLAUDE.md`'s "Verification" (targeted tests in the loop, `make gate` once
when the code is complete, the phase's proof recorded whole on Release, mutants
about one per new decision). Sizes are REASONED from the mattes road map's
numstat (±50 %).

| Phase | Where | What lands | Its proof holds |
|---|---|---|---|
| GR0 | main | This document; the spike against the tree's OWN shader: what tone and a 3D LUT cost an ungraded and a graded layer under three routes, the route chosen by a rule written beforehand; #258's biplanar measurement. | The spike's figures, host and power state named. |
| GR1 | main | **Paid in GR1** (its record below): five pure moves, gated as one change with no grading code: `VideoPane.colorSection` → `VideoPane+Color.swift`; `ProjectSnapshot.swift`'s composition plan → `CompositionPlan.swift`; `AgentCatalog+Clips.swift`'s property rows and their vocabularies → `AgentCatalog+Properties.swift`; the Clip menu's submenu builders out of `AppDelegate+Menus.swift` → `AppDelegate+ClipMenus.swift`; `evaluate.rs` (590)'s composition plan → `plan.rs`, since GR4 must edit its exhaustive `Source` matches. (`LayerUniforms` already moved, `7b80810`.) | Renders byte-identical before and after; `make test` unchanged. |
| GR2 | branch | GR-1..GR-3 and GR-9 with README rows, then **tone**: the nine keys, ranges, defaults, the schema file, recipe keys, `core/tests/tone.rs`; uniforms, step 4c by GR0's route, the Color sub-tab (Color moved, Light added), `set_video`'s prose. The branch's format number. | `tone_proof.py` over MCP: defaults byte-identical to main's build on one fixture; +1 EV on a mid-grey card where linear-light doubling says (±1); temperature raises red and lowers blue; whites and blacks move only their ends; fade lifts black; `render_frame` = export frame; undo and redo; a banding fixture's distinct-level count recorded. Mutants: exposure in encoded space; tone before the obscure regions; the flag gate ignoring a negative value; a range check dropped. |
| GR3 | branch | **Seeing**: the `ungraded` recipe option (View ▸ Show Ungraded, `render_frame {ungraded}`) and the luma waveform panel (View ▸ Waveform), its compute pass run only while shown. | The option's bytes = the ungraded bytes; an export ignores the view switch; a known ramp's waveform (a probe, no photograph); harness captures light and dark; a manual-check row. |
| GR4 | branch | GR-6, then **adjustment clips**: `Source::Adjustment`, every `Source` match classified, `add_adjustment_clip`, the refusals, the recipe role, `core/tests/adjustment.rs`; the eighth pipeline (`reelcut_adjust_fragment`, blending OFF, reads `[[color(0)]]`, weights by the matte coverage), Insert ▸ Adjustment Clip, the clip body, the inspector (Color and Clip only), the MCP tool. | Grades both tracks behind and not the one in front; opacity 0.5 halfway; matted = inside only; on a matte track it grades the matte group; each refusal in its sentence; Preview Quality; every export row including the two alpha rows (the ALPHA channel over a transparent canvas); blending OFF (a mutant turning it on, caught only over a translucent destination). |
| GR5 | branch | GR-7, then **looks**: `LookKind`, each definition as data, `video.look {kind, amount}`; `texture(2)` and its placeholder, step 4d, `LookTextures.swift` (the bake on the GPU, the LRU), the Look section with a gallery drawn by the compositor, Clip ▸ Look ▸. | Amount 0 bytes = no look; an identity definition exact on every 8-bit colour; each built-in differs; a gallery thumbnail = `render_frame` at its size; a look on an adjustment clip; a manual-check row (the owner tunes the eight). |
| GR6a | branch | GR-8 (split like GR4 and GR5), then **LUT import**: the HLG/PQ/BT.2020 check first (T0; no log clip); `MediaKind::Lut` and `LookKind::Lut` through every site, `cube.rs`, `ffi_cube.rs`, `lut.rs`, parser tests; `MediaImporter+LUT.swift`, `LutTextures.swift`, the URLs a look reads (`RecipeSource.lookURLs`), the Media tab's glyph and Remove alert, Consolidate, relink, paste, the MCP mirror. | An identity `.cube` exact; a channel swap exact; sizes 2 and 65; refusals by name; a missing file draws ungraded; `remove_media` clears the looks; a paste across documents. |
| GR6b | branch | The Look gallery's Imported group and its "Import LUT…" button, Clip ▸ Look ▸'s LUT items, the Look summary naming the file, the screen, the README bullet, its GRD row. | Thumbnails by GR-7's rule; the menu's items and states; one undo step "Import LUT". |
| GR7a | branch | The scripted half: every "What it may cost" cap measured against main at the branch point (`grading_verdict.py`, `grading_spike.py --tree`, main's Release build from a throwaway worktree), T4's script half on a LUT the phase writes, and the owner's trial guide. No product code; no verdict. | The caps table's "Measured (GR7a)" column, each figure with its command, host, power and load. |
| GR7b | branch | The owner's trial against "Worth keeping" (T1–T6 and GRD-1…GRD-6, by the trial guide); the verdict. Kept: the merge. Dropped: an ADR on main, the branch kept unmerged, the issues re-iced or closed. | The owner's answers to the trial guide, recorded. |

## Not established

- **Whether AVFoundation converts LOG footage before the compositor sees
  it.** GR6a's T0 measured HLG, PQ and BT.2020 tags (spec §11 GR-8: only the
  container's `colr` atom is read; HLG and PQ arrive unconverted, BT.2020 with
  the BT.709 transfer arrives linearised); Apple Log, S-Log and V-Log were not
  checked — ffmpeg cannot make them and the owner has no log clip. It decides
  whether a camera log LUT (T4) looks right.
- **Banding on real footage** is now a question about the source's own levels,
  not the pipeline's (PR-1, PR-2); GR2's fixture and the owner's eye answer it.
- **Whether 65³ is worth it for built-in looks.** The brief's C3 says 33³ is
  within 3 levels of the analytic look; a built-in look is DEFINED by its baked
  lattice, so that error is not a defect. 65³ matters only for an imported LUT,
  which arrives at its own size.
- **The adjustment clip with Preview Quality and the matte pool** is reasoned
  from the code (both read per destination pixel), not run.
- **Where the waveform panel fits** at the 900 pt minimum window width: GR3's
  design, with a screen-catalog entry.
- **Other editors' behaviour** (adjustment layers reaching every track, scopes
  as a panel) is from general knowledge.

## GR0's rules, written before measuring

The instrument is `tools/proof/grading_spike/` (its `README.md` has the
variants, scenes, rows and statistic). These two rules were written here before
the first `--measure`, with the driver's constants as they stand at the top of
`grading_spike.py`:

```
BOUND = {1080: 0.02, 2160: 0.06}
ROUTE_ORDER = ("VA", "VF", "VC")
WIN_SHARE = 0.5
```

**The route rule.** A route qualifies when its TL variant's S1 overhead is ≤
`BOUND[h]` + C0 noise at both sizes. The chosen route is the first qualifier in
the order VA, VF, VC: no flag to keep in sync, then one pipeline per layer,
then doubled pipelines. If none qualifies, the route with the smallest 4K
overhead is recorded together with the size of the miss, which is a
conversation for the owner, not a stop. The T variants are recorded as GR2's
interim, tone-only figure.

**The #258 rule.** Let G = H16 − B8 and W = H16 − min(X420, X422) on SH at 4K.
- If G ≤ 2·C1 noise, the layer stage does not carry deep decode's cost, and
  #258 is recommended closed.
- Otherwise, if W ≥ `WIN_SHARE`·G, biplanar wins back at least half; #258 stays
  open for the owner's choice, and building it would amend PR-2.
- Otherwise, #258 is recommended closed.
- In every case GR0 records no §11 entry.

## GR0 — the road map and the spike (2026-10-09, on main)

**What landed.** This document; `tools/proof/grading_spike/` (`grading_spike.py`,
`bench.swift`, `README.md`) and its section in `tools/proof/README.md`. No
product code: nothing under `app/`, `core/`, `graphic/` or `designs/spec/`
changed, and the spike's shaders exist only under `tools/proof/work/`. GR0
records no §11 entry. The brief's "22 %" residue in `Compositor.metal` was
already fixed by precision PR1 (`c66d8ab`): lines 922–924 say "about 24 %
(61/255)".

**The instrument.** The tree's own `Compositor.metal` (1,691 lines, read from
the working tree at `3cc61e7`) patched at anchors asserted once into V0 and
eight variants (VF-T, VF-TL, VC-T, VC-TL, VA-T, VA-TL, VE, VB; the folder
README has each), compiled with `xcrun metal`, timed by a bench built over
`app/Sources` with `swift_build.build(…, optimize=True)` (key
`8d398b3fd138d55f`) that fills the app's own `LayerUniforms` plus 16 grade
floats (480 bytes, asserted), builds its pipelines as
`MetalRenderer.pipelineDescriptor` does at `MetalRenderer.workingFormat`
(`rgba16Float`), and wraps #258's sources as IOSurface-backed `CVPixelBuffer`s
through a `CVMetalTextureCache` in the call shape of
`Compositor.texture(from:live:)`. 200 frames after 5 unrecorded, three runs,
each run's series in an order drawn from the seed plus the run index; a figure
is the median of the three runs' medians.

**The recorded run.**
`perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_spike/grading_spike.py --measure`,
2026-10-09 20:49 EDT, exit 0. Host: Apple M2 Max (GPU Apple M2 Max), macOS
26.5.1, `pmset -g` powermode 0, drawing from AC Power; `vm.loadavg` before
`{ 7.68 8.94 9.76 }`, after `{ 6.88 8.61 9.61 }`. Seed 20261009. (The first
`--measure`, two minutes earlier, printed every row and then crashed writing
`result.json` — a driver bug, integer and string keys in one dictionary; fixed,
and the run above is the recorded one; the first run's figures are not part of
this record.) B0–B2 and all 44 K rows passed (K1 7 variants,
K2 6, K3 3, K4 3, K5 3, at each of two sizes).

S1, one ungraded full-bleed layer (ms; the runs' ranges are in `result.json`):

| Variant | 1920×1080 | overhead over V0 | 3840×2160 | overhead over V0 |
|---|---|---|---|---|
| V0, the tree | 0.125 | — | 0.481 | — |
| V0b (C0 CONTROL) | 0.125 | noise 0.001 | 0.481 | noise 0.000 |
| VF-T / VF-TL (flag) | 0.124 / 0.125 | −0.001 / 0.000 | 0.480 / 0.482 | −0.001 / 0.001 |
| VC-T / VC-TL (function constant) | 0.121 / 0.121 | −0.003 / −0.003 | 0.481 / 0.481 | −0.000 / −0.000 |
| VA-T / VA-TL (always on) | 0.140 / 0.147 | 0.015 / **0.022** | 0.537 / 0.564 | 0.056 / **0.083** |
| VE (encoded exposure) | 0.124 | −0.000 | 0.481 | −0.001 |

**T1, the route: VF, the uniform flag.** By the rule above: VA-TL does not
qualify (0.022 ms at 1080p against 0.02 + 0.001, and 0.083 ms at 4K against
0.06 + 0.000 — it misses at both sizes), VF-TL qualifies (0.000, 0.001 ms) and
is the next in the order, and VC-TL also qualifies (−0.003, −0.000 ms). GR2
builds tone at 4c behind `toneEnabled` joining the effects sum, and the look at
4d behind `lookEnabled`. The always-on route costs an ungraded 4K layer about
what the matte placeholder already does (0.056 ms tone alone, 0.083 with the
look), which is the cap's reason.

**T2, a graded layer and an adjustment pass** (ms over the same variant's S1):

| | 1080p VF | 1080p VC | 1080p VA | 4K VF | 4K VC | 4K VA |
|---|---|---|---|---|---|---|
| ST − S1, tone only (T variant) | 0.049 | 0.026 | 0.003 | 0.197 | 0.084 | 0.001 |
| ST − S1 (TL variant) | 0.053 | 0.027 | −0.002 | 0.214 | 0.085 | 0.001 |
| STL − S1, tone and a 33³ look at 0.8 | 0.057 | 0.037 | 0.001 | 0.226 | 0.149 | 0.003 |
| SA − S1, one full-frame adjustment pass | 0.045 | 0.047 | 0.046 | 0.174 | 0.174 | 0.169 |

The absolute medians behind it (ms, 1080p / 4K; the runs' ranges are in `result.json`):

| Series | VA | VF | VC | VE |
|---|---|---|---|---|
| ST, T variant | 0.143 / 0.538 | 0.173 / 0.677 | 0.147 / 0.566 | — |
| ST, TL variant | 0.145 / 0.565 | 0.178 / 0.696 | 0.148 / 0.566 | — |
| STL | 0.148 / 0.568 | 0.182 / 0.708 | 0.159 / 0.630 | 0.171 / 0.669 |
| SA (TL variant) | 0.192 / 0.733 | 0.169 / 0.656 | 0.168 / 0.656 | — |

The linear-light step (VF-TL:STL − VE:STL) costs 0.011 ms at 1080p and 0.040
ms at 4K. Read with T0: under VA a layer pays the arithmetic whether graded or
not, so its graded figures are near zero over its own, dearer S1. Under VF a
GRADED layer pays more than under VC (0.226 against 0.149 ms at 4K with the
look). Why is not established: VC's gate also enters the effects block once
`kTone` is set, and the block's other tests read uniforms in both routes, so
nothing there is compiled out; REASONED, the difference is VF's dynamic
`toneEnabled`/`lookEnabled` branches against VC's constants, which let the
compiler fold the tone and look paths. That is a figure for GR2's
design, not a reason to override the rule, and well inside "Worth keeping"'s
graded-frame cap (four graded layers and one adjustment at 1080p: about 4 ×
0.057 + 0.045 = 0.27 ms over ungraded against the 8 ms budget, REASONED from
these rows).

**P1, stacked grades.** −1 EV then +1 EV as two adjustment passes (VF-TL's
fragment), each in its own render pass, over the 256-column ramp: through
`rgba16Float`, **256 distinct levels of 256**, max |Δ| 0.361 levels, at both
sizes. CONTROL through `bgra8Unorm`: 189 distinct levels, max |Δ| 1 level. (The
brief's scratch C4 gave 129 through `bgra8Unorm` with a scratch shader; this
control halves the LIGHT, not the code value, so the 8-bit intermediate keeps
more codes — REASONED.) PR-1's float pipeline keeps a stacked grade's levels,
which is what GR-3 now says.

**X0, #258's scene** (four video layers, ms):

| Source form | 1080p | 4K |
|---|---|---|
| B8, `bgra8Unorm` (32BGRA), V0 | 0.195 | 0.765 |
| H16, `rgba16Float` (64RGBAHalf), V0 | 0.235 | 0.900 |
| H16b (C1 CONTROL) | 0.236 (noise 0.001) | 0.898 (noise 0.002) |
| X420, `r16Unorm` + `rg16Unorm` at W/2×H/2, VB | 0.193 | 0.769 |
| X422, chroma at W/2×H, VB | 0.205 | 0.792 |
| VB0, VB with `kBiplanar` false, H16 sources | 0.237 | 0.906 |

G = H16 − B8 = 0.040 ms at 1080p and **0.135 ms at 4K**; W = H16 −
min(X420, X422) = 0.042 and **0.131 ms**. VB0 − H16 is 0.002 / 0.006 ms: the
biplanar branch costs a 64RGBAHalf layer next to nothing when it is off.

**X1, #258's outcome: it stays open for the owner's choice.** At 4K, G 0.135 ms
> 2·C1 0.004 ms, and W 0.131 ms ≥ 0.5·G 0.067 ms: a 10-bit biplanar source
wins back essentially all of what the half-float source costs the LAYER STAGE.
Building it would amend PR-2; GR0 records no §11 entry. For scale (REASONED,
not measured here): the layer stage's share in this four-layer scene is 0.135
ms, where #258 quotes PR3's same-load A/B at 8.155 against 6.405 ms for the
whole heavy-4K frame, so most of that difference is outside the layer stage's
sampling.

**D1, decoding the fixtures** (2 s, 3840×2160, 30 fps, made by ffmpeg from
`testsrc2`, tagged BT.709; 60 frames per run through `AVAssetReader`, the eight
(file, format) pairs in a seeded order, three runs; frames per second, the
median with the runs' range):

| Fixture → format | 32BGRA | 64RGBAHalf | x420 | x422 |
|---|---|---|---|---|
| ProRes 422 (`prores_ks` profile 2), `yuv422p10le` | 198.6 (194.3–202.8) | 313.3 (311.5–333.6) | 196.4 (195.9–198.7) | **450.8** (439.0–468.9) |
| HEVC Main 10, `yuv420p10le` | 198.5 (198.3–198.8) | 277.3 (272.9–293.3) | **341.0** (335.9–345.1) | 315.9 (308.1–316.3) |

Each codec decodes fastest into its own native layout (x422 for ProRes 422,
x420 for HEVC 4:2:0), and 64RGBAHalf decodes faster than 32BGRA for both, which
agrees with PR2's "deep decode itself is quicker".

**Mutants**, each a `--check --mutant NAME` on the final instrument, all
killed: `anchor-missing` by B0; `exposure-encoded` by K2, K4;
`lut-axes-swapped` by K3; `adjust-ignores-destination` by K4;
`biplanar-full-range` by K5; `neutral-drift` by K1 (and K2, K3, K4).

**Verified:** `--check` exit 0 (B0–B2, 44 K rows); the six mutants killed;
`python3 tools/proof/swift_build.py --selftest` 10/10; `make gate` PASS (only
its test step ran; the others skipped by stamp); `--measure` exit 0 as above.

**Owed, outside this file:** the issue comments on #118, #120, #122, #124 and
#258 (the orchestrator posts them). GR1's pure moves are next, on main.

## GR1 — pure moves (2026-10-09, on main)

**What landed.** Five pure moves, gated as one change with no grading code
and no behaviour change. Each moved body is unchanged apart from the
visibility listed with it (the Rust plan section was diffed against `HEAD`
after `cargo fmt`: identical).

| Move | `wc -l` before → after | New file | What widened |
|---|---|---|---|
| `core/src/evaluate.rs` → `plan.rs`: `MAX_CONCURRENT_VIDEO_TRACKS` and `// ---- the composition plan` to the end (`Instruction`, `composition_plan`, `instructions`, `warnings_for`) | 590 → 381 | `plan.rs`, 221 | `Segment` and its `to_json`; `CompTrack` and its `id`, `segments`, `voices`; `Assignment`'s `video` and `audio` — all `pub(crate)`. `composition_plan` stays an inherent `pub fn`, so `ffi_query.rs` and the tests did not change. |
| `ProjectSnapshot.swift` → `CompositionPlan.swift`: `// MARK: - Composition plan (spec §7.2)` to the end | 1,871 → 1,750 | 123 | nothing |
| `VideoPane.swift` → `VideoPane+Color.swift`: `// MARK: Colour` and `colorSection()` | 959 → 904 | 58 | nothing (`binding` was already internal) |
| `AgentCatalog+Clips.swift` → `AgentCatalog+Properties.swift`: the five property rows (`set_video`, `set_audio`, `set_text`, `set_shape`, `set_clip`) as `propertyTools(clipsDescription:)`, spliced back after `unnest`, and the nineteen hoisted locals they read (three also read by `add_text_clip` and `add_shape_clip`), as static members with explicit types | 706 → 513 | 247 | `shapeNames`, `textPatchDescription` and `shapePatchDescription` are internal statics, because `add_text_clip` and `add_shape_clip` read them through typed locals; the other sixteen are `private static` |
| `AppDelegate+Menus.swift` → `AppDelegate+ClipMenus.swift`: `backgroundMenu` through `labelDot` | 579 → 494 | 104 | `backgroundMenu`, `transitionMenu`, `motionMenu`, `labelMenu` and `tagged` became internal; `motionSlotMenu` and `labelDot` stay `private` |

`textPatchDescription`'s static initializer names
`AgentServer.textWordsClause`, not `Self.textWordsClause`: Swift refuses a
covariant `Self` in a stored-property initializer, even on a final class.
That is the spec's stated fallback. `propertyTools` binds the five patch
descriptions to typed locals of the same names, so the five row bodies are
byte-identical to what they were.

**Why `evaluate.rs` was paid now.** Both of its `Source` matches are
exhaustive (`segment_of` and `draws`), so GR4's `Source::Adjustment` cannot
compile without editing the file, and it was at 590 of the ~600 cap. The cut
is the one the file's own banner drew. `place`, `segment_of`, `assign` and
`drawing_instances` stay, along with the comments that cite them, and so does
`speed_limits_probe.py`'s mutant anchor `!match_pitch ||`. Every reader of
`crate::evaluate::{json, number, Assignment}` kept its import.

**Verification**, on 2026-10-09, AC power:
- Controls taken from the untouched tree before any edit, never by stashing.
  The Debug catalog was copied to `tools/proof/work/gr1/catalog-before.json`.
  `RC_PROOF_APP=release python3 tools/proof/word_looks_proof.py --only B1`
  ran on the `bd5bb65` Release build: 3/3, B1 `moved: []`
  (`tools/proof/work/gr1/b1-before.txt`).
- `cd core && cargo test --release --test evaluate_tests` (55 passed),
  `--test matte` (8), `--test model_tests` (31) and `--test source_window`
  (9), all passing. `make lint` was clean.
- `make typecheck` after each Swift move: exit 0, 0 errors, exactly the 4
  baseline warnings.
- `make app-debug`, then the catalog compared parsed with
  `tools/proof/work/gr1/catalog-before.json`: equal (exit 0), the tool order
  included.
- `python3 tools/proof/v2_menu.py --only H`: 5/5 pass. H1 found 0 problems
  over 155 leaves and 99 live selectors, and H2's probe table and inventory
  had 99 rows each, no differences.
- `python3 tools/proof/spec_index_proof.py`: 147/147. The
  `07.10-rust-module-map.md` Lines cell went from 85 to 86.
- `make gate`: PASS in 315 s (typecheck 14 s with the 4 baseline warnings,
  fmt 5 s, lint 2 s, test 202 s, app 90 s, with D25 and D26 ok). The Rust
  suites passed 1,251 tests and failed none.
- `RC_PROOF_APP=release python3 tools/proof/word_looks_proof.py --only B1`
  ran on the gate's Release build: 3/3, B1 `moved: []`, the same as the
  control (`tools/proof/work/gr1/b1-after.txt`). The 41 frames of fixture B
  still match the digests recorded from `c66d8ab`.
- No mutants: a pure move adds no decision.

**Owed.** Nothing from GR1. GR2 opens the `grading` branch. The next named
seams are in `designs/adr/app-file-history.md` and `core-file-history.md`:
`ShapeProps.swift`, `VideoPane+Chroma.swift`, and the View menu's submenus.
`AgentCatalog+Clips.swift` and `evaluate.rs` have none named.

## GR2 — the decisions and tone (2026-10-09, on the `grading` branch)

**Where.** The worktree `~/devel/reelcut-grading`, branch `grading`, cut from
main at `4d742cc` (main had not moved, so no merge was due). The owner's
answers to GR2's nine choices were "All as recommended" (2026-10-09).

**What landed.**
- Spec §11 first: `designs/spec/11-decisions/grading.md` with GR-1 (the
  experiment; amends §1), GR-2 (tone, step 4c, local linear light, the route,
  the Color sub-tab and the nine choices), GR-3 (the float pipeline, encoded
  blending) and GR-9 (format 1015, the 15–1014 refusal, the merge's
  renumbering); its README rows; "Amended by GR-2" under CI-5 and CI-6. Then
  §1, §4.3a, §5.2, §7.3 and §7.5, and the spec index's Lines cells.
- Core: `ColorAdjust` gains `exposure`, `temperature`, `tint`, `highlights`,
  `shadows`, `whites`, `blacks`, `vibrance`, `fade`, each
  `skip_serializing_if = "is_zero"`; `props_check.rs`'s `EXPOSURE_MAX` 3 and
  `TONE_MAX` 1 and nine `in_range` checks; nine `bounded` lines in
  `clamp_video`; `actions::color_json` (all thirteen keys) and `video_json`
  at `evaluate_clip`'s base state, `clip_state`'s `video`, `patch.rs`'s video
  template, `edit_split.rs`'s `state_patch` and (`color_json`) the recipe
  layer; `RC_FORMAT_VERSION` 1015 and `BRANCH_BASE_VERSION` 14 with the gap's
  sentence in `format::read`, and the header's `#define`. No new op, op-table
  row or FFI export. New `core/tests/tone.rs` (6) and `schema_v1015.rs` (5).
- App: `LayerUniforms` 104 → 116 floats (464 bytes): the nine, `toneEnabled`
  and two reserved, in Swift and Metal; `Compositor.metal`'s `gradeDecode`,
  `gradeEncode` and `gradeTone` (GR0's spike formulas and numbers), the gate
  sum's `+ u.toneEnabled` and step 4c between 4b and 5, with the
  order-of-operations and cost comments; `Compositor+Uniforms.swift`'s one
  `u.apply(tone:)`. New `GradeProps.swift` (`ColorPatch`, the two neutrality
  helpers, `LayerUniforms.apply(tone:)`) and `VideoPane+Light.swift`;
  `ClipSubTab.color`, its `keyedCount` and Picture's without `color`;
  `ClipPane`'s Color tab (videoClips non-empty and `allSourcePixels`) holding
  Light then Color; Color's rows write `ColorPatch` sparsely; the eyedropper's
  suppression writes all thirteen at 0; `set_video`'s catalog prose names the
  nine keys and ranges.
- Instruments: `tone_proof.py` and `tone_probe.swift`; `phase8_chrome.py`'s
  size row (464); both spikes' benches hand their shader the first 104 floats,
  and `grading_spike.py` reads the shader at `4d742cc`; `clip_inspector2`'s
  T1/T2; the screen catalog's `05b-clip-color` and `05-clip-picture`'s prose;
  `phase9_proof.py`'s version loop over 1–`BRANCH_BASE_VERSION` and the
  current version. GRD-1 in `docs/manual-checks.md`; the README's Light bullet.

**Sizes.** Product code (`app/Sources`, `core/src`, the shader): +347 −64 in
changed files and 165 lines in the two new Swift files, so about +448 net,
against "Worth keeping"'s ≤ 4,500 for GR2–GR6. `ProjectSnapshot.swift` grew
only by `ColorAdjust`'s 34 lines (1,750 → 1,784); `AgentServer+Clips.swift`
stayed 636 and `CanvasSessions.swift` (over the cap) 1,092, both net 0; no
frozen file was touched. The inspector gained one sub-tab with
two sections; Picture lost Color and gained nothing.

**Measured.** Every run on 2026-10-09, Apple M2 Max, macOS 26.5.1, AC power.
- The control: `make app` on the untouched worktree (main's `4d742cc` plus
  only the §11 text), then `RC_PROOF_APP=release tone_proof.py capture
  tools/proof/work/gr2/control`: six neutral frames.
- `tone_proof.py` on Debug in the loop: 18/18 scored rows.
- Recorded, on the final gate's Release build and the final instrument:
  `RC_PROOF_APP=release tone_proof.py
  compare tools/proof/work/gr2/control` 19/19 — N0 the six neutral frames
  byte-identical at 16 bits a channel; E1 exposure +1 takes grey 128 to 176
  (round(255·enc(2·dec(128/255)))), E2 −1 to 92; W1 temperature +0.5 gives
  (134, 128, 122) and tint +0.5 (128, 122, 128); K1 whites +1 keeps 0 and
  takes 128 to 147, blacks +1 keeps 255 and lifts 0 to 38; F1 fade 1 gives
  black 25 (26 ±1) and white 242; A1's mid-span 150 between 128 and E1's
  measured 175; M1 the matte frame's
  mean ×1.367; X1 the `prores_422` frame within ±8 at all 920 samples. **B1
  (recorded, unscored): the 1920-column ramp at exposure +1 keeps 189 distinct
  levels in its middle row against 256 neutral** — the top half of the ramp
  clips to white at +1 EV, which is the operation, not banding.
- `word_looks_proof.py --only B1` on Release: 3/3, `moved: []`.
- `phase8_chrome.py` 150/150 (its size row reads 464); `phase9_proof.py`
  223/223 on Release, the version loop opening 1–14 and 1015 and refusing 1016.
- `clip_inspector2_proof.py` 33/33; `screens.py --only
  05-clip-picture,05b-clip-color` 7/7, 0 new problems;
  `grading_spike.py --check` exit 0 (B0–B2, 44 K rows, as at GR0);
  `matte_spike.py --check` and `--check --tree` exit 0.
- `cargo test --release` (every suite) and `make gate`: the first gate failed
  at test (`schema_v8.rs`, below); after that fix PASS in 278 s, and after the
  last edit (`CanvasSessions.swift` brought back to net 0 lines) PASS in 286 s
  (typecheck 8 s with the 4 baseline warnings, fmt and lint skipped by stamp,
  test 178 s, app 100 s).
- Mutants, each `tone_proof.py --mutant NAME` on Debug, all seven MUTANT PASS
  (every named row failed, no other scored row did): `exposure-encoded` E1
  E2; `tone-before-obscure` O1; `flag-ignores-negative` E2 P2;
  `range-check-dropped` R1 CT; `tone-always-written` N2 CT;
  `lerp-base-unfilled` A1 CT; `light-writes-group` P1. The first pass found
  two instrument faults, both fixed before the final runs: A1 bounded its
  mid-span by E1's FORMULA, so `exposure-encoded` also failed A1 (A1 now reads
  E1's measured value), and R1 left an accepted 3.5 in place for U1's undo
  to land on (R1 now takes back what was accepted). `exposure-encoded` and
  `tone-before-obscure`, which had run before those fixes, were run again on
  the final instrument; the other five ran on it.

**Deviations.** `core/tests/schema_v8.rs`'s
`an_end_patch_that_replaces_the_whole_video_group_falls_through_to_the_base`
compared `clip_state`'s `video` with the stored clip's; `clip_state` now
reports `color` with all thirteen keys (GR-2, the spec's `video_json`), so its
oracle fills tone's nine at 0. The `exposure-encoded` mutant also fails E2 (an
encoded halving is 64, not 92), so it names E1 and E2. Exposure's field shows
" EV" with a space, as every other unit row does (" px", " dB").

**Owed.** GRD-1 (the owner, on real footage). The root and per-side
`CLAUDE.md` lines (app map: `LayerUniforms` 116 floats, `ClipSubTab`'s seven
cases, `GradeProps.swift`, `VideoPane+Light.swift`; core map: `ColorAdjust`'s
tone, format 1015 and its gap, `video_json`) are owed by the phase that edits
them (GR2's spec kept `CLAUDE.md` untouched). GR3, seeing, is next.

## GR3 — seeing the grade: Show Ungraded and the luma waveform (2026-10-09/10, on the `grading` branch)

**Where.** The worktree `~/devel/reelcut-grading`, branch `grading`, at `0545902`
(main merged in). The owner's answers to GR3's eleven choices were "All as
recommended" (2026-10-09): View ▸ Show Ungraded ⌃⌘U and View ▸ Waveform ⌃⌘W after
Preview Window; Show Ungraded strips all thirteen `video.color` keys on every layer;
preview and Preview Window only; an "Ungraded" tag; neither persists; a fixed 248 pt
panel; Rec. 709 Y′ of the composited encoded preview frame, 256 × 256, log density;
clip marks at levels 255 and 0 over 0.5 % of a column and two readouts;
`render_frame {ungraded, waveform}`; Save Frame… ignores the switch.

**What landed.**
- Spec §11 first: GR-4 (the option and the switch) and GR-5 (the waveform, its tap,
  the panel) in `designs/spec/11-decisions/grading.md`, README rows. Then §4.2, §7.3,
  §7.5, §7.9a, §9 and the index's Lines cells.
- Core: `RecipeOptions.ungraded`, read by `of` (a non-boolean is off); `layer` writes
  `moved.color` neutral before `RecipeLayer`, so no key is added and the un-optioned
  recipe is byte-identical. The FFI comments in `ffi_query.rs` and the header; no
  signature, op or format change. New `core/tests/ungraded.rs` (5), its oracle the
  same project's JSON with every `video.color` removed (top level, a nest, a luma
  matte clip, an action's end).
- App: `RecipeOptions.ungraded` and its `json`; `Waveform.metal`
  (`reelcut_waveform_bin`, one atomic add per pixel); `WaveformAnalyzer.swift`
  (`WaveformTrace`, the pass, `analyze(image:)` in the image's own colour space);
  `WaveformTap.swift` (`WaveformTaps`: own queue and texture cache, one pass in
  flight per key, ONE pending frame replaced by each newer one, a token per attach,
  one main hop); `Compositor.serve`'s one `offer` line; `WaveformPanelView.swift`
  (the panel, `WaveformTraceView`, `UngradedTagView`);
  `EditorViewController+Seeing.swift` (the two commands, `installSeeing`, the
  validator); the canvas's trailing edge pinned to the panel; the modal canvas modes
  pinned to the canvas, not the pane; the frozen file's one validator arm; the two
  View items; the menu table and inventory rows; `render_frame`'s `ungraded` and
  `waveform` (the JSON beside the image, one sentence before the last) and their
  catalog rows.
- Instruments: `seeing_proof.py`, `waveform_probe.swift`, the harness's fifteenth
  argument `seeing`, `screens.py`'s `VIEW_SELECTORS` and the screen
  `04b-preview-waveform`. GRD-2 in `docs/manual-checks.md`; the README's Light bullet.

**Sizes.** Product code: +120 −34 in changed files and 720 lines in the five new
files (`WaveformAnalyzer.swift` 189, `WaveformTap.swift` 159,
`WaveformPanelView.swift` 243, `EditorViewController+Seeing.swift` 96,
`Waveform.metal` 33), about +806 net; with GR2's ~448, about 1,254 of "Worth
keeping"'s ≤ 4,500. `ReelCore.swift` 999 → 995 and `Compositor.swift` 724 → 724 (both
over the cap, net ≤ 0); the frozen `EditorViewController.swift` +1 line (wiring);
`core/src/recipe.rs` 521 → 537; `AgentServer+Render.swift` 583,
`AgentCatalog+Files.swift` 579. Menus: the two View items the cap names.

**Measured.** 2026-10-09/10, Apple M2 Max, macOS 26.5.1, AC power.
- Loop, Debug: `seeing_proof.py` every row green; `cargo test --release --test
  ungraded` 5/5, `--test recipe` 15/15, `--test model_tests` 31/31;
  `make typecheck` 0 errors and the 4 baseline warnings; `make lint` clean;
  `v2_menu.py --only H` 5/5; `inventory.py --check` 5/5; `spec_index_proof.py`
  150/150; `screens.py --only 04b-preview-waveform` 6/6, 0 new problems;
  `reference_build_selftest.py --integration` exit 0.
- `make gate`: PASS in 237 s (typecheck 5 s, fmt 2 s, lint 1 s, test 132 s, app 97 s).
- Recorded, on the gate's Release build and the final instrument:
  `RC_PROOF_APP=release seeing_proof.py` 19/19 — U1 the ungraded stack equal to the
  pre-grade bytes; U2 an un-optioned frame still graded with the switch on; U3 the
  `prores_422` export within ±8 of the graded frame at 920 samples and 73 from the
  ungraded one; U4 refused ("ungraded must be true or false."); W1 the 1920-column
  ramp's 256 bins within their rendered values; V1 the panel's (46.5, 0.2) against
  render_frame's (46.46, 0.21) at exposure +2; V2 (0.2, 0.2) against (0.21, 0.21)
  ungraded; V3 the panel 248 pt with the canvas 1031 pt beside it in a 1279 pt pane,
  and off the canvas 1279 pt; V4 the tag; P1–P7; H1–H2 light and dark; Z1. **G1
  (recorded): the pass costs 0.168 ms at 1080p and 0.331 ms at 4K** (GPU time, median
  of ten), only while the panel is shown.
- Mutants, each `seeing_proof.py --mutant NAME` on Debug, all seven MUTANT PASS (every
  named row failed, no other scored row did): `ungraded-ignored` U1 U3 V2 CT;
  `ungraded-tone-only` U1 CT; `view-key-leaks` U2 U3; `luma-weights-swapped` P3;
  `level-floors` P1 P2 P4 W1 V1; `no-paused-refresh` V1 V2; `pending-dropped` P7
  (the orchestrator's row for the latest-wins slot: three 4K frames offered back to
  back, the last delivered trace is the third's). The first pass found
  `no-paused-refresh` surviving V1 — the exposure edit's own refresh was still
  composing when the panel attached — so V1 now waits 2 s after the edit; and
  `level-floors` and `ungraded-ignored` failing more rows than the spec named, all
  true catches, so their named lists grew. Those three were run again on the final
  instrument; the other four ran on an instrument that differed only in V1's wait
  and those two lists.

**Deviations.** The probe has P7 and the proof seven mutants (the orchestrator's
addition). `level-floors` and `ungraded-ignored` name the rows they truly fail
(above). H1–H2 are skipped under `--mutant` (the harness builds the tree's own
sources). `recipe.rs` is 537 lines, against the spec's "≲535". The panel's width
constraint is priority 999 so a pane narrower than 248 pt (unreachable: the split
keeps 380 pt) squeezes it rather than logging a conflict. The harness prints
`seeing trace X Y W H` so H2 can find the well. `WaveformTaps` has an internal
`init(analyzer:)` for the probe's own kernel.

**Owed.** GRD-2 (the owner, on real footage). The `CLAUDE.md` lines, owed by the
phase that edits them (GR3's spec kept `CLAUDE.md` untouched): app map rows for
`WaveformAnalyzer.swift`, `WaveformTap.swift`, `WaveformPanelView.swift`,
`EditorViewController+Seeing.swift` and `Waveform.metal`; the hygiene list's new
seam, the waveform tap's main hop; the agent-parity exemption's Show Ungraded and
Waveform panel; the core map's `RecipeOptions.ungraded`. The comment at
`EditorViewController+ZoomRegion.swift:204` ("both fill `canvasContainer`") is now
loose — the region overlay fills the canvas view — though its conversion is explicit.
GR4, adjustment clips, is next, and extends `layer`'s neutralising to them.

## GR4a — adjustment clips: the kind, the op, the pass, the MCP tool (2026-10-10, on the `grading` branch)

**Where.** The worktree `~/devel/reelcut-grading`, branch `grading`, at `6ecf46c`.
GR4 did not fit one spec and is split: GR4a (this) is the core, the compositor,
the MCP tool, the timeline style and the proof of the picture; GR4b is
Insert ▸ Adjustment Clip, the inspector (Color and Clip only) and its screen. The
owner's answer to GR4's twelve choices, both halves, was "All as recommended"
(2026-10-10), including choice 8: inert on a matte track.

**What landed.**
- Spec §11 first: GR-6 in `designs/spec/11-decisions/grading.md` (all twelve
  choices, GR4b's marked, the matte correction to this road map — on a matte
  track the clip is INERT, not "the matte group's earlier members", because a
  group is one track and two clips on one track share an instant only in a
  transition, which GR-6 refuses — and the note amending GR-9: the format
  stays 1015, the kind refused by name by a build that lacks it), its README
  rows. Then §4.4, §5.2, §6 (06b), §7.3, §7.4, §7.5 (eight pipelines) and
  §7.10, and the index's Lines cells.
- Core: `Source::Adjustment` (`{"kind":"adjustment"}`), every exhaustive match
  classified (`segment_of` none, `draws` true, `source_size` and the media id
  none, `source_media` none). New `edit_adjustment.rs`: `add_adjustment_clip`
  through `add_described_clip`, `is_adjustment`, `check_adjustment_video`
  (beside both `check_blend` calls), `adjustment_overlap` (in
  `check_overlap_rule`, the one placement door, so `set_gained_transitions`
  never mints on one), `adjustment_transition` (`add_transition` after step 1
  for either clip, `set_transition` with a kind, `set_transition_style` after
  its neither-key identity), `adjustment_nested` (`check_clips` inside a nest,
  so a file and a scoped paste meet it on the merged parent),
  `adjustment_cannot_nest` (`nest_clips`), `clamp_adjustment` (the evaluator,
  after `clamp_video`) and `inert_adjustment` (`frame_recipe_opts` drops it
  before `frame_mattes`). The op's `edit.rs` row and dispatch, `op_table.rs`'s
  row (`OP_COUNT` 60), `scope.rs`'s `refused_inside` arm, the recipe's
  `layer_source` arm. The format and header comments. New
  `core/tests/adjustment.rs` (18); `scope.rs`, `op_ticks.rs` (with
  `common/op_ticks_clips.rs`), `op_nullability.rs` and `edit_tests.rs`
  (its op-coverage table, an op-count failure only) take the sixtieth op.
- App: `ClipSource.adjustment` in every switch (`ProjectSnapshot.swift` net
  0), `RecipeSourceRef.adjustment`, `reelcut_adjust_fragment` appended to
  `Compositor.metal`, new `Compositor+Adjustment.swift` (`isAdjustment`,
  `isNeutralAdjustment`, `adjustPipeline`, `drawAdjustment`),
  `Compositor.swift`'s `adjustPipeline` and `.absent` (net −1),
  `encodeLayers`' branch, one arm each in `LayerRenderers.swift`,
  `InspectorTab.swift`, `TimelineLayout.swift` and the frozen
  `TimelineView.swift`; `DS.clipAdjustment` and `ClipKindStyle`'s rose kind;
  `ReelOp.addAdjustmentClip`; new `AgentServer+Grading.swift` and the frozen
  `AgentServer.swift`'s one table row (net 0); the catalog row, `set_video`'s
  sentence and the assistant's topic.
- Instruments: `adjustment_proof.py` (28 rows, seven mutants) and its README
  section; `op_argument_proof.py` and `op_catalog_proof.py` at 90 tools and 60
  ops; `phase9_proof.py`'s `REFUSED_INSIDE` and its section 6 sweep at eight
  (`add_adjustment_clip` sent on the nest's own track), and `phase9_probe.py`'s
  document-level check's label (its set stays the seven).

**Sizes.** Product code about +460 net: changed files +246 −65, new files
`edit_adjustment.rs` 184, `Compositor+Adjustment.swift` 75,
`AgentServer+Grading.swift` 20. With GR2 and GR3, about 1,714 of "Worth
keeping"'s ≤ 4,500. `recipe.rs` 537 → 546, `edit_transition.rs` 574 → 588,
`ProjectSnapshot.swift` 1,784 → 1,784, `Compositor.swift` 724 → 723,
`AgentServer.swift` 785 → 785, `AgentCatalog+Clips.swift` 513 → 529.

**Measured.** 2026-10-10, Apple M2 Max, macOS 26.5.1, AC power.
- Loop, Debug: `cargo test --release` for `adjustment` 18/18, `scope`,
  `op_ticks`, `op_nullability`, `op_table`, `recipe`, `matte`, `ungraded`,
  `add_transition`, `paste`, `nest`, `edit_tests` all green; `make lint`
  clean; `make typecheck` 0 errors and the 4 baseline warnings;
  `assistant_prompt_proof.py --probe` 14/14; `matte_spike.py --check --tree`
  every scored row; `op_catalog_proof.py` 23/23 (60 ops) and
  `op_argument_proof.py` 157/157 (90 product tools); `spec_index_proof.py`
  150/150; `adjustment_proof.py` 28/28.
- `make gate`: PASS in 199 s (typecheck 5 s, fmt 2 s, lint 1 s, test 101 s,
  app 88 s).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release
  adjustment_proof.py` 28/28, no skip (this host has the `hevc_alpha`
  encoder), no `DEFAULTS MOVED`.
- Mutants, each `adjustment_proof.py --mutant NAME` on Debug, all seven MUTANT
  PASS (every named row failed, no other scored row did), on the final
  instrument: `blending-on` A1; `ignores-matte` M1 Q1; `ignores-opacity` O1
  O2; `front-graded` G1; `matte-track-not-inert` M2; `nest-allowed` R1;
  `overlap-allowed` R5.
- Fix pass 1, Debug: `phase9_proof.py` 224/224 (section 6's eight refusals,
  `add_adjustment_clip` with `core/src/scope.rs`'s own sentence) with no
  `Reelcut: ` line; `phase9_probe.py` 48/48 (the document-level set the
  seven).

**Deviations.** A1 compares the PREMULTIPLIED colour (±1), not the straight
one: `render_frame`'s PNG is written from 8-bit premultiplied pixels, so at
alpha 128 a straight value moves in steps of two (the first run read 177
against 179 with a correct pass). R1–R7 hold the sentence as the exact TAIL of
the MCP answer, because the app prefixes a refusal with `<tool>: <step> was
refused at <op>: ` and an error with `<tool>: `. R3 sends the nest's own track,
since the app's argument check refuses a timeline track inside a scope before
the core is asked. `edit_tests.rs` was edited (its op-coverage table gains the
op), as the spec's "any other suite that fails only on an op count" allows.
`ReelOps.swift`'s comment on `documentLevelNames` and §7.4's sentence now say
"the seven DOCUMENT-level ops": `add_adjustment_clip` is the eighth op the core
refuses in a nest but is not document-level, so it is sent scoped and refused,
not sent unscoped onto the timeline. `Compositor.swift`'s pipeline comments were
tightened to hold its size (net −1).

**Owed.** GR4b (the menu item, the inspector, the screen, GRD-3, the README
bullet, the proof's menu and sub-tab rows); until it lands an adjustment clip
shows Picture and Clip. The `CLAUDE.md` lines, owed by the phase that edits
them (GR4a's spec kept every `CLAUDE.md` untouched): root, "eighty-nine product
tools" → ninety; the app map's `Compositor+Adjustment.swift`,
`AgentServer+Grading.swift`, `ClipSource.adjustment` and the eighth pipeline
("Seven pipelines from five fragment functions" → eight from six); the core
map's `edit_adjustment.rs` and `Source::Adjustment`, and `op_table.rs`'s
"fifty-nine op tools".

## GR4b — adjustment clips in the chrome: Insert ▸ Adjustment Clip, the Color/Clip inspector, the matte note, screen 05c (2026-10-10, on the `grading` branch)

**Where.** The worktree `~/devel/reelcut-grading`, branch `grading`, at `a5a6cdf`
(GR4a). The owner's choices are GR-6's [b] items, decided 2026-10-10; none new.
Decided inside GR-6: the undo name is "Add Adjustment Clip" (the MCP tool's); a
range counts only when its end is after its start; the Adjustment section's
summary is the strength ("75%"), its Reset sets opacity 1 (undo "Adjustment"),
and it opens by the first-section rule; Color's `◆N` also counts an end's
`opacity` for an all-adjustment selection (CI-6); the adjustment matte note
shows when every selected clip is an adjustment clip on a matte track.

**What landed.**
- App: new `EditorViewController+Adjustment.swift` (84 lines:
  `insertAdjustmentClip(_:)`, `adjustmentSpan` — the range, else the selected
  clips' span, else the timeline — `adjustmentOps` — the front track when it is
  not a matte and a pure trial of the op answers a project, else
  `add_track "Adjustment"` and the clip on `nextId` — and the validator arm,
  off with a nest open or nothing to cover). The frozen `EditorViewController.swift`
  takes its one validator line. `selectClips(addedSince:in:)` is internal.
  Insert holds Adjustment Clip first (`AppDelegate+GraphicMenu.swift`, no key);
  `UIMenuTable`'s row. `InspectorTab.isAdjustment`, the fourth kind test. New
  `VideoPane+Adjustment.swift` (60 lines: `allAdjustment`, `anyAdjustment`,
  `allGradable`, `adjustmentSection()` — Strength, the opacity as 0–100 %).
  `ClipPane.subTabs`: Picture never with an adjustment clip, Color when every
  clip is gradable; `.color` puts Adjustment first for an all-adjustment
  selection; the badge passes `adjustment:` to `ClipSubTab.keyedCount`, whose
  new parameter is defaulted so every probe compiles unchanged.
  `ClipPane.matteNote` answers "An adjustment clip on a matte track has no
  effect." first, its other answers unchanged. `AgentServer+Grading.swift`'s
  comment names the UI path.
- Instruments: `adjustment_proof.py` gains I1–I4 and S1–S4 and six mutants, and
  launches with three argument-domain section pins (`video.adjustment` open,
  `video.light` and `video.color` closed); `inventory.json`'s
  `insertAdjustmentClip:` row; `graphics_menu_probe.swift`'s M2 (Insert is
  Adjustment Clip then Graphic) and the proof's docstring; `screens.py`'s
  `adjust` fixture and its `video.adjustment` pin (open); the proof README's
  section.
- Documents: screen `05c-clip-adjustment` and the screens README's `adjust`
  fixture; spec §4.3a (sub-tabs, the default, the Color list, the Adjustment
  section, the badge, the note), §9 (Insert ▸ Adjustment Clip), GR-6 (the
  "until GR4b" sentence gone, the risk rewritten) and its README row, the Lines
  cells; GRD-3 in `docs/manual-checks.md`; the README's Adjustment clips
  bullet, `add_adjustment_clip` in the op list and "eight pipelines from six".

**Sizes.** Product code +179 net: changed files +55 −20, new files
`EditorViewController+Adjustment.swift` 84 and `VideoPane+Adjustment.swift` 60.
With GR2–GR4a, about 1,893 of "Worth keeping"'s ≤ 4,500.
`EditorViewController.swift` 1,140 → 1,141 (wiring), `ClipPane.swift` 226 → 234,
`ClipPinnedBlock.swift` 240 → 243, `ClipPane+Matte.swift` 38 → 47,
`InspectorTab.swift` 73 → 81; `VideoPane.swift` (904) untouched.

**Measured.** 2026-10-10, Apple M2 Max, AC power.
- Loop, Debug: `make typecheck` 0 errors and the 4 baseline warnings;
  `inventory.py --check` 5/5; `v2_menu.py --only H` 5/5 (102 rows);
  `matte_chrome_probe.py` 10/10; `adjustment_proof.py --only
  I1,I2,I3,I4,S1,S2,S3,S4` 9/9 (with Z1); `graphics_menu_proof.py` 27/27;
  `clip_inspector2_proof.py` 33/33; `tone_proof.py --only P1,P2,P3,P4` 4/4;
  `screens.py --only 05b-clip-color,10c-matte-track,05c-clip-adjustment` 8/8,
  P2 passing (45 section ids pinned), 0 new layout problems;
  `spec_index_proof.py` 150/150.
- `make gate`: the first run failed in `test` on `graphic/`'s
  `determinism.rs` `a_frame_is_the_same_after_300_others` ("over the 250 ms
  budget at frame 285") under a load average of about 135 from another
  session's builds; this phase touches nothing in `graphic/`. The second run
  PASSED in 253 s (typecheck and fmt and lint skipped as passed, test 145 s,
  app 108 s).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release
  adjustment_proof.py` 36/36 (GR4a's 28 and GR4b's 8), no skip, no
  `DEFAULTS MOVED`, no `Reelcut: ` line.
- Mutants, each `adjustment_proof.py --mutant NAME` on Debug, all six MUTANT
  PASS (every named row failed, no other scored row did), on the final
  instrument, no `DEFAULTS MOVED`: `span-ignores-range` I1 I4 (34/36);
  `matte-front-taken` I3; `enabled-in-nest` I4; `picture-for-adjustment` I1 S1
  S2 (33/36); `strength-in-mixed` S2; `adjustment-note-gone` S4. GR4a's seven
  were not re-run: no anchor of theirs moved.

**Deviations.** A section header draws its title and puts no text in the
`snapshot_ui` layout dump, so S1's "the headers Adjustment, Light and Color top
to bottom" and S2's "has Light" read each section as the visible
`InspectorSection` holding a row of its own (Strength, Exposure, Brightness),
ordered by its frame; S1 also refuses "Scale" beside "Transform". The field reads
"75%". Project SP's image is a `render_frame` PNG of a shape it then deletes,
because `render_frame` has no frame of an empty timeline.

**Owed.** The `CLAUDE.md` lines (the spec kept every `CLAUDE.md` untouched):
the app map's `EditorViewController+Adjustment.swift` (Insert ▸ Adjustment
Clip, its span and track rule, its validator arm), `VideoPane.swift`'s
`+Adjustment`, `InspectorTab`'s four kind tests, `ClipPinnedBlock`'s `color`
rule ("every clip has source pixels or is an adjustment clip; never Picture
with one"), `ClipPane+Matte`'s adjustment note and `AppDelegate+GraphicMenu`'s
Insert holding Adjustment Clip; and GR4a's still-owed lines (root "eighty-nine
product tools" → ninety; the app map's `Compositor+Adjustment.swift`,
`AgentServer+Grading.swift`, `ClipSource.adjustment` and "eight pipelines from
six"; the core map's `edit_adjustment.rs` and `Source::Adjustment`, and
`op_table.rs`'s "fifty-nine op tools"). The person check GRD-3.

## GR5a — looks: `video.look`, the eight as core data, the GPU bake, step 4d (2026-10-10, on the `grading` branch)

**Where.** The worktree `~/devel/reelcut-grading`, branch `grading`, at `09b056c`
(GR4b). GR5 did not fit one spec and is split like GR4: GR5a (this) is the
model, the picture and the MCP mirror; GR5b is the Look section, its gallery and
Clip ▸ Look ▸. The owner's answer to GR5's thirteen choices was "All as
recommended" (2026-10-10), the eighth look Black & White (not Night).

**What landed.**
- Spec §11 first: GR-7 in `designs/spec/11-decisions/grading.md` (the thirteen
  choices with the eight looks' table, GR5b's marked [b]; the bake, the 33³
  `rgba16Float` lattice, step 4d, `texture(2)`, the 2³ placeholder, the uniform
  pair; the Concat rule restated) and its README row. Then §5.2 (`video.look`),
  §7.3 (the `look` key, twenty-three keys, `ungraded` removing it), §7.4 (the
  compositor row), §7.5 (step 4d, the bake, the pair), §7.9a (`ungraded`) and
  §7.10 (`model_look.rs`, `recipe_layer.rs`, `actions.rs`'s guard), and the
  index's Lines cells.
- Core: new `model_look.rs` (`LookKind`, `Look` — `kind` with no default,
  `amount` 1 by default — `SplitTone`, `LookDefinition`, `LOOK_DEFAULT_AMOUNT`,
  and `LookKind::definition`, GR-7's table as data), re-exported through
  `model_props.rs`; `VideoProps.look`, the group's last field, skipped when
  `None`. `props_check.rs` refuses an amount outside 0…1;
  `actions_clamp.rs` bounds an evaluated one (NaN to 0); `patch.rs`'s video
  template carries a look; `recipe_layer.rs` writes the `look` key after
  `color` (`look_json`: null for none, an amount of 0 or an ungraded frame,
  else kind, amount and the definition with all thirteen colour keys);
  `recipe.rs`'s `ungraded` removes it; `actions.rs`'s `evaluate_clip` turns a
  merged look that does not read as a `Look` into `null` beside the motion
  guard, so an end of `{look: {amount}}` on a look-less clip is inert and
  keeps its other animated keys. The format and header comments name
  `video.look`; the number stays 1015. New `core/tests/look.rs` (10);
  `recipe.rs`'s `LAYER_KEYS` at twenty-three; `ungraded.rs`'s fixture gains a
  clip look, an action end's look and an adjustment clip's look, and its twin
  drops `look` with `color`.
- App: new `LookProps.swift` (`LookKind`, `LookProps`, `LookPatch`,
  `SplitTone`, `LookDefinition`, `RecipeLook`, `LayerUniforms.apply(look:)`)
  and `LookTextures.swift` (`LookBakeUniforms`; the bake on its own queue,
  waited for; an LRU of eight under one `NSLock`; the 2³ identity
  placeholder written from the CPU; a failed bake answers the placeholder).
  `LayerUniforms`' `toneReserved0/1` became `lookAmount` and `lookEnabled`
  (still 116 floats, 464 bytes). `Compositor.metal`: the pair, `gradeLook`,
  `lookHueChroma`, `lookSplitTone`, `LookBakeUniforms`, step 4d after 4c in
  `layerColorPremultiplied` and in `reelcut_adjust_fragment`, `lookEnabled` in
  the gate sum, `texture(2)` on the three fragments, the kernel
  `reelcut_look_bake` at the end, and the order-of-operations line.
  `MetalRenderer.looks`; `drawLayer` binds the look before the shadow and the
  reflection, `encodeShadow` takes it to the mask pass, `drawAdjustment` binds
  it and `isNeutralAdjustment` needs no look. `VideoProps.look`,
  `RecipeLayer.look`, `VideoPatch.look` (`LookPatch??`). The eyedropper's
  suppression also sends `look: null`; `keyedCount` counts an end's `look` on
  Color and never on Picture; `set_video`'s catalog prose gains `lookClause`,
  its kinds from `LookKind.allCases`.
- Instruments: `look_proof.py` (18 scored rows and a record, seven mutants) and
  `look_probe.swift`, and the proof README's section.

**Sizes.** Product code about +710 net: changed Swift and Rust files +163 −49,
the shader +97 −11, the header +3 −2, new files `model_look.rs` 199,
`LookProps.swift` 150, `LookTextures.swift` 161. With GR2–GR4b, about 2,600 of
"Worth keeping"'s ≤ 4,500. `model_props.rs` 509 → 523, `recipe_layer.rs` 104 →
125, `actions.rs` 488 → 502, `ProjectSnapshot.swift` 1,784 → 1,783,
`Compositor.swift` 723 → 723, `CanvasSessions.swift` 1,090 → 1,090,
`TypedPatches.swift` 300 → 309, `AgentCatalog+Properties.swift` 252 → 266.

**Measured.** 2026-10-10, Apple M2 Max, macOS 26.5.1, AC power.
- Control: before any product edit, the untouched tree's `make app`, then
  `RC_PROOF_APP=release look_proof.py capture tools/proof/work/gr5/control`
  (four neutral frames: chart, adjustment, card, movie).
- Loop, Debug: `cargo test --release` for `look` 10/10, `recipe`, `ungraded`,
  `tone`, `adjustment`, `patch_door` all green; `make lint` clean; `make
  typecheck` 0 errors and the 4 baseline warnings; `look_proof.py` 17/17;
  `tone_proof.py --only P1,P2,P3,P4,E1,W1` 6/6; `adjustment_proof.py --only
  A1,G1,M1,O1` 5/5 (with Z1); `seeing_proof.py --only U1,U2` 2/2;
  `matte_spike.py --check --tree` every scored row; `spec_index_proof.py`
  150/150.
- `make gate`: PASS in 247 s (typecheck 5 s, fmt 2 s, lint 1 s, test 146 s,
  app 93 s).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release look_proof.py
  compare tools/proof/work/gr5/control` 18/18 — N0's four neutral frames
  byte-identical at 16 bits, so a look-less layer is unchanged — no
  `Reelcut: ` line, no `DEFAULTS MOVED`. D1's smallest pair is teal_orange
  against vivid, 19 levels; black_white moves a sample by 255.
- L4, the bake (each of the eight, a 33³ dispatch waited for): 0.29–0.65 ms on
  the Release run (0.22–0.42 ms on the Debug one); the first frame that needs a
  new definition pays it once.
- Mutants, each `look_proof.py --mutant NAME` on Debug, all seven MUTANT PASS
  (every named row failed, no other scored row did), no `DEFAULTS MOVED`:
  `look-before-tone` O1; `amount-ignored` M1 A1 U2 L3; `ungraded-keeps-look` U1
  CT; `adjustment-ignores-look` J1; `amount-range-dropped` R1 CT;
  `split-ignored` L5; `kindless-look-kept` CT. `amount-ignored`'s first run
  failed U2 and L3 beside its named M1 A1 — both correctly, since U2's amount
  0.5 and L3's read of `lookAmount` are what the mutant breaks — so its list was
  widened to the four and it was re-run on the final instrument.
- `make gate` again after the instrument and §7.5 edits: PASS in 73 s (test 72
  s, the rest skipped as passed).

**Deviations.** `amount-ignored` must fail M1 A1 U2 L3, not the spec's M1 A1
(above). U2's row reads a new kind keeping the clip's amount (`{kind:
vivid}` after M1 renders vivid at 0.5, neither M1's bytes nor D1's vivid), which
the spec's "undo/redo" leaves open; undo and redo are as written. The spec's
`designs/spec/07.10-rust-module-map.md` edit also names `actions.rs`'s look guard
in that file's `actions.rs` row. `Compositor.swift` holds net 0 by two comments
folded to one line each.

**Owed.** GR5b (the Look section and its gallery of `render_frame` thumbnails,
Clip ▸ Look ▸, the menu inventory rows, the screens' pins and prose, §4.3a and
§9, GRD-4, the README bullet, G1 gallery = `render_frame`); until it lands a look
is reachable only through MCP and Paste Attributes. The `CLAUDE.md` lines (the
spec kept every `CLAUDE.md` untouched): the app map's `LookProps.swift`,
`LookTextures.swift`, `LayerUniforms`' look pair and `texture(2)` on the three
layer-stage fragments; the core map's `model_look.rs` and `VideoProps.look`,
and "twenty-three" for the recipe layer's keys at `core/CLAUDE.md:475`; and
GR4a's and GR4b's still-owed lines above.

## GR5b — looks in the chrome: the Look section and its gallery, Clip ▸ Look ▸, screen 05d (2026-10-10, on the `grading` branch)

**Where.** The worktree `~/devel/reelcut-grading`, branch `grading`, at `e3e391e`
(GR5a). GR5b is the rest of GR5: GR-7's [b] items. The four user-visible points
GR-7 [b] left open were put to the owner and accepted "As described" on
2026-10-10, and are written into GR-7 [b] before the code: with an action
selected a tile, None, Reset and the menu change the clip's own look and only
Amount writes the action's end; a thumbnail renders the click's own op; the
menu dashes an item some but not all targets carry, the gallery outlines the
shared kind (None when no target has a look, nothing when mixed) and the summary
is "mixed" when kinds or amounts differ; thumbnails ignore Show Ungraded.

**What landed.**
- Spec first: GR-7 [b] (the four points, the undo names, the two dev seams) and
  its README row; §4.3a (Color lists Look; a *Look* bullet), §9 (Clip ▸ Look ▸
  after Motion ▸), §7.4 (the four new files; `select_inspector_tab`'s
  `section`, the dump default), §7.9a (`select_inspector_tab {tab?, sub_tab?,
  section?}`, `look_thumbnails_pending`, `-RCDevLookGalleryDump`), and the
  index's Lines cells.
- App: new `LookGallery.swift` (257: the targets — pixels and source pixels or
  an adjustment clip — the click's op `set_video {look: {kind}}` / `{look:
  null}`, the thumbnail time, `shared`, `summary`, the 0.3 s settle on a
  `.common` timer, render generations on one serial queue through
  `Exporter.renderFrame` at 256 px with `RecipeOptions.none`, a lock-guarded
  cancel token per generation, a weak registry for the playhead poke,
  `isPending`, the dev dump), `LookGalleryView.swift` (190: the 3×3 grid,
  `LookTileButton` with its aspect-fit thumbnail, name and accent outline; open
  from `isHiddenOrHasHiddenAncestor` on `viewDidHide` / `viewDidUnhide` /
  `viewDidMoveToWindow` and `refresh()`), `VideoPane+Look.swift` (47: the
  section and its Amount row, `allLooked`) and `EditorViewController+Look.swift`
  (64: `setLook:` and its validator, the Motion idiom's tags). Wiring:
  `ClipPane` keeps `lookGallery`, appends the section last on Color and adds
  `allLooked` to its signature; `inspectorPlayheadMoved` pokes the galleries
  before its guard; the frozen `EditorViewController.swift` +1 (the validator
  arm); `lookMenu()` and its row after Motion ▸; `UIMenuTable`'s `setLook:`;
  the dev tool's `section` and `look_thumbnails_pending`. Product Swift: the
  four new files 558 lines, changed files +120 −11. `ClipPane.swift` 234 →
  240, `AgentServer+InspectorTab.swift` 147 → 228, `AppDelegate+Menus.swift`
  504 → 508, `AppDelegate+ClipMenus.swift` 104 → 117,
  `EditorViewController+Inspector.swift` 396 → 399.
- Instruments: `look_proof.py` gains G1, G2, S1, S2, LM1–LM3, G3 and B1–B4
  with seven mutants; `look_probe.swift` B1–B4; `inventory.json`'s `setLook:`;
  `clip_inspector2_probe.swift`'s Color list; `v3_tools.py`'s L1 properties;
  `screens.py`'s `video.look` pin, `NOT_SHOWN` row and `look` fixture; screen
  05d and 05b's / 05c's waits and prose; GRD-4; the README's **Built-in looks**
  bullet; the proof README's section.

**Measured.** 2026-10-10, Apple M2 Max, AC power.
- Loop, Debug: `make typecheck` 0 errors and the 4 baseline warnings;
  `inventory.py --check` 5/5; `v2_menu.py --only H` 5/5 (103 rows);
  `clip_inspector2_proof.py` 33/33; `look_proof.py --only
  G1,G2,G3,S1,S2,LM1,LM2,LM3,B1,B2,B3,B4,Z1` 13/13 (G1's first generation
  naming MOVIE at 0.5 s was generation 1; S1's three tile rows at y 329, 403,
  477); `v3_tools.py --only L,T` 5/5; `screens.py --only
  05b-clip-color,05c-clip-adjustment,05d-clip-look` 8/8, P2 pass, 0 new
  problems, every PNG looked at; `spec_index_proof.py` 150/150.
- `make gate`: PASS in 194 s (typecheck 5 s, test 102 s, app 86 s; fmt and
  lint skipped as passed — no Rust changed).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release look_proof.py
  compare tools/proof/work/gr5/control` 30/30 — GR5a's rows (N0 still
  byte-identical) and GR5b's — no `Reelcut: ` line in either instance's log, no
  `DEFAULTS MOVED`. L4's bakes 0.26–0.55 ms.
- Mutants, each `look_proof.py --mutant NAME` on Debug, all seven MUTANT PASS
  on their first run (every named row failed, no other scored row did):
  `kind-drops-amount` G1 LM1 B3 B4; `menu-no-dash` B2;
  `gallery-ignores-playhead` G1 G2 B3; `renders-while-closed` G3;
  `amount-row-always` S2; `thumbnail-not-click` G1; `adjustment-not-a-target`
  LM3 B2. GR5a's seven were not re-run: none of their anchors moved.

**Deviations.** The spec's menu rows M1–M3 are LM1–LM3: GR5a's `look_proof.py`
already has an M1 (teal_orange at 0.5), and rows are keyed by name; the two
mutants that name them name LM1 and LM3. `v3_tools.py`'s T1 and T4 failed
before this phase's edit — GR2's Color sub-tab was never added to their
expected sub-tab lists — so T1's `[picture, color, sound, clip]` and `SUBS`
gained `color`, which the spec's targeted `v3_tools.py --only L,T` needs. A
`section` refusal puts back the tab and, when a sub-tab was picked, the sub-tab
it showed (through `selectClipSubTab`, so the pick is then explicit). The
gallery's outline reads the clips' own looks (what a tile writes, as the menu
reads); the summary, `differs` and `allLooked` read the evaluated look, as every
other section does. `AppDelegate+ClipMenus.swift`'s doc says "five builders".

**Owed.** The `CLAUDE.md` lines (the spec kept every `CLAUDE.md` untouched):
app/CLAUDE.md's map gains `LookGallery.swift`, `LookGalleryView.swift`,
`VideoPane+Look.swift` and `EditorViewController+Look.swift`, `ClipPane`'s
Color list (Light · Color · Look) and its `lookGallery`, the five Clip
submenus, `select_inspector_tab`'s `section` and `-RCDevLookGalleryDump`; and
its Hygiene list's one-frame render queues gain the gallery's
(`LookGallery.queue`, "a third one-frame render joins this entry"). GRD-4 is the
owner's. GR5a's, GR4a's and GR4b's still-owed lines above.

## GR6a — `.cube` LUTs: media of kind `lut`, the core's parser, a look at step 4d (2026-10-10, on the `grading` branch)

**Where.** The worktree `~/devel/reelcut-grading`, branch `grading`, at `c2b2794`
(GR5b). GR6 is split like GR4 and GR5: GR6a (this) is GR-8, the log/HDR check,
the core, the FFI, import, the picture, the Media tab's row and the MCP mirror;
GR6b is the Look gallery's Imported group and its "Import LUT…" button, Clip ▸
Look ▸'s LUT items, the Look summary naming the file, the screen, the README
bullet and its GRD row. The owner's answer to GR6's eleven choices was "All as
recommended" (2026-10-10), with no log clip to check.

**What landed.**
- Control first: the untouched tree's `make app`, then `RC_PROOF_APP=release
  look_proof.py capture tools/proof/work/gr6/control` (four neutral frames).
- T0, on that untouched Release build, before GR-8 and any product code (below).
- Spec §11 GR-8 in `designs/spec/11-decisions/grading.md` (the eleven choices,
  [b] marked, T0's finding, log unchecked) and its README rows. Then §4.3b (the
  Media tab's LUT row), §5.2 (`video.look`'s `lut` and `media`, `media[].kind`
  `lut`), §6b (the placing ops), §6c (`add_media`'s row rule, `remove_media`),
  §7.1 (the four `rc_cube_*`), §7.3 (the recipe's LUT look), §7.4 (the Swift
  rows), §7.5 (LUT textures and where a look finds its file), §7.7 (import),
  §7.9a (`import_media`'s note, `add_media`'s default), §7.10 (`cube.rs`,
  `ffi_cube.rs`, `lut.rs`, `model_look.rs`), and the index's Lines cells.
- Toll, first and alone (`make typecheck`): `RecipeOptions` out of
  `ReelCore.swift` into `RecipeOptions.swift`, `MediaKind` out of
  `ProjectSnapshot.swift` into `MediaSnapshot.swift`.
- Core: new `cube.rs` (`Cube::parse`, `CUBE_SIZE_MIN`/`MAX`, every refusal
  sentence; red fastest; `copy_rgb` length-checked), `ffi_cube.rs` (the four
  exports through `ffi_util.rs`'s `read_bytes`, `fallible_op`, `boxed`,
  `free_boxed`), `lut.rs` (`check_lut_fields`, `lut_not_placeable`,
  `normalise_look`, `look_media_ids`, `remap_look_media`,
  `Project::check_look_media`, `evaluates_as_look`, `remove_lut`).
  `format.rs`'s `RC_CUBE_MAX_BYTES` (the header's `#define`, equal by test) and
  the 1015 paragraph; `MediaKind::Lut`; `LookKind::Lut`, `Look.media` (stored
  between `kind` and `amount`, only when set), `ALL` → `BUILT_IN`,
  `definition()` → `Option`; `patch.rs`'s template look carries `media`;
  `edit_props.rs` normalises and checks; `actions.rs`'s object discriminants
  are `kind` and `media` and its look guard asks `evaluates_as_look`;
  `recipe_layer.rs` writes `{kind: "lut", amount, media}`; `edit_track.rs`
  checks a `lut` row and hands a LUT's removal to `remove_lut`; `edit_clip.rs`
  and `edit_background.rs` a `Lut` arm each; `model_query.rs`'s `validate`
  checks every clip's base look (`clip N: …`); `edit_paste.rs` absorbs the
  looks' LUTs after the sources' (a look id the payload lacks is skipped) and
  remaps base looks and ends; `edit_paste_attributes.rs` absorbs and remaps the
  source's LUTs before the video group lands, at the first target that takes
  it. `edit.rs`'s six rows. New `core/tests/cube.rs` (9) and `lut.rs` (12);
  `model_tests.rs`'s null sweep; `look.rs` names the nine; `relink.rs`'s serde
  list gains `lut`.
- App: `ReelCube.parse` in `ReelCore.swift`; `MediaKind.lut` ("LUT"); new
  `MediaImporter+LUT.swift` and `MediaImporter.probe`'s dispatch, a LUT getting
  no caches; Add Media… lists `lutType` (one line of the frozen
  `EditorViewController.swift`); new `LutTextures.swift`; `LookTextures.luts`
  and `lattice(for:urls:)`; `LookKind.lut`, `builtIns` (the gallery's, the
  menu's and the validator's one-line switches), `LookProps.media`,
  `RecipeLook.media`; `RecipeSource`'s per-key media URLs and
  `lookURLs(for:)`, published by `Playback.update`; `prepare` resolves
  `PreparedLayer.look` (zeroing `lookEnabled` when a LUT cannot be drawn),
  `drawLayer` binds it and `drawAdjustment` takes the URLs;
  `lookClause`, `remove_media`'s prose, `import_media`'s LUT note and
  `add_media`'s `has_video` default; `MediaUsage` counts base-look users;
  Remove's LUT alert; the row's cube glyph, its tooltip and no drag;
  Insert/Overwrite at Playhead off; `payloadMediaIDs`.
- Instruments: `lut_proof.py` (21 scored rows, T0's record, eight mutants) and
  `lut_probe.swift`; `look_proof.py`'s K1 expects the eight and `lut`, and its
  `kindless-look-kept` anchor follows the guard; `look_probe.swift`'s B1/B2
  and L4 walk `builtIns`; the proof README's sections; GRD-5.

**Sizes.** Product code (`app/Sources`, `core/src`, the header) +1,260 −193,
about +1,067 net, of which the two pure moves are ±0 and the new files are
`cube.rs` 234, `lut.rs` 237, `ffi_cube.rs` 79, `LutTextures.swift` 132,
`MediaImporter+LUT.swift` 58 (`RecipeOptions.swift` 42 moved). With GR2–GR5b
(about 3,270 by their records: 2,600 through GR5a, GR5b's ~670) about 4,340 of
"Worth keeping"'s ≤ 4,500 — GR6b and GR7 have about 160 left. Over-cap files: `ReelCore.swift` 995
→ 989, `ProjectSnapshot.swift` 1,783 → 1,769, `MediaImporter.swift` 591 → 593,
`Playback.swift` 587 → 588, `AgentCatalog+Files.swift` 579 → 579,
`edit_clip.rs` 755 → 757 (two match arms), `EditorViewController.swift` one
line changed.

**Measured.** 2026-10-10, Apple M2 Max, macOS 26.5.1, AC power.
- **T0** (the untouched Release build, then each run since, identical): one
  10-bit ProRes 422 chart, re-tagged by stream copy. **AVFoundation reads only
  the container's `colr` atom**: every tag in the ProRes frame headers alone
  drew the untagged frame's bytes (max |Δ| 0). With `colr`: HLG and PQ keep
  the grey ramp unchanged (grey 129 → 129; no transfer conversion; red 255 →
  243 by the BT.2020 matrix), max |Δ| 13 against `colr`-tagged BT.709;
  BT.2020 primaries with the BT.709 transfer draw grey 129 as 66 — linearised
  (BT.709's inverse OETF of 0.506 is 0.265, ≈ 67) — max |Δ| 63; untagged
  against `colr`-tagged BT.709, up to 22 on saturated patches (red 234 against
  255). Log is unchecked. ffmpeg's `prores_metadata` writes "untagged" as 0
  (ffprobe reads `gbr`/`reserved`), its one non-tag value.
- Loop, Debug: `cargo test --release --test cube --test lut --test look --test
  relink --test paste --test patch_door --test model_tests --test recipe
  --test ungraded --test adjustment` all green; `make lint` clean; `make
  typecheck` 0 errors and the 4 baseline warnings; `lut_proof.py` 21/21;
  `look_proof.py --only R1,K1,M1,J1,G1,LM1,LM2,B2` 8/8 (after B2's walk moved
  to `builtIns`); `spec_index_proof.py` 150/150.
- `make gate`: PASS in 232 s (typecheck 4 s, fmt 2 s, lint 4 s, test 132 s,
  app 88 s).
- Recorded, on the gate's Release build: `RC_PROOF_APP=release lut_proof.py`
  21/21 and T0's record, no `Reelcut: ` line, no `DEFAULTS MOVED`; F1's
  smooth LUTs within 1 level of ffmpeg's trilinear `lut3d` at every sample
  (17, 33 and 65). `RC_PROOF_APP=release look_proof.py compare
  tools/proof/work/gr6/control` 30/30, N0's four neutral frames byte-identical
  at 16 bits — the draw path's change leaves a look-less layer unchanged.
- Mutants, each `lut_proof.py --mutant NAME` on Debug on the final instrument,
  all eight MUTANT PASS on their first run (every named row failed, no other
  scored row did), no `DEFAULTS MOVED`: `blue-fastest` N1 S1 A1 F1 T1;
  `domain-ignored` R1 CT; `size-cap-dropped` R1 CT; `media-interpolates` X1
  CT; `builtin-keeps-media` K1 CT; `remove-deletes-clips` D1 CT;
  `paste-not-remapped` P1 CT; `urls-from-instruction` P3.

**Deviations.** M1 deletes the LUT's file rather than renaming it: the media's
bookmark follows a rename, so a renamed file is never missing; the relink is to
the same bytes at a new path. T0 tags each movie twice — in the ProRes headers
alone (the spec's `-bsf:v prores_metadata`) and again with the container's
`colr` atom (stream options with `+write_colr` under the same `-c copy`) —
because the first measurement found AVFoundation reads only the atom; both are
recorded. `add_background` refuses a LUT as a media with no pixel size (its
existing check runs before its source match), not in `lut_not_placeable`'s
words; GR-8 says so. `check_look_media`'s kind sentence takes "an" before a
vowel (`is an image media, not a lut`). `probeLUT` answers an unreadable file
as `undecodable` ("Could not read NAME.") too, so a `.cube` is never offered to
the ffmpeg step. The Media row's tooltip says "A LUT: apply it to clips as a
look." instead of the drag hint, and its context menu's Insert and Overwrite
are off as the Edit menu's are. `drawAdjustment` draws nothing when a LUT look
is its only grade and cannot be drawn (`isNeutralAdjustment(drawsLook:)`).
`look_probe.swift` (outside the spec's file list) walks `builtIns` in B1/B2 and
L4, which B2 needs: a touched instrument, against the spec's "the probes compile
unchanged", so look_proof's history runs through this phase. `paste_attributes` now checks each copied group against the
project being built (`next`), which holds an absorbed LUT, rather than `self`.

**Owed.** GR6b (above); GRD-5 is the owner's. The `CLAUDE.md` lines (the spec
kept every `CLAUDE.md` untouched): app/CLAUDE.md's map gains
`RecipeOptions.swift`, `MediaImporter+LUT.swift`, `LutTextures.swift`,
`LookKind.builtIns`, `RecipeSource`'s media URLs and `MediaUsage`'s look users;
core/CLAUDE.md's map gains `cube.rs`, `ffi_cube.rs`, `lut.rs` and
`MediaKind::Lut`, `model_look.rs`'s `lut` and `media`, and `actions.rs`'s
object discriminants. GR5b's, GR5a's, GR4a's and GR4b's still-owed lines above.

## GR6b — imported LUTs in the chrome: the Imported group, Import LUT…, Clip ▸ Look ▸'s LUT items, screen 05e (2026-10-10, on the `grading` branch)

The rest of GR6: GR-8's [b] items (choices 1 and 3), app-side and documents
only — no core, FFI, op, tool or format change (`set_video {look: {kind: "lut",
media}}` already carried it from GR6a).

**What landed.**
- Spec first: GR-8 [b] gains "How GR6b reads choices 1 and 3" (Media-tab order
  is the media list's own order; the menu's eight · separator · LUTs ·
  separator · None, unchanged with no LUT; a missing LUT keeps its tile and
  item; Import LUT…'s place, enabling, reuse of a listed file and refusal
  sheet; the titles; the summary "<name> 80%"). Then §4.3a (the Look bullet),
  §9 (Look ▸'s LUT items), §7.4 (the Look row, `LookMenuFiller`,
  `UIMenu.fillDynamic`), §7.9a (the dump's `lut-<id>` and manifest `tiles`;
  perform_menu_item fills Look ▸ for the named window) and the index's Lines.
- App: `LookPatch.media`; `LookGallery.luts(in:)`, `lutName(_:)`,
  `op(lut:clips:)`, `summary(_:names:)` and `lutThumbnails` — a generation
  renders the nine and then one trial per LUT, and the dump writes
  `lut-<id>.png` and `tiles`; `LookGalleryView`'s "Imported" label, `lutTiles`
  in rows of three (each tile the built-in tiles' width, so a short row keeps
  third-width tiles) and `importButton` ("Import LUT…", on exactly when there
  is a target), a LUT tile outlined when every target's own look is that LUT;
  `VideoPane+Look` passes `onPickLUT` (undo "Look") and `onImport` (the
  inspector's `onCommand` with `importLUT:`) and the summary's names;
  `ClipPane`'s signature gains `id=name` per LUT; `EditorViewController+Look`'s
  `lookLUTTag` (−2, `representedObject` the id), `setLook:` and the validator
  for a LUT item, `importLUT(_:)` (a sheet `NSOpenPanel` over
  `MediaImporter.lutType`) and `importLUT(from:into:clips:)` (the probe,
  `backgroundMedia(for:in:)` against `document.project`, then ONE
  `performGroupedEdit("Import LUT", [add_media, set_video])`; a refusal is
  `document.present`); `AppDelegate+ClipMenus`'s `LookMenuFiller`, the Look
  menu's delegate, rewriting the rows between the eight's separator and None
  when it opens; `UIMenu.fillDynamic`, called by `lookup`'s per-level
  `validate` and by `listing`; `AgentServer+Media`'s `import_media` comment
  naming the UI path it mirrors with `set_video`.
- Instruments: `lut_proof.py` gains LG1, LG2, LM4 and probe rows P4–P7 (project
  LG, saved first as LG0 for the probe), its instance launched with
  `look_proof.pins(closed=False, dump=WORK/dump)`, and nine mutants;
  `lut_probe.swift` gains P4–P7; `capture_spike/inventory.json` one site row
  (`importLUT`'s `beginSheetModal`, `reached_from: []`, the Look section's
  button as `other_caller`); `screens.py`'s `lut` fixture (two size-2 `.cube`
  files the script writes, "Warm Print" and "Bleach") and screen 05e; 05d's
  prose; the screens README's fixture row; the proof README's section;
  `look_proof.pins` also pins `ReelcutInspectorWidth` 304 (below).
- Documents: README's **Imported LUTs** bullet; GRD-6 (new) and GRD-5's step 4
  through the gallery rather than MCP.

**Sizes.** Product code (`git diff --numstat 9d237f0 -- app/Sources core/src
core/include app/Resources/Shaders`) +267 −47, **220 net**:
`EditorViewController+Look.swift` +68 −10 (64 → 122), `LookGalleryView.swift`
+64 −7 (190 → 247), `LookGallery.swift` +51 −16 (261 → 296),
`AppDelegate+ClipMenus.swift` +36 (117 → 153), `VideoPane+Look.swift` +20 −8,
`UIMenu.swift` +14 −1 (264 → 277), `LookProps.swift` +9 −5, `ClipPane.swift` +3
(240 → 243), `AgentServer+Media.swift` +2 (the comment; 421 → 423, already over
the 400-line new-file cap before it). No frozen file touched, no new Swift file.
**The running total is about 4,560 of "Worth keeping"'s ≤ 4,500 — the cap is
missed by about 60 lines** (GR2–GR6a about 4,340 by their records, plus GR6b's
220). The owner said "Build GR6b, record the overage" (2026-10-10); GR7's
verdict reads this figure.

**Measured.** 2026-10-10, Apple M2 Max, AC power.
- Loop, Debug: `make typecheck` 0 errors and the 4 baseline warnings;
  `spec_index_proof.py` 150/150; `inventory.py --check` 5/5 (49 grep sites);
  `v2_menu.py --only H` 5/5 (103 rows, as before); `lut_proof.py --only
  LG1,LG2,LM4,P4,P5,P6,P7,Z1` 7/8 on the first build — LG2 found an ambiguous
  `NSStackView` (the LUT row, gravity areas) — then `--only LG2,Z1` 2/2 after the
  row took `distribution = .fill`; `look_proof.py --only
  G1,G2,G3,S1,S2,LM1,LM2,LM3,B1,B2,B3,B4,Z1` 13/13 (S1's rows at y 329, 403,
  477, as GR5b's); `screens.py --only 05d-clip-look,05e-clip-look-lut` 7/7,
  both screens pass in both looks, 0 new problems, every PNG looked at.
- `make gate`: PASS in 257 s, and again in 296 s after the filler's last edit
  (typecheck 8 s, test 156 s, app 130 s; fmt and lint skipped — no Rust).
- Recorded, on the gate's Release build, on the final instrument:
  `RC_PROOF_APP=release lut_proof.py` 28/28 and T0's record (GR6a's rows and
  GR6b's; LG1 generation 2 with tiles none, the eight, `lut-4`, `lut-5`; LG2's
  LUT names on one row at y 527 under "Imported" at 456 and over the button at
  547), no `Reelcut: ` line, no `DEFAULTS MOVED`; `RC_PROOF_APP=release
  look_proof.py --only G1,G2,G3,S1,S2,LM1,LM2,LM3,B1,B2,B3,B4,Z1` 13/13.
- Mutants, each `lut_proof.py --mutant NAME` on Debug on the final instrument,
  all nine MUTANT PASS (every named row failed, no other scored row did), no
  `DEFAULTS MOVED`: `luts-reversed` LG1 LG2 LM4 P4 P5 P6;
  `name-keeps-extension` LG2 LM4 P4 P5 P6; `menu-no-luts` LM4 P5;
  `signature-ignores-luts` LG2; `lut-tile-amount-one` LG1;
  `lut-outline-any-lut` P6; `import-two-steps` P7 (step ii: one undo left the
  row); `import-new-id-always` P7 (step iv: the unminted id was refused, so the
  look stayed warm); `summary-says-lut` P4 P6. `menu-no-luts`' first run crashed
  the filler (an insert past the menu's end) and so failed other rows; the
  filler now inserts at a running index, the mutant removes that insert, and it
  then passed.
- Review fix pass (Import LUT… made the square `StickerButton`; the unused
  `window` parameter dropped from `importLUT(from:into:clips:)`): `make
  typecheck` the 4 baseline warnings; Debug `lut_proof.py --only
  LG1,LG2,LM4,P4,P5,P6,P7,Z1` 8/8 (the button at 94 × 22); `screens.py --only
  05d-clip-look,05e-clip-look-lut` 7/7, 0 new problems, every PNG looked at
  (the button square and bordered in both looks); `make gate` PASS in 203 s;
  then on its Release build `RC_PROOF_APP=release lut_proof.py` 28/28 (LG2's
  names at y 525 under "Imported" at 454, over the button at 545) and
  `look_proof.py --only G1,G2,G3,S1,S2,LM1,LM2,LM3,B1,B2,B3,B4,Z1` 13/13 (S1's
  rows 329, 403, 477), no `Reelcut: ` line, no `DEFAULTS MOVED`. No mutant's
  anchor line changed, so the nine were not re-run.

**Deviations.**
- **The summary is not read over MCP.** The section's header DRAWS its summary
  (`InspectorSectionHeader.drawSummary`), so no view and no layout-dump text
  holds "swap-33 80%". LG2 does not check it; P6 reads the Look section header's
  summary in a headless pane ("pA 80%", by `Mirror` over its private
  `lastSummary`). So `summary-says-lut` fails P4 P6, not the spec's LG2 P4.
- LG2 reads "Imported" as a label of its own, under every built-in tile name and
  over the LUT tiles, rather than on one row with them.
- `LookMenuFiller.fill(_:luts:)` is static, so it builds a LUT item with
  `NSMenuItem` (title, `setLook:`, no key, tag −2) rather than
  `AppDelegate.tagged`, which needs an instance.
- `look_proof.pins` (outside the spec's files) also pins
  `ReelcutInspectorWidth` to 304, screens.py's value: the Release run's S1 failed
  "inside False" with tile rows 96 pt apart, against 74 on Debug — the Release
  domain holds a wider inspector, so the third row fell below the captured
  inspector. Host state, not GR6b; with the pin, Release 13/13 (rows 329, 403,
  477). lut_proof shares the pins.
- Import LUT… is the house square block (`StickerButton`, secondary, at the
  inspector's 22 pt control height, `DS.sans(11)`), as the sharp pass's README
  rules for chrome; the first build's small rounded system bezel was a review
  finding, fixed before the recorded runs. Still an `NSButton`, so the layout
  dump reads its title and P6 its `isEnabled`. `importLUT(from:into:clips:)`
  takes no window: errors go through `document.present`.

**Owed.** GRD-6 and GRD-5 are the owner's; GR7. The `CLAUDE.md` lines (the spec
kept every `CLAUDE.md` untouched): app/CLAUDE.md's Look row gains
`LookMenuFiller` (Clip ▸ Look ▸'s LUT rows, filled when it opens), the
Imported group and Import LUT… (`importLUT`, one undo step "Import LUT"), and
the dump's `lut-<id>` and `tiles`; its dev-tools entry gains
`UIMenu.fillDynamic`. GR6a's, GR5b's, GR5a's, GR4a's and GR4b's still-owed
lines above.

## GR7a — the verdict's figures: every cap measured, T4's script half, the trial guide (2026-10-10, on the `grading` branch)

**Where.** The `grading` branch at 892bfd1, against main at the branch point
`f407f87`. Main's comparison build came only from a throwaway `git worktree
add --detach tools/proof/work/gr7/main f407f87` and a cold `make app` there
(`grading_verdict.py main-tree make`: built in 169 s, load `{ 4.82 5.86 12.83 }`
before and `{ 49.52 34.59 24.06 }` after), removed at the end by `main-tree
remove` (`tree_copy.remove_tree`, then `git worktree prune`; `git worktree
list` no longer shows it). The branch's side is the gate's Release build. No
product code changed; no verdict is written here — it is GR7b's, the owner's.

**What landed.**
- `tools/proof/grading_verdict.py` (new): `sizes` (L1–L4, git only, `work/gr7/sizes.json`),
  `main-tree make|remove`, and `measure` (H0, M1, G0, E1, E2, F4, T4, T4c, Z1)
  with four mutants; the module doc is the row list.
- `tools/proof/grading_spike/tree_bench.swift` (new) and `grading_spike.py
  --tree`: GR0's GPU method on two libraries, V0 (`Compositor.metal` at
  `f407f87`) and VT (the tree's own, unpatched), both handed the app's whole
  464-byte `LayerUniforms`; rows B0–B2, KT, and with `--measure` H0, C0, F, T0
  and TC; mutant `tree-graded`. The default mode is unchanged (`--check`: B0–B2
  and 44 K rows pass).
- Instruments' READMEs: `grading_spike/README.md`'s `--tree` section and the
  proof README's "Road map grading — GR7a, the verdict's figures".
- This document: the caps table's "Measured (GR7a)" column, the Phases table's
  GR7 split into GR7a and GR7b, "The owner's trial guide (GR7)" under "Worth
  keeping"; `docs/manual-checks.md`'s Grading section points to the guide.
- Scratch, never committed, under the gitignored `tools/proof/work/gr7/`: the
  movie `media/testsrc2_1080_10s.mp4` (ffmpeg `testsrc2` 1920×1080, 30 fps,
  10 s, libx264 yuv420p CRF 18, BT.709 tags) and the LUT
  `luts/gr7-camera-33.cube`, written from textbook maths only (33³, red
  fastest: a smoothstep S-curve mixed at 0.5, gains 1.06 / 1.0 / 0.92,
  saturation 1.2 about the Rec. 709 luma, a clamp; the Concat rule).

**Host.** Apple M2 Max, macOS 26.5.1, `pmset -g` powermode 0, drawing from AC
Power, for every command below. The load was high from other sessions
(`ps` before the recorded runs: another session's Rasterize test binary,
`mediaanalysisd` and `spindump`, about one core each); each command's load before and after
is in the table.

| Measure | Cap | Measured | Held or missed by | Command (load before → after) |
|---|---|---|---|---|
| Product code, net lines GR2–GR6b | ≤ 4,500 | 4,528 (+4,878 −350; `app/Sources` +3,161 −244 = 2,917, `core/src` +1,480 −96 = 1,384, `app/Resources/Shaders` +237 −10 = 227, both shaders listed); `core/include` +56 −6 = 50 beside it, outside it | **missed by 28 lines** | `python3 tools/proof/grading_verdict.py sizes` L1 (`{ 18.06 28.25 23.77 }` → `{ 17.26 27.91 23.68 }`) |
| Frozen files | ~50 each | `EditorViewController.swift` 1,139 → 1,142 (+4 −1); `TimelineView.swift` 1,682 → 1,682 (+1 −1); `PreviewCanvasView.swift` 1,124 (untouched); `AgentServer.swift` 785 → 785 (+2 −2); `InspectorViewController.swift` 355 (untouched); together net 3 | held | `sizes` L2 |
| Files over the cap | none unpaid | unpaid: `ProjectSnapshot.swift` 1,750 → 1,769 (+19), `edit_clip.rs` 755 → 757 (+2). Paid (net ≤ 0): `AgentServer+Clips.swift` 636 → 636, `CanvasSessions.swift` 1,090 → 1,090, `Compositor.swift` 724 → 723, `ReelCore.swift` 999 → 989. Exempt: `ReelOps.swift` 1,222 → 1,234, `edit.rs` 931 → 946. Frozen (L2's): `AgentServer.swift`, `EditorViewController.swift`, `TimelineView.swift`. No new file over 400 | **missed by 2 files** | `sizes` L3 |
| Inspector | one sub-tab (Color), ≤ 4 sections; Picture −Color, +nothing | sub-tabs `text, shape, graphic, picture, sound, clip` → `… picture, color, sound, clip`; Color's `lightSection`, `colorSection`, `adjustmentSection`, `lookSection` (4); Picture lost `colorSection`, gained none | held | `sizes` L4 |
| Menus | Clip ▸ Look ▸, Insert ▸ Adjustment Clip, View ▸ Show Ungraded, View ▸ Waveform | main 175 leaves, the branch 187: Clip ▸ Look ▸ 9 (Black & White, Cool, Dramatic, Faded, None, Teal & Orange, Vintage, Vivid, Warm), Insert ▸ Adjustment Clip, View ▸ Show Ungraded, View ▸ Waveform; none removed | held | `RC_PROOF_APP=release perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_verdict.py measure --only H0,M1,G0,E1,E2,Z1` M1 (`{ 15.22 27.13 23.45 }` → `{ 8.35 22.52 21.99 }`) |
| An UNGRADED layer | +0.02 ms at 1080p, +0.06 ms at 4K, plus C0 | VT:S1 − V0:S1 = 0.009 ms at 1080p (V0 0.119, VT 0.127, runs 0.119–0.199 ms) and 0.002 ms at 4K (V0 0.479, VT 0.481 ms); C0 noise 0.000 ms at both; KT: VT's S1 = V0's exactly (max \|Δ\| 0.0) at both sizes | held | `perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_spike/grading_spike.py --measure --tree` TC (`{ 17.26 27.91 23.68 }` → `{ 16.19 27.52 23.56 }`) |
| An ungraded project's export | ≤ 2 % over main | fixture U (60 s at 1080p, two video tracks, the upper at scale 0.5), h264, three rounds alternated: main 5.98 / 5.98 / 5.98 s (spread 0.0 %), the branch 6.00 / 6.00 / 6.02 s (spread 0.3 %); `median(bU)/median(mU) − 1` = +0.33 % | held | `measure` E1 (same command as M1) |
| A graded 60 s export | ≤ 10 % over ungraded | fixture G (U, every clip at GR0's ST tone and `teal_orange` 0.8, a front adjustment clip at exposure 0.2, vibrance 0.2): 5.97 / 6.01 / 5.99 s (spread 0.7 %) against U's 6.00 s median; −0.17 % | held | `measure` E2 (same command) |
| A graded frame | ≤ 8 ms at 1080p | fixture F (20 s, four full-frame tracks at ST with warm, cool, teal_orange, vivid at 0.8, and a front adjustment clip at exposure 0.2), three exports: compositor averages 2.712 / 2.724 / 2.792 ms over 5 windows of 120 frames each, worst windows 7.07 / 7.70 / 7.70 ms; median average 2.724 ms | held | `RC_PROOF_APP=release perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_verdict.py measure --only H0,F4,T4,Z1` F4 (`{ 7.84 22.18 21.88 }` → `{ 8.28 21.80 21.74 }`) |

The graded-against-ungraded fixtures are told apart before any time is taken:
G0, `render_frame` at 0.5 s of G against U, max |Δ| 87 levels (at (1445,
680), blue; must exceed 8), and G holds one adjustment clip. **The exports are
encoder-bound at these sizes**: every 60 s export took 5.97–6.02 s whatever
its grade, while the compositor's averages in the same runs moved — main's U
1.245–1.275 ms, the branch's U 1.277–1.313 ms, G 1.697–1.735 ms per frame. So
E1 and E2 say the grade costs no export time on this fixture, not that the
compositor does no more work; F4 is the frame-time figure.

**L1 per commit**, `git diff --numstat <commit>^1 <commit>` over the three
capped roots (the records' own figures, which some took with the header, in
brackets): GR2 99c0d8f +512 −66, net 446 (about 448); the merge 0545902 net 0;
GR3 6ecf46c +841 −35, net 806 (about 806); GR4a a5a6cdf +528 −68, net 460
(about 460); GR4b 09b056c +201 −20, net 181 (179); GR5a e3e391e +772 −60, net
712 (about 710); GR5b c2b2794 +682 −11, net 671 (about 670 by GR6a's record;
its own: 558 new, +120 −11 changed); GR6a 9d237f0 +1,224 −192, net 1,032 (about 1,067, with the
header); GR6b 892bfd1 +268 −48, net 220 (220). The records summed to about
4,560; the measured total over the cap's own roots is 4,528.

**T4's script half.** Project T (the movie at 0, 1920×1080) at 0.5 s through
`gr7-camera-33.cube` at amount 1 (`set_video {look: {kind: "lut", media,
amount: 1}}`, then `render_frame`) against `ffmpeg -i t4-neutral.png -vf
lut3d=file=…:interp=trilinear` on the neutral frame, both decoded to `rgb24`:
**max |Δ| 2 levels** (at (78, 6), green) over 1920×1080×3 — within ±2, T4
PASS. The CONTROL T4c: the neutral frame against ffmpeg's is 56 levels away
(at (1, 2), red), so the LUT moves the frame. (`measure --only H0,F4,T4,Z1`.)
The owner's own LUT is his to give: `measure --only T4 --lut PATH` adds its
figure as a recorded line, and needs no main build.

**T5: the owner's; no live run** (a paid call), on his own key and budget.

**Verified.**
- Loop: `grading_verdict.py sizes` exit 0; `grading_spike.py --check --tree`
  exit 0 (B0–B2, KT at both sizes, max |Δ| 0.0); `grading_spike.py --check`
  exit 0 (B0–B2 and 44 K rows, the default mode unchanged); `main-tree make`
  exit 0; `RC_PROOF_APP=release grading_verdict.py measure --rounds 1 --seconds
  10` exit 0, every row PASS (before the review's fix pass; on today's
  instrument F4 is a named SKIP under `--rounds 1`).
- `make gate`: PASS in 66 s (test 65 s; typecheck, fmt, lint and app skipped
  as byte-identical to their last pass — no product input changed), and again
  PASS in 66 s after this record and `docs/manual-checks.md` (a test input)
  were written.
- Recorded, on the gate's Release build, before the review's fix pass: `sizes` exit 0;
  `grading_spike.py --measure --tree` exit 0; `measure --only
  H0,M1,G0,E1,E2,Z1` exit 0 (11 projects closed, 12 logs, no `Reelcut: ` line);
  `measure --only H0,F4,T4,Z1` exit 0 (4 projects closed, 4 logs, no `Reelcut: `
  line). No run printed `DEFAULTS MOVED`; every instance ran under the scratch
  `CFFIXED_USER_HOME` and was stopped by its own pid.
- Mutants, each once on the final instrument, each killed by exactly its
  row: `sizes --mutant shader-not-counted` L1 (the shader root unlisted);
  `measure --only M1,Z1 --mutant menus-same-app` M1 (175 leaves on both sides,
  all four paths missing); `measure --only G0,Z1 --seconds 10 --mutant
  graded-fixture-ungraded` G0 (max |Δ| 0, the adjustment clip still 1);
  `measure --only T4,Z1 --mutant lut-not-applied` T4 (56 levels; T4c still
  PASS); `grading_spike.py --check --tree --mutant tree-graded` KT (0.1416,
  i.e. 144.9 / 1023, at both sizes).
- Review fix pass (`grading_verdict.py` only): `numstat` runs with
  `--no-renames` and L3 fails on a changed path it cannot read at HEAD; ffmpeg
  reads a copy of the LUT under a fixed name, so no character of the owner's
  path reaches the filter graph; `--lut` is expanded, resolved and refused
  unless a file; F4 under three exports is a named SKIP; M1 prints `added
  none`; frame decoding runs under `bounded.run`. Re-run on the fixed
  instrument, each exit 0: `sizes` (output unchanged) and its
  `shader-not-counted` mutant (killed by L1); `measure --only H0,F4,T4,Z1`
  (F4 PASS, T4 PASS 2 levels); `--only G0,Z1` (87 levels); `--lut` with a
  path holding an apostrophe and colons (T4 PASS, 2 levels); the
  `lut-not-applied` mutant (killed by T4); `make gate`. Not re-run: M1, E1
  and E2, whose main build had been removed, and whose measuring code did not
  change (M1's only change is its printed text). The recorded F4 figure,
  2.724 ms, is the earlier run's: F4's measuring code did not change, and the
  fix pass's run was taken at a load of 70–133 from another session.

**Owed.** GR7b: the owner's trial (T1–T6 and GRD-1…GRD-6 by the trial guide
above), T4's figure on his own LUT, T5 on his own key, and the verdict. The
two caps missed — product code by 28 lines, two files over the cap that grew
(`ProjectSnapshot.swift` +19, `edit_clip.rs` +2) — are for that verdict, not
fixed here. The still-owed `CLAUDE.md` lines are GR2's through GR6b's, each in
its own record above; GR7a adds none.

**L3 paid (grading L3, after GR7a).** Two pure moves, no op, schema,
catalog, format or render change. `StrokeProps`, `GradientStop`, `Gradient`
and `ShapeProps` went whole from `ProjectSnapshot.swift` to a new
`ShapeProps.swift` (`import Foundation`, nothing lost `private`);
`detach_audio` and `set_enabled`, with the `// ---- enablement` banner, went
from `core/src/edit_clip.rs` to a new `core/src/edit_detach.rs` inside its own
`impl Project` (`mod edit_detach;` in `lib.rs`, nothing widened; the banner
left above `set_reversed` now reads `reversal`). `wc -l`:
`ProjectSnapshot.swift` 1,769 → 1,570 (1,750 at `f407f87`), `edit_clip.rs`
757 → 661 (755 at `f407f87`); `ShapeProps.swift` is 204 and `edit_detach.rs`
108, both under the new-file cap. L1's product-code net rises by the moves'
header lines: `git diff --numstat --no-renames f407f87 -- app/Sources core/src
app/Resources/Shaders`, with the two new files intent-added in a scratch copy
of the index, sums to +5,194 −648 = **4,546** (`app/Sources` 2,922, `core/src`
1,397, the shaders 227), 18 over GR7a's 4,528: `ShapeProps.swift`'s header +5
net, `edit_detach.rs`'s module doc, `use` lines and `impl` braces against
`edit_clip.rs`'s one added doc line +12, `lib.rs` +1. Verified: `make
typecheck` exit 0 with exactly the four baseline warnings; the two moved
blocks byte-identical (`diff` of `HEAD`'s `ProjectSnapshot.swift` lines
1025–1222 against `ShapeProps.swift`'s last 198 lines, and of `HEAD`'s
`edit_clip.rs` lines 661–756 against `edit_detach.rs`'s `impl` body, both
empty); `cargo fmt --check`, `cargo test --release --test edit_tests
detach_audio` (2 passed), `--test refusal_non_edits` (9 passed) and `--test
op_default_booleans` (5 passed), `make lint` and `spec_index_proof.py`
(150/150) exit 0; `make gate` PASS in 221 s (typecheck, fmt, lint, test 126 s,
app 86 s). `grading_verdict.py sizes` reads committed `HEAD`, so its L3 lines
cannot exist before this commit. Run after it at 6f68daa: L3 PASS, "0
unpaid against none: cap held" (`ProjectSnapshot.swift` 1750 → 1570,
`edit_clip.rs` 755 → 661, both paid; the frozen files referred to L2; the two
tables exempt); L1 "net 4546 against ≤ 4500: cap missed by 46 lines". No
mutants: a pure move adds no decision. The `CLAUDE.md` maps were updated in
the same commit (`edit_detach.rs`, `ShapeProps.swift`).

**The product-lines budget removed (owner, 2026-10-10).** "We need as much
code as we need." The brief's ≤ 4,500 net-line budget is gone from "What it
may cost" and from `grading_verdict.py` (L1 now prints the totals as a record:
4,546 net at e969058); the root `CLAUDE.md` now says size rules are per file,
never per feature. The phase records above that measure a running total
against that budget are history, kept as written.
