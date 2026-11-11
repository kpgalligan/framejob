# Spec §11 — decisions: HDR, each phase's settlements (road map "hdr")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the HD- series of [`hdr.md`](hdr.md), so a citation never has to say which file.
This file holds HD-13…HD-17, the settlements of H-2, H-3, H-4, H-6 and H-5. HD-18 on are in
[`hdr-3.md`](hdr-3.md). It is new because `hdr.md` had passed the spec's ~500-line split rule (#548,
2026-11-11); the entries moved here unchanged, and an "above" or "below" in one may now point into a
sibling file.

- **HD-13 — H-2's settlements: the lift's arithmetic, step 0's HLG arms, every drawn layer lifted
  at upload, the grade's BT.2020 constants, what reads through the inverse lift, the frames and
  the exports.** H-2's spec, recorded before its code; it settles what HD-2 and HD-3 left to the
  spec. Format 23.
  - **(a) The lift.** Core Media 709's γ 502/256 decode → linear BT.709 → BT.2020 → ×203/1000 →
    BT.2100's inverse OOTF (γ 1.2 on BT.2020 luminance: `E = Fd·Yd^((1−γ)/γ)`) → the HLG OETF.
    Computed 2026-10-19 by `tools/proof/work/h2/lift_math.py` (scratch, gitignored; run with
    `python3 -I`): it reproduces HD-3's CoreMedia709 row within 0.125 of a 10-bit level at all
    eight greys (0.10 → 0.13582 against 0.1359; 0.50 → 0.50583 against 0.5059; 1.00 → 0.74988
    against 0.7500), and its sRGB-EOTF twin reproduces HD-3's sRGB row within 0.127 (0.50 →
    0.46888 against 0.4690). **The toe, measured in H-2** (`hdr_probe.swift` P6, and a
    scratch drawing into `linearITUR_2020`): Core Graphics draws Core Media 709's γ curve
    with a slope limit — its decode is `max(s/16, s^γ)`, linear below grey 0.0559 (at 1/1023
    it gives 6.109e-5, 1/1023/16, where s^γ is 1.25e-6) — so the pure γ reproduced HD-3's
    eight greys but missed Core Graphics by up to 21 levels below 0.0559 (grey 11/1023: HLG
    0.0220 against 0.0425). HD-3 makes the lift Core Graphics' drawing, so the lift's decode
    takes the toe (`InputConversions.coreMedia709Toe`, 1/16; `InputUniforms.decodeToe`) and
    its inverse the matching `min(16·l, l^(1/γ))`; with it the CPU lift equals Core
    Graphics at all 1,024 greys within 0.25 of a level (P6).
  - **(b) The SDR arms' decodes.** Core Media 709's γ with (a)'s toe for BT.709, untagged and
    wide-gamut SDR sources and for a LUT's output; the sRGB EOTF for the sRGB transfer. Each is
    matrixed from its own primaries.
  - **(c) PQ.** Display light in cd/m². When the effective peak (HD-12) exceeds 1,000, BT.2390's
    EETF applies (Lb 0, target 1,000, `KS = 1.5·maxLum − 0.5`, its Hermite spline); then ÷ 1000
    clipped at 1, the matrix to BT.2020, the inverse OOTF and the OETF. Computed: peak 4,000,
    PQ 0.75 → 808.48 cd/m² → HLG 0.9675.
  - **(d) HLG over P3 or BT.709.** Inverse OETF → the matrix → floored at 0 → the OETF.
  - **(e) Camera log.** Reflection × 0.26741, so 18 % grey lands at HLG 0.3800 (BT.2408's 38 %);
    then the gamut matrix to BT.2020, floored at 0, and the OETF. No shoulder: reflection above
    3.74 clips at signal 1.
  - **(f) Every drawn layer is lifted at upload by step 0's own SDR arm**: text, captions, the
    burn-in, shapes, stills and graphics. CPU twins lift the background, a shadow's colour and
    Fade Through White's white. The missing-media slate is not lifted.
  - **(g) The grade's BT.2020 weights** apply in Color's saturation and hue (`lookHueChroma`,
    `gradeHueShift`), Hue vs Sat, tone, the chroma key's spill and the qualifier; tone's transfer
    becomes HLG's inverse OETF and OETF. Unchanged: the look bake (a lattice is its definition's,
    at Rec. 709 constants), the point filters and the scopes. The waveform's weights move to H-4
    with the rest of `Waveform.metal` (HD-8): this amends HD-2's list by phasing only.
  - **(h) What reads through the inverse lift.** The chroma key's distance and a luma matte's
    coverage read `unliftSDR` of the working value, saturated, against the stored Rec. 709
    numbers, so for every SDR source and drawn layer a key and a matte cut exactly what they cut
    in an SDR project: a white title as a luma matte covers 1, not 0.75, and a green screen keyed
    at [0, 1, 0] still keys after the switch. The eyedropper reads the HLG frame's code values
    (`FrameWriter.pickable`) and stores `unliftedPick` of them, so the stored key stays a Rec. 709
    colour in both outputs. The qualifier is not un-lifted: it keeps HD-2's working-space reading
    with BT.2020 weights, and Pick from Canvas stores the HLG value it reads. The un-lift was
    considered and declined: HD-2 names the qualifier's BT.2020 weights, and the un-lift
    saturates everything above SDR white at 1, so a luma or saturation range could never
    separate the highlights an HLG grade exists for; its ranges are re-picked after a switch,
    which the catalog says. Limit: an HDR source's key in an HLG project reads through the
    un-lift, not GR-15's Apple-anchored HDR→SDR arm (HD-4: HLG 0.50 → 143.1 against 97.1), so a
    key set on an HDR clip in an SDR project may need re-picking after the switch.
  - **(i) Frames.** Every HLG frame is read through the reader and labelled `itur_2100_HLG`; JPEG
    is refused: "JPEG cannot carry an HLG project's picture; save the frame as PNG or HEIC".
  - **(j) Exports.** The three 10-bit rows (`hevc_10bit`, `prores_422`, `prores_4444`) are
    tagged HLG (BT.2020 primaries, the HLG transfer, the BT.2020 matrix), HEVC with
    `kVTHDRMetadataInsertionMode_None`. Every other video row is refused: "{id} cannot carry an
    HLG project's picture; export it as hevc_10bit, prores_422 or prores_4444". Audio rows are
    unchanged.
  - **(k) The words.** The Document tab's Color row (amended by #526) reads "SDR — Rec. 709" or "HDR — Rec. 2100
    HLG"; the Canvas section's Dynamic Range popup offers "SDR" and "HDR (HLG)"; the Look
    section warns "This project is HDR (HLG): a .cube LUT reads its values as Rec. 709."
  - **(l) Known limits, each filed as an issue:** a still image labelled HLG or PQ is drawn as SDR
    (fixing it needs `LayerRenderers.swift`, an output-keyed image cache, a not-lifted flag
    through `LayerSource` and PQ tone mapping for stills), #311; (h)'s HDR-source key across a
    switch, #312.
  **Amended by HD-14** (hdr H-3): (i)'s JPEG and (j)'s non-10-bit video rows now write HD-4's
  SDR version instead of being refused; the JPEG sentence stays only as `FrameWriter`'s guard.
  **Amended by HD-19** (clean-up batch 2, phase 2): (f) an HLG- or PQ-labelled still is
  lifted by its own step-0 arm, not the SDR one (closing (l)'s first limit, #311); (h) the key
  on a layer whose source is HLG or PQ reads through GR-15's HDR→SDR arm, and the eyedropper
  stores the pick through it (closing (l)'s second limit, #312).
  **Amended by HD-22** (clean-up 3 batch B, phase 3): (f) in an HLG project a gain-map still is
  drawn from its HDR rendition through the `.pq(.bt2020)` arm, not lifted by the SDR one.
- **HD-14 — H-3's settlements: the knee at 0.9, one output pass chosen by the key's
  `dynamic_range`, the argument's spelling and its refusals, PQ at 1,000 cd/m² with HD-5's
  metadata, the frames, Show SDR Version's key and the sheet's row.** H-3's spec, recorded before
  its code; it settles what HD-4, HD-5 and HD-7 left to H-3. No format change.
  - **(a) The knee is 0.9**, choice 3a's shape, on the largest linear BT.709 channel over
    reference white (1 = 203 cd/m²), with W = 1000/203 and GR-15's extended-Reinhard shoulder
    after its gamut lift. Recomputed on HD-3's lift by `python3 -I
    tools/proof/work/h3/sdr_version_math.py` (scratch, gitignored; 2026-10-20, AC Power). The lift
    reads 0.10 → 0.13582, 0.42 → 0.43872, 1.00 → 0.74988. At knee 0.9 the levels of 255 are, with
    GR-15's beside them: SDR 0.42 title 107.1 (GR-15 87.4); SDR 0.75 grey 191.2 (127.7); SDR-white
    title **248.4** (154.2); iPhone HLG 0.50 **125.7** (97.1; the brief's 143.1 was BT.1886's);
    HLG 0.85 253.9 (189.4); HLG 0.90 254.4 (209.3); HLG 1.00 255.0. The white title by knee
    0.39/0.5/0.6/0.7/0.75/0.8/0.85/0.9/0.95 reads 212.7/220.7/227.8/234.8/238.3/241.7/245.1/
    248.4/251.7, and 249.6 needs knee 0.9170. The round trip is within 0.5 of a 10-bit level up to
    SDR 0.9531; the knee's SDR grey is 0.9477 (241.7/255). The SDR version at HLG
    0.10/0.25/0.40/0.50/0.60/0.70/0.75/0.80/0.90/1.00 is
    0.06875/0.21101/0.37509/0.49288/0.64091/0.85788/0.97430/0.99102/0.99762/1.00000 (the proof's
    oracle). **BT.2408's own HDR → SDR constants**, read for H-3 (Report ITU-R BT.2408-9, 2026,
    fetched from itu.int on 2026-10-20): the report gives no down-mapping curve or knee of its
    own; §5.2 prefers display-light down-mapping and points to Report BT.2446's three example
    methods, and says a live production's down-mapper follows "a complementary tone-curve to any
    SDR to HDR converters over the lower and middle signal ranges, with compressed highlights
    filling the upper SDR signal range" (a "hybrid-linear" down-mapper) — the shape of this
    choice; §7.1.3 records SDR content at 75 % HLG attenuated on the SDR output "to as little as
    86 % (a 14 % loss)", and round-trip losses "as low as 5 %" where a down-mapper uses the
    super-white range to EBU R.103's ~105 %. Frame Job's SDR deliverable has no super-white, and
    its round trip holds to SDR 0.9531, a loss of about 5 % below SDR white. The knee is unchanged
    by the reading.
  - **(b) One output pass** (`framejob_output_fragment`), for the preview, `render_frame` and
    export, chosen by the recipe key's `dynamic_range` option and drawn only in an HLG project
    whose key asks `sdr` or `pq`: HLG → scene light (the inverse OETF) → display light, scene ·
    Ys^0.2 on BT.2020 luma (1 = 1,000 cd/m²); the SDR version × W → BT.2020 to BT.709 → GR-15's
    gamut lift → the shoulder at the knee → Core Media 709's encode with HD-13 (a)'s toe, `min(16
    · l, l^(256/502))`; PQ × 0.1 → ST 2084's inverse EOTF (1 = 10,000 cd/m²). Premultiplied in
    and out. A composition's colour follows its key: BT.709 for `sdr`, BT.2020/PQ/BT.2020 for
    `pq`, BT.2020/HLG for `hlg`.
  - **(c) `dynamic_range`, not `range`**: `range` is already the export tool's `"project" |
    "in_out"` and the core's `{start, duration}` override, so HD-5's argument is spelled
    `dynamic_range` (`"hlg"`, `"pq"` or `"sdr"`; anything else refused: `export dynamic_range
    must be "hlg", "pq" or "sdr", not …`). Per row: an HLG project's 10-bit rows default to
    `hlg`; its other video rows write `sdr`, refusing `hlg` and `pq` by `{id} is 8-bit and writes
    the SDR version; export dynamic_range "{x}" as hevc_10bit, prores_422 or prores_4444`; an SDR
    project refuses `hlg` and `pq` by `dynamic_range "{x}" needs an HLG project; set_canvas
    output "hlg" first` and takes `sdr` as nothing; an audio row reads and ignores it. The
    resolved settings carry `color` (`hlg`, `pq` or `sdr`) only in an HLG project, so an SDR
    project's and an audio row's settings are the text they were. `rc_export_presets` gains
    `"hdr": true` on the three 10-bit rows alone.
    **Amended by CX-14** (codec-export C2): `av1` joins them, so four rows carry `"hdr"` and
    default to `hlg`, and the sentence reads `… export dynamic_range "{x}" as hevc_10bit, av1,
    prores_422 or prores_4444`.
    **Amended by CX-15** (codec-export C3): `av1_webm` joins them too, so five rows carry
    `"hdr"`, and the sentence reads `… as hevc_10bit, av1, av1_webm, prores_422 or
    prores_4444`.
    **Amended by CX-16** (codec-export C4): `vp9_webm` joins them too, so six rows carry
    `"hdr"`, and the sentence reads `… as hevc_10bit, av1, av1_webm, vp9_webm, prores_422 or
    prores_4444`.
  - **(d) PQ:** HLG display light at 1,000 cd/m² → ST 2084, so nothing exceeds 1,000 cd/m².
    HD-5's metadata is written as two blobs: the mastering display (ST 2086 in SEI 137's order:
    P3's G, B, R, D65, max 1,000 and min 0.005 cd/m² in 0.0001) `33c2 86c4 1d4c 0bb8 84d0 3e80
    3d13 4042 0098 9680 0000 0032`, and the content light level (MaxCLL 1,000, MaxFALL 0) `03e8
    0000`; HEVC beside its existing keys with NO HDR-metadata insertion-mode key, ProRes as a
    compression dictionary of the two keys alone.
  - **(e) Frames:** `render_frame {sdr_version}`, and a JPEG from `render_frame` or Save Frame…
    in an HLG project, draw the SDR version through the reader: a 16-bit PNG, a 10-bit HEIC or a
    JPEG, labelled `frameSpace` (BT.709, PR-11). HD-13 (i)'s JPEG refusal stays only as
    `FrameWriter`'s guard.
  - **(f) Measured for H-3's spec** (M-H3a, 2026-10-20): H-0's spike binary
    (`tools/proof/work/h0/spike/spike`, key `f4c98006cae6b461`) ran `write-hdr
    tools/proof/work/h3/m1/w_<k>.mov <k>`, read with ffprobe 9.0.2. `pq-explicit` (HEVC Main 10,
    explicit keys, no insertion-mode key): `bt2020nc/smpte2084/bt2020`, mastering
    `min_luminance=50/10000 max_luminance=6000000/10000`, CLL 600/200, and no DOVI configuration
    record or RPU. `pq` (Auto): 5/10000, 10000000/10000, 1000/400, no DOVI. `hlg` (no key): DOVI
    profile 8 level 1 compatibility 4 with RPU. `prores-pq-explicit`: ProRes 422 HQ with our
    values. So PQ HEVC sets no insertion-mode key, and HLG HEVC keeps `None`. MaxFALL 0 was
    unmeasured there; `hdr_proof.py`'s DP is its first measurement.
  - **(g) Show SDR Version** (HD-7): it sets `dynamic_range = .sdr` on the document's recipe key;
    the canvas tag "SDR Version" shows; the preview's composition is recoloured BT.709 by
    re-assigning the item's composition, with no rebuild. It has no shortcut, writes no
    `UserDefaults` (so it is not a persisting menu item, and proofs may perform it), is always
    enabled, and never reaches Save Frame…, `render_frame`, an export or the eyedropper. In an SDR
    project it changes no pixel and its tag still shows, and `render_frame {sdr_version: true}` is
    byte-identical to without.
  - **(h) The sheet:** a "Dynamic Range:" row under Format, only in an HLG project. On a 10-bit
    row (`hdr`) it offers "HDR (HLG)", "HDR10 (PQ)" and "SDR version", default HDR (HLG); on any
    other row it is disabled, showing "SDR version", and sends no override. The choice is not
    remembered by the export choice or user presets.
  - **(i) Amends** HD-4 (the knee and its recomputed rows), HD-5 (the spelling), HD-7 ((g)) and
    HD-13 ((i), (j): JPEG and the non-10-bit rows now the SDR version).
  **Amended by HD-16** (hdr H-6): the output pass is also drawn for every project whose
  `canvas.blending` is `linear`, encoding its linear destination (HD-16 (f)).
- **HD-15 — H-4's settlements: the scopes read the picture shown, the SDR version's as an SDR
  project's, the HLG master's on BT.2020's weights, matrix and targets with a cd/m² scale.**
  H-4's spec, recorded before its code; it settles what HD-8 left to H-4. No tool, argument, op
  or format change.
  - **(a) The scopes read the picture shown**, as GR-5 rules: the tap reads the frame the
    compositor finished, and `render_frame` the frame it wrote. In an HLG project that picture is
    the HLG signal, so the scopes read HLG.
  - **(b) Show SDR Version, `render_frame {sdr_version}` and an HLG project's JPEG frame** read
    the SDR version's Rec. 709 signal exactly as an SDR project's scopes do: Rec. 709's weights
    and matrix, the 0/50/100 labels, the "Rec. 709 · encoded" caption, and JSON with no `signal`
    or `scale` key. **Why:** the scopes measure the deliverable on screen, the HLG master is one
    toggle away, and the tap reads the one frame the compositor finished; reading the HLG master
    under the SDR picture would need a second composite the tap does not have.
  - **(c) Show Ungraded** in an HLG project reads the ungraded HLG picture on the HLG scale; with
    both switches on, the scopes read the ungraded SDR version.
  - **(d) The signal comes from the recipe canvas** the frame was drawn with (`ScopeSignal(canvas:)`,
    HLG iff the canvas is HLG and its `dynamic_range` is not `sdr`), so the panel follows the
    frame, not the window's switches. PQ never reaches a scope: an export has no tap, and
    `render_frame` has no `pq`.
  - **(e) The kernels take a 0/1 `signal` uniform** (the waveform and histogram at `buffer(1)`,
    the vectorscope at `buffer(2)` beside its zoom at `buffer(1)`; the parade, whose channels
    carry no weights, none) that chooses between two compile-time constant sets: Rec. 709's
    (today's expressions, unchanged in text) and BT.2020's (`0.2627, 0.6780, 0.0593`, Cb =
    (B′ − Y′)/1.8814, Cr = (R′ − Y′)/1.4746). The weights themselves are not uniforms, so the
    SDR arm stays T4-0's arithmetic (scopes_proof S12). This amends HD-8's "as uniforms".
  - **(f) The scale.** The waveform's and parade's gutter labels at 0/25/50/75/100 % read 0, 10,
    51, 203 and 1000 (cd/m², `ScopeSignal.hlgNits` rounded: a grey at BT.2100's 1,000 cd/m²,
    1000·E^1.2 with E the HLG inverse OETF), right-aligned 2 pt from the well (4 pt in SDR) so
    "1000" fits the 24 pt gutter; the 75 % line, reference white, is dashed (3 pt on, 3 pt off,
    white α 0.45) in place of its solid line. The clip marks and readouts are unchanged: level
    255 is 100 %, 1,000 cd/m². The slot's caption reads "HLG · cd/m²" over a waveform or parade
    and "Rec. 2100 HLG" over a vectorscope or histogram, following the last trace shown. The
    histogram draws no scale.
  - **(g) The vectorscope** in an HLG project uses BT.2020's matrix and BT.2111's 75 % bars, (0.75,
    0, 0) and so on, through it, and the skin line of the ColorChecker patch (194, 150, 130)/255
    lifted by HD-3's lift (`InputConversions.liftSDR`), then BT.2020's matrix. Computed by
    `python3 -I tools/proof/work/h4/h4_math.py` (scratch, gitignored; 2026-10-20, through
    `hdr_proof.py`'s own `lift`): R Cb −0.10472 Cr 0.37500, bins (101, 224) at ×1 (Rec. 709's
    (106, 224)); Mg 0.27028, 0.34484, (197, 216) ((202, 215)); B 0.37500, −0.03016, (224, 120)
    ((224, 119)); Cy 0.10472, −0.37500, (155, 32) ((150, 32)); G −0.27028, −0.34484, (59, 40)
    ((54, 41)); Yl −0.37500, 0.03016, (32, 136) ((32, 137)). At ×2 only R's Cb 75, B's Cr 113,
    Cy's Cb 181 and Yl's Cr 143 stay on the plot, so every target is a rim tick there, as at
    ×4. The skin line is 139.9164° (the lifted patch 0.63832, 0.57381, 0.50898); Rec. 709's
    stays 123.2783°.
  - **(h) The JSON and the sentences.** An HLG project's waveform, parade and histogram JSON add
    `"signal": "hlg"` and `"scale": {"unit": "cd/m²", "ticks": [{percent, level, nits}…],
    "reference_white_percent": 75, "clip_percent": 100}`, the ticks 0/0/0.0, 25/64/9.6,
    50/128/50.7, 75/191/203.2 and 100/255/1000.0 (level round(255·p/100), halves away from zero;
    nits `hlgNits` to 0.1); the vectorscope's adds `"signal": "hlg"`, `"matrix": "Rec. 2020"` and
    (g)'s targets and skin line. The sentences: "Waveform (HLG signal; reference white at 75 %,
    203 cd/m², and 100 % at 1,000 cd/m²): …", "Parade (HLG signal): …", "Vectorscope (Rec. 2020
    Cb and Cr of the HLG values): …" (and "Vectorscope at ×Z (Rec. 2020 …)"), "Histogram (HLG
    signal): … (by Y′, BT.2020 weights); …". An SDR project's, the SDR version's and a JPEG
    frame's JSON and sentences are byte-identical to before H-4.
  - **(i) Nothing new to call or persist:** no tool, argument, op, format or `UserDefaults` key;
    `render_frame`'s description gains one sentence. GR-10's counting rule, the latest-wins tap,
    the 256 levels and bins and GR-31's zoom rule are unchanged.
  - **(j) Amends** HD-8 ((e): a signal, not weights, as the uniform; (b), (c), (f), (h)), GR-10
    and GR-31 (as HD-8 does).
- **HD-16 — H-6's settlements: `canvas.blending`, the decode once per layer after the grade, a
  linear destination encoded once by the output pass, and every reading that keeps its meaning
  kept encoded.** H-6's spec, recorded before its code; it settles what HD-9 and GR-18 left to
  the spec. Format 24 (HD-11).
  - **(a) The key, the op and nests.** `canvas.blending`, `"encoded"` (the default, GR-3) or
    `"linear"`, after `output`, written only when `linear`; `set_canvas {blending}` sets it,
    one undoable step, and an unknown value is refused naming both. Setting the value the canvas
    already has is an identity through `finish`. The recipe canvas carries `"blending":
    "linear"` last (after `output` and `dynamic_range`), for any output, only when linear;
    `get_project` shows it only when linear; the plan is unchanged. A nest shares its document's
    blending: it is flattened into the document's recipe, and `scoped_view` copies the key. No
    new tool or op (92 product tools), no FFI export.
  - **(b) What "linear" means:** the project's own transfer as scene light, with no OOTF — the
    IEC 61966-2-1 pair (`gradeDecode`/`gradeEncode`, GR-18's `linear.py`) in an SDR project,
    HLG's inverse OETF and OETF (BT.2100) in an HLG project.
  - **(c) Where the decode runs:** once per layer, in `layerColorPremultiplied`, right after the
    `if (effects) { … }` block (steps 1–6, with 7a and 9a, which touch alpha only) and before
    7b: `if (u.linearLight > 0.5) rgb = blendDecode(rgb, u.hlgOutput);`. The route is GR0's
    uniform flag (`LayerUniforms.linearLight`, H-2's reserved float renamed), and it does not
    join the effects sum. The gather filters stay encoded (GR-18: blur and sharpen move only if
    the decode moves before the gather). Coverage, the transition weight, opacity, the
    reflection's fade, premultiplication, fixed-function source-over and all eight blend modes
    act on linear values; their formulas are unchanged, and `overlay`'s 0.5 test reads the
    linear backdrop.
  - **(d) Linear too:** the background is cleared to the decode of HD-13's lifted colour
    (`RecipeCanvas.blended`); Fade Through Black and White's colour goes through `blendDecode`;
    a shadow's colour through `blended` after its lift; matte composites, and a routed
    dissolve's halves and their mix, are linear, because the same stage draws them, so a routed
    dissolve equals the unrouted one.
  - **(e) Read encoded, so a value keeps its meaning:**
    - the adjustment pass encodes the un-premultiplied destination before its qualifier and
      grade, then decodes the graded colour before its strength mix. The mix `mix(dst, g, w)`
      stays in linear light, as every other opacity does under (c): where `w` is 0 or 1 the
      result equals the encoded one, and in a qualifier's soft band or blur it is the linear mix
      of the same two colours;
    - the qualifier-map pass (GR-35's blur) encodes the same way;
    - Show Selection writes `blendDecode(q · coverage)`, so the frame shows the grey it showed
      before;
    - a luma matte reads the encoded straight colour (then HD-13 (h)'s un-lift in an HLG
      project), premultiplied, so it cuts what it cut before; alpha mattes are unchanged;
    - the chroma key (step 3) is unchanged, since it runs before the decode;
    - the scopes, picks and the eyedropper read the output pass's encoded frame (GR-18).
  - **(f) The output pass** (HD-14 (b)) is drawn for every linear project. `OutputUniforms`'
    two reserved floats become `linearLight` and `hlgOutput`. An SDR project draws `mode` 0
    and `gradeEncode`; an HLG master `mode` 0 and the HLG OETF; HLG with `sdr` or `pq` (modes 1
    and 2) starts from the linear destination as its scene light in place of
    `hlgInverseOETF(signal)`. The pass stays premultiplied in and out. An encoded project's
    `uniforms(for:)` is exactly what it was, so its frame draws the passes it drew.
  - **(g) The Document tab:** the Canvas section gains a "Blending" popup after Dynamic Range,
    "Encoded" and "Linear light". Each change is one `set_canvas {blending}` step named
    "Blending"; there is no summary row.
  - **(h) Unchanged:** thumbnails and the Media tab (a media thumbnail is one clip, not the
    project's blend), the look bake, Show Ungraded and GR-3's default.
  - **(i) The costs** are GR-18's figures (+0.000–0.001 ms at 4K for the decode and encode,
    one output pass of about a copy, C0's 0.21 ms); H-6's TL measures them.
  - **(j) The order.** H-6 runs before H-5, amending HD-1's and HD-9's "#276 last": H-5 waits
    on Canon's own log document, which the owner has not supplied, and H-6 needs nothing H-5
    adds (HD-1's own "why this order" puts H-6's dependencies on H-2 and H-3 only). H-6 is
    still the first phase to drop. So H-6 takes format 24 and H-5 25 (HD-9, HD-10, HD-11).
  - **Amends** HD-1 and HD-9 (the order; their text and titles otherwise unchanged) and HD-14
    (b) (the output pass is also drawn for a linear project).
- **HD-17 — H-5's settlements: Canon Log 2 and Canon Log 3, each with Cinema Gamut or BT.2020,
  from Canon's curve paper and the ACES project's Canon CSC.** H-5's spec, recorded before its
  code; it settles what HD-10 left to the spec. Format 25 (HD-11).
  - **(a) Sources.**
    - The curves: Canon U.S.A., *Canon Log Gamma Curves* white paper, November 1st, 2018 (10
      pages; sha256 `cc77333058e4c37d53ee8b3809a04d05e36d0d2e69e759a3ca8c88eea2a7341e`):
      Appendix [2] (Canon Log 2, revised), [3] (Canon Log 3), table [4], FAQ Q6 and Q7. Its only
      terms are "© 2018 Canon USA, Inc. All rights reserved."; FAQ Q4 says the formulas were
      supplied to application vendors. It is read in place, never copied.
    - Cinema Gamut: the ACES project's Canon CSCs, `canon/CSC.Canon.CLog2_CGamut_to_ACES.ctl`
      and `canon/CSC.Canon.CLog3_CGamut_to_ACES.ctl`, in
      github.com/aces-aswf/aces-input-and-colorspaces (SPDX Apache-2.0, "Copyright Contributors
      to the ACES Project"), re-read 2026-10-20. Its chromaticities: R 0.7400 0.2700, G 0.1700
      1.1400, B 0.0800 −0.1000, white 0.3127 0.3290 (D65).
    - No ACES code is copied: the matrices are derived by `InputConversions.rgbToXYZ`. The CSCs'
      curves and their 0.9 agree with the paper (a cross-check only).
    - The owner chose this on 2026-10-20: "Use ACES, both gamuts (Recommended)".
  - **(b) Vocabulary.**
    - `log`: `canon_log2`, `canon_log3`. `gamut`: `cinema_gamut`. Each curve pairs with
      `cinema_gamut` (first, the default) or `bt2020`.
    - The Camera Log popup's rows, after V-Log: "C-Log2 / Cinema Gamut", "C-Log2 / BT.2020",
      "C-Log3 / Cinema Gamut", "C-Log3 / BT.2020".
    - Why "C-Log" (the owner's words, "Canon C-Log2/3"): "Canon Log 3 / Cinema Gamut" is 26
      characters, about 172 pt in IBM Plex Mono 11, wider than the 168 pt popup
      (`popupWidth + 52`). The catalog and the spec's prose say Canon Log 2 and 3.
  - **(c) Curves.** x is Canon's scene linear; y the normalized signal.
    - Canon Log 2: for y ≥ 0.092864125, x = (10^((y − 0.092864125)/0.24136077) − 1)/87.099375;
      below it, x = −(10^((0.092864125 − y)/0.24136077) − 1)/87.099375.
    - Canon Log 3: for y < 0.097465473, x = −(10^((0.12783901 − y)/0.36726845) − 1)/14.98325;
      for y ≤ 0.15277891, x = (y − 0.12512219)/1.9754798; otherwise x = (10^((y −
      0.12240537)/0.36726845) − 1)/14.98325.
  - **(d) Scale.** Reflection R = 0.9·x ("reflection = Scene Linear × 0.9"). 18 % grey (x =
    0.2) therefore keeps GR-16's anchor (0.42) and HD-13 (e)'s (HLG 0.380).
  - **(e) Code domain.** y = s, (1, 0), in both ranges: Q6 says clips are recorded full range,
    and Q7 that ProRes's RGB readout is full range. This is Apple Log's rule under GR-22, not
    S-Log3's.
    - `readsRange` stays false, so there is no GR-23 `fullRange` marker.
    - Accepted limit: a video-range-flagged non-ProRes file storing full-range codes reads too
      contrasty (GRD-19).
  - **(f) Step 0.** Kinds 10 and 11.
    - SDR: GR-16's transform (exposure, the gamut's matrix to BT.709, lift, shoulder, encode).
    - HLG: HD-13 (e) (×0.26741, the matrix to BT.2020 — the identity for `bt2020` — the OETF,
      no shoulder).
    - Thumbnails follow (GR-21). No detection; #278 stays open.
  - **(g) Test points.** The formulas reproduce table [4]'s 10-bit full-range codes:
    - Canon Log 2, 0/20/100/800/1600/6400 %: 95/407/575/797/871/1020;
    - Canon Log 3, 0/20/100/800/1600 %: 128/351/577/908/1020.
    - Video-range ProRes stores 64 + 876·y: 145/413/557 (Canon Log 2) and 174/365/558 (Canon
      Log 3) at 0/18/90 % reflection.
    - A stored code's tolerance is its own 10-bit step: the reflections decoded from code − 0.5
      and code + 0.5, each signal rounded to half, never tighter than ±0.005 reflection. Reason:
      Canon Log 2's slope is low near 90 %; code 557's half, 0.562988, sits against the true
      0.562304 and decodes to R 0.90596.
  - **(h) Format 25.** No migration. No op, tool (92), FFI export or `InputUniforms` field.
  - **(i) Amends** HD-10 (its sources and pairings) and GR-16 (its vocabulary).
