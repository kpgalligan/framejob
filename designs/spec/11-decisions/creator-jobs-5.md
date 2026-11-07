# Spec §11 — decisions: Creator jobs, the cutout's edges onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md), [`creator-jobs-3.md`](creator-jobs-3.md) and
[`creator-jobs-4.md`](creator-jobs-4.md) (CJ-, VR-, TX-, SW-, CU- and CO-), so a citation never has
to say which file; `creator-jobs.md` says what the road map builds and how its IDs are made (CJ-7).
This file is new because `creator-jobs-4.md` passed the road map's ~500-line split rule with CO3's
entries (620 lines, 2026-11-02); each phase's decisions are appended here from now on, before its
code. The series continues in [`creator-jobs-6.md`](creator-jobs-6.md) from TX3b's TX-34.

CO-40…CO-42 are CO4's (the cutout's edges), recorded before its code. S-KEY1 (`samples/README.md`:
the owner before an evenly lit plain cloth) does not exist, so CO-S3 — whether the edge needs
refinement, and which — cannot run; the road map's head rule for that case is that r0 ships and
the row is owed. The owner's answer of 2026-11-01 for CO4: Best is **not** the default on a short
clip — Standard always, Best chosen per clip. No format bump, no `rc_*`, no core change, no new
tool, no shader change: two doc comments, the documents and the proof. Vision runs on the Mac, so
nothing here is keyed (CJ-3).

- **CO-40 — r0 is the edge; CO-S3 is owed.**
  - **What ships.** The edge is CO-27's r0 and nothing else: the mask's `.r` sampled bilinearly
    and remapped by `cutoutCover` (`Compositor.metal`), `c = 0.5 − 0.5·edge`, `w = 0.5 +
    0.5·feather`, `lo = clamp(c − w/2, 0, 1)`, `hi = clamp(c + w/2, 0, 1)`, `cover =
    smoothstep(lo, hi, m)`. No r1 (joint bilateral) or r2 (guided filter), no pre-pass, no
    `KeyReading` passed to a refinement (CO-7's clause on a refinement's guide has nothing to
    read yet), no new uniform, no core constant; `LayerUniforms` stays at 160 floats.
  - **The documented amount (the contour rule).** At Feather 0 the outline — where coverage is
    one half, the midpoint of `smoothstep(lo, hi, ·)` — lies at the mask value **m½(e)**: `0.5 −
    0.5·e` for |e| ≤ 0.5, `0.375 − 0.25·e` for e > 0.5 (`lo` clamped at 0), `0.625 − 0.25·e` for
    e < −0.5 (`hi` clamped at 1). At e = −1, −0.5, 0, 0.5, 1 it is 0.875, 0.75, 0.5, 0.25,
    0.125. On a mask edge that rises linearly over R display pixels, Edge +1 moves the outline
    3R/8 outward from Edge 0 and −1 moves it 3R/8 inward; coverage is non-decreasing in `edge`
    at every mask value, so a larger Edge never draws less. This is what Edge means until a
    refinement replaces it; the guide states it in words, and `co4_proof.py` E4 measures it.
  - **CO-S3 runs when S-KEY1 exists**, unchanged: its rule as CJ0a pinned it (`rule_sha256`
    `84ae691664c9d8293b50f70e1f332e68a032984da4f2ae65500561f152e9319f`), after CO-S1's owed
    S-KEY1 rows. A refinement it picks is a new phase, with its own decisions, its own proof
    (CO4's E1–E3: B on S-KEY1's composites against CO-S3's, the same in an HLG project, the
    preview's cost bound) and its own mutants; until then E1–E3 are skipped by name and owed.
- **CO-41 — No Best yet; Best is never a default.** CO-S1 kept no Best (its rule (d) needs
  S-KEY1), so there is no `masks_best` kind, no Quality row (CO-30 stands) and `best` stays
  refused in CO-20's sentence ("video.cutout.quality must be standard: Best masks are not made
  yet") until CO-S1 (d) keeps Best on S-KEY1. When Best exists (the owner, 2026-11-01): Standard
  on every clip, Best only when chosen per clip, with no rule that picks it by duration.
- **CO-42 — CO4's proof.** `co4_proof.py`: B0 its probe (`co2a_probe.swift`, whose `pack` mode
  gains the `ramp` kind: every mask 512 × 288, column i `round(255·clamp((i − 240)/32, 0, 1))`)
  builds; E1, E2 and E3 skipped by name while `tools/proof/media/creator/S-KEY1/` is absent, and
  each a scored failure once it exists; E4 the documented amount on a 1920 × 1080 transparent
  canvas — the bar code at scale 1 over a canned `ramp` pack (a ramp of 32 texels, 120 display
  pixels), at Edge −1, −0.5, 0, 0.5 and 1, Feather 0: on rows 100, 540 and 980 the contour where
  alpha crosses 127.5 within 1 px of `3.75·(240.5 + 32·m½(e))`, and Edge 0 → +1 and −1 → 0 each
  45 ± 1 px; E4r the order on real masks — `push_1080.mov`'s, made by `get_media_analysis` — at
  Edge −1, 0 and +1: alpha non-decreasing in `edge` at every pixel within one level, and the
  count of pixels with alpha ≥ 128 strictly increasing; Z1 each launch's log free of `Frame
  Job: `. Two mutants on Release: Edge's sign reversed (E4, E4r) and `lo`/`hi` unclamped (E4).
  JOB-60 (`docs/manual-checks.md`) is the person's look at real edges.

CO-50…CO-56 are CO5's (Text Behind Subject), recorded before its code. The owner's answer of
2026-11-01 for CO5: Behind Subject is **a clip flag**, not a track flag — a title is placed per
moment, and a track flag would catch every later clip on the track. Nothing here sends anything:
Vision's masks are on-device, so no `ModelKeys` row (CJ-3). No `rc_*` export and no new op: the
tool is an app-state composite of ordinary ops (CJ-8 (f) not needed, no rule must hold inside the
core).

- **CO-50 — Behind Subject is a per-instant relation, drawn by the matte machinery.**
  `video.behind_subject: true` on any drawing clip but an adjustment or nest clip (CO-52). At each
  instant the recipe (`recipe_subject.rs`, called once from `recipe.rs` after the mattes and the
  routed dissolves and before Show Selection) reads it over the covering instances:
  - **A subject** is an instance whose layer's `cutout` is non-null and which is not drawn into a
    matte, `background` `remove` or `keep` alike. **A behind layer** is an instance not drawn into
    a matte and not an adjustment clip whose `evaluate_clip(clip, clip_t).video.behind_subject` is
    true. Nothing is evaluated unless some layer's `cutout` is non-null.
  - **Subject L is behind B** when, with d = B's nest depth, L is at least as deep, L's first d
    enclosing nest clips are B's (by id), and L's level-d track — its own track when L's depth is
    d, else the track of L's d-th enclosing nest clip — has a lower index than B's track in that
    container's tracks (the timeline's at d = 0, else B's innermost nest's). So a subject inside a
    nest on a track behind a top-level title cuts it, and a top-level camera never cuts a title
    inside a nest. No clip names another, so split, move, paste, nest and undo cannot break it.
  - **Ids.** A subject is listed only when at least one behind layer is cut by it. Listed subjects
    take group ids n, n + 1, … in instance order, n one past the largest id any layer's `matte`
    names (0 when none), so the track groups keep their ids and order. Each behind layer's
    `matte` becomes `{into: null, cut: [the ids]}` or gains them, ascending; each subject's entry
    `{group, mode: "alpha_inverted"}` is appended after every track group in `mattes`. The cuts
    multiply (MT-2 as amended). The behind clip's own shadow and reflection are cut with it, as a
    matte cuts them (MT-3).
  - A frame with no behind layer cut by a subject is byte-identical to the frame without the
    relation: `frame_mattes` is untouched, and the inputs come back as they went in.
- **CO-51 — The subject copy, MT-4's third override.** A listed subject is drawn into its group by
  a COPY of its layer inserted directly after it: the original layer object with exactly `blend:
  "normal"`, `shadow: null`, `reflection: null`, `cutout.background: "remove"`,
  `cutout.subject_copy: true` (appended to the cutout object) and `matte: {into: s, cut: <the
  original's track-matte cut>}`; every other key kept, the layer's 28 keys unchanged. It is the
  recipe's THIRD deliberate override of model values, after a transition's `normal` and a matte
  layer's (MT-4). Its Show Selection fact is drawn-into, so `behind` keeps it.
  - **A copy whose mask is not drawn draws nothing** (`CompositorEffects.prepare`): pending, no
    person found, a coverage miss or a slate leave the behind clip whole, never cut by the
    whole camera picture.
  - **Its transition is weighed with no partner correction.** A copy keeps its original's
    `transition` and `dissolve` (dropping them would lose a zoom's scale and a push's offset), but
    `prepare` looks up no partner for it, as `partnerBox` already does for a cut-out partner on
    the canvas (CO-27): an unrouted `cross_dissolve` or `zoom` half's copy weighs `(1 − p)` going
    out and `p` coming in, so a cut-out camera dissolving into an uncut clip fades its subject
    out of group s. A routed half (MT-8) is a run in s whose missing half `encodeDissolve` draws
    as a cleared target, so it mixes to `(1 − p)·out` or `p·in` with no change. Push, slide, wipe
    and fade are per-layer weights and offsets, the same on the canvas and in s. Each copy
    directly follows its original, so `layers.first { $0.clip == partner }` still finds an
    original's partner, and an original's lookup is unchanged.
  - The copy's canvas box duplicates its original's and the hit test answers the same clip; no
    cursor, hit-test or selection-overlay change. `MattePlan.swift`, `Compositor+Matte.swift`,
    `MetalRenderer.swift` and `CutoutWants.swift` are unchanged: a subject group is an ordinary
    group listed after the track groups, and a copy's masks are wanted because it has
    `background: remove`.
- **CO-52 — `video.behind_subject` (format 40).** A boolean after `cutout`, written only when true,
  so every file without it is the text it was; no migration. The bump is so an older build
  refuses a file with the flag instead of dropping it on save. `set_video` and `paste_attributes`
  refuse it on an adjustment clip ("clip N is an adjustment clip and cannot be put behind a
  subject") and on a nest clip ("clip N shows a nest and cannot be put behind a subject")
  (`cutout_check.rs`'s `check_behind_subject_clip`, in `settle_video` after the cutout's clip
  check); a file's flag on an adjustment clip is ignored by the recipe. A boolean, it switches at
  an action's end (§5.4), never refused there. `add_blurred_background`'s copy drops it.
  `background: keep` draws the camera whole on the canvas and still makes it a subject, so the
  title is hidden behind the person while the room stays.
- **CO-53 — The planner, and Insert ▸ Text Behind Subject.** `BehindSubjectPlan.swift`, pure over
  a snapshot, a playhead, the selection and an optional clip, top-level only.
  - **Candidates at `at`:** top-level clips with start ≤ at < end that `CutoutStatus.canCutOut`,
    with `enabled.video`, on a track neither hidden nor a matte track. **The pick:** the named
    clip (refused "Clip N cannot have a title put behind its subject: it must be a clip of a
    video file on the timeline, on a shown track that is not a matte track." when it is not a
    candidate kind, "Clip N does not play at T: pass an at inside it." when it does not play at
    `at`); else the front-most selected candidate; else the front-most candidate with a base
    cutout; else the front-most; none refused "No clip of a video file plays at T on a shown
    track that is not a matte track, so there is no one to put the title behind.".
  - **The track:** a new track named "Behind Subject" at 1 + the index of the front-most track of
    the unbroken run of matte tracks directly in front of the clip's track, or of the clip's own
    track when that run is empty — so it sits behind an ordinary track or at the front and no
    matte targets it (MT-2): with `[V, M1→V, M2]` it goes to index 3, not 2.
  - **The ops, one undo step "Text Behind Subject":** `add_track`, `add_text_clip` (the Title
    preset; `content` when given) at `at` for min(4 s, the clip's end − at), `set_video
    {behind_subject: true}` on the title, and, only when the clip has no base cutout, `set_video
    {cutout: {background: keep}}` on it — the camera stays whole and still hides the title.
  - **The menu item** is Insert ▸ Text Behind Subject, last in the menu, no key equivalent; off
    with a nest open or with no plan. It applies through `applyEdit` and selects the new clips.
- **CO-54 — `text_behind_subject {clip?, at?, content?}`.** An app-state tool (no `scope`), on the
  main thread, mirroring Insert ▸ Text Behind Subject: refused with a nest open
  ("text_behind_subject works on the top-level timeline: set_scope with no nest first."); `at` in
  ticks, else the playhead; `clip` an id; `content` a non-empty string ("content must not be
  empty"); a planner refusal answers its sentence; one undo step through `performGroupedEdit`, the
  selection untouched. It answers `{ok, clip, track, text, duration, cutout_added, project}`. No
  key gate (CJ-3). `set_video`'s description names `behind_subject` and the clip kinds of `cutout`.
- **CO-55 — The Behind Subject section.** In the Clip tab right after Transform, shown when no nest
  is open and no adjustment or nest clip is selected: a checkbox "Behind subject" writing `video
  {behind_subject}` (an end inside an action), one undo step "Behind Subject", mixed over a
  selection that disagrees; Reset writes false; its summary "on" or "off". With one clip selected,
  its flag on, and no cut-out clip behind it at the playhead (the document's recipe there names no
  subject group in its `matte.cut`), a note: "No cut-out clip is behind it at the playhead."
- **CO-56 — The proof, its mutants and JOB-63.** `co5_proof.py` with `co5_probe.swift`: P1 (the
  planner: pick order, min(4 s, rest), the index above a matte pair and above `[V, M1→V, M2]`, the
  three sentences, 3 or 4 ops, `isCutBySubject`); B1 (a full-canvas opaque shape with the flag in
  front of a cut-out `barcode.mov`: all-255 3×3 mask neighbourhoods equal the frame with the shape
  hidden, all-0 the frame with the camera hidden); B2 (a cut-out camera in front does not cut);
  B3 (split, move and undo keep B1's answer); B4 (`background: keep`); B5 (the shape's blur-0
  shadow cut with it); B7 (`play_preview` composes ≥ 95 % of the flag-off frames, median of
  three); B8 (menu and tool give equal projects, one undo each); B9 (a coverage miss leaves the
  shape byte-identical to flag-off); B10 (a cut-out camera cross-dissolving into an uncut clip:
  at p = 0.5 over all-255 the mean of flag-off and shape-hidden within ±3); Z1 (parity logs
  empty). Seven mutants: front-subjects (B2), copy-shadow (B5), three-steps (B8), miss-whole (B9),
  copy-partner (B10), one-matte-skip (P1) and listed-uncut (`behind_subject.rs`'s b6). **JOB-63**:
  a person's look, on S-TH1, at the halo where the soft edge meets the letters.

CO-100…CO-104 are CO10a's (a picture's cutout in the model and the recipe), recorded before its
code. CO10 is split by size: CO10a ships the model, the recipe and the mirror, and CO10b the masks,
their store, their wants, the draw and the UI (CO-102). The owner's answer of 2026-11-01 for CO10:
pictures are in this road map, built last in CO. Format 41 is provisional (CJ-8 (b)); no new op,
tool, `rc_*` export, op-table argument or `ModelKeys` row — Vision is on-device (CJ-3).

- **CO-100 — A picture takes a cutout, and only a picture a foreground subject (format 41).** The
  road map's draft, as built. `CutoutSubject::Foreground` is appended (JSON `foreground`), so
  `video.cutout.subject` is `person` (the default) or `foreground`, and `{}` still reads as
  `person`. An image clip takes a cutout with either subject; a media or still clip takes only
  `person`, and `foreground` on one is refused in its own sentence — "clip N is a media clip and
  cannot take a foreground cutout: only an image clip can", "clip N is a still clip and cannot
  take a foreground cutout: only an image clip can" — checked in `cutout_check.rs`'s
  `check_cutout_clip` after the existing kind refusals (so a text, shape, graphic, adjustment or
  nest clip keeps its sentence), which `edit_props.rs`'s `settle_video` runs, so `set_video`,
  `paste` and `paste_attributes` all meet it. A freeze frame already cuts through its video's
  person masks (CO2a's D11), so a still never needs `foreground`. Pictures' foreground masks are
  `VNGenerateForegroundInstanceMaskRequest`'s (CO-1), made from CO10b. `subject` stays base-only
  (CO-20). Amends CO-20, which refused a cutout on an image clip "until CO10".
- **CO-101 — The recipe's image arm carries the subject.** For an image clip whose media is in the
  project and whose evaluated cutout is set, the layer's `cutout` is `{mask: {kind: "image",
  media, subject, quality}, background, edge, feather}`, `media` the clip's image; otherwise
  `null`, as the media arm. One image's person mask and foreground mask differ and the compositor
  reads only the recipe, so the arm names the subject; CO-21 allows it ("at least"). The media
  arm stays `{kind: "media", media, quality}` with no `subject` key, so every video recipe is the
  text it was. Amends CO-21's "CO10 adds `{kind: "image", media}`".
- **CO-102 — The split.** CO10a: the subject, the clip rule, the image arm, format 41, the Swift
  mirrors (`CutoutSubject.foreground`, `RecipeCutoutMaskKind.image`, `RecipeCutoutMask.subject`,
  read leniently with `person` the default), `set_video`'s description and `analyze_cutout`'s
  refusal (CO-103). An image clip's cutout is kept but drawn uncut, as CO-23 drew video until
  CO2a2: the compositor's guard (`mask.kind == .media`) and `CutoutWants` leave an image layer
  uncut and un-waited, and a cut image is a subject to Behind Subject (CO-50) whose copy draws
  nothing without a mask (CO-51), so a behind title stays whole. CO10b holds the rest of CO10:
  one mask per image (a run at tick 0, grid index 0, person `.balanced` rev 1 or
  `VNGenerateForegroundInstanceMaskRequest` by subject, on the picture as `LayerRenderers.image`
  decodes it), foreground masks in an analysis kind of their own, the image wants windowed apart
  from the plan's segments, the `.image` draw at `texture(4)`, `CutoutStatus`, the Background
  section's Subject pop-up and `BehindSubjectPlan` on pictures, `analyze_cutout` on pictures,
  the guide's pages and JOB-65.
- **CO-103 — `analyze_cutout` leaves pictures out until CO10b.** It decides by `cutout != nil`
  alone, and an image clip would answer `no_picture` (`CutoutStatus`'s detail). So a named image
  clip, after the existing no-cutout check, is refused: "Clip N is an image clip; an image clip's
  Remove Background is kept but not analysed yet."; with `clips` left out the default set is
  every cut clip whose source is not an image, and when that set is empty but an image clip has a
  cutout: "No video or still clip in the open scope has Remove Background on; an image clip's is
  kept but not analysed yet." With no cutout at all the existing sentence stands. CO10b lifts
  both.
- **CO-104 — CO10a's proof.** `co10_proof.py` (one Debug or Release launch on a scratch
  `CFFIXED_USER_HOME`, `media/A.mov` and a 64×48 RGB PNG the script writes): S2 `foreground` on a
  media clip and on a `freeze_frame` still each answers its sentence exactly, the project
  unchanged; S3 an image clip's `{subject: "foreground"}` reads back all five keys, `{edge: 0.25}`
  merges, `null` removes; S4 `render_frame` at two times with the image's cutout on equals it
  off, byte for byte, each call under 10 s; S5 `analyze_cutout`'s image sentence, its default set
  without the image clip, and the empty-set sentence; Z1 the log free of `Frame Job: `. Four
  mutants: M1 `foreground-on-media`, M2 `image-refused`, M3 `arm-no-subject` (each caught by
  `core/tests/cutout_image.rs`) and M4 `analyze-image` (caught by S5 on Debug).

## CU1b1 — the recorder saves the cursor (2026-11-02)

Recorded before the code. CU1b is split (road map "CU1b — the recorder saves the cursor"): CU1b1
writes the file; CU1b2 holds the granted rows K1, K2, K3, K6 and K9 against a burned-tip helper.
The owner's answer: the file sits beside the movie as `<stem>.fjcursor` (CU-2, CU-15).

- **CU-11 — The capture (CU-S1's verdict as the owner ruled on it, CU-6).** `CursorCapture`
  (`app/Sources/CursorCapture.swift`) owns one serial queue, `com.kgalligan.FrameJob.cursor` at
  `.userInteractive`, and the only `CursorSegments` value, touched on that queue alone.
  - **Positions:** a `DispatchSourceTimer` on that queue polls `CGEvent(source: nil)?.location`
    every 1/120 s; a move is recorded only when the point differs from the last polled one, and a
    nil records nothing. Each segment opened is seeded with the last polled point (a move at its
    open, before its anchor, so CU-17 keeps it at t 0): a segment opened after the pointer stopped
    still has its position. Its opening geometry is the last fed (CU-13), else the start's.
  - **Clicks and scrolls:** `NSEvent` global and local monitors, added and removed on main, no
    grant: left, right and other mouse-down and mouse-up, and `scrollWheel`. A click is
    `buttonNumber` (0…31, else dropped), down or up, `cgEvent.location` and `clickCount` (at least
    1). A scroll is `.scrollWheelEventPointDeltaAxis2` / `Axis1` as dx / dy at `cgEvent.location`.
    An event without a `cgEvent` is dropped.
  - **Time:** an event's host time is `cgEvent.timestamp / 1e9` seconds (`event_clock=ns`), else
    its arrival on the host clock (`CMClockGetHostTimeClock`); a poll's is its own host time.
  - **Not captured:** no image sampler (`cursor_image=none`: every file says `none` and the
    arrow is drawn, `image_fallback=arrow`); no hidden spans (`hidden=not-recorded`); no dirty
    boxes (CU-S3 `dirty=not-stored`, 0/10); keys wait for CU6 (`keys=tap`, under Input
    Monitoring). `CursorCaptureBuffer` (CU-17) and `CursorFileWriter` (CU-15) are used as they
    are: seeding and the poll's dedupe live in `CursorSegments`.
- **CU-12 — The anchor is E1 for every source.** A segment's times count from its screen
  did-start's host time (E1), stamped on every segment by the recording output's did-start. E2 is
  never used for a cursor file: on CU-S2's display rows E2's p95 was 14.6–26.1 ms against E1's
  2.5–6.3 ms. The window rows' re-run on a quiet machine is owed; if they still fail, window
  recordings' cursor STOPs to the owner. A landed segment with no E1 gets no file, and its
  `cursorProblem` is "The cursor file for <movie name> was not written: the screen never reported
  its start, so its times have nothing to count from." **Amended at CU0d** (2026-11-04): the
  window rows' quiet-machine re-run passed under E1 (every measured row's E1 p95 within the
  16.7 ms frame, once the instrument's two faults were fixed; CU-6, CU-36 (c)), so nothing STOPs:
  E1 is the anchor for window and picked recordings as well.
- **CU-13 — The frame watch rides every screen recording (amends CAM-9 (3)).**
  `ScreenFrameWatchRule.attaches(camera:cursor:)` is `camera || cursor`, and cursor is true for
  every display, window or picked recording until CU3c and CU4 give a choice. The watch feeds
  each complete frame's `SCStreamFrameInfo` geometry (`screenRect`, `contentRect`,
  `contentScale`, `scaleFactor`; none fed when a key is missing) when it differs from the last,
  timed by the frame's PTS, to `CursorCapture.geometry`.
  - A failed watch add refuses the start only when a camera needs E2
    (`ScreenFrameWatchRule.failsStart(camera:)`, the existing sentence "The screen's frames could
    not be watched: …"). Without a camera the recording goes on without the watch, its reason
    kept as `Session.cursorWatchLost`. A failed re-add at a resume is that segment's
    `cursorWatchProblem`, camera or not (the camera's own `watchFailure` stays as it is).
  - The file is still written, on the geometry known when the segment opened, and its
    `cursorProblem` is "The cursor file for <movie name> has only the geometry the screen had
    when it began: its frames could not be watched (<reason>), so a move or resize of what was
    recorded after that is not in it." (CU-14: never the recording's failure.)
  - **The opening geometry**, before any frame, is what CU-S2's frames reported:
    `scale_factor = filter.pointPixelScale`; `content_scale = content_px_width / (scale_factor ×
    point_width)`; `content_rect = (0, 0, point size × content_scale)`; `screen_rect =
    source_frame` — `CGDisplayBounds` for a display, the CGWindow's `kCGWindowBounds` for a window
    (the filter's `contentRect` when the window list has none), the filter's `contentRect` for a
    picked source. The header's `pixels_per_point` is the configured pixel width ÷ the point
    width; `content_size` the stream's configured size; `in_picture` true (the pointer is still
    burned in until CU3c); `cursor_image` `none`.
  - **Amended by CU-31**: `in_picture` follows the choice; capture and the watch ride both choices.
- **CU-18 — The result, the answer and the notes.** A landed segment carries `cursorURL`,
  `cursorProblem` and `cursorImage` (`RecordingSegment.withCursor`), set by the walker's cursor
  step after the camera's (movie → microphone → camera → cursor; a cursor failure never fails or
  reorders a segment). The step closes the segment's buffer with `movieSize` the probed movie's
  width × height and `CursorAnchor(kind: .e1, host: screenHost)`, then writes through
  `CursorFileWriter` on the capture queue; the writer's sentence wins over CU-13's. A session
  without a capture (a probe's hand-built one) passes the segment through unchanged.
  `record_screen`'s `segments[k]` gains `cursor_path` and `cursor_image` (`"none"`) when the file
  was written and `cursor_problem` when set. `RecordingResult.cursorSegmentsNote` (every
  segment's `cursorProblem`, in order, space-joined) is appended to the tool's notes and the
  panel's landing note (and its failed-landing note). The header's `cursor_image: none` gets no
  landing note: every recording is written that way, so a note would be noise. This deviates from
  the road map's CU1b, which named one. No new tool, op, `rc_*`, project format or cursor-file
  version.
- **CU-19 — CU1b1's proof.** Ungranted, `cursor_capture_probe.py` (with B0 and C1–C6): K0
  `attaches` is `camera || cursor`; K10 120 polls over 12 positions give 12 moves and a nil none;
  K11 a segment opened after the pointer stopped has one move at t 0 at the last point, and its
  opening geometry is the last fed; K12 `segmentFields`' three keys, `cursorSegmentsNote` and
  `resultNotes`; K13 `geometry(from:)` reads the four keys and answers nil when one is missing;
  K14 an `NSEvent(cgEvent:)` click stamped 5e9 ns answers host 5.0, its point and count; K16
  `failsStart` true with a camera and false without, and `cursorProblem`'s precedence. Seven
  mutants: `watch-camera-only` (K0), `poll-every-sample` (K10), `no-seed-at-open` (K11),
  `cursor-note-dropped` (K12), `event-clock-arrival` (K14), `watch-failure-refuses` and
  `watch-lost-dropped` (K16); and the core's `mapping-m1` (`core/tests/cursor_track.rs`).
  Granted, `cursor_proof.py` against Release (skipped by name without Screen Recording or on a
  locked console): K4 display recordings at Nominal and Best, each paused and resumed with the
  pointer warped in each segment, every segment its own file accepted by `ReelCursor` (`source`
  display, `anchor` e1, `cursor_image` none, `movie_size` the track's, each warped point in the
  moves within 1 pt); K5 clicks posted onto the probe's window (skipped by name without
  `CGPreflightPostEventAccess`); K7 a directory at `<stem>.fjcursor.partial` lands the movie with
  no cursor URL and the writer's sentence; K8 the probe's own 1001 × 701 pt window at Nominal,
  `movie_size` the track's; K15 `record_screen {seconds: 2, place: false, path}` answers
  `segments[0].cursor_path` beside its movie with `cursor_image` "none". JOB-20 is the person's
  check of a real recording's clicks.

## TX1b — on-device word starts moved to their sound (2026-11-02)

TX-15…TX-19 are TX1b's (on-device word starts moved to where their sound begins), recorded before
its code; they sit in TX1's block (TX-10…TX-14), whose next free numbers they are. The owner's
decision of 2026-11-02, answering TX3b's STOP: "Fix word starts first." TX-S3 measured E0's
on-device starts always early (−109.6 to −1,185.6 ms), and TX3b measured "Pack" 1.11 s and "How"
1.07 s before their audible onsets, so the word after a pause starts inside the silence. No core,
`rc_*`, op, tool name, format or key change; nothing sends (CJ-3), so there is no `ModelKeys` row.

- **TX-15 — An on-device word's start is moved to where its sound begins.** The rule runs per
  stored run (`DeviceTranscriptCache.Heard`), in media source ticks, over its words in source order
  (`WordOnsets.moved`). A word has start `s`, end `e = max(s, end)`, and `limit = min(e, the next
  word's stored start)` (`e` for the last word). A voice cell k is `[k·chunk, (k+1)·chunk)`,
  `chunk` `MediaSpeech.chunkTicks`, and is speech when `p ≥ defaultVoiceConfidence`.
  - (a) **The first speech cell.** `b` is the first cell after `s`'s cell that is speech, with
    `b < count` and `b·chunk < limit`, whose preceding non-speech run `[a, b)` (the longest run of
    non-speech cells ending at `b − 1`) either holds `s`'s cell or is at least
    `TranscriptCut.minimumRunCells` (2) cells long. With none, the start is unmoved.
  - (b) **The threshold.** `T = max(level, floorRatio × median)`, `level` 0.01 (−40 dBFS, linear)
    and `floorRatio` 4 (+12 dB), in `Float`. The median is the element at index `(n − 1)/2` of the
    sorted peaks of the 10 ms buckets (`MediaPeaks.bucketTicks`) whose start lies in `[a·chunk,
    b·chunk)` — the noise floor of the word's own non-speech run before the onset, never a speech
    level; with no such bucket it is 0.
  - (c) **The onset.** The start of the first bucket with `peak ≥ T`, scanning from the bucket
    holding `max(s, a·chunk, (b − leadCells)·chunk)` (`leadCells` 3, 96 ms) up to, but not
    including, the first bucket starting at or after `(b + 1)·chunk`, then clamped to at least `s`.
    With no such bucket, or no peaks cache, the onset is `b·chunk`.
  - (d) **The walls.** An onset at or past `limit` falls back to `b·chunk`.
  - So a start never moves earlier, never reaches its own end or the next word's start, and needs
    no model and no key. Ends are not moved (TX-19).
- **TX-16 — Applied when words are read, by every on-device reader.** The stored run is unchanged:
  no cache, version or format change, and a moved start is never written back.
  `TimelineTranscript.deviceWords` loads the media's voice and peaks caches and applies TX-15, so
  `get_timeline_transcript`, the Transcript tab and `TranscriptCut` (E0's onset is now the moved
  start) read moved starts, and `get_transcript` applies the same rule to the run it read
  (`TranscriptReader.deviceWords(_:for:moved:)`). A word is placed, and its clip found, by its moved
  start (R6-10's half-open test on the moved tick). Cloud words are read as before. Amends TX-10
  and TR-14.
- **TX-17 — Identity and order survive a move.** `Identity.source` stays the recogniser's tick
  (`SourceWord.identityTick`, `recognisedStart ?? source`), so a selection, an id an agent holds and
  `k` survive a cache landing that moves a start; `TranscriptCut.edges` matches a word to its
  source word by that tick, and TX-22's pause set is keyed by it too. Order within a media is kept:
  by (d) each moved start is earlier than the next word's stored start, which is at most its moved
  start. Across instances TX-10 orders by the moved start.
- **TX-18 — A missing cache.** With no voice cache the words are unmoved and the answer says so in
  its existing note (`get_timeline_transcript`'s `notes[]`, appended to `get_transcript`'s `note`):
  "The word starts of “<name>” are where this Mac's recognizer put them, often early: it has no
  voice cache yet. Call again once it has." (amended by #526) With no peaks cache the move lands on the 32 ms cell
  grid (`b·chunk`). There is no new compute path: the open and import cache pass
  (`generateCaches`) already makes both caches, and a tool answers what is there now, as
  `detect_silence`'s `voice_pending` does. The tab re-reads a media's words when either cache lands
  (`.mediaCacheDidChange` of kind `speech` or `peaks`), keeps the shown words and the selection
  until that re-read merges, and a load that read before a landing (a per-media epoch moved under
  it) is discarded and read again. The request's recommendation to compute the cache on demand is
  declined: `async` is confined to `MediaImporter.swift` (585 lines), and the pass is already
  running for every media a document holds.
- **TX-19 — What is left alone, and how it is measured.** Cloud (AssemblyAI) words are not moved:
  no measurement of them exists without a paid run, and their lead is −60 ms. Ends are not moved:
  TX-S3 measured starts only, and a cut reads a word's end only for its 1 s cap; TX1b's proof
  reports the error at word ends (O7), and an error over one frame is filed. **The acceptance:** a
  phrase's onset is its first sample over −40 dBFS after a gap, by the proof's own arithmetic; each
  phrase-initial on-device word's moved start lies within one 30 fps frame (20,000 ticks) of it; a
  word cut leaves no fragment of the next kept word and at most 0.2 s (120,000 ticks) from
  `cut_end` to that word's onset. The pause BEFORE a deleted word stays (TX-30), and a gap over 1 s
  is TX3b's. TX-S3's E0 note and TX-30 are amended with the re-run's E0 numbers only: E1 and E2
  add their lead to the tool's start (`TranscriptCut.sourceOnsets`, `cut_spike.py`), which is now
  moved, so over moved starts they measure no defined rule; their figures and the verdict the
  spike prints from them are not recorded and are not filed. S-TH1 and S-RT1 do not exist yet:
  TX-S3's real-speech rows are skipped by name and owed, and JOB-11 stays the judge. TX3b keeps its
  no-sliver clamp (its option (a)), per the owner's answer of 2026-11-02; it holds once starts sit
  on their sound.

## CU3b — import and relink attach a cursor file (2026-11-02)

Recorded before the code. CU-34 and CU-38 are CU3b's: a movie's `<stem>.fjcursor` reaches its
media at every import door, at a recording's landing and through Relink, and a clip whose media
has a cursor not in the picture gets a Cursor section with one row. No format bump, no `rc_*`, no
op, no product tool and no core change: `media.cursor` (CU-39) already travels in a probe, and a
probed relink already replaces it (`core/src/edit_relink.rs`). The cursor file is read on the
Mac, so nothing here is keyed (CJ-3).

- **CU-34 — A cursor file is attached only when it opens and its `movie_size` is the movie's.**
  `MediaImporter.cursorAttachment(at:to:)` (`app/Sources/MediaImporter+Cursor.swift`) opens the
  file through `ReelCursor(data:)` (the open is the check, CU-15), then decodes the header's
  `in_picture`, `movie_size` and `cursor_image`, and attaches it only to a descriptor of kind
  video with pictures whose `width` × `height` — the probe's display size — equal `movie_size`.
  Every recording's written track has no rotation, so the two sizes are the same for it; a
  rotated movie's file is not attached.
  - **(a) Every import door.** `probeAllowingRewrap`'s direct probe — the funnel of Add Media…,
    a drop, a document's open, `import_media` and the recorder's settle probe — passes its
    descriptor through `withCursorBeside`, which looks for `CursorFileWriter.url(forMovie:)`
    beside the movie. A missing file, or one that fails the check, attaches nothing and says
    nothing (an import is never refused for its cursor file). A rewrapped copy (a WebM or
    Matroska copy, an ffmpeg conversion) is not looked beside.
  - **(b) What is stored.** `media.cursor = {path: the file's path, bookmark:
    bookmarkString(file), in_picture: the header's}`.
  - **(c) A recording's landing.** The settle probe runs before the cursor file is written (the
    walker's order movie → microphone → camera → cursor, CU-18), so `saveCursor` attaches each
    file it wrote to its segment's descriptor itself, on the capture queue after the write
    (`RecordingSegment.withCursor(url:problem:image:attached:)`); a failed attach leaves the
    segment as CU-18 left it. Until CU3c every recording writes `in_picture: true`, so nothing
    is drawn and no Cursor section shows.
  - **(d) `land_recording {cursor}`** (a dev tool): a cursor file path, only with `movie`,
    attached to the one screen segment through `cursorAttachment` and `withCursor(…, attached:)`
    before either door. Refused by name: `cursor` without `movie`, and a file that does not
    attach (its sentence prefixed "land_recording: ").
  - **The sentences** of a file that does not attach: "The cursor file <name> could not be read:
    <reason>." · "The cursor file <name> was not attached: <the core's sentence>" · "The cursor
    file <name> was not attached: its movie_size is W × H and the movie is W2 × H2." · "The
    cursor file <name> was not attached: <movie> has no picture."
- **CU-38 — Relink, the Cursor section, and the export's cursor warnings.**
  - **(a) Relink.** Every probed relink — Relink…, the Media tab, `relink_media` and the
    re-copy on open — goes through `MediaImporter.relinkProbe(_:current:)`: the probe's own
    cursor (the file beside the new movie, CU-34 (a)) when it has one; else the current
    `media.cursor` kept verbatim when its file still exists (`cursorURL(for:)`) AND the new
    probe is a video with pictures whose `width` × `height` equal the stored media's — the sizes
    CU-34 matched at attach, since a cursor's positions are absolute movie pixels; else none,
    which clears it (CU-39's replace rule, unchanged in the core). No parse: sizes and a
    file-exists check, so it may run on main. `MediaConsolidator` and the relink without a probe
    keep the cursor as CU-39 says.
  - **(b) The Cursor section.** Id `video.cursor`, title "Cursor", in the Picture sub-tab after
    the source-pixels block (after Background) and before Shadow, shown only when every selected
    clip is a media or still clip whose media has `cursor` with `in_picture` false
    (`VideoPane.allCursored`). One checkbox, "Show cursor", reading `video.cursor.show`
    (true without a cursor), mixed over a selection that disagrees, writing a sparse `{cursor:
    {show}}` (`VideoPatch.cursorPart`, `CursorPatch`) — an action's end inside one, where `show`
    switches at the end (CU-30); undo name "Show Cursor"; Reset writes `show: true`; the summary
    "on" or "off"; closed by default. `ClipPane.structureSignature` carries `allCursored`, so the
    section appears or goes when a relink, an undo or a landing changes a media's `cursor` under
    a fixed selection. CU4 adds the section's other rows.
  - **(c) A finished export's cursor warnings** (CU-37 (c)): " 1 cursor warning" or " N cursor
    warnings" after the graphic count on the Export Queue row's message (no hover text) and on
    the progress sheet's line (with " (hover for details)."); each tooltip lists
    `Exporter.cursorSentences`, one per line (`cursorWarningSuffix`, `cursorWarningDetails`).
  - **(d) The proof.** `cursor_layer_proof.py`: I1 import attaches a matching file and not one
    whose `movie_size` differs; I2 relink keeps a resolvable cursor, clears a missing one,
    replaces it with the file beside the new movie, and clears it for a movie of another size;
    I3 `land_recording {cursor}` lands a clip that draws its cursor where the file says, and
    `cursor` without `movie` is refused; I4 (probe) the section's place, its gate, the signature
    under a fixed selection and its one write; I6 (probe) the suffixes, the details and the
    queue row's tooltip; I5 — the road map's granted L1, the overlay against a burned tip — owed
    to CU1b2, whose burned-tip helper it needs, and skipped by name. `cursor_proof.py` K17
    (granted, Release, skipped by name without Screen Recording): `record_screen {seconds: 2,
    place: true}` lands media whose `cursor` is `{path: segments[0].cursor_path, in_picture:
    true}`. Nine mutants: the size check removed (I1); `relinkProbe` not keeping a resolvable
    cursor, and its size test removed (I2); `land_recording`'s `attached:` dropped (I3);
    `allCursored` without its `media.cursor` test, and without its `in_picture` test, the
    `makeSections()` line removed and the `structureSignature` entry removed (I4); the queue
    tooltip's cursor details dropped (I6).
