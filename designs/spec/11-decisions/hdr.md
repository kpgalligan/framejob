# Spec §11 — decisions: HDR (road map "hdr")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is in progress: `designs/hdr.md` holds each phase's record (H-0 the
road map, these decisions and the two pure moves; H-1 #281, the PQ peak; H-2 #277's HLG working
space; H-3 #277's deliverables; H-4 #277's HDR scopes; H-5 #278's curves; H-6 #276, linear light;
H-7 the close). HD-1…HD-11 were recorded in H-0, before any HDR code, from the owner's answers of
2026-10-19 to the HDR brief's twelve choices, every one the recommended answer: four were asked
as questions and the other eight were stated to the owner as taken (`designs/hdr.md`, "The
owner's choices"; the brief is `~/.claude/litecode/framejob/hdr-brief/I-hdr.md` and the answers
`answers.md` beside it, outside the repo). H-1…H-6 each record their numbers as a new entry (HD-12
on) or as Amended-by lines before their code.

**Stands, and nothing here re-litigates it:** GR-3 (blending stays encoded; H-6's linear light is
an opt-in switch, off for every project); GR-18's text (H-6 builds it as written); GR-20 (a wide
working gamut comes only as Rec. 2020 inside the HDR timeline, which this is); PR-1 (encoded
values clamped to [0, 1], in an HLG project HLG values); PR-3 (`hevc` stays pinned to Main: it
carries the SDR version); the foundations' "`AVPlayerLayer` under an overlay view" (the brief's
M8 found the layer handed an HLG-labelled frame and asking for `high` dynamic range by default,
so no reason to replace it). **A risk that would reopen the last:** if HDR-1 (a person at the XDR
display) finds the HLG preview tone-mapped rather than shown in EDR, the first fallback is setting
the layer's `preferredDynamicRange` explicitly; failing that, a `CAMetalLayer` preview, which
would amend the foundations' decision and is the owner's call, not an agent's.
**The Concat rule** (`designs/adr/effects-survey.md`, "Licensing") stands for every phase: the
conversions come from ITU-R BT.2100, BT.2408, BT.2390, BT.2020 and BT.709, SMPTE ST 2084 and
ST 2086, CTA-861.3, ITU-T H.265's SEI syntax and each camera maker's own published log document;
matrices are derived from published primaries and D65; Apple's conversions are MEASURED as
targets, never copied; every fixture is written by a script. Nothing of Concat is opened, at
design time or build time.

- **HD-1 — The HDR road map builds everything the brief offered, in this order: #281, then
  #277 in three phases, then #278's curves, then #276 last.** Choice 1a (owner, 2026-10-19:
  "Everything (Recommended)").
  - **H-1, #281:** the PQ white from the media's own peak (HD-6).
  - **H-2, #277:** the HLG working space (HD-2, HD-3), with the 10-bit rows exported as HLG and
    every other row refused in an HLG project (HD-5).
  - **H-3, #277:** the deliverables (HD-4, HD-5) and Show SDR Version (HD-7).
  - **H-4, #277:** the HDR scopes (HD-8).
  - **H-5, #278:** the new log curves (HD-10); detection from the maker's metadata stays open.
  - **H-6, #276:** linear-light blending as GR-18 wrote it (HD-9), last and the first to drop.
  - **H-7:** the close — the ADR, the archive, the manual-check rows, the issues; #274 measured
    only if a real clip is at hand (it is not HDR work); #280 stays closed under PR-7.
  - **Why this order** (the brief's §9): H-1 needs nothing, and H-2's PQ → HLG arm uses its
    peak; H-3 and H-4 need H-2's working space; H-5 after H-2 tests each curve's log → HLG arm
    too; H-6's decode follows H-2's transfer and its encode belongs in H-3's output pass. Every
    blend, opacity and dissolve is untouched by H-1…H-5.
  - Risk accepted: every proof is synthetic; how an HDR picture looks on a panel is the person
    checks' (the HDR rows, each added by the phase that creates it).
- **HD-2 — An HLG project works in HLG-encoded BT.2020 values: GR-19's design, built in H-2.**
  Choice 1a (owner, 2026-10-19).
  - **The setting:** `canvas.output` is `"sdr"` or `"hlg"`, absent = SDR, written only when
    `hlg`; `set_canvas {output}` sets it, one undoable step; format 23 (HD-11). A property of the
    canvas because the preview, `render_frame` and every export must agree (GR-19).
  - **The values:** every value between stages is an HLG signal in 0…1 over BT.2020 primaries,
    with PR-1's clamps; blending stays encoded, now in HLG (GR-3). A grade's numbers keep their
    0…1 meaning (GR-11…GR-13), so switching the output keeps every grade.
  - **The composition:** every composition of an HLG project is converting
    (`ConvertingCompositor`), its colour BT.2020/HLG. Measured for the brief (M2, a scratch
    instrument making the app's AVFoundation calls): BT.709, untagged, HLG and PQ sources all
    arrived native and labelled as their files are, and the render context's buffers and the
    export reader's output were labelled BT.2020 + HLG.
  - **Step 0's HLG arms**, chosen by the canvas's output as well as the buffer's labels: SDR →
    HLG by HD-3's lift; HLG over BT.2020 the identity; HLG over P3 or BT.709 matrixed to BT.2020
    in scene light; PQ → HLG at 1,000 cd/m² (BT.2408), through BT.2390's EETF when the media's
    peak (HD-6) exceeds 1,000; wide-gamut SDR lifted with its own primaries; camera log by the
    maker's inverse curve to scene light, its gamut to BT.2020 and HLG's OETF; a LUT's Rec. 709
    output lifted as SDR. In an SDR project every arm is today's.
  - **Layers Frame Job draws** (text, shapes, stills, graphics, captions, the burn-in) are lifted
    by HD-3's lift once, at upload, keyed in their pool with the output; the canvas background
    colour is lifted as a uniform.
  - **The grade in an HLG project:** BT.2020's luma weights (0.2627, 0.6780, 0.0593) replace
    Rec. 709's in Color's saturation and hue, tone, the qualifier, the chroma key and the
    waveform; tone's local linear light uses HLG's inverse OETF and OETF instead of the sRGB
    transfer, so exposure +1 still doubles the scene light. Looks and `.cube` LUTs keep their
    0…1 meaning, and the Look section warns when a LUT is applied in an HLG project.
  - **Frames:** `render_frame` and Save Frame… of an HLG project write a 16-bit PNG or a 10-bit
    HEIC labelled BT.2100 HLG, whatever the sources. Measured for the brief: the generator's
    CGImage of an HLG composition is 16-bit but labelled `QuickTime 'nclc' Video (9,1,2)`
    (M3), so the frame is relabelled; ImageIO writes the PNG with a `cICP` chunk 9/18/0/1 (M4).
    JPEG is the SDR version (HD-5).
  - **Every SDR project stays byte-identical**: PR-5's frozen references, `precision_proof.py`
    K1–K6, `hdr_proof.py` H1 and every neutral row of the grading tiers.
  - **Amends**, each an extension the owner chose that applies only in an HLG project, so
    nothing an SDR project does is reopened: GR-19 (its design built); GR-15 (step 0 gains the
    HLG arms); PR-4 (an HLG project's frames are 16-bit whatever their sources); PR-11 (an HLG
    project's frames are labelled BT.2100 HLG); GR-2 (tone's luma weights and transfer); GR-13
    (the qualifier's luma weights); GR-32 and GR-33 (the hue shift keeps BT.2020 luma).
  - Risk accepted: an HLG project adds a step-0 pass for every SDR source (REASONED at the
    tier-3 TI's +0.455 ms per 4K source), so a heavy 4K HLG frame may pass PR-1's 8 ms budget;
    H-2 measures it.
- **HD-3 — SDR white sits at 203 cd/m² (HLG 0.75), fixed, and one lift serves every SDR source
  and every layer Frame Job draws: Core Graphics' conversion from `kCGColorSpaceCoreMedia709`
  into `itur_2100_HLG`.** Choice 2 (taken as recommended, stated to the owner before the
  questions).
  - **Fixed, with no project setting:** GR-19 already put SDR white at BT.2408's HDR reference
    white, and a "graphics white" setting (as Premiere's 100, 203 or 300 cd/m²) can follow if
    someone asks.
  - **The mid-tones:** candidate lifts all put SDR white at HLG 0.75 but part in the mid-tones.
    The lift is the one that reads Frame Job's SDR frames as Apple reads them, as GR-15 anchored
    its shoulder on Apple's points: `kCGColorSpaceCoreMedia709` is the label ColorSync reads
    Frame Job's converted SDR frames through (GR-15's sRGB arm; PR-11's `frameSpace` is the
    same space), so the lift is Core Graphics drawing that space into `itur_2100_HLG`.
  - **Measured in H-0** (2026-10-19, Apple M2 Max, macOS 26.5.1 (25F80), `pmset -g ps`: "Now
    drawing from 'AC Power'"): the brief's spike copied into `tools/proof/work/h0/spike/`
    (gitignored), built by `python3 tools/proof/swift_build.py build --output
    tools/proof/work/h0/spike/spike tools/proof/work/h0/spike/main.swift`, then `./spike
    cg-hlg` and `python3 -I hdr_math.py` in that folder. A grey drawn in each source space into
    a 16-bit-float `itur_2100_HLG` bitmap reads, at SDR 0.00 / 0.10 / 0.25 / 0.42 / 0.50 / 0.75 /
    0.90 / 1.00:
    - **`CoreMedia709` → `ITUR_2100_HLG` (the lift): 0.0000 / 0.1359 / 0.2871 / 0.4387 /
      0.5059 / 0.6548 / 0.7158 / 0.7500.**
    - sRGB → `ITUR_2100_HLG`: 0.0000 / 0.1310 / 0.2576 / 0.4014 / 0.4690 / 0.6401 / 0.7104 /
      0.7500.
    - `itur_709` → `ITUR_2100_HLG`: 0.0000 / 0.1197 / 0.2993 / 0.5029 / 0.5845 / 0.7529 /
      0.8232 / 0.8633 (white not at 0.75, so not a candidate).
    - BT.2408 through BT.1886 (`hdr_math.py` §1, computed): 0.0000 / 0.0891 / 0.2228 / 0.3743 /
      0.4456 / 0.6327 / 0.7080 / 0.7499.
    - Every figure the brief's M6 quoted from the same commands is reproduced.
  - **H-2 holds its rows to it:** its SDR → HLG step-0 arm, the lift of every drawn layer at
    upload and the background's uniform reproduce the CoreMedia709 row above within one 10-bit
    level (HS, HT), so a title and a recording of the same grey stay equal after the lift.
  - **Amends GR-19:** its 203 cd/m² stands; GR-19 named "BT.2408's SDR→HLG mapping" and left the
    mid-tones open, and HD-3 fixes the curve by this measurement — an owner-chosen, measured
    extension, not a re-litigation.
- **HD-4 — The SDR version of an HLG project is the inverse of HD-3's lift, with a shoulder
  above reference white.** Choice 3a (owner, 2026-10-19: "Inverse of the lift (Recommended)").
  - **What it is:** HLG → display light (1,000 cd/m², system gamma 1.2) → ÷ 203 → BT.2020 to
    BT.709 → the inverse of HD-3's lift up to a knee near reference white and a shoulder above
    it → the Rec. 709 encode. Everything up to near reference white comes back as it went in;
    only brighter highlights are compressed.
  - **Why:** a title that is white in the HDR master has to be white in its SDR version.
    Computed for the brief (`hdr_math.py`, greys, levels of 255): an SDR-white title (HLG
    0.7499) comes back at 249.6 with a knee at 0.9, against 154.2 through GR-15's
    Apple-anchored arm (choice 3b).
  - **The price, accepted:** phone HDR footage reads brighter in an HLG project's SDR version
    than the same clip in an SDR project: HLG 0.50 → 143.1 against 97.1 (computed, the same
    table).
  - **Where it is used:** every 8-bit row, GIF, APNG and JPEG (HD-5), and Show SDR Version
    (HD-7) — one path, chosen by the recipe options of the key drawn, so the preview,
    `render_frame` and the export share it.
  - **The knee:** H-3 fixes it against the brief's rows (copied into `designs/hdr.md`, "The SDR
    version, computed"), after reading BT.2408's own HDR → SDR constants, and records it here
    by an Amended-by line before its code. The brief computed those rows on the inverse of the
    BT.1886 route (`hdr_math.py` §1), not of HD-3's measured lift, so H-3 recomputes them on
    HD-3's before fixing the knee.
  - GR-15's mapping is not touched: it stays the conversion of HDR sources in SDR projects.
- **HD-5 — The deliverables: HLG, HDR10 (PQ) or SDR on the 10-bit rows, the SDR version on every
  other row; Dolby Vision off; the HDR10 metadata fixed.** Choices 4a, 5a and 6a (owner,
  2026-10-19: "HLG + HDR10, DV off (Recommended)").
  - **The 10-bit rows** (`hevc_10bit`, `prores_422`, `prores_4444`) of an HLG project write HLG
    by default. `export {range: "hlg" | "pq" | "sdr"}` and the export sheet's Dynamic Range
    popup (HLG · HDR10 (PQ) · SDR) choose. `range` is resolved in the core's export resolver,
    per row: the canvas's output for a 10-bit row, `sdr` otherwise. It is a per-export
    argument, not persisted state.
  - **Every other row** (`h264`, `hevc`, `hevc_alpha`, `gif`, `apng`) and JPEG frames write the
    SDR version (HD-4).
  - **Refusals**, each in its own sentence: `hlg` or `pq` on an 8-bit row, and `hlg` or `pq` in
    an SDR project. Until H-3 lands, H-2 refuses every row but the three 10-bit ones in an HLG
    project, so a merged phase never writes HLG pixels labelled BT.709.
  - **Dolby Vision off** (choice 5a): HEVC is written with `kVTHDRMetadataInsertionMode_None`.
    Measured for the brief (M7): without it VideoToolbox adds a Dolby Vision profile 8.4
    configuration and RPU frames to an HLG HEVC Main 10 file by itself; with it, the same
    `bt2020nc/arib-std-b67/bt2020` tags and no Dolby Vision. Every player then shows the HLG
    that was graded.
  - **HDR10's metadata is fixed** (choice 6a): a P3-D65 mastering display at 0.005–1,000
    cd/m², MaxCLL 1,000, MaxFALL 0 ("unknown"), in one pass. True by construction: PQ is HLG
    → display light at 1,000 cd/m² → ST 2084, so nothing exceeds 1,000 cd/m². Measured for the
    brief (M7): explicit values are written exactly, by HEVC and ProRes 422 HQ alike.
  - **Amends GR-19:** PQ becomes an export range, not a `canvas.output` value (GR-19 left PQ "a
    later option" without saying where), and every 8-bit row carries the SDR version, not only
    GIF and APNG ("GIF and APNG stay SDR"). PR-3 stands: `hevc` stays Main and carries the SDR
    version.
- **HD-6 — #281: a PQ media's own peak sets step 0's PQ white; 1,000 cd/m² when unknown.**
  Choice 7a (taken as recommended, stated to the owner before the questions; the owner's
  2026-10-14 comment on #281 asked for it as a feature).
  - **Read at import:** first the format description's mastering-display and content-light
    extensions; failing those, the first video sample's prefix SEI payloads 137 (mastering
    display) and 144 (content light level), parsed by the core from bytes as a pure function
    (Swift reads the bytes). The peak is **MaxCLL when present and non-zero, else the mastering
    display's maximum**.
  - **Stored on the media** (its key and shape H-1's spec names), with `detected` semantics like
    Apple Log's; shown in the Media tab with an override; `set_media_color` takes the override,
    one optional key and no new op; a peak on media that is not PQ is refused by name.
  - **Step 0:** PQ's white is peak/203 instead of 1000/203, held at 1 or above (above the
    knee); an unknown peak means 1,000, so every unlabelled file renders byte-identical.
    Computed for the brief (`hdr_math.py`, levels of 255 at the PQ arm's output): at PQ 0.70
    (620.9 cd/m²) a 600 cd/m² peak gives 255.0, today's 1,000 gives 246.9, 4,000 gives 242.8.
  - **Thumbnails follow** (GR-21), as they follow Camera Log. **Format 22** (HD-11).
  - **Why both routes:** measured for the brief (M5), AVFoundation reads HDR10 metadata only
    from the sample description, as Apple's writer stores it, and not from the HEVC stream,
    where ffmpeg, HandBrake and x265 write it.
  - **B96's evidence, corrected:** B96 recorded Apple's own reading as identical across its
    four PQ files, but those files carried the metadata in the SEI only, which AVFoundation does
    not see (M5). The brief re-ran the comparison on two Apple-written files whose metadata
    AVFoundation reads (600 against 1,000 cd/m²): Apple's conversion was byte-identical again
    (one digest, `d34d90b3f676a425`). B96's conclusion stands, now on evidence that can see the
    field; H-1 writes that into GR-15's B96 text and `designs/adr/grading-3.md`'s Known limits.
  - **Amends** GR-15's T3-1 numbers (the PQ white), GR-16 (the media's colour record gains the
    peak, and its refusals), and GR-21 (the thumbnails follow the peak) — the amendment the
    owner chose, not a re-litigation.
- **HD-7 — View ▸ Show SDR Version: the preview only, as Show Ungraded is, plus `render_frame
  {sdr_version}`.** Choice 8 (taken as recommended, stated to the owner before the questions).
  - It shows HD-4's SDR version in the window's preview, with a tag in the canvas corner as Show
    Ungraded has (GR-4); it travels on the recipe key's options and is never an export.
    `render_frame {sdr_version: true}` draws the same picture.
  - **Why:** on an XDR display it is the only way to see the SDR deliverable before exporting
    it; on an SDR display the player's own tone mapping is Apple's, not the export's.
  - What it does in an SDR project, and its key, H-3 records here before its code.
- **HD-8 — The scopes of an HLG project read HLG, with a cd/m² scale.** Choice 9 (taken as
  recommended, stated to the owner before the questions).
  - The waveform and the parade read HLG signal % with a cd/m² scale (computed for the brief:
    HLG 0.50 = 50.7, 0.75 = 203.2, 1.00 = 1,000 cd/m²), a reference-white line at 75 % (203
    cd/m², where titles sit) and clip marks at 100 % (1,000 cd/m²).
  - The vectorscope uses BT.2020's matrix and its targets.
  - The scope JSON names its scale. Every SDR project's traces stay identical, and GR-10's
    bound (1.1 ms per scope per 4K frame) holds.
  - **Why:** Rec. 709's weights and targets misread BT.2020 values, and an HDR scale is what an
    HDR editor's user reads.
  - **Amends** GR-10 (its scales, weights and targets in an HLG project) and GR-31 (the
    zoom's targets and rim ticks are BT.2020's in an HLG project).
- **HD-9 — #276 is built last, as GR-18 wrote it; in an HLG project its decode is HLG's scene
  light.** Choice 11 (taken as recommended, stated to the owner before the questions).
  - `canvas.blending`, `"encoded"` or `"linear"`, written only when `linear`; `set_canvas
    {blending}`; off and byte-identical for every project; format 25 (HD-11).
  - "Linear" means the project's own transfer decoded: the sRGB EOTF in an SDR project, HLG's
    inverse OETF (scene light) in an HLG project. Its encode lives in H-3's output pass.
  - GR-18's text is unchanged and takes no Amended-by line: H-6 builds it as written, and the
    transfer it follows is HD-2's.
  - It is the first phase to drop if the road map is shortened.
- **HD-10 — #278: the new curves are Canon Log 2 and Canon Log 3, with Cinema Gamut.** Choice
  10 (owner, 2026-10-19: "Sony S-Log3, Panasonic V-Log, Canon C-Log2/3"). S-Log3 and V-Log
  exist since GR-16, so the new curves are Canon's.
  - Each is built under GR-16's recipe: Canon's published document read for its terms first
    (the owner downloads it, kept outside the repo), the curve's and gamut's constants, its code
    domain, a matrix derived from the primaries (never copied), and an L1-style fixture row and
    an LP3-style maths row. No maker LUT enters the repo.
  - New `log` values are **format 24** (HD-11): an older Frame Job cannot read them.
  - **Detection** of S-Log3 and V-Log from the maker's metadata waits for real files (one per
    camera, read and never copied into the repo): a parser built blind could convert a normal
    clip as log. So #278 stays open after H-5.
  - **Amends GR-16:** its `log` vocabulary and gamut pairs gain Canon Log 2 and Canon Log 3 with
    Cinema Gamut (their spellings are H-5's spec's).
- **HD-11 — The HDR road map's working arrangement: each phase merged into main alone, main's
  numbers, no verdict phase.** Choice 12 (taken as recommended, stated to the owner before the
  questions). GR-14, GR-17 and GR-25 again.
  - The worktree `~/devel/framejob-hdr` on branch `hdr`, outside the repo folder; each phase
    gated (`make gate`) and merged into main alone, the next started from main.
  - Format numbers are main's next when a phase's code is written: 22 for H-1, 23 for H-2, 24
    for H-5, 25 for H-6 at H-0, each renumbered before its merge if main moved first. HD IDs
    likewise.
  - No verdict phase: each phase is kept when its proofs pass.
  - Synthetic fixtures now; the owner's real HDR, HDR10 and log clips become
    `docs/manual-checks.md` rows, read from a path he gives and never copied into the repo.
  - Agents never edit a `CLAUDE.md`: each phase's record lists the edits it owes, and the
    orchestrator applies them.
- **HD-12 — #281's key and shape: `media.color.pq {file?, from?, peak?}`, read by two routes,
  overridden by `set_media_color {color: {peak}}`, published as the `input`'s `peak`.** H-1's
  spec, recorded before its code; it settles what HD-6 left to the spec. Format 22.
  - **The key.** `media.color` gains `pq`, after `detected`: `{file, from, peak}`, each written
    only when set, an empty reading written as `{}`. `file` is the peak import read, in whole
    cd/m²; `from` names which field gave it, `max_cll` or `mastering_display`, and is present
    exactly when `file` is; `peak` is the person's override. Import writes `pq` on every video
    media whose track is labelled PQ (`InputConversion.choose(for:)` answers `.pq`), `{}` when
    neither route reads a peak, and on no other media; so a media has `pq` exactly when it is a
    PQ file. The effective peak is `peak`, else `file`, else 1,000 cd/m².
  - **The routes, in order.** (1) The track's format description: the
    `MasteringDisplayColorVolume` extension (24 bytes, SMPTE ST 2086 in the order H.265's SEI
    137 carries it; the maximum luminance a big-endian u32 at bytes 16–19 in 0.0001 cd/m²) and
    the `ContentLightLevelInfo` extension (4 bytes, CTA-861.3; MaxCLL a big-endian u16 at bytes
    0–1). (2) When the description carries neither: the first video sample with data, read
    unconverted, for an `hvc1` or `hev1` track only: its length-prefixed NAL units (the length
    size 1, 2 or 4 from the description's `hvcC`; anything else reads nothing), the prefix SEI
    NAL units (type 39) before the first VCL unit (type below 32), emulation-prevention bytes
    removed, the `ff`-extended payload type and size, payloads 137 (24 bytes or more) and 144
    (4 or more), the first of each kept. Within the route that answered, MaxCLL when present
    and non-zero, else the mastering maximum. The two routes are never mixed. Measured for
    H-1's spec: an x265 CLI file muxed by ffmpeg carries both payloads in sample 0 and nothing
    in its description, and AVFoundation's first buffer of such a track is empty (no data), so
    the read skips to the first buffer with data.
  - **The arithmetic.** The mastering maximum rounds to the nearest cd/m² in 64 bits,
    `(v + 5000) / 10000`, so a corrupt `0xFFFFFFFF` cannot wrap; then a value above 10,000 is
    clamped to 10,000 and 0 reads as no peak. MaxCLL is read as it stands, 0 meaning absent
    (CTA-861.3), above 10,000 clamped. The reader is the core's pure `hdr10.rs`, bounds-checked
    so no input panics, reached through one export, `rc_hdr10_peak` (the road map's "no FFI
    export" is corrected: this is H-1's one).
  - **The op.** `set_media_color {media, color}` takes one new key, `peak`, a whole number of
    cd/m². `color` replaces the Camera Log (`log`, `gamut`, `lut`) AND the override together;
    import's `file` and `from` survive every op; `null` clears both, keeping `{pq: {file,
    from}}` (no `color` at all on a media without `pq`). Refused, each in its own sentence:
    `color.pq is read from the file at import, not set`; `media {id} is not a PQ file; only a
    PQ file takes a peak`; `color.peak must be 1–10000 cd/m², not {n}`; and an asked `color`
    with none of `log`, `lut` and `peak` (`{}`) keeps today's `color needs log or lut; null
    clears it`. A stored colour (`add_media`'s descriptor, a file) may hold `pq` with neither
    `log` nor `lut`; `pq` is on video only (today's kind sentence), `file` and `peak` within
    1–10,000, and `color.pq.from goes with color.pq.file`. Removing a LUT that converts a media,
    and a paste whose LUT does not come along, clear its Camera Log and keep its `pq`.
  - **What draws.** The recipe layer's and the plan segment's `input` gains `peak`, the
    effective peak, whenever the media has a reading or an override: `{peak}` alone, or beside
    `{log, gamut}` or `{lut}`; a `{}` reading publishes nothing new, so an unlabelled PQ file's
    plan and recipe are the text they were. Step 0's PQ arm takes W = max(peak, 203) / 203,
    1000/203 when `input` names no peak — the same float arithmetic as before, so a 1,000 cd/m²
    file renders byte-identical too.
  - **Thumbnails** (GR-21): a PQ media with an effective peak is drawn through the one-clip
    composition as a Camera Log is, its converted marker carrying `peak`; a PQ media with none
    keeps today's marker (`transfer: "pq"`), so its strip is not redrawn.
  - **The Media tab** shows an **HDR10** section (not the road map's popup): a Peak field in
    cd/m² (1–10,000, quick values 1,000, 2,000, 4,000 and 10,000), a Use File's button that
    clears the override, and a line naming where the peak came from; one undo step "PQ Peak".
    Every Camera Log write keeps the media's override.
  - **Not re-read.** A relink keeps the media's `color`, its reading included (GR-16's rule); a
    project from before format 22 has no `pq` on its PQ media and renders at 1,000 cd/m² until
    the file is imported again. No migration: the owner said on 2026-10-09 that Frame Job is in
    no real use yet.
  - **Amends** GR-15 (the white, and B96's route: its four files held HDR10 metadata only in the
    HEVC SEI, which AVFoundation does not read, M5), GR-16 (the colour record, the op's key and
    its refusals) and GR-21 (the marker's `peak`).
