# Spec §11 — decisions: HDR (road map "hdr")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/hdr.md`, and the
original, `archive/hdr.md`, holds each phase's record (H-0 the road map, these decisions and the
two pure moves; H-1 #281, the PQ peak; H-2 #277's HLG working space; H-3 #277's deliverables; H-4
#277's HDR scopes; H-5 #278's curves; H-6 #276, linear light; H-7 the close). HD-1…HD-11 were
recorded in H-0, before any HDR code, from the owner's answers of 2026-10-19 to the HDR brief's
twelve choices, every one the recommended answer: four were asked as questions and the other
eight were stated to the owner as taken (`archive/hdr.md`, "The owner's choices"; the brief is `~/.claude/litecode/framejob/hdr-brief/I-hdr.md` and the answers
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
ST 2086, CTA-861.3, ITU-T H.265's SEI syntax and each camera maker's own published log document
(Cinema Gamut's chromaticities: the ACES project's Canon CSC, HD-17); matrices are derived from
published primaries and D65; Apple's conversions are MEASURED as targets, never copied; every
fixture is written by a script. Nothing of Concat is opened, at design time or build time.

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
  **Amended by HD-16** (hdr H-6): H-6 runs before H-5. H-5 waits on Canon's own log document,
  which the owner has not yet supplied, and H-6 needs nothing H-5 adds; H-6 is still the first
  phase to drop.
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
  - **The knee:** H-3 fixes it against the brief's rows (copied into `archive/hdr.md`, "The SDR
    version, computed"), after reading BT.2408's own HDR → SDR constants, and records it here
    by an Amended-by line before its code. The brief computed those rows on the inverse of the
    BT.1886 route (`hdr_math.py` §1), not of HD-3's measured lift, so H-3 recomputes them on
    HD-3's before fixing the knee.
  - GR-15's mapping is not touched: it stays the conversion of HDR sources in SDR projects.
  **Amended by HD-14** (hdr H-3): the knee is 0.9 on the largest linear BT.709 channel over
  reference white, with GR-15's extended-Reinhard shoulder to W = 1000/203; recomputed on HD-3's
  lift, the white title reads 248.4/255 (not 249.6) and HLG 0.50 reads 125.7 (not 143.1, which
  was BT.1886's).
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
  **Amended by HD-14** (hdr H-3): the argument is spelled `dynamic_range`, not `range` (which the
  export tool already takes for `"project"` or `"in_out"`); the settings' `color` and presets'
  `"hdr"` carry it.
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
  **Amended by HD-14** (hdr H-3): its key is the recipe option `dynamic_range: "sdr"`; it writes no
  `UserDefaults` and has no shortcut; in an SDR project it changes no pixel and its tag still
  shows.
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
  **Amended by HD-15** (hdr H-4): the weights are not uniforms but a 0/1 `signal` choosing
  between two constant sets; the scopes read the SDR version while Show SDR Version is on and
  in `render_frame {sdr_version}` and an HLG project's JPEG frame; Show Ungraded keeps the HLG
  reading; the scale's labels, line, JSON and sentences as HD-15 lists them.
- **HD-9 — #276 is built last, as GR-18 wrote it; in an HLG project its decode is HLG's scene
  light.** Choice 11 (taken as recommended, stated to the owner before the questions).
  - `canvas.blending`, `"encoded"` or `"linear"`, written only when `linear`; `set_canvas
    {blending}`; off and byte-identical for every project; format 24 (HD-11; 25 at H-0,
    renumbered by HD-16 when H-6 ran before H-5).
  - "Linear" means the project's own transfer decoded: the sRGB EOTF in an SDR project, HLG's
    inverse OETF (scene light) in an HLG project. Its encode lives in H-3's output pass.
  - GR-18's text is unchanged and takes no Amended-by line: H-6 builds it as written, and the
    transfer it follows is HD-2's.
  - It is the first phase to drop if the road map is shortened.
  **Amended by HD-16** (hdr H-6): H-6 runs before H-5. H-5 waits on Canon's own log document,
  which the owner has not yet supplied, and H-6 needs nothing H-5 adds; H-6 is still the first
  phase to drop.
- **HD-10 — #278: the new curves are Canon Log 2 and Canon Log 3, with Cinema Gamut.** Choice
  10 (owner, 2026-10-19: "Sony S-Log3, Panasonic V-Log, Canon C-Log2/3"). S-Log3 and V-Log
  exist since GR-16, so the new curves are Canon's.
  - Each is built under GR-16's recipe: Canon's published document read for its terms first
    (the owner downloads it, kept outside the repo), the curve's and gamut's constants, its code
    domain, a matrix derived from the primaries (never copied), and an L1-style fixture row and
    an LP3-style maths row. No maker LUT enters the repo.
  - New `log` values are **format 25** (HD-11; 24 at H-0, renumbered by HD-16 when H-6 ran
    first): an older Frame Job cannot read them.
  - **Detection** of S-Log3 and V-Log from the maker's metadata waits for real files (one per
    camera, read and never copied into the repo): a parser built blind could convert a normal
    clip as log. So #278 stays open after H-5.
  - **Amends GR-16:** its `log` vocabulary and gamut pairs gain Canon Log 2 and Canon Log 3 with
    Cinema Gamut (their spellings are H-5's spec's).
  **Amended by HD-17** (hdr H-5): the sources are Canon's curve paper (*Canon Log Gamma Curves*,
  Canon U.S.A., November 1st, 2018) plus the ACES project's Canon CSC for Cinema Gamut's
  chromaticities, and each curve also pairs with BT.2020: Canon Log 2 and Canon Log 3, each with
  Cinema Gamut (the default) or BT.2020.
- **HD-11 — The HDR road map's working arrangement: each phase merged into main alone, main's
  numbers, no verdict phase.** Choice 12 (taken as recommended, stated to the owner before the
  questions). GR-14, GR-17 and GR-25 again.
  - The worktree `~/devel/framejob-hdr` on branch `hdr`, outside the repo folder; each phase
    gated (`make gate`) and merged into main alone, the next started from main.
  - Format numbers are main's next when a phase's code is written: 22 for H-1, 23 for H-2, 24
    for H-5, 25 for H-6 at H-0, each renumbered before its merge if main moved first. HD IDs
    likewise. H-6 ran before H-5 (HD-16), so it took 24 when its code was written, and H-5 takes
    25.
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
  **Amended by HD-18** (clean-up batch 2): a WebM/Matroska PQ copy's description carries its
  Colour element's MaxCLL, MaxFALL and MasteringMetadata as route 1's two blobs, and an `av01`
  track's stream route is its `av1C` config OBUs, then its first sample's, HDR_CLL and HDR_MDCV.
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
  - **(k) The words.** The Document tab's Colour row reads "SDR — Rec. 709" or "HDR — Rec. 2100
    HLG"; the Canvas section's Dynamic Range popup offers "SDR" and "HDR (HLG)"; the Look
    section warns "This project is HDR (HLG): a .cube LUT reads its values as Rec. 709."
  - **(l) Known limits, each filed as an issue:** a still image labelled HLG or PQ is drawn as SDR
    (fixing it needs `LayerRenderers.swift`, an output-keyed image cache, a not-lifted flag
    through `LayerSource` and PQ tone mapping for stills), #311; (h)'s HDR-source key across a
    switch, #312.
  **Amended by HD-14** (hdr H-3): (i)'s JPEG and (j)'s non-10-bit video rows now write HD-4's
  SDR version instead of being refused; the JPEG sentence stays only as `FrameWriter`'s guard.
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
- **HD-18 — Clean-up batch 2's settlements: the PQ peak read from a WebM/Matroska Colour
  element and from an AV1 stream's metadata OBUs, the scopes with both switches on, and ProRes
  4444 with alpha from an HLG project measured.** Recorded before the batch's code (#316, #315,
  #317); it settles what HD-12 left to other containers. No op, tool, argument, recipe, catalog
  or format change (format stays 25).
  - **(a) Matroska's HDR10 fields** (RFC 9559's Colour element): MaxCLL 0x55BC and MaxFALL
    0x55BD (unsigned integers, cd/m²) and MasteringMetadata 0x55D0, whose children are floats —
    PrimaryRChromaticityX/Y 0x55D1/0x55D2, G 0x55D3/0x55D4, B 0x55D5/0x55D6, the white point
    0x55D7/0x55D8, LuminanceMax 0x55D9 and LuminanceMin 0x55DA (cd/m²). The core reads them with
    the Colour element and `rc_container_describe` reports them (the video's `mdcv_hex`,
    `clli_hex`, and the Colour's `transfer`, `primaries` and `matrix` codes, each null when
    absent). The copy's format description carries them as HD-12's two blobs **only when the
    Colour's transfer is 16** (PQ), so an SDR or untagged copy gains nothing, and HD-12's route 1
    reads them unchanged:
    - `MasteringDisplayColorVolume`, 24 bytes, written when 0x55D0 is present: the primaries in
      ST 2086's and SEI 137's order G, B, R, then the white point, each x and y a big-endian u16
      of round(c·50000) clamped to 0…50000; then the maximum and minimum luminance, each a
      big-endian u32 of round(L·10000) clamped to the u32's range (NaN or negative → 0). An
      absent child is 0.
    - `ContentLightLevelInfo`, 4 bytes, written when MaxCLL or MaxFALL is present: MaxCLL then
      MaxFALL, each a big-endian u16 clamped to 65535, an absent one 0.
  - **(b) The PQ label.** A copy whose Colour's transfer is 16 is labelled PQ in its format
    description: `TransferFunction` SMPTE ST 2084, and `ColorPrimaries` and `YCbCrMatrix` from
    `CVColorPrimariesGetStringForIntegerCodePoint` and `CVYCbCrMatrixGetStringForIntegerCodePoint`
    when the Colour names them and Core Video maps the code. No other copy's description changes.
  - **(c) AV1.** The description's two extensions first (HD-12's route 1); else the stream (AV1
    §5.3, §5.8; AV1-ISOBMFF §2.3): the `av1C`'s configOBUs (bytes 4 on, when byte 0 is 0x81, the
    marker and version 1; else none), then the first sample with data. Every OBU is walked: the
    type is the header's bits 6–3, an extension byte is skipped, `obu_size` is a leb128 of at
    most 8 bytes when `obu_has_size_field` is set, else the OBU is the rest of the bytes. An
    OBU_METADATA (type 5) is read by its leb128 `metadata_type`: 1 HDR_CLL (`max_cll` a
    big-endian u16, 4 bytes or more) and 2 HDR_MDCV (`luminance_max` a big-endian u32 at payload
    bytes 16–19 in 24.8 fixed point, 24 bytes or more), the first of each kept, the config's
    before the sample's. The maximum is whole cd/m² as (v + 128) / 256 in 64 bits, clamped to
    10,000, 0 no reading; MaxCLL as it stands, 0 absent, clamped to 10,000. MaxCLL first, else
    the mastering maximum, as HD-12. The core's pure `hdr10.rs` reads it through one export,
    `rc_hdr10_av1_peak`; the import probe calls it for an `av01` track.
  - **(d) The scopes, #315.** With Show Ungraded and Show SDR Version both on, the scopes read
    the ungraded SDR version (HD-15 (c)): no new branch, since the recipe's `ungraded` and
    `dynamic_range` are independent and `ScopeSignal` reads the second. A scope slot takes its
    caption and signal only from a trace of its own kind; another kind's trace is "no frame
    yet".
  - **(e) ProRes 4444 with alpha, #317,** is measured by a row before any fix (`hdr_proof.py`
    DA): an HLG project with a transparent background, a translucent shape and its opaque twin,
    exported `prores_4444` at its default, `hlg`, `sdr` and `pq`. Rules, fixed before the row
    runs: at the shape's centre, alpha within ±1/255 and the straight colour within ±2/1023;
    `hlg` and the default against `render_frame`, `sdr` against `render_frame {sdr_version:
    true}`, `pq`'s alpha against `render_frame`'s and its colour against the opaque twin's `pq`
    export. A failure is filed with its figures and fixed in a later phase.
  - **(f) Amends** HD-12 (its routes: a Matroska Colour's fields carried into the copy's
    description, and AV1's metadata OBUs as the stream route for an `av01` track).
