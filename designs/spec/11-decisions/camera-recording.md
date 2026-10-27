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

- **CAM-5 — The panel's Camera source (CR1c), recorded before its code.** The recorder panel
  records a camera; CAM-3's recorder and CAM-4's tool stand.
  1. **The Source row "Camera"** has tag 3 and sits between "Window…" (1) and "Microphone Only"
     (2). It is session-only, as Microphone Only is: the display key is left alone while it is
     chosen, and `rebuildSources` reselects it.
  2. **The Camera popup** (`Camera:`, under Include Frame Job windows) lists
     `CameraDevices.connected()` by name, each row carrying its `uniqueID`; with none connected,
     one row "None connected" with no id. Its selection is the stored `FrameJobRecordingCamera`
     when that camera is connected, else CAM-3 (7)'s default (the system's preferred camera,
     else the first built-in, else the first). It is written on change, rebuilt on `show()`
     while idle, and enabled only while idle with Source Camera. Hot-plug while the panel is up
     is CR2's.
  3. **With Source Camera**, System Audio, Show Clicks, Size, Include Frame Job windows and Rate
     grey out, keeping their values; Microphone and Record Into stay live, and the size note
     names the camera's best format ("1760×1328 at 30 fps — the camera's best format"). The
     choice is `.camera` with `camera` the popup's id; every other source keeps `camera` nil.
  4. **The press** never reads or asks for Screen Recording. In order: no camera →
     "No camera is connected."; the Camera grant — authorized goes on, `notDetermined` asks
     (`AVCaptureDevice.requestAccess(for: .video)`), denied or restricted opens System Settings
     at `Privacy_Camera` and the note says so (the refusal sentence if the pane did not open);
     the Microphone grant, as for every source (Off is allowed); the countdown. A camera
     prompt's answer re-enables Record and continues the press only in an idle, visible panel
     (the microphone prompt's rule), and it re-reads the Camera grant: anything but authorized
     stops there with the refusal sentence — no Microphone prompt, no countdown; authorized
     checks the microphone and starts the countdown.
  5. **The warm-up is spent in the countdown.** The countdown's start builds and starts the
     camera's capture (`ScreenRecorder.prepareCamera`), so CAM-3's warm-up runs through the
     3-2-1. `startCamera` adopts it when it is the same device at the same format, not adopted
     before, with no failed start and no stop on its own; otherwise it lets it go and builds a
     fresh one. A start that comes before the prepared warm-up has answered JOINS it rather
     than starting it again. Cancel, close, an abandoned start and a failed start let it go.
     The tool never prepares, so its start still pays the hold (CAM-3).
  6. **The panel stays UP while a camera records** (the voice-over's precedent: nothing on
     screen is filmed): the rows lock, the meter stays live, the footnote shows ● or ❚❚ and the
     time, and Record reads Stop with Pause / Resume beside it. Close leaves the recording
     running; the quit guard and the welcome button show the panel again. Camera + screen is
     CR3's.
  7. **The meter** reads the camera recording's latest segment's microphone output while
     recording, until that segment's microphone finishes or reports a problem.
  8. **The landing note**, for a result with a camera: `.systemStopped`'s sentence is the
     camera's `problem` (else "The camera stopped on its own.") followed by " What was captured
     was added.", in place of the display's sentence; the warm-up's `camera.note` follows the
     microphone's problem; a landing that fails carries both.

- **CAM-6 — The camera's formats (CR2a), recorded before its code; amends CAM-4 (2)'s sentence
  and CAM-5 (3)'s size note.** The panel's Format popup and `record_screen`'s `camera_format`
  choose one of the chosen camera's formats; Best, CAM-3's pick, is the default of both. CAM-3,
  CAM-4 and CAM-5 stand except where this entry amends them.
  1. **The rows.** "Best (W×H at R fps)" comes first, or "Best" when the camera has no best
     format. Then one row per distinct (width, height, maximum rate) with a maximum rate above 0,
     the first listed kept. The rows are grouped wider than tall, then square, then taller than
     wide; within a group by area, largest first, then by maximum rate, highest first, then in
     the device's own order. Each row is titled "W×H at R fps" (the rate written `%g`) and
     carries the format as `CameraDevices.spelled` writes it (`1920x1080@30`). A format's lower
     rates are NOT rows, because a recording is made at the format's maximum rate (CAM-3); a
     camera that lists a rate as a format of its own (the iPhone's 30 and 60) shows both.
  2. **Persistence and the live rule.** `FrameJobRecordingCameraFormat` is one key for every
     camera: the spelled row, or `""` for Best. It is written with the camera key, and only
     while the Camera popup names a camera. The popup selects the stored row when the chosen
     camera lists it, else Best — at init, on `show()` while idle, and on a change of camera.
     It is live only while idle with Source Camera, the Camera popup's rule (CAM-5 (2)).
  3. **The choice.** With Source Camera, `RecordingChoice.cameraFormat` is the selected row's
     spelling, nil for Best. The format recorded is the first listed format whose spelling
     equals it, else (nil, or a spelling the camera no longer lists) CAM-3's best format.
     `prepareCamera` and `startCamera` both resolve it so, and CAM-5 (5)'s adopt rule compares
     the resolved format, unchanged.
  4. **The size note.** For Best it reads CAM-5's sentence ("1760×1328 at 30 fps — the camera's
     best format"); for a chosen row, "W×H at R fps — the chosen format"; with no camera, "no
     camera connected", as before.
  5. **Continuity Camera.** A device the system marks `isContinuityCamera` is titled
     "<name> (Continuity Camera)" in the Camera popup. `CameraDevices.match` still compares the
     name and the `uniqueID`, and the default rule is unchanged.
  6. **The tool's `camera_format`.** A string, trimmed; blank or null counts as absent, and
     absent means Best. `best` in any case means Best. Otherwise the spelling is matched
     exactly in any case (`1920x1080@30`), else as `WIDTHxHEIGHT` in any case, which takes that
     size's first row — its highest rate. With source `screen` or `voice_over`, a given `camera`
     or `camera_format` is refused in CAM-4 (2)'s step: "With source <kind>, <the given ones,
     joined ", "> cannot be given — only source camera records a camera." With `camera` alone
     the sentence is CAM-4's, byte for byte, and a `camera_format` that is not a string gets
     `stringArg`'s refusal in the same step. With source `camera` the format is checked in
     CAM-3's step (7), AFTER the camera lookup and BEFORE the Camera grant (8): "The camera
     <name> has no format <wanted>. Its formats are best, <the rows spelled, joined ", ">."
     The answer's `camera.format` and the canvas rule are unchanged: the format recorded,
     spelled.

- **CAM-7 — The camera's preview and #373 (CR2b), recorded before its code; amends CAM-5 (2)'s
  hot-plug clause and CAM-5 (5)'s "the countdown's start builds".** With Source Camera the
  recorder panel shows a live preview of the chosen camera, on the capture CAM-5 (5) prepares.
  CAM-3, CAM-5 and CAM-6 stand except where this entry amends them; CAM-5 (5)'s "The tool never
  prepares, so its start still pays the hold" stands (7). CAM-5 (2)'s "Hot-plug while the panel
  is up is CR2's" is now CR2c's.
  1. **The well.** A grid row with no label, holding a 200 × 150 pt well, sits right under
     Format. The well is `DS.canvasVoid` with a 1 pt `DS.border`, and the picture is aspect-fit
     (`.resizeAspect`). It is NOT mirrored (`automaticallyAdjustsVideoMirroring` false,
     `isVideoMirrored` false): what is seen is what lands. The row is shown only with Source
     Camera; with any other source the panel is as it was.
  2. **Its layer** is an `AVCaptureVideoPreviewLayer` made with the PREPARED capture
     (`CameraCapture(…, preview: true)`, on that capture's session), so hosting it is a sublayer
     swap and never reconfigures a running session. Only `prepareCamera` asks for a layer: a
     fresh capture built by `startCamera`, and every capture of the tool, has none.
  3. **The step**, first match wins: (1) the panel not visible (`isVisible` false, or closing)
     or Source not Camera → off; (2) the recorder holds a camera recording → recording; (3) the
     phase is the countdown or starting → prepared; (4) any other phase but idle, or the
     recorder not idle → blank; (5) no camera chosen → "No camera is connected."; (6) the
     Camera grant not authorized → "The preview shows once Frame Job may use the camera.";
     (7) the prepared capture for the chosen camera and format stopped on its own, failed to
     start, or failed to be built (8) → that sentence; (8) → prepare. The grant is read only at
     step 6 and the failure only at step 7. Showing the panel never prompts.
  4. **What each step does.** Off and the two sentences let the prepared capture go when the
     panel's phase and the recorder are both idle, and leave the well blank or showing the
     sentence. A failure stops the prepared capture but keeps its record, so the step is not
     retried, and shows its sentence. Prepare calls `prepareCamera` and shows its layer.
     Prepared shows the prepared capture's layer if there is one and never builds. Recording
     shows the recording's capture's layer, else "The camera is recording." Blank is blank.
     The row's visibility follows Source Camera on every step, and a change refits the panel.
  5. **When it steps**: at the end of `show()`, which first lets a failed prepared capture (or
     a failed build's record) go while idle, so showing the panel again retries; at the end of
     every control change; whenever the phase is drawn; and at the one-second tick while the
     panel is visible. Closing the panel marks it closing before anything else, so the
     countdown's cancel and a starting stop never build; it lets the prepared capture go and
     empties the well. Cancel, an abandoned start and a failed start still let the capture go
     (CAM-5 (5)); the idle step that follows prepares a fresh one, so the camera's light stays
     on while the panel shows Camera.
  6. **#373 fixed.** Every capture runs its device's configuration lock, its format,
     `startRunning` and the format again (`start`), and `stopRunning` then the unlock
     (`stop`), on ONE serial queue all captures share; the lock moves there from `init`, and a
     lock the device refuses is the start's error, in the sentence `init` gave it ("The camera
     <name> could not be configured: …"). So a capture built in the same main turn as another
     capture of its device is let go starts only after that stop, and lock and unlock pairs
     never interleave. `CameraCapture.stop(completion:)` answers on main once its stop has run
     on the queue, also when the capture was stopped before.
  7. **A tool start never adopts.** `startCamera` adopts the prepared capture only for the
     panel's own start (`mayAsk` true). A tool's start lets the prepared capture go and builds
     its own, with no layer, paying CAM-3's hold; the panel's well reads "The camera is
     recording." until that recording ends, and its idle step then prepares again.
  8. **A thrown prepare is remembered.** When `prepareCamera`'s capture cannot be built, the
     recorder records the camera, the format and the sentence; `prepareCamera` does not build
     again while that record matches the camera and format, and the well shows the sentence.
     Letting the prepared capture go (`discardPreparedCamera`) clears the record: leaving Source
     Camera, showing the panel again, or Cancel retries once.

- **CAM-8 — Hot-plug (CR2c), recorded before its code; amends CAM-5 (2)'s "Hot-plug while the
  panel is up", which CAM-7 made CR2c's.** While the recorder panel is up, a camera or a
  microphone plugged in or taken away rebuilds the Camera and Microphone popups, and the Format
  popup when the camera changes, and the preview follows. CAM-3, CAM-5, CAM-6 and CAM-7 stand
  except where this entry amends them.
  1. **The observers.** `AVCaptureDevice.wasConnectedNotification` and
     `.wasDisconnectedNotification`, for any device, delivered on main. `show()` adds them, one
     pair at most, and adding the pair marks the lists pending, so a change made while the
     panel was closed is caught up. Closing the panel removes them; a panel ordered out for a
     recording keeps them.
  2. **Pending until idle.** A notification marks the lists pending and steps the preview
     (CAM-7 (5)). The step's first act applies a pending change, and only when the panel's
     phase is idle and the recorder is idle; otherwise the change waits for the first step that
     finds both idle. The return to idle draws the phase, which steps.
  3. **The rebuild.** The Camera popup's rows (id, title) are compared with what
     `CameraDevices.connected()` gives now — each camera's `popupTitle`, or the one row "None
     connected" — and the Microphone popup's rows (id, title) with "Off" and then the connected
     microphones by (`uniqueID`, `localizedName`). Only a popup that differs is rebuilt. The
     selection, with the id held BEFORE the rebuild as `current`, is the stored id when it is
     listed, else `current` when it is listed, else the default — CAM-3 (7)'s camera, or Off
     for the microphone; a stored `""` counts as none. The camera is selected again (which
     rebuilds the Format popup, CAM-6 (2): the stored format when the camera lists it, else
     Best) only when the Camera popup was rebuilt or the selection's id differs from the one
     selected, so no menu is rebuilt for an unrelated device. The size note is refreshed.
  4. **No key is written.** A hot-plug writes no defaults key, so a camera that goes and comes
     back is selected again with its stored format; the next control change writes what the
     popups then show (CAM-5 (2)).
  5. **Connected only.** The Camera list — which the tool's lookup, the default, the format
     and the recorder's start share — and the Microphone list keep only devices whose
     `isConnected` is true, in the discovery session's own order.
  6. **The preview.** It steps in (2), so a new selection prepares under CAM-7. A prepared
     capture of a camera that went away is CAM-7 (3)'s failure until the rebuild moves the
     selection, and the failure's step stops that capture once, not at every tick.
  7. **During a recording.** A camera taken away during a recording ends it (CAM-3,
     unchanged); its list change applies at idle.

- **CAM-9 — A camera beside the screen (CR3a), recorded before its code.** `ScreenRecorder.start`
  with a display, window or picked source and `choice.camera` set also records the camera: one
  `(Camera).mov` per segment beside the screen's movie, paused and resumed with it, each placed
  against the screen by E2 (CAM-2's second estimator). The result carries the camera's files and
  offsets. CAM-3's files, codec and warm-up, CAM-5 (5)'s take and CAM-7 (7)'s adopt rule stand.
  1. **The start.** The order is `.busy`, the source guards, Screen Recording, then the Camera
     grant (read, never asked). Then the camera lookup ("No camera with the id … is
     connected.", `.cameraDevice`) and its format (`chosenFormat`, CAM-6 (3)). Then the
     Microphone grant and device, the folder, the recording output, the `.screen` frame watch
     (a throw is `.startFailed`) and the microphone capture. The camera is taken LAST
     (`takeCameraCapture(…, adopting: mayAsk)`, CAM-5 (5), CAM-7 (7)); a throw there stops an
     adopted microphone session and refuses. Without a camera `start` is as before: no `.screen`
     output, the same order.
  2. **The warm-up comes before the stream.** The state is `.arming` while the capture starts or
     joins its prepared start. On its answer ONE main turn runs `launchScreen`: the microphone
     file's `startRecording` (when a microphone was chosen), then `stream.startCapture`, then
     segment 0's camera writer is armed (CR0: the order of the starts made no measurable
     difference). Without a camera `start` calls `launchScreen` in its own turn, so road map 3
     R0 q6b's order is kept. A camera that fails to start, or stops on its own while arming,
     fails the start with its `.cameraDevice` sentence. The arm ceiling covers the warm-up.
     `camera.note` is the warm-up's note.
  3. **E2.** The watch is on the stream only with a camera, built with two frame intervals at
     the recording's rate as its bound (`2 / rate` seconds: 33.3 ms at 60 fps; CR0's E2 fell
     9–22 ms after E1). It keeps the PTS (seconds, as delivered; CR0 measured them on the host
     clock) of every COMPLETE frame for 2 s. Each segment's did-start is stamped on the host
     clock where it arrives (E1). E2 is the first kept or later complete frame at or after E1
     and no more than the bound after it. A segment's question is dropped at its close (a pause,
     the finishing), so a frame of a later segment never answers it. No frame in that window, or
     none by the close, leaves E2 unset.
  4. **The offset** is the camera's first buffer's PTS (host clock) minus E2, else minus E1, in
     ticks; POSITIVE means the camera began after the screen. Without both host stamps it is the
     first buffer's arrival minus the screen's start (`screenStart(of:)`); without those, 0. A
     still screen sends no complete frame, so such a segment uses E1, as does a segment whose
     first complete frame came past the bound.
  5. **The files.** Each segment's camera is `<screen movie stem> (Camera).mov`, made unique as
     the microphone's file is, at the format (HEVC else H.264, CAM-3). A resume's candidate name
     is skipped when its camera file is held.
  6. **Pause and resume in step.** A pause closes the open segment's camera writer and drops its
     E2 question; a resume arms the next writer after its output is added. **The watch comes off
     the stream for a resume's add** (measured at CR3a, amending this rule before its code). With
     the `.screen` output left on the running stream, every resumed segment's `SCRecordingOutput`
     reported "Failed due to failure to process first sample buffer" and wrote no movie, in 4 of
     4 runs of G16; without the output both segments landed in 3 of 3. So `resume()` removes the
     watch's `.screen` output BEFORE `addRecordingOutput` and adds it back once that add has
     returned, the new output started (`addRecordingOutput` "Starts Recording if stream is
     already capturing"). Measured so in a scratch copy, both segments landed in 2 of 2 runs,
     with E2 − E1 at 12.0 and 17.3 ms, then 19.7 and 21.5 ms. The pause leaves the watch on the
     stream, as measured. A remove that throws (the watch already off) is ignored. A re-add that
     throws costs that segment's E2 alone: its camera is placed by E1, the fallback named in
     that segment's `cameraNote`; the recording never fails over it, and the next resume tries
     the re-add again.
  7. **A camera failure is never the recording's.** A camera that stops on its own while
     recording or paused sets the result's `camera.problem` (CAM-3's sentence) once: its open
     writer is closed (what it wrote lands), later segments get no camera file, and `stoppedBy`
     is the screen's. A camera writer that took no buffer leaves its segment without a camera,
     silently, its file removed (CAM-3). A writer failure, or a camera file that will not probe,
     is that segment's `cameraProblem`, naming the file when it is on disk (the microphone's
     rule), and the screen segment still lands. A left-out screen segment's camera file is kept
     and named in `keptFiles`, not landed.
  8. **The finishing** drops the open segment's E2 question and waits for every armed camera
     writer's close under `finishCeiling`. The settle stops the capture and the watch. A
     failure's sentence names each segment's camera file after its movie. A failed start closes
     segment 0's camera writer and removes its file unless the screen output had begun writing.
  9. **The result.** `RecordingResult.camera` (name, format, `problem`, `note`) is set for a
     screen recording with a camera; `isCamera` stays the source's alone. Each segment carries
     `cameraDescriptor`, `cameraOffset`, `cameraProblem` and `cameraNote` (the E1 fallback of
     (6), set only beside a descriptor).
  10. **No door yet.** CAM-4 (2) and CAM-6 (6) stand: the tool refuses `camera` with source
      screen, and the panel sets `camera` only for Source Camera. The landing ignores the camera
      fields until CR3b.
