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

- **CX-7 — Opus comes from AudioToolbox** (default), not libopus. It sits where AAC does:
  after the mix and the loudness gain (`ExportAudioGain`, `ExporterLoudness`). The writer
  builds OpusHead and CodecDelay itself, the pre-skip taken from the converter's `primeInfo`
  (312 frames measured), because Apple's 28-byte cookie is not OpusHead. AV1 in MP4 keeps AAC.
  **Risk accepted:** Apple's VBR came in under the asked rate (72 kb/s for 128 k on a test
  tone), and libopus (+0.32 MB) is the fallback only if a quality or control gap shows up.

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
     5 s clips (libvpx overshot by 5–7 %). C1 re-measures on a full-length export.

- **CX-10 — On an M1 or M2 the AV1 export still works, but Frame Job cannot preview or
  re-import that file** (default): those Macs have no AV1 decoder, and #216's refusal stands.
  The user guide says so (C1), and playback is a manual check on an M3 or later. **Risk
  accepted:** a user on an M1/M2 exports a file they cannot watch in Frame Job or QuickTime.

- **CX-11 — The working arrangement** (default): the road map is built in the `codecs`
  worktree, each phase gated and merged on its own. C0 adds no export row and no format bump:
  it records these decisions, opens the road map and builds and links the two libraries.
