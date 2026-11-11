# Spec §11 — decisions: Graphics, props as action targets onward (road map 10)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the G- series of [`graphics.md`](graphics.md), so a citation never has to say which
file. This file holds G-34…G-36. G-37 on are in [`graphics-6.md`](graphics-6.md). It is new because
`graphics.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries moved here
unchanged, and an "above" or "below" in one may now point into a sibling file.

- **G-34 — A graphic's props are action targets: a number and a colour
  ramp, a string, a boolean and an enum switch at the action's end, an
  asset is refused; supersedes G-10's first sentence and its error, and
  amends G-32 (e)** (issue #239, 2026-10-07, issue batch B87; the owner's
  seven answers, each "as recommended", are (b), (d), (e), (f), (g), (i)
  and the limits, and the owner's answer on the paste is (d)). G-10's
  layer half stands, and so does G-32 (h): `graphic` is not a
  `patch::Group`; the action door has its own graphic arm.
  (a) **The shape.** An action's `end` may carry `graphic: {props: {<key>:
  <value>}, kinds: {<key>: <type>}}`. `set_action_end` writes each named
  prop's schema `type` into `kinds` and removes it with the prop. A
  `kinds` in a patch is read and DISCARDED, whatever it holds, because
  every named prop's kind is rewritten from the schema; so an end read
  back from `get_project` can be sent again, and a caller never decides a
  kind (G-4). `name`, `width`, `height`, `in` and `length` are errors
  (`graphic.<key> is not an animation target; an action animates
  graphic.props`); any other key is an unknown key.
  (b) **Which kinds move (answers 1 and 2).** A `number` and a `color` ramp
  along the action's curve. A `string`, `boolean` and `enum` hold their
  start and take the end's value at the action's END, as every
  non-numeric property does (§5.4). An `asset` is an error naming the prop
  (`graphic.props.<key> is an asset; an action does not animate an image —
  set it with set_graphic`). (Amended by G-41: a prop whose schema entry
  says `animate: false`, of any type, is refused too, in its own sentence,
  checked before the asset's.) (Amended by G-42: an asset is no longer
  refused; it switches at the action's END, as a string does, and `""`
  names no image in an end.)
  (c) **How the kind is known, and the check.** From the `schema` the op
  carries. The app fills it from the module's CURRENT revision and never
  takes it from a caller (G-4; a `.filledByTheApp` row). A non-null prop
  with no schema is an error naming it (`graphic.props.<key> needs its
  module's schema to animate, and none came with the op`). A prop the
  schema lacks is `unknown key "graphic.props.<key>" in an action end
  patch`. Every value is checked as `set_graphic` checks it (type,
  `min`/`max`, options, length, a colour normalised) and refused under
  `graphic.props.<key>`. This is the one end that IS range-checked (§5.4's
  ends are not), because nothing clamps a prop: the engine reads no
  `min`/`max`, and `clamp_video` never sees `graphic`. Every curve is
  monotone (§5.4), so a ramp between two in-range ends stays in range.
  Only the props a patch names are checked; a stored end is never
  re-checked. So when a module later narrows a range, a project holding an
  old end still opens and renders as stored (the module is handed the old
  value, as it is a stored base prop), an edit naming another prop of that
  end is not refused, and only a new value for that prop is checked. The
  evaluator knows a colour by `kinds`, never by a value's shape; two numbers
  ramp whatever `kinds` holds, which is how a version-12 end ramps its
  numbers ((k)).
  (d) **The start (answer 4).** The first time an action names a prop that
  the clip's own `graphic.props` does not hold, the schema's CURRENT
  default (a colour normalised) is appended to it in the same edit, so in
  the same undo step. A later change to the module's default does not move
  it. The start is kept in two places it would otherwise be lost.
  G-15 (b)'s "A value equal to the schema's default is written as `null`"
  gains one exception in the core: `set_graphic` with a schema answers a
  `null` for a prop that
  an action on that clip names by storing the schema's default; without a
  schema, or for a key the schema lacks, a `null` still removes. And
  G-32 (e) is amended (the owner's answer, 2026-10-07): Paste Graphic
  Properties, and `paste_attributes`' `graphic` group, KEEP a target key
  the payload lacks when an action on the target names it, in its slot,
  so the ramp survives the paste. Every other key pastes as G-32 (e) says.
  (Amended by G-42: an asset's start is its string default, or `""` when
  its default is `null`.)
  (e) **Numbers arrive fractional (answer 5)**: `a + (b − a) × eased` in
  floating point, never rounded and never snapped to `step`, so two whole
  ends 64 and 129 give 96.5 halfway. A module that needs a whole number
  rounds it. A module written before this entry that does
  `new Array(props.count)` throws on a fraction and draws its error card
  for those frames (G-8), which stops an export.
  (f) **Colours blend channel by channel (answer 6)**, as every colour
  action already does (the model's `[r, g, b, a]`, element by element).
  (Amended by G-43: the model's colours blend in OKLab too, so no colour
  action blends channel by channel.)
  The red, green, blue and alpha of the two `#rrggbb[aa]` strings (no alpha
  is 255) each interpolate STRAIGHT, not premultiplied: `#00000000` to
  `#ffffff` is `#80808080` halfway. Each channel is rounded to the nearest
  byte and the result written as G-12 writes a colour (`#rrggbb` when the
  alpha is 255). Not OKLab. (Amended by G-40: a colour prop blends in
  OKLab, as `interpolateColors` does, with straight alpha; `#00000000` to
  `#ffffff` is `#63636380` halfway; the rounding and written form stand.)
  (g) **Playback (answer 7).** Nothing is built. Every frame of an
  animated prop is drawn at the recorded per-frame cost, so a graphic that
  had settled misses its texture for the action's span. A
  `docs/manual-checks.md` row watches a 4K clip with an animated prop for
  stutter. #127 stays deferred.
  (h) **Evaluation.** Each finished action's `graphic.props` is laid over
  the clip's map in start order, then the spanning action's are
  interpolated. `clip_state` answers the result as `graphic` beside
  `shape`, and the recipe's `props` and `props_json` (and so its hash,
  G-9·b) are those values. The texture key, the export pin (G-13) and the
  prefetch (G-26) do not change. The evaluator is total. Two values of
  different JSON kinds, a colour it cannot read, a malformed `graphic`,
  `props` or `kinds`, and a prop with no start (removed by a `set_graphic`
  without a schema, or a hand-written end) all hold, then switch at the
  end; no frame fails.
  (i) **Edits.** `split` gives the second half the props evaluated at the
  cut, and gives a straddled action's first half an end of those values,
  so a split is invisible: a number exactly on a linear curve (to
  floating-point rounding), a colour to within one byte per channel, and
  on an eased curve at its ends, as for every property. `trim_start` and
  `roll` touch an action's span, never its end; an op under `scope` acts
  on the nested clip as on any other; `rate_stretch` and `set_speed` are
  media-only. `get_project` shows an end as stored, `kinds` included. The
  inspector edits an end as it edits every animated property (CI-1, CI-2,
  CI-6, CI-7, CI-9): the Graphic tab stops being the exception (answer 3).
  (j) **Removing.** `graphic: null` and `graphic.props: null` remove the
  group from the end. A `null` prop removes the prop and its kind,
  unchecked, so a stale key can go. `off` cannot name `graphic` (`graphic
  props cannot be keyed off; name the value a prop ends at in patch`).
  `video.motion` and `text.words` stay errors in their own sentences (W-6).
  (k) **Format version 13**, so an older build refuses the file instead of
  drawing it un-animated. There is no migration step: an end is stored as
  found. A file of version 12 or older whose end already names `graphic`
  (hand-written or pasted; G-10 kept it inert) now animates by these
  rules, its colours switching at the end for want of `kinds`.
  (l) **The Graphic tab** (issue batch B87 phase 3, 2026-10-07). With an
  action of a graphic clip selected, the Properties rows show the selected
  action's END state (`clip_state`'s `graphic`, CI-2), and a row's write is
  ONE `set_action_end` naming `graphic.props.<key>`, carrying the module's
  current schema, filled by the app ((c)). The end takes the value itself,
  never `null`, because a `null` in an end removes ((j)); G-15 (b)'s null
  rule stays the base's. An asset is the base's: its row writes
  `set_graphic` as before, marked ⊘ and still changing the clip, the way
  CI-3 sends a structural write to the base. With no action selected every
  row writes `set_graphic`, as before. The owner's answers, all as
  recommended: a keyed string row's one-line field narrows by about 35 pt
  and reads "at end" only while the selected action keys it, and is full
  width otherwise (O1); a key the end names that its module no longer
  declares gets a stale row of its own — ◆, the end's value and ⌫ ("The
  module no longer declares <key> — remove it from action N") — beside the
  clip's own stale row for that key (O2); a graphic action's band is
  labelled with the prop keys its end changes ("accent, size"), and an
  end's empty `graphic.props` does not stop a zoom being one (O3); the
  Graphic sub-tab's and the Properties section's `◆N` count the keys of the
  end's `graphic.props`, a stale key included (O4, CI-6 amended); the Text
  tab's keyed Content row reads "at end" (O5). Two follow from answer 3
  with CI-7 and CI-9: with an action selected, Width, Height and Follow
  Clip show ⊘, since their writes never reach `set_action_end` and (a)
  refuses those keys in an end (O6); and Properties' Reset writes the end
  through the same split, each declared prop's default into the end and an
  asset's `null` to the base (O7). ◇, Clear, the gutter's ×, the row menu's
  "Set end value to default", the slider's mint segment and coral playhead
  tick are the shared pattern (CI-6, CI-7, CI-9), not new rules.
  **A row short of room: the CONTROL gives way, never the tag** (O8, on
  every tab). Every row's "at end" / "now …" tag is one line
  (`InspectorRowTag.maximumNumberOfLines = 1`): a wrapping tag gave its
  width away by growing tall, so a row short of room squeezed it into a
  sliver instead of narrowing a control. What gives way is fixed by
  priority, below the tag's compression resistance (750): the one-line
  string field (≤ 170 required, == 170 at 249, O1; G-48 drops the cap,
  the field taking the row at 248) and, in `inspectorRow`,
  the row's widest pop-up, or in a row with no pop-up its widest checkbox
  (its intrinsic width held at 749). A row with room is untouched; the rows
  the tag leaves short at `DS.panelWidth` are Font ▸ Family (150 → 140), a
  filter's kind (92 → 74), an obscure region's kind (96 → 74) and a
  module's boolean whose label is longer than about 200 pt (its title
  cut at the checkbox's edge), each narrowing only while keyed and full width
  otherwise (`graphics_inspector_proof.py` K18a, K18b, K18c). (Amended by
  G-42: with an action selected an asset's row writes the end like any
  other row, ◇/◆ and never ⊘, its "None" writing `""` there; Properties'
  Reset writes an asset's default into the end, `""` for `null`.)
  **Limits accepted (answer 3).** A clip's actions do not overlap, and one
  action has one span and one curve for everything it animates. There is
  no per-prop opt-out: a module's own animation composes by being handed
  that frame's value. A prop that a later revision renames or drops stays
  in the end, and the engine passes it through with a warning. `kinds`
  goes stale only if a module changes a prop's type. (Amended by G-41: a
  module may mark a prop `animate: false`, and an action then refuses it;
  a module's own animation still composes by being handed the frame's
  value.)
- **G-35 — A video frame is composited as premultiplied only when its
  buffer says so, and every other frame, an unlabelled one included, as
  straight; the two alpha movie rows are written STRAIGHT — each frame
  un-premultiplied, its transparent pixels' colour filled from the
  nearest visible pixel within 4 px, and labelled `StraightAlpha` —
  so a re-imported export composites to the right colour; amends G-33
  (d) and the reader sentence of G-33 (h)** (issue #242, 2026-10-09,
  issue batch B92, phase 2).
  (a) **Whose choice.** #242 offered two ways, reading the declared mode
  on import or un-premultiplying before encoding. The owner, 2026-10-09:
  "I think we should do both. Compensate for other apps, but export
  straight." And: "We're not using Reelcut in any real work yet, so we
  don't generally need to worry about old files."
  (b) **Import.** `Compositor.swift`'s track source asks
  `MetalRenderer.declaresPremultipliedAlpha` about each frame
  `request.sourceFrame(byTrackID:)` hands it: true only when the
  buffer's `kCVImageBufferAlphaChannelModeKey` attachment equals
  `kCVImageBufferAlphaChannelMode_PremultipliedAlpha`; absent or anything
  else is straight, so an unlabelled movie draws as it always did. The
  answer is the layer's existing `premultiplied` uniform, which
  `layerSample` already divides by, as it does for a text, shape, image or
  graphic texture: no uniform and no shader code changes. It is asked per
  BUFFER, not per file: the decoder attaches the mode to the frames it
  hands over ((f)), and no format description is read for it (a
  synchronous `formatDescriptions` would be a fifth deprecation, and
  `async` stays where W-8 put it). This fixes a premultiplied movie from
  another application (After Effects, Motion) as well as an `hevc_alpha`
  file made before this entry.
  (c) **Export.** On the two rows `ExportWriter` writes whose `alpha` is
  true — `prores_4444` and `hevc_alpha`; `apng` is `ImageSequenceWriter`'s
  and is unchanged — the video pump straightens each frame after the
  reader hands it over and before it is re-timed
  (`ExportStraightAlpha.straighten`): in place on the reader's own copy of
  the 32BGRA buffer, every pixel with a > 0 becomes
  c' = min(255, (c·255 + ⌊a/2⌋) / a) in integers, and the buffer is
  wrapped in a new sample whose format description is made from it. The
  division is exact for 8 bits: re-premultiplying with (s·a + 127) / 255
  gives back c for every one of the 32,895 pairs 0 ≤ c ≤ a, a in 1…255
  (R0, (f)). The rows are split over `DispatchQueue.concurrentPerform`
  inside the video pump. A frame that cannot be straightened (not
  32BGRA, not lockable, no sample made) stops the export with "A frame's
  transparency could not be written straight."
  (Amended by PR-3: the reader's frames are `64RGBAHalf`. `prores_4444`'s
  frame is un-premultiplied in place in float, s = min(1, c/a) for a > 0,
  then filled by (d)'s rule over its half-float pixels; `hevc_alpha`'s is
  first rounded to 8-bit premultiplied BGRA, round(v·255), into a pooled
  32BGRA buffer and then straightened by this paragraph and (d) unchanged.
  A frame in neither format stops the export with the sentence above.)
  (d) **The fill.** Un-premultiplied, a transparent pixel is black at
  alpha 0, and a codec that subsamples colour (HEVC's 4:2:0) or a scaler
  that resamples the frame (the writer's own, at a size off the canvas)
  can carry that black into a half-transparent edge pixel beside it: a
  dark fringe on a straight file. So a pixel with a = 0 within Chebyshev distance
  `ExportStraightAlpha.bleedRadius` = 4 px of a pixel with a > 0 takes
  that pixel's straightened colour — the nearest by dx² + dy², a tie
  going to the first in row-major order — and keeps alpha 0; every other
  a = 0 pixel is left as it was. The nearest is found without walking the
  square: pass 1 records, per row with a visible pixel, each column's
  nearest visible pixel in that row (its smallest |dx| ≤ 4, a tie to the
  left), and a transparent pixel reads that entry in each of the 9 rows of
  its band, top to bottom, keeping only a strictly smaller dx² + dy² — the
  same pixel the sorted square named (issue batch B93 phase 2, #254; K1
  holds the two byte-identical). The fill reads only pixels with a > 0,
  which it never writes, so in place is race-free. A band of rows with no
  visible pixel within 4 rows is skipped whole. The fill changes no alpha
  and no visible pixel, so a reader that composites straight colour by
  its alpha draws the same picture with or without it; what it changes is
  the colour the codec averages into an edge ((f), F1).
  (e) **The labels.** Each straightened buffer carries
  `kCVImageBufferAlphaChannelModeKey` = `StraightAlpha`
  (`.shouldPropagate`), which the ProRes 4444 encoder writes into its
  file, and `hevc_alpha`'s `kVTCompressionPropertyKey_AlphaChannelMode`
  is `kVTAlphaChannelMode_StraightAlpha` where G-33 (d) set
  `PremultipliedAlpha`. Decoded, either row's frame reads `StraightAlpha`
  (M1).
  (f) **The figures** (2026-10-09, Apple M2 Max, macOS 26.5.1, ffmpeg
  9.0.2; `tools/proof/hevc_alpha_proof.py` on the gate's Release build,
  39/39 with the phase review's F2 and Q1, and its mutants on Debug copies; the probe is
  `tools/proof/alpha_mode_probe.swift`). **I1:** FAINT's half-opaque red
  card, re-imported over an opaque white canvas, composites (255,128,128)
  from the `prores_4444` file and (255,127,127) from the `hevc_alpha` one,
  where G-33 (h) recorded (193,129,127) and (191,127,127); the files' own
  centres decode (255,0,0,129) and (255,0,0,128) (A2's is the second).
  **M1:** the first decoded frame of either file reads `StraightAlpha`,
  and so does its track's format description. **T1:** the probe's
  premultiplied (128,0,0,128) card labelled `PremultipliedAlpha` — a
  third-party writer's file, decoding (129,1,0,128) from ProRes 4444 and
  (128,0,0,128) from HEVC with alpha, both labelled `PremultipliedAlpha`
  — composites (255,129,127) and (255,127,127); with the helper answering
  false (mutant `import-straight`) the same files composite (193,129,127)
  and (191,127,127). So the decoder's attachment reaches
  `request.sourceFrame(byTrackID:)`. **T2:** an unlabelled (255,0,0,128)
  ProRes 4444 card decodes `StraightAlpha` and composites (255,128,128).
  **F1:** a red 200 × 200 disc on a clear canvas, exported, re-imported over
  white and compared with the same disc drawn on white over all 230,400
  pixels: the largest channel difference is 1 on `prores_4444` and 18 on
  `hevc_alpha` (2 pixels over 10). Without the fill (mutant `no-bleed`) it
  is 2 and 100 (324 pixels over 10 on `hevc_alpha`, the worst (155,31,30)
  against (255,3,3)): at the document size the fill is what keeps an
  HEVC edge from darkening, and ProRes 4444's 4:4:4 colour does not need
  it. **F2** (off the canvas's size, through the writer's scaling): the
  same disc exported at `720p` (1280 × 720, ×2) and re-imported over white
  at that size, where a red disc keeps red at 255 at every pixel: red falls
  at most 0 on `prores_4444` and 2 on `hevc_alpha`; without the fill 26 and
  45 — a scaled export needs the fill on BOTH rows. Against the same disc
  on white exported at `720p` as `prores_4444` (an opaque frame through the
  same scaler) the edge differs by up to 73 and 75 in a ring of about
  3,100 pixels, which is not a fringe: the scaler resamples a frame's
  alpha apart from its colour, and down column 640 the alpha file's top
  edge reads alpha 51, 203, 255 where the opaque file's coverage reads
  0.09, 0.51, 1 — the alpha edge sits about a third of a pixel outside the
  opaque one. **Q1:** the first cached thumbnail — the JPEG
  `AVAssetImageGenerator` and CoreGraphics make, which the filmstrip and
  the Media tab's row draw — of I1's two straight files, T1's two
  premultiplied-labelled ones and T2's unlabelled one reads (255,127,126)
  at the card's centre for all five: half red over white, the label
  honoured by the generator with no change here. **R0:** 0 mismatches of
  the 32,895 pairs; the 16 × 16 fill exact; the tie to (4,8). **Speed**
  (B93 phase 2, 2026-10-09, Apple M2 Max, macOS 26.5.1, on a host other
  sessions loaded, `vm.loadavg` 25 then 11 over the run;
  `--measure straighten-speed`: the probe built `-O` with whole-module
  optimisation, as the Release app is; 12 cores; best of five, the fill
  before B93 timed on the same frames in the same run, alternating): an
  opaque card on a clear frame 0.53 ms at 1920 × 1080 and 0.87 ms at
  3840 × 2160 (before B93 0.56 and 0.71 ms); soft alpha at every pixel
  (pass 1 divides them all) 0.81 and 2.98 ms (0.86 and 2.87 ms); one
  visible pixel in every 9 × 9 block (pass 2's worst case, nearly every
  pixel transparent and within reach) 0.88 and 3.33 ms (14.78 and
  59.16 ms; B92 recorded 15.1 and 61.4 ms). **K1** (B93): the fill and the
  one before it give the same bytes, padding included, over 65 seeded and
  lattice frames and all 3,160 pairs of visible pixels around a
  transparent centre, 216 of them ties.
  The unoptimised probe takes 33–41 ms for the 1080p card frame. B4:
  `prores_4444`'s sizes and sampled alphas equal the baseline's, and its
  frame digests moved, as (c) and (d) intend.
  (g) **`RC_FORMAT_VERSION` is unchanged and nothing is migrated.**
  Nothing persisted changes shape. An `hevc_alpha` file written before
  this entry is labelled premultiplied and now composites right on import
  ((b)); a `prores_4444` file written before it holds premultiplied
  colour under a straight label and still composites dark. It is not
  relabelled or re-encoded: the owner's answer in (a).
  (h) **Risks accepted.** The writer's own scaling
  (`AVVideoScalingModeKey`) of a straight frame was measured at one size
  off the canvas, ×2 (F2: no fringe with the fill), and its alpha edge
  lands about a third of a pixel from where an opaque row's does; a
  downscale was not measured. A reader that scales the file down by more
  than about 4× or blurs it further than the fill reaches can still pull
  black into an edge. A frame of scattered visible pixels costs pass 2
  the most: 61 ms at 3840 × 2160 in the optimised build, nearly twice a
  30 fps frame's time, so such a 4K export runs slower by up to that much
  a frame; a title, a card or soft alpha costs under 3 ms. Thumbnails,
  filmstrips and poster frames go through CoreGraphics, not (b), and
  draw both labels right (Q1). Only this host's
  encoders and decoders were measured; playback of either row in Safari,
  QuickTime Player and Final Cut is a person's check (`docs/manual-checks.md`
  SE-9). G-33 (h)'s sentence that Frame Job is a reader that ignores the
  declared mode, and its I1 figures, describe the build before this entry.
  **Amended by CX-17** (codec-export C5): the straightening reaches a third
  movie row, `vp9_alpha_webm`, whose 64RGBAHalf frame is straightened in
  place in float by PR-3's `prores_4444` pass and (d)'s fill before the
  bundled encoder's conversion; a frame that cannot be straightened stops
  the export with (c)'s sentence. Its WebM carries no alpha-mode label:
  VP9's alpha is straight by its codec mapping.
- **G-36 — Playback rasterizes upcoming graphic frames ahead on worker
  threads too; the compositor stays the one consumer and the texture key
  decides** (issue #127, G6 phase 2, 2026-10-21; amends G-26 (a)).
  (a) **Where.** On the document's own key, while the transport's rate is
  above 0, the project draws a graphic clip (on the timeline or in any
  nest), the switch is off and an item is built
  (`Playback+Prefetch.swift`'s `syncPrefetch(from:)`). Never while paused,
  in reverse, for `render_frame`, or on an export's key.
  (b) **The grid.** A session starts at its start time — the seek's
  target when a seek starts it, else the playhead — snapped down onto the
  composition's frame grid from 0, at the built composition's
  `frameDuration`. It ends at the in/out range's end while playback loops
  inside that range, else at the composition's end.
  (c) **Restart.** Play, a seek (at its target, a loop's return included),
  an item swap and a property-only edit while playing each stop the
  session and start a fresh one. Pause, a rate of 0 or below and
  `invalidate` stop it.
  (d) **Follow.** Every compositor request reports its time
  (`GraphicPrefetch.reach`). A worker never claims a frame at or before the
  last one the compositor reached; the frames it passes over are counted
  `skipped`. A held raster of a frame before the reached one is dropped as
  unused, freeing its room. A request outside the session's range is not
  followed, and a seek's session (a loop's return included) follows
  nothing until a request lands in its first four frames: a seek installs
  the new session before AVFoundation cancels the old position's requests,
  and those served in between must not move the new one's floor.
  (e) **Bounds.** G-26 (d)'s, per session: `activeProcessorCount − 1`
  workers, `4 × workers` slots and 1 GiB of rasters. An export running
  alongside has its own session. **The owner's choice** (2026-10-21): first
  the same limits as an export's, with no setting; then, shown the
  measurement below, no fixed limit at all — memory limits are relative to
  the Mac (one budget of 25 % of physical memory, given back under memory
  pressure; 16 GB is the floor, 32 GB the usual machine), and drawing ahead
  while paused is a setting, as in Final Cut. #127's next phase replaces
  this paragraph's 1 GiB and slot count, and G-26 (d)'s, with that budget.
  Until it lands the bounds below stand. **What the bound holds, and
  what it does not:** the 1 GiB and the slots bound only the finished
  rasters HELD ahead for the compositor. Outside them are each worker's
  raster in flight (its output and the images it decodes, one per worker
  at a time) and the freed large blocks the system allocator keeps
  resident after them, which stay counted in the process's memory after
  the play until the system needs them. Measured on parive-promo's
  `section` scene (Release, 12 cores, 11 workers, 2026-10-21, fix pass 1's
  instrumented copy): the held rasters peaked at 373 MB in 53 slots, under
  the bound (the slot limit binds first; a frame's layers go in together,
  so the count can pass `4 × workers` by a frame's worth); live large
  allocations were 855 MB in mid-play, the allocator's kept free blocks
  602 MB then and 939 MB after; the process's footprint rose from 366 MB
  to a peak of 2.07 GB while playing (the serial path, the switch on:
  116 MB to 392 MB) and stood at 1.24 GB after the play (serial: 499 MB).
  (f) **The switch.** `FrameJobGraphicPrefetchOff` turns both off.
  (g) **Purity.** G-26 (c) holds unchanged, so every preview frame is the
  serial path's bytes (G-5). A wait that `stop` ends counts as neither a
  hit nor a mismatch. In a following session, a slot the worker left to
  the compositor's pool (the same-texture shortcut) that reaches `take`
  counts `missed`, because playback may have dropped the earlier frame
  whose raster the pool was to hold. The session's log line is an
  export's with `, playback from <start>, <skipped> skipped` appended.
  (h) **Preview Quality.** It does not shrink a graphic's raster (G-7), so
  Quarter gains little: measured on parive-promo's `section` scene (clip 8
  from tick 25 120 000, 10 s, Release, 12 cores, 2026-10-21), the share of
  frames composed was 0.115 at Full and 0.112 at Quarter with the switch
  on, and 0.279 at Full and 0.325 at Quarter with the prefetch
  (`designs/adr/roadmap-10-graphics.md`, "G6 phase 2").
  (i) **Risk accepted.** While playing, a graphic's JavaScript runs twice
  per frame, and up to all cores but one are busy. A restart wastes the
  rasters in flight. `cancelAllPendingVideoCompositionRequests` can wait
  up to one raster on a `take`, no longer than the serial path's own
  raster.
  **Amended by G-37**: (e)'s `4 × workers` slots and 1 GiB are replaced by
  G-37 (a)'s one budget; a document also keeps the frames it drew (G-37
  (c)).
  **Amended by G-38**: (a)'s never-while-paused has one exception, G-38's
  background session; a play ends it.
