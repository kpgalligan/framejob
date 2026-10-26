# Road map "camera-recording" — recording a camera, alone or over a screen recording

**Opened 2026-10-26** (CR0), in the worktree `~/devel/framejob-camera` on branch
`camera-recording`, from `4855e70`; each phase is gated, committed and merged into main alone.
This road map's decisions are CAM-1 onwards, in `designs/spec/11-decisions/camera-recording.md`.
Its parent design is road map 3 (`designs/adr/roadmap-03-screen-recording.md`; the original is
`archive/roadmap-3.md`).

## Goal

Frame Job records a display, a window or a microphone (road map 3, the voice-over). After this
road map it also records a CAMERA: on its own, or at the same time as a screen recording (a
talking head over a screencast). Each lands as its own file and its own clip; over a screen
recording the camera lands above the screen as a corner picture-in-picture the person can move.

## The owner's choices

**2026-10-26** (the brief, `request.md`; binding):

1. **Scope: camera, or camera + screen.** Camera on its own, OR at the same time as a screen
   recording. Each lands as its own file and track. The camera goes above the screen, placed as
   a corner picture-in-picture that can be moved. Callouts stay out.
2. **Entry point: the existing recorder panel.** The panel gains a Camera source, and a camera
   row when recording the screen. One panel, one countdown, one menu-bar status item with
   Pause/Stop, the same landing into the project. File ▸ New Recording… (⌥⌘N) stays the one door.
3. **Devices and panel:** built-in and USB/UVC cameras; iPhone Continuity Camera; a live preview
   of the chosen camera in the panel; a choice of resolution and frame rate (the camera's
   formats; otherwise its best format).
4. **Audio: the chosen microphone, in its own file**, as screen recording does today. The
   microphone the person picks (which can be the camera's own) is a separate audio file on its
   own track, lined up to the picture.

Also the owner's, standing: no feature size budget; memory limits relative to physical RAM;
person-only checks go in `docs/manual-checks.md`.

## Carried over from road map 3 unless a phase measures otherwise

A recording is ordinary media (no source kind, no model field, no format bump); files go in
`~/Movies/Frame Job Recordings/` (`-RCRecordingFolder` for proofs); the panel asks for grants and
the tool never does; the microphone is a second file; a pause is a sequence of files; one grouped
edit lands everything; undo leaves the files on disk; every door has an MCP mirror.

## How it fits the tree (at `4855e70`)

- **The recorder.** `ScreenRecorder.swift` (372) with `+Pause` (287), `+Delegates` (203),
  `+Microphone` (157), `+Finishing` (347), `+Content` (168), `+VoiceOver` (316),
  `+VoiceOverFinishing` (188): one machine `idle → arming → recording ⇄ paused → finishing → idle`.
  The microphone is an `AVCaptureSession` + `AVCaptureAudioFileOutput` prepared during the
  countdown (`prepareMicrophone`). The road map 3 record holds this file at the 400-line new-file
  cap; camera capture lands in new files, never in it.
- **The values.** `RecordingSetup.swift` (381): `RecordingSource` (`display`, `window`, `picked`,
  `voiceOver`), `RecordingChoice`, `RecordingFiles` (folder, stems, `uniqueURL`,
  `microphoneURL(beside:)`), `RecordingConfiguration.make` (pure), `RecordingGrant` (status
  reads, refusal sentences, `screenStep`/`microphoneStep`). `RecordingResult.swift` (293):
  `RecordingResult` over `RecordingSegment`s.
- **The landing.** `RecordingLanding.swift` (388) with `+Placing` (144), `+Microphone` (390),
  `+LeftOut` (151), `+VoiceOver` (86); `ProjectDocument+Recording.swift` (131,
  `untitled(around:)`, whose order is a contract).
- **The chrome.** `RecorderPanelController.swift` (399) with `+Rows` (351), `+Recording` (357),
  `+Grants` (156), `+Pause` (194), `+Landing` (255), `+Picker` (98), `+VoiceOver` (116);
  `RecorderStatusItem.swift` (234); `AppDelegate+Recording.swift` (86).
- **The tool.** `AgentServer+Recording.swift` (375), `+RecordingArguments` (182),
  `+RecordingResult` (379), `+RecordingChrome` (103); the catalog entry in
  `AgentCatalog+Files.swift` (409, over the new-file cap: it pays a toll before it grows).
  `record_screen` already takes `source` (`"screen"` default, `"voice_over"`, spec §11
  recording.md "A voice-over is a recording with no picture"), whose precedent is that a new
  source is an argument, not a new tool.
- **The build.** `project.yml`: `NSMicrophoneUsageDescription` and the entitlement
  `com.apple.security.device.audio-input`. There is no camera key and no camera entitlement.
- **The proofs.** `tools/proof/recording_spike.py` (R0), `recording_probe.py`,
  `recording_proof.py` (headless and granted tiers).
- **The SDK (MacOSX26.2).** `AVCaptureFileOutput`'s delegate has
  `fileOutput(_:didStartRecordingTo:startPTS:from:)` (macOS 15.2; the first buffer's time on the
  session's `synchronizationClock`); on macOS a second `startRecording(to:)` switches files
  without losing samples. `AVCaptureDeviceTypeContinuityCamera` is reported only with the
  Info.plist key `NSCameraUseContinuityCameraDeviceType`; otherwise a Continuity Camera reports
  `builtInWideAngleCamera` (CR0's D2 found the second half false on this host: without the key
  the iPhone is listed as `AVCaptureDeviceTypeExternal`, `isContinuityCamera` still true).
  `SCRecordingOutput` reports no start time; `SCStream` has a `synchronizationClock`. macOS has
  no `.inputPriority` session preset; a session keeps a requested format only while the device's
  configuration lock is held (CR0).
- **The host (2026-10-26).** `system_profiler SPCameraDataType` lists FaceTime HD Camera, OBS
  Virtual Camera (a camera extension) and an iPhone's Continuity Camera.

## Phases

- **CR0 — the spike; CAM-1, CAM-2.** No product code. CAM-1 records the reversal (camera IN,
  callouts still out, the owner's four answers) in a new §11 file and amends recording.md's
  first bullet and §1's non-goal, before any product code. CAM-2 fixes the rule the spike's
  answers are judged by, before the run. `tools/proof/camera_spike/` MEASURES: the device list
  and format list (with and without the Continuity Camera key); the camera grant (status, the
  responsible process of a shell-launched binary, the hardened runtime with and without
  `com.apple.security.device.camera`); camera capture to a file through
  `AVCaptureMovieFileOutput` and through `AVAssetWriter`; the microphone as a second file and
  its offset; the camera beside a running `SCStream` recording and the camera-to-screen offset;
  pause as a file sequence; the live preview's cost; what a proof can measure without a person.
  **Decides**: the writer, the screen file's start estimator, whether the Continuity key and the
  camera entitlement are needed, the "best format" rule, and which rows a proof can run. A STOP
  verdict goes to the owner with the measurement. **Proof**: the spike itself, run whole once;
  its selftest and mutants.
CR1 was one phase until CR0 landed. It is four now: its two tolls are a pure-move phase of
their own (the size rule lands a toll alone); the camera recorder is a phase of its own, proven
by a probe under the terminal's grant, because CR1a's spec could not hold the recorder and its
tool in the space a spec is given; the tool follows it; and the panel that drives both is last.

- **CR1-0 — the tolls.** Two pure moves, landed and gated alone, with nothing widened.
  `AgentCatalog+Files.swift` (409) gives `record_screen`'s row and its four hoisted clauses to a
  new `AgentCatalog+Recording.swift` (`recordingTools()`, spliced back in where they left), the
  seam `designs/adr/app-file-history.md` names. `RecorderPanelController.swift` (399) gives its
  `// MARK: - Showing` (`show()`, the sync timer, `setNote`, `fitWindowToContent`) to a new
  `RecorderPanelController+Showing.swift`. `recording_probe.py`'s reads and mutants of the moved
  code are re-aimed. **Proof**: the Release bundle's catalog snapshot is the same JSON before and
  after (compared parsed: key order aside, since `JSONSerialization` writes no sorted keys; tool
  order kept, `record_screen` last); `recording_probe.py --only chrome,chrome_pause,catalog`; the two re-aimed mutants are
  caught.
- **CR1a — the camera recorder; CAM-3.** CAM-3 is recorded in §11 before the code and settles
  every rule CR1a and CR1b build on:
  - **Best format.** CAM-2's rule picks the built-in camera's square 1552 × 1552. CAM-3 makes
    "best" the largest LANDSCAPE area (CAM-2's rule over the formats wider than tall): the
    built-in camera's 1760 × 1328 @ 30, the iPhone's 1920 × 1440 @ 60, OBS's 1920 × 1080 @ 60.
    The writer is measured at 1760 × 1328 first (the spike's new `--format`), because CR0
    measured it only at 1552 × 1552. CR2's Format popup is where a person picks 1920 × 1080.
  - **The microphone's offset.** By `startPTS` on the host clock or by callbacks. CR0's M1, M2
    and P2 found the two differ by 63–241 ms; the writer's camera start is its first buffer's PTS.
  - **The camera entitlement.** CAM-2's `not-needed` speaks only for a shell-launched binary
    under the terminal's grant.
  - **The files, a camera that stops on its own, and the tool's refusal order** (CR1b's).
  - **The canvas rule.**

  The camera recorder goes in new files:
  - an `AVCaptureSession` with an `AVCaptureVideoDataOutput` feeding one `AVAssetWriter` per
    segment (CR0's writer), `startSession` at the first buffer's PTS;
  - whenever a format is set, the device's configuration lock held from before `startRunning`
    to after `stopRunning`, and the format set again once the session runs (CR0);
  - the microphone as a second file per segment;
  - pause as a new writer on the running session (CR0's P2: resumes in 5–26 ms);
  - a camera that stops on its own ends the recording, as a microphone ends a voice-over; a
    microphone that stops on its own does not: the picture keeps recording and that segment
    carries a `micProblem`, the screen recording's rule;
  - `ScreenRecorder` forwarding to it, as it forwards to `voiceSession`.

  Also in CR1a: `RecordingSource.camera`; files named `Camera Recording <date> at <time>.mov`;
  `NSCameraUsageDescription`, and no `NSCameraUseContinuityCameraDeviceType` (CR0's D2); the
  camera entitlement if CAM-3 says so, with the dist checks' exact sets; `RecordingGrant`'s
  camera read and refusal; the result's camera facts. **Proof**: a new
  `tools/proof/camera_recording_probe.py`. Its pure rows are the format rule, the names, the
  offset arithmetic and a camera result through `RecordingLanding`. Its granted section runs a
  real recorder under the terminal's grant, pausing once, and skips by name without a camera or
  the grant. Mutants. No door reaches the recorder yet, so nothing user-visible changes; the
  docs are spec §7.4's row and `tools/proof/README.md`.
- **CR1b — the tool; CAM-4.** CAM-4 is recorded in §11 before the code: the tool's own
  choices CAM-3 left open (`camera` with another source, the camera answer key, the span
  counted from the first buffer). `record_screen`'s `source: "camera"` and `camera` (a device's
  name or unique id; an unknown name is refused, naming the cameras present), in CAM-3's
  refusal order; the answer's camera keys; the landing: into an open project by the picture
  rule; as a new project with the canvas at the camera format's size and rate. CR1a's residue
  lands here, because the tool is what exposes it: #372 (the review's four nits — the frame
  durations re-set once running, `no-hold` caught by G6's buffer count rather than G3's thin
  margin, a stopped segment's first stamp kept, segment 0's elapsed counted from its mint) and
  #371 (`recording_probe.py`'s two X4 rows, in the file this phase re-aims). **Proof**: a new
  `tools/proof/camera_recording_proof.py` over MCP, with two tiers. The headless tier checks the
  refusals in order, the catalog and parity. The granted tier skips by name without a camera or
  the grant. Beside it: `camera_recording_probe.py` rows for the argument refusals, the
  lookup and the answer, with their mutants; `recording_proof.py`'s and
  `recording_probe.py`'s `record_screen` schema rows; mutants. Docs: spec §7.9 (§6 lists ops
  only, and `record_screen` is an app-state tool); `docs/guide/screen-recording.md` and
  `mcp.md`; a manual-check row for the voice lined up with the picture (a clap). The camera
  prompt's row moves to CR1c: the tool never asks, so until the panel has a Camera source
  nothing in the signed bundle can put the prompt up.
- **CR1c — the panel's Camera source.** The panel gains:
  - a Source ▸ Camera row and a Camera popup (devices by name, the best format);
  - the camera grant, asked by the panel, with its System Settings pane door (`Privacy_Camera`)
    and `RecordingGrant`'s camera step;
  - its defaults key and the harness pin;
  - the status item, as for every source;
  - the microphone meter's camera arm (`publishMicrophoneLevel` reads a camera recording's
    microphone output), and the panel's note for a result's camera problem and for a
    `system_stopped` camera (CR1a puts both on the result; until CR1c only the tool reads them),
    and the result's warm-up `camera.note`;
  - the camera's session started during the countdown, as `prepareMicrophone` warms the
    microphone, so CAM-3's warm-up hold is spent there (CR1a pays it inside the recorder's
    start, about 0.5 s on the built-in camera).

  **Decides** whether the panel stays up for a camera recording (the voice-over's precedent) or
  goes away. **Proof**: probe rows for the grant steps and for the rows → choice; `snapshot_ui`
  of the panel; mutants; manual-check rows for framing and for the camera prompt from the signed
  bundle (`open -a`, moved here from CR1b). Docs: `docs/guide/screen-recording.md`; the
  camera refusal's `notDetermined` sentence, written in CR1a to name the panel's Camera source,
  becomes true here.
- **CR2 — the preview and the formats.** The live preview in the panel: an
  `AVCaptureVideoPreviewLayer`, which CR0's V1 measured at about 155–160 MB of RSS, so it runs
  only while the panel shows the Camera row or the camera row. The Format popup lists the
  camera's formats as resolution × frame rate, Best first, and sets the chosen one under the
  device's configuration lock (CR0). Hot-plug: a camera connected or removed while the panel is
  up. A Continuity Camera is marked by `isContinuityCamera`, since CR0's D2 lists it without the
  key, as External. The tool gains `camera_format`. **Decides** the popup's rows and their
  persistence, the preview's lifetime, and what a removed camera does to a running recording.
  **Proof**: probe rows for the format list → popup items; `snapshot_ui` of the panel; MCP
  `camera_format` rows; a screen in `designs/screens/`; manual-check rows for the preview's look
  and the Continuity Camera pairing.
- **CR3 — camera + screen.** The camera row under Source when recording a display or a window;
  the camera capture started beside the `SCStream` (CR0: the order of the starts made no
  measurable difference, and started in one run-loop turn the writer's camera began 87–130 ms
  before the screen file); per-segment offsets by E2 (CR0: the PTS of the first `.screen` frame
  at or after the did-start's arrival); pause and resume in step; the landing: the screen on its track, the camera on a
  new track ABOVE it at a corner picture-in-picture (the corner, scale and inset decided here),
  the microphone on its back track, one grouped edit; a camera failure in a screen recording is
  that recording's note, never its failure; `record_screen`'s `camera` with the screen source.
  **Decides** the corner rule, the track names, the order of the starts, the result's camera
  fields. **Proof**: `camera_recording_proof.py`'s camera + screen rows (track order and the
  placed transform read back through `get_project`; per-segment offsets in the result), probe
  rows for the landing ops; a manual-check row (the talking head lined up with the screen and
  the voice).
- **CR4 — the close.** The README highlight; `docs/guide/` read back against the code; the
  proofs run whole once on Release; then as root `CLAUDE.md` says: condense this into
  `designs/adr/camera-recording.md`, file each unfinished item as an issue (reviewed against
  the tree), `git mv` this file into `archive/`, and add its row to `archive/INDEX.md`; the ADR
  row in root `CLAUDE.md`'s table is owed to the integrator.

## CR0 — the spike

### Record

**Landed (2026-10-26).** Spec §11 CAM-1 and CAM-2 in `designs/spec/11-decisions/camera-recording.md`
(new), recorded before the run and before any product code; recording.md's first bullet carries
"Amended by CAM-1", §1's opening sentence and non-goal list are amended (callouts stay out), and
both spec indexes gained their rows and Lines cells. The instrument is `tools/proof/camera_spike/`
(`camera_spike.py`, `camera_spike_probe.swift`, `README.md`) with a section in
`tools/proof/README.md`. No product file changed.

**The run.** `python3 tools/proof/camera_spike/camera_spike.py --ask`, run by the owner from the
terminal (every group but `aimed`, `--runs` 3), 2026-10-26 15:04:54–15:13:13, 498.3 s, exit 0,
`failures: []`. HEAD `4855e70a17455f77d88e08d07d75361c6c610434+dirty` (this change, the instrument
unchanged since this change's passing `make gate`: names, typecheck, fmt, lint, test, app, PASS
385 s). `rule_sha256` `de3a4e406dc78d2c465a357f30207b003cb5d902b6e2ddfe7f678be83adb97bf`, the
SHA-256 of `designs/spec/11-decisions/camera-recording.md`, unchanged since it was written
before the first run. Host (H0, at the start
and after every group): Mac14,6, macOS 26.5.1 (25F80), on AC power, one Frame Job running (pid
30591, another session's); 1-minute load 8.19 at the start, 4.68–17.98 between groups (17.98
after `pause`, so V1's percentages are noisy). Selftest 5/5 (S1–S5); the five mutants
`writer-frames-off`, `estimator-wide`, `decode-swap`, `skip-as-fail`, `continuity-inverted` each
exit 1 (caught). An earlier run the same afternoon (15:00:54, before the grant) answered
`VERDICT NOT MEASURED` with every camera row skipped for the terminal's `notDetermined` Camera
grant; `--ask` (CAM-2: the only path that asks) took the grant, and nothing was skipped this time
but A1, which was not requested.

**The re-runs on the final instrument.** In the owner's run no movie-output session held D3's
format: `startRecording` moved the built-in camera from format 6 (1552 × 1552) to format 0
(1920 × 1080) in W2, P1, S and V1, so CAM-2 (a) and (d) were judged on files at 1920 × 1080, not
"at D3's format". macOS has no `.inputPriority` session preset (`API_UNAVAILABLE(macos)` in the
26.2 SDK); a session there keeps a requested format only while the device stays locked for
configuration. So the probe now holds the device's configuration lock from building the session
to stopping it whenever a format is requested, and the runner marks a W2 or P1 run whose format
read back while recording is not D3's as off-format: such a run is reported and left out of
clauses (a) and (d). `python3 tools/proof/camera_spike/camera_spike.py --groups write,pause`
(`devices` ran first, as the runner does), 2026-10-26 15:31:21–15:33:55, 153.6 s, exit 0,
`failures: []`; the same HEAD and `rule_sha256` as above; H0 load 3.05 at the start, 2.97–4.20
between groups, no Frame Job running. Every W2, W3, P1 and P2 run read back format 6 while
recording, and no run was off-format. The lock also changes S's writer path and V1's D3 run, so
those groups ran again: `python3 tools/proof/camera_spike/camera_spike.py --groups screen,preview`
(`devices` first), 2026-10-26 15:36:11–15:41:01, 290.0 s, exit 0, `failures: []`, the same HEAD
and `rule_sha256`; H0 load 4.65 at the start, 2.43–4.60 between groups, no Frame Job running. The
W1–W3, P1, P2, S1, S2 and V1 rows below come from these two re-runs, and D1–D3 answered the same
in both. The other rows come from the owner's run. Those rows set no format, so the lock does not
change what they measure. The owner's S and V1 numbers are kept beside the re-run's where they
differ.

The camera is the FaceTime HD Camera (the `--camera` default) and the microphone the MacBook Pro
Microphone; every timing row is 3 runs (S: 2 per order per path) and reads median (min–max).

| Row | Outcome | Answer |
|---|---|---|
| H0 | ok | as above |
| B0 | ok | both probes built (reused, the same key); `hardened-noent` `flags=0x10002(adhoc,runtime)`, `hardened-ent` the same with `[Key] com.apple.security.device.camera` |
| D1 | ok | 3 cameras with the key: FaceTime HD Camera (`AVCaptureDeviceTypeBuiltInWideAngleCamera`, `bltn`, Apple Inc., 7 formats all `420v` at 15–30 fps: 1920 × 1080, 1280 × 720, 1080 × 1920, 1760 × 1328, 640 × 480, 1328 × 1760, 1552 × 1552; active 1280 × 720), OBS Virtual Camera (`AVCaptureDeviceTypeExternal`, `virt`, OBS Project, one format 1920 × 1080 @ 60 `BGRA`), the owner's iPhone (Continuity Camera) (`AVCaptureDeviceTypeContinuityCamera`, `isContinuityCamera` true, `othr`, model iPhone19,3, 8 formats 640 × 480 to 1920 × 1440 at 30 and 60, active 640 × 480); `systemPreferredCamera` nil; every format's `supportedColorSpaces` is `[0]` (sRGB); 6 microphones |
| D2 | ok | the no-key build lists the same 3 devices both with `.continuityCamera` in the types (no refusal) and without it; the iPhone keeps its `uniqueID` and `isContinuityCamera` true but reports `AVCaptureDeviceTypeExternal` |
| D3 | ok | FaceTime HD Camera 1552 × 1552 @ 30 `420v` (format 6); OBS Virtual Camera 1920 × 1080 @ 60 `BGRA`; the iPhone 1920 × 1440 @ 60 `420v` |
| T1 | ok | responsible process `ghostty`; video `notDetermined`, asked, then `authorized`; audio `authorized`; screen preflight true |
| T2 | ok | hardened, no entitlement: 59 frames in 2 s, 3 black, mean luma 120.9, first frame 381 ms after start |
| T3 | ok | hardened, with the entitlement: 59 frames in 2 s, 2 black, mean luma 120.6, first frame 233 ms after start |
| W1 | ok | movie output, the session's own format (1920 × 1080, format 0, not locked): did-start 1008.6 ms (1007.7–1032.9); `startPTS` − did-start −206.2 ms (−208.3 to −205.8) (the `synchronizationClock` is the host clock; every run converted); 165 frames of 177.1 = 93.2 % in every run, nominal 29.985, average 27.94 fps, 12 gaps over 1.5 frame intervals (max 66.7 ms) per file; drops not reported by a movie output; 931 kB/s; `hvc1` (HEVC and H.264 both writable); colour ITU-R 709 ×3, identity transform; CPU 0.59 s (0.59–0.61); read back format 0 and 1/30 s both durations; close 4.5 ms |
| W2 | ok | movie output at D3's 1552 × 1552 locked at 30, the device held under its lock: read back format 6 while recording in every run, and every file is 1552 × 1552 (0 off-format runs); did-start 1029.6 ms (1016.5–1044.0); `startPTS` − did-start −212.7 ms (−245.2 to −211.7); 165 of 177.1 = 93.2 % in every run, nominal 29.981, average 27.94 fps, 12 gaps (max 66.7 ms) per file; 1046 kB/s; `hvc1`; ITU-R 709 ×3, identity; CPU 0.60 s (0.57–0.66); read back 1/30 s both; close 6.2 ms |
| W3 | ok | asset writer on W2's configuration: read back format 6 while recording, files 1552 × 1552; first append 12.0 ms (9.8–14.4) after the writer was armed; the first buffer's PTS − its append −75.8 ms (−77.6 to −75.5); 151 of 151.1 = 99.9 % in every run, nominal and average 29.98 fps, no gap (max 35 ms); 0 dropped callbacks, 0 not-ready appends; 1047 kB/s; `hvc1`; ITU-R 709 ×3, identity; CPU 0.55 s (0.49–0.58); read back 1/30 s both; close 37.5 ms |
| M1 | ok | one session, camera + microphone + movie output (video only) + `AVCaptureAudioFileOutput`: `canAddOutput` true; microphone − camera by `startPTS` −946.7 ms (−947.8 to −920.4), by callbacks −1161.8 (−1172.3 to −1069.9), the two differ by −215 ms (−224 to −150); camera did-start 1195 ms, microphone 30 ms; the microphone's clock is not the host clock (converted) |
| M2 | ok | the camera session plus a separate microphone session: by `startPTS` −928.3 ms (−929.0 to −918.5), by callbacks −1139.1 (−1170.2 to −1132.0), differing by −213.6 (−241.3 to −210.8); camera did-start 1173 ms, microphone 33 ms |
| S1 | ok | camera first, 4 runs (2 movie-output, 2 asset-writer), the screen file's first frame decoded every time (truth frame 0): **E1 −13.8, −19.9, −20.1, −20.3 ms**; E2 +0.49 ms in every run; camera − screen truth +766.0, −44.6 (movie output), −97.2, −130.1 (writer); camera − E1 by `startPTS` +779.7, −24.7, −77.1, −109.9, by callbacks +982.0, +208.8, +0.0, −32.5; screen 229–286 frames at 57.24–57.60 fps (60 asked); camera 27.49, 29.99 fps (movie output), 29.98, 29.98 (writer); CPU 0.64–0.77 s. The owner's run, before the lock: E1 −10.9, −10.3, −10.7, −8.5 ms, E2 +0.49; camera − screen truth +785.6, +753.0 (movie output), −105.9, −102.5 (writer) |
| S2 | ok | stream first, 4 runs, truth frame 0 every time: **E1 −21.0, −12.9, −11.0, −8.6 ms**; E2 +0.49 ms in every run; camera − screen truth −50.3, −40.3 (movie output), −119.9, −86.6 (writer); camera − E1 by `startPTS` −29.4, −27.4, −108.9, −78.0, by callbacks +215.0, +205.9, −33.4, −2.7; screen 57.24–57.62 fps; camera 29.99, 29.99 (movie output), 29.98, 29.99 (writer); CPU 0.62–0.65 s. The owner's run: E1 −10.1, −15.0, −8.0, −8.9 ms, E2 +0.49; camera − screen truth +777.3, +705.4 (movie output), −105.3, −115.4 (writer) |
| P1 | ok | movie output at D3's format under the device lock, `stopRecording` / `startRecording(to:)` on the running session, 3 runs × 3 segments: format 6 read back while every segment recorded (0 off-format runs); start 1021.1 ms (1008.0–1042.3, n 9), resume start 1018.8 ms (1008.0–1042.3, n 6), close 3.7 ms (1.4–7.1); each file spans 961.5 ms (826.3–963.0) MORE than its segment; every file 1552 × 1552 with 12 gaps; microphone offset by `startPTS` −772.5 ms (−822.2 to −734.9), by callbacks −968.2 (−1007.0 to −960.3) |
| P2 | ok | asset writer finished and a new one started at the next buffer: format 6 read back while every segment recorded; start 8.5 ms (1.9–26.4, n 9), resume start 13.8 ms (5.3–26.4, n 6), close 24.6 ms (14.7–30.0); file − segment +21.5 ms (−6.0 to +27.2); files 1552 × 1552, no gap; microphone offset by `startPTS` +80.7 ms (+65.3 to +95.2), by callbacks +18.1 (+6.8 to +35.2); the data output ran at 29.99 fps (29.26–30.65) through the pauses |
| V1 | ok | probe CPU % and RSS, 10 s each, the format read back as format 6 (1552 × 1552) before the stages in both. Unasked format: session 3.1 %, 37 MB; + preview 9.6 %, 196 MB; + preview + recording 12.2 %, 216 MB. D3's format under the lock: session 3.1 %, 37 MB; + preview 8.1 %, 197 MB; + recording 12.5 %, 209 MB. `ps` found no `cameracaptured`. In the owner's run, before the lock, the numbers were: unasked, 1.1 % / 35 MB, 2.9 % / 191 MB, 3.5 % / 211 MB; D3, 2.8 % / 37 MB, 9.7 % / 196 MB, 11.2 % / 216 MB. In the owner's run, adding the movie output moved the device to 1920 × 1080 in both; in the re-run only the unasked run moved |
| X1 | ok | one virtual camera, OBS Virtual Camera: 180 frames in 3 s, none black, mean luma 44.6, with OBS running (pid 544); delivery with OBS not running not measured |
| A1 | not requested | needs a person (`--aimed`) |

Q0 (what each row needs): nothing — H0, B0, D1, D2, T1 and X1's list; a camera present — D3;
the Camera grant and a camera — T2, T3, W1–W3, P1, P2, V1 (P also the Microphone grant for its
offsets), X1's delivery (a virtual camera, and here its host app running); Camera + Microphone
grants — M1, M2; Camera grant + Screen Recording — S1, S2; a person — A1. So without a person a
proof can measure every row but A1 once its terminal holds the Camera grant; without the grant,
only the device lists, the grant read and the builds.

**VERDICT on the final instrument:** `writer=asset-writer screen_start=E2
continuity_key=not-needed camera_entitlement=not-needed best_format=FaceTime HD
Camera=1552x1552@30 420v; OBS Virtual Camera=1920x1080@60 BGRA; the owner's iPhone (Continuity
Camera)=1920x1440@60 420v`. Each run printed its own line as stderr's last line:
- The owner's run: `VERDICT writer=asset-writer screen_start=E1 continuity_key=not-needed
  camera_entitlement=not-needed best_format=` (the same three formats).
- The `write,pause` re-run: `VERDICT writer=asset-writer screen_start=unmeasured
  continuity_key=not-needed camera_entitlement=unmeasured best_format=` (the same).
- The `screen,preview` re-run: `VERDICT writer=NOT MEASURED screen_start=E2
  continuity_key=not-needed camera_entitlement=unmeasured best_format=` (the same).

In each re-run a field reads `unmeasured` or `NOT MEASURED` only because its group did not run.
So the writer comes from the `write,pause` re-run, the screen start from the `screen,preview`
re-run, and the camera entitlement from the owner's run (T2 and T3 set no format). **The screen
start changed from E1 to E2.** In the `screen,preview` re-run, E1 missed CAM-2's 16.7 ms bound in
4 of 8 runs (−19.9 to −21.0 ms). E2 read +0.49 ms in all 16 S runs across both runs. The writer's
reasons, as the `write,pause` re-run's `results.json` gives them: "(a) a W2 run wrote < 98 % of
span × rate while W3's runs are ≥ 98 %" and "(d) P1's median resume start latency 1018.8 ms
exceeds P2's 13.8 ms by more than one frame (33.3 ms)". The owner's run gave the same two, with
(d) at 1017.6 against 17.9 ms.

**An instrument check before the first run** (not CAM-2 evidence): a scratch copy of the probe's
`screen` mode without the camera recorded the main display three times beside the counter; every
one of the first 4 frames decoded, the truth came from frame 0 each time, E2 read +0.495 to
+0.497 ms and E1 −13.0 to −16.2 ms against it. S1 and S2 above agree on E2 (+0.49). E1 read
−8.0 to −15.0 ms in the owner's run and −8.6 to −21.0 ms in the re-run.

**Decides.**
- **Writer (CR1, CR3): `AVAssetWriter` fed by an `AVCaptureVideoDataOutput`**, `startSession` at
  the first buffer's PTS (CAM-2 (a) and (d)), judged by the re-run with every W2 and P1 run at
  D3's 1552 × 1552. The movie output's shortfall is not the format's. At 1552 × 1552 (W2) and at
  1920 × 1080 (W1) alike, it wrote 93.2 % with 12 gaps per file at 27.94 fps, and it took
  1008–1044 ms to start or resume (W1, W2, P1). The writer, at 1552 × 1552, wrote 99.9 % with no
  gap and started in 10–14 ms (resumes 5–26 ms). **The writer at 1920 × 1080 is unmeasured:** no W3
  or P2 run used format 0. So CR1 measures the writer at the landscape format before choosing a
  landscape "best format" (see Best format below). A movie output's file also starts about 0.2 s
  before its did-start callback and runs about 1 s longer than its segment (P1). On macOS a
  session keeps a requested format only while the device's configuration lock is held, from
  before `startRunning` to after `stopRunning`. Without the lock the movie output's
  `startRecording` re-took the device (the owner's run). Even the writer's session had its format
  moved at `startRunning`; the format held only once it was set again after the session started
  (W3, the owner's run). So CR1 and CR2 hold the lock whenever they set a format.
- **Screen start (CR3): E2**, the PTS of the first `.screen` frame at or after the arrival of
  `recordingOutputDidStartRecording`. It read +0.49 ms against the counter's truth in all 16 S
  runs (bound 16.7 ms). E1, the arrival time itself, passed in the owner's run (|E1| ≤ 15.0 ms, a
  1.7 ms margin). It failed in the re-run on the final instrument: −19.9, −20.1, −20.3 and
  −21.0 ms in 4 of its 8 runs, and −13.8 to −8.6 in the rest. The failures fell on movie-output
  and writer runs alike, so the device lock did not cause them. CAM-2 takes the first estimator
  that passes in every S run, so CR3 uses E2.
- **Camera − screen (CR3):** started in one run-loop turn, the writer's camera starts 87–130 ms
  BEFORE the screen file in both orders (S1, S2, both runs: −86.6 to −130.1). The movie
  output's start does not hold still: it was 705–786 ms after the screen file in the owner's run,
  and in the re-run +766 ms once and 40–50 ms before it three times. The order of the starts made
  no measurable difference.
- **Continuity key (CR1, CR2): not needed** for the camera to be listed: D2 lists the iPhone, by
  its `uniqueID`, without the key and without `.continuityCamera`. The road map's SDK note that
  without the key a Continuity Camera "reports `builtInWideAngleCamera`" is false on this host: it
  reports `AVCaptureDeviceTypeExternal`, `isContinuityCamera` still true, so CR2 can list it by
  `isContinuityCamera` with or without the key. No row recorded from the iPhone.
- **Camera entitlement (CR1): not needed** by CAM-2: T2, a hardened copy without it, delivered 59
  frames (3 black) as T3 with it did. The binary's responsible process is the terminal (T1), so
  this speaks for a shell-launched binary under the terminal's grant; the app is its own
  responsible process, and CR1's camera prompt from the signed bundle (its manual-check row) is
  where the bundle is seen.
- **Best format (CR1, CR2):** CAM-2's rule picks the built-in camera's SQUARE 1552 × 1552 (largest
  area at 30 fps) over its 1920 × 1080; the iPhone's 1920 × 1440 @ 60. A camera-alone canvas sized
  to "the best format" (CR1) would be square on this Mac. CR1 records whether "best" means the
  largest area or the largest landscape area, as an amendment of CAM-2's Best format before its
  code. If it chooses landscape, it first measures the writer there. On this Mac the largest
  landscape format at 30 fps is 1760 × 1328 (format 3, area 2,337,280), not 1920 × 1080 (format
  0, 2,073,600). No run of either path has used format 3.
- **The microphone (CR1, CR3):** both shapes work: one session with an `AVCaptureAudioFileOutput`
  beside the camera (M1, `canAddOutput` true) and today's separate microphone session (M2). The
  offset by `startPTS` and by callbacks differ by 210–241 ms with the movie output (most of it the
  movie output's own −202 ms between its `startPTS` and its callback) and by about 63 ms with the
  writer (P2 in the re-run: +80.7 against +18.1 ms; the owner's run gave +105 against +35).
  CAM-2 has no clause choosing between them and only A1 (a person) measures the truth; CR1 states
  which it uses.
- **Pause (CR1, CR3):** a new writer per segment resumes in 13.8 ms, with the data output running
  at 29.99 fps through the pauses. The files overrun their segments by 21.5 ms.
- **The preview (CR2):** a 320 × 180 `AVCaptureVideoPreviewLayer` adds about 155–160 MB of RSS and
  1.8–6.9 percentage points of probe CPU (noisy host, see H0). At 1552 × 1552 under the lock, a
  session, preview and recording together took 12.5 % in the re-run, against 11.2 % before the
  lock (when the movie output had moved the device to 1920 × 1080).
- **What a proof can run (CR1–CR3):** Q0 above. A virtual camera (OBS Virtual Camera) delivers
  frames while its host app runs, so a headless granted-tier fixture is possible on a host that
  has one; without its host app it is not measured.

**Owed.** Nothing for CR0. Filed as #370: the screen recorder places its microphone file by callback
arrival, and here the callback offset differs from the `startPTS` offset by more than a frame
(M2 213.6 ms, P2 about 63 ms; the screen's own E1 is within 21 ms of its truth and E2 within 0.5 ms); whether it
should move to `startPTS` is an issue, not CR0's (recording.md's "two FILES" bullet stands).

## CR1-0 — the tolls

### Record

**Landed** (2026-10-26). Two pure moves with nothing widened and no body changed:
- `record_screen`'s row (its `// MARK: Recording` block and the `tool("record_screen", …)` entry)
  and its four hoisted clauses (`recordingPauseClause`, `recordingUnreadableClause`,
  `recordingResultClause`, `recordingVoiceOverClause`, with the comment that explains the
  hoisting) moved from `AgentCatalog+Files.swift` to a new `AgentCatalog+Recording.swift`.
  The new file's `recordingTools()` is spliced back in LAST with `rows += recordingTools()`, so
  `record_screen` is still the catalog's last row. The `+Files` header now counts eight rows built
  elsewhere, and `AgentCatalog.swift`'s `tool` doc and its splice comment name the new file.
  These edits are comments only, and `AgentCatalog.swift` stays at 578 lines.
- The panel's `// MARK: - Showing` (`show()`, the private `armSyncTimer()`, the `syncPhase()`
  pointer comment, `setNote`, `fitWindowToContent()`) moved from `RecorderPanelController.swift`
  to a new `RecorderPanelController+Showing.swift`. The base header lists the ninth file.
- `tools/proof/recording_probe.py`: 5h's `fitWindowToContent` read and 5u's `show()` guard and
  body reads now come from `+Showing.swift`. The file is in both sections' "is in the sources"
  lists. `no-constrain` and `show-while-hidden` mutate `+Showing.swift` with their text
  unchanged, and the docstring names it.
- `designs/spec/07.4-swift-file-map.md` row 52 lists `+Showing.swift`. The file still has 57
  lines.

**Sizes** (`wc -l`, before → after): `AgentCatalog+Files.swift` 409 → 166,
`AgentCatalog+Recording.swift` new, 273; `RecorderPanelController.swift` 399 → 326,
`RecorderPanelController+Showing.swift` new, 85.

**Measured** (from the worktree; each command run once but `make gate`, which the build ran
three times):
- `git diff 4855e70 HEAD -- app core project.yml`: empty. `python3 tools/proof/proof_app.py
  --app release check`: `fresh: …/Release/Frame Job.app/Contents/MacOS/Frame Job`, exit 0. The
  bundle's `agent-catalog.json` (298163 bytes) was copied as the "before" snapshot.
- `make typecheck`: exit 0, 0 errors, the 4 baseline warnings, and tsc printed no error.
- `python3 tools/proof/recording_probe.py --only chrome,chrome_pause,catalog`: exit 0,
  `212/212 checks passed`.
- `… --only chrome,chrome_pause --mutant no-constrain`: exit 1, `181/182 checks passed`
  (FAIL 5h: fitWindowToContent constrains the frame to its screen).
- `… --only chrome,chrome_pause --mutant show-while-hidden`: exit 1, `180/182 checks passed`
  (FAIL 5j: show() leaves the panel invisible…; FAIL 5u: show()'s guard is unchanged).
- `make gate`: `gate: PASS 224s` (names pass 1 s, typecheck pass 5 s, fmt skip, lint skip,
  test pass 115 s, app pass 103 s). That was the one full pass. A second invocation, after a
  failed edit of this record that changed nothing, skipped every step; a third, after this
  record was written, re-ran only names (pass) and skipped the rest as byte-identical,
  `gate: PASS 1s`.
- The structural catalog comparison of the "before" snapshot against the gate's Release
  bundle printed `106 record_screen` and exited 0: the parsed documents are equal, the tool
  names are equal in order, and the last is `record_screen`.

**Deviations.** The step order: `make gate` ran before this record was written (the spec has
the record first), so the record could carry the gate's printed numbers; the gate was run again
after the record edit, and only names re-ran. None in the code.

**Owed.** Nothing for CR1-0. Its `app/CLAUDE.md` map entries (`+Showing` in the panel's family,
`+Recording` in the catalog's) landed with it. `designs/adr/app-file-history.md`'s
next-seam line for `AgentCatalog+Files.swift` is condensed at CR4.

## CR1a — the camera recorder

### Record

**Landed** (2026-10-26).
The phase stopped once, on the granted probe's G3 (below), and resumed on the orchestrator's
ruling: the camera's stream is warmed before segment 0, road map 3's `prepareMicrophone`
precedent.
- Spec §11 CAM-3, written before any code, and its index rows (CAM-2's row says "amended by
  CAM-3"); then its **warm-up** bullet, added on the ruling before the hold's code. The
  `11-decisions/` cell is 13074 in 31 files; `camera-recording.md` is 144 lines.
- The spike's `--format WxH` (`camera_spike.py`, its docstring and README): D3 is the chosen
  camera's first format of that size at a maximum rate ≥ 30, recorded as `formatOverride`; a
  size the camera lacks prints `NOT PERFORMED` and exits 2; the selftest is unchanged.
- New: `CameraDevices.swift` (136 lines: the list, facts, lookup, default, CAM-3's best
  format, `spelled`, `canvasRate`, the two sentences), `CameraCapture.swift` (399: the
  session, the configuration lock, the data output, one writer per segment, the warm-up),
  `ScreenRecorder+Camera.swift` (396: `CameraSession`, `CameraSegment`, start, pause, resume,
  stop, elapsed, names), `ScreenRecorder+CameraFinishing.swift` (366: the capture's and the
  microphone's reports, the one finishing path, settle, the probe walk, conclude,
  `cameraMicOffset`, `CameraMicrophoneDelegate`), `RecordingSetup+Camera.swift` (51:
  `cameraStem`, `RecordingGrant.cameraStatus`, `cameraRefusal`).
- Changed: `RecordingSetup.swift` (381 → 387: `RecordingSource.camera`,
  `RecordingChoice.camera`); `RecordingResult.swift` (293 → 317: `RecordingCamera` with
  `problem` and the warm-up's `note`, `RecordingResult.camera`, `isCamera`,
  `RecorderError.cameraDevice`); `ScreenRecorder.swift` (372 → 385: `cameraSession`, `elapsed`
  and `stop()` forwarded, `start()` refusing `.camera`); `+Pause`, `+VoiceOver` (the three
  `held*` reads) and `+Content` (`filter`'s `.camera` arm throws) gain the camera's arm.
- `project.yml`: `NSCameraUsageDescription` and `com.apple.security.device.camera`; the camera
  in every exact entitlement set: the Makefile's comments, `dist_check.py`
  (`APP_ENTITLEMENTS`, D14, D25), `dist_check_mutants.py` (`held` is now
  `dict(dist_check.APP_ENTITLEMENTS)`), `gate.py`'s D25 name, `published_check.py`'s P5.
- **The warm-up** (CAM-3): `CameraCapture.start`'s completion waits until five consecutive
  frame intervals, by PTS, are each within 15 % of the format's frame duration, bounded at 1 s
  from the session's start; past the bound it completes anyway and `WarmUp.note` (the result's
  `camera.note`) names the rate measured. Segment 0's writer is armed only after it, so it
  starts at a steady buffer; a resume, on the running session, does not wait. **CR1c moves the
  warm-up into the countdown**: until the panel's countdown starts the camera's session early,
  the hold is paid inside the recorder's start.
- `tools/proof/camera_recording_probe.py` and `.swift` (values V1–V17, landing L1–L3, granted
  G0–G6; seven mutants); spec §7.4's row 50; `tools/proof/README.md`'s CR1a section and its
  four entitlement passages.
- `tools/proof/recording_probe.py`: one re-aim — `caseName`'s switch over `RecorderError` gains
  `.cameraDevice` (the probe did not compile without it).

**Measured** (the built-in camera, the default microphone, the terminal's grants):
- Step 2 (CAM-3's criterion): `python3 tools/proof/camera_spike/camera_spike.py --groups
  write,pause --camera FaceTime --format 1760x1328`, exit 0, 152.7 s, `rule_sha256
  634e08997566e1aec9f0c4f46fa02f593841354e22c509af8918456376e6ef6a` (CAM-3 before its warm-up
  bullet), `formatOverride {asked 1760x1328, index 3}`. W3 (the writer at format 3, locked):
  ratio 0.9993, 0.9993, 0.9993 (151/151.1, 151/151.1, 150/150.1 frames), every run read back
  format 3 at 1760 × 1328, `offFormatRuns` 0, HEVC, 0 not-ready, 0 dropped. P2: median resume
  start 15.16 ms [1.235, 32.862] over 6 resumes, under one frame (33.3 ms); every segment read
  back format 3 (60–61 frames per 2 s segment). W1 and W2 (the movie output) 0.932 in every
  run, as in CR0. The criterion holds. Every run warmed the session 1 s before arming.
- **The cold start, before the warm-up** (`--only granted`, three runs): G0, G1, G2, G4, G5
  passed every run; G3 failed every run on segment 0 (61 frames, 0.976; 59, 0.9752; 59,
  0.9752) while segment 1 passed (0.9992). Segment 0's first intervals were 33.3, 33.3, then
  five at 43.3 ms, then 33.3 ms steadily. A temporarily instrumented run (reverted) read the
  format NOT moved by `startRunning`, both frame durations 1/30 s at start, and the 43 ms
  buffers arriving before the writer was armed: the device's cold start, not the format hold
  or the writer.
- **With the warm-up**: `--only granted` exit 0, 8/8: G3 59/0.9992 and 61/0.9992; G6 hold
  0.540 s from the session's start, 13 buffers, steady, intervals 33.4, 33.4, 43.3, 43.2,
  43.3, 43.3, 43.2, then 33.4, 33.3, 33.4, 33.4, 33.4 ms; the call to `.recording` 1.962 s;
  no note. The whole probe, `python3 tools/proof/camera_recording_probe.py`: exit 0, `scores:
  31/31`, all checks passed; G3 59/0.9992 and 59/0.9992, G4 micOffset −0.070 and −0.108 s,
  G6 hold 0.530 s, 13 buffers, steady, the call to `.recording` 1.943 s.
- Mutants (each exit 1, caught): `format-any-shape` (V1: 6, 1552x1552@30),
  `offset-by-arrival` (V12a −600000), `offset-sign` (V12a −30000, V12c 12000),
  `canvas-rate-60` (V6), `grant-unread` (V16), `mic-ends-recording` (V15), each `--only
  values`, run before the warm-up (their anchors are unchanged since); and `no-hold`
  (`warmUpRun` 0, `--only granted`): G3 60/0.9796 on segment 0, 0.9992 on segment 1, G6 hold
  0.085 s, 1 buffer. The margin is small (0.9796 against 0.98) and holds only on a cold
  camera.
- `make typecheck`: exit 0, the 4 baseline warnings, tsc clean. `spec_index_proof.py`:
  201/201.
- `make gate`: `gate: PASS 228s` (names 1 s, typecheck 5 s, fmt 2 s, lint 1 s, test 115 s,
  app 103 s). `make dist`: exit 0, `dist_check: 27/27` (D14 the Distribution app's
  entitlements exactly audio-input and camera; D25 the Release app's audio-input, camera and
  get-task-allow), `published_check: 16/16` (P5). `python3 tools/proof/dist_check_mutants.py`:
  `dist_check_mutants: 23/23`.
- `python3 tools/proof/recording_probe.py`: exit 1, `1220/1222 checks passed`. The two
  failures are X4's `recordScreen` reads ("… passes it to RecordingExclusion.make( with
  panelWindowID: nil", "… and to RecordingChoice("): the row finds the variable's name on the
  line that reads `"include_framejob_windows"`, and since the rename (5f7f1d3) its `let
  includeFrameJob =` is on the line above. `AgentServer+Recording.swift` is not changed by
  CR1a, so both fail the same at `9d0c60e`.

**Deviations.**
- `CameraCapture` sets both frame durations (`activeVideoMinFrameDuration` and
  `activeVideoMaxFrameDuration`) under the lock, `spikeApplyFormat`'s measured reference; the
  spec named the minimum.
- `closeCameraSegment` and `CameraSession`'s two index lookups live in `+CameraFinishing`, so
  `+Camera` stays under 400 lines.
- A dropped (frameless) segment's microphone file, if any, is left on disk unnamed; a left-out
  segment's readable voice is probed and kept for its slot, as the screen machine does (#181
  item 2).
- The warm-up (the ruling): the spec's start armed segment 0 when `capture.start` completed;
  that completion now waits for a steady stream. G6, V17 and `no-hold` are rows and a mutant
  the spec did not list. `step 2`'s `rule_sha256` is CAM-3's text before its warm-up bullet;
  the spike was not re-run for the amendment, which does not touch what the spike measures.
- The probe's sections run under `TZ=UTC` (V7's fixed stem), so the granted recordings'
  names are UTC times.

**Owed.**
- CR1c: the panel's countdown starts the camera's session, so the warm-up is spent there.
- `recording_probe.py`'s two X4 `recordScreen` rows, failing since the rename: #371.
- The review's four nits (the frame durations after `startRunning`, `no-hold`'s thin margin
  in G3, a stopped segment's discarded first stamp, segment 0's elapsed before its first
  buffer): #372.
- Applied with the commit (the orchestrator's): `app/CLAUDE.md`'s Recording family gains
  `+Camera`, `+CameraFinishing`, `CameraDevices.swift`, `CameraCapture.swift`,
  `RecordingSetup+Camera.swift` and the camera's sentence; its Hygiene seams list gains
  `CameraCapture`'s two queues (`sessionQueue` for `startRunning`/`stopRunning`,
  `sampleQueue` the data output's delegate queue and the only one that touches the armed
  writer and the warm-up).

## CR1b — the tool

### Record

**Landed** (2026-10-26).
- Spec §11 CAM-4, written before any code: `camera` (a `uniqueID` or a name in any case,
  trimmed, blank or null absent, absent the default), `camera` refused with `screen` or
  `voice_over` right after `source`, the seven arguments a camera refuses, the default
  microphone, the span from segment 0's first buffer, the `camera` answer key, the status item.
  Its index row and the `camera-recording.md` row (144 → 170 lines); the `11-decisions/` cell
  is 13101 in 31 files.
- New: `AgentServer+RecordingCamera.swift` (116 lines: `cameraRefusedArguments`,
  `recordingCameraArgument`, `recordingCameraStrangers`, the pure `recordingCameraID` — CAM-3
  (7), then (8) — `recordingCamera`'s one `onMain` hop over `CameraDevices.connected()`'s
  facts, `systemPreferredCamera` and `RecordingGrant.cameraStatus`, and `cameraFields`).
- Changed: `AgentServer+RecordingArguments.swift` (182 → 187: `RecordingSourceKind.camera`,
  `recordingCameraStrangers` called after `source`'s value; the voice-over's `strangers` line
  byte-identical); `AgentServer+Recording.swift` (375 → 393: `let screen`, the screen-only
  reads defaulted for a camera, the camera lookup and grant after `project`, `camera:` in the
  choice, `record`'s three starts, `awaitVoiceOverDidStart` renamed `awaitFirstStart`, the
  header's order sentence); `AgentServer+RecordingResult.swift` (379 → 387: `camera` in
  `recordingFields`, the camera's `problem` and `note` last in `resultNotes`);
  `AgentCatalog+Recording.swift` (273 → 317: the hoisted `recordingCameraClause`, the `camera`
  property, `source`'s, `rate`'s and the REFUSAL ORDER's sentences, `stopped_by`'s
  `system_stopped`, the Camera grant in THE GRANTS). `record_screen` stays withheld from the
  assistant and the tool count is unchanged.
- #372: item 1, `CameraCapture.start` re-applies the format and both frame durations whenever
  the session runs (399 → 399); item 3, `onSegmentStarted` keeps a stopped segment's first
  stamp; item 4, `openCameraSegment(named:in:)` mints each segment's `calledAt` now, still named
  by the session's call time, so segment 0's elapsed starts at its mint
  (`ScreenRecorder+Camera.swift` 396 → 398); item 2, G6 requires a steady warm-up to have seen
  `WARM_UP_RUN` + 1 buffers and `no-hold` is aimed at G6.
- #371: `recording_probe.py`'s X4 reads the variable's name from the whole `let` statement,
  from its `let` line through the line that reads `"include_framejob_windows"`.
- Proofs: `tools/proof/camera_recording_proof.py` (new, headless and granted tiers);
  `camera_recording_probe.py` and `.swift` gain the `tool` section (T1–T6) and five mutants;
  `recording_probe.py` (D10's vocabulary sentence, 7c's arguments, X4's name read, its
  docstring) and `recording_proof.py` (`RECORD_PROPERTIES`, "thirteen", `source`'s enum,
  `camera` a string, section 1's `source: "x"` sentence, its docstring) re-aimed.
- Docs: spec §7.9a's `record_screen` paragraph (490 → 499 lines) and §7.4's row 52;
  `docs/guide/screen-recording.md` ("For agents": the `source` and `camera` rows, the camera
  paragraph, the order, `system_stopped`; Limits) and `mcp.md` (the grants line, the
  `record_screen` row); `docs/manual-checks.md` REC-12 (the clap); `tools/proof/README.md`'s
  CR1b section and CR1a's `no-hold` line.

**Measured** (the built-in camera, the default microphone, the terminal's grants):
- `python3 tools/proof/spec_index_proof.py`: 201/201, after CAM-4 and again after §7.9a.
- `make typecheck`: exit 0, the 4 baseline warnings, tsc clean.
- `python3 tools/proof/camera_recording_probe.py --only values,landing,tool`: exit 0, `scores:
  30/30`. Each tool mutant, `--only tool`, exit 1, `scores: 6/7`, caught:
  `camera-strangers-admitted` (T1: one stranger and all seven answered `ok: camera`),
  `camera-elsewhere-admitted` (T2: `camera` with screen answered `ok: screen`),
  `grant-before-lookup` (T3: unknown + denied answered the Camera grant's sentence),
  `camera-key-dropped` (T5: no `camera` keys), `camera-notes-dropped` (T6: 1 clause).
- `python3 tools/proof/recording_probe.py --only voiceover_doors,catalog,exclusion`: exit 0,
  88/88 (D10, 7c and X4's rows among them).
- `make app-debug`, then `camera_recording_proof.py` on the Debug instance: exit 0, 36/36, the
  granted tier run: 2.035 s recorded for a 2 s span, `camera` FaceTime HD Camera at
  `1760x1328@30`, by id and by `FACETIME HD CAMERA` the same camera, `mic_offset` −62.0 ms
  (picture at 1 200 000, voice at 1 240 000), one undo ("Add Recording"), and the new project's
  canvas 1760 × 1328 at [30, 1].
- `make gate`: `gate: PASS 224s` (names 1 s, typecheck 5 s, fmt and lint skipped, test 115 s,
  app 103 s); after this record was written, `gate: PASS 1s` (names alone re-ran).
- `python3 tools/proof/recording_probe.py`: exit 0, `1222/1222 checks passed` (#371: CR1a's
  1220/1222).
- `python3 tools/proof/camera_recording_probe.py`: exit 0, `scores: 37/37`, all checks passed;
  G3 59/0.9992 and 59/0.9992; G4 micOffset −0.103 and −0.141 s; G6 hold 0.533 s, 13 buffers,
  steady, intervals 33.4, 33.3, then five at about 43.3 ms, then 33.4 ms; the call to
  `.recording` 1.979 s.
- `python3 tools/proof/camera_recording_probe.py --mutant no-hold`: exit 1, `scores: 7/8`,
  caught by G6 (hold 0.082 s, 1 buffer). G3 PASSED in that run (58/0.9839 on segment 0), the
  thin margin #372 item 2 named: G3 alone would have reported the mutant as survived.
- Release (`proof_app.py launch --app release`, after the gate's `make app`):
  `RC_PROOF_APP=release python3 tools/proof/camera_recording_proof.py <dir>/agent.sock`: exit
  0, 36/36, the granted tier run (2.035 s; `mic_offset` −62.2 ms; canvas 1760 × 1328 at
  [30, 1]). `RC_PROOF_APP=release python3 tools/proof/recording_proof.py <dir>/agent.sock
  --no-screen --no-microphone`: exit 0, 141/141, sections 5 and 6 skipped by flag (79 checks).
  `grep "Frame Job: " <dir>/framejob.log`: nothing. The instance was stopped by its pid.

**Deviations.**
- `recordingCameraStrangers` reads `camera` through `recordingCameraArgument` for every
  source, so a `camera` that is not a string is refused by type ("camera must be a string.")
  right after `source`, before any grant; CAM-4 says nothing of a wrong type.
- `recordingFields`' camera key is an `if let` block of three lines rather than one line.
- The probe's tables carry rows beyond the spec's list: T1 a camera named; T2 a null camera
  with voice_over; T3 an unknown name against an empty list and the default with `restricted`;
  T5 also `has_audio` false and `stopped_by` system_stopped.
- `camera_recording_proof.py` checks that the refusals left `get_project` byte-identical, and
  that they pushed no undo step, once over the whole refusal section, not after each call.

**Owed.**
- Applied with the commit (the orchestrator's): `app/CLAUDE.md`'s Recording family gains
  `AgentServer+RecordingCamera.swift` (the tool's camera: its arguments, lookup, grant and
  answer).
- #371 and #372 are closed by this phase's commit.
- REC-12 (the clap), the owner's.
- CR1c: the panel's Camera source, its grant ask, the warm-up in the countdown, the microphone
  choice.

## CR1c — the panel's Camera source

### Record

## CR2 — the preview and the formats

### Record

## CR3 — camera + screen

### Record

## CR4 — the close

### Record
