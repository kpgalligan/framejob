# Precision: 16-bit-float compositing, deep decode, 10-bit exports (road map "precision", issue batch B94)

- **Status:** Built and closed 2026-10-09. Each phase was one litecode pipeline with its own review:
  - PR0, the decisions, the `LayerUniforms` toll, PR1's controls and the preview-display spike (`7b80810`)
  - PR1, the 16-bit-float working depth and output, with its fix pass (`c66d8ab`; `word_looks_baseline.json` re-recorded on its Release build in `b95d752`)
  - PR2, deep decode (`7853330`)
  - PR3, the `hevc_10bit` row, the documents, the close (uncommitted when this was written)
- **Original:** `archive/precision.md` is the full record. It has no section numbers, so it is cited by phase: "orig PR1" is its "PR1 — …" section.
- **Spec decisions:** PR-1..PR-5 in spec §11 (`designs/spec/11-decisions/precision.md`). They stay binding, and where the original words them differently, §11's text wins:
  - PR-1: the working depth is 16-bit float holding encoded values clamped to [0, 1]. The render context's buffers are `64RGBAHalf`; every target a layer pipeline draws into, and every layer, blend, shadow and dissolve pipeline's attachment, is `rgba16Float`; the coverage stays `r8Unorm` and the placeholder `bgra8Unorm`; the source sample and the blend and dissolve results are `saturate`d; blending stays in encoded sRGB; the preview shows the same buffers, no EDR or HDR. Amends MT-6, MT-8 and MT-9's figures. The measured memory (heavy 4K export +851.7 MB) was accepted by the owner.
  - PR-2: every video source decodes to `64RGBAHalf`; #216's 32BGRA import check stands; HDR stays tone-mapped.
    - Amended by GR-15 (grading-3 T3-0): "tone-mapped" was true of one path only. Measured by the tier-3 brief, the export reader's later frames and the player convert HLG and PQ to SDR, but the first frame a decoder delivers of each HDR clip and every `AVAssetImageGenerator` frame (`render_frame`, Save Frame…, GIF, APNG, the Look gallery's thumbnails, the eyedropper, Pick from Canvas) arrive unconverted, and a BT.2020 file with the BT.709 transfer arrives darkened. GR-15 makes every source arrive native and labelled (`canConformColorOfSourceFrames`) and converts HDR to SDR in Frame Job's own step 0 from T3-1; HDR still reaches the output as SDR.
  - PR-3: the export reader's frames are `64RGBAHalf`; `prores_422`, `prores_4444` and the new `hevc_10bit` row (Main 10, after `hevc_alpha`) take them as they are; `hevc` is pinned to Main; `h264` and `hevc` are rounded to 8-bit BGRA first; amends G-35 (c): `prores_4444` is un-premultiplied in float, `hevc_alpha` rounded to 8 bits and then straightened unchanged.
  - PR-4: `render_frame`, Save Frame…, GIF and APNG write the generator's CGImage, 8-bit when every source is 8-bit and 16-bit float when any is deeper (today's behaviour, written down).
  - PR-5: graphics, text, shapes, word captions, stills, thumbnails, the reversed-clip intermediate, screen recordings and the `r8` coverage stay 8-bit; a frozen reference compares decoded pixels within ±1, or prints its digest unscored.

## Context

The compositor worked in 8-bit BGRA end to end, so a 10-bit camera file lost its gradients on the way in and a ProRes export wrote 8-bit pictures into a 10-bit file. A scoping spike (`~/.claude/litecode/reelcut/precision/S-precision.md`, 2026-10-09) measured the costs and offered seven choices; the owner answered "As recommended" the same day: 16-bit float inside the compositor, every video source decoded deep, ProRes 10-bit automatically, a new HEVC 10-bit row, the HEVC row pinned to 8-bit Main, `render_frame`'s depth rule written down, the preview showing the same deep frames with no HDR, and graphics, text, stills, thumbnails, the reverse intermediate and recordings left 8-bit. HDR, wide gamut and linear light were deferred, and precision was ordered before the colour-grading branch. `Compositor.swift` (961 lines) paid its toll first: `LayerUniforms`, `ShadowUniforms` and `TransitionCode` moved whole to `LayerUniforms.swift` (orig PR0).

## Decisions

- **The 8-bit codecs are handed 8-bit frames.** Fed half-float frames, H.264 encoded the precision ramp at 8.80 steps RMS against 6.27 from 32BGRA, and `hevc` (Main) at 9.04 against 6.46. So `ExportWriter.frameForm` rounds `h264`'s and `hevc`'s frames to 8-bit BGRA (round(v·255)) in a pooled 32BGRA buffer (`ExportFrames`, `ExportStraightAlphaHalf.swift`), and their encoder input is what it was before the road map. `hevc` was added to this in PR1's fix pass. (orig PR1, "The review's fix pass")
- **The `hevc` pin is Main, and its mutant hands it deep frames.** Given no profile key, VideoToolbox follows its input's format, and deep frames gave Main 10. With 8-bit frames it writes Main with or without the pin, so a mutant that only removes the pin is equivalent; `hevc-no-profile` removes the pin AND hands `hevc` the deep frame. (orig PR1)
- **`hevc_10bit` is `hevc` by codec type and decided by codec NAME.** `codecType(for:)` answers `.hevc` for both HEVC rows, so `frameForm` and the profile ask `isMain10(settings)` (`settings.codec == "hevc_10bit"`) first; otherwise the new row would have been rounded to 8 bits. Mutant `hevc10-eightbit` removes that arm. (orig PR3)
- **An 8-bit input is caught by its staircase, not by its error.** Main 10 handed 8-bit frames encoded the ramp at 1.794 steps RMS against 1.459 from deep frames, inside both of T2's RMS bounds as first written, so the mutant survived. T2 now also reads the 8-bit staircase's tone (each column's mean code over the frame, less a 31-column moving average, at 255 steps across the width): 0.014 codes from deep frames, 0.536 from 8-bit ones and 0.758 for `hevc`, which is T2's control that the instrument sees a staircase at all. (orig PR3)
- **h264's claim is its ENCODER INPUT, not its file.** VideoToolbox's H.264 encode is not repeatable (two exports of one project differed by up to 124 levels), so the orchestrator ruled after PR0 that E1 compares what `ExportWriter` hands the encoder, read by `precision_encoder_probe.swift` built from the tree's sources. E2 does the same for `hevc`. (orig PR0, PR1)
- **No script can see what the preview layer displays.** The `CARenderer` spike drew an `AVPlayerLayer`'s content exactly, but its control (a half-float frame tagged Linear) drew within 0.03 of the untagged one, so the instrument cannot see how the layer READS a buffer. The display check is `docs/manual-checks.md`'s PRC-1, and no screen capture was allowed. (orig PR0)
- **The memory rise was accepted as measured.** The export pipeline holds about 19–26 frame buffers at its peak, not the handful the spike reasoned from, so the heavy 4K export rose +851.7 MB, past the road map's +532 MB stop. The owner: "Accept as measured. We shouldn't worry about 8g macs at all, and give only minimal concern to 16g macs." (orig PR1)
- **The generic fill keeps its speed through `allVisible`.** Making `ExportStraightAlpha`'s fill generic over `StraightAlphaLayout` slowed card frames by 15–25 %, because the whole-row-visible check stopped vectorising. Each layout's `allVisible(_:width:)` (a `min` over the alpha) restored B93's product-to-oracle ratios. (orig PR1)
- **A proof that outlasts autosave must work on its own copy.** `graphics_proof.py` Q2 failed after PR1 because the half-float `prores_4444` path doubled the pin probe's export time, past AppKit's autosave delay, so a blue canvas edit was saved into the shared package before the next run opened it. Each run now gets its own copy. (orig PR1)
- **A capture records the formats it was built from, and `compare` picks its rules from them.** K2–K5 are exact at the same output format and ±2 across it; K6 is exact at the same source format and recorded across it. In PR3 the formats are read from the sources of the app actually driven (`app_tree`: the tree whose `build/Build/Products` holds it); an app outside any tree is refused. (orig PR2, PR3)

## What it built — where it lives now

- App: `Compositor.swift` (`outputPixelFormat`, `sourcePixelFormat`, `MetalRenderer.metalFormat(for:)` and `workingFormat`), `Compositor+Matte.swift` (`takeComposite`), `Compositor+Shadow.swift` (`shadowPair`), `LayerUniforms.swift` (new, the PR0 toll), `Compositor.metal`'s three `saturate`s and its rewritten order-of-operations comment, `ExporterWriter.swift` (the reader's format, `frames`), `ExporterWriter+Settings.swift` (`frameForm`, `isMain10`, the `hevc` Main and `hevc_10bit` Main 10 pins, the `hevc_10bit` mapping), `ExportStraightAlpha.swift` (the generic fill, `BGRA8`, `allVisible`), `ExportStraightAlphaHalf.swift` (new: `ExportFrameForm`, `ExportFrames`, `RGBAHalf`), `AgentCatalog+Files.swift` (the `export` tool's preset and size prose).
- Core: the `hevc_10bit` row in `export_table.rs` (11 rows). Tests: `core/tests/export_hevc_10bit.rs` (new), `export.rs`'s oracle, `export_size.rs`'s lists. No format version change.
- Proofs: `precision_proof.py` (C0, D1, D2, P1, H1, R1, R2, C1, T1, T2; `capture`/`compare` K1–K6, E0–E2; `--measure` M1 and `--measure ab` MA; `--selftest`; ten mutants), `precision_encoder_probe.swift`, `preview_display_probe.py` (PR0's spike; exits 1 by design), the preview probes' format reads and PF, `hevc_alpha_proof.py`'s R8, RH, KH, HA. `tools/proof/README.md`'s precision section.
- Person checks: PRC-1 (the preview looks as before; a 10-bit ramp and real footage) and PRC-2 (deep exports play and look right; `hevc_10bit` beside `hevc`) in `docs/manual-checks.md`.
- Docs: spec §7.5 (the formats), §7.8 (the depth paragraph, the HEVC 10-bit paragraph, the row list), the README's export bullet.

**Headline numbers** (Release, Apple M2 Max, macOS 26.5.1, `powermode 0`, AC power; 10-bit steps RMS of a ramp's middle-row luma against the ideal):

| | PR0 (8-bit) | after the road map |
|---|---|---|
| a 50 % gradient over black through `prores_422` (P1) | 2.82 | 0.914 |
| the 10-bit ramp through `prores_422` (R2) | 3.159 | 0.707 |
| the 10-bit ramp's distinct green values in a `render_frame` PNG (R1) | 256 | 1,418 |
| the 10-bit ramp through `hevc` (Main) / `hevc_10bit` (Main 10), one run (T2) | 6.462 / — | 6.18 / 1.459 |

| Compositor average, `prores_422` export | PR0 | PR1 | PR2 |
|---|---|---|---|
| typical 1080p | 1.095 ms | 1.13 ms | 1.115–1.125 ms |
| heavy 1080p | 2.61 ms | 2.77 ms | 2.6–2.945 ms |
| typical 2160p | 2.71 ms | 2.555 ms | 2.735–2.795 ms |
| heavy 2160p | 5.94 ms | 6.015 ms | 7.38–7.585 ms |

**MA, the same-load A/B** (PR3; `precision_proof.py --measure ab --mutant decode-8bit`, Release, heavy 2160p alone, ABBA over 3 rounds, `vm.loadavg` 17.25 before and 16.06 after with other sessions running): compositor average this tree (`64RGBAHalf` sources) 8.005, 8.465, 8.155 ms against the `decode-8bit` copy (32BGRA) 6.67, 6.405, 5.98 ms — medians 8.155 against 6.405 ms, **deep decode ×1.273** — while the export's median wall time was 2.23 s against 2.37 s. This confirms PR2's +23–26 % as the decode's own cost, now measured on one load; which part of the frame pays it (the half-float source sampling was PR2's reasoned cause) is still not isolated.

Memory, each export's lifetime `phys_footprint_peak`, PR0 → PR1: typical 1080p 285.3 → 422.5 MB, typical 4K 618.0 → 1,236.1 MB, heavy 1080p 453.9 → 655.1 MB, heavy 4K 1,238.7 → 2,090.4 MB. PR2 added nothing separable from the run-to-run spread (±200–330 MB at 4K). Blended scenes moved by at most one level (K2–K5); one opaque layer and the H.264 clip alone did not move in PR1. Decoded video moved on 38.4 % of channels, 2.8 % by 5 or more (up to 103) in PR2, and the deep decode is nearer ffmpeg's own decode than the 8-bit one (mean |Δ| 1.677 against 1.966).

Mutants: 13 in PR1, 2 in PR2 and 4 in PR3 (with PR1's two `hevc-no-profile` re-run), all caught; PR3's `hevc10-eightbit` only once T2 read the staircase (above).

## Known limits

- **A heavy 4K frame's compositor average is 7.38–7.585 ms against the 8 ms budget** (M2 Max only; 8.0–8.5 ms in MA's runs at load 16–20), up from 6.0 ms before deep decode — ×1.27 on one load (MA) — while the export as a whole got faster (2.36 → 1.96–2.17 s) because deep decode is quicker. The road map's frame-time stop is 1080p's (2.6–2.945 ms), so this is recorded, not a stop.
- **Exports use about twice the frame memory** (PR-1, accepted). Which pools hold the 19–26 buffers (the render context's, the reader's copies, the encoder's queue) was not measured.
- **The ≥ 5-level edge differences on decoded video** sit at sharp colour edges, where 4:2:0 chroma is reconstructed; which reconstruction each path uses is not established.
- **The preview's look is a person's check** (PRC-1); no instrument sees what the player layer displays.
- **An 8 GB Mac is not measured**, by the owner's ruling.
- **ProRes 4K export speed** is disk-bound here and not established.

## Open items

Filed at the close, each `ai-drafted` and `low-priority`:
- #256: HDR and EDR, wide gamut, linear-light blending (PR-5).
- #257: a 10-bit `hevc_alpha`, a 10-bit reversed-clip intermediate, deep still images, 10-bit screen recording (PR-5).
- #258: 4K headroom, a 10-bit biplanar source instead of `64RGBAHalf`, sampled in the layer stage (amends PR-2), with PR2's frame times and export times and MA's figures.

The owner's PRC-1 and PRC-2 are in `docs/manual-checks.md`.

## Where to look in the original

- "The owner's choices": the seven answers, verbatim and dated.
- PR0: the toll's byte-identity check, the preview-display spike's figures (V0–V2), PR1's controls (E0's unrepeatable H.264 pair, M1's PR0 figures).
- PR1: what was built, E1 under the ruling, the M1 memory stop and the owner's answer, the straighten-speed fix, the pixel sweep, the re-baselined rows table, the twelve mutants, and the review's fix pass (Q2's autosave cause, `hevc` from deep frames, E2, the redefined `hevc-no-profile`).
- PR2: the controls on PR1's tree, the per-format compare rules, both M1 runs, the K6 histogram against ffmpeg's decode, the sweep and the two mutants.
- PR3: the row, T1/T2, MA, the `app_tree` fix and its selftest, the mutants.
