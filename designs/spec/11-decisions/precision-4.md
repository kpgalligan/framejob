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

- **PR-21 — A gradient shape is a deep source of a saved frame (owner, 2026-11-13, #605:
  option 1, "Everything else that isn't waiting on files or manual work from me, go with your
  recommendations").**
  - The rule: a `render_frame` or File ▸ Save Frame… as PNG or HEIC (`keepsDepth`) whose recipe
    at the frame time draws a shape layer with a gradient (`ShapeProps.drawsGradient`: a
    `rectangle` or `ellipse` whose `gradient` has two stops or more) is read through export's
    reader and is deep, a 16-bit PNG or a 10-bit HEIC, beside anything: alone, over 8-bit video,
    beside a graphic. Its key is marked deep, so the gradient is PR-16's 16-bit float ramp with
    no dither. `DeepVideoFrame.reads` asks it second of its `keepsDepth` arms
    (`Exporter.drawsGradientShape`, which opens no file), after PR-20's graphic and before PR-9's
    still and PR-12's track.
  - Why: a person cannot tell a gradient a shape draws from one a graphic draws, so a saved
    frame's depth does not depend on which drew it. The issue's "about twice the bytes" was
    measured otherwise for a gradient alone: Core Graphics' dither is noise a PNG cannot
    compress, so `shape563`'s frame (G0) was an 8-bit PNG of 1,830,922 bytes before this change
    and is a 16-bit one of 78,836 bytes with it (Debug, one run each); over footage the
    footage's own 16 bits set the size, as for a graphic (PR-20).
  - It asks the recipe, as PR-20 does: a gradient shape elsewhere on the timeline is not on the
    frame; one flattened out of a nest counts; one that is a matte member counts, being a recipe
    layer (its coverage is then 16 bits, PR-19). A frame of flat shapes, lines, arrows, text or
    word captions stays 8-bit.
  - What does not change: JPEG, GIF and APNG, the preview, the eyedropper, Pick from Canvas, look
    tiles, thumbnails and every export row, which never ask.
  - Removed as unreachable: a frame that draws a gradient shape no longer reaches the generator
    in a format that keeps depth, so `renderFrameReported`'s `gradient` term in the re-read of a
    frame the generator answers deep (PR-16's) is gone, and that re-read is PR-19's matte
    alone. PR-16's app mutant `shape-generator-frame-not-deep` went with that code. PR-14's
    re-read and its mark stay: they still serve a matted frame the generator answers 8-bit while
    it shows a deep source, which `raster_dither_proof.py` GMr now holds (G7, its old row, is
    read by this arm before the generator).
  - Seen first (`raster_dither_proof.py`, Debug at aa5a1512 and the app at d530de3a^): G0
    (`shape563` alone) and GV (the same over a 256×144 8-bit H.264 clip) were 8-bit PNGs, G0's
    HEIC 8 bits a sample.
  - With it (Release; Debug read the same figures): G0 and GV 16-bit PNGs, 785 distinct greens
    of 801 along row 540, worst 0.0296 of a level from the exact ramp; G0's HEIC 10 bits; GEa, an
    `apng` export's frame of G0's project, equal to the base's (the 8-bit doors keep Core
    Graphics' dithered bytes); GMr, a matted frame over an 8-bit clip, 689 distinct greens and
    banding RMS 0.0765, as GMf; DGo's flat shape still an 8-bit PNG. The whole
    `raster_dither_proof.py --base` (the app at d530de3a^) 37 of 44: the other seven (B1–B4b, F1,
    F2) need PR-13's `--control`, which was not made.
  - Mutants (Debug tree copies, each caught): `gradient-not-a-source` (G0, GV, and G5, whose
    generator path no longer reads a gradient again), `flat-shape-a-source` (DGo). Re-aimed:
    `shape-always-deep` on GEa's APNG door and GEd, `reread-not-marked` (PR-14's mark) on GMr.
  - Other proofs whose frames change: `phase6_proof.py` sections 9–13 read a 16-bit PNG to the
    nearest level, and section 9 compares a one-colour gradient's levels with the flat fill's
    where it compared digests; `matte_proof.py`'s `rgba` reads through `png_read.rgba8` (L2 missed
    by 1.63 of a level through ffmpeg's `rgba`); `precision_proof.py` P1 reads its render at 16
    bits. On Release: `phase6_proof.py` 168/168, `matte_proof.py` 46/46, `precision_proof.py
    --only C0,D1,P1` 4/4 (P1 at RMS 0.357 10-bit steps).
  - No op, catalog, recipe, FFI or format change; `RC_FORMAT_VERSION` is unchanged.
  - Amends PR-16 ("a shapes-only frame stays an 8-bit PNG") and PR-20 ("a shapes-only frame
    stays 8-bit"): a frame of flat shapes only stays 8-bit.

- **PR-22 — `render_frame`'s image block is an 8-bit PNG copy of a deep frame, and
  `full_depth_image` asks for the file (owner, 2026-11-13, #604: "Is the api limit ours? If so,
  I think we should raise it. Perhaps default to 8 bit and have an optional parameter that can
  pull the full PNG.").**
  - The limit is the Anthropic API's, 5 MB an image (5,242,880 bytes of base64), not Frame
    Job's, so it cannot be raised; the second half of the answer applies.
  - The image block is what the model sees, and it is a copy: the file `render_frame` writes and
    the path it answers stay as deep as the frame (PR-9, PR-20, PR-21), and File ▸ Save Frame…
    is unchanged. The block, by the file written:
    - a PNG of a frame of 8 bits a component: the file's bytes, `image/png`, as before;
    - a PNG of a deeper frame: an 8-bit PNG copy, `image/png`;
    - a JPEG: the file's bytes, `image/jpeg`, as before;
    - a HEIC, of any depth: an 8-bit PNG copy, `image/png`. The API takes JPEG, PNG, GIF and
      WebP and not HEIC, and PNG keeps the alpha a HEIC frame carries.
  - `full_depth_image: true` (a boolean, default false) puts the file's own bytes in the block,
    with the file's type (`image/png`, `image/heic`). It chooses the block only: the file's depth
    is still never an argument (PR-4's and PR-9's "no `depth` argument").
  - The copy (`FrameBlock`): the frame labelled as its file is (BT.709, PR-11; an HLG project's
    BT.2100 HLG), drawn at its own size into an 8-bit premultiplied RGBA context in that space
    with no interpolation, and encoded PNG with no properties. Same size as the file, so
    `max_width` bounds both. A copy that cannot be made leaves the file's bytes in the block: a
    copy never fails the tool.
  - The text: a block that is a copy adds one sentence before the last, "The image here is an
    8-bit PNG copy of the 16-bit PNG file." (a HEIC: "… of the HEIC file."); a block that is the
    file adds nothing, so every call that answered an 8-bit PNG answers the text it did, and
    "Written to <path>." stays last.
  - The description says which frames' images are copies, that the full-depth image of a 1080p
    frame can pass the API's 5 MB image limit, and that `max_width` keeps it under; the
    assistant's prompt says the image is an 8-bit copy and not to pass `full_depth_image`.
    `agent/src/main.ts` is unchanged (it forwards the block as given).
  - Not done: bounding an 8-bit block by size (the issue's option c). An 8-bit copy of a canvas
    larger than 1080p can still pass the limit, as an 8-bit frame could before PR-20; `max_width`
    is the way. Measured (BKk, printed): a 3840×2160 frame of noisy generated footage under a
    graphic, its 8-bit block base64 6,782,656.
  - Seen first (`raster_dither_proof.py`, Debug at aa5a1512, generated footage `blk1080` under a
    graphic): the file a 16-bit PNG of 4,804,889 bytes (base64 6,406,520) and the block that file
    (BK1); a HEIC's block `image/heic` (BK4); `full_depth_image` refused by the argument gate as
    a stranger (BK2, BK5).
  - With it (Release; Debug read the same figures): BK1's block an 8-bit PNG of the file's size,
    base64 2,985,988, every sample within one level of the file's rounded (the worst 1, over
    8,294,400 samples), with the copy sentence; BK2 the file's bytes; BK3, an 8-bit frame, its
    file's bytes and no sentence; BK4 the HEIC's default block the 8-bit PNG and with
    `full_depth_image` `image/heic`, the file's bytes; BK5 "full_depth_image must be true or
    false." and the argument published as a boolean. On the owner's footage (DGs, printed,
    Release only), the default block against the file, base64: the title over the 8-bit cut
    2,326,800 against 5,560,860; the cut beside a 16-bit still 2,806,964 against 6,744,504; the
    iPhone clip itself 3,210,716 against 9,328,440; all three under the limit unscaled. In an HLG
    project (BK6, #611, a graphic alone): the block an 8-bit PNG of the file's size, the copy
    drawn in BT.2100 HLG, base64 458,472 against the 16-bit file's 3,305,516, every sample within
    one level of the file's rounded (the worst 1, over 8,294,400), with the copy sentence.
  - Mutants (Debug tree copies, each caught): `block-is-the-file` (BK1, BK4),
    `full-depth-ignored` (BK2, BK4), `block-always-recoded` (BK3, on the copy sentence alone: an
    8-bit frame's re-encoded PNG is byte-identical to its file), `heic-block-follows-file` (BK4),
    `hlg-block-not-copied` (#611: the copy refused in BT.2100 HLG only, so BK6's block is the
    16-bit file with no sentence, while BK1–BK5 pass under it; `block-is-the-file` scored the
    same way breaks BK1 and BK4).
  - No op, recipe, FFI or format change; the catalog gains one argument of an app-state tool.
  - Amends PR-4 and PR-9 (no `depth` argument: still none for the file) and PR-20 (whether the
    image block should be bounded, held for the owner, is decided here).
  - Amended by PR-23: a default block whose base64 would pass the limit is drawn smaller until it
    fits, so "Not done: bounding an 8-bit block by size" and "Same size as the file" no longer
    hold for such a block. Amended by PR-24: 5,242,880 is Amazon Bedrock's limit, the smaller (the
    Anthropic API's own is 10 MB of base64), not the Anthropic API's. Amended by PR-25: PR-23's
    scale is taken out, so both hold again for every block.

- **PR-23 — `render_frame`'s image block is scaled down alone when its base64 would pass the
  API's limit (owner, 2026-11-12, #610: option (b), "#610: b").**
  - The rule: when a default image block's base64 (`Data.base64EncodedString()`, 4·⌈n/3⌉ bytes
    for n raw) would be more than 5,242,880 bytes, the Anthropic API's limit on one image
    (PR-22), the block alone is drawn smaller until it fits. Exactly at the limit fits. The file
    `render_frame` writes, its size and depth, the path it answers, `max_width`'s meaning and
    File ▸ Save Frame… are untouched.
  - Every default block is bounded: the 8-bit PNG copy of a deep PNG and of a HEIC, an 8-bit PNG
    that is the file, and a JPEG that is the file. An 8-bit 4K frame's block could pass the limit
    before PR-20 too, and so can a JPEG's.
  - `full_depth_image: true` is exempt: it is an explicit ask for the file's bytes, which stay in
    the block whatever their size. Its description already said a full-depth frame can pass the
    limit and that `max_width` keeps it under, and now says it is never scaled. BK2's block
    (base64 6,406,520, over the limit) stays the file's bytes.
  - The scaled block's type follows the unscaled one's: an 8-bit PNG where the block was a PNG
    (the file or the copy), a JPEG where it was the JPEG file. A scaled block is never the file's
    bytes.
  - The draw (`FrameBlock.scaledDown`): the frame labelled as its file is (BT.709, PR-11; an HLG
    project's BT.2100 HLG) drawn at the smaller size in that space with `interpolationQuality
    .high`, since a downscale needs interpolation. A PNG goes into an 8-bit premultiplied RGBA
    context and is encoded with no properties; a JPEG goes into an opaque 8-bit context filled
    black first (the file's flatten) and is encoded at `FrameWriter.quality`. It is drawn from the
    frame, not decoded from the unscaled block. PR-22's full-size copy keeps its draw with no
    interpolation, so a block that fits is the bytes it was.
  - The loop: each attempt takes the last encode's raw bytes b and width w; the next width is
    ⌊w · min(0.9, 0.9·√(3,932,160 / b))⌋, 3,932,160 being the raw bytes whose base64 is the
    limit, and the height comes from `Exporter.scaledSize` (`max_width`'s arithmetic: aspect
    kept, rounded, at least 1). It stops at the first encode that fits. PNG size is not monotonic
    in scale, so every attempt is measured, and there are at most 16 (each shrinks the area to at
    most 0.81).
  - A scale never fails the tool, PR-22's rule for the copy: an encode that cannot be made, or
    16 attempts that do not fit, leave the unscaled block, with no scale sentence.
  - The text: one sentence after the copy's sentence when there is one, before "Written to
    <path>.": "The image here is scaled down to <w>×<h> px to fit the API's 5 MB image limit;
    the file is not scaled." A block that fits answers the bytes and the text it did, and the
    test costs it one comparison.
  - `render_frame`'s description says an image block that would pass the limit is scaled down
    alone, the file untouched, and that `full_depth_image` is never scaled; its schema is
    unchanged. The assistant's prompt still asks for `max_width` (unchanged here: #599's road map
    edits that file).
  - Seen first (`raster_dither_proof.py`, Debug at e0206243, each 3840×2160 frame's premise held):
    BKk (`blk2160` under `flat`) the 8-bit copy at 3840×2160, base64 6,782,656, beside the 16-bit
    file's 14,241,128; BKp (`blk2160` alone) the 8-bit file, base64 7,031,532; BKj (a noise still
    as JPEG) the JPEG file, base64 12,441,372; none with a scale sentence, so all three failed.
  - With it (Release; Debug read the same figures): BKk's block an 8-bit PNG of 3038×1709, base64
    4,469,860, after the copy's sentence; BKp's 2984×1679, base64 4,456,620; BKj's `image/jpeg`
    2243×1262, base64 3,242,680; each the first attempt, the file untouched, the scale sentence
    naming its size before "Written to <path>.", and the block the frame (block and file each
    reduced to 64×36: mean |Δ| 0.324, 0.027 and 0.213 levels against a bound of 2).
    `render_frame` took 1.99 s for BKk, 0.67 s for BKp and 0.59 s for BKj on Release (Debug 6.73
    s for BKk, 5.84 s before the change). BK1 (its block base64 2,985,988, as before), BK2 (the
    file, 6,406,520, over the limit and not scaled), BK3 and BK4–BK6 unchanged. The whole
    `raster_dither_proof.py` on Release 31 of 48, the other seventeen needing PR-13's `--control`
    or a base capture, neither made (as #611's run, 28 of 45).
  - Mutants (Debug tree copies, each caught): `block-not-bounded` (the size test always fits:
    BKk, BKp and BKj's blocks over the limit at 3840×2160); `block-always-scaled` (the scale
    entered whatever the size: BK1's copy 1728×972, BK3's block not the file); `full-depth-scaled`
    (the exemption dropped: BK2's block an 8-bit PNG, not the file); `limit-counts-raw-bytes`
    (the raw bytes compared with 5,242,880: BKk's unscaled block, 5,086,992 raw bytes and
    6,782,656 as base64, left over the limit; BKp's, 5,273,648 raw, and BKj's are past both, so
    only BKk can catch it); `scale-sentence-dropped` (BKk, BKp, BKj); `scaled-jpeg-as-png` (BKj's
    block `image/png`); `aspect-not-kept` (the scaled height left at the frame's: BKk 2668×2160,
    BKp 2600×2160). PR-22's `block-is-the-file` (BK1's 16-bit file now scaled to 1563×879 with no
    copy sentence; BK4 `image/heic`) and `hlg-block-not-copied` (BK6 the 16-bit file, BK1–BK5
    passing) run again, since this change moved the function their anchors are in.
  - No op, recipe, FFI, format or catalog schema change; `RC_FORMAT_VERSION` is unchanged.
  - Amends PR-22 (its "Not done: bounding an 8-bit block by size", and "Same size as the file, so
    `max_width` bounds both", which now holds only for a block that fits).
  - Amended by PR-24: the block's sides are deliberately not bounded, by the owner's choice that a
    caller sizes its own image (`max_width`) and that the description says what the API does with
    a large one; the 5 MB bound stays because it is Amazon Bedrock's, the smaller (10 MB on the
    Anthropic API), not the Anthropic API's as the rule above says.
  - Superseded by PR-25 (owner, 2026-11-13, #618: "Take it out"): the scale is removed and no
    block is scaled.

- **PR-24 — `render_frame`'s image block is not bounded by its sides; the description says what
  the API does with a large image, and `max_width` is the caller's control (owner, 2026-11-13,
  #612: option (a)).**
  - The owner's words: "If the tool description describes the situation, leave it alone. Scaling
    images automatically may not be what the caller actually wants. MCP callers need to be smart
    enough to handle these situations."
  - The rule: no cap, no scaling and no refusal of a block by its sides, by default or with
    `full_depth_image`; `max_width` keeps its range 16…8192 and its meaning, so a width of 8001…
    8192 stays legal; no new argument. PR-23's scale by size stands as it is.
  - The facts the texts state, from Anthropic's vision page as quoted on #612 (read 2026-11-12):
    an image past 8000 px on a side is refused; once a request holds more than 20 images a
    stricter per-image limit applies, which 3000 px a side stays under on every platform (the
    page's own advice), and a long conversation reaches that count, since the assistant's helper
    resends its history, frames included, until it compacts; the newest models (Claude 4.7 and
    later) downscale an image past 2576 px on its long edge; an image's base64 may be at most 10
    MB on the Anthropic API and 5 MB on Amazon Bedrock. PR-22's and PR-23's "the Anthropic
    API's limit" is corrected to that: 5,242,880 stays the bound because it is the smaller. The
    texts state these as the API's, not as anything Frame Job does, and they can move with the
    API.
  - `max_width` sets the width and the height follows the aspect (`Exporter.scaledSize`), so on a
    tall canvas (`set_canvas` takes up to 16384 a side) an image can pass a side limit at a
    width under it, and `max_width: 8192` on a wide canvas is itself past 8000; the texts say the
    caller sizes by width and the height follows, never that `max_width` alone keeps an image
    under 8000 px.
  - Where it is said: `render_frame`'s description (its own sentences, apart from PR-23's
    scale-down sentence, so a change to that sentence leaves them whole), `max_width`'s
    description, the assistant's prompt (past 2576 px scaled down before it sees it, past 3000
    px refusable once the conversation holds more than 20 images, the height following the
    width), the site's `render_frame` page (an Image limits section, linked from `max_width`'s)
    and its paragraph on the rendering tools page. The scale-down sentence, `full_depth_image`'s
    description and the site's 5 MB sentences (the `render_frame` page's three, the rendering
    tools page's one and Save Frame's) drop "the Anthropic API's" only; `FrameBlock.scaleNote`
    is unchanged.
  - The check: `raster_dither_proof.py` BKd reads `tools/list`: `render_frame`'s description
    names 8000 px, 3000 px, more than 20 images, 2576 px, 10 MB and Amazon Bedrock and says
    "max_width is the caller's control"; `max_width`'s names 8000 px, 3000 px and 2576 px and
    says the height follows, its schema still 16…8192; none of the three says "Anthropic API's 5
    MB". Seen first (Debug at d0df3607): the description missing all seven phrases, `max_width`'s
    all four, "Anthropic API's 5 MB" in the description and `full_depth_image`'s, the bounds
    (16, 8192), so BKd FAILED. With it (Debug; the Release run in `tools/proof/README.md`): none
    missing, the attribution in none, the bounds (16, 8192), and BK5 and Z1 passing beside it.
  - No op, recipe, FFI, format, schema or behaviour change; `RC_FORMAT_VERSION` is unchanged.
  - Amends PR-22 and PR-23 (whose limit it is, and the sides deliberately not bounded).
  - Amended by PR-25: PR-23's scale by size is taken out, so "PR-23's scale by size stands as it
    is" and "the 5 MB bound stays" no longer hold; the sentences it wrote apart from the
    scale-down sentence now stand alone.

- **PR-25 — `render_frame`'s image block is never scaled: PR-23's scale to fit is taken out, and
  the block is the frame at the caller's size (owner, 2026-11-13, #618: "Take it out").**
  - The owner's words, on #612: "If the tool description describes the situation, leave it
    alone. Scaling images automatically may not be what the caller actually wants. MCP callers
    need to be smart enough to handle these situations." Asked whether #610's automatic downscale
    (PR-23, their earlier choice (b)) should then stay or go: "Take it out".
  - The rule: the image block is PR-22's again, at the file's size, which is `max_width`'s or the
    canvas's: the file's bytes for an 8-bit PNG and a JPEG, the 8-bit PNG copy of a deeper PNG and
    of any HEIC, and with `full_depth_image: true` the file's bytes and type. Frame Job bounds
    neither the block's bytes nor its sides: no scale, no cap, no refusal and no new argument take
    PR-23's place. A block whose base64 is past 5 MB, or past 10 MB, is sent as it is.
  - Removed (`FrameBlock`): the size test, the scale and its loop, the scaled draw, the sentence
    "The image here is scaled down to <w>×<h> px to fit the API's 5 MB image limit; the file is
    not scaled." and the 5,242,880 constant. Kept: the copy and its sentence (PR-22),
    `full_depth_image`, the file, its path, Save Frame…, and "Written to <path>." last, so a call
    whose block PR-23 scaled answers PR-22's text again.
  - One account in every text — `render_frame`'s description, `max_width`'s and
    `full_depth_image`'s descriptions, the site's `render_frame` pages and Save Frame's paragraph
    on the tool, and the assistant's prompt: the limits are the API's (PR-24's: 5 MB of base64 an
    image on Amazon Bedrock and 10 MB on the Anthropic API; refused past 8000 px a side; a stricter
    limit past 20 images in a request, which 3000 px a side stays under; downscaled past 2576 px on
    the long edge by the newest models); Frame Job doesn't scale or cap the image to meet them, on
    its bytes or its sides; `max_width` is the caller's control. The prompt says the image is sent
    at the size asked for and Frame Job never scales it, so the assistant passes `max_width`.
  - What shows the in-app assistant stays under the limits, and where it does not:
    - Its helper posts to the Anthropic API (`ClientFactory`'s default base URL,
      `https://api.anthropic.com`; `RC_ASSISTANT_BASE_URL` is the only override, and nothing in
      the app or the helper names Bedrock) and forwards the block as given (`ToolResults.swift`),
      so its limit on one image is 10 MB of base64, 10,485,760 bytes.
    - The prompt asks it to pass `max_width` to keep the image small, says Frame Job never
      scales it, and says never to pass `full_depth_image`. `assistant_prompt_probe.swift`'s F9
      holds the prompt's `render_frame` paragraph to `max_width` and "never scales", and to
      `max_width` being an argument `render_frame` publishes; M7 drops the clause and F9 fails.
    - Unscaled default blocks measured, one image each, no `max_width`: generated 1080p footage
      under a graphic 2,985,988 (BK1, PR-22); the owner's 1080p footage 2,326,800 to 3,210,716
      (PR-22's DGs); generated 3840×2160 footage (`testsrc2` with noise, `blk2160`) under a
      graphic and alone, BKk's and BKp's below. All are under 10,485,760.
    - Not covered, and said so: no real 3840×2160 camera frame was measured (the iPhone clip's
      1080p block is 3,210,716, and a 4K frame has four times the pixels, so its block could fall
      either side of 10 MB); a noise-like 3840×2160 frame asked with no `max_width` (BKj, a
      JPEG) is past 10 MB, and the API refuses it; and every figure is one image, while the
      helper resends a conversation's earlier frames until it compacts (PR-24), so several large
      frames add up in one request. In each case what keeps the assistant under is the prompt's
      `max_width` alone, by the owner's choice that the caller sizes its own image.
  - The check: `raster_dither_proof.py` BKk, BKp and BKj, PR-23's 3840×2160 rows, now hold the
    block NOT scaled: the file 3840×2160 with its base64 over 5,242,880 (the premise); the block
    exactly 3840×2160 with its base64 over 5,242,880 (BKj's over 10,485,760 too), BKp's and BKj's
    the file's bytes, BKk's the 8-bit copy of the frame (64×36 gap ≤ 2 levels); no "scaled down"
    in the text, the copy sentence (BKk) or none (BKp, BKj) directly before "Written to <path>.".
    BKd adds that the description says "on its bytes or its sides", that `max_width`'s names
    5 MB and 10 MB, and that none of the three descriptions says "scaled down" or "never scaled".
  - Seen first (Debug at e7e525e8, the spec and the proof edited, the app untouched): BKk's
    block 3038×1709 (base64 4,469,860), BKp's 2984×1679 (4,456,620), BKj's 2243×1262
    (3,242,680), each with the scale sentence, so all three failed; BKd failed on the missing
    phrases and the scale words; the prompt probe's F9 failed on HEAD's prompt ("never scales"
    not in its `render_frame` paragraph); BK1, BK2, BK3 and Z1 passed.
  - With it (Debug; the Release run in `tools/proof/README.md`): BKk's block an 8-bit PNG of
    3840×2160, base64 6,782,656, the frame (64×36 gap 0.269), with the copy sentence; BKp's the
    8-bit file's bytes, 7,031,532; BKj's the JPEG file's bytes, 12,441,372, past 10,485,760 too;
    no scale sentence in any; BKd passing; BK1 (2,985,988), BK2 (the file, 6,406,520) and
    BK3–BK6 as before; the prompt probe 16/16.
  - Mutants (Debug tree copies, each caught): `block-scaled-to-fit` (a default block past
    5,242,880 drawn at half its sides: BKk, BKp and BKj fail on the block alone, BK1–BK3 pass),
    `scale-sentence-said` (the answer saying such a block is scaled down: BKk, BKp and BKj fail on
    the sentence alone, BK1 and BK3 pass), `description-says-scaled` (BKd fails, BK5 passes), and
    the prompt probe's M7. PR-22's `block-is-the-file`, `full-depth-ignored` and
    `hlg-block-not-copied` run again, since the function their anchors are in was renamed, each
    caught; PR-23's seven went with the code.
  - No op, recipe, FFI, format, schema or catalog argument change; `RC_FORMAT_VERSION` is
    unchanged.
  - Supersedes PR-23. Amends PR-22 (its "Not done: bounding an 8-bit block by size" and "Same
    size as the file, so `max_width` bounds both" hold again for every block) and PR-24 (above).
  - Amended by SA-14 (#619): the assistant's helper forwards an image at or under 10,485,760
    bytes of base64 as given, and answers one past it to the model as an error text naming its
    size and `max_width`, so it never enters the conversation's history; the tool is unchanged
    and still scales nothing.
