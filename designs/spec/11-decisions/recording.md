# Spec §11 — decisions: Screen recording (road map 3)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **Screen recording is IN; camera recording and callouts stay OUT** (road
  map 3, reversing §1's day-one non-goal). A screen recording is the input
  the whole product was shaped around; camera capture is a second capture
  stack and callouts are a metadata format plus an Input Monitoring grant.
  What ScreenCaptureKit draws into the pixels for free — the cursor, and
  a ring around each click — is taken; nothing is reconstructed afterwards.
- **A recording is ordinary media.** The recorder writes a file and the app
  imports it through exactly the path File ▸ Open and Add Media… use
  (`adoptImported`, the two-try placement). The model learns nothing: no
  source kind, no flag, no schema bump. Every op, cache and export treats a
  recording clip as the media clip it is.
- **The file lives in `~/Movies/Reelcut Recordings/`**, named by date and
  time, never in the package and never in the temporary directory: an
  untitled document has no package (§5.6), and a recording is ORIGINAL
  footage, so the one place it may not go is where a cache is regenerable.
  Consolidate carries it in on the same terms as any other file.
  `-RCRecordingFolder` overrides the folder for a proof.
- **The canvas takes the recorder's RATE; the media record takes the
  file's.** ScreenCaptureKit delivers a frame only when the screen changes,
  so its files are variable-rate and the probe honestly reports something
  like 24981/1000 (measured); the untitled document is built at the 30 or
  60 the panel asked for, because that is the grid the person chose, and
  `set_canvas` is NOT used for it afterwards — an untitled document's
  first project is not an undo step, and the rate is part of what the
  document IS.
- **The panel asks for the grants; the tool never does.** `Transcriber`'s
  rule for two grants: Screen Recording (`CGPreflightScreenCaptureAccess`
  reads, `CGRequestScreenCaptureAccess` asks) and Microphone
  (`AVCaptureDevice.authorizationStatus`, `requestAccess`). The microphone
  status is read BEFORE any `AVCaptureDeviceInput` is constructed, because
  that initializer prompts on its own. `record_screen` reads and refuses by
  name with the fix in the sentence. The built app needs BOTH the plist
  usage key and the hardened-runtime entitlement
  `com.apple.security.device.audio-input` for the microphone; Screen
  Recording needs neither.
- **A press of Record asks for Screen Recording once, and every later
  press opens System Settings at the pane** (2026-09-28). The first press
  without the grant calls `CGRequestScreenCaptureAccess`, and the panel
  remembers it across launches in `ReelcutScreenRecordingAsked`, because
  the system prompt appears once per app, not once per launch; every later
  press opens `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`
  through `NSWorkspace` and the note says System Settings is open at that
  pane (the plain refusal when `open` answers false). The flag counts only
  in a launchd-owned launch (`getppid() == 1`, `launchClause` empty): a
  shell-launched press always asks and never writes it, because TCC gives
  that prompt to the terminal (R0 q1), and a flag written there would stop
  a later Finder launch from ever being put in the pane's list. A
  `.denied` or `.restricted` microphone opens `Privacy_Microphone` the same
  way; `.notDetermined` still asks, and a prompt's answer never opens
  Settings. Only the panel opens a pane: `record_screen` never does, and
  opening Settings is no edit and gets no mirror. Measured on macOS 26.5.1
  (25F80): System Settings is the default handler of
  `x-apple.systempreferences`; `SecurityPrivacyExtension.appex` declares
  `legacyBundleIdentifier` `com.apple.preference.security` with
  `allowsXAppleSystemPreferencesURLScheme` true, and its binary holds
  `Privacy_ScreenCapture` and `Privacy_Microphone`. Accepted: the flag is
  never cleared, so after `tccutil reset ScreenCapture` a launchd-owned
  press opens the pane rather than prompting (the pane's + adds the app).
  Whether the pane lands on its row is a person's check (REC-1, REC-2 in
  `docs/manual-checks.md`). **Before either prompt, and before opening a
  pane, the panel steps down from `.floating` to `.normal`**: a floating
  panel sits over every normal window on the screen, and the prompt and
  System Settings are another process's normal windows — the person found
  the Screen Recording prompt hidden behind the panel. The next press that
  goes on, a granted microphone's answer, and `show()` float it again.
- **Microphone and system audio are two sources and stay two FILES.**
  Measured (road map 3's R0): with both on, `SCRecordingOutput` writes ONE
  stereo track that is their SUM, inseparable and clipping when both are
  loud — the one thing a screencast cutter cannot repair afterwards. So the
  microphone is never on the recording stream; it is an `AVCaptureSession`
  writing its own `.m4a` beside the movie, started first in the same
  run-loop turn, and it lands as its own clip on its own track at the
  offset the two did-start callbacks measured (a per-SEGMENT number since
  R2 — R0 q7 measured a different one at every resume — never a constant).
- **Undo of Add Recording leaves the files on disk**, exactly as undoing Add
  Media… does. A recorder that deleted footage on ⌘Z would be the only
  destructive undo in the app. For a recording that opened as a new project
  the first segment IS the document and has no step; the rest is one step,
  Add Microphone (one segment with a voice) or Add Recording Segments.
- **A paused recording is a SEQUENCE of files over ONE stream** (road map
  3's R2, 2026-09-12). ScreenCaptureKit has no pause: the only lever is
  removing the recording output — its file closes — and adding a fresh one
  to a new file while the stream keeps capturing, measured (R0 q7) at
  5–25 ms to close, 8–10 ms to start and 57 fps through the pause; the
  microphone's writer is stopped and restarted per segment on its one
  session. Each segment is named by its OWN start time, carries its own
  measured offset, and lands as a clip touching the previous one; the model
  still learns nothing, and nothing joins the files afterwards.
- **The recorder panel goes away when a recording starts, for every
  source, and comes back only with something to say** (R2). The menu bar's
  status item is the recording's chrome — Pause Recording and Stop
  Recording, then Resume Recording and Stop Recording while paused; File ▸
  Pause Recording is a second door to pause (below) — and the panel returns
  after the landing only when it was on screen as the recording began and
  the landing's note is non-empty (a stop from the SYSTEM's own indicator —
  Reelcut's item's Stop writes no note — a closed target, a segment left
  out as unreadable, a microphone problem, a refused resume, a file the
  landing could not place, a failure). ⌥⌘N shows it again; while it is
  hidden, the quit guard opens the item's menu rather than beeping.
- **The recorder panel takes key only from an active Reelcut** (#137,
  2026-09-29). Shown with Reelcut active (File ▸ New Recording…, ⌥⌘N, the
  welcome button), it comes to the front key, with Record on Return. Shown
  with Reelcut in the background (a script's `perform_menu_item`, a Dock
  quit while a tool records), it is ordered front without key: Reelcut
  stays inactive, and the person's typing, Return included, stays in the
  app in front. A click on it still works without activating Reelcut
  (`.nonactivatingPanel`).
- **A segment whose movie will not probe is left out** (#97, 2026-09-29).
  The walker that probes a finished recording's segments skips it and goes
  on; the result's `unreadable`, and the landing's note at both doors (the
  panel's and `record_screen`'s), name it and the files it kept on disk.
  Only a recording with NO readable movie fails: the first segment's error,
  `namingFiles` naming every file, so one segment reads byte for byte as
  before. A segment whose recording output reports a FAILURE after its
  `stoppedAt` was set (a pause's or the stop's) is left out the same way
  (#181, 2026-09-30): the failure is that segment's, the recording goes on
  or finishes, and the walker leaves it out UNPROBED with the writer's
  sentence as its `unreadable` reason. Only a did-fail for the segment
  still recording (no `stoppedAt`) is the recording's failure. A
  microphone failure the machine asked for — the segment's
  `stoppedAt` set: a pause's or the stop's did-finish, e.g. −11805 for a
  writer stopped before its first sample — is that segment's `micProblem`
  only; `microphoneProblem`, the live note, is a microphone that dies
  MID-segment.
- **File ▸ Pause Recording** (#98, 2026-09-29). Directly under New
  Recording…, retitled Resume Recording from the RECORDER's state, enabled
  only while it is recording or paused, with no key. It is routed as Stop
  is: the panel's own recording through the panel, any other (a tool's)
  through the recorder. It has **no MCP mirror**: a pause is recorder
  state, not a project edit, so spec §7.9's every-user-visible-edit rule
  does not reach it (Settings' precedent); `record_screen`'s span is wall
  clock and a pause is a person's act; and `perform_menu_item` reaches the
  item in a Release build.
