# Road map "grading-3" — colour grading, tier 3: honest sources, HDR→SDR, camera log

**Opened 2026-10-11** (T3-0, in the worktree `~/devel/reelcut-grading3` on branch `grading-3`,
from `f02a1f3`, merged into main after its gate). The design brief this road map answers is
`~/.claude/litecode/reelcut/grading-tier3/I-grading-tier3.md` (2026-10-11, tree `f02a1f3`), with
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
`f02a1f3`. The cap is ~600 lines, new files 400, and frozen files (`EditorViewController.swift`,
`TimelineView.swift`, `PreviewCanvasView.swift`, `AgentServer.swift`) take wiring only. Size is per
file only (root `CLAUDE.md`): nothing here is a budget on a feature or a phase.

### Tolls (T3-0, each a pure move gated alone)

| File | Lines at `f02a1f3` | Why it is touched | The move |
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
  `e1_proof.py`'s 1c3e92e pixels within ±1 and `hevc_alpha_baseline.json`'s digests —
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

**What landed** (2026-10-11, in the worktree on `grading-3`, from `f02a1f3`). This road map;
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
  the 41 frames of fixture B still matching the digests recorded from `c66d8ab`
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
