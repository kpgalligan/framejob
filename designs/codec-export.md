# Road map "codec-export" — AV1 and VP9 export with bundled encoders (#377)

**Opened 2026-10-27** (C0), in the worktree `~/devel/framejob-codecs` on branch `codecs`, from
`75fd806`; each phase is gated and merged into main alone (CX-11). This road map's decisions are
CX-1 onwards, in `designs/spec/11-decisions/codec-export.md`. Its brief is issue #377; the
acknowledgements its licences feed are #376.

## Goal

Frame Job exports H.264, HEVC (8-bit, 10-bit, with alpha), ProRes and still sequences, all
through AVFoundation and VideoToolbox. After this road map it also exports AV1 and VP9, encoded
by two libraries built into the app (SVT-AV1 and libvpx), into MP4 or WebM, with Opus audio in
WebM and alpha in VP9 WebM.

## The owner's choices

**2026-10-27** (the brief, `request.md`; binding; "It is super valuable to me. Bundle the
encoders."):

- **AV1 encoder: SVT-AV1 only** (pinned v4.2.0). There is no libaom.
  - Three speed choices on the export sheet: Faster = preset 8, Balanced = preset 6 (default),
    Smaller file = preset 4.
- **VP9 encoder: libvpx** (pinned v1.17.0), one speed (cpu-used 4, row-mt).
- **Export rows:** all four of these. VP9-in-MP4 is NOT wanted.
  - AV1 in MP4, with AAC audio;
  - AV1 in WebM, with Opus;
  - VP9 in WebM, with Opus;
  - VP9 + alpha in WebM.
- **WebM writer:** a Rust Matroska/WebM writer in `core/`, next to the import reader, not
  libwebm. Writing container bytes is not sample work, under the precedent of #216-R's reader.

Also the owner's, standing: only higher-quality exports matter (2026-10-27); no feature size
budget; memory limits relative to physical RAM; person-only checks go in
`docs/manual-checks.md`.

## The orchestrator's defaults (each one the owner can change)

- **Opus:** macOS AudioToolbox's Opus encoder, not libopus, after the mix and loudness gain
  (CX-7). *The owner can change this.*
- **HDR:** AV1 at 10 bits with HLG/PQ, plus HDR10 mastering metadata, on the AV1 rows; VP9
  Profile 2 HDR later, WebM only, in its own phase (CX-8). *The owner can change this.*
- **Library sources:** pinned tarballs checked by SHA-256, fetched and built by `make codecs`
  and cached by a stamp; no sources vendored into the repo (CX-5). *The owner can change this.*
- **Rate model:** the bitrate semantics kept on every row, the efficiency spent on the picture
  (CX-9). *The owner can change this.*
- **AV1 decode on M1/M2:** the export works there, but Frame Job cannot preview or re-import
  its own AV1 file; the guide says so (CX-10). *The owner can change this.*
- **The encoders platform-side** (CX-4) and **the working arrangement** (CX-11). *The owner can
  change these.*

## How it fits the tree (at `75fd806`)

- **The export table.** `core/src/export_table.rs` (584) holds each row: `id`, `codec`, the
  container, and `avf_preset` (`None` today means the ImageIO still writer). C1 adds a writer
  field for the encoder rows rather than overloading `avf_preset: None`. `export.rs` (259),
  `export_size.rs` (274) and `export_overrides.rs` (295) are the rest of the settings.
- **The writer.** `app/Sources/ExporterWriter.swift` (586) runs an
  `AVAssetReaderVideoCompositionOutput` of 64RGBAHalf frames into a pump on `videoQueue`;
  `ExporterWriter+Settings.swift` (468) holds `defaultVideoBitrate` (0.07 bits/pixel/frame) and
  the Quality tiers; `+Chapters` (248) the chapters. `Exporter.swift` (598) is at the cap, and
  the encoder path goes in new files. The audio pump reads 48 kHz stereo and gains it once
  (`ExporterAudioGain.swift`, `ExporterLoudness.swift`); `ExportAudioEnd.swift` holds #337's
  length rule.
- **The reader the WebM writer mirrors.** `core/src/container*.rs` (seven files, 2,024 lines
  today): EBML, the headers, the blocks, the timing and its grid rule, Vorbis. The writer goes
  in new modules beside them (CX-6).
- **The build.** `make rust` (cargo, then `project.yml`'s "Build Rust Core" pre-build step) is
  the shape `make codecs` copies (CX-5). `tools/proof/gate.py` stamps each Full step by its
  inputs and tool versions; `tools/proof/swift_build.py` is the one probe build line;
  `tools/proof/tree_copy.py` builds old or mutated trees in copies.
- **The bridge.** `app/Bridging/FrameJob-Bridging-Header.h` imports only the core's header
  today. The encoders' headers join it (CX-4); no `rc_*` export wraps them.

## Phases

- **C0 — decisions and the encoder build; CX-1..CX-11.** CX-1..CX-11 recorded in §11 before
  any code, and this road map with the spike's record. `tools/codecs/build_codecs.py` fetches
  SVT-AV1 v4.2.0 and libvpx v1.17.0 as pinned tarballs, checks each by SHA-256, builds them
  arm64, static and encoder-only at the app's deployment target (26.0), and installs headers,
  archives and licence texts into `build/codecs/`, reused by its stamp. `make codecs`; `app`,
  `app-debug`, `typecheck` and `test` depend on it; `project.yml`'s "Build Codecs" pre-build
  step, the header search path, both archives by full path in every configuration's
  `OTHER_LDFLAGS`, and "Copy Codec Licences" into `Contents/Resources/Licenses/`. One Swift
  file, `CodecLibraries.swift`, reads each library's version and opens an SVT-AV1 handle, behind
  `-RCCodecProbe 1`. The gate, the probe builder, the tree copies, the four spikes' own build
  lines and the publish workflow's cmake. **Acceptance:** `make gate` passes; `dist_check`
  41/41 with a stand-in Sparkle key (D36–D41: the encoder symbols in both executables, no load
  command outside the system and Sparkle, the licences byte-identical in both bundles), its
  mutants 34/34; `build_codecs.py --selftest` and its three mutants; tree_copy's T6.
  **Proof:** `tools/proof/codecs_proof.py` (L1–L3) against Release.
- **C1 — AV1 in MP4 (SVT-AV1), 8-bit.** The row (`av1`, MP4, AAC) and its Speed popup
  (Faster / Balanced / Smaller file, CX-2) on the export sheet and in `export`'s MCP mirror;
  a writer field in the export table instead of overloading `avf_preset: None`; the Metal
  conversion from the compositor's 64RGBAHalf to planar I420 (BT.709, video range); a dedicated
  serial encode queue owning the encoder, with progress counted by frames submitted, the
  existing cancel flag checked per frame by the pump and the queue, and the flush before
  `markAsFinished`; the packets into a passthrough `AVAssetWriterInput` with a
  `CMVideoFormatDescription` holding `av1C` (built in the core from the sequence header OBU);
  temporal delimiters stripped; the `ftyp` patched to carry `av01`; the rate model (CX-9) and
  its re-measurement on a full-length export; the guide page with CX-10's sentence.
  **Acceptance and proof:** ffprobe reads `av1`/`av01` with AAC beside it; ffmpeg decodes every
  frame and the count is the range's; `export_offset_proof`'s clicks land; cancel leaves no
  file; a manual-checks row for playback on an M3 or later.
- **C2 — AV1 10-bit and HDR.** The I010 path; HLG/PQ tagged in the sequence header and in
  `colr`; HD-5's `mdcv`/`clli`; `dynamic_range`'s rules on the row as `hevc_10bit` has them
  (CX-8). **Acceptance and proof:** ffprobe reads `yuv420p10le`, the transfer and primaries,
  and the mastering and light-level side data, for HLG, PQ and SDR; the SDR version export.
- **C3 — the WebM writer and Opus.** The core's EBML writer (`rc_webm_*`: open, add a packet,
  finish), with Cues, chapters, the range, the size and #337's audio length; Opus from
  AudioToolbox through a 960-frame FIFO, OpusHead and CodecDelay built from `primeInfo` (CX-7);
  AV1 in WebM. **Acceptance and proof:** core tests that write and re-read through the #216-R
  reader (codecs, `av1C`, colour, OpusHead, timing on the grid rule, chapters); ffmpeg decodes
  the file with zero errors; Frame Job re-imports it on a Mac that decodes AV1.
- **C4 — VP9 (libvpx) in WebM**, 8-bit, then Profile 2 HDR with the container's `Colour` and
  MasteringMetadata (CX-3, CX-8). **Acceptance and proof:** as C3, for `vp9`; Frame Job
  re-imports and previews its own VP9 WebM on any Apple silicon Mac.
- **C5 — VP9 with alpha in WebM.** A second libvpx instance for the alpha plane, frame-aligned,
  as BlockAdditional 1 with `AlphaMode`; G-35's straight alpha and the shape rule.
  **Acceptance and proof:** the libvpx decoder's alpha against the source's (the spike's PSNR
  method); manual-checks rows for Chrome and Firefox.
- **C6 — 4K and memory.** 4K measured on every row; the export queue's limit on concurrent
  encoder jobs, relative to physical RAM; the sheet's time estimate. **Acceptance and proof:**
  the measurements recorded here, and the limit's rule in §11.

## S — the spike

### Record

**Run 2026-10-27, before C0** (no product code, nothing committed), recorded in
`~/.claude/litecode/framejob/codecs-377/S-spike.md` and copied here: the measurements below,
with each instrument's path in this worktree. `tools/proof/work/` is gitignored, so the
instruments and logs stay in the `~/devel/framejob-codecs` worktree and are not in git. The
spike's phase split became the Phases above, and its eight owner questions were answered on
2026-10-27 ("The owner's choices" above, CX-1..CX-3, CX-6) or taken as the orchestrator's
defaults (CX-4, CX-5, CX-7..CX-10).

Date: 2026-10-27. Host: M2 Max (12 cores: 8 P + 4 E), macOS 26.5.1, AC power, Apple clang 17.0.0.
Worktree: `/Users/kevingalligan/devel/framejob-codecs` (branch `codecs`), no product code
touched, nothing committed. Every instrument, log and output is under
`tools/proof/work/codec-spike/` (gitignored):

| Path | What |
|---|---|
| `tools/proof/work/codec-spike/build.sh` | builds one library from pinned source, timed |
| `tools/proof/work/codec-spike/run.py` | one encode: timed with `/usr/bin/time -l`, then VMAF/PSNR/SSIM with ffmpeg's libvmaf |
| `tools/proof/work/codec-spike/batch8.sh`, `tools/proof/work/codec-spike/batch10.sh`, `tools/proof/work/codec-spike/batch-extra.sh` | the sweeps; logs `batch*.log` |
| `tools/proof/work/codec-spike/results.jsonl` (284 runs), `tools/proof/work/codec-spike/analyse.py`, `tools/proof/work/codec-spike/analysis.md` | the raw rows and the tables below |
| `tools/proof/work/codec-spike/probe/size/` | link-size probes (`link.sh`) |
| `tools/proof/work/codec-spike/probe/mux/` | `muxprobe.swift`, `ivfprobe.swift`, `decprobe.swift`, `av1c.py`, `runmux.sh`, `runivf.sh` |
| `tools/proof/work/codec-spike/probe/webm/` | `webmprobe.cc` (libwebm + libopus), `mkalpha.sh`, `runwebm.sh`, `alpha2.sh` |
| `tools/proof/work/codec-spike/probe/opus/opusprobe.swift` | Apple's Opus encoder |
| `tools/proof/work/codec-spike/probe/frames/frameprobe.swift` | frame conversion costs |
| `tools/proof/work/codec-spike/probe/roundtrip/` | a scratch binary over the core's own `container::Container` (#216-R reader) |

**Timing noise.** Another lane (`raster-dither`, a Frame Job Debug at 941 % CPU, then
swift builds) ran throughout: the 1-minute load average read 7–200 across the runs, and
each row records it (`load1_before`). Wall-clock fps from the first sweep is unreliable
(aom good-6 read 3.3–19.4 fps across runs). CPU-seconds per frame is steadier. The speed
table below therefore uses the three runs per config on the real clip at Frame Job's HEVC
rate, two of them repeats taken late, when the load had fallen to 8–50; their spread is
printed. My own rebuilds of the libraries (build-time repeats) overlapped the first sweep,
deleted `aomenc` under three runs (they failed, were re-run in `batch-extra.sh`), and are
part of that sweep's noise. Swift probes here were compiled with plain `swiftc` (they use
no app source; `swift_build.py` is for probes built from `app/Sources`).

### What was measured

#### Test content

150 frames (5 s) of 1080p each, written to y4m so decode cost is out of the timings:

| Clip | Source | Notes |
|---|---|---|
| `real8` | `tools/proof/media/owner-sync/IMG_0018.MOV` (iPhone, HEVC Main 10, 1920×1080 30p, HLG), from 10 s | converted to 8-bit `yuv420p` with no tone map (no zscale in this ffmpeg), so the picture is HLG code values seen as SDR — fine as encoder content |
| `real10` | same frames, `yuv420p10le`, HLG | the 10-bit runs |
| `gh5` | GH5 V-Log L "borough market" 4K 25p, scaled to 1080p (lanczos) | busy street scene; 25 fps, so its rate targets are ×25/30 |
| `promo` | `~/Movies/Frame Job Promo.mp4` from 30 s | graphics: flat dark background, text, a dial |

The reference HEVC rate is Frame Job's own default for the `hevc` row
(`ExporterWriter+Settings.swift` `defaultVideoBitrate`: 0.07 bits/pixel/frame):
1920×1080×30×0.07 = **4,354 kbps** (3,628 kbps for the 25p clip), keyframe at most every
2 s. HEVC was encoded by VideoToolbox through ffmpeg
(`-c:v hevc_videotoolbox -b:v 4354k -g 60 -profile:v main|main10`), the same encoder and
AverageBitRate key the `hevc`/`hevc_10bit` rows use through `AVAssetWriter`, not the same
call.

Encoder command lines (exact strings are in every `results.jsonl` row's `cmd`):

```
aomenc --good|--rt --cpu-used=N --passes=1 --end-usage=vbr --target-bitrate=K --kf-max-dist=60
       --threads=12 --row-mt=1 --tile-columns=1 [--tile-rows=1 for "Nt"] --lag-in-frames=35 (good) | 0 (rt)
       [--bit-depth=10 --input-bit-depth=10] --ivf -o out.ivf in.y4m
SvtAv1EncApp -i in.y4m -b out.ivf --preset N --rc 1 --tbr K --keyint 60 --passes 1 --progress 0
vpxenc --codec=vp9 --good|--rt --cpu-used=N --passes=1 --end-usage=vbr --target-bitrate=K --kf-max-dist=60
       --threads=12 --row-mt=1 --tile-columns=2 --frame-parallel=0
       --lag-in-frames=25 --auto-alt-ref=1 (good) | --lag-in-frames=0 (rt)
       [--profile=2 --bit-depth=10 --input-bit-depth=10] --ivf -o out.ivf in.y4m
quality: ffmpeg -i dist -i ref -lavfi "[0:v]format=F,setpts=PTS-STARTPTS[d];[1:v]format=F,setpts=PTS-STARTPTS[r];
         [d][r]libvmaf=log_fmt=json:n_threads=12:feature=name=psnr|name=float_ssim" -f null -
```

All single-pass VBR (two-pass would mean composing every frame twice). Rates per config:
2,000 / 4,354 / 6,500 kbps targets (HEVC also 3,000 and 9,000; `promo` also 400 and 700),
so VMAF can be read at HEVC's actual rate and HEVC's VMAF can be read off each curve
(linear in log rate, no extrapolation).

### 1. Building the encoders for the app

#### Sources (pinned, shallow clones of release tags)

| Library | Tag | Commit | `git archive` .tar.gz | Files |
|---|---|---|---|---|
| libaom | v3.15.2 | af3dc9aadc793c1b00edc003e3fc19a44fdeb574 | 6,519,272 B | 1,520 |
| SVT-AV1 | v4.2.0 (gitlab.com/AOMediaCodec/SVT-AV1) | 9292ec8e32bce26f781f277ec8739b53426c4300 | 10,963,018 B | 1,292 |
| libvpx | v1.17.0 | 6df3ec34557879fff673706f4a1d9fbd0f3a6f0e | 5,582,889 B | 1,258 |
| libopus | v1.6.1 | 22244de5a79bd1d6d623c32e72bf1954b56235be | 4,744,780 B | 755 |
| libwebm | libwebm-1.0.0.32 | f2a982d748b80586ae53b89a2e6ebbc305848b8c | 487,117 B | 903 |

#### Build commands and tools (`build.sh`)

```
libaom:   cmake -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
            -DBUILD_SHARED_LIBS=OFF -DENABLE_DOCS=0 -DENABLE_TESTS=0 -DENABLE_TESTDATA=0
            -DENABLE_EXAMPLES=0 -DENABLE_TOOLS=0 -DCONFIG_AV1_DECODER=0  && make -j12 aom
SVT-AV1:  cmake ... -DBUILD_DEC=OFF -DBUILD_APPS=ON -DBUILD_TESTING=OFF && make -j12
libvpx:   configure --target=arm64-darwin25-gcc --enable-static --disable-shared --disable-vp8
            --enable-vp9 --enable-vp9-highbitdepth --disable-unit-tests --disable-docs
            --disable-tools [--enable-examples --enable-webm-io --enable-libyuv: only for vpxenc]
          && make -j12
libopus:  cmake ... -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF && make -j12
libwebm:  cmake ... -DENABLE_WEBMTS=OFF -DENABLE_WEBMINFO=OFF -DENABLE_TESTS=OFF
            -DENABLE_SAMPLE_PROGRAMS=OFF && make -j12 webm
```

**No nasm, yasm, meson or ninja** — none is installed on this Mac and all five built.
On arm64 the SIMD is Neon C intrinsics: cmake reported `Found assembler: /usr/bin/cc`
for libaom and SVT-AV1; libvpx's configure printed `enabling neon`, `neon_dotprod`,
`neon_i8mm` (and compiled SVE/SVE2 files, selected at run time); SVT-AV1 at run time
printed `[asm level selected : up to neon_i8mm]`. What is needed: cmake (libaom, SVT-AV1,
opus, libwebm), a POSIX shell for libvpx's configure, and **perl** for libaom
(`Found Perl`) and libvpx's rtcd generator. macOS ships `/usr/bin/perl` 5.34.1
(measured), so Homebrew is needed only for cmake.

#### Build time (clean, configure included, `-j12`, three runs each under load 90–140)

| Library | Seconds (run 1 / 2 / 3) |
|---|---|
| libopus | 9 / 8 / 9 |
| libwebm | 3 / 6 / 4 |
| libvpx | 22 / 19 / 23 |
| SVT-AV1 (with its app) | 16 / 20 / 30 |
| libaom (with decoder and aomenc) | 33 / 51 / 65 |
| libaom encoder only (the app's build) | 39 (one run) |

So all five from scratch take about 1.5–2.2 minutes on this Mac; once built they are a
cached input.

#### Size each adds to a linked binary

`probe/size/link.sh`: a minimal C program per library that opens an encoder and encodes a
few frames (10-bit where the library has it), linked `-O2 -Wl,-dead_strip` against the
static archive, then stripped. Baseline `base` (printf only) = 33,432 B.

| Library | Archive (.a) | Linked, stripped | Added over baseline |
|---|---|---|---|
| libaom (encoder only) | 8,319,816 | 4,948,472 | **+4.91 MB** |
| SVT-AV1 | 5,701,712 | 3,360,504 | **+3.33 MB** |
| libvpx (VP9 only, high bit depth) | 2,692,696 | 1,619,816 | **+1.59 MB** |
| libopus | 693,976 | 353,864 | **+0.32 MB** |
| libwebm (mkvmuxer) | 299,488 | 73,368 | **+0.04 MB** |

For scale, the installed `/Applications/Frame Job.app` binary is 18,736,176 B and the bundle
108 MB (`du -sh`).

#### Licences and patent grants (read from each tree)

| Library | Copyright licence | Patent grant | Third-party code that lands in the archive |
|---|---|---|---|
| libaom | BSD-2-Clause (`LICENSE`, AOM 2016) | **AOM Patent License 1.0** (`PATENTS`): royalty-free; binary distribution must reproduce the licence "in the documentation, legal notices, and/or other written materials"; defensive termination on patent suit | fastfeat (BSD, `fast.c.o`, `fast_9.c.o`), vector (MIT, `vector.c.o`) |
| SVT-AV1 | BSD-3-Clause **Clear** (`LICENSE.md`, which says "NO EXPRESS OR IMPLIED LICENSES TO ANY PARTY'S PATENT RIGHTS ARE GRANTED BY THIS LICENSE") | **AOM Patent License 1.0** (`PATENTS.md`) supplies the patent grant | fastfeat (BSD), safestringlib (MIT) |
| libvpx | BSD-3-Clause (WebM Project) | Google's "Additional IP Rights Grant (Patents)" (`PATENTS`): royalty-free, terminates on suit | none in `libvpx.a` (libyuv/libwebm only in vpxenc) |
| libopus | BSD-3-Clause (Xiph et al., `COPYING`) | royalty-free IETF IPR statements (Xiph, Microsoft, Broadcom; links in `COPYING`) | — |
| libwebm | BSD-3-Clause (Google) | same Google grant as libvpx (`PATENTS.TXT` byte-identical) | — |

All are compatible with Frame Job's Apache-2.0 (commit 94569d0). Each needs its notice (and
AOM's patent licence text for libaom/SVT-AV1) in the acknowledgements (#376).

#### Fit with the Makefile and xcodegen

The shape that matches `make rust` and project.yml's "Build Rust Core" pre-build step:

- `make codecs`: a script (e.g. `tools/codecs/build.sh`) fetches each pinned tarball by URL
  **and SHA-256**, builds it with the lines above (app deployment target 26.0, arm64,
  Release, encoder-only), and installs headers and `.a` into
  `build/codecs/<lib>-<version>-<digest of script+flags>/`, writing a stamp. A matching stamp
  is a no-op, so like cargo it runs every build and costs nothing when cached.
- project.yml: a pre-build script `Build Codecs` (before "Build Rust Core"), `outputFiles`
  the archives; `LIBRARY_SEARCH_PATHS`/`HEADER_SEARCH_PATHS` to the stamp folder;
  `OTHER_LDFLAGS` adds `-laom|-lSvtAv1Enc -lvpx [-lwebm -lc++] [-lopus]`. Swift calls the C
  APIs through the bridging header (these are platform-side calls, not `rc_*`).
- `make test` needs nothing new; `make gate` gets the archives as inputs; the publish
  workflow needs cmake on its runner (not measured here) and network for the tarballs, or a
  cache of them.
- Provenance file per library (URL, tag, commit, SHA-256, flags), as
  `app/Resources/Models/PROVENANCE.md` does for silero.
- `dist_check.py` rows: the encoder symbols are in the binary (`nm`), no codec dylib load
  command, still signed.

### 2. Encode speed and quality on this Mac

#### Quality at Frame Job's HEVC rate (VMAF; full tables with PSNR/SSIM in `analysis.md`)

"Δ VMAF" is VMAF at HEVC's actual bitrate minus HEVC's; "saving" is the bitrate each needs
to reach HEVC's VMAF, against HEVC's.

`real8` (HEVC 4,466 kbps actual, VMAF 91.70, PSNR-Y 42.91):

| Encoder | Preset | Δ VMAF | kbps for HEVC's VMAF | Saving |
|---|---|---|---|---|
| libaom | good-3 | +4.17 | below the lowest point (1,618 kbps → 92.5) | > 64 % |
| libaom | good-4 | +4.13 | below the lowest point (1,605 → 92.3) | > 64 % |
| libaom | good-5 | +3.67 | 1,724 | 61 % |
| libaom | good-6 | +3.57 | 1,798 | 60 % |
| libaom | rt-8 / rt-10 | +1.37 / +1.10 | 3,620 / 3,758 | 19 % / 16 % |
| SVT-AV1 | 4 | +3.36 | 1,888 | 58 % |
| SVT-AV1 | 6 | +3.11 | 2,144 | 52 % |
| SVT-AV1 | 8 | +2.56 | 2,653 | 41 % |
| SVT-AV1 | 10 / 12 | +0.67 / +0.25 | 3,683 / 4,172 | 18 % / 7 % |
| libvpx VP9 | good-1 / 2 / 4 / 5 | +1.45 / +1.42 / +1.28 / +1.57 | 3,488 / 3,500 / 3,605 / 3,419 | 22 / 22 / 19 / 23 % |
| libvpx VP9 | rt-8 | +0.11 | 4,380 | 2 % |

`gh5` (HEVC 3,729 kbps, VMAF 93.25): libaom good-5 +4.96 (49 % saving), good-6 +4.88 (48 %),
good-3/4 +5.85/+5.74; SVT 4 +5.11 (52 %), 6 +4.75 (47 %), 8 +3.18 (33 %), 10 +0.31, 12 −0.92;
VP9 good-1/2/4/5 +3.52/+3.35/+2.92/+2.56 (31/29/26/23 %), rt-8 +0.22.

`real10`, **10-bit** (HEVC Main 10 4,405 kbps, VMAF 92.23): libaom good-4 +3.90, good-5 +3.33
(57 %), good-6 +3.22 (55 %), rt-10 +0.76; SVT 4 +3.15 (56 %), 6 +2.78 (44 %), 8 +2.05 (32 %),
10 +0.60; VP9 profile 2 good-2/4/5 +1.30/+1.05/+1.32 (19/16/20 %), rt-8 −0.27.

`promo` (graphics; HEVC's 4,354 target came out 2,537 kbps, VMAF 97.45, PSNR-Y 58.35): VMAF
saturates on this content, so read the bitrate column. To reach HEVC's 97.45: libaom good-5
367 kbps (86 % less), good-6 456 (82 %); SVT 4 488 (81 %), 6 662 (74 %), 8 964 (62 %), 10
2,094 (17 %); VP9 good-1 1,763 (31 %), good-2 2,013 (21 %), good-4 2,318 (9 %), rt-8 3,030
(19 % MORE). PSNR agrees: SVT 4 at 876 kbps has PSNR-Y 58.9, above HEVC's 58.4 at 2,537.

Worst frame (`vmaf_min`) on `real8` near 3.5–4.5 Mbps: HEVC 77, VP9 good-2 78, SVT 4 88,
SVT 8 86, libaom good-5 92 — libaom's floor is the highest.

Rate accuracy (1-pass VBR, 5 s clips) at the 4,354 target on `real8`: libaom good 3,669–3,816
(−12 to −16 %), SVT 3,415–3,728 (−14 to −22 %), VP9 4,566–4,667 (+5 to +7 %), HEVC 4,466 (+3 %).

#### Speed (`real8` / `real10` at the 4,354 target; three runs each, load at start in brackets)

| Bits | Encoder | Preset | fps per run | CPU-s/frame | Max RSS |
|---|---|---|---|---|---|
| 8 | HEVC VT | — | 224.3 (30), 154.4 (42), 221.8 (13) | 0.001–0.002 | 149 MB |
| 8 | SVT-AV1 | 4 | 39.6 (26), 41.5 (49), 42.1 (12) | 0.220–0.232 | 1,567 MB |
| 8 | SVT-AV1 | 6 | 71.1 (26), 75.4 (42), 75.7 (13) | 0.129–0.131 | 1,149 MB |
| 8 | SVT-AV1 | 8 | 145.6 (24), 147.9 (42), 152.6 (13) | 0.058–0.059 | 1,152 MB |
| 8 | SVT-AV1 | 10 | 276.5 (24), 299.8 (42), 309.7 (13) | 0.022–0.023 | 1,054 MB |
| 8 | SVT-AV1 | 12 | 309.1 (19), 329.0 (42), 336.2 (13) | 0.019–0.020 | 1,011 MB |
| 8 | libaom | good-3 | 2.2 (51), 2.6 (22), 2.7 (10) | 1.322–1.447 | 632 MB |
| 8 | libaom | good-4 | 2.0 (20), 3.7 (36), 3.7 (12) | 0.935–1.049 | 627 MB |
| 8 | libaom | good-5 | 13.2 (22), 13.6 (40), 13.6 (14) | 0.447–0.456 | 526 MB |
| 8 | libaom | good-5, 2×2 tiles | 15.9 (13), 15.2 (11), 14.8 (11) | 0.450–0.482 | 526 MB |
| 8 | libaom | good-6 | 15.6 (26), 16.1 (46), 16.2 (14) | 0.375–0.383 | 495 MB |
| 8 | libaom | good-6, 2×2 tiles | 19.0 (14), 17.9 (11), 18.0 (11) | 0.374–0.402 | 499 MB |
| 8 | libaom | rt-8 | 92.2 (25), 98.9 (46), 99.9 (14) | 0.036–0.038 | 110 MB |
| 8 | libaom | rt-10 | 115.2 (27), 118.4 (49), 120.3 (14) | 0.028–0.029 | 115 MB |
| 8 | VP9 | good-1 | 21.5 (28), 23.3 (13), 23.3 (10) | 0.354–0.369 | 368 MB |
| 8 | VP9 | good-2 | 26.1 (29), 29.2 (13), 29.6 (10) | 0.274–0.290 | 367 MB |
| 8 | VP9 | good-4 | 31.6 (31), 39.6 (12), 39.1 (9) | 0.191–0.205 | 366 MB |
| 8 | VP9 | good-5 | 16.0 (34), 19.4 (13), 19.3 (10) | 0.168–0.175 | 304 MB |
| 8 | VP9 | rt-8 | 271.0 (34), 289.4 (13), 282.8 (10) | 0.016–0.017 | 257 MB |
| 10 | HEVC VT Main 10 | — | 228.3 (38), 145.9 (13), 229.7 (10) | 0.004–0.005 | 236 MB |
| 10 | SVT-AV1 | 4 / 6 / 8 / 10 | 33.8–34.2 / 63.3–64.3 / 114.1–117.1 / 149.8–157.7 | 0.270 / 0.147 / 0.069 / 0.033 | 2,079 / 1,614 / 1,427 / 1,198 MB |
| 10 | libaom | good-4 / 5 / 6 / rt-10 | 3.2 / 11.7–11.8 / 14.4–14.5 / 83.0–84.5 | 1.08 / 0.49 / 0.39 / 0.039 | 1,088 / 915 / 872 / 165 MB |
| 10 | VP9 p2 | good-2 / 4 / 5 / rt-8 | 24.2–24.9 / 31.6–32.0 / 15.7 / 149.9–171.6 | 0.30 / 0.225 / 0.20 / 0.024 | 522 / 522 / 460 / 305 MB |

The 2×2-tile libaom variants matched their 2-column VMAF (good-6t 94.6 at 3,683 kbps vs
good-6 94.6 at 3,679; good-5t 94.7 at 3,680). VP9 good-5 was slower than good-4 in all six
of its runs here (not chased). RSS is the encoder process including its y4m reader.

Derived, not measured: a minute of 1080p30 (1,800 frames) at these fps is ~24 s with SVT 6,
~12 s SVT 8, ~44 s SVT 4, ~1.9 min libaom good-6, ~8 min libaom good-4, ~46 s VP9 good-4.
The export's compositor time is on top; 4K was not measured (4× the pixels).

#### Recommendation (question 2)

**AV1: SVT-AV1.** Plainly, the numbers argue against libaom as the export encoder despite
the natural pull toward AOM's reference (and the owner's brother's team): at every speed an
export sheet would offer, SVT-AV1 gives more quality for the time.
- Matched quality: SVT 4 ≈ libaom good-5/6 (Δ VMAF +3.36 vs +3.67/+3.57 on `real8`, +5.11 vs
  +4.96/+4.88 on `gh5`, +3.15 vs +3.33/+3.22 at 10-bit) at ~41 fps against 13.6–16 fps:
  about 3× faster.
- Matched speed: at ~100–150 fps SVT 8 gives +2.56 against libaom rt-8's +1.37.
- libaom's best (good-3/4, +4.1–4.2 on `real8`) is ~0.8 VMAF above SVT 4 at 2.6–3.7 fps,
  about 11× slower — a 2-minute clip would take ~16 minutes.
- In libaom's favour: a higher worst-frame VMAF (92 vs 88), lower memory (0.5–1.1 GB vs
  1.0–2.1 GB), and it is AOM's reference. SVT-AV1 is also AOMedia's
  (gitlab.com/AOMediaCodec) under the same AOM patent licence.

Presets the sheet should offer for AV1 (SVT-AV1, all 1080p30 on this Mac):

| Row | SVT preset | fps 8-bit / 10-bit | Bitrate for HEVC's quality (real8 / gh5 / real10) |
|---|---|---|---|
| Faster | 8 | ~148 / ~115 | −41 % / −33 % / −32 % |
| Balanced (default) | 6 | ~75 / ~64 | −52 % / −47 % / −44 % |
| Smaller file | 4 | ~41 / ~34 | −58 % / −52 % / −56 % |

Presets 10 and 12 are within 0–0.7 VMAF of HEVC at 2–3× its CPU cost — not worth a row.

**VP9: libvpx** (the only real option), one row at `--good --cpu-used=4 --row-mt=1`
(~39 fps, 16–26 % less bitrate than HEVC for its quality); good-2 buys +0.14–0.43 VMAF for ~35 % more time; rt-8 is
only HEVC's quality. VP9's reason to exist in the sheet is web playback and alpha, not
efficiency: at matched quality it needs ~1.4–1.7× SVT 6's bitrate (good-4: 3,605 vs 2,144; 2,774 vs 1,989; 3,714 vs 2,452 kbps).

### 3. Containers

#### AV1 in MP4 — yes, AVAssetWriter writes precompressed `av01`

`probe/mux/muxprobe.swift` (AVAssetReader passthrough → AVAssetWriter passthrough, `.mp4`),
inputs made by ffmpeg+SVT-AV1 (60 frames 1080p). `rebuilt` = a NEW
`CMVideoFormatDescription` holding only the codec type, size, the `av1C` atom and colour
extensions, each sample re-wrapped onto it:

```
##### av1-8.mp4 o-av1-8-pass.mp4 passthrough mp4
source codec av01 1920x1080 atoms ["av1C", "btrt"]
canAdd(av01 → mp4) = true
appended 60 failed 0 status 2 error nil
stream|codec_name=av1|profile=Main|codec_tag_string=av01|pix_fmt=yuv420p|...|nb_frames=60
ffmpeg decoded frames: 60
##### av1-10-hlg.mp4 o-av1-10-hlg-rebuilt.mp4 rebuilt mp4 hlg
appended 60 failed 0 status 2 error nil
stream|codec_name=av1|...|pix_fmt=yuv420p10le|color_space=bt2020nc|color_transfer=arib-std-b67|color_primaries=bt2020|nb_frames=60
##### av1-10-pq.mp4 o-av1-10-pq-rebuilt.mp4 rebuilt mp4 pq
...|color_transfer=smpte2084|color_primaries=bt2020|nb_frames=60|...Mastering display metadata|red_x=34000/50000|...
   |min_luminance=50/10000|max_luminance=10000000/10000|...Content light level metadata|max_content=1000|max_average=0
```

**The encoder path itself** (`ivfprobe.swift`): packets straight from my built
`aomenc`/`vpxenc` (IVF), an `av1C` built from the encoder's own sequence-header OBU
(`av1c.py`: `81080c00` + OBU, profile 0 level_idx 8) or a `vpcC` built by hand
(`010000000028820101010000`; 10-bit HLG `010000000228a20912090000`), into `.mp4`, with an AAC
track beside it:

```
AV01 1920x1080 30/1 canAdd true / canAdd AAC beside AV01 true
frames 60 sync 1 temporal-delimiters seen 60 stripped status 2 nil
stream|codec_name=av1|codec_tag_string=av01|duration=2.000000|nb_frames=60
stream|codec_name=aac|codec_tag_string=mp4a|duration=2.000000|nb_frames=96
ffmpeg decoded: ivf 60 frames, mp4 60 frames; every frame md5 identical      (each of 5 cases)
```

Findings:
- libaom's `aom_codec_get_global_headers` returns only the sequence-header OBU
  (`av1_get_global_headers`, encoder.c:6075); SVT's `svt_av1_enc_stream_header` likewise. The
  4-byte `av1C` prefix is ours to build — a decision from the encoder's config.
- libaom emits a temporal delimiter OBU in every packet (60 of 60). AV1-ISOBMFF §2.4 says
  TDs "SHOULD NOT be used"; with them kept, ffmpeg still decoded every frame identically,
  but they should be stripped (an OBU-header walk).
- **AVAssetWriter's `ftyp` is `mp42` [`isom mp41 mp42`]** — no `av01`, which AV1-ISOBMFF §2.1
  says the file "SHALL" have among its compatible brands (ffmpeg writes
  `isom av01 iso2 mp41`). A 4-byte in-place rewrite of `mp41` → `av01` after
  `finishWriting` (3 bytes differ) kept the file decoding all 60 frames, with no offsets
  moved. Whether any player rejects the unpatched file was not measured.
- **This M2 cannot decode AV1 at all**: `decprobe` on every AV1 output → status 3, error
  −11833 (decoder not found), as #216 records. VP9 MP4 outputs decode through AVFoundation
  (60 of 60 frames, the supplemental decoder).

#### VP9 in MP4 — yes, the same way

`vp09` with `vpcC` passthrough and rebuilt, 8-bit and Profile 2 HLG, all `canAdd true`,
60/60 appended, ffmpeg decodes 60 frames md5-identical to the IVF, and AVFoundation decodes
60 frames. VP9 in MP4 cannot carry alpha.

#### WebM — libwebm works; recommend a writer in the core

`probe/webm/webmprobe.cc` (libwebm mkvmuxer + libopus) wrote from encoder packets: VP9 +
alpha (BlockAdditional 1) + Opus; AV1 + Opus; AV1 10-bit HLG + Opus; VP9 Profile 2 PQ with
MasteringMetadata, MaxCLL. All four: ffmpeg decode errors 0, video frames decoded 60,
Opus decoded. **Frame Job's own #216-R reader read all four back** (`probe/roundtrip`, the
core's `container::Container`): codecs, `av1C`/`vpcC`, colour codes, `mdcv_hex`/`clli_hex` and
the OpusHead cookie as written. One finding: libwebm by default writes millisecond times and
no DefaultDuration, so the reader saw `nominal_fps 30.303…`; with `set_default_duration`
it saw `30.0000003`, but `grid` stayed false (as it does for ffmpeg's own WebM) — the
writer's timing and the reader's grid rule need checking together.

libwebm vs a muxer in the core:

| | libwebm (C++) | Rust writer in `core/` |
|---|---|---|
| Code | mkvmuxer is 6,981 lines (`wc -l`); +0.04 MB linked; links libc++ | new; the reader it mirrors is 2,140 lines over 8 files |
| Proven | Google's muxer; vpxenc and Chrome tooling use it | round-trip testable in `make test` against the reader, black-box |
| Licence | another BSD notice | none |
| Rule fit | Swift would call C++ through a C shim | `#216-R` already put container BYTES in the core ("the core reads the container … Neither side touches a pixel or a sample") |

Is writing container bytes "sample work"? No. The rule's line, as #216-R drew it, is pixels
and samples: the core already parses EBML, VP9 keyframe headers and Opus TOCs, and
`av1C`/TD stripping are the same OBU-header walk. A WebM writer decides timestamps, cluster
and cue placement, CodecDelay — decisions — and touches compressed packets only as opaque
bytes. Recommendation: **a Rust WebM writer in the core** (`rc_webm_*` handle: open, add
packet, finish), with `av1C` construction and TD stripping beside it, tested by writing
and re-reading through the existing reader. libwebm is the fallback if the owner prefers
Google's muxer. Note spec §7.8's argument against a second writer: chapters, explicit
bitrates and the size must be honoured by the WebM path too (Matroska has Chapters).

### 4. Alpha

`probe/webm/mkalpha.sh`: a transparent 1080p30 2 s source (testsrc2 whose alpha is a moving
opaque disc over a 0–50 % ramp), encoded two ways: ffmpeg
`-c:v libvpx-vp9 -pix_fmt yuva420p` (`ffmpeg-alpha.webm`), and two separate `vpxenc` streams
(colour; alpha as full-range luma) muxed by libwebm as BlockAdditional 1
(`w-vp9-alpha-opus.webm`). Both carry `alpha_mode=1`. Decoded with the libvpx decoder,
alpha against the source's alpha (numpy over all 60 frames):

```
ffmpeg-alpha.webm     frames 60 alpha PSNR mean 72.79 min 47.43 max 138.13 dB; mean abs err 0.02 code values
w-vp9-alpha-opus.webm frames 60 alpha PSNR mean 71.84 min 47.50 max 138.13 dB; mean abs err 0.02 code values
```

ffmpeg's native `vp9` decoder ignores the alpha (`YMIN=255`, opaque); only the libvpx
decoder reads it. libvpx has no alpha encoder of its own: alpha is a second encoder
instance, frame-aligned (same keyframes, no alt-ref mismatch), which is what ffmpeg does.

Browsers, from documentation: Chrome plays WebM alpha since Chrome 31 ("Chrome 31 now
supports video alpha transparency in WebM", developer.chrome.com/blog/alpha-transparency-in-chrome-video,
updated 2013-07-25, VP8 and VP9). Firefox has a WebM alpha reftest fixed for Firefox 53
(bugzilla.mozilla.org/show_bug.cgi?id=1331528) — evidence it renders alpha, not a
changelog. Safari plays WebM (caniuse.com/webm: supported 16.0+, iOS 17.4+) but the only
sources found for "no alpha in Safari" are secondary (rotato.app's guide, a caniuse-derived
table); not established from a primary source. HEVC with alpha remains Safari's route
(Frame Job's `hevc_alpha`). A person should confirm with one file in each browser.

**AV1 alpha does not exist in practice**: libaom's `aom_image.h` says
"0x400 used to signal alpha channel, skipping for backwards compatibility"; neither libaom's
nor SVT-AV1's API has an alpha input; the Matroska AV1 mapping
(ietf-wg-cellar codec/av1.md) defines no alpha or BlockAdditional use. (AVIF's alpha is a
still-image auxiliary item, not video.)

### 5. Audio

**macOS encodes Opus itself** (`probe/opus/opusprobe.swift`):

```
AVAudioConverter Opus asked 64000 b/s: ... 251 packets, 42046 b/s measured, cookie 28 bytes ..., primeInfo leading 312 trailing 648
AVAudioConverter Opus asked 128000 b/s: ... 251 packets, 72281 b/s measured ...
AVAudioConverter Opus asked 192000 b/s: ... 251 packets, 118240 b/s measured ...
AVAssetWriter Opus into .mp4: canAdd true / .mov: canAdd true / .m4a: canAdd false
```

(`afconvert -d opus` also wrote a valid Opus CAF.) Packets are 960 frames (20 ms) and the
lead is 312 samples — the same pre-skip libopus 1.6.1 reported in `webmprobe` — so a WebM
writer builds OpusHead (pre-skip 312, 48 kHz) and CodecDelay itself; Apple's 28-byte cookie
is not OpusHead. Apple's VBR came in under the asked rate on this test tone (72 kb/s for
128 k).

Either encoder slots in after the mix exactly as AAC does: the export's audio pump already
reads 48 kHz stereo — 16-bit, or float then gained and quantised once
(`ExportAudioGain`) — so loudness normalisation (`ExporterLoudness`'s measurement pass and
the gain) is unchanged; only the last step changes from an AAC `AVAssetWriterInput` to
packets for the WebM writer, through a 960-frame FIFO, with the range-end rule (#337)
applied before it. Recommendation: **AudioToolbox's Opus (no libopus)**, libopus
(+0.32 MB) only if a quality or control gap shows up. **AV1 in MP4 keeps AAC** — measured
beside `av01` above.

### 6. The frame path

Today (`ExporterWriter.swift`): `AVAssetReaderVideoCompositionOutput` hands 64RGBAHalf
frames to a pump on `videoQueue` inside `requestMediaDataWhenReady`; `ExportFrames`
converts per row (an 8-bit round in a pooled 32BGRA buffer for `h264`/`hevc`), and the
frame is appended to an `AVAssetWriterInput`.

Conversion costs per 1080p frame (`probe/frames/frameprobe.swift`, 200 iterations, run under
load ~118):

| Path | Median | p10 / p90 |
|---|---|---|
| A1 vImage 64RGBAHalf → 8-bit RGBA | 1.065 ms | 0.592 / 2.023 |
| A2 vImage BGRA8 → I420 planar, BT.709 video range | 0.175 ms (0.544 in the first run) | 0.129 / 0.503 |
| B1 VTPixelTransferSession → NV12 (420v) | 0.446 ms | 0.355 / 1.907 |
| B2 VTPixelTransferSession → I420 planar (y420) | 1.833 ms | 1.603 / 3.079 |
| B3 VTPixelTransferSession → 10-bit biplanar (x420) | 0.409 ms | 0.346 / 1.088 |
| B4 CPU x420 → I010 (shift + deinterleave, 8 threads) | 0.278 ms | 0.146 / 0.528 |
| C1 Metal compute RGBA16F → I420, commit+wait (GPU 0.065 ms) | 1.208 ms | 0.491 / 3.651 |
| C2 Metal compute RGBA16F → I010, commit+wait (GPU 0.069 ms) | 0.844 ms | 0.394 / 2.571 |

Check: the Metal I420 luma against vImage's: max |diff| 1, mean 0.159 code values.

Every path costs ≤ ~2 ms against ~6.8 ms (SVT 8, 148 fps) to ~24 ms (SVT 4, 41 fps) of encode per frame, so
conversion is not the bottleneck. libaom and libvpx take NV12 directly
(`AOM_IMG_FMT_NV12`, `VPX_IMG_FMT_NV12`, checked in `av1_cx_iface.c`/`vp9_cx_iface.c`); 10-bit
needs planar 16-bit (`*_I42016`), as does SVT-AV1 for both depths. Recommendation: **one
Metal compute pass** (the compositor already owns a device; output straight into planar
buffers the encoder reads, BT.709 or BT.2020 matrix, video range), with
VTPixelTransferSession as the no-shader alternative.

Queue, progress, cancel: keep the reader/pump structure; the video pump converts and hands
each frame to a **dedicated serial encode queue** owning the encoder (libaom/libvpx encode
synchronously with internal lag; SVT is send/receive with its own threads). Encoded packets
go to the passthrough `AVAssetWriterInput` (MP4) or the WebM writer. Progress: frames
submitted (the encoder's lag, 25–35 frames, is under a second at 30 fps); a final flush
(`encode(NULL)` / SVT EOS) before `markAsFinished`. Cancel: the existing flag, checked per
frame by both pump and encode queue, then the encoder destroyed after `allInputsFinished`,
as G3c requires for the reader. Back-pressure is natural: the pump's
`isReadyForMoreMediaData` loop blocks on a bounded queue to the encoder.

Memory: one compositor frame is 16,588,800 B; I420 3,110,400 B; I010 6,220,800 B. Encoder
RSS measured above: SVT-AV1 1.0–2.1 GB at 1080p (most at preset 4 and 10-bit), libaom
0.5–1.1 GB, libvpx 0.3–0.5 GB. SVT's thread/buffer count follows `--lp`; 4K will be larger
(not measured).

### 7. HDR

| | HEVC rows today | AV1 | VP9 |
|---|---|---|---|
| Profile | Main 10 | Main (profile 0), 10-bit | Profile 2 |
| Colour in the bitstream | VUI | sequence header `color_config`: `AV1E_SET_COLOR_PRIMARIES/TRANSFER_CHARACTERISTICS/MATRIX_COEFFICIENTS` (libaom), `color_primaries`/`transfer_characteristics` in SVT's config — measured: aomenc `--transfer-characteristics=hlg` gave an MP4 ffprobe reads as `arib-std-b67` with no container tags | only `color_space` (BT.709/BT.2020…, `VP9E_SET_COLOR_SPACE`), **no transfer** — HLG/PQ must come from the container |
| MP4 tags | `colr` from `AVVideoColorPropertiesKey` | `colr` from the description's extensions — measured HLG and PQ | `vpcC` carries primaries/transfer/matrix — measured HLG |
| HDR10 metadata (HD-5's fixed values) | VT compression keys | `mdcv`/`clli` boxes from `MasteringDisplayColorVolume`/`ContentLightLevelInfo` extensions — measured written and read back; in-band metadata OBUs available (`aom_img_add_metadata` with `OBU_METADATA_TYPE_HDR_MDCV/CLL`, SVT `mastering_display`/`content_light_level`), not exercised; AV1-ISOBMFF says the boxes SHOULD be present and SHALL equal the OBUs | MP4 boxes as for AV1; WebM `Colour/MasteringMetadata` + `MaxCLL`/`MaxFALL` — measured with libwebm and read back by the core |
| WebM tags | — | `Colour` element — measured HLG | `Colour` element — measured PQ |

So the new 10-bit rows can take `hevc_10bit`'s place in H-3's rules (`"hdr": true`,
`dynamic_range` hlg/pq/sdr), with the tags written in both the bitstream (AV1) and the
container. No Dolby Vision question arises. Not measured: any player's HDR rendering of
these files.

### Risks

1. **Speed.** Software AV1 is 1.5–5.4× (SVT 8–4) slower than VideoToolbox HEVC per 1080p frame
   here (148–41 fps against ~222) and needs 1.0–2.1 GB; 4K is untested and will be ~4× the work. The sheet must say
   so (an estimate), and the Export Queue must not run two SVT jobs at once on a 16 GB Mac
   without measuring it.
2. **No AV1 decode on M1/M2**: Frame Job cannot preview or re-import its own AV1 export
   there (#216 refuses it), QuickTime won't play it, and proofs must check AV1 output with
   ffmpeg/dav1d. Only an M3+ can confirm playback (a manual-checks row).
3. **`av01` brand missing** from AVAssetWriter's `ftyp`; the in-place patch is a small byte
   rewrite after `finishWriting` that has to be right on every file (moov-first too).
4. **Rate accuracy**: 1-pass VBR undershot by up to 22 % on 5 s clips; an explicit
   `video_bitrate` will not be met exactly, and the "encoder decides" default needs an AV1
   rule (HEVC's 0.07 bpp is ~2× what SVT 6 needs for the same VMAF here).
5. **WebM is a second writer**, against §7.8's one-writer argument: chapters, range, size,
   the #337 audio length rule and graphic failures must hold there too.
6. **Alpha**: only Chrome/Firefox (Safari unconfirmed), ffmpeg's default VP9 decoder drops
   it, and Frame Job's own import drops VP9 alpha (#216-R) — an alpha WebM cannot come back
   in with its alpha.
7. **Build**: cmake on every build machine and the publish runner (runner not measured);
   perl from the OS; ~2 min clean build; network or a tarball cache for the sources.
8. **Licence duties**: BSD notices and the AOM patent licence text in the acknowledgements
   (#376); the AOM and Google grants terminate for a party that sues.
9. **VMAF caveats**: VMAF is not calibrated for HLG code values (`real8`/`real10`) and
   saturates on graphics (`promo`); clips are 5 s; HEVC was driven through ffmpeg rather than
   AVAssetWriter.
10. **WebM timing**: libwebm's default millisecond times and the reader's grid rule
    disagreed (grid false even with DefaultDuration, as for ffmpeg's WebM).

## C0 — decisions and the encoder build

### Record

**Built 2026-10-27** in `~/devel/framejob-codecs` (branch `codecs`, from `75fd806`), not yet
committed or merged.

**Decisions first.** CX-1..CX-11 in `designs/spec/11-decisions/codec-export.md` (new), with
its file row and eleven "Every decision" rows in `11-decisions/README.md` and the folder's
cell in `designs/spec/README.md` (13734 in 33 files); `spec_index_proof.py` 210/210. Then
this road map, with the spike's record, before any code.

**What landed.**
- `tools/codecs/build_codecs.py` (new): `PINS`, `find_cmake()`, `build_env()`,
  `tool_versions()`, `key()`, `verdict()`, `check_download()`; the install in
  `build/codecs/` (`include/`, `lib/libSvtAv1Enc.a`, `lib/libvpx.a`, `licenses/`,
  `stamp.json`), the tarballs in `build/codecs-downloads/`, an `fcntl` lock at
  `build/codecs.lock`; `--selftest` (K0–K2, R0–R3, S0, S1, P1, C1, C2) and three mutants.
  `tools/codecs/PROVENANCE.md` (new) records each pin.
- The pins, read from the downloaded tarballs: SVT-AV1 v4.2.0 SHA-256
  `c7b13c4a84bd3751aa35fcc72be13e6875467e7c2216879251a486e5b1e4e740` (11,070,537 bytes),
  `git get-tar-commit-id` `9292ec8e32bce26f781f277ec8739b53426c4300`; libvpx v1.17.0 SHA-256
  `1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a` (5,670,546 bytes),
  commit `6df3ec34557879fff673706f4a1d9fbd0f3a6f0e`. Both commits equal the spike's.
- `Makefile`: `codecs`; `app`, `app-debug`, `typecheck` and `test` depend on it;
  `typecheck`'s `-Xcc -Ibuild/codecs/include`; `test` runs `build_codecs.py --selftest`.
- `project.yml`: the "Build Codecs" pre-build step (first), `HEADER_SEARCH_PATHS`, both
  archives by full path in base, Debug and Release `OTHER_LDFLAGS`, and "Copy Codec
  Licences" into `Contents/Resources/Licenses/` (before "Build Agent Helper").
- The bridging header includes `<svt-av1/EbSvtAv1Enc.h>`, `<vpx/vpx_encoder.h>` and
  `<vpx/vp8cx.h>`. `app/Sources/CodecLibraries.swift` (new, 53 lines): the version reads,
  `openSVTAV1Handle()` and `probeIfAsked()`; `main.swift` calls it straight after
  `DecoderSupport.enable()`.
- `tools/proof/`: `swift_build.py` (the codec flags in the line and `typecheck`, the
  archives and stamp in the key, the `make codecs` refusal, K1's two new entries);
  `gate.py` (`tools/codecs` among typecheck's and app's inputs, `cmake --version`,
  typecheck's bound 600 s, selftest M8); `proof_app.py` (`LISTED`); `tree_copy.py`
  (`build/codecs` linked to the tree's, T6, T1's `tools`); `dist_check.py` D36–D41 (41
  rows); `dist_check_mutants.py` (`Licenses/` in the skeleton, four new cases, 34);
  `codecs_proof.py` (new, L1–L3); the four closed spikes' own swiftc lines append
  `swift_build.codec_args()`; `README.md`.
- `.github/workflows/publish.yml`: the Toolchain step installs cmake when the runner
  lacks it and prints `cmake --version`. `docs/developing.md`: cmake, the first fetch,
  `make codecs` and the changed targets, the layout, the runner.

**Commands run and what they printed** (load 7–23 on a shared machine).
- `build_codecs.py` cold: `codecs: built da6fd6aa… in 30 s`; again: `codecs: reused
  da6fd6aa…`; under `env -i HOME=… PATH=/usr/bin:/bin:/usr/sbin:/sbin`: `reused`, the
  same key.
- `otool -l` on each archive: only `minos 26.0` (235 members in `libSvtAv1Enc.a`, 178 in
  `libvpx.a`). The Release link log's four "built for newer 'macOS' version (26.2)"
  warnings are all `libframejob_core.a`'s QuickJS objects, as before this change; none
  names a codec archive. Nothing links a codec dylib (D38/D39).
- `build_codecs.py --selftest` 12/12; mutants `key-no-tools` failed {K1},
  `reuse-unchecked` {R1, R2}, `sha-unchecked` {S1}, each exactly.
- `make typecheck`: exit 0, the four baseline warnings, `tsc` clean.
- `swift_build.py --selftest` 10/10, `gate.py --selftest` 34/34 (its four mutants each
  exact), `proof_app.py --selftest` 15/15, `tree_copy.py --selftest` 6/6,
  `spec_index_proof.py` 210/210.
- Hand mutants, each reverted: `tools/codecs` out of gate's typecheck inputs failed M8;
  the archives and stamp out of `_key_files` failed K1 ("unchanged: an encoder archive's
  bytes, the encoders' stamp"); `make_copy`'s symlink removed failed T6.
- `make app-debug`, then `codecs_proof.py` 3/3 (Debug).
- `make gate`: names, typecheck, fmt, lint, test (207 s), app (124 s), `gate: PASS 364s`.
- `make dist`: `dist_check: 40/41` (D31) and `published_check: 20/21` (P20), the owner's
  missing key (PUB-8). D36–D41 passed.
- `make app` and the stand-in-key Distribution build: `dist_check: 41/41`;
  `dist_check_mutants.py` 34/34, `codec-stripped-release` {D36}, `codec-dylib-release`
  {D38}, `licence-missing-dist` {D41}, `licence-changed-release` {D40}.
- `RC_PROOF_APP=release python3 tools/proof/codecs_proof.py`: 3/3 — `svt-av1 v4.2.0`,
  `libvpx v1.17.0 (WebM Project VP9 Encoder v1.17.0)`.

**Found.** `libSvtAv1Enc.a` holds `vector.c.o` (`Source/Lib/Codec/vector.c`, MIT, Peter
Goldsborough), whose notice is only in the source's header, so no shipped text carries it;
the acknowledgements (#376) must reproduce it. safestringlib, whose licence ships as
pinned, is not compiled on macOS (no `*_s.c.o` member). The SVT handle prints its banner
on stderr (`Svt[info]: …`) at `svt_av1_enc_init_handle`; C1 decides whether to route it
through `svt_av1_set_log_callback`.

**CLAUDE.md edits owed** (the integrator's):
- root Commands: a `make codecs` line; cmake (`brew install cmake`), the system perl
  and the first fetch's network as prerequisites of `make app`, `make app-debug`,
  `make typecheck` and `make test` ("needs cmake"); `make typecheck`'s
  `-Xcc -Ibuild/codecs/include` and its `codecs` prerequisite; `make test`'s
  `tools/codecs/build_codecs.py --selftest`; the `make gate` line's typecheck step
  building the codecs and its `cmake --version` fingerprint;
- root file map: `tools/codecs/` (`build_codecs.py`, `PROVENANCE.md`) and `build/codecs/`
  (the installed encoders, never committed);
- root Architecture: the encoders are platform-side (CX-4) — Swift calls SVT-AV1 and
  libvpx through the bridging header, no `rc_*` wraps them, and "no ffmpeg dependency"
  stands;
- `app/CLAUDE.md`: `CodecLibraries.swift` in the file map, and `main.swift`'s wiring
  (`CodecLibraries.probeIfAsked()` after `DecoderSupport.enable()`).

**Owed to later phases.** C1–C6 above; the acknowledgements file (#376), which lists
`Contents/Resources/Licenses/` and `vector.c`'s notice; a `published_check.py` row for
the codecs and an actions cache for `build/codecs` (neither in C0).
