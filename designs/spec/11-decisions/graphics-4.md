# Spec §11 — decisions: Graphics, an export's even pixel dimensions (road map 10)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the G- series of [`graphics.md`](graphics.md), so a citation never has to say which
file. This file holds G-33. G-34 on are in [`graphics-5.md`](graphics-5.md). It is new because
`graphics.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries moved here
unchanged, and an "above" or "below" in one may now point into a sibling file.

- **G-33 — On every export row that needs even pixel dimensions the CORE
  resolves and lists the even size the file will have, so the size
  reported is the size written and no size of the canvas's own shape is
  refused for being odd; `hevc_alpha`,
  "HEVC with Alpha (MOV)", is a tenth row whose frames carry the canvas's
  alpha; every movie row FILLS the frame instead of padding it when the
  miss is within a pixel; a missing encoder ends in the preset's own
  sentence and no file** (issue #103, 2026-10-05, issue batch B85, phase
  3). Built in two phases, gated in order and committed apart: A is the
  even rule alone, which moved the REPORT and no picture (commit 979440f);
  B is the row, the fill rule, the guard's test, the encoder outcome and
  the Document tab's note. Every figure below was measured by the designer
  on 2026-10-05 (Apple M2 Max, macOS 26.5.1, ffmpeg 9.0.2) in a scratch
  `AVAssetWriter` program at 320 × 180 and 30 frames, unless it says "on
  the built app": those are `tools/proof/hevc_alpha_proof.py`'s, on the
  same host and day, one-second exports no larger than 1296 × 728. That
  proof's `--rows size` was phase A's gate, and its row G1 is red by
  design on a build that holds phase B (it requires the pad the baseline
  recorded and an unknown `hevc_alpha`).
  (a) **Whose choices.** Batch B85's choices 12–17, accepted as
  recommended on 2026-10-04: a NEW format row "HEVC with Alpha (MOV)"
  directly after "HEVC (MP4)", `hevc_alpha` to the `export` tool; `.mov`,
  AAC sound, HEVC's Quality tiers and bit-rate controls, "optimize for
  network use" off by default; the sheet's summary says "alpha" (its
  footnote's text is "HEVC_ALPHA · MOV · alpha". On the built app the
  footnote's slot beside the sheet's three buttons is 88 pt and that line
  needs 144, so it is DRAWN cut with a tail ellipsis, before the word — a
  footnote gives way before a button (#141), and ProRes 4444's
  "PRORES4444 · MOV · alpha" has been cut the same way, 144 pt in 88,
  on this build (measured beside it). Its TOOLTIP is the whole line:
  `syncReadout` writes the tooltip after the text and clears it where it
  clears the text, so resting the pointer on the footnote shows "HEVC_ALPHA
  · MOV · alpha" (the proof's row E1 requires the layout dump's `tooltip`
  to equal the text; on the build before those two lines it read the empty
  string `sheetFootnote("")` set once). ProRes 4444's footnote takes the
  same two lines and no row opens the sheet on it. So the choice holds of
  the footnote's text and its tooltip and NOT of the sheet's drawn face;
  the sheet's layout is not changed by this entry, and (h) names what is
  left); the `export` tool's
  `preset` description names
  the three rows that keep transparency and its answer reports `preset:
  "hevc_alpha"`, `container: "mov"`, `codec: "hevc_alpha"`; the Document
  tab's note becomes "Transparent — kept by 3 export formats." (one or two
  rows are still named; three or more are counted, because three names
  run to about 295 pt in a row 244 pt wide at the inspector's narrowest;
  on the built app the counted note is 183 pt); a custom size of a different
  shape from the canvas is refused with ProRes 4444's sentence; the row is
  always listed, and a Mac whose encoder refuses it ends with "This Mac
  cannot export with the “hevc_alpha” preset." and no file. The owner's
  four answers of 2026-10-05: a miss of under a pixel is FILLED rather
  than fitted on `h264`, `hevc` and `prores_422`; an odd size is NEVER
  refused — the owner's answer (c): the core resolves and reports the even
  size that will be written (as built this holds of every size of the
  canvas's own shape; section (c) below says what becomes of a typed size
  of another shape) — which SUPERSEDES choice 18 (a) of 2026-10-04 (a
  refusal in a sentence of its own: there is no such error case and no
  such sentence); ProRes 4444 is filled too; and the sheet's footnote
  keeps the core's codec as it prints every row's, `HEVC_ALPHA`. One
  choice was left to the orchestrator, who took the NARROWER of two fill
  rules the same day and then amended its first arm, because as built it
  refused an odd size typed in the canvas's own proportions ((c) below
  says which, why, and what the amendment costs).
  (b) **The even rule (phase A).** A row is EVEN-SIZED when AVFoundation
  writes it (`avf_preset` is not null) and its codec is not `prores4444`
  (`Preset::even_sized` in `export_table.rs`): `h264`, `hevc`,
  `prores_422` and the three audio-only rows, which have no picture and go
  on listing what `h264` lists — and `hevc_alpha`. `prores_4444`, `gif`
  and `apng` KEEP an odd edge.
  A new AVFoundation row is therefore even-sized until someone exempts it,
  and `core/tests/export_size.rs` fails on a row nobody classified. On an
  even-sized row each edge is resolved on its own
  (`export_size::even_size`): below 2 it is 2, an odd edge is one SMALLER,
  an even edge is itself. The core applies it in the two places a size is
  answered: `Project::export_settings`, after the width and height are
  read (the override, else the preset's cap, else the canvas) — an image
  format is fitted as before, else an even-sized row answers the even
  pair, else the pair as asked — and `Project::export_sizes`, whose
  `document` row on an even-sized row holds the canvas evened and is named
  exactly "Document (even)" when those are not the canvas's numbers and
  "Document size" when they are. The id stays `document`; the standard
  rows are unchanged (the short edge named, the long edge to the nearest
  even integer, a tie going up); no key is added to either answer. **Down,
  because** it is the size `ExportWriter.evenDimension` already wrote on
  `h264`, `hevc` and `prores_422`, so the change moves the report to the
  file and no shipped file changes size; rounding up would hand the
  encoder a frame larger than the picture on that axis; and every listed
  row is then its own fixed point (a row's numbers sent back as `width`
  and `height` resolve to themselves). **What reports it.** The Size
  popup's title (`"\(name) · \(width) × \(height)"`), the sheet's readout
  and the size fields under a popup row, and the `export` tool's `width`
  and `height` each print the resolved pair, and each is proved
  (`hevc_alpha_proof.py`: rows R1–R4 hold the tool's answer to ffprobe's
  reading of the file, and E2 reads the popup, the readout and the two
  fields off the sheet — on a 321 × 181 document all of them say 320 ×
  180, where the build before this entry answered 321 × 181 beside a 320 ×
  180 file; the baseline recorder requires that failure before it writes,
  and its two recordings agreed on every value they kept). The queue's
  tooltip prints the same `ExportSettings` value BY CONSTRUCTION and no
  row reads it: the sheet hands its own resolved settings to
  `enqueueExport`, `ExportQueueController.Job.settings` is a `let`, and
  `ExportQueueRowView.toolTip(for:)` prints its `width` × `height`; no MCP
  tool adds a job and Add to Queue ends in a save panel.
  `ExportWriter.encodedSize` stays as the floor under any other caller and
  is the identity on what the core answers. In Custom the fields keep what
  was typed and the readout shows the resolved pair. **What does not
  move.** No stored value: `ExportChoice` keeps a row id (`document` is
  unchanged) or the typed pair, which stays as typed and resolves even on
  use; `get_project` reports the canvas and nothing about export. On an
  even canvas with no odd size asked, and on `prores_4444`, `gif` and
  `apng` on any canvas, the settings object is byte-for-byte what it was.
  Where an odd edge is evened — the Document row on an odd canvas, or an
  odd size asked for on any canvas (R4's `h264` at `[321, 181]` on 640 ×
  360) — the settings object's `width` and `height` are the even pair; the
  frame the encoder is given, the scaling mode and the picture are what
  they were; and what changes in a FILE is a bit rate computed from that
  pair. There are two. The DEFAULT, when no rate is asked, which
  `ExportWriter.defaultVideoBitrate` computes from the resolved pair: 0.25
  % lower at 1001 × 667 (2,797,200 against 2,804,201 bits per second for
  `h264` at 30 fps, by arithmetic) and identical under its 1 Mbps floor at
  321 × 181. And the rate a chosen Quality tier of the sheet sends, which
  is computed from the frame the controls ask for
  (`ExportSheetResolve.requestedFormat()`, by reading): with the Size
  popup on its first row that is the Document row's numbers, now even, so
  the tier is computed over the smaller area too — but
  `QualityTier.videoBitsPerSecond` rounds to the nearest 100 kbps, so the
  rate sent moves only where the smaller area crosses a rounding step
  (High for `h264` at 1001 × 667 is 2,600,000 either way, by arithmetic:
  2,583,871 and 2,577,420 before rounding). On another row of the popup it
  is that row's numbers, which did not move, and in Custom the TYPED pair,
  as before, even where the file is a pixel smaller. This amends
  `export_size.rs`'s earlier "a Document size that was not the document's
  size would be a lie" — the lie was a row that said 321 × 181 over a file
  of 320 × 180 — and spec §7.8's Document row.
  (c) **The fill rule.** One shape test, in integers, shared by the alpha
  guard and the scaling mode (`ExportWriter.shapeGap`; nothing else
  compares shapes). With `cw`, `ch` the canvas's rounded width and
  height (each at least 1) and `bw` × `bh` the frame the encoder is given:
  `d = bw*ch − bh*cw` and `gap = |d|`. `gap == 0` is the canvas's exact
  shape. When `d > 0` the frame is wider than the canvas's shape: a fit
  leaves `gap/ch` px of width uncovered and a fill overshoots the height
  by `gap/cw` px; when `d < 0` it is the other way round. `limit` has two
  arms. **A canvas-shaped size less at most one pixel on each axis** —
  `(bw + a)·ch == (bh + b)·cw` for some `a`, `b` in {0, 1}, which is `d`
  one of 0, `cw`, `−ch` and `cw − ch`: `max(cw, ch)` — the fit leaves at
  most a pixel OR the fill overshoots by at most a pixel. **Any other
  frame**: `ch` when `d > 0`, else `cw` — the fit leaves at most a pixel,
  which is the phase-7b guard in integers. `gap <= limit` is "within a
  pixel", `<=` and in integers on purpose: an evened canvas whose odd edge
  is the SHORT one sits exactly on the limit (181 × 320 into 180 × 320:
  gap 320, limit 320). A frame with `0 < gap <= limit` is FILLED
  (`AVVideoScalingModeResizeAspectFill`), whatever the codec; `gap == 0`
  and `gap > limit` are fitted as before (`…ResizeAspect`), and on a row
  whose `alpha` is true `gap > limit` is REFUSED with
  `alphaAspectMismatch`'s sentence instead, so an alpha row is exact or
  filled and never padded. **No size of the canvas's own shape is refused
  for being odd.** The evened Document row, and any `[width, height]`
  typed in the canvas's proportions (`w·ch == h·cw`, each edge at least
  2), is after the core's evening a canvas-shaped size less at most a
  pixel on each axis, where `gap = |b·cw − a·ch|` is never above
  `max(cw, ch)`: exact or filled at any scale, smaller than the canvas or
  larger, on every row. So the shape sentence's last clause, "or at any
  size with the same proportions", is true of both alpha rows. A typed
  size of ANOTHER shape is judged as the even frame it becomes, which is
  the size the sentence names, and the evening can carry a frame from
  within a pixel to past it: 1279 × 720 on 1920 × 1080 is filled on
  `prores_4444` (a fit leaves 0.562 px) and is 1278 × 720 on `hevc_alpha`
  (1.125 px), refused. **Why the
  fit's half is not enough alone:** an evened row can miss by more than a
  pixel fitted — 181 × 320 into 180 × 320 leaves 320/181 = 1.77 px and 481
  × 181 into 480 × 180 leaves 1.66 px — so the old test would letterbox
  those rows and refuse `hevc_alpha` at its own default size, on 6,285,314
  of the 16,769,025 canvases with both edges in 2…4096 (the first is 3 ×
  4). With the first arm the evened row (W−a) × (H−b), a and b each 0 or
  1, has `gap = |bW − aH|`, one of 0, W, H and |W − H| and never above
  `max(W, H)`: exact on 4,196,351 of those canvases, filled on 12,572,674,
  neither on none. A standard row's short edge is exact and its long edge
  within a pixel of exact, so a fit leaves at most a pixel and the second
  arm is enough: of 67,076,100 rows over the same canvases 1,961,452 are
  exact, 65,114,648 filled and none is neither, under the old test and the
  new alike. These counts are an integer sweep with no encoder, not the
  scratch writer's, swept with the two arms as written above (2026-10-05,
  the sweep's column `shaped`): the Document row's three counts and the
  standard rows' three are also what the arm phase B first built — the
  canvas ITSELF less at most a pixel on each axis, the column `tight` —
  printed beside them in the same run (no standard row's verdict differs
  between the two), and what the designer's wider first arm, every frame
  no larger than the canvas, printed in the run before. **Why the first
  arm is not every frame a fill would overshoot by at most a pixel:** a
  frame typed LARGER than the canvas to pad it (736 × 90 on 728 × 90, 2560
  × 1080 on 2558 × 1080, 402 × 100 on 400 × 100) is a picture written
  pixel for pixel between bars — measured at 402 × 100: `hevc`, `h264` and
  `prores_422` write 2 wholly black columns, both at the right, and the
  picture between is pixel for pixel (ProRes 4444's ramp: 0 of 402
  blended) — and stays one; a rule that looked only at the overshoot would
  fill it (gap 200 against 400), stretching 400 columns over 402 (312 of
  402 blended). None of those three is a canvas-shaped size less a pixel,
  so each is still past the limit, as 394 × 98 on 400 × 100 and 640 × 480
  on 640 × 360 are. **Why it is a canvas-shaped size at ANY scale** (the
  orchestrator, twice on 2026-10-05). The first decision was narrower
  than the designer's "every frame no larger than the canvas": only the
  canvas itself less at most a pixel on each axis, because the owner
  agreed to fill "at an under-a-pixel miss" and a hand-typed frame a few
  pixels inside the canvas is outside that. Built so, it REFUSED an odd
  size typed in the canvas's own proportions on `hevc_alpha` — `[720,
  405]` on 1920 × 1080 is evened to 720 × 404, gap 1920 against a limit of
  1080 — in a sentence naming a size the caller never sent and ending "or
  at any size with the same proportions", against the owner's answer that
  an odd size is never refused: 256 of the 512 sizes in 1920 × 1080's
  proportions with each edge in 2…8192 (every one with an odd edge), and
  on the built app `[400, 225]` and `[1296, 729]` on 640 × 360, with a
  typed 400 × 224 as `prores_4444` (the proof's row O5, which that build
  failed). The amended arm refuses none: 0 of those 512, and 0 on each of
  the ten canvases swept, as typed and evened alike. **What the amendment
  costs, accepted with it**, each because Swift is handed only the even
  frame and cannot tell a typed even size from an odd one the core
  evened: (1) 396 × 98 on a 400 × 100 document — the frame the first
  decision named, and also an evened 396 × 99 — is FILLED on every row
  (gap 400; a fit leaves 4 px, a fill overshoots 1) where it was scaled
  down between bars; (2) on a canvas whose ratio is a whole number, a
  frame typed that many pixels wider than a canvas-shaped size — 404 ×
  100 on 400 × 100, 2002 × 1000 on 2000 × 1000, each also an evened 404 ×
  101 or 2002 × 1001 — is filled where it was padded, or on an alpha row
  refused; (3) on the opaque
  rows an odd size typed in the canvas's proportions (`[720, 405]` on
  1920 × 1080 as `h264`, written 720 × 404) is filled where a fit left
  1.778 px to the pad; (4) on `prores_4444`, which keeps an odd edge, the
  same even frames typed as they are, and a frame one pixel short of a
  canvas-shaped size on both axes (395 × 98, 403 × 100 on 400 × 100), are
  written, filled, where the guard refused them; (5) the pixel is a large
  share of a tiny frame — `[16, 9]` on 1920 × 1080 is written 16 × 8 on
  the even-sized rows, the fill carrying one of the picture's nine rows
  past the frame, where it was refused or letterboxed. Among typed frames
  within 8 px of nine canvases (400 × 100, 728 × 90, 2558 × 1080, 1920 ×
  1080, 640 × 360, 181 × 320, 321 × 180, 321 × 181, 1081 × 1920) the
  amended arm fills, beyond the first decision's, 396 × 98 and 404 × 100
  on 400 × 100 on the even-sized rows and seven frames there on
  `prores_4444` (392 × 97, 395 × 98, 396 × 98, 403 × 100, 404 × 100, 407 ×
  101, 408 × 101), none on the other eight canvases, and letterboxes or
  refuses nothing the first decision wrote. (1) to (5) are by arithmetic
  over `shapeGap` — the same integer sweep, no encoder; what the built
  app wrote of them is O5's three files, below. The amended arm loses no
  row the sheet offers: an evened Document row is the canvas less at most
  a pixel on each axis by construction, and a standard row is filled by
  the second arm alone. **What is newly
  written:** on the opaque rows a frame within a pixel is filled where it
  was padded with black — the evened size on an odd canvas (2 wholly black
  rows or columns before on `hevc`, `h264` and `prores_422` in every one
  of four canvas classes measured, `prores_422` 1 row at 321 × 180; none
  after) and a standard row that misses by under a pixel (334 × 222 at
  `720p`, 1084 × 720: 2 black columns at the right before, none after).
  That is where `hevc` is no longer "the same file as before" (choice 12),
  and nowhere else: at an exact shape the encoder's dictionary is the one
  it was, and a frame further off is letterboxed as it was. On
  `prores_4444`, which keeps an odd edge, a typed frame one pixel short on
  one axis or both (400 × 99 and 399 × 99 on 400 × 100, 180 × 320 on
  181 × 320) is written, filled, where the phase-7b guard refused it, and
  so is a canvas-shaped size less a pixel at another scale (400 × 224 on
  640 × 360). On `hevc_alpha` an odd size typed in the canvas's
  proportions is written one pixel smaller on its odd edges. On
  the two alpha rows a fitted miss of under a pixel left an edge at the
  wrong alpha (`hevc_alpha` up to 16, ProRes 4444 255); filled, all four
  edges are 0. **On the built app** (the proof's rows, each beside the
  baseline the build before this entry recorded): a 321 × 181 and a 181 ×
  320 opaque red document at their evened sizes, as `hevc`, `h264` and
  `prores_422`, are red at both ends of the middle row and of the middle
  column where the baseline had two black pixels among those eight (B3);
  334 × 222 on white at `720p` has its last three columns white where the
  baseline's last two were black (B2); 400 × 100 at `[402, 100]` keeps
  exactly two black columns, 400 and 401, as the baseline has them (L2),
  and 334 × 222 at `[640, 640]` is letterboxed (L1); `prores_4444` at
  three sizes equals the baseline by frame digest, a kept odd edge among
  them (B4), and `hevc` on an even canvas equals it in the stream's and
  the file's fixed parameters and by frame digest (B1; its byte count and
  bit rates are printed, not compared — (h)). On the alpha rows every
  pixel of all
  four edges is alpha 0 — `hevc_alpha` at an evened 320 × 180 and 180 ×
  320 and at 1276 × 720 and 1084 × 720, `prores_4444` at 1084 × 720 and at
  a typed 180 × 320 on 181 × 320 (O1, O2, O4, P1, P2), and on 640 × 360
  `hevc_alpha` asked `[400, 225]` and `[1296, 729]`, written 400 × 224 and
  1296 × 728 as its answer says, and `prores_4444` at a typed 400 × 224
  (O5) — and both refuse
  402 × 100 on 400 × 100, and `hevc_alpha` 640 × 480 on 640 × 360, in the
  shape sentence, no file (S2, S1). Three mutants hold the rows to the rule: with the
  core's even rule and the fill switched off the size and fill rows fail;
  with the limit `max(cw, ch)` for every frame L2 and S2 fail — the two
  rows that tell the limits apart — and with every frame filled L1 fails.
  **What the fill costs, by ramp** (ProRes 4444; a pattern whose red and
  green carry the source coordinate and whose blue alternates 255 and 0,
  so a blend reads as a blue that is neither). ONE odd edge, 181 × 320
  into 180 × 320: output column 0 is source column 1 and output 179 is
  source 179, each unblended, so source columns 0 and 180 are read by
  nothing — one source pixel dropped on each side of the odd axis, two in
  all — and the 179 left are stretched over 180 (180/179, 0.56 %), 141 of
  the 180 output pixels a blend; the other axis is pixel for pixel (0 of
  320 blended). 321 × 180 into 320 × 180 is the same on its odd axis:
  columns 0 and 320 dropped, 319 stretched over 320 (320/319, 0.31 %), 249
  of 320 blended, 0 of 180 on the other axis. BOTH odd, 321 × 181 into 320
  × 180: nothing is dropped and every output pixel on both axes is a
  blend, 321 columns over 320 and 181 rows over 180. The same three
  FITTED, as before this entry: every output pixel of the picture is a
  blend on both axes, beside the black lines. So the scaler drops whole
  source pixels per side — one at an arithmetic overshoot of 1.000 px,
  none at 0.436, 0.50 or 0.624, two at 3.56 — and stretches what is left:
  the quotient `gap/cw` or `gap/ch` is the arithmetic overshoot and NOT
  the measured cut.
  (d) **The encoder.** The row is written by `AVAssetWriter(.mov)` with
  `AVVideoCodecType.hevcWithAlpha` (`"hevc_alpha"` in
  `ExportWriter.codecType(for:)`), fed the compositor's premultiplied
  32BGRA as every row is. Its compression dictionary is the HEVC row's —
  the average bit rate, the 2 s key-frame interval,
  the expected frame rate, and HEVC's 0.07 bits per pixel per frame when
  no rate is asked — plus `kVTCompressionPropertyKey_AlphaChannelMode:
  kVTAlphaChannelMode_PremultipliedAlpha`, which says what the pixels are
  (0 of 57,600 pixels differ from leaving it unset; the decoded buffer
  then reads `PremultipliedAlpha`). No
  `kVTCompressionPropertyKey_TargetQualityForAlpha` and no profile key:
  unset, the file's size and error figures are those of 0.75 — alpha off
  by at most 2 at 960 of 57,600 pixels on a hard-edged card and by at most
  5 on a soft disc — and 1.0 is exact on the card at 4,951 bytes against
  4,654 (7,029 against 5,753 on the disc); an alpha-quality control is out
  of scope. Decoded, in the scratch writer: `hvc1`, `ContainsAlphaChannel`
  1, pixels (0,0,0,0), (128,0,0,128) and (255,0,0,255) for clear, half and
  opaque red, through `ExportWriter`'s own shape (a custom compositor,
  `AVAssetReaderVideoCompositionOutput`, `append(sampleBuffer)`). On the
  built app a hard-edged opaque red card on a clear 640 × 360 canvas
  decodes with two alphas in the whole frame, 0 and 255, the corner
  (0,0,0,0) and the card's centre (255,0,0,255); the same card at half
  opacity decodes (129,0,0,128) at its centre; an opaque canvas decodes
  every alpha 255; and ffprobe says `hevc`, `hvc1`, `yuv420p` (rows A1–A4).
  AAC in a `.mov` is a combination no row wrote before: the file holds an
  `aac` stream at 48 kHz with 2 channels, and the export's loudness is
  measured as on every row (A5).
  (Amended by G-35 (e): the row's frames are un-premultiplied before the
  encoder and the key says `StraightAlpha`.)
  (e) **Hardware, and a Mac without the encoder.** This host lists "Apple
  Muxed Alpha-Apple HEVC (HW)" and "(SW)"; with hardware disabled the file
  still carries alpha (largest error 6). The row is always listed. A
  refusing encoder was measured with an encoder
  specification nothing satisfies, on `.hevcWithAlpha` and `.hevc` alike:
  `canApply` is TRUE, the input constructs, `canAdd` is TRUE, and
  `startWriting()` returns false with `AVFoundationErrorDomain` −11834
  ("Cannot Encode", underlying `NSOSStatusErrorDomain` −12908), leaving a
  0-byte file — so `addVideo`'s `canAdd` test does not catch it.
  `Exporter.encoderOutcome`, applied where `startWriting` hears the
  pipeline, maps exactly that domain and code to
  `ExportError.presetUnavailable` with the preset's name and removes the
  file, and returns every other result as it came. No new error case.
  `.hevcWithAlpha` in an `.mp4` is refused by `canApply` and `canAdd`, the
  existing `.presetUnavailable` branch. On the built app this is proved by
  a mutant, since no Mac without the encoder was to hand: a copy of the
  tree whose `videoSettings` adds that same unsatisfiable specification
  for `.hevcWithAlpha` answers `export` with exactly "This Mac cannot
  export with the “hevc_alpha” preset." and leaves nothing at the path
  (row X1), and the same copy with the mapping switched off answers
  AVFoundation's own "Cannot Encode" over a 0-byte file.
  (f) **How alpha is proved.** ffprobe reports `hevc`, `hvc1`,
  `Main`, `yuv420p` for an HEVC-with-alpha file and for a plain HEVC file
  in the same `.mov`, so `phase7_proof.py`'s `startswith("yuva")` test
  cannot see this row; only the DECODED frame tells them apart (plain
  `.hevc`: every alpha 255; the alpha file through `phase7_proof.py`'s
  `Raster` command: (0,0,0,0), (129,0,0,128), (255,0,0,255)). The proof's
  alpha rows read a transparent, a half and an opaque pixel back from the
  decoded RGBA, and its control `plain-hevc-reader` scores the same
  readers over plain `hevc` exports of the same two projects, where both
  fail.
  (g) **`RC_FORMAT_VERSION` stays 11.** No project stores a preset id or
  an export size; the remembered export choice is a `UserDefaults` record
  holding a row id or the typed pair, and a build without the `hevc_alpha`
  row leaves its Format popup where it was (`apply(_:)`'s `firstIndex`).
  Nothing persisted changes shape.
  (h) **Risks accepted.** Only this host's encoders were measured.
  Playback in Safari, QuickTime Player and Final Cut is a person's check:
  the row SE-9 of `docs/manual-checks.md`. The proof's baseline is this
  host's bytes: on another chip, macOS or ffmpeg the rows that read a
  digest (B1, B4, and G1 under `--rows size`) are not scored, every other
  row is, and the script exits 2 to say the claim is incomplete there.
  And B1 compares no byte count: the stream's `bit_rate` and the file's
  `size` and `bit_rate` are printed beside the baseline's and not scored
  — they are byte counts of a hardware HEVC bitstream, which the encoder
  does not promise to repeat — while the stream's and the file's fixed
  parameters (codec, tag, profile, level, pixel format, size, frame
  rates, frame count, colour values; container, stream count, duration),
  the alphas, the corner and frame 0's digest are compared. The row
  compared all of it until one full run on the built app printed `hevc`
  on an even canvas differing from the baseline in its stream and format
  values with frame 0's digest equal, where eight later reads of the same
  build were equal: not reproduced, and that line did not print WHICH
  values moved, so nothing here says it was those three — a frame count
  or a duration that moves still fails the row, by name. What the row no
  longer sees is a change of the encoder's rate — and on its 640 × 360
  fixture it could not see the line of `defaultVideoBitrate` this entry
  changed either: 483,840 at 0.07 bits a pixel and 967,680 at 0.14 are
  both raised to the 1,000,000 floor (arithmetic, not run).
  `tools/proof/README.md` has the runs. A
  canvas
  with an edge of exactly 1 px is raised to 2 on an even-sized row and can
  then be a different shape, where the shape sentence answers on the alpha
  rows: of the 8,192 canvases 1 × n and n × 1 with n in 1…4096 the evened
  Document row is neither exact nor filled on 4,094 ((c)'s integer sweep,
  the same under the old test, the designer's wider first arm, the arm
  phase B first built and the first arm as written), and a size TYPED
  with an edge of 1 is raised the same way (3 × 1 on 300 × 100 becomes 2
  × 2, refused on `hevc_alpha`) — not proved on the built
  app. The 481 × 181 class (both edges odd, wider than 2:1) is measured in
  the scratch writer only, and a both-odd canvas far from square (an
  arithmetic overshoot between 0.62 and 1 px) was not measured at all.
  Phase A's gate compares pixels only on canvases under the default bit
  rate's 1 Mbps floor; the 0.25 % lower default rate on a larger odd
  canvas, and a Quality tier's rate where it crosses a rounding step
  ((b)), are by arithmetic. A reader that ignores the declared
  premultiplied mode draws translucent pixels dark, **and Frame Job is such
  a reader**: `Compositor.swift` builds every video source as straight
  alpha and nothing in `app/Sources` reads a file's declared mode, so an
  exported `hevc_alpha` or `prores_4444` movie re-imported is multiplied
  by its alpha a second time (the proof's line I1 prints the composite
  and never scores it: on the built app a half-opaque red card over an
  opaque white canvas comes back (191,127,127) from the `hevc_alpha` file
  and (193,129,127) from the `prores_4444` one, where a correct composite
  is about (255,128,128); the ProRes 4444 file also holds premultiplied
  colour under a `StraightAlpha` label — a half-red source pixel decodes
  (129,0,0,128)). The export sheet's footnote is DRAWN cut before the
  word "alpha" on both alpha movie rows; its tooltip carries the whole
  line ((a)), and whether the summary gets room on the sheet's face — a
  line of its own, or a wider sheet, either a visible change to every
  format's sheet — is the owner's choice. What to do about any of the
  three is an issue's, not this entry's.
  **Amended 2026-10-09 (issue #243, issue batch B91; the owner chose a
  wider sheet, the issue's (b), and then "own line + wider", both of
  (a) and (b)):** the export sheet is 480 pt wide, 60 more than every
  other sheet (`ExportSheetController.cardWidth`), and its footnote is
  the content stack's last line, under the readout and above the buttons,
  no longer in the button row's leading slot — 436 pt of room where the
  slot beside the three buttons was 88 pt on the 420 pt sheet and 148 on
  the 480. Every row of the preset table draws its footnote whole at its
  default quality (the alpha movie rows' lines are 144 pt, ProRes 422's
  "PRORES422 · MOV" 90, which the 88 pt slot also cut), and so do the
  footnotes a Quality tier and a loudness target lengthen: "H264 · MP4 ·
  900 kbps · 256 kbps audio" (228 pt) and `hevc_alpha` at Maximum with −14
  LUFS (378 pt), which the 148 pt slot cut. `hevc_alpha_proof.py` E1 and
  E3 hold it: E1 and E3's first form were red on the 420 pt sheet, and E3
  as it stands (the long footnotes and the own line scored) on the 480 pt
  sheet with the footnote beside the buttons. (a)'s and (h)'s sentences on
  the cut footnote describe the 420 pt sheet.
