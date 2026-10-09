# Road map "precision" — 16-bit-float compositing, deep decode, 10-bit exports

**In progress.** Issue batch B94. The decisions are spec §11 PR-1..PR-5
(`designs/spec/11-decisions/precision.md`); this file is the phases' record.
When the road map closes (PR3) it is condensed into `designs/adr/precision.md`
and moved to `archive/precision.md`.

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
| PR1 | 16-bit-float working depth and output (sources stay 32BGRA): the render context, targets and pipelines `rgba16Float`, the shader clamps, the export reader deep, `ExportFrames` (`prores_4444` straightened in float, `hevc_alpha` and `h264` rounded to 8 bits first), the `hevc` Main pin, the preview probes reading the new format, the pixel sweep's re-baselines | — |
| PR2 | Deep decode: every video source `64RGBAHalf`; the ramp rows; the video-sourced re-baselines | — |
| PR3 | The `hevc_10bit` row (core and app), the documents, the ADR, close | — |

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
