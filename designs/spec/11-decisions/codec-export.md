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
     **Amended by PUB-10**: SVT-AV1's `vector.c` notice is installed as `vector.c-LICENSE`.

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
  **Amended by CX-16** (C4): `vp9_webm` is Profile 0 8-bit for an SDR picture and Profile 2
  10-bit for HLG and PQ, the WebM `Colour` the only transfer label, with HD-5's HDR10 on PQ.

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
  **Amended by CX-16** (C4): (1)'s neighbour `vp9_webm` follows `av1_webm`, an HDR row with
  `writer` `libvpx` and no speeds; (2)'s `ExportWebMWriter` writes it too, its pump choosing the
  encoder by `writer`; and (3)'s Track 1 is `V_AV1` with its `av1C` or `V_VP9` with no
  CodecPrivate, BitsPerChannel 10 on AV1 and 8 or 10 on VP9 by the picture.
  **Amended by CX-17** (C5): a `V_VP9` track may carry `alpha_mode`: its TrackEntry then has
  `MaxBlockAdditionID` 1 and its Video `AlphaMode` 1, and each video block is a BlockGroup
  {Block, BlockAdditions{BlockMore{BlockAddID 1, BlockAdditional}}, ReferenceBlock on non-keys}.
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
