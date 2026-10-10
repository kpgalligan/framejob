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

| Measure | Cap |
|---|---|
| Frozen files | Wiring only; no frozen file grows by more than ~50 lines in total |
| Files over the cap | None left unpaid |
| Inspector | One new sub-tab (Color) of at most four sections; Picture loses one section (Color) and gains none |
| Menus | Clip ▸ Look ▸, Insert ▸ Adjustment Clip, View ▸ Show Ungraded, View ▸ Waveform; nothing else |
| An UNGRADED layer | At most +0.02 ms at 1080p and +0.06 ms at 4K over main, by the matte spike's method (the placeholder's 0.054 ms at 4K is the precedent) |
| An ungraded project's export | Within 2 % of main's time on one fixture, three runs |
| A graded frame | Four graded full-frame layers and one adjustment clip at 1080p within the 8 ms budget; a graded 60 s 1080p fixture exports at most 10 % slower than ungraded |

Kept if T1–T5 succeed, the owner says he would reach for it again, and every
cap holds. A missed cap is a conversation, not an automatic no: the record says
which cap and by how much.

("Section 1" and "section 9" are the brief's: section 1 is "Tier 1 as answered"
above, section 9 the brief's cost figures, quoted under GR0.)

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
| GR6 | branch | GR-8, then **LUT import**: a one-file check first (does AVFoundation hand the compositor a log or HLG file's code values unchanged?); `MediaKind::Lut` through every site, `cube.rs`, the FFI export, parser tests; `MediaImporter+LUT.swift`, the Media tab's glyph and count, Consolidate, relink, the Look gallery's Imported group. | An identity `.cube` exact; a channel swap exact on lattice values; sizes 2 and 65; refusals by name; a missing file draws ungraded; `remove_media` clears the looks; a paste across documents. |
| GR7 | branch | The owner's trial against "Worth keeping"; the figures; the verdict. Kept: the merge. Dropped: an ADR on main, the branch kept unmerged, the issues re-iced or closed. | The tables above, filled in. |

## Not established

- **Whether AVFoundation converts log or HDR-tagged files before the
  compositor sees them.** Spec §7.5 says HDR is tone-mapped to SDR; what it
  does to Apple Log, S-Log or V-Log files tagged other ways was not checked. It
  decides whether a camera log LUT (T4) looks right. GR6's first step, with a
  real clip.
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
