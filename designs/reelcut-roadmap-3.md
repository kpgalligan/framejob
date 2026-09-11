# Reelcut — road map 3: recording

**Status: PLANNED, nothing built.** Road map 2 is complete
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

## 1. Status

| Phase | Theme | Sessions | Schema | Status |
|---|---|---|---|---|
| R0 | The spike — five questions measured before design leans on them | ½ | — | planned |
| R1 | Screen recording | 2–3 | — | planned |

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
