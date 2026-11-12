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

PR-6 on are in [`precision-2.md`](precision-2.md) (PR-6…PR-12) and
[`precision-3.md`](precision-3.md) (PR-13 on), moved there unchanged on 2026-11-11 because this file
had passed the spec's ~500-line split rule (#548).

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

PR-14 was recorded in docs bugs b3 (#488), before its code, from the frozen base app's measurement
of twelve track layouts; it amends PR-4, PR-9 and PR-12.

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
  - Amended by PR-19 (#597): the coverage is `r16Unorm` in a frame delivered deeper than 8 bits;
    every other frame keeps it `r8Unorm`.
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
  **Amended by PR-14** (docs bugs b3, #488): "any source is deeper" was not what the generator did.
  A 10-bit HEVC or ProRes clip above an 8-bit clip came back 8-bit; such a frame is now re-read
  through export's reader, so it is deep in `render_frame` and Save Frame… (PNG, HEIC).
  **Amended by PR-20** (#566): a frame whose recipe draws a graphic is read through export's
  reader too, so it is deep in `render_frame` and Save Frame… (PNG, HEIC), beside anything.
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
  **Amended by PR-15** (#374): a graphic is drawn at 16 bits a channel where its frame is
  delivered deeper than 8 bits (a deep export row, a deep `render_frame` or Save Frame…); every
  other frame keeps the 8-bit raster, and text, shapes, word captions and 8-bit stills stay
  8-bit; the list is not edited.
  **Amended by PR-16** (#563): a shape's gradient is drawn at 16-bit float where its frame is
  delivered deeper than 8 bits, as a graphic is; flat shapes, text and word captions stay 8-bit.
  **Amended by PR-19** (#597): the `r8` coverage is `r16Unorm` in a frame delivered deeper than
  8 bits, and 8-bit in every other; the list is not edited.
