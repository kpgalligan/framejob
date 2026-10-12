# Precision-2: deep stills and the 10-bit reverse (road map "precision-2", #257)

- **Status:** Built and closed 2026-10-11. Each phase was one litecode pipeline with its own review, worked in `~/devel/reelcut-i257` on branch `i257` and merged into main after its gate:
  - P2-0, the road map, PR-6..PR-8 and the toll, `ReverseProgressSheetController.swift` (`34445fa`)
  - P2-1, deep stills (PR-6) (`44b2077`)
  - P2-2, the 10-bit reverse (PR-7) (`aed143d`)
  - P2-3, the close: this record (uncommitted when this was written)
- **Original:** `archive/precision-2.md` is the full record. It has no section numbers, so it is cited by phase: "orig P2-1" is its "P2-1 — deep stills" section.
- **Spec decisions:** PR-6..PR-8 in spec §11 (`designs/spec/11-decisions/precision.md`), with the amendments they wrote into PR-4 and PR-5. They stay binding, and where the original words them differently, §11's text wins:
  - PR-6: a still deeper than 8 bits a component is drawn at 16-bit float. `LayerRenderers.renderImage` checks `image.bitsPerComponent > 8`, draws into a 16-bit-float premultiplied RGBA sRGB context and uploads `rgba16Float`; an 8-bit still takes the old path byte for byte. The decode is unchanged; no shader, uniform, recipe or format change; thumbnails and posters stay 8-bit. Amends PR-5's "still images".
  - PR-7: the reversed intermediate is 10-bit, carries the source's colour labels and keeps the source's exact size. An even-sized source is written HEVC Main 10 at every size from `x420` frames, at HEVC's rate; an odd width or height is written ProRes 422 from `x422` frames. No `AVVideoColorPropertiesKey`; the held copy is per plane and propagates the buffer's attachments; the slice budget counts the held format's bytes; the digest's input gains a renderer version. PR-2 stands: HDR stays tone-mapped in the compositor (amended by GR-15: HDR still reaches the output as SDR, converted by Reelcut's own step 0). Amends PR-5's "the reversed-clip intermediate".
  - PR-8: 10-bit `hevc_alpha` and 10-bit screen recording are not wanted; PR-5's list is not edited, and this closes those two of its deferrals.
  - Amended: PR-4, by PR-6 — "any source is deeper" counts video sources only: a stills-only project renders 8-bit (S4), as does a 16-bit still over an 8-bit clip (S5), while a 16-bit still over a 10-bit clip renders 16-bit with the still's depth kept (S6); the owner accepted the stills-only case, "Accept it". PR-4, by PR-7 — a reversed clip counts by its intermediate, which is 10-bit, so a project whose only video is a reversed 8-bit clip renders 16-bit frames; the owner, "Accept 16-bit". PR-5 carries an "Amended by PR-6 and PR-7" line.

## Context

PR-5 left four paths 8-bit and deferred them to #257: 10-bit `hevc_alpha`, the reversed-clip intermediate, still images and screen recording. The #257 brief (`~/.claude/litecode/reelcut/i257-8bit-paths/I-257.md`, 2026-10-11, tree `19ef985`) measured each, and the owner's answers (`…/i257-8bit-paths/answers.md`) were "All as recommended": build deep stills (1a) and the 10-bit reverse for every reverse with the source's colour labels (2a), close 10-bit `hevc_alpha` (3) and 10-bit recording (4) as not wanted, and work the grading-2 way in one worktree, each phase merged when its gate passes (5). The odd-size reverse defect the brief found (a 1919×1079 source reversed to 1918×1078) was fixed in P2-2 rather than filed. Two items were built and two closed.

## Decisions

- **The depth test is `image.bitsPerComponent > 8`, and an 8-bit still keeps the old path byte for byte.** `ramp8.png` reads 256 levels either way, at 25.7 ms decode+draw through the 8-bit bitmap against 63.4 ms through the half-float one, so only a deep still pays. Its guard, the `still-always-deep` mutant, survived S3's opaque and alpha-ramp scenes (both byte-identical to the 8-bit draw) and was caught only once S3 gained a colour scene (`still8a.png` under brightness 0.1 and contrast 0.5), where the compositor's un-premultiply carries the 8-bit draw's premultiplied rounding through a non-identity step (`{0: 921138, 1: 462}`). (orig "Deep stills (P2-1)", P2-1)
- **The deep bitmap is sRGB half-float** (`premultipliedLast | floatComponents | byteOrder16Little`, with `bitmap(_:)`'s size guard), because the compositor works on encoded values. The `still-deep-linear` mutant (the bitmap in `linearSRGB`) failed S1 and S2 on RMS, 214.9438. (orig P2-1)
- **The 8-bit control fixture is written ROUNDED.** The first `ramp8.png`, ffmpeg's `rgb48`→`rgb24` conversion of the 16-bit ramp, truncates, which put its steps where they nearly cancelled the staircase tone that Core Graphics' rounded 8-bit draw produces (0.0301, under the 0.3 the instrument needs to discriminate). Written 8-bit and rounded (`round(X*255/(W-1))`), it matches Core Graphics' draw of `ramp16.png` in 1916 of 1920 columns, max |Δ| 1. Every threshold stayed. (orig P2-1)
- **The 10-bit HEIC fixture goes through a float bitmap, and out of the preflight.** ffmpeg cannot mux HEIF; `sips` gave 410 codes and ImageIO's writer handed the PNG's 16-bit INTEGER image 256 at quality 0.99, while the same writer handed the image drawn into a 16-bit-float sRGB bitmap wrote Main 10 with 1,024 codes, which ImageIO decodes at `bitsPerComponent` 10. So `heic10_writer.swift` is the fixture's maker. It is made only when S7 runs, and a refusal is S7's FAIL naming the reason, so no other row depends on the Swift build or ImageIO's HEIC writer. (orig P2-1, fix passes 1–2)
- **HEVC Main 10 at every even size, ProRes 422 at an odd size.** HEVC 4:2:0 cannot hold an odd size: 1919×1079 came back 1918×1078 from both the old renderer and the Main 10 variant, and `videoSettings`' own doc says the size must be exact or the clip stretches when reversed. `ReverseRenderer.Intermediate` is decided once in `write` from the measured dimensions: `.hevcMain10` (`x420`, 3 bytes a held pixel) or `.proRes422` (`x422`, 4 bytes). The cost was accepted for exact size: 6.0× the old file on `testsrc2` at 1919×1079 (`reverse-cost`), roughly 5–8× in the brief's codec-only figures. (orig "The 10-bit reverse (P2-2)", P2-2)
- **No colour key, and the decoder's attachments propagated.** An HLG BT.2020 ramp reversed by the old renderer held HLG-coded values in a file labelled `bt709` ×3; the Main 10 variant with no forced labels kept `arib-std-b67/bt2020/bt2020nc`. Forcing BT.709 through a transcode that kept the reader's attachments converted the picture (mean |Δ| 20.8 and 20.6 8-bit levels), so forcing labels is wrong either way. `copyBuffer` copies every plane, with no plane guard, and calls `CVBufferPropagateAttachments`. Mutants: `reverse-709-labels` (V2 `bt709` ×3, V3 25.661 levels), `reverse-no-attachments` (V2 no tags; V3 also failed, 3.863, not scored), `reverse-planar-drop` (the old one-plane guard: 0 frames written). (orig "The 10-bit reverse (P2-2)", P2-2)
- **V3 was made to discriminate with a chroma ramp, bound 0.25 levels.** On the grey HLG ramp (Cb = Cr = 512) no matrix or primaries label can move a code, and V3 passed on the unchanged product at the spec's 1.0 bound (0.541). The old renderer converted through RGB with the source's matrix, so its picture was right and only its labels were wrong. `chroma10_hlg.mov` (Cb rising, Cr falling across the width) reads 0.764 (max 3.86) on the old renderer and 0.078 (max 0.996) on the new; the bound was set between them. (orig P2-2)
- **The digest carries the renderer's version, and V4 waits for it by name.** `ReverseCache.rendererVersion = 2`; the digest's input ends `|v2`, so an old 8-bit reverse lands under a different name and `prune` deletes it; §5.6's `<media id>-<digest>.mov` pattern is unchanged. The planted pre-version file already matched V4's glob, so the review made V4 wait for the versioned file by name (`wait_reverse(…, want=)`); `reverse-unversioned` then fails V4 by the wait's 300 s bound. (orig P2-2)
- **The slice budget counts the intermediate's bytes a pixel** (`sliceDuration`), so `bufferBudget`'s 512 MiB holds 86 frames of 1080p and 21 of 4K at 3 bytes a pixel. (orig "The 10-bit reverse (P2-2)", P2-2)
- **R1's control clause holds only for a 32BGRA-decoded capture.** That clause (≤ 256 distinct) was written for a capture whose tree decoded 32BGRA; `ctl-p21` decodes `64RGBAHalf` and read 1418. R1 now holds the control to ≤ 256 only when the capture's recorded `formats.source` is 32BGRA (or absent), and otherwise prints it. (orig P2-1)
- **The two closures (PR-8).** 10-bit `hevc_alpha`: Main 10 with alpha works (877 colour levels against 219 at Main), but the alpha plane stays 8-bit at every profile (256 levels, measured); its content is mostly PR-5's 8-bit graphics, and `prores_4444` is the deep alpha master. 10-bit recording: `SCRecordingOutputConfiguration` has no profile, depth or rate key (only `avc1`/`hvc1` and MP4/MOV, measured); the only documented 10-bit route is the HDR10 PQ preset, which PR-2 would tone-map back, and a self-written encoder would rebuild the recorder's pause and segment machinery. (orig "Closed as not wanted")

## What it built — where it lives now

- App: `LayerRenderers.swift` (537 lines: `renderImage`'s `let deep = image.bitsPerComponent > 8`, `deepBitmap(_:)`, `upload(pixelFormat:)` defaulting to `.bgra8Unorm`); `ReverseRenderer.swift` (1,221 lines: `Intermediate`, `read`'s pixel format through `walkBackwards`, `copyBuffer`, `videoSettings`, `sliceDuration`, `ReverseCache.rendererVersion`, the rewritten doc comments); `ReverseProgressSheetController.swift` (192 lines, the P2-0 toll: `// MARK: - Progress` moved out whole).
- Core: none. No compositor, shader, FFI, MCP or format change.
- Proofs: `precision_proof.py` (S1–S7, `capture` Sc, `compare` S3, V0–V6, the mode `reverse-cost`, and precision-2's ten mutants: `still-eightbit`, `still-deep-linear`, `still-always-deep`, `reverse-bgra`, `reverse-main`, `reverse-709-labels`, `reverse-planar-drop`, `reverse-no-attachments`, `reverse-unversioned`, `reverse-odd-hevc`); `reverse_probe.swift` (the real renderer on one file, built through `swift_build.build`; its stamp half is `source_mirror_probe.py` §3's); `heic10_writer.swift`; `tools/proof/capture_spike/inventory.json`'s `ensureReversedMedia()` anchor re-pinned to `ReverseProgressSheetController.swift`. `tools/proof/README.md`'s "precision-2 P2-1" and "precision-2 P2-2" paragraphs.
- Person checks: PRC-3 (a reversed HDR clip, and a log clip with a LUT, beside their forward twins) and PRC-4 (a 16-bit gradient still under a strong curve, preview and `prores_422`) in `docs/manual-checks.md`.
- Docs: spec §5.6 (the digest sentence, "and the renderer's version"), §7.5 (a deep still is an `rgba16Float` source), §11 (PR-6..PR-8, the PR-4 and PR-5 amendments, the index rows), the README's Export bullet, `app/CLAUDE.md`'s `ReverseRenderer.swift` and `LayerRenderers.swift` entries.

**Stills** (Release, `precision_proof.py --control ctl-p21`, fix pass 1's recorded run, 17/17; AC power, `powermode 0`; other sessions working, so no timing is claimed; distinct 10-bit Y codes on the ramp's middle row, RMS against the ideal, staircase tone):

| | distinct | RMS | tone |
|---|---|---|---|
| S1 `ramp16.png` / S2 `ramp16.tif` through `prores_422` | 862 | 0.4007 | [0.0069, 0.0063] |
| S7 `ramp10.heic` through `prores_422` | 862 | 0.4699 | [0.0183, 0.0139] |
| the in-run 8-bit control (`ramp8.png`) | 513 | 1.4157 | [1.2258, 0.0119] |
| the control tree (`ctl-p21`, P2-0's product) | 512 | 1.414 | [1.2236, 0.0134] |

`render_frame` depth: S4 8 for both stills; S5 8 (256 greens); S6 16 (1,920 greens, the still's; 256 when it is drawn 8-bit). `compare ctl-p21`: 10/10, S3 byte-identical on all three scenes. Brief figures (Apple M2 Max, macOS 26.5.1, AC power): 1,024 levels from the deep draw against 256; decode+draw 87.5 against 87.3 ms (1080p PNG); a deep 4K texture 66.4 MB against 33.2 MB.

**Reverse** (Release, `precision_proof.py --control ctl-p21`, 24/24; the old figures from a Debug copy whose `ReverseRenderer.swift` is `44b2077`'s, 1/8):

| Row | old renderer | after PR-7 |
|---|---|---|
| V0, the 10-bit ramp's reverse | H.264, 216 codes, 2.545 RMS | `hevc` Main 10 `yuv420p10le`, 860 codes, 0.592 RMS; stamps 30 of 30 |
| V1, reversed through `prores_422` (forward 0.707) | 3.077 | 0.643 |
| V2, an HLG BT.2020 ramp's labels | `bt709` ×3 | `arib-std-b67/bt2020/bt2020nc`, mean \|Δ\| 0.108 codes |
| V3, the HLG chroma ramp against its forward twin | 0.764 levels | 0.078 (max 0.996), bound 0.25 |
| V4, a pre-version reverse in `cache/reversed/` | used and kept | re-rendered, the planted file pruned |
| V5, the 1919×1079 ramp | 1918×1078 | ProRes 422 `yuv422p10le` at 1919×1079 |
| V6, a reversed 8-bit clip's `render_frame` | 8-bit, `h264` | 16-bit, `hevc` Main 10 |

`reverse-cost` (the probe built `-O`, three reverses each, medians; AC power; load 7.7–8.7 for the old renderer, 25.9–28.7 for the new, so wall times compare loosely):

| Source | Wall | Size | Rate | Peak RSS | Written as |
|---|---|---|---|---|---|
| 2 s ProRes 1080p | 0.453 → 0.474 s | 2,344,933 → 1,764,385 B | 9.38 → 7.06 Mbps | 587 → 454 MB | h264 → hevc Main 10 |
| 2 s ProRes 2160p | 0.925 → 0.916 s | 7,124,361 → 7,025,662 B | 28.5 → 28.1 Mbps | 788 → 708 MB | hevc Main → Main 10 |
| 2 s `testsrc2` 1919×1079 | 0.461 → 0.384 s | 2,959,786 → 17,698,683 B (6.0×) | 11.84 → 70.79 Mbps | 589 → 574 MB | h264 1918×1078 → ProRes 422 1919×1079 |
| 1 s ramp | 0.313 → 0.317 s | 34,223 → 13,195 B | — | 333 → 263 MB | h264 → hevc Main 10 |

Mutants: all ten MUTANT PASS (P2-1's three, `still-always-deep` once S3 had its colour scene; P2-2's seven).

## Known limits

- **HEVC Main 10 playback decode cost against H.264** (the ≤ 1080p reverses that switched codec) is REASONED, not measured: Apple silicon decodes both in hardware, and the compositor decodes every source to `64RGBAHalf` already.
- **The odd-size ProRes branch's cost is measured on synthetic sources only** (`testsrc2` and a flat ramp; 6.0× at 1919×1079). On camera footage it is REASONED larger (#274).
- **A 4K deep still is 66.4 MB** against 33.2 MB, in a layer pool of up to 64 entries (`LayerRenderers.cacheLimit`); the peak with many deep stills is not measured.
- **`render_frame`, Save Frame…, GIF and APNG of a deep still are 8-bit unless a deep video source is in the frame** (S4, S5; PR-4 as amended). The owner's ruling covered the stills-only case; S5 is measured and recorded (#275). Exports keep the depth.
- **The preview's look is a person's check**: PRC-3 (the reverse beside its forward twin) and PRC-4 (a deep still under a strong curve); `precision_proof.py` measures levels and labels on synthetic fixtures.
- **`ReverseRenderer.swift` is 1,221 lines**, under the 1,311 it was before P2-0's toll. Its named next cut is `ReverseCache`, `ReverseResolution`, `ReverseStatus` and `ReverseSource` out whole to `ReverseCache.swift` (`designs/adr/app-file-history.md`).
- **`reverse-cost`'s wall times compare loosely**: other sessions were working (load 7.7–28.7 across P2-2's runs), and the old and new renderers ran at different loads.

## Open items

Filed at the close, each `ai-drafted` and `low-priority`:
- #274: The odd-size reverse's ProRes 422 cost, measured on camera footage.
- #275: `render_frame`, Save Frame…, GIF and APNG of a deep still are 8-bit unless a deep video source is in the frame.

Commented: #256 (the reverse now carries the source's colour labels, so HLG stays HLG, PR-7; a deep still is drawn half-float in sRGB, PR-6; tier 3 inherits both). The owner's PRC-3 and PRC-4 are in `docs/manual-checks.md`. #257 closed by the orchestrator, naming the four commits.

## Where to look in the original

- "The owner's choices": the five answers, verbatim and dated, and the odd-size fix taken into P2-2.
- "Deep stills (P2-1)": where the depth was lost (line numbers at `19ef985`), what changes, the brief's still measurements, `render_frame`'s mechanism.
- "The 10-bit reverse (P2-2)": where the depth and labels were lost, the colour-label measurements, the odd-size fix and its cost, the brief's real-renderer table and its host.
- "Closed as not wanted": PR-8's two measurements.
- "Not established": the seven open points as planned, each settled or carried in the phase records and the close.
- P2-0: the pure move, its two `diff`s and the cold gate.
- P2-1: what landed, S4 and the owner's "Accept it", the rounded 8-bit fixture, the control `ctl-p21`, R1's control clause, the recorded runs and mutants; fix pass 1 (S3's colour scene, S5/S6, the 10-bit HEIC and S7) and fix pass 2 (the HEIC out of the preflight, S3c's kept references).
- P2-2: what landed, V6 and the owner's "Accept 16-bit", V3 made to discriminate, the odd-sized cost fixture, the controls on the unchanged product, the recorded runs, `reverse-cost`, the seven mutants and the review's two nits.
- P2-3: the close, its verification and the issues.
