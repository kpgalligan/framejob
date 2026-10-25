# HDR: the PQ peak, the HLG timeline, its deliverables and scopes, linear light, Canon Log (road map "hdr")

- **Status:** Built and closed 2026-10-20. Each phase was one litecode pipeline with its own review, worked in `~/devel/framejob-hdr` on branch `hdr` and merged into main alone after its gate (HD-11). H-6 ran before H-5 (HD-16 (j)), so H-6 took format 24 and H-5 format 25:
  - H-0, the road map, HD-1…HD-11 and two pure moves (`ExportSheetCommit.swift`, `MediaImporter+Thumbnails.swift`) (`dcd08f3`)
  - H-1, #281: an HDR10 file's PQ white placed at its own peak (HD-6, HD-12, format 22) (`d93ece2`, the toll; `ec08cb9`)
  - H-2, #277 part 1: the HLG working space (HD-2, HD-3, HD-13, format 23) (`7aef1e8`)
  - H-3, #277 part 2: the deliverables — HLG, HDR10 and the SDR version (HD-4, HD-5, HD-7, HD-14) (`2540545`, the toll; `b2c247c`)
  - H-4, #277 part 3: HDR scopes (HD-8, HD-15) (`fe551cc`)
  - H-6, #276: linear-light blending as an opt-in project switch (GR-18, HD-9, HD-16, format 24) (`f35e56d`)
  - H-5, #278: Canon Log 2 and Canon Log 3, with Cinema Gamut or BT.2020 (HD-10, HD-17, format 25) (`13ccb1f`, Canon's paper ignored by git; `105ac08`)
  - H-7, the close: this record (the commit that moved this record to `archive/`)
- **Original:** `archive/hdr.md` is the full record. It has no section numbers, so it is cited by its own headings: "orig H-2" is its "H-2 — #277, the HLG working space (HD-2, HD-3, HD-13)" section.
- **Spec decisions:** HD-1..HD-17 in spec §11 (`designs/spec/11-decisions/hdr.md`). They stay binding, and where the original words them differently, §11's text wins:
  - HD-1: the road map builds everything (owner, 2026-10-19, choice 1a): #281, #277 in three phases (the working space, the deliverables, the scopes), #278's curves, #276 last and the first to drop, then the close; #274 only if a real clip is at hand.
  - HD-2: an HLG project: `canvas.output` `sdr`/`hlg`, BT.2020 HLG-encoded values with PR-1's clamps and encoded blending, every composition converting in BT.2020/HLG, step 0's HLG arms, drawn layers lifted at upload, BT.2020 luma and HLG's transfer in the grade, frames 16-bit labelled BT.2100 HLG, every SDR project byte-identical; format 23.
  - HD-3: SDR white fixed at 203 cd/m² (HLG 0.75), no setting; one lift for every SDR source and drawn layer, Core Graphics' `kCGColorSpaceCoreMedia709` → `itur_2100_HLG` (SDR 0.50 → 0.5059, 1.00 → 0.7500).
  - HD-4: the SDR version is the inverse of the lift with a shoulder above reference white (choice 3a).
  - HD-5: the deliverables: HLG on the 10-bit rows by default, HLG · HDR10 · SDR chosen per export, the SDR version on every other row and JPEG, Dolby Vision off, HDR10 metadata fixed (P3-D65, 0.005–1,000 cd/m², MaxCLL 1,000, MaxFALL 0).
  - HD-6: #281: the PQ peak read at import (the format description, else the first sample's SEI 137/144), MaxCLL over the mastering maximum, an override, PQ white = peak/203, unknown 1,000; thumbnails follow; B96's evidence corrected; format 22.
  - HD-7: View ▸ Show SDR Version, the preview only, with a corner tag; `render_frame {sdr_version}`.
  - HD-8: HDR scopes in an HLG project: HLG % with a cd/m² scale, a 75 % reference line, clip marks at 100 %, the BT.2020 vectorscope; the JSON names its scale.
  - HD-9: #276 built last as GR-18 wrote it (`canvas.blending`); in an HLG project its decode is HLG's scene light.
  - HD-10: #278: Canon Log 2 and Canon Log 3 with Cinema Gamut under GR-16's recipe; S-Log3/V-Log detection waits for real files.
  - HD-11: the working arrangement: the `hdr` worktree, each phase gated and merged alone, main's next format numbers and HD IDs, no verdict phase, synthetic fixtures with real clips as manual checks, agents listing the `CLAUDE.md` edits owed.
  - HD-12: #281's key `media.color.pq {file?, from?, peak?}`, `set_media_color {color: {peak}}` and its three refusals, the `input`'s and the marker's `peak`, the Media tab's HDR10 section, `rc_hdr10_peak`, no re-read on relink or for a pre-22 file.
  - HD-13: H-2's settlements: the lift with Core Graphics' toe, the SDR, PQ (BT.2390's EETF above 1,000 cd/m²), HLG and camera-log arms, layers lifted at upload, the grade's BT.2020 constants, the key and a luma matte through the inverse lift, frames, the 10-bit rows tagged HLG, the words, two limits filed.
  - HD-14: H-3's settlements: the knee at 0.9, one output pass chosen by the key's `dynamic_range`, `export {dynamic_range}` and its refusals, PQ at 1,000 cd/m² with HD-5's two blobs, frames and JPEG the SDR version, Show SDR Version's key, the sheet's Dynamic Range row.
  - HD-15: H-4's settlements: the scopes read the picture shown, the signal from the recipe canvas, a 0/1 `signal` uniform, the 0/10/51/203/1000 cd/m² labels and the dashed 75 % line, BT.2111's bars and the lifted skin line, the HLG JSON and captions.
  - HD-16: H-6's settlements: `canvas.blending` `encoded`/`linear`, linear as the project's own transfer as scene light, the decode once per layer after the effects block, what stays read encoded, the output pass drawn for every linear project, the Blending popup, H-6 before H-5.
  - HD-17: H-5's settlements: Canon Log 2 and 3 from Canon's *Canon Log Gamma Curves* white paper, Cinema Gamut from the ACES project's Canon CSC (owner, 2026-10-20), each curve with Cinema Gamut or BT.2020, reflection 0.9 × scene linear, the code domain (1, 0) in both ranges, step 0's kinds 10 and 11, format 25.
  - Amended: GR-2, GR-13, GR-15, GR-19, GR-32, GR-33, PR-4, PR-11 (by HD-2); GR-19 (by HD-3, HD-5); GR-15, GR-16, GR-21 (by HD-6, HD-12); GR-10, GR-31 (by HD-8, HD-15); GR-16 (by HD-10, HD-17); and among the HD entries HD-1, HD-4, HD-5, HD-7, HD-8, HD-9, HD-10, HD-13 and HD-14 by later ones (HD-14, HD-15, HD-16, HD-17).

## Context

Grading tier 3 converted HDR footage to Rec. 709 at step 0 and deferred the rest: GR-18 linear light (#276), GR-19 the HDR timeline (#277), and two items filed at its close, #278 (more log curves and their detection) and #281 (PQ's shoulder fixed at 1,000 cd/m² whatever the file says). On 2026-10-19 the owner said "Push. For 299, go with your recommendation. Then start HDR." and answered the HDR brief (`~/.claude/litecode/framejob/hdr-brief/I-hdr.md`, outside the repo) with every choice as recommended: "Everything (Recommended)" for the scope, "Inverse of the lift (Recommended)" for the SDR version, "HLG + HDR10, DV off (Recommended)" for the deliverables, and Sony S-Log3, Panasonic V-Log and Canon C-Log2/3 for #278, of which only Canon's two curves were new. The road map took #281, #277, #278 and #276, and #274 only if a real clip came (none did). On 2026-10-20, when Canon's own Cinema Gamut paper turned out only to plot the triangle, the owner chose "Use ACES, both gamuts (Recommended)" (HD-17). (orig "The owner's choices", "The road map as answered", H-5)

## Decisions

- **The PQ peak is read by two routes, MaxCLL first.** AVFoundation reads a sample description's `mdcv`/`clli` but not the HEVC SEI, and files from ffmpeg, HandBrake or x265 carry the SEI only (M5). So import reads the description's two extensions first and, failing those, the first sample's prefix SEI 137/144, parsed from bytes by a pure core reader (`rc_hdr10_peak`). The peak is MaxCLL when present and non-zero, else the mastering maximum, clamped to 10,000; unknown means 1,000, so every unlabelled file is byte-identical. Apple's own conversion ignores the metadata either way. (orig "#281 — the PQ peak (H-1, HD-6; the brief's §3)", H-1; HD-6, HD-12)
- **An HLG working space, with every SDR project untouched.** In an HLG project every value between stages is an HLG signal over BT.2020, and every composition converts in BT.2020/HLG (M2, M8). An SDR project keeps today's arms, uniforms and composition colour, which every phase's H1 compare held byte-identical. (orig "The HLG working space (H-2, HD-2, HD-3; the brief's §2)"; HD-2)
- **The lift is Core Graphics' drawing, toe and all.** HD-3 fixed the lift as Core Graphics' CoreMedia709 → `itur_2100_HLG` (measured: SDR 0.50 → 0.5059), so a title and a recording of the same grey stay equal. H-2's P6, built to the pure γ, failed by 21 levels at grey 11/1023: Core Graphics decodes `max(s/16, s^γ)`. The lift took the toe, and the CPU lift then matched Core Graphics within 0.25 levels at all 1,024 greys. (orig H-2 "Found while building, and settled"; HD-3, HD-13)
- **The SDR version's knee sits at 0.9.** The brief's rows were recomputed on HD-3's lift. Report ITU-R BT.2408-9 was read before the knee was fixed: it gives no HDR → SDR curve or knee of its own (it points to BT.2446), so the knee stayed at 0.9 (a white title 248.4/255, HLG 0.50 125.7/255). (orig H-3; HD-4, HD-14)
- **One output pass, chosen by `dynamic_range`.** The SDR version and PQ are one final pass after the last layer, chosen by the recipe options of the key drawn, so the preview, `render_frame` and the export share one path. `export {dynamic_range}` (not `range`) defaults per row and refuses `hlg`/`pq` on an 8-bit row or in an SDR project. PQ never exceeds 1,000 cd/m², which makes HD-5's fixed metadata true. (orig "The deliverables (H-3, HD-4, HD-5, HD-7; the brief's §2)", H-3; HD-5, HD-14)
- **The scopes read the picture shown.** Under Show SDR Version, `render_frame {sdr_version}` and a JPEG, the scopes read the SDR version as an SDR project's, because they measure the deliverable on screen; Show Ungraded keeps the HLG reading. A 0/1 `signal` uniform picks Rec. 709's or BT.2020's constants, so the SDR arm stays T4-0's arithmetic. (orig H-4; HD-8, HD-15)
- **Linear means the project's own transfer, behind a switch.** `canvas.blending` is off for every project (GR-3 stands). On, the decode is the sRGB EOTF in SDR and HLG's inverse OETF in HLG, as scene light with no OOTF. It runs once per layer after the effects block, and the output pass encodes. The adjustment pass and the qualifier map read encoded values, and Show Selection's grey, a luma matte, the key and the scopes keep their meaning. (orig "Linear light (H-6, HD-9; the brief's §4)", H-6; HD-9, HD-16)
- **Canon from Canon's paper, Cinema Gamut from the ACES CSC.** The curves come from Canon's *Canon Log Gamma Curves* white paper (November 1st, 2018), read in place and never copied. Cinema Gamut's chromaticities come from the ACES project's Canon CSC (Apache-2.0), with no code copied and the matrices derived by `InputConversions.rgbToXYZ`. The code domain is (1, 0) in both ranges, as Apple Log's under GR-22. (orig H-5; HD-10, HD-17)
- **H-6 ran before H-5.** H-5 waited on Canon's document, and H-6 needed nothing H-5 adds, so under HD-11 H-6 took format 24 and H-5 format 25. (orig H-6; HD-16 (j))
- **The Concat rule held** at design and build time: nothing of Concat was opened. The sources were ITU-R BT.2100, BT.2408, BT.2390, BT.2020 and BT.709, SMPTE ST 2084, ST 2086 and CTA-861.3, ITU-T H.265's SEI syntax, Canon's published Canon Log documents, the ACES project's Canon CSC for Cinema Gamut's chromaticities, and Apple's conversions measured as targets, never copied. (orig "The Concat rule")

## What it built — where it lives now

- Core: `hdr10.rs` and `ffi_hdr10.rs` (the SEI and description reader, `rc_hdr10_peak`), `model_media_color.rs` (`PqColor`, `PeakSource`, `MediaColor.pq`, `LogCurve::CanonLog2`/`CanonLog3`, `CameraGamut::CinemaGamut`), `media_color.rs` (the op's `peak`), `model.rs` (`CanvasOutput`, `Canvas.output`), `model_canvas.rs` (`CanvasBlending`), `edit_canvas.rs` (`set_canvas`'s `output` and `blending`), `op_table.rs` (`Kind::Output`, `Kind::Blending`), `dynamic_range.rs` (`DynamicRange`, `HDR_ROWS`, `Project::deliverable`), `export.rs`, `export_overrides.rs`, `export_table.rs`, `recipe.rs`, `recipe_options.rs`, `scope.rs`; `RC_FORMAT_VERSION` 22 (H-1), 23 (H-2), 24 (H-6) and 25 (H-5). Tests: `hdr10.rs`, `media_peak.rs`, `canvas_output.rs`, `dynamic_range.rs`, `canvas_blending.rs`, `schema_v22.rs`…`schema_v25.rs`. One FFI export; no new op or tool (92).
- Metal: `Compositor.metal`'s step-0 HLG arms (`inputToHLG`, `hlgInverseOOTF`, `pqEETF`), the Canon kinds 10 and 11, `blendDecode`/`blendEncode`, and `framejob_output_fragment`; `Waveform.metal`'s `signal` uniform and the BT.2020 constants.
- Swift: `MediaImporter+Color.swift` (`detectedPQ`), `MediaPane+HDR10.swift`, `MediaColor.swift`; `CanvasOutput.swift` (`CanvasOutput`, `CanvasBlending`), `InputConversions.swift` and `Compositor+Input.swift` (the HLG arms and the lift's CPU twins), `LayerLift.swift`, `FrameWriter.swift` (`hlgSpace`, `pickable`); `OutputTransform.swift`, `Compositor+Output.swift`, `ExportSheetDynamicRange.swift`, View ▸ Show SDR Version in `EditorViewController+Seeing.swift` with `SDRVersionTagView`; `ScopeSignal.swift`, `WaveformAnalyzer.swift`, `ScopeTraces.swift`, `WaveformTap.swift`; `DocumentPane.swift`'s Colour row, Dynamic Range and Blending popups; `MediaPane+CameraLog.swift`'s four C-Log rows; the MCP prose for `set_media_color`, `set_canvas`, `render_frame` and `export`.
- Proofs: `hdr_proof.py` (H7's family, HS–HX, HK, HM, P6, DT–DX, TO, SI–SP, LT–LU, TL) with `hdr_probe.swift` (P5–P9) and `hdr10_writer.swift`; `log_proof.py` (LP5, LP6, L19–L22) with `log_probe.swift`; `log_thumbs_proof.py`'s TP; `scopes_proof.py`'s S15 and T1's HLG variants; the screens `11-document-inspector` and `04b-preview-scopes`.
- Person checks, in `docs/manual-checks.md`: HDR-1 (H-2, H-3), HDR-2 and HDR-3 (H-3), HDR-4 (H-1), HDR-6 (H-4), LIN-1 (H-6), GRD-16's and GRD-17's HLG steps (H-2), GRD-19 (H-5). HDR-5 was never assigned; the IDs are kept as the road map numbered them.
- Pure moves: H-0's `ExportSheetController.swift` → `ExportSheetCommit.swift` (639 → 528) and `MediaImporter.swift` → `MediaImporter+Thumbnails.swift` (599 → 573); H-1's `ReelCore.swift` → `ExportValues.swift` (989 → 815); H-3's `Playback.swift` → `Playback+Scope.swift` (588 → 564). `designs/adr/app-file-history.md` names the next seams.

**Headline numbers** (Apple M2 Max, AC power; the host was loaded by other sessions throughout).

| Measure | Bound | Measured | Command |
|---|---|---|---|
| HD-3's anchor (H-0) | the brief's M6 | CoreMedia709 → `ITUR_2100_HLG`: SDR 0.50 → 0.5059, 1.00 → 0.7500; every other M6 figure unchanged | `./spike cg-hlg`; `python3 -I hdr_math.py` (the brief's spike in `tools/proof/work/h0/spike/`) |
| The PQ peak (H-1) | the oracle at each peak; `hdr_math.py` §4 | 21/21; H7p at PQ 0.70: 255.00, 246.96, 243.57, 242.72 against the computed 255.0, 246.9, 243.5, 242.8 (peaks 600, 1,000, 2,000, 4,000) | `RC_PROOF_APP=release hdr_proof.py --control tools/proof/work/h1/ctl` |
| The HLG working space (H-2) | HT 0.7500 ±1/1023; HL about 38 % | 32/32; HT the white title 0.74951; HL 18 % grey 0.3801; P6 the CPU lift 0.250 levels from Core Graphics at worst | `… hdr_proof.py --control tools/proof/work/h2/ctl` |
| The heavy 4K HLG frame (H-2) | PR-1's 8 ms | TH mean 3.405 ms, +0.835 ms over the same project in SDR | `… hdr_proof.py --measure` TH |
| The SDR version (H-3) | HD-14's 248.4 and 125.7 ±1 | 42/42; DV the white title 248.28/255, HLG 0.50 125.63/255 | `… hdr_proof.py --control tools/proof/work/h3/ctl` |
| The PQ export's metadata (H-3) | HD-5's values | DP `min_luminance=50/10000 max_luminance=10000000/10000`, `max_content=1000 max_average=0` on all three PQ files | `… hdr_proof.py` DP |
| The output pass at 4K (H-3) | recorded | TO hlg mean 1.925 ms against sdr 1.885 ms (−0.040 ms, inside two runs' noise) | `… hdr_proof.py --measure` TO |
| HDR scopes (H-4) | SV the lifted skin line; GR-10's 1.1 ms | 49/49; SV skin line 139.916428844002 (wanted 139.9164); T1's worst 4K parade 0.629 ms, vectorscope ×1/×2/×4 0.407/0.362/0.336, histogram 0.667, in HLG vectorscope 0.401/0.326/0.324, histogram 0.559 | `… hdr_proof.py --control tools/proof/work/h4/ctl`; `scopes_proof.py` T1 |
| Linear light (H-6) | GR-18's formulas | 63/63; LT white at 0.5 linear 187.3 (oracle 186.8) against encoded 127.5; the dissolve's luminance 0.199 encoded against 0.463 linear (GR-18's 0.199 and 0.464) | `… hdr_proof.py --control tools/proof/work/h6/ctl` |
| Linear light's cost at 4K (H-6) | PR-1's 8 ms | TL encoded 2.330 ms, linear 2.500 ms | `… hdr_proof.py --measure` TL |
| Canon Log 2 and 3 (H-5) | LP ±2e-3; L21 0.380 ±1/1023 | `log_proof` 29/29; LP5 worst 0.0009752512, LP6 0.0010080338; L21's 18 % patch 0.3801 for both curves | `RC_PROOF_APP=release log_proof.py compare tools/proof/work/h5/log-ctl` |
| Every SDR project (H-1…H-6) | byte-identical | H1's 12 SDR scenes byte-identical at 0 and 0.5 s with equal picks, in every phase | `… hdr_proof.py compare tools/proof/work/<phase>/ctl --only H1,…,Z1` |

Mutants, each run once on the final instrument and each answering MUTANT PASS: H-1 5, H-2 12, H-3 8, H-4 9, H-6 10, H-5 7; H-0 none, two pure moves. The gates passed first in 301 s (H-0), 246 s (H-1's toll) and 243 s (H-1), 257 s (H-2), 203 s (H-3's toll) and 250 s (H-3), 206 s (H-4), 247 s (H-6) and 345 s (H-5).

## Known limits

- **Synthetic fixtures only.** No owner HDR or log clip reached the road map; real footage is HDR-1…HDR-6, LIN-1 and GRD-16, GRD-17, GRD-19's.
- **HD-2's named risk:** if HDR-1 finds the XDR panel shows the HLG preview tone-mapped rather than in EDR, the first fallback is setting the preview layer's `preferredDynamicRange` explicitly, then a `CAMetalLayer` preview, which would amend the `AVPlayerLayer` decision and is the owner's call.
- **An HDR still is read by an HLG- or PQ-based colour space** (HD-19 (a)), **or by an ISO or Apple HDR gain map, in an HLG project only** (HD-22): a gain-map photo's un-gained parts are the base's own light, not HD-3's lift of its codes, and its SDR version is the rendition toned down, not the photo's own base (owner's choices). Only a synthetic gain map was measured; a real iPhone photo, Apple's pre-ISO map and JPEG or AVIF gain maps are HDR-7's. A key picked on a gain-map still in an SDR project is close, not exact, after the switch to HLG (HD-22 (g)).
- **The key's SDR reading is close, not exact, in two cases** (HD-19 (c)): HLG over P3 or BT.709 (its working colour was matrixed in scene light) and PQ above 1,000 cd/m² (BT.2390's EETF is not undone). A Camera Log clip's key reads its SDR colour since HD-20 (#324).
- **Apple's own conversion ignores the peak:** M5's digest `d34d90b3f676a425` for the 600 and 1,000 cd/m² files, and H-1's unscored reading of all seven files (worst |Δ| 0 against `pq_plain`).
- **AV1's peak is measured without a decode:** P10 reads libsvtav1 files through `MediaImporter.detectedPQ` on an M2 Max, which refuses AV1 imports; an AV1 file's import, render and Media-tab section on an M3 or later Mac is HDR-4's step 7.
- **A video-range-flagged non-ProRes Canon file storing full-range codes reads too contrasty** (HD-17 (e); GRD-19).
- **No log detection** from the makers' metadata (#278).
- **No re-read of the peak on relink, or for a file imported before format 22** (HD-12).
- **The output pass's cost** did not show against two runs' noise (TO −0.040 ms); it is not resolved.
- **LB's 0.5 grey sits on a rounding boundary** of the SDR frame path: encoded 127.5 against linear 126.5, inside ±1/255.
- **The reverse's intermediate digest** differed from the control's in every phase, printed and unscored; its renders were byte-identical.
- **Timings** come from one M2 Max on a loaded host and are recorded, not budgets.

## Open items

Still open:
- #278: S-Log3/V-Log detection from the makers' metadata (Canon Log 2 and 3 built by H-5, HD-17).
- #330 (clean-up 3, batch B phase 3): `hdr_proof` HG's gain-map peak mutant is caught only by the bands' order (HD-22 (k)).
- #274: the odd-size reverse's ProRes 422 cost on camera footage — not measured: no owner HDR or log clip reached the road map (HD-1).

Closed: #281 (H-1, HD-6, HD-12), #277 (H-2…H-4, HD-2…HD-5, HD-7, HD-8, HD-13…HD-15) and #276 (H-6, HD-9, HD-16) as built; #313 and #314, instrument defects older than the road map, fixed in H-2 and H-3; #310 (clean-up batch 1, the instruments held to the spec) and #315, #316, #317 (clean-up batch 2, HD-18; #317 measured, no defect), and #311, #312, #321 (clean-up batch 2, phase 2, HD-19); #324 and #325 (clean-up 3 batch B phase 1, HD-20: a Camera Log clip's key, a PQ still's HDR10 peak, format 26), #323 (phase 2, HD-21: an HDR still's thumbnails through step 0) and #322 (phase 3, HD-22: a gain-map still drawn as HDR in an HLG project).

Not filed, each decided at the close:
- How the XDR panel and an SDR external display show an HLG preview: HDR-1's steps 3–4.
- The HLG project's 4K cost: measured (TH, TO, TL).
- VideoToolbox's HEVC Main 10 HLG/PQ encode speed: the SDR `hevc_10bit` encoder with tags and two blobs; no decision waits on it.
- BT.2408's own HDR → SDR constants: read in H-3 (HD-14 (a)).
- Other editors' exact behaviour: general knowledge.
- Dolby Vision in iPhone sources: REASONED not to change what the compositor receives; HDR-2 watches for a badge.
- "Found while reading" 1–4: settled in H-1, H-1, H-2 and H-2.

Clean-up batch 2, phase 1 (#316, #315, #317; spec §11 HD-18, recorded before the code): a
WebM/Matroska Colour element's MaxCLL, MaxFALL and MasteringMetadata are read by
`container_header.rs`, reported by `rc_container_describe` (`mdcv_hex`, `clli_hex`,
`transfer`, `primaries`, `matrix`) and written into a copy's description as HD-12's two blobs,
with the PQ label, only when the Colour's transfer is 16; an `av01` track's peak is read from its
`av1C` config OBUs, then its first sample's, HDR_CLL and HDR_MDCV (`hdr10.rs`'s `av1_peak`,
`rc_hdr10_av1_peak`); a scope slot takes its caption only from its own kind's trace. The toll
moved `SpeedLimits` and the graphics value types to `CoreValues.swift` (`designs/adr/app-file-history.md`).
The control was captured on the toll's Release build (`hdr_proof.py capture
tools/proof/work/cleanup2/ctl --only H1,H7i,SI,Z1`, H-4's precedent), and DA, written before any
product code, passed there: each arm's alpha 0.50013 against `render_frame`'s 0.50001, the
straight colour's worst |Δ| 0.160/1023 (default, hlg), 0.282/1023 (sdr) and 0.000/1023 (pq
against the opaque twin), so #317 found no defect. On the phase's Release build `hdr_proof.py
compare` scored 68/68 (H1's 12 SDR scenes byte-identical with equal picks; H7w: the copies'
side data read 40000000/10000 and 600, 20000000/10000, and none, so the blobs survived the
passthrough write and step 5's atom fallback was not taken; the PQ grey rows' worst |Δ| 1 level
at 600 and 2,000; DA as on the control), `container_rewrap_probe.py` 61/61,
`container_import_proof.py` 16/16, `scopes_proof.py` 27/27 and `seeing_proof.py` 19/19. The
eleven mutants each printed MUTANT PASS; `av1-mastering-over-cll` and `av1-luminance-as-st2086`
first survived because `hdr_probe.swift` linked the tree's core, not the mutant copy's, and
passed once `build_probe` linked a copy's own built core. `webm-pq-unlabelled` was killed by
H7w's CONTROL (no copy read as PQ without the label), so HD-18 (b)'s label write stays. The gate
passed first in 243 s (the toll) and 299 s, and again in 70 s after `build_probe`'s change (names and test
re-run).

## Where to look in the original

- "Goal", "The owner's choices": the owner's answers of 2026-10-19 verbatim, the twelve choices as taken, and #278's curves.
- "The road map as answered": what #281, #277, #278, #276, #274 and #280 asked, with the corrections to B96's evidence and to #277's text (M5, M8).
- "How it fits the tree", its seven subsections: "#281 — the PQ peak" (M5's table of where the peak is, the computed #281 table); "The HLG working space" (the step-0 arm table, the lift candidates, the grade's constants); "The deliverables" (the output transforms, the SDR-version table, M7); "HDR scopes"; "Log curves"; "Linear light"; "#274 and #280 (the brief's §6)" (#274's status and #280's closure under PR-7).
- "The standard recipe, file by file, and the tolls": H-0's tolls, the conditional tolls, the core's formats and ops, the documents.
- "Spec §11: the plan": what stands, the sixteen Amended-by pairs, HD-2's named risk, what each phase was to settle.
- "Where the work happens (HD-11)"; "Phases": the per-phase table of what landed, its proof and what it owed, and each phase's planned rows and mutants.
- "Person checks"; "Test media and what to ask the owner".
- "Costs": what was recorded, M1–M8 with their commands and host, and what was reasoned from them.
- "Not established"; "Found while reading" (H7's fixture maker, B96's evidence, `DocumentPane`'s comment, the current headroom); "The Concat rule".
- H-0: the two moves, their diffs and `wc -l`, HD-3's anchor re-run, the screens and catalog controls.
- H-1: the toll, `hdr10.rs` and the Swift, the mux and fixture findings, H7d/H7i/H7p/H7o/H7r, the five mutants, #310 found.
- H-2: HD-13, the landed list, the Core Graphics toe and the other findings, `LayerLift`'s key, HS–HX and TH, the twelve mutants, #311, #312, #313.
- H-3: HD-14, BT.2408-9 read, the toll, the output pass and the sheet, DT–DX and TO, the eight mutants, #314.
- H-4: HD-15, the signal uniform, the rules written before the rows, SW/SV/SS/SD/SP and P8, T1, the nine mutants, #315.
- H-6: HD-16, the order change, the landed list, LU's deviation, LT–LU and TL, the ten mutants.
- H-5: HD-17, the owner's ACES choice, the curves, LP5/LP6 and L19–L22, the seven mutants, `log_thumbs_proof`'s TH.
- H-7: the close, the issues filed and not filed.

Clean-up batch 2, phase 2 (#311, #321, #312; spec §11 HD-19, recorded before the code, its (a)
and (b) amended with M1's and the control's figures as they came): an HLG- or PQ-labelled still is
drawn in its own colour space at 16-bit float (`LayerRenderers.renderHDRImage`, `StillColor`) and
run through its own step-0 arm in both outputs, `LayerLift` now taking a conversion and an output;
an HLG WebM/Matroska copy (Colour transfer 18) is labelled HLG (`ContainerRewrapWriter`'s
`hlgLabels`); and an HLG project's chroma key on an HLG or PQ source reads the colour an SDR
project shows (`KeyReading` in `ChromaKeyHDR.swift`, the shader's `keyReadSDR` behind
`LayerUniforms.keyReading`, the reserved float renamed), the eyedropper storing the pick through
the keyed clips' common reading. The owner chose the key's meaning on 2026-10-20 ("Key means SDR
colour (Recommended)"). M1 found today's still decode, `decodeImage`, keeps an HLG or PQ PNG's,
HEIC's, AVIF's and JPEG XL's space, depth and codes and is the only route that bounds and orients
(HD-19 (a) holds its figures), so the decode is unchanged. The phase's control was captured on the
untouched tree's Release build (`hdr_proof.py capture tools/proof/work/cleanup2/ctl-p2 --only
H1,H7i,SI,Z1`), and HI, HKh and H7h, written before any product code, all failed there: HI's HLG
and PQ PNGs as far as 209.80 and 256.25 10-bit levels from their oracles in an HLG project and
140.72 and 190.44 in an SDR one (drawn as SDR); HKh's keyed left halves read [0.3003, 0.6201,
0.2808] (green_hlg) and [0.1862, 0.9380, 0.1636] (green_pq) for the lifted background 0.5059, so
the key no longer keyed after the switch; H7h's copy read 158.27 and 213.67 levels off, so the
HLG label is written. HKh's rule fixed each fixture's tolerance from its oracle: 0.1 for
green_hlg (the un-lift 0.2267 away) and 0.02 for green_pq (white 1000/203 0.0374 away). On the
phase's Release build `hdr_proof.py compare tools/proof/work/cleanup2/ctl-p2` scored 73/73 (H1's
12 SDR scenes byte-identical with equal picks, SI's 50 JSON files byte-identical; HI's worst
|Δ| 0.00, 0.50 and 1.00 levels in an HLG project and 0.38 and 0.34 in an SDR one; HKh's left
halves 0.50585 and green_pq's right 0.61474 against 0.61518; H7h's worst 1.94 and 1.41 levels;
P12's twins 0.451 and 0.412 levels from `InputStage`; P13's lift 0.0 levels at both outputs, the
9000×600 still read 8192×546 and the Orientation-6 HEIC 128×1024), `precision_proof.py --only
S1,S2,S4,S6,S7` 6/6 against a HEAD-built control (`ctl-p2/precision`, captured `--only Sc,Sd`
from a tree copy with the phase's app files restored to HEAD: S4's ramp16.png within max |Δ| 1,
mean 0.476, of it), `container_rewrap_probe.py` 61/61 and `container_import_proof.py` 16/16.
The thirteen mutants (the spec's twelve and `hdr709-as-2020`, since BT.709 HLG/PQ spaces' own
primaries are a branch of their own) and `key-not-unlifted`, re-pinned to the new distance's two
lines, each printed MUTANT PASS with `--control tools/proof/work/cleanup2/ctl-p2`; each key
mutant failed the fixture it aimed at (`key-pq-white-fixed` and `key-pq-as-hlg` green_pq,
`key-track-reading-hlg-terms` green_hlg, `key-reading-dropped` both). The gate passed first in
266 s, and again in 1 s after this record (names re-run). The review passed with two nits, applied
at merge: `KeyReading.pick` on `.unlift` now calls `InputConversions.unliftedPick` (the same
arithmetic, so P6 and P12 read one function), and a comment on a still whose HDR bitmap Core
Graphics refuses; `make gate` passed in 211 s and P6, P12, HK, HKh, Z1 5/5 on Release after them.
Residue filed: #322 (gain-map HDR photos), #323 (an HDR still's thumbnails), #324 (a Camera Log
clip's key across the switch), #325 (a PQ still's HDR10 peak).
