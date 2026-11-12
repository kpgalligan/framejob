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

- **PR-20 — A graphic is a deep source of a saved frame (owner, 2026-11-12, #566: "go with your
  recommendations").**
  - The rule: a `render_frame` or File ▸ Save Frame… as PNG or HEIC (`keepsDepth`) whose recipe
    at the frame time draws a graphic layer is read through export's reader (`DeepStillFrame.read`)
    and is deep, a 16-bit PNG or a 10-bit HEIC, its graphics drawn from PR-15's 16-bit raster
    with no dither. Its key is marked deep, so a gradient shape (PR-16) and a matte's coverage
    (PR-19) on the same frame are deep too. `DeepVideoFrame.reads` asks it first of its
    `keepsDepth` arms (`Exporter.drawsGraphic`, which opens no file), beside PR-9's still and
    PR-12's VP9 track.
  - The reading, which the owner's answer carries: a deep source makes its frame deep beside
    anything (PR-9's shape), so a graphic over 8-bit video is a 16-bit PNG too, not only a frame
    that shows graphics alone.
  - It asks the recipe, not the project: a graphic elsewhere on the timeline, or one Show
    Selection leaves out, is not on the frame; a graphic drawn as its slate or its error card
    counts, being a graphic layer; one inside a nest counts, the recipe flattening it.
  - What does not change: JPEG, GIF and APNG (8-bit containers; an image sequence's frames are
    drawn with `keepsDepth` false), the eyedropper, Pick from Canvas, look tiles, thumbnails,
    `render_graphic`, the preview and every export row, which never ask. A frame showing only
    shapes stays 8-bit: PR-16's bullet stands, and whether a gradient shape should count too is
    a question of its own (#566 asked about graphics). The issue's second question, drawing the
    preview and the 8-bit outputs from the deep raster, stays no (PR-13's last bullet, PR-15).
  - Removed with the arm: a frame that draws a graphic no longer reaches the generator in a
    format that keeps depth, so `renderFrameReported`'s `graphic` term in the re-read of a frame
    the generator answers deep, and its two graphics marks there and in PR-14's re-read, could
    not run and are gone; the reader's branch marks the graphics pin whenever `keepsDepth` (a
    no-op for a key with no pin). PR-15's app mutants `generator-frame-not-deep` and
    `reread-not-deep` went with that code.
  - The proofs: `tools/proof/png_read.py` is the proofs' one 8- and 16-bit PNG reader;
    `graphics_proof.py`'s pixels are read through it (`graphic_prop_action_proof.py` imports
    them). Of the 26 hand decoders in `tools/proof/`, it was the one that read a `render_frame`
    of a graphic; the rest read harness and `snapshot_ui` captures or frames of projects with no
    graphic, and were left as they are. `raster_dither_proof.py`'s B3, F2 and E1 read their 8-bit
    frame through an `apng` export of the same project (an 8-bit door drawn with `keepsDepth`
    false). The app at d530de3a^ (Debug) wrote APNG frames that decode equal to its own 8-bit
    `render_frame` PNGs of the same frames, and the app before and after this change writes APNG
    frames equal to those PNGs (E1).
  - Seen first (Debug at 3cacf181, `--base` a capture by the app at d530de3a^): `render_frame`
    of `band374` alone (DG), of `flat` alone (DGf), of `band374` over an 8-bit H.264 clip (DGv)
    and of a graphic's frame (DGo) were 8-bit PNGs, DG's 1,765,486 bytes and its HEIC 8 bits a
    sample.
  - With it (Release; Debug read the same figures): DG and DGv 16-bit PNGs, 781 distinct greens
    of 801 along row 540, worst 0.0606 of a level from the exact value (D1's figures), DG
    2,372,532 bytes and its HEIC 10 bits; DGf one value in its one-colour rect, (13104, 26208,
    39295), worst 0.1012 of a level from (51, 102, 153); DGo's frame at 0.5 s 16-bit and at 1.5 s
    (no graphic) 8-bit; a JPEG of DG's frame (DGj) and E1's sheets and APNG frames equal to the
    base's. `raster_dither_proof.py --base` 30 of 37: the other seven (B1–B4b, F1, F2) need
    PR-13's `--control`, which was not made. DG's `render_frame` took 2.04 s on Debug before
    (the generator) and 0.38 s on Debug and 0.35 s on Release after (the reader), one call each.
  - Sizes (`raster_dither_proof.py` DGs, printed): a 1920×1080 8-bit H.264 cut of the owner's
    iPhone clip under a title was an 8-bit PNG of 1,743,875 bytes (base64 2,325,168) and is a
    16-bit one of 4,170,643 bytes (base64 5,560,860), past the Anthropic API's 5 MB limit on an
    image, which the assistant's helper forwards unscaled; at `max_width` 1280 it is 2,918,745
    bytes (base64 3,891,660). Frames already deep before this change are past it too: the same
    cut beside a 64×64 16-bit still, base64 6,744,504 (4,728,408 at 1280), and the iPhone clip
    itself (HEVC Main 10), base64 9,328,440 (4,994,044 at 1280). The assistant's prompt asks for
    `max_width`; whether `render_frame`'s image block should be bounded is held for the owner.
  - Mutants (Debug tree copies, each caught): `graphic-not-a-source` (DG, DGf, DGv 8-bit PNGs;
    D5, D7 at 44 distinct greens, worst 0.8918 of a level), `graphic-anywhere` (DGo: both frames
    16-bit) and `graphic-frame-pin-not-marked` (DG, D1, DGv: 16-bit PNGs of the 8-bit dithered
    raster, 44 distinct greens). Run again where this change touched their anchors or rows:
    `shape-reread-not-marked` (G7), `sdr-version-marked` (GEb), `frame-matte-not-reread` (GMf),
    `always-deep` (E1, through B3's APNG frame). `png_read.py`'s `bpp-channels` fails R1, R2 and
    R5.
  - The proofs whose frames change, on Release: `graphics_proof.py` 51/51,
    `graphic_prop_action_proof.py` 20/20, `matte_proof.py` 46/46, `image_cache_proof.py` 6/6,
    `graphics_files_proof.py` 10/10, `paste_graphic_proof.py` 8/8, `cu8_proof.py` 12/12 (its O5
    compares a 16-bit frame with an 8-bit one, so both are now read to the nearest level,
    `png_read.rgba8`; with ffmpeg's own `rgba` conversion every row differed),
    `derived_proof.py` 13/13, `docs_bugs_c1_proof.py` 35/35, `debug_release_proof.py` 10/10;
    and, sharing the edited function, `precision_proof.py` D1, S8, S10, S14–S16, `log_proof.py`
    L17, L18 and `docs_bugs_b3_proof.py` D1–D8.
  - No op, catalog schema, recipe, FFI or format change; `RC_FORMAT_VERSION` is unchanged.
    `render_frame`'s description gains one sentence. Amends PR-4, PR-9 and PR-15.
