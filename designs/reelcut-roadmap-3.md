# Reelcut — road map 3: recording

**Status: BUILT, reviewed and fixed (2026-09-11).** The sections below
are the plan as it was written, kept as written; "R0 — the answers" and
"What R0 and the scouts change in R1" override them, and "R1 — the record"
says what landed and what the review found. Road map 2 is complete
(`reelcut-roadmap-2.md` §1) and `reelcut-remaining.md` §5 says a third road
map starts at road map 2's §4, "Considered and left out". This is the plan
for the first thing taken off that list: **screen recording**, the feature
spec §1 named a non-goal on day one. It is sized for **two to three sessions
plus a half-session spike**, one phase, closable on its own and ending in
evidence.

Companion relations, unchanged: `reelcut-design.md` stays normative for the
schemas (§5), the op table (§6) and the architecture (§7); **this phase adds
no op, no field and no FFI export**, so §5, §6 and the header do not move.
What it amends is §1 (the non-goal), §3 (the welcome window), §7.4 (the
Swift file map), §7.9 (the tool list), §9 (one key) and §11 (five
decisions, written below so they are made before the code and not by it).
`CLAUDE.md` holds the milestone status; its paragraph for this phase is
written when the proof exists. Every fact below that was read off the tree
carries its file and line, and every fact that was read off a header is
marked so; **the scouts verify both, they do not trust them** — the road map
2 record shows the plan overturned by the code in every phase.

## 0. What this reverses, and the decisions to record first

Spec §1: "Deliberate non-goals: screen or camera recording, multicam …".
Spec §2 drops from a screencast editor "everything that only makes sense for a
recording it made itself (mouse/keyboard/touch callouts, pointer effects)".
Road map 1 §4 and road map 2 §4 repeat the exclusion; road map 2 §4 puts
microphone capture "on the boundary" and calls it the user's decision.

The decision this road map records: **screen recording is IN; camera
recording and callouts stay OUT.** The line is drawn there because a screen
recording is the input the whole product was shaped around (spec §1's first
sentence is "a screencast editor's editor without a screencast editor's recorder"; phase 3 of
road map 2 is "the screencast trio"), while camera capture is a second
capture stack and callouts are a metadata format plus an Input Monitoring
grant. What ScreenCaptureKit draws into the pixels for free — the cursor,
and on macOS 15 a circle around each click — is taken; nothing is
reconstructed after the fact.

Five §11 entries to write BEFORE the phase's first line of code, each one a
decision the code would otherwise make silently:

1. **A recording is ordinary media.** It is a file the recorder wrote and
   then imported through exactly the path File ▸ Open and Add Media… use
   (`ProjectDocument.readMediaFile`, `ProjectDocument.swift:566`;
   `ProjectDocument.importMedia`, `:940`). The model learns nothing about
   recordings: no source kind, no flag, no schema bump. A recording clip is
   a media clip and every op, cache and export treats it as one.
2. **The file lives in `~/Movies/Reelcut Recordings/`**, named by date and
   time, never in the package and never in the temporary directory. Media is
   referenced, not copied (§11, "Media is referenced"); an untitled
   document has no package (§5.6, Consolidate's first rule); a recording is
   ORIGINAL footage, so the temporary directory — where a cache is
   regenerable and media would be lost (§5.6 again) — is the one place it
   may not go. Consolidate Media carries it into the package on the same
   terms as any other file. The folder is created on demand; a
   `-RCRecordingFolder` launch argument overrides it, `-RCFFmpegPath`'s
   shape, so a proof can record into `tools/proof/work/` and delete it.
3. **The canvas takes the recorder's RATE, the media record takes the
   file's.** ScreenCaptureKit delivers a frame only when the screen changes,
   so its files are variable-rate and `MediaImporter.rationalFrameRate`
   (`MediaImporter.swift:310`) will honestly report something like
   47300/1000, which `readMediaFile`'s `makeProject(around:)` would then
   make the timeline's grid. The media entry keeps the honest number, as a
   later `import_media` of the same file would; the untitled document is
   built at 30 or 60, whichever the panel asked for, because that is the
   grid the person chose. `set_canvas` is NOT used for this after the fact:
   an untitled document's first project is not an undo step, and the rate
   is part of what the document IS.
4. **The panel asks for the grants; the tool never does.** `Transcriber`'s
   rule (`Transcriber.swift:389`, `canAsk`), restated for two grants:
   Screen Recording (`CGPreflightScreenCaptureAccess()` is the synchronous
   read, `CGRequestScreenCaptureAccess()` the ask — both `CGWindow.h`,
   macOS 10.15) and Microphone (`AVCaptureDevice.authorizationStatus(for:
   .audio)` and `requestAccess`). `record_screen` reads the status and
   refuses by name with the fix in the sentence.
5. **Microphone and system audio are two sources and stay two sources.**
   Whether they land as two tracks of one file or as two files is R0's
   question 2; the decision that does not wait on it is that the mix is
   never folded into one track by the recorder, because a voiceover the
   editor cannot separate from the application's own sound is the one thing
   a screencast cutter cannot repair afterwards.

One more that is a limit rather than a decision: **undo of "Add Recording"
removes the media and the clip and leaves the file on disk**, exactly as
undoing Add Media… does. A recorder that deleted footage on ⌘Z would be the
only destructive undo in the app.

Two more, recorded for R2 (2026-09-12) before its first line of code — the
first forced by the framework, the second asked for by the user:

6. **A paused recording is a SEQUENCE of files over ONE stream.**
   ScreenCaptureKit has no pause: `SCStream` and `SCRecordingOutput` carry
   none, and the header's only lever is `removeRecordingOutput` ("Stops
   Recording if the stream is currently recording") beside
   `addRecordingOutput` ("Starts Recording if stream is already capturing").
   R0's question 7 measured that pair on a running stream (below), so a
   pause REMOVES the recording output — its file closes — and a resume ADDS
   a fresh one to a new file while the stream keeps capturing; the
   microphone's writer is stopped and restarted per segment on its one
   running session. Each segment is named by ITS OWN start time
   (`RecordingFiles.stem(at:)` at the resume), is a `(movie, mic)` pair with
   its own measured offset, and lands as a clip placed at the previous
   segment's end — so a paused recording is `n` ordinary media files and
   `n` touching clips, and the model still learns nothing (decision 1). No
   post-processing joins them (§5's rule: the cutter trims and joins).
7. **The panel goes away when the recording starts, for EVERY source, and
   comes back only with something to say.** R1 kept the panel on screen for
   a display recording (the programmatic filter excludes Reelcut) and hid
   it for a picked window; the user asked for the dialog to go away when a
   recording starts and for the menu bar's item to be the recording's
   controls — Pause Recording and Stop Recording, then Resume Recording and
   Stop Recording while paused. So the status item is the recording's whole
   chrome, the panel orders out at `recordingDidStart` whatever the source,
   and after the landing it returns ONLY when the landing's note is
   non-empty (a stop from the menu bar's own indicator, a closed target, a
   microphone problem, a failure) — a clean recording lands in its document
   or opens its new project and the panel stays away. ⌥⌘N shows it again.

## 1. Status

| Phase | Theme | Sessions | Schema | Status |
|---|---|---|---|---|
| R0 | The spike — five questions measured before design leans on them (and a sixth from the scouts) | ½ | — | **done** 2026-09-10; the answers are in §3 |
| R1 | Screen recording | 2–3 | — | **done** 2026-09-11, `a4c476f` (the fix wave's record and the proof scores are in "R1 — the record") |
| R2 | Pause and resume; the panel that goes away | 1 | — | **spiked** 2026-09-12 (R0 q7, outcome A); building — the plan is "Phase R2" below |

R0 comes first and its answers are written into R1's section before R1's
waves are briefed. Two of R1's branches (the audio landing, the panel's
visibility during capture) are written both ways below and R0 picks.

## 2. What the tree already has, read for this phase

Named so the phase builds on it instead of beside it (road map 2 §1's table
is the precedent).

| | |
|---|---|
| `ProjectDocument.readMediaFile` + `makeProject(around:)` (`ProjectDocument.swift:566–600`) | a media file becomes an untitled document sized and rated to it. `makeProject` is `private static`; R1b widens it to internal and gives it an `fps:` override (decision 3). `importSourceURL` is what points the save panel at the file's folder — for a recording that is the Recordings folder, which is right. |
| `ProjectDocument.importMedia` / `commitImport` (`:940–985`) | probe, then ONE grouped edit, then `generateCaches()`; the new ids read off the snapshot. `AgentServer+Media.importMedia` (`AgentServer+Media.swift:25`) is the same shape on the server thread with a semaphore, and documents the id contract: **`add_media`'s new id is `next_id` from before the op**. |
| `EditorViewController.addGeneratedClip` (`EditorViewController+AddClips.swift:52`) | "at the playhead": the front track if the op applies purely, else a new track above everything — one undo step. It is `private`; R1b either widens it or has `RecordingLanding` compute the same two-try op list itself against `editedProject.applying(_:)`. A Finder drop inside a nest is already `add_media` (document-level) plus `add_clip` (scoped) in ONE edit — `ReelOp.documentLevelNames` (app/CLAUDE.md, phase 9) — so "Add Recording" inside an open nest is the same shape. |
| `MediaImporter.probe(url:completion:)` (`MediaImporter.swift:113`) and `probeBlocking` (`:192`) | the descriptor a finished file becomes; completion on MAIN. Rewrap is not involved: the recorder writes `.mov`. |
| `AgentServer.offMainTools` (`AgentServer.swift:103`) and `transcribe` (`AgentServer+Captions.swift:78–110`) | the shape of a tool that waits on a callback-driven framework: off main, `onMain` hops for every document touch, the caller's own mistakes refused ABOVE the grant so they stay reachable on an ungranted machine, the grant read synchronously and named in the refusal. |
| `PreviewWindowController` (`PreviewWindowController.swift`) | the app's first `NSPanel` and the measured reason: a titled `NSWindow` becomes MAIN and every editor selector dies. It is also the delegate for `windowWillReturnUndoManager`. The recorder panel is a panel for the same reason and, unlike the preview, must exist with NO document open. |
| `LevelMeter` / `LevelMeterView` (`LevelMeter.swift:342`, `publish` on MAIN) | the model publishes a raw peak/RMS reading, the view owns the ballistics. A microphone meter feeds the same model from a serial queue through a main hop — NOT the `Synchronization` path, which is confined to the render-thread sink. |
| `FFmpegRewrap.canAsk` / `Transcriber.canAsk` | an agent-driven app (`-AgentServerEnabled YES`) never puts up a system prompt. |
| `harness <welcome> …` (`tools/proof/harness/`) | the welcome window is photographable offscreen, which is how the third button is checked. `build.sh` names no frameworks — Swift auto-links what `app/Sources` imports, and phase 4's `Speech` import already rides it — so `import ScreenCaptureKit` costs the harness nothing. What the harness cannot do is CALL the framework: it is a bare Mach-O with no `Info.plist` (`Transcriber.swift:403`), so the probe builds configurations and never presents a picker or asks for content. |
| `tools/proof/README.md`'s launch line and count rule (`:150–212`) | one instance per port, the parity log empty, and "the EXACT tool count belongs to the newest phase's script" — 74 today, asserted by `phase9_proof.py`; this phase takes 75 and phase 9's becomes a floor. |
| `reelcut-remaining.md` §3, the size ledger | `AgentCatalog.swift` at 807 with its cut named in its own header (the FILE groups to `AgentCatalog+Files.swift`); `ProjectDocument.swift` at 1336, "a pure addition takes the `+DisplayStem` shape"; `AppDelegate.swift` 223 and `AppDelegate+Menus.swift` 499 have room. |

**ScreenCaptureKit, read off the installed SDK (Xcode 26.2, macOS 26.5.1
host, deployment target 15.0 in `project.yml`) — to verify, not to trust:**

- `SCRecordingOutput` / `SCRecordingOutputConfiguration` (`SCRecordingOutput.h`,
  macOS 15.0): `outputURL`, `videoCodecType`, `outputFileType`, a delegate
  with did-start / did-fail / did-finish, `recordedDuration` and
  `recordedFileSize`. `SCStream.addRecordingOutput(_:)` (`SCStream.h:523`):
  ONE per stream, added BEFORE `startCapture` so the first sample lands in
  the file; `stopCapture` without removing it finishes the file; a
  configuration update mid-recording stops it. **This is what makes the
  phase small: no `AVAssetWriter`, no sample-buffer plumbing.**
- Every call the recorder needs has a completion-handler form —
  `startCapture(completionHandler:)`, `stopCapture(completionHandler:)`
  (`SCStream.h:507, 514`), `SCShareableContent.getShareableContent(completionHandler:)`
  (`SCShareableContent.h:146`), `updateConfiguration(_:completionHandler:)`
  — so **the `async` rule stands** (spec §11) with no third named file.
- `SCStreamConfiguration` (`SCStream.h`): `width`/`height`,
  `minimumFrameInterval`, `showsCursor`, **`showMouseClicks` (15.0)**,
  `capturesAudio` (13.0) with `sampleRate`/`channelCount`,
  **`excludesCurrentProcessAudio` (13.0)** — so the timeline can play while
  a recording runs and not be in it — `captureResolution`
  (automatic/best/nominal, 14.0), **`captureMicrophone` and
  `microphoneCaptureDeviceID` (15.0)**, and the third output type
  `.microphone` (15.0).
- `SCContentFilter` (`SCStream.h:146–162`): a window, or a display
  excluding/including windows, or a display including/excluding
  APPLICATIONS excepting windows. `excludingApplications: [Reelcut]` is how
  the programmatic path keeps the recorder's own panel out of the picture.
- `SCContentSharingPicker` (`SCContentSharingPicker.h`, 14.0): a system UI,
  `sharedPicker`, an observer protocol (`didUpdateWithFilter`,
  `didCancelForStream`, `startDidFailWithError`), a configuration with
  `allowedPickerModes`, `excludedBundleIDs`, `excludedWindowIDs`. Whether a
  display filter it hands back honours `excludedBundleIDs` for CAPTURE and
  not only for the listing is R0's question 3.
- `SCStreamDelegate.stream(_:didStopWithError:)` and the error vocabulary
  (`SCError.h`): `userDeclined` −3801, `userStopped` −3817 (the system's
  own menu-bar indicator can stop a capture), `attemptToStartStreamState`
  −3807, `noDisplayList` / `noWindowList`. `streamDidBecomeInactive` is
  15.2 and goes behind `#available`.
- `CompositionBuilder.firstTrack` (`CompositionBuilder.swift:344`) and the
  peaks reader (`MediaImporter.swift:557`) both take a media's FIRST audio
  track. **A file with two audio tracks loses the second silently**, which is
  what makes R0's question 2 a design question and not a curiosity.

## 3. Phases

### Phase R0 — The spike

*Half a session. A tracked script, `tools/proof/recording_spike.py`, that
embeds a Swift probe the way `phase9_probe.py` does, compiles it with
`harness/build.sh`'s `swiftc` line against NOTHING from `app/Sources` (the
spike is before the code), and prints one JSON object. Its numbers are pasted
into R1 below before R1 is briefed, with the date and the host OS. An
untracked spike is the debt `reelcut-remaining.md` §1 paid twice; this one is
tracked from its first run.*

The five questions, each with the two designs it chooses between:

1. **TCC attribution of a shell-launched binary.** Every proof launches
   `Reelcut.app/Contents/MacOS/Reelcut` directly from a shell
   (`tools/proof/README.md:156`); for the Microphone and Screen Recording
   services TCC may attribute that process to the TERMINAL, in which case a
   grant given to Reelcut.app in System Settings does not reach the proof's
   instance and `CGPreflightScreenCaptureAccess()` stays false forever. The
   probe launches the built app both ways — the direct line, and
   `open -a <path> --env RC_AGENT_PORT=<port> --stdout <log> --stderr <log>
   --args -ApplePersistenceIgnoreState YES -AgentServerEnabled YES` (`open`
   has all three flags; measured on this host) — and reads the preflight
   through a one-line MCP tool stub or through `log stream`. **Outcome A:**
   the direct launch is attributed to the bundle and nothing changes.
   **Outcome B:** only `open` is; the README's launch line changes for this
   phase and the parity-log grep reads the `--stderr` file. Either way the
   answer goes into `tools/proof/README.md` beside the launch line.
2. **What `SCRecordingOutput` writes with `capturesAudio` and
   `captureMicrophone` both on** — how many audio tracks, in which order,
   at what layout — and what `MediaImporter.probe` and
   `CompositionBuilder.firstTrack` then make of it. The probe records five
   seconds of a display with a tone playing (`afplay` of a file it writes
   with `say -o`) and the microphone on, then lists the file's tracks with
   `AVURLAsset` and reports `hasAudio` off a probe. **Outcome A (one mixed
   track, or the mic in track 1 and system in track 2 is NOT acceptable
   either — decision 5):** the recorder records the microphone to a SECOND
   file through an `AVCaptureSession` with `AVCaptureAudioFileOutput` (a
   delegate API, macOS-only, `.m4a` or `.wav`), started in the same runloop
   turn as `startCapture`, and lands it as a second clip on a second track;
   the offset between the two files' first samples is measured by the
   spike (a screencast editor keeps them separate for the same reason). **Outcome B
   (two tracks, system first, mic second, or the reverse):** ONE file, and
   the landing puts TWO clips on it — `CompositionBuilder.firstTrack` gains
   a track-index argument threaded from a new `Source::Media` field? NO: that
   is a schema bump the phase does not want. Instead the landing writes the
   mic track out to its own file with `AVAssetExportSession`'s audio-only
   preset at land time, which is a second file again. So both outcomes end
   in two files and the difference is only WHEN the second is written; the
   spike decides which is simpler and whether the mic's start offset is
   measurable. **Outcome C (SCRecordingOutput does not write the mic at
   all):** outcome A's design, forced.
3. **Whether a picker-made display filter excludes the app's own
   windows** when `SCContentSharingPickerConfiguration.excludedBundleIDs`
   names Reelcut. **Outcome A:** it does, and the recorder panel can stay on
   screen with its Stop button, floating and non-activating. **Outcome B:**
   it does not, and the panel orders out for the duration; Stop lives on the
   status item and the File menu. The programmatic path (the tool's) always
   excludes through the filter itself.
4. **The nominal frame rate a recording reports** through
   `MediaImporter.rationalFrameRate` for a 60 and a 30 configuration of a
   mostly-static screen — expected: not 60 and not 30 — which is decision 3's
   evidence, and whether `captureResolution = .nominal` on a Retina display
   gives the display's point size and `.best` its pixel size.
5. **Whether a `.microphone` stream output can be added beside a recording
   output** on one stream (the mic meter's source), and on which queue its
   buffers arrive. **Outcome A:** yes — the meter reads it. **Outcome B:**
   no — the meter lights from the second file's `AVCaptureAudioFileOutput`
   session under question 2's outcome A, or is left out under B and
   recorded in §5.

What the spike does NOT do: present the picker (a system UI needs a person),
or decide anything about the panel's layout.

#### R0 — the answers, measured 2026-09-10

Host: macOS 26.5.1 (25F80), Xcode 26.2, main display 1728×1117 points at
scale 2 (3456×2234 pixels), a second 2560×1440 display at scale 1. The
script is `tools/proof/recording_spike.py` (`python3 tools/proof/recording_spike.py`,
`--only 2,5` for a subset); its record run's JSON is
`tools/proof/work/spike/answers.json`, ignored. Every number below is from
that run unless it says otherwise, and each question runs in its own
subprocess so a crash is a reported outcome.

1. **Outcome B.** The README's direct launch of
   `Reelcut.app/Contents/MacOS/Reelcut` is attributed by TCC to the
   TERMINAL — `responsibility_get_pid_responsible_for_pid` names ghostty
   (pid 29081), `responsibleForItself: false` — so a Screen Recording or
   Microphone grant given to Reelcut.app never reaches a proof's instance,
   and the terminal's grants are what it runs under (which is why
   `CGPreflightScreenCaptureAccess()` already reads true from this shell).
   `open -a … --env RC_AGENT_PORT=4891 --stdout LOG --stderr LOG --args
   -ApplePersistenceIgnoreState YES -AgentServerEnabled YES` launches an
   instance that is responsible for ITSELF (ppid 1, `responsibleName:
   Reelcut`), binds the port the `--env` gave it and answers 74 tools, so
   both flags reach the app that way. Consequence: the launch line does not
   change; the granted tier runs under the terminal's grants and SAYS whose
   grant it ran under in its summary line; a person checking the shipped
   app's own grant uses the `open` line. Trap: `open -a` of a bundle with an
   instance already running ACTIVATES it instead of launching one.
2. **Outcome A, decision 5's bad case.** With `capturesAudio` and
   `captureMicrophone` both on, `SCRecordingOutput` writes exactly ONE
   stereo 48 kHz AAC track that is the SUM of system and microphone: a
   both-on recording of nothing carries the microphone's floor (RMS
   0.00148) where a system-only recording of nothing decodes to exactly 0,
   and a smoke run with a person audible clipped at peak 1.218. So the
   microphone never goes on the recording stream: the `SCStream` carries
   `capturesAudio` alone (its system track is at unity — RMS 0.3514 for a
   0.354-RMS tone, independent of the output volume) and the microphone is
   a SECOND file through `AVCaptureSession` + `AVCaptureAudioFileOutput`,
   landing as a second clip. Timing: `recordingOutputDidStartRecording`
   fires 0.09–0.20 s BEFORE `startCapture`'s completion in every row (a
   state machine must tolerate the callback arriving first); the file holds
   all but 13–43 ms of the span between did-start and the stop call, so the
   "`addRecordingOutput` after `startCapture`" mutant is caught by a lower
   bound near the full span and not by a large gap; stop → did-finish is
   0.03 s without a microphone and 0.84–1.11 s with one, so `stop` bounds
   its wait; `recordedDuration` is WHOLE seconds (`CMTime` timescale 1) —
   fine for the panel's timer, useless as an offset.
   `availableVideoCodecTypes` is `[avc1, hvc1]`, `availableOutputFileTypes`
   `[mp4, mov]`, the default codec `avc1`.
3. **Unmeasured for the picker; measured for the programmatic filter.**
   `SCContentSharingPicker.h` documents `excludedBundleIDs` (:47–49) and
   `excludedWindowIDs` (:42–44) as "for picking" and says nothing about
   capture. `SCContentFilter(display:excludingApplications:exceptingWindows:)`
   removes 99.19 % of the excluded application's window pixels against a
   same-filter noise floor of 0 %, so the tool's path and the panel's
   display-popup path (both programmatic, both excluding Reelcut) may keep
   the panel on screen; a PICKER-made filter takes outcome B — the panel
   orders out for the recording's duration and Stop lives on the status
   item and the File menu — until a person checks A (§4 of
   `reelcut-remaining.md`). Instrument note: `SCShareableContent.windows`
   is NOT front to back; z-order comes from
   `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, and the spike's first
   version read a false "does nothing" off an occluded window.
4. **Decision 3 stands on evidence, and `.best` does not scale.** A 4 s
   recording of a mostly static screen reported `nominalFrameRate` 25.58 at
   `minimumFrameInterval` 1/60 and 16.78 at 1/30 (earlier runs 18.69 /
   21.53 and 1.60 / 17.64 — the number is whatever the screen did), so
   `rationalFrameRate` passes it through and — measured in the built app
   afterwards — `open_project` of such a file makes the canvas 24981/1000.
   `captureResolution` `.best` and `.automatic` at the display's POINT size
   give a point-sized file; pixels come only when `width`/`height` are asked
   in pixels, which `RecordingConfiguration.make` must do itself under
   `.best`, reading the pixel size off `CGDisplayCopyDisplayMode`
   (`CGDisplayPixelsWide` reports POINTS on this Retina display). The H.264
   writer rounds the odd point height 1117 UP to 1118, so a proof row
   comparing the file's size to the display's allows even rounding.
5. **Outcome A, and moot.** A `.microphone` stream output beside the
   recording output is accepted and delivers ~94 buffers/s of 512 frames on
   the named serial queue, in the DEVICE's native format (Int24 mono 48 kHz
   for one device, Float32 mono 24 kHz for another — a meter must read each
   buffer's format). But under question 2 the microphone is not on the
   stream at all, so the meter's source is the `AVCaptureSession`: its file
   output's connection exposes `AVCaptureAudioChannel.averagePowerLevel` /
   `peakHoldLevel` in decibels, polled at 30 Hz from main, which is the
   meter with no queue and no sample buffer in it.
6. **Outcome A three times, and one order to pick.** Measured by a
   `--only 6` run of the same script at 22:29:58 EDT the same day (the
   probe gained a `mic-capture` mode and `record` three defaulted spec
   keys; a subset run now carries the other questions' answers forward
   byte-identical under `carriedForward.dates`, so the five above are
   still the 22:01 record run's); two earlier runs at 22:25 and 22:27 are
   quoted where they widen a number. **(a) Show Clicks under BGRA is
   buildable.** `SCStream.h:257` says `showMouseClicks` "currently applies
   when pixelFormat is set to BGRA" and a fresh configuration reads `420v`;
   4 s of the main display recorded as question 4 does with
   `showMouseClicks` on under `kCVPixelFormatType_32BGRA` added its output,
   started, fired did-start and did-finish and wrote 1728×1118 `avc1`, 56
   video samples, 4.153 s, 142,001 bytes; the same under the default `420v`
   wrote 73 samples, 4.163 s, 260,037 bytes, and BGRA with clicks off 78
   samples, 4.162 s, 265,844 bytes. The two clicks files differ by 118,036
   bytes (66,111 and 11,325 in the earlier runs) against a
   same-configuration spread of 772,677 across this run's clicks-off file
   and the record run's three point-size question-4 files
   (265,844–1,038,521), so the format changes nothing a size can see, and
   `RecordingConfiguration.make` sets BGRA when clicks are on as R1 already
   says. Limit: the pointer was warped two pixels and back sixteen times
   per row and restored (`CGWarpMouseCursorPosition`, no grant, nothing
   clicked), but it sat on the SECOND display (x 3134) throughout, so no
   cursor excursion is in any file and the "static" screen was a live
   terminal in every row; the probe reports `onRecordedDisplay` now so the
   next run cannot mistake that. **(b) The second file lands in both
   orders with a measurable offset.** `AVCaptureSession` +
   `AVCaptureDeviceInput` (RØDE PodMic USB) + `AVCaptureAudioFileOutput`
   writing `.m4a`, and an `SCStream` + `SCRecordingOutput` with
   `capturesAudio` on and `captureMicrophone` off, started in ONE run-loop
   turn. `session.startRunning()` BLOCKS the main thread 102–183 ms
   (fifteen runs) and returns with `isRunning` true; `startRecording`
   returns in under a millisecond with `isRecording` still FALSE — the
   panel waits for the did-start, not the property;
   `fileOutput(_:didStartRecordingTo:from:)` fires 63–87 ms after it when
   the session goes first (20–31 ms when the stream is already running or
   there is none) on a private queue labelled "File ou",
   `Thread.isMainThread` false, so the state machine hops — while
   `fileOutput(_:didFinishRecordingTo:from:error:)` fired ON MAIN, 2–28 ms
   after `stopRecording`, in every run; `recordingOutputDidStartRecording`
   fires 65–90 ms after `startCapture` and, in EVERY run of both orders,
   86–107 ms BEFORE `startCapture`'s completion (question 2's finding
   holds); `stopCapture` to its did-finish is 4–34 ms with no microphone on
   the stream. The offset, the screen's did-start minus the microphone's:
   session first +8.4 and +27.5 ms this run, −7.5, +26.8, +5.2 and +3.1 ms
   in the two before — mean about +11 ms, scatter 35 ms, every sample
   within a frame of zero; stream first −85.5 and −83.9 ms, and −76.8,
   −77.9, −74.4, −83.1 before — steadier at 11 ms of scatter but some 80 ms
   (two and a half frames at 30) of picture with no microphone under it.
   **R1 starts the session first**: its offset is the smaller and is
   centred on zero, so a landing that mis-reads it by its whole scatter is
   still within a frame, and the landing applies the MEASURED offset per
   recording, never a constant. Sign: positive means the picture began
   AFTER the microphone, so the microphone clip starts that much earlier
   than the picture's clip (or has its in point trimmed by it). The
   microphone `.m4a` holds ONE mono 48 kHz AAC track (the device's
   connection reports one channel, `isActive` before the session runs),
   5.012–5.097 s, all but 40–74 ms of the span from its did-start to the
   stop call, RMS 0.00054–0.00154 (the speakers barely reach a dynamic
   microphone); the screen `.mov` holds the tone in its one stereo track at
   RMS 0.3504–0.3517 (unity, as in question 2), all but 15–63 ms of its
   own span, and again a video track ending at the last screen change
   (2.475 s in a 5.104 s file). The file output's `recordedDuration` is
   fractional (5.12 and 5.0347 s before the stop), unlike the recording
   output's whole seconds; `availableOutputFileTypes` is aiff, m4a, caf,
   mp4, aifc, 3gpp and wav; no runtime-error notification arrived in any
   run. The entitlement caveat above is unchanged: a bare `swiftc` probe
   carries no hardened runtime, so this measures the framework and not the
   app, which needs `com.apple.security.device.audio-input` first. **(c)
   The meter needs no queue.** Polling
   `output.connection(with: .audio)?.audioChannels` from the main run loop
   in 1/30 s slices — alone for 3 s, and beside the stream in each of the
   four (b) runs — read one channel on every poll, never a nil connection
   and never an empty array: 82 polls at a median 37.3 ms (33.8–38.5)
   alone, 147 at 34.3 ms (33.3–36.5) beside the stream, so the slice comes
   back at 27–29 Hz rather than 30 and the panel's timer should not assume
   better; `averagePowerLevel` −62.68…−39.59 dB (median −55.46) and
   `peakHoldLevel` −55.66…−34.74 dB (median −42.15), all 147 average
   readings distinct beside the stream (82 of 82 alone), both moving by
   more than 1 dB. `canAddOutput(AVCaptureAudioDataOutput())` beside the
   file output is true and is not needed.

**Two things the plan did not anticipate.** First, and the one with teeth:
**a recording's VIDEO track ends at the last screen change.** ScreenCaptureKit
delivers a frame only when something changes and the writer ends the video
track at the last one, so a 5.2 s recording of a static screen with sound
has a 2.16 s video track (and a silent one, a 1.03 s track in a 5.10 s
file). `MediaImporter` reads the asset's duration — the audio's — so the
media record is right, but measured in the built app the frame is picture
at 0.5 s and 1.5 s and BLACK from 3 s to the end: `CompositionBuilder.fill`
inserts a source range the track does not cover and AVFoundation leaves the
tail empty. A screencast with narration over a still screen — the commonest
kind — would go black after its last change. R1 cures it in the composition
(below), not in the recorder. Second, the built app's microphone needs the
hardened-runtime entitlement `com.apple.security.device.audio-input`
(`project.yml` has `ENABLE_HARDENED_RUNTIME` and no entitlements), which a
bare `swiftc` probe never needs — so the spike's microphone rows measure
what the framework does and NOT what the app will do until the entitlement
lands, and the proof's granted tier asserts the entitlement is in the signed
binary before trusting a microphone row.

#### R0 — the seventh answer, measured 2026-09-12 (for R2)

Host as above (macOS 26.5.1, Xcode 26.2, the same two displays), the
terminal's Screen Recording grant, the Microphone grant authorized;
`python3 tools/proof/recording_spike.py --only 7`, answers carried into
`tools/proof/work/spike/answers.json`.

7. **Outcome A — pause is buildable over one stream, and the numbers are
   small.** Three 2 s segments with 1.5 s pauses, the recording output
   REMOVED at each pause and a fresh one ADDED at each resume on the one
   running `SCStream`, a `.screen` stream output counting frames alongside:
   `removeRecordingOutput` returns in under 0.1 ms and the removed output's
   `recordingOutputDidFinishRecording` lands **5–25 ms** later;
   `addRecordingOutput` on the running stream returns in 0.2 ms and the new
   output's did-start lands **8–10 ms** later (against 67–78 ms for the
   first output after `startCapture`); the stream never stops
   (`didStopWithError` never fires) and keeps delivering **56–58 fps while
   paused**, the same rate as while recording — so a paused recording costs
   what a recording costs and the system's own menu-bar indicator stays up
   (a person checks that, §4). Every file's duration is its segment's span
   to within 40 ms (2.14 / 2.01 / 2.00 s against 2.15 / 2.04 / 2.02 s asked;
   the sum 6.15 s over a 9.33 s wall clock, the two pauses excluded), with
   one video and one audio track each. The `immediate` row — the next output
   added the moment the previous is removed, BEFORE its did-finish — is as
   clean (every add ok, every did-finish arrives, files 2.13 / 2.01 / 2.03
   s), so the machine need not wait for a closing file before resuming.
   **The microphone as a second file per segment** — one `AVCaptureSession`
   running throughout, its `AVCaptureAudioFileOutput` `stopRecording()` at
   each pause and `startRecording(to:)` to a new file at each resume — lands
   too: the restart's did-start in 25–95 ms, the stop's did-finish in 1–30
   ms, each segment's mic file within 0.13 s of its movie, and the
   screen-minus-microphone did-start offset per segment −22 / −72 / −67 ms
   on the AirPods and +33 / −23 / −16 ms on the built-in microphone — a
   per-SEGMENT number, which is why each segment carries its own offset
   and the landing never reuses the first one. **And one host fact found
   on the way**: the FIRST mic row of the day, on AirPods Max whose input
   had not been used since they connected, wrote a 2 ms first file (48
   Float32 packets at 24 kHz, the did-start 0.60 s after the call — the
   headset switching profiles mid-recording) and then failed every
   restarted file on the same output with `kAudioFileInvalidPacketOffsetError`
   (`'pck?'`, −11800): "a format or device change will result in the
   recording being stopped", the header says, and this one poisoned the
   writer for the rest of the session. Two later runs on the same headset
   and one on the built-in microphone were clean. So a segment's
   microphone can fail where the picture does not — R1's `micProblem`
   posture, now per segment — and `prepareMicrophone` (the countdown's
   session start) is exactly the cost that pays this before the recording.

#### What R0 and the scouts change in R1

Recorded here before R1 is briefed; the phase sections above are the plan
as written and this list is what overrides them. Each item names the scout
finding or the R0 answer it comes from.

- **The microphone is a second file** (R0 q2): `ScreenRecorder` owns an
  `AVCaptureSession` with an `AVCaptureDeviceInput` for the chosen device
  and an `AVCaptureAudioFileOutput` writing `.m4a` beside the movie, started
  before the stream so its start latency is not in the picture's head;
  `RecordingResult` carries `micDescriptor` and the measured offset between
  the two files' did-start callbacks, and the landing places the microphone
  clip at the playhead plus that offset on a new track. The `.microphone`
  stream output is not used. The meter reads the file output connection's
  `AVCaptureAudioChannel` levels from the panel's own 30 Hz timer, so
  `app/CLAUDE.md`'s `DispatchQueue` seam list gains NOTHING.
- **The composition holds a media's last frame when its video track ends
  before the requested source range** (the R0 surprise): in
  `CompositionBuilder.fill`, a video insert past the source track's
  `timeRange` inserts what the track covers and then the track's last frame
  stretched over the remainder — the freeze-frame idiom (§7.2) applied
  inside one segment — BEFORE the segment's own speed scaling, so the
  composition range's length is unchanged. Audio is untouched; a media
  whose video covers the range is byte-identical by construction, which
  every earlier proof re-checks. The headless proof row is an
  `ffmpeg`-made fixture with 1 s of picture and 5 s of sound: `render_frame`
  at 3 s equals `render_frame` at 0.99 s byte for byte and neither is black.
- **`ProjectDocument.swift` takes one internal method, not two tokens**
  (document scout): `project` and `importSourceURL` are `private(set)` and
  `clampViewState()` is private, so an extension file cannot build the
  untitled document. `adoptImported(_ descriptor:, source:, fps:)` (~10
  lines) does what `readMediaFile` does after its probe — source, `fileURL`
  nil, package type, `makeProject(around:fps:)`, the view state reset, the
  clamp — and `readMediaFile` calls it, so there is one spelling;
  `makeProject` stays `private static` and gains `fps: Fps? = nil`. The
  `.newProject` ORDER is a contract: `openUntitledDocumentAndDisplay(false)`
  → `adoptImported` → `makeWindowControllers()` → `showWindows()`; no
  `addDocument` (the untitled call already adds it), and nothing reads
  `displayName` before the adopt, because AppKit pins the name on first
  read. `makeWindowControllers` already dirties the document and runs
  `generateCaches()`.
- **`RecordingLanding` answers ops and predicted ids, and each caller
  commits through its own door** (document scout): the panel through
  `document.performGroupedEdit("Add Recording", ops)` then
  `generateCaches()` and the selection, the tool through
  `AgentServer.performGroupedEdit` / `editResult`, which reports `created`
  ids and the scope landing — a document-side commit would turn a tool's
  refusal into a sheet. The two-try track choice runs over a project that
  already HOLDS the media (`add_media` applied purely first, the id read off
  the result or, for a path already in the list, off the list —
  `placeImageBackground` and `backgroundMedia(for:in:)` are the precedent,
  not `addGeneratedClip`, whose probe cannot see a media the project lacks),
  scoped through `.scoped(scope)` when a nest is open, and the new track's
  id is the probed result's `nextId`. With a microphone file the second pair
  is derived from the first pair's purely-applied result, never from one
  `nextId` read. A landing while `document.isLiveEditing` is deferred to
  the gesture's end.
- **The destination is `.document(recipeKey:)`**, not an
  `ObjectIdentifier` (document scout): an identifier of a closed document is
  reused by the next one at the same address (`RelinkSheetController.swift:29`
  says so), while `recipeKey` is never minted twice, so the miss →
  `.newProject` fallback is exact.
- **`record_screen`'s target rule** (server scout): a named `project` goes
  through `target(a)` and its by-name refusal STANDS (no tool silently
  records into a fresh document when the caller misspelt a path); an
  unnamed one with no document open lands as `.newProject`; otherwise the
  frontmost. The wait is `import_media`'s `DispatchSemaphore` + `AgentBox`
  around `onMain { recorder.start … }` / `onMain { recorder.stop … }` with
  `semaphore.wait(timeout: .now() + seconds + 30)` and a timeout that asks
  main to stop the recorder — never `transcribe`'s synchronous-body shape.
  The handler is an extension method and its two registrations (a name in
  `offMainTools`, a line in `handlers`) go into the frozen file, with the
  four count sentences the commit makes stale. `tools/proof/mcp.py`'s
  client timeout is 600 s, so `MCP.__init__` gains a `timeout` parameter
  the proof passes.
- **The toll shares one hoisted local** (server scout): `render_frame`'s
  `t` row reads `ticks`, so `AgentCatalog+Files.swift` is
  `func fileTools(ticks: String) -> [[String: Any]]` spliced after the
  Canvas group, taking the six file-only locals with it, about 400 lines;
  the header's "none of them shares a hoisted local" sentence is corrected.
  Because the three groups are the LAST three, `tools/list` is byte-identical
  before and after, which is the cheapest gate beside phase 9's 214/214.
- **The count handover is two rows in `phase9_proof.py`**, not one (server
  and proof scouts): `TOOLS` becomes a floor AND `APP_STATE_TOOLS` gains
  `record_screen` (or becomes a subset check), in the same commit as the
  tool; `recording_proof.py` owns the exact 75, the exact 55 scoped, the
  twenty scopeless names, and "`scope` absent on `record_screen`".
- **Show Clicks needs BGRA** (SDK scout): `showMouseClicks` "currently
  applies when pixelFormat is set to BGRA" and a fresh configuration's
  `pixelFormat` is `420v`, so `RecordingConfiguration.make` sets
  `kCVPixelFormatType_32BGRA` when clicks are on; the spike's question 6
  measures that a recording output over a BGRA stream starts and writes.
- **Spellings that differ from the plan's** (SDK scout, compiled):
  `SCShareableContent.getExcludingDesktopWindows(_:onScreenWindowsOnly:completionHandler:)`
  and `getWithCompletionHandler(_:)` — there is no `getShareableContent`
  in Swift and the docs' `current` is `async`-only; `SCStreamError.Code`,
  not `SCError`; `SCContentFilter(display:including:)` for windows and
  `(display:including:exceptingWindows:)` for applications;
  `.systemStoppedStream` (−3821) is a second external stop beside
  `.userStopped` and takes the same finishing path;
  `.failedToStartMicrophoneCapture` (−3820) names the microphone;
  `SCRecordingOutputConfiguration.outputURL` imports non-optional and is
  nil underneath until assigned, so reading it first TRAPS (exit 133) —
  `make` assigns it before anything reads the configuration and the probe
  reads fields only off a returned one; `AVCaptureDevice.DeviceType.microphone`
  and `.external`, since `.builtInMicrophone` is a deprecation warning at
  15.0; `AVCaptureDeviceInput(device:)` auto-prompts on `.notDetermined`,
  so the tool reads the status first.
- **The chrome** (chrome scout): `ScreenRecorder.shared` and
  `RecorderPanelController.shared` (`ExportQueueWindowController`'s mould),
  so `AppDelegate.swift` changes by the quit guard's line alone and
  `AppDelegate+Recording.swift` stores nothing — probes instantiate
  `AppDelegate()`; the retitle is in `AppDelegate.validateMenuItem` beside
  the agent-server branch (the delegate's items never reach
  `validateUserInterfaceItem`); the panel is
  `[.titled, .closable, .nonactivatingPanel]`, `level = .floating`,
  `hidesOnDeactivate = false`, `isExcludedFromWindowsMenu = true`,
  `isReleasedWhenClosed = false`, no window delegate; `LevelMeterView`
  gains `init(meter: LevelMeter = .shared)` (it is bound to `.shared` by
  name today, and publishing the microphone there would make the timeline
  bar meter the microphone) and `AccentButton` gains `fill: NSColor =
  DS.accent` (both defaults keep every chrome render byte-identical, which
  the earlier chrome proofs check); `DS.meterClip` is the warning red, not
  "the one coral". Quit while recording: `applicationShouldTerminate` is
  asked AFTER the document review, so the guard is a backstop and the order
  is recorded — the save sheet comes first, and a target document closed by
  the review lands as `.newProject`, which the `recipeKey` lookup makes
  exact. `project.yml` gains `entitlements` with
  `com.apple.security.device.audio-input` beside the plist key, and the
  generated `app/Reelcut.entitlements` joins `.gitignore`.
- **The proof** (proof scout): the granted tier's detection is
  `record_screen {seconds: 1, place: false, path: …}` against a document
  the script opened, a TRUE preflight followed by a `userDeclined` start
  scores as a failure quoting the sentence; the tier launches its own
  instance with `-RCRecordingFolder` through `phase8_proof.py`'s `Instance`
  and names the responsible application in its summary; the microphone
  refusal names the framework's status word rather than assuming absence.
  The welcome cross-build's reference is a pickaxe on the button's title
  (`git log -S"New Recording" -- app/Sources/WelcomeWindowController.swift`,
  last + `^`; `HEAD` while uncommitted), since the file's adding commit is
  the initial commit; a third button moves the other two, so the score is
  `extent(diff)` equal to the new row's rectangle with nothing outside it,
  clusters printed and never counted as one.

#### R1 — the record (written as the phase landed; the plan above is unchanged)

- **The granted tier first RAN unattended on 2026-09-11 at 00:24 EDT**, under
  a poller that waited for the console to unlock (the whole of lane D's
  session had run against a locked console with the display asleep, where
  ScreenCaptureKit lists no display under a TRUE preflight, so the tier's
  33 + 6 rows had been written blind against the seam). Under the
  terminal's grants (R0 q1: the direct launch is ghostty's, which the tier's
  summary line prints) it scored **101/102** on its first run: a new
  project's `canvas.fps` was `[60, 1]` while the media's was `[42381, 1000]`
  (decision 3 measured on a real recording); `size: best` wrote 3456×2234
  for a 1728×1117 display; the two-try rule's second branch minted a new
  front track; inside a nest the answer said `scope 13, document_ops
  [add_media]` and the view showed the clip while the timeline did not;
  one undo removed media and clip while the file stayed; and the
  microphone rows — the entitlement in the signed binary, the terminal's
  grant authorized — landed the second file on a track named Microphone
  with the two clips' starts differing by the measured `mic_offset` of
  36 158 ticks (60 ms) to within half a frame. **The one failure was the
  proof's, not the recorder's:** the "tone captured" row asked
  `detect_silence` to find less than half of a recording made while
  `afplay` played a 1 kHz tone, and on this host it found all of it. Two
  measurements settled why. The host's output was MUTED, and a muted
  output reaches the tap UNRELIABLY — R0's unity tone arrived at about
  −10 dB against the floor in one 3 s run at 02:30 and not at all in the
  next; and something else was playing (Plex, into the tap, at 0.025 RMS),
  which a threshold detector cannot tell from a tone. The rows were
  rewritten: the two recordings are decoded to PCM and read through a
  Goertzel filter at 1 kHz (the tone recording's 1 kHz power ≥ 100× the
  silent one's, and ≥ a quarter of its own total power), so a noisy host
  cannot fail them and a quiet one cannot pass them vacuously, and when
  `osascript` reads `output muted` they are SKIPPED with their count and
  the numbers printed. The re-run at 02:26 scored **100/100 with the two
  tone rows skipped by name**; unmuting the host is what scores them.
- **The review, and the fix wave's first stage.** Nine readers over the
  uncommitted tree (session, landing, chrome, tool, composition, rules,
  proof, grants, plan) returned 68 findings; three refuters per finding were
  briefed and the usage limit killed most of them mid-run, so 11 findings are
  CONFIRMED by every vote, 2 refuted, and 55 were never judged and were
  triaged by hand — an unjudged finding is not a refuted one. The recorder's
  lane closed the eleven and the recorder-side unjudged ones (`ScreenRecorder.swift`,
  `+Microphone.swift` — new, the capture session prepared during the
  countdown after lane A's smoke run lost the first 421 ms of voice —
  `+Finishing.swift`, `+Content.swift`, `RecordingSetup.swift`): a microphone
  problem is `micProblem` on a `.success` and never the recording's failure
  (the movie is probed FIRST, the mic file left on disk and named);
  `stop()` in any state past idle JOINS the finishing under way instead of
  answering `.busy`, which had dropped a landing when a person's Stop
  followed the menu bar's by a second; `settle` is one-shot
  (`Session.settling` — measured, a did-finish landing during the probe had
  concluded TWICE and wiped the next session); a microphone that dies
  mid-recording sets `microphoneProblem` live and silences the meter while
  the picture records on; the hook is `onFinish`, a parameter of `start`
  stored on the session and called exactly once, because a Record refused
  `.busy` from the other door had erased the running recording's hook; the
  arm ceiling has its own sentence; every failure past `beginFinishing`
  names its files (`RecorderError.filesKept`); a late `didStopWithError` is
  adopted as the reason when no `stop()` ended the recording; the grant
  sentences carry the launching process's pid when `getppid()` is not 1,
  since a shell-launched instance runs under the terminal's grants and the
  pane sentence alone sent a person to grant the wrong application;
  `shareableContent` issues its call from a global queue for both doors
  (a panel that made it on main would have frozen the app for the ~37 s the
  framework held a locked console's caller); two dead helpers went.
  `recording_probe.py` section 3 grew 49 rows over a FAKED session — an
  `SCContentFilter()`, an `SCStream` and an `SCRecordingOutput` all
  construct in a bare Mach-O, only `startCapture` needs the grant — with
  four mutants: `busy-finishing` 617/620, `no-oneshot` 617/620,
  `mic-fails-all` 618/620, `no-path` 618/620.
- **The landing's fixes.** A new-project recording with a microphone read
  CLEAN after one ⌘Z and ⌘W closed it without a prompt (the mic edit was the
  document's only change count; `makeWindowControllers`' import count is
  guarded by `!isDocumentEdited` and was skipped): `untitled(around:)` makes
  the import count itself BEFORE the microphone's edit (mutant
  `no-import-count` 619/620). That edit is named "Add Microphone", since it
  removes the voice and keeps the picture. The landing's comment that the
  trial "cannot see `check_caps`" was false — the trial applies each scoped
  op to the parent handle, which is the scoped apply — and row 8 measures
  `too many tracks: 65 (max 64)` thrown in the trial, in a nest and out; the
  one-list limit (a refused microphone track takes the picture down with
  it) is recorded in `placement`'s doc rather than fixed.
- **The filmstrip's fix, and the cap.** The held tail was measured from the
  RECORD's nominal rate, so a sparse recording's last tiles showed the slide
  before the last (three frames in 50 s read as 0.06 fps, a 16.7 s frame,
  the tail held from 34 s); it is the track's last sample's own time now
  (an `AVSampleCursor` mapped through the edit list; `remaining_probe.py` 5f
  gained the sparse shape, 170/170, mutants `record-rate-tail` 166/170 and
  `rounded-end` 168/170). Lane F's recorded limit was half true and is
  replaced by the measured facts. `MediaImporter.swift` was 619 against the
  ~600 cap with the tail in it and paid its toll mid-wave: the await-free
  half went to `MediaImporter+Probe.swift` as a pure move (619 → 518 → 571).
- **The doors' fixes (stage B of the wave).** The panel asks for BOTH grants
  unconditionally on a press — a `canAsk` gate told a person under
  `-AgentServerEnabled` to press the button they had just pressed and left a
  `notDetermined` microphone unrecoverable; decision 4 is that the TOOL never
  asks, and the panel is the tool's opposite — a `.starting` attempt is
  numbered and bounded by the arm ceiling, `land()` reads the commit's
  outcome off the project handle (a beep-and-return refusal was reported as
  added), Record Into freezes at the captured choice through a recording,
  the grown card is constrained to its screen, the countdown and tick run in
  `.common` run-loop modes, `show()` beeps while a picked recording hid the
  panel, Record over the Window… row with no filter refuses first, the tick
  shows a live microphone problem and a landed one, the capture session is
  prepared when the countdown begins, and File ▸ Stop Recording routes a
  tool's recording to the recorder instead of beeping at it — with the panel
  now five files (`+Landing`, `+Picker`) and `recording_probe.py` section 5
  at 116 rows with eight mutants at 660–661/662. The tool names the file in
  every failure after the recording was written ("The recording was saved at
  … but could not be added: …", measured on a document at `MAX_TRACKS`),
  waits out a live drag on the server thread at the panel's own bound,
  bounds its stop wait at 75 s independent of `seconds` (the recorder's
  finish ceiling plus two 30 s probe ceilings), refuses zero shareable
  displays by name, treats a blank `path` as absent (a mutant landed a
  recording in `tools/proof/  /`), carries `mic_problem`, puts up the same
  menu-bar status item the panel does, mentions macOS 15's periodic
  screen-recording consent alert in both timeout sentences, and is three
  files (`+RecordingArguments`, `+RecordingResult`). Its proof scores a 1 kHz
  SHARE on Parseval's scale with a self-test (the first Goertzel rows had
  compared two scales and could not fail), skips the `canvas.fps` row by
  count when the file's own rate is exactly 60/1, reports a raise inside the
  granted tier as one failure plus a counted skip, reads the microphone
  status off the launched instance, and gained the mic rows that see a lost
  head: **with a prepared session the microphone LEADS the picture by 65–75
  ms** (three runs), its file LONGER than the movie by that lead plus the
  writers' tail difference, and the landing at playhead 0 takes the
  head-trim branch — R0's +11 ms mean was for a session started inside
  `start`, and lane A's −421 ms is what the one-sided head-loss row fails.
- **Host state is a proof INPUT, read and named, never assumed.** Four of
  it in one night: a locked console (0 shareable displays under a true
  preflight — the tool answers `display must be 0…0 (got 0); 0 displays are
  shareable.` in 0.1 s, and the tier skips with a count), a muted output
  (above), another application's sound in the tap, and — measured at 12:10
  the next day with AirPods Max as the default output — **a Bluetooth output
  hands the system-audio tap DIGITAL SILENCE**: `afplay` and `say` both
  alive through a 3 s `record_screen`, the file decoding to RMS 0.0 and peak
  0.0, where the built-in speakers had given R0's unity tone. The proof's
  host probe now reads the default output device and its transport through
  CoreAudio and skips the tone rows by name (`the default output 'Kevin's
  AirPods Max' is a Bluetooth device, which delivers nothing to the
  system-audio tap on this host`); a wired or built-in output scores them.
  Each of the four is a named skip or a measurement that survives it, and
  none is a pass.

### Phase R1 — Screen recording

*Two to three sessions. No schema change (v6 stands). No new op
(`OP_NAMES` stays 55). ONE new tool (`record_screen`; the catalog goes 74 →
**75**). No FFI change. One size toll paid first and alone.*

#### R1·toll — `AgentCatalog+Files.swift`

`AgentCatalog.swift` is 807 against the ~600 cap and its own header names
the cut: the FILE groups — Media, Captions, Rendering, export — to
`AgentCatalog+Files.swift`, about 300 lines, sharing no hoisted local with
what stays. Landed ALONE, gated by `make typecheck`, `make app`, an EMPTY
parity log (all four parts; the tool count and every op tool's `scope` are
what a botched move would break) and `phase9_proof.py` at 214/214 against
the built binary — the catalog is what phase 9 asserts most exactly. Only
then does `record_screen`'s entry go into the new file, so the diff that adds
it is a diff of one entry.

`ProjectDocument.swift` (1336) is NOT cut: the phase's addition is a pure
extension file (`ProjectDocument+Recording.swift`), the `+DisplayStem` shape,
and the base file changes by exactly two tokens (`private` → internal on
`makeProject(around:)`, and its new `fps:` parameter with a default so
`readMediaFile` compiles untouched).

#### R1a. The session — `ScreenRecorder.swift` and `RecordingSetup.swift`

`RecordingSetup.swift` is the half a probe can call: values in, values out,
no framework object that needs a bundle.

- `RecordingChoice`: the source (`.display(CGDirectDisplayID)`,
  `.window(CGWindowID)`, or `.picked` — the panel's picker result, carried
  as the filter it produced), `microphone: String?` (an
  `AVCaptureDevice.uniqueID`, nil for off), `systemAudio: Bool`,
  `showClicks: Bool`, `rate: 30 | 60`, `resolution: .nominal | .best`, the
  `destination` (`.newProject` or `.document(ObjectIdentifier)` — an
  identity and not a reference, `LevelMeter`'s rule, so a document that
  closed mid-recording is a lookup that fails and not a dangling pointer),
  and the folder.
- `RecordingFiles`: the folder (decision 2, launch-argument override), the
  name — `Screen Recording 2026-09-10 at 14.03.22.mov`, the Screenshot app's
  spelling, made unique with ` (2)` — and `create()`.
- `RecordingConfiguration.make(_ choice:, display size:, scale:)` →
  `SCStreamConfiguration` + `SCRecordingOutputConfiguration`: width and
  height from the display's point size times the scale under `.best`, the
  point size under `.nominal`; `minimumFrameInterval` 1/rate; `showsCursor`
  true; `showMouseClicks` from the choice; `capturesAudio` from the choice
  with `sampleRate` 48 000, `channelCount` 2, `excludesCurrentProcessAudio`
  TRUE always; `captureMicrophone` and `microphoneCaptureDeviceID` from the
  choice; codec HEVC where `availableVideoCodecTypes` offers it, H.264
  otherwise; file type `.mov`; `outputURL` from `RecordingFiles`. Pure, so
  the probe reads every field back.

`ScreenRecorder.swift` is the class: a state machine `idle → arming →
recording → finishing → idle`, owning the `SCStream`, the
`SCRecordingOutput`, their delegates, the optional `.microphone` output for
the meter (R0 question 5) and, under R0 question 2's outcome A, the
`AVCaptureSession` for the second file.

- `start(filter:, choice:, completion:)` — completion-handler API only;
  `addRecordingOutput` BEFORE `startCapture` (the header's own rule); the
  completion fires on MAIN with the start error or nothing. A start while
  not idle is a refusal with a name, not a crash.
- `stop(completion:)` — `stopCapture`, then wait for
  `recordingOutputDidFinishRecording` (or `didFailWithError`), then probe
  the file through `MediaImporter.probe(url:completion:)` and answer a
  `RecordingResult { descriptor, micDescriptor?, choice, startedAt }` on
  main. A `didStopWithError` with `userStopped` (the system's menu-bar
  indicator) takes the SAME finishing path, so a recording the person ended
  from outside the app still lands.
- `elapsed` reads `recordedDuration` for the panel's timer.
- The meter: the `.microphone` output's buffers on a serial queue of this
  file's own, peak and RMS by vDSP, published to a `LevelMeter` through
  `DispatchQueue.main.async` — this is our queue and not a render thread,
  so the atomic sink is not needed and app/CLAUDE.md's `Synchronization`
  rule is untouched. `app/CLAUDE.md`'s `DispatchQueue` seam list gains this
  queue by name.

**The `async` rule holds** (spec §11): every ScreenCaptureKit entry point
used has a completion-handler form, read off the header and re-verified by
the scout. No `await` outside `MediaImporter.swift`.

#### R1b. The landing — `RecordingLanding.swift` and `ProjectDocument+Recording.swift`

`RecordingLanding` is a value type, `AudioNormalize`'s shape: a
`RecordingResult` and a target in, ops or a document out, so the panel and
the tool provably land the same way.

- `.document`: the document is looked up by identity among
  `NSDocumentController.shared.documents`; found, the ops are
  `[.addMedia(descriptor), .addClip(track, media: expectedId, at: playhead)]`
  (+ the mic file's own pair, on a NEW track under the picture's, when there
  is one), where `expectedId` is `next_id` before the op (the documented
  contract) and `track` is chosen exactly as `addGeneratedClip` chooses:
  the front track if `editedProject.applying(_:)` accepts the clip there,
  else a `.addTrack` first. One `performGroupedEdit("Add Recording", ops)`,
  then `generateCaches()`, then the selection set to the new clip. Inside an
  open nest the `add_media` is document-level and the `add_clip` scoped —
  `ReelOp.documentLevelNames` already sorts a mixed edit (phase 9). **If the
  document is gone, the result lands as `.newProject`** and the answer says
  so.
- `.newProject`: `ProjectDocument.untitled(around:fps:)` in
  `ProjectDocument+Recording.swift` — `openUntitledDocumentAndDisplay(false)`,
  then the document's `importSourceURL` set to the recording and its
  project built by `makeProject(around: descriptor, fps: choice.rate)`
  (decision 3), then `makeWindowControllers()` and `showWindows()`, the
  `open_project` handler's sequence (`AgentServer+Project.swift:40–47`). The
  descriptor's own `fps` stays what the probe found; only the CANVAS is
  overridden. The document opens untitled and dirty, as an opened movie
  does.

#### R1c. The chrome — the panel, the menu, the welcome button, the status item

- **File ▸ New Recording… (⌥⌘N)** on `AppDelegate` — `newProject`'s
  precedent (`AppDelegate.swift:150`): a nil-target action that resolves
  with NO document open, which the welcome window needs. `⌥⌘N` is checked
  against spec §9 by the scout (⌘N and ⇧⌘N are taken; the modifier keeps
  the key off the first responder, the rule every phase since 4 records)
  and its row is promoted into §9 on landing. While a recording runs the
  same item reads **Stop Recording** and its action stops it; the
  validator retitles it, the Preview Window toggle's checkmark precedent.
- **The welcome window's third button**, "New Recording…", a
  `StickerButton` `.secondary` beside New Project
  (`WelcomeWindowController.swift:58–66`); the paragraph above it gains no
  words.
- **`RecorderPanelController.swift`** — an `NSPanel`, `.floating`,
  `.nonactivatingPanel` so Stop can be clicked without bringing Reelcut
  forward over the thing being recorded, `hidesOnDeactivate` false, ONE
  instance owned by `AppDelegate` (`AppDelegate+Recording.swift`) because it
  outlives documents and exists with none. Rows: Source (a popup of
  displays by name plus "Window…", which presents the picker in window
  mode; the picker's `didUpdateWithFilter` fills the choice), Microphone (a
  popup of `AVCaptureDevice`s of type audio plus Off; the meter beside it
  lights while recording — the pre-roll meter is §5), System Audio (a
  switch), Show Clicks (a switch), Rate (30 / 60), Size (Nominal / Best),
  Record Into (New Project, then each open document by `displayName`; the
  front document preselected when one exists), and the Record button in
  `DS.meterClip`, the one coral the app has. Every choice persists in
  `UserDefaults` under `ReelcutRecording…` keys, which the harness pins
  along with the others if it ever renders the panel (it does not need to).
- **Pressing Record**: the grants first — `CGPreflightScreenCaptureAccess()`,
  then `CGRequestScreenCaptureAccess()` if false and `canAsk`; the
  microphone's `requestAccess` if a device is chosen — with the refusal
  sentence and the System Settings pane named in a note under the button
  when a grant is denied (`TranscribeSheetController.swift:277–291`'s
  shape); then a 3-2-1 countdown drawn in the panel; then `start`. Under R0
  question 3's outcome A the panel stays; under B it orders out.
- **`RecorderStatusItem.swift`** — the app's first `NSStatusItem`: a red
  dot and the elapsed time in the menu bar while recording, a menu with Stop
  Recording. It exists because a global hotkey needs an Input Monitoring or
  Accessibility grant and the recorder's panel may be hidden or behind the
  recorded app; the status item needs nothing. It is created when a
  recording starts and removed when it lands.
- **Quit while recording** (`applicationShouldTerminate`,
  `AppDelegate.swift:90`): answers `.terminateCancel`, stops nothing, and
  brings the panel forward — a person who meant to stop presses Stop. A
  quit that silently finished a recording would land a file into a document
  that is about to ask whether to save, which is the wrong moment for both.
- **Info.plist**: `NSMicrophoneUsageDescription` joins the speech key in
  `project.yml`'s `info.properties` (the comment there, "No microphone
  key", is rewritten). Screen Recording has no plist key; the system prompt
  is triggered by the first capture or by `CGRequestScreenCaptureAccess()`.

#### R1d. The mirror — `record_screen` (`AgentServer+Recording.swift`)

```
record_screen {
  display?: int         // index into the shareable displays, 0 = main; default 0
  window?: int          // a CGWindowID; exclusive with display
  seconds: number       // 1 … 600
  microphone?: bool     // default false; needs the Microphone grant
  system_audio?: bool   // default true
  show_clicks?: bool    // default false
  rate?: 30 | 60        // default 60
  size?: "nominal" | "best"   // default "nominal"
  place?: bool          // default true: land in the target document at the playhead
  path?: string         // override the file's location (the Recordings folder otherwise)
  project?: string      // the usual target selector
}
→ { ok, path, mic_path?, media, mic_media?, clip?, mic_clip?, duration, width,
    height, fps: [num, den], audio_tracks, landed: "document" | "new_project",
    project }
```

- In `offMainTools`, `transcribe`'s shape: the wait is the call, every
  document touch an `onMain` hop, the ceiling `seconds + 30`.
- **The refusal order is the contract**, and it is `transcribe`'s: the
  caller's own mistakes FIRST — `seconds` out of range or missing, both
  `display` and `window` given, a `rate` or `size` outside the vocabulary,
  `microphone: true` with the Microphone grant absent — then the Screen
  Recording grant, read synchronously and named ("Screen Recording is not
  granted to Reelcut. Turn it on in System Settings ▸ Privacy & Security ▸
  Screen & System Audio Recording, then relaunch."), and only then the
  display or window lookup through `getShareableContent`, which is below
  the grant because it cannot be asked without one. Never
  `CGRequestScreenCaptureAccess()`, never the picker (decision 4).
- The filter is built programmatically and ALWAYS
  `excludingApplications: [Reelcut]`.
- With `place` true and a target document, R1b's `.document` path; with no
  document open (or `place` true and `project` naming nothing), R1b's
  `.newProject` path, and `landed` says which; `place: false` lands the
  media (and the mic media) without a clip, `import_media`'s note repeated.
- The catalog entry names the UI path ("File ▸ New Recording…") and
  declares NO `scope`: the parity check's fourth part reads op tools only
  (`rc_op_names`), and `record_screen` is an app-state tool like
  `transcribe`. The scout confirms that the check does not also demand it of
  app-state tools.

#### R1e. Lockstep and documents

`CLAUDE.md` (the designs list; the tool list at 75 with `record_screen`
named among the app-state tools; the milestone paragraph, written LAST),
`app/CLAUDE.md` (file-map rows for the six new files; the `DispatchQueue`
seam list; the `NSPanel` paragraph gains the second panel and why it is
non-activating; the `NSStatusItem`), spec §1, §3, §7.4, §7.9, §9 (⌥⌘N
promoted) and §11 (the five decisions above, in §11's words),
`README.md` (user-facing: the menu item and the folder),
`tools/proof/README.md` (the launch line if R0 question 1 says so; the count
handover to 75; the "with the grant" paragraph), `project.yml`, and
`reelcut-remaining.md` §3 (the catalog row struck, any new file near the cap
added) and §4 (what only a person can check — below). Road map 2 §4's
"voice-over recording" bullet is rewritten: the microphone half is now
this phase's, and a standalone voice-over button is what remains.

**Where.** New: `RecordingSetup.swift`, `ScreenRecorder.swift`,
`RecordingLanding.swift`, `ProjectDocument+Recording.swift`,
`RecorderPanelController.swift`, `RecorderStatusItem.swift`,
`AppDelegate+Recording.swift`, `AgentServer+Recording.swift`,
`AgentCatalog+Files.swift` (the toll); `tools/proof/recording_spike.py`,
`recording_proof.py`, `recording_probe.py`. Changed: `AppDelegate.swift`
(the stored panel, the quit guard's one call), `AppDelegate+Menus.swift`
(one item), `WelcomeWindowController.swift` (one button),
`ProjectDocument.swift` (two tokens), `AgentServer.swift` (one name in
`offMainTools`, one handler line), `AgentCatalog.swift` (the toll, then
nothing), `project.yml`, and every document named above. Each new Swift
file is budgeted under 400 lines; road map 2's phase 6 says the estimate is
worth two thirds of the truth, so the cap is what the lane is briefed with
and the estimate is not.

**Proof.** Three instruments, the mutants named before the code so the
proof cannot be written to pass.

- **`recording_proof.py` over MCP, in two tiers.** The HEADLESS tier always
  runs and carries the exact count: the catalog is EXACTLY 75 and
  `record_screen` is in it with its declared argument names; the refusals,
  exact and IN ORDER — `seconds` 0 and 601 and absent, `display` with
  `window`, `rate: 24`, `size: "huge"`, `microphone: true` (on this machine
  the Microphone grant is absent, so the sentence names it), and then the
  Screen Recording sentence with the pane's name inside it — each leaving
  the project JSON unchanged and pushing no undo step; and, because a build
  whose grant check ran FIRST would answer every row with the grant's
  sentence, the ordering rows are the ones that fail against that mutant.
  The GRANTED tier runs when `CGPreflightScreenCaptureAccess()` is true for
  the instance (the script asks through a `render_frame`-free probe: a
  `record_screen` with `seconds: 1` and reads whether the answer is the
  grant's sentence) and otherwise prints the sentence and SKIPS with a
  count that the summary line reports — never a vacuous pass. With the
  grant: two seconds of display 0 into `tools/proof/work/recordings/`
  (`-RCRecordingFolder`) → the file exists there, its name has the date
  shape, `width`/`height` equal the display's point size under `nominal`
  and its pixel size under `best` (read through `CGDisplayBounds` and the
  backing scale in the script's own probe), `duration` in [1.5 s, 3.5 s],
  the clip in `get_project` at the playhead on the front track with the new
  media id, `undo` removes both media and clip in ONE step and the file is
  still on disk, `render_frame` at the clip's midpoint is neither the slate
  nor black (the frame's byte variance above a floor, and DIFFERENT from a
  `render_frame` of the empty project); `place: false` lands the media
  alone; with no document open the answer says `new_project`, the new
  document's `canvas.fps` is `[60, 1]` while the media's `fps` is NOT
  (decision 3's row — the mutant that drops the override fails here and
  nowhere else); inside an open nest the clip lands in the NEST and
  `get_project`'s view shows it; `system_audio: true` while `afplay` plays
  a tone gives `has_audio` true and a peaks file with a non-zero bucket,
  and `system_audio: false` gives `has_audio` false. Under R0 question 2's
  design the mic rows are written for whichever outcome landed.
- **`recording_probe.py`**, a probe over the WHOLE of `app/Sources`
  (`phase9_probe.py`'s instrument): `RecordingFiles` naming and uniqueness
  over a temp folder; `RecordingConfiguration.make` read back field by
  field for 30 and 60, nominal and best, mic on and off, with
  `excludesCurrentProcessAudio` asserted TRUE in every combination (the
  mutant that flips it is invisible over MCP — nothing plays — and this is
  the only row that sees it); `RecordingLanding`'s op list for a front
  track that accepts, a front track that refuses (a clip already at the
  playhead → an `add_track` first), and a dead document identity (→
  `.newProject`); the recorder's state machine refusing a second `start`
  and ignoring a `stop` while idle, with no framework call made (the
  harness has no bundle); and the structural reads: the File-menu item
  exists with `⌥⌘N` and the right selector, the welcome window's
  third button is there with the right action, the catalog file's group
  moved whole (a name count before and after the toll). It also renders the
  welcome window through the harness against a reference build of the tree
  ONE commit before the button existed, the phase 5 cross-build pattern,
  scoped to the button row: exactly one new cluster of changed pixels, at
  the row's rectangle.
- **`recording_spike.py`** stays in the tree after R0 as the record of the
  five answers, re-runnable.

Mutants, each named with the check that kills it: the grant check hoisted
above the argument checks (the ordering rows); the `.newProject` fallback
deleted (the dead-identity probe row, and the MCP row with no document
open); the `fps:` override deleted (the `canvas.fps` row); the undo group
split into two edits (the one-step undo row); `excludesCurrentProcessAudio`
false (the probe's read-back); `addRecordingOutput` moved AFTER
`startCapture` (the duration row's lower bound — the first frames are
lost); the mic rows per R0's outcome; the welcome button's action pointed at
`newProject` (the structural read); a `scope` accidentally declared on the
tool (the headless catalog row asserts it is absent, so a later phase that
starts demanding it of app-state tools fails loudly here).

**Adversarial review**, road map 2 §5's clause: nine readers, findings
routed by root file, each fix with its own mutant. The questions to hand
them, beyond "is it right": a document that CLOSES mid-recording; a save of
the target document between stop and land; the system indicator's Stop
(`userStopped`) — the file must still land; a display that sleeps or
disconnects (`didStopWithError`, not a hang); an `SCRecordingOutput` that
fails to start (its delegate's error, not a silent empty file); the app
hidden (⌘H) while recording; two documents with the same `displayName` in
the Record Into popup (`NSPopUpButton.addItem(withTitle:)` REMOVES a
duplicate — phase 4's defect, the tag-or-representedObject cure); a mic that
is unplugged mid-recording; and whether `CGRequestScreenCaptureAccess()`
returns synchronously on a first ask or only after the prompt.

**What only a person at the machine can check** (for
`reelcut-remaining.md` §4): the picker's window mode actually presenting and
the choice arriving; the countdown's look; that the recording does not
contain the panel (question 3's outcome) or the status item's own menu; that
the timeline's playback is absent from the file; the menu bar's own
screen-recording indicator naming Reelcut.

### Phase R2 — Pause and resume, and the panel that goes away

*One session. No schema change (v6 stands). No new op (`OP_NAMES` is 55).
No new tool (the catalog is 75; `record_screen`'s RESULT grows two keys).
No FFI change. Decisions 6 and 7 (§0) are its contract; R0's seventh
answer is its evidence. Three size tolls, two of them PURE MOVES landed
alone first: `RecordingResult.swift` (the foot of `RecordingSetup.swift`,
387 → 298) and `RecordingLanding+Microphone.swift` (the microphone half of
`RecordingLanding.swift`, 350 → 238), so every later diff to those files is
attributable; the third, `ScreenRecorder+Pause.swift`, is where the new
code lives rather than a move. Every file under the 400-line cap.*

#### R2a. The session — `ScreenRecorder` learns to pause

`State` gains `paused`: `idle → arming → recording ⇄ paused → finishing →
idle`. `isRecording` (`state != .idle`) is unchanged, so File ▸ Stop
Recording, the quit guard and `.busy` all read a paused recording as one
in progress. Two new entries, MAIN THREAD, synchronous, `throws`:

```
func pause() throws     // .recording → .paused; anything else throws .notRecording
func resume() throws    // .paused → .recording; anything else throws .notPaused;
                        // an addRecordingOutput that throws → .startFailed(sentence),
                        // the state STAYS .paused (the stream still captures; Stop lands
                        // what was recorded)
var isPaused: Bool
```

`pause()` removes the current segment's `SCRecordingOutput` from the stream
(`removeRecordingOutput`; its did-finish arrives on that segment), stops
the microphone's file output when there is one (its did-finish likewise),
stamps the segment's `stoppedAt`, publishes `.silent` to the meter, and
that is all — the stream keeps capturing (R0 q7: 57 fps while paused).
`resume()` mints a NEW segment: `RecordingFiles.stem(at: Date())` through
`uniqueURL` for the movie, `microphoneURL(beside:)` for the mic, a fresh
`SCRecordingOutput` added to the running stream (`addRecordingOutput`;
did-start in ~10 ms), `startRecording(to:)` on the same microphone output,
both stamped where the calls are made and the did-starts stamped where
they land (R1's rule). The `immediate` row of q7 says a resume need not
wait for the paused segment's did-finish, so `resume()` never does.

`Session` becomes the stream, the microphone session and output, the
choice, the hook, the reason, the failure and `segments: [Segment]` —
never empty; a `Segment` is what one file pair owns: `movieURL`, `micURL`,
`output`, `addedAt`, `micRecordingCalledAt`, `screenStartedAt`,
`micStartedAt`, `stoppedAt`, `screenFinished`, `micFinished`, `micFailure`.
The delegates find their segment by IDENTITY of the output for the screen
and by the FILE URL the microphone delegate reports for the mic (one
output writes every segment's file), and a callback for an output that
belongs to no segment of the current session changes nothing, as before.
`elapsed` is the SUM over segments of `(stoppedAt ?? now) − (screenStartedAt
?? addedAt)`, so it freezes while paused and never counts the gap.

`stop()` while `.paused` begins finishing as `.recording` does, except that
no output is attached and the microphone is already stopped:
`beginFinishing` sends `stopRecording` to the mic output only while
recording, calls `stopCapture` either way, and `checkFinished` waits for
EVERY segment's `screenFinished` and (with a microphone) `micFinished` —
the paused segment's may already be true. An external stop
(`didStopWithError`) while paused takes the same path with its reason.
`settle` probes every segment's movie in order, then each one's
microphone file, and answers ONE `RecordingResult` carrying one
`RecordingSegment` per segment; a movie that will not probe is the
recording's failure exactly as in R1 — `filesKept` naming EVERY file,
comma-joined, the single-segment sentence byte for byte what it was — and
a microphone file that will not is that SEGMENT's `micProblem`, the
picture landing without it. (Landing the readable segments of a recording
whose last one failed is the kinder rule and is NOT built here: the R1
posture — a picture failure fails the recording, naming its files — stays,
and this sentence records the alternative.) A microphone that failed on
one segment is still asked to record the next: `resume()` calls
`startRecording` regardless, each segment is judged on its own file, and
`microphoneProblem` (the live sentence) is set on the first failure and
kept, since the panel writes its note once.

`RecordingResult.swift` — already moved — gains the segment:

```
struct RecordingSegment {
    let descriptor: MediaDescriptor      // the movie, probed
    let micDescriptor: MediaDescriptor?  // the mic file, probed; nil with micProblem
    let micOffset: Ticks                 // screen did-start − mic did-start, THIS segment's
    let startedAt: Date                  // the screen's did-start (fallbacks as R1)
    let micProblem: String?
}
struct RecordingResult {
    let segments: [RecordingSegment]     // never empty
    let choice: RecordingChoice
    let stoppedBy: StopReason
    var descriptor: MediaDescriptor      // segments[0].descriptor — "the recording's file":
                                         // the untitled document's source, its name, the
                                         // path a tool addresses it by
    var startedAt: Date                  // segments[0].startedAt
    var micProblem: String?              // the segments' problems joined by a space; nil when none
    var pauses: Int                      // segments.count − 1
    init(segments:choice:stoppedBy:)
    init(descriptor:micDescriptor:micOffset:choice:startedAt:stoppedBy:micProblem:)
                                         // ONE segment — R1's shape, kept so the probe's rows
                                         // and a single-segment construction read as they did
}
```

There is deliberately NO `result.micDescriptor` and NO `result.micOffset`:
a reader that compiled against a first-segment convenience would be
silently wrong for a paused recording, and the compiler is the cheapest
reviewer. `RecorderError` gains `notPaused` ("The recording is not
paused."); `filesKept` keeps its shape and its `movie` / `microphone`
strings may hold a comma-joined list.

#### R2b. The landing — segments back to back

`RecordingLanding.placement(_:in:place:)` lands `n` segments as ONE
grouped edit: each segment's `add_media` in order; with `place`, each
picture clip on ONE track, the first at the playhead and each later one at
the previous clip's END as read off the trial after its apply (the core
snaps a clip's length to the frame grid, so the end is read, never
computed), touching and never overlapping — `add_clip` refuses an overlap
and touching is not one. The two-try track rule is applied to the
SEQUENCE: every picture on the front track of the open container, and if
any one of them refuses there, ALL on a new front track (a recording split
across two tracks would read as two recordings). With microphone files,
one new BACK track "Microphone" (added once), and segment `k`'s mic clip
at `pictureStart_k − micOffset_k` FLOORED at the previous mic clip's end
(and at 0): the R1 head-trim dance — `add_clip` at the floor, `trim_start`
to floor + head, `move_clip` by −head — with the floor in place of 0, so
two segments' voices can neither overlap (a refusal) nor be placed late.
`Placement` gains `clipIds: [UInt32]` and `micClipIds: [UInt32]` (the
existing `clipId` / `micClipId` are the first of each, so every reader
still compiles; the panel selects them all). `place: false` lands every
media and no clip.

`microphonePlacement` becomes **`remainderPlacement(_:in:)`**: for the
untitled document that already holds segment 1's picture at 0 on track 1
(`makeProject`), the ops for everything ELSE — segments 2…n's pictures on
that track from clip 1's end, then every mic clip by the rule above — and
nil when there is nothing to add. Its undo step is named by
`remainderActionName(for:)`: "Add Microphone" for one segment with a
microphone (R1's name, R1's reason), "Add Recording Segments" otherwise.
`ProjectDocument.untitled(around:)`'s ORDER is unchanged: the import count
before the remainder's edit, the remainder before the window, and the
first segment is what the document IS.

#### R2c. The chrome — the status item is the recording's controls

`RecorderStatusItem` takes three closures — `onPause`, `onResume`,
`onStop` — and `update(elapsed:paused:)`; when `paused` flips it rebuilds
its menu from `menuTitles(paused:)`, PURE: `["Pause Recording", "Stop
Recording"]` recording, `["Resume Recording", "Stop Recording"]` paused.
`title(elapsed:paused:)` draws the coral dot and the time while recording
and a pause glyph (`❚❚`) in the menu bar's own colour with the FROZEN time
while paused; the tooltip says which. The label's arithmetic is untouched.

`RecorderPanelController.Phase` gains `.paused` (the button reads Stop; the
footnote the pause glyph and the frozen time). `+Pause.swift` (new) holds
`pauseRecording()` (`.recording` → `recorder.pause()` → `.paused`; a throw
beeps) and `resumeRecording()` (`.paused` → `recorder.resume()` →
`.recording`; a throw sets the note and stays paused). `record(_:)` and
`stopRecording()` treat `.paused` as `.recording`; the tick runs through
`.paused` (the meter poll is a no-op there — the recorder guards it — and
the recorder silenced the bar at the pause). **`recordingDidStart` hides
the panel for EVERY source** (decision 7): `showWhenLanded = window is
visible`, `hiddenForRecording = true`, `orderOut`. `recordingEnded` clears
`hiddenForRecording` and shows NOTHING; `landed`, `failedToLand` and the
failure arm end in `revealIfNoted()` — the panel comes back only when
`showWhenLanded` and the note is non-empty, and `showWhenLanded` is
cleared either way. `show()` still beeps while hidden (the quit guard and
the welcome button reach it); File ▸ New Recording… still reads Stop
Recording and stops. `AppDelegate+Recording.newRecording`'s `.paused` arm
stops through the panel as `.recording` does.

#### R2d. The mirror — `record_screen`'s result, and its menu-bar item

`RecordingToolChrome` builds the same item with `onPause` / `onResume`
calling `ScreenRecorder.shared.pause()` / `resume()` (`try?` — a refusal
there is a race with the recording's own end and beeps nothing) and its
1 Hz tick passes `paused: recorder.isPaused`. The span is WALL CLOCK,
unchanged: a person who pauses an agent's recording from the menu bar
shortens what was recorded, and the result says so. The result gains
`pauses` (an integer, `segments.count − 1`) and `segments` (an array, one
entry per segment, ALWAYS present: `path`, `duration`, `started_at`, and
`mic_path`, `mic_duration`, `mic_offset`, `mic_problem` on R1's terms, plus
`media` / `clip` / `mic_media` / `mic_clip` when they are known — from the
placement for a document landing, by path for a new project). The
top-level keys keep their R1 meaning for the FIRST segment (`path`,
`width`, `height`, `fps`, `has_audio`, `audio_tracks`, `mic_path`,
`mic_duration`, `mic_offset`, `media`, `clip`, `mic_media`, `mic_clip`);
`duration` becomes the TOTAL recorded (the sum), which for an unpaused
recording is what it was; `mic_problem` is the joined text. Every failure
sentence that named "the recording" names every segment's file.
The description gains the Pause sentence and the two keys; the catalog
count stays 75 and the parity check has nothing new to see.

#### R2e. Proof, review, lockstep

`tools/proof/recording_spike.py` question 7 is the measurement of the
framework pair and stays as the record. `recording_probe.py` grows: section
3's faked session becomes a segment (`Session(segments:)`), with rows for
`pause()` / `resume()` / a stop while paused / the delegates finding a
segment by output identity and mic file URL / `elapsed` frozen /
`notPaused` and `notRecording` by name / `filesKept` over two files; section
4 rows for a two- and a three-segment result (touching clips on ONE track
with the ends read off the handle, the sequence falling to a new track
together, the mic floor with an offset that would overlap, `place: false`,
`remainderPlacement` through the real untitled order and its two names);
section 5 rows for `menuTitles`, `title(paused:)`, the `.paused` phase's
button and footnote, the panel HIDDEN after `recordingDidStart` for a
DISPLAY source (driven, `isVisible` read), and `revealIfNoted` both ways;
section 7's description phrases; and a NEW section 9, the probe's own
GRANTED tier under the terminal's grant (R0 q1; the spike proves a bare
Mach-O can): a real `ScreenRecorder()` on the main display — start, 1 s,
`pause()`, `elapsed` read twice 0.5 s apart and equal, `resume()`, 1 s,
`stop()` — answering a result with TWO segments whose files probe at about
a second each and are named by their own start times; skipped BY NAME
with a count under a false preflight or zero shareable displays.
`recording_proof.py` reads the two new keys and the Pause phrase off the
description, and `pauses == 0` with one segment on its existing detection
call. Mutants, one per rule, in the probe's table: the segment placed at
the playhead instead of the previous end; the mic floor dropped; the menu
not rebuilt on pause; the panel's hide narrowed back to `.picked`; the
reveal made unconditional; `elapsed` counting through a pause; `resume`
reusing the first segment's mic offset.

Review: five readers over the uncommitted tree — the machine's races (a
did-finish landing after the resume; a Stop inside the ~10 ms between a
remove and its did-finish; an external stop while paused; two pauses in a
row), the landing's arithmetic, the chrome (the hidden panel's notes; the
item's menu under the tracking run loop; quit while paused), the tool
(span versus pause; the keys; the files a failure names), and the
documents against the code. Fixes routed by root file with a mutant each;
then the lockstep pass: `record_screen`'s description, spec §7.4's file
map and §7.9's tool list, §11's two decisions, `CLAUDE.md`'s paragraph,
`app/CLAUDE.md`'s recorder entries, `tools/proof/README.md`, and
`reelcut-remaining.md` §4 (what a person checks: the item's two menus, the
pause glyph, the system indicator staying up through a pause, the panel
returning only with a note).

## 4. Proposed keys and menu items

Checked against spec §9 by the scout; a phase that binds one promotes its
row into §9.

| Keys | Action | Phase |
|---|---|---|
| ⌥⌘N | File ▸ New Recording… (reads Stop Recording while one runs) | R1 |

Menus: File ▸ New Recording… directly under New Project, with no separator,
because both make a document out of nothing; nothing in the Clip menu, since
a recording is not an edit of the selection.

## 5. Considered and left out

- **Camera recording.** A second capture stack (`AVCaptureSession` +
  `AVCaptureMovieFileOutput`, a delegate API), a second file, a clip on a
  front track. One session on its own once R1 has landed the panel and the
  landing, which it would share; spec §1's exclusion stands until then.
- **Keystroke and click callouts reconstructed after the fact.** An event
  tap, an Input Monitoring grant, a sidecar format and a text-clip
  generator. `showMouseClicks` is the free tenth of it and is taken.
- **A pre-roll microphone meter.** Needs a capture session running before
  Record is pressed; the meter lights during the recording instead.
- **A global stop hotkey.** Needs a grant of its own; the status item is
  the answer.
- **Trimming the countdown out of the file**, or any post-processing of
  the recording. It is ordinary media; the cutter trims.
- **Recording into the package directly.** An untitled document has none
  (decision 2), and a saved one is a Consolidate away.
- **HDR capture.** ScreenCaptureKit's default 8-bit BGRA is what the
  compositor consumes; nothing in the pipeline is wide-gamut.
- **Voice-over recording as its own command** (road map 2 §4's bullet):
  once R1 records a microphone, a picture-less recording is a Source popup
  entry away and is left for whoever wants it.

## 6. What "done" means here

The same as road map 2 §5: the proof exists as measured output from the
built binary and from probes, `make test` 494 and `make lint` clean,
`make typecheck` at its baseline (0 errors, the same 4 AVFoundation
warnings), the parity log EMPTY, the catalog at 75, every earlier proof
unchanged against the final binary (66, 85, 121, 8, 84, 88, 167, 92, 79,
214 over MCP — phase 9's exact count now a floor — and 26, 33, 59, 81, 70,
78, 150, 48, 62, 101 offscreen), the status table above saying "done" with
the date and the commit, and `CLAUDE.md`'s milestone status, the spec's
tables and the README saying what now exists. Plus road map 2's clause: the
change has been read back adversarially and what that found is fixed and
covered. And one of this road map's own: **R0's five answers are in this
file, dated, before R1's first wave is briefed.**

## 7. How the work is run

The shape that landed road map 2's phases 2, 3, 7, 8, 9 and the
remainder, in order:

1. **R0**, by one agent, its script tracked, its answers pasted above.
2. **Scouts**, read-only, one per seam, each returning facts with
   file:line and a `blockers` field naming what this plan says that the
   code says cannot be built: the ScreenCaptureKit surface as the SDK has
   it; `ProjectDocument`'s untitled path and `importSourceURL`'s
   visibility; the agent server's off-main shape and the parity check's
   four parts; the menus, the welcome window and `applicationShouldTerminate`;
   the proof infrastructure and the count handover.
3. **The toll** — `AgentCatalog+Files.swift` — landed and gated alone.
4. **Wave 1**, four lanes on disjoint files with the two seams declared
   verbatim in every brief: lane A `RecordingSetup.swift` +
   `ScreenRecorder.swift` (+ the probe's rows for them); lane B
   `RecordingLanding.swift` + `ProjectDocument+Recording.swift` (+ its
   rows); lane C the panel, the status item, `AppDelegate+Recording.swift`,
   the menu item, the welcome button, `project.yml`; lane D
   `AgentServer+Recording.swift`, the catalog entry, `recording_proof.py`.
   The seams: `ScreenRecorder.start(filter:choice:completion:)` /
   `stop(completion:)` / `RecordingResult` (A ↔ C, D) and
   `RecordingLanding.land(_ result:, into:, completion:)` (B ↔ C, D). Lanes
   that need `make app` run after lanes that measure the existing binary.
5. **Proof and adversarial review in parallel**, then fixers by root file,
   each fix with its own mutant, then the orchestrator's lockstep and
   documents pass, then the commit.
