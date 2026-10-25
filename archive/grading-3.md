# Road map "grading-3" — colour grading, tier 3: honest sources, HDR→SDR, camera log

**Opened 2026-10-11** (T3-0, in the worktree `~/devel/reelcut-grading3` on branch `grading-3`,
from `8707ada`, merged into main after its gate). The design brief this road map answers is
`~/.claude/litecode/reelcut/grading-tier3/I-grading-tier3.md` (2026-10-11, tree `8707ada`), with
the owner's answers beside it in `…/grading-tier3/answers.md`; both live outside the repo, so
everything a later phase needs from them is written here. Where the brief and this file differ,
this file wins. Tier 1's road map is closed (`designs/adr/grading.md`, `archive/grading.md`,
spec §11 GR-1..GR-9 in `designs/spec/11-decisions/grading.md`), and so is tier 2's
(`designs/adr/grading-2.md`, `archive/grading-2.md`, GR-10..GR-14 in
`designs/spec/11-decisions/grading-2.md`). Tier 3's decisions are GR-15 onwards, in
`designs/spec/11-decisions/grading-3.md`.

## Goal

Build tier 3 of colour grading as the owner chose it: **honest sources and Reelcut's own
HDR→SDR conversion** (T3-1, closing a measured defect on ordinary iPhone footage), then **camera
log footage** (T3-2, #264). Each is a phase that lands whole on main, judged by its own proofs on
synthetic fixtures; the owner's real clips become manual checks later. Linear-light blending
(GR-18) and the HDR timeline (GR-19) are filed as issues at the close with their designs; a
wide-gamut working space for SDR projects is closed as not wanted (GR-20). There is no verdict
phase.

## The owner's choices

**2026-10-11**, verbatim (`answers.md`):

> Owner, 2026-10-11, on I-grading-tier3.md:
> - Choice 1 (scope): "HDR fix + log (Recommended)" — T3-1 honest sources + Reelcut's own HDR→SDR at step 0; T3-2 log footage. Linear-light blending (opt-in switch, later) and the HDR timeline filed as issues; wide gamut for SDR projects closed as not wanted.
> - Choices 2–6, 10: "All as recommended" — own ITU-based HDR→SDR keeping Apple's measured brightness; camera log on the MEDIA (set_media_color, the 91st tool); built-in curves + user .cube via Use LUT…, no bundled maker LUTs; Apple Log auto-detected with a None override, S-Log3/V-Log by hand; Show Ungraded keeps the log conversion; tier-2 workflow (worktree outside repo, gate → commit → ff-merge per phase).
> - Footage: "Synthetic now (Recommended)" — build and prove on synthetic fixtures; the owner's real Apple Log / HDR clips later become a manual check.

The choices therefore read:

1. **(a)** Two phases now: honest sources with Reelcut's own HDR→SDR, then log footage; the rest
   filed or closed (choices 7–9).
2. **(a)** Reelcut's own conversion from the ITU recommendations, tuned so iPhone footage keeps
   the brightness Apple's conversion gives it today (GR-15).
3. **(a)** The camera-log setting lives on the media: one per file, `set_media_color`, the
   ninety-first product tool (GR-16).
4. **(a)** Built-in conversions from each maker's published curve and gamut plus Reelcut's
   display transform; Use LUT… takes an imported `.cube` as the conversion; no maker LUT bundled.
5. **(a)** Apple Log recognised by its label; S-Log3 (S-Gamut3.Cine, S-Gamut3) and V-Log (V-Gamut)
   by hand; any other curve its own issue.
6. **Yes**: Apple Log converted from import, the popup's None shows the log picture, and Show
   Ungraded keeps the conversion.
7. **(a)** Linear-light blending later, filed; when built, an opt-in project switch, off for
   every project (GR-18).
8. **(a)** The HDR timeline later, filed with its design (GR-19).
9. **(a)** A wide-gamut working space for SDR projects closed as not wanted (GR-20).
10. **Yes**: tier 2's arrangement — one worktree outside the repo, each phase merged into main
    when its gate passes, main's format numbers, no verdict phase (GR-17).

**Footage**: synthetic now. Every proof runs on fixtures a script makes; the owner's real Apple
Log, iPhone HDR and camera-log clips (choice 11, "Test media" below) become manual checks.

## Tier 3 as answered

- **#264** (log) asks whether AVFoundation converts log footage (Apple Log, Sony S-Log, Panasonic
  V-Log) before the compositor sees it, and whether a camera maker's log-to-Rec. 709 `.cube` then
  looks right. Its "done when" is GR8's T0 method run on a real log clip, plus a maker's LUT
  against ffmpeg's `lut3d`. Tier 2's comment on it said an input LUT is "its own step BEFORE 4c,
  with its own texture slot", and that a qualifier on a per-clip input LUT would read converted
  values. **Answered by T3-2** (GR-16): log is a setting on the media, converted at step 0 —
  earlier than tier 2 said (below, "The stage order").
- **#256** (tier 3) asks for HDR sources above 1.0, an EDR preview and HDR export flags; wide
  gamut carried rather than clamped; linear-light blending "as an option or as the default, with
  its effect on today's pixels measured". Done when each has a §11 decision and a measured proof,
  **or is closed by the owner**. Tier 2's comment: every tier-2 stage is defined on ENCODED values;
  the 0…1 domain belongs to the stage; the scopes are a Rec. 709 matrix. #257's comment: the
  reverse carries its source's labels (PR-7), and a deep still enters as encoded sRGB (PR-6).
  **Answered by GR-15** (HDR sources converted honestly to SDR, T3-1), **GR-18** and **GR-19**
  (deferred, filed at T3-3 with their designs) and **GR-20** (closed).
- **What the records said, and why both were right.** PR-2 (and spec §7.5): "HDR stays
  tone-mapped to SDR: `supportsHDRSourceFrames` stays false". GR-8, from GR6a's T0 through
  `render_frame`: "HLG and PQ draw the grey ramp UNCHANGED (no transfer conversion)". The brief
  measured why they disagree: each is true of a different path (next section). Both now carry
  an "Amended by GR-15" line, and GR-8 an "Amended by GR-16" line on its accepted risk; tier 2's
  ADR line "an input LUT would be its own step before 4c" carries an "Amended by GR-16" line.

## How it fits the tree

### What happens to an HDR, wide-gamut or log source today (the brief's §2, measured)

The brief's scratch instrument reproduces the app's own AVFoundation calls: a custom compositor,
`64RGBAHalf` sources and output, no colour properties on the video composition, the export's
`AVAssetReaderVideoCompositionOutput`, `render_frame`'s `AVAssetImageGenerator`, and an `AVPlayer`
with an item video output. The fixture is a 10-bit ProRes 422 HQ ramp (a grey ramp over a chroma
ramp), re-tagged by stream copy in the ProRes headers and the container's `colr` atom (GR6a's T0
method); the grey column at signal 0.5 is the probe. The value the compositor receives, by path:

| Source | Export reader, 1st frame of a clip | Export reader, later frames | Preview (`AVPlayer`), after the first frame | `render_frame` / Save Frame / GIF / APNG / eyedropper / thumbnails (`AVAssetImageGenerator`), every frame |
|---|---|---|---|---|
| BT.709 or untagged | 0.5000 | 0.5000 | 0.5000 | 0.5000 |
| HLG (BT.2020) | **0.5000, unconverted** | 0.3843, converted to SDR | 0.3843 | **0.5000, unconverted** |
| PQ (BT.2020) | **0.5000** | 0.7192 | — | **0.5000** |
| BT.2020 primaries with the BT.709 transfer | 0.2568 | 0.2568 | — | 0.2568 |
| Apple Log (labelled) | 0.5000 | 0.5000 | — | 0.5000 |

- **Within a sequence** (BT.709, HLG, BT.709, five frames each, one reader) the HLG segment's
  FIRST frame arrived unconverted (0.5000) and its next four converted (0.3843); the same for HEVC
  Main 10 HLG. The unconverted frame is the first a decoder delivers, wherever the clip starts.
- **The labels lie on the unconverted frames**: the generator's HLG frame says BT.709 primaries,
  BT.709 transfer and the BT.2020 matrix while holding HLG values.
- **AVFoundation's conversion clips colour**: HLG's chroma patch (0.42, 0.84, 1.17 native)
  arrived as (0.00, 0.73, 1.00).
- **The player**: the paused first frame and the first frame on Play arrived unconverted; the
  rest of the play and a seek on a running decoder converted.
- **For a user** (REASONED from those paths; GR6a's T0 measured the same through the real app's
  `render_frame`): the preview and an export of iPhone HDR look right except one washed-out frame
  where each HDR clip starts in an export; everything drawn through `Exporter.renderFrame` —
  `render_frame`, File ▸ Save Frame…, GIF and APNG, the Look gallery's thumbnails, the chroma-key
  eyedropper, Pick from Canvas — shows HDR unconverted, always, so the eyedropper picks a green
  the preview does not key on. A parity defect (spec §7.3) on ordinary iPhone footage. A BT.2020
  file with the BT.709 transfer is darkened on every path (0.5 → 0.2568).

**What fixes it: `canConformColorOfSourceFrames`** (macOS 12+), which tells AVFoundation the
compositor converts colour itself. With it and `supportsHDRSourceFrames` both true, every frame
on every path arrived **native and honestly labelled** (HLG 0.5000 labelled HLG, PQ 0.5000
labelled PQ, Apple Log labelled Apple Log, the BT.2020/709 file 0.5000); the BT.709 | HLG | BT.709
sequence arrived native on all fifteen frames with the right label on each segment; the same held
with the 10-bit biplanar `x422` format. `supportsHDRSourceFrames` alone moves the problem: the
BT.709 frames came out 0.4458, except the first. **SDR sources are unchanged by the switch, byte
for byte**: a full-frame digest of the source buffer was identical with and without it for BT.709
and untagged ProRes, BT.709 and untagged H.264, a matrix-only-tagged HEVC 8-bit 1080p and H.264
1080p (the precision spike's media), and the recording proof's `short-video.mov`.

**Log today**: a ProRes file rewritten through `AVAssetWriter` with the Apple Log
format-description key reads back with `LogTransferFunction = com.apple.rec2020.apple-log`
(stored in a `logs` atom; `colr` BT.2020 primaries, transfer "unspecified" (2), BT.2020 matrix;
ffprobe reads `bt2020nc/unknown/bt2020`) and arrives unconverted on every path, so it shows flat
and grey, as log should. S-Log3 and V-Log have no label AVFoundation knows and arrive as their
`colr` says. Today's only tool is GR-8's LUT as a look at 4d, after every correction — backwards.

### The stage order: step 0 (the brief's §3)

Tier 2 put an input LUT "before 4c". **It has to go earlier, before step 3**: step 3
(`layerSample`) already runs the chroma key and Color's four on the sample, and both must see
converted values — a green screen keyed in log is the wrong green. So the conversion is a
**step 0, per source**:

| Step | What | Note |
|---|---|---|
| **0** | **input conversion** (new): a source pass that converts a source texture once per frame into a working `rgba16Float` texture, which the layer stage then samples as its source | Only for a source whose conversion is not the identity: in T3-1 an HLG, PQ or BT.2020-primaries/BT.709-transfer source (GR-15, chosen by the buffer's transfer label); in T3-2 also a media whose `color` setting converts (GR-16). Every other source is sampled exactly as today, so it renders byte-identical by construction. |
| 1–2 | zoom remap, pixelate | unchanged; they move coordinates in the converted texture |
| 3 | sample: chroma key, Color's four | now on converted values |
| 4–4b | blur, sharpen, obscure | each tap reads the converted texture: no per-tap conversion |
| 4c–4c.2 | tone, wheels, curves | unchanged, on encoded Rec. 709 |
| 4d | the look or a creative LUT | unchanged; "correct first, then the look" (GR-7) now holds for log too |
| 7 (adjustment pass) | the qualifier | reads the composited destination, so it selects converted values |

**Why a pass and not arithmetic inside the sample**: measured in the brief's scratch shader, a
conversion inside a 25-tap blur cost +3.06 ms at 4K (once per tap), against +0.001–0.009 ms once
per pixel. The pass costs about one copy (0.21 ms at 4K, measured) and one pooled `rgba16Float`
target per converted source (66.4 MB at 4K, PR-1's figure). A phase can draw the conversion inside
the sample when a layer has no multi-tap effect: an optimisation the phase measures, not a design
change. The pass has its own small uniform block and binds an input LUT itself, so
`LayerUniforms` stays 128 floats and no layer-stage texture slot is taken: `texture(2)` stays the
look, `texture(3)` the curve strip, and #124's `texture(4)` is untouched.

### The HDR conversion (GR-15, T3-1)

- Reelcut converts HLG and PQ to SDR Rec. 709 in step 0, the same on every path: the BT.2100 HLG
  inverse OETF and system gamma, or the ST 2084 EOTF; then the BT.2020 → BT.709 matrix; then a
  shoulder; then the encode. A BT.2020-primaries/BT.709-transfer source takes the matrix between
  its transfer's decode and the encode.
- **The anchor** (choice 2a): Apple's measured brightness, so a preview hardly moves. Apple's
  points, measured: HLG 0.25 / 0.5 / 0.75 / 1.0 → 0.215 / 0.384 / 0.604 / 1.0 (reference white,
  75 % signal, near 60 %). PQ 0.5 (about 92 nits) → 0.719; PQ 0.75 (about 980 nits) → 1.0,
  clipped. Highlights roll off; colours outside Rec. 709 are compressed by the shoulder, not
  clipped (a visible improvement on saturated HLG colours). The proof records the distance to
  Apple's conversion on a ramp and holds it to a bound written before measuring (H3).
- **A log or unrecognised transfer stays the identity in T3-1**: Apple Log carries BT.2020
  primaries, so a selector on primaries alone would matrix and shoulder log values; GR-15 selects
  by transfer, and T3-1 leaves Apple Log "unchanged (still log)" until GR-16 assigns its
  conversion.
- **How common**: very. Every iPhone since the 12 records HLG (Dolby Vision 8.4) by default.
  T3-1's visible effect is mostly in the places that were wrong:

| Who sees what | T3-1 | T3-2 |
|---|---|---|
| iPhone HDR footage in the preview and an export | about the same (choice 2a), with no first-frame flash; saturated colours compressed, not clipped | — |
| The same in `render_frame`, Save Frame, GIF, APNG, the Look gallery, the eyedropper, Pick from Canvas | now right (was flat and grey) | — |
| A BT.2020 / BT.709-transfer file | no longer darkened | — |
| Apple Log footage | unchanged (still log) | normal video on import; popup to None to see log |
| S-Log3 / V-Log | not darkened if so tagged | normal video once the popup is set |
| Every SDR project | byte-identical | byte-identical (no key, no input pass) |

### Log footage (GR-16, T3-2)

- **Recognition**: Apple Log by its label (`kCMFormatDescriptionExtension_LogTransferFunction` =
  `com.apple.rec2020.apple-log`, the SDK's `kCMFormatDescriptionLogTransferFunction_AppleLog`),
  read from the track's format description when `MediaImporter.probe` runs (measured readable on a
  synthetic file). The SDK also defines Apple Log 2 (`kCVImageBufferLogTransferFunction_AppleLog2`,
  macOS 26), whose header sets no primaries or transfer and the BT.2020 matrix: a different gamut,
  and an issue at T3-3 (no published curve read). S-Log3 and V-Log by hand, from the Media
  inspector's Camera Log popup or the tool; Sony's XAVC `rtmd` and Panasonic's own fields are not
  read by AVFoundation and are out of scope.
- **`media.color {log, gamut, lut, detected}`**, written only when set, or when auto-detected
  (`log: "apple_log"`, `detected: true`, so the inspector can say "(from the file)"). A reverse
  follows its media, whatever labels its intermediate keeps. A media's setting supersedes GR-15's
  label choice for that media.
- **The conversion, four pieces** (three published, one Reelcut's):
  1. the log curve, inverted to scene-linear light, from each maker's document: Apple's *Apple Log
     Profile* white paper (Apple Developer downloads, as the SDK header says); Sony's technical
     summary for S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3; Panasonic's V-Log/V-Gamut reference
     manual — each a closed formula (a linear toe, then a log segment);
  2. the camera gamut → Rec. 709 matrix, from each document's primaries and white point by the
     standard RGB→XYZ→RGB derivation (Apple Log uses BT.2020 primaries);
  3. the BT.709 inverse EOTF / sRGB encode at the end (IEC 61966-2-1, already in the tree);
  4. Reelcut's own display transform from scene light to SDR: GR-15's shoulder, its exposure
     anchored so 18 % grey lands at a sensible mid-grey — a look choice, written into GR-16 with
     its numbers by T3-2.
- **Why no maker LUT is bundled**: their redistribution terms were not found (a web search turned
  up only third-party packs, some forbidding re-hosting); Apple's Apple Log LUT is behind the
  developer login; a 33³ lattice is up to 3 levels off an analytic curve (tier 1's C3); and the
  Concat rule forbids Concat's tables in any case. T3-2 checks each document's own terms before
  implementing from it and records them in GR-16.
- **Use LUT…**: the Camera Log popup's last item assigns a `.cube` media (GR-8's parser,
  unchanged) as the media's input conversion, `media.color.lut`, sampled once per pixel in the
  input pass (measured +0.009 ms at 4K for a 33³ sample).
- **With a look or a LUT at 4d**: a user who already applies a camera LUT as a look would convert
  twice once Camera Log is set, so the Look section says so when the clip's media converts and
  the look is a LUT — a warning only, since a creative LUT there is legitimate. Show Ungraded
  removes the 4d look, not the step-0 conversion (choice 6). Paste Attributes carries nothing new.

## The standard recipe, file by file, and the tolls

The ledger is `wc -l app/Sources/*.swift core/src/*.rs graphic/src/*.rs | sort -rn`, here at
`8707ada`. The cap is ~600 lines, new files 400, and frozen files (`EditorViewController.swift`,
`TimelineView.swift`, `PreviewCanvasView.swift`, `AgentServer.swift`) take wiring only. Size is per
file only (root `CLAUDE.md`): nothing here is a budget on a feature or a phase.

### Tolls (T3-0, each a pure move gated alone)

| File | Lines at `8707ada` | Why it is touched | The move |
|---|---|---|---|
| `Compositor.swift` | 723 | T3-1: `canConformColorOfSourceFrames`, `supportsHDRSourceFrames`, the input pass's call | Its named seam, `DestinationPass` out whole. **Paid in T3-0**: 723 → 658, `DestinationPass.swift` 66 (below). Its next named seam is `MetalRenderer`'s `// MARK: - Sources` → `Compositor+Sources.swift`, where step 0 meets a track's buffer (`designs/adr/app-file-history.md`). |
| `AgentServer+Render.swift` | 595 | only if `render_frame` changes (it should not: parity comes by construction) | Its named seam (`// MARK: - Export` → `AgentServer+Export.swift`), only if touched |
| `ProjectSnapshot.swift` | 1,523 | T3-2: `MediaSnapshot` gains `color` | none: the field lands in `MediaSnapshot.swift` (82), already the media group's own file |

Not tolls: `CompositionBuilder.swift` (536) gains at most the composition's explicit BT.709 colour
properties; `ExporterWriter+Settings.swift` (427) is untouched until the HDR timeline (its
output-tag comment is corrected in T3-1); `MediaImporter.swift` (593) is at the edge, so Apple Log
detection goes into `MediaImporter+Probe.swift` or a new `MediaImporter+Color.swift`;
`ReelCore.swift` (989) is untouched (no FFI export).

### Core (T3-2 only; T3-1 has no core change)

| Step | Files | Note |
|---|---|---|
| Model | `model.rs` (541): `Media.color: Option<MediaColor>` with a serde default; new `model_color.rs` (`MediaColor {log, gamut, lut, detected}`, `LogCurve {apple_log, slog3, vlog}`, `CameraGamut`) re-exported | written only when set |
| Checks | new `color_check.rs`: the `log` and `gamut` pairings (S-Log3 takes S-Gamut3.Cine or S-Gamut3; V-Log takes V-Gamut; Apple Log only BT.2020); `lut` names a `lut` media; refused on an audio, image or LUT media, each in its own sentence | refused, not clamped |
| Op | `edit.rs` row and module doc, `op_table.rs` args: **`set_media_color {media, color}`** (`color: null` clears); `remove_media` of a LUT used as an input clears it (GR-8's choice 6 rule) | the parity check sees one new op, so one new tool |
| Recipe | `recipe_layer.rs` (145): an `input` key on a video layer (the media's conversion, or absent); the recipe stays pure | Swift's lenient decoder: always write the key (tier 2's precedent) |
| Format | `format.rs` (484) + the header: main's next (**19** at T3-0); `core/tests/schema_v19.rs` | optional key, no migration (owner: no real use yet) |
| Tests | new `core/tests/media_color.rs`: each refusal, the pairings, `remove_media`, copy/paste carries it (matched by media), consolidate and relink keep it, the recipe's `input` | |

### Swift and Metal

| Step | Files | Note |
|---|---|---|
| Source honesty (T3-1) | `Compositor.swift`: `canConformColorOfSourceFrames` and `supportsHDRSourceFrames` true; `CompositionBuilder.swift`: the composition's colour properties set to BT.709 explicitly | the measured switch; SDR digests identical |
| Input pass (T3-1) | new `Compositor+Input.swift` (the pass, its target pool, the choice of conversion from the buffer's attachments in T3-1 and from the recipe's `input` in T3-2); new `InputConversions.swift` (each curve's constants, the matrices, the shoulder's numbers, mirrored into the shader); `Compositor.metal`: `reelcut_input_fragment` and its functions | its own uniform block; `LayerUniforms` stays 128 |
| Reverse | `ReverseRenderer.swift` (1,221): none. Its intermediate keeps the labels (PR-7), and in T3-2 the media's setting governs | its class doc's PR-2 sentence corrected in T3-1 |
| Import (T3-2) | Apple Log detection at probe; `MediaSnapshot.swift` `color` | |
| Inspector (T3-2) | the Media tab's inspector (`MediaPane.swift`, 497, or the inspector's Media pane): a **Camera Log** section (popup: None · Apple Log · S-Log3 / S-Gamut3.Cine · S-Log3 / S-Gamut3 · V-Log / V-Gamut · Use LUT…), with "(from the file)" when detected; one undo step, "Camera Log" | new `MediaColorSection.swift` if the pane is near the cap |
| Look warning (T3-2) | `VideoPane+Look.swift`: a line when the clip's media has a conversion and the look is a LUT | |
| MCP (T3-2) | new `AgentServer+MediaColor.swift` and a catalog row: **`set_media_color`**, the ninety-first product tool (root `CLAUDE.md`'s "ninety" becomes "ninety-one"); `get_project` shows `media[].color` by itself | the gate, parity and the menu inventory |
| Patches | `TypedPatches.swift` (329) / `ReelOps.swift`: the typed builder | |

### Documents (each phase's own)

Spec §5.2 (`media.color`, the format), §6 (`set_media_color`), §7.3 (the recipe's `input`), §7.5
(step 0, the source attributes, PR-2's corrected sentence — T3-1), §7.7 (Apple Log detection),
§7.9a (the tool), §4.3b (the Camera Log section); the spec index's Lines cells; `app/CLAUDE.md`
and `core/CLAUDE.md` map entries; the README's grading and import bullets;
`docs/manual-checks.md` rows (GRD-16…GRD-18); the screen catalog (a new Media-inspector screen
with Camera Log).

## Spec §11: the plan

**Stands, and nothing here re-litigates it:** R5-1; PR-1 (encoded values in [0, 1]: step 0
converts INTO that range, so it holds); PR-3…PR-8 (PR-5's frozen references among them); MT-3;
GR-1 (tier 3 deferred as issues: this takes it up); GR-3 (blending stays encoded); GR-10…GR-14.

**Amended, each by an "Amended by" line under the original, never rewriting it:**
- **PR-2** by GR-15: "HDR stays tone-mapped to SDR" is true of the export reader's later frames
  and the player; the first decoded frame and the generator are unconverted. The decision "HDR
  reaches the output as SDR" stands; only who converts changes. §7.5's twin sentence and the three
  code comments that repeat PR-2 wait for T3-1.
- **GR-8** by GR-15 (T0's "HLG and PQ … UNCHANGED" is true of the generator and a decoder's first
  frame) and by GR-16 (its accepted risk shrinks: log is converted at step 0, a LUT can be the
  input conversion, and the Look section warns).
- Tier 2's ADR line "an input LUT would be its own step before 4c" by GR-16 (`designs/adr/` is
  not §11, but the line is a record a later reader trusts).

**New, in `designs/spec/11-decisions/grading-3.md`**, each with its README row and the Lines
cells, all recorded in T3-0 before any tier-3 code:
- **GR-15 — Honest sources**: the switch, step 0 chosen by the buffer's transfer label (a log or
  unrecognised transfer the identity until GR-16), the HDR conversion and its anchor, what does not
  change, the defect it closes, the amendments. T3-1 adds the shoulder's constants and H3's bound
  before its code.
- **GR-16 — Camera log**: `media.color`, `set_media_color`, recognition, the conversion and its
  sources, step 0 before the chroma key, Show Ungraded's exemption, the refusals, the look warning,
  what is not in. T3-2 adds the sources' terms, the constants and the format number before its
  code.
- **GR-17 — Tier 3's working arrangement** (below).
- **GR-18 — Linear-light blending deferred**, with its design notes.
- **GR-19 — The HDR timeline deferred**, with its design.
- **GR-20 — A wide-gamut working space for SDR projects closed.**

## Where the work happens (GR-17)

- One worktree, `~/devel/reelcut-grading3` on branch `grading-3`, outside the repo folder and
  outside `.claude/worktrees/`. Each phase: start from main, write the code, `make gate` in the
  worktree; when it passes, commit and merge into main (a fast-forward when main has not moved),
  then start the next phase from main. Nothing is built in or switched in the main tree, which
  other sessions use.
- Per worktree: `core/target/`, `build/`, `tools/proof/work/`, the generated project. Shared: the
  git objects, and the Debug and Release apps' identities and defaults domains (V-5) — harmless,
  since proofs run under scratch homes and never move defaults.
- **Format numbers**: T3-2 takes main's next number when its code is written (19 at T3-0) and
  renumbers before its merge if main moved first. T3-1 has no format change.
- **No verdict phase**: each phase is kept when its proofs pass.
- **Fixtures**: synthetic now; the owner's real clips later as manual checks, read from a path he
  gives in an environment variable, never copied into the repo.

## Phases

Each phase is one implement-review cycle, gated and merged into main alone, ending with the root
`CLAUDE.md`'s "Verification": targeted tests in the loop, `make gate` once when the code is
complete, the phase's proof recorded whole on Release, mutants about one per new decision.

| Phase | What lands | Its proof holds |
|---|---|---|
| T3-0 | This road map; `11-decisions/grading-3.md` with GR-15…GR-20, its README rows and Lines cells; the Amended-by lines on PR-2, GR-8 and three ADRs; the toll: `DestinationPass` out of `Compositor.swift` | Renders byte-identical before and after; `make test` unchanged; the Debug catalog equal. No mutants: a pure move adds no decision. |
| T3-1 | **Honest sources and Reelcut's HDR→SDR** (GR-15): the two compositor properties; the composition's BT.709 colour; step 0's pass, chosen from each buffer's transfer label; the HLG, PQ and BT.2020 conversions; no format change | H1–H6, TC, TI (below) |
| T3-2 | GR-16's numbers first, then **log footage** (#264): `media.color`, Apple Log detected at import, S-Log3 and V-Log by hand, an input LUT; the Camera Log section; `set_media_color` (op, tool 91); the recipe's `input` key; main's next format | L1–L9 (below) |
| T3-3 | **The close**: the ADR, the archive, the issues | — |

### T3-1 — honest sources and Reelcut's HDR→SDR (GR-15)

- **Lands**: `canConformColorOfSourceFrames` and `supportsHDRSourceFrames` true in `Compositor`;
  the composition's BT.709 colour in `CompositionBuilder`; step 0's pass, its target pool and its
  choice from each buffer's transfer label (`Compositor+Input.swift`, `InputConversions.swift`,
  `reelcut_input_fragment`); the HLG, PQ and BT.2020/BT.709-transfer conversions. Before its code,
  GR-15 gains the shoulder's constants and H3's bound.
  **Corrected after T3-1's H1 stop** (GR-15 as amended, 2026-10-12): the two properties and the
  BT.709 colour are per composition — `ConvertingCompositor` and BT.709 only for a composition
  holding an HLG, PQ or wide-gamut source; `Compositor` keeps both false and no colour — and an
  sRGB-transfer source takes step 0's sRGB arm.
- **Also owns the wording PR-2's amendment left**: spec §7.5's "HDR sources arrive tone-mapped"
  sentence, and the three code comments that repeat PR-2 — `Compositor.swift`'s
  `sourcePixelBufferAttributes` doc ("HDR still arrives tone-mapped to SDR
  (`supportsHDRSourceFrames` is not implemented, so false; §7.5)"), `ExporterWriter+Settings.swift`
  at line 246 ("The compositor works in SDR sRGB/709 and tone-maps HDR sources on the way in"),
  and `ReverseRenderer.swift` at line 389 ("PR-2: HDR is tone-mapped there, not here") — each
  corrected with the code that makes it true.
- **Proof** (`hdr_proof.py`, with a probe over `app/Sources` for the conversion's maths, as
  `curves_probe.swift` is):
  - **H1**: every SDR fixture's `render_frame` byte-identical to the control tree — ProRes BT.709
    and untagged, H.264 BT.709 and untagged, matrix-only HEVC, an 8-bit still, a reversed SDR
    clip — plus `precision_proof.py compare` K1–K6 and the PR-5 frozen rows.
  - **H2**: on an HLG and a PQ fixture, `render_frame` equals the export's decoded frame at the
    same tick, ±1, at frame 0 and at the first frame of an HLG segment mid-timeline. The flash
    row; the control tree fails it (which also runs the brief's scratch finding through the app
    first).
  - **H3**: the HLG and PQ ramps land on the conversion's formula (±1 at 8 bits), and within a
    bound, written into GR-15 before measuring, of Apple's measured points.
  - **H4**: a saturated HLG patch is compressed, not clipped.
  - **H5**: the BT.2020/BT.709-transfer file is no longer darkened.
  - **H6**: the eyedropper on an HLG clip picks the colour the preview keys on (a probe of
    `CanvasEyedropperSession` over `render_frame`'s picture).
  - **TC**: an unconverted layer's cost held (`grading_spike.py --measure --tree`, +0.02 / +0.06
    ms).
  - **TI**: a converted 4K source's pass time recorded.
- **Mutants**: `canConform` removed (H2 fails on the flash); the HLG inverse OETF's branch point
  moved; the 2020 → 709 matrix transposed; the shoulder dropped (H4 clips); the pass run for SDR
  sources too (H1 must still pass, so this one is caught by TI's time or is equivalent; the phase
  decides which and says so); the composition's colour properties dropped.
- **Person check GRD-16 — iPhone HDR footage**: a default-settings iPhone clip in the preview, in
  Save Frame… and in a GIF, side by side with QuickTime Player; no flash where the clip starts in a
  `prores_422` export; the eyedropper keys the green it picked. PRC-3's HLG half is re-run.

### T3-2 — log footage (GR-16, #264)

- **Lands**: the core and app rows of "The standard recipe" above. Before its code, GR-16 gains
  each source document's terms, each curve's constants and the makers' test points, the recipe's
  `input` key and the format number.
- **Proof** (`log_proof.py` with `log_probe.swift`):
  - **L1**: each built-in curve's synthetic ramp converts to its scene-linear values within a
    level, the makers' own test points (0 %, 18 % and 90 % reflectance) included.
  - **L2**: an Apple-Log-labelled file is detected at import, and `get_project` shows
    `media[].color {log: "apple_log", detected: true}`.
  - **L3**: the conversion precedes the chroma key: a log-encoded green card keys with the
    converted green's numbers.
  - **L4**: Color's four act on converted values.
  - **L5**: Use LUT… with a script-written `.cube` matches ffmpeg's `lut3d` (±2, GR-8's T4
    method).
  - **L6**: a reversed log clip follows its media.
  - **L7**: Show Ungraded keeps the conversion and drops the look.
  - **L8**: the refusals by name, `set_media_color` undo, copy and paste, consolidate.
  - **L9**: H1's SDR identity again.
- **Mutants**: the conversion after step 3 (L3 fails); S-Log3's breakpoint wrong; the gamut
  matrix for 709 swapped for 2020; detection ignoring the label; Show Ungraded removing the
  conversion; the input LUT sampled without the half-texel offset.
- **Person checks**: **GRD-17 — Apple Log footage** on the owner's clip (normal on import; Camera
  Log ▸ None shows log; a grade then a look; against Apple's LUT if he has it); **GRD-18 — Sony or
  Panasonic log**, if he has a clip; #264's T0 run on the real clip and recorded in GR-16.

### T3-3 — the close

- `designs/adr/grading-3.md`; this road map `git mv`'d to `archive/`; its `archive/INDEX.md` row.
- The issues (each reviewed against the tree first, `ai-drafted`, `low-priority`): linear light
  with GR-18's table and design; the HDR timeline with GR-19's design; more log curves (Canon Log
  3, F-Log2, D-Log, LogC…); Apple Log 2.
- #264 closed as built; #256 closed or narrowed to what is filed.

## Costs: recorded, measured, reasoned

### Recorded in the repo

- Tier 1's linear step inside 4c: 0.011 ms at 1080p, 0.040 ms at 4K (GR0).
- A deep 4K texture or composite: 66.4 MB (PR-1, PR-6).
- A heavy 4K frame's compositor average: 7.38–7.585 ms against the 8 ms budget (precision).
  T3-1's pass adds to it only for converted sources.

### Measured for the brief (its scratch spike, gitignored)

These are the brief's figures, quoted with its commands; this road map ran none of them. Host:
Apple M2 Max (38-core GPU), macOS 26.5.1, `pmset -g` powermode 0, AC power (read before the
runs), `vm.loadavg` 1.2–3.5 across the session, 2026-10-11. Folder:
`tools/proof/work/grading-tier3-spike/` in the main tree (fixtures in `media/`).

- **Fixtures**: `base.mov` by `ffmpeg -f lavfi -i "color=c=black:size=1024x128:rate=30:duration=1,format=yuv422p10le,geq=lum='64+X*876/(W-1)':cb='if(lt(Y,64),512,112+X*800/(W-1))':cr='if(lt(Y,64),512,912-X*800/(W-1))'" -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le`;
  each tag by `-c copy -bsf:v prores_metadata=… -color_primaries … -color_trc … -colorspace …
  -movflags +write_colr` (`bt709`, `hlg`, `pq`, `b2020_709`), and `untagged` with the bsf's
  `unknown`; `hlg_hevc.mov` by `hevc_videotoolbox -profile:v main10 -pix_fmt p010le` with the HLG
  tags; two H.264 `testsrc2` files, tagged and untagged; `applelog.mov` by `./spike tag-applelog
  media/bt709.mov media/applelog.mov`.
- **Instrument 1, `main.swift`** (AVFoundation paths; final build key `17e8bb355e5ade4b`), built
  with `python3 -c "import sys; sys.path.insert(0,'tools/proof'); import swift_build; print(swift_build.build(sources=['tools/proof/work/grading-tier3-spike/main.swift'], output='tools/proof/work/grading-tier3-spike/spike', optimize=True))"`.
  `./spike decode FILE ROUTE PROPS` (one-track composition, the reader at `64RGBAHalf`; ROUTE
  `sdr` today's compositor, `hdr`, `wide`, `conform`, and the `x422` variants; PROPS the
  composition's colour: `none`, `709`, `hlg`, `pq`); `./spike seq A B ROUTE PROPS`; `./spike gen
  FILE ROUTE PROPS T…` (the generator with zero tolerance, as `Exporter.renderFrame`); `./spike
  player FILE ROUTE`; `./spike write-hdr OUT hlg|pq` then ffprobe; `./spike edr`. The decisive
  rows re-run on the final key (`final-key-runs.txt`): `seq bt709 hlg sdr none` 0.5 ×6, 0.3843 ×4,
  0.5 ×5; `hdr none` 0.5, 0.4458 ×4, 0.5 ×5, 0.4458 ×5; `conform none` and `conform 709` 0.5 ×15;
  `gen` HLG, PQ, HLG HEVC and Apple Log under `sdr none` 0.5 with 709 labels (Apple Log's own);
  the same under `conform 709` 0.5 with honest labels. Full-frame FNV digests of the source buffer,
  today's route against `conform`: identical for `bt709.mov` and `untagged.mov`
  (61d4105dccd7bbfa), `h264_709.mp4`, `h264_untagged.mp4`, `hevc8_1080.mov`, `h264_1080.mp4` and
  `short-video.mov`; different, as expected, for `b2020_709.mov` (07e23f73… today, e909499a…
  native). The H.264 rows ran through the generator only (an H.264 reader run in `decode` hung and
  was killed; not investigated).
- **Instrument 2, `gpu.swift`** (a full-frame `rgba16Float` pass over a gradient; variants
  shuffled per frame; median of three runs' medians, first five frames dropped; key
  `0128c16f6bc47964`): `./gpu --frames 100 --runs 3 --seed 1` and `--seed 2`, which agreed within
  0.001 ms. ms over the copy pass, 1080p / 4K:

| Variant | 1080p | 4K |
|---|---|---|
| C0 copy (baseline) | 0.035 | 0.213 |
| C0b copy again (control) | +0.000 | −0.001…+0.000 |
| L1 sRGB decode then encode (a linear wrap) | +0.000…+0.001 | +0.000…+0.001 |
| I1 PQ: EOTF, 2020→709, shoulder, encode | +0.007 | +0.001 |
| I2 HLG: inverse OETF, system gamma, 2020→709, shoulder, encode | +0.003…+0.004 | +0.002…+0.003 |
| I3 a log2 camera curve, matrix, shoulder, encode | +0.001 | +0.001…+0.002 |
| I4 one 33³ `rgba16Float` LUT sample | +0.003 | +0.009 |
| B0 a 25-tap blur | +0.118 | +0.410 |
| B1 the same blur with the PQ conversion in every tap | +0.898…+0.901 | +3.472…+3.473 |

  The shader is scratch, not the compositor's, so only the differences are read; its curves use
  the standards' shapes with placeholder constants for the log curve and the shoulder, so their
  cost, not their values, was measured.
- **`linear.py`** (numpy, the sRGB IEC 61966-2-1 transfer): GR-18's table, and the round-trip
  precision of linear values in half-float.

### Reasoned from those

- **T3-1's cost per frame**: about one copy pass per converted source (0.21 ms at 4K), plus a few
  thousandths of a millisecond of arithmetic; zero for an SDR source. A 4K timeline with two HDR
  clips crossing in a dissolve adds about 0.43 ms of GPU, inside the 8 ms budget but on top of the
  heavy 4K frame's 7.4–7.6 ms. TI measures it in the app.
- **Memory**: one pooled 66.4 MB target per converted 4K source in flight.
- **Export speed**: encoder-bound at these sizes (tier 1's E1/E2), so no visible change is
  expected; the phase records it.

## What tier 3 defers

- **Linear-light blending** (GR-18, filed at T3-3). What changes visibly (computed, `linear.py`):

| Operation | Encoded (today) | Linear light | |
|---|---|---|---|
| White at 50 % opacity over black | 128 | **188** | a "50 % black dim" over white becomes far lighter |
| White at 25 % over black | 64 | 137 | |
| A cross-dissolve red → green, midpoint | (128, 128, 0); luminance 0.199, **below both ends** (0.213, 0.715): the dark dip | (188, 188, 0); luminance 0.464 | the dissolve's dip disappears |
| Multiply 50 % grey × 50 % grey | 64 | 61 (spec §7.5's own figure) | |
| One blur tap at 1/3 white coverage | 85 | 156 | a white line on black blurs wider and brighter; text edges look bolder |

  Where decode and encode sit: the grade (3, 4c–4d) stays on encoded values, so a linear pipeline
  decodes after the grade and before step 7, keeps the destination linear, and encodes once in an
  output pass; an adjustment clip and the qualifier encode before reading and decode after; the
  scopes read the encoded output. It touches blending and every blend mode (11), opacity and the
  reflection's fade (9), the transition weight (8), the matte and corner coverage (7), the dissolve
  and its routed halves, the shadow; blur and sharpen (4) only if the decode moves before the
  gather. Half-float precision: a linear value in half-float returns every 10-bit code within
  0.162 of a level (encoded half-float storage: 0.250), and every 8-bit code survives the round
  trip. Off, it is byte-identical by GR0's route rule (the PR-5 frozen references —
  `e1_proof.py`'s 77934fe pixels within ±1 and `hevc_alpha_baseline.json`'s digests —
  `precision_proof.py` K1–K6, every tier-1 and tier-2 neutral row); on, the proof measures the
  table as `render_frame` rows plus the output pass's 4K frame time.
- **The HDR timeline** (GR-19, filed at T3-3): `canvas.output: "sdr" | "hlg"` (absent = SDR; PQ
  later), a format bump; an HLG project works in HLG-encoded BT.2020 values so every stage keeps
  its 0…1 meaning, PR-1's clamps stay and blending stays encoded (in HLG); SDR sources enter by
  ITU-R BT.2408's SDR→HLG mapping (SDR white at 203 cd/m², 75 % HLG), so a title is not a
  1,000-nit flare; the preview's composition and render-context buffers become BT.2020/HLG and
  `AVPlayerLayer` shows HDR on an EDR display by itself (REASONED; the built-in Liquid Retina XDR
  reports a potential EDR headroom of 16.0, the BenQ GW2790QT 1.0); the export, measured, writes
  HEVC Main 10 `bt2020nc/arib-std-b67/bt2020` with VideoToolbox adding Dolby Vision 8.4 by itself,
  and PQ with default mastering-display and content-light-level metadata under
  `kVTHDRMetadataInsertionMode_Auto`; its costs: graphics, text and captions through the SDR→HLG
  mapping, the scopes a BT.2020 matrix and an HLG or nits scale, the waveform's clip marks,
  `render_frame` PNGs in a BT.2100 space, GIF and APNG staying SDR. Two or three phases.
- **Wide gamut for SDR projects** (GR-20): closed. P3 photos are converted by Core Graphics when
  drawn, BT.2020 video by GR-15's matrix; their out-of-709 colours are lost, which is right for a
  Rec. 709 output. Wide gamut comes only as Rec. 2020 inside the HDR timeline.

## Test media, and what to ask the owner for

**Synthetic, measured working by the brief**: HLG and PQ ProRes and HEVC Main 10 ramps (ffmpeg
with `prores_metadata` plus `colr`, or `hevc_videotoolbox -profile:v main10` with the HLG tags,
precision's `ramp10_hlg.mov` recipe); an HLG HEVC Main 10 file with Dolby Vision 8.4 written by
`AVAssetWriter` from half-float frames; an Apple-Log-labelled ProRes file (ffmpeg writes the code
values, an `AVAssetWriter` passthrough rewrite adds the label: the format description rebuilt
without `VerbatimSampleDescription`, `LogTransferFunction` set, the transfer key removed, BT.2020
primaries and matrix; reads back with the label, a `logs` atom and `colr` 9/2/9); log code values
by ffmpeg's `geq`, each published curve applied to a known scene-linear ramp with the makers'
test points (S-Log3 and V-Log need no label); a BT.2020-primaries/BT.709-transfer file
(`b2020_709.mov`).

**Only real footage can answer**: whether a real iPhone Apple Log file carries the `logs` atom
(REASONED yes) and #264's T0 on it; how real Sony and Panasonic files are tagged in `colr`;
whether Reelcut's conversion looks right on skin, sky and a bright window against the maker's LUT
and against Final Cut Pro or Photos; whether iPhone HLG with real Dolby Vision metadata converts as
the synthetic ramp does; how a real Reelcut screen recording is labelled (no real recording is on
disk, and an agent may not record the owner's screen: the recording proof's own run or one
recording the owner makes settles it; if it is labelled Display P3 or sRGB, H1 is re-checked on
it).

**What to ask the owner for** (choice 11; each kept on his disk, its path given to the proof in
an environment variable, never copied into the repo):
1. An iPhone Apple Log clip: iPhone 15 Pro or later, Camera set to ProRes with Log (or Blackmagic
   Camera in Apple Log), 10–20 seconds, a face, some sky and a bright window in frame.
2. An ordinary iPhone HDR clip of the same scene (default Camera settings, HEVC).
3. If he owns a Sony or Panasonic camera: an S-Log3 or V-Log clip, and the maker's own LUT
   downloaded by him, used only for a comparison row.
4. Optional: Apple's Apple Log LUT, if his developer account reaches it, for the same comparison.
5. Later, for the HDR timeline only: a look at an HLG export on the built-in XDR display.

## Not established

- **The defect in the app itself.** The first-frame and generator behaviour was measured with
  `AVMutableVideoComposition` in a scratch program; the app builds
  `AVVideoComposition(configuration:)`. REASONED the same engine, and GR6a's T0 (through the app's
  `render_frame`) agrees. T3-1's H2 runs it through the app first, on the control tree.
- **Real footage**: an iPhone Apple Log file's labels; Sony and Panasonic tags; real Dolby Vision
  HLG; a real screen recording's labels.
- **Whether `canConformColorOfSourceFrames` holds for every codec Reelcut takes**: measured on
  ProRes 422, HEVC Main 10, H.264 and HEVC 8-bit, through the reader and the generator; not on
  ProRes 4444 with alpha, the WebM rewrap (#228's copy), the HEVC-with-alpha path, or the player at
  length.
- **The player's first frame after T3-1**: REASONED fixed (the same conversion that was skipped),
  measured only in the reader and generator.
- **Apple's HLG→SDR curve beyond four points**, and how it treats Dolby Vision metadata.
- **Apple Log 2**'s curve and gamut (no published source read).
- **Whether `AVPlayerLayer` shows EDR for a custom compositor's HLG output** (HDR timeline only): a
  person's check.
- **The maker LUTs' licences**: not found; moot under choice 4a.
- **Other editors' behaviour** (Final Cut Pro's automatic Apple Log conversion, Photos' HDR
  handling) is general knowledge, not measured.

## The Concat rule, and where the maths comes from

**Concat (`~/devel/Concat`) is AGPL-3.0-or-later. None of its code, shaders, chains or colour
tables may be carried over** (root `CLAUDE.md`; `designs/adr/effects-survey.md`), at design time
and build time. The brief consulted nothing of Concat, and neither did this road map. The sources
instead:
- **HLG and PQ**: ITU-R BT.2100 (the HLG OETF and its inverse, the system gamma; PQ is SMPTE ST
  2084's EOTF, reproduced in BT.2100); ITU-R BT.2408 (reference white at 203 cd/m², 75 % HLG; the
  SDR↔HDR mappings); ITU-R BT.2390 (a PQ roll-off); ITU-R BT.2020 and BT.709 primaries. All freely
  published ITU texts.
- **Log curves**: each maker's own published document, formulas only, each document's terms
  checked and recorded in GR-16 before T3-2 implements from it.
- **Matrices**: computed from published primaries and D65 by the standard derivation, in a script
  the phase keeps.
- **The shoulder** and its anchor: Reelcut's own numbers, set by choice 2 and the H3 row; Apple's
  conversion is MEASURED as a target, not copied.
- **sRGB**: IEC 61966-2-1 (already in the tree).
- Every test LUT and fixture is written by a script.

## T3-0 — the road map, GR-15…GR-20 and the move

**What landed** (2026-10-11, in the worktree on `grading-3`, from `8707ada`). This road map;
`designs/spec/11-decisions/grading-3.md` with GR-15…GR-20, its "Holds" row and six ID rows in
`11-decisions/README.md`, and the Lines cells; "Amended by GR-15" under PR-2 (`precision.md`) and
at the end of GR-8 (`grading.md`), "Amended by GR-16" at the end of GR-8, and "— amended by GR-15"
/ "— amended by GR-15, amended by GR-16" on their index rows; one Amended-by sub-bullet each in
`designs/adr/precision.md` (PR-2), `designs/adr/grading.md` (the `colr` bullet) and
`designs/adr/grading-2.md` ("Tier 2 closes nothing off for tier 3": the input conversion is step
0, before step 3, not a step before 4c); spec §7.4's `Compositor.swift` row gains
`DestinationPass.swift` and its sentence; and one pure move, gated alone with no tier-3 code and
no behaviour change. The moved block was diffed against `git show HEAD:app/Sources/Compositor.swift`
(lines 267–330): identical.

| Move | `wc -l` before → after | New file | What widened |
|---|---|---|---|
| `Compositor.swift` → `DestinationPass.swift`: the doc comment ("The destination render pass, as a value that can be suspended and resumed.") through `struct DestinationPass`'s closing brace, with `import Metal` and nothing else; the blank line after it went too | 723 → 658 | 66 | nothing (`DestinationPass` and its members keep their access; `Compositor+Shadow.swift`, `+Dissolve.swift`, `+Matte.swift` and `+Adjustment.swift` compile unchanged) |

No proof anchor lay inside the moved block (`adjustment_proof.py`, `matte_proof.py` and
`precision_proof.py` anchor other `Compositor.swift` lines), and no comment was edited: §7.5 and
the PR-2 code comments wait for T3-1. `designs/adr/app-file-history.md` ("Named next cuts")
records the move and names the next seam: `MetalRenderer`'s `// MARK: - Sources` (`LayerSource`,
`source(for:…)`, `texture(from:live:)`) out whole to `Compositor+Sources.swift` as an `extension
MetalRenderer`, where T3-1's step 0 meets a track's buffer.

**Verification**, 2026-10-11, AC power (`pmset -g`: powermode 0; `pmset -g ps`: AC Power):
- Controls from the untouched worktree before any edit, never by stashing: `make app-debug`
  (BUILD SUCCEEDED), its `agent-catalog.json` copied to `tools/proof/work/t3-0/catalog-before.json`;
  `make app` (exit 0); `RC_PROOF_APP=release python3 tools/proof/precision_proof.py capture
  tools/proof/work/t3-0/ctl`: 6/6, K1–K6 rendered (K1 a1e4332cd0b2b295, K2 2aa1e1c100bff3ba, K3
  db8d6c07fd2c0b06, K4 bc119a50b8d0725b, K5 a1769b4377b27ff7, K6 642926e7a1ca6022), Z1 no
  `Reelcut: ` line (`tools/proof/work/t3-0/control-precision-capture.txt`).
- `make typecheck` after the move: exit 0, 0 errors, exactly the 4 baseline warnings.
- `python3 tools/proof/spec_index_proof.py` after the last doc edit: 156/156. The cells:
  `precision.md` 222 → 233, `grading.md` 443 → 459, `grading-3.md` new at 212, and the spec
  README's `11-decisions/` cell 6807 in 19 files → 7053 in 20.
- `make app-debug` (BUILD SUCCEEDED), then `python3 -c "import json,sys; a,b=(json.load(open(p))
  for p in sys.argv[1:]); sys.exit(a!=b)" tools/proof/work/t3-0/catalog-before.json
  "build/Build/Products/Debug/Reelcut.app/Contents/Resources/agent-catalog.json"`: exit 0, the
  parsed catalogs equal (96 tools).
- `make gate`: PASS in 280 s (typecheck 5 s, fmt 2 s, lint 22 s, test 167 s, app 83 s, with D25 and
  D26 ok). The cargo suites passed 1,367 tests in 119 result lines and failed none;
  `spec_index_proof.py` 156/156 among its proof steps. No test file was added or removed.
- On the gate's Release build: `RC_PROOF_APP=release python3 tools/proof/precision_proof.py
  compare tools/proof/work/t3-0/ctl --only K1,K2,K3,K4,K5,K6`: 7/7, K1–K6 byte-identical to the
  control (K4 the routed dissolve), Z1 no `Reelcut: ` line (`after-precision-K-release.txt`);
  `RC_PROOF_APP=release python3 tools/proof/matte_proof.py --only C0,S1,T1,N7`: 4/4 (S1 the shadow's
  suspend and resume, T1 and N7 the dissolves; `after-matte-release.txt`);
  `RC_PROOF_APP=release python3 tools/proof/word_looks_proof.py --only B1`: 3/3, B1 `moved: []`,
  the 41 frames of fixture B still matching the digests recorded from `914b56a`
  (`after-word_looks-B1-release.txt`). No `DEFAULTS MOVED` in any of them.
- No mutants: a pure move adds no decision.

**Owed.** The `app/CLAUDE.md` compositor entry (applied by the orchestrator): its first lines
become

```
- `Compositor.swift` · `Compositor+Uniforms.swift` · `Compositor+Shadow.swift` ·
  `Compositor+Matte.swift` · `MattePlan.swift` · `Compositor+Dissolve.swift` ·
  `Compositor+Adjustment.swift` · `DestinationPass.swift` (the destination
  render pass as a value a shadow or a routed dissolve suspends and
  resumes) ·
```

with the following line (`` `CompositorEffects.swift` · `LayerUniforms.swift` (`LayerUniforms`, ``)
unchanged. T3-1 (honest sources, GR-15) is next, from main after this phase's merge.

**Review.** One pass, verdict pass, three nits applied by the orchestrator: PR-5's index row
notes GR-20's closure of its SDR wide gamut; `designs/adr/precision.md`'s PR-2 amendment names
the Look gallery's thumbnails and Pick from Canvas among the generator paths; GR-8's amendment
marks its cut quote of T0 with "…". The `app/CLAUDE.md` entry above is applied. After them:
`spec_index_proof.py` 156/156, `make gate` PASS.

## T3-1 — honest sources and Reelcut's HDR→SDR at step 0

**What landed** (2026-10-11/12, in the worktree on `grading-3`, from `e4f9ec1`; GR-15 as appended
and as amended after the H1 stop).
- **The pure move first**: `Compositor.swift`'s `// MARK: - Sources` (`LayerSource`,
  `source(for:…)`, `texture(from:live:)`) to `Compositor+Sources.swift` as `extension
  MetalRenderer`; `textureCache`, `renderers` and `texture(from:live:)` widened from `private`;
  658 → 572 lines, the new file 91. Gated alone: `make gate` PASS (300 s), `RC_PROOF_APP=release
  precision_proof.py compare tools/proof/work/t3-1/precision-ctl --only K1…K6` 7/7.
- **Step 0**: `InputConversions.swift` (`InputPrimaries`; `InputConversion` — HLG, PQ,
  wide-gamut SDR and the sRGB arm, the selector by transfer through two readers, a buffer's
  attachments and a format description's extensions, `startsConversion`, the uniforms;
  `InputConversions`, every number Reelcut chose or derived, `toBT709` derived from the
  chromaticities and D65, exactly the identity for BT.709); `Compositor+Input.swift`
  (`ConvertingCompositor`; `InputUniforms`, 24 floats; `InputError`; `InputStage` — the ninth
  pipeline, a size-keyed `rgba16Float` pool on `MattePool`'s 30-frame policy, the frame's
  converted tracks, the pass count; `encodeInputs`); `Compositor.metal`'s input pass
  (`reelcut_input_fragment` and its helpers, the standards' constants only; step 0 in the ORDER OF
  OPERATIONS note); `Compositor+Sources.swift`'s `.track` takes the converted texture.
- **The switch, per composition**: `Compositor` is no longer `final` and answers
  `canConformColorOfSourceFrames` and `supportsHDRSourceFrames` false (today's answers, stated);
  `ConvertingCompositor` answers both true; `serve` passes `converts:` to `render`, which runs
  `encodeInputs` only then, after the command buffer and before `encodeMattes`.
  `CompositionBuilder.build` collects its video tracks and asks `convertsSources` (their format
  descriptions read by key): `ConvertingCompositor` and BT.709 colour when any answers a
  conversion that starts one, else `Compositor` and no colour. The timing line gains `, N input
  passes` (appended). `Compositor.swift` 600 lines, `CompositionBuilder.swift` 558.
- **Wording PR-2 left**: `sourcePixelBufferAttributes`' doc, `ExporterWriter+Settings.swift`'s
  output-tag comment and `ReverseRenderer.swift`'s class doc (comment-only, line-neutral); spec
  §7.5 (the per-composition step-0 bullet, NINE pipelines from seven), §7.4's compositor row,
  README's Export bullet, GRD-16, `lut_proof.py`'s T0 heading.

**The H1 stop and its redesign.** The first code set BT.709 on every composition. The
implementer stopped at H1 (2026-10-11): every SDR scene's pixels were identical (0 differing
16-bit samples), but 7 of the 12 single-source scenes — untagged ProRes and H.264, matrix-only
HEVC, the PNG still, VP9, the sRGB HEVC and Apple Log — came out with `kCGColorSpaceCoreMedia709`
in place of the control's `sRGB` chunk or the source's ICC, and their eyedropper picks moved
(untagged grey 0.251 → 0.286); a diagnostic build without the composition colour passed H1 12/12
but failed H2 and H3 (HDR frames followed the source's HLG tag). The owner chose "Redesign, keep
SDR exact" (2026-10-12); the designer measured M1–M8 in scratch (GR-15's amendment records them)
and the switch became per composition; the owner then chose "Convert it now" for an sRGB-transfer
clip in a converting composition (the sRGB arm). Kept from the stopped code: the pure move, the
two controls, the instruments, GR-15's append, step 0 itself and the comment edits.

**Measured** (2026-10-12, AC power, `pmset -g` powermode 0; Release unless said):
- Controls on the untouched tree (2026-10-11, Release): `hdr_proof.py capture
  tools/proof/work/t3-1/ctl` — H2, H3, H4, H5 and H6 FAILED (each discriminates), H1's references
  for 12 scenes; a control-on-control `compare --only H1,Z1` 2/2 (H1 repeatable; a reversed
  clip's intermediate differs by digest run to run, its render does not); `precision_proof.py
  capture tools/proof/work/t3-1/precision-ctl` 6/6.
- `RC_PROOF_APP=release python3 tools/proof/hdr_proof.py compare tools/proof/work/t3-1/ctl`:
  14/14, no `Reelcut: ` line, no DEFAULTS MOVED. H1 12 scenes byte-identical, picks equal. H1m
  both mixed projects' PNG bytes and picks equal the base tree's. H1s picks mixed = alone ([64,
  64, 64], [127, 128, 128], [88, 249, 255]), export rows worst 4 levels, x=512 116 = 116; the base
  tree picks [10, 10, 10], [62, 63, 63], [26, 243, 255] (fails, as it must). H1w picks = Apple's
  reading of the file's labels ([64, 64, 64], [127, 128, 128], [0, 253, 255]), export grey 116 =
  srgb alone's 116; the base tree [13, 13, 13], [54, 55, 55], [0, 251, 255] (fails). H2 frame 0 =
  frame +5 exactly on all four, render vs export ≤ 1. H3 worst 1 level against the oracle; Apple's
  points HLG +0.96 / −0.86 / +0.12 / 0.00, PQ −0.81 / −0.37 (bound 3). H4 383 columns, worst hue
  gap 0.21°, every value inside the envelope (the patch [0, 144, 255] against the oracle's [0, 143,
  255]; the control's [107, 215, 255]). H5 greys within 1, chroma inside the envelope (worst
  sited |Δ| 4 / 3 / 7, all near black). H6 HLG pick [144, 0, 19] against its export's [143, 0,
  20], keyed export (255, 0, 255); the base tree [158, 46, 0] (fails). R0 (record) the newest
  recording `bt709/bt709/bt709`, the identity arm, its tags in H1. P1 23 cases through both
  readers; P2 worst 4.9e-8; P3 worst 9.8e-4 (bound 2e-3); P4 the constants and a 96-byte block.
- `RC_PROOF_APP=release python3 tools/proof/hdr_proof.py --measure` (TI): the 4K HLG twin's two
  lines report 120 and 120 input passes, averages 2.02 and 1.76 ms (worst 8.8, 3.07); the BT.709
  twin's 0 and 0, 1.55 and 1.32 ms (worst 6.82, 3.49): a mean difference of 0.455 ms. The host was
  loaded (loadavg 17.39 / 29.86 / 23.86 before, another session's work), so the figures are
  recorded, not a budget.
- `precision_proof.py compare …/precision-ctl --only K1…K6` 7/7 byte-identical; `--only V2,V3`
  3/3 (V2 mean |Δ| 0.108 codes, V3 0.097 levels, the HLG reverse now through step 0);
  `hevc_alpha_proof.py` 43/43; `e1_proof.py` 101/101 against the 77934fe reference (PR-5's frozen
  pixels within ±1); `grading_spike.py --measure --tree --tree-base e4f9ec1` (TC): 1080p
  VT:S1 − V0:S1 −0.007 ms (cap 0.028), 4K −0.001 ms (cap 0.061), TA 0.001 / 0.000 ms: held.
- `make gate` PASS (240 s, typecheck 0 errors and the 4 baseline warnings).
- **Mutants**, once each on the final instrument (Debug copies), all caught; every failing row:
  `no-conform` H2 H3 (and H1s H1w H4 H5 H6); `hlg-branch-moved` P3 (and H4); `matrix-transposed`
  H3 H5 H1w P2 P3 (and H4); `shoulder-dropped` H3 H4 P3; `lift-dropped` H4 P3;
  `no-composition-color` H2 H3 H1m (and H1s H1w H4 H6); `select-by-primaries` H1 P1 (and H1m H1w
  H3 H4); `convert-everywhere` H1 H1m; `conform-everywhere` H1m (and H1 H1s H1w);
  `srgb-arm-dropped` H1s P1; `srgb-starts-conversion` H1 P1 (and H1m); `srgb-wide-as-sdrwide` H1w
  P1. Twelve, past ten, because each guards a separate decision (the spec's reason).

**Owed.** GRD-16 (the owner's real iPhone HDR clip, PRC-3's HLG half, a screen recording beside
it); the `app/CLAUDE.md` compositor entry (the orchestrator applies it). HDR10 static metadata on
a converted frame is unmeasured (GR-15's accepted limit).

**Review.** One pass, verdict pass, three nits applied by the orchestrator: `InputUniforms.encodePower`'s
doc names the sRGB arm's 256/502; `InputStage`'s unused `init?(coder:)` removed; the sRGB arm's encode
power is set in its own `switch` case. The `app/CLAUDE.md` compositor entry is applied. After them:
`make typecheck` at its 4 baseline warnings, `make gate` PASS, `RC_PROOF_APP=release hdr_proof.py
compare tools/proof/work/t3-1/ctl` 14/14 (no `Reelcut: ` complaint, no DEFAULTS MOVED), `hdr_proof.py
--only P1,P2,P3,P4,Z1` 5/5. No mutant anchor sits on the changed lines.

## T3-2 — camera log footage at step 0 (GR-16, #264)

**What landed** (2026-10-12, in the worktree on `grading-3`, from `8e20fff`; GR-16 as appended
before the code).
- **The sources first.** T3-2's first run stopped at its step 1: Apple's paper sat behind the
  developer login and pro.sony refused this host (403). The owner downloaded Apple's *Apple Log 2
  White Paper* (September 2025, v1.1, whose curve is Apple Log's), Sony's *Technical Summary for
  S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3* and Apple's LUT download; Panasonic's *V-Log/V-Gamut
  Reference Manual* Rev. 1.0 was fetched directly. Every constant the spec named matched. GR-16's
  append records each document, its terms (Apple's copyright notice; none stated by Sony or
  Panasonic), the constants, the test points, the code domains, Apple Log 2, the display transform
  (mid-grey 0.42, the owner's "42%, as planned"), the wire and the format. Apple's
  AppleLogToLin-v1.0.cube agrees with the paper's inverse to 3.0·10⁻⁵ (a scratch check; no Apple
  or Sony file is in the repo).
- **Apple Log 2 is in** (the owner's leftover rule): the paper gives Apple Wide Gamut, and the SDK
  names the label (`kCVImageBufferLogTransferFunction_AppleLog2`, macOS 26). `log: "apple_log2"`
  with `gamut: "apple_wide_gamut"`, detected like Apple Log, the curve shared (kind 5).
- **Core** (format 19): `model_media_color.rs` (`LogCurve`, `CameraGamut`, `MediaColor`),
  `media_color.rs` (`set_media_color`, the strict reader, `check_media_color`, `media_input`,
  `media_converted_by`), `Media.color`; the 61st op (`edit.rs`, `op_table.rs` `OP_COUNT` 61,
  `scope.rs`'s ninth refusal); `MEDIA_KEYS` 12 and `add_media`'s check; a relink probe refuses
  `color` and a relink keeps it; `remove_lut` refuses naming the media a LUT converts and clears
  them with `with_clips`; paste carries a shown media's conversion LUT and remaps or drops it;
  `validate` checks every media's colour; the recipe layer's `input` (26 keys, after `look`, kept
  by `ungraded`); a video plan segment's `input` only when its media converts. Tests:
  `media_color.rs` (16), `schema_v19.rs` (6), `schema_v18.rs`'s pin relaxed, `recipe.rs`'s 26
  keys, `edit_tests.rs`'s and `scope.rs`'s op tables.
- **Swift and Metal**: `MediaColor.swift` (its own decoder: an `input` carries no `detected`);
  `MediaSnapshot.color`, `MediaDescriptor.color` (a relink's probe drops it);
  `MediaImporter+Color.swift`'s `detectedColor` (`MediaImporter.swift` +3, 596 lines);
  `PlanSegment.input`, `CompositionPlan.convertsMedia`, the builder's `converts` line,
  `RecipeLayer.input`; `InputConversions.swift` (four camera gamuts, `.log`, `.lut`,
  `choose(input:)`, the log constants and code domains); `Compositor+Input.swift`
  (`exposure`/`codeScale`/`codeOffset` from the three reserved floats, kinds 5–8, `encode(…,
  lut:)` with a 1³ placeholder at `texture(1)`, `encodeInputs` input-first and the LUT through
  `lookURLs` and `LutTextures`); `Compositor.metal` (the makers' constants, three inverse curves,
  the log arm and the LUT arm). `Compositor.swift` and `Compositor+Sources.swift` not edited.
- **The chrome and the agent**: the Media tab's Camera Log section (`MediaPane+CameraLog.swift`,
  appended in `makeSections()` when the project has a video file; a click on a row refreshes it),
  Use LUT… (`EditorViewController+CameraLog.swift`, one grouped "Camera Log" step), Remove's
  alert counts conversions, `MediaUsage.mediaConverted(by:)`, the Look section's warning
  (`lutOverCameraLog`, in `ClipPane`'s signature), Copy carries a conversion LUT's row;
  `set_media_color` (handler, table line, catalog entry, `add_media`'s prose, the prompt's media
  topic), `add_media`'s hand-read descriptor taking `color` (each key and word refused by name,
  what it may hold the core's), the tool counts in comments.

**Deviations from the spec, each measured.**
- **Apple Log's code domain.** The spec assumed every curve reads CV = 64 + 876·s; Apple's paper
  defines P as the normalized signal ("10 bit, full range" codes are P·1023), so Apple Log reads
  P = s (`codeScale` 1, `codeOffset` 0) and its fixture stores 64 + 876·P (patches 196/492/661);
  Sony's and Panasonic's stay as specified. Recorded in GR-16; GRD-17 checks a real file.
- **The oracle rounds the decoded signal to half** before the formula (`oracle_at`): step 0 reads
  an `rgba16Float` source, and at S-Log3's black code 95 the rounding alone is 0.84 of a level
  (measured on Debug: render 2 against an unrounded oracle 0 at the ramp's first column).
- **L6 compares the reverse to its own codes.** The HEVC Main 10 intermediate (PR P2-2) moved
  the ramp's first column from code 95 to 98 (S-Log3) and 196 to 199 (Apple Log), seven levels
  through the toe; every other of 131 samples was within 2. L6 now holds the reversed render to
  the media's conversion of the intermediate's own codes (hdr_proof's H4 envelope, Y ±1 widened
  by 1) at every sample, to the forward render ±2 where the intermediate's code is the file's
  within 1, and ≥ 10 levels from unconverted.
- **L1 samples more than the spec's grid.** On the first mutant run `slog3-breakpoint` and
  `cine-as-709` survived L1: every 8th grey column misses S-Log3's break (code 171.2 falls between
  columns 9 and 10), and a grey row cannot see a gamut matrix. L1 now also reads every column of
  the first 32 and green.mov's card; both mutants then failed it (below).
- **L8's null on none** is the agent's identity answer ("Camera Log made no change: …"), not an
  `ok`, as every identity is (`AgentServer.performGroupedEdit`).
- **green.mov's first build** carried only its matrix tag (bt2020nc, no primaries or transfer)
  and rendered its card [50, 165, 73] in L3's scenes against the oracle's [61, 156, 74], while
  L5's LUT scene matched ffmpeg within 1; remade with bt2020/bt709/bt2020nc it renders [61, 156,
  74] exactly. L1 and L5 now also score `green_m.mov`, the same card tagged bt2020nc alone (in
  the ProRes header and the `colr` atom, primaries and transfer unknown), against its own decode:
  it renders [61, 156, 74], 0 levels off, in both. A scratch run on Debug (fix pass 1) over the
  same card tagged other ways: untagged → [59, 154, 76], and the matrix in the ProRes header
  only, no `colr` atom → [59, 154, 76], both the BT.709-coefficient decode (AVFoundation reads
  the `colr` atom, ffmpeg the header); in the `colr` atom only → [61, 156, 74]. The old [50, 165,
  73] is the BT.601-coefficient decode ([49, 165, 73] by the oracle) within 1, which none of
  these taggings reproduces. Not explained (residue).

**Measured** (2026-10-12, AC power, `pmset -g` powermode 0, loadavg 15.5 / 13.4 / 11.9 at the
first recorded runs and 31.1 / 32.2 / 26.1 after the last, other sessions' work; Release unless
said; every recorded run is on the final product and instrument):
- Control on the untouched product tree (`make app` at 8e20fff's sources, Release):
  `log_proof.py capture tools/proof/work/t3-2/ctl` — L9's references for 5 of 5 fixtures; LP1–LP4
  and L1–L8 all FAILED (`set_media_color` unknown, the probe would not build); Z1 ok.
- `make gate` PASS (227 s after the last product edit; typecheck at its 4 baseline warnings).
- `RC_PROOF_APP=release python3 tools/proof/log_proof.py compare tools/proof/work/t3-2/ctl`:
  14/14 on the final instrument (re-run after fix pass 1 added `green_m.mov`), no `Reelcut: `
  line, no DEFAULTS MOVED. L9 5 fixtures byte-identical. L1 worst 1 level on every grey fixture
  and 0 on both cards (`green.mov`, `green_m.mov`); the patches render [1/2/3,
  107, 200] (0 %, 18 %, 90 %), the oracle's exactly. L2
  {apple_log, bt2020, detected}, {apple_log2, apple_wide_gamut, detected}, none. L3 keyed with the
  converted green [0.2385, 0.6105, 0.2901] → [255, 0, 255]; with the log green the card stays [61,
  156, 74] (oracle [61, 156, 74]). L4 1 level from the export's grade, 48 from the unconverted
  grade. L5 worst 1 (S-Log3) and 0 (both cards). L6 forward gap 1 / 2 where the codes agree, the
  moved samples inside the envelope, 48 / 33 from unconverted. L7 ungraded = look-less byte for
  byte, 48 from None. L8 every sentence. LP1 11 colours; LP2 worst 4.9·10⁻⁸; LP3 worst 9.1·10⁻⁴
  (bound 2·10⁻³), the makers' codes within ±0.005 of reflectance; LP4 the constants, 96 bytes.
- `RC_PROOF_APP=release python3 tools/proof/hdr_proof.py compare tools/proof/work/t3-1/ctl --only
  H1,H1m,H2,H3,P1,P2,P3,P4,Z1`: 9/9 (H1 12 scenes byte-identical and picks equal; H1m equal to
  the base tree, which reads version-18 copies).
- `RC_PROOF_APP=release python3 tools/proof/hdr_proof.py compare tools/proof/work/t3-1/ctl --only
  H6,Z1` (fix pass 1: H6's base asks read `base_copy` packages, a refused copy its reason): 2/2;
  the tree picks [144, 0, 19] against its export's [143, 0, 20], the keyed export [255, 0, 255],
  the base tree [158, 46, 0] (the control fails).
- `op_argument_proof.py` on a Release instance: 159/159, 91 product tools, 14 opaque doors
  (`set_media_color.color` the new one, its unknown key named by the core).
- `RC_PROOF_APP=release python3 tools/proof/screens.py --only 10b-media-tab`: 6/6, 0 new layout
  problems.
- **Mutants** (Debug copies; a core mutant builds its own core), all caught, on the final
  product; `slog3-breakpoint` and `cine-as-709` on L1 as widened to the toes and the card, the
  other eight on L1's every-8th-column grid, before that widening and before fix pass 1 added
  `green_m.mov` to L1 and L5 (each only adds samples a row can fail on); every failing row: `source-unconverted` L1 L3 L4 (and L5 L6 L7 L9); `slog3-breakpoint`
  LP3 L1 (L1 at columns 6, 7, 9: [26, 28, 31] against [28, 30, 33]); `cine-as-709` LP2 L1 L3
  (and LP1 LP3; the card [100, 141, 91] against [61, 156, 74]); `detection-ignores-label` L2;
  `ungraded-drops-input` L7; `lut-no-half-texel` LP3 L5; `plan-input-dropped` L1 (and L6);
  `labels-over-setting` L1 (and L3 L4 L5 L6 L7); `remove-lut-keeps-conversion` L8; `log2-as-log`
  L2. Ten: the spec's nine and Apple Log 2's one. `slog3-breakpoint` and `cine-as-709` survived
  L1 on the first run (above) and were run again after it changed; the other eight ran once.

**Owed.** GRD-17 (the owner's Apple Log clip: the label, the code range, Apple's LUT) and GRD-18
(a Sony or Panasonic clip); the `CLAUDE.md` edits (the orchestrator applies them); the green.mov
observation above (its [50, 165, 73] is BT.601's decode, and a file whose matrix is in the ProRes
header alone decodes with BT.709's coefficients); the reverse intermediate's toe shift: the HEVC
Main 10 reverse (PR P2-2) stores code 98 where the file has 95 (S-Log3) and 199 where it has 196
(Apple Log), 7 levels after the log curve, which L6's rewritten bound now absorbs.

**Re-review.** Pass 2, verdict pass. One nit applied by the orchestrator: `tools/proof/README.md`
says `base_copy` serves H1m and H6. The CLAUDE.md edits the notes owed (root, `app/`, `core/`:
the 91 tools and 61 op tools, the Media tab, import and compositor entries, `model_media_color.rs`
and `media_color.rs`, the recipe's twenty-six keys) are applied.

## T3-3 — the close

**What landed** (2026-10-12, in the worktree on `grading-3`, from `2a8421b`). `designs/adr/grading-3.md`. This road map
`git mv`'d to `archive/grading-3.md`, with its `archive/INDEX.md` row. Every `designs/grading-3.md` citation outside
`archive/` now points here: §11 `grading-3.md`'s first paragraph in the closed form, `grading.md` (GR-8's amendment),
`precision.md` (PR-2's amendment) and `tools/proof/README.md`'s two record lines. Each "PR-2 stands" outside `archive/`
gained "(amended by GR-15…)": `precision.md`'s opening and PR-7, the PR-7 index row, and `designs/adr/precision-2.md`.
Spec §1's non-goals sentence now names tier 3. GRD-16 gained the preview's first frame and playback to the end. GR-15
gained one sub-bullet, "Measured at T3-3". `hdr_proof.py` gained rows H1a and H7, three fixtures (`hevc_alpha`,
`pq_plain`, `pq_hdr10`) and TI's export wall time. No product file changed.

**Measured** (2026-10-12, `powermode 0`; AC power for the Debug run and the first Release run, then battery from
the `--measure` run on, `pmset -g batt` "Now drawing from 'Battery Power'", 99 %, and AC again for the H7 re-run;
the host was loaded by other sessions):
- `python3 tools/proof/hdr_proof.py --only H1a,H7,Z1` (Debug, loadavg 38.17 / 14.78 / 11.98 before): 3/3.
- `RC_PROOF_APP=release python3 tools/proof/hdr_proof.py --only H1a,H7,Z1` (loadavg 24.04 / 24.86 / 17.35 before):
  3/3, with the same figures as Debug, no `Reelcut: ` line and no DEFAULTS MOVED.
  - **H1a**: prores4444 | hlg | hevc_alpha | webm at 640×360. At 0.5 s into the ProRes 4444, HEVC-alpha and WebM
    clips the tree's PNG bytes are equal to e4f9ec1's and its picks are equal (e.g. HEVC alpha [0, 0.541, 0.541],
    [0.173, 0, 0], [0, 0.863, 0.863] on both). At the HLG clip (CONTROL) the PNGs differ in 143,449 16-bit samples,
    grey pick 0.424 (tree, converted) against 0.545 (base). So GR-15's switch holds for alpha and the WebM rewrap.
  - **H7** in these runs carried metadata naming 1,000 cd/m² (`L(10000000,1):max-cll=1000,400`), the
    conversion's own peak, so equal renders could not tell "ignores" from "follows"; the review caught it and H7
    was re-run with a 4,000 cd/m² peak (below).
- `RC_PROOF_APP=release python3 tools/proof/hdr_proof.py --only H7,Z1` (the fix pass, `pq_hdr10` remade with
  `L(40000000,50):max-cll=4000,400`; AC power, loadavg 28.72 / 39.30 / 38.72 before): 2/2, no `Reelcut: ` line and
  no DEFAULTS MOVED.
  - **H7**: ffprobe names "Mastering display metadata" and "Content light level metadata" on `pq_hdr10`'s first
    frame with `max_luminance=40000000/10000` and `max_content=4000`, and none of them on `pq_plain`'s (CONTROL; a
    stale 1,000-nit fixture now fails it). Each grey row is within 1 level of the PQ oracle (x=512: render
    [183, 183, 183], oracle [183, 183, 183]). The two renders' PNG bytes are equal: with metadata naming a peak
    other than its own 1,000 cd/m², the shoulder ignores it (#281).
- `RC_PROOF_APP=release python3 tools/proof/hdr_proof.py --measure`: 2/2. TI: the HLG twin had 2 lines with
  passes [120, 120], averages 2.12 / 1.74 ms and worst 10.09 / 2.89, export wall 0.96 s. The BT.709 twin had passes
  [0, 0], averages 1.62 / 1.29 ms and worst 6.57 / 2.29, export wall 0.95 s. The mean averages were 1.930 and
  1.455 ms. Battery power, loadavg 21.41 / 24.27 / 17.23 before. Recorded, not a budget; with a 4K ProRes export of
  this ramp the conversion adds no wall time that one run can see.
- `python3 tools/proof/spec_index_proof.py` 156/156; `python3 tools/proof/capture_spike/inventory.py --check` 5/5;
  `git grep -n "designs/grading-3.md" -- . ':!archive'` prints nothing; every `git grep -n "PR-2 stands" -- .
  ':!archive'` hit carries the GR-15 note.
- `make gate`: PASS (test re-run, 78 s; typecheck, fmt, lint and app skipped as byte-identical to their last pass,
  typecheck at its 4 baseline warnings).
- No mutants: the phase adds no product decision, and H1a's and H7's CONTROLs discriminate.

**The issues** (drafted at the close, each `ai-drafted`, `low-priority`, reviewed against the tree first):
#276 linear-light blending as an opt-in project switch (GR-18); #277 the HDR timeline: HLG output, EDR
preview, HDR export (GR-19); #278 camera log: more curves, and S-Log3/V-Log detected from the maker's metadata;
#279 a colour tag in the ProRes header but not the `colr` atom, green.mov's unexplained [50, 165, 73], and
sources whose description lacks their frames' labels; #280 the 10-bit reverse's toe shift on log footage;
#281 PQ's shoulder ignores HDR10 static metadata (H7); #282 thumbnails show the log picture; #283 a
full-range-flagged log file is read as video range. Not filed: Apple Log 2 (built in T3-2); Apple's HLG curve
beyond four points (moot: H3 holds Reelcut's own formula); the maker LUTs' licences (moot: none bundled); real
footage (GRD-16…GRD-18); the player's first frame and the player at length (GRD-16, extended here); a recording's
labels (R0 read `bt709`); the brief's scratch H.264 reader hang (a scratch instrument's).

**Close comments**: #264 closed as built (T3-2, `2a8421b`, GR-16; L1–L9 on synthetic fixtures; its "done when" on
a real clip is GRD-17/GRD-18). #256 closed: HDR sources converted honestly (GR-15, T3-1), wide gamut for SDR
projects closed by the owner (GR-20, choice 9a), linear light → #276, HDR/EDR/HDR export → #277.

**Owed.** GRD-16…GRD-18 (the owner's clips). The root `CLAUDE.md` ADR list names `grading-3` (the orchestrator
applies it). The issues are filed and #256/#264 closed by the orchestrator, and the `#TBD-n` placeholders are
substituted (`git grep -n "#TBD-"`).

**Review and close.** Review pass 1: fix-required (H7's fixture named the conversion's own 1,000
cd/m² peak, so it could not discriminate; two nits). One fix pass (the 4,000 cd/m² fixture, H7
re-run on Release 2/2), re-review pass 2: pass, two nits applied by the orchestrator (the peak
lines matched whole; a README paragraph rewrapped), after which H7 on Release 2/2 again (AC
power). Filed: #276 (GR-18 linear light), #277 (GR-19 the HDR timeline), #278 (more log curves),
#279 (header-only colour tags), #280 (the reverse's toe shift on log), #281 (PQ ignores HDR10
metadata), #282 (log thumbnails), #283 (full-range log files). #264 and #256 closed. The root
`CLAUDE.md` ADR entry is applied.
