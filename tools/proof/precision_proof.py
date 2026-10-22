#!/usr/bin/env python3
"""The precision road map (issue batch B94; spec §11 PR-1..PR-5,
`designs/adr/precision.md`, the phase records `archive/precision.md`) — the
16-bit-float compositor and its exports, over
MCP. Written in PR0, before any product edit, so PR1's controls are captured
on PR0's product.

    python3 tools/proof/precision_proof.py [--app PATH] [--only C0,D1,D2,P1,H1,R1,R2,C1,T1,T2,S1,S2,S4,...,S8,S10,S14,S15,S16,V0,...,V6] [--control DIR]
    python3 tools/proof/precision_proof.py reverse-cost          # no app; the reverse's cost
    python3 tools/proof/precision_proof.py capture DIR          # the CONTROL tree
    python3 tools/proof/precision_proof.py compare DIR [--only K1,...,E2,S3,S11]
    python3 tools/proof/precision_proof.py --measure capture|compare DIR   # release-only
    python3 tools/proof/precision_proof.py --measure ab --mutant decode-8bit [--rounds N]  # release-only
    python3 tools/proof/precision_proof.py --mutant NAME [compare DIR]
    python3 tools/proof/precision_proof.py --selftest           # no app

`matte_proof.py`'s shape: it launches the app `proof_app` picks (Debug unless
`RC_PROOF_APP=release`; `--measure` is release-only) on a scratch socket of its
own and stops only that process. The app must be a product of a TREE — a
`build/Build/Products/…` under a folder holding `app/Sources/Compositor.swift`
(this tree, or a mutant's copy) — because `capture` records, and `compare`
and D2 read, the pixel formats of the SOURCES the driven app was built from
(`app_tree`); `--app PATH` or `RC_PROOF_APP` naming an app outside any tree is
refused (exit 2), never read against this tree's formats. The instance runs in a scratch home,
`CFFIXED_USER_HOME=tools/proof/work/precision/run/home`; every package, PNG
and movie of a run is under `tools/proof/work/precision/run/`, removed at the
start and at exit. DIR (a capture) is kept. No menu item is performed, no
default is written: `--measure` passes `-FrameJobCompositorTiming YES` as a
launch argument. Every call is bounded (`CALL_BOUND`), every ffmpeg too.

The ffmpeg fixtures, made once under `tools/proof/work/precision/media/`:
the spike's 10-bit ProRes 422 HQ ramp (`make_media.sh`'s RAMP line, every
10-bit code 64..940 across 1920 px, 1 s), a 640×360 1 s H.264 `testsrc2`
(copied into DIR by `capture`, so `compare` reads the same bytes) and 2 s
ProRes 422 `testsrc2` movies at 1080p and 2160p (M1's); and the stills
(precision-2 P2-1, the brief's make_media.sh lines): `ramp16.png` (`rgb48be`)
and `ramp16.tif` (`rgb48le`), 1920×1080, every column X at X/1919 of full
scale in all three channels; `ramp8.png`, the same ramp `rgb24`; and two
640×360 8-bit `testsrc2` stills, `still8.png` (`rgb24`) and `still8a.png`
(`rgba`, alpha X·255/639), copied into DIR by `capture`. The reverse's
(precision-2 P2-2), each made only when a row needing it runs and kept only
when ffprobe reads what it should (a refusal is that row's FAIL, naming it):
`ramp10_odd.mov` (the RAMP at 1919×1079, ProRes 422 HQ), `ramp10_hlg.mov`
(the ramp `yuv420p10le` tagged HLG BT.2020, `hevc_videotoolbox` Main 10),
`chroma10_hlg.mov` (the same with Cb rising and Cr falling across the
width, `CHROMA`) and `prores422_odd.mov` (`testsrc2` 1919×1079 2 s, through
`format=yuv444p10le`, which keeps the odd size; `reverse-cost` only). The
bt709 movies of five makers (the H.264 clip, the ramp, `prores_clip`'s two
heights and the two odd ones; issue batch B98, #290) are made through
`tagged`: TAG on the output and `SETPARAMS` on the lavfi input (given to the
output alone, ffmpeg wrote `colorspace` and left primaries and transfer
`unknown`), each kept only when ffprobe reads bt709 ×3 with its codec, pix_fmt and size and
`read_back` holds — its first frame against its own lavfi graph rendered raw,
mean |Δ| ≤ READBACK_MEAN 8-bit levels on each of Y, Cb and Cr. A refused
file, a stale cached one included, is removed and made once more; a second
refusal of the clip or the ramp is the preflight's exit 2, naming it.

The scenes, on a 640×360, 30 fps canvas, black background, read at 0.5 s
(K4 at 1.25 s), after the spike's S1–S5:
  K1 a full card (0.2, 0.6, 0.9); K2 K1 and a title; K3 K1, a full
  black→white gradient at 50 %, the title and a yellow `multiply` overlay;
  K4 red then green full cards nested, the nest clip split at 1 s and a
  0.5 s linear `cross_dissolve` made from the first half's tail (a ROUTED
  dissolve, spec §11 MT-8), mid-way; K5 six layers (K3's four, a red ellipse
  at 60 % and a blue `screen` rectangle at 80 %); K6 the H.264 clip alone.

Rows (`ID ok|FAIL — detail`, then `n/m`; exit 0 iff every scored row passes):
  C0  two renders of K3 are byte-equal.
  D1  `render_frame` of an all-8-bit project (K1's card and the H.264 clip)
      is an 8-bit PNG (spec §11 PR-4).
  P1  a full-canvas black→white gradient at opacity 0.5 over black,
      1920×1080, exported `prores_422`: the middle row's luma (ffmpeg
      `gray16le`, columns 16…W−16) against 0.5·g/255, g the gradient's 8-bit
      value from `render_frame` at opacity 1, RMS ≤ 1.0 10-bit steps. An 8-bit
      canvas measures about 1.4 or more; `capture` records the control's.
  H1  an `hevc` export of K6's clip: ffprobe `profile` Main, `pix_fmt` yuv420p.
  D2  (PR2; a STOP, spec §11 PR-4) D1's project, every source now decoded
      `64RGBAHalf`: its `render_frame` is still an 8-bit PNG.
  R1  (PR2) `render_frame` of the 10-bit ramp on a 1920×1080 canvas is a
      16-bit PNG whose middle row's green holds ≥ 850 distinct values; with
      `--control DIR` the control's (decoded 32BGRA) must hold ≤ 256; a capture
      whose tree decoded deep (`ctl-p21`) is printed, not held to it.
  R2  (PR2) the ramp through `prores_422`: the middle row's luma against
      x/1919 is ≤ 1.0 10-bit steps RMS (`--control DIR` prints the control's).
  C1  (PR2) the H.264 clip at `video.color.brightness` −0.4: every colour
      channel within ±2 of max(0, its brightness-0 render − 102) — a deep
      frame arrives unclamped, and `layerSample`'s `saturate` bounds it.
  T1  (PR3) the 10-bit ramp exported `hevc_10bit`: ffprobe says `hevc`,
      profile `Main 10`, `yuv420p10le`, and an MP4 (major brand `mp42`, not
      QuickTime's `qt  `).
  T2  (PR3) the same ramp's middle-row luma against x/1919: `hevc_10bit` is
      ≤ 2.0 10-bit steps RMS and ≤ ½ of an `hevc` export's RMS of the same
      project in the same run; and its encoder was handed DEEP frames: the
      8-bit staircase's tone (`staircase_tone`: each column's mean code over
      the frame's rows, less a 31-column moving average, at 255 steps across
      the width) is ≤ 0.1 codes, where the `hevc` file's — 8-bit, the control
      that the instrument sees a staircase — is ≥ 0.3. Main 10 handed 8-bit
      frames passes the RMS halves (1.794 against 1.459) but not the tone.
  S1  (precision-2 P2-1, spec §11 PR-6) `ramp16.png` alone on a 1920×1080
      canvas (imported, placed at 0, trimmed to 1 s), exported `prores_422`:
      the middle row's distinct 10-bit Y codes (columns 16…W−16) ≥ 800, its
      luma RMS against x/1919 under the in-run 8-bit control's (`ramp8.png`,
      the same project), its staircase tone ≤ TONE_MAX where the control's is
      ≥ TONE_SEEN (the instrument sees a staircase). With `--control DIR` it
      prints DIR's `stills.png16` figures and requires their distinct < 800
      (the instrument tells the old draw from the new) — unless DIR holds Sd
      (captured by B97's instrument, after PR-6, so drawn deep): printed then,
      not held, as R1 treats a deep-decoded control.
  S2  (P2-1) the same with `ramp16.tif`, against the same 8-bit control
      (computed once) and DIR's `stills.tif16`.
  S4  (issue batch B97, spec §11 PR-9; P2-1 read 8-bit here, PR-6) S1's
      `render_frame` PNGs: `ramp16.png`'s is a 16-bit PNG whose middle row's
      green holds ≥ MIXED_DISTINCT distinct values (`rgb48le`), and whose RGB
      scaled to 8 bits (round(v/257)) is within ±1 a channel of the `--control`
      tree's 8-bit `still-png16.png` (mean and max |Δ| printed; no control is a
      FAIL), and its `sips -g profile` equals `ramp8.png`'s (the generator's,
      same run); `ramp8.png`'s is an 8-bit PNG.
  S5  (B97, PR-9; P2-1's fix pass read 8-bit) `ramp16.png` on a track above
      the H.264 clip on a 1920×1080 canvas, covering it: `render_frame` is a
      16-bit PNG, green ≥ MIXED_DISTINCT, within ±1 of the control tree's
      `mixed-h264.png` the same way.
  S6  (P2-1's fix pass) the same over the 10-bit ramp clip: a 16-bit PNG
      whose middle row's green — the still's, which covers the frame — holds
      ≥ MIXED_DISTINCT (850) distinct values (the deep draw reaches a 16-bit
      frame; drawn 8-bit it holds 256).
  S7  (P2-1's fix pass) S1 with `ramp10.heic`: `ramp16.png` drawn at 16-bit
      float and written by ImageIO's HEIC writer (`heic10_writer.swift`, through
      `swift_build.build`), refused as a fixture unless ffprobe reads HEVC
      Main 10 `yuv420p10le` and its middle row holds ≥ 800 distinct 10-bit Y
      codes. ImageIO decodes it at 10 bits a component, so it is drawn deep.
  S8  (B97, PR-9) `ramp16.png` at 0–1 s then the H.264 clip at 1–2 s on one
      track, rendered at 1.5 s (the still not on the frame): an 8-bit PNG
      byte-identical to the same frame after the still is deleted (the clip
      left at 1 s), so a deep still elsewhere in the project changes nothing.
  S10 (B97, recorded) `render_frame format: heic` of `ramp16.png` alone;
      `sips -g bitsPerSample` printed; scored only on the file being written.
  S14 (B97, PR-9) the H.264 clip on track 1 at 0 at `set_video` scale 3 (it
      sits at native size, §5.3, so it fills the canvas only so) and
      `ramp16.png` above it at scale 0.5, on a 1920×1080 canvas: `render_frame` at T and
      T+1/60 s (off the 30 fps grid), then the still deleted and rendered at
      T, T+1/60 and T+1/30. Each deep render is a 16-bit PNG whose OUTER
      columns (0–399 and 1520–1919, every row), scaled to 8 bits, are within
      ±1 of the still-less render at the same time — the reader reads the
      generator's frame time. Fixture guard: the still-less renders at T and
      T+1/30 differ in those columns.
  S15 (B97, PR-9) the same scene over `ramp10_hlg.mov` (a converting
      composition, spec §11 GR-15), at T, then the still deleted, at T: both
      16-bit PNGs, their `sips -g profile` equal (the reader's space is the
      generator's), the outer columns within ±1 at 8-bit scaling. A refused
      HLG fixture is a FAIL.
  S16 (B97, PR-9) `render_frame max_width 960` of `ramp16.png` alone on a
      1920×1080 canvas: a 960×540 16-bit PNG whose middle row holds > 256
      distinct greens (the reader scales, keeping depth).
  V0  (precision-2 P2-2, spec §11 PR-7) the real renderer (`reverse_probe.swift`,
      built through `swift_build.build` with this tree's — or a mutant copy's
      — `app/Sources`; a probe that will not build is a FAIL) reverses the
      10-bit ramp: ffprobe hevc, Main 10, yuv420p10le, 1920×1080; the first
      frame's middle row ≥ 800 distinct 10-bit Y codes at < 1.0 code RMS
      against 64 + x·876/1919; `source_mirror_probe.py` §3's stamps (as many
      frames as the source, the first at 0, ascending, drift ≤ 1).
  V1  (P2-2, MCP) the ramp clip reversed (`set_reversed`, then the wait: the
      `cache/reversed/<media>-*.mov` with no `.partial` and no sheet, bounded
      by REVERSE_BOUND) and exported `prores_422`: luma RMS ≤ the forward
      clip's (R2's, or V1's own) + V1_MARGIN, ≥ 800 distinct 10-bit Y codes.
  V2  (P2-2) the HLG ramp reversed by the probe keeps arib-std-b67/bt2020/
      bt2020nc, its middle row's Y, Cb, Cr within mean |Δ| ≤ V2_BOUND codes of
      the source's; stamps as V0.
  V3  (P2-2, MCP) the HLG chroma ramp forward at 0 and reversed at 1 s:
      `render_frame` at 0.5 s and 1.5 s, middle rows (`rgb48le`) within mean
      |Δ| ≤ V3_BOUND 8-bit levels (0.25, set from the measurement; the old
      renderer read 0.764 — its picture was right, rounded to 8 bits).
  V4  (P2-2, MCP) a reverse planted under the pre-version digest's name is
      not used and is pruned: the `…|v<rendererVersion>` name (read from the
      driven tree's `ReverseCache.swift`) exists, the planted file is
      gone, and `render_frame` holds ≥ 850 distinct green (the ramp).
  V5  (P2-2) the 1919×1079 ramp reversed by the probe: prores, yuv422p10le,
      exactly 1919×1079 (ffprobe and the natural size); stamps as V0.
  V6  (P2-2; PR-4 as amended by PR-7, the owner 2026-10-11) the 8-bit H.264
      clip alone, reversed: `render_frame` is a 16-bit PNG and the reverse
      hevc Main 10 (the old renderer: 8-bit, h264 — an expected FAIL).
  reverse-cost (P2-2; no DIR, no app): the probe built `-O` reverses
      `prores422_1080`, `prores422_2160`, `prores422_odd` and the ramp three
      times each, a process each: the median wall time, bytes, Mbps and peak
      RSS, the codec and size, and the power and load before and after. Exit
      0 iff every reverse completed.
  capture: the tree's `Compositor.swift` formats recorded (`formats`, read
      from `app/Sources`; a capture without them is PR0's, both 32BGRA);
      K1–K6 rendered into DIR; E0 (CONTROL) two `h264` exports of K6's
      clip decoded to `rgb24`, their digests recorded, equal or not; the P1
      figure; the ramp's controls (the middle row's distinct green values in
      `render_frame`, and a `prores_422` export's RMS against x/1919).
  Sc  (P2-1, CONTROL) the three stills' figures (`png16`, `tif16`, `png8`:
      S1's reading) recorded under `capture.json`'s `stills`; `still8.png`
      and `still8a.png` copied into DIR, each rendered alone on the 640×360
      canvas at 0.5 s into `S3-opaque.png` and `S3-alpha.png`, and
      `still8a.png` under `S3_COLOR` (brightness 0.1, contrast 0.5) into
      `S3-color.png`.
  Sd  (B97, CONTROL) into DIR: a `gif` export and a `render_frame format:
      jpeg` of `ramp16.png` alone, an `apng` export of `ramp8.png` alone, S5's
      scene as `mixed-h264.png` (its control picture), and an `apng` export of
      the 10-bit ramp clip alone at the first of SD_SIZES whose file ffprobe
      reads 8-bit — today's `sized` redraw seen — the size recorded in
      `capture.json`'s `Sd` (`no-redraw` when none does), with every file's
      digest.
  S3c (CONTROL; `capture DIR --only S3c`, P2-1's fix pass) S3's three scenes
      rendered into an EXISTING capture, only its `capture.json`'s `S3`
      replaced (and `S3_tree` naming the tree): how a scene added after DIR
      was captured gets its reference. Only a scene DIR lacks is rendered; a
      scene `capture.json` records whose `S3-<name>.png` is in DIR at that
      digest is kept as it is, PNG and fixture copy untouched, so the current
      tree never replaces an older tree's reference. `ctl-p21`'s
      `S3-color.png` was rendered so on P2-1's own Release build (its opaque
      and alpha digests equal the control tree's).
  compare (each histogram of differences printed): K1 byte-identical to
      DIR's; K2–K5 (no video) byte-identical when this tree's output format
      is the control's (PR2 against PR1), within ±2 when it is not (PR1
      against PR0); K6 (video) byte-identical when the source format is the
      control's, and when it is not (PR2 against PR1) recorded, not scored
      (spec §11 PR-2's ±1 on video).
  S3 (compare; P2-1) DIR's `still8.png` and `still8a.png` rendered as `capture`
      did (opaque; the alpha ramp; the alpha ramp under `S3_COLOR`): each
      `render_frame` is an 8-bit PNG whose `rgba` decode is byte-identical to
      DIR's (an 8-bit still takes today's draw byte for byte), the histogram
      printed. Only the colour scene tells an 8-bit still drawn deep from the
      8-bit draw: the compositor un-premultiplies before the controls, so
      the 8-bit draw's premultiplied rounding is carried through them.
  S11 (compare; B97, PR-9) Sd's files made again on this tree, each
      byte-identical to DIR's: GIF and JPEG stay 8-bit, an APNG with no deep
      still is today's, and so is a deep video source's APNG at the recorded
      size (that file skipped by name when DIR recorded `no-redraw`). A DIR
      captured before B97 has no Sd: a FAIL. Since issue batch B102 (spec
      §11 PR-11) the JPEG and `ramp8.png`'s APNG carry the BT.709 label, so a
      DIR captured before B102 fails S11 on those two, on labels alone
      (`frame_label_proof.py same-pixels DIR NEW` shows the pixels equal); the
      GIF and the 10-bit clip's APNG, already labelled BT.709, are unchanged.
  E1 (compare; the orchestrator's ruling after PR0, because E0 showed
      VideoToolbox's H.264 encode is not repeatable — two exports of one
      project differed by up to 124 levels): what `ExportWriter` hands the
      `h264` ENCODER. K6's and K3's scenes are saved as packages and read by
      `precision_encoder_probe.swift`, compiled through `swift_build.build`
      over this tree's `app/Sources` (a mutant's copy under `--mutant`): the
      core's `h264` settings, the composition as an export builds it, one
      frame through an `AVAssetReaderVideoCompositionOutput` in
      `Compositor.outputPixelFormat`, then `ExportWriter.frameForm` and
      `ExportFrames.convert` — or the reader's frame as it is when the form is
      nil. The handed buffer must be 32BGRA and, against DIR's `render_frame`
      PNG of the same scene (the captured tree's 8-bit frame), K6 (opaque, one layer)
      byte-identical and K3 (blended) every channel within ±1, the
      compositor's own ±1 at 16-bit float (K3's row). Across a decode change
      (PR2 against PR1's capture) K6's bound is the largest |Δ| of this
      tree's own K6 render against DIR's (the re-baseline rule's "within
      K6's histogram"), and the handed frame must also be byte-identical to
      that render. A probe that does not
      build is a scored FAILURE. This tree's `h264` export of K6, decoded to
      `rgb24`, is printed beside E0's digests, unscored.
  E2 (compare; PR1's fix pass): the same for the `hevc` (Main) encoder. Fed
      the half-float frame it encoded the precision ramp at 9.04 10-bit steps
      RMS against PR0's 6.46 from 32BGRA (both repeatable over three exports
      each), so `hevc` is rounded to 8 bits as `h264` is.
  --measure (M1, recorded, release-only): `prores_422` exports of a TYPICAL
      fixture (2 video tracks and a title) and a HEAVY one (4 video tracks,
      2 mattes, a routed dissolve, a shadow), each 8 s of the 2 s movie
      looped, at 1080p and 2160p, each on an instance of its own: the
      compositor timing log's average and worst over the export's 120-frame
      windows, and the memory — `phys_footprint` sampled every 0.5 s during
      the export (`footprint -p <pid>`), and the instance's lifetime
      `phys_footprint_peak` read after it, which is the figure compared (an
      export of 8 s takes 0.6–2.7 s, so a few samples miss its peak).
      `compare` prints PR0's beside, the implied extra buffers (Δpeak ÷ the
      per-buffer Δ, 64RGBAHalf against 32BGRA) and the frame-time stop
      (1080p's heavy average reaching 8 ms). The memory is printed and
      recorded, not a stop: the owner accepted PR1's measured rise (heavy 4K
      +851.7 MB, spec §11 PR-1) and retired the road map's +532 MB stop. A
      refused `footprint` is a named skip of the memory half.
  --measure ab --mutant decode-8bit (MA, recorded, release-only; PR2's
      review): the heavy 2160p fixture alone, exported on this tree's Release
      app and on a Release build of the `decode-8bit` copy (every source
      32BGRA, nothing else changed), alternated `--rounds` times (default 3)
      so both see the same host load; each export's compositor average and
      worst, the medians, and the deep decode's share (tree median ÷ copy
      median). Scored only on every export measuring.
  --selftest (no app): `app_tree` reads a scratch tree's formats from an app
      under its `build/Build/Products`, refuses an app outside any tree, and
      the default (no `--app`) is this tree's (rows S1–S3).
  Z1  the projects close and the log holds no `Frame Job: ` line.

`--mutant NAME` (PR1; spec B94) builds ONE `tree_copy.make_copy` with each
named anchor asserted to occur exactly once and replaced, by the copy's own
`make app-debug` (`make app` under `RC_PROOF_APP=release`;
`tree_copy.build_app`), and runs only its named rows on the copy — the probe
built from the copy's `app/Sources`:
  h264-deep        `frameForm` answers nil for `h264`: E1 FAILS (compare DIR).
  output-8bit      `Compositor.outputPixelFormat` is 32BGRA: P1 FAILS, and
                   `preview_refresh_probe.py --sources <copy>` scores PF FAILED.
  hevc-deep        `frameForm` answers nil for `hevc`: E2 FAILS (compare DIR).
  hevc-no-profile  the `hevc` Main pin removed AND `hevc` handed the deep
                   frame (`hevc-deep`'s anchor; with the 8-bit frame
                   VideoToolbox writes Main with or without the pin, so the pin
                   alone is an equivalent mutant): H1 FAILS
                   (`hevc_alpha_proof.py --mutant hevc-no-profile` holds B1 to it).
  decode-8bit      (PR2) `Compositor.sourcePixelFormat` is 32BGRA: R1 and R2
                   FAIL.
  no-source-clamp  (PR2) `layerSample`'s `saturate` removed (the clamp landed
                   in PR1; only a deep source reaches it): C1 FAILS.
  hevc10-main      (PR3) `hevc_10bit`'s profile is Main, not Main 10: T1 FAILS.
  hevc10-unmapped  (PR3) `codecType(for:)` drops `"hevc_10bit"`: T1 FAILS.
  hevc10-eightbit  (PR3; carried from PR1's fix pass) `frameForm` answers
                   `.eightBit` for `hevc_10bit` (the `isMain10` arm removed,
                   so `.hevc` decides): T2 FAILS.
  row-before-hevc-alpha  (PR3, core) the `hevc_10bit` row moved before
                   `hevc_alpha` in `export_table.rs`: no app is built; row CT
                   runs `cargo test --release --no-fail-fast --test export
                   --test export_hevc_10bit` in the copy's own `core/`, and
                   FAILS naming `hevc_alpha_sits_directly_after_hevc` and
                   `it_sits_directly_after_hevc_alpha`.
  still-eightbit   (P2-1) `renderImage`'s `let deep = …` is `false`, every
                   still into the 8-bit bitmap: S1, S2, S6 and S7 FAIL (S4 run
                   beside, in the mutant's `also`, printed and not required
                   to fail).
  still-deep-linear (P2-1) the deep bitmap's space is `linearSRGB`: S1 and S2
                   FAIL (S4 beside).
  still-always-deep (P2-1) `let deep = true`, every 8-bit still drawn deep
                   (compare DIR): S3 FAILS on its colour scene. Its opaque and
                   alpha scenes alone left it equivalent (P2-1's first run).
  reverse-bgra     (P2-2) the reader asks for 32BGRA: V0 FAILS (V1, V2 beside).
  reverse-main     (P2-2) the Main 10 pin is Main: V0 FAILS.
  reverse-709-labels (P2-2) BT.709 colour properties back in the HEVC
                   settings: V2 and V3 FAIL.
  reverse-planar-drop (P2-2) the old copy's one-plane guard: V0 FAILS.
  reverse-no-attachments (P2-2) `CVBufferPropagateAttachments` removed: V2
                   FAILS (V3 beside).
  reverse-unversioned (P2-2) the digest without the `|v<version>` suffix: V4 FAILS.
  reverse-odd-hevc (P2-2) `Intermediate.init` always `.hevcMain10`: V5 FAILS.
  deep-always      (B97, PR-9) `DeepStillFrame.shows` answers true: D1 and S8
                   FAIL.
  deep-project-wide (B97) `shows` reads every image media of the project
                   (`project.snapshot`) instead of the recipe at the frame
                   times: S8 FAILS.
  jpeg-deep        (B97) JPEG's `carriesDepth` true (compare DIR): S11 FAILS.
  reader-unscaled  (B97) `read` ignores `maxWidth`: S16 FAILS.
  reader-next-frame (B97) `read`'s range starts one `frameDuration` late: S14
                   FAILS.
  A survivor of jpeg-deep (the format's bytes do not move) is recorded as
  equivalent; S11 stays the guard. GIF and APNG have no depth decision
  (ImageIO writes both at 8 bits a component, measured in B97), so S11's GIF
  and APNG files are their guard. B97's `reader-space-swapped` was retired
  in issue batch B102: its anchor, `DeepStillFrame.read`'s two colour-space
  branches, is gone (the reader's image is in `FrameWriter.frameSpace`, spec
  §11 PR-11).
A mutant's `also` rows are selected, run and printed on the MUTANT line beside
the named ones, and are not required to fail.
Exit 0 when every named row FAILED (caught), 1 when one passed (survived), 2
when the control could not be performed.
"""

import argparse
import atexit
import hashlib
import json
import math
import os
import re
import tempfile
import shutil
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/precision"
WORK = BASE / "run"
HOME = WORK / "home"
MEDIA = BASE / "media"
CALL_BOUND = 600
SEC = 600_000
T = SEC // 2
W, H = 640, 360
RELEASE_ONLY = "M1 measures the compositor's frame times and the app's memory"
TAG = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
# Issue batch B98 (#290): the TAG fixtures' tags given to ffmpeg's INPUT as well
# (given to the output alone, ProRes wrote `colorspace` and left primaries and
# transfer `unknown`; B95: an output-only tag can convert the codes), and what
# ffprobe must read back. READBACK_MEAN: a fixture's first frame against its
# own lavfi graph rendered raw, mean |Δ| per plane in 8-bit levels (10-bit
# codes ÷ 4), fixed before the run.
SETPARAMS = "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709"
TAG_WANT = {"color_primaries": "bt709", "color_transfer": "bt709", "color_space": "bt709"}
READBACK_MEAN = 2.0
TAG_REFUSED = {}
RAMP = ("color=c=black:size=1920x1080:rate=30:duration=1,format=yuv422p10le,"
        "geq=lum='64+X*876/1919':cb=512:cr=512")
CARD = [0.2, 0.6, 0.9, 1]
GRADIENT = {"kind": "linear", "angle": 0, "stops": [{"at": 0, "color": [0, 0, 0, 1]},
                                                    {"at": 1, "color": [1, 1, 1, 1]}]}
TIMING = re.compile(r"\[framejob\] compositor: ([\d.]+) ms average, ([\d.]+) ms worst")
# 3840×2160 IOSurface sizes the spike measured (S-precision.md §7): one
# 64RGBAHalf buffer less one 32BGRA buffer.
PER_BUFFER = {2160: 66_355_264 - 33_177_664, 1080: (66_355_264 - 33_177_664) // 4}
STOP_MS = 8.0
# An MP4's major brands as AVFoundation and ffmpeg write them; QuickTime's is "qt  ".
MP4_BRANDS = ("mp42", "mp41", "isom")
# T2's 8-bit staircase tone, in 10-bit codes (`staircase_tone`). Measured on
# the ramp (M2 Max, macOS 26.5.1, precision PR3): hevc_10bit 0.014 (floor
# 0.010); hevc_10bit handed 8-bit frames (mutant hevc10-eightbit) 0.536;
# hevc (8-bit Main) 0.758.
TONE_MAX, TONE_SEEN = 0.1, 0.3
# The formats a tree's `Compositor.swift` names; a capture records its own
# (PR2), and a capture without them is PR0's: both 32BGRA.
FORMAT = re.compile(r"static let (output|source)PixelFormat: OSType = (kCVPixelFormatType_\w+)")
PR0_FORMATS = {"output": "kCVPixelFormatType_32BGRA", "source": "kCVPixelFormatType_32BGRA"}
BRIGHTNESS = -0.4
PROBE_SOURCE = ROOT / "tools/proof/precision_encoder_probe.swift"
PROBE_DIR = BASE / "encoder-probe"
BUILD_BOUND = 1500
SETTINGS = "app/Sources/ExporterWriter+Settings.swift"
TABLE = "core/src/export_table.rs"
RENDERERS = "app/Sources/LayerRenderers.swift"
# The stills (precision-2 P2-1): the brief's make_media.sh ramp, every column
# X at X/(W−1) of full scale in all three channels.
G16 = "format=gbrp16le,geq=r='X*65535/(W-1)':g='X*65535/(W-1)':b='X*65535/(W-1)'"
STILL_RAMP = f"color=c=black:size=1920x1080:d=1,{G16}"
G8 = "format=gbrp,geq=r='round(X*255/(W-1))':g='round(X*255/(W-1))':b='round(X*255/(W-1))'"
STILL_RAMP8 = f"color=c=black:size=1920x1080:d=1,{G8}"
# S1/S2: the deep ramp's distinct 10-bit Y codes on the middle row of its
# prores_422 export (the brief: 256 levels drawn 8-bit, 1,024 drawn deep).
STILL_DISTINCT = 800
# S6: the deep still's middle-row distinct green in a 16-bit render_frame (R1's
# figure for the 10-bit ramp; an 8-bit draw holds 256).
MIXED_DISTINCT = 850
# The reverse (precision-2 P2-2, spec §11 PR-7). V1: 10-bit steps over the
# forward clip's RMS. V2: 10-bit codes, mean |Δ| of the middle row's Y, Cb and
# Cr. V3: 8-bit levels, mean |Δ| of the two renders' middle rows, on the
# CHROMA fixture — set from P2-2's measurement (Debug, M2 Max): the old
# renderer read 0.764 (max 3.86, its 8-bit rounding; its picture was right,
# only its labels were wrong), the new one 0.078 (max 0.996); the spec's 1.0
# passed both, so it was tightened to tell them apart. The wait for one
# reverse, in seconds.
V1_MARGIN = 0.5
V2_BOUND = 2.0
V3_BOUND = 0.25
REVERSE_BOUND = 300
REVERSE_DISTINCT = 800
REVERSE_PROBE = ROOT / "tools/proof/reverse_probe.swift"
REVERSE_DIR = BASE / "reverse-probe"
REVERSER = "app/Sources/ReverseRenderer.swift"
REVERSE_READ = "app/Sources/ReverseRenderer+Read.swift"
REVERSE_CACHE = "app/Sources/ReverseCache.swift"
DEEP = "app/Sources/DeepStillFrame.swift"
RAMP_ODD = ("color=c=black:size=1919x1079:rate=30:duration=1,format=yuv422p10le,"
            "geq=lum='64+X*876/(W-1)':cb=512:cr=512")
HLG = ["-color_primaries", "bt2020", "-color_trc", "arib-std-b67", "-colorspace", "bt2020nc"]
HLG_TAGS = "arib-std-b67/bt2020/bt2020nc"
CHROMA = ("color=c=black:size=1920x1080:rate=30:duration=1,format=yuv420p10le,"
          "geq=lum='64+X*876/1919':cb='112+X*800/1919':cr='912-X*800/1919'")
V_ROWS = ("V0", "V1", "V2", "V3", "V4", "V5", "V6")
HEVC10_ROW = ('    Preset {\n        id: "hevc_10bit",\n        name: "HEVC 10-bit (MP4)",\n'
              '        container: Container::Mp4,\n        codec: "hevc_10bit",\n'
              '        video: true,\n        alpha: false,\n        size: None,\n'
              '        fps: None,\n'
              '        avf_preset: Some("AVAssetExportPresetHEVCHighestQuality"),\n    },\n')
HEVC_DEEP = (SETTINGS, "        return codec == .h264 || codec == .hevc ? .eightBit : nil\n",
             "        return codec == .h264 ? .eightBit : nil\n")
MUTANTS = {
    "h264-deep": {"mode": "compare", "rows": ["E1"], "anchors": [
        (SETTINGS, "        return codec == .h264 || codec == .hevc ? .eightBit : nil\n",
         "        return codec == .hevc ? .eightBit : nil\n")]},
    "output-8bit": {"mode": "rows", "rows": ["P1"], "pf": True, "anchors": [
        ("app/Sources/Compositor.swift",
         "    static let outputPixelFormat: OSType = kCVPixelFormatType_64RGBAHalf\n",
         "    static let outputPixelFormat: OSType = kCVPixelFormatType_32BGRA\n")]},
    "hevc-deep": {"mode": "compare", "rows": ["E2"], "anchors": [HEVC_DEEP]},
    # With `hevc`'s frame rounded to 8 bits, VideoToolbox writes Main with or
    # without the pin, so the pin alone removed is an equivalent mutant: this
    # one removes it AND hands `hevc` the deep frame, the input the pin is for.
    "hevc-no-profile": {"mode": "rows", "rows": ["H1"], "anchors": [
        (SETTINGS,
         "            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as "
         "String\n", ""), HEVC_DEEP]},
    # PR2.
    "decode-8bit": {"mode": "rows", "rows": ["R1", "R2"], "anchors": [
        ("app/Sources/Compositor.swift",
         "    static let sourcePixelFormat: OSType = kCVPixelFormatType_64RGBAHalf\n",
         "    static let sourcePixelFormat: OSType = kCVPixelFormatType_32BGRA\n")]},
    "no-source-clamp": {"mode": "rows", "rows": ["C1"], "anchors": [
        ("app/Resources/Shaders/Compositor.metal", "    float4 texel = saturate(source.sample(\n",
         "    float4 texel = (source.sample(\n")]},
    # PR3.
    "hevc10-main": {"mode": "rows", "rows": ["T1"], "anchors": [
        (SETTINGS, "            compression[AVVideoProfileLevelKey] = "
         "kVTProfileLevel_HEVC_Main10_AutoLevel as String\n",
         "            compression[AVVideoProfileLevelKey] = "
         "kVTProfileLevel_HEVC_Main_AutoLevel as String\n")]},
    "hevc10-unmapped": {"mode": "rows", "rows": ["T1"], "anchors": [
        (SETTINGS, '        case "hevc_10bit": return .hevc\n', "")]},
    "hevc10-eightbit": {"mode": "rows", "rows": ["T2"], "anchors": [
        (SETTINGS, "        if isMain10(settings) { return nil }\n", "")]},
    "row-before-hevc-alpha": {"mode": "core", "rows": ["CT"], "anchors": [
        (TABLE, HEVC10_ROW, ""),
        (TABLE, '    Preset {\n        id: "hevc_alpha",\n',
         HEVC10_ROW + '    Preset {\n        id: "hevc_alpha",\n')]},
    # precision-2 P2-1 (spec §11 PR-6). `also` rows run and print beside the
    # named ones, and are not required to fail.
    "still-always-deep": {"mode": "compare", "rows": ["S3"], "anchors": [
        (RENDERERS, "        let deep = image.bitsPerComponent > 8\n",
         "        let deep = true\n")]},
    "still-eightbit": {"mode": "rows", "rows": ["S1", "S2", "S6", "S7"], "also": ["S4"],
                       "anchors": [
        (RENDERERS, "        let deep = image.bitsPerComponent > 8\n",
         "        let deep = false\n")]},
    "still-deep-linear": {"mode": "rows", "rows": ["S1", "S2"], "also": ["S4"], "anchors": [
        (RENDERERS, "            let deepSpace = CGColorSpace(name: CGColorSpace.sRGB)\n",
         "            let deepSpace = CGColorSpace(name: CGColorSpace.linearSRGB)\n")]},
    # precision-2 P2-2 (spec §11 PR-7): the reverse.
    "reverse-bgra": {"mode": "rows", "rows": ["V0"], "also": ["V1", "V2"], "anchors": [
        (REVERSE_READ, "                    kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),\n",
         "                    kCVPixelBufferPixelFormatTypeKey as String: "
         "Int(kCVPixelFormatType_32BGRA),\n")]},
    "reverse-main": {"mode": "rows", "rows": ["V0"], "anchors": [
        (REVERSER, "            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as "
         "String,\n",
         "            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,\n")]},
    "reverse-709-labels": {"mode": "rows", "rows": ["V2", "V3"], "anchors": [
        (REVERSER, "            AVVideoCompressionPropertiesKey: compression,\n",
         "            AVVideoColorPropertiesKey: [\n"
         "                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,\n"
         "                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,\n"
         "                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,\n"
         "            ],\n"
         "            AVVideoCompressionPropertiesKey: compression,\n")]},
    "reverse-planar-drop": {"mode": "rows", "rows": ["V0"], "anchors": [
        (REVERSE_READ, "        guard width > 0, height > 0 else { return nil }\n",
         "        guard width > 0, height > 0, CVPixelBufferGetPlaneCount(source) <= 1 else "
         "{ return nil }\n")]},
    "reverse-no-attachments": {"mode": "rows", "rows": ["V2"], "also": ["V3"], "anchors": [
        (REVERSE_READ, "        CVBufferPropagateAttachments(source, target)\n", "")]},
    "reverse-unversioned": {"mode": "rows", "rows": ["V4"], "anchors": [
        (REVERSE_CACHE, '        for byte in "\\(source.path)|\\(size)|\\(Int64(modified.rounded()))'
         '|v\\(rendererVersion)".utf8 {\n',
         '        for byte in "\\(source.path)|\\(size)|\\(Int64(modified.rounded()))".utf8 {\n')]},
    "reverse-odd-hevc": {"mode": "rows", "rows": ["V5"], "anchors": [
        (REVERSER, "            self = dimensions.width % 2 != 0 || dimensions.height % 2 != 0 "
         "? .proRes422 : .hevcMain10\n",
         "            self = .hevcMain10\n")]},
    # Issue batch B97 (spec §11 PR-9): a frame showing a deep still, read
    # through the export's reader.
    "deep-always": {"mode": "rows", "rows": ["D1", "S8"], "anchors": [
        (DEEP, "        for layer in recipe.layers {\n",
         "        if recipe.layers.count >= 0 { return true }\n"
         "        for layer in recipe.layers {\n")]},
    "deep-project-wide": {"mode": "rows", "rows": ["S8"], "anchors": [
        (DEEP, "        guard let recipe = project.recipe(at: max(0, t), options: options) else "
         "{ return false }\n"
         "        for layer in recipe.layers {\n"
         "            guard case .image(let media) = layer.source, let url = urls[media] else "
         "{ continue }\n",
         "        for item in project.snapshot.media where item.kind == .image {\n"
         "            guard let url = urls[item.id] else { continue }\n")]},
    "jpeg-deep": {"mode": "compare", "rows": ["S11"], "anchors": [
        ("app/Sources/FrameWriter.swift",
         "    var carriesDepth: Bool {\n        switch self {\n        case .png, .heic: return "
         "true\n        case .jpeg: return false\n",
         "    var carriesDepth: Bool {\n        switch self {\n        case .png, .heic: return "
         "true\n        case .jpeg: return true\n")]},
    "reader-unscaled": {"mode": "rows", "rows": ["S16"], "anchors": [
        (DEEP, "        let size = Exporter.scaledSize(built.videoComposition.renderSize, "
         "to: maxWidth)\n",
         "        let size = built.videoComposition.renderSize\n")]},
    "reader-next-frame": {"mode": "rows", "rows": ["S14"], "anchors": [
        (DEEP, "            start: CompositionBuilder.time(max(0, t)),\n",
         "            start: CMTimeAdd(\n                CompositionBuilder.time(max(0, t)), "
         "built.videoConfiguration.frameDuration),\n")]},
}
CORE_TESTS = ("hevc_alpha_sits_directly_after_hevc", "it_sits_directly_after_hevc_alpha")
ROWS = ["C0", "D1", "D2", "P1", "H1", "R1", "R2", "C1", "T1", "T2", "S1", "S2", "S4", "S5", "S6",
        "S7", "S8", "S10", "S14", "S15", "S16", *V_ROWS, "Z1"]
CAPTURE_ROWS = ["K", "E0", "P1c", "Rc", "Sc", "Sd", "S3c", "Z1"]
COMPARE_ROWS = ["K1", "K2", "K3", "K4", "K5", "K6", "E1", "E2", "S3", "S11", "Z1"]
rows = {}
selected = set()
sources_folder = ROOT / "app/Sources"


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def skip(name, reason):
    print(f"  skip {name} — {reason}", flush=True)


def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    try:
        # `export` answers an id since #326; the helper follows it to the file.
        answer = (client.export_with(arguments) if tool == "export"
                  else client.call_with(tool, arguments))
        return {"ok": True, "reply": answer}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


class Doc:
    """One open project at `path` and the calls the rows make on it."""

    made = 0

    def __init__(self, client, name, width=W, height=H):
        Doc.made += 1
        self.client, self.path = client, WORK / f"{Doc.made:02d}-{name}.framejob"
        self.width, self.height = width, height
        self.ok, self.why = True, None
        self.note("new_project", attempt(client, "new_project", {"path": str(self.path)}))
        sized = self.call("set_canvas", width=width, height=height, fps=[30, 1],
                          background=[0, 0, 0, 1])
        if "made no change" not in sized.get("error", ""):   # a new project's own canvas
            self.note("set_canvas", sized)

    def note(self, tool, got):
        """Records the first failed step: `ok` false and `why` its tool and error."""
        if not got["ok"] and self.ok:
            self.ok, self.why = False, f"{tool}: {got.get('error', '')[:300]}"
        return got

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def first_track(self):
        return (self.project().get("tracks") or [{}])[0].get("id")

    def new_track(self):
        before = {t.get("id") for t in self.project().get("tracks") or []}
        self.call("add_track")
        made = [t.get("id") for t in self.project().get("tracks") or []
                if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def place(self, tool, **arguments):
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not (got["ok"] and len(new) == 1):
            self.note(tool, got if not got["ok"] else {"ok": False, "error": f"{len(new)} new"})
            return None
        return new[0]

    def step(self, tool, **arguments):
        return self.note(tool, self.call(tool, **arguments))

    def shape(self, track, patch, at=0, duration=2 * SEC, video=None):
        made = self.place("add_shape_clip", track=track, at=at, duration=duration,
                          shape=dict({"kind": "rectangle", "stroke": None,
                                      "width": self.width, "height": self.height}, **patch))
        if made is not None and video:
            self.step("set_video", clips=[made], patch=video)
        return made

    def title(self, track, duration=2 * SEC):
        return self.place("add_text_clip", track=track, at=0, duration=duration,
                          text={"content": "Precision"})

    def movie(self, track, path, repeats=1, seconds=1):
        """`path` imported once per project, then placed `repeats` times back to back."""
        self.media = getattr(self, "media", {})
        if path not in self.media:
            got = self.call("import_media", path=str(path))
            self.media[path] = reply(got).get("media")
            if self.media[path] is None:
                self.note("import_media", got if not got["ok"] else {"ok": False, "error": "no id"})
        media = self.media[path]
        if media is None:
            return []
        return [self.place("add_clip", track=track, media=media, at=i * seconds * SEC)
                for i in range(repeats)]

    def still(self, track, path):
        """The still at `path` imported, placed at 0 on `track` and trimmed to
        end at 1 s; its clip id, or None (`note`d)."""
        got = self.call("import_media", path=str(path))
        media = reply(got).get("media")
        if media is None:
            self.note("import_media", got if not got["ok"] else {"ok": False, "error": "no id"})
            return None
        clip = self.place("add_clip", track=track, media=media, at=0)
        if clip is not None:
            trimmed = self.call("trim_end", clip=clip, to=SEC)
            if "made no change" not in trimmed.get("error", ""):
                self.note("trim_end", trimmed)
        return clip

    def render(self, out, t=T, **extra):
        """`render_frame` at `t` into `out` (`extra` its other arguments,
        `max_width`); the PNG's bytes, or None."""
        out = Path(out)
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out), **extra)
        if not (got["ok"] and out.exists()):
            print(f"       render {out.name}: {got.get('error', 'no file')}", flush=True)
            return None
        return out.read_bytes()

    def export(self, preset, out, size="document", **extra):
        """`export` of `preset` at `size` (a Size row id, or [width, height])
        into `out`; the path, or None. The reply is kept as `exported`."""
        out = Path(out)
        if out.exists():
            out.unlink()
        got = self.call("export", preset=preset, path=str(out), size=size, **extra)
        self.exported = reply(got)
        if not (got["ok"] and out.exists()):
            print(f"       export {out.name}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def close(self):
        return attempt(self.client, "close_project",
                       {"project": str(self.path), "discard": True})["ok"]


# ---------------------------------------------------------------------------
# Fixtures and decoding.


def ffmpeg_make(out, argv):
    if out.exists():
        return out
    MEDIA.mkdir(parents=True, exist_ok=True)
    made = bounded.run(["ffmpeg", "-v", "error", "-y", *argv, str(out)], 600)
    return out if made["rc"] == 0 and out.exists() else None


def h264_clip():
    return tagged("testsrc2_640.mp4", [
        "-f", "lavfi", "-i", f"testsrc2=size={W}x{H}:rate=30:duration=1,{SETPARAMS}"],
        ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18"],
        {"codec_name": "h264", "pix_fmt": "yuv420p", "width": W, "height": H}, TAG_REFUSED)


def ramp_clip():
    return tagged("ramp10_prores422hq.mov", ["-f", "lavfi", "-i", f"{RAMP},{SETPARAMS}"],
                  ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"],
                  {"codec_name": "prores", "pix_fmt": "yuv422p10le", "width": 1920,
                   "height": 1080}, TAG_REFUSED)


def prores_clip(height):
    width = height * 16 // 9
    return tagged(f"prores422_{height}.mov", [
        "-f", "lavfi", "-i", f"testsrc2=size={width}x{height}:rate=30:duration=2,{SETPARAMS}"],
        ["-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le"],
        {"codec_name": "prores", "pix_fmt": "yuv422p10le", "width": width, "height": height},
        TAG_REFUSED)


# The planar layouts `read_back` reads: bytes a sample, chroma subsampling.
PLANAR = {"yuv420p": (1, 2, 2), "yuv422p10le": (2, 2, 1)}


def planes(raw, pix_fmt, width, height):
    """`raw` (one frame) as its Y, Cb and Cr sample lists, chroma sized by
    ceil, or None when it is short."""
    size, sub_x, sub_y = PLANAR[pix_fmt]
    cw, ch = -(-width // sub_x), -(-height // sub_y)
    counts = (width * height, cw * ch, cw * ch)
    if not raw or len(raw) < size * sum(counts):
        return None
    values = struct.unpack(f"<{sum(counts)}{'H' if size == 2 else 'B'}",
                           raw[:size * sum(counts)])
    return [values[:counts[0]], values[counts[0]:counts[0] + counts[1]],
            values[counts[0] + counts[1]:]]


def read_back(out, graph, pix_fmt):
    """(held, detail): `out`'s first frame decoded to `pix_fmt` against the
    first frame of `graph` (the fixture's own input argv) rendered raw to
    `pix_fmt` with no encode, by mean |Δ| per plane in 8-bit levels (10-bit
    codes ÷ 4); held when each of Y, Cb and Cr is ≤ READBACK_MEAN."""
    probe = stream(out)
    width, height = probe.get("width"), probe.get("height")
    if not width or not height:
        return False, f"ffprobe read no size from {out.name}"
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", *graph, "-frames:v", "1", "-f",
                              "rawvideo", "-pix_fmt", pix_fmt, "-"], capture_output=True,
                             timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        raw = None
    written, stored = (planes(raw, pix_fmt, width, height),
                       planes(decode(out, pix_fmt), pix_fmt, width, height))
    if written is None or stored is None:
        return False, (f"read back {pix_fmt}: the graph's frame {'ok' if written else 'short'}, "
                       f"{out.name}'s {'ok' if stored else 'short'}")
    scale = 4 if PLANAR[pix_fmt][0] == 2 else 1
    means = [sum(abs(a - b) for a, b in zip(w, s)) / len(w) / scale
             for w, s in zip(written, stored)]
    return (all(m <= READBACK_MEAN for m in means),
            "read-back mean |Δ| Y, Cb, Cr " + ", ".join(f"{m:.3f}" for m in means)
            + " 8-bit levels")


def tagged(name, graph, codec, want, refused):
    """`MEDIA/name`, made from `[*graph, *codec, *TAG]` and kept only when
    ffprobe reads `want` and TAG_WANT and `read_back` holds (issue batch B98,
    #290). A refused file, a stale cached one included, is removed and made
    once more; a second refusal is None, `refused["why"]` naming it."""
    if name in TAGGED:
        return TAGGED[name]
    out, need = MEDIA / name, {**want, **TAG_WANT}
    for attempt in (1, 2):
        made = ffmpeg_make(out, [*graph, *codec, *TAG])
        if made is None:
            refused["why"] = f"ffmpeg did not make {name}"
            continue
        probe = stream(made)
        wrong = {k: probe.get(k, "unknown") for k, v in need.items() if probe.get(k) != v}
        held, detail = (False, "not read") if wrong else read_back(made, graph, want["pix_fmt"])
        if held:
            print(f"       {name} kept: {tags(probe)}; {detail}", flush=True)
            TAGGED[name] = made
            return made
        refused["why"] = (f"{name} refused (attempt {attempt}): ffprobe read "
                          f"{wrong or 'as wanted'}, want {need}; {detail}")
        print(f"       {refused['why']}", flush=True)
        out.unlink(missing_ok=True)
    return None


def checked(maker, want, refused):
    """`maker()`'s file kept only when ffprobe reads every (key, value) in
    `want`; else None, `refused["why"]` naming the fixture and what it read
    (the row that needed it scores that as a FAIL), and the file removed."""
    out = maker()
    if out is None:
        refused["why"] = f"ffmpeg did not make {maker.__name__}'s movie"
        return None
    probe = stream(out)
    wrong = {k: probe.get(k) for k, v in want.items() if probe.get(k) != v}
    if wrong:
        refused["why"] = f"{out.name} refused: ffprobe read {wrong}, want {want}"
        print(f"       {refused['why']}", flush=True)
        out.unlink()
        return None
    return out


def ramp_odd():
    """The 10-bit ramp at 1919×1079 (V5; precision-2 P2-2), ProRes 422 HQ."""
    return tagged("ramp10_odd.mov", ["-f", "lavfi", "-i", f"{RAMP_ODD},{SETPARAMS}"],
                  ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"],
                  {"codec_name": "prores", "pix_fmt": "yuv422p10le", "width": 1919,
                   "height": 1079}, ODD_REFUSED)


def ramp_hlg():
    """The 1920×1080 ramp as an HLG BT.2020 HEVC Main 10 movie (V2, V3), as
    VideoToolbox writes it; kept only when ffprobe reads hevc, Main 10,
    yuv420p10le and arib-std-b67/bt2020/bt2020nc."""
    return checked(lambda: ffmpeg_make(MEDIA / "ramp10_hlg.mov", [
        "-f", "lavfi", "-i", RAMP + ",format=yuv420p10le,setparams=color_primaries=bt2020:"
        "color_trc=arib-std-b67:colorspace=bt2020nc", "-c:v", "hevc_videotoolbox",
        "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v", "hvc1", "-b:v", "20M", *HLG]),
        {"codec_name": "hevc", "profile": "Main 10", "pix_fmt": "yuv420p10le",
         "color_transfer": "arib-std-b67", "color_primaries": "bt2020",
         "color_space": "bt2020nc"}, HLG_REFUSED)


def chroma_hlg():
    """V3's fixture: the HLG BT.2020 HEVC Main 10 movie of `CHROMA` — the
    10-bit luma ramp with Cb rising and Cr falling across the width, so the
    middle row holds saturated colours, which a wrong matrix or primaries
    label moves (on the grey ramp neither label moves a code). Kept only when
    ffprobe reads hevc, Main 10, yuv420p10le and the HLG tags."""
    return checked(lambda: ffmpeg_make(MEDIA / "chroma10_hlg.mov", [
        "-f", "lavfi", "-i", CHROMA + ",setparams=color_primaries=bt2020:"
        "color_trc=arib-std-b67:colorspace=bt2020nc", "-c:v", "hevc_videotoolbox",
        "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v", "hvc1", "-b:v", "20M", *HLG]),
        {"codec_name": "hevc", "profile": "Main 10", "pix_fmt": "yuv420p10le",
         "color_transfer": "arib-std-b67", "color_primaries": "bt2020",
         "color_space": "bt2020nc"}, HLG_REFUSED)


def prores_odd():
    """`reverse-cost`'s odd-sized movie: 2 s of `testsrc2` at 1919×1079, ProRes
    422. The `format` filter keeps the size: left to negotiate 4:2:0, ffmpeg
    wrote 1918×1078 (P2-2's control)."""
    return tagged("prores422_odd.mov", [
        "-f", "lavfi", "-i",
        f"testsrc2=size=1919x1079:rate=30:duration=2,format=yuv444p10le,{SETPARAMS}"],
        ["-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le"],
        {"codec_name": "prores", "pix_fmt": "yuv422p10le", "width": 1919, "height": 1079},
        ODD_REFUSED)


ODD_REFUSED, HLG_REFUSED, TAGGED = {}, {}, {}


def still16_png():
    return ffmpeg_make(MEDIA / "ramp16.png", [
        "-f", "lavfi", "-i", STILL_RAMP, "-frames:v", "1", "-pix_fmt", "rgb48be"])


def still16_tif():
    return ffmpeg_make(MEDIA / "ramp16.tif", [
        "-f", "lavfi", "-i", STILL_RAMP, "-frames:v", "1", "-pix_fmt", "rgb48le"])


def still10_heic():
    """`ramp16.png` as a 10-bit HEIC (ffmpeg cannot mux HEIF): drawn into a
    16-bit-float bitmap and written by ImageIO's HEIC writer
    (`heic10_writer.swift`, built through `swift_build.build`; its comment
    has why only that route keeps 10 bits), and kept only when `ffprobe`
    reads HEVC Main 10 `yuv420p10le` AND its middle row holds ≥
    STILL_DISTINCT distinct 10-bit Y codes, so the fixture is 10-bit in
    content, not only in name (P2-1's fix pass). Made only when S7 is
    selected, never in the preflight: on None, `HEIC_REFUSED["why"]` says why,
    and S7 scores that as a FAIL."""
    out = MEDIA / "ramp10.heic"
    if not out.exists():
        source = still16_png()
        if source is None:
            HEIC_REFUSED["why"] = "ffmpeg did not make ramp16.png"
            return None
        writer = BASE / "heic10-writer" / "heic10_writer"
        try:
            swift_build.build(sources=[ROOT / "tools/proof/heic10_writer.swift"], output=writer,
                              timeout=BUILD_BOUND)
        except swift_build.SwiftBuildFailed as failure:
            HEIC_REFUSED["why"] = f"heic10_writer did not build: {str(failure)[:300]}"
            print(f"       {HEIC_REFUSED['why']}", flush=True)
            return None
        made = bounded.run([str(writer), str(source), str(out)], 120)
        if made["rc"] != 0 or not out.exists():
            HEIC_REFUSED["why"] = (f"heic10_writer exited {made['rc']}: "
                                   f"{(made.get('stderr') or '')[:300]}")
            print(f"       {HEIC_REFUSED['why']}", flush=True)
            return None
    probe = ffprobe(out)
    raw = decode(out, "gray10le")
    codes = (len({raw[(540 * 1920 + x) * 2:(540 * 1920 + x) * 2 + 2] for x in range(1920)})
             if raw and len(raw) == 1920 * 1080 * 2 else None)
    if (probe.get("pix_fmt") != "yuv420p10le" or probe.get("profile") != "Main 10"
            or codes is None or codes < STILL_DISTINCT):
        HEIC_REFUSED["why"] = (f"ramp10.heic refused: {probe.get('profile')} "
                               f"{probe.get('pix_fmt')}, middle-row codes {codes}")
        print(f"       {HEIC_REFUSED['why']}", flush=True)
        out.unlink()
        return None
    return out


HEIC_REFUSED = {}


def still8_png():
    """The 8-bit control ramp, written 8-bit directly and ROUNDED, so its 256
    levels step at 255/(W−1) cycles a pixel as Core Graphics' 8-bit draw of
    the 16-bit ramp does, the frequency `staircase_tone` reads. ffmpeg's own
    `rgb48`→`rgb24` conversion truncates, which puts the steps near 256/(W−1)
    and read a tone of 0.0301 against 1.2236 (P2-1's first capture)."""
    return ffmpeg_make(MEDIA / "ramp8.png", [
        "-f", "lavfi", "-i", STILL_RAMP8, "-frames:v", "1", "-pix_fmt", "rgb24"])


def still8_opaque():
    return ffmpeg_make(MEDIA / "still8.png", [
        "-f", "lavfi", "-i", f"testsrc2=size={W}x{H}", "-frames:v", "1", "-pix_fmt", "rgb24"])


def still8_alpha():
    return ffmpeg_make(MEDIA / "still8a.png", [
        "-f", "lavfi", "-i", f"testsrc2=size={W}x{H},format=rgba,"
        "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='X*255/639'",
        "-frames:v", "1", "-pix_fmt", "rgba"])


# The preflight's stills; `still10_heic` is not one (it needs a Swift build
# and ImageIO's HEIC writer, so only S7 makes it, and scores its refusal).
STILLS = (still16_png, still16_tif, still8_png, still8_opaque, still8_alpha)
# S3's scenes: (name, fixture, `set_video` patch). `color` is the alpha-ramp
# still under a non-identity colour control: the compositor un-premultiplies
# before the controls, so an 8-bit still's premultiplied rounding is carried
# through them there, and an 8-bit still drawn deep is not (P2-1's fix pass).
S3_COLOR = {"color": {"brightness": 0.1, "contrast": 0.5}}
S3_SCENES = (("opaque", still8_opaque, None), ("alpha", still8_alpha, None),
             ("color", still8_alpha, S3_COLOR))


def decode(path, pix_fmt, extra=(), frames=1):
    """The raw `pix_fmt` bytes of `path`'s first `frames` frames (all with
    `frames=None`), or None — bounded."""
    argv = ["ffmpeg", "-v", "error", "-i", str(path), *extra]
    if frames is not None:
        argv += ["-frames:v", str(frames)]
    try:
        raw = subprocess.run(argv + ["-f", "rawvideo", "-pix_fmt", pix_fmt, "-"],
                             capture_output=True, timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw or None


def png_depth(data):
    """A PNG's IHDR bit depth, or None."""
    return data[24] if data and data[:8] == b"\x89PNG\r\n\x1a\n" else None


def rgba(path, width=W, height=H):
    raw = decode(path, "rgba")
    return raw if raw and len(raw) == width * height * 4 else None


def luma_row(path, width, height):
    """The middle row of `path`'s first frame as `gray16le` fractions of full
    scale (`ramp_error.py`'s reading)."""
    raw = decode(path, "gray16le", ["-vf", f"crop={width}:2:0:{height // 2}"])
    if not raw or len(raw) < width * 2:
        return None
    return [v / 65535 for v in struct.unpack(f"<{width}H", raw[:width * 2])]


def y10_columns(path, width, height):
    """`path`'s first frame decoded as `yuv420p10le`: (the middle row's luma
    CODES, each column's mean code over rows 8…H−8), or (None, None). The
    ramp is the same on every row, so the column mean averages the encoder's
    block noise away and keeps what every row shares — an 8-bit staircase
    under it, if the encoder was handed 8-bit frames."""
    raw = decode(path, "yuv420p10le")
    if not raw or len(raw) < width * height * 2:
        return None, None
    plane = struct.unpack(f"<{width * height}H", raw[:width * height * 2])
    middle = list(plane[(height // 2) * width:(height // 2 + 1) * width])
    rows = range(8, height - 8)
    means = [sum(plane[y * width + x] for y in rows) / len(rows) for x in range(width)]
    return middle, means


def staircase_tone(means, width):
    """The 8-bit staircase's tone: the column means less their own 31-column
    moving average (detail finer than 31 px is left — an 8-bit staircase's
    sawtooth, a step every 7.5 px on this ramp — and no offset or gentle
    curve, which the average follows), and that residual's amplitude, in
    codes, at the staircase's own frequency (255 steps across W−1 px); with
    the median amplitude over 41 frequencies either side of it (0.09–0.12 and
    0.15–0.18 cycles/px) as its floor. (tone, floor)."""
    errors = [means[x] - sum(means[x - 15:x + 16]) / 31 for x in range(32, width - 32)]

    def amplitude(f):
        re = sum(e * math.cos(2 * math.pi * f * n) for n, e in enumerate(errors))
        im = sum(e * math.sin(2 * math.pi * f * n) for n, e in enumerate(errors))
        return 2 * math.hypot(re, im) / len(errors)
    floor = sorted(amplitude(f) for f in [0.09 + 0.03 * k / 20 for k in range(21)]
                   + [0.15 + 0.03 * k / 19 for k in range(20)])
    return amplitude(255 / (width - 1)), floor[len(floor) // 2]


def rms_steps(measured, ideal):
    """RMS of (measured − ideal) in 10-bit steps over columns 16…W−16."""
    errors = [(m - i) * 1023 for m, i in list(zip(measured, ideal))[16:len(ideal) - 16]]
    return math.sqrt(sum(e * e for e in errors) / len(errors))


def histogram(a, b):
    """{|difference|: channel count} over two equal-length byte strings."""
    if a == b:
        return {0: len(a)}
    counts = {}
    for x, y in zip(a, b):
        d = abs(x - y)
        counts[d] = counts.get(d, 0) + 1
    return dict(sorted(counts.items()))


def short(counts):
    """A histogram for a line: |Δ| 0–5 by count, then the rest summed with its largest."""
    head = {d: n for d, n in counts.items() if d <= 5}
    rest = {d: n for d, n in counts.items() if d > 5}
    return f"{head}" + (f" + {sum(rest.values())} more up to {max(rest)}" if rest else "")


def digest(data):
    return hashlib.sha256(data).hexdigest()[:16] if data else None


def tree_formats(folder=None):
    """{"output", "source"}: the pixel formats `folder`'s (by default
    `sources_folder`'s) `Compositor.swift` names — the sources of the app
    driven (`app_tree`), this tree's or a mutant copy's."""
    try:
        return dict(FORMAT.findall((Path(folder or sources_folder) / "Compositor.swift")
                                   .read_text()))
    except OSError:
        return {}


def app_tree(binary):
    """The tree whose `app/Sources` built `binary`: the folder above the
    `build/Build/Products` it sits in, when that folder holds
    `app/Sources/Compositor.swift`; else None (an app outside any tree, whose
    formats cannot be read). PR2's review: `--app PATH` once read the WORKING
    tree's formats whatever PATH was."""
    path = Path(os.path.abspath(binary))
    for parent in path.parents:
        if (parent.name, parent.parent.name, parent.parent.parent.name) == (
                "Products", "Build", "build"):
            tree = parent.parent.parent.parent
            return tree if (tree / "app/Sources/Compositor.swift").is_file() else None
    return None


# ---------------------------------------------------------------------------
# The scenes.


def k_scene(client, name, clip):
    """Scene `name` (K1–K6, or D1's card and clip) built in a new project;
    (doc, render time)."""
    doc = Doc(client, name)
    t1 = doc.first_track()
    if name == "K6":
        doc.movie(t1, clip)
        return doc, T
    if name == "K4":
        red = doc.shape(t1, {"fill": [1, 0, 0, 1]}, at=0, duration=SEC)
        green = doc.shape(t1, {"fill": [0, 1, 0, 1]}, at=SEC, duration=SEC)
        doc.step("nest", clips=[red, green])
        nests = lambda: sorted((c["start"], c["duration"], c["id"])  # noqa: E731
                               for c in doc.project().get("clips") or []
                               if (c.get("source") or {}).get("kind") == "nest")
        first = nests()[0][2] if len(nests()) == 1 else None
        doc.step("split", clips=[first], at=SEC)
        halves = nests()
        second = halves[1][2] if len(halves) == 2 else None
        doc.step("add_transition", clip=second, kind="cross_dissolve", duration=SEC // 2,
                 align="after")
        doc.step("set_transition_style", clip=second, curve="linear")
        if [h[:2] for h in nests()] != [(0, SEC + SEC // 2), (SEC, SEC)]:
            doc.note("halves", {"ok": False, "error": f"{nests()}"})
        return doc, SEC + SEC // 4
    doc.shape(t1, {"fill": CARD})
    if name == "D1":
        doc.movie(doc.new_track(), clip)
        return doc, T
    if name in ("K3", "K5"):
        doc.shape(doc.new_track(), {"fill": [1, 1, 1, 1], "gradient": GRADIENT},
                  video={"opacity": 0.5})
    if name == "K5":
        doc.shape(doc.new_track(), {"kind": "ellipse", "fill": [1, 0, 0, 1], "width": 300,
                                    "height": 200}, video={"opacity": 0.6, "x": -80})
    if name in ("K2", "K3", "K5"):
        doc.title(doc.new_track())
    if name in ("K3", "K5"):
        doc.shape(doc.new_track(), {"fill": [1, 0.8, 0.3, 1], "width": 320, "height": 180},
                  video={"blend": "multiply", "x": 80, "y": 40})
    if name == "K5":
        doc.shape(doc.new_track(), {"fill": [0.2, 0.3, 1, 1], "width": 200, "height": 300},
                  video={"blend": "screen", "opacity": 0.8, "x": 150})
    return doc, T


def p1_figure(client, out_dir):
    """P1's measurement: (RMS in 10-bit steps, detail) or (None, why)."""
    doc = Doc(client, "P1", 1920, 1080)
    grad = doc.shape(doc.first_track(), {"fill": [1, 1, 1, 1], "gradient": GRADIENT})
    full = doc.render(out_dir / "p1-opacity1.png")
    doc.step("set_video", clips=[grad], patch={"opacity": 0.5})
    movie = doc.export("prores_422", out_dir / "p1.mov")
    ok = doc.ok and full is not None and movie is not None and png_depth(full) == 8
    closed = doc.close()
    if not ok:
        return None, (f"fixture {doc.why or 'ok'}; render depth {png_depth(full)}; "
                      f"export {movie}"), closed
    raw = rgba(out_dir / "p1-opacity1.png", 1920, 1080)
    measured = luma_row(movie, 1920, 1080)
    if raw is None or measured is None:
        return None, "the render or the export did not decode", closed
    g = [raw[(540 * 1920 + x) * 4 + 1] for x in range(1920)]
    figure = rms_steps(measured, [0.5 * v / 255 for v in g])
    return figure, f"g {min(g)}…{max(g)}", closed


def ramp_controls(client, out_dir):
    """The ramp's figures: (distinct green values on the render's middle row,
    the prores_422 export's RMS against x/1919, the PNG's depth)."""
    doc = Doc(client, "ramp", 1920, 1080)
    doc.movie(doc.first_track(), ramp_clip())
    png = doc.render(out_dir / "ramp.png")
    movie = doc.export("prores_422", out_dir / "ramp.mov")
    closed = doc.close()
    distinct = rms = None
    if png is not None:
        raw = decode(out_dir / "ramp.png", "rgb48le")
        if raw and len(raw) == 1920 * 1080 * 6:
            row = raw[540 * 1920 * 6:541 * 1920 * 6]
            distinct = len({row[x * 6 + 2:x * 6 + 4] for x in range(1920)})
    if movie is not None:
        measured = luma_row(movie, 1920, 1080)
        rms = rms_steps(measured, [x / 1919 for x in range(1920)]) if measured else None
    return distinct, rms, png_depth(png), closed


def still_figures(client, out_dir, path, label):
    """A still's figures (precision-2 P2-1): a 1920×1080 project holding the
    still alone; its `render_frame` PNG's depth and middle-row distinct green
    (`rgb48le`), and a `prores_422` export's middle-row distinct 10-bit Y
    codes (columns 16…W−16), luma RMS against x/1919 and staircase tone
    (amplitude, floor). (figures, closed)."""
    doc = Doc(client, f"still-{label}", 1920, 1080)
    doc.still(doc.first_track(), path)
    png = doc.render(out_dir / f"still-{label}.png")
    movie = doc.export("prores_422", out_dir / f"still-{label}.mov")
    closed = doc.close()
    figures = {"fixture": doc.why or "ok", "png_depth": png_depth(png), "green": None,
               "distinct": None, "rms": None, "tone": None}
    if png is not None:
        raw = decode(out_dir / f"still-{label}.png", "rgb48le")
        if raw and len(raw) == 1920 * 1080 * 6:
            row = raw[540 * 1920 * 6:541 * 1920 * 6]
            figures["green"] = len({row[x * 6 + 2:x * 6 + 4] for x in range(1920)})
    if movie is not None:
        measured = luma_row(movie, 1920, 1080)
        codes, means = y10_columns(movie, 1920, 1080)
        figures["distinct"] = len(set(codes[16:-16])) if codes else None
        figures["rms"] = (round(rms_steps(measured, [x / 1919 for x in range(1920)]), 4)
                          if measured else None)
        figures["tone"] = [round(v, 4) for v in staircase_tone(means, 1920)] if means else None
    return figures, closed


def mixed_figures(client, out_dir, movie, label):
    """S5/S6's scene (P2-1's fix pass): `ramp16.png` on a track above `movie`
    on a 1920×1080 canvas, covering it, rendered at 0.5 s; its PNG's depth
    and middle-row distinct green (`rgb48le`). (figures, closed)."""
    doc = Doc(client, f"mixed-{label}", 1920, 1080)
    doc.movie(doc.first_track(), movie)
    doc.still(doc.new_track(), still16_png())
    png = doc.render(out_dir / f"mixed-{label}.png")
    closed = doc.close()
    figures = {"fixture": doc.why or "ok", "png_depth": png_depth(png), "green": None}
    if png is not None:
        raw = decode(out_dir / f"mixed-{label}.png", "rgb48le")
        if raw and len(raw) == 1920 * 1080 * 6:
            row = raw[540 * 1920 * 6:541 * 1920 * 6]
            figures["green"] = len({row[x * 6 + 2:x * 6 + 4] for x in range(1920)})
    return figures, closed


def against_control(path, state, name, width=1920, height=1080):
    """S4/S5's picture (B97, PR-9): this run's 16-bit PNG at `path`, its RGB
    scaled to 8 bits (round(v/257)), against the control tree's 8-bit render
    `name` in the `--control` DIR (`state["_dir"]`): {good (every channel
    within ±1), detail (mean and max |Δ|)}."""
    folder = state.get("_dir")
    if not folder:
        return {"good": False, "detail": "picture: no control tree (--control DIR)"}
    deep, then = decode(path, "rgb48le"), decode(Path(folder) / name, "rgb24")
    count = width * height * 3
    if not deep or not then or len(deep) != count * 2 or len(then) != count:
        return {"good": False, "detail": f"picture: {path.name} or DIR's {name} did not decode "
                f"at {width}×{height} ({len(deep or b'')} and {len(then or b'')} bytes)"}
    values = struct.unpack(f"<{count}H", deep)
    deltas = [abs((v + 128) // 257 - b) for v, b in zip(values, then)]
    largest, mean = max(deltas), sum(deltas) / count
    return {"good": largest <= 1,
            "detail": f"picture against the control tree's {name} (8-bit): mean |Δ| {mean:.4f}, "
                      f"max |Δ| {largest} (±1 allowed)"}


def profile(path):
    """`sips -g profile`'s answer for `path` (the embedded profile's name),
    or None when sips reads none."""
    if not Path(path).exists():
        return None
    ran = bounded.run(["sips", "-g", "profile", str(path)], 60)
    found = [line.split(":", 1)[1].strip() for line in (ran.get("stdout") or "").splitlines()
             if line.strip().startswith("profile:")]
    return found[0] if found else None


# S14/S15: the columns a half-scale still leaves showing the video under it,
# on the 1920×1080 canvas (the still covers 480…1439).
OUTER = (range(0, 400), range(1520, 1920))


def outer_columns(path, width=1920, height=1080):
    """`path`'s OUTER columns, every row, as 8-bit values (the `rgb48le`
    decode's round(v/257); an 8-bit PNG decodes to v·257, so it is exact), or
    None."""
    raw = decode(path, "rgb48le")
    if not raw or len(raw) != width * height * 6:
        return None
    values = struct.unpack(f"<{width * height * 3}H", raw)
    out = []
    for y in range(height):
        base = y * width * 3
        for span in OUTER:
            out.extend((v + 128) // 257 for v in values[base + span.start * 3:base + span.stop * 3])
    return out


def outer_delta(a, b):
    """(mean, max) |Δ| of two outer-column lists, or None."""
    if a is None or b is None or len(a) != len(b) or not a:
        return None
    deltas = [abs(x - y) for x, y in zip(a, b)]
    return sum(deltas) / len(deltas), max(deltas)


def apng_figures(path):
    """An APNG's stream `pix_fmt` and read frame count (ffprobe), and its first
    frame's middle-row distinct green (`rgb48le`); {} keys None when unread."""
    ran = bounded.run(["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
                       "-show_entries", "stream=codec_name,pix_fmt,width,height,nb_read_frames",
                       "-of", "json", str(path)], 120)
    try:
        probe = (json.loads(ran["stdout"]).get("streams") or [{}])[0]
    except (ValueError, IndexError):
        probe = {}
    green = None
    width, height = probe.get("width"), probe.get("height")
    if width and height:
        raw = decode(path, "rgb48le")
        if raw and len(raw) >= width * height * 6:
            row = raw[(height // 2) * width * 6:(height // 2 + 1) * width * 6]
            green = len({row[x * 6 + 2:x * 6 + 4] for x in range(width)})
    frames = probe.get("nb_read_frames")
    return {"codec": probe.get("codec_name"), "pix_fmt": probe.get("pix_fmt"),
            "size": [width, height], "frames": int(frames) if frames else None, "green": green}


def s8_project(client, label):
    """S8's project: `ramp16.png` at 0–1 s and the H.264 clip at 1–2 s on one
    track of a 1920×1080 canvas; (doc, the still's clip id)."""
    doc = Doc(client, label, 1920, 1080)
    track = doc.first_track()
    still = doc.still(track, still16_png())
    got = doc.call("import_media", path=str(h264_clip()))
    media = reply(got).get("media")
    if media is None:
        doc.note("import_media", got if not got["ok"] else {"ok": False, "error": "no id"})
    else:
        doc.place("add_clip", track=track, media=media, at=SEC)
    return doc, still


def still_alone(client, label, path):
    """`path` alone on a 1920×1080 canvas (placed at 0, trimmed to 1 s)."""
    doc = Doc(client, label, 1920, 1080)
    doc.still(doc.first_track(), path)
    return doc


PIX_EIGHT = ("rgba", "rgb24")
# Sd: the sizes tried, in order, for the 10-bit ramp clip's APNG until one's
# file reads 8-bit — today's `sized` redraw seen (the generator missed the size).
SD_SIZES = ([961, 541], [959, 539], [641, 361])


def run_pr9(client):
    """S8, S10, S14, S15 and S16 (issue batch B97, spec §11 PR-9)."""
    closed = True
    if "S8" in selected:
        doc, still = s8_project(client, "S8")
        with_still = doc.render(WORK / "s8-with.png", SEC + SEC // 2)
        doc.step("delete", clips=[still])
        left = [(c.get("start"), c.get("duration")) for c in doc.project().get("clips") or []]
        without = doc.render(WORK / "s8-without.png", SEC + SEC // 2)
        check("S8 (PR-9) ramp16.png at 0–1 s then the H.264 clip at 1–2 s, at 1.5 s (the still "
              "not drawn): an 8-bit PNG byte-identical to the same frame with the still deleted",
              doc.ok and with_still is not None and png_depth(with_still) == 8
              and with_still == without and left == [(SEC, SEC)],
              f"fixture {doc.why or 'ok'}; depth {png_depth(with_still)}; with the still "
              f"{digest(with_still)}, deleted {digest(without)} (depth {png_depth(without)}); "
              f"clips left {left}")
        closed = doc.close() and closed
    if "S10" in selected:
        doc = still_alone(client, "S10", still16_png())
        out = WORK / "s10.heic"
        got = doc.call("render_frame", t=T, path=str(out), format="heic")
        bits = bounded.run(["sips", "-g", "bitsPerSample", str(out)], 60) if out.exists() else {}
        sample = [line.strip() for line in (bits.get("stdout") or "").splitlines()
                  if "bitsPerSample" in line]
        check("S10 (PR-9, recorded: scored only on the file being written) render_frame "
              "format heic of ramp16.png alone; sips's bitsPerSample printed",
              doc.ok and got["ok"] and out.exists(),
              f"fixture {doc.why or 'ok'}; {got.get('error', 'written')}; sips: "
              f"{sample or 'nothing read'}")
        closed = doc.close() and closed
    if "S14" in selected:
        closed = run_s14(client) and closed
    if "S15" in selected:
        closed = run_s15(client) and closed
    if "S16" in selected:
        doc = still_alone(client, "S16", still16_png())
        png = doc.render(WORK / "s16.png", max_width=960)
        raw = decode(WORK / "s16.png", "rgb48le") if png else None
        green = (len({raw[270 * 960 * 6 + x * 6 + 2:270 * 960 * 6 + x * 6 + 4] for x in range(960)})
                 if raw and len(raw) == 960 * 540 * 6 else None)
        size = list(struct.unpack(">II", png[16:24])) if png else None
        check("S16 (PR-9) render_frame max_width 960 of ramp16.png alone on a 1920×1080 canvas "
              "is a 960×540 16-bit PNG whose middle row holds > 256 distinct greens",
              doc.ok and png_depth(png) == 16 and size == [960, 540] and (green or 0) > 256,
              f"fixture {doc.why or 'ok'}; depth {png_depth(png)}; size {size}; middle-row "
              f"distinct green {green}")
        closed = doc.close() and closed
    return closed


def half_still_over(client, label, movie, fill=None):
    """S14/S15's scene: `movie` on track 1 at 0 (at `set_video` scale `fill`
    when given: a 640×360 clip sits at native size, §5.3, so only scale 3
    reaches the outer columns) and `ramp16.png` on a track above it at scale
    0.5 (centred, so the OUTER columns show the movie alone), on a 1920×1080
    canvas; (doc, the still's clip id)."""
    doc = Doc(client, label, 1920, 1080)
    placed = doc.movie(doc.first_track(), movie)
    if fill is not None and placed and placed[0] is not None:
        doc.step("set_video", clips=[placed[0]], patch={"scale": fill})
    still = doc.still(doc.new_track(), still16_png())
    if still is not None:
        doc.step("set_video", clips=[still], patch={"scale": 0.5})
    return doc, still


def run_s14(client):
    """S14 (PR-9): the reader reads the frame the generator does, at the
    frame time and off the 30 fps grid."""
    doc, still = half_still_over(client, "S14", h264_clip(), fill=3)
    times = {"T": T, "T+1/60": T + SEC // 60, "T+1/30": T + SEC // 30}
    deep = {k: doc.render(WORK / f"s14-deep-{i}.png", times[k]) for i, k in
            enumerate(("T", "T+1/60"))}
    doc.step("delete", clips=[still])
    flat = {k: doc.render(WORK / f"s14-flat-{i}.png", t) for i, (k, t) in enumerate(times.items())}
    lines, good = [], doc.ok and still is not None
    for i, k in enumerate(("T", "T+1/60")):
        delta = outer_delta(outer_columns(WORK / f"s14-deep-{i}.png") if deep[k] else None,
                            outer_columns(WORK / f"s14-flat-{i}.png") if flat[k] else None)
        good = good and png_depth(deep[k]) == 16 and delta is not None and delta[1] <= 1
        lines.append(f"at {k}: depth {png_depth(deep[k])}, outer columns against the still-less "
                     f"render (depth {png_depth(flat[k])}) " + (
                         f"mean |Δ| {delta[0]:.4f}, max |Δ| {delta[1]}" if delta else "unread"))
    guard = outer_delta(outer_columns(WORK / "s14-flat-0.png") if flat["T"] else None,
                        outer_columns(WORK / "s14-flat-2.png") if flat["T+1/30"] else None)
    good = good and guard is not None and guard[1] > 0
    lines.append("fixture guard, still-less T against T+1/30: " + (
        f"mean |Δ| {guard[0]:.4f}, max |Δ| {guard[1]}" if guard else "unread"))
    check("S14 (PR-9) the H.264 clip under ramp16.png at scale 0.5, rendered at T and T+1/60 "
          "(off the grid): each a 16-bit PNG whose outer columns, scaled to 8 bits, are within "
          "±1 of the still-less render at the same time; the still-less renders at T and "
          "T+1/30 differ there (the fixture moves)",
          good, f"fixture {doc.why or 'ok'}; " + "; ".join(lines))
    return doc.close()


def run_s15(client):
    """S15 (PR-9): a converting composition (the HLG ramp) under a deep still
    keeps the generator's colour space and picture outside it."""
    movie = ramp_hlg()
    if movie is None:
        check("S15 (PR-9) the HLG ramp under ramp16.png at scale 0.5 (a converting "
              "composition): a 16-bit PNG with the still-less render's profile and outer "
              "columns within ±1", False, f"fixture refused: {HLG_REFUSED.get('why')}")
        return True
    doc, still = half_still_over(client, "S15", movie)
    deep = doc.render(WORK / "s15-deep.png")
    doc.step("delete", clips=[still])
    flat = doc.render(WORK / "s15-flat.png")
    tagged = [profile(WORK / "s15-deep.png") if deep else None,
              profile(WORK / "s15-flat.png") if flat else None]
    delta = outer_delta(outer_columns(WORK / "s15-deep.png") if deep else None,
                        outer_columns(WORK / "s15-flat.png") if flat else None)
    check("S15 (PR-9) the HLG ramp under ramp16.png at scale 0.5 (a converting composition), "
          "at T, against the same frame with the still deleted: both 16-bit PNGs, sips "
          "profiles equal, outer columns within ±1 at 8-bit scaling",
          doc.ok and still is not None and png_depth(deep) == 16 and png_depth(flat) == 16
          and tagged[0] is not None and tagged[0] == tagged[1] and delta is not None
          and delta[1] <= 1,
          f"fixture {doc.why or 'ok'}; depths {png_depth(deep)} and {png_depth(flat)}; "
          f"profiles {tagged[0]!r} (with the still, the reader) and {tagged[1]!r} (without, "
          f"the generator); outer columns " + (
              f"mean |Δ| {delta[0]:.4f}, max |Δ| {delta[1]}" if delta else "unread"))
    return doc.close()


def sd_files(client, out_dir, sizes, pick=True):
    """Sd's files (B97, the CONTROL for S11) written into `out_dir`: a `gif`
    export and a `render_frame` JPEG of ramp16.png alone, an `apng` export of
    ramp8.png alone, and the 10-bit ramp clip's `apng` at the first of `sizes`
    whose file ffprobe reads 8-bit (`pick`, the capture), or at `sizes[0]`
    whatever it reads (S11, at the size DIR recorded). ({name: file name},
    the size or "no-redraw", detail, closed)."""
    closed, files, lines = True, {}, []
    doc = still_alone(client, "Sd-16", still16_png())
    if doc.export("gif", out_dir / "sd-gif16.gif") is not None:
        files["gif16"] = "sd-gif16.gif"
    got = doc.call("render_frame", t=T, path=str(out_dir / "sd-jpeg16.jpg"), format="jpeg")
    if got["ok"] and (out_dir / "sd-jpeg16.jpg").exists():
        files["jpeg16"] = "sd-jpeg16.jpg"
    lines.append(f"ramp16.png alone: fixture {doc.why or 'ok'}; jpeg {got.get('error', 'ok')}")
    closed = doc.close() and closed
    doc = still_alone(client, "Sd-8", still8_png())
    if doc.export("apng", out_dir / "sd-apng8.png") is not None:
        files["apng8"] = "sd-apng8.png"
    lines.append(f"ramp8.png alone: fixture {doc.why or 'ok'}")
    closed = doc.close() and closed
    doc = Doc(client, "Sd-10", 1920, 1080)
    doc.movie(doc.first_track(), ramp_clip())
    chosen = "no-redraw"
    for size in sizes:
        out = out_dir / "sd-apng10.png"
        movie = doc.export("apng", out, size=size)
        figures = apng_figures(movie) if movie else {}
        lines.append(f"10-bit ramp clip at {size}: {figures} (export at "
                     f"{doc.exported.get('width')}×{doc.exported.get('height')})")
        if movie is not None and (not pick or figures.get("pix_fmt") in PIX_EIGHT):
            chosen, files["apng10"] = size, "sd-apng10.png"
            break
    if chosen == "no-redraw" and (out_dir / "sd-apng10.png").exists():
        (out_dir / "sd-apng10.png").unlink()
    lines.append(f"fixture {doc.why or 'ok'}")
    closed = doc.close() and closed
    return files, chosen, "; ".join(lines), closed


def s3_render(client, path, out, video=None):
    """S3's scene: the 640×360 8-bit still at `path` alone on the 640×360
    canvas, with `video` (a `set_video` patch) when given, rendered at 0.5 s
    into `out`. (fixture why, PNG bytes, closed)."""
    doc = Doc(client, f"S3-{out.stem}")
    clip = doc.still(doc.first_track(), path)
    if clip is not None and video:
        doc.step("set_video", clips=[clip], patch=video)
    png = doc.render(out)
    return doc.why, png, doc.close()


def run_s(client, state):
    """S1, S2 and S4 (precision-2 P2-1, spec §11 PR-6): the 16-bit PNG and
    TIFF ramps against the in-run 8-bit control `ramp8.png` (computed once),
    and with `--control DIR` the control tree's own figures for each."""
    closed, got = True, {}
    wanted = (("png8", still8_png, {"S1", "S2", "S4", "S7"}), ("png16", still16_png, {"S1", "S4"}),
              ("tif16", still16_tif, {"S2"}), ("heic10", still10_heic, {"S7"}))
    for label, maker, rows_using in wanted:
        if selected & rows_using:
            path = maker()
            if path is None:  # only still10_heic can refuse here: S7 scores it
                got[label] = {"fixture": HEIC_REFUSED.get("why", f"{maker.__name__} made nothing")}
                print(f"       {label} figures: {got[label]}", flush=True)
                continue
            got[label], ok = still_figures(client, WORK, path, label)
            closed = ok and closed
            print(f"       {label} figures: {got[label]}", flush=True)
    control = state.get("stills") or {}
    eight = got.get("png8") or {}
    for row, label, name in (("S1", "png16", "PNG"), ("S2", "tif16", "TIFF"),
                             ("S7", "heic10", "HEIC (10-bit)")):
        if row not in selected:
            continue
        deep = got.get(label) or {}
        figures = [deep.get("distinct"), deep.get("rms"), (deep.get("tone") or [None])[0],
                   eight.get("rms"), (eight.get("tone") or [None])[0]]
        distinct, rms, tone, eight_rms, eight_tone = figures
        then = control.get(label)
        # A capture with Sd is B97's or later, so its tree drew stills deep
        # (PR-6): its figures are printed, not held to < STILL_DISTINCT (R1's rule).
        held = then is not None and "Sd" not in state
        good = (deep.get("fixture") == "ok" and eight.get("fixture") == "ok"
                and None not in figures and distinct >= STILL_DISTINCT and rms < eight_rms
                and tone <= TONE_MAX and eight_tone >= TONE_SEEN
                and (not held or (then.get("distinct") is not None
                                  and then["distinct"] < STILL_DISTINCT)))
        check(f"{row} a 1920×1080 {'' if row == 'S7' else '16-bit '}{name} ramp alone through prores_422: ≥ "
              f"{STILL_DISTINCT} distinct 10-bit codes on the middle row, luma RMS against "
              f"x/1919 under the 8-bit ramp8.png control's, staircase tone ≤ {TONE_MAX} where "
              f"the control's is ≥ {TONE_SEEN}" + (f", and the control tree's < "
                                                  f"{STILL_DISTINCT}" if held else ""),
              good,
              f"deep: fixture {deep.get('fixture')}, distinct {distinct}, RMS {rms}, tone "
              f"{deep.get('tone')}; 8-bit control: fixture {eight.get('fixture')}, distinct "
              f"{eight.get('distinct')}, RMS {eight_rms}, tone {eight.get('tone')}; control "
              f"tree: {then if then is not None else 'not given (--control DIR)'}"
              + ("" if held or then is None else " (a capture with Sd drew deep: printed, "
                 "not held)"))
    if "S4" in selected:
        deep = got.get("png16") or {}
        green = deep.get("green")
        picture = against_control(WORK / "still-png16.png", state, "still-png16.png")
        tagged = [profile(WORK / f"still-{label}.png") for label in ("png16", "png8")]
        check(f"S4 (PR-9, the owner 2026-10-13) render_frame of a project whose only picture is "
              f"the 16-bit ramp16.png is a 16-bit PNG whose middle row's green holds ≥ "
              f"{MIXED_DISTINCT} distinct values and whose RGB, scaled to 8 bits, is within ±1 "
              f"of the control tree's 8-bit render, and whose colour profile (sips) is "
              f"ramp8.png's (the generator's, same run); ramp8.png's is an 8-bit PNG",
              deep.get("png_depth") == 16 and green is not None and green >= MIXED_DISTINCT
              and picture["good"] and eight.get("png_depth") == 8
              and tagged[0] is not None and tagged[0] == tagged[1],
              f"ramp16.png depth {deep.get('png_depth')} (middle-row distinct green {green}); "
              f"{picture['detail']}; ramp8.png depth {eight.get('png_depth')} (distinct green "
              f"{eight.get('green')}); profiles {tagged[0]!r} and {tagged[1]!r}")
    if "S5" in selected:
        figures, ok = mixed_figures(client, WORK, h264_clip(), "h264")
        closed = ok and closed
        green = figures["green"]
        picture = against_control(WORK / "mixed-h264.png", state, "mixed-h264.png")
        check(f"S5 (PR-9) ramp16.png over the 8-bit H.264 clip: render_frame is a 16-bit PNG "
              f"whose middle row's green holds ≥ {MIXED_DISTINCT} distinct values and whose "
              f"RGB, scaled to 8 bits, is within ±1 of the control tree's 8-bit render",
              figures["fixture"] == "ok" and figures["png_depth"] == 16 and green is not None
              and green >= MIXED_DISTINCT and picture["good"],
              f"fixture {figures['fixture']}; depth {figures['png_depth']}; middle-row distinct "
              f"green {green}; {picture['detail']}")
    if "S6" in selected:
        figures, ok = mixed_figures(client, WORK, ramp_clip(), "ramp10")
        closed = ok and closed
        green = figures["green"]
        check(f"S6 (PR-4 as amended by PR-6) ramp16.png over the 10-bit ramp clip: render_frame "
              f"is a 16-bit PNG and the still (covering the frame) keeps its depth in it: the "
              f"middle row's green holds ≥ {MIXED_DISTINCT} distinct values",
              figures["fixture"] == "ok" and figures["png_depth"] == 16 and green is not None
              and green >= MIXED_DISTINCT,
              f"fixture {figures['fixture']}; depth {figures['png_depth']}; middle-row distinct "
              f"green {green}")
    return closed


# ---------------------------------------------------------------------------
# The modes.


def run_rows(client, state):
    clip = h264_clip()
    closed = True
    if "C0" in selected:
        doc, t = k_scene(client, "K3", clip)
        a, b = doc.render(WORK / "c0-a.png", t), doc.render(WORK / "c0-b.png", t)
        check("C0 CONTROL: two renders of K3 are byte-equal", doc.ok and a is not None
              and a == b, f"fixture {doc.why or 'ok'}; {digest(a)} vs {digest(b)}")
        closed = doc.close() and closed
    if selected & {"D1", "D2"}:
        doc, t = k_scene(client, "D1", clip)
        png = doc.render(WORK / "d1.png", t)
        check("D1 render_frame of an all-8-bit project (a card and the H.264 clip) is an 8-bit "
              "PNG (spec §11 PR-4)", doc.ok and png_depth(png) == 8,
              f"fixture {doc.why or 'ok'}; bit depth {png_depth(png)}")
        check("D2 (STOP, PR-4) with every source decoded 64RGBAHalf (PR2) the same project's "
              "render_frame is still an 8-bit PNG — a failure stops PR2 and returns PR-4 to the "
              "owner", doc.ok and png_depth(png) == 8,
              f"fixture {doc.why or 'ok'}; bit depth {png_depth(png)}; this tree's formats "
              f"{tree_formats()}")
        closed = doc.close() and closed
    if "P1" in selected:
        figure, detail, ok = p1_figure(client, WORK)
        closed = ok and closed
        control = state.get("P1", "not given (--control DIR)")
        check("P1 a 50 % gradient over black through prores_422: the middle row's luma "
              "against 0.5·g/255 is ≤ 1.0 10-bit steps RMS",
              figure is not None and figure <= 1.0,
              f"RMS {figure if figure is None else round(figure, 3)} (control {control}); "
              f"{detail}")
    if "H1" in selected:
        doc, _ = k_scene(client, "K6", clip)
        movie = doc.export("hevc", WORK / "h1.mp4")
        probe = ffprobe(movie) if movie else {}
        check("H1 an hevc export is Main, yuv420p", doc.ok and probe.get("profile") == "Main"
              and probe.get("pix_fmt") == "yuv420p", f"fixture {doc.why or 'ok'}; {probe}")
        closed = doc.close() and closed
    if selected & {"R1", "R2"}:
        distinct, rms, depth, ok = ramp_controls(client, WORK)
        closed = ok and closed
        FIGURES["R2"] = rms
        ramp = state.get("ramp") or {}
        control = ramp.get("distinct_green")
        # The control's ≤ 256 is PR2's: a capture whose tree decoded 32BGRA. A
        # later capture (precision-2's `ctl-p21`) decodes deep and is printed,
        # not held to it.
        decoded = (state.get("formats") or PR0_FORMATS).get("source") if state else None
        held = control is not None and decoded == PR0_FORMATS["source"]
        check("R1 render_frame of the 10-bit ramp on a 1920×1080 canvas is a 16-bit PNG whose "
              "middle row's green holds ≥ 850 distinct values (a 32BGRA-decoded control "
              "≤ 256)", depth == 16 and distinct is not None and distinct >= 850
              and (not held or control <= 256),
              f"bit depth {depth}; {distinct} distinct (control "
              f"{control if control is not None else 'not given (--control DIR)'}"
              + ("" if held or control is None else f", decoded {decoded}: printed, not held "
                 "to ≤ 256") + ")")
        check("R2 the ramp through prores_422: the middle row's luma against x/1919 is ≤ 1.0 "
              "10-bit steps RMS", rms is not None and rms <= 1.0,
              f"RMS {rms if rms is None else round(rms, 3)} (control "
              f"{ramp.get('prores_422_rms', 'not given (--control DIR)')})")
    if "C1" in selected:
        closed = run_c1(client, clip) and closed
    if selected & {"T1", "T2"}:
        closed = run_t(client) and closed
    if selected & {"S1", "S2", "S4", "S5", "S6", "S7"}:
        closed = run_s(client, state) and closed
    if selected & {"S8", "S10", "S14", "S15", "S16"}:
        closed = run_pr9(client) and closed
    if selected & set(V_ROWS):
        closed = run_v(client) and closed
    return closed


def run_t(client):
    """T1 and T2 (PR3): the 10-bit ramp exported `hevc_10bit` and `hevc` from
    one project in one run; each file's ffprobe, major brand, middle-row luma
    RMS against x/1919, distinct middle-row codes and staircase tone."""
    doc = Doc(client, "T", 1920, 1080)
    doc.movie(doc.first_track(), ramp_clip())
    got = {}
    for preset in ("hevc_10bit", "hevc"):
        movie = doc.export(preset, WORK / f"t-{preset}.mp4")
        measured = luma_row(movie, 1920, 1080) if movie else None
        codes, means = y10_columns(movie, 1920, 1080) if movie else (None, None)
        got[preset] = {"probe": ffprobe(movie) if movie else {},
                       "brand": major_brand(movie) if movie else None,
                       "rms": rms_steps(measured, [x / 1919 for x in range(1920)])
                       if measured else None,
                       "distinct": len(set(codes[16:-16])) if codes else None,
                       "tone": staircase_tone(means, 1920) if means else (None, None)}
    closed = doc.close()
    ten, eight = got["hevc_10bit"], got["hevc"]
    probe = ten["probe"]
    check("T1 a hevc_10bit export is hevc, Main 10, yuv420p10le, in an MP4",
          doc.ok and probe.get("codec_name") == "hevc" and probe.get("profile") == "Main 10"
          and probe.get("pix_fmt") == "yuv420p10le" and ten["brand"] in MP4_BRANDS,
          f"fixture {doc.why or 'ok'}; {probe}; major brand {ten['brand']!r}")
    a, b = ten["rms"], eight["rms"]
    tone, control = ten["tone"][0], eight["tone"][0]
    fmt = lambda v: None if v is None else round(v, 3)  # noqa: E731
    check("T2 the ramp through hevc_10bit: the middle row's luma against x/1919 is ≤ 2.0 "
          "10-bit steps RMS and ≤ ½ of hevc's in the same run, and the encoder was handed "
          f"deep frames — no 8-bit staircase: its tone ≤ {TONE_MAX} codes, where hevc's "
          f"(8-bit, the control) is ≥ {TONE_SEEN}",
          doc.ok and None not in (a, b, tone, control) and a <= 2.0 and a <= b / 2
          and tone <= TONE_MAX and control >= TONE_SEEN,
          f"hevc_10bit RMS {fmt(a)}; hevc RMS {fmt(b)} (half {fmt(b / 2 if b else None)}); "
          f"staircase tone (amplitude, floor) in codes: hevc_10bit "
          f"{[fmt(v) for v in ten['tone']]}, hevc {[fmt(v) for v in eight['tone']]}; distinct "
          f"10-bit Y codes on the middle row: hevc_10bit {ten['distinct']}, hevc "
          f"{eight['distinct']}; hevc {eight['probe']}, brand {eight['brand']!r}")
    return closed


def run_c1(client, clip):
    """C1: the H.264 clip at brightness −0.4 against max(0, its brightness-0
    render − 102), every colour channel within ±2. A deep-decoded frame
    arrives unclamped (spec §11 PR-2, −0.46…1.47); without `layerSample`'s
    `saturate` a channel above 1.0 reads 1.0 at brightness 0 (the output
    clamps) and above 0.6 at −0.4."""
    doc = Doc(client, "C1")
    made = [c for c in doc.movie(doc.first_track(), clip) if c is not None]
    base = doc.render(WORK / "c1-0.png")
    doc.step("set_video", clips=made, patch={"color": {"brightness": BRIGHTNESS}})
    took = [((c.get("video") or {}).get("color") or {}).get("brightness")
            for c in doc.project().get("clips") or [] if c.get("id") in made]
    dim = doc.render(WORK / "c1-dim.png")
    a, b = rgba(WORK / "c1-0.png"), rgba(WORK / "c1-dim.png")
    closed = doc.close()
    counts, white = {}, 0
    if a and b and len(a) == len(b):
        for i in range(len(a)):
            if i % 4 == 3:
                continue
            white += a[i] == 255
            d = abs(b[i] - max(0, a[i] - 102))
            counts[d] = counts.get(d, 0) + 1
    largest = max(counts) if counts else None
    check("C1 the H.264 clip at brightness −0.4: every colour channel within ±2 of "
          "max(0, its brightness-0 render − 102) — the source clamp holds a deep frame's "
          "values above 1.0", doc.ok and took == [BRIGHTNESS] and largest is not None
          and largest <= 2,
          f"fixture {doc.why or 'ok'}; brightness {took}; depths {png_depth(base)}/"
          f"{png_depth(dim)}; {white} channels read 255 at brightness 0; histogram |Δ|: "
          f"{short(dict(sorted(counts.items())))}")
    return closed


# ---------------------------------------------------------------------------
# The reverse (precision-2 P2-2, spec §11 PR-7).

REVERSE_BUILT = {}
FIGURES = {}


def build_reverse_probe(optimize=False):
    """`reverse_probe.swift` over `sources_folder` (this tree's `app/Sources`,
    or a mutant copy's) as a `main.swift` of its own, through
    `swift_build.build` — `build_encoder_probe`'s pattern — once a run.
    (binary, None) or (None, why): a probe that will not build is the probe
    rows' scored FAIL, never an exit."""
    if optimize in REVERSE_BUILT:
        return REVERSE_BUILT[optimize]
    folder = REVERSE_DIR / ("optimized" if optimize else "plain")
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    if not entry.exists() or entry.read_text() != REVERSE_PROBE.read_text():
        entry.write_text(REVERSE_PROBE.read_text())
    binary = folder / "reverse_probe"
    try:
        made = swift_build.build(sources=swift_build.app_sources(sources_folder) + [entry],
                                 output=binary, optimize=optimize, timeout=BUILD_BOUND)
    except swift_build.SwiftBuildFailed as error:
        REVERSE_BUILT[optimize] = (None, "reverse_probe did not build: swiftc rc "
                                   f"{error.rc if error.rc is not None else 'before running'}: "
                                   f"{(list(error.diagnostics) or [str(error)])[:6]}")
        print(f"       {REVERSE_BUILT[optimize][1]}", flush=True)
        return REVERSE_BUILT[optimize]
    print(f"  reverse probe{' (-O)' if optimize else ''}: "
          f"{'up to date' if made.reused else f'built in {made.seconds:.0f} s'} from "
          f"{sources_folder}", flush=True)
    REVERSE_BUILT[optimize] = (binary, None)
    return REVERSE_BUILT[optimize]


def reverse(source, label, optimize=False, refused=None):
    """One real reverse of `source` by the probe into `WORK/reverse-<label>.mov`:
    the probe's JSON with `dest` added, or {"ok": False, "error": why}."""
    if source is None:
        return {"ok": False, "error": (refused or {}).get("why", "no fixture")}
    binary, why = build_reverse_probe(optimize)
    if binary is None:
        return {"ok": False, "error": why}
    dest, out = WORK / f"reverse-{label}.mov", WORK / f"reverse-{label}.json"
    out.unlink(missing_ok=True)
    ran = bounded.run([str(binary), str(source), str(dest), str(out)], REVERSE_BOUND,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        got = json.loads(out.read_text())
    except (OSError, ValueError):
        return {"ok": False, "error": f"no answer (rc {ran['rc']}, expired {ran['expired']}): "
                                      f"{ran['stderr'][-300:]}"}
    got["dest"] = dest
    return got


def stamps(got):
    """`source_mirror_probe.py` §3's claims over one probe answer: as many
    frames written as the source has, the first at zero, strictly ascending,
    every stamp within one unit of `T − following`. (good, detail)."""
    drift = got.get("worstDrift")
    good = (got.get("ok") is True and (got.get("sourceFrames") or 0) > 0
            and got.get("writtenFrames") == got.get("sourceFrames")
            and got.get("firstIsZero") is True and got.get("ascending") is True
            and drift is not None and drift <= 1)
    return good, (f"stamps: {got.get('writtenFrames')} written of {got.get('sourceFrames')}, "
                  f"first zero {got.get('firstIsZero')}, ascending {got.get('ascending')}, "
                  f"worst drift {drift}")


def y10_ramp(path, width=1920, height=1080):
    """V0's reading of the 10-bit ramp: the first frame's middle-row Y codes
    (`y10_columns`), columns 16…W−16: (distinct, RMS in codes against
    64 + x·876/(W−1)), or (None, None)."""
    codes, _ = y10_columns(path, width, height)
    if not codes:
        return None, None
    columns = codes[16:-16]
    ideal = [64 + x * 876 / (width - 1) for x in range(16, width - 16)]
    rms = math.sqrt(sum((c - i) ** 2 for c, i in zip(columns, ideal)) / len(columns))
    return len(set(columns)), rms


def yuv_rows(path, width=1920, height=1080):
    """The first frame as `yuv420p10le`: the middle row's Y codes, and the
    middle row of each W/2 × H/2 chroma plane; or None."""
    raw = decode(path, "yuv420p10le")
    size, cw, ch = width * height, width // 2, height // 2
    if not raw or len(raw) < (size + 2 * cw * ch) * 2:
        return None
    values = struct.unpack(f"<{size + 2 * cw * ch}H", raw[:(size + 2 * cw * ch) * 2])
    y = values[(height // 2) * width:(height // 2 + 1) * width]
    cb = values[size + (ch // 2) * cw:size + (ch // 2 + 1) * cw]
    cr = values[size + cw * ch + (ch // 2) * cw:size + cw * ch + (ch // 2 + 1) * cw]
    return [list(y), list(cb), list(cr)]


def rgb48_row(path, width, height):
    """The middle row of a PNG decoded `rgb48le`, every channel; or None."""
    raw = decode(path, "rgb48le")
    if not raw or len(raw) != width * height * 6:
        return None
    return struct.unpack(f"<{width * 3}H", raw[(height // 2) * width * 6:(height // 2 + 1)
                                                * width * 6])


def fnv1a(text):
    """`ReverseCache.digest`'s FNV-1a 64 over `text`, hex zero-padded to 16."""
    value = 0xcbf2_9ce4_8422_2325
    for byte in text.encode():
        value = ((value ^ byte) * 0x0000_0100_0000_01b3) & 0xFFFF_FFFF_FFFF_FFFF
    return f"{value:016x}"


def wait_reverse(doc, media, tag, want=None):
    """Waits, polling every 0.25 s for at most REVERSE_BOUND, until
    `<doc>/cache/reversed/<media>-*.mov` exists (and the file `want`, when
    given: V4's planted file already matches the glob) with no `.partial`
    sibling AND `snapshot_ui(window="sheet")` refuses with "no sheet
    attached". (the files, None) or (the files, why) on expiry, after
    `cancel_sheet`."""
    if media is None:
        return [], "no media to wait for"
    folder = Path(doc.path) / "cache" / "reversed"
    deadline = time.monotonic() + REVERSE_BOUND
    while True:
        files = sorted(folder.glob(f"{media}-*.mov")) if folder.is_dir() else []
        partial = folder.is_dir() and any(folder.glob(f"{media}-*.partial"))
        if files and not partial and (want is None or want.exists()):
            got = doc.call("snapshot_ui", window="sheet", path=str(WORK / f"{tag}-sheet.png"))
            if not got["ok"] and "no sheet attached" in got.get("error", ""):
                return files, None
        if time.monotonic() > deadline:
            doc.call("cancel_sheet")
            return files, (f"the reverse did not finish within {REVERSE_BOUND} s (files "
                           f"{[f.name for f in files]}, partial {partial})")
        time.sleep(0.25)


def run_v(client):
    """V0–V6 (precision-2 P2-2, spec §11 PR-7): the real renderer through
    `reverse_probe.swift` (V0, V2, V5) and a reversed clip through the app
    (V1, V3, V4, V6)."""
    closed, ramp = True, ramp_clip()
    if "V0" in selected:
        got = reverse(ramp, "V0")
        probe = stream(got["dest"]) if got.get("ok") else {}
        distinct, rms = y10_ramp(got["dest"]) if got.get("ok") else (None, None)
        timed, timing = stamps(got)
        check(f"V0 the 10-bit ramp reversed by the real renderer is hevc, Main 10, yuv420p10le "
              f"at 1920×1080, its first frame's middle row ≥ {REVERSE_DISTINCT} distinct 10-bit Y "
              "codes at < 1.0 code RMS against 64 + x·876/1919, and its stamps hold "
              "(source_mirror_probe §3)",
              timed and probe.get("codec_name") == "hevc" and probe.get("profile") == "Main 10"
              and probe.get("pix_fmt") == "yuv420p10le"
              and (probe.get("width"), probe.get("height")) == (1920, 1080)
              and distinct is not None and distinct >= REVERSE_DISTINCT and rms < 1.0,
              f"{got.get('error') or 'rendered'}; {probe}; distinct {distinct}, RMS "
              f"{None if rms is None else round(rms, 3)} codes; {timing}")
    if "V1" in selected:
        doc = Doc(client, "V1", 1920, 1080)
        clip = (doc.movie(doc.first_track(), ramp) or [None])[0]
        forward, whose = FIGURES.get("R2"), "R2's, this run"
        if forward is None:
            movie = doc.export("prores_422", WORK / "v1-forward.mov")
            measured = luma_row(movie, 1920, 1080) if movie else None
            forward = rms_steps(measured, [x / 1919 for x in range(1920)]) if measured else None
            whose = "V1's own forward export"
        doc.step("set_reversed", clip=clip, reversed=True)
        files, late = wait_reverse(doc, getattr(doc, "media", {}).get(ramp), "v1")
        movie = None if late else doc.export("prores_422", WORK / "v1.mov")
        measured = luma_row(movie, 1920, 1080) if movie else None
        rms = rms_steps(measured, [x / 1919 for x in range(1920)]) if measured else None
        codes, _ = y10_columns(movie, 1920, 1080) if movie else (None, None)
        distinct = len(set(codes[16:-16])) if codes else None
        cache = stream(files[0]) if files else {}
        closed = doc.close() and closed
        check(f"V1 the reversed 10-bit ramp clip through prores_422: luma RMS against x/1919 ≤ "
              f"the forward clip's + {V1_MARGIN}, and ≥ {REVERSE_DISTINCT} distinct 10-bit Y "
              "codes on the middle row",
              doc.ok and late is None and None not in (rms, forward, distinct)
              and rms <= forward + V1_MARGIN and distinct >= REVERSE_DISTINCT,
              f"fixture {doc.why or 'ok'}; wait {late or 'ok'}; reversed RMS "
              f"{None if rms is None else round(rms, 3)}, forward "
              f"{None if forward is None else round(forward, 3)} ({whose}); distinct {distinct}; "
              f"the reverse file {[f.name for f in files]}: {cache}")
    if "V2" in selected:
        hlg = ramp_hlg()
        got = reverse(hlg, "V2", refused=HLG_REFUSED)
        probe = stream(got["dest"]) if got.get("ok") else {}
        a = yuv_rows(hlg) if hlg else None
        b = yuv_rows(got["dest"]) if got.get("ok") else None
        mean, each = None, None
        if a and b:
            deltas = [[abs(x - y) for x, y in zip(p, q)] for p, q in zip(a, b)]
            mean = sum(map(sum, deltas)) / sum(map(len, deltas))
            each = [round(sum(d) / len(d), 3) for d in deltas]
        timed, timing = stamps(got)
        check(f"V2 an HLG BT.2020 ramp reversed by the real renderer keeps {HLG_TAGS}, and its "
              f"middle row's Y, Cb and Cr codes are within mean |Δ| ≤ {V2_BOUND} of the "
              "source's first frame",
              timed and tags(probe) == HLG_TAGS and mean is not None and mean <= V2_BOUND,
              f"{got.get('error') or 'rendered'}; {probe}; mean |Δ| "
              f"{None if mean is None else round(mean, 3)} codes (Y, Cb, Cr {each}); {timing}")
    if "V3" in selected:
        closed = run_v3(client) and closed
    if "V4" in selected:
        closed = run_v4(client, ramp) and closed
    if "V5" in selected:
        odd = ramp_odd()
        got = reverse(odd, "V5", refused=ODD_REFUSED)
        probe = stream(got["dest"]) if got.get("ok") else {}
        timed, timing = stamps(got)
        check("V5 the 1919×1079 10-bit ramp reversed by the real renderer is prores, "
              "yuv422p10le, at exactly 1919×1079 (ffprobe and the track's natural size), and "
              "its stamps hold",
              timed and probe.get("codec_name") == "prores"
              and probe.get("pix_fmt") == "yuv422p10le"
              and (probe.get("width"), probe.get("height")) == (1919, 1079)
              and (got.get("width"), got.get("height")) == (1919, 1079),
              f"{got.get('error') or 'rendered'}; {probe}; natural size {got.get('width')}×"
              f"{got.get('height')}; {timing}")
    if "V6" in selected:
        clip_path = h264_clip()
        doc = Doc(client, "V6")
        clip = (doc.movie(doc.new_track(), clip_path) or [None])[0]
        doc.step("set_reversed", clip=clip, reversed=True)
        files, late = wait_reverse(doc, getattr(doc, "media", {}).get(clip_path), "v6")
        png = None if late else doc.render(WORK / "v6.png", T)
        cache = stream(files[0]) if files else {}
        closed = doc.close() and closed
        # PR-4 as amended by PR-7 (the owner, 2026-10-11, "Accept 16-bit"): a
        # reversed clip counts by its intermediate, which is 10-bit, so this
        # all-8-bit project renders 16-bit. On the old renderer (an 8-bit
        # H.264 reverse) the row FAILS, as expected: depth 8, h264/High.
        check("V6 (PR-4 as amended by PR-7) render_frame of a project whose one clip, the 8-bit "
              "H.264 clip, is reversed is a 16-bit PNG, its reverse hevc Main 10",
              doc.ok and late is None and png_depth(png) == 16
              and cache.get("codec_name") == "hevc" and cache.get("profile") == "Main 10",
              f"fixture {doc.why or 'ok'}; wait {late or 'ok'}; bit depth {png_depth(png)}; the "
              f"reverse file {[f.name for f in files]}: "
              f"{cache.get('codec_name')}/{cache.get('profile')}/{cache.get('pix_fmt')}")
    return closed


def run_v3(client):
    """V3: the HLG chroma ramp (`chroma_hlg`) forward at 0 and the same media
    reversed at 1 s, one Doc; `render_frame` at 0.5 s and 1.5 s, the middle
    rows' mean |Δ|. On the old renderer the reverse's picture was right (it
    converted through RGB and only its labels were wrong), so what tells the
    two apart here is its 8-bit rounding; the labels themselves are V2's,
    and a wrong label that changes the picture (`reverse-709-labels`,
    `reverse-no-attachments`) is what the chroma moves."""
    hlg = chroma_hlg()
    doc = Doc(client, "V3", 1920, 1080)
    clips = []
    if hlg is None:
        doc.note("ramp_hlg", {"ok": False, "error": HLG_REFUSED.get("why", "no fixture")})
    else:
        clips = doc.movie(doc.first_track(), hlg, repeats=2)
    second = clips[1] if len(clips) == 2 else None
    doc.step("set_reversed", clip=second, reversed=True)
    files, late = wait_reverse(doc, getattr(doc, "media", {}).get(hlg), "v3")
    a = None if late else doc.render(WORK / "v3-forward.png", T)
    b = None if late else doc.render(WORK / "v3-reversed.png", SEC + T)
    cache = stream(files[0]) if files else {}
    closed = doc.close()
    one = rgb48_row(WORK / "v3-forward.png", 1920, 1080) if a else None
    two = rgb48_row(WORK / "v3-reversed.png", 1920, 1080) if b else None
    mean = largest = None
    if one and two:
        deltas = [abs(x - y) for x, y in zip(one, two)]
        mean, largest = sum(deltas) / len(deltas) / 257, max(deltas) / 257
    check(f"V3 the HLG chroma ramp forward at 0.5 s and reversed at 1.5 s: render_frame's middle rows "
          f"agree within mean |Δ| ≤ {V3_BOUND} 8-bit levels over three channels",
          doc.ok and late is None and mean is not None and mean <= V3_BOUND,
          f"fixture {doc.why or 'ok'}; wait {late or 'ok'}; mean |Δ| "
          f"{None if mean is None else round(mean, 3)}, max "
          f"{None if largest is None else round(largest, 3)} levels; depths {png_depth(a)}/"
          f"{png_depth(b)}; the reverse file {[f.name for f in files]}: {tags(cache)} {cache}")
    return closed


def renderer_version():
    """`ReverseCache.rendererVersion` as the driven app's tree writes it
    (issue batch B98: V4 read a hard-coded 2 before), or None."""
    try:
        text = (Path(sources_folder).parents[1] / REVERSE_CACHE).read_text()
    except OSError:
        return None
    found = re.search(r"static let rendererVersion = (\d+)\n", text)
    return int(found.group(1)) if found else None


def run_v4(client, ramp):
    """V4: an old-named (pre-version) reverse planted in `cache/reversed/`
    before `set_reversed` is neither used nor kept."""
    doc = Doc(client, "V4", 1920, 1080)
    clip = (doc.movie(doc.first_track(), ramp) or [None])[0]
    media = getattr(doc, "media", {}).get(ramp)
    path = next((m.get("path") for m in doc.project().get("media") or []
                 if m.get("id") == media), None) or str(ramp)
    info = os.stat(path)
    named = f"{path}|{info.st_size}|{math.floor(info.st_mtime + 0.5)}"
    version = renderer_version()
    old, new = fnv1a(named), fnv1a(f"{named}|v{version}")
    folder = Path(doc.path) / "cache" / "reversed"
    folder.mkdir(parents=True, exist_ok=True)
    planted, fresh = folder / f"{media}-{old}.mov", folder / f"{media}-{new}.mov"
    shutil.copy2(h264_clip(), planted)
    doc.step("set_reversed", clip=clip, reversed=True)
    files, late = wait_reverse(doc, media, "v4", want=fresh)
    png = doc.render(WORK / "v4.png", T)
    closed = doc.close()
    row = rgb48_row(WORK / "v4.png", 1920, 1080) if png else None
    green = len({row[x * 3 + 1] for x in range(1920)}) if row else None
    check(f"V4 an old-named reverse planted before set_reversed is not used and is pruned: the "
          f"versioned file exists, the planted one is gone, and render_frame at 0.5 s holds ≥ "
          f"{MIXED_DISTINCT} distinct green values on its middle row (the ramp)",
          doc.ok and late is None and fresh.exists() and not planted.exists()
          and green is not None and green >= MIXED_DISTINCT,
          f"fixture {doc.why or 'ok'}; wait {late or 'ok'}; digest input {named!r}, renderer "
          f"version {version}; {fresh.name} exists {fresh.exists()}; planted {planted.name} exists "
          f"{planted.exists()}; files {[f.name for f in files]}; depth {png_depth(png)}, "
          f"distinct green {green}")
    return closed


def media_seconds(path):
    ran = bounded.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                       "default=noprint_wrappers=1:nokey=1", str(path)], 60)
    try:
        return float(ran["stdout"].strip())
    except ValueError:
        return None


def host_state():
    """`pmset -g`'s power mode lines, `pmset -g batt` and `sysctl vm.loadavg`."""
    power = bounded.run(["pmset", "-g"], 30)["stdout"]
    modes = [line.strip() for line in power.splitlines()
             if line.strip().split(" ")[0] in ("powermode", "lowpowermode")]
    battery = " | ".join(line.strip() for line in
                         bounded.run(["pmset", "-g", "batt"], 30)["stdout"].splitlines())
    load = bounded.run(["sysctl", "vm.loadavg"], 30)["stdout"].strip()
    return f"{'; '.join(modes)}; {battery}; {load}"


def run_reverse_cost():
    """`reverse-cost` (precision-2 P2-2, PR-7's measured cost): the probe
    built `-O`; four sources reversed three times each, one probe process a
    reverse; the median wall time, file size, rate and peak RSS. 0 iff every
    reverse completed."""
    print(f"precision — reverse-cost: the real renderer from {sources_folder}", flush=True)
    print(f"  host before: {host_state()}", flush=True)
    sources = (("prores422_1080", prores_clip(1080), None),
               ("prores422_2160", prores_clip(2160), None),
               ("prores422_odd", prores_odd(), ODD_REFUSED),
               ("ramp10_1080", ramp_clip(), None))
    done = total = 0
    for label, source, refused in sources:
        runs = []
        for n in range(3):
            total += 1
            got = reverse(source, f"cost-{label}-{n}", optimize=True, refused=refused)
            if got.get("ok"):
                done += 1
                probe = stream(got["dest"])
                seconds = media_seconds(got["dest"])
                got["mbps"] = (round(got["bytes"] * 8 / seconds / 1e6, 2)
                               if seconds else None)
                got["probe"] = (f"{probe.get('codec_name')}/{probe.get('profile')}/"
                                f"{probe.get('pix_fmt')} {probe.get('width')}×"
                                f"{probe.get('height')}")
                got["dest"].unlink(missing_ok=True)
            runs.append(got)
            print(f"  {label} #{n + 1}: " + (
                f"{got['seconds']:.3f} s, {got['bytes']} bytes, {got['mbps']} Mbps, peak RSS "
                f"{got['peakRSS'] / 1e6:.1f} MB, {got['probe']}" if got.get("ok")
                else f"FAILED — {got.get('error')}"), flush=True)
        good = [r for r in runs if r.get("ok")]
        if good:
            def median(key):
                values = sorted(r[key] for r in good if r.get(key) is not None)
                return values[len(values) // 2] if values else None
            print(f"  {label} median of {len(good)}: {median('seconds'):.3f} s, "
                  f"{median('bytes')} bytes, {median('mbps')} Mbps, peak RSS "
                  f"{(median('peakRSS') or 0) / 1e6:.1f} MB, {good[0]['probe']}", flush=True)
    print(f"  host after: {host_state()}", flush=True)
    print(f"{done}/{total} reverses completed")
    return 0 if done == total else 1


def ffprobe(path):
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt", "-of", "json", str(path)], 60)
    try:
        return (json.loads(ran["stdout"]).get("streams") or [{}])[0]
    except (ValueError, IndexError):
        return {}


def stream(path):
    """ffprobe's first video stream: codec, profile, pix_fmt, size and the
    three colour tags (precision-2 P2-2); {} when it reads nothing."""
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt,width,height,color_transfer,"
                       "color_primaries,color_space", "-of", "json", str(path)], 60)
    try:
        return (json.loads(ran["stdout"]).get("streams") or [{}])[0]
    except (ValueError, IndexError):
        return {}


def tags(probe):
    return (f"{probe.get('color_transfer')}/{probe.get('color_primaries')}/"
            f"{probe.get('color_space')}")


def major_brand(path):
    """The file's `ftyp` major brand as ffprobe reads it, or None."""
    ran = bounded.run(["ffprobe", "-v", "error", "-show_entries", "format_tags=major_brand",
                       "-of", "json", str(path)], 60)
    try:
        return ((json.loads(ran["stdout"]).get("format") or {}).get("tags") or {}).get(
            "major_brand")
    except ValueError:
        return None


def h264_pair(client, clip, out_dir, names):
    """`h264` exports of K6's scene over `clip`, one per name in `names`, each
    decoded to rgb24 (every frame); [(path, raw)]."""
    doc, _ = k_scene(client, "K6", clip)
    made = []
    for name in names:
        movie = doc.export("h264", out_dir / f"{name}.mp4")
        made.append((movie, decode(movie, "rgb24", frames=None) if movie else None))
    return made, doc.ok, doc.close()


def run_capture(client, where):
    where.mkdir(parents=True, exist_ok=True)
    clip = h264_clip()
    if clip is None:
        check("K CONTROL: the fixtures", False, "ffmpeg did not make the H.264 clip")
        return False
    shutil.copy2(clip, where / "k6.mp4")
    clip = where / "k6.mp4"
    record, closed = {"formats": tree_formats()}, True
    rendered = []
    for name in ("K1", "K2", "K3", "K4", "K5", "K6"):
        doc, t = k_scene(client, name, clip)
        png = doc.render(where / f"{name}.png", t)
        rendered.append((name, doc.why, digest(png)))
        closed = doc.close() and closed
    check("K CONTROL: K1–K6 rendered into DIR", all(not why and d for _, why, d in rendered)
          and len(record["formats"]) == 2,
          "; ".join(f"{n} {why or 'ok'} {d}" for n, why, d in rendered)
          + f"; this tree's formats {record['formats']}")
    pair, fixture, ok = h264_pair(client, clip, where, ("e0-a", "e0-b"))
    closed = ok and closed
    (_, a), (_, b) = pair
    record["E0"] = {"a": digest(a), "b": digest(b), "equal": a is not None and a == b,
                    "bytes": len(a or b"")}
    largest = max(histogram(a, b)) if a and b and len(a) == len(b) else None
    record["E0"]["largest"] = largest
    check("E0 CONTROL: two h264 exports of K6's clip decoded to rgb24, digests recorded",
          fixture and a is not None and b is not None and len(a) == len(b),
          f"{record['E0']}")
    figure, detail, ok = p1_figure(client, where)
    closed = ok and closed
    record["P1"] = None if figure is None else round(figure, 3)
    check("P1c CONTROL: P1's figure on this tree recorded", figure is not None,
          f"RMS {record['P1']} 10-bit steps; {detail}")
    distinct, rms, depth, ok = ramp_controls(client, where)
    closed = ok and closed
    record["ramp"] = {"distinct_green": distinct, "prores_422_rms": None if rms is None
                      else round(rms, 3), "png_depth": depth}
    check("Rc CONTROL: the ramp's render and prores_422 export recorded",
          distinct is not None and rms is not None, f"{record['ramp']}")
    stills = {}
    for label, maker in (("png16", still16_png), ("tif16", still16_tif), ("png8", still8_png)):
        stills[label], ok = still_figures(client, where, maker(), label)
        closed = ok and closed
    record["stills"] = stills
    record["S3"] = s3_capture(client, where)
    s3 = record["S3"]
    closed = s3.pop("closed") and closed
    check("Sc CONTROL: the three stills' figures (png16, tif16, png8) and S3's three 8-bit "
          "renders recorded", all(f["fixture"] == "ok" and None not in (f["distinct"], f["rms"], f["tone"])
                          for f in stills.values())
          and all(r["fixture"] == "ok" and r["digest"] for r in s3.values()),
          f"stills {stills}; S3 {s3}")
    files, size, detail, ok = sd_files(client, where, SD_SIZES)
    closed = ok and closed
    mixed, ok = mixed_figures(client, where, h264_clip(), "h264")
    closed = ok and closed
    record["Sd"] = {"files": {name: digest((where / file).read_bytes())
                              for name, file in files.items()},
                    "apng10_size": size, "mixed_h264": mixed}
    check("Sd CONTROL (B97): a gif export and a render_frame JPEG of ramp16.png, an apng "
          "export of ramp8.png, the 10-bit ramp clip's apng at a size today's resize redraws "
          "(or no-redraw), and S5's mixed-h264.png, into DIR",
          {"gif16", "jpeg16", "apng8"} <= set(files) and mixed["fixture"] == "ok"
          and (where / "mixed-h264.png").exists(),
          f"files {record['Sd']['files']}; 10-bit apng size {size}; mixed-h264 {mixed}; "
          f"{detail}")
    (where / "capture.json").write_text(json.dumps(record, indent=1, sort_keys=True))
    return closed


def s3_capture(client, where, keep=None):
    """S3's scenes rendered into DIR (`S3-<name>.png`, each fixture copied
    beside): {name: {fixture, png_depth, digest}, "closed": bool}. With
    `keep` (S3c: the recorded `S3`), a scene recorded there whose PNG is in
    DIR at its recorded digest is kept, not re-rendered, and a fixture copy
    already in DIR is not replaced."""
    s3, closed = {}, True
    for name, maker, video in S3_SCENES:
        recorded = (keep or {}).get(name) or {}
        png_path = where / f"S3-{name}.png"
        if (keep is not None and recorded.get("digest") and png_path.is_file()
                and digest(png_path.read_bytes()) == recorded["digest"]):
            s3[name] = recorded
            print(f"       S3 {name}: kept DIR's reference ({recorded['digest']})", flush=True)
            continue
        copy = where / maker().name
        if keep is None or not copy.exists():
            shutil.copy2(maker(), copy)
        why, png, ok = s3_render(client, copy, where / f"S3-{name}.png", video)
        closed = ok and closed
        s3[name] = {"fixture": why or "ok", "png_depth": png_depth(png), "digest": digest(png),
                    "video": video}
    s3["closed"] = closed
    return s3


def run_s3c(client, where):
    """`capture DIR --only S3c` (P2-1's fix pass): S3's scenes DIR lacks
    rendered into an EXISTING capture, its `capture.json`'s `S3` replaced and
    nothing else touched — the way a scene added after DIR was captured gets
    its reference. A scene already recorded, with its PNG in DIR at the
    recorded digest, is kept as it was (`s3_capture`'s `keep`), so a tree
    whose 8-bit draw changed cannot turn it into a self-comparison."""
    try:
        record = json.loads((where / "capture.json").read_text())
    except (OSError, ValueError):
        sys.exit(f"no capture at {where}; --only S3c adds to an existing capture")
    s3 = s3_capture(client, where, keep=record.get("S3") or {})
    closed = s3.pop("closed")
    record["S3"], record["S3_tree"] = s3, str(sources_folder.parents[1])
    check("S3c CONTROL: S3's three 8-bit renders recorded into the existing capture",
          all(r["fixture"] == "ok" and r["digest"] and r["png_depth"] == 8 for r in s3.values()),
          f"S3 {s3}; rendered on {sources_folder.parents[1]}")
    (where / "capture.json").write_text(json.dumps(record, indent=1, sort_keys=True))
    return closed


def against_ffmpeg(clip, renders):
    """Unscored (PR2): each K6 render's colour channels against ffmpeg's own
    decode of the clip's frame at 0.5 s (frame 15; BT.709, limited range,
    `accurate_rnd+full_chroma_int`) — which decode a reference decoder
    is nearer, for spec §11 PR-2's edge differences."""
    ref = decode(clip, "rgba", ["-vf", "select=eq(n\\,15)", "-sws_flags",
                                "bicubic+accurate_rnd+full_chroma_int"])
    if not ref or len(ref) != W * H * 4:
        return "against ffmpeg's decode (unscored): no reference frame"
    parts = []
    for label, data in renders.items():
        if not data or len(data) != len(ref):
            parts.append(f"{label} n/a")
            continue
        deltas = [abs(a - b) for i, (a, b) in enumerate(zip(data, ref)) if i % 4 != 3]
        parts.append(f"{label} mean |Δ| {sum(deltas) / len(deltas):.3f}, "
                     f"≥ 5 on {sum(d >= 5 for d in deltas)}, largest {max(deltas)}")
    return "against ffmpeg's decode (unscored): " + "; ".join(parts)


def run_compare(client, where):
    try:
        record = json.loads((where / "capture.json").read_text())
    except (OSError, ValueError):
        sys.exit(f"no capture at {where}; run `capture` on the control tree first")
    clip, closed = where / "k6.mp4", True
    then, now = record.get("formats") or PR0_FORMATS, tree_formats()
    same_output = then.get("output") == now.get("output")
    same_source = then.get("source") == now.get("source")
    print(f"  formats: control {then}, this tree {now}", flush=True)
    for name in ("K1", "K2", "K3", "K4", "K5", "K6"):
        if name not in selected:
            continue
        doc, t = k_scene(client, name, clip)
        doc.render(WORK / f"{name}.png", t)
        got, want = rgba(WORK / f"{name}.png"), rgba(where / f"{name}.png")
        closed = doc.close() and closed
        counts = histogram(got, want) if got and want else {}
        largest = max(counts) if counts else None
        # K1 is one opaque card: exact always. K2–K5 (no video) are exact
        # when the working depth is the control's (PR2 against PR1), within
        # ±2 across it (PR1 against PR0). K6 (video) is exact when the decode
        # is the control's, and across it (PR2 against PR1) its histogram is
        # recorded, not scored (spec §11 PR-2's ±1 on video).
        rule = ("exact" if name == "K1" or (name != "K6" and same_output)
                or (name == "K6" and same_source) else "recorded" if name == "K6" else "two")
        good = doc.ok and got is not None and want is not None and len(got) == len(want) and (
            got == want if rule == "exact" else rule == "recorded" or largest <= 2)
        extra = ""
        if name == "K6":
            extra = "\n       " + against_ffmpeg(clip, {"this tree": got, "DIR": want})
        check(f"{name} against the control: " + {
            "exact": "byte-identical", "two": "every channel within ±2",
            "recorded": "the histogram recorded (the decode moved, spec §11 PR-2)"}[rule], good,
              f"fixture {doc.why or 'ok'}; histogram |Δ|: channels {short(counts)}{extra}")
    if "E1" in selected:
        closed = run_e1(client, where, clip, record, same_source) and closed
    if "E2" in selected:
        closed = run_e2(client, where, clip, same_source) and closed
    if "S3" in selected:
        good, lines = True, []
        for name, maker, video in S3_SCENES:
            file = maker().name
            why, png, ok = s3_render(client, where / file, WORK / f"S3-{name}.png", video)
            closed = ok and closed
            got, want = rgba(WORK / f"S3-{name}.png"), rgba(where / f"S3-{name}.png")
            counts = histogram(got, want) if got and want and len(got) == len(want) else {}
            good = (good and why is None and got is not None and got == want
                    and png_depth(png) == 8)
            lines.append(f"{name} ({file}{', ' + json.dumps(video) if video else ''}): fixture "
                         f"{why or 'ok'}; depth {png_depth(png)}; "
                         f"histogram |Δ| against DIR's: channels {short(counts)}")
        check("S3 an 8-bit still's render_frame (opaque; with an alpha ramp; the alpha ramp "
              "under a colour control) is an 8-bit PNG byte-identical to DIR's", good,
              "\n       ".join(lines))
    if "S11" in selected:
        closed = run_s11(client, where, record) and closed
    return closed


def run_s11(client, where, record):
    """S11 (B97, PR-9): Sd's files made again on this tree, each byte-identical
    to DIR's — GIF and JPEG stay 8-bit, an APNG with no deep still is today's,
    and a deep video source's APNG at a size the resize redraws is too (skipped
    by name when DIR recorded `no-redraw`)."""
    sd = record.get("Sd")
    if not sd:
        check("S11 GIF, JPEG and still-less APNG files byte-identical to DIR's", False,
              "DIR has no Sd (captured before B97)")
        return True
    size = sd.get("apng10_size")
    redraw = size not in (None, "no-redraw")
    if not redraw:
        skip("S11's 10-bit apng", "DIR recorded no-redraw: no size made today's resize redraw")
    files, _, detail, closed = sd_files(client, WORK, [size] if redraw else [], pick=False)
    good, lines = True, []
    for name, want in sorted(sd.get("files", {}).items()):
        got = (WORK / files[name]).read_bytes() if name in files else None
        same = got is not None and digest(got) == want
        good = good and same
        lines.append(f"{name}: {digest(got)} against DIR's {want} "
                     f"({'byte-identical' if same else 'DIFFERENT'}"
                     + (f", {len(got)} bytes" if got is not None else ", not written") + ")")
    check("S11 (PR-9) a gif export and a render_frame JPEG of ramp16.png, an apng export of "
          "ramp8.png" + (f", and the 10-bit ramp clip's apng at {size}" if redraw else "")
          + ": each file byte-identical to DIR's", good and bool(sd.get("files")),
          "\n       ".join(lines + [detail]))
    return closed


# ---------------------------------------------------------------------------
# E1 — the h264 encoder's input (the orchestrator's ruling after PR0).


def build_encoder_probe():
    """`precision_encoder_probe.swift` over `sources_folder` (the tree's
    `app/Sources`, or a mutant copy's), beside that tree's `Compositor.metal`
    as `default.metallib` and `Blank.mp4`. (binary, None) or (None, why)."""
    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    entry = PROBE_DIR / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    binary = PROBE_DIR / "precision_encoder_probe"
    try:
        made = swift_build.build(sources=swift_build.app_sources(sources_folder) + [entry],
                                 output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc rc {error.rc if error.rc is not None else 'before running'}: "
                      f"{(error.diagnostics or ['(no output)'])[:6]}")
    print(f"  encoder probe: {'up to date' if made.reused else f'built in {made.seconds:.0f} s'}"
          f" from {sources_folder}", flush=True)
    resources = sources_folder.parent / "Resources"
    shader, air, library = (resources / "Shaders/Compositor.metal", PROBE_DIR / "Compositor.air",
                            PROBE_DIR / "default.metallib")
    library.unlink(missing_ok=True)
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
                       300)
    if step["rc"] == 0:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o", str(library)],
                           300)
    if step["rc"] != 0 or not library.exists():
        return None, f"the shader did not build: {step['stderr'][-400:]}"
    shutil.copy2(resources / "Blank.mp4", PROBE_DIR / "Blank.mp4")
    return binary, None


def handed_frames(client, where, clip, preset, prefix, same_source):
    """K6's and K3's scenes saved, the encoder probe's frames handed to
    `preset`'s encoder against DIR's renders: (good, detail, closed). K6's
    bound is 0 when this tree decodes as the control did; across a decode
    change (PR2 against PR1) it is the largest |Δ| of this tree's own K6
    render against DIR's — the re-baseline rule's "within K6's histogram" —
    and the handed frame must equal that render byte for byte."""
    closed, frames, bounds, own = True, [], {"K6": 0, "K3": 1}, {}
    for name in ("K6", "K3"):
        doc, t = k_scene(client, name, clip)
        if name == "K6" and not same_source:
            doc.render(WORK / f"{prefix}-K6.png", t)
            own = rgba(WORK / f"{prefix}-K6.png")
            want = rgba(where / "K6.png")
            counts = histogram(own, want) if own and want and len(own) == len(want) else {}
            bounds["K6"] = max(counts) if counts else None
        doc.step("save_project")
        frames.append({"tag": name, "package": str(doc.path), "tick": t, "preset": preset,
                       "raw": str(WORK / f"{prefix}-{name}.bgra"), "why": doc.why})
        closed = doc.close() and closed
    binary, why = build_encoder_probe()
    answer = {}
    if binary is not None:
        request, out = WORK / f"{prefix}-request.json", WORK / f"{prefix}-answer.json"
        request.write_text(json.dumps({"frames": frames,
                                       "fonts": str(sources_folder.parent / "Resources/Fonts")}))
        ran = bounded.run([str(binary), str(request), str(out)], 300, cwd=str(PROBE_DIR),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
        try:
            answer = {row["tag"]: row for row in json.loads(out.read_text())["frames"]}
        except (OSError, ValueError, KeyError):
            why = f"no answer (rc {ran['rc']}, expired {ran['expired']}): {ran['stderr'][-300:]}"
    good, lines = binary is not None and bool(answer), []
    for frame in frames:
        name = frame["tag"]
        got = answer.get(name, {})
        want = rgba(where / f"{name}.png")
        handed = None
        if got.get("format") == "BGRA" and got.get("raw") and Path(got["raw"]).exists():
            bgra = Path(got["raw"]).read_bytes()
            handed = bytearray(bgra)
            handed[0::4], handed[2::4] = bgra[2::4], bgra[0::4]
            handed = bytes(handed)
        counts = histogram(handed, want) if handed and want and len(handed) == len(want) else {}
        largest = max(counts) if counts else None
        bound = bounds[name]
        ok = (frame["why"] is None and handed is not None and largest is not None
              and bound is not None and largest <= bound)
        if name == "K6" and not same_source:
            # Across a decode change the handed frame must also be this
            # tree's own 8-bit render exactly: the rounding is the render's.
            mine = histogram(handed, own) if handed and own and len(handed) == len(own) else {}
            ok = ok and mine == {0: len(handed or b"")}
            lines.append(f"K6 handed against this tree's own render (byte-identical): {short(mine)}")
        good = good and ok
        claim = ("byte-identical" if bound == 0 and name == "K6" else
                 f"within ±{bound}" + (" (this tree's K6 render against DIR's)"
                                       if name == "K6" else ""))
        lines.append(f"{name} ({claim}): "
                     f"{'ok' if ok else 'FAIL'}; fixture {frame['why'] or 'ok'}; form "
                     f"{got.get('form')}, handed {got.get('format')} {got.get('width')}×"
                     f"{got.get('height')} at {got.get('time')} s"
                     + (f", error {got['error']}" if got.get("error") else "")
                     + f"; histogram |Δ| against DIR's render: {short(counts)}")
    detail = ((f"probe {why or 'ok'}\n       " if why or binary is None else "")
              + "\n       ".join(lines))
    return good, detail, closed


def run_e1(client, where, clip, record, same_source):
    """E1: the frames handed to the h264 encoder against DIR's renders; the
    encoded K6 file printed, unscored."""
    good, detail, closed = handed_frames(client, where, clip, "h264", "e1", same_source)
    pair, fixture, ok = h264_pair(client, clip, WORK, ("e1",))
    closed = ok and closed
    encoded = pair[0][1]
    a = decode(where / "e0-a.mp4", "rgb24", frames=None)
    unscored = (f"the encoded file (unscored): E1 {digest(encoded)} against E0 "
                f"{record.get('E0', {}).get('a')} / {record.get('E0', {}).get('b')}, "
                f"|Δ| against E0 a {short(histogram(encoded, a)) if encoded and a and len(encoded) == len(a) else 'n/a'}")
    check("E1 the frame ExportWriter hands the h264 encoder is 32BGRA and equals DIR's 8-bit frame "
          "(K6 byte-identical, or across a decode change within K6's own |Δ| and byte-identical "
          "to this tree's render; K3, blended, within ±1 — the compositor's own ±1 at 16-bit "
          "float)",
          good, detail + "\n       " + unscored)
    return closed


def run_e2(client, where, clip, same_source):
    """E2: the frames handed to the hevc (Main) encoder against DIR's renders."""
    good, detail, closed = handed_frames(client, where, clip, "hevc", "e2", same_source)
    check("E2 the frame ExportWriter hands the hevc (Main) encoder is 32BGRA and equals DIR's "
          "8-bit frame (K6 byte-identical, or across a decode change within K6's own |Δ| and "
          "byte-identical to this tree's render; K3, blended, within ±1) — fed half-float frames it "
          "encoded the ramp at 9.04 steps RMS against PR0's 6.46", good, detail)
    return closed


# ---------------------------------------------------------------------------
# M1 (--measure).


def footprint(pid):
    """(phys_footprint, phys_footprint_peak) in bytes, or None when refused."""
    ran = bounded.run(["footprint", "-f", "bytes", "-p", str(pid)], 30)
    now = re.search(r"phys_footprint: (\d+) B", ran["stdout"])
    peak = re.search(r"phys_footprint_peak: (\d+) B", ran["stdout"])
    return (int(now.group(1)), int(peak.group(1))) if now and peak else None


def m1_fixture(client, kind, height):
    """M1's TYPICAL or HEAVY project at `height`, 8 s of the 2 s movie looped."""
    width = height * 16 // 9
    doc = Doc(client, f"m1-{kind}-{height}", width, height)
    movie, title_track = prores_clip(height), None
    v1 = doc.first_track()
    loop = doc.movie(v1, movie, repeats=4, seconds=2)
    small = {"scale": 0.5, "x": width / 4, "y": -height / 4}
    if kind == "typical":
        for clip in doc.movie(doc.new_track(), movie, repeats=4, seconds=2):
            doc.step("set_video", clips=[clip], patch=small)
        title_track = doc.new_track()
    else:
        # A routed dissolve (spec §11 MT-8): v1's four clips nested, the nest
        # clip split at 4 s, a 1 s cross dissolve from the first half's tail.
        doc.step("nest", clips=loop)
        nest = [c["id"] for c in doc.project().get("clips") or []
                if (c.get("source") or {}).get("kind") == "nest"]
        if len(nest) == 1:
            doc.step("split", clips=nest, at=4 * SEC)
            halves = sorted((c["start"], c["id"]) for c in doc.project().get("clips") or []
                            if (c.get("source") or {}).get("kind") == "nest")
            if len(halves) == 2:
                doc.step("add_transition", clip=halves[1][1], kind="cross_dissolve",
                         duration=SEC, align="after")
        for n, (patch, matte) in enumerate((
                (dict(small, shadow={"color": [0, 0, 0, 1], "opacity": 0.8, "blur": 10,
                                     "distance": 20, "angle": 315}), "alpha"),
                ({"scale": 0.5, "x": -width / 4, "y": height / 4}, "luma"),
                ({"scale": 0.35}, None))):
            track = doc.new_track()
            for clip in doc.movie(track, movie, repeats=4, seconds=2):
                doc.step("set_video", clips=[clip], patch=patch)
            if matte:
                window = doc.new_track()
                fill = {"fill": [1, 1, 1, 1], "width": width // 2, "height": height // 2}
                if matte == "luma":
                    fill["gradient"] = GRADIENT
                doc.shape(window, fill, duration=8 * SEC, video={"x": patch["x"],
                                                                 "y": patch["y"]})
                doc.step("set_track", track=window, matte=matte)
        title_track = doc.new_track()
    doc.title(title_track, duration=8 * SEC)
    return doc


def m1_measure(binary, kind, height, label=""):
    """One M1 export, on an instance of its own so its lifetime
    `phys_footprint_peak` is this fixture's; (its figures, its log)."""
    log = WORK / f"m1-{kind}-{height}{label}.log"
    launched = mcp.launch(str(binary), ["-FrameJobCompositorTiming", "YES"],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            return {"fixture": f"the app did not listen at {launched.socket_path}",
                    "exported": False, "windows": 0, "closed": False}, log
        return m1_export(launched, kind, height), log
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)


def m1_export(launched, kind, height):
    client, pid, log = launched.client, launched.child.pid, Path(launched.log_path)
    doc = m1_fixture(client, kind, height)
    figures = {"fixture": doc.why or "ok"}
    before = footprint(pid)
    offset = log.stat().st_size
    out = WORK / f"m1-{kind}-{height}.mov"
    result = {}
    worker = threading.Thread(target=lambda: result.update(movie=doc.export("prores_422", out)))
    started = time.monotonic()
    worker.start()
    samples = []
    while worker.is_alive():
        tick = time.monotonic()
        sample = footprint(pid)
        if sample:
            samples.append(sample[0])
        worker.join(max(0.0, 0.5 - (time.monotonic() - tick)))
    figures["export_s"] = round(time.monotonic() - started, 2)
    figures["exported"] = result.get("movie") is not None
    after = footprint(pid)
    with open(log, errors="replace") as handle:
        handle.seek(offset)
        windows = [(float(a), float(w)) for a, w in TIMING.findall(handle.read())]
    figures["windows"] = len(windows)
    if windows:
        figures["average_ms"] = round(sum(a for a, _ in windows) / len(windows), 3)
        figures["worst_ms"] = max(w for _, w in windows)
    if before is None or after is None:
        figures["footprint"] = "refused"
    else:
        # The instance's lifetime peak, read after the export: an export is
        # shorter than a few 0.5 s samples, so the samples alone miss it.
        figures["before_bytes"] = before[0]
        figures["peak_bytes"] = after[1]
        figures["sampled_peak_bytes"] = max(samples) if samples else None
        figures["samples"] = len(samples)
    if out.exists():
        out.unlink()
    figures["closed"] = doc.close()
    return figures


def run_measure(binary, mode, where, logs):
    where.mkdir(parents=True, exist_ok=True)
    figures = {}
    for kind in ("typical", "heavy"):
        for height in (1080, 2160):
            figures[f"{kind}-{height}"], log = m1_measure(binary, kind, height)
            logs.append(log)
            print(f"  {kind} {height}p: {figures[f'{kind}-{height}']}", flush=True)
    measured = all(f["fixture"] == "ok" and f["exported"] and f["windows"] > 0
                   for f in figures.values())
    refused = any(f.get("footprint") == "refused" for f in figures.values())
    if refused:
        skip("M1 memory", "`footprint -p` was refused on this host")
    path = where / "measure.json"
    if mode == "capture":
        path.write_text(json.dumps(figures, indent=1, sort_keys=True))
        check("M1 CONTROL: timing and footprint recorded for both fixtures at both sizes",
              measured, f"written to {path}")
        return all(f["closed"] for f in figures.values())
    try:
        control = json.loads(path.read_text())
    except (OSError, ValueError):
        sys.exit(f"no measure capture at {where}; run `--measure capture` on the control tree")
    stops = []
    for key, now in figures.items():
        then = control.get(key, {})
        height = int(key.split("-")[1])
        line = (f"{key}: average {then.get('average_ms')} → {now.get('average_ms')} ms, worst "
                f"{then.get('worst_ms')} → {now.get('worst_ms')} ms")
        if "peak_bytes" in now and "peak_bytes" in then:
            delta = now["peak_bytes"] - then["peak_bytes"]
            line += (f"; peak {then['peak_bytes'] / 1e6:.1f} → {now['peak_bytes'] / 1e6:.1f} MB "
                     f"(Δ {delta / 1e6:+.1f} MB, {delta / PER_BUFFER[height]:+.1f} buffers)")
        if key == "heavy-1080" and (now.get("average_ms") or 0) >= STOP_MS:
            stops.append(f"heavy 1080p average {now.get('average_ms')} ms ≥ 8 ms")
        print(f"       {line}", flush=True)
    check("M1 measured beside the control (memory printed and recorded; the owner retired the "
          "+532 MB stop, spec §11 PR-1), and no frame-time stop (1080p heavy average < 8 ms)",
          measured and not stops,
          f"stops: {stops or 'none'}")
    return all(f["closed"] for f in figures.values())


def run_ab(tree_binary, copy_binary, rounds):
    """MA (PR2's review, recorded in PR3): the heavy 2160p fixture exported on
    this tree's Release app and on the `decode-8bit` copy's, alternated
    (ABBA…) `rounds` times so both see the same load. The compositor averages,
    their medians and the deep decode's share."""
    runs, logs = {"tree": [], "decode-8bit": []}, []
    for n in range(rounds):
        order = [("tree", tree_binary), ("decode-8bit", copy_binary)]
        for label, binary in (order if n % 2 == 0 else order[::-1]):
            figures, log = m1_measure(binary, "heavy", 2160, f"-{label}-{n}")
            logs.append(log)
            runs[label].append(figures)
            print(f"  round {n + 1} {label}: average {figures.get('average_ms')} ms, worst "
                  f"{figures.get('worst_ms')} ms, export {figures.get('export_s')} s, "
                  f"{figures.get('windows')} windows, fixture {figures['fixture']}", flush=True)
    measured = all(f["fixture"] == "ok" and f["exported"] and f["windows"] > 0
                   for one in runs.values() for f in one)
    median = {k: sorted(f.get("average_ms") or 0 for f in v)[len(v) // 2] for k, v in runs.items()}
    export = {k: sorted(f.get("export_s") or 0 for f in v)[len(v) // 2] for k, v in runs.items()}
    share = (round(median["tree"] / median["decode-8bit"], 3)
             if median["decode-8bit"] else None)
    check("MA the heavy 2160p export's compositor average, this tree (64RGBAHalf sources) "
          "against the decode-8bit copy (32BGRA), alternated on one host load", measured,
          f"medians {median} ms (tree ÷ copy {share}); export medians {export} s; "
          f"averages tree {[f.get('average_ms') for f in runs['tree']]}, copy "
          f"{[f.get('average_ms') for f in runs['decode-8bit']]}")
    return all(f["closed"] for one in runs.values() for f in one), logs


def run_core_mutant(name):
    """A core mutant: the copy's `core/` made its own, the anchors replaced,
    and `cargo test` of the two export files in it (row CT). No app."""
    from hevc_alpha_proof import own_core
    dest = BASE / "mutant"
    made, reason = tree_copy.make_copy(str(dest), agent=False)
    atexit.register(tree_copy.remove_tree, str(dest))
    if made is None:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    copy = Path(made)
    reason = own_core(copy)
    if reason is None:
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            reason = f"the copy's core/tests could not be linked: {error}"
    reason = reason or replace_anchors(copy, name)
    if reason:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "export",
                       "--test", "export_hevc_10bit"], 900, cwd=str(copy / "core"))
    out = ran["stdout"] + ran["stderr"]
    if ran["expired"] or "test result:" not in out:
        print(f"mutant {name}: the control could not be performed — cargo rc {ran['rc']}, "
              f"expired {ran['expired']}: {out[-600:]}")
        return 2
    failed = [t for t in CORE_TESTS if re.search(rf"^test {t} \.\.\. FAILED$", out, re.M)]
    every = re.findall(r"^test (\w+) \.\.\. FAILED$", out, re.M)
    print(("  ok   " if ran["rc"] == 0 else "  FAIL ") + "CT cargo test --test export --test "
          f"export_hevc_10bit in the copy's core\n       failed: {every}", flush=True)
    caught = ran["rc"] != 0 and failed == list(CORE_TESTS)
    print(("MUTANT PASS" if caught else "MUTANT FAILURE") + f": {name} — CT "
          + ("FAILED" if ran["rc"] != 0 else "passed")
          + f"; named tests failed: {failed} (want {list(CORE_TESTS)})")
    return 0 if caught else 1


def selftest():
    """S1–S3: `app_tree` over scratch trees, and main's refusal; no app."""
    results = []

    def row(name, good, detail):
        results.append(bool(good))
        print(("  ok   " if good else "  FAIL ") + name + f"\n       {detail}", flush=True)

    print("precision (B94) — the selftest: which sources an app's formats are read from")
    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        tree = scratch / "tree"
        (tree / "app/Sources").mkdir(parents=True)
        (tree / "app/Sources/Compositor.swift").write_text(
            "    static let outputPixelFormat: OSType = kCVPixelFormatType_TEST_OUT\n"
            "    static let sourcePixelFormat: OSType = kCVPixelFormatType_TEST_SRC\n")
        inside = tree / "build/Build/Products/Release/Frame Job.app/Contents/MacOS/Frame Job"
        inside.parent.mkdir(parents=True)
        inside.write_text("")
        found = app_tree(inside)
        formats = tree_formats(found / "app/Sources") if found else {}
        row("S1 an app under a tree's build/Build/Products reads THAT tree's formats",
            found == tree and formats == {"output": "kCVPixelFormatType_TEST_OUT",
                                          "source": "kCVPixelFormatType_TEST_SRC"},
            f"tree {found}; formats {formats}")
        outside = scratch / "elsewhere/Frame Job.app/Contents/MacOS/Frame Job"
        outside.parent.mkdir(parents=True)
        outside.write_text("")
        bare = proof_app.executable(scratch / "bare/build/Build/Products/Debug/Frame Job Debug.app")
        bare.parent.mkdir(parents=True)
        bare.write_text("")
        ran = bounded.run([sys.executable, str(Path(__file__).resolve()), "--app", str(outside),
                           "--only", "D1"], 120)
        refused = "is not a product of a tree" in ran["stdout"]
        row("S2 an app outside any tree (or under a build folder with no app/Sources) is "
            "refused, exit 2, before any launch",
            app_tree(outside) is None and app_tree(bare) is None and ran["rc"] == 2
            and refused and "instance PID" not in ran["stdout"],
            f"outside {app_tree(outside)}; bare {app_tree(bare)}; main rc {ran['rc']}: "
            f"{ran['stdout'].strip().splitlines()[-1:] if ran['stdout'].strip() else ran['stderr'][-200:]}")
    default = proof_app.binary()
    row("S3 the default app (no --app) is this tree's, so its formats are this tree's",
        app_tree(default) == ROOT, f"{default} → {app_tree(default)}")
    print(f"{sum(results)}/{len(results)}")
    return 0 if all(results) else 1


# ---------------------------------------------------------------------------


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        return [f"{log} could not be read"]


def tail(log, count=4):
    try:
        lines = [line.rstrip() for line in open(log, errors="replace")]
    except OSError:
        return [f"{log} could not be read"]
    return lines[-count:] or ["(empty)"]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def replace_anchors(copy, name):
    """Every anchor of `name` replaced in `copy`, each found exactly once (in
    order, so a later anchor sees an earlier one's text); None, or why not."""
    for path, anchor, replacement in MUTANTS[name]["anchors"]:
        target = copy / path
        if not target.resolve().is_relative_to(BASE / "mutant"):
            return f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    return None


def build_mutant(name, release_only=None):
    """A copy of the tree with every anchor of `name` replaced (each found
    once), built by `tree_copy.build_app`. (app bundle, copy) or (None, why)."""
    made, reason = tree_copy.make_copy(str(BASE / "mutant"))
    atexit.register(tree_copy.remove_tree, str(BASE / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    reason = replace_anchors(copy, name)
    if reason:
        return None, reason
    print(f"  building the copy ({len(MUTANTS[name]['anchors'])} anchor(s) replaced, each found "
          "once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND, release_only=release_only)
    return (app, copy) if app is not None else (None, reason)


def mutant_pf(copy):
    """`preview_refresh_probe.py --sources <copy>/app/Sources`: whether its PF
    row passed (None when the probe printed no PF line), and the line."""
    ran = bounded.run([sys.executable, str(ROOT / "tools/proof/preview_refresh_probe.py"),
                       "--sources", str(copy / "app/Sources")], 900)
    lines = [line.strip() for line in ran["stdout"].splitlines()
             if line.strip().startswith(("ok   PF", "FAIL PF", "skip PF"))]
    for line in lines:
        if line.startswith("ok   PF"):
            return True, line
        if line.startswith("FAIL PF"):
            return False, line
    return None, (lines or [f"no PF line (rc {ran['rc']}): {ran['stdout'][-300:]}"])[0]


def main_ab(rounds):
    """`--measure ab --mutant decode-8bit`: MA and Z1 (release-only)."""
    global selected
    selected = {"MA", "Z1"}
    tree_binary = Path(proof_app.binary(release_only=RELEASE_ONLY))
    print(f"precision (B94) — --measure ab: the heavy 2160p export, {tree_binary} against a "
          f"Release build of the decode-8bit copy, {rounds} rounds", flush=True)
    if not tree_binary.is_file():
        print(f"instrument failure: no app binary at {tree_binary}")
        return 2
    app, copy = build_mutant("decode-8bit", release_only=RELEASE_ONLY)
    if app is None:
        print(f"instrument failure: the decode-8bit copy did not build — {copy}")
        return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    if prores_clip(2160) is None:
        print("instrument failure: ffmpeg did not make M1's 2160p movie")
        return 2
    try:
        closed, logs = run_ab(tree_binary, proof_app.executable(app), rounds)
    except Exception as error:  # a row that could not run is a failure
        print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
        closed, logs = False, []
    found = [line for log in logs for line in complaints(log)]
    check("Z1 CONTROL: the projects close and no log holds a `Frame Job: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    passed = sum(1 for name in ("MA", "Z1") if rows.get(name))
    print(f"{passed}/2")
    return 0 if passed == 2 else 1


def main_reverse_cost():
    """`reverse-cost`: no app launched; this tree's `app/Sources`."""
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    return run_reverse_cost()


def main():
    global selected, sources_folder
    parser = argparse.ArgumentParser()
    parser.add_argument("--app")
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--control", help="a capture DIR whose P1 figure the rows print")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--rounds", type=int, default=3, help="--measure ab's rounds")
    parser.add_argument("mode", nargs="?", choices=("capture", "compare", "ab", "reverse-cost"))
    parser.add_argument("dir", nargs="?")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    if args.mode == "reverse-cost":
        if args.dir or args.only or args.measure or args.mutant or args.app or args.control:
            parser.error("reverse-cost takes no DIR and no other option")
        return main_reverse_cost()
    ab = args.mode == "ab"
    if ab and not (args.measure and args.mutant == "decode-8bit" and args.dir is None
                   and not args.only and args.rounds >= 1):
        parser.error("ab is `--measure ab --mutant decode-8bit [--rounds N]`")
    if not ab and ((args.mode is None) != (args.dir is None)
                   or (args.measure and args.mode is None)):
        parser.error("capture and compare take DIR; --measure takes capture or compare DIR")
    mutant = MUTANTS.get(args.mutant)
    if mutant and not ab and (args.measure or args.only or args.mode not in (
            None if mutant["mode"] in ("rows", "core") else "compare",)):
        parser.error(f"--mutant {args.mutant} runs {mutant['mode']}"
                     + (" DIR" if mutant["mode"] == "compare" else "") + " alone")
    if mutant and mutant["mode"] == "core":
        print(f"precision (B94) — the {args.mutant} core MUTANT (CT must FAIL, naming "
              f"{', '.join(CORE_TESTS)})", flush=True)
        return run_core_mutant(args.mutant)
    if ab:
        return main_ab(args.rounds)
    universe = (["M1", "Z1"] if args.measure else CAPTURE_ROWS if args.mode == "capture"
                else COMPARE_ROWS if args.mode == "compare" else ROWS)
    selected = set(universe)
    if mutant:
        selected = set(mutant["rows"]) | set(mutant.get("also", [])) | {"Z1"}
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()} | {"Z1"}
        unknown = selected - set(universe)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    elif args.mode == "capture":
        selected.discard("S3c")   # a whole capture records S3 under Sc
    if mutant:
        also = mutant.get("also", [])
        print(f"precision (B94) — the {args.mutant} MUTANT ({', '.join(mutant['rows'])}"
              f"{', PF' if mutant.get('pf') else ''} must FAIL"
              f"{'; ' + ', '.join(also) + ' run beside, not scored' if also else ''})",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        args.app, sources_folder = str(app), copy / "app/Sources"
    binary = Path(args.app or proof_app.binary(
        release_only=RELEASE_ONLY if args.measure else None))
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    tree = app_tree(binary)
    if tree is None:
        print(f"instrument failure: {binary} is not a product of a tree (a build/Build/Products "
              "under a folder holding app/Sources/Compositor.swift), so the formats it was "
              "built from cannot be read")
        return 2
    sources_folder = tree / "app/Sources"
    where = Path(args.dir).resolve() if args.dir else None
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    for maker in (h264_clip, ramp_clip):
        if maker() is None:
            print(f"instrument failure: {maker.__name__}'s movie refused — "
                  f"{TAG_REFUSED.get('why')}")
            return 2
    for maker in STILLS:
        if maker() is None:
            print(f"instrument failure: ffmpeg did not make {maker.__name__}'s movie")
            return 2
    if args.measure and None in (prores_clip(1080), prores_clip(2160)):
        print("instrument failure: ffmpeg did not make M1's ProRes movies")
        return 2
    print(f"precision (B94) — {('--measure ' if args.measure else '') + (args.mode or 'rows')}"
          f" on {binary}", flush=True)
    if args.measure:
        logs = []
        try:
            closed = run_measure(binary, args.mode, where, logs)
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
        found = [line for log in logs for line in complaints(log)]
        check("Z1 CONTROL: the projects close and no log holds a `Frame Job: ` line",
              closed and not found, f"closed {closed}; complaints {found}")
        passed = sum(1 for name in ("M1", "Z1") if rows.get(name))
        print(f"{passed}/2")
        return 0 if passed == 2 else 1
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        state = {}
        if args.control:
            try:
                state = json.loads((Path(args.control) / "capture.json").read_text())
            except (OSError, ValueError):
                print(f"  no capture.json in {args.control}; P1 prints no control", flush=True)
            state["_dir"] = str(Path(args.control).resolve())
        try:
            if args.mode == "capture" and selected == {"S3c", "Z1"}:
                closed = run_s3c(launched.client, where)
            elif args.mode == "capture":
                closed = run_capture(launched.client, where)
            elif args.mode == "compare":
                closed = run_compare(launched.client, where)
            else:
                closed = run_rows(launched.client, state)
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("Z1 CONTROL: the projects close and the log holds no `Frame Job: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    scored = [name for name in universe if name in selected]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if mutant:
        named = {name: rows.get(name) for name in mutant["rows"]}
        if mutant.get("pf"):
            named["PF"], line = mutant_pf(Path(sources_folder).parents[1])
            print(f"  preview_refresh_probe on the copy: {line}", flush=True)
        if None in named.values() or not rows.get("Z1"):
            print(f"mutant {args.mutant}: the control could not be performed — {named}, "
                  f"Z1 {rows.get('Z1')}")
            return 2
        caught = not any(named.values())
        beside = {name: rows.get(name) for name in mutant.get("also", [])}
        print(("MUTANT PASS" if caught else "MUTANT FAILURE") + f": {args.mutant} — "
              + ", ".join(f"{k} {'passed' if v else 'FAILED'}" for k, v in named.items())
              + ("; also (not scored) " + ", ".join(
                  f"{k} {'not run' if v is None else 'passed' if v else 'FAILED'}"
                  for k, v in beside.items()) if beside else ""))
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
