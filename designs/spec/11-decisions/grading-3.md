# Spec §11 — decisions: Grading tier 3 (road map "grading-3")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map making these is in progress: `designs/grading-3.md` (T3-0 the road map, these
decisions and the pure move; T3-1 honest sources and Reelcut's HDR→SDR; T3-2 log footage; T3-3
the close). The IDs continue the GR- series of [`grading.md`](grading.md) and
[`grading-2.md`](grading-2.md), so a citation never has to say which file. GR-15…GR-20 were
recorded in T3-0, before any tier-3 code, from the owner's answers of 2026-10-11 to the tier-3
brief's choices: "HDR fix + log" for choice 1, "All as recommended" for choices 2–6 and 10, and
"Synthetic now" for the footage (`designs/grading-3.md`, "The owner's choices"; the brief is
`~/.claude/litecode/reelcut/grading-tier3/I-grading-tier3.md`, outside the repo). T3-1 and T3-2
each add to their own entry the numbers their code needs (GR-15's shoulder and H3's bound;
GR-16's sources' terms, constants and format number) before that code is written.

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies, never a runtime);
PR-1 (encoded values in [0, 1]: step 0 converts INTO that range); PR-3…PR-8; MT-3; GR-1 (tiers
2 and 3 deferred as issues, not out: tier 3 is that deferral being taken up, and GR-18…GR-20
settle what of it is not built now); GR-3 (blending stays encoded); GR-10…GR-14.
**The Concat rule** (`designs/adr/effects-survey.md`, "Licensing") stands for every phase: the
conversions come from ITU-R BT.2100, SMPTE ST 2084, ITU-R BT.2020, BT.709, BT.2408 and BT.2390,
IEC 61966-2-1, and each camera maker's own published log document; the matrices are computed
from published primaries and D65 by the standard derivation; Apple's conversion is MEASURED as
a target, never copied; every fixture and test LUT is written by a script. Nothing of Concat is
opened, at design time or build time.

- **GR-15 — Honest sources: Reelcut converts HDR to SDR itself, at a new step 0; every other
  source is sampled exactly as today.** Choices 1a and 2a (owner, 2026-10-11).
  - **The switch:** the compositor answers `canConformColorOfSourceFrames` and
    `supportsHDRSourceFrames` true, and the video composition's colour properties are set to
    BT.709 (primaries, transfer and matrix) explicitly. Measured by the tier-3 brief (a scratch
    instrument making the app's AVFoundation calls, 2026-10-11): with both, every frame on every
    path — the export reader, `AVAssetImageGenerator`, the player — arrived native and honestly
    labelled (at a grey signal of 0.5: HLG 0.5000 labelled HLG, PQ 0.5000 labelled PQ, Apple Log
    labelled Apple Log, a BT.2020-primaries/BT.709-transfer file 0.5000), and a BT.709 | HLG |
    BT.709 sequence arrived native on all fifteen frames. `supportsHDRSourceFrames` alone only
    moves the problem: AVFoundation then converts into a space it picks (the BT.709 frames came
    out 0.4458, except the first).
  - **SDR sources are unchanged by it, byte for byte**: a full-frame digest of the source buffer
    was identical with and without the switch for BT.709 and untagged ProRes, BT.709 and
    untagged H.264, a matrix-only-tagged HEVC 8-bit and H.264 1080p, and the recording proof's
    `short-video.mov`.
  - **The defect it closes** (measured, the brief's §2): today an export draws the FIRST frame
    of each HLG or PQ clip unconverted (0.5000 where the rest of the clip is 0.3843 for HLG,
    0.7192 for PQ), and every frame `AVAssetImageGenerator` draws is unconverted and labelled
    BT.709 — `render_frame`, File ▸ Save Frame…, GIF and APNG, the Look gallery's thumbnails, the
    chroma-key eyedropper and Pick from Canvas — so the eyedropper picks HLG values while the
    preview keys on converted ones (a parity defect under §7.3); a BT.2020 file with the BT.709
    transfer is darkened on every path (0.5 → 0.2568); and AVFoundation's conversion clips
    colour (the fixture's HLG chroma patch, (0.42, 0.84, 1.17) native, arrived as (0.00, 0.73,
    1.00)).
  - **Step 0** is a per-source pass before the layer stage: it converts a source texture once
    per frame into a pooled `rgba16Float` target, which the layer stage then samples as that
    layer's source. It runs only for a non-identity conversion, chosen by the buffer's TRANSFER
    label: the HLG transfer, the PQ transfer, or BT.2020 primaries with the BT.709 transfer. A
    buffer carrying a log transfer function (Apple Log's `LogTransferFunction`, with BT.2020
    primaries and transfer "unspecified") or any transfer Reelcut does not recognise stays the
    identity until GR-16 assigns its conversion: T3-1 leaves Apple Log unchanged (still log).
    Every other source is sampled exactly as today, so it renders byte-identical by
    construction.
  - **Why a pass, not arithmetic inside the sample:** measured in the brief's scratch shader, a
    conversion inside a 25-tap blur cost +3.06 ms at 4K (once per tap), against +0.001–0.009 ms
    once per pixel; the pass costs about one copy (0.21 ms at 4K) and one pooled target per
    converted source (66.4 MB at 4K, PR-1's figure). Drawing the conversion inside the sample
    when a layer has no multi-tap effect is an optimisation a phase may measure, not a change to
    this decision.
  - **The conversion:** HLG by the BT.2100 HLG inverse OETF and its system gamma; PQ by the
    SMPTE ST 2084 EOTF (as reproduced in BT.2100); then the BT.2020 → BT.709 matrix; then a
    shoulder; then the encode into PR-1's encoded values. The BT.2020/BT.709-transfer source takes
    the same matrix between its transfer's decode and the encode.
  - **The anchor** (choice 2a): Apple's measured brightness, so the owner's iPhone footage keeps
    the look its preview and export have today: HLG signal 0.25 / 0.5 / 0.75 / 1.0 → 0.215 /
    0.384 / 0.604 / 1.0 (HLG's reference white, 75 % signal, near 60 %); highlights roll off
    instead of clipping, and colours outside Rec. 709 are compressed by the shoulder, not
    clipped. ITU-R BT.2408's mapping (reference white at full SDR white, choice 2b) was not
    taken. T3-1 adds the shoulder's constants and H3's bound (the distance to Apple's four
    points, written before it is measured) to this entry before its code.
  - **What does not change:** `LayerUniforms` stays 128 floats (the pass has its own small
    uniform block); the layer stage's texture slots are unchanged (`texture(2)` the look,
    `texture(3)` the curve strip, #124's `texture(4)` untouched); no op, tool, recipe key, FFI
    export or format number.
  - **It amends PR-2** ("HDR stays tone-mapped to SDR: `supportsHDRSourceFrames` stays false")
    **and GR-8's T0 sentence** ("HLG and PQ draw the grey ramp UNCHANGED"), each by an "Amended
    by GR-15" line: each sentence was true of one path. This is a measured correction, not a
    re-litigation: PR-2's decision that HDR reaches the output as SDR stands, and only who
    converts changes. §7.5's wording and the three code comments that repeat PR-2
    (`Compositor.swift`'s `sourcePixelBufferAttributes` doc, `ExporterWriter+Settings.swift`'s
    output-tag comment, `ReverseRenderer.swift`'s class doc) are corrected by T3-1 with its code.
  - Risk accepted: one pooled 66.4 MB target per converted 4K source in flight, and about one
    copy pass per converted source per frame (a 4K dissolve between two HDR clips adds about
    0.43 ms of GPU, REASONED, on top of a heavy 4K frame's 7.4–7.6 ms). Not measured before
    T3-1: whether the switch holds for ProRes 4444 with alpha, the WebM rewrap, the HEVC-with-alpha
    path and the player at length; Apple's HLG curve beyond its four measured points; and a real
    screen recording's labels (if one is labelled Display P3 or sRGB, H1's byte identity is
    re-checked on it).
- **GR-16 — Camera log is a setting on the media, `media.color {log, gamut, lut, detected}`,
  converted at step 0 before the chroma key and Color's four.** Choices 3a, 4a, 5a and 6
  (owner, 2026-10-11).
  - **On the media** (choice 3a): one setting per file. Every clip of the media, and its
    reverse, follows it. `log` is one of `apple_log`, `slog3`, `vlog`; `gamut` the camera gamut
    it pairs with (S-Log3 with S-Gamut3.Cine or S-Gamut3, V-Log with V-Gamut, Apple Log with
    BT.2020 only); `lut` a `lut` media used as the conversion instead of a built-in curve;
    `detected` true when the setting came from the file's label. Written only when set or
    detected. A media's `color` setting, when set, supersedes GR-15's choice from labels for that
    media.
  - **The op and the tool:** `set_media_color {media, color}` (`color: null` clears), one new op
    (`edit.rs`, `op_table.rs`) and the ninety-first product tool, mirroring the Media
    inspector's **Camera Log** popup (None · Apple Log · S-Log3 / S-Gamut3.Cine · S-Log3 /
    S-Gamut3 · V-Log / V-Gamut · Use LUT…), one undo step. `get_project` shows `media[].color`.
  - **Recognition** (choices 5a and 6): Apple Log is detected when `MediaImporter.probe` runs,
    from the track's format description (`kCMFormatDescriptionExtension_LogTransferFunction` =
    `com.apple.rec2020.apple-log`), written `{log: "apple_log", detected: true}` and converted
    from the moment of import; the popup reads "Apple Log (from the file)", and None is the
    override that shows the log picture. S-Log3 and V-Log carry no label AVFoundation knows, so
    they are chosen by hand; Sony's and Panasonic's own metadata is not read.
  - **The conversion** (choice 4a): a built-in is the maker's published log curve inverted to
    scene-linear light (Apple's *Apple Log Profile* white paper; Sony's technical summary for
    S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3; Panasonic's V-Log/V-Gamut reference manual), the
    camera gamut → Rec. 709 matrix computed from the document's published primaries and white
    point, GR-15's display transform with its exposure anchored so 18 % grey lands at a sensible
    mid-grey, then the encode. **No maker's LUT is bundled**: their redistribution terms were not
    found, Apple's sits behind the developer login, and a 33³ lattice is up to 3 levels off an
    analytic curve. **Use LUT…** makes a `.cube` media (GR-8's parser, unchanged) the input
    conversion, sampled once per pixel in step 0.
  - **Where it runs:** step 0 (GR-15), before step 3, so the chroma key, Color's four, Light,
    the wheels, the curves, a look at 4d and the qualifier all see converted values; "correct
    first, then the look" (GR-7) then holds for log footage too. **Show Ungraded keeps it**: it is
    the file's interpretation, not a grade. A reverse follows its media whatever labels its
    intermediate keeps. Paste Attributes carries nothing new (the setting is the media's).
  - **Refused by name**, each in its own sentence: a setting on an audio, image or LUT media; a
    `log` and `gamut` pairing outside the list above; a `lut` that names no `lut` media.
    `remove_media` of a LUT used as a media's input conversion clears that conversion (GR-8's
    choice 6 rule).
  - **The look warning:** the Look section says so when the clip's media converts and its look
    is a LUT (a camera LUT applied as a look would convert twice). A warning only: a creative
    LUT there is legitimate.
  - **Not in:** other log curves (Canon Log 3, Fujifilm F-Log2, DJI D-Log, ARRI LogC…) and Apple
    Log 2 are each an issue (T3-3), built when asked.
  - T3-2 adds to this entry, before its code, each source document's terms (checked before
    implementing from it), each curve's constants and the makers' test points, the recipe's
    `input` key, and the format number (main's next when its code is written).
  - **It amends GR-8's accepted risk** ("a LUT that expects log … draws wrong … and nothing
    warns"), by an "Amended by GR-16" line.
  - Risk accepted: built and proved on synthetic fixtures only (choice "Synthetic now"); whether
    a real iPhone Apple Log file carries the measured label, and how real Sony and Panasonic files
    are tagged, wait for the owner's clips (GRD-17, GRD-18). The display transform's mid-grey is
    Reelcut's look choice, not a maker's. A user who already applies a camera LUT as a look and
    then sets Camera Log converts twice, and is only warned.
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
    coverage is 85 and 156). Reelcut's material is screen recordings and titles, where encoded
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
- **GR-20 — A wide-gamut working space for SDR projects is not wanted: closed.** Choice 9a
  (owner, 2026-10-11). SDR deliverables are Rec. 709, every tier-2 stage is defined on encoded
  Rec. 709 values, and a wider space pays off only with linear-light grading, which nobody has
  asked for. No source is mis-read without it: a P3 photo is converted by Core Graphics when
  drawn (PR-6's path and the 8-bit path), and BT.2020 video by GR-15's matrix; their
  out-of-709 colours are lost, which is right for a Rec. 709 output. Wide gamut comes only as
  Rec. 2020 inside GR-19's HDR timeline. This settles, for SDR projects, the wide gamut PR-5
  deferred, without editing PR-5's list.
