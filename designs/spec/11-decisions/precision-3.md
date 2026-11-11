# Spec §11 — decisions: Precision, dither and deep graphics onward (#375, #488, #374)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the PR- series of [`precision.md`](precision.md), so a citation never has to say
which file. This file holds PR-13 on (PR-13…PR-15 when it was made), and a new PR- decision is
appended here. It is new because `precision.md` had passed the spec's ~500-line split rule (#548,
2026-11-11); the entries moved here unchanged, and an "above" or "below" in one may now point into a
sibling file.

- **PR-13 — A graphic's gradients are dithered where tiny-skia rounds them to 8 bits (owner,
  2026-10-27, #375: "Both, raster first").**
  - What: every gradient paint tiny-skia draws — linear and radial, the two-stop fast path
    (`EvenlySpaced2StopGradient`) and the general many-stop stage (`Gradient`) — gets a fixed
    offset by pixel position before it is rounded to 8 bits. resvg 0.48.1 builds only
    `LinearGradient` and `RadialGradient` shaders (`resvg/src/path.rs`). Solid fills, images,
    text and alpha are not dithered.
  - How: tiny-skia 0.12.0 is vendored in `graphic/vendor/tiny-skia/` with a four-file patch
    (`graphic/vendor/tiny-skia-dither.diff`, provenance and the re-apply steps in
    `graphic/vendor/README.md`), linked through a `[patch.crates-io]` table in both
    `graphic/Cargo.toml` and `core/Cargo.toml` (Cargo ignores a dependency's `[patch]`, and the
    staticlib the app links is built from `core/`). Nothing else in the crate is edited, and
    `graphic/src/` is unchanged (G-7's BGRA8 copy stands).
  - Where: a new last stage, `Stage::Dither`, pushed once in `Gradient::push_stages` after the
    gradient's own stages (its `Premultiply` and `push_stages_post`), so before blend and store.
    That is Skia's own place for it, one line, and resvg draws in tiny-skia's default `Linear`
    colour space, so no gamma stage follows it.
  - Highp: lowp has no `Dither` (its entry is `null_fn`), so any pipeline holding the stage is
    compiled highp (`RasterPipelineBuilder::compile`'s `is_lowp_compatible`). The cost is below.
  - The pattern: for each pixel, `h = lowbias32(lowbias32(y ^ 0x9E3779B9) ^ x)` (wrapping
    multiplies `0x7feb352d`, `0x846ca68b`; shifts 16, 15, 16), and `d = ((h >> 8) / 2^24 − 0.5)
    × 7/8 / 255`: uniform over ±7/16 of a level. One `d` is added to R, G and B, each clamped
    to [0, a]; alpha is untouched. The span is 7/8 of a level, under one, so a premultiplied
    value on a level stays exact: a colour on a level never moves.
  - Static: the stage reads only the pixel's position — no frame, time, thread or global state
    — so the same module, frame and props draw the same pixels, on any thread (the
    `GraphicPrefetch` workers draw the bytes the serial path does).
  - The seed is salted (`0x9E3779B9`) where #375 part 2's compositor dither keeps its own
    unsalted hash (PR-14), so the two quantizers' noise is independent.
  - Limits:
    - The pattern is anchored to the pixmap drawn into. A gradient inside a group with opacity,
      a mask, a clip or a filter layer, or a `<pattern>` tile, is dithered in that layer; the
      layer's composite is an image draw and is not dithered again.
    - A gradient used in a luminance mask dithers the coverage it makes.
    - The premultiplied colour is what is dithered: a translucent one-colour gradient whose
      premultiplied channels fall between levels takes the two levels beside them, where a
      solid fill of that colour takes one.
    - A shape clip's gradients are CoreGraphics', not this.
  - Re-recorded: `graphic/tests/pins.json`'s `title-card` (the only fixture with a gradient).
    Checked unchanged: the other five fixtures' pins, `core/tests/graphic_ffi.rs`'s
    `lower-third` pin, `graphics_proof.py` (solid rects only) and `graphics_prefetch_proof.py`,
    whose comparison is within a run.
  - No op, FFI, catalog, schema, format or MCP mirror change; always on, with no setting.
  - Measured on the control (`raster_dither_proof.py capture`, Debug, 2026-10-27, the unchanged
    product, its B4a/B4b files from a copy built without the `[patch]` tables): row 540 of
    #374's gradient (`band374`, x 0–800) took 44 green levels, median run 19 px, widest 19, in
    `render_graphic` and `render_frame` alike; rows 500–580's 16-px block max |mean(G − e)| was
    0.0755. `graphic/tests/dither.rs` on the control: the bracket, column-mean and alpha oracles
    failed (column-mean RMS 0.2887, round(e)'s own); the level, channel and solid oracles
    passed. `section_gradient_raster_cost` (`band374` at 1920×1080, 30 draws, three runs):
    median 9.41, 9.51, 9.40 ms.
  - Measured after the change (Debug, 2026-10-27, `raster_dither_proof.py --control`, 9/9): row
    540 took 43 levels, median run 2, widest 19, every G within a level of `e` (0 outside the
    bracket), block max |mean(G − e)| 0.0300, in `render_graphic` and `render_frame` alike; a
    `prores_422` export (B4a, 16-bit decode) banding RMS 0.0943 against the control's 0.3249,
    the per-pixel noise it kept 0.3306 against 0.0291, 9,195,715 bytes against 4,515,695; a
    `hevc_10bit` export of the moving fixture (B4b) 0.1185 against 0.1729; flat colours and the
    one-colour gradient byte-equal to the control (F1, F2: (51, 102, 153, 255)).
    `dither.rs` 6/6 (column-mean RMS 0.0435); the bench 8.73, 8.92, 8.91 ms (forcing highp cost
    nothing measurable here). The nine mutants (`raster_dither_proof.py --mutant`) are caught.
  - **Limit: an 8-bit lossy export strips the dither** (owner, 2026-10-27: "I don't really care
    about low-bitrate exports. I only care about higher quality exports."). Measured
    (a throwaway variant run, control build against dithered, one run each, banding RMS on a
    16-bit decode, dithered over control; its table is #375's comment 6454026110): `h264` at default quality 1.105
    static and 0.780 on a 5 s clip whose gradient moves; at `video_bitrate` 8 Mbit/s 1.130
    static, 0.825 moving; at 16 Mbit/s 0.971 static, 0.734 moving; `hevc` 0.892 static. Their
    row-540 runs stay 16–24 px median, 40–48 px widest. VideoToolbox does not spend the
    requested rate on smooth content: the 16 Mbit/s static file is 11,139 bytes for 1 s and the
    moving one 379,520 bytes for 5 s (about 0.6 Mbit/s), and the per-pixel noise it keeps
    (0.00–0.24) is too little or of the wrong kind to break the bands. `raster_dither_proof.py`
    prints three of these (L1–L3) unscored.
  - A wider span does not get through either: at ±1 and ±1.5 levels the moving `h264` ratio is
    0.802 and 0.762 at +61 % and +141 % file size, and at 16 Mbit/s 0.735 and 0.693 at +123 % and
    +288 %; `render_frame`'s visible noise rises from 0.376 to 0.629 and 0.896 levels RMS, and
    a colour on a level stops being exact (8,024 and 10,830 of a one-colour gradient's 16,384
    pixels move a level off its solid fill). So the span stays ±7/16.
  - The remedy for a gradient in a delivery file is a 10-bit export: `hevc_10bit` now (B4b; its
    control already bands at 0.17–0.19 against 0.38–0.47 for 8-bit codecs), and AV1 or VP9 at
    10 bits later (#377). A check with ffmpeg's libsvtav1 and libvpx-vp9 at 10 bits on the
    dithered ProRes measured 0.106 stair-step for both, against 0.094 for the source (one run
    each; commands and figures in #375's comment 6454026110). B4 is therefore scored on those exports: B4a
    `prores_422` (≤ ½ the control's) and B4b `hevc_10bit` (≤ 0.15 and under the control's).
  - Amends PR-5.
  - **Amended by PR-15** (#374): the dither is the 8-bit raster's; a raster drawn deep takes
    none, and a deep layer read at 8 bits inside the renderer takes this offset there.
  - The compositor's own output is NOT dithered (#375 part 2, dropped by the owner 2026-10-27):
    the 8-bit lossy codecs strip a ±7/16 dither as they strip the raster's, ProRes and the
    10-bit rows keep the float frame's levels, and what remained (8-bit PNG and JPEG stills,
    GIF, APNG) was judged not worth a new compositor pass. PR-3 and PR-4's rounding stand.
- **PR-14 — A frame the generator answers at 8 bits while it shows a deeper source is read deep,
  through export's reader (docs bugs b3, #488).**
  - `render_frame` and File ▸ Save Frame… as PNG or HEIC, of a frame whose recipe at the frame
    time names a track whose composition segment there reads a deep source, come out deep (a
    16-bit PNG, a 10-bit HEIC) even when `AVAssetImageGenerator` hands back an 8-bit image.
  - Measured on the frozen base app (`render_frame` as PNG, an SDR project, the 10-bit sources a
    luma ramp, levels the distinct greens in one row; stacks back to front). Alone: HEVC 10
    16-bit, 875 levels; ProRes 16-bit, 957. H.264 then HEVC 10: 8-bit, 256. H.264 then ProRes:
    8-bit, 256. HEVC 8 then HEVC 10: 8-bit, 256. Swapped, HEVC 10 or ProRes under H.264: 16-bit.
    H.264 on the bottom track at 0 s and HEVC 10 above it at 6 s, the frame at 7 s, only the
    10-bit clip showing: 8-bit, 256. An empty bottom track under HEVC 10: 16-bit, 875. So the
    generator's depth follows the lowest track that has video, and the levels show it is real
    loss and not only a label.
  - The mechanism: in `Exporter.renderFrameReported`, after `copyCGImage`, when `keepsDepth`, the
    image's `bitsPerComponent` is 8 or less and `DeepVideoFrame.showsDeepSource` answers yes,
    `DeepStillFrame.read` reads the frame; a nil read keeps the generator's image.
  - `isDeepSource` is PR-12's `isDeep` (a VP9 `vpcC`), or an `hvcC` atom of at least 18 bytes
    whose byte 17 low 3 bits (`bitDepthLumaMinus8`) are above 0, or a ProRes subtype (Proxy, LT,
    422, HQ, 4444, 4444 XQ). AV1 stays out, as in PR-12: not decodable on the host. A reversed
    clip counts through its 10-bit intermediate, as PR-7 says.
  - What keeps the generator byte for byte: a frame it already answers deep never reaches the
    test, so HEVC or ProRes alone is unchanged, and so is every frame showing no deep source: an
    8-bit HEVC clip, H.264 alone, and a deep clip elsewhere on the timeline. `isDeep` stays VP9
    only, so `DeepVideoFrame.reads` keeps PR-12's path, and JPEG, GIF, APNG, the eyedropper and
    look thumbnails do not keep depth and never ask.
  - No op, FFI, recipe, format or catalog change. No `depth` argument.
  - Amends PR-4, PR-9 and PR-12.
- **PR-15 — A graphic is drawn deeper than 8 bits where its frame is delivered deeper (#374;
  owner, 2026-11-10: "begin all").**
  - The rule: a graphic clip's raster is 16 bits a channel, with no dither, exactly when the
    frame it is drawn into leaves Frame Job deeper than 8 bits:
    - a movie export whose video row keeps more than 8 bits: `hevc_10bit`, `prores_422`,
      `prores_4444`, `av1`, `av1_webm`, and `vp9_webm` as HLG or HDR10 (`Exporter.graphicsDeep`,
      read from `ExportWriter.frameForm` and the bundled encoders' depth, nothing else);
    - a `render_frame` or File ▸ Save Frame… as PNG or HEIC (`keepsDepth`) whose frame comes
      out deep: PR-9's still, PR-12's VP9 track, a frame the generator answers deep, PR-14's
      re-read, and every such frame of an HLG project.
  - Everything else draws PR-13's dithered 8-bit raster, byte for byte: the preview with its
    prefetch and kept frames (G-36, G-37, G-38), `h264`, `hevc`, `hevc_alpha`, `vp9_alpha_webm`,
    SDR `vp9_webm`, an HLG project's SDR version on those rows, an 8-bit PNG, every JPEG, GIF
    and APNG (in an HLG project too), the eyedropper, look tiles, `render_graphic`, the Graphic
    pane's and the browser's thumbnails and the cursor arrow.
  - Why not deep everywhere: PR-13's last bullet. The compositor's 8-bit output is not
    dithered (#375 part 2, dropped by the owner 2026-10-27), so a deep raster rounded to 8 bits
    by the compositor would band where PR-13's dither does not: PR-13 measured row 540 at
    median run 2 px dithered against 19 px undithered. It also keeps playback's raster time and
    memory as they are, and moves no 8-bit proof baseline. It is one switch:
    `GraphicRegistry.resolve` answers `deep` false for a document's own key.
  - A frame showing only graphics is still an 8-bit PNG (PR-4 and PR-9 stand): a graphic is not
    a deep source. Held for the owner, below.
  - The patch: a second diff on the vendored tiny-skia, `graphic/vendor/tiny-skia-deep.diff`,
    applied after PR-13's (which stays byte-identical); every hunk marked `// Frame Job (spec
    §11 PR-15):`.
    - A deep `Pixmap` keeps its RGBA8 `data` and gains a residual plane of the same size. A
      channel's value in 1/256 levels is `data × 256 + (residual as i8)`, 65,280 being 1.
      `data` alone is the value rounded to 8 bits, which keeps resvg's 8-bit readers correct;
      resvg is not vendored.
    - The door is `tiny_skia::with_deep_pixmaps(f)`: inside it, on the calling thread only,
      `Pixmap::new` makes the plane, so the root and every layer resvg makes under it (an
      isolated group, a mask, a clip, a pattern tile, an image) are deep. A thread-local flag
      restored by a drop guard, on a panic too. The prefetch workers and `CursorSprites` draw
      8-bit rasters beside it on other threads.
    - The highp pipeline loads, stores, source-overs and samples both planes; a deep
      destination forces highp (lowp has no deep form); `load_mask_u8` is given a body, because
      a deep `apply_mask` runs highp where upstream only ever ran lowp; a solid memset and
      `fill` zero the residual; a gradient pushes no `Stage::Dither` for a deep destination and
      pushes it as before for an 8-bit one.
    - `Pixmap::copy_rgba16` writes the output: premultiplied RGBA, 65,535 as 1,
      `(v × 257 + 128) >> 8`, exact for a value on an 8-bit level. A row with no residual
      widens `data` alone.
  - Where the renderer reads a deep layer at 8 bits, it rounds with PR-13's offset
    (`pixmap::collapse`: the same hash, seed and ±7/16 span, R, G and B clamped to [0, alpha],
    alpha untouched, a value on a level never moved). That is:
    - `Pixmap::data_mut` and `pixels_mut` (resvg's filters and image decoders), after which an
      owned pixmap is 8-bit;
    - a `Pixmap`'s `clone` and `clone_rect`, which only resvg's filters call (a filter reads
      its source through a clone, under any `color-interpolation-filters`);
    - a luminance `Mask::from_pixmap`, whose coverage is the one today's dithered raster makes.
    So a filtered group and a luminance mask come out on 8-bit levels, dithered as today, and
    everything outside them is deep. `collapse` cannot tell a gradient from anything else, so
    the offset goes to every pixel holding a residual: inside a filtered group of a deep raster
    a flat translucent colour whose premultiplied value sits between two levels (`#336699` at
    `fill-opacity` 0.8 is 40.8) and a soft edge come out as a fine mix of the two neighbouring
    levels whose mean is the exact value within a tenth of a level (measured 40.85), where the
    8-bit raster draws the nearer level flat. A flat
    opaque colour is on a level and never moves (`graphic/tests/deep.rs`,
    `a_flat_colour_in_a_filter_takes_the_offset`). resvg's filters are not patched: that means vendoring
    resvg (4,600 lines, eleven filter files), and no bundled template uses a filter. A filter
    under the default `linearRGB` interpolation already takes a dark gradient through an 8-bit
    sRGB-to-linear table (sRGB 21 to 79 is linear 2 to 20), so `band374` inside one has about
    20 levels at any depth, today and after this.
  - The crate: `graphic::rasterize_deep` (`src/deep.rs`), `rasterize`'s checks and warnings
    with `stride` counted in 16-bit values; `raster.rs`'s `draw` is the parse and render both
    share. `rasterize` keeps its signature, texts and bytes.
  - The FFI: `rc_graphic_rasterize_deep(lib, svg, w, h, uint16_t *out_rgba16, stride,
    diag_out)`, `rc_graphic_rasterize`'s contract in native-endian 16-bit values;
    `GraphicLibrary.rasterize(…, deep:)`; a deep `GraphicRaster` holds `rgba16` and an empty
    `bgra`, and `byteCount` is what every budget counts.
  - The app: the texture is `.rgba16Unorm` under a key ending `:16`, so the two depths never
    serve each other; no shader, uniform, recipe or pipeline change (a deep still is already
    `rgba16Float` through the same layer stage, and the HLG lift and the matte pass sample what
    they are handed). `GraphicRegistry.pin(_:for:deep:)` and `markDeep` carry the depth on the
    offline key; a single frame is marked before the reader reads it, and a frame the
    generator answers deep with a graphic on it is read once more through
    `DeepStillFrame.read` with its graphics deep.
  - G-36, G-37 and G-38 are unchanged: the preview's keys are never deep. An export's prefetch
    counts a deep raster's real bytes (8 a pixel), so G-37's budget holds half the frames for a
    deep export and bounds itself; CX-18's encoder ledger is separate and unchanged.
  - PR-5's other members stay 8-bit: text, shapes, word captions and 8-bit stills are drawn by
    Core Text and Core Graphics in Swift (`LayerRenderers.bitmap`), not by this crate. Whether a
    shape's Core Graphics gradient bands in a 10-bit export was not measured (filed).
  - Limits:
    - The preview and a deep export differ in a graphic's low bits: dithered 8-bit against
      deep. A colour on a level is the same in both.
    - A filtered group, and a luminance mask's coverage, are 8-bit (above), and in a deep
      raster a filtered group's translucent flats and soft edges take the offset as its
      gradients do: at most one level from the 8-bit raster, no bundled template uses a filter.
    - A `hevc_10bit` file at the default rate gains little: the encoder bands a smooth
      gradient itself (measured below). ProRes and a still keep the levels.
  - No op, catalog, schema, recipe or format change; `RC_FORMAT_VERSION` is unchanged. One new
    export, `rc_graphic_rasterize_deep`.
  - Measured in the crate (`graphic/tests/deep.rs`, `band374` at 1920×1080, row 540, x 0–800,
    green): 801 distinct 16-bit values of 801 pixels, the worst 0.93 of 65,535 from the exact
    value; 801 through a group at opacity 0.6, a pattern tile, a translucent solid over it, a
    clip path and a flat mask (the masked value within 1.29); a filtered group and an arithmetic
    composite under sRGB interpolation on 8-bit levels at median run 2 px, a luminance mask at
    1 px; every bundled template within 2.24 levels of its 8-bit raster, no channel over its
    alpha, the same warnings; a fade under half a level keeps 102 distinct alphas below 128.
  - Raster time (`graphic/tests/deep_bench.rs`, one thread, medians of alternating rounds, on a
    12-core host under two other lanes' builds, load average 60 to 90, so the ratios are
    steadier than the milliseconds; two runs): the 23 templates at two frames each, summed,
    1.73× and 1.75× at 1920×1080 (123 ms against 213 and 216) and 2.24× and 2.74× at
    3840×2160; an empty frame 0.32 ms against 0.70 at 1080p, so the fixed cost is 0.38 ms a
    frame where the spike's was 0.72; a full-canvas translucent solid, the worst scene, 3× to
    5×. Memory is exactly twice: 16,588,800 bytes a 1080p raster against 8,294,400. Only a
    deep export or a deep still pays either.
  - Measured in the app (Release, 2026-11-10, `raster_dither_proof.py --base`, 8/8, the base a
    capture of the app at d7d791c1; Debug gave the same figures): the 8-bit sheets and frames decode equal to the base's (E1);
    `render_frame` beside a 16-bit still, beside a 10-bit HEVC clip, and beside one over an
    H.264 clip, each a 16-bit PNG with 781 distinct greens of 801, the worst 0.0606 of a level
    from `e`, where the base's held 44 (D1, D5, D7); an HLG project's frame 737 distinct
    against 56 (D6); a `prores_422` export's per-pixel noise 0.0165 against the base's 0.3306,
    its error from `e` less its mean 0.1115 against 0.3460, its banding RMS 0.0974 against
    0.0943 (that figure cannot tell the base's dither from 10-bit steps; an undithered 8-bit
    raster measured 0.3249, PR-13), and its file 2,123,379 bytes against 9,195,715 (D3); a
    `hevc_10bit` export of the moving fixture banding 0.1213 against 0.1185 and noise 0.0741
    against 0.1059 (D4).
  - Mutants: fifteen, over the rule of ten, because the change adds decisions in two places
    that share no instrument: seven in the vendored crate (the dither on a deep store, layers
    made 8-bit, lowp on a deep destination, the mask load, the collapse without its offset, the
    door left open, a residual dropped at the copy), five in the app (never deep, always deep,
    Main 10 not deep, a generator's deep frame not read again, PR-14's re-read not marked) and
    three in the probe (the byte count, the frame-form test, one budget site). PR-13's
    `core-unpatched` is now caught by the build: without core's `[patch]` table the staticlib
    does not compile, naming `with_deep_pixmaps`.
  - Held for the owner (neither blocks this): (1) whether a frame that shows only a graphic
    should be saved as a 16-bit PNG, counting a graphic as a deep source (recommended, as its
    own batch: about thirty proofs read graphic frames with an 8-bit decoder); (2) whether the
    preview and the 8-bit outputs should draw from the deep raster, which needs the
    compositor's output dither dropped on 2026-10-27 (recommended: leave it).
  - Amends PR-5 and PR-13.

- **PR-16 — A shape's gradient is drawn at 16-bit float where its frame is delivered deeper
  than 8 bits (#563).**
  - The question PR-15 left ("whether a shape's Core Graphics gradient bands in a 10-bit export
    was not measured") is settled here, and the answer is not "it bands". Core Graphics dithers
    a gradient it draws into an 8-bit bitmap, so the ramp has no staircase; what a deep file
    gets is that dithered 8-bit ramp, which is the state a graphic was in between PR-13 and
    PR-15.
  - Measured on the app before this decision (Debug at 692e3f5a, Darwin 25.5, 2026-11-11,
    `raster_dither_proof.py capture`; fixture `shape563`, a 1920×1080 rectangle with
    a linear 0° gradient `#0D1512` → `#2A4F3D`, green, row 540, x 0–800, where the exact ramp
    `e` spans 24 levels):
    - an 8-bit `render_frame`: 26 levels, median run 2 px, widest 17, not monotonic, 76 of rows
      500–580 differing from row 540, RMS of G − e 0.4066 of a level, the worst 0.9922, the
      worst 16-px block bias 0.0273. Dithered, about twice PR-13's ±7/16 span, and unbiased;
    - `render_frame` beside a 16-bit still, beside a 10-bit HEVC clip and beside one over an
      H.264 clip: a 16-bit PNG holding 26 distinct greens of 801, the worst 0.9602 of a level
      from `e`; an HLG project's frame 35 distinct;
    - a `prores_422` export: per-pixel noise kept 0.3786, error from `e` less its mean 0.3887,
      banding RMS 0.0812, 8,603,875 bytes; a `hevc_10bit` export: 25 levels at median run 32 px,
      noise 0.0437, banding RMS 0.1081 (the encoder strips the dither and bands, PR-15's limit).
  - The verdict rule, fixed before the app was measured: cure when the 8-bit ramp's
    `prores_422` file keeps at least the noise and the error PR-15's base measured for a
    graphic's dithered raster (0.3306 and 0.3460), record the figures only when it keeps less.
    0.3786 and 0.3887 are both above, so the cure is built. The owner's standing lean is to keep
    precision; the cure is the one #563 names.
  - The rule: a shape clip's texture is 16-bit float (`rgba16Float`, drawn in sRGB into
    `LayerRenderers.halfFloatBitmap`) exactly when BOTH hold:
    - the description draws a gradient: kind `rectangle` or `ellipse`, `gradient` set with at
      least two stops (`ShapeProps.drawsGradient`);
    - its frame is delivered deeper than 8 bits, PR-15's two cases word for word: a movie export
      row for which `Exporter.graphicsDeep` is true, and a `render_frame` or File ▸ Save Frame…
      as PNG or HEIC whose frame comes out deep (PR-9's still, PR-12's VP9 track, a frame the
      generator answers deep, PR-14's re-read, and every such frame of an HLG project).
  - Everything else is today's 8-bit bitmap, byte for byte: every flat shape, line and arrow in
    any frame; every shape in the preview, `h264`, `hevc`, `hevc_alpha`, `vp9_alpha_webm`, SDR
    `vp9_webm`, an HLG project's SDR version on those rows, an 8-bit PNG, every JPEG, GIF and
    APNG, the eyedropper and look tiles; text and word captions everywhere (text has no gradient
    fill).
  - Why not deep everywhere: PR-15's reason. The compositor's 8-bit output is not dithered, so
    an exact ramp rounded to 8 bits there would band (median run about 33 px on this fixture)
    where Core Graphics' own dither does not.
  - A frame showing only shapes is still an 8-bit PNG: a gradient shape is not a deep source
    (PR-4). PR-15's held question (1) covers it and is not reopened.
  - How: the "delivered deep" fact is a set of keys on `RecipeSource` (`markDeep`,
    `deliversDeep`, cleared by `unregister`), because PR-15's flag lives on a graphic pin and a
    project with no graphic set has none. It is marked beside each of PR-15's marks and never on
    a document's own key: the export's key when `Exporter.graphicsDeep`; a frame the reader
    reads, when `keepsDepth`; a frame the generator answers deep that draws a gradient shape
    (`Exporter.drawsGradientShape`), which is then read once more through `DeepStillFrame.read`
    as a graphic's is; PR-14's re-read. `MetalRenderer.source(for:)` hands the answer to
    `LayerRenderers.shape(_:hash:deep:)`, which draws with the same Core Graphics calls into
    the half-float bitmap. `GraphicRegistry`'s flag is not moved.
  - The cache: deep shape textures sit in a pool of their own of `graphicCacheLimit` (6), for
    the graphics' reason: a gradient animated by an action mints a texture a frame at 8 bytes a
    pixel (66 MB at a full 4K canvas), and the shared pool's 64 would hold 4.2 GB of them. Two
    pools also keep the depths from serving each other under one key. No ledger counts layer
    textures (G-37 counts graphic rasters, CX-18 the encoders), and none is added.
  - Limits:
    - The preview and an 8-bit file show Core Graphics' dithered ramp and a deep file the exact
      one, so they differ by up to about one 8-bit level a pixel.
    - A deep gradient shape's stroke and antialiased edge are drawn in the same half-float
      bitmap, so they differ from the 8-bit draw in their low bits too; a one-colour gradient
      lands within half-float's step of its level.
    - A `hevc_10bit` file gains little: the encoder bands a static smooth ramp itself (G4).
    - More than six distinct deep gradient shapes on one frame are redrawn every frame: correct
      and slower.
  - Measured in the app with the cure (Release, 2026-11-11, `raster_dither_proof.py --base`,
    the base the capture above; Debug gave the same figures): `render_frame` beside a 16-bit
    still, beside a 10-bit HEVC clip and beside one over an H.264 clip, each a 16-bit PNG with
    785 distinct greens of 801, the worst 0.0296 of a level from `e`, where the base held 26
    (G1, G5, G7); an HLG project's frame 776 distinct against 35 (G6); a `prores_422` export's
    per-pixel noise 0.0000 against 0.3786, its error from `e` less its mean 0.1025 against
    0.3887, its banding RMS 0.0897 against 0.0812 (10-bit steps, which that figure cannot tell
    from the base's dither), and its file 1,578,575 bytes against 8,603,875 (G3); a
    `hevc_10bit` export banding 0.1054 against 0.1081 and noise 0.0358 against 0.0437 (G4, not
    scored); the 8-bit frame, the HLG project's JPEG and a deep frame of flat shapes decode
    equal to the base's (GEa, GEb, GEc), as do the graphics' 8-bit sheets and frames (E1).
    `precision_proof.py` P1 (a gradient shape at 50 % through `prores_422` against the 8-bit
    frame) read 0.902 ten-bit steps RMS against 0.914 before, bound 1.0.
  - Mutants: seven, one per decision added, each caught (`raster_dither_proof.py --app-mutant`):
    the read site never deep (G1, G3, G5, G6) and always deep (GEa), a flat shape drawn deep
    (GEc), the export's key not marked (G3), a generator's deep frame not read again for a
    gradient shape (G5), PR-14's re-read not marked (G7), and the reader's frame marked without
    `keepsDepth` (GEb). PR-15's `generator-frame-not-deep` was re-aimed at its moved line and
    run again (D5).
  - Measured since (#588, 2026-11-11):
    - The cost of the float texture, as a cache miss of `LayerRenderers.shape` (the Core
      Graphics draw plus the upload; the draw alone is private), `shape563`'s gradient,
      medians of fifteen alternating pairs in one process, three runs of
      `shape_draw_probe.py` on an Apple silicon Mac under other builds (load average 23 to
      24): at 1920×1080 the 8-bit texture 6.49, 6.56 and 6.58 ms and the float one 7.85, 7.62
      and 7.95 ms, a ratio of 1.21, 1.16 and 1.21; at 3840×2160 25.89, 26.10 and 26.51 ms
      against 31.07, 31.10 and 32.07 ms, a ratio of 1.20, 1.19 and 1.21. A measurement, not a
      bound: a gradient animated by an action pays it a frame in a deep export.
    - An 8-bit movie row: `shape563` exported `h264` decodes equal to the base's, byte for
      byte (GEd); with the export's mark stripped of its guard the same frame differs by up
      to 4 levels, 0.69 on average (the mutant `export-always-marked`).
    - A gradient shape on a matte track: PR-17.
  - No op, catalog, schema, recipe, FFI or format change; `RC_FORMAT_VERSION` is unchanged.
  - Amends PR-5 and PR-15. Amended by PR-17.

- **PR-17 — A gradient shape on a matte track keeps its 8-bit dithered draw in every frame
  (#588).**
  - What PR-16 did not see: a layer on a matte track (its recipe layer's `matte.into` names a
    group) is drawn through the same `source(for:)` into the matte's composite, and each cut
    set is then resolved into the `r8Unorm` coverage (MT-6), which PR-5 keeps 8-bit and
    which is not dithered. So since PR-16, in a frame delivered deep, a matte member's ramp
    was the exact float one rounded to 8 bits there: a staircase, where Core Graphics' own
    dithered ramp, rounded the same way, has none. PR-16's "Why not deep everywhere" names
    the same effect for the compositor's 8-bit output.
  - The rule, fixed before the app was measured: a `prores_422` export of a white full-canvas
    card under `shape563` on a `luma` matte track, canvas background black, so the picture's
    green is the coverage, whose exact value is the gradient's Rec. 709 luma (19.08 to 69.83
    levels across the canvas); banding RMS at most 0.15 (D3's and B4b's bound) and the
    row-540 50-px block means strictly increasing (`raster_dither_proof.py` GM).
  - Measured (Debug, 2026-11-11, row 540, x 0–800): on the tree as PR-16 left it, banding RMS
    0.2770, 22 levels at median run 38 px, per-pixel noise 0.0000, 1,943,855 bytes: GM fails.
    The app before PR-16 (Debug at 2be9bf9a): 0.0921, 23 levels at median run 1 px, noise
    0.4411, 8,918,275 bytes.
  - The decision: `MetalRenderer.source(for:)` asks for the deep shape texture only when the
    layer is not a matte member (`layer.matte?.into == nil`). A matte member's gradient shape
    is Core Graphics' 8-bit dithered bitmap in every frame, as it was before PR-16 and as it
    is in the preview and every 8-bit export. With it GM reads the base's figures exactly
    (0.0921, the same 8,918,275 bytes; Release, `raster_dither_proof.py --base`, 17/17 with
    PR-15's and PR-16's rows; Debug gave the same figures).
  - Unchanged: a gradient shape that is CUT by a matte, or that no matte touches, is deep
    where PR-16 says (G1, G3, G5, G6, G7). A shape inside a nest whose clip is on a matte
    track is a matte member too: the recipe flattens it with `into` set
    (`core/src/recipe_matte.rs`). The two pools keep the depths apart under one hash, so one
    shape description drawn both on a matte track and on the canvas gets a texture of each.
  - Not chosen: a 16-bit coverage in deep frames. It reopens PR-5's and MT-6's memory
    figures and changes what a 10-bit clip used as a `luma` matte gets; it is a candidate
    issue, not decided here.
  - Left open, and filed: a GRAPHIC on a matte track. PR-15's deep raster takes no dither
    either, and its depth is its key's pin, read by the prefetch ahead of the frame, so the
    fix is not this one condition. `band374` as the `luma` matte in the same project reads
    banding RMS 0.3398, 37 levels at median run 21 px (GMg, printed and not scored), on this
    tree and on the app before PR-16 alike.
  - Mutant: `matte-shape-deep` (the condition removed) fails GM at 0.2770. PR-16's
    `shape-never-deep` and `shape-always-deep`, whose anchor is the next line, were run again
    and caught (G1, G3, G5, G6; GEa).
  - No op, catalog, schema, recipe, FFI or format change; `RC_FORMAT_VERSION` is unchanged.
  - Amends PR-16.
