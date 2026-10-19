# Spec §11 — decisions: Grading tier 3 (road map "grading-3")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/grading-3.md`,
and the original, `archive/grading-3.md`, holds each phase's record (T3-0 the road map, these
decisions and the pure move; T3-1 honest sources and Frame Job's HDR→SDR; T3-2 log footage; T3-3
the close). The IDs continue the GR- series of [`grading.md`](grading.md) and
[`grading-2.md`](grading-2.md), so a citation never has to say which file. GR-15…GR-20 were
recorded in T3-0, before any tier-3 code, from the owner's answers of 2026-10-11 to the tier-3
brief's choices: "HDR fix + log" for choice 1, "All as recommended" for choices 2–6 and 10, and
"Synthetic now" for the footage (`archive/grading-3.md`, "The owner's choices"; the brief is
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

- **GR-15 — Honest sources: Frame Job converts HDR to SDR itself, at a new step 0; every other
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
    primaries and transfer "unspecified") or any transfer Frame Job does not recognise stays the
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
  - **T3-1's numbers** (appended before T3-1's code; each figure below computed by
    `tools/proof/hdr_proof.py`'s oracle, `convert`). The shader holds only the standards'
    constants and formula shapes; every number Frame Job chose is `InputConversions.swift`'s.
    - **HLG**: the BT.2100 inverse OETF (a = 0.17883277, b = 1 − 4a, c = 0.5 − a·ln 4a), the
      signal floored at 0 and not capped; BT.2100's OOTF shape E·Ys^(γ − 1), Ys = 0.2627 R +
      0.6780 G + 0.0593 B, with the **system gamma γ 0.96**; then a **gain of 1.07**. Both are
      Frame Job's anchor to Apple's points (choice 2a), not BT.2100's nominal γ 1.2: with γ 1.2
      the best single gain (this shoulder, its white at the gain) leaves the worst of Apple's
      four points 9.1 levels of 255 off (0.25 at −9.1, 0.75 at +8.9), and a gain fitted to the
      0.5 point alone leaves 0.25 at −5.9.
    - **PQ**: the SMPTE ST 2084 EOTF as BT.2100 reproduces it (m1 = 2610/16384, m2 =
      2523/4096 × 128, c1 = 3424/4096, c2 = 2413/4096 × 32, c3 = 2392/4096 × 32), the signal
      clamped to [0, 1], in cd/m² divided by the **reference white 203 cd/m²** (BT.2408), so
      reference white is 1.0 (× 10000/203).
    - **Both, then**: the matrix to BT.709, derived from the published chromaticities and D65
      by the standard derivation (BT.709 R 0.640 0.330, G 0.300 0.600, B 0.150 0.060; BT.2020
      R 0.708 0.292, G 0.170 0.797, B 0.131 0.046; P3 D65, SMPTE EG 432-1, R 0.680 0.320,
      G 0.265 0.690, B 0.150 0.060; D65 0.3127 0.3290); **the gamut lift**: when a channel is
      negative, the colour moves toward its BT.709 luminance Y until its lowest channel is 0,
      L = Y + (L − Y)·Y/(Y − min L) (black when Y ≤ 0), which keeps its hue in linear
      opponent space; **the shoulder** on the largest channel m, every channel scaled by
      S(m)/m: S(m) = m up to the **knee 0.39**, then 0.39 + 0.61·t(1 + t/tw²)/(1 + t), t = (m −
      0.39)/0.61, tw = (W − 0.39)/0.61, reaching 1 at the **white W** (HLG 1.07, the gain at full
      signal; PQ 1000/203, 1,000 cd/m²) and 1 above it, so highlights and colours outside
      Rec. 709 roll off instead of clipping; then the encode, BT.1886's inverse, L^(1/2.4).
    - **A premultiplied source** (its buffer labelled so, G-35 (b)) is un-premultiplied with
      the layer stage's own floor, rgb / max(a, 10⁻⁴), converted, and premultiplied back;
      alpha passes through, and a texel at alpha 0 stays finite.
    - **The distance to Apple's measured points**, computed before measuring: HLG 0.25 / 0.5 /
      0.75 / 1.0 at +0.93 / −0.84 / +0.17 / 0.00 levels of 255; PQ 0.5 / 0.75 at −0.79 / −0.28.
      **H3's bound: each of Apple's six points within 3/255 of the render.**
    - **The selector** (`InputConversion.choose`, from the buffer's attachments), in order: a
      log transfer attachment (`kCVImageBufferLogTransferFunctionKey`) → the identity; the HLG
      transfer → HLG; the PQ transfer → PQ (each with the primaries: BT.2020 → BT.2020, P3 D65
      → P3 D65, BT.709 → BT.709, absent or any other → BT.2020); the BT.709, BT.2020 or sRGB
      transfer with BT.2020 primaries → wide-gamut SDR from BT.2020, with P3 D65 primaries →
      wide-gamut SDR from P3 D65; anything else → the identity: no pass, and the buffer's own
      texture sampled exactly as today.
    - **Wide-gamut SDR is converted too** (owner, 2026-10-11, "Convert it"): with
      `supportsHDRSourceFrames` true AVFoundation no longer converts a wide-gamut source for
      the compositor (`AVVideoCompositing.h`, `canConformColorOfSourceFrames`), so step 0
      must, to keep it looking converted: decode L = signal^2.4 (BT.1886), the matrix, the
      encode; no lift and no shoulder (the layer stage's clamp, PR-1). It also covers a screen
      recording labelled Display P3, should one turn up. Measured on the control
      (`hdr_proof.py capture` at 716720c, Release): a BT.2020/BT.709-transfer, a P3/BT.709 and
      a BT.2020/BT.2020-10 file each drew a grey of 128 as 65 or 66 on `render_frame`.
    - **The screen recording's labels** (owner, 2026-10-11, "Yes, read labels"): `hdr_proof.py`
      R0 reads only the colour labels (ffprobe) of the newest existing recording in
      `~/Movies/Frame Job Recordings/`, never its pixels, and nothing records the screen for it.
    - **Where the owed "real screen recording's labels" check went**: R0 on the control
      (Release, 2026-10-11) read `Screen Recording 2026-09-28 at 10.45.11.mov` as HEVC
      `bt709/bt709/bt709`, the identity arm, so H1 holds a ramp carrying exactly those tags
      (`rec_tags.mov`) byte-identical; how a recording looks against QuickTime Player is
      GRD-16's.
  - **Amended after T3-1's H1 stop** (owner, 2026-10-12, "Redesign, keep SDR exact"): **the
    switch is per composition.** A composition whose video tracks hold a source that starts a
    conversion — HLG, PQ, or wide-gamut SDR (BT.2020 or P3 D65 primaries with an SDR
    transfer, the sRGB one included) — is built with `ConvertingCompositor` (both AVFoundation
    properties true) and BT.709 colour, and a frame it composes is labelled BT.709. Every
    other composition is built exactly as before: `Compositor`, both properties false, no
    composition colour, no step 0, so an SDR-only project keeps its pixels and labels by
    construction. The choice is `CompositionBuilder.convertsSources`, over each composition
    track's format descriptions (the same selector over their extensions); every path copies
    the built configuration, so the preview, every export and every rendered frame agree, and
    adding or removing an HDR clip rebuilds and re-chooses.
    - **Why** (measured in scratch, 2026-10-12, `tools/proof/work/t3-1/redesign/`): T3-1's first
      code set BT.709 on every composition; every SDR frame's pixels were identical, but 7 of
      H1's 12 single-source scenes (untagged ProRes and H.264, matrix-only HEVC, a PNG still,
      VP9, sRGB HEVC, Apple Log) came out labelled `kCGColorSpaceCoreMedia709` instead of sRGB
      or their own ICC, and the eyedropper's picks moved (grey 0.251 → 0.286); with no
      composition colour H1 held but HDR frames followed the source's HLG tag (H2, H3 failed).
      M1: a destination carries the render context's labels, and the context is per
      composition, not per frame (in HLG | untagged × 2 with no colour every frame is
      HLG-labelled). M2: writing the BT.709 triple on the destination reaches every consumer,
      but by M1 cannot keep a mixed project's unconverted frames right by itself. M3:
      `canConformColorOfSourceFrames` changes SDR-only mixes (in sRGB | BT.709 today conforms
      the BT.709 clip into the sRGB context, pick 66, export 55; conformed natively 127, 115),
      hence `Compositor` keeps today's answers. M4: beside HLG, today's class and
      `ConvertingCompositor` + BT.709 give byte-identical generator PNGs, equal picks and equal
      export pixels for every SDR clip measured (untagged and BT.709 ProRes, H.264 709 and
      untagged, matrix-only HEVC, ProRes 4444, Apple Log, SMPTE-C ProRes; untagged beside PQ and
      beside P3/709) except the sRGB-transfer HEVC (export 53 → 126, pick 62 → 139). M5: a
      composition track's `formatDescriptions`, read by key, lists every inserted source's
      labels (10 sources, Apple Log's log extension included).
    - **The sRGB arm** (owner, 2026-10-12, "Convert it now"): every sRGB-transfer source takes
      it, `InputConversion.srgb(p)` (kind 4): the IEC 61966-2-1 EOTF per channel of the signal
      floored at 0 (s ≤ 0.04045 ? s/12.92 : ((s + 0.055)/1.055)^2.4), the source's primaries to
      BT.709 in linear light (`toBT709(from: p)`, the identity for BT.709; p is BT.2020 or P3
      D65 for those primaries, BT.709 for BT.709, absent or any other), the negatives clamped,
      then the encode L^(256/502): the inverse of the gamma of Core Media's BT.709 profile
      (`kCGColorSpaceCoreMedia709`'s TRC is `curv` 502/256, a pure power of 1.9609375, with
      BT.709/D65 primaries), which ColorSync reads a converted frame through. No lift, no
      shoulder. One with BT.709 or other non-wide primaries takes it only inside a converting
      composition and never makes one (`startsConversion` false only for `.srgb(.bt709)`), so it
      renders there as it does alone; one with P3 D65 or BT.2020 primaries is wide gamut, makes
      its composition converting, and renders as Apple reads the file's own labels. M7 (the
      target, `srgb.mov` alone on today's path: mid-grey exports at 115.7, picks [128, 128,
      128], [153, 48, 0], [87, 249, 255]): the EOTF then BT.709's OETF picks 126, [153, 36, 0],
      [82, 249, 255]; then BT.1886's inverse exports within 19 levels; then 256/502 picks all
      three identical, exports 115.7 at mid-grey and within 3.5 (grey row) and 5.1 (chroma row)
      levels over the rows, all near black, where VideoToolbox's sRGB → 709 conversion has a
      toe of its own. M8 (`p3srgb.mov`, smpte432/iec61966-2-1/bt709): Apple's reading of the
      file's own labels picks [128, 128, 128], [166, 36, 0], [0, 253, 255]; today's Frame Job
      alone [55, 55, 55], [98, 4, 0], [0, 251, 255]; the earlier `sdrWide` reading [139, 139,
      139], [175, 35, 0], [0, 254, 255]; `.srgb(.p3D65)` [128, 128, 128], [167, 36, 0], [0, 253,
      255].
    - **Accepted limits**: a source whose file's format description lacks the colour labels
      its decoded frames carry stays on today's path (AVFoundation's conversion), since the
      class is chosen from the descriptions; HDR10 static metadata on a converted frame is not
      measured (no fixture carries it). — Amended by GR-21: an HLG or PQ source's thumbnails are
      drawn through step 0.
      - **Measured at T3-3** (`hdr_proof.py` H1a, H7; `--only H1a,H7,Z1` on Debug and on
        Release, 3/3 each): in a converting composition (ProRes 4444 with an alpha ramp | HLG |
        HEVC with alpha | VP9 WebM, 640×360), the tree's frames at 0.5 s into each non-HLG clip
        are byte-identical to 716720c's, with equal picks, while the HLG clip's differ (143,449
        16-bit samples; grey pick 0.424 converted against 0.545), so the switch holds for alpha
        and the WebM rewrap. A PQ ramp with HDR10 static metadata naming a 4,000 cd/m² peak
        (x265's mastering display and content light level, which ffprobe names on its first
        frame), not the conversion's 1,000, renders byte-identical to its twin without it, each
        grey row within 1 level of the oracle (`--only H7,Z1` on Release, 2/2): the shoulder
        ignores the metadata. The player's first frame and the player at length are GRD-16's.
        Measured in issue batch B96 (#281; `hdr_proof.py --only H7,Z1` on Debug and on Release,
        2/2 each): two more twins — a 600 cd/m² mastering display with MaxCLL 600, and the
        4,000 cd/m² display with MaxCLL 1,000, each peak read back by ffprobe — also render
        byte-identical to the plain PQ ramp, all four grey rows within 1 level of the oracle; and
        Apple's own reading of each file (an `AVAssetImageGenerator` frame with no composition,
        `hdr_pick_probe.swift`'s `plain`) is the same for all four at the grey row's every 64th
        column (worst |Δ| 0 levels against the plain file), so Apple's generator reading
        follows neither field either (the player was not measured).
  **Amended by NM-4** (rename R0): `~/Movies/Reelcut Recordings/` is now
  `~/Movies/Frame Job Recordings/` (the folder `hdr_proof.py` R0 reads).
  **Amended by HD-2** (hdr H-0): in an HLG project step 0 gains HLG arms chosen by the canvas's
  output as well as the buffer's labels (SDR → HLG by HD-3's lift, HLG over BT.2020 the identity, PQ
  → HLG at 1,000 cd/m², log → HLG); in an SDR project every arm is this entry's.
  **Amended by HD-6** (hdr H-0): T3-1's PQ white is the media's own peak ÷ 203, held at 1 or above,
  instead of a fixed 1000/203; an unknown peak means 1,000 cd/m², so every unlabelled file renders
  byte-identical (H-1).
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
    Frame Job's look choice, not a maker's. A user who already applies a camera LUT as a look and
    then sets Camera Log converts twice, and is only warned.
  - **T3-2's append, before its code** (2026-10-12). Nothing above is rewritten; where a number
    or a choice here sharpens one above, this is the record.
    - **The sources, each read before implementing from it** (the owner downloaded them on
      2026-10-12; the copies T3-2 read sit outside the repo, and no maker's file, table or LUT is
      copied into the repo, a fixture or a proof's data):
      - Apple, *Apple Log 2 White Paper*, September 2025, Part 028-00834, Version 1.1 (sha256
        030d2441248bd5be2c2e7e766c08f41808ada8aa15fccd7bd5bb877657bf8688; its LUT download,
        `Apple_Log_2_LUTs.zip`, a0e8f7abe32fe217b90a5ff55154986e40b949d9eb0b7d75b94daa5a70cde805),
        downloaded by the owner from Apple Developer Downloads (the SDK header's
        `developer.apple.com/download/all/?q=Apple%20log%20profile`).
        It says "The Apple Log 2 color space uses the Apple Log transfer function", so its curve
        IS Apple Log's. Terms: "Copyright © 2025 Apple Inc. All rights reserved" and Apple's
        trademarks; nothing in it restricts implementing or using the published function, and a
        copyright notice does not (the coordinator's ruling, 2026-10-12).
      - Sony, *Technical Summary for S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3* (7 pages, made
        2014-02-15; sha256 d9c8a042e7e9e8ee248df97633b645681b5370099a508b6cee97d8bad880d5d3),
        downloaded by the owner from pro.sony (this host's requests are refused there with 403).
        Terms: none stated.
      - Panasonic, *V-Log/V-Gamut Reference Manual*, Rev. 1.0, November 28, 2014 (sha256
        d8a1837725abcca5da348b2dc6f212446db6a598cb61b093891af7ecbc0c8dcc),
        `pro-av.panasonic.net/en/cinema_camera_varicam_eva/support/pdf/VARICAM_V-Log_V-Gamut.pdf`
        (the owner's download is the same file). Terms: none stated.
    - **The curves, as each document gives them** (s is the decoded, normalized signal Frame Job's
      step 0 reads; every constant below is the document's):
      - **Apple Log** (the paper's §Transfer function): P = γ·log2(R + β) + δ for R ≥ Rt, c·(R −
        R0)² for R0 ≤ R < Rt, 0 below R0; R0 = −0.05641088, Rt = 0.01, c = 47.28711236, β =
        0.00964052, γ = 0.08550479, δ = 0.69336945. Its inverse: R = 2^((P − δ)/γ) − β for P ≥ Pt,
        √(P/c) + R0 for 0 ≤ P < Pt, R0 below 0, Pt = c·(Rt − R0)² (≈ 0.2085553). The test points:
        0 / 18 / 90 / 1200 % → P 0.150477 / 0.488272 / 0.681686 / 1.0, which the paper prints
        as "10 bit, full range" 154 / 500 / 697 / 1023. Apple's own AppleLogToLin-v1.0.cube (a
        4096-entry 1D table in the same download) is within 3.0·10⁻⁵ of this inverse
        everywhere (8.1·10⁻⁵ relative), a scratch check never committed.
      - **S-Log3** (the summary's appendix): y = (420 + 261.5·log10((x + 0.01)/0.19))/1023 for x ≥
        0.01125, else (x·(171.2102946929 − 95)/0.01125 + 95)/1023; its inverse x = 10^((1023·y −
        420)/261.5)·0.19 − 0.01 for y ≥ 171.2102946929/1023, else (1023·y − 95)·0.01125/(171.2102946929
        − 95). Test points 0 / 18 / 90 % → CV 95 / 420 / 598 (3.5 / 41 / 61 % IRE).
      - **V-Log** (the manual's §3): out = 5.6·L + 0.125 for L < 0.01 (cut1), else 0.241514·log10(L
        + 0.00873) + 0.598206; its inverse (in − 0.125)/5.6 for in < 0.181 (cut2), else 10^((in −
        0.598206)/0.241514) − 0.00873, in = code/1023. Test points 0 / 18 / 90 % → 128 / 433 / 602
        (7.3 / 42 / 61 % IRE).
    - **The gamuts** (each D65, 0.3127 0.3290): S-Gamut3.Cine R 0.766 0.275, G 0.225 0.800, B 0.089
      −0.087; S-Gamut3 R 0.730 0.280, G 0.140 0.855, B 0.100 −0.050; V-Gamut R 0.730 0.280, G
      0.165 0.840, B 0.100 −0.030; Apple Log BT.2020; **Apple Wide Gamut** (the paper's) R 0.725
      0.301, G 0.221 0.814, B 0.068 −0.076. Each matrix to BT.709 is derived from these by
      GR-15's standard derivation (`InputConversions.toBT709`), never copied; Panasonic's
      published V-Gamut → BT.709 matrix (1.806576 −0.695697 −0.110879 / −0.170090 1.305955
      −0.135865 / −0.025206 −0.154468 1.179674) equals the derivation to six places.
    - **Each curve's code domain** (the one correction to T3-2's spec: it assumed Apple's codes
      sit where Sony's do): Sony's and Panasonic's formulas read the STORED 10-bit code CV over
      1023 — their IRE columns are video levels (Sony's FAQ Q4: S-Log3 is written "Full
      (Extended) range", codes 0–1023 spanning −7 to 109 IRE), so CV = 64 + 876·s and y =
      (64 + 876·s)/1023. Apple's P is the normalized signal itself ("floating point encoding
      normalized to the [0,1] range"), its "10 bit, full range" codes being P·1023, so in the
      video-range file AVFoundation decodes, P = s. Step 0 reads both as y = codeScale·s +
      codeOffset: 876/1023 and 64/1023 for S-Log3 and V-Log, 1 and 0 for Apple Log. Accepted
      limits: a log file flagged full range is read as video range — Amended by GR-22; whether a
      real iPhone file is stored this way is GRD-17's.
    - **Apple Log 2 is IN** (the owner's "do a leftover now when it can be done", 2026-10-12):
      the paper gives Apple Wide Gamut's primaries and white, and the SDK names its label
      (`kCVImageBufferLogTransferFunction_AppleLog2`, macOS 26 — the deployment target — with
      primaries and transfer absent and the BT.2020 matrix). So `log` gains `apple_log2`, paired
      only with `gamut: "apple_wide_gamut"`, detected at import from its label as Apple Log is,
      and the popup gains "Apple Log 2". Its curve is Apple Log's; only the gamut differs. The
      "Not in" line above no longer names it.
    - **Frame Job's display transform** (choice 4a's mid-grey: the owner, 2026-10-12, "42%, as
      planned"): scene light R × the **exposure 0.42^2.4/0.18 (≈ 0.6927)**, so 18 % grey encodes
      to 0.42 (107/255, near BT.709's 0.409); the camera gamut's matrix; GR-15's lift; GR-15's
      shoulder with the **knee 0.39** and the **white 64·0.42^2.4 (≈ 7.98)**, six stops over 18 %
      grey; the encode L^(1/2.4). The test points through it: 0 % → 0, 18 % → 0.42, 90 % → ≈
      0.785 (200/255).
    - **Use LUT…** in step 0: the source's signal s, un-premultiplied, sampled at the lattice's
      texel CENTRES (as `gradeLook` samples a look), trilinear, clamped to the lattice; the
      output is taken as encoded Rec. 709 and goes on to step 3 unchanged (no exposure, matrix or
      shoulder). A LUT that cannot be drawn (missing, refused) leaves the source unconverted.
    - **The wire**: a recipe layer gains `input` after `look` — `{"log": "slog3", "gamut":
      "s_gamut3_cine"}`, `{"lut": 12}`, or `null` for none, for an image, text or burn-in, and for
      a media with no `color`; Show Ungraded keeps it. A plan video segment gains `input` ONLY
      when its media converts, the same object, so every other plan is byte-identical; a
      segment with `input` makes its composition converting (`CompositionPlan.convertsMedia`),
      and the layer's `input`, when set, decides that source's conversion before its labels.
    - **The format**: **version 19**, `media.color {log, gamut, lut, detected}`, each key written
      only when set (`detected` only when true); no migration step.
    - **T3-2's decisions** (the spec's, recorded): an absent `gamut` with a `log` is stored as
      the curve's first (Apple Log BT.2020, S-Log3 S-Gamut3.Cine, V-Log V-Gamut, Apple Log 2
      Apple Wide Gamut); `detected` is written by import only, and `set_media_color` refuses it;
      a relink's probe may not carry `color`, and a relink keeps the stored one (as Consolidate,
      which relinks without a probe); `remove_media` of a LUT that is a media's conversion is
      refused naming those media, and with `with_clips` clears the conversions with the looks;
      paste brings a pasted media's conversion LUT by path with it, and a pasted row whose LUT
      did not come drops its `color`; the Media tab's Camera Log section acts on the row
      selected in the list.
    - **Accepted limits**: thumbnails on the timeline and in the Media tab show the log picture;
      Sony's and Panasonic's own metadata is not read; a full-range-flagged log file is read as
      video range — Amended by GR-22. — Amended by GR-21: thumbnails are drawn through step 0.
  **Amended by HD-6** (hdr H-0): the media's colour record gains the PQ peak read at import (from
  the format description, else the first sample's HEVC SEI; MaxCLL first), which `set_media_color`
  overrides and refuses by name on media that is not PQ; its key is H-1's spec's.
  **Amended by HD-10** (hdr H-0): the `log` vocabulary gains Canon Log 2 and Canon Log 3 with Cinema
  Gamut, each built under this entry's recipe from Canon's published document (format 24); "Sony's
  and Panasonic's own metadata is not read" still stands.
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
