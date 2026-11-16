# Spec §11 — decisions: Grading tier 3, the working arrangement onward (road map "grading-3")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the GR- series of [`grading-3.md`](grading-3.md), so a citation never has to say
which file. This file holds GR-17…GR-23. GR-24 on are tier 4's, in [`grading-4.md`](grading-4.md),
which is why this file is lettered. It is new because `grading-3.md` had passed the spec's ~500-line
split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below" in one
may now point into a sibling file.

- **GR-17 — Tier 3's working arrangement: each phase gated in the `grading-3` worktree and
  merged into main alone, main's format numbers, no verdict phase; synthetic fixtures now.**
  Choice 10 and the footage answer (owner, 2026-10-11). GR-14's arrangement again: the worktree
  `~/devel/reelcut-grading3` on branch `grading-3`, outside the repo folder; each phase merged
  into main once its `make gate` passes, the next started from main. A phase takes main's next
  format number when its code is written and renumbers before its merge if main moved first.
  There is no experiment verdict or trial phase. Every proof runs on fixtures a script makes;
  the owner's real Apple Log, HDR and camera-log clips become manual checks later, read from a
  path he gives and never copied into the repo.
- **GR-18 — Linear-light blending is deferred: filed as an issue at T3-3, and when built it is
  an opt-in project switch, off for every project.** Choice 7a (owner, 2026-10-11).
  - Why not now: it changes every opacity, dissolve and text edge (computed by the brief's
    `linear.py`: white at 50 % over black is 128 encoded and 188 linear, so a "50 % black dim"
    becomes far lighter; a red → green dissolve's midpoint luminance is 0.199 encoded, below both
    ends, and 0.464 linear; multiply 50 % × 50 % grey is 64 and 61; one blur tap at a third white
    coverage is 85 and 156). Frame Job's material is screen recordings and titles, where encoded
    blending is what designers expect, so it is a preference to offer when asked, not a fix.
  - Design notes for the issue: the grade (steps 3 and 4c–4d) stays on encoded values; a linear
    pipeline decodes after the grade and before step 7, keeps the destination linear and encodes
    once in an output pass; an adjustment clip and the qualifier encode before reading the
    destination and decode after; the scopes read the encoded output. It touches blending and
    every blend mode, opacity and the reflection's fade, the transition weight, the matte and
    corner coverage, the dissolve and its routed halves, and the shadow; blur and sharpen only if
    the decode moves before the gather. Half-float holds it: a linear value in half-float returns
    every 10-bit code within 0.162 of a level and every 8-bit code exactly. The decode and encode
    cost +0.000–0.001 ms at 4K (measured, scratch), plus one output pass (about one copy).
  - With the switch off, everything stays byte-identical by GR0's route rule (a uniform flag
    behind the effects gate): the PR-5 frozen references, `precision_proof.py` K1–K6 and every
    tier-1 and tier-2 neutral row. With it on, the proof measures the table above as
    `render_frame` rows, plus the output pass's 4K frame time.
- **GR-19 — The HDR timeline is deferred: filed as an issue at T3-3, with its design.** Choice
  8a (owner, 2026-10-11).
  - A project setting, `canvas.output: "sdr" | "hlg"` (absent = SDR, today; PQ a later option),
    a property of the canvas because the preview, `render_frame` and every export must agree;
    a format bump.
  - An HLG project works in HLG-encoded BT.2020 values, so every stage keeps its 0…1 meaning
    (GR-11…GR-13), PR-1's clamps stay and blending stays encoded, now in HLG. SDR sources
    (recordings, stills, titles, graphics) enter by ITU-R BT.2408's SDR→HLG mapping, SDR white
    at HDR reference white (203 cd/m², 75 % HLG). PQ output is one conversion at the output.
  - The preview: the composition's colour properties and the render context's buffers become
    BT.2020/HLG, and `AVPlayerLayer` shows HDR on an EDR display by itself (REASONED); measured
    here, the built-in Liquid Retina XDR reports a potential EDR headroom of 16.0 and an external
    BenQ GW2790QT 1.0. Whether it looks right is a person's check.
  - The export, measured: `AVAssetWriter` with HEVC Main 10 and BT.2020/HLG colour properties
    fed `64RGBAHalf` wrote `bt2020nc/arib-std-b67/bt2020`, and VideoToolbox added a Dolby Vision
    profile 8.4 configuration and RPU by itself; with PQ and `kVTHDRMetadataInsertionMode_Auto`
    it wrote mastering-display and content-light-level metadata (defaults, not measured from the
    content); ProRes takes the same colour properties. So HDR export is a settings change on
    `ExporterWriter+Settings.swift` plus the reader asking for the same colour.
  - Its costs: every graphic, text and caption needs the SDR→HLG mapping; the scopes need a
    BT.2020 matrix and an HLG or nits scale; the waveform's clip marks change meaning;
    `render_frame` PNGs need a BT.2100 colour space; GIF and APNG stay SDR. Two or three phases.
  - Why not now: it touches every clamp in the compositor and every graphic's brightness, its
    main check is a person's at an XDR display, and a screen-recording editor's HDR deliverables
    are rare. The export half is measured cheap, so nothing blocks it later.
  **Amended by HD-2** (hdr H-0): its design is built in H-2: `canvas.output` `"sdr"` or `"hlg"`,
  HLG-encoded BT.2020 working values, and every composition of an HLG project converting in
  BT.2020/HLG.
  **Amended by HD-3** (hdr H-0): SDR white stays at 203 cd/m², and the SDR → HLG mapping's mid-tones
  are fixed by measurement: Core Graphics' `kCGColorSpaceCoreMedia709` → `itur_2100_HLG` (SDR 0.50 →
  HLG 0.5059, measured in H-0).
  **Amended by HD-5** (hdr H-0): PQ becomes an export range (`export {range: "pq"}`), not a
  `canvas.output` value, and every 8-bit row carries HD-4's SDR version, not only GIF and APNG.
- **GR-20 — A wide-gamut working space for SDR projects is not wanted: closed.** Choice 9a
  (owner, 2026-10-11). SDR deliverables are Rec. 709, every tier-2 stage is defined on encoded
  Rec. 709 values, and a wider space pays off only with linear-light grading, which nobody has
  asked for. No source is mis-read without it: a P3 photo is converted by Core Graphics when
  drawn (PR-6's path and the 8-bit path), and BT.2020 video by GR-15's matrix; their
  out-of-709 colours are lost, which is right for a Rec. 709 output. Wide gamut comes only as
  Rec. 2020 inside GR-19's HDR timeline. This settles, for SDR projects, the wide gamut PR-5
  deferred, without editing PR-5's list.
  **Amended by CJ-1** (2026-11-01): no longer excluded by §1; not built. This was the owner's
  verdict, so a road map that would build it asks the owner first.
- **GR-21 — A converting media's thumbnails are drawn through step 0** (#282; amends GR-15
  and GR-16). Owner, 2026-10-12: HLG and PQ included, SDR wide gamut not.
  - The cache pass renders a video media whose Camera Log converts, or whose video track's
    format description answers HLG or PQ, as a one-clip project around it (its display size,
    its rate, the media at 0, its Camera Log and LUT), through `CompositionBuilder` and the
    generator, so the strip is the preview's picture. A Camera Log decides before the labels, as
    step 0's does.
  - Why HDR: H0's numbers, on the grey row of hdr_proof's 1024×128 fixtures against
    `render_frame` at tick 0, the plain generator (`ForceSDR`) being AVFoundation's tone map and
    not step 0's: worst |Δ| 11 levels for HLG (about 10 darker through the mids) and 19 for PQ
    (darker in the mids, brighter on the shoulder), on 2026-10-12 in v1's TH and again in this
    change's H0. SDR wide gamut (`.sdrWide`) and the sRGB arms stay on the plain generator: the
    BT.2020 and P3 SDR fixtures measured within 1.
  - The marker: the flat `CacheStamp` exactly as before for a strip drawn plain; a
    `ConvertedThumbsStamp` for one drawn through step 0 — the `source` stamp, and the curve and
    gamut, or the LUT's resolved path, size and modification second, or the HDR `transfer`
    ("hlg" / "pq"). A LUT is named by its path as well as its size and second, so another LUT
    file of the same size and second is not taken for the old one. The head check: with a Camera
    Log, the converted marker of that input; without one, the flat stamp, or a converted marker
    of the same `source` naming only a `transfer` (an HDR file's labels are fixed by its stamp, so
    the no-op pass opens no picture). Every other media's strip and marker stay byte-identical.
  - A committed change of a media's converting Camera Log (set, clear, another LUT, undo, redo,
    `remove_media` of its LUT) starts a pass for it, superseding one already running: the cache
    ledger starts a new generation for a changed input as it does for another file.
  - A LUT whose file does not resolve draws the plain asset, as step 0 draws it unconverted. A
    failed one-clip build draws the plain asset and writes no marker.
  - Accepted limit: an HLG or PQ strip certified by a flat marker from a build before GR-21 keeps
    its plain picture until its file changes or its cache is removed (no package in real use,
    owner 2026-10-09).
  - Amended by GR-23: the converted marker of an S-Log3 or V-Log media from a full-range source
    also carries `fullRange: true`, and the head check reads that range for those media alone.
  **Amended by HD-6** (hdr H-0): a PQ media's strip is drawn through step 0 at its own peak, as a
  Camera Log's is at its curve; how the converted marker names the peak is H-1's spec's.
  **Amended by HD-12** (hdr H-1): a PQ media with an effective peak takes the Camera Log path (its
  `color` counts as converting), and its converted marker carries `peak`; a PQ media with no
  reading and no override keeps the `transfer: "pq"` marker it had.
  **Amended by HD-21** (clean-up 3 batch B, phase 2): an HLG- or PQ-labelled still, or a PQ still
  with a peak, joins the converted strips, and its flat marker from an older build is drawn
  again.
- **GR-22 — A log file's code domain follows its media's range flag** (#283; amends GR-16).
  - The range is the media's forward video track's `kCMFormatDescriptionExtension_FullRangeVideo`.
    It is read when the composition is built and carried per instruction, per track, as
    orientation is. Absent means video range, the behaviour before this decision.
  - In a full-range file, AVFoundation decodes s = CV/1023, so S-Log3 and V-Log take y = s
    (codeScale 1, codeOffset 0). Video range is unchanged (876/1023 and 64/1023).
  - Apple Log and Apple Log 2 are (1, 0) in both ranges, because P is the normalized signal.
  - A reverse follows its media's range. Its intermediate is written in video range from codes
    the decoder has rescaled.
  - Unchanged: Use LUT… (sampled at s, per GR-16's append), and HLG, PQ and every SDR arm (the
    decoder applies the range).
  - Thumbnails drawn through step 0 (GR-21) follow it.
  - Accepted limits: a file written in one range but flagged as the other is read by its flag. A
    strip GR-21 certified before GR-22 keeps its picture until its file or setting changes (no
    package is in real use).
  - Measured (issue batch B95, `log_proof.py` L10–L12 on HEVC Main 10 fixtures, Release): before
    this decision a full-range S-Log3 file's 0 % patch rendered 28 levels (V-Log 29) where the
    oracle is 0 (2); after it, L10 is within 1 level on the full-range S-Log3 and V-Log files and
    their video-range twin, L11 (full-range Apple Log) within 1, and a reversed full-range clip's
    0 % patch renders 5, 22 levels from the video-domain reading.
  - Amended by GR-23: a VP9 track, whose format description has no `FullRangeVideo` key, takes
    its range from its `vpcC` record; a strip GR-21 certified before GR-23 for a full-range
    S-Log3 or V-Log media is drawn again.
- **GR-23 — A VP9 track's range is read from its `vpcC` record** (issue batch B99, #291; amends
  GR-21, GR-22 and PR-10).
  - The range flag (`CompositionBuilder.isFullRange`) is the first format description's
    `kCMFormatDescriptionExtension_FullRangeVideo` when the key is present. When it is absent,
    it is the `videoFullRangeFlag` of a version-1 `vpcC` record (the VP codec ISOBMFF binding:
    version, three flag bytes, profile, level, then bitDepth:4 | chromaSubsampling:3 |
    videoFullRangeFlag:1, byte 6). Otherwise it is video range. The key wins whenever present,
    so HEVC, ProRes and every other track read as before.
  - All three VP9 routes carry `vpcC`: a VP9 MP4, opened as is; the WebM/Matroska rewrap, whose
    record the core writes (`container_codec.rs`'s `vpcc()`, the Colour element's Range over the
    keyframe's colour-range bit, #216-R); and ffmpeg's opt-in copy into MP4 (#227).
  - Every reader of the flag follows: step 0's log code domain (GR-22), PR-10's odd-size reverse
    and GR-21's strips. The reverse's renderer version is 4 (PR-7's digest rule), so a reverse
    already in a package is rendered again.
  - The marker: a converted marker of an S-Log3 or V-Log media (the curves whose code domain
    follows the range) from a full-range source carries `fullRange: true`; the head check reads
    the range for those inputs alone, from the file's first video track's format description,
    with no picture decoded. A strip certified without the field is drawn again, which closes
    GR-22's strip limit for these media. Every other marker is byte-identical to before, and a
    plain, HDR, LUT or Apple Log head check opens no asset.
  - No op, FFI, recipe, format or catalog change.
  - Accepted limits: a `vpcC` of another version reads as video range. A full-range HEVC S-Log3
    or V-Log strip drawn after GR-22 is drawn once more, for its new field.
  - Measured (the control, issue batch B99, Debug, before the code): `log_proof.py` L13's
    `slog3_fr_vp9` (1024×129, VP9 MP4, `pc`) reversed with toe worst 90 (column 0: 95 → 159)
    and a spread of 28 from its forward render, its video-range twin within 1; L14 with S-Log3
    set rendered `slog3_fr_vp9e.mp4` and `slog3_fr_webm.webm` 28 levels off the oracle (0 %
    patch [28, 28, 28] against [0, 0, 0]: the video-domain reading), `slog3_vr_vp9e.mp4` within
    1. `log_thumbs_proof.py` T9: the full-range VP9 strip's marker was `source`, `log` and
    `gamut` alone, and a reopen did not draw it again (`0.jpg` not rewritten); the video-range
    strip's marker had that shape and its `0.jpg` was within 1 of its render.
  - Measured after (Debug, the same commands): L13's `slog3_fr_vp9` holds (ProRes 422 1024×129,
    toe worst 1, 95 → 146, spread 2) and its twin is unchanged; L14 renders the 0 % patch of
    `slog3_fr_vp9e.mp4` and `slog3_fr_webm.webm` [0, 0, 0] (the oracle's), each file's worst 2
    levels, at 8 samples on the grey row (at x 400, 158 against 160), and
    `slog3_vr_vp9e.mp4`'s 1. The 2 is the VP9 decode, not the range: the same codes in HEVC
    (`slog3_fr`) and in VP9 render up to 0.88 of a level apart with no Camera Log and 1.25 with
    S-Log3 (a diagnostic run, tagged or untagged alike), so L14 holds a VP9-decoded file to ±2,
    not L10's ±1 (a misread range is 28 off), and passes. T9 holds: the full-range marker carries
    `fullRange: true`, the video-range one is `source`, `log` and `gamut`, the marker rewritten
    without the field was drawn again (`0.jpg` rewritten, within 1 of its render), and an
    unchanged reopen held both strips for 5 s.
  - Measured (issue batch B101, #293): AV1 in profiles 0 and 1 carries `FullRangeVideo`, so
    GR-23's fallback is not needed for it; profile 2 does not. `log_proof.py` L15
    (`av1_range_probe.swift`, descriptions only, on the tree before any edit) read the key on
    every AV1 fixture (libsvtav1 `yuv420p10le`, profile 0): `true` on `av1_fr.mp4`,
    `av1_fr_colr.mp4` and the rewrapped `av1_fr_webm.webm`, `false` on `av1_vr.mp4` and the
    rewrapped `av1_vr_webm.webm`, each answering its range flag. Only `av1_fr_colr.mp4` holds a
    `colr` box, and the rewrap's description holds only the core's `av1C`, so AVFoundation reads
    the key from the `av1C` sequence header itself. Twelve synthetic `av1C` records, each the
    only colour source of a one-sample movie: the nine in profiles 0 and 1 (range 1, range 0,
    timing info with a uvlc, a decoder model and two operating points, an initial display delay,
    a reduced still-picture header, monochrome, profile 1's (1, 13, 0) implied range, frame ids
    with order hints and forced screen content, and no colour description) each got the key and
    answered their own `color_range`. The three in profile 2 (12 bits range 0, 12 bits range 1,
    10 bits range 1) got no `FullRangeVideo` key and no `BitsPerComponent`, and each answered
    false: right for the range-0 one, wrong for both range-1 ones. Accepted limit (owner,
    2026-10-14): a full-range Professional-profile (profile 2) AV1 track reads as video range,
    so step 0, PR-10's reverse and GR-21's strips read it so; there is no GR-24 and no `av1C`
    parser. The evidence is synthetic records only, because this Mac does not decode AV1 and
    its ffmpeg (libsvtav1, profile 0 only) cannot write profile 2. It is accepted because the
    case is rare and cannot be tested on real media here. No product code changed. L15 scores
    the two profile 2 range-1 records at today's answer, false, so a change in AVFoundation's
    answer fails it and is noticed.
  - Measured (issue batch B101, #294; `log_proof.py decode-gap`, no app): the first frame of
    `slog3_fr.mov` and `slog3_vr.mov` (HEVC) and `slog3_fr_vp9e.mp4` and `slog3_vr_vp9e.mp4`
    (VP9), read by `AVAssetReaderTrackOutput` at 159 points (every 8th column of the grey row,
    its first 32 columns, and the three patches). In each file's own range (`xf20` for `pc`,
    `x420` for `tv`), all 159 points match the written codes, for VP9 and for HEVC alike. VP9's
    `64RGBAHalf` and `128RGBAFloat` frames equal HEVC's at every point (0.000 levels), and its
    `64RGBALE` frames are within 0.004 of a level. The verdict is **neither**: the gap B99
    measured is not in the decoder's output or in the reader's conversion to `64RGBAHalf`, so
    requesting another pixel format cannot remove it, and L14 keeps its bound of 2. Where the
    gap does arise (between the reader and the compositor's source frames) is not measured.
  - Measured (issue batch B102, #294; `log_proof.py composition-gap`, Debug, on the tree before
    any B102 code and again after it, the same figures): each of `slog3_fr.mov`, `slog3_vr.mov`
    (HEVC) and `slog3_fr_vp9e.mp4`, `slog3_vr_vp9e.mp4` (VP9) alone on a 1024×128 canvas, with
    Camera Log None and with S-Log3, saved, and read by `composition_gap_probe.swift` at 0.5 s at
    the 159 `decode-gap` points, VP9 against HEVC. The compositor's source frames (a probe
    compositor in the built configuration's place, the built class's three answers copied) are
    `RGhA` 1024×128 in both and equal at every point (0.000 levels). The compositor's output (an
    `AVAssetReaderVideoCompositionOutput` over the built composition) is equal under S-Log3
    (0.000) and within 0.125 of a level with Camera Log None, where the HEVC file (tagged
    BT.2020) is built with `ConvertingCompositor` and the untagged VP9 file (VideoToolbox's
    guessed BT.709) with `Compositor`. `render_frame`'s image (`Exporter.renderFrame`, read in its
    own space) parts: worst 0.623 of a level with Camera Log None (at x 1000 and 840 on the grey
    row) and 0.529 with S-Log3 (at x 14 and 4), because `AVAssetImageGenerator` hands back an
    8-bit image of each VP9 file and a 16-bit one of each HEVC file. The verdict is
    **generator**: the gap L14 allows is the 8-bit rounding of a VP9 frame in `render_frame` and
    Save Frame… (the generator's image of each VP9 file is 8-bit and of each HEVC file 16-bit, as
    `composition-gap` printed; why the generator answers 8-bit for VP9 was not measured). It is not in Frame Job's compositor,
    and an export, which reads the compositor's output, does not have it. The fix that would
    remove it: read a frame whose composition holds a 10-bit VP9 track through export's reader,
    as PR-9 does for a deep still (`DeepStillFrame.read`), which is a PR-4 amendment of its own.
    The owner chose that fix (2026-10-14, #294), to land with its PR-4 amendment in the batch
    after B102. It landed as PR-12 (issue batch B103), and L14 holds ±1 again: on Debug,
    `log_proof.py compare` against B103's control, worst 1 on `slog3_fr_vp9e`, `slog3_vr_vp9e`
    and `slog3_fr_webm` (2, 1 and 2 at ±2 before), each VP9 file's `render_frame` a 16-bit PNG.
