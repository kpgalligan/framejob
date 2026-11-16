# Spec §11 — decisions: Creator jobs, masks made on demand onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-4.md`](creator-jobs-4.md), so a citation never has to
say which file. This file holds CO-22 (CO2b), CJ-30…CJ-35 (CJ3) and CO-30…CO-32 (CO3). The series
goes on in [`creator-jobs-5.md`](creator-jobs-5.md), which is why this file is lettered. It is new
because `creator-jobs-4.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the
entries moved here unchanged, and an "above" or "below" in one may now point into a sibling file.

CO-22 is CO2b's (masks made on demand, and files that wait), recorded before its code; the number
was reserved by CO0 for this phase. The owner's answers it builds on: analysis at once (CO-15, the
CO1 answer of 2026-11-01), and for CO2b a pending cutout drawn uncut in the preview — **yes**, with
the status saying so, which is CO3's Background section. No format bump, no core change, no `rc_*`.

- **CO-22 — Masks are made when a clip asks; a file waits for them.**
  - **(a) What is wanted.** Every plan video segment (duration > 0) of a clip — top level or inside
    a nest — whose BASE `video.cutout` is set (any `background`), from the document's `project`
    and, with a nest open, its `editedProject`; a media with no file (a slate) is not wanted. A
    window is in FORWARD source ticks: forward `[sourceTick(a), sourceTick(b))`, reversed (its
    pivot T from `ReverseMirror.pivot`) `[T − sourceTick(b), T − sourceTick(a))`, where `[a, b)` is
    the segment clipped to the range asked (none: the whole segment) and `sourceTick` is
    `CutoutLookup.sourceTick`. **The need rule** — what CO-24's lookup can ask of a window — is
    `⌊lower·rate + 1e-9⌋ … grid.index(of: max(lower, upper − 1))`, clamped to the grid: at most one
    frame past a frame-aligned window, so a ×0.5 clip's last frame is not a miss. One request per
    media, holding its merged missing ranges (`AnalysisStore.lookup` per need range).
  - **(b) When.** `ensureMasks()` is the last line of `ensureRampAudio()`, so it runs after every
    edit, at the open, when a reverse lands and when a ramp settles — never inside a live gesture —
    and at once (CO-15). Main reads the handles, `mediaURLs()` and `cacheDirectory` (only when a
    cut-out clip exists; with none it releases a want it made before); `CutoutWants.queue`, one
    serial `.utility` queue for every document, builds the requests and wants them. One lane owner
    per document (`AnalysisLane.newOwner()`), alive while `RecipeSource.shared.project(for:
    recipeKey)` is not nil; a settle calls `masksDidSettle()` on main:
    `packageContentsDidChangeOnDisk()`, then `ensureMasks()`.
  - **(c) The keep rule, for every role (document, export, frame).** The candidates are
    `AnalysisLane.openRequests(kind: .masks, cacheDir:)` — every owner's queued and running masks
    requests for that cache folder — so an export or a frame shares the document's job rather than
    queueing a second one behind it (`pictureWidth` 1). Of these, a **running** request (started,
    not ended) whose ranges meet its media's need is kept; a **queued** one only when every range
    of it lies inside its media's need, so a queued job never analyses frames nobody wants; an
    ended one never. Only a media with a miss is wanted at all. The caller wants the kept requests
    plus, per media, a new request holding only the needed, uncovered indices outside the kept
    requests' ranges. An edit never restarts a running job that has published.
  - **(d) A publish redraws.** `AnalysisStore.publishFile` posts `.analysisDidPublish` on main after
    each successful publish (`kind`, `media`, the standardized `cacheDir`); the editor of the
    document whose `intendedCacheDirectory` matches, for `masks`, calls
    `playback.refreshPausedFrame()` (CU3a2's path). No rebuild: the plan did not change and the
    compositor re-reads the pack on the marker's stat (CO-25). This replaces the road map's
    `.reversedMediaDidChange` line.
  - **(e) An export waits** in `Exporter.withRampAudio`, before its image-sequence guard, so a GIF
    or an APNG waits too, for `windows(plan:, range: start ..< start + duration)` of its settings,
    under a lane owner of its own (alive always, made at its first want, kept per export recipe key
    and released by `Exporter.releaseMasks(key:)` inside `releaseRecipeKey`'s `ramp` deferral).
    No cache folder, an unreadable media or a failed job fails it `cutoutFailed` — "Clip N's person
    masks could not be made: <why>." — naming the first window's clip of that media, the reason
    "the project has no cache folder to keep the analysis in", the request error's sentence, or
    the job's own. It wants and `AnalysisLane.wait`s on (c)'s kept requests plus the remainder,
    with no deadline but the export's `cancelled`; after `.landed` the store is read again, and a
    media still missing after a second landing fails it ("its masks do not cover the frames it
    plays").
  - **(f) A frame waits** only when asked (`cutoutWait > 0`): `render_frame` and File ▸ Save
    Frame… pass 30 s (`Exporter.frameCutoutWait`); the eyedropper, the look gallery, the qualifier
    pick, `snapshot_ui`, thumbnails and an image sequence's frames pass none (CO-6). Its windows are
    the recipe layers at t with `cutout.background == remove`, `mask.kind == media` and a `.track`
    source, through `CutoutPlan.covering`, over `[t, t + 1)`. It wants (c)'s requests under a
    fresh owner, polls the store every `AnalysisLane.pollInterval` until every need is covered, one
    of its requests failed, or the limit, then releases the owner. Drawn uncut, and named: those
    layers' clips still uncovered (an unreadable media at once; with no cache folder, every one).
    `render_frame` says "Clip N is drawn uncut: its person masks were not ready within 30 s." once
    per clip, ascending, before its last sentence; Save Frame, after a successful save, shows an
    informational sheet "Saved without Remove Background" — "<file names> drawn whole: the person
    masks were not ready within 30 seconds." A clip covered with no person found (CO-5) is not
    named.
  - **(g) The preview** draws a pending, cancelled or failed cutout uncut (CO-6, the owner's CO2b
    answer); the status saying so is CO3's Background section.
  - **(h) The dev log.** In a dev build every want of the three roles is logged once per (role,
    owner, request), the last 512 kept; `analysis_job` answers them as `mask_wants: [{role, owner,
    media, ranges, wanted, outcome?, error?, queued_at?, started_at?, ended_at?}]`, `wanted` true
    while that owner wants it now, always present.
  - **(i) The proof** is `co2b_proof.py`: P1 (the need rule), P2 (the keep rule), W1–W9 with W3b
    and W4b, Z1, and eight mutants; JOB-62 is the person's check that a paused picture redraws
    cut without play.

CJ-30…CJ-35 are CJ3's (face samples: the `faces` analysis kind), recorded before its code with
spike CJ-S2's verdicts; CJ-35 was recorded after CJ-S3 (b)'s run with a `faces` job, which needs
the built app, and CJ-34's measure after the probe's. The road map expected
no owner question for CJ3, and the owner's answers of 2026-11-01 hold none. Nothing here sends
anything: Vision runs on the Mac, so there is no `ModelKeys` row (CJ-3). No core, FFI or format
change (CJ-20); no tool is added.

- **CJ-30 — `faces`, the first machine-learning kind, at CJ-S2's rate, size and reader.** Per
  sample of source time, every face Vision finds: its box, confidence, roll and yaw
  (`VNDetectFaceRectanglesRequest` revision 3) and, from `VNDetectFaceLandmarksRequest` revision 3
  with `constellation = .constellation76Points` over those observations, the mouth's inner-lip gap
  and outer-lip width, each over the face box's height in picture pixels (CJ-33). Each request is
  FRESH, on a fresh `VNImageRequestHandler`, per analysed frame; no request is stateful.
  - **CJ-S2's run** (`faces_spike.py`, `rule_sha256` `c41417fb…95bb2b11`, matching; macOS 26.5.1
    (25F80), Apple M2 Max, on AC power, three lanes on the machine). The inputs were the face
    fixtures (`face_fixtures.py`); S-TH1…S-TH4 do not exist. `VERDICT rate=10 size=720
    landmarks=yes rectangles=neural_engine(branch 1) landmarks_device=neural_engine(branch 1)
    reader=converted compare=cross_run dropped=none realtime_1080=10.30 realtime_4k=8.88`.
  - **Rule 3, the size.** On `faces_small.mov` (the face box an eighth of the frame's height),
    recall was 1.0000 over 600 samples at 720, 1280, 1920 and native (1920), so the read's long
    side is **720**, or the media's own when smaller.
  - **Rule 2, the rate.** At 720 on rule 1's devices, decode + rectangles + landmarks ran at
    10.29, 10.30 and 10.31× real time on 1080p30 (`faces_moving.mov`) and 8.87, 8.88 and 8.95×
    on 4K30 (`faces_moving_4k.mov`), past 3× and 1.5×: **10 samples a second**.
  - **Rule 4, landmarks.** At that rate on 1080p30 the landmarks' median Vision seconds were
    1.51 against the rectangles' 4.02 (0.38×, under 2×): the mouth measures **stay in `faces`**,
    and SW8 builds no `mouths` kind.
  - **Rule 5, the reader.** No log or HLG sample exists, so face kinds read through the
    **converted** reader for a converting media — `AnalysisFrames.read`'s standard arms, direct
    or through `oneClip` and step 0 (CJ-23), not CO-7's third arm. The log and HLG rows are owed
    with S-TH2…S-TH4.
  - **Rule 6** (S-TH1's face share) and every S-TH row skip by name and are owed in CJ3's record.
    Run at CJ7b (2026-11-06) under rule 6's amended window (the owner: count from the first face
    in frame): 0.9967 (598/600), a pass; CJ-30 unchanged.
- **CJ-31 — No identity is stored.** Each sample's faces are stored as Vision found them, in a
  fixed order: by box centre x, then centre y, both in CJ-22's top-left frame, compared as exact
  `Float`s (`AnalysisFaces.ordered`). A consumer that needs a face followed links faces itself over
  the window it reads (VR in the core, VR-21; SW by each sample's largest face, SW-81). No face is
  named or compared across media. Values are raw; smoothing is a planner's.
- **CJ-32 — Each request is pinned to its device, read back per job and recorded in the stamp.**
  CJ-S2's rule 1 picks a device per request, and only among devices that EVERY stage of that
  request reads back after the pin (`AnalysisVision.pin`): a device left `auto` or `unavailable`,
  or read back as another, is dropped and listed. In the run both requests had one stage
  (`VNComputeStageMain`), and every run on each of the three devices read back that device, so
  none was dropped. Each device's three digests were identical, and the Neural Engine was the
  fastest for both: rectangles 5.15…5.21 s over 600 samples at 1280 (the GPU 6.69…6.97, the CPU
  13.90…13.99), landmarks 1.18…1.20 s (the GPU 2.76…5.79, the CPU 3.59…8.85). So **both requests
  run on the Neural Engine** (branch 1). The stamp's `device` is
  `rectangles:<readback>;landmarks:<readback>`, read once; a job re-pins every fresh request and
  refuses to run when one reads back other than the stamp says (`FaceError.device`). Branch 1
  means two runs on the pinned device write the same bytes, which `faces_proof.py`'s F2 checks
  across runs; under branch 3 the proofs would compare against the cache only (E9's rule).
- **CJ-33 — The sample grid and `samples.bin`.**
  - **The grid** is `AnalysisGrid(samplesPerSecond: 10, duration:)` (`AnalysisKind.grid(of:)`):
    the coverage and the payload are indexed by sample k, at `ticks(k) = round(k × 600000 / 10)`.
  - **Sample k** takes the first kept frame whose pts lies in `[ticks(k), ticks(k) + one sample
    interval)`; with none it holds pts −1 and no faces. A frame is tested against the kept frame
    before it, so the choice is the same whatever the job's bounds, and a frame serving two
    samples is analysed once (`AnalysisFaces.samples(at:after:grid:)`).
  - **The read** covers the frame indices from `ticks(k0)` through one sample interval plus one
    frame past `ticks(k1)`, clamped to the media, through `AnalysisFrames.read` with its pre-roll
    (so the frame before the first is known), at CJ-30's size.
  - **The mouth.** The gap is the vertical extent of `innerLips.pointsInImage`, the width the
    horizontal extent of `outerLips.pointsInImage`, each divided by the face box's height in the
    read picture's pixels; image axes, raw. NaN when Vision gives no lips.
  - **The file** (`cache/analysis/faces/<id>/samples.bin`, little-endian): a 16-byte header —
    ASCII `FJFS`, `UInt16` version 1, `UInt16` face record bytes (36, or 28 without landmarks),
    `UInt32` sample count, `UInt32` face count; one 16-byte row per sample index from 0 — `Int64`
    the frame's pts in ticks (−1: none), `UInt32` its first face, `UInt32` its face count; then
    the face records — `Float32` x, y, width, height (0…1, top-left, display orientation),
    confidence, roll, yaw (radians), mouth gap, mouth width (NaN: absent).
  - **The publish.** A job publishes through `AnalysisStore.publishFile` every 30 s, through the
    samples decided (a sample is decided once a frame past its interval, or the frame serving it,
    has been read), and at each range's end. Its write decodes the on-disk file and replaces the
    covered samples; a file that does not decode, or holds another sample count or record size,
    is written fresh and answers false, so the marker keeps the job's coverage alone.
- **CJ-34 — `get_media_analysis {kind: "faces"}`'s answer.** Beside the common fields (CJ-25):
  `rate` (10), `count` and `samples`, one row per COVERED sample in the window:
  `{source, frame, faces: [{box: [x, y, w, h], confidence, roll, yaw, mouth_gap, mouth_width}]}`,
  `source` the sample's instant `ticks(k)`, `frame` the read frame's pts or null; with `clip` also
  `clip_time` and `timeline` from `source` (`AnalysisClipTimes`). Every float is rounded to 4
  decimals in the ANSWER only (`AgentServer.answerValue`; ≤ 0.4 px of a 4K frame's width), NaN
  answering null; the cache stays raw. The rounded value is written as a decimal number
  (`NSDecimalNumber` of its shortest spelling): `JSONSerialization` prints a `Double` to 17
  significant figures, so a rounded `Double` alone came out as `0.43219999999999997` (P5's first
  run). CJ-25's default window (the whole media, or the clip's played window) and its 512 KiB cap
  stand: over the cap the call is refused naming as the largest `to` the `source` of the first row
  that does not fit, as masks' runs are. **Measured** (`faces_probe.swift` P5, a one-face row at a
  late source): 176 bytes without `clip` and 221 with it, so a default call holds 2,962 rows, 296 s
  of samples (2,361, 236 s, with `clip`), less with more faces in frame. The catalog's prose and
  spec §7.9j state that length and tell an agent to read a longer media in `from`/`to` windows of
  at most that (the prose's example is 2 minutes).
- **CJ-35 — CJ-S3 (b) with a `faces` job: no pause.** `lane_spike.py --playback --kind faces`
  (`rule_sha256` `209c6f01…f0309ce830`, matching) on a Release instance: `play_preview`'s composed
  frames over 20 s of a 1080p30 timeline, idle and then with a `faces` job wanted on another
  document over the moving still, three of each. The recorded run, with the job over the whole
  ten-minute still and running through every play: idle 600, 600, 600 and busy 600, 600, 600, a
  0.0 % drop. Three earlier runs on the same instance: a 120 s window (597, 599, 600 against 598,
  600, 600; each job landed in about 9 s, inside the play, so the window was widened); the whole
  still with the job rows read wrongly (600, 599, 600 against 600, 600, 600); and once more (600,
  599, 600 against 224, 600, 600, the 224 while the machine's load average was 32.85 with the other
  lanes' builds; the median still 600). No run passed the 2 % rule, so **the picture queue does not
  pause** for `faces`, and CJ-21 stands unamended.

CO-30…CO-32 are CO3's (Remove Background in the inspector and the menus), recorded before its
code. The owner's answer for CO3 (2026-11-01): Clip ▸ Remove Background has **no key
equivalent**. No format bump, no core change, no `rc_*`: Swift, the documents and the proofs on
top of CO2a1, CO2a2 and CO2b. Vision runs on the Mac, so nothing here is keyed (CJ-3).

- **CO-30 — The Background section and Clip ▸ Remove Background.**
  - **(a) The rows, in order.** The Picture sub-tab's **Background** section (`video.cutout`),
    right after Chroma Key, shown when every selected clip can be cut out (a media or still clip
    of a video file with pictures, `CutoutStatus.canCutOut`): "Remove background" (a checkbox);
    Background (a popup, Remove / Keep); Edge (−1…1, two decimals, a slider, quick values −0.5,
    −0.25, 0, 0.25, 0.5); Feather (0–100 %, quick 0, 10, 25, 50); Status (a read-out 170 pt wide,
    its tooltip the full words); and a button row, Analyze Now. The road map's draft is set aside
    twice: there is **no Quality row** (CO-S1 kept no Best and CO-20 refuses `best`; CO4 owes it)
    and **no "Paused while playing"** (CO-12: a masks job does not pause). Background animates as
    CO-20 says — it switches at an action's end — superseding the draft's "Background
    base-only".
  - **(b) Where each row writes.** The checkbox and the section's Reset write the clip's BASE
    `set_video` only, so inside an action their gutter is ⊘: turning on writes a whole default
    cutout (`{cutout: {}}`'s five defaults) only to the selected clips that have none, turning off
    writes `cutout: null` to them all. `InspectorBinding.structural(video:for:)` sends `cutout`
    (its presence, a whole one or null) to the base, always. Background, Edge and Feather are
    enabled only when every selected video clip has a base cutout (`allCutOut`) and write a sparse
    `VideoPatch.cutoutPart`, which animates: with an action selected an end gets only the row's
    own key (`set_action_end {video: {cutout: {edge}}}`), never `subject`, `quality` or a null.
  - **(c) The summary and the Status words.** The summary is "off" while no selected clip is cut
    out; else the Status words for one clip, or "on". Status: no cutout "Off"; no frame to analyse
    "No picture to analyze"; analysing "Analyzing N %" (N = ⌊progress × 100⌋, at most 99); every
    needed frame covered "Ready", or "No person found" when no run of the clip's window found one
    (CO-26); a failure "Failed: <why>" — "the media file is missing", "the media file cannot be
    read", "no cache folder", or the lane's own sentence; several clips "—". Analyze Now is
    enabled when a selected cut-out clip is analysing or failed; it runs
    `ProjectDocument.analyzeMasksNow()`: `ensureMasks()` (CO-22 stays the one want path), then,
    on `CutoutWants.queue` after that want, `AnalysisLane.retry(owner:)`, which clears the
    `.failed` or `.cancelled` outcome of the owner's requests that are neither running nor queued
    (as `want` does for a request wanted anew) and reconciles; a running or queued request is
    untouched, and `want`'s reset rule and `wait` are unchanged.
  - **(d) The read-out's life.** The pane holds its status (`CutoutStatus.Memo`) while the
    document's handles and its `ReverseSource` resolution are unchanged, and through a live
    gesture. While the held state is analysing or failed and the read-out is in a window, a 0.5 s
    main-run-loop ticker re-reads only the lane — each of the owner's requests' runs (outcome and
    `endedAt`) and the running job's progress; a changed run, or a `masks` `.analysisDidPublish`
    for the document's cache folder, recomputes the status, refreshing the pane when the state
    changed and the read-out alone otherwise. The pane's Analyze Now drops the held status.
  - **(e) The menu.** Clip ▸ Remove Background, right after Look ▸, no key equivalent (the
    owner's answer): enabled when the selection in the open scope holds a clip that can be cut
    out; its checkmark is on when every such clip is cut out, mixed when some are, off when none
    is; it toggles them (all on → all off; otherwise the off ones on, a cut-out clip's own values
    kept) as one undo step, "Remove Background", one base `set_video` per clip as Clip ▸ Motion ▸
    writes.
- **CO-31 — `analyze_cutout` and the status rule.**
  - **(a) The status of a clip** (`CutoutStatus.status`, main thread). Its windows are
    `CutoutWants.windows` of the document's handles (`[project]`, with a nest open `[project,
    editedProject]`) for that clip; `frames` is the count of their merged needs (CO-22 (a));
    `covered` the needed indices the store covers for the stamp the analysis would make (the stamp
    made once per cache folder, media and URL, on main); `subject_found` CO-26's, over the clip's
    hull window. The order: no base cutout → off; `frames` 0 → no picture; `covered == frames` →
    ready, or no person — before any failure check, so a clip whose masks are all stored is never
    failed by another window's job; no file, no cache folder or no stamp → failed; a `.failed` run
    among the document owner's (`maskOwner`) requests of the media whose ranges meet the clip's
    needed, uncovered indices → failed with the lane's sentence; else analysing. **Progress** is
    `(C_out + f · R_in) / N`: N the needed indices, R_in those inside the ranges of the owner's
    running masks request of that media, C_out the covered needed indices outside them, f that
    request's `AnalysisLane.progress` (0 before its first frame); with no running request R_in is
    0 and C_out is every covered needed index. A running job's mid-job publishes count through f
    alone, never twice.
  - **(b) The tool.** `analyze_cutout {clips?, wait?}` is an app-state tool, off the main thread,
    with no `scope`: it acts in the open scope and names its clips there. Refusals, in order:
    `wait` that is not a number or lies outside 0…60 — "wait must be from 0 to 60 seconds."; a
    named clip that does not exist (`optionalClipsArg`'s sentence); a named clip with no base
    cutout — "Clip N has no Remove Background; set_video {cutout: {}} turns it on."; with none
    named and no cut-out clip in the open scope — "No clip in the open scope has Remove Background
    on; set_video {cutout: {}} turns it on.". Then one main hop runs `analyzeMasksNow()` (the
    pane's Analyze Now), then `CutoutWants.queue.sync {}` off main, so the want and the retry have
    run before the first read; then it reads the statuses every 0.25 s (main hops) until every
    clip is ready, no person, failed or no picture, `wait` seconds pass (0 when absent: the status
    now), or the assistant's Stop — never a timeout refusal.
  - **(c) The answer.** `{ok, clips: [{clip, media, state, progress, quality, frames, covered,
    ready, subject_found, centroid, error?}], project}`: `state` one of `analyzing`, `ready`,
    `no_person`, `failed`, `no_picture`; `progress` to three decimals (`covered / frames` outside
    analysing); `quality` the clip's; `ready` whether `covered == frames > 0`; `error` the tool's
    sentence when failed, "Clip N's person masks could not be made: <why>." **`centroid`** is null
    unless the clip is ready and a subject was found: the mean, over the needed and covered pack
    frames whose mask is `found`, of each frame's value-weighted centroid `(Σ v·(x + 0.5) / Σ v,
    Σ v·(y + 0.5) / Σ v)` in mask texels, scaled by the media's width over the mask's and its
    height over the mask's — `{x, y}` in the media's upright display pixels, top-left origin, y
    down — computed off main from values captured on it. CO7's `focus` reads it.
- **CO-32 — CO3's proof.** `co3_proof.py`, its probe `co3_probe.swift`: I1 the section registered
  after Chroma Key and its checkbox committing one `set_video {cutout: {five defaults}}` step; I2
  Status reading "Analyzing 0 %" under `-RCDevAnalysisHold`, then "Ready" on the person fixture
  and "No person found" on the screen recording, from `snapshot_ui`'s layout dump; I3 with an
  action selected Edge writing `set_action_end {video: {cutout: {edge}}}` alone, Background
  `{background}` alone, the checkbox ⊘ and its write the base `set_video`; I4 `analyze_cutout
  {wait: 0}` under the hold answering analysing, not ready, `covered < frames`, centroid null, and
  `{wait: 60}` without it ready with `covered == frames ==` `get_media_analysis`'s `frames`; I5
  the menu item's state off, mixed and on, and a mixed toggle turning on only the off clip (the
  other's edge kept) in one undo step; I6p and I6 the centroid against the probe's own reading of
  the pack, within 1e-6 px; I7 a clip ready beside a clip of the same media failed by a read-only
  masks folder, then, the folder restored, `analyze_cutout {wait: 0}` taking the failed clip's
  Status out of "Failed" within 2 s and `{wait: 60}` answering ready; I8 the progress rule's three
  cases; Z1 an empty parity log. Eight mutants, once, on Release. No JOB row: the screen catalog's
  `05i-clip-background` is the section's look.
