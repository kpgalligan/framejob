# Spec §11 — decisions: Camera recording, the preview onward (road map "camera-recording")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the CAM- series of [`camera-recording.md`](camera-recording.md), so a citation
never has to say which file; that file names the condensed record and the original. This file
is new because `camera-recording.md` reached the spec's ~500-line split rule at the road map's
close (2026-10-27); the entries moved here unchanged.

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

- **CAM-10 — A camera beside the screen lands, and `record_screen` records it (CR3b), recorded
  before its code; amends CAM-4 (2), CAM-6 (6) and CAM-9 (10).** A screen recording's
  `(Camera).mov` files (CAM-9) land in the same grouped edit as its movies and microphone files,
  and the tool admits `camera` and `camera_format` with source `screen`. CAM-3 to CAM-9 stand
  except where this entry amends them.
  1. **The track.** ONE new track at the open container's FRONT (its index is the container's
     track count after the pictures have landed), named "Camera", added on the attempt of the
     first camera clip that takes a frame and kept only when that clip lands (`addMicrophones`'
     attempt pattern), so a recording none of whose camera files makes a clip adds no track.
  2. **Time.** Segment k's camera clip is asked at `screenStart_k + cameraOffset_k`, its floor
     `max(screenStart_k, the previous camera clip's end)`. A start below the floor is head-trimmed
     to it by the microphone's shared dance (`headTrimmed`: add at the floor, `trim_start`, move
     back, read back, a second try a frame up at an inexact rate). CR3a measured every
     `cameraOffset` negative, so the trim is the usual path. A camera wholly under its head
     lands as media only with "<path> was added to the media list without a clip: less than a
     frame of it would remain after the <ms> ms head that keeps it clear of <the start of its
     screen clip | the previous camera clip>." A screen picture that minted no clip still gives
     its `at`. A segment LEFT OUT because its screen movie would not probe (`UnreadableSegment`)
     keeps its camera file on disk, named in `kept_files` and its left-out sentence (CAM-9 (7)),
     and never lands it; only its microphone takes the slot (#181 item 2), so the camera's
     starts are read off the `.segment(k)` stretches alone.
  3. **The corner.** With the container's canvas `cw × ch` (inside an open nest, the nest's) and
     the camera file's `sw × sh`: `s = clamp(min(0.25·cw/sw, ch/(3·sh)), 0.01, 10)` — the box a
     quarter of the canvas wide and a third of it tall, the core's scale range —
     `x = (cw/2 − 0.05·cw − sw·s/2).rounded()` and `y = (ch/2 − 0.05·ch − sh·s/2).rounded()`, in
     the C frame (`core/src/edit_zoom.rs`: an offset of the layer's centre from the canvas
     centre, y down). So the picture sits in the BOTTOM-RIGHT corner, inside the 90 % ring of
     View ▸ Safe Areas (the guide spec §4.1 names title-safe; the industry's action-safe). One
     `set_video {x, y, scale}` per clip, right after its placement; nothing else is set, and the
     clip stays an ordinary clip a person moves.
  4. **One grouped edit**, in the order pictures → cameras → microphones. `place: false` lands
     the camera media with no clip and no track. A new project lands the cameras through
     `remainderPlacement`, after the later pictures; without clip 1, as media only with its
     `unplacedNote`. For ONE segment that undo step is "Add Camera and Microphone" with a camera
     and any voice (its own or a left-out segment's), "Add Camera" with a camera alone, and
     otherwise as before ("Add Microphone", "Add Recording Segments").
  5. **The tool.** `camera` and `camera_format` are admitted with source `screen`, lifting CAM-4
     (2) and CAM-6 (6) for it. With source screen, a `camera_format` given without `camera` is
     refused in CAM-4 (2)'s step (3): "With source screen, camera_format needs camera — name the
     camera to record beside the screen." With source voice_over the given ones of `camera`,
     `camera_format` are refused there together: "With source voice_over, <a, b> cannot be given
     — a voice-over records the microphone alone." (CAM-4 (2)'s "only source camera records a
     camera" is no longer true.) The order after step (5): (6) `project`; (7) the camera lookup
     and its format — for a screen recording too, when `camera` is given; (8) the Camera grant;
     then, for a screen, the Screen Recording grant and the display or window lookup; (9) the
     recording. The tool never prepares a capture or adopts one (CAM-7 (7)).
  6. **The answer.** Per `segments[k]` and never at the top level: `camera_path`,
     `camera_duration` and `camera_offset` when that segment has a camera file;
     `camera_problem` and `camera_note` when set; `camera_media` and `camera_clip` when known.
     The top-level `camera` is CAM-4 (6)'s, unchanged. `note` gains every segment's
     `cameraProblem` then `cameraNote`, in order, after `camera.problem` and `camera.note`.
  7. **The stop wait** counts three probes per segment with a camera beside the screen
     (`finishCeiling + 3 × probeTimeout × max(n, 1) + 5`), and its timeout sentence names the
     camera files after the movies (" Its camera file is at <c>." / " Its camera files are at
     <a>, <b>."), read from the recorder's held camera paths.
  8. **The readers.** With a camera BESIDE the screen the panel's landing note says the
     display's `.systemStopped` sentence (not the camera's) and puts `camera.problem` after the
     microphone's problem; every segment's `cameraProblem` and `cameraNote` lead the placement's
     notes, and follow `camera.note` in a failed landing's note. `filesClause` adds " and its
     camera at <p>" or " and its camera files at <a>, <b>" after the microphone clause.
  9. **No panel door yet.** The recorder panel offers no camera with a screen source until CR3c
     (CAM-11); until then the tool is the one door that records a camera beside the screen.

- **CAM-11 — The panel's camera beside the screen (CR3c), recorded before its code; amends CAM-5
  (2), CAM-6 (2), CAM-7 (1) and (3), and CAM-10 (7) and (9).** With a display or the Window row
  chosen, the recorder panel offers a "Record the camera too" checkbox; ticked, the panel records
  the chosen camera at the chosen format beside the screen (CAM-9, CAM-10). CAM-3 to CAM-10
  stand except where this entry amends them.
  1. **The box** is a grid row with no label, directly under Include Frame Job windows and above
     Camera. It is enabled only while idle with a display row or the Window row; under Camera or
     Microphone Only it is greyed with its value kept. It is a control of its own: an "Off" row
     in the Camera popup would change what the shared camera key means for Source Camera and for
     hot-plug (CAM-8).
  2. **The key.** `FrameJobRecordingCameraBeside`, a Bool, off when absent, is written by
     `persistChoices` on every change and read by `restoreChoices`. It persists across launches,
     unlike the session-only Camera row; it is the panel's tenth `FrameJobRecording…` key, pinned
     in the harness and `screens.py`. A hot-plug writes nothing (CAM-8 (4)).
  3. **A camera wanted** means Source Camera, or the box ticked with a display row or the Window
     row. Then the Camera and Format popups are live while idle (amending CAM-5 (2) and CAM-6
     (2)'s "only while idle with Source Camera"). `currentChoice()` carries `camera` (the popup's
     id) and `cameraFormat` (nil for Best) beside a `.display` or `.picked` source; otherwise
     `camera` is nil, as before. With the box ticked, System Audio, Show Clicks, Size, Include
     Frame Job windows and Rate stay live, and the size note is the screen's.
  4. **The preview** (amending CAM-7 (1) and (3)). The well's row is shown, and CAM-7's step
     runs, whenever a camera is wanted; step (1) reads "the panel not visible or closing, or no
     camera wanted → off". Step (2) also covers a screen recording's camera beside it: that
     capture's layer, else "The camera is recording.". `prepareCamera` acts for any choice
     naming a camera whose source is not `.voiceOver`. The countdown keeps that capture, and the
     panel's `start(…, mayAsk: true)` adopts it (CAM-9 (1)); a tool start never does (CAM-7
     (7)).
  5. **The press with the box ticked**, in order: (1) Window… with nothing picked gives its
     sentence; (2) no camera gives "No camera is connected."; (3) the Screen Recording grant;
     (4) the Camera grant, asked from `notDetermined`, `Privacy_Camera` opened when denied or
     restricted, and a prompt's answer re-read before the microphone is checked (CAM-5 (4));
     (5) the Microphone grant; (6) the countdown. With the box off nothing changes, and the
     Camera grant is never read.
  6. **The recording** is a screen recording: the panel orders out (`hidesForRecording`
     unchanged), the status item is its chrome, and it lands by CAM-10.
  7. **The timeout sentence** (amending CAM-10 (7)) spells the ceiling the stop wait used — its
     `camera:` is the wait's own `cameraBeside` — even when the recorder holds no camera file.
  8. **CAM-10 (9) is lifted.** The box is the panel's door to a camera beside the screen, and
     the catalog's `record_screen` description and the guide name it.
