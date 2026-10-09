# Road map "precision" — 16-bit-float compositing, deep decode, 10-bit exports

**Closed 2026-10-09** (PR3). Issue batch B94. The decisions are spec §11
PR-1..PR-5 (`designs/spec/11-decisions/precision.md`); this file is the
phases' record, condensed into `designs/adr/precision.md` and moved here,
`archive/precision.md`, at the close.

## Goal

Reelcut composites in 16-bit float, decodes every video source to
`64RGBAHalf`, writes ProRes 422/4444 from deep frames, pins the `hevc` row to
8-bit Main and adds an `hevc_10bit` row, so a 10-bit source survives to a
10-bit file. Blending stays in encoded sRGB (§7.5, MT-3); HDR, wide gamut and
linear light are deferred. The scoping spike is
`~/.claude/litecode/reelcut/precision/S-precision.md` (2026-10-09); its
section 0 holds the seven choices and its figures are marked MEASURED or
REASONED.

## The owner's choices

**2026-10-09**, verbatim: "As recommended" — answering the spike's seven
choices, which therefore read:

1. Working depth inside the compositor: 16-bit float (`rgba16Float`).
2. Decode every video source deep.
3. ProRes 422 and 4444 export 10-bit automatically; a NEW "HEVC 10-bit"
   export row; the existing HEVC row pinned to 8-bit Main (today it names no
   profile — the spike's trap). H.264, HEVC with alpha, GIF, APNG and image
   sequences stay 8-bit.
4. `render_frame`'s PNG depth keeps today's rule (it follows the sources),
   written down.
5. Preview shows the same deep frames as export; no HDR/EDR; add a
   manual-check row. A separate 8-bit preview output only if a problem shows.
6. Stays 8-bit in this road map: graphics, text, shapes, stills, thumbnails,
   the reversed-clip intermediate, screen recordings. HDR, wide gamut and
   linear light are deferred.
7. Order: precision first, on main, before the colour-grading branch.

## Phases

Each phase is committed alone, after its review.

| Phase | What | State |
|---|---|---|
| PR0 | PR-1..PR-5 recorded in spec §11 before any code (amending MT-6, MT-8, MT-9 and G-35); `LayerUniforms`, `ShadowUniforms` and `TransitionCode` out of `Compositor.swift` into `LayerUniforms.swift`, a pure move gated alone; PR1's controls captured on PR0's tree and the preview-display spike (V0–V2) | done (below) |
| PR1 | 16-bit-float working depth and output (sources stay 32BGRA): the render context, targets and pipelines `rgba16Float`, the shader clamps, the export reader deep, `ExportFrames` (`prores_4444` straightened in float, `hevc_alpha` and `h264` rounded to 8 bits first), the `hevc` Main pin, the preview probes reading the new format, the pixel sweep's re-baselines | built; M1's memory stop returned to the owner, who accepted the measured figures (below) |
| PR2 | Deep decode: every video source `64RGBAHalf`; the ramp rows; the video-sourced re-baselines | built (below) |
| PR3 | The `hevc_10bit` row (core and app), the documents, the ADR, close | built (below) |

## PR0 — the decisions, the toll, the controls (2026-10-09)

**Decisions.** PR-1..PR-5 recorded in `designs/spec/11-decisions/precision.md`
before any code, with their five rows and the file's row in that folder's
README, the spec index's `11-decisions/` cell, and an "(Amended by PR-1: …)" /
"(Amended by PR-3: …)" parenthetical in G-33's style on MT-6, MT-8 and MT-9
(`mattes.md`) and G-35 (c) (`graphics.md`), each README row marked "amended
by".

**The toll.** `Compositor.swift`'s file-level `// MARK: - Uniforms` through
`TransitionCode` (`LayerUniforms`, `ShadowUniforms`, `TransitionCode`; HEAD
7ef96c5's lines 258–522) moved whole to the new `LayerUniforms.swift` with
`import Foundation` and nothing else; the moved block is byte-identical to
the removed one (`git show HEAD:app/Sources/Compositor.swift | sed -n
258,522p` against the new file's body, `diff` silent), and the
`Compositor.swift` diff is 266 deletions and no additions. `wc -l
app/Sources/Compositor.swift`: 961 before, 695 after; `LayerUniforms.swift`
is 267. The next seam named for `Compositor.swift` is `DestinationPass`, out
whole (`designs/adr/app-file-history.md`).

**Verification of the move.** `make typecheck` (0 errors, the 4 baseline
warnings) and `spec_index_proof.py` (147/147) in the loop; `make gate` PASS
(typecheck, test, app run; fmt and lint skipped as unchanged).
`video_configuration_proof.py capture` on a Release build of HEAD 7ef96c5
BEFORE the move (C1, C2: 2/2), then `compare` on the gate's post-move
Release: 7/7 — the three renders, the APNG, the GIF and both ProRes exports
byte for byte (ProRes masked), the probe now built from 350 sources where it
was 349. `MemoryLayout` read by a probe compiled from the post-move
`app/Sources`: `LayerUniforms` 416 bytes (stride 416), `ShadowUniforms` 48
(stride 48), `phase8_chrome.py`'s contract. `phase8_chrome.py` itself was
not run: its `dispatch` mode activates a bundle and takes the keyboard focus
for about a second (its own docstring), which this road map's proofs may not
do without asking; the move is byte-identical, so its rows have no input
that changed.

**The preview-display spike (V0–V2), on PR0's tree.**
`tools/proof/preview_display_probe.py --rows spike` (new): a probe-owned
`AVVideoCompositing` hands an `AVPlayerLayer` in no window four flat
quadrants over a 640×360 H.264 movie paused at 0.5 s, and
`CARenderer(mtlTexture:options:)` (sRGB) draws the layer under a magenta root
into a `bgra8Unorm` texture. Result, 2/3 (2026-10-09, M2 Max, macOS 26.5.1):

| Row | Frame | Quadrant means (R, G, B) | Verdict |
|---|---|---|---|
| V0 | 32BGRA | (192,192,192) (200,60,30) (64,64,64) (128,128,128); magenta 0 | ok — the content is drawn, exact |
| V1 | 64RGBAHalf, `TransferFunction_Linear` | grey 128 → (127.98, 127.98, 127.97) | **FAIL** — 0.03 off V0, needs ≥ 10 |
| V2 | 64RGBAHalf, untagged | every quadrant within 0.08 of V0 | ok |

The instrument sees the layer's CONTENT (the quadrants come out exact,
upside down in the texture), but the mis-tagged control does not move it, so
it cannot be shown to see how the layer READS a buffer: either the layer
ignores a lone transfer-function tag or the in-process `CARenderer` path does,
and the run cannot tell which. The render context's buffer carries only
`CVCleanAperture` and `HorizontalDisparityAdjustment` (no colour tag), as the
spec assumed; `displayedPixelBuffer()` answers nil for the windowless layer
with `isReadyForDisplay` true. **So PV is not built**, and the
`capture`/`compare` modes it would have used are not in the probe. Spec §11
PR-1's check of the displayed picture is `docs/manual-checks.md`'s PRC-1
alone (PR1 writes it): PR2 and PR3 proceed after PR1's commit, since neither
changes the display path; the owner is asked to run PRC-1 as soon as PR1 is
committed; a wrong preview is then a fix of its own (choice 5's fallback, a
separate 8-bit preview output, by a decision recorded then).

**PR1's controls, captured on PR0's Release** (the gate's `make app`;
`tools/proof/precision_proof.py`, new, written before any product edit; the
capture is `tools/proof/work/precision/ctl-pr0/`, gitignored):
- `capture`: 5/5. K1–K6 rendered (digests a1e4332cd0b2b295, 2dad090bb09959ed,
  ccce0b10a0605f14, bc119a50b8d0725b, 715a32984d842823, 76ab60469c24daa1).
  **E0**: the two `h264` exports of K6's clip decoded to rgb24 were NOT equal
  (27266c5820dc4dd7 and 8b2c1ab173c6f686): frames 0–4 identical, frames 5–29
  differing on 56,431–107,531 channels each, by up to 124 — VideoToolbox's
  H.264 encode is not repeatable run to run on this host (two earlier capture
  runs' pairs were both 8b2c1ab173c6f686). So E1's bound under the spec's rule
  is 124. **P1**'s control (8-bit canvas): RMS 2.82 10-bit steps (g 0…255).
  The ramp: `render_frame` a 16-bit PNG whose middle row holds 256 distinct
  green values; its `prores_422` export 3.159 steps RMS against x/1919.
- The rows on the same build: C0, D1 (8-bit PNG) and H1 (`hevc`, Main,
  `yuv420p`) ok; P1 FAIL at 2.82, as an 8-bit canvas must (4/5).
- `compare` against its own capture, as a check of the instrument: 8/8 — K1–K6
  identical, E1 (8b2c1ab173c6f686) within E0's 124.
- `--measure capture` (M1): 2/2. Host: `powermode 0`, AC power, `vm.loadavg`
  4.33 before and 4.04 after (other sessions running). Each export on an
  instance of its own, `-ReelcutCompositorTiming YES`, two 120-frame windows
  each:

| Fixture | Export | Average | Worst | `phys_footprint` before | Lifetime peak |
|---|---|---|---|---|---|
| typical 1080p | 0.63 s | 1.095 ms | 2.40 ms | 96.3 MB | 285.3 MB |
| typical 2160p | 1.62 s | 2.71 ms | 5.01 ms | 106.3 MB | 618.0 MB |
| heavy 1080p | 0.98 s | 2.61 ms | 18.05 ms | 200.9 MB | 453.9 MB |
| heavy 2160p | 2.63 s | 5.94 ms | 32.2 ms | 352.5 MB | 1,238.7 MB |

  An 8 s export finishes in 0.6–2.7 s, so the 0.5 s samples (2–6 per export)
  catch the peak only sometimes; the instance's lifetime `phys_footprint_peak`,
  read after the export on an instance that did nothing else, is the figure
  `--measure compare` compares.

## PR1 — 16-bit-float working depth and output (2026-10-09)

**Built.** `Compositor.outputPixelFormat` is `kCVPixelFormatType_64RGBAHalf`
(`sourcePixelFormat` stays 32BGRA until PR2); `MetalRenderer.metalFormat(for:)`
and `workingFormat` (`rgba16Float`) give every layer, blend, shadow and
dissolve pipeline's attachment, the matte composites and dissolve halves
(`MattePool.takeComposite`) and the shadow pair; `texture(from:)` wraps a
buffer by its own format. `Compositor.metal`: `layerSample` `saturate`s its
sample, the blend and dissolve entry points `saturate` what they return, and
the order-of-operations comment is true for a 16-bit-float canvas (linear
light's 50 % × 50 % is about 24 %, 61/255). The export reader reads
64RGBAHalf; `ExportWriter.frameForm` and `ExportFrames`
(`ExportStraightAlphaHalf.swift`, new) straighten `prores_4444` in float,
round `hevc_alpha`, `h264` and `hevc` to 8-bit BGRA in a pooled 32BGRA
buffer (the first then straightened by G-35's 8-bit rule, unchanged; `hevc`
since the review's fix pass, below), and `hevc` is pinned to Main. `ExportStraightAlpha.swift`'s fill is generic over
`StraightAlphaLayout` (`BGRA8`, `RGBAHalf`): one fill. `wc -l`:
`Compositor.swift` 695 → 724, `ExporterWriter.swift` 573 → 572,
`ExporterWriter+Settings.swift` 393 → 413, `ExportStraightAlpha.swift`
246 → 244, `ExportStraightAlphaHalf.swift` 252 (new; both after the
`allVisible` fix below).

**E1 under the ruling.** `precision_encoder_probe.swift` (new, built through
`swift_build`) reads what `ExportWriter` hands the `h264` encoder. Its first
run failed K3 by up to 194 levels on the title: a bare binary has no
`ATSApplicationFontsPath`, so the title drew in a fallback face; the probe
now registers the bundled fonts, and K3's handed frame then equals PR1's
own render byte for byte.

**Recorded on Release** (the gate's `make app`; against PR0's capture
`tools/proof/work/precision/ctl-pr0/`):
- `precision_proof.py` rows 5/5: C0 ok; D1 an 8-bit PNG; **P1 0.914 10-bit
  steps RMS** (PR0's 8-bit canvas: 2.82); H1 `hevc`, Main, `yuv420p`.
- `compare` 8/8: K1 and K6 byte-identical; K2 740 channels at |Δ| 1, K3
  177,726, K4 none, K5 147,333 (of 921,600; none past 1); **E1**: `h264`'s
  handed frame is 32BGRA, K6 byte-identical to PR0's render and K3 within
  ±1 (the same 177,726 channels as K3's row). The encoded file decoded to
  the same digest as E0's first export (27266c5820dc4dd7), unscored.
- `--measure compare` 1/2 — **M1 hits the memory stop** (host: `powermode
  0`, AC power, `vm.loadavg` 13.05 before and 15.05 after, other sessions
  running):

| Fixture | Average (PR0 → PR1) | Worst | Lifetime peak (PR0 → PR1) | Δ | Implied extra buffers (Δ ÷ one buffer's Δ at that size) |
|---|---|---|---|---|---|
| typical 1080p | 1.095 → 1.13 ms | 2.40 → 2.80 ms | 285.3 → 422.5 MB | +137.2 MB | +16.5 |
| typical 2160p | 2.71 → 2.555 ms | 5.01 → 6.14 ms | 618.0 → 1,236.1 MB | +618.0 MB | +18.6 |
| heavy 1080p | 2.61 → 2.77 ms | 18.05 → 19.82 ms | 453.9 → 655.1 MB | +201.2 MB | +24.3 |
| heavy 2160p | 5.94 → 6.015 ms | 32.2 → 35.87 ms | 1,238.7 → 2,090.4 MB | **+851.7 MB** | +25.7 |

  Frame time is not a stop (heavy 1080p averages 2.77 ms against the 8 ms
  stop). Memory is: the heavy 4K export's peak rose +851.7 MB, past the
  spec's stop of +532 MB (twice the spike's reasoned +266 MB). The typical
  4K peak exactly doubled (PR-1's "frame memory doubles"); the heavy one
  rose 69 %. The implied extra 4K buffers (Δpeak ÷ 33.2 MB, the
  64RGBAHalf-less-32BGRA size) are 18.6 and 25.7: the export pipeline holds
  about that many frame buffers at its peak, where the spike reasoned from
  a handful. Which pools they are (the render context's, the reader's
  copies — `alwaysCopiesSampleData` — or the encoder's queue) was not
  measured. **Per the spec this returned to the owner** (PR-1's risk, "Owner
  choices"), who answered the same day: "Accept as measured. We shouldn't
  worry about 8g macs at all, and give only minimal concern to 16g macs."
  The figures and the acceptance are in spec §11 PR-1; the +532 MB stop no
  longer applies to this road map (PR2's included), and `precision_proof.py
  --measure` prints and records the memory without scoring it. Footprints
  are still measured and recorded each phase.

**After the owner's answer (2026-10-09).**
- **The straighten speed.** It was measured again on a quieter host.
  - The generic fill had slowed card and soft frames by 15–25 %. A standalone `-O` WMO bench of the PR0 file against PR1's showed it: 4K card 0.84 → 1.05 ms, soft 2.92 → 3.58 ms.
  - The cause: `nearestInRow`'s whole-row-visible check, asked through `visible` per pixel, no longer vectorised.
  - The fix: `StraightAlphaLayout` gained `allVisible(_:width:)`, a `min` over the alpha alone per layout. K1 and KH are unchanged.
  - `--measure straighten-speed`, with the pre-B93 oracle in the same run:
    - 1080p: card 0.34 ms (oracle 0.34), soft 0.93 (0.91), sparse 1.04 (16.63);
    - 4K: card 1.06 (0.85), soft 3.40 (3.37), sparse 3.63 (65.08).
  - The product-to-oracle ratios are now B93's own.
- **`hevc_alpha_proof.py` whole on Release:** 42/43, then B1 re-baselined under PR-5, and `--rows size` showed B1 ok. The re-baseline was withdrawn in the fix pass (below): with `hevc` fed 8-bit frames again B1 reproduces the baseline's digest exactly.
- **HA** (`--measure hevc-alpha-deep`): the writer takes 64RGBAHalf for `hevc_alpha`. ffprobe reads hevc/hvc1, Main, yuv420p. Decoded alphas are {0, 1, 2, 127, 128, 129}, and the centre is (254, 0, 0, 128) for a straight (255, 0, 0, 128) card. This is recorded, not used.
- **The pixel sweep on Release.**
  - Each proof ran on an instance of its own, and every parity log was empty.
  - Every score was full except the re-baselined rows below and `graphics_proof` Q2 (PR1's own, fixed in the fix pass below):
    - phase1 66/66, phase2 86/86, phase3 123/123, phase4 83/83, phase5 90/90, phase6 168/168, phase7 92/92, phase8 79/79, phase9 222/222;
    - `phase6_chrome` 70/70, `phase7_chrome` 79/79, `phase8_chrome` 150/150 (run with the owner's leave to take focus; `LayerUniforms` 416, `ShadowUniforms` 48);
    - `e1_proof` 101/101, `e2_proof` 75/75;
    - `matte_proof` 46/46, `matte_probe` 6/6;
    - `graphics_proof` 50/51 (Q2; 51/51 after the fix pass), `graphics_files_proof` 10/10, `graphics_prefetch_proof` 7/7, `graphic_prop_action_proof` 17/17, `paste_graphic_proof` 8/8;
    - `word_looks_proof` 15/16 (B1, to re-record), `word_looks_sheet_proof` 9/9, `words_picture_proof` 7/7, `word_captions_proof` 20/20;
    - `codec_import_proof` 10/10, `container_import_proof` 16/16, `clip_inspector6_proof` 25/25, `debug_release_proof` 10/10, `export_cancel_proof` 7/7, `remaining_proof` 80/80, `silence2_proof` 100/100;
    - `recording_proof` 140/140 with `--no-screen --no-microphone`, recording nothing (79 checks skipped by name);
    - the three preview probes 59/59, 24/24 and 32/32.
  - phase4's one failure (82/83 first) was its `transcribe` argument row, which predated spec §11 W-15's slide/fill/dim. It was not PR1's and is fixed.
- **Re-baselined rows** (script, row, old → new, cause):

| Script | Row | Old | New | Cause |
|---|---|---|---|---|
| `e1_proof.py` | the version-6 `wipe` against 1c3e92e | byte-identical (3f25059c…) | within ±1 a channel (5e6ff5dc…; \|Δ\| 1 on 1,080 channels) | PR-1: the wipe's soft edge is blended at 16-bit float; PR-5's rule for a frozen reference that holds pixels |
| `e1_proof.py` | five version-6 cross-dissolve ticks | byte-identical | within ±1 (still \|Δ\| 0 on every tick) | PR-5's rule, the same row family |
| `hevc_alpha_proof.py` | B1 | frame 0's digest d038e20d… scored; samples exact | WITHDRAWN in the fix pass: exact again, digest d038e20d… | was: `hevc` fed 64RGBAHalf moved the digest to 2da5cab7… and the centre red to 254; `hevc` is now rounded to 8 bits first (below) |
| `word_looks_baseline.json` | B1 (fixture B, 41 frames) | PR0's digests (PR0's Release reproduced all 41) | to re-record after PR1's commit | PR-1: 40 frames moved, 76,550 channels, every one by exactly 1, measured against a scratch Release build of PR0. `--record-baseline` refuses an uncommitted tree, so the recording is owed to the commit |

- **The mutants, once, on the final instrument.** All 12 were caught:
  - `precision_proof.py`:
    - `h264-deep`: E1 FAILS; the handed frame is RGhA.
    - `output-8bit`: P1 FAILS at 2.82, and PF FAILS through `preview_refresh_probe.py --sources`.
    - `hevc-no-profile`: H1 FAILS; the profile reads Main 10.
  - `hevc_alpha_proof.py`:
    - `hevc-no-profile`: B1 FAILS on Main 10.
    - `label-premultiplied`, on its new anchor: M1 FAILS.
    - The probe-only `bgra8-truncates` (R8), `half-no-unpremultiply` (RH) and `half-no-fill` (KH).
    - The four B93 probe mutants: K1 (`row-tie-right` also R0).
- **`make gate` PASS** on the final tree.
- **`graphics_proof.py` Q2 (`direct`)** failed on both Release runs: (1440, 540) read blue (0, 0, 255) where the row wants black, the canvas colour `swapOut` sets after the export was handed its project. It was first called a pre-existing race and filed as #255.

**The review's fix pass (2026-10-09).**
- **Q2 was PR1's, and a proof defect, not a product race.** The pin probe (`graphics_pin_probe.swift`, built `-Onone` by `swift_build`) was run as the proof runs it, Q1's `queue pin`/`nopin` then Q2's `direct pin`/`nopin` over ONE package, from a black-canvas copy of PQ, 3 rounds per tree, each tree's probe built from its own `app/Sources` and shader:
  - PR0 (7b80810): 12 of 12 runs drew (1440, 540) black (Q1 3/3, Q2 3/3); each run took 9.3–10.2 s; the package's canvas stayed black.
  - PR1: Q1 3/3 black, Q2 `direct pin` **0/3** (blue every time); each run took 17.3–32.4 s, and after every round's first run the package's saved canvas was blue.
  - The cause: `swapOut`'s blue canvas is a document edit, and `ProjectDocument` autosaves in place. A run that outlasts AppKit's autosave delay writes the blue canvas into the package, so the NEXT run opens blue. Each export itself drew black, from the project it was handed. PR1 doubled the probe's `-Onone` `prores_4444` export time (the half-float path), which crossed that delay; PR0's runs finished first. The earlier "PR0 races too" run was over a PQ an earlier run had already autosaved.
  - The fix: `graphics_proof.py`'s `run_probe` hands each run its own copy of the package (`work/graphics/<tag>.reelcut`). Over the fixed `run_probe`, PR1's probe drew black in 10 of 10 pin runs (5 rounds, Q1 and Q2); every copy was autosaved blue and the source package stayed black. `graphics_proof.py` whole on Release: 51/51.
- **`hevc` (Main) from deep frames, measured** (review nit 2; the precision proof's 10-bit ramp at 1920 × 1080 through the app, decoded luma against x/1919, 10-bit steps RMS; three `hevc` exports, one `prores_422` and two `h264` per build, each figure identical across its repeats):

| Build | `hevc` | `prores_422` | `h264` |
|---|---|---|---|
| PR0 Release (scratch build of 7b80810) | 6.462 | 3.159 (PR0's capture: 3.159) | 7.863 |
| PR1 Release, `hevc` fed 64RGBAHalf | **9.040** | 2.007 | 7.863 |
| PR1 Release, `hevc` rounded to 8 bits | 6.462 | 2.007 | 7.863 |

  - `hevc` was worse from deep frames, as `h264` was, so `frameForm` now gives `hevc` the `.eightBit` form (spec §11 PR-3 amended, §7.8 too). Profile and pixel format are unchanged: Main, `yuv420p`.
  - New row **E2** (`precision_proof.py compare`): the frame handed to the `hevc` encoder is 32BGRA, K6 byte-identical to PR0's render and K3 within ±1 (the same 177,726 channels as E1's). New mutant **`hevc-deep`** (`frameForm` answers nil for `hevc`) targets E2.
  - **`hevc-no-profile` was redefined in both scripts.** With the 8-bit frame, VideoToolbox writes Main with or without the pin, so the pin alone removed is an equivalent mutant. The mutant now also hands `hevc` the deep frame (`hevc-deep`'s anchor), the input the pin is for; H1 and B1 still catch it on Main 10.
  - **B1's re-baseline is withdrawn.** `hevc_alpha_proof.py --rows size` on Release read frame 0's digest d038e20d…, the baseline's, with the five samples exact, so B1 compares exactly again as it did before PR1.
  - **Mutants, once, on Release** (the ones whose anchors the fix pass touched): `h264-deep` (its anchor line now holds `hevc` too) — E1 FAILS, handed RGhA; `hevc-deep` — E2 FAILS, handed RGhA; `precision_proof.py`'s `hevc-no-profile` — H1 FAILS on Main 10; `hevc_alpha_proof.py`'s `hevc-no-profile` — B1 FAILS (frame 0, the samples and the stream differ). All four caught; the phase's mutants are now 13.
  - **Owed to PR3:** `frameForm` keys on `codecType`, so PR3's `hevc_10bit` (mapped to `.hevc`) must answer nil there, or it would be rounded to 8 bits. PR3's T2 (RMS ≤ 2.0) would catch it.

## PR2 — deep decode (2026-10-09)

**Built.** `Compositor.sourcePixelFormat` is `kCVPixelFormatType_64RGBAHalf`,
so `sourcePixelBufferAttributes` asks every video track for 16-bit float,
wrapped as `rgba16Float` by `texture(from:)` (spec §11 PR-2). HDR still
arrives tone-mapped to SDR: `supportsHDRSourceFrames` is not implemented, so
it is false. Nothing else in the product changed: PR1's `layerSample`
`saturate` is the clamp a deep source's unclamped values reach. `wc -l
app/Sources/Compositor.swift`: 724 → 724. The comment was first written
two lines longer (726, the build the recorded runs and the sweep drove), then
reworded within its old lines, because the file is over the ~600-line cap
and takes nothing on. The trim is comment-only; the gate and M1's second run
ran on the trimmed build.

**PR2's controls, on PR1's committed tree** (HEAD b95d752, Release, before
the product edit; `tools/proof/work/precision/ctl-pr1/`, gitignored).
`precision_proof.py` now records the tree's formats in a capture (`formats`,
read from `Compositor.swift`; a capture without them is PR0's) and picks each
K row's rule from the control's formats against the tree's:
- `capture`: 5/5. K1–K6 rendered (K3 db8d6c07fd2c0b06, K6 76ab60469c24daa1 —
  PR0's K6 digest); formats 64RGBAHalf out, 32BGRA in. **E0** this time:
  the two `h264` exports were equal (8b2c1ab173c6f686). P1's figure 0.914.
  The ramp: `render_frame` a 16-bit PNG holding 256 distinct green values;
  `prores_422` 2.007 steps RMS.
- `--measure capture`: 2/2 (`vm.loadavg` 5.83 before, 17.81 after):

| Fixture | Average | Worst | Lifetime peak |
|---|---|---|---|
| typical 1080p | 1.23 ms | 3.58 ms | 439.1 MB |
| typical 2160p | 2.465 ms | 5.7 ms | 1,432.7 MB |
| heavy 1080p | 2.775 ms | 19.08 ms | 656.7 MB |
| heavy 2160p | 6.005 ms | 36.27 ms | 2,020.1 MB |

  The same build's PR1 record read 1,236.1 MB and 2,090.4 MB for the 4K
  peaks: the lifetime peak moves by up to ±200 MB run to run on this host.

**Recorded on Release** (the gate's `make app`):
- `precision_proof.py --control ctl-pr1`: 9/9. C0 ok; D1 and **D2** an 8-bit
  PNG — spec §11 PR-4's stop did not trip: an all-8-bit project still renders
  8-bit with every source decoded deep; P1 0.914; H1 Main, `yuv420p`;
  **R1** a 16-bit PNG whose middle row holds **1,418** distinct green values
  (the control 256); **R2** the ramp through `prores_422` at **0.707** 10-bit
  steps RMS (the control 2.007; PR0's 3.159); **C1** the H.264 clip at
  brightness −0.4: every colour channel within 1 of max(0, its brightness-0
  render − 102) (686,264 at 0, 4,936 at 1; 117,361 channels read 255 at
  brightness 0).
- `compare ctl-pr1`: 9/9. **K1–K5 byte-identical** (no video: the decode
  reaches none of them). **K6** (the H.264 clip, recorded): {0: 567,322, 1:
  184,945, 2: 130,427, 3: 7,718, 4: 5,673, 5: 2,221} and 23,294 more up to
  103, of 921,600 channels (alpha included, never moved): 38.4 % moved, 2.8 %
  by 5 or more — PR-2's spike figures (18–50 %, ≤ 3.5 %). **Measured beside
  it, against ffmpeg's own decode of the same frame** (BT.709,
  `accurate_rnd+full_chroma_int`; colour channels): the deep decode is
  NEARER the reference decoder — mean |Δ| 1.677 against PR1's 1.966, ≥ 5 on
  37,237 channels against 45,022 (largest 155 against 153). Both decoders
  differ from ffmpeg's at the clip's sharp colour edges, where 4:2:0 chroma
  is reconstructed; which reconstruction each uses is still not established.
  **E1 and E2**: the frame handed to the `h264` and `hevc` encoders is
  32BGRA; K3 byte-identical to PR1's render; K6 within the K6 row's own 103
  (the re-baseline rule's "within K6's histogram") AND byte-identical to this
  tree's own render — the 8-bit rounding is the render's own.
- `--measure compare ctl-pr1`: 2/2, no stop (`vm.loadavg` 31.91 before and
  28.00 after — other sessions were running):

| Fixture | Average (PR1 → PR2) | Worst | Lifetime peak (PR1 → PR2) | Δ |
|---|---|---|---|---|
| typical 1080p | 1.23 → 1.125 ms | 3.58 → 3.61 ms | 439.1 → 463.9 MB | +24.8 MB |
| typical 2160p | 2.465 → 2.795 ms | 5.7 → 8.71 ms | 1,432.7 → 1,671.5 MB | +238.8 MB |
| heavy 1080p | 2.775 → 2.945 ms | 19.08 → 22.89 ms | 656.7 → 665.1 MB | +8.3 MB |
| heavy 2160p | 6.005 → 7.585 ms | 36.27 → 49.36 ms | 2,020.1 → 1,882.1 MB | −138.1 MB |

  A second run on the final build (after the comment trim below; `vm.loadavg`
  11.43 before and 10.75 after):

| Fixture | Average (PR1 → PR2) | Worst | Lifetime peak (PR1 → PR2) | Δ |
|---|---|---|---|---|
| typical 1080p | 1.23 → 1.115 ms | 3.58 → 2.96 ms | 439.1 → 449.2 MB | +10.1 MB |
| typical 2160p | 2.465 → 2.735 ms | 5.7 → 7.2 ms | 1,432.7 → 1,270.6 MB | −162.0 MB |
| heavy 1080p | 2.775 → 2.6 ms | 19.08 → 23.15 ms | 656.7 → 626.9 MB | −29.8 MB |
| heavy 2160p | 6.005 → 7.38 ms | 36.27 → 44.78 ms | 2,020.1 → 1,694.3 MB | −325.8 MB |

  - **Frame time.** Heavy 1080p averages 2.945 and 2.6 ms against the 8 ms
    stop, so no stop trips. **At 4K, deep decode costs compositor time**, and
    both runs agree: heavy 6.005 → 7.585 and 7.38 ms (+23–26 %), typical
    2.465 → 2.795 and 2.735 ms (+11–13 %), while 1080p is unchanged within
    noise. The likely cost (REASONED, not measured) is each video layer's
    half-float source texture, twice the bytes per sample. A heavy 4K frame now
    averages within 0.6 ms of the 8 ms budget, while the heavy 4K export as a
    whole got faster (2.36 → 2.17 and 1.96 s), the faster deep decode
    outweighing the compositor's extra time. The spec's only frame-time stop is at 1080p, so this
    is recorded, not a stop.
  - **Memory.** The 4K peaks fall or rise by up to ±330 MB between runs of
    the same build, as the control's own spread showed (±200 MB). Deep decode
    adds no memory this instrument can separate from noise, and the +532 MB
    stop (which the owner retired) is not approached.

- **The pixel sweep on Release**, each proof on an instance of its own,
  every parity log empty, every score full, **no row re-baselined**:
  - phase1 66/66, phase2 86/86, phase3 123/123, phase4 83/83, phase5 90/90,
    phase6 168/168 (its §8, the expected video-sourced re-baseline, did not
    move: its claims hold at PR2's decode), phase7 92/92, phase8 79/79,
    phase9 222/222;
  - `phase6_chrome` 70/70, `phase7_chrome` 79/79;
  - `e1_proof` 101/101 (the 1c3e92e reference rows within ±1, as PR1 left
    them; the wipe's |Δ| 1 on 1,080 channels again), `e2_proof` 75/75;
  - `matte_proof` 46/46, `matte_probe` 6/6, `hevc_alpha_proof` 43/43;
  - `graphics_proof` 51/51, `graphics_files_proof` 10/10,
    `graphics_prefetch_proof` 7/7, `graphic_prop_action_proof` 17/17,
    `paste_graphic_proof` 8/8;
  - `word_looks_proof` 16/16 (b95d752's baseline holds), `word_looks_sheet_proof`
    9/9, `words_picture_proof` 7/7, `word_captions_proof` 20/20;
  - `codec_import_proof` 10/10, `container_import_proof` 16/16,
    `clip_inspector6_proof` 25/25, `debug_release_proof` 10/10,
    `export_cancel_proof` 7/7, `remaining_proof` 80/80, `silence2_proof`
    100/100;
  - `recording_proof` 140/140 with `--no-screen --no-microphone`, recording
    nothing (79 checks skipped by name);
  - the three preview probes 59/59 (PF included), 24/24 and 32/32.
  - Not run: `phase8_chrome.py` (its `dispatch` mode takes the keyboard
    focus, and the owner's leave covered PR1's run; PR2 changes only the
    video decode, and its compositor section draws shapes alone) and
    `preview_display_probe.py` (exits 1 by design, PR0's spike).
- `make gate` PASS on the final tree.
- **The mutants, once, on the final instrument** (Debug copies, built by
  `tree_copy.build_app`). Both were caught:
  - `decode-8bit` (`sourcePixelFormat` = 32BGRA): R1 FAILS (256 distinct)
    and R2 FAILS (2.007 steps RMS);
  - `no-source-clamp` (`layerSample`'s `saturate` removed): C1 FAILS, with
    1,233 channels off by more than 5, up to 102.

**What PR2 answers of the road map's "not established" list.** Banding: R1
and R2 measure the 10-bit ramp keeping 1,418 green values in a render and
0.707 steps RMS through `prores_422` (PR1 256 and 2.007). Real footage is
PRC-1's (its PR2 steps). The ≥ 5-level edge differences on decoded video
are measured against ffmpeg's own decode: the deep decode is the nearer of
the two. Their cause, the 4:2:0 chroma reconstruction each path uses, is
still not established. Frame times and footprints at 1080p and 4K are M1's
above, on this host only.


## PR3 — the `hevc_10bit` row, the documents, the close (2026-10-09)

**Built.**
- Core: `export_table.rs`'s eleventh row, `hevc_10bit` ("HEVC 10-bit (MP4)",
  `Container::Mp4`, codec `hevc_10bit`, video, no alpha, no size or rate,
  `AVAssetExportPresetHEVCHighestQuality`), at index 3, after `hevc_alpha`
  (spec §11 PR-3). No FFI, header or format change. Tests:
  `core/tests/export_hevc_10bit.rs` (new, 4: the preset row and its resolved
  settings written out whole, with nothing asked and with every optional
  override; the row directly after `hevc_alpha` and before `prores_422`; no
  alpha on an opaque or a transparent canvas), `export.rs`'s `EXPECTED`
  (11 rows) and module doc, `export_size.rs`'s `MOVIE_FORMATS` and
  `EVEN_SIZED`. `the_hevc_row_is_what_it_was` passes untouched.
- App: `ExporterWriter+Settings.swift` maps `"hevc_10bit"` to `.hevc`, pins
  it to `kVTProfileLevel_HEVC_Main10_AutoLevel`, and `frameForm` answers nil
  for it — PR1's carry-over: `codecType` answers `.hevc` for both HEVC rows,
  so `isMain10(settings)` (the codec NAME) is asked first, or the row would
  have been rounded to 8 bits. The `hevc` Main pin's line is kept verbatim
  (an `else if`), so PR1's `hevc-no-profile` anchors still occur once.
  `AgentCatalog+Files.swift`: the `export` tool's preset description says
  which rows keep the compositor's 16-bit frames (prores_422, prores_4444 and
  hevc_10bit; ProRes 4444 at 12 bits) and which are 8-bit (h264, hevc,
  hevc_alpha); its size description's even-dimension list gains `hevc_10bit`
  (and `hevc_alpha_proof.py`'s T0 phrase with it).
- `wc -l`: `export_table.rs` 564 → 581, `ExporterWriter+Settings.swift`
  413 → 427, `AgentCatalog+Files.swift` 562 → 564.

**`precision_proof.py`** (1,239 → 1,538 lines):
- **T1** a `hevc_10bit` export of the 10-bit ramp: ffprobe `hevc`, `Main 10`,
  `yuv420p10le`, and an MP4 (major brand `mp42`). **T2** the same ramp's
  middle-row luma against x/1919 through `hevc_10bit` ≤ 2.0 10-bit steps RMS
  and ≤ ½ of an `hevc` export's of the same project in the same run.
- **PR2's review nit 3, fixed:** `tree_formats()` read the working tree's
  `app/Sources` whatever `--app` named. `app_tree(binary)` now takes the
  sources from the tree whose `build/Build/Products` holds the app driven
  (this tree, or a mutant's copy), and an app outside any tree is refused,
  exit 2, before any launch. `--selftest` (no app): S1 a scratch tree's
  formats read through an app under its build folder; S2 an app outside any
  tree, and one under a build folder with no `app/Sources`, refused by
  `main`; S3 the default app is this tree's. 3/3.
- **MA** (`--measure ab --mutant decode-8bit`, release-only; PR2's review):
  the heavy 2160p fixture alone on this tree's Release app and on a Release
  build of the `decode-8bit` copy, alternated ABBA… (below).
- Four mutants: `hevc10-main`, `hevc10-unmapped`, `hevc10-eightbit` (PR1's
  carry-over: `frameForm` answering `.eightBit` for `hevc_10bit`) and the
  core `row-before-hevc-alpha` (no app; row CT runs `cargo test --test export
  --test export_hevc_10bit` in the copy's own core).

**Verification.**
- The loop (Debug): the three core test files (4, 38 and 20 tests), `make
  typecheck` (0 errors, the 4 baseline warnings), `make lint`, `make
  app-debug`, `--selftest` 3/3, `--only T1,T2,H1` 4/4 (T2: 1.459 against
  `hevc`'s 6.18).
- `make gate`: the first run failed its test step on the spec index's Lines
  cell for §7.8 (336 against 350), fixed; the second PASSED (typecheck, fmt
  and lint skipped as already passed; test 67 s, app 89 s).
- **Recorded on Release** (the gate's `make app`), run twice, the second on
  the final instrument (T2 with its tone; every figure the same in both):
  `precision_proof.py --control ctl-pr1` 11/11 — C0; D1 and D2 8-bit PNGs; P1 0.914; H1 Main,
  `yuv420p`; R1 1,418 distinct (control 256); R2 0.707 (control 2.007); C1
  within 1; **T1** `hevc`, `Main 10`, `yuv420p10le`, `mp42`; **T2
  `hevc_10bit` 1.459 steps RMS against `hevc`'s 6.18** (Main, `yuv420p`),
  staircase tone 0.014 codes (floor 0.010) against `hevc`'s 0.758, distinct
  middle-row codes 859 against 216; Z1. `hevc` measures 6.18 here against PR1's 6.462; the likely cause
  (REASONED, not isolated) is that its 8-bit frame is now rounded from a
  deep-decoded source rather than an 8-bit one. `hevc_alpha_proof.py` whole: 43/43 (T0
  reads the new even-dimension list).
- **The mutants** (Debug copies by `tree_copy.build_app`; the core one builds
  no app). All but `hevc10-eightbit`'s final run drove the instrument before
  T2 gained its tone; that change added measurements to `run_t` and a claim
  to T2, and left T1's, H1's and CT's code as it was:
  - `row-before-hevc-alpha`: CT FAILS — `hevc_alpha_sits_directly_after_hevc`,
    `it_sits_directly_after_hevc_alpha` and `the_menu_is_the_table` fail.
  - `hevc10-main`: T1 FAILS (`Main`, `yuv420p`).
  - `hevc10-unmapped`: T1 FAILS (the export is refused: "This Mac cannot
    export with the “hevc_10bit” preset").
  - **`hevc10-eightbit` SURVIVED T2 as the spec wrote it**, then was caught.
    Main 10 handed 8-bit frames encoded the ramp at 1.794 steps RMS — under
    2.0 and under half of `hevc`'s 6.18 — so the RMS halves cannot tell a deep
    input from an 8-bit one. Measured on the tree and the mutant in the same
    way (distinct middle-row codes 859 against 798; the column means' fine
    residual 0.541 against 0.846 codes; their amplitude at the 8-bit
    staircase's frequency 0.014 against 0.536, floor 0.010 and 0.029, and
    `hevc`'s 0.758), T2 gained the third: the staircase tone at most 0.1
    codes, with `hevc`'s at least 0.3 as its control. On the final
    instrument the tree passes (0.014) and the mutant FAILS T2 (0.536).
  - Re-run because PR3 rewrote the lines around their anchors (the `hevc`
    Main line is kept verbatim inside an `else if`): `precision_proof.py`'s
    `hevc-no-profile` — H1 FAILS; `hevc_alpha_proof.py`'s `hevc-no-profile` —
    B1 FAILS. Both caught.
- **MA, the heavy-4K A/B (PR2's review, measured now)**:
  `RC_PROOF_APP=release precision_proof.py --measure ab --mutant decode-8bit
  --rounds 3` 2/2. The `decode-8bit` copy built Release in 91 s; heavy 2160p
  alone, each export on an instance of its own, ABBA (`vm.loadavg` 17.25
  before, 16.06 after; `powermode 0`, AC power; other sessions running):

| Round | This tree (`64RGBAHalf` sources) | `decode-8bit` copy (32BGRA) |
|---|---|---|
| 1 | 8.005 ms (worst 39.02), export 2.23 s | 6.67 ms (40.49), 2.29 s |
| 2 | 8.465 ms (37.94), 3.93 s | 6.405 ms (37.75), 2.38 s |
| 3 | 8.155 ms (45.64), 2.19 s | 5.98 ms (36.25), 2.37 s |

  Medians 8.155 against 6.405 ms: **deep decode costs ×1.273 of the heavy
  4K compositor average on one load**, confirming PR2's +23–26 % as the
  decode's own cost (PR2's runs could not rule out the host load). The export
  medians are 2.23 against 2.37 s: the faster deep decode still outweighs it.
  Which part of the frame pays (PR2's REASONED half-float source sampling)
  is still not isolated: the timing log is one number a frame, and
  `Compositor.swift` (724) is over the cap for per-pass GPU timestamps.
  The averages above 8 ms are this load's; the road map's frame-time stop
  is 1080p's, and is not approached.
- `make gate` PASS on the final tree (attempt 3, 79 s; attempt 1 failed on a stale §7.8 Lines cell, fixed).

**Unfinished, filed at the close** (`ai-drafted`, `low-priority`): PR-5's
deferred list as #256 (HDR/EDR, wide gamut, linear-light blending) and #257
(10-bit `hevc_alpha`, a 10-bit reversed-clip intermediate, deep still
images, 10-bit screen recording), and #258, 4K headroom: a 10-bit biplanar
source sampled in the layer stage instead of `64RGBAHalf` (amends PR-2),
with PR2's frame and export times and MA's figures above.
