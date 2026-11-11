# Spec §11 — decisions: Creator jobs, Make Vertical's step onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-10.md`](creator-jobs-10.md), so a citation never has
to say which file. This file holds VR-30…VR-37 (VR3a) and CO-80…CO-84 (CO8). The series goes on in
[`creator-jobs-11.md`](creator-jobs-11.md), which is why this file is lettered. It is new because
`creator-jobs-10.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries
moved here unchanged, and an "above" or "below" in one may now point into a sibling file.

## VR3a — Make Vertical's step, its copy and make_vertical_version (2026-11-03)

Recorded before the code. VR3a is the first half of VR3's split (the road map's "Split"
paragraph under VR3): the step as a function of a document, the copy through CJ5b's derived
document, and the tool. VR3b, next in lane C and before VR4, adds File ▸ Make Vertical
Version… and its sheet, the Analyzing sheet and its Stop, `-RCDevVerticalAccept YES`, the
screen, the guide, spec §9 and JOB-33. No core, FFI, header, op or `Kind` change, and no format
change (43 stands; `OP_COUNT` 70); one product tool (123 → 124); nothing is sent anywhere, so
nothing is keyed (VR-2, CJ-3). The owner's answers of 2026-11-01 for VR3: 4:5 is offered beside
9:16 and 1:1 (VR-32), and the copy opens with the step as its one undo step (VR-31). VR-38 is
left to JOB-35.

- **VR-30 — Make Vertical is one grouped edit applied to a document; the copy is the default**
  (`VerticalVersion.swift`, `VerticalVersion+Plan.swift`, `ProjectDocument+VerticalCopy.swift`,
  all new). The step is `VerticalVersion.plan` on a handle — its ops tried in one
  `SwitchAngle.Trial` — and FC9 calls the same step on its own short (FC-90). The copy is
  CJ5b's derived document handed the source's handle unchanged (`range: nil`: every media
  stays, every cache and analysis is carried); the step is applied there with one
  `performGroupedEdit`. The source never changes and gains no undo step. With `copy: false` the
  step is applied to the addressed project in place. **Owed to VR3b:** File ▸ Make Vertical
  Version…, its "Make a copy" checkbox (ticked by default, never remembered) and the sheet.
- **VR-31 — The copy opens with the step as its one undo step, "Make Vertical"** (FC-90's
  name; the owner's answer), named "<source name> (9:16)", "(4:5)" or "(1:1)" until saved
  (`derived(…, name: "<displayStem> (<shape>)")`). When the copy's handle is still the one it
  opened with after the grouped edit, the door closes the copy, removes the package at `path`
  when one was given, and throws "Make Vertical did not apply to the copy, so nothing was
  made."
- **VR-32 — Shapes and sizes** (`VerticalShape`): `9:16`, `4:5` and `1:1` (the owner's answer
  adds 4:5). w = min(W, H) rounded down to even; h = 2 × round(w × r / 2) with r = 16/9, 5/4
  or 1 — from 1920 × 1080: 1080 × 1920, 1080 × 1350 and 1080 × 1080. A size equal to the
  current canvas is refused ("the canvas is already W × H, so there is no <shape> version to
  make."). 4:5 is a size and nothing more: every rule here and in VR4 that reads "taller than
  wide" applies to it.
- **VR-33 — How each top-level clip is classed** (`VerticalVersion.classify`: the first match
  per top-level clip with a picture — not audio-only, not an adjustment clip — in id order, on
  the OLD snapshot; a nest's contents are never touched). Fill is `max(W/sw, H/sh)` over
  `snapshot.sourceSize(of:)`, clamped to `CanvasScaleSession.minScale…maxScale`
  (`edit_fit.rs`'s `fill_scale`).
  (1) **Backdrop**: named exactly "Blurred Background", with a partner on a track in front of
  it with an equal `source`, `start` and `duration`.
  (2) **Plate**: a `shape` rectangle whose width and height are within 0.5 px of the old
  canvas, x and y within 1e-6 of 0 and scale within 1e-6 of 1 (a shape plate); or an `image`
  or `still` named "Background" with x and y within 1e-6 of 0 and scale within 1e-6 × fill of
  the old fill (an image plate).
  (3) **Picture**: a `media` clip with a picture, a `still` or an `image` whose `canvasRect` at
  its first frame (base `VideoProps` with scale, x and y from `clip_state` at its start)
  covers one axis of the old canvas — both edges at or beyond the canvas's, at most 1 px
  inside — and on the other axis is centred within 2 % of that side or covers it too. A
  punch-in, or a clip Follow Subject framed at its 1.25 default, is a picture; a
  picture-in-picture, covering neither axis, is not.
  (4) **Nest**: a nest clip passing the same test.
  (5) VR4's full-frame graphics are class 6 until VR4 (VR-42).
  (6) **Other**: everything else.
- **VR-34 — The order of the step, and where it stops** (`VerticalVersion.opening`, `plan`).
  The draft's (3) and (4) are swapped, because a backdrop's fate reads its partner's result.
  Every op is tried on one `SwitchAngle.Trial`; the trial's ops and handle are the plan.
  (1) `set_canvas {width, height}` with no rescale and (2) `add_track {index: 0, name:
  "Backgrounds"}` (`opening`); a refusal answers "Make Vertical was refused at
  set_canvas|add_track: <reason>" and nothing is made.
  (3) In clip-id order, each picture, nest and other clip gets `reframe_clip {clip, follow,
  zoom, where_empty, from_width: W, from_height: H, backdrop: Backgrounds}` (W × H the old
  canvas): a media picture takes the settings' follow, with `where_empty` and `subjects` only
  for a following kind; a media picture whose media file is missing (no URL in `mediaURLs()`)
  under a following kind takes `keep` and is not followed, "its media file is missing, so it
  is kept as placed" (under `center` it is centred as any media picture); a still or image
  picture takes `center` and is not followed, "it is a still picture, so it is centered"; a
  nest takes `center`, "it is a nest, so it is centered" (amended by #526); an other clip takes `keep` and is
  kept. Only the op's answer decides an entry. **Applied:** a following kind or `center` on a
  media picture is **whole** only when the op added a "Blurred Background" clip to the trial
  (any track) AND `FollowSubject.framing` (k = s′/s, dx = x′ − k·x, dy = y′ − k·y from both
  handles' `clip_state`) agrees within 1e-6 at every sample time — the clip's start, its last
  tick, and each action's start and end in the new clip; otherwise **followed**, its reason "it
  is shown whole on a blurred copy where no subject is found" when a backdrop was added, then
  the clip's own motion ("moves by its own motion: <name>", the first active slot that is
  neither a fade nor a spin, during then in then out), joined by " and "; a clip centred by
  `where_empty: center` with no subject stays followed with no reason. **Identity:** treated
  as applied with no op. **Refused:** retried as `keep` and not followed, its reason the core's
  sentence; a refused `keep` stops the step: "Make Vertical was refused at reframe_clip for
  clip C: <reason>". Swift restates none of VR-26's refusals: a matte, rotated or spinning clip
  reaches `keep` through the core's sentence. The counts sum `FollowSubject.counts(…, replace:
  false)` over the entries whose applied op was not `keep`; a kept or not-followed entry counts
  0 (`keep`'s per-axis rescale is no framing). `more_tracks` is VR-29's sum.
  (4) Classes 1 and 2 in clip-id order: a backdrop whose partner was applied with a non-`keep`
  follow is deleted (`delete`, **removed**); any other backdrop, and every image plate, gets
  `set_video {x: 0, y: 0, scale: new fill}` (**refilled**); a shape plate gets `set_shape
  {width: W′, height: H′}` (**refilled**). A refusal answers "Make Vertical was refused at <op>
  for clip C: <reason>".
  (5) `remove_track` of Backgrounds when no clip is on it.
  (6) VR4's captions and graphics, owed to VR4.
  **Counts under compose** (VR-27 (f), `counts`' compose branch): an action in both handles
  with the same span is carried when F differs by more than 1e-6 between its two ends;
  re-eased is unchanged, and the replace branch Follow Subject reads is unchanged.
- **VR-35 — The summary** (`VerticalVersion.summary`): "Makes a W × H version." then, each only
  when non-zero, " Follows N clip[s]." " Shows N clip[s] whole on a blurred copy." " Keeps N
  clip[s] as placed." " Re-fills N background[s]." " Removes N blurred cop[y|ies] the framing
  replaces." then VR-29's sentences for Backgrounds, more tracks, re-eased and carried; then
  one line per entry with a reason: "Clip C is not followed: <reason>." or "Clip C is
  followed, but <reason>."
- **VR-36 — `make_vertical_version {shape, follow?, zoom?, where_empty?, copy?, path?}`**
  (`AgentServer+VerticalVersion.swift`, its row in `AgentCatalog+Framing.swift`; off main,
  never asking the person, reading no `UserDefaults`). `shape` is required (`9:16`, `4:5`,
  `1:1`); `follow` subject, face, person, salient or center (default subject; anything else
  "follow must be subject, face, person, salient or center, not <v>."); `zoom` default 1;
  `where_empty` fit or center (default fit); `copy` default true; `path` read only with
  `copy`. `captions` is VR4's. The first main hop refuses in this order: the target and each
  argument; an open nest ("make_vertical_version works on the top-level timeline: set_scope
  with no nest first."); `path` with `copy: false` ("make_vertical_version writes path only for
  a copy: drop path, or copy."); the path as `new_project_from_range` refuses it; a size equal
  to the canvas; `opening`'s refusal. It then runs a **dry plan** with no subjects, so a core
  error for a bad argument (`zoom` outside 1…4) is thrown at once, before any analysis is
  asked for. The answer: `ok`, `canvas {width, height}`, `cached`, `clips [{clip, treatment,
  reason?}]` in clip-id order (`followed`, `whole`, `kept`, `refilled`, `removed`,
  `not_followed`), `backgrounds`, `more_tracks`, `re_eased`, `moves_carried`, `summary`,
  `project`, and for a copy `carried {files, bytes, seconds}`, with `path` `saved` (the copy
  saved through `save_project`'s `save(_:to:operation:)`). It is ask-first for the assistant
  only when it names `path` (amends **AI-7** by one row, `askOnlyWith: "path"`, CJ-52's
  shape).
- **VR-37 — Analysis comes before the copy, in the source's cache.** For a following kind the
  requests are `FramingAnalysis.requests` over the media pictures whose media is present, on
  the SOURCE (so an offline media never throws `missingFile`); the wait is `reframe_clip`'s,
  lifted into `waitForAnalysis` with CJ-25's bound, and past it the answer is `analyzing`
  ("Still analyzing the media of N clip[s] (P %); call make_vertical_version again to make the
  version.") with nothing made. The subjects are read off main from the source's cache, so the
  copy carries copies of the analysis files and a later run on the source reuses them. The
  last hop refuses a changed project or scope ("the project changed while
  make_vertical_version read the analysis, so nothing was made. Call make_vertical_version
  again."). **Owed to VR3b:** the Analyzing sheet's Stop, which makes nothing.
  **Choices left to the code:** a picture's first-frame test reads `clip_state` at its start
  for scale, x and y; the dry plan's answer is discarded.

## CO8 — layout and cutout at record time (2026-11-03)

Recorded before the code. With "Record the camera too" ticked, the recorder panel chooses the
camera's layout (Corner, Rounded Corner, Circle, Side by Side, Camera Full) and whether the
camera's background is removed when it lands; `record_screen` takes `camera_layout` and
`camera_cutout`, and the dev tool `land_recording` lands a fixture camera with both. The owner's
answer (2026-11-01): the panel's default layout is Corner, today's landing. No core, FFI, header,
op, format or tool-count change (43 stands; 124 product tools); the cutout runs on-device, so
nothing is keyed (CJ-3).

- **CO-80 — The recorder offers a layout** (amends CAM-10 (3)).
  - (a) **One `switch_layout` per camera clip.** Right after segment k's camera clip is placed,
    the landing applies ONE `switch_layout {camera: the clip, screen: segment k's screen clip,
    layout, shape, corner: bottom_right, at: the clip's start, duration: one frame of the
    container's canvas, through}`. `through` is max(segment k's screen clip's end, the camera
    clip's end), per segment and never the whole recording's end, so the reach re-bases only a
    later screen clip this camera overruns into: never a later segment's own screen, nor a clip
    placed before the recording. The op is built by `ReelOp.switchLayout` unscoped, applied to
    the trial scoped as the commit is, and read back; a refusal throws "Clip N could not be laid
    out: <the core's sentence>". It sends no `curve`, `focus` or `nest`: no masks exist at
    landing, so the crop centres on the source (CO-70 needs them).
  - (b) **The one-frame switch.** The one-frame `duration` makes both roles cut at `at`. The
    camera is always cut at its clip time 0: its base and a one-frame layout action there. A
    screen whose clip time at `at` is 0 gets the same; a screen whose clip time is t > 0 (a
    positive `camera_offset`, or the floor after an overrunning camera) keeps its base and gets
    one one-frame layout action at t, so it stays full until the camera arrives. `corner_square`
    reproduces CAM-10 (3)'s geometry to the pixel (`layout.rs`'s corner is the same arithmetic).
  - (c) **The fallback.** When segment k's screen minted no clip, or its screen clip does not
    play at the camera clip's start (`screen.start ≤ at < screen end` fails), the camera takes
    CAM-10 (3)'s `cornerPatch` `set_video {x, y, scale}` whatever the layout, and the landing
    never throws for that reason: without it the core would pick another clip as the screen,
    or refuse.
  - (d) **A recorded limit.** An Auto Zoom visit that starts in a screen clip's first frame, or
    at a screen's mid-clip layout action, meets that one-frame action and is dropped and counted
    (CU-75).
- **CO-81 — The cutout follows the landing as its own undo step "Remove Background"**
  (AU-68's pattern, with no wait). `RecordingCutout.cameraClips` is every clip of the open
  container whose media path is one of the segments' camera paths, that `CutoutStatus.canCutOut`
  and has `video.cutout == nil`, in id order; `ops` is one base `set_video {cutout:
  CutoutProps()}` per clip; `apply` commits them through `performGroupedEdit` right after the
  landing — both branches of the panel and the tool door — before Enhance Voice and the polish
  (CU-101 (a)), so the order is the landing, Remove Background, Enhance Voice, then the polish.
  It is never inside the landing's step. With no camera clip the panel is quiet and the tool
  answers `camera_cutout_error` = "No camera clip landed on the timeline, so Remove Background
  did not run."; otherwise the answer gains `camera_cutout: {clips: [id…]}`. Not key-gated: it
  runs on-device (CJ-3).
- **CO-82 — The panel's rows and keys** (amends CAM-11). Two rows after the camera's preview
  and before Microphone: "Layout:" with a pop-up of the five (`RecordingCameraLayout`, each
  item's `representedObject` its raw value, read from `selectedItem`), and under it, unlabelled,
  "Remove the camera's background when it lands". Both are live only while idle with
  `cameraBesideSelected`; otherwise greyed with their values kept. `applyCameraLanding`: the
  layout is the pop-up's with `cameraBesideSelected`, else `.cornerSquare`; the cutout is the
  box's value and `cameraBesideSelected`. The keys `FrameJobRecordingCameraLayout` (a String;
  absent or stale reads `corner_square`, the owner's Corner) and `FrameJobRecordingCameraCutout`
  (a Bool, absence tested by `object(forKey:) == nil`, reads off) are the panel's seventeenth and
  eighteenth, written on every change and restored on show, and pinned at those values in the
  harness and `screens.py`.
- **CO-83 — The tools' arguments** (amends CAM-4 (2), (3) and CAM-10 (5)).
  - (a) **`recordingCameraStrangers`.** With source voice_over, the given ones of `camera,
    camera_format, camera_layout, camera_cutout` in its one sentence; with source screen and no
    `camera`, the first given one of `camera_format, camera_layout, camera_cutout`, as "With
    source screen, <arg> needs camera — name the camera to record beside the screen."; with
    source camera, both new arguments join `cameraRefusedArguments`, before `rate`.
  - (b) **`recordingCameraLanding`** runs after `recordingPolish` and before any grant: the enum
    first (`enumArg` refuses an unknown value with the vocabulary), then with `place: false`
    "camera_layout lays out the landed camera clips, so it needs place: true." when the layout
    is given and "camera_cutout: true removes the landed camera clips' background, so it needs
    place: true." when the cutout is true. The tool's defaults are `corner_square` and false,
    because a tool reads no `UserDefaults`.
  - (c) **`land_recording`** takes `camera` (a path, only with `movie`: "camera cannot be given
    without movie — a camera lands beside the screen segment's movie."), and `camera_offset`
    (integer ticks, default 0), `camera_layout` and `camera_cutout`, each only with `camera`:
    "<arg> cannot be given without camera — it applies to the camera's clips.". The fixture
    camera is probed as the others are, the segment built with `cameraDescriptor` and
    `cameraOffset`, `choice.camera` the fixed id "land_recording", and the place checks are
    `recordingCameraLanding`'s. Its panel door builds its own choice, so the two panel keys
    never reach it (CU-102 (c)'s rule).
- **CO-84 — CO8's proof.** `co8_proof.py` (MCP, both doors of `land_recording`, ffmpeg fixtures
  under `tools/proof/work/co8/`): R1 the default landing (the camera at CAM-10 (3)'s arithmetic,
  the screen an `add_clip` twin's, one one-frame layout action at clip time 0 each); R1b a +2
  frame `camera_offset`; R2 the five layouts against a twin given `switch_layout` by hand; R3
  the cutout as a second step "Remove Background" on the camera clips only; R4 every CO-83
  sentence through `record_screen` and `land_recording`, the project unchanged; R6 a clip placed
  before the recording left byte-identical; R7 `fit_new_clips` off; Z0 the parity log clean;
  app mutants `cutout-in-landing` (R3), `default-rounded` (R1), `no-frame-duration` (R1b).
  `co8_probe.py` (built through `swift_build.build()`): Q1 the rows, Q2 the keys, Q3 the gates
  and `currentChoice`, Q4 the refusals, Q5 a write run then a read run, Q6 two segments with the
  second camera absent, Q7 a +3 frame offset and an overrun screen's fallback; probe mutants
  `gate-ignored` (Q3), `cutout-without-camera` (Q4), `through-whole-recording` (Q6),
  `throw-on-unplayed-screen` (Q7) and `no-through` (Q6). No JOB row: the landing is measured.
