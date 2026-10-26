# Spec §11 — decisions: Camera recording (road map "camera-recording")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map is `designs/camera-recording.md`; its parent design is road map 3
(`designs/adr/roadmap-03-screen-recording.md`), whose decisions in [`recording.md`](recording.md)
stand unless an entry here amends one. CAM-1 and CAM-2 were recorded in CR0, before any product
code and before the spike's measured run. A later phase records its rule here (CAM-3 on), before
its code.

- **CAM-1 — Camera recording is IN; callouts stay OUT** (the owner, 2026-10-26, reversing the
  camera half of recording.md's first bullet and §1's non-goal). Frame Job records a camera on
  its own, or at the same time as a screen recording (a talking head over a screencast). The
  owner's four answers, as given:
  1. **Camera alone, or camera at the same time as a screen recording.** Each capture lands as
     its own file on its own track. With a screen recording the camera goes on a track ABOVE
     the screen, placed as a corner picture-in-picture that can be moved; the corner, the scale
     and the inset are CR3's to decide.
  2. **The entry is the existing recorder panel**: a Camera source, and a camera row when
     recording the screen. One panel, one countdown, one menu-bar status item with Pause and
     Stop, the same landing into the project. File ▸ New Recording… (⌥⌘N) stays the one door.
  3. **Devices**: built-in and USB/UVC cameras and iPhone Continuity Camera; a live preview of
     the chosen camera in the panel; a choice of resolution and frame rate from the camera's
     formats, otherwise its best format.
  4. **Audio**: the chosen microphone (which can be the camera's own) is its own audio file on
     its own track, lined up to the picture, as screen recording does today.

  Everything else recording.md decided carries over: a recording is ordinary media, the files
  live in `~/Movies/Frame Job Recordings/`, the panel asks for the grants and the tool never
  does, the microphone is a second file, a pause is a sequence of files, one grouped edit lands
  everything, and every door has an MCP mirror (a new source is an argument of `record_screen`,
  the voice-over's precedent, unless a phase records otherwise). Callouts stay out for the
  reason recording.md gives: a metadata format plus an Input Monitoring grant. **Risk
  accepted:** a second capture stack (`AVCaptureSession` for a camera) beside ScreenCaptureKit,
  a Camera grant and its entitlement, and a camera's own clock to line up with the screen's and
  the microphone's; CR0 measures each before any of it is built.

- **CAM-2 — The camera spike's rule (CR0), fixed before its run.** `tools/proof/camera_spike/`
  measures camera capture alone and beside a running screen recording; `results.json` stores
  this file's SHA-256 as `rule_sha256`, so the rule a recorded run read is pinned. The VERDICT
  line reads `VERDICT writer=<movie-output|asset-writer|STOP> screen_start=<E1|E2|STOP>
  continuity_key=<needed|not-needed|unmeasured> camera_entitlement=<needed|not-needed|unmeasured>
  best_format=<per-device summary>`, or `VERDICT NOT MEASURED: <reason>` when every `write` row
  is skipped.
  - **Writer.** `AVCaptureMovieFileOutput` is chosen unless, on the chosen camera at D3's
    format, any run shows one of: (a) frames written < 98 % of span × rate while W3's
    (`AVAssetWriter` fed by an `AVCaptureVideoDataOutput` on W2's whole device configuration)
    are ≥ 98 %; (b) no `startPTS` callback, or no conversion of it to the host clock; (c)
    neither HEVC nor H.264 is writable at that format; (d) P1's median resume start latency
    exceeds P2's by more than one frame interval. Any of these picks `AVAssetWriter`. If
    neither path reaches 98 %, the verdict is STOP.
  - **Screen start.** The truth is the display link's `targetTimestamp` (the presentation host
    time, not the draw time) logged for the counter code read in the screen file's first frame.
    The estimators are E1, the arrival host time of `recordingOutputDidStartRecording`, and E2,
    the PTS of the first `.screen` frame at or after E1. The first of E1, E2 whose |error|
    against that truth is ≤ 16.7 ms in every S run is chosen; if neither passes, the verdict is
    STOP.
  - **Black frame.** A frame whose mean luma (8-bit, 0–255) is < 24.
  - **Continuity key.** `unmeasured` when D1 marks no device `isContinuityCamera`. Otherwise
    `needed` iff D2 without `.continuityCamera` and without the key
    `NSCameraUseContinuityCameraDeviceType` lists no device (matched by `uniqueID`) that D1
    marks `isContinuityCamera`, else `not-needed`.
  - **Camera entitlement.** `unmeasured` when T3 (the hardened copy WITH
    `com.apple.security.device.camera`) delivers no frame or only black frames — a dark room or
    a covered lens measures nothing. Otherwise `needed` iff T2 (the hardened copy without it)
    delivers no frame or only black frames, else `not-needed`.
  - **Best format.** The largest width × height whose maximum rate is ≥ 30; ties go to the
    higher maximum rate, then to the format listed first.

  A skipped row (no grant, no camera, no person) is never a failure; the probe never asks for a
  grant but under `--ask`, which asks for Camera and Microphone only, never Screen Recording.
  **Risk accepted:** a bare binary's grant is its responsible process's (road map 3 R0 q1), so
  T2 and T3 measure the hardened runtime under the terminal's grant, not a signed bundle's own
  prompt; that prompt is a person's check in CR1.

- **CAM-3 — The camera recorder's rules (CR1a), recorded before its code; amends CAM-2's Best
  format.** CR0's verdict chose `AVAssetWriter` (CAM-2 Writer) and E1; these are the rules CR1a's
  recorder and CR1b's tool build on.
  - **Best format.** CAM-2's rule (the largest width × height whose maximum rate is ≥ 30, ties
    to the higher maximum rate, then to the format listed first) is applied to the formats
    WIDER THAN TALL. If none qualifies, CAM-2's rule over every format; if that finds none
    either, the device's active format. The recording is made at the chosen format's maximum
    rate. On CR0's host it picks the FaceTime HD Camera's 1760 × 1328 @ 30 (format 3), OBS
    Virtual Camera's 1920 × 1080 @ 60 and the iPhone's 1920 × 1440 @ 60 (over its 1920 × 1440 @
    30 on rate). A person picks 1920 × 1080 in CR2's Format popup.
  - **Step 2's criterion.** Before the recorder is relied on, the spike's writer row W3 runs at
    the format this rule picks (the spike's `--format`): every W3 run writes ≥ 98 % of span ×
    rate with the format read back as asked, and P2's median resume start latency is ≤ one
    frame interval. A failure is a STOP for the owner, with no product code.
  - **The microphone's offset.** The camera's first appended buffer's PTS and the microphone
    file output's `startPTS`, each converted to the host clock through its own session's
    `synchronizationClock`; the offset is the camera's minus the microphone's. If either is
    missing, the two arrival stamps (the first buffer's and the did-start's) are used instead;
    if those are missing too, 0. POSITIVE means the picture began after the microphone, the
    sign `RecordingSegment.micOffset` already has. The truth is a person's (CR1b's clap row).
  - **The camera entitlement is ADDED.** `com.apple.security.device.camera` joins the app's
    entitlements and `NSCameraUsageDescription` its Info.plist. CAM-2's `not-needed` speaks
    only for a shell-launched binary under the terminal's grant; road map 3 R0 found the signed
    app needed the microphone's entitlement where a bare probe did not, and the camera follows
    that finding. The dist checks' exact sets (D14, D25, P5) gain it.
  - **Files.** `Camera Recording <yyyy-MM-dd> at <HH.mm.ss>.mov`, and the microphone's
    ` (Microphone).m4a` beside it (`RecordingFiles.microphoneURL(beside:)`). HEVC where the
    writer `canApply` it at the format's size, else H.264. Each later segment is named by its
    own start and is unique against the names the session holds (the voice-over's rule). A
    segment that wrote no frame is cancelled and dropped; if none wrote a frame, the recording
    fails: "The camera delivered no frame."
  - **The warm-up** (added when CR1a's granted probe found it). A cold camera's first frames
    come slower than its format's rate: the built-in camera at 1760 × 1328 @ 30 delivered its
    first intervals at 33.3, 33.3, then five at 43.3 ms, then 33.3 ms steadily, which left
    segment 0 at 0.975 of span × rate in every run, while a resumed segment, on a warm session,
    was 0.999. So a camera recording begins on a warm stream, as a screen recording's
    microphone does (`prepareMicrophone`, warmed during the countdown): `.arming` holds until
    the stream runs at the format's rate — FIVE consecutive frame intervals, by PTS, each
    within 15 % of the format's frame duration (the cold intervals are 30 % long, the spike's
    steady W3 never passed 35.0 ms, 5 %, and five rather than three because the cold start
    opens with two on-time intervals) — bounded at 1 s from the session's start. Segment 0's
    writer is armed only then, so it starts at a steady buffer. Past the bound the recording
    starts anyway and the result's `camera.note` names the rate measured; the hold never fails
    a start. A start pays the hold once, up to the bound; a resume, on the running session,
    does not. Until CR1c's countdown exists the hold is paid inside the recorder's start; CR1c
    starts the camera's session during the countdown, so the hold is spent there.
  - **A camera that stops on its own** — a runtime error, an interruption or a disconnect,
    while recording or paused — ends the recording: `stoppedBy` is `.systemStopped`, the
    sentence is the result's `camera.problem`, and what was written lands.
  - **A microphone that stops on its own** (a did-finish that arrived before its segment's
    stop, the voice-over's arrival test) does NOT end a camera recording: the screen
    recording's rule. The picture keeps recording, that segment's `micProblem` carries the
    sentence, and the recorder's `microphoneProblem` is set once for the session. A later
    segment's microphone is started again at resume, and a start that fails is that segment's
    `micProblem`.
  - **The tool's refusal order** (CR1b builds it): (1) `seconds`; (2) `source`; (3) the
    arguments the source refuses — with `camera`, `display`, `window`, `system_audio`,
    `show_clicks`, `size`, `include_framejob_windows` and `rate`, refused together; with any
    other source, `camera`; (4) the screen's own checks; (5) `microphone: true` without its
    grant; (6) `project`; (7) the camera lookup, which needs no grant and so comes before the
    grant read: the system's preferred camera, else the first built-in, else the first, when
    `camera` is absent; "No camera is connected." when none is; a sentence naming every camera
    present when the name or id is unknown; (8) the Camera grant; (9) the recording.
  - **Canvas.** A new project's canvas is the file's size at the format's maximum rate,
    rounded (at least 1). In an open project the camera lands by the screen recording's picture
    rule (`RecordingLanding.placement`, unchanged).
  - **The rule's hash.** This entry changes the file's SHA-256, so step 2's run records a new
    `rule_sha256`; CR0's pinned hash stays CR0's.

- **CAM-4 — `record_screen`'s camera (CR1b), recorded before its code.** The tool's own choices
  CAM-3 left open; CAM-3's refusal order stands, and this entry fills in its steps (3) and (7).
  1. **`camera`** is a string matched by `CameraDevices.match`: a device's `uniqueID` exactly,
     else its name case-insensitively. It is trimmed; a blank string or a JSON null counts as
     absent, and absent takes CAM-3 (7)'s default (the system's preferred camera, else the
     first built-in, else the first).
  2. **`camera` with another source.** With source `screen` or `voice_over`, a given `camera`
     is refused right after `source`'s value and before the voice-over's own checks: "With
     source <screen|voice_over>, camera cannot be given — only source camera records a
     camera." CR3 lifts this for `screen`.
  3. **The arguments a camera refuses.** With source `camera`, the given ones of `display`,
     `window`, `system_audio`, `show_clicks`, `size`, `include_framejob_windows` and `rate`
     are refused together, in that order: "With source camera, <a, b> cannot be given — a
     camera recording records the camera alone, at the camera's own format."
  4. **The microphone.** `microphone: true` records the DEFAULT microphone, as with the screen
     source. Choosing a microphone is the panel's (CR1c).
  5. **The span** counts from segment 0's first buffer (the recorder's `heldFirstStartedAt`,
     the voice-over's wait), so `seconds` is the picture recorded and the warm-up is not in it.
  6. **The answer** carries `camera: {name, id, format, problem?, note?}` exactly when the
     result has a camera. `id` is the chosen device's `uniqueID`, `format` the format recorded
     at as `CameraDevices.spelled` writes it, and `problem` and `note` appear only when set;
     each is also appended verbatim to `note`, after the microphone's clause. `stopped_by:
     system_stopped` also means a camera that stopped on its own. `has_audio` is false: the
     movie holds no audio.
  7. **The chrome.** The menu-bar status item goes up as for every source.
