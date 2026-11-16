# Spec §11 — decisions: Creator jobs, motion blur drawn onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-9.md`](creator-jobs-9.md), so a citation never has to
say which file. This file holds CU-117…CU-119 (CU11b), VR-27 (VR2b1), CU-31 and CU-36 (CU3c) and
TX-35 and TX-36 (docs bugs c2). The series goes on in [`creator-jobs-10.md`](creator-jobs-10.md),
which is why this file is lettered. It is new because `creator-jobs-9.md` had passed the spec's
~500-line split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below"
in one may now point into a sibling file.

## CU11b — motion blur drawn, its Transform row and Auto Zoom's Motion blur (2026-11-03)

Recorded before the code. CU11b is the remainder CU-116 names: CU11a stored `video.motion_blur`
(format 42), the recipe's `blur` key, the cursor's `shutter` and `state`'s `ends`, with nothing
drawn. CU11b draws them and shows them. No core change, no `rc_*` export, no op and no format
bump (43 stands); CU-110…CU-115 stand as recorded. Nothing sends anything anywhere, so nothing
is keyed (CJ-3). The owner's answer of 2026-11-01 stands: the shutter Auto Zoom sets is 50 %
(a 180° shutter).

- **CU-117 — The drawing.** (a) A recipe layer whose `blur` is non-null with at least one
  sample is drawn by `Compositor+MotionBlur.swift`'s `drawBlurred`, reached from the first
  statement of `drawLayer` — the one per-layer draw under `encodeLayers`, so a blurred layer on
  the canvas, in a matte group's members and in a routed dissolve's half all take it. A layer
  with `blur` null draws exactly as before; Swift never second-guesses the core's sharp list
  (CU-111) and never re-derives N: N is `blur.samples.count`. (b) The layer is prepared once
  (`prepare`: its texture, cursor and cutout), then drawn N times into one destination-sized
  `mattePool` composite cleared to transparent, sample k at its recipe placement — the anchor
  W/2 + x, H/2 + y, the scale (floored at 0.0001), the rotation in radians and the sample's
  `clip_rect` (none clears the clip) — everything else in the block the layer's own; its
  reflection drawn per sample as `drawLayer` draws it, but ADDED to the layer inside the
  accumulate pass rather than lying under it source-over, so where a layer meets its own
  reflection the composite holds their sum: at a gap of 0 the antialiased seam row, never more
  than about one pixel (CU11b's review, accepted as a limit). The accumulate pipelines are the plain
  layer fragment (and its gathering specialization) with source factors `blendColor` (RGB) and
  `blendAlpha` (alpha) and destination factors `one`, the blend colour set to 1/N in all four
  channels, so the composite holds the mean of the N premultiplied samples. (c) The composite
  is then laid on the destination in one full-frame draw of `framejob_motion_blur_fragment`,
  which returns `saturate(blendPremultiplied(mode, accumulated, dst))` with the layer's blend
  mode, on a pipeline with blending OFF (the programmable-blend rule of
  `MetalRenderer.pipelineDescriptor`). So a blended clip blends its averaged picture ONCE, not
  each sample; at `normal` that equals the mean of N sharp source-over draws exactly. A target
  that cannot be made throws "A motion-blurred layer's offscreen target could not be made."
  (`MotionBlurError.noTarget`), as a routed dissolve's does. (d) The cursor travel group: four
  floats after `cutoutReserved` in `LayerUniforms`, Swift and Metal in one edit —
  `cursorTravelX`, `cursorTravelY`, `cursorSamples`, `cursorTravelReserved` — taking the block
  from 160 floats (640 bytes) to 164 (656 bytes, 41 × 16); no existing field moves. (e) A
  cursor whose recipe key carries `shutter` and that draws a sprite asks `state` once with
  `ends` = the two ends' source ticks, each read through `cursorTime(at:reversed:file:)` (the
  forward stamp, or for a reversed clip `pivot − at − frame`, CU-33 (f)); with o the sprite's
  origin less the state's (x, y), `cursorX`/`cursorY` become end 0 + o, the travel end 1 − end 0
  and `cursorSamples` the shutter's `samples` — only when the travel is not (0, 0); otherwise the
  group stays 0 and the sprite draws as today. Ripples stay sharp. (f) The shader's
  `compositeCursor` keeps today's sprite step verbatim while `cursorSamples` < 1.5; at 2 or more
  it averages min(n, 16) premultiplied sprite samples at origins cursorXY + travel·(k + 0.5)/n
  (zero outside each rect) and composites that average as the one sprite was. `nearCursor` tests
  the box spanning both ends (travel read as 0 below 1.5, so every old comparison is the same).
  (g) A blurred layer whose cursor travels draws in sample k the cursor at its own sharp point,
  cursorXY + travel·(k + 0.5)/N, with `cursorSamples` 0 in that sample's block: the layer's N
  samples already average it, and blurring it again inside each would smear it twice.
- **CU-118 — The Transform row and Auto Zoom's Motion blur.** (a) The toll first, a pure move:
  `VideoPane.swift`'s Transform section (`transformSection` through `fitOrFill`) into
  `VideoPane+Transform.swift`, every `private` kept, committed alone. (b) The Transform section
  gains **Motion Blur** after Blend and before the Fit/Fill buttons: 0–100 %, quick picks 0, 25,
  50 and 100, writing `video.motion_blur` as value/100 through `binding.ops(video:)` (so inside an
  action it writes the action's end, CU-113's animatable key); disabled when any selected video
  clip is a nest clip or an adjustment clip (`VideoPane.motionBlurApplies`), the core's two
  refusals (CU-111), `blendApplies`' convention. Reset Transform adds `motion_blur: 0`. (c) Auto
  Zoom (`AutoZoom.plan`, both doors' planner) appends, after the core's ops, one
  `set_video {motion_blur: s}` over the distinct clips named in the answer's `actions` whose BASE
  `video.motion_blur` is 0, when s > 0; a clip that already has a shutter keeps it. `blurred` is
  their count. (d) The sheet's "Motion blur" checkbox under Replace, on by default; on is the
  owner's 50 % (`AutoZoomSettings.motionBlurShutter`), off is 0. It is remembered as a Bool under
  `FrameJobAutoZoomMotionBlur`, written by `remember(changedFrom:)` only when changed (mcp.py's
  DEFAULTS MOVED guard). (e) `auto_zoom` takes `motion_blur` (a number 0–1, default 0.5, through
  `resolveAutoZoom`'s `number` helper: "Motion_blur is 1.5; it runs 0–1.") and answers `blurred`
  beside the other counts. (f) `set_video`'s catalog clause says the blur is drawn in the
  preview, `render_frame` and every export, and names the UI path, the Picture sub-tab's
  Transform section's Motion Blur.
- **CU-119 — The proof, the mutants and JOB-26.** `tools/proof/cu11_proof.py` gains MB1–MB6 and
  K2–K4 and two modes, `capture DIR` and `compare DIR`; every picture row reads 16-bit
  `render_frame` PNGs through ffmpeg's `rgba64le` and compares at ±1/255 (±257 in 16-bit units)
  per channel per pixel. MB1 a 320 × 180 16-px checker clip under a 2× `ease_in_out` zoom over
  [0, 1 s) with `motion_blur` 0.5: `render_frame` at 0.5 s equals the mean of 16 sharp renders of
  what the shutter reads at t + o_k, o_k = round(((2k + 1 − 16)/32)·0.5·20,000), and the sharp
  frame at t differs by more than 8/255 somewhere (the control). **As built** (a deviation found
  at the first run): `render_frame` reads the composition on its frame grid, so a render at
  t + o_k is the frame at t; each sharp render is made AT t with sample k's placement (the
  action removed, the base scale set to the action's `ease_in_out` value at t + o_k) and, for a
  cursor, a cursor file whose moves are o_k earlier (`set_media_cursor`). And since an SDR frame
  of 8-bit sources is written 8-bit, which quantises each sharp render on its own, every picture
  fixture holds a 16-bit still (the checker, or a 2 × 2 dot off the canvas) so `render_frame`
  reads the frame deep and writes a 16-bit PNG. MB1b the same over an opaque 0.2-grey plate
  with `blend: add` and a checker of greys 0.1 and 0.7: `add` clamps (`kBlendAdd` is `min(src + dst, 1)`), so the mean
  of sharp `add` renders equals the averaged picture added once only where no sum passes 1 —
  hence greys whose sums stay below 1; a blend mode lost in the composite misses there by the
  plate's 0.2. MB2 an unmoving clip, and a cursor at rest, byte-identical with blur 0.5 and 0.
  MB3 a `prores_4444` export's frame 15 within ±8/255 of `render_frame` at 0.5 s (with the
  control past 24/255 from the sharp frame) — **a deviation from the road map's "identical"**:
  the export is lossy, so identity is the MB4 claim on its own bytes, not across writers. MB4
  (`compare` only) a version-41 package — a cursor movie with ripples, a zoom action, a shadow,
  a `screen` blend and a reflection — whose 3 `render_frame` PNGs and a 1 s `prores_4444`
  export's per-frame md5 are byte-identical to the `capture` made on a Release build of the
  toll's commit, before any product edit. MB5 a cursor moving at 600 px/s on a `color=` movie
  equals the mean of 16 sharp renders; MB6 MB5 under MB1's zoom. K2 `auto_zoom`'s `motion_blur`
  (0.5 stored, `blurred` 1; a clip at 0.3 kept; 0 sets none; 1.5 refused in its sentence); K3
  the Transform section's Motion Blur row below Blend (`snapshot_ui`); K4 the sheet through
  `-RCDevAutoZoomAccept YES` stores 0.5, and none with `-FrameJobAutoZoomMotionBlur NO`. The
  mutants, by hand, each file restored byte-identical by SHA-256: `leading` (the core's
  `shutter_offsets` at k/N) → MB1; `weight` (the blend colour 1/(N + 1)) → MB1;
  `dissolve-blur` (the `dissolve` arm out of `sharp`) → `cargo test --release --test
  motion_blur a_nested_pairs_routed_dissolve_is_sharp`; `composite-normal` (the composite's
  blend mode 0) → MB1b; `cursor-fraction` (k/n in the shader) → MB5; `cursor-in-samples`
  (`sampleUniforms` keeping `cursorSamples`) → MB6. **JOB-26** is the person's check that the
  blur reads as motion and not as smear.

## VR2b1 — framing composed into existing actions, and `reframe_clip`'s `replace` (2026-11-03)

Recorded before the code. VR2b is split (the road map's "Split" paragraph under VR2b): VR2b1
settles VR-27, the core's composition and the op's `replace`; VR2b2 is VR-29 (Clip ▸ Follow
Subject…), its sheet, menu, screen, manual checks and the proof's menu rows. No FFI, no header,
no new op, tool or `Kind`, and no format change (43 stands; `OP_COUNT` 70; 122 product tools);
nothing sends anything anywhere, so nothing is keyed (VR-2, CJ-3). The owner's answers of
2026-11-01 for VR2b (fill, follow one, 38 %) are VR2a's settings and stand.

- **VR-27 — Compose, or replace** (`core/src/reframe_compose.rs`, new; `reframe.rs`,
  `reframe_path.rs`, `reframe_cover.rs`, `edit_reframe.rs`). P(t) is the clip's evaluated
  `video` (scale, x, y) at clip tick t; F the planned path; F′ the scheduled path.
  (a) **The planner reads the placement in force.** Each sample's point is (★) through P at its
  own tick (`Frame.placed`, filled by `plan_framing` from `evaluate_clip` at each in-clip
  sample). Every window is clamped inside the COMMON rect: the intersection of the cropped rects
  of the base and of P at every action's end. Where the window would not fit, `k` is raised:
  `k = max(k_base, W / common_w, H / common_h)`, still held so that `k·s` at every one of those
  placements is at most `SCALE_MAX`. Coverage at every written key except a `fit` key then holds
  by convexity (VR-7). Where `SCALE_MAX` stops the raise, `clamp` centres, as VR2a2 does. An
  empty common rect falls back to the base rect. With no action naming x, y or scale this is
  VR2a2's arithmetic exactly.
  (b) **Composition.** The base becomes F′(0)∘P(0). Every action end writes
  `video.{scale,x,y}` = F′(end)∘P(end) when it names any of them (`null` included) or when F′
  changes across its span; otherwise its end is untouched. Exact wherever F′ is constant over an
  action, or P is constant over a move.
  (c) **Scheduling** runs after (d): cuts split first, then moves are scheduled against the
  resulting pieces. Busy spans are the clip's actions after the splits, `[start,
  start + duration)`; a head, a cut piece or a tail is a busy span of its own and may carry. A
  move (two consecutive keys of F whose values differ, cuts excluded) that overlaps no busy span
  becomes its own action. One that overlaps a span is shifted earlier to end at the start of the
  first span it overlaps, when the shift is at most `SHIFT_MAX` (0.5 s) and the move then starts
  at or after both the previous key and the previous span's end. Otherwise the move is CARRIED
  by that first span's action A: F′ holds until A's start and reaches the move's end value at
  A's end, along A's curve. Later moves that overlap A chain into it, and A's end takes the last
  one's value.
  (d) **Cuts.** A cut piece `[c − frame, c]` (`FramingPath.cuts`: each hard cut's key time whose
  key differs from the hold at `c − frame`, VR-24 (b)) inside an action A that names `speed`, or
  that ends past the clip's duration, is carried as in (c). Any other A is split into up to three
  pieces: the head `[A.start, c − frame]`, which keeps A's id and curve and whose end is
  `narrow_to(state_patch(eval at c − frame), A.end)`; the cut piece, `linear`, ending at
  `narrow_to(state_patch(eval at c), A.end)`; and the tail `[c, A.end]`, which keeps A's end and
  curve (`edit_split.rs`'s two helpers, lifted `pub(crate)`). Each piece is clamped into A (an
  edge of A off the frame grid can fall inside the cut frame, and the clamped cut piece is still
  F′'s own segment), and one of length 0 is not written. Each piece then takes (b)'s x, y and
  scale rule. A linear A plays unchanged on every key, volume included; an eased A is re-eased on
  each side. A cut in no action is its own `linear` action, as VR2a2's.
  (e) **Ids** are minted in time order for the new actions and tails (a head keeps its
  action's id), then VR-25's track, then the copy. A clip's actions are written in start order.
  (f) **Counts.** `Composed {re_eased, carried}`: `re_eased` the non-linear actions that were
  split, `carried` the actions across which F′ changes from a carried move or a carried cut. The
  op answers only applied, identity or refused, so a command recomputes them from the two
  handles with no planner: re-eased = an action id of the clip in both handles whose duration
  shrank and whose curve is not `linear`; carried = an action in both with the same span across
  which F, solved from both handles' `rc_project_clip_state` at its two ends (`k = s′/s`,
  `dx = x′ − k·x`, `dy = y′ − k·y`), differs by more than 1e-6. Under `replace` (g) P is
  constant once (g) has run, so the before handle's placement is not read: carried is then an
  action in both handles with the same span across which the AFTER handle's (scale, x, y)
  differs by more than 1e-6.
  (g) **`replace: true`**, read by every follow but `keep` (absent is `false`): the keys `x`,
  `y` and `scale` are removed from every end's `video` (removed, not keyed off), a `video` group
  left empty is dropped, then an action whose end is left `{}`; the base is set to the Fit
  placement of the cropped picture on the canvas (`zoom_scale(.., ZoomFit::Fit, 0)` and
  `zoom_offset`, as `Frame`'s `fit`); then the clip is planned and composed.
  (h) **`keep`** applies `rescale_video`'s rule to the base and to every end key among x, y and
  scale that the end names (through `rescale_video` itself, never restated).
  (i) **The backdrop copy keeps the speed actions.** VR-25's copy keeps the original's actions
  that name `speed`, each end narrowed to `speed`, so a ramped clip's copy reads the same frames;
  every other action is dropped, as before. Its actions' ids follow the copy's.
  **Choices left to the code:** F′ "changes across" an action when F′ at its start and at its end
  differ; the composed placement at a time is F′ there composed into P there, both read raw;
  `composed` and `replaced` are `pub` (not `pub(crate)`) so `core/tests/reframe_compose.rs` can
  read the planner's counts beside (f)'s recount.

## CU3c — the recorder stops burning the pointer (2026-11-03)

Recorded before the code. CU3c gives a screen recording a Cursor choice: the recorder panel's
Cursor row and `record_screen`'s `cursor`. With Separate, ScreenCaptureKit draws no pointer and no
click ring, the cursor file says `in_picture: false`, and Frame Job draws the cursor (CU-4,
CU-32). In the picture is today's configuration, byte for byte. The owner's answers stand:
2026-11-01 ("Separate, unless CU-S2's Separate rows failed") and 2026-11-03 ("the picker rows
waived"; CU-6's "Settled 2026-11-03"). No core, FFI, op, format or cursor-file version change.
Nothing is sent anywhere, so nothing is keyed (CJ-3).

- **CU-31 — The stream's pointer and ring only In the picture** (amends CU-13; restates R0 q6a).
  (a) `RecordingConfiguration.make` sets `showsCursor = (choice.effectiveCursor == .inPicture)`
  and `showMouseClicks = showClicks && inPicture`, and asks for `kCVPixelFormatType_32BGRA` only
  when both hold ("Show Clicks needs BGRA"). Separate leaves the default `420v`. In the picture is
  byte for byte the configuration before CU3c. (b) The cursor file's `in_picture` follows the
  choice (`cursorStart`'s `inPicture: choice.effectiveCursor == .inPicture`). The capture, the
  frame watch (`ScreenFrameWatchRule.attaches`) and the file ride both choices unchanged. (c) With
  Separate, Show Clicks means "land the screen clips with ripples on". The landing adds ONE
  `set_video {cursor: {clicks: "ripple"}}` over the placed screen clips whose media's cursor is not
  in the picture (`RecordingLanding.addRipples`, called right after `addSequence`). It is CU-42's
  write, inside the landing's one step. In a new project it goes inside `untitled(around:)`'s
  remainder step, which is named "Cursor Clicks" (`ripplesActionName`) when nothing else is in it.
  No op is added when no clip qualifies. A voice-over never takes it (`wantsRipples` is
  `showClicks && effectiveCursor == .separate && !isVoiceOver`). (d) A Separate segment left
  with no cursor file has no pointer anywhere. That covers no E1, a writer failure and nothing
  captured. Its `cursor_problem` (CU-12's sentence, and `cursorProblem`'s writer arm) ends with
  `cursorSeparateLost`: " The pointer is not in the movie either: it was recorded Separate."
  In the picture keeps the sentences as before. The watch-lost sentence is unchanged for both,
  since a file exists then.
- **CU-36 — The default, the key and the tool argument** (the owner, 2026-11-03).
  - (a) Separate is the default for a display recording. CU-S2's separate rows passed: display tip
    p95 0–0.5 px, E1 p95 2.5–6.3 ms.
  - (b) In the picture is the default for a window or picked recording
    (`RecordingCursor.windowDefault`). It stays so until a quiet-machine re-run of CU-S2's window
    rows settles their anchor; at load ≈ 30 they were 1.3–3.3 s off under every anchor. That
    re-run is owed. `RecordingCursor.defaultFor` answers `.separate` for `.display`,
    `windowDefault` for `.window` and `.picked`, and `.separate` for `.voiceOver` and `.camera`,
    which have no pointer to draw. `RecordingChoice.cursor` is nil for "the source's default", and
    `effectiveCursor` is `cursor ?? .defaultFor(source)`. **Amended at CU0d** (2026-11-04): the
    re-run settled the window rows' anchor as E1, so Separate is the default for a window or
    picked recording too: `windowDefault` is `.separate`, and `defaultFor` answers `.separate`
    for every source, its `switch` unchanged.
  - (c) The flip. When that re-run answers an anchor for the window rows under CU-S2's pinned rule,
    the phase that records it sets `windowDefault = .separate` and amends CU-36, CU-6 and the
    guide's default cells. A key never chosen (`""`) and the tool's absent argument follow at once;
    a person's choice stays. If the re-run fails, window recordings' cursor STOPs to the owner
    (CU-12) and the default stays. **Amended at CU0d** (2026-11-04): the re-run ran with every
    lane idle. Run 1, the instrument as it stood, at load 4.2/9.27/12.79, reproduced the loaded
    run (window-moved.picture E1 p95 1344 ms, window-moved.separate 2101 ms,
    window-odd.separate 3335 ms), so load was not the cause. The cause was two faults in
    `cursor_spike.py`'s `s2_row`, not the anchor: (i) the mapping was chosen by
    `p95(tip[m]) or 9999.0`, which ranks a perfect mapping (p95 exactly 0.0, as Separate rows
    give) last, so window-moved.separate was timed through M3, 277.8 px off; (ii) every frame
    whose marker fell inside the move's span was timed, including frames before the move began
    with the pointer parked inside it. The fix ranks only a mapping with no value last, and times
    a frame only when its marker moved since the last counted frame, and not the first frame after
    one under the red floor (selftest rows T3 and T4, mutants `perfect-mapping-last` and
    `parked-frame-timed`). Run 2, fixed, at load 6.78/7.49/10.92, gave E1 p95 within the
    16.7 ms frame on every measured row: window-moved picture 11.129 / separate 10.067 ms,
    window-odd picture 10.88 (8 frames) / separate 9.258 ms. Both runs printed `rule_sha256
    15d61ec5…c851`. Its VERDICT line reads `mapping_display=M2 mapping_window=owed
    separate=owed anchor=owed e1_still_p95_ms=10.2` because the waived picked rows count as
    skipped; with them recorded `absent` (the waiver of 2026-11-03) `deciders.decide_s2` gives
    `mapping_display M2, mapping_window M2, separate pass, anchor E1, e1_still_p95_ms 10.2`.
    The flip is made: `windowDefault = .separate`. A key never chosen (`""`) and
    `record_screen`'s absent `cursor` follow at once; a person's stored `in_picture` stays.
    (f)'s first mutant is now `window-default-in-picture` (P2, P5, P7), which sets
    `windowDefault` back to `.inPicture`. The evidence is in
    `~/.claude/litecode/framejob/cj-cu0d/evidence/`; the record is `designs/creator-jobs.md`'s
    "CU0d's record (2026-11-04)".
  - (d) The key. `FrameJobRecordingCursor` is the panel's thirteenth key: `""` follows the source,
    `separate` or `in_picture` is a choice. Every `persistChoices` writes it from
    `cursorChosen`, which only the popup's own change sets, never from the popup's shown row. It
    is restored on show, and an unknown value reads as `""`. The popup shows `cursorChosen ??
    .defaultFor(currentChoice().source)` for a screen source (`syncCursorPopup()`, the first
    statement of `refreshSizeNote()`, so the Window row's early return is covered). It is greyed
    for Microphone Only and Camera with its value kept. The harness and `screens.py` pin it to
    `""` (AU-69 (b)).
  - (e) The tool. `record_screen`'s `cursor` is `separate` or `in_picture`; absent is
    `defaultFor(source)`. It is read after `keys`, and its vocabulary refusal ("cursor must be
    one of separate, in_picture (got "x").") falls among the caller's own mistakes after `keys`'.
    It is refused by name with `voice_over` and with `camera` (`voiceOverScreenOnlyArguments` and
    `cameraRefusedArguments`, after `keys`). `show_clicks` keeps its meaning per mode: the ring in
    the picture with In the picture, the landed clips' ripples with Separate. The dev tool
    `land_recording` takes `cursor_mode` (the same enum, setting `choice.cursor`) and `show_clicks`
    (default false), each refused by name without `movie`. The road map named the first `cursor`,
    which is already that tool's file path.
  - (f) The proof. `cu3c_probe.py` P1–P6 with mutants `window-default-separate`,
    `persist-shown-cursor`, `sync-after-returns` and `separate-lost-dropped`. `recording_probe.py`
    B2 has 32 configuration rows and mutants `separate-shows-cursor`, `separate-bgra` and
    `voice-strangers-cursor`. `cursor_layer_proof.py` has B3 (and B3b) and B5, and mutant
    `ripple-write-skipped` by hand. `cursor_proof.py` has granted B1 and B4 and K17's
    `in_picture` false. JOB-21, JOB-27 and JOB-28 are the person's.

## Docs bugs c2 (2026-11-04)

- **TX-35 — Whole timeline, In/out range and an unnamed `transcribe` read only clips that can be
  heard.** The test is TX-10's: a plan audio segment `SilenceDetector.isAudible` passes, per clip,
  so a clip audible anywhere is read whole. Selected clips and a named `clips` keep every clip the
  gate takes: selecting both of two clips reads both, and that is how a person captions a muted
  clip. The sheet opens on Selected clips only when they hold a clip that can be heard, or when no
  other scope has work. `Transcriber.jobs` is unchanged, because `no_words`, the fillers and
  `CaptionRetime` share it, and `hasTranscribableClip` stays the cheap snapshot question, so with
  nothing heard the sheet opens and says so. An unnamed `transcribe` with nothing heard is refused:
  "Nothing heard in this timeline can be transcribed. Name a clip in clips to transcribe it
  anyway." The test asks only whether the gate would take a clip and nothing heard is left to
  read. Beside a reversed clip or a nest that plays, a muted clip alone still gets the sentence,
  which therefore says that nothing heard can be transcribed, not that nothing can be heard; the
  sheet reads "Nothing heard can be transcribed. Select a clip." (docs bugs rc).
- **TX-36 — The Transcript tab names a clip as the timeline does, its id beside the name** (amends
  TX-22, TX-24). The same-speech note reads "“Interview.mov” (clip 5) and “Mic.wav” (clip 6) carry
  the same speech. Mute one, or switch its audio off, to read it once." and a no-words row
  "“Interview.mov” (clip 5) — its audio is switched off", "(clip 5 in nest Intro)" in a nest. The
  tool's `notes`, `tag` and TX-10's sentence are unchanged: an agent reads ids. The owner's TX1
  answer was "name the pair", and no decision weighs a person being unable to look an id up.
