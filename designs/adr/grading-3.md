# Grading tier 3: honest sources, HDR→SDR at step 0, camera log (road map "grading-3")

- **Status:** Built and closed 2026-10-12. Each phase was one litecode pipeline with its own review, worked in `~/devel/reelcut-grading3` on branch `grading-3` and merged into main alone after its gate (GR-17):
  - T3-0, the road map, GR-15…GR-20 and `DestinationPass`'s pure move (`716720c`)
  - T3-1, honest sources and Frame Job's HDR→SDR at step 0 (GR-15) (`e76d827`)
  - T3-2, camera log footage (#264, GR-16, format 19) (`c47d97d`)
  - T3-3, the close: H1a, H7 and TI's export wall time, this record (the commit that moved this record to `archive/`)
- **Original:** `archive/grading-3.md` is the full record. It has no section numbers, so it is cited by phase: "orig T3-1" is its "T3-1 — honest sources and Reelcut's HDR→SDR at step 0" section.
- **Spec decisions:** GR-15..GR-20 in spec §11 (`designs/spec/11-decisions/grading-3.md`). They stay binding, and where the original words them differently, §11's text wins:
  - GR-15: honest sources: `ConvertingCompositor` (`canConformColorOfSourceFrames` and `supportsHDRSourceFrames` true) and BT.709 composition colour only for a composition holding an HLG, PQ or wide-gamut source; a per-source step 0 chosen by the buffer's TRANSFER label (HLG, PQ, wide-gamut SDR, the sRGB arm); the HLG inverse OETF with system gamma 0.96 and gain 1.07, PQ over reference white 203 cd/m², the derived matrix to BT.709, the gamut lift, the shoulder (knee 0.39), the encode L^(1/2.4); H3's bound, 3/255 of Apple's measured points; every other composition built exactly as before.
  - GR-16: camera log on the media, `media.color {log, gamut, lut, detected}`, `set_media_color` (the 61st op, the 91st product tool), Apple Log and Apple Log 2 detected from their labels, S-Log3 and V-Log by hand, Use LUT…; converted at step 0 before the chroma key; Show Ungraded keeps it; the makers' curves, each document's terms and code domain; Frame Job's display transform with mid-grey 0.42; the look warning; format 19.
  - GR-17: each phase merged into main alone, main's format numbers, no verdict phase, synthetic fixtures now.
  - GR-18: linear-light blending deferred; when built, an opt-in project switch, off for every project, with its design notes (#276).
  - GR-19: the HDR timeline deferred with its design: `canvas.output`, BT.2408's SDR→HLG, the measured HDR export (#277).
  - GR-20: a wide-gamut working space for SDR projects closed as not wanted.
  - Amended: PR-2 by GR-15 ("HDR stays tone-mapped" was true of one path; HDR still reaches the output as SDR, converted by Frame Job's own step 0); GR-8 by GR-15 (T0's "HLG and PQ … UNCHANGED" was true of the generator and a decoder's first frame) and by GR-16 (its accepted risk shrinks: log is converted at step 0, a LUT can be the input conversion, the Look section warns); `designs/adr/grading-2.md`'s line "an input LUT would be its own step before 4c" by GR-16 (it is step 0, before step 3).

## Context

GR-1 deferred tier 3 "as issues, not out"; tier 1's close filed #256 (HDR above 1.0, an EDR preview, HDR export, wide gamut, linear light) and #264 (camera log). The tier-3 brief (2026-10-11, outside the repo) measured why PR-2 ("HDR stays tone-mapped") and GR-8 ("HLG and PQ draw UNCHANGED") disagreed: each was true of a different path. The export reader's later frames and the player arrived converted (grey 0.5 → HLG 0.3843, PQ 0.7192), but a decoder's first frame of each HLG or PQ clip and every `AVAssetImageGenerator` frame (`render_frame`, Save Frame…, GIF, APNG, the Look gallery, the eyedropper, Pick from Canvas) arrived unconverted and labelled BT.709. That is a parity defect on ordinary iPhone footage. A BT.2020/BT.709-transfer file was darkened everywhere (0.5 → 0.2568), and AVFoundation's conversion clipped colour. On 2026-10-11 the owner answered "HDR fix + log" for choice 1, "All as recommended" for choices 2–6 and 10, and "Synthetic now" for the footage. (orig "The owner's choices", "How it fits the tree")

## Decisions

- **A step-0 pass, not arithmetic inside the sample.** In the brief's scratch shader, a conversion inside a 25-tap blur cost +3.06 ms at 4K (once per tap), against +0.001–0.009 ms once per pixel. The pass costs about one copy (0.21 ms at 4K) and one pooled `rgba16Float` target per converted source (66.4 MB at 4K). It has its own uniform block and binds an input LUT itself, so `LayerUniforms` stays 128 floats and no layer-stage texture slot is taken. It must precede step 3, because the chroma key and Color's four must see converted values. (orig "The stage order: step 0")
- **Chosen by the transfer label, not the primaries.** Apple Log carries BT.2020 primaries, so a selector on primaries would matrix and shoulder log values. The `select-by-primaries` mutant fails H1 and P1. (orig "The HDR conversion")
- **The H1 stop and the per-composition switch.** T3-1's first code set BT.709 colour on every composition. Every SDR pixel was identical, but 7 of H1's 12 single-source scenes came out labelled `kCGColorSpaceCoreMedia709` and their picks moved (untagged grey 0.251 → 0.286). The owner chose "Redesign, keep SDR exact" (2026-10-12). The designer measured M1–M8: the render context's labels are per composition, and `canConformColorOfSourceFrames` changes SDR-only mixes. So `Compositor` keeps today's answers and no colour. `ConvertingCompositor` and BT.709 are used only when `CompositionBuilder.convertsSources` (or a media's setting, `plan.convertsMedia`) finds a source that starts a conversion. (orig T3-1 "The H1 stop and its redesign"; GR-15 as amended)
- **The sRGB arm** (owner, "Convert it now"): an sRGB-transfer source takes the IEC 61966-2-1 EOTF, the matrix, and the inverse of Core Media's 709 gamma (256/502), with no lift or shoulder. With BT.709 primaries it converts only inside a converting composition and never makes one, so it renders there as it does alone. With P3 D65 or BT.2020 primaries it is wide gamut and renders as Apple reads its labels (M7, M8). (GR-15 as amended)
- **The shoulder is anchored on Apple's measured points** (choice 2a): HLG system gamma 0.96 and gain 1.07, not BT.2100's nominal 1.2, because with γ 1.2 the best single gain leaves a point 9.1 levels off. H3's bound (3/255) was written before measuring, and the distances computed beforehand were +0.93 / −0.84 / +0.17 / 0.00 (HLG) and −0.79 / −0.28 (PQ). Colours outside Rec. 709 are lifted toward their luminance and rolled off, not clipped. (GR-15's T3-1 numbers)
- **Log is a setting on the media** (choice 3a): one per file, followed by every clip and its reverse. A media's setting supersedes GR-15's choice from labels. Apple Log and Apple Log 2 are detected at import (`detected: true`), and None is the override that shows the log picture. (GR-16)
- **Apple Log's code domain differs from Sony's and Panasonic's.** Apple's P is the normalized signal (P = s in the video-range file AVFoundation decodes). S-Log3 and V-Log read the stored code, CV = 64 + 876·s. This is the one correction to T3-2's spec, and step 0 reads it as `codeScale`/`codeOffset`. (orig T3-2 "Deviations"; GR-16's append)
- **Mid-grey 0.42** (owner, "42%, as planned"): exposure 0.42^2.4/0.18 and white 64·0.42^2.4, six stops over 18 % grey. 90 % reflectance lands near 200/255. (GR-16's append)
- **Apple Log 2 is built** (the owner's leftover rule): the paper gives Apple Wide Gamut and the SDK names the label. It shares Apple Log's curve and is detected the same way. (orig T3-2)
- **Use LUT… samples at texel centres**, as `gradeLook` does, and its output is taken as encoded Rec. 709, with no exposure, matrix or shoulder. The `lut-no-half-texel` mutant fails LP3 and L5. (GR-16's append)
- **Show Ungraded keeps step 0**: it is the file's interpretation, not a grade (choice 6). (GR-16)
- **The log oracle rounds the decoded signal to half** before the formula, because step 0 reads an `rgba16Float` source and at S-Log3's black code 95 the rounding alone is 0.84 of a level. (orig T3-2 "Deviations")
- **L1 was widened after two mutants survived.** Every-8th-column sampling missed S-Log3's break, and a grey row cannot see a gamut matrix. L1 now reads every column of the first 32 and a green card, and `slog3-breakpoint` and `cine-as-709` then failed it. (orig T3-2)
- **No maker LUT is bundled**: their redistribution terms were not found, and Apple's sits behind the developer login. The three documents' terms are recorded in GR-16 (Apple's copyright notice; none stated by Sony or Panasonic), and no maker's file, table or LUT is in the repo. (GR-16's append)
- **The Concat rule held**: none of Concat's code, shaders, chains or colour tables was opened. The sources are ITU-R BT.2100, BT.2408, BT.2020, BT.709, SMPTE ST 2084, IEC 61966-2-1 and each maker's own document, with the matrices derived from published chromaticities and D65. (orig "The Concat rule")

## What it built — where it lives now

- Core (T3-2): `model_media_color.rs` (`LogCurve`, `CameraGamut`, `MediaColor`), `media_color.rs` (`set_media_color`, `check_media_color`, `media_input`, `media_converted_by`), `Media.color`; the 61st op in `edit.rs` and `op_table.rs`; `MEDIA_KEYS` 12; relink, `remove_lut`, paste and `validate` rules; the recipe layer's `input` (26 keys, kept by `ungraded`) and a plan video segment's `input` only when its media converts; `RC_FORMAT_VERSION` 19. Tests: `media_color.rs`, `schema_v19.rs`. T3-1 had no core change.
- Metal: `Compositor.metal`'s `framejob_input_fragment` (step 0, the ninth pipeline): HLG, PQ, wide-gamut SDR, sRGB, the three inverse log curves and the LUT arm, with the standards' and makers' constants only.
- Swift: `InputConversions.swift` (the selector through two readers, `startsConversion`, every number Frame Job chose, `toBT709` derived, the camera gamuts, the code domains); `Compositor+Input.swift` (`ConvertingCompositor`, `InputUniforms`, `InputStage`, `encodeInputs`); `Compositor+Sources.swift` (T3-1's pure move); `CompositionBuilder.convertsSources`; `MediaColor.swift`, `MediaImporter+Color.swift`, `MediaPane+CameraLog.swift`, `EditorViewController+CameraLog.swift`, the Look section's `lutOverCameraLog`; `AgentServer`'s `set_media_color` handler and catalog entry.
- Proofs: `hdr_proof.py` (H1, H1m, H1a, H1s, H1w, H2–H7, R0, TI, P1–P4, Z1, twelve mutants) with `hdr_probe.swift`, `hdr_pick_probe.swift` and `applelog_writer.swift`; `log_proof.py` (LP1–LP4, L1–L9, Z1, ten mutants) with `log_probe.swift`; screen `10b-media-tab`.
- Person checks: GRD-16 (iPhone HDR footage, the preview's first frame and playback at length), GRD-17 (Apple Log), GRD-18 (Sony or Panasonic log) in `docs/manual-checks.md`.
- Pure moves: `DestinationPass` out of `Compositor.swift` (T3-0, 723 → 658); `MetalRenderer`'s `// MARK: - Sources` to `Compositor+Sources.swift` (T3-1, 658 → 572). `designs/adr/app-file-history.md` names the next seams.

**Headline numbers** (Apple M2 Max, macOS 26.5.1, `powermode 0`; AC power for T3-0–T3-2; at T3-3 AC for the Debug run and the first Release run, battery from the `--measure` run on, and AC for the H7 re-run, as their host lines say).

| Measure | Bound | Measured | Command |
|---|---|---|---|
| SDR identity (T3-1) | byte-identical, picks equal | 12 single-source scenes byte-identical, picks equal; H1m's two mixed projects equal to 716720c's | `RC_PROOF_APP=release hdr_proof.py compare tools/proof/work/t3-1/ctl` H1, H1m |
| Alpha and WebM in a converting composition (T3-3) | byte-identical to 716720c at the non-HLG ticks; CONTROL: the HLG tick differs | ProRes 4444 alpha, HEVC alpha and VP9 WebM frames byte-identical with equal picks; the HLG tick differs (143,449 16-bit samples, grey pick 0.424 against 0.545) | `RC_PROOF_APP=release hdr_proof.py --only H1a,H7,Z1` H1a |
| The first-frame flash (T3-1) | frame 0 = frame +5 ±1; render = export ±1 | frame 0 = frame +5 exactly on all four scenes; render vs export ≤ 1 | `… compare …` H2 |
| The conversion against its formula and Apple (T3-1) | ±1 at 8 bits; Apple's points within 3/255 | worst 1 level; HLG +0.96 / −0.86 / +0.12 / 0.00, PQ −0.81 / −0.37 | `… compare …` H3 |
| A saturated HLG patch (T3-1) | hue within 2°, inside the envelope | 383 columns, worst hue gap 0.21°; patch [0, 144, 255] against the oracle's [0, 143, 255] (control [107, 215, 255]) | `… compare …` H4 |
| The eyedropper on HLG (T3-1) | its export's pick ±3; keyed magenta ±8 | [144, 0, 19] against [143, 0, 20]; keyed (255, 0, 255); base tree [158, 46, 0] | `… compare …` H6 |
| HDR10 static metadata naming a 4,000 cd/m² peak, not the conversion's 1,000 (T3-3) | CONTROL: ffprobe names both and the peak on `pq_hdr10`, none on `pq_plain`; grey row = oracle ±1; renders equal | both and `max_luminance=40000000/10000`, `max_content=4000` named, and none; worst 1 level on each, x=512 183 = 183; the two PNGs byte-identical | `RC_PROOF_APP=release hdr_proof.py --only H7,Z1` H7 |
| Step 0 at 4K (T3-1) | recorded | HLG twin averages 2.02 / 1.76 ms (120 input passes each), BT.709 1.55 / 1.32 ms, mean difference 0.455 ms; loadavg 17.39 / 29.86 / 23.86 | `RC_PROOF_APP=release hdr_proof.py --measure` TI |
| Step 0 at 4K, and the export's wall time (T3-3) | recorded | HLG 2.12 / 1.74 ms (120 passes each), wall 0.96 s; BT.709 1.62 / 1.29 ms (0 passes), wall 0.95 s; battery, powermode 0, loadavg 21.41 / 24.27 / 17.23 before | `RC_PROOF_APP=release hdr_proof.py --measure` TI |
| An unconverted layer (T3-1) | +0.028 / +0.061 ms (1080p / 4K) | −0.007 / −0.001 ms; TA 0.001 / 0.000 | `grading_spike.py --measure --tree --tree-base 716720c` TC |
| Each log curve on its ramp (T3-2) | within a level | worst 1 level on every grey fixture, 0 on both cards; patches [1/2/3, 107, 200] = the oracle | `RC_PROOF_APP=release log_proof.py compare tools/proof/work/t3-2/ctl` L1 |
| Use LUT… against ffmpeg's `lut3d` (T3-2) | ±2 | worst 1 (S-Log3), 0 (both cards) | `… compare …` L5 |
| The log maths in the probe (T3-2) | 2·10⁻³ | worst 9.1·10⁻⁴; the makers' codes within ±0.005 of reflectance | `… compare …` LP3 |
| The argument gate (T3-2) | every row | 159/159, 91 product tools | `op_argument_proof.py` |

Mutants, each run once on the final instrument and all caught: T3-1's twelve (`hdr_proof.py --mutant`; past ten because each guards a separate decision) and T3-2's ten (`log_proof.py --mutant`; `slog3-breakpoint` and `cine-as-709` run again after L1 was widened). The gates passed in 280 s (T3-0), 240 s (T3-1) and 227 s (T3-2).

## Known limits

- **Synthetic fixtures only.** Real iPhone HDR, Apple Log and Sony or Panasonic files are GRD-16…GRD-18. Whether a real Apple Log file carries the label and video-range codes is GRD-17's.
- **The player's first frame and the player at length** are REASONED fixed, because they go through the same conversion. The reader and the generator are measured; the preview is GRD-16's.
- **A source whose format description lacks its frames' labels** stays on AVFoundation's path, since the class is chosen from the descriptions (GR-15; #279).
- **The PQ shoulder ignores HDR10 static metadata** (H7, measured with metadata naming 4,000 cd/m² against the conversion's 1,000; #281). Issue batch B96 added a 600 cd/m² display with MaxCLL 600 and the 4,000 cd/m² display with MaxCLL 1,000: all four PQ ramps render byte-identical, each grey row within 1 level of the oracle, and Apple's own reading of each file (`AVAssetImageGenerator`, no composition) is identical too, worst |Δ| 0 at the grey row's every 64th column (`hdr_proof.py --only H7,Z1`, Debug and Release, 2/2 each). Whether the white should follow the metadata is put to the owner (issue batch B96). **Corrected in the HDR road map's H-1:** B96's files held their HDR10 metadata only in the HEVC stream's SEI (x265 through ffmpeg), which AVFoundation does not read (the HDR brief's M5), so Apple's reading could not have followed it; on two Apple-written files whose sample description carries 600 and 1,000 cd/m², Apple's conversion was byte-identical again (digest `d34d90b3f676a425`, M5), so the conclusion stands. H-1 makes the shoulder follow the file's peak (spec §11 HD-6, HD-12; `designs/hdr.md`).
- **Thumbnails** on the timeline and in the Media tab showed the log picture (#282): closed by GR-21, which draws a converting media's thumbnails — Camera Log, HLG and PQ — through step 0. **A full-range-flagged log file** was read as video range (#283): closed by GR-22 (issue batch B95), which takes S-Log3's and V-Log's code domain from the media's range flag; log_proof's L10–L12 measure it.
- **The 10-bit reverse shifts a log toe**: code 95 → 98 (S-Log3) and 196 → 199 (Apple Log), seven levels after the curve. L6's bound absorbs it (#280).
  Issue batch B96 measured the intermediate's variants (`log_proof.py reverse-variants`: a probe over a tree copy, no app; worst |Y₁₅ − expected| on `slog3` / `applelog` / `slog3_fr` over 131 points and the toe's columns 0–31; MB per minute and ratio to today's on 2 s grain-detail ProRes 422 HQ fixtures). Fixed before the run: a variant holds at ≤ 1 on all three, and qualifies when it also costs ≤ 2.0× today's. None qualified, so the choice is put to the owner (issue batch B96):

  | Variant | Worst toe | Holds | MB/min 1080p30 | MB/min 2160p30 | Ratio 1080 / 2160 |
  |---|---|---|---|---|---|
  | today's (HEVC Main 10, `x420`) | 3, 3, 3 | no | 54 | 213 | 1.00 / 1.00 |
  | HEVC Main 10 fed `x422` | 2, 3, 90 | no | 54 | 216 | 0.99 / 1.01 |
  | HEVC Main 4:2:2 10 | 2, 3, 90 | no | 54 | 215 | 0.99 / 1.01 |
  | rate ×2 | 1, 1, 3 | no | 108 | 429 | 1.99 / 2.01 |
  | rate ×4 | 1, 1, 2 | no | 215 | 867 | 3.98 / 4.06 |
  | rate ×8 | 1, 1, 2 | no | 437 | 1742 | 8.08 / 8.16 |
  | quality 1.0 | 1, 1, 2 | no | 3399 | 13633 | 62.86 / 63.86 |
  | ProRes 422 | 1, 1, 90 | no | 1113 | 4343 | 20.58 / 20.35 |
  | ProRes 422 HQ | 0, 0, 90 | no | 1722 | 6843 | 31.85 / 32.06 |

  The cause is the rate, not the `x420` feed: more bits close the video-range toe, and 4:2:2 alone does not. Every `x422` read of the full-range `slog3_fr` (4:2:0 HEVC) lands up to 90 codes off (column 0: 95 → 159 or 161 against 145), and no lossy HEVC variant gets that file within 1 (best 2). Issue batch B98 measured the same shift on the product path (#289, `log_proof.py` L13, no Camera Log): today's odd-size reverse reads video-range `x422`, and a full-range 1024×129 file reversed with toe worst 90 (95 → 159) and a render 27–28 levels off its forward twin, on HEVC 4:2:2 and VP9 alike, while each video-range twin held at 1 code and 1 level. Spec §11 PR-10 reads full-range `x422` for an odd size flagged full range: the HEVC 4:2:2 file then holds (95 → 146, 1 level). A VP9 MP4 carries no `FullRangeVideo` extension, so GR-22's flag read it as video range and its reverse still shifted (toe 90, spread 28). Closed by spec §11 GR-23 (issue batch B99, #291): the flag falls back to the track's `vpcC` range bit, and the VP9 pair then holds (toe 1, 95 → 146, spread 2); step 0's log domain follows (`log_proof.py` L14: the full-range VP9 MP4's and WebM's 0 % patch 28 → 0 levels, worst 2 against the oracle, which the VP9 decode alone accounts for), and so do GR-21's strips (`log_thumbs_proof.py` T9). The HEVC branch (this bullet's choice) is unchanged.
- **A colour tag in the ProRes header and not the `colr` atom** decodes with BT.709 coefficients ([59, 154, 76] against [61, 156, 74]). The first `green.mov`'s [50, 165, 73] (BT.601-like) is explained by B95's measurement: `prores_ks` given `-colorspace bt2020nc` on the encode itself converts the card's codes at encode (462/466/470 → 473/463/465), and [50, 165, 73] is the BT.2020nc oracle at those stored codes, so it was ffmpeg's conversion of the fixture, not a BT.601 decode by Frame Job. Its BT.2020nc decode means that file carried a `colr` atom (inferred; it was not kept). That file, re-made, has no `colr` atom and renders [47, 162, 75], the BT.709-coefficient oracle at its own codes; the header-only tagging still renders [59, 154, 76]. Whether to read a ProRes header's tags is put to the owner (#279).
- **The display transform's mid-grey** is Frame Job's look choice, not a maker's. A camera LUT applied as a look over Camera Log converts twice and is only warned.
- **Timings** come from one M2 Max on a loaded host and are recorded, not budgets.

## Open items

Filed at the close, each `ai-drafted` and `low-priority`:
- #276: linear-light blending as an opt-in project switch (GR-18).
- #277: the HDR timeline: HLG output, EDR preview, HDR export (GR-19).
- #278: camera log: more curves, and S-Log3/V-Log detected from the maker's metadata.
- #279: a colour tag in the ProRes header but not the `colr` atom, and sources whose description lacks their frames' labels.
- #280: the 10-bit reverse's toe shift on log footage.
- #281: PQ's shoulder ignores HDR10 static metadata — built by the HDR road map's H-1 (spec §11 HD-12).
- #282: thumbnails show the log picture of a converting media — closed by GR-21 (thumbnails through step 0, HLG and PQ included).
- #283: a full-range-flagged log file is read as video range — closed by GR-22 (issue batch B95).
- #291: a VP9 track's range flag is not read — closed by GR-23 (issue batch B99).
- #293: an AV1 track's range — measured in issue batch B101: AV1 in profiles 0 and 1 carries `FullRangeVideo`, read by AVFoundation from its `av1C`, but profile 2 gets no key, so a full-range profile 2 AV1 reads as video range; no code; the owner accepted it as a known limit (2026-10-14), closed (GR-23's "Measured (issue batch B101, #293)"; `log_proof.py` L15 stays as a guard).
- #294: the VP9 gap L14 allows — measured in issue batch B101 (`log_proof.py decode-gap`): verdict **neither**, since VP9's reader codes and `64RGBAHalf` frames equal HEVC's, so the cause lies between the reader and the compositor's source frames; left open for the owner with the figures (GR-23's "Measured (issue batch B101, #294)"); issue batch B102 placed it in the generator's 8-bit image of a VP9 file, and it is closed by PR-12 (issue batch B103): a frame showing a deep VP9 track is read through export's reader.

Closed: #264 as built (T3-2, `c47d97d`, GR-16); its "done when" on a real clip is GRD-17 and GRD-18. #256 is closed into GR-15 (HDR sources converted honestly, T3-1), GR-20 (wide gamut for SDR projects, closed by the owner, choice 9a), #276 (linear light) and #277 (HDR, EDR and HDR export).

## Where to look in the original

- "The owner's choices" and "Tier 3 as answered": the owner's answers verbatim, the ten choices and what #256 and #264 asked.
- "How it fits the tree": the brief's path table (what each path received for each source), `canConformColorOfSourceFrames`, log today, the stage order with step 0, and the HDR and log conversions as planned.
- "The standard recipe, file by file, and the tolls": the tolls and the per-file plan.
- "Costs": the brief's spike tables (`gpu.swift`'s pass costs, the fixtures' commands) and what was reasoned from them.
- "What tier 3 defers": GR-18's linear-light table and design, GR-19's HDR timeline, GR-20.
- "Test media, and what to ask the owner for"; "Not established".
- T3-0: the toll and its verification. T3-1: the H1 stop and its redesign, the measured rows, the twelve mutants. T3-2: the sources, the deviations (Apple Log's code domain, the oracle's half rounding, L6, L1's widening, green.mov), the measured rows, the ten mutants.
- T3-3: H1a, H7, TI's wall time, the issues and the close comments.
