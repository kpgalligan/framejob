# Spec §11 — decisions: Precision, a matte's coverage in a deep frame onward (#597)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the PR- series of [`precision.md`](precision.md), [`precision-2.md`](precision-2.md)
and [`precision-3.md`](precision-3.md), so a citation never has to say which file. This file holds
PR-19 on, and a new PR- decision is appended here. It is new because PR-19 would have taken
`precision-3.md` past the spec's ~500-line split rule; an "above" or "below" in one entry may point
into a sibling file.

- **PR-19 — A matte's coverage is 16 bits in a frame delivered deeper than 8 bits, and a matte
  member is drawn at its frame's depth (owner, 2026-11-12, #597: "go with your
  recommendations").**
  - The owner's rule, before any code: measure a 10-bit `luma` matte first; if it bands in a
    deep export, draw mattes at 16 bits in deep exports only; if it does not, record 8-bit
    mattes as a limit.
  - What was true: a matte's composite is `MetalRenderer.workingFormat`, `rgba16Float` since
    PR-1 (MT-9's "`bgra8Unorm` composite" had been stale since then, and is corrected), so the
    one 8-bit link was the coverage, `r8Unorm` and not dithered (PR-5, MT-6).
  - The measurement and its rule, fixed before the run: `raster_dither_proof.py` GMc, a white
    full-canvas card under `precision_proof.py`'s 10-bit ProRes 422 HQ ramp (grey, every 10-bit
    code 64..940 across 1920 px) on a `luma` matte track, canvas background black, exported
    `prores_422`, the frame at 0.5 s as `rgb48le`; GMs, the same with `ramp16.png` (a 16-bit PNG
    of the same ramp) as the matte; each beside its control, the source placed plainly and
    exported the same way. The matte bands when GMc or GMs reads banding RMS above 0.15 (GM's
    bound) while its control reads at or under it.
  - Measured (Release at b86b605e, the tree before this change; row 540, x 0–800): GMc 0.3431
    against its control's 0.1126, 206 distinct 16-bit greens against 360; GMs 0.3369 against
    0.0939, 215 against 366; a `render_frame` PNG of GMc's project (GMf) 0.2930 against the
    clip's own frame's 0.0765, 107 distinct greens against 689. The coverage rounds the ramp to
    8-bit levels, a step every 7.5 px: it bands. The app at d530de3a^ (Debug) read the same
    figures.
  - The decision: the coverage is `r16Unorm` exactly when its frame is delivered deeper than 8
    bits, `RecipeSource.deliversDeep` of the frame's key (PR-16's fact): a movie export row that
    keeps the depth (PR-15's list) and a `render_frame` or Save Frame… that comes out deep. Every
    other frame keeps the `r8Unorm` coverage byte for byte: the preview, every 8-bit row, an
    8-bit PNG, JPEG, GIF, APNG, look tiles and thumbnails. The owner's words are "deep exports
    only"; a frame saved deep is included because PR-15 and PR-16 tie every other depth choice to
    the same fact, and a saved frame should not disagree with the export of the same frame.
  - How: `MattePool.beginFrame(width:height:deep:)` keeps the frame's depth, and a change of it
    empties the coverages (never the composites), as a size change empties both; `coverage(_:)`
    makes the depth's format (`MattePool.coverageFormat`). There are two resolve pipelines, one
    per format (`matteResolvePipeline`, `matteResolveDeepPipeline`), and `resolve` takes the one
    of the coverage it was handed, so the two cannot disagree. No shader change: the resolve
    returns `clamp(v, 0, 1)` and both samplers of the coverage read `.r`. `r16Unorm`, not
    `r16Float`: the same bytes, the same clamp to [0, 1] as `r8Unorm`, and uniform 16-bit steps
    where a half float has 11 bits between 0.5 and 1.
  - A frame the generator answers deep with its key unmarked (a 10-bit clip on the matte track
    and no graphic or gradient shape) is read again with its key deep when its recipe lists a
    matte (`Exporter.drawsMatte`), beside PR-15's and PR-16's reasons.
  - Memory, in a frame delivered deep only: one 3840×2160 coverage is 17,235,968 bytes
    `r16Unorm` against 8,880,128 bytes `r8Unorm`, as the device allocates them
    (`matte_pool_probe.py` P4, Apple M2 Max; 16.6 MB and 8.3 MB of pixels), one per distinct cut
    set a frame resolves. MT-9's ten matte pairs at 4K hold 66.4 MB + 10 × 16.6 MB = 232.3 MB in a
    deep frame, against 149.4 MB. No ledger counts matte textures, and none is added.
  - PR-17 and PR-18 withdrawn, decided by measurement after the coverage changed: their 8-bit
    dithered member drew only against the 8-bit coverage. On this change with each exception
    removed (their own mutants, `matte-shape-deep` and `matte-graphic-deep`, Debug), GM read
    banding RMS 0.0839, noise kept 0.0000, RMS of G − m less its mean 0.0911, and GMg 0.0836,
    0.0249 and 0.0996, both under the bound; with the exceptions kept, GM read 0.0765, 0.3744 and
    0.3834, and GMg 0.0872, 0.3216 and 0.3355. So a gradient shape or a graphic on a matte track
    is drawn at its key's depth like any other (PR-16, PR-15): the condition at
    `MetalRenderer.source(for:)` and `GraphicRegistry.Resolved.drawsDeep(matteMember:)` are gone,
    and `LayerRenderers.graphic` takes no `matteMember`. Kept: the prefetch slot's `deep` (a slot
    carrying its own depth is still right). A deep member never meets an 8-bit coverage: the
    graphics' deep pin is set only beside a `RecipeSource` mark.
  - With it (Release, after the gate's `make app`; `raster_dither_proof.py --base` the app at
    d530de3a^; Debug gave the same figures): GMc reads its control's figures exactly, banding RMS
    0.1126 and 360 distinct greens; GMs 0.0939 and 366; GMf 0.0765 and 689; GMe decodes equal to
    the base's; GM 0.0839, noise kept 0.0000 (0.0921 and 0.4411 before), and GMg 0.0836, noise
    0.0249 (0.1043 and 0.3964); E1, D1–D7, G0–G7 and GEa–GEd pass as before, 25 rows in all (the
    other seven, B1–B4b, F1 and F2, need PR-13's `--control` and were not run against one).
    `matte_proof.py` 46/46 (E4 and E5 export through a matte deep; F1 1 hit, 0 mismatched),
    `hdr_proof.py` HM and LM (an HLG project's luma mattes, within their bounds),
    `graphics_proof.py` 51/51, `graphics_prefetch_proof.py` 7/7, `matte_pool_probe.py` 5/5.
  - Mutants: `coverage-never-deep` (the frame's depth not passed: GMc, GMs, GM, GMg fail),
    `coverage-always-deep` (GMe: the h264 export of a 60 % grey card under the ramp clip no
    longer decodes equal to the base's), `frame-matte-not-reread` (GMf), and
    `matte_pool_probe.py`'s `depth-kept` (P4). PR-17's and PR-18's three mutants and
    `matte_proof.py`'s `matte-graphic-prefetch-deep` go with the code they edited.
  - Pixels change only in a deep export or a deep frame that draws a matte: the coverage is no
    longer rounded to 8 bits, so a soft edge or a product of mattes moves by under one 8-bit
    level, and a gradient shape or graphic on a matte track is drawn deep. No op, catalog,
    schema, recipe, FFI or format change; `RC_FORMAT_VERSION` is unchanged.
  - Amends PR-1 and PR-5 (the `r8` coverage), MT-6 and MT-9; withdraws PR-17 and PR-18.
