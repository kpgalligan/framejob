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
  status item is the recording's whole chrome — Pause Recording and Stop
  Recording, then Resume Recording and Stop Recording while paused — and the
  panel returns after the landing only when it was on screen as the
  recording began and the landing's note is non-empty (a stop from the
  SYSTEM's own indicator — Reelcut's item's Stop writes no note — a closed
  target, a microphone problem, a refused resume, a file the landing could
  not place, a failure). ⌥⌘N shows it again; while it is hidden, the quit
  guard opens the item's menu rather than beeping.
