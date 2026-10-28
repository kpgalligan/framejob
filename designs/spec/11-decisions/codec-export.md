# Spec §11 — decisions: Codec export (road map "codec-export", #377)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is `designs/codec-export.md` (in progress); its spike record
(`## S — the spike`) holds every measurement cited here. CX-1..CX-11 were recorded in C0,
before any code. Each is marked "owner" (the owner's choice, 2026-10-27) or "default" (the
orchestrator's default, which the owner can still change by a new entry here).

- **CX-1 — The road map: bundled software encoders, four export rows** (owner, 2026-10-27:
  "It is super valuable to me. Bundle the encoders."). Frame Job exports AV1 and VP9 with
  encoders built into the app, as four rows:
  1. AV1 in MP4, with AAC audio;
  2. AV1 in WebM, with Opus audio;
  3. VP9 in WebM, with Opus audio;
  4. VP9 with alpha in WebM.

  VP9 in MP4 is not wanted: it works (the spike measured it) but carries no alpha and is less
  efficient than AV1 in MP4, so it does nothing another row does not. AV1 with alpha is not
  wanted because none exists in practice: neither SVT-AV1's nor libaom's API takes an alpha
  input, and the Matroska AV1 mapping defines none. **Risk accepted:** software encoding is
  1.5–5.4× slower than VideoToolbox's HEVC per 1080p frame on the spike's M2 Max and needs
  1.0–2.1 GB, and the app grows by about 5 MB.

- **CX-2 — AV1 is SVT-AV1 v4.2.0 alone; there is no libaom** (owner). Its three speeds are
  Faster = preset 8, Balanced = preset 6 (the default) and Smaller file = preset 4. The
  spike measured SVT-AV1 at about 3× libaom's speed at matched quality (SVT 4 ≈ libaom
  good-5/6), and better quality at every matched speed; libaom's best tier (good-3/4) was
  about 0.8 VMAF above SVT 4 at about 11× the time. Presets 10 and 12 were within 0–0.7 VMAF
  of HEVC at 2–3× its CPU cost, so they get no row. **Risk accepted:** SVT-AV1's worst frame
  (VMAF 86–88) is lower than libaom's (92), and its memory is higher (1.0–2.1 GB against
  0.5–1.1 GB).

- **CX-3 — VP9 is libvpx v1.17.0 at `--good` cpu-used 4 with row-mt, one speed** (owner).
  VP9's reason to be on the sheet is web playback and alpha, not efficiency: at matched
  quality it needs 1.4–1.7× SVT 6's bitrate. cpu-used 2 bought +0.14–0.43 VMAF for about 35 %
  more time, and rt-8 only matched HEVC, so neither gets a row. **Risk accepted:** one speed,
  so no faster VP9 for a long export.

- **CX-4 — The encoders are platform-side** (default). Swift calls their C APIs through the
  bridging header (`app/Bridging/FrameJob-Bridging-Header.h`); no `rc_*` export wraps them and
  the core never links them, because encoding is sample work and the core does none (spec
  §7). They are arm64, static (each `.a` linked by its full path into the app's one
  executable, never a dylib) and encoder-only (SVT-AV1 `BUILD_DEC=OFF`, libvpx
  `--disable-vp8 --disable-vp9-decoder`). "No ffmpeg dependency in the product" stands: these
  are two encoder libraries, not ffmpeg. **Risk accepted:** the encoders' C APIs become part
  of the Swift side's surface, and an encoder bug crashes the app rather than a helper.

- **CX-5 — The build policy** (default):
  1. Each library is a pinned release tarball checked by SHA-256, fetched and built by
     `make codecs` and by Xcode's "Build Codecs" pre-build step
     (`tools/codecs/build_codecs.py`), installed into `build/codecs/` and reused while its
     stamp's key (the script's bytes, the pins, the tool versions and the deployment target)
     and every recorded output's digest match.
  2. No library source is in git (about 16.7 MB of tarballs stay out). The tools are cmake
     from Homebrew and the system's perl (`/usr/bin/perl`); no nasm, yasm, meson or ninja.
  3. A downloaded tarball whose digest is not the pin's fails the build, naming both digests,
     and is deleted.
  4. Each library's licence and patent texts ship in the bundle at
     `Contents/Resources/Licenses/<library>/`, copied from the source tree; the
     acknowledgements (#376) list them.

  **Risk accepted:** cmake on every build machine and the publish runner, network for the
  first fetch, and a clean build of about one to two minutes.

- **CX-6 — The WebM writer is Rust in `core/`, beside #216-R's reader, not libwebm** (owner).
  Writing container bytes is not sample work, under #216-R's precedent (`deepening.md`): the
  writer decides timestamps, cluster and cue placement and CodecDelay, and touches compressed
  packets only as opaque bytes. It honours spec §7.8's chapters, range and size and #337's
  audio length, so the WebM rows are not a lesser second writer, and it is round-trip tested
  against the reader in `make test`. **Risk accepted:** a new writer to maintain instead of
  Google's proven muxer, and the reader's grid rule and the writer's timing must agree (the
  spike saw libwebm's millisecond times read back off the grid).
  **Amended by CX-15** (C3): the writer is `rc_webm_*` (`webm_ebml.rs`, `webm_writer.rs`), its
  layout and interleave as CX-15 (3) and (4) say, and the app's second `ExportPipeline`.

- **CX-7 — Opus comes from AudioToolbox** (default), not libopus. It sits where AAC does:
  after the mix and the loudness gain (`ExportAudioGain`, `ExporterLoudness`). The writer
  builds OpusHead and CodecDelay itself, the pre-skip taken from the converter's `primeInfo`
  (312 frames measured), because Apple's 28-byte cookie is not OpusHead. AV1 in MP4 keeps AAC.
  **Risk accepted:** Apple's VBR came in under the asked rate (72 kb/s for 128 k on a test
  tone), and libopus (+0.32 MB) is the fallback only if a quality or control gap shows up.
  **Amended by CX-15** (C3): 192 kb/s by default, 20 ms packets behind a 960-frame FIFO, the
  pre-skip `primeInfo.leadingFrames`, and the tail cut to #337's length by DiscardPadding.

- **CX-8 — HDR** (default): the AV1 rows are 10-bit, with HLG or PQ tagged in both the
  bitstream (the sequence header's colour config) and the container (`colr` in MP4, `Colour`
  in WebM), plus HD-5's HDR10 mastering metadata (`mdcv`/`clli`, WebM's MasteringMetadata).
  They take `hevc_10bit`'s place in H-3's rules. VP9 Profile 2 HDR is a later phase of its
  own, WebM only, because VP9's bitstream carries no transfer function and the container must.
  **Risk accepted:** no player's HDR rendering of these files was measured.

- **CX-9 — The rate model keeps the bitrate semantics on every row** (default):
  1. `video_bitrate` is the single-pass VBR target (two passes would compose every frame
     twice);
  2. the Quality tiers apply HEVC's 0.6 factor to AV1 and VP9, and "Format default" is HEVC's
     0.07 bits per pixel per frame;
  3. the efficiency goes to the picture, not the file size, because the owner wants quality
     (2026-10-27): SVT 6 measured +2.8 to +4.8 VMAF over HEVC at HEVC's rate;
  4. **risk accepted:** a rate is a target, and single-pass SVT-AV1 undershot it by 14–22 % on
     5 s clips (libvpx overshot by 5–7 %). C1 re-measures on a full-length export. *Result
     (C1):* on the owner's 55 s 1080p30 clip single-pass VBR at Balanced came in at
     0.667–0.670 of the target in six runs, at "Format default" and at High
     (`designs/codec-export.md`, C1); the owner then chose capped constant quality for the
     AV1 rows, CX-13, which replaces (1) and this item there.

- **CX-10 — On an M1 or M2 the AV1 export still works, but Frame Job cannot preview or
  re-import that file** (default): those Macs have no AV1 decoder, and #216's refusal stands.
  The user guide says so (C1), and playback is a manual check on an M3 or later. **Risk
  accepted:** a user on an M1/M2 exports a file they cannot watch in Frame Job or QuickTime.

- **CX-11 — The working arrangement** (default): the road map is built in the `codecs`
  worktree, each phase gated and merged on its own. C0 adds no export row and no format bump:
  it records these decisions, opens the road map and builds and links the two libraries.

- **CX-12 — C1's shape: AV1 in MP4 at 8 bits** (default, recorded in C1 before its code):
  1. **The row.** `av1`, "AV1 (MP4)", after `hevc_10bit` in the table: MP4, codec `av1`, video
     with AAC audio, no alpha, even-sized as every AVFoundation row but `prores_4444` (G-33).
     Its `avf_preset` is `AVAssetExportPresetPassthrough`, a record only, because
     AVFoundation still writes the container; a new field, `writer` (`svt_av1`), names the
     encoder route, so `avf_preset: null` keeps meaning the ImageIO writer and no other row
     changes.
  2. **The speed.** `encoder_speed` is `faster`, `balanced` (the default) or `smaller` — SVT-AV1
     preset 8, 6 or 4 (CX-2) — and is refused on a row without encoder speeds, naming the key.
     The sheet's Speed row sits under Format (after Dynamic Range when that is shown); on
     another row it is disabled and shows the last choice, as Quality does, and the choice is
     remembered with the rest of the sheet (`ExportChoice`).
  3. **Keyframes.** A closed GOP (`intra_refresh_type` = `SVT_AV1_KF_REFRESH`), a keyframe at
     least every 2 s (`intra_period_length` = ⌊2·fps⌋ − 1). The sync samples are the
     passthrough `AVAssetWriter`'s own, read from the bitstream: C1 measured that marking every
     sample `NotSync` left the file's sync samples at exactly its KEY_FRAMEs, so the pump
     writes no sync attachment, and `av1_export_proof.py` A5's match of each key-flagged
     packet to a shown KEY_FRAME, both ways, is the guard. The `SVT_AV1_KF_REFRESH` line is
     live only under CX-13's capped CRF: SVT-AV1 v4.2.0 forces KF refresh under single-pass
     VBR (`lap_rc`), and under CRF its FWDKF refresh writes each 2 s refresh as a hidden
     INTRA_ONLY frame (`frame_type` 2, `show_frame` 0, shown later by `show_existing_frame`)
     after one KEY_FRAME, which A5 refuses.
  4. **The container bytes are the core's.** The `av1C` record (built from SVT's sequence
     header OBU), the stripping of temporal delimiters from every packet and the rewrite of
     the written file's `ftyp` to carry `av01` are decided in the core (CX-6's container-bytes
     precedent; `rc_av1_*`). A written file whose `ftyp` cannot take `av01` fails the export.
  5. **The frames.** The compositor's 64RGBAHalf frames are converted on the GPU to BT.709
     video-range I420 (chroma the mean of each 2×2 block); when the export size is not the
     canvas, `MPSImageLanczosScale` scales first, fit or fill per G-33 (c), with black bars.
  6. **SVT-AV1's log** goes through `svt_av1_set_log_callback`: info and debug are dropped,
     warnings and errors become `NSLog("SVT-AV1: …")`.
  7. **HDR projects.** In an HLG project the `av1` row writes the SDR version, by HD-14's
     existing rule for an SDR row; 10-bit and HDR AV1 are C2's (CX-8).
  **Amended by CX-14** (C2): the row is 10-bit (I010, not (5)'s 8-bit I420, the matrix per
  picture) and, replacing (7), one of HD-5's HDR rows.
  **Amended by CX-15** (C3): (1)'s `writer` is no longer one row's: `av1_webm` carries
  `svt_av1` too, with the same speeds, and its `avf_preset` name also means "the composition
  is read back through AVFoundation".

- **CX-13 — AV1's rate is a soft cap: capped constant quality, quality first** (owner,
  2026-10-27, "Capped constant quality", chosen after C1 measured single-pass VBR at
  0.667–0.670 of its target on a 55 s 1080p clip; then 2026-10-28, "Quality first, soft
  cap"; amends CX-9 (1) and (4) for the AV1 rows, CX-9 (2) and (3) standing):
  1. **The mode.** SVT-AV1 runs capped CRF: `rate_control_mode` 0 with `aq_mode` 2 (what its
     own `--crf` sets), `qp` the CRF, and `max_bit_rate` the cap — the mode SVT-AV1 v4.2.0's
     `EbSvtAv1Enc.h` documents for `max_bit_rate` and `mbr_over_shoot_pct` ("Capped CRF") and
     its `enc_settings.c` refuses outside rate-control mode 0. `mbr_over_shoot_pct` is SVT's
     own default, 50 (`EbSvtAv1Enc.h` "Default is 50", `enc_settings.c`, `Docs/Parameters.md`),
     so the requested rate is a cap the encoder aims under that hard footage may exceed: at
     (3)'s CRFs on the spike's clips the largest whole-file average was **1.254 × the cap**
     (gh5, 25 fps, Faster at Format default; 14 of 45 files over 1 ×, all of them gh5 but one
     real8 at 1.022 ×), with every file at or above HEVC's VMAF (the least margin +0.035).
     **The tolerance:** `av1_export_proof.py` R1 and R2 hold each file of the owner's clip to
     at most 1.30 × the cap (raised from 1.25 × at integration, above the measured 1.254 ×) and to a VMAF at or above `hevc`'s. **Declined (owner, 2026-10-28):
     a strict cap.** At 12 % overshoot every spike file stayed at or under 0.990 × the cap, but
     the cap then lowers the picture while the file is far under it (SVT holds keyframes and
     base-layer frames to a share of each 60-frame window), and the owner's clip at Faster,
     Format default, plateaued under HEVC's 95.469:

     | Faster, Format default, owner's clip | 12 % overshoot | 50 % overshoot |
     |---|---|---|
     | CRF 24 | 95.055 (0.645 × the cap) | 95.583 (0.729 ×) |
     | CRF 20 | 95.184 (0.703 ×) | 95.919 (0.844 ×) |
     | CRF 16 | 95.348 (0.735 ×) | — |

     (25 % and 20 % held gh5 to 1.03 × and 0.999 × at the first CRFs; at 10 % the cap
     dropped gh5 at Faster's Medium 0.02–0.08 VMAF under HEVC.)
  2. **The cap** is the rate the row resolves today: `video_bitrate` when asked (the Quality
     popup's tier rate, HEVC's 0.6 factor, CX-9 (2)), else HEVC's 0.07 bits per pixel per
     frame ("Format default"), clamped to SVT's 100,000 kb/s.
  3. **The CRF matches or beats HEVC at HEVC's own rate, so a Quality tier moves it.** The
     encoder sees only the cap, so the CRF is a function of the cap's bits per pixel per frame
     (cap ÷ (width × height × fps)) and the speed: linear between the calibrated points below,
     rounded down (a lower CRF is the better picture), and the end point's CRF beyond either
     end. Each point is the lower of two calibrations, each the highest CRF on its grid at
     which SVT-AV1 at that preset reached VMAF ≥ HEVC's at the point's rate (ffmpeg's libvmaf;
     `tools/proof/work/codec-spike/crf.py`, `crf_owner.py`, `crf.jsonl`): the spike's three
     8-bit 1080p clips (gh5, promo, real8), SVT-AV1's own encoder against VideoToolbox HEVC
     through ffmpeg, CRF 18–46 in steps of 2; and the owner's 55 s 1080p30 IMG_0018.MOV
     through Frame Job itself, its `av1` export (a copy of the tree reading the CRF from a
     file) against its `hevc` export, both scored against its `prores_422` export, CRF 12–44
     on a grid of 2 to 8. The second was added when `av1_export_proof.py` R1 and R2 found the
     first's CRFs 0.6–1.9 VMAF under the app's HEVC on that clip: the spike's command-line
     encodes of decoded frames score lower than the app's own, by 1.1 VMAF for SVT-AV1 at one
     CRF and 1.6 for HEVC at one rate on that clip, so the first did not transfer.

     | bits per pixel per frame (the 1080p30 rate) | Faster (8) | Balanced (6) | Smaller file (4) |
     |---|---|---|---|
     | 0.0386 (Low, 2.4 Mb/s) | 40 | 36 | 36 |
     | 0.0579 (Medium, 3.6 Mb/s) | 28 | 30 | 30 |
     | 0.0700 (Format default, 4.35 Mb/s) | 24 | 26 | 26 |
     | 0.0772 (High, 4.8 Mb/s) | 22 | 24 | 24 |
     | 0.1157 (Maximum, 7.2 Mb/s) | 14 | 16 | 16 |

     The owner's clip binds every point but Faster's Medium, which the spike's promo graphic
     binds (its VMAF saturates near 97.7, so its margins are hundredths of a point), and
     Faster's Low, where both give 40. At (1)'s 50 % the owner's clip held it under the real
     cap (`--rate` on Release, 2026-10-28): Format default 95.570 / 95.632 / 95.506 and High
     95.856 / 96.067 / 95.951 (Faster / Balanced / Smaller file) against `hevc`'s 95.469 and
     95.777, every file 0.48–0.73 × the cap.
  4. **What the user is told.** The guide, the MCP page, the sheet's tier titles and footnote
     ("usually ≤ …") and `export`'s `video_bitrate` description say the rate is a soft cap the
     file usually stays under, and one sentence names the measured overshoot (about 1.25 ×).
     **Risk accepted:** a file's size is no longer predictable from its rate and can exceed
     it; the calibration is four clips at 1080p (other sizes are placed by bits per pixel
     alone), one of them the binding one, so other footage can land a little under HEVC; and
     the owner clip's grid is coarse (Balanced and Smaller file at Low: 36 passed, 44 did not).
  **Amended by CX-14** (C2): R1 and R2 compare `av1` with `hevc_10bit`, both scored as
  10-bit 4:2:0, and the owner-clip half of (3)'s calibration is re-checked at 10 bits against
  `hevc_10bit` (CX-14 (6)).

- **CX-14 — C2: one `av1` row, always 10-bit, among HD-5's HDR rows** (default, recorded in C2
  before its code; amends CX-12 (5) and (7), CX-13 (3) and HD-14 (c)):
  1. **One row, always 10-bit.** `av1` encodes 10-bit Main 4:2:0 in SDR and HLG projects alike;
     there is no `av1_10bit` and no 8-bit AV1 path. CX-1 fixed four rows; CX-8 makes the AV1
     rows 10-bit and puts them in `hevc_10bit`'s place in H-3's rules. `hevc` stays an 8-bit
     row (PR-3) for decoders that take HEVC Main alone; AV1 has no such split, since Main
     profile decodes 8 and 10 bits alike, and the owner's rule is that only the higher-quality
     export matters.
  2. **An HDR row.** `av1` joins HD-5's HDR rows (`HDR_ROWS`): `"hdr": true` in
     `rc_export_presets`, `hlg` by default in an HLG project, `pq` or `sdr` as asked, and the
     8-bit refusal now names it: `{id} is 8-bit and writes the SDR version; export
     dynamic_range "{x}" as hevc_10bit, av1, prores_422 or prores_4444`. Replaces CX-12 (7);
     amends HD-14 (c)'s sentence and its "three 10-bit rows". An SDR project's settings are
     unchanged; an HLG project's `av1` settings gain only `color`.
     **Amended by CX-15** (C3): `av1_webm` is a fifth HDR row, and the sentence reads `… as
     hevc_10bit, av1, av1_webm, prores_422 or prores_4444`.
  3. **The frames: I010.** The compositor's frame (scaled first as CX-12 (5) says) becomes
     video-range 10-bit 4:2:0 in 16-bit little-endian samples: Y′ = kr·R + (1−kr−kb)·G + kb·B,
     Cb′ = (B−Y′)/(2(1−kb)), Cr′ = (R−Y′)/(2(1−kr)), RGB clamped to 0…1 and read premultiplied;
     Y = round(64 + 876·Y′) and each chroma sample clamp(round(512 + 896·C′), 0, 1023), C′ the
     mean of its 2 × 2 block. The matrix is the picture's: BT.709 (0.2126, 0.0722) for `sdr`,
     BT.2020 non-constant (0.2627, 0.0593) for `hlg` and `pq`.
  4. **The tags, in both places.** The sequence header's colour config and the `av01` entry's
     `colr` (`nclx`) carry the same CICP, video range: `sdr` 1/1/1, `hlg` 9/18/9, `pq` 9/16/9.
  5. **HDR10 on PQ only, in both places.** HD-5's fixed metadata (P3-D65, 0.005–1,000 cd/m²,
     MaxCLL 1,000, MaxFALL 0) goes into SVT-AV1's `mastering_display` and
     `content_light_level`, set by `svt_aom_parse_mastering_display` and
     `svt_aom_parse_content_light_level` from `G(0.265,0.690)B(0.150,0.060)R(0.680,0.320)
     WP(0.3127,0.3290)L(1000,0.005)` and `1000,0`, which SVT-AV1 v4.2.0 writes as HDR_MDCV and
     HDR_CLL metadata OBUs on each KEY_FRAME (`packetization_process.c` 678–688); and into the
     `av01` entry's `mdcv` and `clli` boxes from OutputTransform's two blobs (HD-14 (d)). Both
     carry the same values, as AV1-ISOBMFF requires. `hlg` and `sdr` carry neither.
  **Risks accepted:** 10-bit SVT-AV1 is about 15 % slower and needs about 40 % more memory (the
  spike: Balanced at 1080p 75 → 64 fps, 1.15 → 1.61 GB); the CRF table is calibrated in SDR
  only (VMAF is not calibrated for HLG or PQ); and no player's HDR rendering was measured (CX-8).
  6. **The CRF comparator** (amends CX-13 (3)): the owner-clip half of each point is
     re-calibrated at 10 bits against `hevc_10bit`; the spike half (gh5, promo and real8 through
     ffmpeg at 8 bits against 8-bit VideoToolbox HEVC) is not re-run and stands as CX-13
     recorded it, so each point is still the lower of the two. The run
     (`crf_owner.py --ten-bit`, 2026-10-28, 02:02–03:28 on a shared machine, one run): a
     Release copy at the table's own CRF, IMG_0018.MOV exported as `prores_422` (the
     reference), `hevc_10bit` at the five rates and `av1` at each speed and rate under the
     real cap (`video_bitrate` the rate, 50 % overshoot), all scored as `yuv420p10le`; a cell
     under `hevc_10bit` lowered by 2 until it reached it (`via: "app-10bit"` in `crf.jsonl`).
     `hevc_10bit` scored 92.723 / 95.246 / 96.075 / 96.367 / 97.435 at Low / Medium / Format
     default / High / Maximum (8-bit `hevc` scored 95.469 at Format default and 95.777 at High
     in CX-13). That run's one Format default `hevc_10bit` encode came out at 4,215,901 b/s
     and 95.828, and `av1_export_proof.py` R1 then failed against a 96.075; seven later
     encodes of the same export (four runs, 03:45–04:20) were each 4,342,949 b/s and 96.075,
     the other four rates matched the first run exactly, and Format default was calibrated
     again against 96.075 (`--tiers default`, 04:14–04:49). Each `av1` VMAF, CRF in brackets, the kept one
     last:

     | Rate | Faster | Balanced | Smaller file |
     |---|---|---|---|
     | Low | 91.611 (40), 92.235 (38), **92.828 (36)** | **93.351 (36)** | **93.316 (36)** |
     | Medium | 95.165 (28), **95.471 (26)** | 95.203 (30), **95.617 (28)** | 95.103 (30), **95.498 (28)** |
     | Format default | 95.982 (24), **96.193 (22)** | 96.048 (26), **96.487 (24)** | 95.924 (26), **96.377 (24)** |
     | High | 96.278 (22), **96.447 (20)** | **96.505 (24)** | **96.385 (24)** |
     | Maximum | 97.282 (14), **97.376 (12)**, 97.296 (10), 97.325 (8), 97.298 (6), 97.266 (4) | **97.568 (16)** | **97.492 (16)** |

     So the table became Low 36 / 36 / 36, Medium 26 / 28 / 28, Format default 22 / 24 / 24,
     High 20 / 24 / 24 and Maximum 12 / 16 / 16. Faster's Medium, which the promo half bound
     in CX-13 (28), is now bound by the owner clip at 10 bits (26). **Faster at Maximum
     reached no CRF:** from 12 down the cap binds (0.93–1.03 × it) and the VMAF stays
     0.06–0.17 under `hevc_10bit`'s 97.435. **Accepted (owner, 2026-10-28, "Best CRF,
     accept 0.06"):** the cell is 12, the best measured, at 97.376 — 0.059 under
     `hevc_10bit`'s 97.435 and still 0.53 above C1's 8-bit `hevc` comparator (96.85) —
     because below CRF 12 the cap binds and a lower CRF gains nothing.

- **CX-15 — C3: `av1_webm`, the core's WebM writer and Opus** (default, recorded in C3 before
  its code; amends CX-6, CX-7, CX-12 (1), CX-14 (2), HD-5 and HD-14 (c)):
  1. **The row.** `av1_webm` is "AV1 (WebM)", directly after `av1`: container `webm`
     (`org.webmproject.webm`), codec `av1`, video, no alpha, `size` and `fps` null,
     `avf_preset` `AVAssetExportPresetPassthrough`, `"hdr": true`, `writer` `svt_av1` and
     `av1`'s `encoder_speeds`. It is even-sized and one of HD-5's HDR rows. It shares `av1`'s
     speeds, CX-13's cap and CRF table, and CX-14's I010, CICP and PQ HDR10, all through the
     same `SVTAV1Encoder`. `optimize_for_network` defaults to false and has no effect on this
     row, as it has none on WAV.
  2. **The writer is a second `ExportPipeline`, an exception to §7.8's one-writer argument.**
     `Exporter.pipeline` chooses `ExportWebMWriter` for the `webm` container. It reads through
     the same reader outputs as `ExportWriter` and the same `ExportEncodePump`, and uses the
     same `ExportAudioGain`, `ExportAudioEnd`, `ExportChapter.partition`,
     `encodedSize`/`fillsTheBox` and bitrate resolution, so chapters, rates, size, range and
     #337 are one decision each. **A composition with no audio track is a silent movie, as in
     `ExportWriter.addAudio`:** the layout has no `audio`, and no audio reader output, Opus
     encoder or audio queue is made. **One `AVAssetReader` per output** (fix pass 1): the
     video composition output on a reader of its own, the audio mix output on another, both
     over the same composition and range (a silent movie has the video reader alone). WHY:
     two outputs of one reader are coupled — an output nobody reads stalls the reader — so
     on a shared reader a stop on one pump could leave the other blocked in
     `copyNextSampleBuffer` for good (G-17's starvation, seen once in C3), and
     `cancelReading()` cannot wake it: AVFoundation's header forbids calling it concurrently
     with a read, and G-17 measured it crashing. With a reader each, neither read waits on
     the other; the other pump sees a recorded stop at its next check and leaves, and each
     pump, after its own last read, cancels its own reader on its own queue — G-17's rule,
     no thread cancelling another's reader. Two readers read what one did: the same 150
     frames byte for byte (I010 of the first, middle and last too) and the same 240,000
     frames of sound (`webm_export_proof.py` R1, measured before the change).
  3. **The layout.**
     - The header is EBML with DocType `webm`, DocTypeVersion 4 and DocTypeReadVersion 2. The
       Segment size is written as 8 bytes and patched at finish. A Void reserved after the
       Segment header is overwritten at finish by a SeekHead (Info, Tracks, Chapters when
       present, Cues).
     - Info has TimestampScale 1,000,000, Duration = duration_ns / 1e6, and MuxingApp and
       WritingApp "Frame Job".
     - Track 1 (UID 1) carries `V_AV1` with the `av1C` record as CodecPrivate, DefaultDuration
       round(1e9 · den / num) ns, PixelWidth and PixelHeight, and Colour (the sequence
       header's CICP, Range 1, BitsPerChannel 10). On PQ alone, Colour also carries MaxCLL,
       MaxFALL and MasteringMetadata decoded from `OutputTransform`'s two blobs.
     - Track 2 (UID 2), when the layout has audio, carries `A_OPUS` with OpusHead version 1 as
       CodecPrivate (channels, pre-skip, 48,000, gain 0, mapping family 0), CodecDelay
       round(pre_skip · 1e9 / 48,000) ns, SeekPreRoll 80,000,000 ns, and Audio at 48,000.0 Hz
       with its channel count.
     - Chapters are one EditionEntry (UID 1) holding one ChapterAtom per chapter (UID i + 1,
       start, end), each with a ChapterDisplay (ChapString, ChapLanguage `und`).
     - Block times are round-half-up(pts_ns / 1e6) ms. SimpleBlocks are written in
       nondecreasing time, video first among equal times, with the key flag on video keys and
       on every audio block. A packet with a DiscardPadding above 0 is written as a BlockGroup
       with DiscardPadding.
     - A new Cluster starts before each video key block, and before any block whose relative
       time would pass 32,767 ms. The Cues hold one CuePoint per key-started Cluster
       (CueTime, track 1, CueClusterPosition from the Segment's data) and are written at
       finish.
  4. **Interleave.** The core buffers each track the layout declares. It writes the earliest
     head only while every declared track that has not ended has a head, and `end_track`
     releases that constraint; a layout with one track writes each packet as it arrives. The
     memory bound accepted is the whole Opus track at worst, about 1.4 MB a minute at
     192 kb/s. Back-pressure on the audio pump is not used, because a stalled output starves
     the shared reader (G-17's note).
  5. **Opus.** AudioToolbox (CX-7) at 48 kHz stereo in 20 ms packets. The default is
     192 kb/s, the AAC rows' own number, so the more efficient codec matches or beats AAC at
     the same rate. `audio_bitrate` and the Quality tiers pass through, snapped to the
     converter's `applicableEncodeBitRates`. The pre-skip is `primeInfo.leadingFrames`.
     **The tail:** the encoder's `finish()` feeds pre-skip frames of silence before the end
     of stream, so that packets × 960 ≥ pre-skip + `ExportAudioEnd.target` holds by
     construction. The writer computes padding = packets × 960 − pre-skip − target frames,
     drops whole trailing packets while the padding is 960 or more, and fails the export
     ("The audio could not be encoded to its exact length.") if it is below 0. The last
     packet carries the padding (in ns) as DiscardPadding, so the decoded length is #337's
     exactly. **The sound is placed at its stamps** (fix pass 1): each buffer's rebased
     stamp decides where it goes (`ExportAudioEnd.align`) — zeros for a gap before it (a
     straddling buffer dropped at the range's start, a hole in the stamps), the frames
     already covered cut from its head — so packet k's first frame is the one stamped
     k × 20 ms, the time it is written at. The encoder's FIFO counts a buffer's frames from
     its bytes; bytes that are not whole 16-bit stereo frames fail the export in a sentence.
  6. **Risks accepted:** a second writer to keep in step with `ExportWriter`; no player's HDR
     rendering of WebM was measured; CX-10 holds (no re-import on an M1 or M2); and the
     composition decoded by two readers, not one (the audio reader reads only the audio
     tracks, so the extra cost is their decode). **G-17's starvation is closed for WebM**
     by (2)'s per-output readers: an audio-pump failure, a video-sink failure and a cancel
     while the audio read is held each end within 10 s with no file and both readers
     cancelled by their own pumps (`webm_export_proof.py` F1–F3, `-RCDevWebMFault`); a
     shared reader is named every time only by the readers' log line, F1–F3's timings alone
     catching it only through G-17's crash. It stays accepted on `ExportWriter`'s shared
     reader (G-17), whose same fix is filed as #378.
