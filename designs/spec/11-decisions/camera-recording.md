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
