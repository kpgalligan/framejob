# Grading: tone, adjustment clips, looks and `.cube` LUTs, kept (road map "grading")

- **Status:** Built and closed 2026-10-10, kept by the owner's verdict and merged into main. Each phase was one litecode pipeline with its own review:
  - GR0, the road map and the spike on the tree's own shader (`bd5bb65`, on main)
  - GR1, five pure moves that made room (`4d742cc`, on main)
  - GR2, the decisions and tone (`99c0d8f`, the `grading` branch from here on)
  - GR3, Show Ungraded and the luma waveform (`6ecf46c`)
  - GR4a, adjustment clips in the core, the compositor and MCP (`a5a6cdf`); GR4b, in the chrome (`09b056c`)
  - GR5a, looks as core data, the GPU bake and step 4d (`e3e391e`); GR5b, the Look section and its gallery (`c2b2794`)
  - GR6a, `.cube` LUTs as media and looks (`9d237f0`); GR6b, imported LUTs in the chrome (`892bfd1`)
  - GR7a, the verdict's figures (`e2dbb9e`); L3, the two over-cap files paid by pure moves (`6f68daa`)
  - GR7b, the verdict, format 15 and the close (the commit that moved this record to `archive/`)
- **Original:** `archive/grading.md` is the full record. It has no section numbers, so it is cited by phase: "orig GR4a" is its "GR4a — …" section.
- **Spec decisions:** GR-1..GR-9 in spec §11 (`designs/spec/11-decisions/grading.md`). They stay binding, and where the original words them differently, §11's text wins:
  - GR-1: tier 1 (tone, adjustment clips, looks, LUT import, Show Ungraded, one waveform) is in; flip and the shape mask were cut; tiers 2 and 3 are deferred as issues, not out; amends spec §1. Verdict (owner, 2026-10-10): kept.
  - GR-2: tone is nine keys on `video.color` after `hue`, written only when not 0, at step 4c behind `toneEnabled`; exposure and white balance in local linear light; the Color sub-tab (Light, Color).
  - GR-3: grading runs on PR-1's float pipeline; blending stays encoded (§7.5).
  - GR-4: the `ungraded` recipe option, View ▸ Show Ungraded (⌃⌘U), preview and an asked `render_frame` only, never an export, not persisted.
  - GR-5: the luma waveform (View ▸ Waveform, ⌃⌘W): Rec. 709 Y′ of the composited preview frame, clip marks, a latest-wins tap run only while shown; no export path.
  - GR-6: adjustment clips (`Source::Adjustment`, `add_adjustment_clip`) grade everything behind them in their container by the eighth pipeline; inside the matte when matted, inert on a matte track; refused in a nest, a transition, an overlap and with blur, sharpen, pixelate or a blend.
  - GR-7: looks, `video.look {kind, amount}`: eight built-ins defined in the core as data, baked on the GPU into a 33³ `rgba16Float` lattice, mixed at step 4d at `texture(2)`.
  - GR-8: a `.cube` LUT is media of kind `lut`, parsed by the core (3D, sizes 2–65), applied as a look on encoded values; a missing LUT draws ungraded.
  - GR-9: the branch wrote format 1015 and refused 15–1014; at the merge 1015 became **15**, a file numbered 1015 is read as 15 by one migration step, and 16 and above, 1014 included, are newer.

## Context

Colour grading was a non-goal of spec §1 ("color grading beyond per-clip controls"); the effects survey filed it as #118 (E3), #120 (E5), #121 (E6) and #122 (E7), iced with the owner's "we'll eventually add color grading and LUT import, but not now" (2026-09-15). On 2026-10-09 he said "Start grading" and "All as recommended" to the brief's choices: tier 1 as an experiment on a branch, agreed criteria ("Worth keeping") before any code, and a verdict on his own footage at the end. Precision closed first, so grading never had an 8-bit pipeline to work around (GR-3). The branch took its own format number, 1015, so no main build could open a graded project and drop its grades on save (GR-9).

## Decisions

- **The ungraded layer's route was chosen by a rule written before measuring.** GR0 timed three routes on the tree's own `Compositor.metal` (a uniform flag, function constants, always on at neutral values). Always-on missed the bound at both sizes (0.022 ms at 1080p against 0.02 + 0.001 noise; 0.083 ms at 4K against 0.06), the flag qualified, and it was first in the agreed order: tone at 4c behind `toneEnabled`, the look at 4d behind `lookEnabled`. (orig GR0)
- **Exposure and white balance run in linear light locally, inside step 4c.** They decode, multiply and re-encode within the stage; every blend stays in encoded sRGB, so this is not the §7.5 change. GR0 priced the linear step at 0.011 ms at 1080p and 0.040 ms at 4K. (orig GR0, GR2)
- **The Concat rule held at design and build time.** Concat is AGPL-3.0: none of its code, shaders, chains or colour tables were opened or carried over. The sRGB transfer functions (IEC 61966-2-1), Rec. 709 luma weights, trilinear sampling and the `.cube` format are textbook; the eight looks are Reelcut's own numbers; every test LUT is written by a script. (orig "The Concat rule")
- **An adjustment clip on a matte track is inert, not the matte group's grade.** A group is one track, and two clips on one track share an instant only in a transition, which GR-6 refuses, so the road map's "grades the group's earlier members" had nothing to grade. The recipe drops it before the matte pass and the Clip tab says so. (orig GR4a)
- **A look is defined by its baked lattice.** The eight are core data (Color, Light and split-tone values) baked by the tone stage's own Metal functions into 33³, so preview, `render_frame` and export agree by construction; Core Image's photo effects were rejected as not Reelcut's own. (orig GR5a)
- **AVFoundation reads only the container's `colr` atom** (T0, before any LUT code): tags in the ProRes headers alone change nothing; HLG and PQ arrive unconverted; BT.2020 with the BT.709 transfer arrives linearised. Log was not checked: no log clip. (orig GR6a)
  - Amended by GR-15 (grading-3 T3-0): T0's "HLG and PQ arrive unconverted" is true of `render_frame`'s generator and of the first frame a decoder delivers; the export reader's later frames and the player convert them to SDR (the tier-3 brief, measured). From T3-1 every source arrives native and labelled, and Reelcut converts HLG, PQ and BT.2020/BT.709-transfer sources at step 0, before the layer stage.
- **The format renumbering is one step before the gate.** `migrate_1015_to_15` maps 1015 to the literal 15, not to `RC_FORMAT_VERSION`, so a later bump still runs its own steps from 15; `GRADING_BRANCH_VERSION` names 1015 and the rest of the base-version machinery left with the merge. (orig GR7b)

## What it built — where it lives now

- Core: `ColorAdjust`'s nine tone keys (`model_props.rs`), `props_check.rs`'s ranges, `actions::color_json`; `RecipeOptions.ungraded`; `Source::Adjustment` and `edit_adjustment.rs`; `model_look.rs` (`LookKind`, `Look`, `LookDefinition`) and the recipe's `look` key; `cube.rs`, `ffi_cube.rs` (four `rc_cube_*` exports) and `lut.rs`; `MediaKind::Lut`; `format.rs` at 15 with `migrate_1015_to_15`. Tests: `tone.rs`, `ungraded.rs`, `adjustment.rs`, `look.rs`, `cube.rs`, `lut.rs`, `schema_v15.rs`.
- App: `GradeProps.swift`, `VideoPane+Light.swift`, `VideoPane+Adjustment.swift`, `VideoPane+Look.swift`, `ClipSubTab.color`; `LayerUniforms` at 116 floats (tone, `toneEnabled`, `lookAmount`, `lookEnabled`); `Compositor.metal`'s `gradeTone`, `gradeLook`, `reelcut_adjust_fragment` and `reelcut_look_bake`; `Compositor+Adjustment.swift`, `LookTextures.swift`, `LutTextures.swift`; `Waveform.metal`, `WaveformAnalyzer.swift`, `WaveformTap.swift`, `WaveformPanelView.swift`, `EditorViewController+Seeing.swift`; `EditorViewController+Adjustment.swift`, `EditorViewController+Look.swift`, `LookGallery.swift`, `LookGalleryView.swift`, `LookMenuFiller`; `MediaImporter+LUT.swift`; `AgentServer+Grading.swift` (`add_adjustment_clip`, the ninetieth product tool); `render_frame {ungraded, waveform}`.
- Pure moves it paid for: GR1's five (`plan.rs`, `CompositionPlan.swift`, `VideoPane+Color.swift`, `AgentCatalog+Properties.swift`, `AppDelegate+ClipMenus.swift`), GR6a's `RecipeOptions.swift` and `MediaSnapshot.swift`, L3's `ShapeProps.swift` and `edit_detach.rs`.
- Proofs: `grading_spike/` (GR0 and `--tree`), `tone_proof.py`, `seeing_proof.py`, `adjustment_proof.py`, `look_proof.py`, `lut_proof.py`, `grading_verdict.py`, each with its probe and mutants; screens `04b-preview-waveform`, `05b-clip-color`, `05c-clip-adjustment`, `05d-clip-look`, `05e-clip-look-lut`.
- Person checks: GRD-1…GRD-10 in `docs/manual-checks.md`.

**Headline numbers** (Apple M2 Max, macOS 26.5.1, `powermode 0`, AC power).

GR0, one ungraded full-bleed layer, overhead over the tree (ms, 1080p / 4K): flag (VF-TL) 0.000 / 0.001; function constants (VC-TL) −0.003 / −0.000; always on (VA-TL) 0.022 / 0.083. T2, a graded layer over its own ungraded figure, flag route: tone only 0.049 / 0.197; tone and a 33³ look 0.057 / 0.226; one full-frame adjustment pass 0.045 / 0.174. The spike's comments in `Compositor.metal` cite these rows (GR0's T0 and T2).

#258's X1 (GR0, four video layers at 4K): G = H16 − B8 = 0.135 ms, W = H16 − min(X420, X422) = 0.131 ms ≥ 0.5·G, so a 10-bit biplanar source wins back nearly all the half-float source's layer-stage cost; #258 stays open for the owner.

GR7a's caps against main at the branch point `f407f87`:

| Measure | Cap | Measured | Command |
|---|---|---|---|
| Frozen files | wiring only, ~50 lines | `EditorViewController.swift` +3, the other four net 0: held | `grading_verdict.py sizes` L2 |
| Files over the cap | none unpaid | held after L3: `ProjectSnapshot.swift` 1,750 → 1,570, `edit_clip.rs` 755 → 661 | `sizes` L3 (at `6f68daa`) |
| Inspector | one sub-tab, ≤ 4 sections | Color: Light, Color, Adjustment, Look; Picture −Color: held | `sizes` L4 |
| Menus | the four named items | 175 → 187 leaves, those four, none removed: held | `RC_PROOF_APP=release grading_verdict.py measure --only H0,M1,G0,E1,E2,Z1` M1 |
| An ungraded layer | +0.02 ms 1080p, +0.06 ms 4K | +0.009 / +0.002 ms (C0 noise 0.000): held | `grading_spike.py --measure --tree` TC |
| An ungraded export | ≤ 2 % over main | +0.33 % (6.00 s against 5.98 s, 60 s at 1080p): held | `measure` E1 |
| A graded export | ≤ 10 % over ungraded | −0.17 % (5.99 s against 6.00 s): held | `measure` E2 |
| A graded frame | ≤ 8 ms at 1080p | 2.724 ms median compositor average (worst window 7.07–7.70 ms): held | `RC_PROOF_APP=release grading_verdict.py measure --only H0,F4,T4,Z1` F4 |

The exports are encoder-bound at these sizes, so E1 and E2 say the grade costs no export time on that fixture, not that the compositor does no more work; F4 is the frame-time figure. T4's script half: a 33³ LUT through Reelcut against ffmpeg's `lut3d` on the same frame, max |Δ| 2 levels (the control, no LUT, 56).

## The verdict

The owner, 2026-10-10: "I think we can merge this." And: "T1 and T3 look good to me. I'll get feedback later from others and we can adjust."
- T1 (Light on a warm, dark clip) and T3 (a built-in look): run, good.
- T4 (a LUT): run with test LUTs, not one of his own: "LUT worked".
- T2 (one adjustment clip over a whole video), T5 (the Assistant) and T6 (a power window): not run by the owner; now GRD-7, GRD-8 and GRD-9. GRD-10 is the feedback from others.
- GRD-1…GRD-6: not reported; they stay standing rows.
- Every cap in the table above held.

## Known limits

- **Whether AVFoundation converts log footage** (Apple Log, S-Log, V-Log) before the compositor is not established, and so neither is whether a camera log LUT looks right: no log clip was available (#264).
- **Banding on real footage** is a question about the source's own levels, answered by GR2's fixture and the owner's eye (GRD-1), not by a script.
- **Whether 65³ is worth it for built-in looks** is not measured; a built-in look is defined by its 33³ lattice, so that is not a defect. An imported LUT arrives at its own size.
- **The adjustment clip with Preview Quality and the matte pool** is reasoned from the code, not run.
- **Other editors' behaviour** (adjustment layers reaching every track, scopes as a panel) is from general knowledge.
- **The trial is partial**: T2, T5 and T6 and GRD-1…GRD-10 are the owner's standing checks, and other people's feedback is still to come.

## Open items

Filed or touched at the close; the new ones are each `ai-drafted` and `low-priority`:
- #259: flip_x and flip_y, cut from tier 1 (from #118, closed).
- Tier 2: #260 (colour wheels), #261 (curves), #262 (HSL qualifiers), #263 (vectorscope, RGB parade, histogram beside the waveform).
- #264: log footage through AVFoundation and a camera log LUT; needs a log clip.
- #256: tier 3, colour management (linear light, log, HDR).
- #258: the 10-bit biplanar source, left open for the owner's choice (X1 above).

Closed as built: #118 (tone; its mask answered by a matte track over an adjustment clip), #120 (eight looks), #121 (adjustment clips), #122 (LUT import).

## Where to look in the original

- "The owner's choices", "Tier 1 as answered" and "How it fits the tree": the nine choices, what was cut and why, the texture slots, mattes and nests, the Rust/Swift split.
- "The Concat rule": what may and may not be used, at design and build time.
- "Worth keeping": the six tasks, the caps as agreed and as measured, and the owner's trial guide.
- GR0: the spike's instrument, S1/T2/P1/X0/X1/D1 tables, the route rule's reading and the six mutants. GR1: the five moves and what each widened.
- GR2–GR6b: each phase's landed list, sizes, recorded runs, mutants, deviations and owed lines.
- GR7a: the caps table with each command and load, L1 per commit, T4's script half, and the L3 payment.
- GR7b: the verdict, format 15's renumbering, its verification and mutants, and the issues.
