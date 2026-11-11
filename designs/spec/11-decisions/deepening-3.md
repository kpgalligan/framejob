# Spec §11 — decisions: Deepening, an agent's `open_project` off the main thread onward (road map 7)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The entries continue [`deepening.md`](deepening.md), so a citation never has to say which file. This
file holds #231, #233, #227 and #234. #326 on are in [`deepening-4.md`](deepening-4.md). It is new
because `deepening.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries
moved here unchanged, and an "above" or "below" in one may now point into a sibling file.

- **#231 — An agent's `open_project` reads off the main thread and answers
  when the read ends, with no window and no question** (issue batch B79;
  amends #228-P's and #228-O's tool-call and risk sentences; MC-5 holds).
  `open_project` is an `offMainTools` member, in three steps. **Step A, on
  main** (`onMain`): the already-open answer, else the file's type. **Step
  B, on the lane's thread inside `MediaImporter.withoutAsking`:**
  `makeDocument(withContentsOf:ofType:)`, the whole read, as AppKit's own
  concurrent read does it (`canConcurrentlyReadDocuments`). **Step C, on
  main:** the holder re-check — a document that came to hold the path
  during the read wins: the made document is closed, never added and never
  shown, and the call answers `already_open` — then add, window
  controllers, show, the recent note and the answer (amended by #234: steps
  A and C also see a person's open of the path still in flight, and wait
  for it). `withoutAsking` is a
  property of the reading thread and every reader of it runs synchronously
  on that thread (`MediaImporter.isWithoutAsking`), so it covers the probe,
  the copy, the ffmpeg policy and the re-copy on open, which passes no
  watch inside it as it passes none on main. **During the wait:** main is
  free — every window usable; the person may edit, open, close, quit;
  every other tool call, MCP's or any window's assistant's, waits on the
  lane's lock, as during `export` (AI-2); a quit ends the process with the
  call unanswered, as `agent_socket_proof.py`'s K14 shows for `export` and
  its K15 for `open_project` (amended by issue batch B81, which measured
  what B79 argued from K14), and leaves the `.partial.mov` (#228-P O8).
  **The copy lock cannot deadlock:** it is
  never held across a wait on main (a watch only posts to main, and a tool
  call passes none), and the lane's lock is never taken on main or by a
  person's import. **The risks it accepts:** no progress and no cancel for
  the agent (MC-5); other tool calls wait the copy's length; a read AppKit
  itself runs on main still copies there, with no window. **Measured**
  (2026-10-03, macOS 26.5.1, Apple M2 Max; `python3
  tools/proof/agent_open_proof.py`, a 278.8 MiB VP9+Opus WebM, a 10 ms
  main-thread timer counting during each call, three runs): `open_project`
  of the WebM answered in 3.018 s, 1.501 s and 1.403 s, with 107, 50 and 52
  main-thread ticks that saw the copy's `.partial.mov` (A2); the re-copy on
  `open_project` of its package answered in 1.187 s, 0.796 s and 9.504 s,
  with 69, 57 and 373 such ticks (A5); no tick of either saw a progress
  controller (A3, A6); and a document that took the package's path during
  the read was answered as `already_open`, one document at the path (A7).
  With `"open_project"` out of the off-main set (`--mutant open-on-main`) 0
  ticks saw the partial in either call. On the built app,
  `container_import_proof.py`'s M12 opens a WebM by `open_project`.
  **Amended by #235** (issue batch B81): **the spread of those seconds is
  the disk's, not the app's.** The designer ran B79's probe 43 times in a
  scratch home over the same 278.8 MiB fixture (2026-10-03; the data volume
  98 % full, 23 GiB free of 926; load average 7–81): 57 copies answered in
  0.383–8.898 s, five of them in 3 s or more (3.601, 3.704, 6.447, 7.995,
  8.898). In the four slow ones timed, the `.partial.mov` existed for 3.45
  of 3.601 s, 5.99 of 6.447, 7.87 of 7.995 and 8.54 of 8.898 — so the wait
  is not the copy lock, the lane, the index or step C — and it grew the
  whole time, with stalls of up to 1.56 s; `iostat -d -w 1 disk0` read
  45–134 MB/s through the three longest against 289–519 MB/s at the peak of
  a fast copy; `sample <pid> 3 5` of two slow copies found AVAssetWriter's
  `com.apple.coremedia.formatwriter.qtmovie` thread inside `pwritev` in 302
  of 469 and 455 of 464 samples (30–71 of 35–77 in fast runs); and main
  kept ticking through them (77–547 ticks a call, longest gap 94–885 ms).
  Nothing in the product changes for it. **A2 and A5 are counts, not
  timings:** each wants at least 3 main-thread ticks that saw the partial
  (a re-copy's went as low as 13 on that host, so B79's floor of 10 was the
  host's), and each call's row prints where its seconds went: before the
  partial was first seen, while it was written, after it was last seen. One
  run of this batch's (the data volume then 88 % full, 112 GiB free):
  `open_project` of the WebM took 1.146 s — 0.252 s before, 0.210 s while
  the partial was written, 0.684 s after — with 22 partial ticks, and the
  re-copy 0.452 s — 0.065, 0.208 and 0.179 s — with 19. **A quit during
  the read is measured** (`python3 tools/proof/agent_socket_proof.py`, row
  K15: the built app in a scratch home, a 532.2 MiB WebM, K14's quit event
  sent by a sender armed before the call): the event went when the copy's
  `.partial.mov` appeared, 0.099 s into the call, with nothing yet to read
  on the call's connection; the app exited in 0.07 s, its socket file was
  gone, the connection read 0 bytes and closed by EOF, and `Rewrapped/`
  held exactly `big-<16 hex>.partial.mov`. The next launch's `open_project`
  of the same file answered a project whose one media is `big-<16
  hex>.mov`, on disk, with no partial left (#228-P O8).
- **#233 — A file the opt-in ffmpeg step converts records the file it was
  made from as the media's `original`, exactly as the built-in copy does;
  the re-copy on open stays the built-in copy's alone** (issue batch B80;
  amends #228-O's "ffmpeg's opt-in conversions record none" sentence).
  `MediaImporter.probeConverted` sets `original {path, bookmark}` on the
  descriptor of every conversion that probes, on every door through
  `probeAllowingRewrap`, so the name (`MediaSnapshot.name`), the Media tab
  row's tooltip, Reveal in Finder, and `import_media`'s and
  `relink_media`'s `original` are #228-O's, unchanged, and a relink to a
  file ffmpeg converts records it. The tooltip of a re-encoded conversion
  keeps B78's sentence, "`<original path>` — copied into Frame Job's Rewrapped
  folder." (the owner's choice 1, the default kept). **The re-copy on open
  is unchanged: the built-in copy only, never ffmpeg, never a question.** A
  missing ffmpeg-made copy stays missing (the slate, the badge, Relink…): a
  non-Matroska original fails `isMatroska`, and a Matroska one is refused
  `.unsupported` by `ContainerRewrap.rewrap`. The one free case, already in
  the code: a Matroska original whose conversion is still on disk under its
  digest name is relinked to it by `ContainerRewrap.assist`'s
  `existingRewrap`, with no ffmpeg run. **The risk it accepts:** a
  non-Matroska original with its conversion still on disk is not relinked
  (O41's rule). **Measured** (2026-10-03, macOS 26.5.1, Apple M2 Max,
  ffmpeg 9.0.2; `python3 tools/proof/ffmpeg_rewrap_proof.py`, a VP9 + FLAC
  MKV under a scratch home with `-RCFFmpegImport always`): the import's
  descriptor carries `original.path` and a bookmark that resolves to the
  MKV (O1); `import_media` answers `original` and `get_project` carries it
  (O2); the media is named `v0.mkv`, the tooltip's first line is
  "`<the MKV's path>` — copied into Reelcut's Rewrapped folder." and Reveal
  is the MKV (O3); with the conversion discarded the re-copy on open
  answers the same project, ffmpeg's log gains no line and `Rewrapped/` no
  file (O4), and with it still on disk the media's path becomes the digest
  file with no ffmpeg run (O5). With the re-copy sent through the whole
  import funnel (`--mutant recopy-ffmpeg`) O4 fails: the log gains a line
  and `Rewrapped/` a file.
  **Amended by NM-5** (rename R0): the tooltip's "copied into Reelcut's
  Rewrapped folder." is now "copied into Frame Job's Rewrapped folder."; the
  measured run above is quoted as it printed.
- **#227 — The opt-in ffmpeg step copies a VP9 Profile 0 or 2 video stream
  instead of re-encoding it, only when the copy's frame times are exact,
  which the product checks on the copy itself before keeping it; every
  other source re-encodes as before** (issue batch B80; amends
  Foundations' "AVFoundation, not ffmpeg"). **Copies:** the first video
  stream is `vp9`, ffprobe's `profile` is 0 or 2
  (`FFmpegRewrap.vp9CopyProfiles`), its `r_frame_rate` is `N/D` with both
  positive integers, ffmpeg's snapped copy exits 0, the copy's video
  packets sit at `p0 + k·D/N` s for every k with `p0` a whole number of
  frames (the frame check, `FFmpegRewrap.keepsFrameGrid`), and the file
  then probes and decodes its first frame. **Re-encodes, as before:** VP9
  Profile 1, 3 or unknown; no usable `r_frame_rate`; every variable-rate
  source — dropped frames, jittered times, a header rate that is not the
  true rate — because its copy fails the frame check; a user's ffmpeg whose
  `setts` has no `prescale` (the copy fails); a copy that will not decode;
  every non-VP9 codec, untouched. **The file** is MP4-format (`-f mp4`:
  §7.7 measured that ffmpeg writes VP9 into no `.mov`, and B72's V10/V17
  that VP9 Profile 0 and 2 MP4s decode) under the unchanged
  `<stem>-<16 hex>.mov` digest name and `.partial.mov`, so `existingRewrap`,
  `discard` and the built-in copy's reuse are untouched; sound: `aac` and
  `alac` are copied, everything else is AAC at 256k. **The snap:** the
  copy's command is the stream copy's with `-bsf:v
  setts=time_base=D/N:prescale=1` directly after `-c:v copy` (one argv
  element, never a shell). **Frame accuracy does not regress against the
  re-encode:** `setts … prescale=1` rounds each packet's time to the
  nearest 1/rate, which is what the re-encode's encoder time base does, and
  the frame check (`ffprobe -v error -select_streams v:0 -show_entries
  stream=time_base:packet=pts -of csv=p=0`, read before the partial is
  moved into place) refuses any copy where that did not yield consecutive
  frames, so no unchecked copy ever holds the digest name. **The
  fallback** is the frame check, the product's own probe (`waitForProbe`,
  which runs `DecoderSupport.decodesFirstFrame`) or ffmpeg's failure — then
  the re-encode, once (`FFmpegRewrap.assist(…, reencodingVP9: true)`, which
  reuses no file (amended by issue batch B81: but a re-encode this process
  made and kept, below), obeys the policy as the first call does and, under
  `ask`, asks again with the Convert text; a timeout is not retried). The question
  for a copy keeps the stream-copy texts (the owner's choices 2 and 3, the
  defaults kept). **Measured at spec time** (ffmpeg 9.0.2, 128×72
  `testsrc2`, `AVAssetImageGenerator` at zero tolerance asked for frame k
  at exactly k·D/N; "exact" = the answer's time equals the request's): an
  unsnapped copy is exact for 20 of 60 requests at 30 fps (packets 0, 528,
  1072 /16000) and 2 of 60 at 30000/1001, where the re-encode is 60 of 60
  on both; the snapped copy is 60 of 60 at 30 (Profile 0 and 2) and at
  30000/1001 (packets 0, 1001, 2002 /30000), and n of n at 24, 25, 60, 120,
  24000/1001 and 19001/317 (what Matroska reports for 59.94), with packet
  times identical to the re-encode's on each, and a video starting 100 ms
  late keeps p0 = 3 frames in both. Rejected snaps: `-video_track_timescale
  30000` alone on 30000/1001 is 2 of 60 (packets 0, 990, 2010);
  `setts=time_base=…:ts=round(TS*TB/TB_OUT)` exits 0 and 56 of 60 requests
  fail, which is why the product checks the file and not the exit code.
  Variable rate: a source with every fifth frame dropped, and one with
  times jittered by 0/9/18 ms, both report `r_frame_rate` =
  `avg_frame_rate` = 30/1, so no header field tells them apart; their
  snapped copies (0, 512, 1536 … and 0, 512, 1536, 1537 …) fail the frame
  check at k = 2 and re-encode. The frame check on a 10-minute,
  18,000-frame, 101 MB copy took 0.11 s. **Measured by the proof**
  (2026-10-03, macOS 26.5.1, Apple M2 Max, ffmpeg 9.0.2; `python3
  tools/proof/ffmpeg_rewrap_proof.py`, 30-frame 128×72 fixtures, the same
  count over frames 0–29): the command's own output is 30 of 30 right and
  30 distinct times at 30/1 (T1), at 30000/1001 (T2) and for Profile 2 at
  30/1 (T3); the product's kept copies of the same three sources are `vp09`
  after one `-c:v copy … -f mp4` run and count 30 of 30 (V1, V2, V6), the
  first two with an `mp4a` sound entry and a first frame that decodes to
  128×72 BGRA; a Profile 1 source is re-encoded in one run (V3); a copy
  that ffmpeg fails (V4), a copy that will not decode (V5), a jittered
  source (V7) and a gapped one (V8) each import as `avc1` after two runs,
  the copy and then the re-encode, leaving one file and no partial. Without
  the snap (`--mutant no-snap`) the command's output is 10 of 30 right at
  30/1 (T1, T3) and 1 of 30 at 30000/1001 (T2), and the frame check sends
  all three product copies to the re-encode; without the frame check
  (`--mutant no-check`) the jittered and the gapped copies are kept as
  `vp09`. **The risks it accepts:** a
  variable-rate VP9 costs one discarded copy before its re-encode, and
  under `ask` it is asked about a copy and then about the conversion; VP9
  alpha is dropped (#216); a cached VP9 copy re-imported through the
  Matroska door that no longer decodes is refused once and converted on the
  next import. **Amended by issue batch B81**, which closes the two risks
  B80 recorded here (a wait that counted one conversion, and two imports of
  one failing VP9 file each discarding the other's re-encode) and two
  smaller debts. **The wait covers what one import's own runs can take:**
  `import_media`'s and `relink_media`'s wait (`AgentServer.probeCeiling`) is
  `FFmpegRewrap.longestAssist` plus three header probes
  (`MediaImporter.probeTimeout`, 30 s each: the source, the copy, the
  re-encode), and `longestAssist` is the sum of every bound the step has:
  the plan's ffprobe (`planTimeout`, 20 s), the frame check
  (`frameCheckTimeout`, 300 s), the encoder query (`encoderQueryTimeout`,
  20 s), two conversions (`longestConversion`, 4 h each: the copy, then the
  re-encode) and `run`'s grace on each of those five runs (`runGrace`, 20 s,
  half for the tool to exit after `terminate` and half for its pipes). The
  sum counts ONE plan because the second attempt takes the first attempt's
  (`assist`'s `planned`). **One re-encode per file:** under the conversion
  lock the second attempt first asks whether the file at the destination is
  a re-encode this process made and kept — the path's file number
  (`FileAttributeKey.systemFileNumber`) equals the one noted when that
  re-encode finished (`isKeptReencode`, `noteReencode`) — and answers it;
  only otherwise does it discard and re-encode. A conversion that will not
  probe is thrown away only while the file at its name is still the one
  that was probed (`discard(_:ifStill:)`, the file number read before the
  probe), so one import's failed probe never removes a file another import
  has since put there. **A source whose first plan copies no VP9 gets no
  second attempt** (`MediaImporter.probeConverted`): the first attempt's
  error is thrown with no second `assist`, which is the ffprobe run that
  call used to make before answering nil. **The frame check's arithmetic is
  `FFmpegRewrap.onFrameGrid`,** pure: the next expected time is computed
  with `addingReportingOverflow`, only before a further packet, and an
  overflow answers false, where B80 added unchecked after every packet, the
  last included. **The risks that stay:** the note of a kept re-encode is
  this process's own, so a second Frame Job process importing the same failing
  file at the same moment still discards and re-encodes; and the wait counts
  one import's own runs, not the time it queues behind another import —
  conversions are serialised by one lock held for a whole ffmpeg run
  (`FFmpegRewrap.conversionLock`), so an `import_media` that arrives while a
  person's conversion runs can still answer a timeout before its own
  conversion ends (read from the code, not measured).
  **Measured by the proof, B81** (2026-10-03, macOS 26.5.1, Apple M2 Max,
  ffmpeg 9.0.2; `python3 tools/proof/ffmpeg_rewrap_proof.py`, `passed
  22/22`, and `passed 23/23` on 2026-10-04 with #234's row M1 added, with an
  `ffprobe` wrapper beside the ffmpeg one that logs each run): the jittered
  source imports after its two runs with exactly one plan of it in
  `ffprobe.log` (V7); two imports of one jittered file started together both
  import `avc1` at one digest path after 1 encoder run and 1 or 2 copy runs,
  leaving 1 file and no partial, and the second attempt then called directly
  answers that path, `ffmpeg.log` gaining no line and the file's number
  unchanged (V9); `discard(_:ifStill:)` leaves a file that replaced the one
  numbered and removes the one numbered (V10); `onFrameGrid` answers true
  for one packet at 9223372036854774000, the largest multiple of a 3000-unit
  step not above `Int64.max`, and false for two packets from there (G1);
  `probeCeiling` reads 29330 s and `longestAssist` 29240 s (C1); and a
  Profile 1 source whose re-encode will not open imports nothing, with the
  source's own refusal, after one plan and one run, no file left (P1).
  Without the kept check (`--mutant discard-kept`) only one of V9's two
  imports lands, after 2 encoder runs, and the direct call re-encodes again;
  with the second attempt planning again (`--mutant plan-twice`) V7 and P1
  each count 2 plans; `--mutant pure-rows` fails V10, G1 and C1, where the
  ceiling reads 14930 s.
- **#234 — While either side's read of a file is in flight, an agent's
  `open_project` and a person's open of it end as one document at the path,
  or the agent is refused by name past a bound; `new_project {path}` and
  `save_project {path}` refuse a path a person's open is reading** (issue
  batch B81; amends #231's steps A and C and #40's held-path check; MC-5
  and #231's `withoutAsking` hold). **The hole it closes is AppKit's:** a
  document added for a URL while
  `openDocument(withContentsOf:display:completionHandler:)` is reading it
  is not seen when that read ends, so the controller adds a second document
  at the path (measured, below); #231's step C looked only at documents
  already added, and a person's open still reading was invisible to it.
  **The controller knows what AppKit is reading**
  (`ProjectDocumentController`, the app's `NSDocumentController`, made in
  `main.swift` before any other controller can be): its overrides of the
  two public asynchronous opens,
  `openDocument(withContentsOf:display:completionHandler:)` and
  `reopenDocument(for:withContentsOf:display:completionHandler:)`, add one
  to a count for the path's canonical spelling (`AgentServer.canonical`) on
  the main thread before `super`, and take one off in a wrapped completion
  handler before the caller's runs, the key removed at 0; a reopen with no
  URL is not counted. `isOpening(url)` is "the count is above 0", and
  answers false when the shared controller is not this class (a proof probe
  with its own). A launch whose shared controller is not this class logs
  `Frame Job: …`, the startup complaint every MCP proof requires absent.
  **`open_project`** (#231's three steps): **step A**, one main-thread
  block: a holder → `already_open`; else an open in flight → wait; else the
  file's type. **Step B** is unchanged: the read on the lane's thread
  inside `withoutAsking`, never through AppKit's open. **Step C**, one
  main-thread block: a holder → the made document is closed and the call
  answers `already_open`; else an open in flight → wait; else add, window
  controllers, show, the recent note and the answer. **Waiting** is a
  50 ms sleep on the calling thread and the same block again, until
  `AgentServer.personOpenWait` (30 s) after that step's first "wait"; on
  the main thread the deadline is at once, and nothing sleeps there. Past
  it step A refuses — "`<name>` is being opened in a window; call
  open_project again once it has opened." — and step C closes the document
  it made, which was never added or shown, and refuses in the same
  sentence. **`new_project {path}` and `save_project {path}`**
  (`refuseHeldPath`, after #40's holder check, both callers): a path whose
  open is in flight is refused before anything is created or written —
  "`<path>` is being opened in a window, so `<tool>` did not write there:
  call `<tool>` again once it has opened, or pass another path." **Why a
  step is whole:** each is one block on the main thread; the count rises on
  main before AppKit's own already-open check and falls in the completion,
  which AppKit calls on main after `addDocument:`. So a block sees a
  holder, or an open in flight, or neither with no AppKit open begun — and
  in the last case step C adds in that same block, so a person's open that
  begins afterwards finds the document. **The doors, and how each is
  known.** *Driven* (`agent_open_proof.py`): File ▸ Open's own action,
  `openDocument(_:)`, with the panel answered by a probe override (A8);
  the direct call Welcome's Recent row and `FileDropView`'s drops make
  (A10); `reopenDocument(for:withContentsOf:display:completionHandler:)`
  (A11). *Read* (static, this AppKit — macOS 26.5.1 — from a disassembly of
  the 3,513 AppKit methods and blocks whose names match `NSDocument`,
  `NSApplication(NSAppleEventHandling)`, `RecentItemsMenuController`,
  `Seamless`, `DocumentOpen`, `NSPersistentUI`, `NSWindowRestor` and
  `NSWorkspace`; nothing run): `addDocument:` is sent by six functions — a
  block of `_openDocumentWithContentsOfURL:requestedBySourceApp:display:completionHandler:`
  (sent only by the public open), a block of the public reopen,
  `openUntitledDocumentAndDisplay:error:`,
  `_finishOpeningDocument:andShowWindows:` (sent only by the two deprecated
  synchronous opens and `duplicateDocument…`) and two deprecated methods.
  File ▸ Open, an open-documents Apple event (a Finder double-click, a Dock
  drop: `_handleCoreEvent:` → `_handleAEOpenDocumentsForURLs:` →
  `_openURLs:requestedBySourceApp:completionHandler:`), the Open Recent
  menu (`_openRecentDocument:` → `_openURLs:…`) and `_doOpenFile:` →
  `_openFile:` all reach
  `_openDocumentsWithContentsOfURLs:requestedBySourceApp:presentErrors:completionHandler:`,
  whose block sends the public open or the public reopen; its only other
  branch, the deprecated synchronous open, is behind
  `_canPerformBatchedDocumentOpening`, which is
  `_CFExecutableLinkedOnOrAfter`. Restoration
  (`_restorePersistentDocumentWithState:`) and
  `_autoreopenDocumentsFromRecords:` send the public open or reopen.
  *Read* (the app's own source): `WelcomeWindowController`'s Recent row and
  `FileDropView`'s drops call the public open; `AppDelegate` implements no
  `application(_:open…)`; `openUntitledDocumentAndDisplay` (File ▸ New
  Project, the dev assistant launch, `new_project`) adds a document with no
  path; a recording's landing adds its document and gives it its movie in
  one main-thread turn; no product caller reaches `openProject` on the main
  thread (`AgentLane.serve` asserts off main, `submit` runs on a queue).
  **The risks it accepts:** the lane is held for up to `personOpenWait` at
  each of the two steps, so every other tool call waits that long behind an
  `open_project` that is waiting; a hop to main is `onMain`'s
  (`AgentLane.onMainWhenIdle`, unbounded while a gesture is live) and is
  not counted in the bound; the person's open wins, and at step C the
  agent's finished read — a WebM's copy included, which stays in
  `Rewrapped/` — is thrown away; an open whose completion AppKit never
  calls leaves the path refused until quit; an AppKit that routes an open
  around the two public methods reopens the hole, and only A8 would say so;
  and a tool's main hop is not served while the ffmpeg conversion question
  is on screen when the question was asked from a background thread (read
  from the source, not measured: the import queue and a read on AppKit's
  read queue ask there): `consent` runs its modal inside its own
  `DispatchQueue.main.sync`, and a main-queue block is not served from
  inside another, so the tool call waits for the person's answer. Measured
  (2026-10-04, macOS 26.5.1; `ffmpeg_rewrap_proof.py` row M1, `passed
  23/23`, in a `.prohibited` probe that activates nothing): with `consent`
  called on a background thread and the question ended by
  `NSApp.abortModal()` 2.009 s after it came up, `AgentServer.onMain {}`
  called as it came up ran at 2.019 s, the question gone; with `consent`
  called on the main thread itself, from outside any main-queue block — what
  a read AppKit runs on main does unless AppKit runs it inside one, which
  was not looked at — the same hop ran at 0.008 s with the question still
  up; with no question up it is served in under a millisecond. With the
  question put up from a run-loop block instead (`--mutant ask-in-run-loop`)
  the first hop too runs with the question up, at 0.008 s, and M1 fails.
  Where a person's read ran (2026-10-04; `agent_open_proof.py`, `passed
  15/15`, in its `.prohibited` probe, whose two `makeDocument` overrides
  note `Thread.isMainThread` as a person's read is entered): at File ▸
  Open's own action (A8), at the direct call (A10) and at reopen (A11) the
  person's read entered `makeDocument` 1 time, 0 of them on the main thread;
  with the probe's note inverted those three rows fail and no other
  (`passed 12/15`). No row put the question up from a person's read, the
  doors that were read and not driven (an open-documents Apple event, Open
  Recent, `_openFile:`, restoration, autoreopen) were not measured, and no
  door at which a person's read runs on main was found or looked for beyond
  A8, A10 and A11; whether AppKit runs such a read inside a main-queue
  block is still not looked at. It is every tool's behaviour, not this
  decision's. **One window stays:**
  `refuseHeldPath`'s check and the save it guards are two main-thread hops
  (`newProject`, `saveProject`), and the save itself is asynchronous, so a
  person's open of the path that BEGINS after the check — between the hops,
  or while the save writes — is not seen, and by R6 (a Save As onto a URL
  mid-open) ends as two documents at the path. Read from the code and from
  R6, not driven in the product. **Not changed:** two untitled projects of
  one movie made one after the other (no read is in flight; spec §1's own
  behaviour); a person's Save As onto a path a person's own open is reading
  (AppKit's, between two of a person's actions); there is no cancel for the
  agent's wait and no progress over MCP (MC-5). **Measured** (2026-10-03,
  macOS 26.5.1, Apple M2 Max). *That it happens in AppKit:* in a standalone
  `.prohibited` `NSDocument` app whose first read lasts 1.5 s, a document
  added for the URL 0.3 s into the public open's read is not seen when the
  read ends ("documents at URL mid-read 1, at the end 2"), while two such
  opens of one URL are de-duplicated by AppKit ("wasOpen true, documents 1,
  reads 1") — the designer's run. The reviewer's run, over these two
  overrides: a reopen runs off main in a `.prohibited` process and its
  completion is called on main with the document already in `documents`
  (R1); the hole exists through reopen ("documents at the end 2", R2); a
  read that throws calls both completions and leaves the count empty (R3);
  two opens mid-read count 2, then none (R4); a reopen with a nil URL is not
  counted (R5); a document given the URL mid-open, a Save As onto it, makes
  2 (R6). *In the product* (`python3 tools/proof/agent_open_proof.py`: a
  probe over `app/Sources` whose controller is the app's own with seams — a
  finished read is held, off main, until the other side has got as far as
  the row needs, each hold bounded at 120 s; `passed 15/15`, no hold
  expired): File ▸ Open's own action with the agent's call mid-read answers
  `already_open: true`, with one document at the path, the one the person's
  open's completion carries, and the agent reads nothing (A8, A9); the
  agent's read first and the person's open mid-read answers `already_open:
  true`, one document, the person's, and the document the agent made is
  never among the open ones (A10); the same through reopen (A11); with
  `personOpenWait` at 1 s and the person's open held past it, step A refuses
  after 1.136 s having read nothing (A12) and step C refuses 1.201 s after
  the person's open was called, its made document never added (A13), each
  then leaving one document, the person's; and `new_project {path}` onto the
  path being opened is refused with `project.json`'s bytes unchanged (A14).
  With `isOpening` answering false (`--mutant no-inflight`, the app as it
  was before this decision), A8, A10 and A11 each end with "2 open documents
  at the package's path", the agent reads during A8 (A9), A12 and A13 are
  answered a project and leave 2 documents, and A14's `new_project` answers
  "Timed out saving a4.reelcut." with a second project left open. `--mutant
  no-recheck` (step C's holder check off) fails A7 and A10, and `--mutant
  open-on-main` fails A8 and A10–A13 beside its B79 rows, because on the
  main thread the wait's deadline is at once.
  **Amended by NM-5** (rename R0): the startup complaint `Reelcut: …` is now
  `Frame Job: …`; a project is a `.framejob` package (NM-3), so A14's mutant
  now reads "Timed out saving a4.framejob."; the measured runs above are
  quoted as they printed.
