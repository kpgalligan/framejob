# Spec §11 — decisions: Codec export, VP9 in WebM onward (road map "codec-export", #377)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the CX- series of [`codec-export.md`](codec-export.md), so a citation never has to
say which file. This file holds CX-16…CX-18. It is new because `codec-export.md` had passed the
spec's ~500-line split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or
"below" in one may now point into a sibling file.

- **CX-16 — C4: `vp9_webm`, 8-bit Profile 0 for SDR and 10-bit Profile 2 for HLG and PQ**
  (default, recorded in C4 before its code; amends CX-8, CX-15 (1)–(3), HD-5 and HD-14 (c)):
  1. **The row.** `vp9_webm` is "VP9 (WebM)", directly after `av1_webm`: container `webm`,
     codec `vp9`, video, no alpha (alpha is C5's row), `size` and `fps` null, `avf_preset`
     `AVAssetExportPresetPassthrough` (a record, as on `av1_webm`), `"hdr": true` and `writer`
     `libvpx`, with no `encoder_speeds`. It is even-sized, one of HD-5's HDR rows, and
     `optimize_for_network` has no effect on it. Its settings carry `writer` (`libvpx`) and
     no `encoder_speed`; `color` in an HLG project as every HDR row's.
     **Amended by CX-17** (C5): the alpha row is `vp9_alpha_webm`, directly after this one,
     an 8-bit SDR row and not an HDR row.
  2. **One speed (CX-3 binds).** libvpx runs `VPX_DL_GOOD_QUALITY` at cpu-used 4 with row-mt.
     There is no `encoder_speeds`, `encoder_speed` on the row is refused with the existing
     sentence (`vp9_webm has no encoder speed; encoder_speed applies to av1 and av1_webm`), and
     the sheet's Speed popup is drawn disabled on it, as on every row without speeds. The
     brief's "Speed popup mapped to cpu-used" is not built: it would re-litigate CX-3.
  3. **The depth is the picture's.** `sdr` (an SDR project, or `sdr` asked in an HLG project)
     is Profile 0 (`g_profile` 0): 8-bit I420, BT.709. `hlg` and `pq` are Profile 2: 10-bit
     I010, BT.2020 non-constant, with `g_profile` 2, `VPX_CODEC_USE_HIGHBITDEPTH`,
     `g_bit_depth` and `g_input_bit_depth` 10 and `VPX_IMG_FMT_I42016` (libvpx's
     `validate_config` refuses a depth above 8 at a profile below 2). WHY: Profile 0 is VP9's
     universal decode profile, VP9's reason to be on the sheet is web playback (CX-3), and
     unlike AV1's Main profile (CX-14 (1)) Profile 0 cannot carry 10 bits, so an always-10-bit
     row would be a Profile 2 file for every SDR export. The 8-bit samples are CX-14 (3)'s
     arithmetic at 8 bits: Y = round(16 + 219·Y′) and each chroma sample
     clamp(round(128 + 224·C′), 0, 255), C′ the mean of its 2 × 2 block, the matrix BT.709's.
  4. **The tags.** libvpx's `VP9E_SET_COLOR_SPACE` is `VPX_CS_BT_709` or `VPX_CS_BT_2020` and
     `VP9E_SET_COLOR_RANGE` studio. VP9's bitstream carries no transfer function, so the WebM
     `Colour` is the only transfer label (CX-8): the picture's CICP (`sdr` 1/1/1, `hlg` 9/18/9,
     `pq` 9/16/9), Range 1 and BitsPerChannel 8 or 10; on PQ alone it also carries HD-5's
     MasteringMetadata, MaxCLL and MaxFALL from `OutputTransform`'s two blobs, as CX-15 (3)
     writes them for `av1_webm`.
  5. **No CodecPrivate.** Matroska's VP9 mapping makes it optional, ffmpeg writes none, and
     #216-R's reader builds `vpcC` from the first keyframe, so the TrackEntry is `V_VP9` with
     none. The layout's `codec_private_hex` becomes optional: required and non-empty on `V_AV1`,
     refused on `V_VP9`; `bits_per_channel` is checked to be 8 or 10.
  6. **Keys and packets.** `kf_mode` auto, `kf_min_dist` 0 and `kf_max_dist` ⌊2·fps⌋ (a
     keyframe at least every 2 s, as CX-12 (3)); the block's key flag is libvpx's
     `VPX_FRAME_IS_KEY`. `g_lag_in_frames` 25, auto-alt-ref 1, `VP9E_SET_TILE_COLUMNS` 2,
     frame-parallel decoding 0, `g_threads` the active processor count; timebase 1/fps, a
     frame's pts its index, duration 1. libvpx packs a hidden alt-ref into the next shown
     frame's superframe, so each packet is one shown frame at its pts. A libvpx failure reads
     "libvpx failed: <step> answered <code>: <detail>", and one before the first frame "libvpx
     could not start: …".
  7. **The rate: capped constant quality, quality first** (CX-13's model). `rc_end_usage` is
     `VPX_CQ`, `VP8E_SET_CQ_LEVEL` the table's value and `rc_target_bitrate` the cap in kb/s
     (rounded, at least 1), the cap CX-13 (2)'s: `video_bitrate` when asked (the Quality tiers'
     0.6 factor, CX-9 (2)), else HEVC's 0.07 bits per pixel per frame. `rc_overshoot_pct` and
     `rc_undershoot_pct` stay at libvpx's defaults (25 / 25), as CX-13 took SVT's own. The CQ
     level is a function of the cap's bits per pixel per frame and the depth: linear between
     CX-13's five points, rounded down, the end point's beyond either end. The 8-bit column is
     the lower of two calibrations: (a) the spike's gh5, promo and real8 through the spike's
     `vpxenc` (`--end-usage=cq`, the flags above, CQ 10–50 in steps of 2) against `crf.jsonl`'s
     HEVC rows, and (b) the owner's IMG_0018.MOV in an SDR project through a Release copy
     reading the CQ from a file, against `hevc`, both scored against `prores_422` as yuv420p.
     The 10-bit column is the owner clip in an HLG project at `hlg`, against `hevc_10bit` at
     `hlg`, scored as yuv420p10le. Each cell is the highest CQ reaching at least the
     comparator's VMAF under the real cap; a cell that misses is lowered by 2 until it meets
     the comparator or the cap binds. The measurements are (8).
  8. **The calibration** (`tools/proof/work/codec-spike/crf_vp9.py`, gitignored; rows `kind`
     "vpx" in `crf.jsonl`), 2026-10-28 on a shared machine. VMAF pairs the two files' frames
     by INDEX (`settb=1/30,setpts=N`): a WebM's block times are whole milliseconds, and
     libvmaf's timestamp pairing put a third of the owner clip's frames against a neighbour's
     (the first owner run read 76.17 at CQ 30 / Low where index pairing reads about 91; its
     rows lack `"align": "index"` and are not used). Each VMAF below is "CQ: VMAF (share of
     the cap)", the kept cell in bold.
     - **(a) The spike's clips** (vpxenc, 8-bit, against `crf.jsonl`'s spike HEVC rows,
       scored against each clip's own y4m as those rows were; a search of the grid, 81
       encodes): cells gh5 / promo / real8 — Low 46 / 34 / 36, Medium 38 / 30 / 30, Format
       default 34 / 30 / 26, High 32 / 30 / 24, Maximum 28 / 28 / 16. The largest cap share
       of the 81 was **1.143 ×** (gh5 at Low, at CQ 10 and 30, where the cap binds).
     - **(b) The owner's clip at 8 bits** (an SDR project, `vp9_webm` against `hevc` —
       91.141 / 94.415 / 95.469 / 95.777 / 96.85 — both against its `prores_422` as
       yuv420p): Low 36: 90.871 (0.712), **34: 91.568 (0.786)**; Medium 32: 92.880, 30:
       93.664, 28: 94.081, **26: 94.431 (0.867)**; Format default 30: 93.874, 28: 94.367,
       26: 94.811, 24: 95.215, 22: 95.375, **20: 95.498 (0.938)**; High 30: 93.957 … 20:
       95.753, **18: 95.882 (0.948)**; Maximum 26: 95.248 … 16: 96.844, **14: 96.993
       (0.912)**.
     - **(c) The owner's clip at 10 bits** (an HLG project at `hlg`, against `hevc_10bit` at
       `hlg` — 92.064 / 94.681 / 95.620 / 95.976 / 97.133 — scored as yuv420p10le): Low
       36: 91.907 (0.786), **34: 92.455 (0.852)**; Medium 30: 94.571 (0.790), **28: 94.897
       (0.848)**, 26: 95.164 (0.904); Format default 28: 95.316 (0.748), 26: 95.679
       (0.825), **24: 95.958 (0.893)** (kept after R3, below), 22: 96.066, 20: 96.145
       (0.948); High 26: 95.868 (0.775),
       **24: 96.198 (0.855)**, 22: 96.338, 20: 96.435, 18: 96.499 (0.946); Maximum 22:
       97.038 (0.700), **20: 97.234 (0.754)**, 18: 97.393, 16: 97.508, 14: 97.578 (0.890).

     | bits per pixel per frame (the 1080p30 rate) | 8-bit (Profile 0) | 10-bit (Profile 2) |
     |---|---|---|
     | 0.0386 (Low, 2.4 Mb/s) | 34 | 34 |
     | 0.0579 (Medium, 3.6 Mb/s) | 26 | 28 |
     | 0.0700 (Format default, 4.35 Mb/s) | 20 | 24 |
     | 0.0772 (High, 4.8 Mb/s) | 18 | 24 |
     | 0.1157 (Maximum, 7.2 Mb/s) | 14 | 20 |

     The owner's clip binds every 8-bit point (the spike's cells are 34 / 30 / 26 / 24 /
     16); every cell reached its comparator under the real cap, so no STOP. The guide, the
     MCP page and `video_bitrate`'s description name the measured maximum as about 1.15 ×
     the cap. The least margins kept: 8-bit Medium +0.016, Format default +0.029.
     **The 10-bit Format default cell was lowered from 26 to 24 at the first `--rate` run**
     (`vp9_export_proof.py` R3 on Release): that run's `hevc_10bit` Format default encode
     scored 95.692 (the calibration's, 95.620) and `vp9_webm` at CQ 26 the calibration's
     95.679, 0.013 under; by (7)'s rule the cell went down by 2, to the CQ 24 the
     calibration had measured at 95.958 (0.893 × the cap), +0.27 over either comparator. C2
     saw the same one-encode variance in VideoToolbox's `hevc_10bit` (CX-14 (6)).
  9. **The C wrappers.** `vpx_codec_enc_init` is a macro and `vpx_codec_control_` is variadic,
     neither of which Swift can call, so `app/Bridging/FrameJobVPX.h` wraps them in two
     `static inline` functions (`framejob_vpx_vp9_enc_init`, `framejob_vpx_control_int`).
  10. **An SDR WebM/Matroska copy is labelled too** (the orchestrator's ruling of 2026-10-28 on
      C4's STOP; amends HD-18 (b) and HD-19 (b)). Measured in C4: Frame Job's own 640 × 360
      SDR `vp9_webm`, re-imported, rendered as BT.601 (cyan (0, 255, 255) read back
      (23, 255, 255); R/G/B 11.83 / 0.78 / 5.65 of 255 from the source's render), because the
      copy's description carried no colour and AVFoundation chose the matrix by the picture's
      size (the same round trip at 1280 × 720 read 0.53 / 0.16 / 0.30). So a copy whose
      Colour's transfer is neither 16 nor 18 now carries the labels its source states, from
      these sources in order, each field on its own:
      - **The Colour element:** `YCbCrMatrix` from MatrixCoefficients 1, 5, 6 or 9 (BT.709,
        BT.601, BT.601, BT.2020), `ColorPrimaries` from Primaries 1, 5, 6 or 9, and
        `TransferFunction` from TransferCharacteristics 1, 6, 13, 14 or 15 (the BT.709 class
        and sRGB), each the string Core Video names for the code
        (`CV…GetStringForIntegerCodePoint`), and none written for any other value or a code
        Core Video does not name.
      - **Else, for the matrix of a VP9 track, the first keyframe's `color_space`:** CS_BT_709
        is matrix 1, CS_BT_601 and CS_SMPTE_170 are 6, CS_BT_2020 is 9; CS_UNKNOWN and every
        other space write nothing. The core reads it with the `vpcC` it already builds and
        publishes it through `rc_container_describe` as `stream_matrix` (null when none); only
        Swift writes the labels.
      - **Neither:** the copy's description is unchanged, as before.

      The PQ (transfer 16) and HLG (transfer 18) copies are labelled exactly as HD-18 (b) and
      HD-19 (b) say. **Risk accepted:** an SDR WebM or MKV that was imported before reads
      differently now (its old copy in `Rewrapped/` keeps the old description until the
      source changes, the copy's name being a digest of the source); a label that lies is
      believed, as it is for every other movie.
  **Risks accepted:** VP9 is slow (about 39 fps at 1080p on the spike's M2 Max at cpu-used 4)
  and needs more bits than AV1 for the same picture; Profile 2 is decoded by fewer players
  than Profile 0; no player's HDR rendering was measured (CX-8); VMAF is not calibrated for
  HLG, so the 10-bit column's comparison is by the same instrument but not a perceptual
  claim; and the calibration covers four clips at 1080p.

- **CX-17 — C5: `vp9_alpha_webm`, VP9 with alpha in WebM: an 8-bit SDR row, a second libvpx
  encoder for the alpha, written as BlockAdditional 1** (default, recorded in C5 before its
  code; amends CX-15 (3), CX-16 (1) and G-35):
  1. **The row.** `vp9_alpha_webm` is "VP9 with Alpha (WebM)", directly after `vp9_webm`:
     container `webm`, codec `vp9`, video, `alpha` true, `size` and `fps` null, `avf_preset`
     `AVAssetExportPresetPassthrough` (a record, as on `vp9_webm`) and `writer` `libvpx`, with
     no `encoder_speeds` (CX-16 (2): `encoder_speed` is refused in the existing sentence, and
     the sheet's Speed popup is disabled). It is even-sized and `optimize_for_network` has no
     effect on it. **It is not an HDR row** (not in HD-5's `HDR_ROWS`): always 8-bit Profile 0,
     BT.709, as CX-16 (3)'s `sdr`. In an HLG project it writes the SDR version (settings
     `color` `sdr`), and `hlg` or `pq` asked of it is refused by the existing 8-bit sentence.
     WHY: the row's reason to exist is transparency in a browser, and `hevc_alpha`, the other
     delivery alpha row, is SDR too. It is one of the four rows whose `alpha` is true
     (`prores_4444`, `hevc_alpha`, `vp9_alpha_webm`, `apng`), so G-33's shape rule binds it:
     a size within a pixel of the canvas's shape is filled, and any other shape is refused in
     `alphaAspectMismatch`'s sentence before a file is made.
  2. **Straight alpha** (G-35 extended to the row). Each composed frame (`64RGBAHalf`) is
     straightened in place in float before its conversion, through PR-3's `prores_4444` pass
     (`ExportStraightAlpha.straighten(half:…)`: s = min(1, c/a) for a > 0, then G-35 (d)'s
     fill), and a frame that cannot be straightened stops the export with G-35's "A frame's
     transparency could not be written straight." The colour plane is BT.709 video range from
     the straight colour (CX-16 (3)'s 8-bit arithmetic); the alpha plane is a second 8-bit
     I420 picture whose Y = round(255 · clamp(a, 0, 1)), full range, and whose chroma is a
     constant 128.
  3. **Two encoders.** Two `VP9Encoder`s live on the pump's encode queue. The picture is
     exactly CX-16's 8-bit: capped CQ, CX-16 (7)'s table, the cap. The alpha runs `VPX_Q`
     (constant quality, no cap) at `VP8E_SET_CQ_LEVEL` `alphaCQLevel(pixels:)` (6), with
     `VP9E_SET_COLOR_RANGE` full (`VPX_CR_FULL_RANGE`), and otherwise CX-16 (6)'s settings.
     The cap and `video_bitrate` govern the colour stream alone.
  4. **Keys aligned by construction.** Both encoders run `kf_mode` auto with `kf_min_dist` =
     `kf_max_dist` = ⌊2 · fps⌋ (at least 1), and each frame whose index is a multiple of it is
     sent with `VPX_EFLAG_FORCE_KF`. Packets are paired by pts: the pump answers a packet only
     when both encoders have answered that frame. An alpha frame at another pts fails the
     export ("libvpx's alpha stream answered frame a where the picture's answered p."), and so
     does a key disagreement ("libvpx's alpha frame p and picture frame p disagree on being a
     keyframe.").
  5. **The layout** (amends CX-15 (3)). The TrackEntry carries `MaxBlockAdditionID` 1, and its
     Video carries `AlphaMode` 1. No `BlockAdditionMapping` is written: it is not in WebM's
     element set, and BlockAddID 1 is VP9's alpha by the codec mapping. Each video block is a
     BlockGroup: a Block (flags 0); BlockAdditions holding one BlockMore {BlockAddID 1,
     BlockAdditional = the alpha frame}; and, on non-key blocks only, a ReferenceBlock equal
     to the previous video block's ms − this block's ms. Clusters and Cues start at keys as
     CX-15 (3) says. The core refuses `alpha_mode` on `V_AV1` ("alpha_mode needs V_VP9; V_AV1
     carries no alpha"), a packet without its alpha on such a track, and one with alpha on a
     track without it, each in its own sentence (`rc_webm_add_video_with_alpha`).
  6. **The alpha's quality** (calibrated in C5). `tools/proof/work/codec-spike/alpha_vp9.py`
     (gitignored) encodes the alpha planes of two fixtures — the spike's
     `probe/webm/src-rgba.mov` (a moving disc over a 0–50 % ramp, 1080p30) and the proof's
     TITLE fixture exported as `prores_4444` at 1920 × 1080 — through the spike's
     `build/libvpx/vpxenc` with (3)'s and (4)'s flags, `--end-usage=q --cq-level=N`, N = 0, 2
     … 48, and decodes them with ffmpeg's `libvpx-vp9` (the spike's method). The level kept is
     the highest N at which every frame of both fixtures has an alpha PSNR of at least
     48.0 dB against its source; if none does, STOP. If the app's own A4 row
     (`vp9_alpha_export_proof.py`: any frame under 48.0 dB, or CLEAR's corner or card not
     exactly 0 or 255) misses at the kept level, `alphaCQLevel` is lowered by 2 until A4
     passes (CX-16 (7)'s rule), and each run's level and worst frame in dB, per fixture and
     tier, is recorded here; a miss at level 0 is a STOP. **The measurements** (2026-10-28,
     the spike's `vpxenc` v1.17.0 and ffmpeg 9.0.2's `libvpx-vp9`, rows `run` "c5" in the
     spike's `alpha.jsonl`; worst frame / mean of the frames not exact, in dB):
     - **DISC** (60 frames): CQ 0 exact on every frame; 2: 75.06 / 78.31; 10: 65.54 /
       68.74; 20: 59.88 / 62.66; 30: 55.56 / 58.11; 38: 51.79 / 53.76; 40: 50.51 / 52.72;
       **42: 48.85 / 51.22**; 44: 47.79 / 49.95; 46: 47.03 / 49.06; 48: 45.90 / 48.28.
     - **TITLE** (60 frames, a still title): exact at CQ 0 and 2; 85.07 at 4; 75.46 at 20;
       64.12 at 42; 60.30 at 48 — every level passes.

     So **`alphaCQLevel` is 42**, DISC binding it (the first miss is 44). The alpha stream
     at 42 is 74,933 bytes for DISC's 2 s and 5,768 for TITLE's. **The app at 42**
     (`vp9_alpha_export_proof.py` A4, Debug, first run): DISC 1080p 48.73 dB worst (frame 7)
     at both the Low and the Maximum tier, TITLE 64.16 dB at both — the alpha does not
     depend on the tier, the cap being the picture's — so no lowering by 2 was needed.
     CLEAR's corner 0 and card 255 on all 30 frames. DISC at 640 × 360 read 43.53 dB worst
     (mean 46.84) at 42, the disc's edge being a larger share of a smaller picture.

     **Amended in C5's fix pass (2026-10-28; the orchestrator's RULING-1 on the owner's
     standing preference for quality): the 48.0 dB floor holds at every size, so the level
     is banded by the picture's size.** `VP9Encoder.alphaCQLevel(pixels:)` answers the level
     of the band at or below the picture's pixel count, and a picture smaller than the
     smallest band takes the smallest band's level. Each band's level is the highest N whose
     worst DISC frame is at least 48.0 dB, by the method above on one fixture at every size:
     the proof's own DISC (`vp9_alpha_export_proof.disc_source`, the spike's `mkalpha.sh`
     regenerated as ProRes 4444 at the size, 60 frames), its alpha read as 8-bit gray
     (`work/codec-spike/alpha_vp9_ladder.py`, gitignored; rows `run` "c5-ladder"). The same
     lower-by-2 rule binds each band the app's A4 scores. At 1920 × 1080 this fixture binds
     lower than the spike's `src-rgba.mov` did (worst 47.91 dB at 42), so the 1080p band is
     40, not 42. The share is the alpha stream's rate (`vpxenc`'s bytes over the 2 s) over
     itself plus the picture's cap at 30 fps, at the Low (0.0386 bpp) and Maximum (0.1157)
     tiers; the picture usually stays under its cap, so the share is a lower bound.

     | Band (from) | Level | Worst / mean dB at the level | Next level up | Alpha kb/s | Share at Low / Maximum |
     |---|---|---|---|---|---|
     | 640 × 360 (and below) | **34** | 48.14 / 49.58 | 36: 47.22 | 158.3 | 37.2 % / 16.5 % |
     | 1280 × 720 | **38** | 48.66 / 50.17 | 40: 47.83 | 238.5 | 18.3 % / 6.9 % |
     | 1920 × 1080 | **40** | 48.91 / 50.54 | 42: 47.91 | 341.9 | 12.5 % / 4.5 % |
     | 3840 × 2160 | **46** | 48.18 / 49.72 | 48: 47.16 | 529.2 | 5.2 % / 1.8 % |

     At 640 × 360 the alpha at 34 costs half as much again as at 42 (105.2 kb/s): the size
     cost the floor takes on a small picture. A4 scores DISC at 640 × 360, 1280 × 720 and
     1920 × 1080 and TITLE (the 4K band is `vpxenc`'s alone: A4's PSNR is pure Python, too
     slow over 4K frames). **The app at the bands** (`vp9_alpha_export_proof.py`'s A4 alone,
     Release, 2026-10-28; worst frame / mean of the finite in dB, the same at the Low and
     Maximum tiers; the alpha's share of the file's video bytes at Low / Maximum): DISC
     640 × 360 48.79 / 50.77 (frame 27), share 38.8 % / 20.6 % (148.9 kb/s); DISC 1280 × 720
     49.88 / 52.23, 20.6 % / 9.3 % (227.2 kb/s); DISC 1920 × 1080 50.54 / 52.77, 14.4 % / 6.4 %
     (321.4 kb/s); TITLE 65.03 / 65.05, 43.5 % / 44.3 % (20.8 kb/s: a still title's picture is
     nearly empty, so its small alpha is a large share). Every band passed at its level, so
     none was lowered; CLEAR's corner 0 and card 255 on all 30 frames.
  7. **Import.** A re-imported `vp9_alpha_webm` keeps its colour and loses its alpha: the
     rewrap (#216-R) copies the Block and not the BlockAdditional, and Apple's VP9 decoder has
     no alpha. Accepted as a limit, recorded in the guide; keeping the alpha on import is not
     built.
  8. **Risks accepted:** Safari's playback of WebM alpha is unconfirmed (a person's check,
     `docs/manual-checks.md` SE-21; `hevc_alpha` is Safari's route); ffmpeg's native `vp9`
     decoder ignores the alpha, so only a libvpx decoder reads it; HDR and 10-bit alpha, and
     AV1 alpha (CX-1), are not built.

- **CX-18 — C6a: the Export Queue's memory limit on bundled-encoder jobs, and the sheet's time
  estimate** (default, recorded in C6a before its code; amends #326's `queued` answer; the
  chain of road map 2's 7e and #326 is not touched):
  1. **The queue stays one job at a time** (#326, 7e): one `Exporter` on the main thread, a
     fresh one per job, `ReverseSource.pin` at most one. The limit is not a pool size; it is
     a hold on a queued job while OTHER bundled-encoder exports in the app already use the
     memory it needs.
  2. **The limit is app-wide over bundled-encoder exports** — every export whose settings
     carry a `writer` (`svt_av1`, `libvpx`; `av1`, `av1_webm`, `vp9_webm`, and C5's alpha row
     on arrival, since the rule keys on `writer` and not on a row id): the queue's running job
     and every Export… progress sheet's. They are booked in one main-thread ledger
     (`ExportEncoderLedger`) from just before the exporter starts to its finish.
  3. **The budget is a quarter of physical memory** (`ProcessInfo.physicalMemory / 4`), the
     share G-37 gives graphic rasters, so an export's two large consumers together stay within
     half the Mac. Relative to physical RAM, never a fixed figure (the owner's standing rule).
  4. **Each job costs its resident peak**, measured per key — preset, AV1 speed, bit depth
     (10 on `svt_av1`, CX-14; on `libvpx` 10 for `hlg`/`pq`, else 8) — at 1920 × 1080 and
     3840 × 2160 (`tools/proof/encoder_memory_measure.py`, the road map's "## C6a" record),
     and scaled by the export's pixels: proportionally below 1080p, linearly through both
     points above it, extrapolated past 4K. **A writer row with no measured cost costs the
     whole budget**, so it runs alone and nothing joins it, until it is measured.
  5. **A queued job is admitted** when nothing is booked, or when the booked costs and its own
     fit the budget. Otherwise it waits, and its row and `export_status` say why, in one
     sentence: "Waiting for memory: AV1 and VP9 exports running now hold about X GB of the
     Y GB this Mac allows them, and this one needs about Z GB." A booking's end re-runs the
     queue.
  6. **An Export… sheet is counted but never held**: a person who chose Export… asked to
     write now, and waiting behind a hidden queue job would contradict the sheet's own bar.
  7. **A held job is passed over** by a later job the ledger admits — an AVFoundation job
     always — so a waiting AV1 job does not stall an H.264 one behind it; among AVFoundation
     jobs the chain's order is today's.
  8. **`export_status`**: `queued` adds `waiting` (the held sentence, present only while
     held); `queued` and `running` add `estimated_seconds` on a writer row. `export`'s answer
     is unchanged.
  9. **The estimate.** The export sheet's summary gains "Estimated time: about …" on a writer
     row: setup seconds plus the range's frames times a per-frame time scaled by pixels as in
     (4), from a per-key table whose every constant names its source. Rounded to 5 s under a
     minute, whole minutes under an hour, then hours and minutes. The constants are
     PROVISIONAL (one run each, on a shared machine) until C6b measures 4K on every row and
     the idle three-run speeds, which replace them by a table edit. No estimate on an
     AVFoundation row, in a queue row or in `export`'s answer, nor when the rate cannot be
     stepped (no frame count: no estimate rather than one for 0 frames).
  10. No format bump, no op, no `rc_*` export.
  **Risks accepted:** the cost is a measured peak on one machine and one picture, not a
  bound — a heavier timeline can exceed it; a sheet export can take the app past the budget
  (6); the estimate is a single-run figure until C6b.
  **Amended by C6b** (2026-10-29): the time constants are final, and (9)'s PROVISIONAL and
  the risk's "single-run figure" no longer hold. **Method:** `encoder_memory_measure.py`
  against Release, Apple M2 Max (Mac14,6), 96 GiB, on AC, on a machine idle before each
  batch (no other Frame Job, build or compiler; 1-minute load ≤ 4 at the batch's start; the
  load read during a batch is its own encoders' threads). The picture is real camera
  footage: the owner's GH5 borough-market clip (H.264 8-bit 3840 × 2160 25p) on a 25 fps
  canvas, its in/out range exported. Each writer key ran three rounds at 1920 × 1080 and
  3840 × 2160 over 10 s (250 frames, batch "long") and again over 2 s (50 frames, "short"),
  every key once per round so drift spreads across keys. Per key and size the intercept
  s = e_S − n_S·(e_L − e_S)/(n_L − n_S) on the median wall times; `setupSeconds` is the
  smaller of the two sizes' intercepts when both pass 0.5 s, else 0, and `perFrame` is
  (median e_L − setupSeconds) / 250. **Rules:** `av1_webm`'s three time entries copy `av1`'s
  at the same speed, because `av1_webm:balanced`'s median was within 10 % of `av1:balanced`'s
  at both sizes (−1.9 % at 1080p, −0.1 % at 4K; same encoder, speeds and CRFs, CX-15). Each
  memory figure is max(the C6a or C5 figure, C6b's largest Δ at that size), so no figure is
  lowered below a measured peak, and its source names the run that won, size by size. The
  estimate's formula (9) and the ledger (1)–(8) are unchanged. **Medians** (long, short in
  seconds; the bytes are the long batch's median file; Δ the largest across both batches):

  | Key | Size | Long s (min–max) | Short s | setup s | s/frame | MB | Δ GiB |
  |---|---|---|---|---|---|---|---|
  | av1 faster | 1080p | 2.380 (2.352–2.446) | 0.895 | 0.524 | 0.007425 | 5.60 | 1.32 |
  | av1 balanced | 1080p | 4.175 (4.107–4.194) | 1.425 | 0.738 | 0.013750 | 5.39 | 2.22 |
  | av1 smaller | 1080p | 5.792 (5.756–5.808) | 1.747 | 0.736 | 0.020225 | 5.10 | 2.43 |
  | av1_webm balanced | 1080p | 4.096 (4.063–4.174) | 1.422 | 0.753 | 0.013370 | 5.30 | 2.18 |
  | vp9_webm SDR | 1080p | 7.020 (6.988–7.074) | 1.761 | 0 | 0.028080 | 5.19 | 0.37 |
  | vp9_webm HLG | 1080p | 9.043 (8.994–9.049) | 2.031 | 0 | 0.036172 | 5.07 | 0.50 |
  | vp9_alpha_webm | 1080p | 7.889 (7.877–7.905) | 1.935 | 0 | 0.031556 | 5.21 | 0.75 |
  | av1 faster | 4K | 7.127 (7.059–7.188) | 1.995 | 0.524 | 0.026413 | 20.92 | 4.49 |
  | av1 balanced | 4K | 13.971 (13.863–14.064) | 3.803 | 0.738 | 0.052934 | 16.53 | 7.48 |
  | av1 smaller | 4K | 19.887 (19.764–20.191) | 5.124 | 0.736 | 0.076605 | 14.61 | 8.10 |
  | av1_webm balanced | 4K | 13.953 (13.889–14.127) | 3.772 | 0.753 | 0.052798 | 16.51 | 7.63 |
  | vp9_webm SDR | 4K | 23.549 (23.263–23.610) | 4.846 | 0 | 0.094196 | 18.55 | 1.04 |
  | vp9_webm HLG | 4K | 31.237 (31.128–31.488) | 6.202 | 0 | 0.124948 | 17.33 | 1.56 |
  | vp9_alpha_webm | 4K | 26.286 (26.190–26.401) | 5.422 | 0 | 0.105144 | 18.58 | 2.14 |

  The setup column is the key's `setupSeconds` (the smaller intercept), the same at both
  sizes; the two `av1_webm balanced` rows show its own fit, while the shipped entries copy
  `av1`'s (within the 10 % rule). Memory raised by C6b: `av1` balanced and smaller and `av1_webm` balanced at both
  sizes; `av1` faster, `vp9_webm` SDR and `vp9_alpha_webm` at 1080p only. Every other figure
  keeps its C6a or C5 value and source. The estimate was checked on an export it was not
  fitted on: 30 s from 20 s at 2560 × 1440 (road map "## C6b").
  **Risk accepted:** the figures are one machine and one picture's medians; harder footage,
  a heavier timeline or a busy Mac takes longer.
