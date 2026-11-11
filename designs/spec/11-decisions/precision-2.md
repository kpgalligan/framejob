# Spec §11 — decisions: Precision, road map "precision-2" and the frames read deep (#257, #275, #289, #295, #294)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the PR- series of [`precision.md`](precision.md), so a citation never has to say
which file. This file holds PR-6…PR-12: PR-6…PR-8 are road map "precision-2"'s, whose condensed
record is `designs/adr/precision-2.md`. PR-13 on are in [`precision-3.md`](precision-3.md). It is
new because `precision.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the
entries moved here unchanged, and an "above" or "below" in one may now point into a sibling file.

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
  - Why not the generator: `AVAssetImageGenerator` hands back a 16-bit image only when the
    lowest track that has video is deep (corrected by PR-14; this read "every video track of
    the composition", from B97's first pass). A 10-bit carrier track
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
  **Amended by PR-14** (docs bugs b3, #488): the reader also re-reads a frame the generator answers
  at 8 bits while it shows a 10-bit HEVC or ProRes source.
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
  **Amended by PR-14** (docs bugs b3, #488): "HEVC, ProRes" under "keep the generator byte for
  byte" holds for a frame the generator answers deep, which is what L17 measured, each alone. A
  frame it answers at 8 bits while it shows one of them is re-read.
