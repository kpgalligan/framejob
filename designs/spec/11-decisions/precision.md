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
    - where it holds the reference's pixels (`e1_proof.py`'s 1c3e92e build), it compares
      decoded pixels within ±1 a channel;
    - where it holds only a digest (`hevc_alpha_baseline.json`'s B1/G1), it prints the digest
      unscored beside the reference's and names this decision.
  **Amended by PR-6 and PR-7** (precision-2 P2-0): a still deeper than 8 bits a component is
  drawn at 16-bit float (PR-6), and the reversed-clip intermediate is 10-bit (PR-7); the list is
  not edited, and PR-8 closes its 10-bit `hevc_alpha` and 10-bit recording as not wanted.
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
    space from the buffer's attachments, BT.709 when there is none.
  - What stays: JPEG frames, GIF and APNG exports (8-bit, as before); the preview, movie
    exports, the eyedropper, Pick from Canvas, the look gallery, `snapshot_ui`, thumbnails and
    posters, which never ask. There is no `depth` argument.
  - Measured in B97 (Release, 2026-10-14, `precision_proof.py` against the control
    `ctl-b97`, captured on the tree before any PR-9 code): S4, `ramp16.png` alone, a 16-bit PNG
    with 1,920 distinct middle-row greens (256 before), its RGB scaled to 8 bits equal to the
    control's render (max |Δ| 0), profile `sRGB IEC61966-2.1` as the generator's; S5, over the
    8-bit H.264 clip, the same (1,920, max |Δ| 0); S14, the clip under a half-scale still, the
    uncovered columns within ±1 (mean 0.491) of the still-less render at the frame time and off
    the 30 fps grid; S15, over an HLG clip (converting), the generator's `HDTV` profile and max
    |Δ| 0; S16, `max_width 960`, a 960×540 16-bit PNG; D1 and S8 8-bit, and every all-8-bit
    render, GIF, JPEG and APNG byte-identical to the control (K1–K6, S3, S11).
