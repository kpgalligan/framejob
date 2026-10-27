# Camera recording: a camera alone, or beside the screen (road map "camera-recording")

- **Status:** Built and closed 2026-10-27, from the owner's brief of 2026-10-26. Each phase was one litecode pipeline with its own review, worked in `~/devel/framejob-camera` on branch `camera-recording` (from `4855e70`), and gated, committed and merged into main alone. CR0 was a spike judged by a rule fixed before its run, and the three tolls were pure-move phases landed alone:
  - CR0, the spike, CAM-1 and CAM-2 (`2eb8b80`)
  - CR1-0, the tolls: `AgentCatalog+Recording.swift`, `RecorderPanelController+Showing.swift` (`9d0c60e`)
  - CR1a, the camera recorder, CAM-3 (`7d4f0ee`)
  - CR1b, the tool, CAM-4, #371 and #372 (`150ab81`)
  - CR1c, the panel's Camera source, CAM-5 (`d6393e3`)
  - CR2-0, the tolls: `CameraCapture+WarmUp.swift`, `ScreenRecorder+CameraSession.swift` (`11879f0`)
  - CR2a, the formats, CAM-6 (`80b36c0`)
  - CR2b, the preview and #373, CAM-7 (`d82636d`)
  - CR2c, hot-plug, CAM-8 (`8edf73d`)
  - CR3-0, the tolls: five recorder, landing and tool files (`643a295`)
  - CR3a, the recorder: a camera beside the screen, CAM-9 (`7b8786b`)
  - CR3b, the landing and the tool, CAM-10 (`aa635f9`)
  - CR3c, the panel's camera row, CAM-11 (`d7c70ea`)
  - The close, CR4: this record (the commit that moved the original to `archive/`)
- **Original:** `archive/camera-recording.md` is the full record. It has no section numbers, so it is cited by its own headings: "orig CR2b" is its "CR2b — the preview and #373" section, and "orig Phases" its "Phases" list.
- **Spec decisions:** CAM-1..CAM-11 in spec §11: CAM-1…CAM-6 in `designs/spec/11-decisions/camera-recording.md`, CAM-7…CAM-11 in `camera-recording-2.md` (split at the close by the spec's ~500-line rule). They stay binding, and where the original words them differently, §11's text wins:
  - CAM-1: camera recording is IN and callouts stay OUT (the owner, 2026-10-26), with the owner's four answers: a camera alone or beside a screen recording, the one recorder panel, built-in, USB/UVC and Continuity cameras with a preview and a format choice, the chosen microphone in its own file.
  - CAM-2: the spike's rule, fixed before its run and pinned by `rule_sha256`: the writer, the screen start's estimator, black frames, the Continuity key, the camera entitlement, the best format.
  - CAM-3: the camera recorder's rules: the best format the largest LANDSCAPE area at ≥ 30 fps, step 2's criterion, the microphone's offset by `startPTS` on the host clock, the camera entitlement added, the files, the warm-up hold, a camera that stops on its own ending the recording and a microphone that stops on its own not, the tool's refusal order, the canvas.
  - CAM-4: `record_screen`'s `camera` (a `uniqueID` or a name in any case), refused with another source, the seven arguments a camera refuses, the default microphone, the span from the first buffer, the `camera` answer key.
  - CAM-5: the panel's Camera source: the Source row and the Camera popup, the controls a camera greys, the press and the Camera grant, the warm-up spent in the countdown, the panel kept up, the meter, the landing note's camera sentences.
  - CAM-6: the camera's formats: the Format popup's rows (a format's lower rates are not rows), its key and live rule, the fallback to Best, the size note, the Continuity Camera title, `camera_format`.
  - CAM-7: the preview and #373: the well under Format on the prepared capture, the step rule, one shared session queue holding the configuration lock, a tool start never adopting, a thrown prepare remembered.
  - CAM-8: hot-plug: the device observers from `show()` to close, a change pending until idle, the popups compared before any rebuild, the selection rule, no key written, connected devices only.
  - CAM-9: a camera beside the screen in the recorder: the start's order, the warm-up before the stream, E2 from a `.screen` frame watch, the offset, the `(Camera).mov` files, pause and resume in step with the watch off the stream for a resume's add, a camera failure never the recording's, the finishing and the result's fields.
  - CAM-10: a camera beside the screen lands, and `record_screen` records it: one front Camera track, the time rule and the shared head trim, the bottom-right corner, one grouped edit and its undo names, the tool's admission and order, the per-segment answer keys, the stop wait's third probe, the readers.
  - CAM-11: the panel's "Record the camera too" box, its key `FrameJobRecordingCameraBeside`, the preview and its prepared capture with a screen source, the press's order, the timeout sentence's ceiling the wait's.
  - Amended: recording.md's first bullet and §1's non-goal (by CAM-1); CAM-2's Best format (by CAM-3); CAM-3 (its warm-up bullet, added at CR1a on the orchestrator's ruling before the hold's code); CAM-4 (2) (by CAM-6's sentence, then CAM-10); CAM-5 (2)'s hot-plug clause (by CAM-7, then CAM-8); CAM-5 (3)'s size note (by CAM-6); CAM-5 (5)'s countdown build (by CAM-7); CAM-5 (2), CAM-6 (2), CAM-7 (1) and (3) (by CAM-11); CAM-6 (6) (by CAM-10); CAM-9 (6) (at CR3a, before its fix, on the measured STOP); CAM-9 (10) (by CAM-10); CAM-10 (7) and (9) (by CAM-11).

## Context

Spec §1 and §11's recording.md (road map 3) kept camera recording out. On 2026-10-26 the owner reversed that for the camera ("We should add the option to record a feed from a camera") and answered four questions: a camera alone or beside a screen recording, each its own file and track, the camera above the screen as a movable corner picture-in-picture; the existing recorder panel as the one door; built-in, USB/UVC and Continuity cameras, a live preview and a format choice; and the chosen microphone as its own file. Road map 3's decisions carried over unless a phase measured otherwise: a recording is ordinary media, files go in `~/Movies/Frame Job Recordings/`, the panel asks for grants and the tool never does, a pause is a sequence of files, one grouped edit lands everything, and every door has an MCP mirror. The precedent of `source: "voice_over"` made the camera an argument of `record_screen`, not a new tool. (orig "Goal", "The owner's choices", "Carried over from road map 3 unless a phase measures otherwise", "How it fits the tree (at `4855e70`)")

## Decisions

- **The writer is `AVAssetWriter` fed by a data output, not the movie output (CAM-2, CR0).** At 1552 × 1552 (W2) and 1920 × 1080 (W1) alike the movie output wrote 93.2 % of span × rate with 12 gaps per file at 27.94 fps and took 1008–1044 ms to start or resume; the writer (W3) wrote 99.9 % with no gap, started in 10–14 ms and resumed in 5–26 ms (P2). On macOS a session keeps a requested format only while the device's configuration lock is held from before `startRunning` to after `stopRunning` (there is no `.inputPriority` preset), so every format is set under the lock, and set again once the session runs. (orig CR0 "Decides")
- **The best format is the largest LANDSCAPE area (CAM-3).** CAM-2's rule picked the built-in camera's square 1552 × 1552, so CAM-3 applies it to the formats wider than tall: 1760 × 1328 @ 30 on the FaceTime HD Camera, 1920 × 1440 @ 60 on the iPhone, 1920 × 1080 @ 60 on OBS Virtual Camera. Step 2 measured the writer there first: W3 0.9993 in every run, P2's median resume 15.16 ms. (orig CR1a)
- **A camera recording starts on a warm stream (CAM-3's warm-up).** A cold camera's first intervals ran 33.3, 33.3, then five at 43.3 ms, which left segment 0 at 0.975 of span × rate in every run while a resumed segment read 0.999. So segment 0's writer is armed only after five consecutive intervals within 15 % of the frame duration, bounded at 1 s, with `camera.note` past the bound (G6: a hold of about 0.53 s, 13 buffers). The panel spends it in the countdown (`prepareCamera`, CAM-5): G7's adopted start answered in 0.036 s against a cold 1.943–1.962 s. The tool never prepares or adopts, so it still pays the hold (CAM-7 (7)). (orig CR1a, CR1c)
- **The entitlement is added though the spike found it not needed (CAM-3).** CR0's T2, a hardened binary without `com.apple.security.device.camera`, delivered frames, but under the terminal's grant; road map 3 found the signed app needed the microphone's entitlement where a bare probe did not, so the camera follows that finding, and `NSCameraUsageDescription` and the dist checks' exact sets carry it. No Continuity key: CR0's D2 lists the iPhone without it, as `AVCaptureDeviceTypeExternal` with `isContinuityCamera` true, which the SDK note had said otherwise. (orig CR0 "Decides", CR1a)
- **The microphone is placed by `startPTS` on the host clock (CAM-3).** The two offsets, by `startPTS` and by callbacks, differ by about 63 ms with the writer (P2) and by 210–241 ms with the movie output. Only a person's clap (REC-12) measures the truth. The tool's `mic_offset` read −59.9 to −80.1 ms across the Release runs. The screen recorder's own microphone, placed by callbacks, is #370. (orig CR0, CR1b–CR2c)
- **One shared session queue fixes #373 (CAM-7).** A fresh capture built in the same main turn as the stop of another capture of its device recorded no frame (CR1c's `prepare-ignored`; CR2b's `session-queue-per-capture` mutant reproduced it: fresh starts at 1.035 and 1.037 s, "The camera delivered no frame."). Every capture's lock, format, `startRunning` and `stopRunning` now run on one serial queue, and `stop(completion:)` answers on main after the stop ran (G8: the completion at 0.070 s, the session's did-stop before it). The preview's layer is made with the prepared capture, never on a session of its own. (orig CR2b)
- **The screen's start is E2, and the frame watch comes off the stream for a resume (CAM-9).** CR0's re-run on the final instrument found E1 (the did-start's arrival) past the 16.7 ms bound in 4 of 8 runs (−19.9 to −21.0 ms) while E2, the first complete `.screen` frame at or after it, read +0.49 ms in all 16. CR3a first left the watch on through a resume: every resumed segment's `SCRecordingOutput` failed "to process first sample buffer" in 4 of 4 runs. The orchestrator ruled for removing the watch before the resume's `addRecordingOutput` and adding it back after, and CAM-9 (6) recorded it before the fix; then 4 of 4 runs passed with E2 − E1 1.7–22.3 ms. A re-add that throws costs that segment's E2 alone, named in its `cameraNote`. (orig CR0, CR3a)
- **The camera begins before the screen, so the head trim is the usual path (CAM-10).** Started in one run-loop turn, the writer's camera began 87–130 ms before the screen file in CR0, and every `cameraOffset` in CR3a's G16 was negative (−0.032 to −0.146 s). So each camera clip is asked at its screen clip's start plus its offset, floored there and at the previous camera clip's end, and head-trimmed by the microphone's shared dance (`headTrimmed`), not a copy. (orig CR3a, CR3b)
- **The corner is fixed (CAM-10 (3)).** A box a quarter of the canvas wide and a third tall, inside the 90 % ring of View ▸ Safe Areas, by one `set_video {x, y, scale}`, and the clip stays an ordinary clip to move. L5 read 1760 × 1328 → (625, 306, 0.27108) on a 1920 × 1080 canvas. The ring is named by its percentage because spec §4.1 calls the 90 % ring title-safe. (orig CR3b)
- **The box is a control of its own (CAM-11).** "Record the camera too" under Include Frame Job windows, live only with a display or the Window row, persisted in `FrameJobRecordingCameraBeside`. An "Off" row in the Camera popup was not chosen: it would change what the shared camera key means for Source Camera and for hot-plug. The press reads Screen Recording, then Camera, then Microphone. (orig CR3c)
- **Hot-plug never writes a key (CAM-8).** The popups follow the devices while the panel is up and idle, a list compared before it is rebuilt, a returning camera chosen again with its format; a change made during a recording waits for idle. (orig CR2c)

## What it built — where it lives now

- Swift, new: `CameraDevices.swift` (the list, facts, lookup, default, best format, format rows and sentences), `CameraCapture.swift` and `CameraCapture+WarmUp.swift` (the session, the lock on the shared queue, the data output, one writer per segment, the preview layer, the warm-up), `ScreenRecorder+Camera.swift`, `+CameraSession.swift`, `+CameraFinishing.swift` and `+CameraPrepare.swift` (a camera alone; the countdown's prepared capture), `ScreenRecorder+CameraBeside.swift`, `+CameraBesideFinishing.swift` and `ScreenFrameWatch.swift` (a camera beside the screen), `RecordingSetup+Camera.swift`, `RecordingLanding+Camera.swift` (the front Camera track, the time rule, the corner), `AgentServer+RecordingCamera.swift` (the tool's camera arguments, lookup, grant and answer), `RecorderPanelController+Camera.swift`, `+CameraPreview.swift`, `+Devices.swift` and `CameraPreviewWell.swift`.
- Swift, new by pure moves (the tolls; `designs/adr/app-file-history.md` "Recording"): `AgentCatalog+Recording.swift` and `RecorderPanelController+Showing.swift` (CR1-0), `CameraCapture+WarmUp.swift` and `ScreenRecorder+CameraSession.swift` (CR2-0), `ScreenRecorder+Stop.swift`, `RecordingLanding+Placement.swift`, `RecordingLanding+Remainder.swift`, `AgentServer+RecordingLanding.swift` and `AgentServer+RecordingSentences.swift` (CR3-0).
- Swift, changed: `ScreenRecorder.swift`, `+Pause`, `+Delegates`, `+Finishing`, `+Content`, `+VoiceOver`, `+Microphone`; `RecordingSetup.swift` (`RecordingSource.camera`, `RecordingChoice.camera` and `cameraFormat`, `cameraPaneURL`), `RecordingResult.swift` (`RecordingCamera`, the segments' camera fields, `filesClause`, `cameraSegmentsNote`); `RecordingLanding.swift`, `+Placement`, `+Remainder`, `+Microphone`; `ProjectDocument+Recording.swift`'s doc; `AgentServer+Recording.swift`, `+RecordingArguments`, `+RecordingResult`, `+RecordingSentences`; `AgentCatalog+Recording.swift`; `RecorderPanelController.swift`, `+Rows`, `+Grants`, `+Recording`, `+VoiceOver`, `+Landing`, `+Pause`, `+Showing`.
- The build: `project.yml`'s `NSCameraUsageDescription` and `com.apple.security.device.camera`; the camera in every exact entitlement set (`dist_check.py` D14, D25, `published_check.py` P5, `gate.py`, the Makefile's comments).
- The panel's remembered keys went from seven to ten: `FrameJobRecordingCamera`, `FrameJobRecordingCameraFormat`, `FrameJobRecordingCameraBeside`, pinned in `harness/main.swift` and `screens.py`.
- No op, no FFI export, no core or model change and no format bump: a recording stays ordinary media. `record_screen` gained `source: "camera"`, `camera` and `camera_format`; the tool count is unchanged, and it stays withheld from the assistant.
- Proofs: `tools/proof/camera_spike/` (`camera_spike.py`, `camera_spike_probe.swift`, its `README.md`; CR0, and step 2's `--format` at CR1a); `tools/proof/camera_recording_probe.py` and `.swift` (values V1–V22, landing L1–L9, tool T1–T11, panel P1–P23, beside B1–B7, granted G0–G15, screen G16–G17; 81 mutants at the close); `tools/proof/camera_recording_proof.py` (headless and granted tiers over MCP, section D's `snapshot_ui` of the panel); `recording_probe.py` (78 mutants) and `recording_proof.py` re-aimed; `tools/proof/README.md`'s CR0–CR3c sections; `screens.py`'s recorder screen (`designs/screens/16-recorder-panel.md`).
- Documents: spec §1 and recording.md's first bullet (amended by CAM-1), §7.4's rows 50–52, §7.9d (`record_screen`, moved out of §7.9a at the close), §11 `camera-recording.md` and `camera-recording-2.md`; `docs/guide/screen-recording.md`, `mcp.md`, `menus-and-shortcuts.md`'s New Recording… row, the guide index's row and the README's Screen recording highlight.
- Person checks, in `docs/manual-checks.md`: REC-12 (a camera recording's voice lined up with its picture, a clap), REC-13 (the Camera prompt from the app itself), REC-14 (a camera recording from the panel), REC-15 (the preview's look), REC-16 (an iPhone as a Continuity Camera), REC-17 (a camera plugged in and taken away while the panel is up), REC-18 (a camera beside the screen from the panel, a talking head lined up).

**Headline numbers** (Mac14,6, macOS 26.5.1; the FaceTime HD Camera, the default microphone and the terminal's grants; nothing spent).

| Measure | Measured | Command |
|---|---|---|
| The spike (CR0) | VERDICT `writer=asset-writer screen_start=E2 continuity_key=not-needed camera_entitlement=not-needed`; W3 99.9 % against the movie output's 93.2 %; E2 +0.49 ms in 16 of 16 S runs, E1 past 16.7 ms in 4 of 8; the preview about 155–160 MB of RSS | `camera_spike.py --ask`, then `--groups write,pause` and `--groups screen,preview` |
| The writer at the landscape best (CR1a) | W3 0.9993 ×3 at 1760 × 1328, P2's median resume 15.16 ms | `camera_spike.py --groups write,pause --camera FaceTime --format 1760x1328` |
| The warm-up (CR1a, CR1c) | cold segment 0 0.975 of span × rate; warm 0.9992; G6 hold 0.523–0.598 s, 13 buffers; G7 adopted start 0.03–0.063 s; G9 joined start 0.687–0.728 s | `camera_recording_probe.py --only granted` |
| #373 (CR2b) | `session-queue-per-capture`: fresh starts 1.035 and 1.037 s, no frame; the fix: G12 0.768–0.775 s, G14 0.764–0.768 s, frames 0.9991–0.9992; G8's completion 0.070–0.090 s, the did-stop before it | `camera_recording_probe.py --only granted` |
| A camera beside the screen (CR3a–CR3c) | G16 E2 − E1 1.7–22.6 ms, `cameraOffset` −0.032 to −0.179 s, frames 0.9992; the Release tool's `camera_offset` −161.5 ms (CR3b) and −170.4 ms (CR3c) | `camera_recording_probe.py --only screen`; `RC_PROOF_APP=release camera_recording_proof.py` |
| The final runs (CR3c) | `camera_recording_probe.py` 98/98, G0–G17 all run, in 62 s; `recording_probe.py` 1222/1222 in 152 s; Release `camera_recording_proof.py` 61/61; Release `recording_proof.py --no-screen --no-microphone` 142/142; Release `screens.py --only 16-recorder-panel` 6 pass of 6; `make gate` PASS 223 s | as named |

Mutants, each run on the final instrument and each caught: CR0 five (the spike's), CR1-0 two re-aimed, CR1a seven, CR1b five and `no-hold` re-aimed at G6, CR1c ten, CR2-0 `no-hold` re-aimed, CR2a ten and two re-aimed, CR2b eleven, CR2c nine, CR3-0 three re-aimed, CR3a twelve, CR3b eight and two re-aimed, CR3c nine and two re-aimed. Every phase passed `make gate`; CR1b, CR1c, CR2a, CR2b, CR2c, CR3b and CR3c each ran `camera_recording_proof.py` whole on Release, and CR3-0 and CR3a ran `recording_proof.py` there.

## Known limits

- **One rate per format** (CAM-6): a camera records at a format's highest frame rate; a lower rate within the format's range is not offered.
- **The corner is fixed** (CAM-10 (3)): the bottom-right corner, a quarter wide and a third tall inside the 90 % ring, with no control for another corner, scale or inset; the clip is moved by hand afterwards.
- **A left-out segment's camera is kept, never landed** (CAM-10 (2)): its screen movie would not read, so its camera file stays on disk, named in `kept_files` and the note, and only its microphone takes the slot.
- **The watch's remove is at the resume, not the pause** (CAM-9 (6)): a remove at the pause was not measured, and the pause leaves the watch on the stream as measured. One run in which only the re-add was kept, without the remove, also passed. The re-add's throw is structural only: on a never-started stream no faked add throws, so B7 sets `watchFailure` by hand.
- **The camera offset's spread**: the Release tool runs read −161.5 and −170.4 ms, past CR3a's 32–146 ms and within G16's 0.5 s bound, one run each.
- **A tool start pays the warm-up** (CAM-7 (7)): it never adopts the panel's prepared capture, so it builds its own (about 0.77 s in G12 and G14), and the panel's preview reads "The camera is recording." meanwhile.
- **The microphone's truth is a person's**: the offset by `startPTS` and the offset by callbacks differ by about 63 ms with the writer; REC-12's clap is the measurement.
- **A virtual camera**: OBS Virtual Camera delivered frames with OBS running (X1); without its host app it is not measured. No spike row recorded from the iPhone; its pairing is REC-16.
- **Synthetic and host fixtures only**: the granted tiers run on this Mac's cameras under the terminal's grants and skip by name without them; the look, framing and lining up are REC-12..REC-18.

## Open items

- #370: open. The screen recorder places its own microphone file by callback arrival, which can differ from the `startPTS` offset by more than a frame (CR0's M2 and P2); filed at CR0 and outside this road map's work.
- #371 and #372: closed on push by CR1b's `Closes` lines (`150ab81`).
- #373: fixed by CR2b (`d82636d`), whose message named it but did not close it; closed by the close's commit.
- Nothing new is known to be unfinished, so no issue was filed at the close.

Not filed, each decided:
- CAM-6's one rate per format, CAM-10's fixed corner and a left-out segment's camera not landed: decided limits, recorded in §11.
- CR3a's remove at the pause instead of at the resume: unmeasured, and the ruling kept the pause as measured.
- CR3a's review nits not acted on: `+Pause`'s remove and re-add lines past ~100 columns (wrapping them would move `resume-keeps-watch`'s anchors), and `nextMovieURL`'s camera clause going through `uniqueURL`, as the microphone's does, so it never matches a held file.
- CR1c's review nit: `cameraAnswered` does not re-check that Source is still Camera, as `microphoneAnswered` does not; the recorder's own refusal catches a switched source.

## Where to look in the original

- "Goal" and "The owner's choices": the brief's four binding answers of 2026-10-26.
- "Carried over from road map 3 unless a phase measures otherwise": what stood unless measured.
- "How it fits the tree (at `4855e70`)": the recorder, values, landing, chrome, tool, build, proofs, SDK and host the phases started from.
- "Phases": what each phase was to build, including how CR1, CR2 and CR3 were each split as the earlier phase landed, and CR4's preface.
- "CR0 — the spike": the run, the re-runs on the final instrument under the configuration lock, the full row table (H0–X1), Q0, the VERDICT lines and "Decides".
- "CR1-0 — the tolls": the two moves, the sizes and the catalog compared before and after.
- "CR1a — the camera recorder": the STOP on G3 and the warm-up ruling, step 2's run, the cold start's intervals and the seven mutants.
- "CR1b — the tool": CAM-4, #371 and #372, the five tool mutants and `no-hold`'s thin G3 margin.
- "CR1c — the panel's Camera source": CAM-5, the panel kept up, G7–G9, the ten mutants, and #373 found.
- "CR2-0 — the tolls": the two moves and G8's question under `no-hold`.
- "CR2a — the formats": CAM-6's rows, V18's order, G10 at 1920 × 1080 and the ten mutants.
- "CR2b — the preview and #373": the shared queue, G8 on the completion, G11–G15, the eleven mutants and CR2-0's question answered.
- "CR2c — hot-plug": CAM-8, P16a–e, P17, P18 and the nine mutants.
- "CR3-0 — the tolls": the five moves and the byte-identity check.
- "CR3a — the recorder: a camera beside the screen": the STOP on G16 and CAM-9 (6)'s amendment, the E2 and offset rows, the twelve mutants and how `resume-keeps-watch` was settled.
- "CR3b — the landing and the tool": CAM-10, the ops L4 lists, the corner's numbers, the eight mutants and the review's ceiling nit.
- "CR3c — the panel's camera row": CAM-11, P20–P23, G17, the nine mutants and the final Release runs.
- "CR4 — the close": this record's landing, the read-back, the moves and the gate.
