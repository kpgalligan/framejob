# Spec §11 — decisions: Precision (issue batch B94, road map "precision")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/precision.md`, and
the original, `archive/precision.md`, holds each phase's record (PR0–PR3). PR-1..PR-5 were
recorded in PR0, before any code, from the owner's
seven answers of 2026-10-09 ("As recommended") to the scoping spike's choices
(`~/.claude/litecode/reelcut/precision/S-precision.md` §0). They change how many bits hold a
pixel, not what a pixel means: blending stays in encoded sRGB (§7.5, MT-3), and HDR, wide gamut
and linear light are deferred. They amend MT-6, MT-8, MT-9 and G-35 the way G-35 amended G-33,
and re-litigate nothing.

PR-6..PR-8 were recorded in P2-0 of road map "precision-2" (#257), before any of its code, from
the owner's "All as recommended" (2026-10-11) to the #257 brief's choices 1a, 2a, 3 (close), 4
(close) and 5 (`~/.claude/litecode/reelcut/i257-8bit-paths/I-257.md` §0; the answers in
`…/i257-8bit-paths/answers.md`). That road map is closed: its condensed record is
`designs/adr/precision-2.md`, and the original, `archive/precision-2.md`, holds each phase's
record (P2-0–P2-3). They take up PR-5's deferral of the 10-bit rest: PR-6 and PR-7 amend its
list, and PR-8 closes its other two items. PR-2 stands: HDR stays tone-mapped in the compositor
(amended by GR-15: HDR still reaches the output as SDR, converted by Frame Job's own step 0).

PR-9 was recorded in issue batch B97 (#275) from the owner's choice of 2026-10-13 ("Go with 1":
read the frame the way video export does), after its mechanism was measured and before the rest
of its code; it amends PR-4 and PR-6.

PR-10 was recorded in issue batch B98 (#289), before its code, from `log_proof.py` L13's
measurement of the unchanged product; it amends PR-7.

PR-11 was recorded in issue batch B102 (#295), before its code, from the owner's choice of
2026-10-14 ("BT.709 always"), after issue batch B101 measured what label a rendered frame
carried; it amends PR-4 and PR-9.

PR-12 was recorded in issue batch B103 (#294), before its product code, from the owner's choice
of 2026-10-14 ("fix it") and `log_proof.py`'s control on the unchanged product (L14, L16, L17);
it amends PR-4 and PR-9.

PR-13 was recorded for #375 part 1, before its code, from the owner's choice of 2026-10-27
("Both, raster first": dither the graphic raster's gradients now, the compositor's 8-bit output
next as #375 part 2, a deeper raster deferred to #374) and `raster_dither_proof.py`'s control on
the unchanged product; it amends PR-5.

- **PR-1 — The working depth is 16-bit float, holding encoded values clamped to [0, 1] (owner,
  2026-10-09, choices 1 and 5).**
  - The render context's buffers are `kCVPixelFormatType_64RGBAHalf`.
  - Every target a layer pipeline draws into is `rgba16Float`: the destination, each matte's
    composite, each routed dissolve half, and the shadow's canvas-sized pair (its silhouette
    pass draws with the layer pipelines, so it shares their attachment format). So is the
    attachment of every layer, blend, shadow and dissolve pipeline.
  - The matte coverage stays `r8Unorm`, and the 1×1 placeholder stays `bgra8Unorm`.
  - The layer stage `saturate`s its source sample. The blend and dissolve entry points
    `saturate` what they return; the plain stage already clamps.
  - Blending stays in encoded sRGB (§7.5; MT-3 stands).
  - The preview shows these same buffers, with no EDR and no HDR flag. A separate 8-bit preview
    output comes only if a problem shows, and only by a decision recorded then.
  - Spike figures (2026-10-09; M2 Max, macOS 26.5.1, `powermode 0`, AC power): at most
    +0.04 ms a frame at 1080p and +0.13 ms at 4K, against the 8 ms budget. One opaque layer
    comes out byte-identical. Blended scenes move by one level (rarely two) on up to 16 % of
    channels.
  - Amends MT-6 (a matte's composite is `rgba16Float`), MT-8 (a routed dissolve's halves are
    `rgba16Float`) and MT-9's figures (66.4 MB per composite at 3840×2160; the coverage's
    8.3 MB stands).
  - Risk accepted: frame memory doubles. At 4K that is about 265 → 531 MB for a typical project
    and 611 → 1,143 MB for a heavy one, with PR-2 (REASONED from measured buffer sizes; PR1 and
    PR2 measure the app's own figures). A project with a shadow holds another 67 MB at 4K.
  - Measured in PR1 (2026-10-09; Release, `precision_proof.py --measure`, each `prores_422`
    export's lifetime `phys_footprint_peak`, PR0 → PR1): typical 1080p 285.3 → 422.5 MB,
    typical 4K 618.0 → 1,236.1 MB, heavy 1080p 453.9 → 655.1 MB, heavy 4K 1,238.7 → 2,090.4 MB
    (+851.7 MB). The export pipeline holds about 19–26 frame buffers at its peak, where the
    reasoned figures assumed a handful, so the heavy 4K rise passed the road map's stop of
    +532 MB. **Accepted as measured by the owner (2026-10-09):** "We shouldn't worry about 8g
    macs at all, and give only minimal concern to 16g macs." The +532 MB stop no longer applies
    to this road map; each phase still measures and records the footprints.
- **PR-2 — Every video source decodes to `64RGBAHalf` (choice 2).**
  - `sourcePixelBufferAttributes` asks every track for `kCVPixelFormatType_64RGBAHalf`, wrapped
    as `rgba16Float`.
  - #216's import check (a one-frame decode to 32BGRA) stands, as a test that the file decodes.
  - HDR stays tone-mapped to SDR: `supportsHDRSourceFrames` stays false, and the spike's HLG and
    PQ ramps arrived within 0…1.0.
  - Measured by the spike:
    - Decode is 1.5–2.4× faster than 32BGRA on every source tried.
    - A 10-bit ramp keeps 816–877 levels, where 32BGRA keeps 256.
    - A frame decoded from video moves by about one level on 18–50 % of channels, and by
      ≥ 5 levels on ≤ 3.5 %, at sharp colour edges.
    - Values arrive unclamped (−0.46…1.47); PR-1's source clamp bounds them.
  **Amended by GR-15** (grading-3 T3-0): "HDR stays tone-mapped to SDR" is true of one path,
  not of every frame. Measured by the tier-3 brief (2026-10-11, a scratch instrument making the
  app's own AVFoundation calls; `archive/grading-3.md`, "How it fits the tree"), at a grey signal
  of 0.5: the export reader's later frames and the player arrive converted to SDR (HLG 0.3843,
  PQ 0.7192), but the FIRST frame a decoder delivers of each HLG or PQ clip, and every frame
  `AVAssetImageGenerator` draws (`render_frame`, Save Frame…, GIF, APNG, the Look gallery's
  thumbnails, the eyedropper, Pick from Canvas), arrive unconverted (0.5000) and labelled BT.709;
  a BT.2020 file with the BT.709 transfer arrives darkened on every path (0.2568). GR-15 sets
  `canConformColorOfSourceFrames` and `supportsHDRSourceFrames` true, so every source arrives
  native and honestly labelled, and Frame Job converts HDR to SDR itself at step 0 (from T3-1).
  The decision "HDR reaches the output as SDR" stands; only who converts changes.
- **PR-3 — Which exports carry the depth (choice 3).**
  - The export reader's frames are the compositor's `64RGBAHalf`. `prores_422` (10-bit 4:2:2)
    and `prores_4444` (12-bit 4:4:4:4) take them as they are.
  - A new row, `hevc_10bit` ("HEVC 10-bit (MP4)", codec `hevc_10bit`):
    - writes `AVVideoCodecType.hevc` with `kVTProfileLevel_HEVC_Main10_AutoLevel`;
    - sits after `hevc_alpha` and before `prores_422`, since G-33 keeps `hevc_alpha` directly
      after `hevc`;
    - is even-sized, carries no alpha, and takes HEVC's Quality tiers and default rate.
  - `hevc` is pinned to `kVTProfileLevel_HEVC_Main_AutoLevel`. Measured: given no profile key,
    VideoToolbox follows its input's format, and deep frames gave Main 10.
  - `h264` (High, 8-bit), `hevc_alpha`, `gif`, `apng` and JPEG frames stay 8-bit.
  - `h264`'s frame is first rounded to 8-bit BGRA (round(v·255)) into a pooled 32BGRA buffer,
    unstraightened and unlabelled, so its encoder input is what it was. Measured: H.264 fed
    half-float frames gave 8.80 steps RMS on the ramp, against 6.27 from 32BGRA.
  - `hevc`'s frame is rounded the same way (amended in PR1's fix pass). Measured on the app:
    `hevc` (Main) encoded the precision proof's 10-bit ramp at 9.04 steps RMS from half-float
    frames, against 6.46 from PR0's 32BGRA, each figure the same over three exports.
  - Amends G-35 (c):
    - `prores_4444`'s frame is un-premultiplied in place in float (s = min(1, c/a) for a > 0),
      then filled by G-35 (d)'s rule over its half-float pixels.
    - `hevc_alpha`'s frame is first rounded to 8-bit premultiplied BGRA (round(v·255), which is
      exact for every k/255) into a pooled 32BGRA buffer. It is then straightened by G-35 (c)
      and (d) unchanged, so that row's encoder input and its exactness are what they were.
    - A frame in neither format stops the export with G-35's sentence.
  - Spike figures, ramp error in 10-bit steps RMS: ProRes 422 0.49 from deep frames against
    3.27 from 8-bit; HEVC Main 10 1.13 against 2.18. H.264 and HEVC encode at the same speed;
    ProRes exports run about twice as fast end to end.
  - `hevc_alpha` fed deep frames is measured in PR1 and recorded in the road map, not used.
- **PR-4 — `render_frame`'s depth follows its sources (choice 4).**
  - `render_frame`, File ▸ Save Frame…, GIF and APNG frames write the CGImage
    `AVAssetImageGenerator` hands back: 8 bits a component when every source is 8-bit, 16-bit
    float when any source is deeper.
  - This writes down today's behaviour. The spike measured an all-8-bit composition through a
    half-float compositor as 6,220,800 of 6,220,800 bytes exact; the depth rows are
    `phase6_proof.py` §0 and `phase7_proof.py`.
  - No `depth` argument. JPEG stays 8-bit.
  - If PR2 makes an all-8-bit composition's image 16-bit, PR2 stops and this decision returns
    to the owner.
  **Amended by PR-6** (precision-2 P2-1; its stills-only case accepted by the owner
  2026-10-11): "any source is deeper" counts video sources only, as measured on Release in
  P2-1: a project whose only picture is a still drawn deep (PR-6) renders an 8-bit frame (S4),
  as does a 16-bit still covering an 8-bit H.264 clip (S5); a 16-bit still covering a 10-bit
  clip renders a 16-bit frame that keeps the still's depth (S6: 1,920 distinct green values on
  its middle row, 256 when the still is drawn 8-bit). Exports keep the depth (S1).
  **Amended by PR-7** (precision-2 P2-2; accepted by the owner 2026-10-11, "Accept 16-bit"): a
  reversed clip counts by its intermediate, which is 10-bit (HEVC Main 10, or ProRes 422 at an
  odd size), whatever its source's depth. So a project whose only video is a reversed 8-bit
  clip renders a 16-bit `render_frame`, Save Frame…, GIF and APNG frame; the picture's content
  is still the 8-bit source's. Measured on Release in P2-2 (V6): the 640×360 H.264 clip alone,
  reversed, renders a 16-bit PNG, its reverse `hevc`/Main 10/`yuv420p10le`; on the renderer
  before PR-7 the same project rendered 8-bit, its reverse `h264`/High/`yuv420p`.
  **Amended by PR-9** (B97, the owner 2026-10-13): a frame whose recipe draws a still deeper
  than 8 bits a component is read through export's reader instead of the generator, so it is
  deep in `render_frame` and Save Frame…: a 16-bit PNG, a 10-bit HEIC (S10); S4 and S5 above now
  read 16-bit. GIF, APNG and JPEG stay 8-bit, and every other frame is still the generator's.
  PR-7's "GIF and APNG frame" above holds for the frame only: ImageIO writes a multi-frame GIF
  or APNG FILE at 8 bits a component whatever the frames' depth (measured in B97), so PR-7's
  depth reaches `render_frame` and Save Frame… alone.
  **Amended by PR-11** (B102, the owner 2026-10-14): every such frame's FILE carries the one
  BT.709 label, `FrameWriter.frameSpace`, whatever its sources (`render_frame`, Save Frame… as
  PNG, JPEG and HEIC, APNG frames); a GIF carries no colour label and is left as it is. The
  depth and the pixels are unchanged.
  **Amended by PR-12** (B103, the owner 2026-10-14): a frame whose recipe shows a VP9 track of
  more than 8 bits is read through export's reader too, so it is deep in `render_frame` and
  Save Frame… (PNG, HEIC), however many other video tracks the composition holds. The
  generator's 8-bit image of such a file (B102's `composition-gap`) no longer reaches a frame.
  **Amended by HD-2** (hdr H-0): an HLG project's `render_frame` and Save Frame… frames are 16-bit
  (PNG) or 10-bit (HEIC) whatever their sources; JPEG, GIF and APNG carry the 8-bit SDR version
  (HD-5).
- **PR-5 — What stays 8-bit, and the frozen references (choice 6).**
  - These stay 8-bit:
    - graphics (G-7's BGRA8);
    - text, shapes and word captions (W-16 and W-17 stand);
    - still images;
    - thumbnails and poster frames;
    - the reversed-clip intermediate;
    - screen recordings;
    - the `r8` coverage.
  - Each is an 8-bit source or side output on a deeper canvas, and a lone 8-bit layer
    composites byte-identical (spike S1).
  - Deferred, each filed as an issue at the close: HDR/EDR, wide gamut, linear light, and
    10-bit `hevc_alpha`, reverse intermediate, still images and recording.
  - A proof row that compares against a frozen pre-change reference, and so cannot be
    re-recorded:
    - where it holds the reference's pixels (`e1_proof.py`'s 77934fe build), it compares
      decoded pixels within ±1 a channel;
    - where it holds only a digest (`hevc_alpha_baseline.json`'s B1/G1), it prints the digest
      unscored beside the reference's and names this decision.
  **Amended by PR-6 and PR-7** (precision-2 P2-0): a still deeper than 8 bits a component is
  drawn at 16-bit float (PR-6), and the reversed-clip intermediate is 10-bit (PR-7); the list is
  not edited, and PR-8 closes its 10-bit `hevc_alpha` and 10-bit recording as not wanted.
  **Amended by PR-13** (#375 part 1): graphics stay 8-bit, and a graphic's gradients are dithered
  where tiny-skia rounds them to 8 bits; the list is not edited.
- **PR-6 — A still deeper than 8 bits a component is drawn at 16-bit float (owner, 2026-10-11,
  choice 1a).**
  - `LayerRenderers.renderImage` checks `image.bitsPerComponent > 8`. When it is, the image is
    drawn into a 16-bit-float premultiplied RGBA sRGB context and uploaded `rgba16Float`. An
    8-bit still takes today's path byte for byte.
  - The decode is unchanged (`MediaCacheFiles.decodeImage`, 16 bpc kept, measured). There is no
    shader, uniform, recipe or format change. Thumbnails and posters stay 8-bit (PR-5).
  - Measured (the #257 brief §8; M2 Max, macOS 26.5.1, `powermode 0`, AC power): 1,024 levels
    from the deep draw against 256; a deep 4K texture is 66.4 MB against 33.2 MB; decode+draw
    87.5 against 87.3 ms (1080p PNG).
  - `render_frame` keeps PR-4's mechanism: its PNG is the CGImage `AVAssetImageGenerator` hands
    back. Whether a deep still makes that image 16-bit is NOT ESTABLISHED until P2-1's S4: a
    stills-only project has only `CompositionBuilder.addPlaceholderIfNeeded`'s empty track (brief
    §2, §9). The deep claim is proven through `prores_422` (S1).
  - If S4 reads an 8-bit PNG, P2-1 stops and the point returns to the owner as an amendment of
    PR-4's "any source is deeper". P2-1 does not append a bullet that contradicts PR-4.
  - Amends PR-5's "still images".
  - Measured in P2-1 (S4, 2026-10-11, Release): `render_frame` of a project whose only picture
    is a 16-bit still is an 8-bit PNG, as is an 8-bit still's; the `prores_422` export keeps the
    depth (S1: 862 distinct 10-bit codes on the ramp's middle row, against 512 from the old
    draw). The owner accepted it on 2026-10-11 ("Accept it"), and PR-4 is amended to match.
  **Amended by PR-9** (B97, the owner 2026-10-13): `render_frame` of a frame showing a deep
  still no longer takes PR-4's mechanism: it is read through export's reader, 16-bit; the
  still's draw is unchanged.
- **PR-7 — The reversed intermediate is 10-bit, carries the source's colour labels, and keeps
  the source's exact size (owner, 2026-10-11, choice 2a; the odd-size fix with it).**
  - An even-sized source is written as HEVC with `kVTProfileLevel_HEVC_Main10_AutoLevel` at every
    size (no H.264), from `x420` frames, at HEVC's rate (0.12 bits/pixel/frame, 2–240 Mbps).
  - An odd width or height is written as ProRes 422 from `x422` frames. HEVC 4:2:0 cannot hold
    an odd size: measured, 1919×1079 → 1918×1078 on both today's renderer and the Main 10
    variant. The brief's transcode probe wrote ProRes 422 from `x422` at 1919×1079: ffprobe of
    `/Users/kevingalligan/devel/reelcut/tools/proof/work/i257/out/odd_pr422x422.mov` reads
    `prores,Standard,1919,1079,yuv422p10le`, against `hevc,Main 10,1918,1078` for
    `odd_m10x420.mov`.
  - No `AVVideoColorPropertiesKey`. The held copy is per plane and propagates the buffer's
    attachments, so the frames' own labels reach the file (measured: HLG kept
    `arib-std-b67/bt2020/bt2020nc`, mean |Δ| 0.0; today's file says `bt709` ×3).
  - The slice budget counts the held format's bytes per pixel.
  - The digest's input gains a renderer version. §5.6's `<media id>-<digest>.mov` pattern is
    unchanged, and `prune` removes the old sibling, so an old 8-bit reverse is never reused.
  - Measured cost of the even-sized HEVC Main 10 path only: same wall time at 1080p and 4K, file
    the same size or smaller, peak RSS lower; depth 872 levels / 0.466 steps against
    219 / 2.226.
  - Measured cost of the odd-size ProRes 422 branch (brief §8, codec cost alone): 66.8 Mbps
    against today's 12.0 at 1080p (0.23 s against 1.16 s for 300 frames), 226.3 against 29.0 at
    4K (0.56 s against 1.65 s for 150 frames), so roughly 5–8× today's file. On the flat
    1919×1079 ramp fixture the file is 2,727,219 bytes against 10,812 for today's
    (`odd_pr422x422.mov` against `odd_today.mov`). The decision accepts this cost for exact
    size.
  - Why the branch is rare (REASONED, not measured): a Retina capture is 2× its point size, so
    its pixel sizes are even. Odd sizes come from 1× displays and from cropped or odd-sized
    imported sources.
  - If P2-2 measures the real renderer's odd-size path at any size but the source's, P2-2 stops
    and this decision returns to the owner.
  - Measured in P2-2 (2026-10-11, the real renderer through `reverse_probe.swift`; MCP rows on
    Release): the 10-bit ramp reverses to HEVC Main 10 `yuv420p10le` holding 860 distinct
    10-bit Y codes at 0.592 codes RMS (V0; the old renderer: H.264, 216 at 2.545). Exported
    `prores_422` the reversed clip reads 0.643 steps RMS against the forward clip's 0.707 (V1;
    old 3.077). An HLG BT.2020 source's reverse keeps `arib-std-b67/bt2020/bt2020nc`, its
    codes within 0.108 of the source's (V2; old `bt709` ×3); an HLG chroma ramp renders within
    0.078 8-bit levels of its forward twin (V3; old 0.764, its 8-bit rounding). A reverse under
    the pre-version name is re-rendered and pruned (V4). The 1919×1079 ramp reverses to ProRes
    422 `yuv422p10le` at exactly 1919×1079 (V5; old H.264 1918×1078), so the odd-size stop did
    not fire.
  - Measured in P2-2, the cost (`precision_proof.py reverse-cost`: the probe built `-O`, three
    reverses each, medians; AC power; load 7.7–8.7 for the old renderer, 25.9–28.7 for the
    new, so wall times compare loosely): 2 s ProRes 1080p 0.453 → 0.474 s, 2,344,933 →
    1,764,385 bytes (9.38 → 7.06 Mbps), peak RSS 587 → 454 MB; 2 s ProRes 2160p 0.925 → 0.916
    s, 7,124,361 → 7,025,662 bytes (28.5 → 28.1 Mbps), 788 → 708 MB; 2 s `testsrc2` at
    1919×1079 0.461 → 0.384 s, 2,959,786 → 17,698,683 bytes (11.84 → 70.79 Mbps, 6.0×), 589 →
    574 MB; the 1 s ramp 0.313 → 0.317 s, 34,223 → 13,195 bytes, 333 → 263 MB.
  - Measured in P2-2, and accepted by the owner (2026-10-11, "Accept 16-bit"): an 8-bit
    source's reverse is Main 10 too, so a project whose only video is a reversed 8-bit clip
    renders 16-bit frames (V6: a 16-bit PNG, the reverse `hevc`/Main 10/`yuv420p10le`); PR-4
    is amended to match.
  - PR-2 stands: HDR stays tone-mapped in the compositor (amended by GR-15: HDR still reaches
    the output as SDR, converted by Frame Job's own step 0); the reverse only stops mislabelling.
  - Amends PR-5's "the reversed-clip intermediate".
  - **Amended by PR-10** (B98, #289): an odd-size reverse of a media flagged full range reads
    `422YpCbCr10BiPlanarFullRange` frames, not `x422`.
  - **Accepted limit** (owner, 2026-10-14, #280): the HEVC Main 10 intermediate moves a log
    clip's toe up 3 codes (S-Log3 95 → 98, Apple Log 196 → 199; about 7 levels after the curve),
    every other sample within 2. Measured in B96 (5b14a35, `log_proof.py reverse-variants`): the
    rate is the cause, not 4:2:0. 2× rate leaves 1–3 codes at 2× the file, 4× rate 1–2 at 4×
    (867 MB/min at 2160p30), 4:2:2 HEVC no better at 1×; ProRes 422 HQ costs 32×. Nothing held
    ±1 within 2× the size, so the rate stays; `log_proof.py` L6 holds the reversed render to the
    intermediate's own codes.
- **PR-8 — 10-bit `hevc_alpha` and 10-bit screen recording are not wanted (owner, 2026-10-11,
  choices 3a and 4a).**
  - `hevc_alpha`: Main 10 with alpha works (877 colour levels), but the alpha plane stays 8-bit
    at every profile (256 levels, measured). Its content is mostly PR-5's 8-bit graphics, and
    `prores_4444` is the deep alpha master. Players' Main 10 alpha support is unchecked.
  - Recording: `SCRecordingOutputConfiguration` has no profile, depth or rate key (only
    `avc1`/`hvc1` and MP4/MOV, measured). The only documented 10-bit route is the HDR10 PQ preset
    (`captureHDRRecordingPreservedSDRHDR10`: `x420`, ITU-R 2100 PQ), which PR-2 would tone-map. A
    self-written encoder would rebuild the recorder's segment machinery.
  - PR-5's list is not edited; this closes those two of its deferrals.
- **PR-9 — A frame showing a deep still is read deep, through export's reader (owner,
  2026-10-13, #275; APNG left out by the owner 2026-10-14).**
  - `render_frame` and File ▸ Save Frame… (PNG, HEIC) of a frame whose recipe draws a still
    deeper than 8 bits a component come out deep: a 16-bit PNG, a 10-bit HEIC (the reader's
    image is 16-bit; ImageIO's HEIC writer keeps 10, S10). GIF, APNG and JPEG stay 8-bit, and every
    frame with no deep still — so every all-8-bit project — keeps the generator's path byte for
    byte (PR-4's guarantee).
  - The mechanism: `DeepStillFrame.shows` asks the RECIPE at the frame time (a still elsewhere
    on the timeline, or one Show Selection leaves out, does not count; one the recipe draws
    counts whatever its opacity, crop or cover) whether an `image` layer's file is deep
    (`kCGImagePropertyDepth` of its first image above 8, the header twin of PR-6's
    `bitsPerComponent > 8`). When it is and the format keeps depth, `Exporter.renderFrame` reads
    the frame with `DeepStillFrame.read` instead of `AVAssetImageGenerator`: an
    `AVAssetReaderVideoCompositionOutput` at `Compositor.outputPixelFormat` (`64RGBAHalf`, export's
    own two settings) over one frame's range starting at the frame time, its first sample copied
    into a 16-bit-float CGImage, and the reading cancelled on the thread that read it (G-17).
    With `max_width` below the canvas it is redrawn at the generator's size into a 16-bit-float
    context.
  - Why not the generator: `AVAssetImageGenerator` hands back a 16-bit image only when every
    video track of the composition is deep, measured in B97's first pass. A 10-bit carrier track
    beside an 8-bit one, or beside the stills-only placeholder, left the image 8-bit; only a
    composition whose sole video track was the carrier read 16-bit. A deep still over 8-bit
    video (S5) cannot reach that, so the carrier was dropped for the reader.
  - APNG stays 8-bit, as GIF does: ImageIO's PNG destination writes a file of more than one
    frame at 8 bits a component whatever it is handed (measured in B97 on macOS 26.5.1: float16
    and int16 RGBA frames give a 16-bit one-frame PNG and an 8-bit `rgba` or `rgb24` APNG, with
    or without the APNG properties; the product's APNG of `ramp16.png` read through the reader
    was `rgba`, 256 greens). Frame Job writing its own 16-bit APNG encoder was not wanted
    (owner, 2026-10-14: "APNG is quite niche. I don't care about it."), so an image-sequence
    export never asks.
  - The colour space: `sRGB IEC61966-2.1`, the generator's tag, when the composition converts
    nothing (no output primaries); a converting composition (GR-15) keeps its buffer's own RGB
    space from the buffer's attachments, BT.709 when there is none. **Amended by PR-11** (B102):
    the reader's image is built in `FrameWriter.frameSpace`, the BT.709 label every rendered
    frame's file carries, in both cases; its pixels are the buffer's, as before.
  - What stays: JPEG frames, GIF and APNG exports (8-bit, as before); the preview, movie
    exports, the eyedropper, Pick from Canvas, the look gallery, `snapshot_ui`, thumbnails and
    posters, which never ask. There is no `depth` argument.
  **Amended by PR-12** (B103, the owner 2026-10-14): the reader also reads a frame whose recipe
  shows a deep VP9 track (`DeepVideoFrame`), and the question is asked in `Exporter` after the
  composition is built: callers pass `keepsDepth` (`carriesDepth`), no longer `deepStill`.
  Everything else here stands.
  - Measured in B97 (Release, 2026-10-14, `precision_proof.py` against the control
    `ctl-b97`, captured on the tree before any PR-9 code): S4, `ramp16.png` alone, a 16-bit PNG
    with 1,920 distinct middle-row greens (256 before), its RGB scaled to 8 bits equal to the
    control's render (max |Δ| 0), profile `sRGB IEC61966-2.1` as the generator's; S5, over the
    8-bit H.264 clip, the same (1,920, max |Δ| 0); S14, the clip under a half-scale still, the
    uncovered columns within ±1 (mean 0.491) of the still-less render at the frame time and off
    the 30 fps grid; S15, over an HLG clip (converting), the generator's `HDTV` profile and max
    |Δ| 0; S16, `max_width 960`, a 960×540 16-bit PNG; D1 and S8 8-bit, and every all-8-bit
    render, GIF, JPEG and APNG byte-identical to the control (K1–K6, S3, S11).
- **PR-10 — An odd-size reverse of full-range media reads full-range frames (issue batch B98,
  #289).**
  - An odd-size reverse (PR-7's ProRes 422 branch) of a media whose forward video track is
    flagged full range — GR-22's flag, `kCMFormatDescriptionExtension_FullRangeVideo`, read by
    `CompositionBuilder.isFullRange` — asks the reader for, holds and hands the writer
    `kCVPixelFormatType_422YpCbCr10BiPlanarFullRange` frames
    (`ReverseRenderer.Intermediate.pixelFormat(fullRange:)`). Every other reverse reads as PR-7
    says: an even size `x420`, an odd video-range size `x422`. The HEVC branch's read is not
    changed (its intermediate is #280's open choice).
  - The renderer version is 3 (`ReverseCache.rendererVersion`), so every reverse already in a
    package is rendered again under a new name and the old sibling pruned (PR-7's digest rule).
  - No op, FFI, recipe, format or catalog change.
  - Why: measured by `log_proof.py` L13 on the unchanged product (Debug, 2026-10-14). The S-Log3
    ramp and patches stored as 1023·y at 1024×129, no Camera Log, forward and reversed at 0.5 s.
    A full-range file's odd-size reverse read `x422` came back shifted: `slog3_fr_odd` (HEVC Rext
    4:2:2, flagged `pc`) and `slog3_fr_vp9` (VP9 Profile 2 4:2:0, `pc`) each wrote a ProRes 422
    `yuv422p10le` 1024×129 intermediate whose Y was up to 90 codes from the file's code in the
    intermediate's range (column 0: 95 → 159 against 145), and whose reversed render was 27 and
    28 8-bit levels from the forward one. Their video-range twins (`slog3_vr_odd`,
    `slog3_vr_vp9`) held: worst 1 code, 95 → 95, renders within 1 level. B96's
    `reverse-variants` had seen the same 90 codes on every `x422` read of a full-range 4:2:0
    file (#289).
  - Measured after the change (Debug, 2026-10-14, `log_proof.py --only L10,L12,L13,Z1`):
    `slog3_fr_odd`'s intermediate is ProRes 422 `yuv422p10le` 1024×129 flagged video range, its
    toe worst 1 code (column 0: 95 → 146), its reversed render within 1 level of the forward
    one; its twin unchanged (worst 1, spread 1); L10 and L12 unchanged (worst 1 on each file;
    L12's 0 % patch [5, 5, 5]).
  - Not reached, and left open: a VP9 MP4's track carries no `FullRangeVideo` extension (its
    range is in `vpcC` alone, measured), so GR-22's flag reads `slog3_fr_vp9` as video range and
    its reverse is still read video-range `x422` (toe 90, spread 28, as before). Reading that
    flag from `vpcC` is GR-22's reader, not this decision's; `log_proof.py`'s `L13_OPEN` held
    the pair (#291) — closed by GR-23 (issue batch B99, #291).
  - Amends PR-7.
- **PR-11 — Every rendered frame's file is labelled BT.709 (owner, 2026-10-14, #295: "BT.709
  always").**
  - Every frame Frame Job writes as an image file carries one colour label,
    `FrameWriter.frameSpace`, whatever its sources: `render_frame` and File ▸ Save Frame… as
    PNG, JPEG and HEIC (deep or not), and every frame of an APNG export. `frameSpace` is the
    space `CVImageBufferCreateColorSpaceFromAttachments` makes of the BT.709 primaries, transfer
    function and matrix, which is the space the generator already gives a frame of a
    BT.709-tagged source: an `iCCP` named `kCGColorSpaceCoreMedia709` in a PNG or APNG, `sips`'s
    profile `HDTV` in a JPEG or HEIC. If that call answers nil, `frameSpace` is
    `CGColorSpace.itur_709`.
  - GIF: a GIF export carries no colour label. ImageIO writes no `ICCRGBG1` extension and reads
    every GIF as sRGB, whatever space its frames were in (measured on the tree before PR-11,
    `frame_label_proof.py` E3). So a GIF's frames are left as they are
    (`ImageSequenceFormat.carriesLabel` is false for `.gif`).
  - Pixels are unchanged. The label is applied by `CGImage.copy(colorSpace:)` at the write
    (`FrameWriter.writeFrame` for `render_frame` and Save Frame…, `FrameWriter.labelled` for an
    APNG's frames before `sized`), never inside `Exporter.renderFrame`. So the eyedropper, Pick
    from Canvas, the scopes, `snapshot_ui` and thumbnails still read a frame in its own space
    (GR-15's H1 stop). `sized` and JPEG's flatten draw in the image's own space, which is then
    the label, so neither converts. `DeepStillFrame.read` builds its image in `frameSpace`.
  - `FrameWriter.write` stays unlabelled for `snapshot_ui`, `render_graphic`'s sheets and the
    look gallery's tiles. A PNG's properties dictionary stays nil: the label comes only from the
    image's colour space.
  - Why: BT.709 is the composition's working space (GR-15 builds a converting composition's
    colour as BT.709) and every movie export's tag (issue batch B101's `frame_label_proof.py`
    E1: an `h264` export of an untagged source and of a BT.709 one are both bt709 ×3). Before
    PR-11 the label followed the sources even when they were hidden: #295's two frames have
    identical pixels (F5/F6 raw |Δ| 0) but read up to 10.98 levels apart once matched to sRGB.
  - No op, FFI, recipe, format or catalog change. No depth changes (PR-4, PR-9).
  - Measured (issue batch B102, Debug, `frame_label_proof.py compare` against the control
    `label-ctl`, captured on the tree before any PR-11 code): the default `frameSpace` holds, so
    `itur_709` was not needed. Every PNG and APNG (F1–F10, E2) carries `iCCP`
    `kCGColorSpaceCoreMedia709`, as B101's F2 control did, and every JPEG and HEIC (F11: F1's,
    F2's and F9's frames) carries `HDTV`, at B101's depths (F9's 16-bit PNG, its 10-bit HEIC).
    Every one of the 20 files decodes raw to the control's pixels (P1, max |Δ| 0, F9's deep
    frames included). The 10 whose control already carried their PR-11 label, both GIFs among
    them, are byte-identical (P2). #295's pair now carries one label: F5/F6 matched |Δ| 0 (0.623 / 10.984
    before). On the control, F0, F1, F3, F5, F6, F8, F9, F11 and E2 failed and E3 passed (a GIF
    has no `ICCRGBG1` extension). Labelling a GIF's frames anyway (`gif-flipped`) moves its
    pixels (F1's GIF by up to 98.63 levels, mean 0.807): ImageIO converts a non-sRGB frame into
    its palette's sRGB, so "left as they are" keeps a GIF's pixels. The frozen byte references
    moved on labels alone: `log_proof.py` L9 (3 of 5 PNGs), `hdr_proof.py` H1 (14 of 24) and
    `precision_proof.py` S11 (the JPEG and `ramp8.png`'s APNG), each decoded raw equal to its
    control (`frame_label_proof.py same-pixels`, max |Δ| 0).
  - Amends PR-4 and PR-9.
  **Amended by HD-2** (hdr H-0): an HLG project's frames are labelled BT.2100 HLG (a PNG's `cICP`
  9/18/0/1), not `frameSpace`; the SDR version's frames (JPEG, APNG) and every SDR project keep
  `frameSpace`.
- **PR-12 — A frame showing a deep VP9 track is read deep, through export's reader (owner,
  2026-10-14, #294: "fix it").**
  - `render_frame` and File ▸ Save Frame… as PNG or HEIC, of a frame whose recipe at the frame
    time names a track whose composition segment there reads a VP9 file of more than 8 bits (the
    `vpcC` record's bitDepth), go through `DeepStillFrame.read`, PR-9's reader: a 16-bit PNG, a
    10-bit HEIC, labelled by PR-11.
  - JPEG stays 8-bit. GIF and APNG never ask.
  - These keep the generator byte for byte: an 8-bit VP9 file, HEVC, ProRes, a VP9 clip
    elsewhere on the timeline, and a reversed VP9 clip (its composition reads PR-7's 10-bit
    intermediate, not the VP9 file; held by construction, not measured).
  - Why VP9 alone: the control's depths (`log_proof.py` L17, Debug, 2026-10-14, the unchanged
    product): `render_frame` of the 10-bit VP9 files alone (`slog3_fr_vp9e.mp4`,
    `slog3_vr_vp9e.mp4`, the rewrapped `slog3_fr_webm.webm`) wrote 8-bit PNGs, as did the mixed
    project (8-bit VP9 at 0, `slog3_fr_vp9e.mp4` at 1 s) at 1.5 s, while HEVC Main 10
    (`slog3_fr.mov`), HEVC Rext (`slog3_fr_422.mov`) and ProRes 422 HQ (`slog3.mov`) alone wrote
    16-bit PNGs, and 8-bit VP9 an 8-bit one. No other codec the generator reads 8-bit was found.
    AV1 does not decode on the host these measurements ran on (an M2 Max, macOS 26.5.1;
    `DecoderSupport`, B101), so no AV1 depth was measured and AV1 is not in the rule.
  - Why `vpcC`: every VP9 MP4 writes the record, and so does the built-in rewrap
    (`container_codec.rs`'s `vpcc()`) for a WebM, as GR-23 reads its range bit from the same
    record (version 1, bitDepth the high nibble of byte 6). A record shorter than 7 bytes or of
    another version is not deep.
  - The mechanism: `render_frame` and Save Frame… pass their format's `carriesDepth` as
    `keepsDepth`, and `Exporter.renderFrameReported` asks `DeepVideoFrame.reads` after the
    composition is built: PR-9's still (`DeepStillFrame.shows`), else this track test. Every
    other caller passes nothing and keeps the generator.
  - No op, FFI, recipe, format or catalog change. No `depth` argument.
  - Measured on the control (`log_proof.py capture`, `log-ctl`): L14 at ±1 failed (worst 2 on
    `slog3_fr_vp9e` and `slog3_fr_webm`, 8 samples each off by 2, e.g. 158 against 160 at
    column 400; 1 on `slog3_vr_vp9e`), and L16's probe did not build.
  - Measured after the change (Debug, 2026-10-14, `log_proof.py compare log-ctl --only
    L9,L14,L16,L17,L18,Z1`, 6/6): L14 worst 1 on each VP9 file; L16's eight answers as wanted,
    the 10-bit files' `vpcC` byte 6 `a3` or `a2` (bitDepth 10) and `vp9_8bit`'s `82` (8), the
    HEVC and ProRes files without a `vpcC`; L17 a 16-bit PNG for each VP9 file alone and for the
    mixed project at 1.5 s; L18 byte-identical to the control (`slog3_fr.mov` and `vp9_8bit.mp4`
    alone and the mixed project at 0.5 s, 16-, 8- and 8-bit PNGs; `slog3_fr_vp9e.mp4` as JPEG);
    L9 byte-identical. PR-9's rows hold (`precision_proof.py --only D1,S8,S10,S14,S15,S16,Z1`,
    7/7). A JPEG asked to keep depth (`vp9-jpeg-deep`) writes the same bytes (5,099), so JPEG's
    `carriesDepth` false is equivalent there, as PR-9's `jpeg-deep` was.
  - Amends PR-4 and PR-9.
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
