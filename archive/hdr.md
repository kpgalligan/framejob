# Road map "hdr" — HDR and colour: HDR10-aware PQ, the HLG timeline, log curves, linear light

**Opened 2026-10-19** (H-0, in the worktree `~/devel/framejob-hdr` on branch `hdr`, from
`0f8c9f5`, merged into main after its gate). The design brief this road map answers is
`~/.claude/litecode/framejob/hdr-brief/I-hdr.md` (2026-10-19, tree `b6aac41`), with the owner's
answers beside it in `~/.claude/litecode/framejob/hdr-brief/answers.md`; both live outside the
repo, so everything a later phase needs from them is written here. Where the brief and this file
differ, this file wins. The grading road maps are closed (`designs/adr/grading.md`,
`grading-2.md`, `grading-3.md`, `grading-4.md`; GR-1..GR-35), and so are precision's
(`designs/adr/precision.md`, `precision-2.md`; PR-1..PR-12). This road map's decisions are HD-1
onwards, in `designs/spec/11-decisions/hdr.md`.

## Goal

Make HDR an output, not only an input. Today HDR footage goes in and only SDR comes out (GR-15):
an iPhone HLG clip is converted to Rec. 709 at step 0, the same way on every path. As the owner
chose on 2026-10-19 (HD-1), this road map builds, in order: **#281**, a PQ file's own HDR10 peak
setting step 0's PQ white (H-1); **#277**, the HDR timeline GR-19 designed, in three phases — an
HLG working space (H-2), its deliverables (HLG, HDR10 and an SDR version; H-3) and HDR scopes
(H-4); **#278**'s new log curves, Canon Log 2 and Canon Log 3 (H-5); and **#276**, linear-light
blending as GR-18 wrote it, last and the first to drop (H-6). H-7 closes. Every SDR project stays
byte-identical throughout. Each phase lands whole on main, judged by its own proofs on synthetic
fixtures; how an HDR picture looks on a panel is a person's check (the HDR rows, "Person checks").
There is no verdict phase.

## The owner's choices

**2026-10-19**, verbatim (`answers.md`):

> Owner, 2026-10-19, on I-hdr.md (asked as four questions; every answer was the recommended one):
> - Choice 1 (scope): "Everything (Recommended)" — #281 first, then #277 in three phases (working space; HLG / HDR10 / SDR-version deliverables; HDR scopes), then #278's log curves, then #276 linear light last (first to drop).
> - Choice 3 (SDR version): "Inverse of the lift (Recommended)" — 3(a): a white title stays white (249.6/255); phone HDR in the SDR version reads brighter than in an SDR project (HLG 0.5 → 143 vs 97).
> - Choices 4–6 (deliverables): "HLG + HDR10, DV off (Recommended)" — the Dynamic Range choice HLG · HDR10/PQ · SDR on the 10-bit rows, the SDR version on 8-bit/GIF/APNG/JPEG; Dolby Vision metadata off; HDR10 metadata fixed and true by construction (P3-D65, 0.005–1,000 cd/m², MaxCLL 1,000, MaxFALL 0).
> - Choice 10 (#278): Sony S-Log3, Panasonic V-Log, Canon C-Log2/3 (multi-select). Each needs the maker's published document; detection from metadata waits for real files.
> - Not asked separately, taken as recommended (stated to the owner before the questions): choice 2 fixed SDR white at 203 cd/m²; choice 7 the HDR10 peak read at import (sample description, else our own HEVC SEI parser), stored on the media with a Media-tab override, MaxCLL wins; choice 8 View ▸ Show SDR Version + render_frame {sdr_version}; choice 9 HDR scopes (HLG % with cd/m² scale, 75 % reference line, BT.2020 vectorscope); choice 11 #276 last, first to drop; choice 12 the grading-tier arrangement — worktree outside the repo (~/devel/framejob-hdr, branch hdr), each phase merged into main when its gate passes, main's next format numbers (22 onward), synthetic fixtures, the owner's real clips as manual-check rows.
> - Phasing: H-0 road map + §11 file (HD-1…) + tolls (ExportSheetController 639, MediaImporter 599 pure moves); H-1 #281; H-2 HLG working space; H-3 deliverables; H-4 HDR scopes; H-5 #278 curves; H-6 #276; H-7 close.
> - Found while reading, to fold in: hdr_proof H7's control likely fails (ffmpeg 9.0.2 libx265 no longer writes mastering-display with H7's params; x265 CLI does) — H-1 rewrites H7; B96's #281 evidence used files AVFoundation can't read metadata from — ADR known-limits line to say so; screen headroom reading is not proof the preview went HDR.

And the owner's instruction that started it (2026-10-19): "Push. For 299, go with your
recommendation. Then start HDR."

**#278's curves.** S-Log3 and V-Log already exist (GR-16, grading-3 T3-2), so of choice 10's
three the new curves are **Canon Log 2 and Canon Log 3**, with Cinema Gamut (HD-10). S-Log3's and
V-Log's detection from the maker's metadata waits for real files, so #278 stays open after H-5.

The choices therefore read: 1a (everything, in this order); 2 fixed (SDR white at 203 cd/m²,
HD-3); 3a (the SDR version is the inverse of the lift, HD-4); 4a, 5a, 6a (HLG · HDR10 · SDR on
the 10-bit rows, the SDR version elsewhere, Dolby Vision off, HDR10 metadata fixed; HD-5); 7a
(the peak read at import by both routes, MaxCLL first, an override; HD-6); 8 yes (Show SDR
Version, HD-7); 9 yes (HDR scopes, HD-8); 10 (Canon Log 2 and 3; HD-10); 11 yes (#276 last,
HD-9); 12 yes (the working arrangement, HD-11).

## The road map as answered

- **#281** (enhancement, owner 2026-10-14: "keep as a potential new feature"): GR-15's PQ shoulder
  uses a fixed 1,000 cd/m² white whatever the file's HDR10 static metadata says. **H-1.**
  **Correction to B96's evidence**, carried on the issue: B96 found Apple's own reading "identical
  across all four files", but those files held their metadata only in the HEVC stream, which
  AVFoundation does not read (M5). The brief re-ran the comparison on two Apple-written files whose
  metadata AVFoundation reads and attaches (600 against 1,000 cd/m²): Apple's conversion was
  byte-identical again (M5's digest). B96's conclusion stands, now on evidence that can see the
  field.
- **#277** (GR-19, owner 2026-10-11, choice 8a, deferred): the HDR timeline. **H-2, H-3, H-4.**
  **Correction to its text**, carried on the issue: it says `AVPlayerLayer` should show HDR "by
  itself (REASONED)". Now partly measured for the brief (M8): the layer is handed an HLG-labelled
  frame and its `preferredDynamicRange` reads `high` with nothing set. How the panel looks is
  still a person's check (HDR-1).
- **#278** (GR-16's "Not in"): more log curves, and S-Log3/V-Log detected from the maker's
  metadata. **H-5** builds Canon Log 2 and Canon Log 3; detection stays open.
- **#276** (GR-18, choice 7a, deferred): linear-light blending as an opt-in project switch. **H-6.**
- **#274** (precision-2's known limit): the odd-size reverse's ProRes 422 cost on camera footage.
  Not HDR work. Its "done when" allows "an odd-size crop of real footage", so if the owner's HDR or
  log clips arrive, **H-7** measures it and records the figure under PR-7; otherwise it stays open
  as it is. If PR-7's cost turns out unacceptable, the choice returns to the owner.
- **#280** (closed 2026-10-14): the 3-code log toe in the 10-bit reverse is PR-7's accepted limit.
  A reversed HLG or log clip in an HDR project goes through the same intermediate, which keeps its
  colour labels (PR-7), so the reverse needs no HDR work.

## How it fits the tree

Every figure below is labelled: **measured for the brief (M#)** is the brief's own scratch run
(its commands and host are under "Costs"), **computed** is `hdr_math.py`'s arithmetic, and
**REASONED** is an argument with no run behind it. This road map re-ran only M6's two commands
(H-0's record).

### #281 — the PQ peak (H-1, HD-6; the brief's §3)

**What the user sees.** A PQ file mastered at 4,000 cd/m² (from Resolve, a camera or a streaming
master) in an SDR project rolls off today as if mastered at 1,000, so everything above 1,000
cd/m² is white; after H-1 its highlights keep their gradation up to 4,000. A file mastered at 600
cd/m² reaches white at 600 instead of looking dim. The Media tab's Camera Log section (renamed
"Colour" if it grows) shows "HDR10: mastered at 4,000 cd/m² (MaxCLL, from the file)" with an
override popup ("1,000 cd/m²", "Custom…"). Every unlabelled file renders exactly as today.

**Where the peak is** (measured for the brief, M5):

| File | AVFoundation's format description | the decoded frames' attachments | ffprobe |
|---|---|---|---|
| PQ HEVC from the x265 CLI with `--master-display … L(40000000,50)` `--max-cll 4000,400` (SEI only) | no `MasteringDisplayColorVolume`, no `ContentLightLevelInfo` | none (the track output and the compositor's source) | both, 4,000 / 4,000 |
| PQ HEVC from `AVAssetWriter` with explicit 600 cd/m² / CLL 600,200 | both, our bytes | both | both |
| PQ HEVC from `AVAssetWriter`, Auto | both (1,000 / 1,000,400) | both | both |
| ProRes 422 HQ PQ with explicit values | both | (not read) | both |

So AVFoundation reads the sample description's `mdcv`/`clli` and not the HEVC SEI, and files
muxed by ffmpeg, HandBrake or x265 carry the SEI only. **Apple's conversion ignores the
metadata:** `AVAssetReaderTrackOutput` asked for BT.709 gave byte-identical frames (digest
`d34d90b3f676a425`) for the 600 and 1,000 cd/m² Apple-written files, rolling off identically
(0.7212 at signal 0.5, 1.0000 from 0.75; M5).

**The design** (HD-6; H-1's spec settles the key and its shape):
- Read at import: the format description's two extensions first; failing those, the first video
  sample's prefix SEI payloads 137 (mastering display) and 144 (content light level), parsed by
  the core from bytes as a pure function (as it already indexes WebM), Swift reading the bytes.
- The peak is MaxCLL when present and non-zero, else the mastering display's maximum; stored on
  the media (for example `media.color.hdr {peak, from}`) with `detected` semantics like Apple
  Log's; `set_media_color` takes an override (one optional key, no new op); a peak on non-PQ
  media is refused by name.
- Step 0: PQ's white W = peak/203 instead of 1000/203, kept at W ≥ 1; unknown means 1,000, so
  every unlabelled file is byte-identical. Thumbnails follow (GR-21). Format 22.

**Computed** (`hdr_math.py` §4, levels of 255 at the PQ arm's output; re-run in H-0):

| PQ signal (cd/m²) | peak 600 | 1,000 (today) | 2,000 | 4,000 |
|---|---|---|---|---|
| 0.58 (201.7) | 221.1 | 219.6 | 219.1 | 219.0 |
| 0.65 (390.5) | 242.7 | 237.9 | 236.1 | 235.7 |
| 0.70 (620.9) | 255.0 | 246.9 | 243.5 | 242.8 |
| 0.75 (983.4) | 255.0 | 254.7 | 248.8 | 247.5 |
| 0.80 (1,555.2) | 255.0 | 255.0 | 252.9 | 250.6 |

H7 becomes a row whose two renders differ by these amounts, which is what #281 asked.

**What it takes.** Core: the media field, the op's key, the SEI parser (a new module, with tests
on bytes x265 wrote), `schema_v22.rs`. Swift: `MediaImporter+Color.swift` (29) reads the peak
through a call in `MediaImporter.swift` (573 after H-0's toll), `InputConversion.uniforms` takes
the peak, the Media tab's row.

### The HLG working space (H-2, HD-2, HD-3; the brief's §2)

**What the user sees.** The Document tab's summary gains the **Colour** row the handoff designed
and `DocumentPane.swift` left out because "the whole pipeline is sRGB": "SDR — Rec. 709" or "HDR
— Rec. 2100 HLG". The Canvas section gains a **Dynamic Range** popup (SDR · HDR (HLG)), one
`set_canvas {output}` step, undoable; an agent sees `canvas.output` in `get_project`. Switching
keeps every grade's numbers (grades are defined on encoded values, GR-11…GR-13). On the built-in
XDR display an iPhone HLG clip's highlights glow above the interface's white, while a title or
screen recording sits at reference white (BT.2408); on an SDR display the player tone-maps the
HLG picture itself (Apple's tone mapping, not the SDR export's; HD-7's Show SDR Version shows
the export's). Save Frame… and `render_frame` write a 16-bit PNG labelled BT.2100 HLG, with
ImageIO's `cICP` chunk 9/18/0/1 (M4), or a 10-bit HEIC. Unchanged: SDR projects (byte-identical),
thumbnails (SDR, GR-21), the Media tab, every op but `set_canvas`.

**How it works.**
- Every value between stages is an HLG signal in 0…1 over BT.2020 primaries; PR-1's clamps stay,
  and blending stays encoded, now in HLG. **Measured for the brief (M2):** with
  `ConvertingCompositor`'s two properties and the composition set to BT.2020/HLG, every source
  arrives native and labelled as its file is (grey 0.5000 in; labels BT.709 / BT.709 for untagged
  / HLG / PQ), and both the render context's buffer and the export reader's output are labelled
  BT.2020 + HLG. **(M8):** the player's render context is labelled the same way, and so is the
  frame the `AVPlayerLayer` displays.
- **Step 0 in an HLG project:** a new set of arms in `InputConversion`, chosen by the canvas's
  output as well as the buffer's labels; in an SDR project every arm is exactly today's.

| Source | Arm in an HLG project | Notes |
|---|---|---|
| BT.709, untagged, sRGB (screen recordings, most video) | SDR → HLG by HD-3's lift (SDR white = 203 cd/m² = HLG 0.7500) | today the identity, so this pass is new for every SDR source; REASONED cost from TI (T3-1's HLG twin against BT.709): +0.455 ms per 4K source |
| HLG, BT.2020 | identity | sampled as today |
| HLG, P3 or BT.709 primaries | matrix to BT.2020 in scene light | |
| PQ | PQ → nits → BT.2390 EETF when the peak (H-1) exceeds 1,000 → HLG at 1,000 cd/m² | BT.2408's PQ → HLG |
| wide-gamut SDR (P3, BT.2020 with an SDR transfer) | SDR → HLG with its own primaries | |
| camera log (GR-16) | the maker's inverse curve → scene light → gamut to BT.2020 → HLG OETF, 18 % grey at about 38 % HLG (BT.2408's grey) | the HDR case that matters: Apple Log becomes real HDR |
| Use LUT… | the LUT's Rec. 709 output → SDR → HLG | a camera LUT made for SDR stays SDR-bright |

- **Layers Frame Job draws** (text, shapes, stills, graphics, captions, burn-in) are drawn by
  Core Graphics or resvg into 8-bit or 16-bit sRGB bitmaps (`LayerRenderers`). In an HLG project
  each is lifted once when it is uploaded, keyed in its pool with the output, not per sample —
  step 0's own rule, a pass rather than arithmetic inside the sample (a 25-tap blur would repeat
  it 25 times). The canvas background colour is lifted as a uniform.
- **One lift for every SDR layer** (HD-3), so equal encoded numbers stay equal: a title and a
  recording of the same grey still match. The candidates all put SDR white at HLG 0.7500 but part
  in the mid-tones (SDR 0.50 → HLG):

| SDR 0.50 → HLG | via | |
|---|---|---|
| 0.4456 | BT.1886 (γ 2.4), `hdr_math.py` | computed |
| 0.4690 | Core Graphics drawing sRGB into `itur_2100_HLG` | measured (M6; re-run in H-0) |
| **0.5059** | **Core Graphics drawing Core Media 709 into `itur_2100_HLG`** — the label ColorSync reads Frame Job's converted SDR frames through (GR-15's sRGB arm) | measured (M6; re-run in H-0); **HD-3's lift** |

- **The grade's constants in an HLG project** change only when the output is HLG, so every SDR
  project keeps its uniforms: Rec. 709 luma weights → BT.2020's (0.2627, 0.6780, 0.0593, already
  in `Compositor.metal` as `kLuma2020`) in Color's saturation and hue, tone, the qualifier, the
  chroma key and the waveform; tone's local linear light (`gradeDecode`/`gradeEncode`, the sRGB
  transfer) → HLG's inverse OETF and OETF, so exposure +1 is still twice the scene light; the
  vectorscope's matrix and targets → BT.2020's (H-4). Looks and `.cube` LUTs keep their 0…1
  meaning; the Look section warns when a LUT is applied in an HLG project, as GR-16's warning
  does for a LUT over Camera Log.
- **Exports in H-2:** the 10-bit rows tagged HLG with Dolby Vision off (HD-5), and every other
  row refused in an HLG project in its own sentence until H-3 — so a merged H-2 never writes HLG
  pixels labelled BT.709.
- **M3:** `AVAssetImageGenerator`'s CGImage of an HLG composition is 16-bit but labelled
  "QuickTime 'nclc' Video (9,1,2)" (BT.2020 primaries with the BT.709 transfer,
  `CGColorSpaceUsesITUR_2100TF` false), so `render_frame` relabels the image itself, as PR-11
  already does for BT.709.

**What it takes.** Core: `Canvas.output` (serde default `sdr`, written only when `hlg`),
`RC_FORMAT_VERSION` 23 and `schema_v23.rs`; `set_canvas`'s `output` argument in `op_table.rs`, so
the op tool prints it and needs no schema; the recipe canvas's `output`; `validate`'s rule. Swift
and Metal: `CompositionBuilder` (573: near the cap; a pure move first if its designer finds it
must take lines) — an HLG canvas means converting, with BT.2020/HLG colour; `InputConversion`'s
HLG arms and `Compositor.metal`'s step-0 arms; a new `LayerRenderers+Output.swift` for the lift
at upload; the uniforms for luma and transfer; `FrameWriter.frameSpace` per output (PR-11
amended); `DocumentPane` (508) for the Colour row and popup; the 10-bit rows' colour key and the
Dolby Vision key in `ExporterWriter+Settings.videoSettings` (427). Spec §4.3, §5.2, §6, §7.3,
§7.5. MCP: no new tool; `set_canvas`'s catalog sentence and UI path; the parity check sees
`output` through the core's table.

### The deliverables (H-3, HD-4, HD-5, HD-7; the brief's §2)

**What the user sees.** The export sheet's 10-bit rows say "HDR (HLG)" and gain the **Dynamic
Range** popup (HLG · HDR10 (PQ) · SDR); the 8-bit rows, GIF and APNG say "SDR version"; an
`export` call takes `range`. **View ▸ Show SDR Version** shows the export's SDR picture on any
display, with a tag in the canvas corner as Show Ungraded has; `render_frame {sdr_version:
true}` draws the same.

**The output transforms** are one final pass, chosen by the recipe options of the key being
drawn, so the preview, `render_frame` and export share one path:
- **HLG:** none.
- **SDR version** (HD-4): HLG → display light (1,000 cd/m², γ 1.2) → ÷ 203 → BT.2020 to BT.709 →
  the inverse of HD-3's lift with a shoulder whose knee sits near reference white → the encode.
- **PQ:** HLG → display light at 1,000 cd/m² → ST 2084. Nothing exceeds 1,000 cd/m², which is
  what makes HD-5's metadata true.

**The SDR version, computed** (`hdr_math.py` §1–§2, greys, levels of 255; re-run in H-0):

| In the HDR master | GR-15's arm (choice 3b) | the inverse, knee 0.39 | the inverse, knee 0.9 (choice 3a's shape) |
|---|---|---|---|
| an SDR 0.42 title (HLG 0.3743) | 77.0 | 107.1 | 107.1 |
| an SDR 0.75 grey (HLG 0.6327) | 122.5 | 188.5 | 191.3 |
| an SDR white title (HLG 0.7499) | 154.2 | 219.9 | 249.6 |
| an iPhone grey at HLG 0.50 (50.7 cd/m²) | 97.1 | 143.1 | 143.1 |
| HLG 0.85 (379 cd/m²) | 189.4 | 237.2 | 254.1 |

H-3's designer fixes the knee against these rows, after reading BT.2408's own HDR → SDR
constants ("Not established"), and records it on HD-4 before the code. The rows were computed on
the inverse of the BT.1886 route (`hdr_math.py` §1), not of HD-3's measured Core Graphics lift
(which reads SDR 0.50 as HLG 0.5059 where BT.1886 reads 0.4456), so H-3 recomputes them on
HD-3's lift first.

**Measured for the brief (M7), the export:**
- HEVC Main 10 HLG: `bt2020nc/arib-std-b67/bt2020`, with a Dolby Vision profile 8.4
  configuration (compatibility id 4) and RPU frames. With `kVTHDRMetadataInsertionMode_None`, the
  same tags and no Dolby Vision.
- PQ with Auto: mastering 0.0005–1,000 cd/m², CLL 1,000/400. PQ with explicit values: exactly
  ours (600 cd/m² / 0.005, CLL 600/200). ProRes 422 HQ took them too (`mdcv`/`clli`, read back by
  ffprobe and AVFoundation).
- ProRes 422 HQ HLG and PQ: the right tags.

**What it takes.** Core: the export resolver (`export.rs`, `export_overrides.rs`) decides
`range` per row (the canvas default for 10-bit rows, `sdr` otherwise; `hlg`/`pq` refused on an
8-bit row or in an SDR project, each in its own sentence) and hands the writer the colour triple;
`RecipeOptions` gains `sdr_version`. No FFI export: the canvas and the settings already cross as
JSON. No persisted state: `range` is per export, and the presets store is the app's. Swift and
Metal: `ExporterWriter+Settings.videoSettings` (427) — the colour key, the Dolby Vision key, the
HDR10 keys; the output pass; the popup in `ExportSheetOptions` (214) or `ExportSheetController`
(528 after H-0's toll); `EditorViewController+Seeing` (178) for Show SDR Version; `Exporter.swift`
(595) and `ExporterWriter.swift` (572) only if they must take lines, with a pure move first.
Spec §7.8 (rows and `range`), §9 (View ▸ Show SDR Version). MCP: `export {range}` and
`render_frame {sdr_version}` each a catalog sentence with its UI path.

### HDR scopes (H-4, HD-8; the brief's §2)

The waveform and parade read HLG signal % with a cd/m² scale (computed: HLG 0.50 = 50.7, 0.75 =
203.2, 1.00 = 1,000 cd/m²); a dashed line at 75 % marks reference white, where titles sit; clip
marks at 100 %. The vectorscope uses BT.2020's matrix and targets. What it takes:
`Waveform.metal`'s weights and vectorscope targets as uniforms, `WaveformTraceView` and
`VectorscopeView` scales, `ScopeTraces`' JSON naming its scale.

### Log curves (H-5, HD-10; the brief's §5)

The Media tab's Camera Log popup gains four rows after V-Log (HD-17 (b)): "C-Log2 / Cinema
Gamut", "C-Log2 / BT.2020", "C-Log3 / Cinema Gamut" and "C-Log3 / BT.2020" — Canon Log 2 and Canon
Log 3, each with Cinema Gamut (the default) or BT.2020 — each converted at step 0 as S-Log3 is
today; in an HLG project the same curves feed the log → HLG arm, where they matter most. Each is
GR-16's recipe: the curves from Canon's *Canon Log Gamma Curves* white paper (November 1st, 2018),
read for its terms first; Cinema Gamut's chromaticities from the ACES project's Canon CSC
(Apache-2.0; Canon's own Cinema Gamut paper only plots the triangle), the owner's choice of
2026-10-20; the code domain (1, 0) in both ranges (HD-17 (e)); a matrix derived from the
primaries (never copied); L1-style fixture rows and LP3-style maths rows. Sony's site refused this
host with 403 at T3-2, so the owner downloads each document, as he did for Sony's and
Panasonic's. `LogCurve`'s new values are format 25 (24 at H-0; H-6 ran first and took 24, HD-16
(j)), since an older Frame Job cannot read them.
**Detection** from the maker's metadata is not built: AVFoundation does not expose Sony's or
Panasonic's labels (GR-16); from general knowledge only, Sony's XAVC files carry an XML
"NonRealTimeMeta" block naming the gamma ("s-log3-cine") inside the MP4, and Panasonic's location
is unknown. A parser built without a real file guesses its box layout, and a misfire converts a
normal clip as log. Real files first: one per camera, from the owner, read and never copied into
the repo.

### Linear light (H-6, HD-9; the brief's §4)

A Document-tab row, **Blending: Encoded · Linear light**, off for every project, and its MCP
mirror `set_canvas {blending}`. With it on (GR-18's figures, the tier-3 brief's `linear.py`): a
50 % white over black reads 188 instead of 128; a red → green dissolve loses its dark dip
(luminance 0.464 instead of 0.199); glows and blurred edges get brighter. In an HLG project
"linear" means HLG's scene light (the inverse OETF), not the sRGB EOTF, so the decode/encode pair
takes the working transfer from the canvas. What it takes: `canvas.blending` (format 24, 25 at
H-0, renumbered when H-6 ran before H-5 (HD-16 (j)); written
only when `linear`), `set_canvas`'s argument and the recipe canvas; `Compositor.metal` — the
decode after the grade and before step 7, the destination kept linear, an encode in H-3's output
pass (which grows an arm), and the adjustment pass and qualifier wrapped (encode before reading
the destination, decode after); the scopes keep reading the encoded output. Its costs stand as
measured for GR-18: +0.000–0.001 ms at 4K for the decode and encode; one output pass, about one
copy (REASONED, 0.21 ms at 4K from C0).

### #274 and #280 (the brief's §6)

#280 is closed, accepted under PR-7; an HDR project changes nothing about it. #274 is not HDR: its
measurement (`precision_proof.py reverse-cost` on an odd-size crop of real footage) needs one real
clip and about the time of its synthetic rows. If the owner's HDR or log clips arrive during the
road map, H-7 measures it and records the figure under PR-7; otherwise it stays open.

## The standard recipe, file by file, and the tolls

The ledger is `wc -l app/Sources/*.swift core/src/*.rs graphic/src/*.rs | sort -rn`, here at
`0f8c9f5` as printed in H-0 before any edit. The cap is ~600 lines, new files 400, and frozen
files take wiring only. Size is per file only (root `CLAUDE.md`): nothing here is a budget on a
feature or a phase.

### Tolls (H-0, two pure moves gated alone)

| File | Lines at `0f8c9f5` | Why it is touched | The move |
|---|---|---|---|
| `ExportSheetController.swift` | 639 (over the cap) | H-3's Dynamic Range popup and the rows' "HDR (HLG)" / "SDR version" wording | `// MARK: - Commit` through `panelMessage` (`cancelClicked`, `exportClicked`, `queueClicked`, `commit(queue:)`, `recipeOptions`, `suggestedName`, `panelMessage`) out to `ExportSheetCommit.swift`, the three `@objc private func` made `@objc func` for `loadView`'s `#selector`s. **Paid in H-0**: 639 → 528, the new file 120. Next seam: `// MARK: - Controls` and the `NSTextFieldDelegate` extension out whole to `ExportSheetControls.swift`. |
| `MediaImporter.swift` | 599 | H-1's peak read is called from the probe | Its named seam ("a pass's await-free body out to its `+` file"): inside `thumbnails`, the image branch and the closing publication out to `MediaImporter+Thumbnails.swift` as `writeImageThumbnail` and `publishThumbnails`. **Paid in H-0**: 599 → 573, the new file 57. Next seam: the frames loop's per-result write (the `switch result` body) out to `+Thumbnails`. |

### Conditional tolls (each phase's designer's call)

Each designer pays a toll only where the phase must add lines to that file, as a pure move gated
alone before the phase's code:

| File | Lines at `0f8c9f5` | The phase that may touch it | Its named seam (`designs/adr/app-file-history.md`) |
|---|---|---|---|
| `Exporter.swift` | 595 | H-3 | none named; the designer names one |
| `Playback.swift` | 588 | H-2, H-3 (Show SDR Version's key) | `seekFinished()` and `report(_:)` to `Playback+Scope.swift` |
| `CompositionBuilder.swift` | 573 | H-2 (an HLG canvas means converting) | the orientation helpers to `CompositionBuilder+Orientation.swift` |
| `ExporterWriter.swift` | 572 | H-3 | none named; the designer names one |
| `LayerRenderers.swift` | 537 | H-2 (the lift at upload, planned in a new `LayerRenderers+Output.swift`) | none named |
| `DocumentPane.swift` | 508 | H-2 (the Colour row and the popup), H-6 (Blending) | none named |

Of the core: `model.rs` 550 and `recipe.rs` 528 take H-2's and H-6's canvas fields; `op_table.rs`
350, `export.rs` 248 and `export_overrides.rs` 266 are far from the cap. `Compositor.metal` and
`Waveform.metal` are outside the ledger's glob. `PreviewCanvasView.swift` is frozen and needs
nothing: the preview layer takes the HLG frame by itself (M8).

### Core

- **Formats** (HD-11): 22 (H-1, the media's peak), 23 (H-2, `canvas.output`), 24 (H-6,
  `canvas.blending`), 25 (H-5, new `log` values), each main's next when its code is written and
  renumbered before its merge if main moved first. At H-0 these read 24 for H-5 and 25 for H-6;
  H-6 runs before H-5 (HD-16 (j)), so it took 24. H-3 and H-4 change no persisted state.
- **Ops:** `set_canvas` gains `output` (H-2) and `blending` (H-6); `set_media_color` gains the
  peak override (H-1). No new op, no new tool (the product tool count stays 92). One FFI export,
  H-1's `rc_hdr10_peak` (the SEI reader's door; corrected in H-1, which this line had as none).
- **New module:** the HEVC SEI reader (H-1).

### Documents (each phase's own)

Spec §4.3 (the Document tab), §5.2 (`canvas.output`, `canvas.blending`, the media's peak), §6
(`set_canvas`, `set_media_color`), §7.3 (the recipe canvas, `sdr_version`), §7.5 (the working
space, step 0's HLG arms, the output pass), §7.8 (rows and `range`), §9 (View ▸ Show SDR
Version); `app/CLAUDE.md`'s entries for the files that change role (owed, listed per phase); the
README's HDR bullet; `docs/manual-checks.md`'s new "HDR" section; the screens a phase changes.

## Spec §11: the plan

**Stands, and nothing here re-litigates it** (recorded in `11-decisions/hdr.md`'s header): GR-3
(encoded blending is the default; H-6 is opt-in); GR-18's text (H-6 builds it as written); GR-20
(wide gamut only inside the HDR timeline, which this is); PR-1 (clamped 0…1, now HLG values in an
HLG project); PR-3 (`hevc` pinned to Main; it carries the SDR version); the foundations'
"`AVPlayerLayer` under an overlay view" (M8 found no reason to replace it); the Concat rule.
**The risk that would reopen one:** if HDR-1 finds the XDR panel shows the HLG preview
tone-mapped rather than in EDR, the fallback is setting the layer's `preferredDynamicRange`
explicitly (it already reads `high`); failing that, a `CAMetalLayer` preview, which would amend
the `AVPlayerLayer` decision and is the owner's call.

**Amended now (H-0), each by an "Amended by HD-n" line at the end of the entry and an "amended by
HD-n" suffix on its index row** — sixteen pairs on twelve entries, each an owner-chosen or
measured extension that applies only in an HLG project or to a labelled PQ file, never a
re-litigation:
- HD-2 → GR-2, GR-13, GR-15, GR-19, GR-32, GR-33, PR-4, PR-11 (the HLG working space: luma
  weights, tone's transfer, step 0's HLG arms, 16-bit frames labelled BT.2100 HLG).
- HD-3 → GR-19 (the SDR → HLG mapping's mid-tones fixed by measurement).
- HD-5 → GR-19 (PQ an export range, not a canvas value; the SDR version on every 8-bit row).
- HD-6 → GR-15 (T3-1's PQ white), GR-16 (the media's peak), GR-21 (thumbnails follow the peak).
- HD-8 → GR-10, GR-31 (an HLG project's scopes).
- HD-10 → GR-16 (Canon Log 2 and 3).

**Amended later, each by its own phase before its code** (an Amended-by line, or a new HD entry
from HD-12 on):
- **H-1:** HD-6's key and shape on the media, the marker's peak; GR-15's B96 text naming the
  route its evidence was taken on (`designs/adr/grading-3.md`'s Known limits line too).
- **H-2:** anything HD-2 leaves to the spec (the Colour row's words, the LUT warning's sentence,
  the refusal sentences for the non-10-bit rows).
- **H-3:** HD-4's knee (after reading BT.2408's HDR → SDR constants); HD-7's SDR-project
  behaviour and its key.
- **H-4:** the scale's ticks and the JSON's field name under HD-8.
- **H-5:** HD-10's spellings, constants and code domains from Canon's document.
- **H-6:** nothing new expected: GR-18 as written, HD-9's transfer.

**New, in `designs/spec/11-decisions/hdr.md`**, each with its README row and the Lines cells,
recorded in H-0 before any HDR code: **HD-1** the scope and order; **HD-2** the HLG working space;
**HD-3** SDR white at 203 cd/m² and its lift; **HD-4** the SDR version; **HD-5** the
deliverables; **HD-6** #281; **HD-7** Show SDR Version; **HD-8** HDR scopes; **HD-9** #276 last;
**HD-10** #278's curves; **HD-11** the working arrangement.

## Where the work happens (HD-11)

- One worktree, `~/devel/framejob-hdr` on branch `hdr`, outside the repo folder. Each phase:
  start from main, write the code, `make gate` in the worktree; when it passes, the orchestrator
  commits and merges into main (a fast-forward when main has not moved), then the next phase
  starts from main. Nothing is built in or switched in the main tree, which other sessions use.
- Per worktree: `core/target/`, `build/`, `tools/proof/work/`, the generated project, and the
  gitignored `tools/proof/media/` copied in. Shared: the git objects, and the Debug and Release
  apps' identities and defaults domains (V-5) — harmless, since proofs run under scratch homes
  and never move defaults.
- **Format numbers** and **HD IDs**: main's next when a phase's code is written (22, 23, 24, 25
  at H-0), renumbered before a merge if main moved first.
- **No verdict phase**: each phase is kept when its proofs pass.
- **Fixtures**: synthetic; the owner's real clips become `docs/manual-checks.md` rows.
- **`CLAUDE.md`**: agents never edit one; each phase's record lists the edits it owes, and the
  orchestrator applies them.

## Phases

Each phase is one implement-review cycle, gated and merged into main alone, ending with the root
`CLAUDE.md`'s "Verification": targeted tests in the loop, `make gate` once when the code is
complete, the phase's proof recorded whole on Release, mutants about one per new decision.

| Phase | What lands | Its proof holds | It owes |
|---|---|---|---|
| H-0 | This road map; `11-decisions/hdr.md` with HD-1…HD-11, its README rows and Lines cells; the sixteen Amended-by lines; HD-3's anchor measured; the tolls: `ExportSheetController.swift`'s commits out to `ExportSheetCommit.swift`, `MediaImporter.swift`'s thumbnail halves out to `MediaImporter+Thumbnails.swift` | The moves byte-for-byte; renders and the Debug catalog unchanged; `make test` unchanged. No mutants: a pure move adds no decision | the `app/CLAUDE.md` map lines (its record) |
| H-1 | **#281**: the PQ peak read at import (the sample description, else the core's parse of the HEVC SEI), stored on the media with an override in the Media tab and `set_media_color`; step 0's PQ white at the peak, 1,000 when unknown; GR-21's thumbnails follow; format 22 | `hdr_proof` H7 turned into rows: an unlabelled file and a 1,000-nit file byte-identical to today; 600 and 4,000 differ by the computed amounts; both metadata routes detected; MaxCLL wins; the override | HDR-4; GR-15's B96 line; H7's fixture maker |
| H-2 | **#277, the HLG working space**: `canvas.output`, `set_canvas {output}`, the Document tab's Colour row and popup; every composition of an HLG project converting in BT.2020/HLG; step 0's HLG arms; drawn layers and the background lifted; the grade's BT.2020 constants; `render_frame`/Save Frame… 16-bit labelled BT.2100 HLG; the 10-bit rows tagged HLG with Dolby Vision off and every other row refused in an HLG project until H-3; format 23 | Every SDR project byte-identical; HS, HH, HP, HT, HL, HW, HF, HX (below) | HDR-1; the heavy-4K HLG frame time |
| H-3 | **#277, the deliverables**: `range` (HLG/PQ/SDR) resolved in the core; the SDR version for the 8-bit rows, GIF, APNG and JPEG, lifting H-2's refusals; PQ by one output conversion with HD-5's metadata; the Dynamic Range popup; View ▸ Show SDR Version and `render_frame {sdr_version}` | ffprobe tags per row; no Dolby Vision; the mastering-display and content-light values as chosen; the SDR export = Show SDR Version's frame ±1; every SDR project's encoder input unchanged | HDR-2, HDR-3; HD-4's knee, HD-7's SDR-project behaviour |
| H-4 | **#277, HDR scopes**: HLG % with a cd/m² scale and a 75 % line; the BT.2020 vectorscope and targets; the scope JSON names its scale | HLG fixtures' traces against oracles; every SDR trace identical; GR-10's 1.1 ms at 4K | HDR-6 |
| H-5 | **#278**: Canon Log 2 and Canon Log 3, each with Cinema Gamut or BT.2020 (HD-17), each per GR-16; the curves from Canon's paper, Cinema Gamut from the ACES Canon CSC; format 25 (runs after H-6, HD-16 (j)) | Each curve on its ramp within a level; maths rows; a mutant per breakpoint and domain | GRD-19 (real clips per camera); Canon's document from the owner |
| H-6 | **#276**: `canvas.blending` (`encoded`/`linear`), opt-in; HLG projects decode by HLG's transfer; format 24 (runs before H-5, HD-16 (j)) | GR-18's table as `render_frame` rows; off byte-identical; the output pass's 4K time | LIN-1 |
| H-7 | The close: ADR `designs/adr/hdr.md`, the archive, `archive/INDEX.md`, the manual-check rows; #281, #277, #276 closed as built; #278 left open for detection; #274 measured if a real clip is at hand | — | — |

### H-1 — #281, the PQ peak (HD-6)

- **Lands:** "#281 — the PQ peak" above, with format 22. Before its code: HD-6's key and shape,
  the marker's peak, and GR-15's B96 text naming its route (an Amended-by line), with the
  matching line in `designs/adr/grading-3.md`'s Known limits ("Found while reading" 2).
- **Proof** (`hdr_proof.py` H7 rewritten, with fixtures made by the x265 CLI and by
  `AVAssetWriter`'s explicit keys — "Found while reading" 1): an unlabelled PQ file and a
  1,000-nit file byte-identical to today; 600 and 4,000 differing by the computed amounts above;
  both metadata routes detected (the sample description, the SEI); MaxCLL over the mastering
  maximum; the override; the refusal on non-PQ media; the core's SEI parser tested on bytes x265
  wrote.
- **Mutants** (five): `peak-ignored`, `mastering-over-cll`, `sei-unparsed`, `unknown-not-1000`,
  `peak-below-knee`.
- **Person check, HDR-4:** a real HDR10 file mastered above 1,000 cd/m² in an SDR project, its
  highlights rolling off, not clipped.

### H-2 — the HLG working space (HD-2, HD-3)

- **Lands:** "The HLG working space" above, with format 23.
- **Proof rows:**
  - **Identity:** every SDR project byte-identical (H1, H1m, K1–K6, PR-5's references, the
    neutral rows of tiers 1–4).
  - **HS:** an SDR ramp → HD-3's lift ±1 at 10 bits.
  - **HH:** an HLG ramp unchanged.
  - **HP:** a PQ ramp → BT.2100's PQ → HLG ±1, and above 1,000 cd/m² the EETF with H-1's peak.
  - **HT:** a white title = 0.7500 ±1/1023; a title equal to a recording's grey stays equal.
  - **HL:** an S-Log3 18 % grey → about 38 % HLG.
  - **HW:** the BT.2020 weights (a saturation-0 clip's luma).
  - **HF:** `render_frame` 16-bit with `cICP` 9/18/0/1.
  - **HX:** an HLG project's `hevc_10bit` export tagged HLG with no Dolby Vision, and `h264`
    refused by its sentence.
- **Mutants** (nine, one per decision): `sdr-not-lifted`, `title-not-lifted`,
  `background-not-lifted`, `709-weights-in-hlg`, `srgb-tone-in-hlg`, `pq-no-eetf`,
  `frame-labelled-709`, `log-to-sdr-in-hlg`, `dv-left-on`.
- **Measured:** the heavy 4K HLG frame against PR-1's 8 ms with two SDR sources (REASONED today
  from TI's +0.455 ms per 4K source).
- **Person check, HDR-1:** an HLG project with an iPhone HLG clip, a title and a screen
  recording, on the XDR display, on an SDR display, and (from H-3) with Show SDR Version.
- `DocumentPane.swift`'s "the whole pipeline is sRGB" comment is replaced by the Colour row
  ("Found while reading" 3).

### H-3 — the deliverables (HD-4, HD-5, HD-7)

- **Lands:** "The deliverables" above. Before its code: HD-4's knee and HD-7's SDR-project
  behaviour.
- **Proof rows:** per row ffprobe's primaries, transfer and matrix; no `DOVI configuration
  record` on any HEVC row; the PQ row's mastering display and CLL; the SDR version's title at the
  knee's computed value ±1; export = `render_frame {sdr_version}` ±1; the refusals of `hlg` on an
  8-bit row and in an SDR project; every SDR project's encoder input unchanged (E1/E2's rule).
- **Mutants** (five): `range-ignored`, `sdr-via-gr15`, `pq-auto-metadata`, `8bit-row-hlg`,
  `sdr-version-preview-only`.
- **Person checks:** HDR-2 (HLG exports — `hevc_10bit`, `prores_422` — in QuickTime Player on the
  XDR display and on an iPhone, and the SDR export beside them: titles white, faces natural);
  HDR-3 (an HDR10 export in QuickTime Player and in a player that shows HDR10 metadata).

### H-4 — HDR scopes (HD-8)

- **Proof rows:** HLG fixtures' waveform columns at the oracle; the vectorscope's targets at
  BT.2020's 75 % bars; every SDR project's traces byte-identical; T1's 1.1 ms with six fixtures.
- **Mutants:** `scope-709-in-hlg`, `ref-line-at-100`.
- **Person check, HDR-6:** the scopes on real HDR footage.

### H-5 — log curves (HD-10)

- **Lands:** Canon Log 2 and Canon Log 3, each with Cinema Gamut or BT.2020 (HD-17's four
  pairings), format 25; the curves from Canon's *Canon Log Gamma Curves* white paper, Cinema
  Gamut's chromaticities from the ACES project's Canon CSC. **H-6 runs before H-5** (HD-16 (j)):
  H-5 waited on Canon's document.
- **Proof rows:** per curve, an L1-style row (L19, L20) and an LP3-style row (LP5, LP6); the
  HLG arm (L21); the existing curves byte-identical (L22).
- **Mutants:** per curve, its breakpoint and its code domain (two each).
- **Person check:** GRD-19 (real clips from each camera).

### H-6 — linear light (HD-9)

- **Proof:** off byte-identical by GR0's route rule (PR-5's frozen references,
  `precision_proof.py` K1–K6, every tier-1/2 neutral row); on, GR-18's table as `render_frame`
  rows, plus the output pass's 4K frame time.
- **Mutants:** `linear-before-grade`, `adjustment-unwrapped`, `hlg-decoded-as-srgb`,
  `no-output-encode`.
- **Person check, LIN-1:** dissolves and glows look right, on and off.

### H-7 — the close

`designs/adr/hdr.md`; this road map `git mv`'d to `archive/`, with its `archive/INDEX.md` row; the
root `CLAUDE.md`'s ADR list (owed to the orchestrator); the manual-check rows; #281, #277 and #276
closed as built, each closing comment naming its HD entry; #278 left open for detection; #274
measured if a real clip is at hand.

## Person checks

A new `docs/manual-checks.md` section, "HDR", each row added by the phase that creates it:
HDR-1 (H-2), HDR-2 and HDR-3 (H-3), HDR-4 (H-1), HDR-6 (H-4), LIN-1 (H-6); GRD-16 and GRD-17
each gain an HLG-project step (H-2); GRD-19 (H-5). H-0 adds no row.

## Test media and what to ask the owner

**Synthetic, made by a script** (each measured to work for the brief): ProRes 422 HQ ramps
re-tagged HLG, PQ, BT.709 or untagged (tier 3's method); HEVC Main 10 HLG and PQ written by
`AVAssetWriter` (metadata in the sample description); PQ HEVC with SEI-only HDR10 metadata from
the **x265 CLI** (not ffmpeg's libx265 wrapper; "Found while reading" 1); S-Log3, V-Log and Apple
Log ramps (T3-2's makers); a P3 still, and the 10-bit HEIC writer.

**What to ask the owner for, plainly:**
1. An ordinary iPhone HDR clip (GRD-16 asks already), and an Apple Log clip if the phone records
   it (GRD-17).
2. An HDR10 PQ file whose mastering peak is not 1,000 cd/m², with its stated peak: a Resolve
   export, a camera's HDR10 recording or a downloaded HDR10 sample.
3. For Canon Log 2 and Canon Log 3: Canon's published document (downloaded, kept outside the
   repo), and ideally one clip.
4. Later, for #278's detection: one Sony XAVC and one Panasonic V-Log file.
5. Any real camera clip, for #274.

Paths are given, read, and never copied into the repo (GR-17's rule).

## Costs: recorded, measured, reasoned

### Recorded in the repo (quoted, not re-measured)

- **TI** (T3-1, step 0 at 4K): HLG 2.02 / 1.76 ms against BT.709 1.55 / 1.32 ms, mean difference
  0.455 ms.
- **C0's copy**: 0.21 ms at 4K.
- **GR-18's linear figures** (the tier-3 brief's `linear.py`), above.
- **GR-19's BenQ headroom**: 1.0.
- **PR-1's heavy-4K frame**: 7.38–7.585 ms against the 8 ms budget.

### Measured for the brief (its scratch spike, gitignored)

These are the brief's figures, quoted with its commands; this road map re-ran only M6's two
(H-0's record).

**Host:** Apple M2 Max, macOS 26.5.1 (25F80); `pmset -g batt`: AC Power, 100 %, charged;
`pmset -g`: `powermode 0`; `vm.loadavg` 4.81 / 5.48 / 5.63 at the start and 24.17 / 19.47 / 13.76
later (other sessions working). No timing is claimed from the brief. ffmpeg 9.0.2, x265 4.3+1.

**Folder:** `~/devel/framejob/tools/proof/work/hdr-brief-spike/` (gitignored, in the main tree).
**The build:** `python3 tools/proof/swift_build.py build --output
tools/proof/work/hdr-brief-spike/spike tools/proof/work/hdr-brief-spike/main.swift`, from the
repo root; the commands below run in that folder.

**Fixtures** (`media/`): `bt709`, `untagged`, `hlg`, `pq` (ProRes 422 HQ 1024×128) and `hlg_hevc`,
copied from the tier-3 spike's media (ffprobe: `bt709/bt709/bt709`, `gbr/reserved/reserved`,
`bt2020nc/arib-std-b67/bt2020`, `bt2020nc/smpte2084/bt2020`, and HEVC `yuv420p10le` HLG);
`pq_hdr10.mov`, the base ramp, 6 frames, through `x265 --input-depth 10 --output-depth 10
--lossless --colorprim bt2020 --transfer smpte2084 --colormatrix bt2020nc --master-display
"G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(40000000,50)" --max-cll "4000,400"`,
stream-copied into MOV (ffprobe names `Mastering display metadata max_luminance=40000000/10000`
and `Content light level metadata max_content=4000`); `pq_plain.mov`, `hdr_proof.py`'s PQ_X265
command without metadata.

| # | Command | Figure |
|---|---|---|
| M1 | `./spike edr` | Built-in Retina Display: now 1.0, potential 16.0, reference 0.0; `AVPlayer.eligibleForHDRPlayback` true (later runs read now 4.0, see M8) |
| M2 | `./spike decode media/<f>.mov conform hlg` for bt709, untagged, hlg, pq, hlg_hevc | source native: x=512 0.5000 (hlg_hevc 0.5005); source labels as the file's (untagged arrives BT.709 ×3); render-context buffer and reader output `ColorPrimaries=ITU_R_2020, TransferFunction=ITU_R_2100_HLG`, matrix absent |
| M3 | `./spike gen media/<f>.mov conform hlg 0.2` (and `conform 709`, `sdr none`) | HLG composition: bpc 16, `QuickTime 'nclc' Video (9,1,2)`, 2100TF false; BT.709 composition and today's SDR: `kCGColorSpaceCoreMedia709` |
| M4 | `./spike still-hdr out`, then a PNG chunk reader (`python3 -I`) | `still_hlg.png`: IHDR depth 16, `iCCP` 'kCGColorSpaceITUR_2100_HLG' (7,156 bytes, has a cicp tag), `cICP` 9/18/0/1; `still_pq.png` `cICP` 9/16/0/1; HEIC read back bpc 10, `ITUR_2100_HLG` / `ITUR_2100_PQ`, 2100TF true |
| M5 | `./spike exts …`, `./spike track … [709]`, `./spike decode … conform 709` | `pq_hdr10` (SEI only): no mastering or CLL extension or attachment. `w_pq-explicit` (AVAssetWriter): `MasteringDisplayColorVolume = 0x33c286c41d4c0bb884d03e803d134042005b8d8000000032`, `ContentLightLevelInfo = 0x025800c8` in the description and on frames. `track … 709` of `w_pq` and `w_pq-explicit`: digest `d34d90b3f676a425` both; row 32 from x=512 every 32: 0.7212 0.8032 0.8706 0.9238 0.9595 0.9819 0.9946 0.9990 then 1.0000 |
| M6 | `./spike cg-hlg`; `python3 -I hdr_math.py` | sRGB → `ITUR_2100_HLG`: 0.10→0.1310, 0.25→0.2576, 0.42→0.4014, 0.50→0.4690, 0.75→0.6401, 0.90→0.7104, 1.00→0.7500; → PQ 1.00→0.5806; Core Media 709 → HLG 0.50→0.5059, 1.00→0.7500; `itur_709` → HLG 1.00→0.8633; BT.1886 route 0.50→0.4456, 1.00→0.7499 (re-run in H-0, the same figures: HD-3) |
| M7 | `./spike write-hdr out/w_<k>.mov <k>`; ffprobe | `hlg`: `hevc Main 10 yuv420p10le bt2020nc/arib-std-b67/bt2020`, DOVI configuration record profile 8 compatibility 4, frames carry "Dolby Vision RPU Data"; `hlg-nometa`: same tags, no DOVI; `pq`: mastering `min_luminance=5/10000 max_luminance=10000000/10000`, CLL 1000/400; `pq-explicit`: `50/10000`, `6000000/10000`, 600/200; `prores-hlg`: `prores HQ yuv422p10le bt2020nc/arib-std-b67/bt2020`; `prores-pq`: PQ tags, no side data; `prores-pq-explicit`: `max_luminance=6000000/10000`, `max_content=600`, and AVFoundation's extensions as M5's |
| M8 | `./spike edr-layer <file> <route> [props]` (a 512×64 window, about 3 s) | layer `preferredDynamicRange high`, `toneMapMode automatic`, nothing set; displayed buffer: plain HLG file → BT.2020/HLG/2020; HLG composition (hlg or bt709 source) → BT.2020/HLG, matrix absent; BT.709 composition → BT.709/BT.709. Screen "now" headroom: 1.00 throughout one run, 4.00 before/during/after others, 3.79 in one: not ours |
| — | `hdr_math.py` sections 1–4 | the SDR-version and #281 tables above; HLG → cd/m² 0.10:1.1, 0.25:9.6, 0.50:50.7, 0.60:84.8, 0.75:203.2, 0.90:522.1, 1.00:1000.0; PQ 0.500:92.2, 0.580:201.7, 0.750:983.4, 0.900:3905.6; cd/m² → PQ 203:0.5807, 1000:0.7518; → HLG 203:0.7499 |
| — | ffmpeg's libx265 with `hdr_proof.py`'s `PQ_X265` + `HDR10_DISPLAY` params (and again with `hdr10=1:repeat-headers=1`) | ffprobe names only "Content light level metadata max_content=4000", no mastering display ("Found while reading" 1) |

### Reasoned from those

- An HLG project adds a step-0 pass for every SDR source (REASONED at TI's +0.455 ms per 4K
  source), so a heavy 4K HLG frame with two SDR sources may pass 8 ms. H-2 measures it.
- The output pass costs about one copy (REASONED, 0.21 ms at 4K from C0). H-3 measures it.

## Not established

- **How the XDR panel shows an HLG preview** (EDR or tone-mapped): HDR-1. M8 shows the layer gets
  an HLG frame and asks for `high`; it cannot show the panel.
- **An SDR external display's tone mapping of an HLG composition:** no external display was
  connected for the brief.
- **The cost of an HLG project at 4K:** step 0 for every SDR source, the lift at upload, the
  output pass, and the export's wall time — all REASONED from TI and C0.
- **Encode speed:** VideoToolbox's HEVC Main 10 HLG and PQ at 4K.
- **ProRes 4444 with alpha** in an HLG project.
- **Other containers:** whether AVFoundation reads HDR10 metadata from a Matroska or WebM Colour
  element (the rewrap path) or from AV1.
- **Exact standard constants:** BT.2408's own recommended HDR → SDR constants (the brief did not
  re-read the standard). H-3 reads it before fixing the knee.
- **Other editors' exact behaviour** (Final Cut Pro, Resolve, Premiere): general knowledge.
- **Sony's and Panasonic's metadata layout:** general knowledge only; real files are needed.
- **Dolby Vision in iPhone sources:** whether an iPhone clip's Dolby Vision 8.4 metadata changes
  what the compositor receives. REASONED not: the compositor reads the HLG base layer, and the
  per-frame metadata cannot pass through a custom compositor.

## Found while reading

The brief's §12 and the owner's "to fold in", each placed in the phase that takes it:

1. **`hdr_proof.py` H7's fixture maker on this host** — **H-1**, which rewrites H7. ffmpeg 9.0.2's
   libx265 wrapper (x265 4.3) wrote **no mastering-display SEI** with H7's own `PQ_X265 +
   HDR10_DISPLAY … L(…):max-cll=…` parameters, only the content light level; the x265 CLI with
   the same values wrote both. `tools/proof/work/hdr/media/` holds no `pq_*` fixture, so H7's
   next run rebuilds them and its CONTROL ("ffprobe names both") will likely fail. Measured for
   the brief on a twin of the command; `hdr_proof.py` itself was not run. H-1 makes the HDR10
   fixtures with the x265 CLI or `AVAssetWriter`'s explicit keys (M7).
2. **B96's #281 evidence** ("AVAssetImageGenerator's own reading … identical") was taken on files
   whose HDR10 metadata AVFoundation cannot see (SEI only, M5). The conclusion holds on
   Apple-written files (M5's digest). **H-1** names the route in `designs/adr/grading-3.md`'s
   Known-limits line and in GR-15's B96 text (an Amended-by line) when it amends them; HD-6
   records the correction now.
3. **`DocumentPane.swift`'s summary comment** says "the whole pipeline is sRGB". True until
   **H-2**, which replaces it with the Colour row.
4. **The current headroom is not proof of EDR:**
   `NSScreen.maximumExtendedDynamicRangeColorComponentValue` read 4.0 and 3.79 with nothing of the
   spike on screen (M8). GR-19's "potential 16.0" stands. **H-2**'s proofs never use the current
   value as "the preview went EDR"; that is HDR-1's.

## The Concat rule

**Concat (`~/devel/Concat`) is AGPL-3.0-or-later. None of its code, shaders, chains or colour
tables may be carried over** (root `CLAUDE.md`; `designs/adr/effects-survey.md`), at design time
and build time. The brief consulted nothing of Concat, and neither did this road map. The
sources instead: ITU-R BT.2100 (HLG and PQ), BT.2408 (SDR ↔ HDR and reference white), BT.2390
(the EETF), BT.2020 and BT.709 (primaries and luma), SMPTE ST 2084, ST 2086 and CTA-861.3 (HDR10's
metadata), ITU-T H.265's SEI syntax (payloads 137 and 144), Canon's published Canon Log
documents, Cinema Gamut's chromaticities from the ACES project's Canon CSC (Apache-2.0, HD-17; no
ACES code copied), and Apple's conversions measured as targets, never copied. Every fixture is written by
a script.

## H-0 — the road map, HD-1…HD-11 and the two moves

**What landed** (2026-10-19, in the worktree on `hdr`, from `0f8c9f5`). This road map;
`designs/spec/11-decisions/hdr.md` with HD-1…HD-11, its Files row and eleven ID rows in
`11-decisions/README.md`, and the Lines cells in both READMEs; sixteen "Amended by HD-n" lines,
one per (entry, HD) pair, at the end of twelve entries — HD-2 on GR-2 (`grading.md`), GR-13
(`grading-2.md`), GR-15 and GR-19 (`grading-3.md`), GR-32 and GR-33 (`grading-4.md`), PR-4 and
PR-11 (`precision.md`); HD-3 and HD-5 on GR-19; HD-6 on GR-15, GR-16 and GR-21; HD-8 on GR-10
(`grading-2.md`) and GR-31 (`grading-4.md`); HD-10 on GR-16 — with the matching sixteen "amended
by HD-n" suffixes on their index rows; spec §7.4's `MediaImporter.swift` row naming
`MediaImporter+Thumbnails.swift` and a new row for the export card's six files;
`designs/adr/app-file-history.md`'s "Named next cuts" recording both moves and naming the next
seams; `tools/proof/capture_spike/inventory.json`'s `commit` site re-pinned from
`ExportSheetController.swift:582` to `ExportSheetCommit.swift:78` with its four anchored refs, and
`tools/proof/remaining_probe.py`'s 1e (`SITES`, `BARE_ALLOWED`) naming `ExportSheetCommit.swift`.
And two pure moves, gated alone with no HDR code and no behaviour change: no op, tool, format,
header or FFI change.

| Move | `wc -l` before → after | New file | What widened |
|---|---|---|---|
| `ExportSheetController.swift` → `ExportSheetCommit.swift`: the blank line, then `// MARK: - Commit` through `panelMessage`'s closing brace (lines 513–623 at `0f8c9f5`: `cancelClicked`, `exportClicked`, `queueClicked`, `commit(queue:)`, `recipeOptions`, `suggestedName`, `panelMessage`) into `extension ExportSheetController`, with `import AppKit`, `import UniformTypeIdentifiers` and a five-line doc; the type's doc (its lines 44–48) names the fourth extension | 639 → 528 | 120 | the three `@objc private func` (`cancelClicked`, `exportClicked`, `queueClicked`) became `@objc func`, because `loadView`'s `#selector`s must reach them from the other file; nothing else (`commit(queue:)`, `suggestedName` and `panelMessage` stay `private`, `recipeOptions` was internal; every member they reach — `resolved`, `currentChoice`, `burnInCheckbox`, `isFrameSequence` — was already internal) |
| `MediaImporter.swift` → `MediaImporter+Thumbnails.swift`: inside `thumbnails`, the image branch's body (lines 353–366 at `0f8c9f5`) as `writeImageThumbnail`, with its own `written` and line 349's comment, and the closing publication (lines 451–457, its comment 440–450 as the doc) as `publishThumbnails`; each called from where its lines stood, so `defer { reader.finish() }` still runs after the publication; with `import AVFoundation` and a doc in `MediaImporter+Speech.swift`'s style | 599 → 573 | 57 | nothing (`decodeImage`, `writeJPEG`, `stripHolds`, `writeStamp`, `writeThumbsStamp`, `postCacheChange`, `thumbsKind`, `thumbnailHeight` and `ThumbnailReader`'s fields were already internal); every `await` stays in `MediaImporter.swift`, and `cache_pass_probe.py`'s six anchors there still occur once each |

The ledger, `wc -l app/Sources/*.swift core/src/*.rs graphic/src/*.rs | sort -rn`: 144,622 lines
before the moves and 144,662 after (the two new files' imports, docs, signatures and calls).

**The commit section is shown unchanged by the verbatim diff, `make typecheck` and
`remaining_probe.py` 1e, not by a run**: no proof presses Export… or Add to Queue
(`designs/screens/12-export-sheet.md` opens the card and cancels it; `hevc_alpha_proof.py` says
neither button is ever pressed). The screens rows below cover the card's controls and `loadView`
after the move — the `#selector`s resolve and the card paints byte-identical.

**The SDR anchor measurement** (HD-3): `./spike cg-hlg` and `python3 -I hdr_math.py`, on the
brief's spike copied into `tools/proof/work/h0/spike/` and built by `swift_build.py` (key
`f4c98006cae6b461`), printed the CoreMedia709 → `ITUR_2100_HLG` row HD-3 records (SDR 0.50 →
0.5059, 1.00 → 0.7500) and every other figure the brief's M6 quoted, unchanged; the host
2026-10-19 18:55 EDT, Apple M2 Max, macOS 26.5.1 (25F80), "Now drawing from 'AC Power'".

**Verification**, 2026-10-19 (`pmset -g ps`: "Now drawing from 'AC Power'"):
- Controls from the untouched worktree before any edit, never by stashing: `make app-debug`
  (BUILD SUCCEEDED), its `agent-catalog.json` copied to `tools/proof/work/h0/catalog-before.json`;
  `python3 tools/proof/remaining_probe.py`: 176/176; `python3 tools/proof/cache_pass_probe.py`:
  13/13; `python3 tools/proof/screens.py --only 12-export-sheet --out
  tools/proof/work/h0/screens-ctl`: exit 1, 5 pass, 1 fail of 6 — **the control's own failure**,
  P2 "keys neither pinned nor in NOT_SHOWN ['RCDevSyncHold']" (the dev-only launch default
  audio-sync AS-4 added in `eeb894b` is not in `screens.py`'s pinned or `NOT_SHOWN` lists; not
  this phase's), with the screen itself "pass — 2 captures, 0 new problems";
  `python3 tools/proof/log_thumbs_proof.py --only T1,T7,T9`: 3/3.
- After the moves: `make typecheck` exit 0, 0 errors, exactly the 4 baseline warnings, tsc
  clean; `diff <(git show HEAD:app/Sources/ExportSheetController.swift | sed -n '514,623p' | sed
  's/@objc private func/@objc func/') <(sed -n '/MARK: - Commit/,$p'
  app/Sources/ExportSheetCommit.swift | sed '$d')` exit 0, and the kept part (`HEAD`'s lines
  1–43, 49–512 and 624–639 against the file's 1–43 and 49–528) exit 0; `diff` of
  `publishThumbnails`' body against `HEAD`'s lines 451–457 exit 0; `git diff HEAD --
  app/Sources/ExportSheetController.swift app/Sources/MediaImporter.swift` read: only the removed
  block, the doc hunk and the two call sites.
- `python3 tools/proof/capture_spike/inventory.py --check`: exit 0, 5/5 (K1: "I2 and I3 clean over
  52 grep sites and 52 pins").
- `python3 tools/proof/remaining_probe.py`: **175/176**. 1e's 25 rows passed, the five on the export
  card among them naming `ExportSheetCommit.swift`. The one failure is 5f's "while its `.bin` and
  marker land with one peaks post" for the sound file under its own record (`bin=False marker=False
  posts=[]`, the pass "settled" by the probe's 1.5 s quiet window): `thumbnails` returns at its
  first line, `guard media.hasVideo`, for that record, so no moved line runs, and the peaks pass is
  untouched; `vm.loadavg` read 32.72 / 19.14 / 15.18 at the ledger's print, with other sessions
  working. Re-run once on the final tree after the review (loadavg 3.25 / 4.01 / 9.92 before it,
  3.25 / 3.93 / 9.69 after): **176/176**, exit 0, 5f's row "ok while its `.bin` and marker land
  with one peaks post — whatever it wrote before" among them. The 175 was a host-load miss.
- `python3 tools/proof/cache_pass_probe.py`: 13/13, equal to the control.
- `python3 tools/proof/spec_index_proof.py` after the last Lines edit: 177/177. The cells:
  `grading.md` 480 → 484, `grading-2.md` 421 → 427, `grading-3.md` 590 → 612, `grading-4.md` 357
  → 363, `precision.md` 446 → 452, `hdr.md` new at 257; the spec README's `07.4` 53 → 54 and its
  `11-decisions/` cell 9561 in 25 files → 9874 in 26. `python3 tools/proof/name_residue.py`: exit 0.
- `make app-debug` (BUILD SUCCEEDED), then the parsed catalogs compared against
  `catalog-before.json`: exit 0, equal (98 tools).
- `python3 tools/proof/screens.py --only 12-export-sheet --out tools/proof/work/h0/screens-after
  --compare tools/proof/work/h0/screens-ctl`: "compare: 2/2 byte-identical" (light and dark), the
  screen "pass — 2 captures, 0 new problems", and the control's P2 failure again (exit 1).
- `python3 tools/proof/log_thumbs_proof.py --only T1,T7,T9`: exit 0, 3/3.
- No `Frame Job: ` line (every run reports "`Frame Job: ` lines 0") and no `DEFAULTS MOVED` in
  any run.
- `make gate`, first run: names, typecheck (exactly the 4 baseline warnings), fmt and lint passed
  (1 s, 5 s, 2 s, 22 s); I stopped it during its test step when a Lines cell went stale under it
  (`hdr.md` 255 → 257 after an HD-4 sentence), fixed the cell and the folder total, and
  `spec_index_proof.py` read 177/177. Second run: **PASS in 301 s** — names 1 s; typecheck, fmt
  and lint skipped, their inputs byte-identical to the first run's pass; test 155 s; app 144 s,
  with D25 and D26 ok. The cargo suites passed 1,430 tests in 127 result lines and failed none;
  `spec_index_proof.py` 177/177 among its proof steps. No test file was added or removed.
  After the fix pass (P2's `NOT_SHOWN` row, the record's re-runs) and the orchestrator's
  `app/CLAUDE.md` map edits, `make gate` passed again in 67 s (names and test re-ran; the rest
  skipped as unchanged).
- On the gate's Release build: `RC_PROOF_APP=release python3 tools/proof/screens.py --only
  12-export-sheet --out tools/proof/work/h0/screens-release`: the screen "pass — 2 captures, 0
  new problems", both captures byte-identical to the Debug control's (`cmp`), and the control's
  P2 failure again (exit 1); `RC_PROOF_APP=release python3 tools/proof/log_thumbs_proof.py
  --only T1,T7,T9`: exit 0, 3/3. No `DEFAULTS MOVED` in either, nor in the gate's test log.
- The P2 failure fixed after the review: `screens.py`'s `NOT_SHOWN` gains `RCDevSyncHold` (a dev
  launch default that holds Synchronize Audio's background analysis so a proof can act during it;
  no screen launches with it), in the `RCDevAssistantSend` entry's shape. Then `python3
  tools/proof/screens.py --only 12-export-sheet --out tools/proof/work/h0/screens-fix-debug
  --compare tools/proof/work/h0/screens-ctl`: exit 0, 6 pass of 6, P2 "40 key literals: 27
  pinned (one, RCDevAppearance, per look), 13 not shown", the screen "pass — 2 captures, 0 new
  problems"; its compare read 0/2, "size differs ((480, 654) vs (960, 1308))" for both looks,
  because the host's main display had moved from the 1x external panel to the built-in Retina
  one (2x) since the control. That is host state, not paint: the 1x compare above was 2/2.
  `RC_PROOF_APP=release python3 tools/proof/screens.py --only 12-export-sheet --out
  tools/proof/work/h0/screens-fix-release`: exit 0, 6 pass of 6, both captures byte-identical
  (`cmp`) to that Debug run's 2x ones. `Frame Job: ` lines 0 and no `DEFAULTS MOVED` in either.
- No mutants: a pure move adds no decision.
- After the gate, a comment on each issue saying this road map now holds it and naming its phase,
  none closed: #281 (H-1, with B96's M5 correction), #277 (H-2–H-4, with the M8 correction),
  #278 (H-5, Canon Log 2 and 3; detection left open) and #276 (H-6).

**Owed.** The `app/CLAUDE.md` edits (applied by the orchestrator):
- line 271, `` `MediaImporter.swift` (+`Probe`, +`Speech`, +`Peaks`, +`Color`: the `` gains
  `` +`Thumbnails` `` (the await-free half of `thumbnails`: `writeImageThumbnail`,
  `publishThumbnails`);
- line 1870, `` `ExportSheetController.swift` (+`Options`, +`Resolve`, +`Presets`, `` gains
  `ExportSheetCommit.swift` (the two commits that end in the save panel, a pure move, hdr H-0).

The root `CLAUDE.md` needs nothing until the road map closes. **Residue:** none. `screens.py`'s
P2, which failed on the untouched tree (`RCDevSyncHold`, added in `eeb894b`, neither pinned nor
in `NOT_SHOWN`), is fixed in this phase by its `NOT_SHOWN` row. H-1 (#281) is next, from main
after this phase's merge.

## H-1 — #281, the PQ peak (HD-6, HD-12)

**What landed** (2026-10-19, in the worktree on `hdr`, from `dcd08f3`). Spec §11 **HD-12**, written
before the code (`11-decisions/hdr.md`: the key `media.color.pq {file?, from?, peak?}`, both
routes, the 64-bit rounding and the clamp, the op's `peak` and its three new sentences, `null`
keeping the reading, the `input`'s `peak`, the marker's `peak`, the Media tab's HDR10 section in
place of this road map's popup, no re-read on relink or for a pre-22 file), its README row, the
Lines cells, and "Amended by HD-12" lines on GR-15 (B96's route named: SEI only, unread by
AVFoundation, M5's digest `d34d90b3f676a425`), GR-16 and GR-21 with their index suffixes. Then:

- **The toll, gated alone first:** `ReelCore.swift` lines 411–583 at `dcd08f3` (`ExportPreset`,
  `ExportSettings`, `ExportSize` and their docs; no `rc_*` call) out whole to `ExportValues.swift`
  under `import AppKit` and a three-line doc — 989 → 815, the new file 178, nothing widened; the
  verbatim `diff` of the block and of the kept lines both exit 0; `make typecheck` 0 errors and the
  4 baseline warnings; `make gate` PASS in 246 s. Recorded in `designs/adr/app-file-history.md`
  with the next seam (the graphics value types and `SpeedLimits` to a values file). `ReelCore.swift`
  is 842 after `ReelHDR10`.
- **Core:** `hdr10.rs` (new, 214 lines), the pure reader — the description route when either
  blob is given, else the first sample's prefix SEI (NAL length 1, 2 or 4; before the first VCL
  unit; emulation prevention removed; `ff`-extended type and size; 137 ≥ 24 bytes and 144 ≥ 4,
  the first of each), MaxCLL when non-zero, else the mastering maximum rounded in u64, clamped to
  10,000, 0 none (MaxCLL clamped too: a u16 reaches 65,535); `ffi_hdr10.rs` (new), the one export
  `rc_hdr10_peak`, in the header's new `hdr10` block; `model_media_color.rs` `PEAK_MIN`/`PEAK_MAX`,
  `PeakSource`, `PqColor` (`effective()`), `MediaColor.pq`, `without_camera_log`;
  `media_color.rs` the op's `peak` (an `Err` when not a whole number), the reading kept by every
  op, the refusals in the order `detected`, `pq`, the peak's range, not PQ, the media's kind,
  none of `log`/`lut`/`peak`, then `check_media_color` (which now takes a `pq`-only colour and
  holds `pq` to its range and `from` with `file`), `media_input` publishing `peak`; `lut.rs`'s
  `remove_lut` and `edit_paste.rs` keep `pq`; format **22** in `format.rs` and the header;
  `edit.rs`'s row. Tests: `core/tests/hdr10.rs` (12, on x265's 47 bytes, M5's blobs, every
  prefix, the routes, MaxCLL 0, the rounding and the `0xFFFFFFFF` clamp, NAL sizes 1/2/3/4/0/8,
  VCL first, a suffix SEI, `ff` values, first-wins, NULLs), `media_peak.rs` (10), `schema_v22.rs`
  (5); `rc_hdr10_peak` in `model_tests.rs`'s null sweep; `schema_v21.rs`'s literal "the current
  version is 21" became the `>= 21` const assert `schema_v20.rs` uses (the bump broke it).
- **Swift:** `MediaColor.swift` (`PeakSource`, `PQColor`, `MediaColor.pq` and `.peak`, the two
  dictionaries); `ReelCore.swift`'s `// MARK: - HDR10` `ReelHDR10`; `MediaImporter+Color.swift`'s
  `detectedPQ` (synchronous: the description's two extensions, else an `hvc1`/`hev1` track's NAL
  length and first sample with data, `outputSettings: nil`, then `cancelReading()`) and the one
  changed line in `MediaImporter.swift` (573, unchanged count); `InputConversions.pqShoulderWhite`
  and `uniforms(…, peak:)`; `InputStage.encode(…, peak:)`, `encodeInputs` passing
  `layer.input?.peak` (its two `let conversion` lines unchanged); thumbnails (`convertingColor`
  counts a peak, `oneClip` carries `pq`, `ConvertedThumbsStamp.peak`, `holdsHDR` requires none);
  `MediaPane+HDR10.swift` (new, 96) registered by `MediaPane.swift`; the Camera Log writes keep
  `pq`; `ReelOps.setMediaColor` sends `null` for an empty dictionary; `AgentServer+Media.swift`
  reads a descriptor's `color.pq` and names the step "PQ Peak" for a peak-only `color`;
  `AgentCatalog+Files.swift`'s prose for `set_media_color` and `add_media` (no argument changed,
  so `op_argument_proof.py` and `phase9_proof.py` were not run).
- **Proof:** `hdr_proof.py`'s H7 rewritten as H7 (CONTROL), H7d, H7i, H7p, H7o, H7r, with P5 in
  `hdr_probe.swift`, five mutants, `capture --only`, and the fixtures by the x265 CLI and the new
  `hdr10_writer.swift`; `log_thumbs_proof.py`'s TP; `log_proof.py`'s `remove-lut-keeps-conversion`
  re-pinned to `lut.rs`'s new line; `tools/proof/README.md`'s "Road map hdr — H-1" section.
- **Documents:** spec §4.3b, §5.2, §5.6, §6c, §7.1, §7.2, §7.3, §7.4, §7.5, §7.7, §7.10 and the
  Lines; `designs/adr/grading-3.md`'s Known-limits line ("Found while reading" 2) and its #281
  row; `docs/manual-checks.md`'s new **HDR** section with **HDR-4**; the README's Camera log
  bullet and its `set_media_color` row; this road map's "no FFI export" (§ "Core") corrected.

**Found while building, and settled in the instrument:**
- `ffmpeg -r 30 -i x.hevc -c copy` started the stream at −0.08 s under an edit list
  (`pq_plain` 0.933 s); `-framerate 30 … -avoid_negative_ts make_zero` puts the 30 frames at k/30
  from 0. Measured with ffprobe's packet times.
- The writer's first fixtures marked every frame a sync sample (the reader's attachments were not
  copied), so `AVAssetImageGenerator` at zero tolerance answered nil at 0.5 s; copying each
  sample's attachments leaves only the IDR frame sync (ffprobe's `K__` on packet 0 alone), and
  Apple's reading of both writer files then reads.
- With `--master-display` alone x265 still writes SEI 144, as 0,0 (ffprobe: `max_content=0` on
  `pq_hdr10_display`), so that fixture tests "MaxCLL when non-zero" for real.
- ffprobe reports a writer fixture's `mdcv`/`clli` as its first frame's side data too when the
  frames carry no SEI (`pq_desc_600`), so H7's CONTROL reads the writer fixtures from the stream
  side data and `pq_both`'s first frame for its kept SEI.

**Verification**, 2026-10-19 (`pmset -g ps`: "Now drawing from 'AC Power'"), own instances on
scratch sockets and homes, each stopped by its pid; no `Frame Job: ` line in any run (Z1) and no
`DEFAULTS MOVED`:
- **Controls**, on the product as the toll's gate left it (its Release build; for the second and
  third, a `ditto` copy of it outside the products folder, because the phase's first core edit
  made the tree's own bundle stale to `proof_app`): `capture tools/proof/work/h1/ctl --only
  H1,H7i,Z1` exit 0 (H1's 12 scenes captured, H7i ok); after the mux fix `capture … --only
  H7i,Z1` exit 0, H7i ok (pq_plain and pq_hdr10_cll worst 1 level against the oracle at 1,000);
  `--control tools/proof/work/h1/ctl --only H7,H7d,H7i,H7p,H7o,H7r,Z1`: 3/7 — H7, H7i and Z1 ok,
  **H7d, H7p, H7o and H7r FAILED** (no `pq` stored; pq_desc_600 9 levels off the oracle at 600;
  the override and the sentences refused as `unknown key "peak" in color`); `log_thumbs_proof.py
  --only TP,Z1`: 1/2, **TP FAILED** (pq_hdr10's marker `{"transfer": "pq"}`, the override refused).
  Each new row discriminates; H7i is the unchanged-picture row and passes there by design.
- In the loop: the core tests above, `make lint` clean, `make typecheck` 0 errors and the 4
  warnings, `swift_build.py typecheck hdr_probe.swift` exit 0, `make app-debug` BUILD SUCCEEDED;
  on Debug `--only H7,H7d,H7i,H7p,H7o,H7r,P5,Z1` found two instrument bugs (H7r placed its three
  clips at 0, so the third import never ran; P5 read `peakBucketsPerSecond` as a `peak` key),
  both fixed, then `--only H7r,P1,P2,P3,P4,P5,Z1` 7/7; `log_thumbs_proof.py --only TP,Z1` 2/2;
  `spec_index_proof.py` 177/177.
- `make gate`: **PASS in 243 s** (names 1 s, typecheck 5 s, fmt 2 s, lint 1 s, test 138 s, app
  96 s). After the Release runs, `hdr_proof.py`'s core-copy fix, the proof README and this record,
  `make gate` passed again in 66 s (names 1 s and test 64 s re-ran; typecheck, fmt, lint and app
  skipped as unchanged); this sentence is the only edit after it.
- **Release** (the gate's `make app`): `hdr_proof.py --control tools/proof/work/h1/ctl` whole:
  **21/21**, R0 recorded. H7d read exactly `{}`, `{4000, max_cll}`, `{600, max_cll}`, `{1000,
  max_cll}`, `{2000, mastering_display}`, `{600, max_cll}` (pq_desc_600), `{600, max_cll}`
  (pq_both, the description over the SEI's 4,000), the ProRes `pq` retag `{}`, no `pq` on hlg or
  bt709. H7i: both renders byte-equal the control's pq_plain PNG, worst 1 level against the
  oracle at 1,000. H7p: worst 1 level against the oracle at 600, 2000, 4000 and 600; at PQ 0.70
  255.00, 246.96, 243.57, 242.72 against the computed 255.0, 246.9, 243.5, 242.8; pq_desc_600's
  PNG bytes = pq_hdr10_600's. H7o and H7r as their rows say; P1–P5 ok. Unscored: Apple's reading
  of all seven files is the same at every 64th column (worst |Δ| 0 against pq_plain), the B96
  values, so Apple's conversion follows neither route's metadata — the same as M5 found.
  `compare tools/proof/work/h1/ctl --only H1,Z1`: 2/2, every one of H1's 12 SDR scenes
  byte-identical to the control at 0 and 0.5 s with equal picks (the reverse's intermediate
  digest differs from the control's, f761e4934e0c2243 against 9664f5afa03f769b, a printed and
  unscored figure; its renders are among the byte-identical ones).
- `log_proof.py` whole: **21/21** (L8's sentences unchanged, the conversion LUT's removal and
  paste). `log_thumbs_proof.py --only T1,T2,T6,T7,T8,TP,Z1`: **7/7**; TP's markers `{"peak":
  4000}`, then `{"peak": 1000}`, and pq_plain's `{"transfer": "pq"}`, each `0.jpg` 1 level from its
  render at worst. `recording_probe.py --only catalog`: 31/31 (the catalog's prose).
- `lut_proof.py` whole: **27/28 — LG1 FAILED** ("lut-4: set ok, render ok, bytes differ",
  lut-5 the same: the Look gallery's LUT tiles are not byte-identical to `render_frame`). Run
  alone on Release it failed again (1/2), and on the copy of the toll's build — the product
  before any H-1 code — it failed the same way (1/2), so it predates this phase; filed as #310.
  Every other row passed, the rows on `remove_lut` and paste among them.
- **Mutants** (Release copies, each `--only <its rows>,Z1` against `tools/proof/work/h1/ctl`),
  all **MUTANT PASS**, no other row failing: `peak-ignored` (H7p, H7o), `mastering-over-cll` (H7d
  read `mastering_display` on every two-field file; H7i pq_hdr10_cll 2 levels under the oracle at
  1,000 from x 648), `sei-unparsed` (H7d read `{}`; H7p at 1,000), `unknown-not-1000` (H7i, P5),
  `peak-below-knee` (H7o, P5). `mastering-over-cll` and `sei-unparsed` first answered "the control
  could not be performed": `hdr_proof.py`'s copy symlinked `core/`, so it now gives a core edit its
  own copy of `core/` as `log_proof.py` does, and both ran again. `log_proof.py --mutant
  remove-lut-keeps-conversion` on the re-pinned anchor: MUTANT PASS (L8: `media 7: color.lut 6 is
  not a media of this project`); L9, L18 and Z1 failed beside it only because that mutant's default
  `--control`, `tools/proof/work/t3-2/ctl`, does not exist in this worktree ("… is missing from
  the control"), as they would on any build.

**Owed.** The `CLAUDE.md` edits (applied by the orchestrator):
- `core/CLAUDE.md`'s module map: a row for `hdr10.rs` · `ffi_hdr10.rs` (a PQ file's HDR10 peak
  read from bytes, pure; the one `rc_hdr10_peak` export), and the `model_media_color.rs` /
  `media_color.rs` entry gaining `PEAK_MIN`/`PEAK_MAX` (their one home), `PeakSource`, `PqColor`,
  `MediaColor.pq` and `without_camera_log`, and the op's `peak`, the reading kept by every op and
  `media_input`'s `peak`.
- `app/CLAUDE.md`: `ExportValues.swift` (the export values out of `ReelCore.swift`, a pure move,
  hdr H-1); `ReelCore.swift`'s list gaining `ReelHDR10`; the Media tab's row gaining
  `MediaPane+HDR10.swift` (the HDR10 section, one undo step "PQ Peak") and `MediaColor.swift`'s
  `PeakSource` and `PQColor`; `MediaImporter+Color.swift`'s role gaining `detectedPQ`.

**Residue:** #310 (LG1, found here and older than this phase). The owner's person check is
HDR-4. Nothing else is open: the road map's question 2 (an HDR10 file mastered off 1,000 cd/m²)
is HDR-4's file.

## H-2 — #277, the HLG working space (HD-2, HD-3, HD-13)

**What landed** (2026-10-19, in the worktree on `hdr`, from `ec08cb9`). Spec §11 **HD-13**, written
before the code (`11-decisions/hdr.md`: (a) the lift's arithmetic, (b) the SDR arms' decodes, (c)
PQ through BT.2390's EETF above 1,000 cd/m², (d) HLG over P3 or BT.709, (e) camera log at
×0.26741, (f) every drawn layer lifted at upload, (g) the grade's BT.2020 weights and tone's HLG
transfer, (h) the key and a luma matte through the inverse lift, the qualifier not, (i) frames,
(j) exports, (k) the words, (l) the two limits), its README row and the Lines cells. No toll: no
file passed its cap (`CompositionBuilder.swift` 573 → 579, `Exporter.swift` 595 with its one line
replaced in place, `ProjectSnapshot.swift` wiring only, `LayerRenderers.swift`, `Playback.swift`,
`ExporterWriter.swift`, `CanvasSessions.swift` and the frozen files untouched). Then:

- **Core:** `model.rs` `CanvasOutput` (`Sdr` default, `Hlg`, `is_sdr`) and `Canvas.output`, written
  last and only when `hlg`; `edit_canvas.rs` `set_canvas`'s `output` (the same output an identity
  through `finish`); `edit.rs` `Op::SetCanvas.output`, its dispatch and doc row; `op_table.rs`
  `Kind::Output` (`["sdr", "hlg"]`, "thirteen named types") and `opt("output", Output)` last in
  `set_canvas`'s row; `op_schema.rs` the vocabulary arm; `scope.rs` `scoped_view` copying the
  parent's output (and its doc row); `recipe.rs` the canvas's `"output": "hlg"`, `plan.rs` the
  plan's, each only when hlg; `export.rs` `HLG_ROWS` (the three 10-bit rows gain `"color": "hlg"`,
  every other video row refused by its sentence, audio rows unchanged); format **23** in
  `format.rs` and the header. Tests: `core/tests/canvas_output.rs` (new, 7), `schema_v23.rs`
  (new, 5); `op_table.rs`, `op_schemas.rs` and `op_nullability.rs` take `Kind::Output` in their
  exhaustive matches, `op_schemas.rs`'s count of kinds 19 → 20 and `op_nullability.rs`'s optional
  inventory 68 → 69 (63 → 64 not plain).
- **Swift and Metal:** `CanvasOutput.swift` (new, 32); the three decodes (`CanvasSnapshot.output`,
  `RecipeCanvas.output`, `CompositionPlan.output`); `ReelOps.setCanvas(…, output:)` and
  `setCanvasRaw(…, output:)`; `AgentServer+Tracks.setCanvas` reading `output` by `stringArg`
  and counting it in "nothing to change"; the catalog's `output` description and one HLG sentence
  each on `render_frame` and `export`. Step 0: `InputConversion.sdr`,
  `choose(input:buffer:output:)`, `uniforms(…, output:)` and its `hlgUniforms`,
  `InputConversions`' `hlgNominalGamma`, `hlgLogGrey`, `logHLGExposure`, `coreMedia709Toe`,
  `toBT2020(from:)`, `hlgOETF`, `hlgInverseOETF`, `pqSignal(nits:)`, `liftSDR`, `unliftSDR`,
  `unliftedPick`; `InputUniforms` 24 → 28 floats (`output`, `liftScale`, `ootfGamma` in the three
  reserved, then `eetfSourcePQ`, `eetfMaxLum`, `eetfKnee`, `decodeToe`); `CompositionBuilder`
  converting with BT.2020/HLG colour when `plan.output == .hlg`; the shader's `inputToHLG`,
  `hlgInverseOOTF`, `pqEETF`, and above the grade the moved HLG constants, `kLuma2020`/`kLuma709`
  and `hlgInverseOETF`, with `hlgOETF`, `kBT2020ToBT709` (derived) and `hlgUnliftSDR`. Layers and
  grade: `LayerLift.swift` (new, 104); `MetalRenderer` holding it, passing `canvas.output` to
  `encodeInputs` and clearing to the lifted background; `source(for:…, output:)`;
  `prepare` passing the output; `LayerUniforms`' HLG group (`hlgOutput`, `liftedWhite`, two
  reserved: 128 → 132 floats); `QualifierUniforms`' (16 → 20); `MatteUniforms.hlgOutput`;
  `gradeWeights`, `lookHueChroma`/`gradeHueShift`/`gradeHueCurves` taking their weights, tone's HLG
  pair, the key's and the matte resolve's un-lift, Fade Through White's lifted white, a shadow's
  colour lifted. Frames and export: `FrameWriter.hlgSpace`, `isHLG`, `labelled` keeping an HLG
  label, `pickable`, `WriteError.hlgJPEG`; `DeepStillFrame.read` labelling by the composition's
  transfer; `DeepVideoFrame.reads(…, keepsDepth:)`; the one `Exporter.swift` line;
  `ExportSettings.color`; `videoSettings` tagging HLG and turning Dolby Vision off. Picks:
  `CanvasEyedropperSession.keyColor` (in `EditorViewController+Eyedropper.swift`), `QualifierPick`
  reading `FrameWriter.pickable`. UI: `DocumentPane`'s Colour row (the "whole pipeline is sRGB"
  comment replaced) and Dynamic Range popup; `VideoPane+Look.lutInHLG` and its warning row, read
  by `ClipPane`'s signature.
- **Proof:** `hdr_proof.py`'s HS, HH, HP, HT, HL, HW, HK, HM, HF, HX, TH, P6 (in
  `hdr_probe.swift`), twelve mutants, the `hlg_p3`, `green_709` and `grey8` fixtures, and its
  `no-composition-color` and `convert-everywhere` re-pinned; the layout asserts of
  `tone_probe.swift`, `look_probe.swift`, `wheels_probe.swift`, `curves_probe.swift` (512 → 528),
  `qualifier_probe.swift` (64 → 80, sixteen → twenty), `log_probe.swift` and `hdr_probe.swift`
  (InputUniforms 96 → 112), and `log_probe.swift`'s `describe` gaining `.sdr`; the re-pinned
  anchors of `curves_proof.py` (four mutants), `tone_proof.py`, `wheels_proof.py` and
  `log_proof.py`; `tools/proof/README.md`'s "Road map hdr — H-2".
- **Documents:** spec §4.3b, §5.2 (its title's format 21 → 23), §6c, §7.2, §7.3, §7.4, §7.5, §7.8
  and the Lines; `designs/screens/11-document-inspector.md`; `docs/manual-checks.md`'s **HDR-1**
  and an HLG step on GRD-16 and GRD-17; the README's HDR (HLG) bullet and `render_frame` row.

**Found while building, and settled:**
- **Core Graphics draws Core Media 709's γ curve with a toe.** P6, built to the spec's arithmetic
  (the pure γ 502/256), failed by 21 levels at grey 11/1023 (CPU 0.0220 against Core Graphics'
  0.0425). A scratch drawing of every 10-bit grey into `linearITUR_2020` read Core Graphics'
  decode exactly: `max(s/16, s^γ)` (1/1023 → 6.109e-5, which is 1/1023/16; grey 57 the last
  linear one, 58 on the curve). HD-3 makes the lift Core Graphics' drawing, so the lift takes the
  toe (HD-13 (a) and (b) record it): the CPU lift then equals Core Graphics within 0.25 levels at
  all 1,024 greys and its inverse returns every grey within 0.0002 levels (P6). HD-3's eight anchor
  greys are all above the toe, which is why the pure γ reproduced them.
- **`InputUniforms`' new group is four, not five:** the spec's three renamed fields and five new
  ones make 29 floats (116 bytes, not a multiple of 16); its last reserved became `decodeToe`, so
  the block is the 28 floats, 112 bytes it named.
- **An SDR project's `render_frame` of a drawn layer is not its drawn value:** through
  `AVAssetImageGenerator` a 128/255 texture reads 0.49999 and white 0.99615, where an HLG
  project's frame is the reader's — so HT holds a layer to the value it is drawn with (128/255),
  and prints the SDR figures unscored.
- **A decoder's reading of a code is many levels at black through the lift's toe:** `srgb.mov`
  (HEVC Main 10) renders column 0 at 0.0182 against a nominal 0 (18.65 levels; the sRGB EOTF's
  linear toe) and `hlg_hevc` 1.41 levels from its own signal, where the ProRes fixtures stay under
  half a level. Each fixture row is held to the oracle's ±1-code envelope widened by 1/1023 (H4's
  `envelope` at 16 bits), and HP's EETF row to the columns where the clip and the EETF part by
  more than 3 levels (near the 4,000 cd/m² peak both reach 1.0 again).
- **ImageIO writes `cICP` 9/18/0/1 from the half-float HLG image directly** (`iCCP`
  `kCGColorSpaceITUR_2100_HLG`), so the spec's conditional redraw into a 16-bit integer context
  was not needed; the HEIC reads back 10-bit, `sips` naming its profile "Rec. ITU-R BT.2100 HLG".
- Instruments: an empty timeline renders no frame (HT's background scene holds a clear 16 × 16
  shape); a track holds no two clips at once (HM nests its two shapes and removes the emptied
  track); `prores_ks`'s `-color_*` flags left `green_709` untagged (re-tagged by stream copy);
  the layout asserts of seven probes (`tone_`, `look_`, `wheels_`, `curves_`, `qualifier_`,
  `log_`, `hdr_probe.swift`) follow the grown blocks, and `log_probe.swift`'s exhaustive
  `describe` gained `.sdr`.
- **`LayerLift`'s key, the source texture's identity, cannot serve a stale lift** (the review's
  open question: an animated graphic, a changing text). Every texture it is given is new and
  written once: `lifting` (`Compositor+Sources.swift`:25) is called only on `renderers.image`,
  `text`, `shape` and `graphic` (:63, :67, :70, :75), each of which comes through `cached`
  (`LayerRenderers.swift`:92), whose miss makes a texture by `upload` — `device.makeTexture` then
  one `replace` (`LayerRenderers.swift`:531–532; the graphic's `LayerRenderersGraphic.swift`:203,
  :206), the only `makeTexture` and `replace` calls in `LayerRenderers*.swift`. Nothing there
  draws into a texture it has already returned; a new text hash or a graphic's new frame (its key
  is the frame's SVG, `LayerRenderersGraphic.swift`:72) is a new texture, so a new entry. Each
  entry holds its source strongly (`LayerLift.swift`:90), so an identity is not reused while its
  lift is held, and a hit also checks `===` (:61). No row added; the key is unchanged.

**Verification**, 2026-10-19 (`pmset -g ps`: "Now drawing from 'AC Power'"; other sessions'
load on the host, loadavg about 7), own instances on scratch sockets and homes, each stopped by
its pid; no `Frame Job: ` line in any run (Z1) and no `DEFAULTS MOVED`:
- **Controls**, on the untouched tree's Release build before the first product edit
  (`RC_PROOF_APP=release`), each exit 0: `hdr_proof.py capture tools/proof/work/h2/ctl --only
  H1,H7i,Z1` (H1's 12 scenes and picks captured, H7i ok); `precision_proof.py capture
  …/precision-ctl` 7/7; `tone_`, `wheels_`, `curves_`, `qualifier_`, `look_proof.py capture
  …-ctl` (6, 6, 18, 8 and 4 frames); `log_proof.py capture …/log-ctl`. A `ditto` copy of that
  build is kept outside the products folder (`tools/proof/work/h2/ctl-app/`, gitignored).
- In the loop: the core tests above and `scope`, `export`, `schema_v22`, `op_table`,
  `op_schemas`, `op_nullability`; `make lint` clean; `make typecheck` 0 errors and the 4 baseline
  warnings; each changed probe through `swift_build.py typecheck`; `make app-debug` BUILD
  SUCCEEDED; on Debug `hdr_proof.py --only HS,HH,HP,HT,HL,HW,HK,HM,HF,HX,P1,P2,P3,P4,P5,P6,Z1`
  first 7/17 (instrument faults above, and P6's toe), then 17/17; `spec_index_proof.py` 177/177.
- `make gate`: **PASS in 257 s** (names 1 s, typecheck 5 s, fmt 2 s, lint 1 s, test 148 s, app
  100 s). After the Release runs, the record and the instrument fixes (`op_argument_proof.py`,
  the proof README), `make gate` passed again in 74 s (names 1 s and test 72 s re-ran;
  typecheck, fmt, lint and app skipped as unchanged).
- **Release** (the gate's `make app`): `hdr_proof.py --control tools/proof/work/h2/ctl` whole:
  **32/32**, R0 recorded. HS: bt709 and untagged worst 0.479 levels from the lift (x = 512:
  0.50536 against 0.50583), srgb 18.654 at column 0 (inside the envelope). HH: hlg 0.413, hlg_hevc
  1.412 levels from their own signal; hlg_p3 grey 0.413, chroma 0 of 16 columns outside, 15 moved
  > 4 levels by the matrix (CONTROL). HP: worst 1.009 levels for both; pq_hdr10 on the EETF at the
  10 columns 776–848 where it parts from the clip by 28.3 … 3.76 levels. HT: white title 0.74951;
  grey title, grey still and grey shape each 0.50732 against the recording at 128/255 0.50718 and
  the lift 0.50741; background 0.50585. HL: worst 0.392 levels; 18 % grey 0.3801. HW: 0 of 16
  chroma columns outside BT.2020 luma (15 separating the weights by > 2 levels, CONTROL); exposure
  +1 worst 0.662 levels. HK: key [0.0, 0.99951, 0.00012]; SDR keyed left 0.50001 (CONTROL); HLG
  left 0.50585, right 0.50536 against 0.50584. HM: worst left 0.219, right 0.347 levels. HF: depth
  16, `cICP` [9, 18, 0, 1], `iCCP` 'kCGColorSpaceITUR_2100_HLG'; HEIC bitsPerSample 10, "Rec.
  ITU-R BT.2100 HLG"; JPEG refused by its sentence. HX: both files bt2020nc/arib-std-b67/bt2020,
  no DOVI record, no RPU; h264 and gif refused by the sentence; audio_wav written. P6: the CPU
  lift 0.250 levels from Core Graphics at worst, the round trip 0.0002 levels, the pick
  [0.6196, 0.4, 0.2118] for [0.62, 0.40, 0.21], the HLG key [0.7611, 0.3468, 0.1548] against
  `unliftedPick` [0.7621, 0.3467, 0.1523]. `compare tools/proof/work/h2/ctl --only H1,Z1`: **2/2**,
  every one of H1's 12 SDR scenes byte-identical to the control at 0 and 0.5 s with equal picks
  (the reverse's intermediate digest differs, 962ccd7b115483ae against d7dd0befa51aa9c8, printed
  and unscored, as in H-1).
- **TH and TI** (`--measure`, 3/3): TH's SDR project 0 input passes per 120 frames (two lines),
  averages 2.63 and 2.51 ms (mean 2.570), worst 6.39 and 8.06 ms; the HLG project 240 passes,
  averages 3.61 and 3.2 ms (**mean 3.405 ms**), worst 12.98 and 6.79 ms — under PR-1's 8 ms
  average budget, +0.835 ms over the same project in SDR for its two 4K sources' passes and the
  lifted title; exports' wall 1.02 and 1.06 s. TI as before (HLG 120 passes, mean 1.975 ms;
  BT.709 0, mean 1.395 ms).
- `precision_proof.py compare …/precision-ctl` **11/11** (K1–K6 byte-identical, E1, E2, S3, S11);
  `tone_proof.py` 19/19, `wheels_proof.py` 23/23, `curves_proof.py` 59/59, `qualifier_proof.py`
  40/40, each `compare` with its N0 byte-identical; `look_proof.py compare` **28/30 — G1 and S1
  FAILED**, and both fail the same way on the pre-H-2 copy (`--app …/ctl-app --only G1,S1,Z1`:
  1/3): G1 is LG1's twin for the built-in tiles, added to #310; S1's expected refusal predates the
  Color sub-tab's wheels and curves sections (noted on #310). `log_proof.py compare …/log-ctl`
  **23/23**; `log_thumbs_proof.py --only T1,T2,T6,T7,T8,TP,Z1` 7/7; `lut_proof.py` **27/28 — LG1
  FAILED**, #310 as in H-1; `matte_proof.py` 46/46; `frame_label_proof.py` 16/16;
  `hevc_alpha_proof.py` 43/43; `op_argument_proof.py` 160/160 (after its candidates learned to try
  every member of a closed vocabulary: `set_canvas.output`'s first member, `sdr`, is what an SDR
  canvas already says, so the first run read it as unread, 158/160); `phase9_proof.py` 233/233;
  `recording_probe.py --only catalog` 31/31; `screens.py --only 11-document-inspector` 6/6, 0 new
  problems (the Colour row and the Dynamic Range popup in both looks).
- **Mutants** (Release copies, each `--only <its rows>,Z1` against `tools/proof/work/h2/ctl`), all
  twelve **MUTANT PASS** with no other row failing: `sdr-not-lifted` (HS: bt709 213.94 levels
  from the lift; HT), `title-not-lifted` (HT: the white title 1.00000, the grey 0.50196),
  `background-not-lifted` (HT), `709-weights-in-hlg` (HW), `srgb-tone-in-hlg` (HW),
  `pq-no-eetf` (HP), `frame-labelled-709` (HF), `log-to-sdr-in-hlg` (HL), `dv-left-on` (HX),
  `pick-tone-mapped` (P6), `key-not-unlifted` (HK), `matte-not-unlifted` (HM). The re-pinned
  ones: `hdr_proof.py`'s `no-composition-color` (H2, H3, H1m) and `convert-everywhere` (H1, H1m),
  `curves_proof.py`'s `hue-from-graded` (H13), `hue-before-channel-curves` (H14) and
  `color-hue-guarded` (H19), `tone_proof.py`'s `exposure-encoded` (E1, E2),
  `wheels_proof.py`'s `push-not-luma-neutral` (C1) and `log_proof.py`'s `labels-over-setting`
  (L1, `--control …/log-ctl --only L1,Z1`): MUTANT PASS. `curves_proof.py`'s
  `hue-shift-reversed` first answered MUTANT FAILURE: its five rows all FAILED (caught), and B2
  failed beside them — B2 (T4-3's hue-curve blend, whose oracle is the same hue shift) postdates
  the mutant's row list, and the same mutant on a detached worktree of `ec08cb9` (before any H-2
  edit) failed the same way, the same B2 columns (52/58), filed as #313. B2 is now in its row
  list (`curves_proof.py`'s `MUTANTS` and docstring), and on Release (2026-10-20) it answered
  MUTANT PASS: H15 H1 H4 H13 H17 B2 all FAILED, survived none, other rows failed none, B2 at
  52/58 columns.

**Owed.** The `CLAUDE.md` edits (applied by the orchestrator):
- `app/CLAUDE.md`: `LayerLift.swift` (an HLG project's lift of every layer Frame Job draws, once
  at upload by step 0's `.sdr` arm, an LRU of `LayerRenderers.cacheLimit + graphicCacheLimit`
  entries keyed by the source texture); `CanvasOutput.swift` (the project's dynamic range, `sdr`
  or `hlg`, on the canvas snapshot, the recipe's canvas and the plan); step 0's role in
  `Compositor+Input.swift` and `InputConversions.swift` gaining the HLG arms
  (`choose(input:buffer:output:)`, `uniforms(…, output:)`, `InputUniforms`' HLG fields) and the
  lift's CPU twins (`liftSDR`, `unliftSDR`, `unliftedPick`, `coreMedia709Toe`); `FrameWriter`'s
  role gaining `hlgSpace`, `pickable` and the HLG JPEG refusal; `DocumentPane`'s gaining the
  Colour row and the Dynamic Range popup.
- `core/CLAUDE.md`'s module map: `model.rs` gaining `CanvasOutput` (`Canvas.output`, written only
  when `hlg`), `op_table.rs` gaining `Kind::Output`, and `export.rs`'s HLG arm (`HLG_ROWS`).

**Residue:** #311 (an HLG or PQ still is drawn as SDR in an HLG project) and #312 (a key set on
an HDR clip in an SDR project may need re-picking after the switch), filed from HD-13 (l); #310
(LG1, and now look_proof's G1 and S1, older than this phase); #313 (`hue-shift-reversed`'s row
list missing B2, older than this phase) fixed here, B2 added and the mutant passing. The owner's
person check is HDR-1, with the HLG steps added to GRD-16 and GRD-17.

## H-3 — #277, the deliverables (HD-4, HD-5, HD-7, HD-14)

**What landed** (2026-10-20, in the worktree on `hdr`, from `7aef1e8`). Spec §11 **HD-14**, written
before the code (`11-decisions/hdr.md`: (a) the knee at 0.9, recomputed on HD-3's lift by
`tools/proof/work/h3/sdr_version_math.py` — the white title 248.4/255, HLG 0.50 125.7/255 —
with BT.2408's own reading beside it; (b) the one output pass and the composition's colour;
(c) `dynamic_range`, not `range`, its per-row defaults and two refusals; (d) PQ and HD-5's two
blobs; (e) frames; (f) M-H3a, the spike's HEVC PQ with no insertion-mode key; (g) Show SDR
Version; (h) the sheet's row; (i) the amendments), its README row, "amended by HD-14" on HD-4,
HD-5, HD-7 and HD-13 with their Amended-by lines, and the Lines cells. **BT.2408 read:** Report
ITU-R BT.2408-9 (2026), fetched from itu.int, gives no HDR → SDR curve or knee of its own (§5.2
points to Report BT.2446's three methods; §7.1.3 records SDR content at 75 % HLG attenuated "to
as little as 86 %" on a live SDR output, and round-trip losses "as low as 5 %" with a
super-white range); the knee is unchanged by it, and no issue was needed. No format change, no
FFI export, no new tool (92), no op change. Then:

- **The toll, gated alone first** (`04-toll.patch` in the handoff): `Playback.swift`'s named seam —
  `seekFinished()` and `report(_:)` with their docs (and the blank line before) moved verbatim to
  the end of `Playback+Scope.swift`, each losing only `private`; `reported` and `refreshWanted`
  widened from `private`; `player` stays private; the type's doc and `+Scope`'s name the pair.
  `wc -l app/Sources/Playback.swift`: 588 → 564; `Playback+Scope.swift` 35 → 60. The verbatim
  `diff` of the moved block and of the kept lines both exit 0; `make typecheck` 0 errors and the
  4 baseline warnings; `make gate` **PASS in 203 s** (names 1 s, typecheck 5 s, fmt and lint
  skipped, test 104 s, app 93 s). Recorded in `designs/adr/app-file-history.md` with the next seam
  (`setPreviewQuality` and `recompose()` to `+PreviewQuality` behind an internal read of the
  player's item).
- **Core:** `dynamic_range.rs` (new, 95: `DynamicRange`, `HDR_ROWS`, `Project::deliverable`);
  `lib.rs`; `export.rs` (the reader called right after `object(overrides)?`, `deliverable`, the
  settings' `color` = the picture, H-2's `HLG_ROWS` and refusal gone; 268 → 259);
  `export_overrides.rs` (`dynamic_range`, its sentence); `export_table.rs` (`"hdr": true` on
  `HDR_ROWS`, 581 → 584); `recipe_options.rs` (`dynamic_range`, read by `parse`); `recipe.rs`
  (the canvas's `dynamic_range` after `output`, only for HLG + `sdr`/`pq`); `ffi_query.rs` and the
  header (doc comments only: the opts and the overrides paragraph name `dynamic_range`, the
  resolved `color` a sentence). Tests: `core/tests/dynamic_range.rs` (new, 7),
  `canvas_output.rs`'s row test (the non-10-bit rows now `"color": "sdr"`),
  `export_hevc_10bit.rs`'s row (`"hdr": true`).
- **Swift and Metal:** `OutputTransform.swift` (new, 105: `DynamicRange`, `VideoColour`,
  `OutputUniforms`, `sdrKnee`, `compositionColour`, `uniforms(for:)`, the two blobs);
  `Compositor+Output.swift` (new, 42: `outputPipeline`, `encodeOutput`); the shader's
  `OutputUniforms`, `pqInverseEOTF` and `framejob_output_fragment` after the input fragment;
  `MetalRenderer` (the pipeline, one call after `encodeLayers`; 356 → 364); `RecipeOptions`
  (`dynamicRange`, `json`, `delivering`, `forFrame`); `RecipeCanvas.dynamicRange`;
  `ExportPreset.carriesHDR`, `ExportSettings.dynamicRange`; `CompositionBuilder` (its `let hlg`
  and `let converts` lines kept verbatim, the colour through `compositionColour` with the key's
  option, `BuiltComposition.output`; 579 → 581); `Exporter.swift`'s one line replaced in place
  (595); `videoSettings` (PQ's tags, the two keys beside HEVC's with no insertion-mode key, a
  ProRes compression dictionary of the two; 444 → 469); Save Frame…'s options through
  `forFrame`; `Playback.recompose()` (579), `setPreviewQuality` calling it, `finishRebuild`
  passing `sdrVersion`, `previewComposition(…, sdrVersion:)`; View ▸ Show SDR Version
  (`toggleShowSDRVersion`, no shortcut, no default written, always enabled), `SDRVersionTagView`
  third in the tag stack, `UIMenuTable`'s row and `inventory.json`'s entry (verdict `none`, "view
  state, not persisted"); the sheet's "Dynamic Range:" row under Format in an HLG project only
  (`ExportSheetDynamicRange.swift`, new, 55; `ExportSheetController.swift` 528 → 537,
  `ExportSheetResolve.swift` 578 → 580 wiring only, `Applies.dynamicRange`); MCP:
  `render_frame {sdr_version}` (built after `frameDestination` through `forFrame`, the text's ",
  as the project's SDR version"), `export {dynamic_range}` forwarded unread and the result's
  `dynamic_range`, the catalog's two properties and sentences.
- **Proof:** `hdr_proof.py`'s DT, DP, DV, DI, DE, DR, DS, DM, DX and TO, HX and HF rewritten,
  seven mutants, `no-composition-color` re-pinned to `compositionColour`, the docstring;
  `hdr_probe.swift`'s P7; `phase8_chrome.py`'s View group (six rows, Show SDR Version after Show
  Selection); `tools/proof/README.md`'s "Road map hdr — H-3".
- **Documents:** spec §4.2, §7.1, §7.3, §7.4, §7.5, §7.8, §7.9a, §7.10, §9 and the Lines;
  `docs/manual-checks.md`'s HDR-1 (step 7, Show SDR Version; JPEG saves the SDR version), **HDR-2**
  and **HDR-3**; the README's HDR bullet and its `render_frame` and `export` rows.

**Found while building, and settled in the instrument:**
- DE's `h264` at the encoder's own rate read the grey row's decoded chroma 2.720/255 off the
  render at worst (x 528–536, R and B apart by about 0.015 on a neutral row: H.264's chroma
  compression of the 1024 × 128 ramp), against the spec's ±2/255; the row now exports `h264` at
  the default dynamic range and 50 Mbit/s (`DE_H264_BITRATE`), where it read 1.034/255. The bound
  is unchanged.
- The layout dump carries no enabled state, so DX reads the Dynamic Range popup's title ("HDR
  (HLG)" / "SDR version"); its disabled state on a non-10-bit row is HDR-2's to see.
- `export_as`'s glob first matched a document package and an instance log of the same name (TO's
  first two `--measure` runs stopped on them); it now takes files only and TO's names differ.

**Verification**, 2026-10-20 (`pmset -g ps`: "Now drawing from 'AC Power'"; other sessions'
load on the host, loadavg about 10–15), own instances on scratch sockets and homes, each stopped
by its pid; no `Frame Job: ` line in any run and no `DEFAULTS MOVED`:
- **Controls**, on the toll's Release build before the first product edit (a `ditto` copy,
  `tools/proof/work/h3/ctl-app/`, gitignored; `precision_proof.py`'s on the tree's own build,
  which needs a product of a tree): `hdr_proof.py capture tools/proof/work/h3/ctl --only
  H1,H7i,Z1` exit 0; `precision_proof.py capture …/precision-ctl` 7/7; `tone_`, `wheels_`,
  `curves_`, `qualifier_`, `look_`, `log_proof.py capture …-ctl` exit 0 (6, 6, 18, 8, 4 frames;
  log's control FAILED none); `screens.py --only 12-export-sheet --out …/screens-ctl` 6/6.
- In the loop: `cargo test --release` `dynamic_range` 7, `canvas_output` 7, `export` 38,
  `export_hevc_10bit` 4, `recipe` 15, `scope` 38, all passing; `make lint` clean; `make
  typecheck` 0 errors and exactly the 4 baseline warnings; `swift_build.py typecheck
  hdr_probe.swift` exit 0; `inventory.py --check` 5/5; `v2_menu.py --only H` 5/5;
  `spec_index_proof.py` 177/177; `make app-debug` BUILD SUCCEEDED; on Debug `hdr_proof.py
  --only DT,…,DX,HX,HF,P1–P7,Z1` first 18/19 (DE, above), then `--only DE,Z1` 2/2.
- `make gate`: **PASS in 250 s** (names 1 s, typecheck 5 s, fmt 2 s, lint 1 s, test 138 s, app
  103 s). After the Release runs, the instrument fixes (`export_as`, TO's names), this record,
  the proof README and the manual checks, `make gate` passed again in 67 s (names 1 s and test
  66 s re-ran; typecheck, fmt, lint and app skipped as unchanged). The review's fix pass (comment
  re-wraps, the export sheet's split `rows.insert`, phase8_chrome's size check and the harness's
  `mediaFilter`): `make typecheck` 0 errors and the 4 baseline warnings; `make gate` **PASS in
  210 s** (names 1 s, typecheck 5 s, fmt 2 s, lint 1 s, test 108 s, app 92 s), then
  `phase8_chrome.py` on its Release build 150/150; this record's lines on that pass came after it.
- **Release** (the gate's `make app`): `hdr_proof.py --control tools/proof/work/h3/ctl` whole on
  the final instrument: **42/42**, R0 recorded. DT: every row and range tagged as its picture
  (h264, hevc, hevc_alpha and every `sdr` bt709 ×3; the 10-bit rows' default and `hlg`
  bt2020nc/arib-std-b67/bt2020; `pq` bt2020nc/smpte2084/bt2020), no DOVI record or RPU on any of
  the eight HEVC files, gif and apng written. DP: all three PQ files' side data exactly
  `red_x=34000/50000 … white_point_y=16450/50000 min_luminance=50/10000
  max_luminance=10000000/10000`, `max_content=1000 max_average=0` (MaxFALL 0's first
  measurement), prores_422's grey row 1.283/1023 from the PQ oracle at worst. DV: the ramp
  0.108/255 from the oracle at worst; HLG 0.50 125.63/255; the white title 248.28/255; the 0.42
  title 106.89/255; the PNG's label `kCGColorSpaceCoreMedia709`, as an SDR project's, no cICP.
  DI: 122 columns at or below SDR 0.9477 0.374/255 from the SDR render at worst, 6 above 0.244/255
  from the shoulder oracle. DE: h264 frame 15 1.034/255 (at 50 Mbit/s), prores_422 {sdr} 0.289/255,
  the JPEG 0.498/255 from the sdr_version PNG, both profiles "HDTV". DR: the four sentences. DS: PNG
  `9c1e7efe2da2592b` and JPEG `6697a302554930b8` each equal with and without `sdr_version`; the
  h264 settings equal. DM: the tag shown and hidden again, the render `ad786e55f69451fd` both
  times. DX: "HDR (HLG)" pinned to hevc_10bit, "SDR version" pinned to h264, no row in an SDR
  project. HF: the PNG 16-bit cICP [9, 18, 0, 1]; the HEIC 10-bit "Rec. ITU-R BT.2100 HLG"; the
  JPEG written, "HDTV". HX: both 10-bit files HLG with no Dolby Vision, h264 bt709 ×3, gif and
  audio_wav written. P1–P7 ok. `compare tools/proof/work/h3/ctl --only H1,Z1`: **2/2**, every one of
  H1's 12 SDR scenes byte-identical at 0 and 0.5 s with equal picks (the reverse's intermediate
  digest differs, f651dfe600c6b1a2 against f3be809e5b36946f, printed and unscored, as in H-1 and
  H-2).
- **`--measure`** (4/4): TI (HLG 120 passes, mean 1.945 ms; BT.709 0, mean 1.400 ms); TH (SDR 0
  passes, mean 2.200 ms; HLG 240, mean 3.000 ms); **TO**: the 4K HLG project's prores_422 at hlg
  bt2020nc/arib-std-b67/bt2020, averages 2.09 and 1.76 ms (mean 1.925), and at sdr bt709 ×3,
  averages 2.05 and 1.72 ms (mean 1.885): the output pass's cost did not show against two
  runs' noise (−0.040 ms; C0's copy 0.21 ms was the REASONED figure), host loadavg 10–11.
- `precision_proof.py compare …/precision-ctl` **11/11** (K1–K6 byte-identical, E1, E2, S3,
  S11); `tone_proof.py` 19/19, `wheels_proof.py` 23/23, `curves_proof.py` 59/59,
  `qualifier_proof.py` 40/40, each `compare` with its N0 byte-identical; `look_proof.py compare`
  **28/30 — G1 and S1 FAILED** as before (#310); `log_proof.py compare` 23/23;
  `log_thumbs_proof.py --only T1,T2,T6,T7,T8,TP,Z1` 7/7; `lut_proof.py` **27/28 — LG1 FAILED** as
  before (#310); `frame_label_proof.py` 16/16; `hevc_alpha_proof.py` 43/43; `seeing_proof.py`
  19/19; `op_argument_proof.py` 160/160 and `phase9_proof.py` 233/233 (on an instance launched by
  `proof_app.py launch`); `recording_probe.py --only catalog` 31/31.
- `phase8_chrome.py`: **147/150** — the View group's new row passes ("Preview Quality | Preview
  Window | Show Ungraded | Show Selection | Show SDR Version | Scopes"); three checks FAILED, and
  a detached worktree of `7aef1e8` (before any H-3 edit, its own core built) failed the same three
  (147/150): `LayerUniforms` 528 bytes against the check's 512 (H-2's growth), and the Media pane's
  `mediaFilter` finding two `OptionPopupControl`s, which blanks the sort-popup check. Filed as
  #314. The review's fix pass mended all three on the instrument side: the size check expects
  528/528 (132 floats since H-2's HLG group, 33 x 16), and the harness's `mediaFilter` picks the
  sort popup by `MediaListFilter.controls`' own tooltip, since the second popup is grading-3's
  Camera Log section (GR-16), not H-1's. On the fix pass's Release build: **150/150**.
- `screens.py --only 12-export-sheet --compare`: the first compare read 0/2, "size differs
  ((960, 1308) vs (480, 654))" — the host's main display had moved from 1x to 2x since the
  control (H-0 saw the same); the control captured again on the copy of the toll's build at 2x
  (6/6) and the Release run compared against it: **2/2 byte-identical**, the SDR card unchanged.
- **Mutants** (Release copies, each `--only <its rows>,Z1` against `tools/proof/work/h3/ctl`), all
  eight **MUTANT PASS** with no other row failing: `range-ignored` (DP, DR), `sdr-via-gr15` (DV,
  DI), `pq-auto-metadata` (DP), `8bit-row-hlg` (DT, DE, HX), `sdr-version-preview-only` (DE),
  `jpeg-not-sdr-version` (DE, HF), `preview-keeps-hlg` (P7), and the re-pinned
  `no-composition-color` (H2, H3, H1m). They ran before TO's log rename, which no mutant row
  reaches.

**Owed.** The `CLAUDE.md` edits (applied by the orchestrator):
- `app/CLAUDE.md`: `OutputTransform.swift` (an HLG project's output values: `DynamicRange`,
  `VideoColour`, `OutputUniforms`, the knee, `compositionColour` — the colour every composition is
  labelled with — and HD-5's two HDR10 blobs); `Compositor+Output.swift` (the output pass,
  `framejob_output_fragment`, after the last layer when the recipe canvas's `dynamic_range` asks);
  `ExportSheetDynamicRange.swift` (an HLG project's Dynamic Range row); `Playback+Scope.swift`'s
  role gaining `seekFinished` and `report` (the H-3 toll); `EditorViewController+Seeing.swift`'s
  gaining View ▸ Show SDR Version; `ScopesPanelView.swift`'s gaining `SDRVersionTagView`;
  `CompositionBuilder.swift`'s gaining the colour through `compositionColour` and
  `BuiltComposition.output`; `Playback.swift`'s gaining `recompose()`.
- `core/CLAUDE.md`'s module map: a row for `dynamic_range.rs` (`DynamicRange`, `HDR_ROWS`,
  `Project::deliverable`, the two refusals), and `export.rs`'s HLG arm (`HLG_ROWS`) replaced by
  the resolver's call.

Both map edits were applied by the orchestrator at merge, with the second review's nit: a comment
at `MediaListFilter.swift`'s sort tooltip naming the harness that matches its opening words;
`make gate` PASS (202 s) after them.

**Residue:** #310 (LG1, G1, S1) as before; #314 (phase8_chrome's stale checks, older than this
phase) fixed in this phase, to close with its commit. The owner's person checks are HDR-1's new step, HDR-2 and HDR-3.

## H-4 — #277, HDR scopes (HD-8, HD-15)

**What landed** (2026-10-20, in the worktree on `hdr`, from `b2c247c`). Spec §11 **HD-15**, written
before the code (`11-decisions/hdr.md`: (a) the scopes read the picture shown; (b) Show SDR
Version, `render_frame {sdr_version}` and an HLG project's JPEG read the SDR version as an SDR
project's — Rec. 709, the 0/50/100 labels, "Rec. 709 · encoded", JSON with no `signal` key —
because the scopes measure the deliverable on screen, the HLG master is one toggle away and the
tap reads the one frame the compositor finished; (c) Show Ungraded keeps the HLG reading; (d) the
signal from the recipe canvas; (e) a 0/1 `signal` uniform choosing two constant sets, not the
weights as uniforms, so the SDR arm is T4-0's arithmetic — amending HD-8's "as uniforms"; (f) the
scale; (g) the BT.2020 targets and the lifted skin line, printed by `python3 -I
tools/proof/work/h4/h4_math.py` (scratch, gitignored) through `hdr_proof.py`'s own `lift`; (h)
the JSON and sentences; (i) nothing new to call or persist), its README row, "amended by HD-15"
on HD-8 with its Amended-by line, and the Lines cells. No format change, no FFI export, no new
tool (92), argument or op. H-4 inherits H-3's Show SDR Version (its recipe key's
`dynamic_range: "sdr"` is what the canvas carries to the tap) and the preview's tag stack
(unchanged: the scopes add no tag). No file was near the cap, so no toll.

- **Metal:** `Waveform.metal`'s waveform and histogram take `signal` at `buffer(1)`, the
  vectorscope at `buffer(2)` beside its zoom; `kLuma2020Weights` and `chromaBins2020` beside the
  Rec. 709 set, whose text is unchanged (every `scopes_proof` and `seeing_proof` anchor still
  occurs once in the shader).
- **Swift:** `ScopeSignal.swift` (new, 137 lines: the init table, `uniform`, `matrixName`,
  `caption(for:)`, `graticule`, `referenceWhitePercent`, `labelGap`, `hlgNits`, `jsonKeys`,
  `scaleJSON`); `WaveformAnalyzer` (`encode`/`trace`/`analyze` take `signal`, default `.sdr`);
  `ScopeTraces` (each trace's `signal`, last and defaulted, so every memberwise call compiles
  unchanged; `chroma(…, signal:)`, `targets(for:)`, `skinLineDegrees(for:)`; the JSON);
  `WaveformTap` (`offer(_:key:signal:)`, the pending frame's own signal); `Compositor.serve`'s one
  offer line passes `ScopeSignal(canvas: recipe?.canvas)`; `ScopeWell.graticule(…, signal:)`
  draws the cd/m² labels and the dashed 75 % line; `ParadeView` and `VectorscopeView` keep the
  last trace's signal; `ScopeSlotView`'s caption follows it; `writeScopes(…, signal:…)` and the
  four HLG sentences; `renderFrame` computes the signal from the project and
  `options.dynamicRange`; one sentence in `render_frame`'s description.
- **Proofs:** `hdr_proof.py` SI, SW, SV, SS, SD, SP and P8 (`hdr_probe.swift`), the `hlg_bars`
  fixture and nine mutants; `scopes_proof.py` S15 and T1's HLG variants; two `scopes_proof`
  anchors re-pinned (`tap-first-kind-only`, `render-ignores-zoom`: the edits unchanged).
- **Documents:** spec §4.2 (the HLG captions, labels and dashed line), §7.5 (the tap's per-frame
  signal; "(the waveform's move at H-4)" replaced), §7.9a (the HLG JSON keys and sentences), the
  spec index's Lines cells; README's HDR (HLG) and scopes bullets; `tools/proof/README.md`'s H-4
  section and the scopes section's S15 and T1; `docs/manual-checks.md` HDR-6, and GRD-17's step
  now reads "near 38 % on the waveform's HLG scale".

**Rules written before the rows they judge** (the spec's step 7, carried into the rows): SW's
oracle is the source codes through the identity (hlg) or the lift (bt709), each pixel's envelope
its codes ±1 as H-2's rows take it, both ways ±1; SV's six fullest bins ±1 of a bar's BT.2020 bin
of the decoded codes, the targets exact; SS the scale recomputed here; SP's readouts within 0.2.
Two rules were set on the first Debug run's evidence and say so in the script: SW's oracle holds
each column's levels holding more than 8 px (`SEAM_PIXELS`), because the render's row 64, where
the ramp's chroma half begins, is off every oracle level of its column (the decoder's chroma
upsampling mixes the halves; SW prints the rows, and every run printed `[64]` alone), every level
still held to the PNG's own pixels ±1; and SW's envelope, because the bt709 ramp's first column
read level 2 beside the nominal oracle's 0/4/6 (the lift's toe spreads one code over several
levels near black). SV's first fixture was wrong, not the product: geq's X on a 4:2:2 chroma
plane is that plane's own, so the chroma bars now switch every 80 px. `analyze(image:)` was left
drawing into the image's own space: SW read the HLG-labelled frames' waveforms at 0 (hlg) and 1
(bt709) levels from the PNGs' own pixels, inside the spec's one level.

**Measured** (Release, 2026-10-20, AC Power, Apple M2 Max). The control: `capture
tools/proof/work/h4/ctl --only H1,H7i,SI,Z1` on the untouched tree's Release build (exit 0; SI
"50 JSON files of 50"), its app kept by `ditto` in `tools/proof/work/h4/ctl-app/`, and `screens.py
--only 04b-preview-scopes --out tools/proof/work/h4/screens-ctl` on the same build (6/6, run with
`RC_PROOF_APP=release` so the compare's build matches).
- `make gate`: **PASS** (206 s; names, typecheck — its four baseline warnings — test and app ran;
  fmt and lint skipped, no Rust changed).
- `hdr_proof.py --control tools/proof/work/h4/ctl` whole: **49/49**. SI: 50 of 50 JSON files
  byte-identical, the text the same. SW: hlg 0 waveform columns off the oracle, 145 seam levels
  left to the PNG (rows off the oracle `[64]`), worst 0 against the PNG, parade 0 off, 212
  chroma-row columns part Rec. 709 from BT.2020 by > 2 levels (CONTROL); bt709 0, 121, `[64]`,
  worst 1, parade 0, 101 (CONTROL). SV: the six fullest bins (101, 224) 20480 px, (224, 120),
  (197, 216), (155, 32), (59, 40), (32, 136) 20352 px each, the bars' BT.2020 bins exactly; the
  skin line 139.916428844002 (wanted 139.9164); 4 bars part Rec. 709 from BT.2020 by ≥ 2 bins
  (CONTROL). SS: the scale as wanted, the vectorscope "Rec. 2020", the five sentences. SD: the
  SDR version's waveform at most 1 level from its PNG's Rec. 709 levels; the JPEG's scopes with
  no `signal`; ungraded `signal` "hlg", 0 columns off, the exposed render's waveform different.
  SP: HLG captions with readouts (0.1, 0.1) against `render_frame`'s (0.146484375,
  0.146484375); Show SDR Version both "Rec. 709 · encoded", (4.3, 1.1) against (4.296875,
  1.123046875) (CONTROL: highlights 4.296875 against the HLG 0.146484375, more than 1 point
  apart); off again and under Show Ungraded the HLG
  captions; an SDR project's "Rec. 709 · encoded". P8: dashed rows [98, 99] at 75 % in the
  waveform's and every parade well's HLG bitmap, none in SDR; six boxes on the plot at ×1 in
  each, none at ×2 (every target a rim tick there, HD-15 (g)); the skin rays 133.3 px apart at
  0.9 of the reach; 4 targets part HLG from SDR by ≥ 4 pt (CONTROL). H-2's and H-3's rows all
  passed in the same run (HS…HX, DT…DX).
- `hdr_proof.py compare tools/proof/work/h4/ctl --only H1,SI,Z1`: **3/3** — H1's 12 SDR scenes
  byte-identical at 0 and 0.5 s with equal picks (the reverse's intermediate digest differs,
  2f713bfc59c23c7c against 0c5a3cc65738520e, printed and unscored as in H-1…H-3), SI 50 of 50.
- **Mutants** (Release copies, each `--only <its rows>,Z1 --control tools/proof/work/h4/ctl`),
  all nine **MUTANT PASS** with no other row failing: `scope-709-in-hlg` (SW, SV),
  `histogram-709-in-hlg` (SW), `ref-line-at-100` (SS, P8), `sdr-version-read-as-hlg` (SD, SP),
  `tap-signal-dropped` (SP), `render-scopes-sdr` (SW, SV, SS), `sdr-json-names-scale` (SI, P8),
  `vectorscope-view-709-targets` (P8), `parade-graticule-sdr` (P8).
- `scopes_proof.py` whole: **27/27** — S12 holds every ×1 SDR count to `28ada7d`'s shader; S15
  9 of 9 cards part Rec. 709 from BT.2020 (CONTROL); T1's worst 4K: parade 0.629 ms, vectorscope
  ×1/×2/×4 0.407/0.362/0.336, histogram 0.667; in HLG vectorscope 0.401/0.326/0.324, histogram
  0.559 (recorded: waveform 0.451, waveform + vectorscope 0.815, HLG waveform 0.452). The
  re-pinned mutants: `tap-first-kind-only` MUTANT PASS (S7, S8; S14 tolerated, failed),
  `render-ignores-zoom` MUTANT PASS (S13).
- `seeing_proof.py` **19/19**; `screens.py --only 04b-preview-scopes --compare
  tools/proof/work/h4/screens-ctl` **4/4 byte-identical**; `recording_probe.py --only catalog`
  **31/31**. No run's log held a `Frame Job: ` line and none printed `DEFAULTS MOVED`.
  `phase8_chrome.py`, `op_argument_proof.py` and `phase9_proof.py` were not run: the SDR chrome
  is byte-identical and no tool's arguments changed.

**Owed.** The `CLAUDE.md` edits (applied by the orchestrator): `app/CLAUDE.md` gains a
`ScopeSignal.swift` entry (what a scope's frame holds: the init from the canvas, the kernels'
uniform, the captions, the scale and the JSON keys); `WaveformAnalyzer.swift` and
`ScopeTraces.swift` gain `signal`; `WaveformTap.swift` gains the per-frame signal;
`ScopeSlotView.swift`'s caption follows the signal.

The review passed with three nits; the CLAUDE.md map edits above were applied by the orchestrator
at merge. **Residue:** #315 (the review's nits 1 and 2: no row reads Show Ungraded and Show SDR
Version on together, HD-15 (c); `ScopeSlotView.show(_:)` takes its caption from any kind's trace);
#310 (LG1, G1, S1) as before, not run here. The owner's person check is HDR-6 (the scopes on real
HDR footage).

## H-6 — #276, linear light (HD-9, HD-16; format 24)

**What landed** (2026-10-20, in the worktree on `hdr`, from `fe551cc`). **H-6 runs before H-5**:
H-5 waits on Canon's own log document, which the owner has not supplied, and H-6 needs nothing H-5
adds, so under HD-11 H-6 took **format 24** and H-5 will take 25. Spec §11 **HD-16**, written
before the code (`11-decisions/hdr.md`: (a) the key, `set_canvas {blending}`, the recipe canvas
and nests sharing it; (b) linear as the project's own transfer as scene light, no OOTF; (c) the
decode once per layer after the effects block, before 7b, behind GR0's flag, the gather filters
encoded; (d) the background, fade colour and shadow colour decoded, matte composites and the
routed dissolve linear; (e) what reads encoded — the adjustment pass and its strength mix in
linear light, the qualifier map, Show Selection's grey, a luma matte, the key, the scopes and
picks; (f) the output pass drawn for every linear project; (g) the Blending popup; (h) what is
unchanged; (i) the costs; (j) the order), its README row, HD-1's and HD-9's "Amended by HD-16"
lines (H-6 before H-5) and HD-14's (the output pass also drawn for a linear project, HD-16 (f)),
the format numbers in HD-9, HD-10 and HD-11, and the Lines cells. No FFI export, no new tool (92)
or op; `set_canvas` gains `blending`. No file was near the cap (largest after: `model.rs` 574 →
584, `AgentCatalog.swift` 572 → 576, `DocumentPane.swift` 515 → 522), so no toll.

- **Core:** `model_canvas.rs` (new, 32: `CanvasBlending`, `is_encoded`), re-exported by
  `model.rs`, whose `Canvas.blending` sits after `output`, written only when `linear`;
  `edit.rs` (`Op::SetCanvas.blending`, its dispatch, the doc row's sentence); `edit_canvas.rs`
  (`set_canvas`'s ninth optional field); `op_table.rs` (`Kind::Blending`, fourteen named types,
  `opt("blending", Blending)`); `op_schema.rs`; `recipe.rs` (the canvas's `"blending":
  "linear"` last); `scope.rs` (`scoped_view` copies it); `format.rs` and the header (24). Tests:
  `canvas_blending.rs` (new, 8) and `schema_v24.rs` (new, 5); `op_table.rs`, `op_schemas.rs`
  (21 kinds) and `op_nullability.rs` (70 optionals) updated.
- **Metal:** `blendDecode`/`blendEncode` beside `gradeDecode`/`gradeEncode`; the layer stage's
  step (7) decode after the effects block; the fade colour; `LayerUniforms.hlgReserved0`,
  `QualifierUniforms.reserved0`, `MatteUniforms.reserved1` and `OutputUniforms`' two reserved
  floats renamed (`linearLight`, and `hlgOutput` in `OutputUniforms`), no size changed; the
  adjust fragment's encode before and decode after, its selection grey decoded; the qualifier
  map's encode; the matte resolve's encode of a linear composite; the output fragment's mode-0
  encode and modes 1/2 from the linear scene light; the "blends in the ENCODED sRGB space,
  deliberately" comment now names HD-16's opt-in.
- **Swift:** `CanvasOutput.swift` (`CanvasBlending` with `menuName`, `RecipeCanvas.blended`);
  `RecipeCanvas.blending` and `CanvasSnapshot.blending` (lenient, `.encoded`; the snapshot file
  over the cap takes wiring only); `Compositor+Uniforms` (`u.linearLight`); `Compositor+Adjustment`
  (`q.linearLight`); `Compositor+Matte` (`resolve(…, linear:)`); `Compositor+Shadow` (the colour
  through `blended` after its lift); `MetalRenderer.background` (through `blended`);
  `OutputTransform.uniforms(for:)` (an encoded canvas's answer is H-3's, `encodedUniforms`; a
  linear canvas always draws a pass); `ReelOps.setCanvas`/`setCanvasRaw`; the MCP handler reads
  `blending` as a string, forwarded unread; `AgentCatalog`'s description ("UI: Document tab ▸
  Canvas ▸ Blending."); `DocumentPane`'s Blending popup row after Dynamic Range.
- **Proofs:** `hdr_proof.py` LT, LH, LG, LA, LS, LM, LD, LB, LF, LR, LE, LO, LU, TL and P9
  (`hdr_probe.swift`), and ten mutants; `tools/proof/README.md`'s H-6 section.
- **Documents:** spec §4.3b, §5.2 (format 24), §6c, §7.3, §7.4, §7.5 (the linear-light entry),
  §7.10 (`model_canvas.rs`), the Lines cells; this file's format numbers and order; README's
  Linear light bullet; `docs/manual-checks.md` LIN-1; the screen catalog's Document inspector.

**Rules written before the rows they judge** (the spec's step 5): SDR rows are formula over
measured bytes (each input drawn alone in the same run) ±2/255; HLG rows ±2/1023 on 16-bit PNGs;
equality rows ±1/255 or ±1/1023; a formula row's encoded CONTROL is held to the encoded formula and
must part from the linear figure by more than the bound (≥ 2 levels for SDR multiply); an equality
row's CONTROL is the encoded render it is compared to. **One deviation from the spec's rows:**
LU's "snapshot_ui reads Encoded, then Linear light" cannot be read — the layout dump carries no
title for an `OptionPopupControl` (it draws its own text) — so LU reads the "Blending" row's popup
as its drawn pixels in the inspector capture, which must differ between encoded and linear while
the Dynamic Range popup's do not (CONTROL), and P9 pins the items' names, "Encoded" and "Linear
light".

**Verification**, 2026-10-20 (`pmset -g ps`: "Now drawing from 'AC Power'"; loadavg about 5–11),
own instances on scratch sockets and homes, each stopped by its pid; no `Frame Job: ` line in any
run and no `DEFAULTS MOVED`:
- **Controls**, on the untouched tree's Release build before the first product edit (a `ditto`
  copy kept in `tools/proof/work/h6/ctl-app/`, gitignored; the runs `RC_PROOF_APP=release`, each
  exit 0): `hdr_proof.py capture tools/proof/work/h6/ctl --only H1,H7i,SI,Z1`; `precision_proof.py
  capture …/precision-ctl` 7/7; `tone_`, `wheels_`, `curves_`, `qualifier_`, `look_`,
  `log_proof.py capture …-ctl` (6, 6, 18, 8, 4 frames; log's control FAILED none);
  `screens.py --only 11-document-inspector --out …/screens-ctl` 6/6.
- In the loop: `cargo test --release` `canvas_blending` 8, `schema_v24` 5, `canvas_output` 7,
  `op_table` 10, `op_schemas` 8, `op_nullability` 2, `recipe` 15, `scope` 38, all passing;
  `make lint` clean; `make typecheck` 0 errors and exactly the 4 baseline warnings; `swift_build.py
  typecheck hdr_probe.swift` exit 0; `spec_index_proof.py` 177/177; `make app-debug` BUILD
  SUCCEEDED; on Debug `hdr_proof.py --only LT,…,LU,P9,Z1` first 12/15 (LT and LH: `set_video
  {opacity: 1}` on a new shape is the identity's refusal, so the inputs at 1 were never drawn —
  `l_patch` now takes "made no change" as applied; LU: the popup's title is not in the dump, as
  above), then 15/15.
- `make gate`: **PASS in 247 s** (names 1 s, typecheck 5 s, fmt 2 s, lint 1 s, test 142 s, app
  96 s).
- `hdr_proof.py --control tools/proof/work/h6/ctl` whole on Release: **63/63** — every H-1…H-4
  row (H1m, H1a, H1s, H1w, H2–H7r, HS–HX, DT–DX, SI–SP) and every H-6 row. LT (SDR, /255):
  white at 0.5 linear 187.3 (oracle 186.8), CONTROL 127.5 (127.0), parted 59.28 levels; at 0.25
  136.5 (136.4), CONTROL 63.8; at 1/3 155.4 (155.6), CONTROL 84.7; multiply 60.8 (60.4), CONTROL
  63.8 (63.7), parted 3.33; the dissolve at p 0.4983 linear (187.2, 187.3, 0.0), CONTROL (127.4,
  127.5, 0.0), linear luminance 0.199 encoded against 0.463 linear (GR-18's 0.199 and 0.464).
  LH (HLG, /1023): white at 0.5 620.4 (620.9), CONTROL 383.4; multiply 152.1 (152.1), CONTROL
  263.2; the dissolve at p 0.4992 parted 117.61 levels. LG: worst |linear − encoded| 0.125/255
  (SDR) and 0.500/1023 (HLG), the grade moving 254 of 256 pixels each (CONTROL). LA: unblurred 469
  pixels at w 0 or 1 (worst 0.249/255) and 43 in the band (worst 0.169/255); blurred 466 and 46
  (0.374, 0.169). LS worst 0.374/255 over 50 levels 0…255. LM m 0.5000, linear 187.3 (186.8),
  CONTROL 127.5. LD the grey shadow 127.5 both; black at 0.5 over white 187.3 (186.8). LB SDR
  encoded 127.5, linear 126.5 (inside ±1/255: the 16-bit PNG reads 32767 and 32511; a 0.25 and a
  1.0 background read identical on Debug, so the 0.5 grey sits on a rounding boundary of the SDR
  frame path), HLG 517.5 both. LF 766.7/1023 both. LR the routed dissolve = the unrouted, linear
  and encoded, to the printed tenth. LE SDR export 187.5 against the render 187.3, HLG 620.1
  against 620.4. LO and LU as wanted ("Canvas" undone). P9 worst `blended` |Δ| 9.2e-8.
- `hdr_proof.py --measure` on Release: **5/5**. TL (TH's 4K SDR project, `prores_422`): encoded
  2.330 ms and linear 2.500 ms mean average per frame (PR-1's budget 8 ms): linear costs +0.170
  ms, beside GR-18's decode/encode and C0's 0.21 ms copy (REASONED). TI, TH and TO as before
  (TH sdr 2.310, hlg 3.270 ms).
- `precision_proof.py compare …/precision-ctl` **11/11** (K1–K6 byte-identical, E1, E2);
  `tone_` 19/19, `wheels_` 23/23, `curves_` 59/59, `qualifier_` 40/40, `log_` 23/23 compares,
  each N0 (or L9) byte-identical to its control; `look_proof.py compare` 28/30, failing G1 and S1
  only (#310, as before), its N0 byte-identical; `matte_proof.py` 46/46; `adjustment_proof.py`
  36/36; `hevc_alpha_proof.py` 43/43; `phase6_proof.py` 168/168, `op_argument_proof.py` 160/160
  and `phase9_proof.py` 234/234, each on an instance of its own from `proof_app.py launch --app
  release`; `recording_probe.py --only catalog` 31/31; `screens.py --only 11-document-inspector
  --out tools/proof/work/h6/screens-release` 6/6 (its inspector dumps hold the Blending row);
  `phase8_chrome.py` 150/150.
- `hdr_proof.py compare tools/proof/work/h6/ctl --only H1,SI,Z1` on Release: **3/3** — H1's 12
  SDR scenes byte-identical at 0 and 0.5 s with equal picks (the reverse's intermediate digest
  differs, 775c01fbad7af266 against 6f5be3c956bca5cc, printed and unscored as in H-1…H-4), SI 50 of
  50 JSON files equal.
- **Mutants** (Release copies, each `--only <its rows>,Z1 --control tools/proof/work/h6/ctl`), all
  ten **MUTANT PASS** with no other row failing: `linear-before-grade` (LG),
  `adjustment-unwrapped` (LA), `hlg-decoded-as-srgb` (LH), `no-output-encode` (LT, LH),
  `background-not-decoded` (LB), `shadow-colour-not-decoded` (LD), `fade-colour-not-decoded`
  (LF), `matte-reads-linear` (LM), `qualifier-map-reads-linear` (LA's blurred case),
  `selection-grey-not-decoded` (LS).
- After this record, `make gate` passed again in 1 s (names re-ran; every other step's inputs
  unchanged).

**Owed.** The `CLAUDE.md` edits (applied by the orchestrator): `core/CLAUDE.md` gains a
`model_canvas.rs` row (`CanvasBlending`, the canvas's blending, format 24) and `Kind::Blending`
among `op_table.rs`'s closed vocabularies; `app/CLAUDE.md`: `CanvasOutput.swift` gains
`CanvasBlending` and `RecipeCanvas.blended`, `DocumentPane.swift`'s Canvas section gains the
Blending row, and the output pass (`Compositor+Output.swift`, `OutputTransform.swift`) is drawn
for every linear project as well as an HLG project's SDR version and PQ. The review passed with one nit, `MetalRenderer.swift`'s output-pass comment, fixed by the
orchestrator at merge with the CLAUDE.md map edits above; `make gate` passed after them.
**Residue:** #310 (LG1,
G1, S1) as before. The owner's person check is LIN-1. Next: H-5 when Canon's document arrives,
then H-7.

## H-5 — #278, Canon Log 2 and Canon Log 3 (HD-10, HD-17; format 25)

**What landed** (2026-10-20, in the worktree on `hdr`, from `13ccb1f`). The designer's first spec
stopped: Canon's own Cinema Gamut paper only plots the triangle. The owner chose on 2026-10-20
"Use ACES, both gamuts (Recommended)": the curves from Canon's *Canon Log Gamma Curves* white
paper (Canon U.S.A., November 1st, 2018; read in place in the main tree, never copied), Cinema
Gamut's chromaticities from the ACES project's Canon CSC (Apache-2.0; no ACES code copied, the
matrices derived by `InputConversions.rgbToXYZ`), and each curve paired with Cinema Gamut or
BT.2020. Spec §11 **HD-17**, written before the code ((a) the sources, (b) the vocabulary and the
popup's "C-Log" rows, (c) the curves, (d) the 0.9 scale, (e) the code domain (1, 0) in both
ranges and its accepted limit, (f) step 0's kinds 10 and 11 in SDR and HLG, (g) table [4]'s test
points and a code's own 10-bit step as its tolerance, (h) format 25, (i) what it amends), its
README row, HD-10's and GR-16's "Amended by HD-17" lines, GR-16's "(format 24)" corrected to 25,
the Concat-rule sources sentence and the Lines cells. No FFI export, no new op or tool (92), no
`InputUniforms` field (112 bytes). No file was near the cap (`InputConversions.swift` 473 → 482,
`MediaColor.swift` 153 → 161, `AgentCatalog+Files.swift` 403 → 404, `format.rs` 531 → 540), so
no toll.

- **Core:** `model_media_color.rs` (`LogCurve::CanonLog2`, `CanonLog3`; `CameraGamut::
  CinemaGamut`; `gamuts()` `[CinemaGamut, Bt2020]` for both); `format.rs` and the header (25).
  Tests: `schema_v25.rs` (new, 4) and `media_color.rs` (six Canon pairings, two refusals).
- **Metal:** kinds `kInputCanonLog2` 10 and `kInputCanonLog3` 11; Canon's constants one per line
  beside V-Log's, `kCanonReflection` 0.9; `canonLog2Inverse`, `canonLog3Inverse`, `inputIsLog`
  and `logInverse`; both log tests (`inputToHLG` and the SDR arm) now `inputIsLog(kind)` and both
  three-way ternaries `logInverse(kind, y)`. Every existing constant line and `inputToHLG`'s
  `hlgOETF(max(inputMatrix(u, r * u.exposure), 0.0))` line unchanged.
- **Swift:** `MediaColor.swift` (`canonLog2`, `canonLog3` displayed "C-Log2", "C-Log3";
  `cinemaGamut` "Cinema Gamut"); `InputConversions.swift` (`InputPrimaries.cinemaGamut`, its
  chromaticities row citing the ACES CSC, two new `codeDomain` lines `return (1, 0)`);
  `Compositor+Input.swift` (`InputUniforms.canonLog2` 10, `canonLog3` 11, `kind(of:)`);
  `MediaPane+CameraLog.swift` (four popup rows after V-Log); `AgentCatalog+Files.swift`
  (`set_media_color`'s sentence).
- **Proofs:** `log_proof.py` LP5, LP6, L19–L22, L2, L8 and L9 extended, seven mutants;
  `log_probe.swift` (LP2's Cinema Gamut, the pass loop run for `p3`, `p5`, `p6`, an item's
  `output`, LP4's kinds 10 and 11); `hdr_probe.swift`'s `name(_:)` arm; `tools/proof/README.md`'s
  H-5 section.
- **Documents:** spec §4.3b, §5.2 (format 25), §6c, §7.5, §7.10, the Lines cells; this file's
  "Log curves", H-5 phase, Phases row and Concat rule; README's two Camera Log bullets;
  `docs/manual-checks.md` GRD-19; the screen catalog's Media tab prose.

**Rules written before the rows they judge** (the spec's Approach 2): LP5/LP6's ramp and seeded
triples ±2e-3 against `log_convert` (SDR) and the shader's `hlgOETF(max(M→2020·R·0.26741, 0))`
(HLG); the makers' codes within the larger of LP3's ±0.005 display bound and the code's own 10-bit
step (code ± 0.5, each signal half-rounded), because Canon Log 2's 90 % code 557 decodes to R
0.90596; the Python encode must reproduce table [4] or the row fails as an instrument failure;
L19/L20 ±1 at 8 bits, the grey rows equal ±1, the cards' centres parting by ≥ 8 levels (the
CONTROL that the matrix moved, computed R 0 against 54); L21 HL's ±1-code envelope ±1/1023 and the
18 % patch at 0.380 ±1/1023; L22 byte-equal.

**Verification**, 2026-10-20 (`pmset -g ps`: "Now drawing from 'AC Power'"), own instances on
scratch sockets and homes, each stopped by its pid; no `Frame Job: ` line in any run and no
`DEFAULTS MOVED`:
- **Controls**, on the untouched tree's Release build (`make app`) before any product edit, each
  `RC_PROOF_APP=release`: `log_proof.py capture tools/proof/work/h5/log-ctl` exit 0 — L9 7 of 7,
  L18 4 of 4 and L22 6 of 6 references captured; on the control FAILED LP1–LP6, L8, L19, L20, L21.
  LP1–LP6 failed because the edited `log_probe.swift` does not build over the untouched
  `app/Sources` (its diagnostics name `InputPrimaries.cinemaGamut`, `CameraGamut.cinemaGamut` —
  LP2's new list entry — and `InputUniforms.canonLog2`/`canonLog3`, the spec's new names only), so
  LP5's and LP6's discrimination is the mutants'; LP1–LP4 are regression rows. L8, L19–L21 failed
  on `unknown variant canon_log2/canon_log3`. L2 passed on the control (not discriminating: the
  untouched tree imports the Canon fixtures with no colour too). `log_thumbs_proof.py capture
  tools/proof/work/h5/thumbs-ctl` exit 1: H0 and T0 FAILED, as they must on any tree after #282
  (they are #282's untouched-tree controls), T4's and T5's references captured. `hdr_proof.py
  capture tools/proof/work/h5/hdr-ctl --only H1,H7i,SI,Z1` exit 0.
- In the loop: `cargo test --release` `media_color` 16, `schema_v25` 4, `schema_v24` 5,
  `schema_v19` 5, all passing; `make lint` clean; `make typecheck` 0 errors and exactly the 4
  baseline warnings; `swift_build.py typecheck` of `log_probe.swift` and `hdr_probe.swift` exit 0;
  `spec_index_proof.py` 177/177; every mutant anchor of `log_proof.py`, `hdr_proof.py` and
  `log_thumbs_proof.py` found once; `make app-debug` BUILD SUCCEEDED; on Debug `log_proof.py
  --only LP1,LP2,LP3,LP4,LP5,LP6,L2,L8,L19,L20,L21,Z1` **12/12**.
- `make gate`: **PASS in 345 s** (names 1 s, typecheck 14 s, fmt 5 s, lint 2 s, test 205 s, app
  116 s).
- `log_proof.py compare tools/proof/work/h5/log-ctl` on Release: **29/29**. L9 (7 fixtures, the
  Canon ramps among them), L18 and L22 (slog3, vlog, applelog, applelog2, green with their Camera
  Log, and slog3 in an HLG project) byte-identical to the control. LP5 worst |Δ| 0.0009752512, LP6
  0.0010080338 (LP3 0.000910759); table [4] reproduced (95/407/575/797/871/1020 and
  128/351/577/908/1020). L19: worst 1 on each ramp and card; patches render [0, 107, 200] (oracle
  the same) under both gamuts; the card's centre [0, 157, 49] under Cinema Gamut and [54, 145, 82]
  (oracle [54, 145, 83]) under BT.2020, apart 54; grey rows apart 0. L20: patches [7, 107, 200]
  under both; centres [0, 158, 50] and [54, 146, 83], apart 54; grey rows apart 0. L21: worst
  0.695 (Canon Log 2) and 0.622 (Canon Log 3) levels on the grey row; the 18 % patch (codes 413 and
  365) renders 0.3801 in both.
- **Mutants** (Release copies, each `--only <its rows>,Z1 --control tools/proof/work/h5/log-ctl`),
  all seven **MUTANT PASS** with no other row failing: `clog2-breakpoint` (LP5, L19),
  `clog3-breakpoint` (LP6, L20), `clog2-video-domain` (LP5, L19), `clog3-video-domain` (LP6, L20),
  `canon-scale-dropped` (LP5, LP6, L19, L20, L21), `cinema-as-2020` (LP2, L19, L20),
  `canon-not-log-in-hlg` (L21).
- `hdr_proof.py --control tools/proof/work/h5/hdr-ctl` whole on Release: **63/63**.
  `hdr_proof.py compare tools/proof/work/h5/hdr-ctl --only H1,SI,Z1`: **3/3** — H1's 12 SDR scenes
  byte-identical with equal picks (the reverse's intermediate digest differs, 29cc0c3ac0d133b6
  against e00e3b2470eba08b, printed and unscored as before), SI 50 of 50 JSON files equal.
- `log_thumbs_proof.py compare tools/proof/work/h5/thumbs-ctl` on Release: first **11/12**. TH
  FAILED only on its control file: `thumbs-ctl/h0.json` did not hold, because H0 is #282's
  untouched-tree control and cannot hold on a tree past #282. The review's fix: under `compare DIR`
  TH scores its own figures and prints DIR's H0 state as a note naming #282's held control
  (`tools/proof/work/i282/ctl/h0.json`); a plain run and a mutant keep the gate. Re-run: **12/12**.
  TH: HLG and PQ `transfer` markers, worst 1 level each (bound 4); `b2020_709` and `p3_709` flat,
  worst 1 each (bound 5). T1–T9, TP and Z1 passed (T4 byte-equal to the control, T1 worst 1, 1, 1,
  1 and 2).
- `op_argument_proof.py` **160/160** and `phase9_proof.py` **235/235** on an instance of their own
  (`proof_app.py launch --app release`); `recording_probe.py --only catalog` **31/31**.
- After this record, `make gate` passed again in 2 s (names re-ran; every other step's inputs
  unchanged).

**Owed.** The `CLAUDE.md` edit (applied by the orchestrator): `core/CLAUDE.md`'s
`model_media_color.rs` entry says format 25 adds `canon_log2`, `canon_log3` and `cinema_gamut`.
The second review passed; the `core/CLAUDE.md` edit above was applied by the orchestrator at
merge and `make gate` passed after it.

**Residue:** #278 stays open for detection from the makers' metadata. #310 (LG1, G1, S1)
as before, not run here. The owner's person check is GRD-19. Next: H-7.

## H-7 — the close

**What landed** (2026-10-20, in the worktree on `hdr`, from `105ac08`). `designs/adr/hdr.md`.
This road map `git mv`'d to `archive/hdr.md`, with its `archive/INDEX.md` row. Every
`designs/hdr.md` citation outside `archive/` now points at the ADR or here: §11 `hdr.md`'s first
paragraph in the closed form, its line naming "The owner's choices" and HD-4's "copied into"
line; `designs/adr/grading-3.md`'s B96 line; `docs/manual-checks.md`'s HDR section intro, now in
the past tense; and `tools/proof/README.md`'s six record lines (H-1, H-2, H-3, H-4, H-6, H-5).
`designs/adr/grading-3.md` gained "built by" notes on GR-18 and GR-19 and on its #276, #277,
#278 and #281 lines. Spec §1's non-goals sentence now names the HDR road map's work in place of
"deferred, GR-18 #276, GR-19 #277", and the `11-decisions/README.md` row drops "in progress".
The spec indexes' Lines cells follow. Every HDR person check (HDR-1, HDR-2, HDR-3, HDR-4, HDR-6,
LIN-1, GRD-16's and GRD-17's HLG steps, GRD-19) was read against the code — the Colour row's
words (`CanvasOutput.swift`), the undo names Dynamic Range, Blending and PQ Peak, Use File's, the
"SDR Version" tag, `HDR_ROWS` and the popup's HDR (HLG) · HDR10 (PQ) · SDR version, the scope
captions (`ScopeSignal.swift`), the C-Log rows, the LUT warning — and each agreed, so no row
changed. No product, core, Swift, shader or proof-script file changed.

**Verification** (2026-10-20, `pmset -g ps`: "Now drawing from 'AC Power'"):
- `python3 tools/proof/spec_index_proof.py`: exit 0, 177/177.
- `python3 tools/proof/name_residue.py`: exit 0, no output.
- `git grep -n "designs/hdr\.md" -- . ':!archive'`: prints nothing.
- `git status --porcelain`: `RM designs/hdr.md -> archive/hdr.md` (the rename staged, this
  section unstaged on top of it).
- `make gate`: PASS in 84 s (names 1 s, test 83 s; typecheck, fmt, lint and app skipped as
  byte-identical to their last pass); the test log has 136 `test result: ok` lines and no
  FAILED, and `spec_index_proof.py` 177/177 among its steps. This line was written after the gate
  passed (`archive/` is outside every gate step's inputs, `gate.py`'s `EXCLUDED`).
- No mutants: the phase adds no product decision.

**The issues.** Filed, each `ai-drafted` and `low-priority`: **#316**, the PQ peak not read from a
WebM/Matroska Colour element (`container_header.rs`'s `video_settings` reads 0x55B1, 0x55B9,
0x55BA and 0x55BB only, skipping MaxCLL 0x55BC and MasteringMetadata 0x55D0) or from AV1's HDR
metadata OBUs ("Not established: Other containers", REASONED from the code); **#317**, ProRes 4444
with alpha from an HLG project unmeasured (DT and DP read its tags and side data, no row its
alpha; "Not established"). Reviewed against the tree and the tracker (read-only): #281, #277 and
#276 are closed as completed (built); #313 and #314 closed (instrument, fixed in H-2 and H-3);
#278, #310, #311, #312, #315 and #274 are open and hold what they hold. Not filed, each decided:
the XDR panel and an SDR external display (HDR-1's steps 3–4); the HLG project's 4K cost
(measured: TH, TO, TL); VideoToolbox's HEVC Main 10 HLG/PQ encode speed (the SDR `hevc_10bit`
encoder with tags and two blobs; no decision waits on it); BT.2408's constants (read in H-3,
HD-14 (a)); other editors (general knowledge); Dolby Vision in iPhone sources (REASONED not;
HDR-2 watches for a badge); "Found while reading" 1–4 (settled in H-1, H-1, H-2, H-2). #274 was
not measured: no owner HDR or log clip reached the road map (HD-1).

**Owed.** A comment on #278 saying the road map closed into `designs/adr/hdr.md`, with the
original at `archive/hdr.md`, since its H-0 comment names `designs/hdr.md` (the orchestrator's).
The root `CLAUDE.md`'s ADR list names `hdr` (the orchestrator applies it). The owner's person
checks: HDR-1, HDR-2, HDR-3, HDR-4, HDR-6, LIN-1, GRD-16's and GRD-17's HLG steps, GRD-19.
